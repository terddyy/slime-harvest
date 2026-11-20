class_name Farmhouse
extends Node2D
## The farmhouse door and the room behind it. The room is drawn far away from the farm
## (at ROOM_ORIGIN); going through the door fades out, moves the player there and swaps
## the camera limits and walk bounds. The bed skips the night (see SleepRules).
## Main creates it and calls setup(). Press E near the door (outside or inside) or the bed.

const TILE := 16
const ROOM_ORIGIN := Vector2(4000, 0)
const FLOOR := Rect2(0, 32, 192, 112)  # room-local pixels
const WALK_RECT := Rect2(8, 44, 176, 96)  # where the player's feet can be, room-local
const INSIDE_DOOR := Vector2(96, 140)  # room-local, on the floor in front of the exit
const BED_SPOT := Vector2(24, 70)  # room-local, where you stand to sleep
const DOOR_RANGE := 22.0
const BED_RANGE := 26.0
const FADE_TIME := 0.3
const SLEEP_FADE_TIME := 0.8
const SLEEP_HOLD_TIME := 0.7

const WALLS := preload("res://assets/cute_fantasy/Buildings/Houses_Interiors/Interior_Walls.png")
const FLOOR_TILES := preload("res://assets/cute_fantasy/Buildings/Houses_Interiors/Wood_Floor_Tiles.png")
const BEDS := preload("res://assets/cute_fantasy/Buildings/House_Decor/Beds.png")
const SHELVES := preload("res://assets/cute_fantasy/Buildings/House_Decor/BookShelves.png")
const WINDOWS := preload("res://assets/cute_fantasy/Buildings/House_Decor/windows.png")
const DOORS := preload("res://assets/cute_fantasy/Buildings/House_Decor/Doors.png")

const WALL_PLANKS := Rect2(48, 48, 16, 16)
const FLOOR_PLANKS := Rect2(16, 32, 16, 16)
const WALL_COLOR := Color(0.27, 0.16, 0.13)
const DOOR_REGION := Rect2(0, 0, 16, 32)

## Door outside: bottom-middle cell of the farmhouse plot, so B1's building can match it.
static func door_cell() -> Vector2i:
	var plot: Rect2i = WorldLayout.area(&"farmhouse_plot")
	return Vector2i(plot.position.x + plot.size.x / 2, plot.end.y - 1)


## The spot in front of the outside door (where E works).
static func door_point() -> Vector2:
	return Vector2(door_cell() * TILE) + Vector2(TILE / 2.0, TILE)


## Where the player is put when stepping out: just below the door, on the road.
static func outside_spot() -> Vector2:
	return Vector2(door_cell() * TILE) + Vector2(TILE / 2.0, TILE + 6.0)


var is_inside := false
## Online only (set by Main): sleeping waits for every player, see _sleep_together.
var world: CoopWorld

var _player: Player
var _camera: CameraZoom
var _farm: Farm
var _fences: Fences
var _hud: Hud
var _entities: Node2D
var _fade := ColorRect.new()
var _wait_label := UiStyle.make_label("", 10)
var _busy := false
var _waiting := false  # in bed online, waiting for the others
var _outside_walk_bounds := Rect2()
var _outside_limits := Rect2i()
var _rng := RandomNumberGenerator.new()


