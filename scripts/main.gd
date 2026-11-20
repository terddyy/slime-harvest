extends Node2D
## Builds the world (grass, trees, market stall, buildings), starts the night Spawner,
## tints the screen for day/night and handles the E key (open the shop or the restoration board, or harvest).

const TILE := 16
const MAP_SIZE := WorldLayout.MAP_SIZE
const STALL_CELL := WorldLayout.STALL_CELL
const STALL_RANGE := 30.0
const GAYLE_TALK_RANGE := 26.0
## How far above each guide target's feet the tutorial arrow points (pixels).
const GUIDE_ABOVE_PERSON := 28.0
const GUIDE_ABOVE_AZY := 46.0  # above Azy's name tag
const GUIDE_ABOVE_BOARD := 34.0
const GUIDE_ABOVE_DOOR := 34.0
const ROCK_REGION := Rect2(64, 144, 16, 16)  # a boulder in Outdoor_Decor.png

const BIG_OAK := preload("res://assets/cute_fantasy/Trees/Big_Oak_Tree.png")
const MEDIUM_OAK := preload("res://assets/cute_fantasy/Trees/Medium_Oak_Tree.png")
const DECOR := preload("res://assets/cute_fantasy/Outdoor decoration/Outdoor_Decor.png")
const STALLS := preload("res://assets/cute_fantasy/Buildings/Buildings/Unique_Buildings/Stalls/Market_Stalls.png")

const DAY_COLOR := Color(1, 1, 1)
const DUSK_COLOR := Color(1.0, 0.78, 0.62)
const NIGHT_COLOR := Color(0.45, 0.5, 0.78)  # dark enough to feel like night, bright enough to see slimes

@onready var ground: TileMapLayer = $Ground
@onready var farm: Farm = $Farm
@onready var cursor: Node2D = $Cursor
@onready var entities: Node2D = $Entities
@onready var player: Player = $Entities/Player
@onready var night_tint: CanvasModulate = $NightTint
@onready var hud: Hud = $HUD

var _stall_position := Vector2.ZERO
var _shopkeeper := Shopkeeper.new()
var _shop := Shop.new()
var _buildings := Buildings.new()
var _board := RestorationBoard.new()
var _announced := {}  # project id -> true once its "you can restore" banner was shown
var _spawner := Spawner.new()
var _fences := Fences.new()
var _sprinklers := Sprinklers.new()
var _tutorial := Tutorial.new()
var _feedback := Feedback.new()
var _farmhouse := Farmhouse.new()
var _herd := Herd.new()
var _orchard := Orchard.new()
var _camera: CameraZoom
var _gayle := Gayle.new()
var _gayle_talk := GayleTalk.new()
var _guide := GuideArrow.new()
var _inventory := InventoryPanel.new()
var _coop: CoopSession  # only while online
var _tutorial_was_finished := false  # restored on exit: a joiner skips the tips without ending them for good
var _goal_where := ""  # guide target of the current farm goal, refreshed when the stats change


func _ready() -> void:
	GroundBuilder.build(ground)
	farm.bounds = WorldLayout.PLAY_AREA
	farm.blocked = WorldLayout.blocked_cells()
	farm.crop_parent = entities
	_place_ponds()
	_place_trees()
	_place_rocks()
	_place_stall()
	_place_orchard_sign()
	_buildings.entities = entities
	add_child(_buildings)
	move_child(_buildings, entities.get_index())  # its flat ghosts go under the entities
	_orchard.area = WorldLayout.area(&"orchard")
	_orchard.tree_parent = entities
	add_child(_orchard)
	_fences.farm = farm
	_fences.fence_parent = entities
	add_child(_fences)
	_sprinklers.farm = farm
	_sprinklers.sprinkler_parent = entities
	add_child(_sprinklers)

	player.farm = farm
	player.fences = _fences
	player.sprinklers = _sprinklers
	player.orchard = _orchard
	player.position = Vector2(WorldLayout.PLAYER_START * TILE) + Vector2(TILE / 2.0, TILE / 2.0)
	player.walk_bounds = Rect2(Vector2(24, 40), Vector2(MAP_SIZE * TILE) - Vector2(48, 56))
	player.harvest_requested.connect(_harvest)
	_add_camera()
	_place_gayle()

	_spawner.farm = farm
	_spawner.fences = _fences
	_spawner.player = player
	_spawner.entities = entities
	_spawner.map_size = Vector2(MAP_SIZE * TILE)
	_spawner.enemy_killed.connect(_on_enemy_killed)
	add_child(_spawner)

	_herd.entities = entities
	_herd.player = player
	_herd.collected.connect(_on_product_collected)
	add_child(_herd)

	hud.setup(player)
	add_child(_shop)
	add_child(_board)
	_inventory.player = player
	add_child(_inventory)
	hud.goals_requested.connect(_inventory.toggle_goals)
	hud.inventory_requested.connect(_inventory.toggle)
	_gayle_talk.gayle = _gayle
	add_child(_gayle_talk)
	add_child(_tutorial)
	_tutorial.setup(farm, _board, _gayle_talk)
	_guide.tutorial = _tutorial
	_guide.locate = _guide_point
	_guide.goal_target = _guide_goal
	add_child(_guide)
	add_child(_feedback)
	_feedback.setup(farm, player, hud)
	add_child(_farmhouse)
	_farmhouse.setup(player, _camera, farm, _fences, hud, entities)
	Game.phase_changed.connect(_on_phase_changed)
	_register_save_systems()
	if Net.is_online():
		_start_coop()
	if not _is_joiner():  # a joiner's farm arrives from the host (CoopSession)
		_load_or_start_new()
	_announce_restorable(true)
	Game.stats_changed.connect(_announce_restorable.bind(false))
	_update_goal_target()
	Game.stats_changed.connect(_update_goal_target)
	Audio.play_music("day")


