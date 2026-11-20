class_name Player
extends CharacterBody2D
## The farmer. Moves, animates a layered sprite, uses tools on a target tile (the tile in
## front with the keyboard, or the tile under the mouse within TOOL_REACH). There is no
## health: slimes only eat crops. The node's position is the character's feet.

signal tool_changed(tool: Tool)
signal seed_changed(crop_id: String)
## A tool was used on a ripe crop: Main harvests it (same as pressing E on it).
signal harvest_requested(cell: Vector2i)

enum Tool { HOE, WATER, SEEDS, SWORD, FENCE, SPRINKLER }

const SPEED := 70.0
## Mouse aiming reaches this many tiles from the player's tile (in each direction).
const TOOL_REACH := 2
## The sword always swings the way the player faces (the last direction walked). It hits
## enemies up to SWORD_RANGE px away inside a wide arc in front (SWORD_ARC is the minimum
## dot product: 0.2 is about 80 degrees to each side, so the front diagonals count),
## plus anything closer than SWORD_HUG px in any direction.
const SWORD_RANGE := 32.0
const SWORD_ARC := 0.2
const SWORD_HUG := 12.0
## Mouse moves smaller than this (px) don't switch the highlight to the mouse (touchpad jitter).
const MOUSE_JITTER := 3.0
const SWORD_DAMAGE := 1  # before "sword" upgrades, see sword_damage()

const COLUMNS := 9
const ROWS := 56
const BODY_DIR := "res://assets/cute_fantasy/Player/"
## Drawn bottom to top. All layers share the same 64x64 grid (see docs/ASSETS.md).
const BODY_LAYERS := [
	"Player_Base/Player_Base_animations.png",
	"Feet/Shoes_1_Brown.png",
	"Legs/Farmer_Pants/Farmer_Pants_1_Blue.png",
	"Chest/Farmer_Shirt/Farmer_Shirt_1_White_and_Brown.png",
	"Hands/Hands_1_Bare.png",
	"Head/Hair_1/Hair_1_Brown.png",
]
const SWORD_TEXTURE := preload("res://assets/cute_fantasy/Player/Tools/Iron/Iron_Sword.png")
const TOOLS_TEXTURE := preload("res://assets/cute_fantasy/Player/Tools/Iron/Iron_Tools.png")

## rows = sheet row when facing [down, side, up]. Side rows face right; we flip for left.
const ANIMS := {
	"idle": {"rows": [0, 1, 2], "frames": 6, "fps": 8.0, "loop": true},
	"walk": {"rows": [3, 4, 5], "frames": 6, "fps": 10.0, "loop": true},
	"attack": {"rows": [6, 9, 12], "frames": 4, "fps": 16.0, "loop": false},
	"hoe": {"rows": [32, 33, 34], "frames": 6, "fps": 26.0, "loop": false},
	"water": {"rows": [38, 39, 40], "frames": 6, "fps": 26.0, "loop": false},
}

var farm: Farm
## The player can't leave this rectangle (world pixels). Set by Main.
var walk_bounds := Rect2(0, 0, 0, 0)
## While set (not INF), saves store this spot instead of the real position. The farmhouse
## uses it so a save made indoors loads you outside the door.
var save_position_override := Vector2.INF
var tool := Tool.HOE
var seed_id := "carrot"  # crop type planted by the Seeds tool
## Fruit tree held by the Seeds tool instead of a seed ("" = a seed is held).
var sapling_id := ""
## What the tools do to the farm (shared with the host's handling of a joiner's requests). Set by Main.
var actions: WorldActions
## Online joiner: tool use is sent to the host instead of applied here (the host owns the farm).
var remote_world: CoopWorld
var facing := Vector2.DOWN