func setup(player: Player, camera: CameraZoom, farm: Farm, fences: Fences, hud: Hud, entities: Node2D) -> void:
	_player = player
	_camera = camera
	_farm = farm
	_fences = fences
	_hud = hud
	_entities = entities
	_rng.randomize()
	position = ROOM_ORIGIN
	z_index = -1  # under the y-sorted Entities (the Ground layer is far away)
	_build_fade()
	_add_furniture(BEDS, Rect2(0, 64, 32, 32), Vector2(24, 66))
	_add_furniture(SHELVES, Rect2(16, 0, 32, 32), Vector2(152, 62))
	_add_outside_door()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-400, -300, 1000, 800), Color.BLACK)
	draw_rect(Rect2(-TILE, 0, FLOOR.size.x + TILE * 2, 160), WALL_COLOR)
	for x in range(0, int(FLOOR.size.x), TILE):
		draw_texture_rect_region(WALLS, Rect2(x, 0, TILE, TILE), WALL_PLANKS)
		draw_texture_rect_region(WALLS, Rect2(x, TILE, TILE, TILE), WALL_PLANKS)
		for y in range(int(FLOOR.position.y), int(FLOOR.end.y), TILE):
			draw_texture_rect_region(FLOOR_TILES, Rect2(x, y, TILE, TILE), FLOOR_PLANKS)
	draw_texture_rect_region(WINDOWS, Rect2(88, 4, 16, 24), Rect2(0, 0, 16, 24))
	draw_texture_rect_region(DOORS, Rect2(INSIDE_DOOR.x - 8, 128, 16, 32), DOOR_REGION)


## E near the door or the bed. Returns true when it handled the press.
func interact() -> bool:
	if _busy:
		if _waiting:
			world.cancel_sleep()  # E again: get out of bed
		return true
	if is_inside:
		if _near_inside_door():
			_go(false)
			return true
		if _near_bed():
			_try_sleep()
			return true
		return false
	if _near_outside_door():
		_go(true)
		return true
	return false


## Text for the HUD hint line ("" when there is nothing to do here).
func hint() -> String:
	if _waiting:
		return "E: get out of bed"
	if _busy:
		return ""
	if is_inside:
		if _near_inside_door():
			return "E: go outside"
		if _near_bed():
			return "E: sleep until morning" if _can_sleep() else "Too early to sleep (afternoon or night)"
		return ""
	return "E: go inside" if _near_outside_door() else ""


# --- Going in and out -------------------------------------------------------

func _go(inside: bool) -> void:
	_busy = true
	_player.set_physics_process(false)
	await _fade_to(1.0, FADE_TIME)
	_set_inside(inside)
	await _fade_to(0.0, FADE_TIME)
	_player.set_physics_process(true)
	_busy = false


func _set_inside(inside: bool) -> void:
	is_inside = inside
	if inside:
		_outside_walk_bounds = _player.walk_bounds
		_outside_limits = Rect2i(_camera.limit_left, _camera.limit_top, _camera.limit_right - _camera.limit_left, _camera.limit_bottom - _camera.limit_top)
		_player.walk_bounds = Rect2(WALK_RECT.position + ROOM_ORIGIN, WALK_RECT.size)
		_player.global_position = ROOM_ORIGIN + INSIDE_DOOR + Vector2(0, -6)
		_player.facing = Vector2.UP
		_player.save_position_override = outside_spot()
		_set_camera_limits(Rect2i(Vector2i(ROOM_ORIGIN) + Vector2i(-300, -200), Vector2i(792, 560)))
	else:
		_player.walk_bounds = _outside_walk_bounds
		_player.global_position = outside_spot()
		_player.facing = Vector2.DOWN
		_player.save_position_override = Vector2.INF
		_set_camera_limits(_outside_limits)
	_camera.reset_smoothing()
	_player.velocity = Vector2.ZERO


func _set_camera_limits(limits: Rect2i) -> void:
	_camera.limit_left = limits.position.x
	_camera.limit_top = limits.position.y
	_camera.limit_right = limits.end.x
	_camera.limit_bottom = limits.end.y


# --- Sleeping ---------------------------------------------------------------

func _can_sleep() -> bool:
	return SleepRules.can_sleep(Game.is_night, Game.phase_progress())


func _try_sleep() -> void:
	if not _can_sleep():
		_hud.show_banner("Too early to sleep")
		return
	if Net.is_online():
		_sleep_together()
	else:
		_sleep()


