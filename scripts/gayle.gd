class_name Gayle
extends CharacterBody2D
## Imogen's spouse and helper. By day she waters a dry crop near Imogen every few seconds;
## at night she walks to a slime that is eating a crop and hits it (weaker than Imogen).
## She follows Imogen or stays where she is (toggled by talking to her, see GayleTalk).
## She lives on physics layer 2, so she never blocks Imogen (who only sees layer 1), but
## trees, ponds and the stall still stop her. Slimes ignore her.
## The node's position is her feet.

enum Mode { FOLLOW, STAY }

const SPEED := 60.0
const FOLLOW_NEAR := 22.0  # stop walking this close to Imogen
const FOLLOW_FAR := 34.0  # start walking when farther than this
const TELEPORT_DISTANCE := 180.0
const STUCK_TIME := 2.0  # trying to walk but not moving this long: teleport next to Imogen
const WATER_INTERVAL := 4.0
const ATTACK_INTERVAL := 1.0
const ATTACK_RANGE := 14.0
const ATTACK_DAMAGE := 1  # Imogen's sword does 1 + upgrades
## Same 64x64 layer sheets as Player (see docs/ASSETS.md), different hair and clothes.
const LAYERS := [
	"Player_Base/Player_Base_animations.png",
	"Feet/Shoes_1_Brown.png",
	"Legs/Farmer_Pants/Farmer_Pants_1_Purple.png",
	"Chest/Farmer_Shirt/Farmer_Shirt_1_Pink.png",
	"Hands/Hands_1_Bare.png",
	"Head/Hair_4/Hair_4_Ginger.png",
]

var farm: Farm
var player: Player
var mode := Mode.FOLLOW
## She can't leave this rectangle (world pixels). Set by Main.
var walk_bounds := Rect2(0, 0, 0, 0)
var facing := Vector2.DOWN

var _anim := "idle"
var _anim_time := 0.0
var _layers: Array[Sprite2D] = []
var _tool_sprite := Sprite2D.new()
var _water_timer := 0.0
var _attack_timer := 0.0
var _action_cell := Vector2i.ZERO
var _water_pending := false
var _attack_pending := false
var _stuck := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("gayle")
	var body := Node2D.new()
	body.position = Vector2(0, -8)  # feet are 8 px below the frame centre
	add_child(body)
	for path: String in LAYERS:
		var layer := Sprite2D.new()
		layer.texture = load(Player.BODY_DIR + path)
		layer.hframes = Player.COLUMNS
		layer.vframes = Player.ROWS
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
	_water_timer += delta
	_attack_timer += delta
	var busy := _is_busy()
	var goal := global_position
	var has_goal := false  # a target to hunt, or Imogen to follow
	var wants_to_walk := false
	if Game.is_night:
		var target := _find_target()
		if target != null:
			goal = target.global_position
			has_goal = true
			if global_position.distance_to(goal) > ATTACK_RANGE:
				wants_to_walk = true
			elif not busy and _attack_timer >= ATTACK_INTERVAL:
				_start_attack(target)
	elif not busy and _water_timer >= WATER_INTERVAL:
		_try_water()
	if not has_goal and mode == Mode.FOLLOW and player != null:
		goal = player.global_position
		var limit := FOLLOW_NEAR if _anim == "walk" else FOLLOW_FAR
		wants_to_walk = global_position.distance_to(goal) > limit

	var walking := wants_to_walk and not busy
	if walking:
		var direction := global_position.direction_to(goal)
		velocity = direction * SPEED
		facing = axis_of(direction)
		_play("walk")
	else:
		velocity = Vector2.ZERO
		if not busy:
			_play("idle")
	var before := global_position
	move_and_slide()
	if walk_bounds.has_area():
		global_position = global_position.clamp(walk_bounds.position, walk_bounds.end)
	_check_stuck(delta, walking, before)
	_animate(delta)


func to_save() -> Dictionary:
	return {"x": global_position.x, "y": global_position.y, "mode": int(mode)}


func from_save(data: Dictionary) -> void:
	var spot := Vector2(SaveUtil.number(data, "x", global_position.x), SaveUtil.number(data, "y", global_position.y))
	global_position = spot.clamp(walk_bounds.position, walk_bounds.end) if walk_bounds.has_area() else spot
	var saved_mode := int(SaveUtil.number(data, "mode", Mode.FOLLOW))
	mode = Mode.STAY if saved_mode == Mode.STAY else Mode.FOLLOW


func toggle_mode() -> void:
	mode = Mode.STAY if mode == Mode.FOLLOW else Mode.FOLLOW


func is_following() -> bool:
	return mode == Mode.FOLLOW