func _load_or_start_new() -> void:
	if SaveGame.load_requested:
		SaveGame.load_requested = false
		if SaveGame.load_game():
			Tutorial.is_finished = true
			_tutorial.visible = false
			hud.show_banner("Welcome back - Day %d" % Game.day)
		else:
			_start_new_day_one()
	else:
		_start_new_day_one()


## A new run: the story intro first (once, see Game.intro_seen), then the first-day banner.
func _start_new_day_one() -> void:
	var banner := func() -> void: hud.show_banner("Day 1 - plant carrots before night!")
	if Game.intro_seen or Net.is_online():  # the intro would pause the game for the friends too
		banner.call()
		return
	Game.intro_seen = true
	hud.play_intro(banner)


## One banner per project, the first time its price is within reach. `silent` only records
## what is already affordable (after loading a save), so nothing is announced twice.
func _announce_restorable(silent: bool) -> void:
	silent = silent or (_is_joiner() and not _coop.has_farm())  # the host's farm is still arriving
	var id := Restoration.affordable_next(Game.restored, Game.gold)
	if id == "" or _announced.has(id):
		return
	_announced[id] = true
	if not silent:
		hud.show_banner("You can restore the %s! Go to the board by the farmhouse." % String(Restoration.project(id)["name"]).to_lower())


func _update_goal_target() -> void:
	_goal_where = String(FarmGoals.current(FarmGoals.build(Game.goal_state())).get("where", ""))


func _exit_tree() -> void:
	SaveGame.unregister_all()
	Tutorial.is_finished = _tutorial_was_finished


func _process(_delta: float) -> void:
	_update_tint()
	_update_cursor_and_hint()
	if Input.is_action_just_pressed("skip_phase"):
		Game.skip_phase()


## Floating text that rises and fades, e.g. "+15g".
func popup(text: String, world_pos: Vector2, color := Color.WHITE) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.05))
	label.add_theme_constant_override("outline_size", 3)
	label.position = world_pos + Vector2(-10, -34)
	label.z_index = 10
	add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - 14, 0.9)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.9)
	tween.tween_callback(label.queue_free)


## E is read as an event (not polled in _process) so the press that closes the shop,
## which the shop marks as handled, doesn't reach this and reopen it.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_interact()


func _interact() -> void:
	if _farmhouse.interact():
		return
	if _is_near_stall():
		_shop.open()
		return
	if _buildings.is_near_board(player.global_position):
		_board.open()
		return
	if _is_near_gayle():
		_gayle_talk.open()
		return
	if _herd.collect_near(player.global_position):
		return
	var cell := player.target_cell()
	var sapling := _sapling_to_plant()
	if _orchard.has_fruit(cell):
		var tree_id := _orchard.harvest(cell)
		Audio.play_sfx("harvest", 0.05)
		Game.add_fruit(tree_id, Orchard.FRUIT_PER_TREE)
		popup("+%d %s" % [Orchard.FRUIT_PER_TREE, Orchard.TYPES[tree_id]["name"].to_lower()], _tree_top(cell), Color(1, 0.7, 0.3))
	elif sapling != "" and _orchard.can_plant(cell):
		_orchard.plant(cell, sapling)
		Game.use_sapling(sapling)
		Audio.play_sfx("plant")
	else:
		_harvest(cell)