func _sleep() -> void:
	_busy = true
	_player.set_physics_process(false)
	await _fade_to(1.0, SLEEP_FADE_TIME)
	_hud.show_banner(sleep_through_night())
	await get_tree().create_timer(SLEEP_HOLD_TIME).timeout
	await _fade_to(0.0, SLEEP_FADE_TIME)
	_player.set_physics_process(true)
	_busy = false


## The night passes: slimes eat the crops that are not fenced in, then it is morning.
## Returns the banner text. Solo it runs when you sleep; online the host runs it once everybody is in bed.
func sleep_through_night() -> String:
	var eaten := SleepRules.eaten_crops(_farm.crop_cells(), _fences.has_fence, _farm.bounds, _rng)
	for cell in eaten:
		_farm.remove_crop(cell)
	Game.sleep_to_morning()  # Main reacts: dawn banner, clears enemies, auto-save
	if eaten.is_empty():
		return "Day %d - you slept well" % Game.day
	return "Day %d - slimes ate %d crop%s while you slept" % [Game.day, eaten.size(), "" if eaten.size() == 1 else "s"]


## Online: go to bed and wait. When every player is in bed the host runs the morning and CoopWorld
## wakes everybody (E gets you out of bed again). The world keeps running meanwhile.
func _sleep_together() -> void:
	_busy = true
	_waiting = true
	_player.set_physics_process(false)
	await _fade_to(1.0, SLEEP_FADE_TIME)
	_wait_label.text = "Waiting for the others..."
	_wait_label.visible = true
	var woke_with := [false, ""]
	world.woke.connect(func(text: String) -> void:
		woke_with[0] = true
		woke_with[1] = text, CONNECT_ONE_SHOT)
	world.sleep_waiting.connect(_show_waiting)
	world.set_sleeping(true)
	while not woke_with[0]:
		await get_tree().process_frame
	world.sleep_waiting.disconnect(_show_waiting)
	_waiting = false
	_wait_label.visible = false
	if woke_with[1] != "":
		_hud.show_banner(woke_with[1])
		await get_tree().create_timer(SLEEP_HOLD_TIME).timeout
	await _fade_to(0.0, SLEEP_FADE_TIME)
	_player.set_physics_process(true)
	_busy = false


func _show_waiting(missing: int) -> void:
	_wait_label.text = "Waiting for %d more..." % missing if missing > 0 else "Waiting for the others..."


# --- Helpers ----------------------------------------------------------------

func _near_outside_door() -> bool:
	return _player.global_position.distance_to(door_point()) < DOOR_RANGE


func _near_inside_door() -> bool:
	return _player.global_position.distance_to(ROOM_ORIGIN + INSIDE_DOOR) < DOOR_RANGE


func _near_bed() -> bool:
	return _player.global_position.distance_to(ROOM_ORIGIN + BED_SPOT) < BED_RANGE


func _fade_to(alpha: float, time: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, time)
	await tween.finished


func _build_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)
	_wait_label.size = UiStyle.SCREEN
	_wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wait_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wait_label.visible = false
	layer.add_child(_wait_label)
	add_child(layer)


## A static body (so the player walks around it) standing on `feet`, a room-local position.
func _add_furniture(texture: Texture2D, region: Rect2, feet: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.position = Vector2(-region.size.x / 2.0, -region.size.y)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(region.size.x - 4.0, 10.0)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = Vector2(0, -5)
	var body := StaticBody2D.new()
	body.position = ROOM_ORIGIN + feet
	body.add_child(sprite)
	body.add_child(collider)
	_entities.add_child(body)


## Placeholder door sprite on the farm side. B1's restored farmhouse should be drawn
## around door_cell() and can drop this.
func _add_outside_door() -> void:
	var sprite := Sprite2D.new()
	sprite.texture = DOORS
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = DOOR_REGION
	sprite.offset = Vector2(-8, -32)  # feet at the node position (bottom-centre of the door cell)
	sprite.position = Vector2(door_cell() * TILE) + Vector2(TILE / 2.0, TILE)
	_entities.add_child(sprite)