## Puts her next to Imogen (used when she is too far away or stuck behind something).
func teleport_to_player() -> void:
	if player != null:
		global_position = player.global_position + Vector2(-16, 2)
		_stuck = 0.0


static func axis_of(direction: Vector2) -> Vector2:
	if absf(direction.x) > absf(direction.y):
		return Vector2(signf(direction.x), 0)
	return Vector2(0, signf(direction.y))


# --- Helping ------------------------------------------------------------------

func _find_target() -> Node2D:
	var stay := mode == Mode.STAY or player == null
	var anchor := global_position if stay else player.global_position
	var reach := GayleBrain.STAY_FIGHT_RANGE if stay else GayleBrain.FIGHT_RANGE
	return GayleBrain.eating_enemy(get_tree().get_nodes_in_group("enemies"), farm, global_position, anchor, reach)


func _try_water() -> void:
	var cell := GayleBrain.dry_crop_cell(farm, farm.cell_at(global_position + Vector2(0, -2)), global_position)
	if cell == GayleBrain.NO_CELL:
		return
	_water_timer = 0.0
	_action_cell = cell
	_water_pending = true
	facing = axis_of(farm.cell_center(cell) - global_position)
	_play("water", true)


func _start_attack(target: Node2D) -> void:
	_attack_timer = 0.0
	facing = axis_of(target.global_position - global_position)
	_attack_pending = true
	_play("attack", true)


## Gives up and teleports when she keeps trying to walk to Imogen without moving.
func _check_stuck(delta: float, walking: bool, before: Vector2) -> void:
	if player == null or mode == Mode.STAY:
		_stuck = 0.0
		return
	if global_position.distance_to(player.global_position) > TELEPORT_DISTANCE:
		teleport_to_player()
	elif walking and global_position.distance_to(before) < SPEED * delta * 0.2:
		_stuck += delta
		if _stuck >= STUCK_TIME:
			teleport_to_player()
	else:
		_stuck = 0.0


# --- Animation (same sheets and rows as Player) ----------------------------------

func _play(anim_name: String, restart := false) -> void:
	if anim_name == _anim and not restart:
		return
	_anim = anim_name
	_anim_time = 0.0


func _is_busy() -> bool:
	var anim: Dictionary = Player.ANIMS[_anim]
	return not anim["loop"] and _anim_time < anim["frames"] / anim["fps"]


func _animate(delta: float) -> void:
	_anim_time += delta
	var anim: Dictionary = Player.ANIMS[_anim]
	var frame_count: int = anim["frames"]
	var index := int(_anim_time * anim["fps"])
	index = index % frame_count if anim["loop"] else mini(index, frame_count - 1)
	var facing_index := 0 if facing.y > 0.0 else (2 if facing.y < 0.0 else 1)
	var row: int = anim["rows"][facing_index]
	var flip := facing.x < 0.0
	for layer in _layers:
		layer.frame = row * Player.COLUMNS + index
		layer.flip_h = flip
	_update_tool_sprite(row, index, flip)
	if _anim_time >= frame_count / float(anim["fps"]) * 0.5:  # the tool "hits" halfway
		if _water_pending:
			_water_pending = false
			if farm.water(_action_cell):
				Audio.play_sfx("water", 0.1)
		if _attack_pending:
			_attack_pending = false
			_hit_nearby_slime()


## One slime per swing, the closest one in reach.
func _hit_nearby_slime() -> void:
	var origin := global_position + Vector2(0, -6)
	var best: Node2D = null
	var best_distance := ATTACK_RANGE + 6.0
	for enemy: Node2D in get_tree().get_nodes_in_group("enemies"):
		var distance: float = (enemy.body_center() - origin).length()
		if distance <= best_distance:
			best = enemy
			best_distance = distance
	if best != null:
		Audio.play_sfx("sword_swing", 0.1)
		best.take_hit(ATTACK_DAMAGE, global_position)


func _update_tool_sprite(row: int, index: int, flip: bool) -> void:
	match _anim:
		"attack":
			_show_tool(Player.SWORD_TEXTURE, 4, 9, row - 6, index, flip)
		"water":
			_show_tool(Player.TOOLS_TEXTURE, 6, 12, row - 29, index, flip)
		_:
			_tool_sprite.visible = false


func _show_tool(texture: Texture2D, columns: int, rows: int, row: int, index: int, flip: bool) -> void:
	if _tool_sprite.texture != texture:
		_tool_sprite.texture = texture
		_tool_sprite.hframes = columns
		_tool_sprite.vframes = rows
	_tool_sprite.frame = row * columns + index
	_tool_sprite.flip_h = flip
	_tool_sprite.visible = true