## The sapling E plants: the one held by the Seeds tool, else the first one you own.
func _sapling_to_plant() -> String:
	if player.sapling_id != "" and Game.sapling_count(player.sapling_id) > 0:
		return player.sapling_id
	return Game.next_sapling()


func _holds_sapling() -> bool:
	return player.tool == Player.Tool.SEEDS and player.sapling_id != "" and player.held_count() > 0


## What the guide arrow points at once the tips are over: the orchard while a sapling is held
## and you are not in it yet, else the current farm goal.
func _guide_goal() -> String:
	if _holds_sapling() and not _orchard.area.has_point(farm.cell_at(player.global_position)):
		return "orchard"
	return _goal_where


func _tree_top(cell: Vector2i) -> Vector2:
	return Vector2(cell * TILE) + Vector2(TILE / 2.0, TILE)


## Picks a ripe crop: E on it, or using a farming tool on it (Player.harvest_requested).
func _harvest(cell: Vector2i) -> void:
	var crop := farm.get_crop(cell)
	if crop != null and farm.harvest(cell):
		Audio.play_sfx("harvest", 0.05)
		Game.add_crop(crop.crop_id)
		var crop_name: String = Crop.TYPES[crop.crop_id]["name"]
		popup("+1 " + crop_name.to_lower(), farm.cell_center(cell), Color(1, 0.7, 0.3))


func _is_near_stall() -> bool:
	return (
		player.global_position.distance_to(_stall_position) < STALL_RANGE
		or player.global_position.distance_to(_shopkeeper.global_position) < Shopkeeper.TALK_RANGE
	)


## Where the tutorial's guide arrow points for `target`: a world position just above the place
## to walk to, or Vector2.INF for none. Inside the farmhouse it shows the bed for the sleep tip
## and the way out for every other tip.
func _guide_point(target: String) -> Vector2:
	if _farmhouse.is_inside:
		if target == "house":
			return Farmhouse.ROOM_ORIGIN + Farmhouse.BED_SPOT + Vector2(0, -GUIDE_ABOVE_PERSON)
		return Farmhouse.ROOM_ORIGIN + Farmhouse.INSIDE_DOOR + Vector2(0, -8)
	match target:
		"stall":
			return _shopkeeper.global_position + Vector2(0, -GUIDE_ABOVE_AZY)
		"board":
			return _buildings.board_position + Vector2(0, -GUIDE_ABOVE_BOARD)
		"gayle":
			return _gayle.global_position + Vector2(0, -GUIDE_ABOVE_PERSON)
		"house":
			return Farmhouse.door_point() + Vector2(0, -GUIDE_ABOVE_DOOR)
		"orchard":
			return Vector2(WorldLayout.area(&"orchard").get_center() * TILE)
	return Vector2.INF


func _is_near_gayle() -> bool:
	return player.global_position.distance_to(_gayle.global_position) < GAYLE_TALK_RANGE


