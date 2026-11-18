extends Node
## Input regression test with real input events (run as a scene, exit 1 on failure):
##   godot --headless --path . res://tests/aim_test.tscn
## Guards against bugs found in play-testing:
## - with the mouse resting to the right, attacks went right even when running left
## - the sword must hit in front and on the front diagonals, never behind
## - clicking a ripe crop with a farming tool harvests it
## - holding the button and dragging waters tile after tile, quickly

var _main: Node
var _player: Player
var _farm: Farm
var _start := Vector2.ZERO
var _mouse_screen := Vector2.ZERO
var _failures := 0


func _ready() -> void:
	SaveGame.path = "user://test_save_aim.json"  # never touch the real save
	SaveGame.delete()
	Game.reset()
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	_player = _main.get_node("Entities/Player")
	_farm = _main.get_node("Farm")
	_start = _player.global_position
	await get_tree().create_timer(0.3).timeout
	await _test_sword()
	await _test_click_harvest()
	await _test_drag_watering()
	await _test_drag_untilling()
	await _test_run_and_water()
	await _test_zoom()
	await _test_no_survival()
	await _test_buildings()
	await _test_farmhouse()
	await _test_save_load()
	await _test_animals()
	await _test_gayle()
	await _test_music_pause()
	await _test_inventory()
	await _test_saplings()
	await _test_save_roundtrip()
	SaveGame.delete()
	print("aim test: %d failed" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	print("%s %s" % ["ok  " if ok else "FAIL", label])
	if not ok:
		_failures += 1


# --- Sword ------------------------------------------------------------------

func _test_sword() -> void:
	_player.choose_slot(Player.Tool.SWORD)
	# [label, key to face with, slime offset, attack with, should hit]
	var cases := [
		["face left, slime left, Space", KEY_A, Vector2(-20, 0), "space", true],
		["face left, slime left, click (mouse on the right)", KEY_A, Vector2(-20, 0), "click", true],
		["face left, slime up-left diagonal", KEY_A, Vector2(-15, -15), "space", true],
		["face left, slime down-left diagonal", KEY_A, Vector2(-15, 15), "click", true],
		["face up, slime up-left diagonal", KEY_W, Vector2(-15, -15), "space", true],
		["face down, slime below", KEY_S, Vector2(0, 20), "space", true],
		["face right, slime right", KEY_D, Vector2(20, 0), "click", true],
		["face right, slime behind (left)", KEY_D, Vector2(-22, 0), "space", false],
	]
	for case in cases:
		_player.global_position = _start
		await _tap(case[1])
		_player.global_position = _start
		_park_mouse_right()
		var slime := _main._spawner.spawn("medium", _start + case[2]) as Slime
		slime.set_process(false)
		await get_tree().process_frame
		var hp := slime.hp
		if case[3] == "space":
			await _tap(KEY_SPACE)
		else:
			await _click()
		await get_tree().create_timer(0.35).timeout
		_check((slime.hp < hp) == case[4], "%s (hit=%s, facing=%s)" % [case[0], slime.hp < hp, _player.facing])
		slime.queue_free()
		await get_tree().create_timer(0.1).timeout

	# Running left (key held) and clicking with the mouse on the right still swings left.
	_player.global_position = _start
	_park_mouse_right()
	var left_slime := _main._spawner.spawn("medium", _start + Vector2(-24, 0)) as Slime
	left_slime.set_process(false)
	await _key(KEY_A, true)
	await get_tree().physics_frame
	await _click()
	await _key(KEY_A, false)
	await get_tree().create_timer(0.35).timeout
	_check(left_slime.hp < Slime.STATS[Slime.Size.MEDIUM]["hp"], "running left + click hits the slime on the left")
	left_slime.queue_free()

	# Attacking while running doesn't stop the player.
	_player.global_position = _start
	var ahead := _main._spawner.spawn("medium", _start + Vector2(26, 0)) as Slime
	ahead.set_process(false)
	await _key(KEY_D, true)
	await get_tree().create_timer(0.1).timeout
	var x_before := _player.global_position.x
	await _tap(KEY_SPACE)
	await get_tree().create_timer(0.15).timeout
	var moved := _player.global_position.x - x_before
	var swinging := _player._anim == "attack"
	await _key(KEY_D, false)
	await get_tree().create_timer(0.2).timeout
	_check(moved > 10.0 and swinging, "running right + Space keeps moving during the swing (moved %.1f px)" % moved)
	_check(ahead.hp < Slime.STATS[Slime.Size.MEDIUM]["hp"], "the running swing hits the slime ahead")
	ahead.queue_free()


# --- Farming ----------------------------------------------------------------

func _test_click_harvest() -> void:
	_player.global_position = _start
	var cell := _farm.cell_at(_start + Vector2(0, -2)) + Vector2i(1, 0)
	_farm.till(cell)
	_farm.plant(cell, "carrot")
	var crop := _farm.get_crop(cell)
	for i in Crop.STAGES:
		crop.try_grow(true)
	_player.choose_slot(Player.Tool.WATER)
	var before := Game.crop_count("carrot")
	_move_mouse(_farm.cell_center(cell))
	await _click()
	await get_tree().create_timer(0.2).timeout
	_check(_farm.get_crop(cell) == null and Game.crop_count("carrot") == before + 1,
		"clicking a ripe crop with the watering can harvests it")


func _test_drag_watering() -> void:
	_player.global_position = _start
	var own := _farm.cell_at(_start + Vector2(0, -2))
	var cells: Array[Vector2i] = [own + Vector2i(-1, 2), own + Vector2i(0, 2), own + Vector2i(1, 2)]
	for cell in cells:
		_farm.till(cell)
	_player.choose_slot(Player.Tool.WATER)
	var started := Time.get_ticks_msec()
	_move_mouse(_farm.cell_center(cells[0]))
	await _mouse_button(true)
	for cell in cells:
		_move_mouse(_farm.cell_center(cell))
		var waited := 0
		while not _farm.is_wet(cell) and waited < 60:
			await get_tree().physics_frame
			waited += 1
	await _mouse_button(false)
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	var all_wet := cells.all(func(c: Vector2i) -> bool: return _farm.is_wet(c))
	_check(all_wet, "holding the button and dragging waters 3 tiles")
	_check(seconds < 1.2, "watering 3 tiles by dragging takes under 1.2 s (took %.2f s)" % seconds)


## The first tile of a hoe hold decides: grass = till every tile, soil = untill every tile.
func _test_drag_untilling() -> void:
	_player.global_position = _start
	var own := _farm.cell_at(_start + Vector2(0, -2))
	var row: Array[Vector2i] = [own + Vector2i(-1, 1), own + Vector2i(0, 1), own + Vector2i(1, 1)]
	_player.choose_slot(Player.Tool.HOE)
	await get_tree().create_timer(0.5).timeout  # let the watering animation end

	# Start on grass, drag over soil: everything ends up tilled.
	_farm.till(row[1])
	await _drag_hoe(row)
	_check(row.all(func(c: Vector2i) -> bool: return _farm.is_tilled(c)), "hoe drag from grass tills every tile, even already tilled ones stay")

	# Start on empty soil, drag over grass and a crop: soil goes, crop soil stays.
	_farm.untill(row[2])
	_farm.plant(row[1])
	await _drag_hoe(row)
	_check(not _farm.is_tilled(row[0]), "hoe drag from soil untills the first tile")
	_check(_farm.is_tilled(row[1]) and _farm.get_crop(row[1]) != null, "hoe drag never touches soil with a crop")
	_check(not _farm.is_tilled(row[2]), "hoe drag from soil does not till grass")

	_farm.remove_crop(row[1])
	for cell in row:
		_farm.untill(cell)


func _drag_hoe(cells: Array[Vector2i]) -> void:
	_player.global_position = _start
	_move_mouse(_farm.cell_center(cells[0]))
	await _mouse_button(true)
	for cell in cells:
		_move_mouse(_farm.cell_center(cell))
		for i in 30:
			await get_tree().physics_frame
	await _mouse_button(false)
	await get_tree().create_timer(0.3).timeout


func _test_run_and_water() -> void:
	# Hold Space with the watering can and run right along a tilled row: each tile just
	# ahead of the player gets watered as they go.
	_player.global_position = _start + Vector2(0, -48)  # a fresh row above the others
	var row_start := _player.global_position
	await _tap(KEY_D)  # face right
	_player.global_position = row_start
	var own := _farm.cell_at(row_start + Vector2(0, -2))
	var cells: Array[Vector2i] = []
	for x in range(1, 6):
		cells.append(own + Vector2i(x, 0))
		_farm.till(cells[-1])
	_player.choose_slot(Player.Tool.WATER)
	await _key(KEY_SPACE, true)
	await get_tree().physics_frame
	await _key(KEY_D, true)
	var x_before := _player.global_position.x
	await get_tree().create_timer(1.0).timeout
	await _key(KEY_D, false)
	await _key(KEY_SPACE, false)
	var moved := _player.global_position.x - x_before
	var wet := cells.filter(func(c: Vector2i) -> bool: return _farm.is_wet(c)).size()
	_check(moved > 50.0, "holding Space while running keeps moving (moved %.0f px)" % moved)
	_check(wet >= 4, "running along a row with Space held waters it (%d of 5 wet)" % wet)


func _test_zoom() -> void:
	var camera := get_viewport().get_camera_2d() as CameraZoom
	_check(camera != null, "the player camera is a CameraZoom")
	var start_zoom := camera.zoom_level()
	await _tap(KEY_EQUAL)
	_check(camera.zoom_level() > start_zoom, "+ zooms in")
	await _tap(KEY_MINUS)
	await _tap(KEY_MINUS)
	_check(camera.zoom_level() < start_zoom, "- zooms out")

	_player.choose_slot(Player.Tool.HOE)
	var before := camera.zoom_level()
	await _wheel(MOUSE_BUTTON_WHEEL_UP, true)
	_check(camera.zoom_level() > before and _player.tool == Player.Tool.HOE,
		"Ctrl + wheel zooms and doesn't switch tools")
	before = camera.zoom_level()
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN, false)
	_check(camera.zoom_level() == before and _player.tool == Player.Tool.WATER,
		"plain wheel switches tools and doesn't zoom")

	before = camera.zoom_level()
	var pinch := InputEventMagnifyGesture.new()
	pinch.factor = 1.2
	Input.parse_input_event(pinch)
	await get_tree().physics_frame
	_check(camera.zoom_level() > before, "touchpad pinch zooms in")

	for i in 10:
		await _tap(KEY_EQUAL)
	_check(is_equal_approx(camera.zoom_level(), CameraZoom.ZOOM_STEPS[-1]), "zoom stops at the closest step")
	await get_tree().create_timer(0.4).timeout  # let the zoom tween and camera settle
	var own := _farm.cell_at(_player.global_position + Vector2(0, -2))
	_move_mouse(_farm.cell_center(own + Vector2i(1, -1)))
	await get_tree().physics_frame
	_check(_player.aim_cell(_player.get_global_mouse_position()) == own + Vector2i(1, -1),
		"mouse aiming picks the right tile while zoomed in")
	for i in 10:
		await _tap(KEY_MINUS)
	_check(is_equal_approx(camera.zoom_level(), CameraZoom.ZOOM_STEPS[0]), "zoom stops at the widest step")
	while camera.zoom_level() < 1.0:
		camera.change_zoom(1)  # leave the normal zoom for the next run