var _anim := "idle"
var _anim_time := 0.0
var _action_cell := Vector2i.ZERO
var _action_pending := false
var _layers: Array[Sprite2D] = []
var _tool_sprite := Sprite2D.new()
var _use_requested := false  # set by _unhandled_input, so clicks on the HUD don't use tools
var _use_with_mouse := false  # the pending use came from a click (aim at the mouse)
var _use_held := false  # use button still held: keep going on each new tile
var _last_action_cell := Vector2i(1 << 20, 0)
## The first tile of a hoe hold decides the whole hold: true = every tile is un-tilled.
var _hold_untills := false
var _hold_decided := false
var _aim_with_mouse := false  # highlight follows the mouse; only changes what is shown


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("player")
	Game.stats_changed.connect(_on_game_stats_changed)

	var body := Node2D.new()
	body.position = Vector2(0, -8)  # feet are 8 px below the frame centre
	add_child(body)
	for path: String in BODY_LAYERS:
		var layer := Sprite2D.new()
		layer.texture = load(BODY_DIR + path)
		layer.hframes = COLUMNS
		layer.vframes = ROWS
		body.add_child(layer)
		_layers.append(layer)
	body.add_child(_tool_sprite)

	var shape := RectangleShape2D.new()
	shape.size = Vector2(8, 4)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = Vector2(0, -2)
	add_child(collider)


func _physics_process(delta: float) -> void:
	if Game.ui_open:  # online a menu does not pause the world, so the farmer just stands still
		velocity = Vector2.ZERO
		_use_requested = false
		_use_held = false
		if not _is_busy():
			_play("idle")
		_animate(delta)
		return
	if not _is_busy():
		_read_tool_keys()
		var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		velocity = input * SPEED
		if input != Vector2.ZERO:
			facing = _snap_to_axis(input)
			_play("walk")
		else:
			_play("idle")
		if _use_requested:
			_start_action()
		elif _use_held and (tool == Tool.SWORD or target_cell() != _last_action_cell):
			_start_action()  # holding the button waters/tills/plants tile after tile
	else:
		# Using a tool never stops you: keep running, but keep facing the way the tool
		# was used until its animation ends.
		velocity = Input.get_vector("move_left", "move_right", "move_up", "move_down") * SPEED
	if not Input.is_action_pressed("use_tool"):
		_use_held = false
		_hold_decided = false

	_use_requested = false  # a press while busy is dropped, not queued
	move_and_slide()
	if walk_bounds.has_area():
		position = position.clamp(walk_bounds.position, walk_bounds.end)
	_animate(delta)


## Remembers whether the player is aiming with the mouse or the keyboard.
## The scroll wheel cycles tools.
func _input(event: InputEvent) -> void:
	# Ctrl + wheel is zoom (CameraZoom), so only the plain wheel switches tools.
	if event is InputEventMouseButton and event.pressed and not event.ctrl_pressed and not Game.is_paused():
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_tool(Tool.values()[(tool + 1) % Tool.size()])
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_tool(Tool.values()[(tool - 1 + Tool.size()) % Tool.size()])
	if event is InputEventMouseMotion and event.relative.length() >= MOUSE_JITTER:
		_aim_with_mouse = true
	elif event is InputEventMouseButton and event.pressed:
		_aim_with_mouse = true
	elif event is InputEventKey and event.pressed and _is_keyboard_aim_key(event):
		_aim_with_mouse = false  # E doesn't switch, so "point at a crop + E" harvests it


func _is_keyboard_aim_key(event: InputEvent) -> bool:
	for action in ["use_tool", "move_left", "move_right", "move_up", "move_down"]:
		if event.is_action(action):
			return true
	return false


## The tile tools act on: the tile under the mouse (pulled in to at most TOOL_REACH tiles
## away), or with the keyboard the tile the player is facing.
func target_cell() -> Vector2i:
	if _aim_with_mouse:
		return aim_cell(get_global_mouse_position())
	return farm.cell_at(global_position + Vector2(0, -2)) + Vector2i(facing)


## The tile aimed at when pointing at `world_pos`, pulled in to at most TOOL_REACH tiles.
func aim_cell(world_pos: Vector2) -> Vector2i:
	var own_cell := farm.cell_at(global_position + Vector2(0, -2))
	var offset := farm.cell_at(world_pos) - own_cell
	return own_cell + offset.clamp(Vector2i(-TOOL_REACH, -TOOL_REACH), Vector2i(TOOL_REACH, TOOL_REACH))