func _update_cursor_and_hint() -> void:
	var cell := player.target_cell()
	var can_act := false
	match player.tool:
		Player.Tool.HOE:
			can_act = farm.can_till(cell) or farm.can_untill(cell)
		Player.Tool.WATER:
			for area_cell in player.tool_cells():
				can_act = can_act or farm.can_water(area_cell)
		Player.Tool.SEEDS:
			if player.sapling_id != "":
				can_act = _orchard.can_plant(cell) and player.held_count() > 0
			else:
				can_act = farm.can_plant(cell) and player.held_count() > 0
		Player.Tool.FENCE:
			can_act = _fences.has_fence(cell) or (_fences.can_place(cell) and Game.fence_pieces > 0)
		Player.Tool.SPRINKLER:
			can_act = _sprinklers.has_sprinkler(cell) or (_sprinklers.can_place(cell) and Game.sprinkler_pieces > 0)
	cursor.visible = player.tool != Player.Tool.SWORD and not _farmhouse.is_inside
	cursor.show_cells(player.tool_cells(), can_act)

	var crop := farm.get_crop(cell)
	var animal := _herd.animal_ready_near(player.global_position)
	var house_hint := _farmhouse.hint()
	if house_hint != "":
		hud.set_hint(house_hint)
	elif _farmhouse.is_inside:
		hud.set_hint("")
	elif _is_near_stall():
		hud.set_hint("E: talk to Azy (shop)")
	elif _buildings.is_near_board(player.global_position):
		hud.set_hint("E: restoration board")
	elif _buildings.ruin_near(player.global_position) != "":
		var ruin: Dictionary = Restoration.project(_buildings.ruin_near(player.global_position))
		hud.set_hint("%s: restore for %dg at the board by the farmhouse" % [ruin["name"], ruin["cost"]])
	elif _is_near_gayle():
		hud.set_hint("E: talk to Gayle")
	elif animal != null:
		var product: Dictionary = AnimalTypes.PRODUCTS[AnimalTypes.TYPES[animal.type_id]["product"]]
		hud.set_hint("Click or E: collect %s" % String(product["name"]).to_lower())
	elif _orchard.has_fruit(cell):
		hud.set_hint("E: pick fruit")
	elif _sapling_to_plant() != "" and _orchard.can_plant(cell):
		hud.set_hint("E: plant sapling")
	elif _holds_sapling():
		if _orchard.area.has_point(cell):
			hud.set_hint("Too close to another tree")
		else:
			hud.set_hint("Saplings grow in the orchard - follow the arrow")
	elif crop != null and crop.is_ripe():
		hud.set_hint("Click or E: harvest")
	elif player.tool == Player.Tool.SEEDS:
		hud.set_hint("Q: change seed")
	elif player.tool == Player.Tool.FENCE and _fences.has_fence(cell):
		hud.set_hint("Space: pick up fence")
	elif player.tool == Player.Tool.FENCE and Game.fence_pieces == 0:
		hud.set_hint("No fences left - buy more at the stall")
	elif player.tool == Player.Tool.SPRINKLER and _sprinklers.has_sprinkler(cell):
		hud.set_hint("Space: pick up sprinkler")
	elif player.tool == Player.Tool.SPRINKLER and Game.sprinkler_pieces == 0:
		hud.set_hint("No sprinklers left - Azy sells them once the farm is restored")
	else:
		hud.set_hint("")


func _update_tint() -> void:
	if _farmhouse.is_inside:
		night_tint.color = DAY_COLOR  # the house is always lit
		return
	var progress := Game.phase_progress()
	if Game.is_night:
		var dark := DUSK_COLOR.lerp(NIGHT_COLOR, smoothstep(0.0, 0.1, progress))
		night_tint.color = dark.lerp(DAY_COLOR, smoothstep(0.85, 1.0, progress))
	else:
		night_tint.color = DAY_COLOR.lerp(DUSK_COLOR, smoothstep(0.8, 1.0, progress))


func _is_joiner() -> bool:
	return Net.is_online() and not Net.is_host()


## Online play. The host's world is the real one; a joiner gets it from the host as a snapshot.
## Until the world sync (C3) a joiner's own farm work only changes its own screen.
func _start_coop() -> void:
	if _is_joiner():
		SaveGame.write_enabled = false  # the farm is the host's: a joiner never writes a save file
		_tutorial_was_finished = Tutorial.is_finished
		Tutorial.is_finished = true
		_tutorial.visible = false
		_gayle.process_mode = Node.PROCESS_MODE_DISABLED  # the host runs Gayle
		player.global_position += CoopRules.start_offset(Net.my_id())
	_coop = CoopSession.new()
	_coop.player = player
	_coop.entities = entities
	_coop.hud = hud
	add_child(_coop)


func _on_phase_changed(is_night: bool) -> void:
	Audio.play_sfx("night_start" if is_night else "day_start")
	Audio.play_music("night" if is_night else "day")
	if is_night:
		if not _is_joiner():  # only the host spawns slimes
			_spawner.start_night(Game.day)
		hud.show_banner("Night %d - slimes are coming!" % Game.day)
	else:
		_spawner.end_night()
		_orchard.new_day()
		_sprinklers.water_all()  # every sunrise, also after sleeping through the night
		hud.show_banner("Day %d - the slimes retreat" % Game.day)
		SaveGame.save()


func _on_product_collected(world_pos: Vector2, product_id: String) -> void:
	popup("+1 " + String(AnimalTypes.PRODUCTS[product_id]["name"]).to_lower(), world_pos, Color(1, 0.95, 0.6))


func _on_enemy_killed(world_pos: Vector2, gold: int) -> void:
	popup("+%dg" % gold, world_pos, Color(1, 0.9, 0.3))


# --- World building ---------------------------------------------------------

func _place_trees() -> void:
	for cell in WorldLayout.border_trees():
		_add_tree(cell, true)
	for cell in WorldLayout.scatter_trees():
		_add_tree(cell, false)