# --- Input helpers ----------------------------------------------------------

func _park_mouse_right() -> void:
	_move_mouse(_start + Vector2(120, 30))


func _move_mouse(world: Vector2) -> void:
	_mouse_screen = get_viewport().get_final_transform() * (get_viewport().get_canvas_transform() * world)
	var motion := InputEventMouseMotion.new()
	motion.position = _mouse_screen
	motion.global_position = _mouse_screen
	motion.relative = Vector2(1, 0)  # jitter-sized, like a resting touchpad
	Input.parse_input_event(motion)


func _mouse_button(pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = _mouse_screen
	e.global_position = _mouse_screen
	Input.parse_input_event(e)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _wheel(button: MouseButton, ctrl: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.position = _mouse_screen
	e.global_position = _mouse_screen
	Input.parse_input_event(e)
	await get_tree().physics_frame


func _click() -> void:
	await _mouse_button(true)
	await _mouse_button(false)


func _key(key: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = key
	e.keycode = key
	e.pressed = pressed
	Input.parse_input_event(e)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _tap(key: Key) -> void:
	await _key(key, true)
	await _key(key, false)


# --- No survival (Sprint 2) -----------------------------------------------------

func _test_no_survival() -> void:
	_check(not _player.has_method("take_damage") and not ("hp" in _player), "the player has no health")
	var slime := _main._spawner.spawn("medium", _start + Vector2(4, 0)) as Slime
	slime.set_process(false)
	await get_tree().create_timer(0.5).timeout
	_check(is_instance_valid(slime) and not ("player" in slime), "slimes do not know about the player")
	slime.queue_free()


# --- Farmhouse (B2) -----------------------------------------------------------------

func _test_farmhouse() -> void:
	var house: Farmhouse = _main._farmhouse
	var door := Vector2(Farmhouse.door_cell() * 16) + Vector2(8, 16)
	_player.global_position = door + Vector2(0, 8)
	await get_tree().process_frame
	_check(house.hint() == "E: go inside", "farmhouse: hint at the door")
	house.interact()
	await get_tree().create_timer(1.0).timeout
	_check(house.is_inside and _player.global_position.x > Farmhouse.ROOM_ORIGIN.x, "farmhouse: E at the door moves you inside")
	_check(_player.to_save()["x"] < 2000.0, "farmhouse: a save made indoors stores the outside spot")

	# Too early to sleep (start of a day), then sleep at night with one exposed and one fenced crop.
	Game.is_night = false
	Game.time_left = Game.DAY_LENGTH
	_player.global_position = Farmhouse.ROOM_ORIGIN + Farmhouse.BED_SPOT
	var day := Game.day
	house.interact()
	await get_tree().create_timer(0.3).timeout
	_check(Game.day == day, "farmhouse: no sleeping early in the day")
	Game.is_night = true
	Game.time_left = 20.0
	house.interact()
	await get_tree().create_timer(2.8).timeout
	_check(Game.day == day + 1 and not Game.is_night, "farmhouse: sleeping skips to the next morning")

	_player.global_position = Farmhouse.ROOM_ORIGIN + Farmhouse.INSIDE_DOOR
	house.interact()
	await get_tree().create_timer(1.0).timeout
	_check(not house.is_inside and _player.global_position.distance_to(Farmhouse.outside_spot()) < 20.0, "farmhouse: E at the inside door puts you back outside")
	_check(_player.to_save()["x"] == _player.global_position.x, "farmhouse: saves use the real position outside")
	Game.day = 1


# --- Saving (F3) --------------------------------------------------------------------

## Saves the running world, wipes it, loads it back: farm, fences, player and Game all return.
func _test_buildings() -> void:
	var buildings: Buildings = _main._buildings
	var board: RestorationBoard = _main._board
	var barn := buildings.get_building("barn")
	_check(barn != null and not barn.restored, "buildings: the barn starts as a ruin")
	_player.global_position = buildings.board_position + Vector2(0, 10)
	_check(buildings.is_near_board(_player.global_position), "buildings: the board can be used from in front of it")
	_check(not buildings.is_near_board(_start), "buildings: the board is out of reach from the field")
	Game.gold = 0
	board.open()
	_check(get_tree().paused, "buildings: the board pauses the game")
	board._restore("barn")
	_check(not barn.restored and not Game.is_restored("barn"), "buildings: no gold, no repair")
	Game.gold = int(Restoration.project("barn")["cost"]) + 5
	board._restore("barn")
	_check(barn.restored and Game.is_restored("barn") and Game.gold == 5, "buildings: paying for the barn restores it")
	board.close()
	_check(not get_tree().paused, "buildings: closing the board unpauses")
	Game.restored = {}
	Game.stats_changed.emit()  # what loading a save does
	_check(not barn.restored, "buildings: syncing with Game turns the barn back into a ruin")
	_player.global_position = _start


func _test_save_load() -> void:
	var fences: Fences = _main._fences
	var cell := _farm.cell_at(_start) + Vector2i(0, 3)
	_farm.till(cell)
	_farm.water(cell)
	_farm.plant(cell, "tomato")
	var fence_cell := cell + Vector2i(2, 0)
	fences.place(fence_cell)
	_player.global_position = _start + Vector2(10, 6)
	_player.facing = Vector2.LEFT
	_player.set_tool(Player.Tool.FENCE)
	Game.gold = 77
	Game.day = 4
	_check(SaveGame.save() and SaveGame.has_save(), "save: the running world saves")

	_farm.remove_crop(cell)
	fences.remove(fence_cell)
	_player.global_position = _start
	_player.facing = Vector2.DOWN
	_player.set_tool(Player.Tool.HOE)
	Game.gold = 0
	Game.day = 1
	_check(SaveGame.load_game(), "save: the save loads")
	_check(_farm.get_crop(cell) != null and _farm.get_crop(cell).crop_id == "tomato" and _farm.is_wet(cell), "save: crop and wet soil are back")
	_check(fences.has_fence(fence_cell), "save: fence is back")
	_check(_player.global_position.distance_to(_start + Vector2(10, 6)) < 0.1 and _player.facing == Vector2.LEFT, "save: player position and facing are back")
	_check(_player.tool == Player.Tool.FENCE, "save: selected tool is back")
	_check(Game.gold == 77 and Game.day == 4, "save: gold and day are back")
	Game.gold = 0
	Game.day = 1


# --- Animals (B3) --------------------------------------------------------------------

## Buy a chicken, wait for the next day, collect with E, then save, wipe and load the herd.
func _test_animals() -> void:
	var herd: Herd = _main._herd
	Game.reset()
	Game.gold = 500
	Game.restored = {"chicken_coop": true}
	_player.global_position = _start
	_check(Game.buy_animal("chicken") and herd.animals().size() == 1, "animals: buying spawns a chicken")
	var chicken: Animal = herd.animals()[0]
	var pen := Herd.pen_rect("chicken")
	_check(pen.has_point(chicken.position), "animals: the chicken starts inside its pen")
	await get_tree().create_timer(3.0).timeout
	_check(pen.has_point(chicken.position), "animals: the chicken stays in its pen while wandering")
	_check(not chicken.has_product(), "animals: no egg on the day it was bought")
	_check(not herd.collect_near(chicken.global_position), "animals: nothing to collect yet")
	Game.day += 1
	_check(chicken.has_product(), "animals: an egg is ready the next day")
	_player.global_position = chicken.global_position
	var press := InputEventAction.new()
	press.action = "interact"
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	_check(Game.products_in_bag.get("egg", 0) == 1 and not chicken.has_product(), "animals: E collects the egg once")

	chicken.global_position = Herd.pen_rect("chicken").position + Vector2(5, 5)
	Game.day += 1
	var saved_position := chicken.position
	_check(SaveGame.save(), "animals: saves")
	Game.reset()
	herd.from_save({})
	_check(herd.animals().is_empty(), "animals: an empty save clears the herd")
	SaveGame.load_game()
	await get_tree().process_frame
	_check(herd.animals().size() == 1 and herd.animals()[0].position.distance_to(saved_position) < 0.1, "animals: the herd and its position are back")
	_check(herd.animals()[0].has_product(), "animals: the ready egg is still ready after loading")
	Game.reset()
	herd.from_save({})


# --- Gayle (B4) --------------------------------------------------------------------

func _test_gayle() -> void:
	var gayle: Gayle = _main._gayle
	Game.is_night = false
	_player.global_position = _start
	gayle.global_position = _start + Vector2(120, 0)
	await get_tree().create_timer(2.0).timeout
	_check(gayle.global_position.distance_to(_player.global_position) < Gayle.FOLLOW_FAR + 8.0, "gayle: follows Imogen")

	# Walking straight through Gayle is never blocked (she is on another physics layer).
	gayle.global_position = _player.global_position + Vector2(10, 0)
	_player.facing = Vector2.RIGHT
	var before := _player.global_position.x
	Input.action_press("move_right")
	await get_tree().create_timer(0.4).timeout
	Input.action_release("move_right")
	_check(_player.global_position.x - before > 15.0, "gayle: never blocks Imogen")

	# Day: waters a dry crop near her.
	var cell := _farm.cell_at(_player.global_position) + Vector2i(0, 2)
	_farm.till(cell)
	_farm.plant(cell)
	gayle._water_timer = Gayle.WATER_INTERVAL
	await get_tree().create_timer(1.0).timeout
	_check(_farm.is_wet(cell), "gayle: waters a dry crop by day")

	# Night: hits a slime that is eating a crop.
	Game.is_night = true
	var slime := _main._spawner.spawn("medium", _farm.get_crop(cell).global_position + Vector2(2, 0)) as Slime
	var hp := slime.hp
	await get_tree().create_timer(3.0).timeout
	_check(not is_instance_valid(slime) or slime.hp < hp, "gayle: hits a slime that eats a crop at night")
	if is_instance_valid(slime):
		slime.queue_free()
	Game.is_night = false

	# Stay mode: she holds her spot; the mode and position are saved.
	gayle.toggle_mode()
	var spot := gayle.global_position
	_player.global_position = _start + Vector2(100, 0)
	await get_tree().create_timer(1.0).timeout
	_check(gayle.global_position.distance_to(spot) < 1.0, "gayle: stays where she is in Stay mode")
	_check(SaveGame.save(), "gayle: world saves")
	gayle.toggle_mode()
	gayle.global_position = _start
	_check(SaveGame.load_game() and gayle.mode == Gayle.Mode.STAY and gayle.global_position.distance_to(spot) < 0.1, "gayle: mode and position round trip")
	gayle.toggle_mode()
	gayle.teleport_to_player()
	_check(gayle.global_position.distance_to(_player.global_position) < 24.0, "gayle: teleports back next to Imogen")
	var talk: GayleTalk = _main._gayle_talk
	talk.open()
	_check(talk.is_open() and get_tree().paused, "gayle: E opens the dialog and pauses")
	talk._on_toggle()
	_check(not gayle.is_following(), "gayle: dialog toggle switches to Stay")
	talk.close()
	_check(not talk.is_open() and not get_tree().paused, "gayle: dialog closes and unpauses")


# --- Save coverage (P2) -----------------------------------------------------------------

## Music tracks loop; sound effects (also children of Audio) do not.
func _is_looping_music(player: AudioStreamPlayer) -> bool:
	var wav := player.stream as AudioStreamWAV
	return wav != null and player.playing and wav.loop_mode != AudioStreamWAV.LOOP_DISABLED


## Opening the pause menu pauses the music players, closing it resumes them.
func _test_music_pause() -> void:
	var menu := _main.get_node("PauseMenu") as PauseMenu
	var players: Array[AudioStreamPlayer] = []
	for child in Audio.get_children():
		if child is AudioStreamPlayer and _is_looping_music(child as AudioStreamPlayer):
			players.append(child)
	_check(not players.is_empty(), "music: a track is playing")
	menu.open()
	await get_tree().process_frame
	var all_paused := true
	for player in players:
		all_paused = all_paused and player.stream_paused
	_check(all_paused, "music: pause menu pauses the music")
	menu.close()
	await get_tree().process_frame
	var any_paused := false
	for player in players:
		any_paused = any_paused or player.stream_paused
	_check(not any_paused, "music: closing the pause menu resumes it")


## Tab opens and closes the inventory (pausing the game and keeping the music going), Left/Right
## switch pages, a seed row equips it, G opens the Goals page, and it never opens over the shop.
func _test_inventory() -> void:
	var panel: InventoryPanel = _main._inventory
	Game.seeds["corn"] = 2
	await _tap(KEY_TAB)
	_check(panel.is_open() and get_tree().paused, "inventory: Tab opens it and pauses")
	await get_tree().create_timer(InventoryPanel.SLIDE_TIME + 0.1).timeout
	_check(panel.visible and is_equal_approx(panel._panel.position.y, InventoryPanel.OPEN_Y), "inventory: slid up above the hotbar")
	await _tap(KEY_RIGHT)
	_check(panel._page == InventoryPanel.Page.STORAGE, "inventory: Right switches to Storage")
	await _tap(KEY_LEFT)
	await _tap(KEY_LEFT)
	_check(panel._page == InventoryPanel.Page.GOALS, "inventory: Left wraps round to Goals")
	await _tap(KEY_TAB)
	_check(not panel.is_open() and not get_tree().paused, "inventory: Tab closes it and unpauses")
	await get_tree().create_timer(InventoryPanel.SLIDE_TIME + 0.1).timeout
	_check(not panel.visible, "inventory: hidden after sliding down")

	panel.open()
	panel.show_page(InventoryPanel.Page.BACKPACK)
	var corn_button: Button
	for button in panel._backpack.find_children("*", "Button", true, false):
		if (button as Button).text.begins_with("Corn"):
			corn_button = button
	_check(corn_button != null, "inventory: corn seeds listed in the backpack")
	if corn_button != null:
		corn_button.pressed.emit()
	_check(_player.tool == Player.Tool.SEEDS and _player.seed_id == "corn", "inventory: clicking corn seeds equips them")
	_check(not panel.is_open() and not get_tree().paused, "inventory: equipping closes it")

	await _tap(KEY_G)
	_check(panel.is_open() and panel._page == InventoryPanel.Page.GOALS, "inventory: G opens the Goals page")
	await _tap(KEY_ESCAPE)
	_check(not panel.is_open() and not get_tree().paused, "inventory: Esc closes it without opening the pause menu")
	_check(not (_main.get_node("PauseMenu") as PauseMenu).is_open(), "inventory: Esc did not open the pause menu")

	get_tree().paused = true  # something else (the shop) owns the pause
	panel.open()
	_check(not panel.is_open(), "inventory: never opens while another menu has the game paused")
	get_tree().paused = false
	await get_tree().create_timer(InventoryPanel.SLIDE_TIME + 0.1).timeout


## Q cycles seeds and then owned saplings, the bag equips a sapling, using the Seeds tool plants
## only inside the orchard, and outside it the hint and guide arrow send you there.
func _test_saplings() -> void:
	var orchard: Orchard = _main._orchard
	orchard.from_save({})
	Game.seeds = {"carrot": 3, "corn": 2}
	Game.saplings = {"apple": 1, "pear": 1}
	_player.set_seed("carrot")
	_player.set_tool(Player.Tool.SEEDS)
	var order: Array[String] = []
	for i in 4:
		await _tap(KEY_Q)
		order.append(_player.sapling_id if _player.sapling_id != "" else _player.seed_id)
	_check(order == ["corn", "apple", "pear", "carrot"], "saplings: Q cycles seeds then saplings (%s)" % [order])

	var panel: InventoryPanel = _main._inventory
	panel.open()
	panel.show_page(InventoryPanel.Page.BACKPACK)
	for button in panel._backpack.find_children("*", "Button", true, false):
		if (button as Button).text.begins_with("Apple"):
			(button as Button).pressed.emit()
	_check(_player.tool == Player.Tool.SEEDS and _player.sapling_id == "apple", "saplings: clicking one in the backpack equips it")
	_check(_main.hud._seed_count.text == "1", "saplings: the hotbar slot shows the sapling count")

	_player.global_position = _start
	_move_mouse(_start + Vector2(0, 16))
	await get_tree().create_timer(0.1).timeout
	_check(_main._guide_goal() == "orchard", "saplings: the guide arrow points at the orchard from outside")
	_check(_main.hud._hint_label.text.contains("follow the arrow"), "saplings: hint outside the orchard says where to go")
	await _click()
	_check(orchard.tree_count() == 0 and Game.sapling_count("apple") == 1, "saplings: nothing is planted outside the orchard")

	var inside := orchard.area.position + Vector2i(3, 3)
	_player.global_position = _farm.cell_center(inside + Vector2i(-1, 0))
	await get_tree().create_timer(1.0).timeout  # the camera glides after the jump; the mouse is placed on screen
	_move_mouse(_farm.cell_center(inside))
	await get_tree().create_timer(0.1).timeout
	_check(_main._guide_goal() != "orchard", "saplings: no orchard arrow once you are in the orchard")
	await _click()
	_check(orchard.has_tree(inside) and Game.sapling_count("apple") == 0, "saplings: clicking in the orchard plants the sapling")
	_check(_player.sapling_id == "pear", "saplings: the next sapling is selected when one runs out")
	_move_mouse(_farm.cell_center(inside + Vector2i(1, 0)))
	await _click()
	_check(not orchard.has_tree(inside + Vector2i(1, 0)) and Game.sapling_count("pear") == 1, "saplings: trees keep one cell apart")
	Game.saplings = {}
	Game.seeds = {}
	orchard.from_save({})
	_player.set_seed("carrot")
	_player.global_position = _start


## Plays a few days with every Phase-2 system holding state, saves, wipes the world, loads,
## and checks that saving again gives exactly the same file contents.
func _test_save_roundtrip() -> void:
	var herd: Herd = _main._herd
	var orchard: Orchard = _main._orchard
	var gayle: Gayle = _main._gayle
	var fences: Fences = _main._fences
	Game.reset()
	herd.from_save({})
	orchard.from_save({})
	_player.global_position = _start
	Game.gold = 5000
	Game.restored = {"well": true, "chicken_coop": true, "barn": true}
	Game.stats_changed.emit()
	Game.buy_animal("chicken")
	Game.buy_animal("cow")
	Game.saplings = {"apple": 1}
	var tree_cell := orchard.area.position + Vector2i(1, 2)
	orchard.plant(tree_cell, "apple")
	var crop_cell := _farm.cell_at(_start) + Vector2i(0, 4)
	_farm.till(crop_cell)
	_farm.water(crop_cell)
	_farm.plant(crop_cell, "carrot")
	fences.place(crop_cell + Vector2i(3, 0))
	gayle.mode = Gayle.Mode.STAY
	gayle.global_position = _start + Vector2(30, 20)
	_player.set_tool(Player.Tool.SWORD)
	Game.upgrades["sword"] = 1
	Game.crops_in_bag = {"carrot": 3}
	Game.products_in_bag = {"egg": 2}
	Game.fruit_in_bag = {"apple": 1}
	for i in 4:  # four mornings: trees grow, animals have products again
		Game.sleep_to_morning()
		orchard.new_day()
	Game.is_night = false
	Game.time_left = 60.0
	_check(SaveGame.save(), "roundtrip: world saves")
	var before := JSON.stringify(SaveGame.read())

	# Wipe every system, then load.
	Game.reset()
	Game.stats_changed.emit()
	herd.from_save({})
	orchard.from_save({})
	_farm.from_save({})
	fences.from_save({})
	gayle.mode = Gayle.Mode.FOLLOW
	gayle.global_position = _start
	_player.global_position = _start
	_check(SaveGame.load_game(), "roundtrip: the save loads")
	_check(JSON.stringify(SaveGame.read()) == before, "roundtrip: the file did not change by loading")
	_check(SaveGame.save() and JSON.stringify(SaveGame.read()) == before, "roundtrip: saving a loaded world gives the same save")
	_check(Game.day == 5 and Game.is_restored("barn") and Game.animal_count("cow") == 1, "roundtrip: day, buildings and animals are back")
	_check(herd.animals().size() == 2, "roundtrip: the herd is back")
	_check(orchard.has_tree(tree_cell) and orchard.stage(tree_cell) >= 1, "roundtrip: the fruit tree and its age are back")
	_check(_farm.get_crop(crop_cell) != null and fences.has_fence(crop_cell + Vector2i(3, 0)), "roundtrip: crop and fence are back")
	_check(gayle.mode == Gayle.Mode.STAY and _player.tool == Player.Tool.SWORD, "roundtrip: Gayle and the tool are back")
	Game.reset()
	herd.from_save({})
	orchard.from_save({})
	_farm.from_save({})
	fences.from_save({})
	gayle.mode = Gayle.Mode.FOLLOW
	_player.global_position = _start