## The tiles the selected tool acts on (an upgraded watering can covers several).
func tool_cells() -> Array[Vector2i]:
	if tool == Tool.WATER:
		return WorldActions.water_area(target_cell(), facing, Game.upgrade_level("can"))
	if tool == Tool.SPRINKLER:
		return Sprinklers.area_cells(target_cell())  # shows what the sprinkler would water
	var cells: Array[Vector2i] = [target_cell()]
	return cells


## Name of the animation playing now ("idle", "walk", ...), for co-op to show on other screens.
func current_anim() -> String:
	return _anim


func set_tool(new_tool: Tool) -> void:
	tool = new_tool
	tool_changed.emit(tool)


func set_seed(crop_id: String) -> void:
	seed_id = crop_id
	sapling_id = ""
	seed_changed.emit(seed_id)


func set_sapling(tree_id: String) -> void:
	sapling_id = tree_id
	seed_changed.emit(seed_id)


## How many of the item the Seeds tool holds (seeds or saplings) are left.
func held_count() -> int:
	return Game.sapling_count(sapling_id) if sapling_id != "" else Game.seed_count(seed_id)


func to_save() -> Dictionary:
	var spot := global_position if save_position_override == Vector2.INF else save_position_override
	return {
		"x": spot.x, "y": spot.y,
		"facing": [facing.x, facing.y],
		"tool": int(tool),
		"seed": seed_id,
	}


func from_save(data: Dictionary) -> void:
	var spot := Vector2(SaveUtil.number(data, "x", global_position.x), SaveUtil.number(data, "y", global_position.y))
	global_position = spot.clamp(walk_bounds.position, walk_bounds.end) if walk_bounds.has_area() else spot
	var saved_facing: Variant = data.get("facing")
	if SaveUtil.is_entry(saved_facing, 2):
		var dir := Vector2(float(saved_facing[0]), float(saved_facing[1]))
		if dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			facing = dir
	var saved_tool := int(SaveUtil.number(data, "tool", tool))
	if saved_tool >= 0 and saved_tool < Tool.size():
		set_tool(Tool.values()[saved_tool])
	if Crop.TYPES.has(data.get("seed")):
		set_seed(data["seed"])


func sword_damage() -> int:
	return SWORD_DAMAGE + Game.upgrade_level("sword")


## The inventory picked a seed type: select the Seeds tool with it. False if you have none.
func equip_seed(crop_id: String) -> bool:
	if not Crop.TYPES.has(crop_id) or Game.seed_count(crop_id) <= 0:
		return false
	set_seed(crop_id)
	set_tool(Tool.SEEDS)
	Audio.play_sfx("ui_select")
	return true


## The inventory picked a sapling type: select the Seeds tool with it. False if you have none.
func equip_sapling(tree_id: String) -> bool:
	if not Orchard.TYPES.has(tree_id) or Game.sapling_count(tree_id) <= 0:
		return false
	set_sapling(tree_id)
	set_tool(Tool.SEEDS)
	Audio.play_sfx("ui_select")
	return true


## Key, HUD click or wheel picked hotbar slot `index` (0 = hoe ... 5 = sprinkler).
func choose_slot(index: int) -> void:
	if index == Tool.SEEDS and tool == Tool.SEEDS:
		_cycle_seed()  # choosing seeds again picks the next seed type
	else:
		set_tool(Tool.values()[index])
		Audio.play_sfx("ui_select")


## Clicks that the HUD (e.g. a hotbar slot) already used never arrive here.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("use_tool") and not Game.ui_open:
		_use_requested = true
		_use_held = true
		# The input that triggered the use decides the aim: a click aims at the mouse,
		# Space/J use the way the player faces, even if the mouse rests somewhere else.
		_use_with_mouse = event is InputEventMouseButton


func _read_tool_keys() -> void:
	for i in Tool.size():
		if Input.is_action_just_pressed("tool_%d" % (i + 1)):
			choose_slot(i)
	if tool == Tool.SEEDS and Input.is_action_just_pressed("cycle_seed"):
		_cycle_seed()


## Selects the next seed type or sapling type you own. Stays put if there is no other.
func _cycle_seed() -> void:
	var current := PlantCycle.key("sapling", sapling_id) if sapling_id != "" else PlantCycle.key("seed", seed_id)
	var next := PlantCycle.next(current, Game.seeds, Game.saplings)
	if next == current:
		return
	var parts := next.split(":")
	if parts[0] == "sapling":
		set_sapling(parts[1])
	else:
		set_seed(parts[1])