func _place_rocks() -> void:
	for cell in WorldLayout.scatter_rocks():
		var sprite := Sprite2D.new()
		sprite.texture = DECOR
		sprite.centered = false
		sprite.region_enabled = true
		sprite.region_rect = ROCK_REGION
		sprite.position = Vector2(-8, -13)
		var shape := RectangleShape2D.new()
		shape.size = Vector2(12, 7)
		_add_obstacle(cell, sprite, shape, Vector2(0, -4))
		farm.blocked[cell] = true


## One static body with a box per pond; the tiles themselves are painted by GroundBuilder.
func _place_ponds() -> void:
	var body := StaticBody2D.new()
	for rect in WorldLayout.PONDS:
		var shape := RectangleShape2D.new()
		shape.size = Vector2(rect.size * TILE)
		var collider := CollisionShape2D.new()
		collider.shape = shape
		collider.position = Vector2(rect.position * TILE) + shape.size / 2.0
		body.add_child(collider)
	add_child(body)


func _add_tree(cell: Vector2i, big: bool) -> void:
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.region_enabled = true
	if big:
		sprite.texture = BIG_OAK
		sprite.region_rect = Rect2(64, 0, 64, 80)
		sprite.position = Vector2(-32, -62)
	else:
		sprite.texture = MEDIUM_OAK
		sprite.region_rect = Rect2(32, 0, 32, 48)
		sprite.position = Vector2(-16, -31)
	var trunk := CircleShape2D.new()
	trunk.radius = 6.0 if big else 4.0
	_add_obstacle(cell, sprite, trunk, Vector2(0, -3))
	farm.blocked[cell] = true


func _place_stall() -> void:
	var sprite := Sprite2D.new()
	sprite.texture = STALLS
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, 48, 48)
	sprite.position = Vector2(-24, -46)
	var counter := RectangleShape2D.new()
	counter.size = Vector2(42, 10)
	var stall := _add_obstacle(STALL_CELL, sprite, counter, Vector2(0, -6))
	_stall_position = stall.global_position + Vector2(0, 8)
	# Azy stands on the plaza just right of the counter (2 cells over is outside the stall footprint).
	_shopkeeper.position = stall.position + Vector2(TILE * 2, 0)
	entities.add_child(_shopkeeper)


## A sign at the west edge of the orchard, next to the east road, so the area is easy to find.
func _place_orchard_sign() -> void:
	var area := WorldLayout.area(&"orchard")
	var cell := Vector2i(area.position.x - 1, area.position.y + 1)
	var sprite := Sprite2D.new()
	sprite.texture = Building.SIGNS
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = Building.SIGN_REGION
	sprite.position = Vector2(-8, -30)
	var post := RectangleShape2D.new()
	post.size = Vector2(8, 5)
	var sign_body := _add_obstacle(cell, sprite, post, Vector2(0, -3))
	var label := Label.new()
	label.text = "Orchard"
	label.custom_minimum_size = Vector2(40, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.05))
	label.add_theme_constant_override("outline_size", 3)
	label.position = Vector2(-20, -37)
	sign_body.add_child(label)
	farm.blocked[cell] = true


## A static body standing on the bottom-centre of `cell`, with a sprite and a collision shape.
func _add_obstacle(cell: Vector2i, sprite: Sprite2D, shape: Shape2D, shape_offset: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = Vector2(cell * TILE) + Vector2(TILE / 2.0, TILE - 2.0)
	body.add_child(sprite)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = shape_offset
	body.add_child(collider)
	entities.add_child(body)
	return body


## Order matters when loading: Game first, then the farm, then fences (they need the soil rules).
func _register_save_systems() -> void:
	SaveGame.register("game", Game)
	SaveGame.register("farm", farm)
	SaveGame.register("fences", _fences)
	SaveGame.register("sprinklers", _sprinklers)  # after "farm": placing checks the soil rules
	SaveGame.register("herd", _herd)  # after "game": it reads Game.animals
	SaveGame.register("orchard", _orchard)
	SaveGame.register("player", player)
	SaveGame.register("gayle", _gayle)
	SaveGame.register("camera", _camera)


## Gayle starts next to Imogen, in the same entities node so she is y-sorted with everyone.
func _place_gayle() -> void:
	_gayle.farm = farm
	_gayle.player = player
	_gayle.walk_bounds = player.walk_bounds
	_gayle.position = player.position + Vector2(-18, 2)
	entities.add_child(_gayle)


func _add_camera() -> void:
	var camera := CameraZoom.new()
	_camera = camera
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = MAP_SIZE.x * TILE
	camera.limit_bottom = MAP_SIZE.y * TILE
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	player.add_child(camera)