func _start_action() -> void:
	_aim_with_mouse = _use_with_mouse
	if _use_with_mouse and tool != Tool.SWORD:
		var aim := get_global_mouse_position() - global_position
		if aim.length() > 2.0:
			facing = _snap_to_axis(aim)  # turn toward the tile you clicked
	_action_cell = target_cell()
	_last_action_cell = _action_cell
	var crop := farm.get_crop(_action_cell)
	if tool != Tool.SWORD and crop != null and crop.is_ripe():
		harvest_requested.emit(_action_cell)  # any farming tool picks a ripe crop
		return
	_action_pending = true
	match tool:
		Tool.HOE:
			if not _hold_decided:
				_hold_decided = true
				_hold_untills = farm.can_untill(_action_cell)
			_play("hoe", true)
		Tool.WATER:
			_play("water", true)
		Tool.SWORD:
			_play("attack", true)
		Tool.SEEDS, Tool.FENCE, Tool.SPRINKLER:
			_apply_action()  # planting and building are instant


## Runs halfway through the tool animation, when the tool "hits". A joiner only asks the host to do it.
func _apply_action() -> void:
	_action_pending = false
	if remote_world != null:
		remote_world.send_tool(tool, _action_cell, _hold_untills, facing, seed_id, sapling_id)
		return
	var result := actions.use_tool(tool, _action_cell, _hold_untills, facing, seed_id, sapling_id if tool == Tool.SEEDS else "", global_position)
	Audio.play_sfx(result["sfx"], result["variation"])
	if tool == Tool.SEEDS and result["sfx"] == "plant" and held_count() == 0:
		_cycle_seed()


## Joiner: the host used up the last seed or sapling of the held kind, so pick the next one.
func _on_game_stats_changed() -> void:
	if remote_world != null and tool == Tool.SEEDS and held_count() == 0:
		_cycle_seed()


func _snap_to_axis(direction: Vector2) -> Vector2:
	if absf(direction.x) > absf(direction.y):
		return Vector2(signf(direction.x), 0)
	return Vector2(0, signf(direction.y))


# --- Animation -------------------------------------------------------------

func _play(anim_name: String, restart := false) -> void:
	if anim_name == _anim and not restart:
		return
	_anim = anim_name
	_anim_time = 0.0


func _anim_length() -> float:
	var anim: Dictionary = ANIMS[_anim]
	return anim["frames"] / anim["fps"]


func _is_busy() -> bool:
	return not ANIMS[_anim]["loop"] and _anim_time < _anim_length()


func _facing_index() -> int:
	if facing.y > 0.0:
		return 0
	if facing.y < 0.0:
		return 2
	return 1


func _animate(delta: float) -> void:
	_anim_time += delta
	var anim: Dictionary = ANIMS[_anim]
	var frame_count: int = anim["frames"]
	var index := int(_anim_time * anim["fps"])
	index = index % frame_count if anim["loop"] else mini(index, frame_count - 1)
	var row: int = anim["rows"][_facing_index()]
	var flip := facing.x < 0.0
	for layer in _layers:
		layer.frame = row * COLUMNS + index
		layer.flip_h = flip
	_update_tool_sprite(row, index, flip)

	if _action_pending and _anim_time >= _anim_length() * 0.5:
		_apply_action()


func _update_tool_sprite(row: int, index: int, flip: bool) -> void:
	match _anim:
		"attack":
			_show_tool_frame(SWORD_TEXTURE, 4, 9, row - 6, index, flip)
		"hoe", "water":
			_show_tool_frame(TOOLS_TEXTURE, 6, 12, row - 29, index, flip)
		_:
			_tool_sprite.visible = false


func _show_tool_frame(texture: Texture2D, columns: int, rows: int, row: int, index: int, flip: bool) -> void:
	if _tool_sprite.texture != texture:
		_tool_sprite.texture = texture
		_tool_sprite.hframes = columns
		_tool_sprite.vframes = rows
	_tool_sprite.frame = row * columns + index
	_tool_sprite.flip_h = flip
	_tool_sprite.visible = true
