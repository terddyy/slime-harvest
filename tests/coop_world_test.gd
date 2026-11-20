extends Node
## Multi-process test of the co-op world sync with real farm scenes (run as a scene, exit 1 on failure):
##   godot --headless --path . res://tests/coop_world_test.tscn
## The host process starts a relay and one joiner process (same scene, --role=client). They play a
## short game together and both check the same things. The joiner uses the real Player code
## (tools, harvesting, selling, buying, restoring, sword, bed), the host the world:
##   till -> water -> plant -> (host grows it) -> harvest -> sell -> buy a seed -> restore the well
##   -> build a fence -> (host breaks it) -> (host buys a chicken) -> kill a slime -> night -> bed.
## Requests a joiner must not be able to make (far away tool use, add_gold) are sent too and must do nothing.
## At the end both worlds write a signature (soil, crops, fences, gold, bags, day) and the host compares them.
## Joiner logs and signatures go to $TEMP/sh_sprint3/ and the log is printed when the joiner fails.

const JOINER_SPOT := Vector2(520, 520)  # cell (32, 32)
const HOST_SPOT := Vector2(640, 400)
const CELL_A := Vector2i(32, 33)  # below the joiner
const CELL_B := Vector2i(33, 32)  # right of the joiner
const FAR_CELL := Vector2i(70, 40)
const START_GOLD := 500
const WAIT := 20.0
const RELAY_START_TRIES := 40

var _failures := 0
var _checks := 0
var _port := 0
var _pids: Array[int] = []
var _main: Node
var _farm: Farm
var _fences: Fences
var _player: Player
var _world: CoopWorld
var _woke_text := ["", false]  # [text, did it happen]
var _log_dir := ""


func _ready() -> void:
	_log_dir = OS.get_environment("TEMP") + "/sh_sprint3"
	DirAccess.make_dir_recursive_absolute(_log_dir)
	var args := OS.get_cmdline_user_args()
	if "--role=client" in args:
		_run_client(args)
	else:
		_run_host()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("FAIL: " + label)


func _wait_until(condition: Callable, seconds: float = WAIT) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func _pause(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _spawn(godot_args: Array) -> int:
	var pid := OS.create_process(OS.get_executable_path(), PackedStringArray(godot_args))
	_pids.append(pid)
	return pid


func _project_args() -> Array:
	return ["--headless", "--path", ProjectSettings.globalize_path("res://")]


func _build_farm() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_farm = _main.get_node("Farm") as Farm
	_fences = _main.get("_fences") as Fences
	_player = _main.get_node("Entities/Player") as Player
	_world = _main.get_node("CoopWorld") as CoopWorld


## The things that must be the same in both worlds, as text.
func _signature() -> String:
	var soil: Array = []
	for entry: Array in _farm.to_save()["soil"]:
		soil.append("%d,%d,%d" % [entry[0], entry[1], entry[2]])
	soil.sort()
	var plants: Array = []
	for entry: Array in _farm.to_save()["crops"]:
		plants.append("%d,%d,%s,%d" % [entry[0], entry[1], entry[2]["id"], entry[2]["stage"]])
	plants.sort()
	var shared: Dictionary = Game.to_save()
	shared.erase("time_left")
	shared.erase("intro_seen")
	return JSON.stringify({"soil": soil, "crops": plants, "fences": _fences.to_save(), "game": shared}, "", true)


func _slime_puppets() -> Array:
	var found := []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is Slime and enemy.puppet:
			found.append(enemy)
	return found


func _finish() -> void:
	for pid in _pids:
		OS.kill(pid)
	print("\n%d checks, %d failed" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# --- joiner process ---

## Uses the tool on the tile next to the farmer the way a keypress does (Player decides what happens).
func _act(tool: Player.Tool, facing: Vector2, seconds := 0.6) -> void:
	_player.global_position = JOINER_SPOT
	_player.facing = facing
	_player.set_tool(tool)
	await _pause(0.1)
	_player._use_requested = true
	await _pause(seconds)


func _run_client(args: PackedStringArray) -> void:
	var code := ""
	for arg in args:
		if arg.begins_with("--code="):
			code = arg.trim_prefix("--code=")
	SaveGame.path = "user://test_save_coopworld_client.json"
	SaveGame.delete()
	Game.reset()
	var started := [false]
	Net.game_start.connect(func() -> void: started[0] = true)
	if not await Net.join(code, "Anna"):
		print("client: join failed")
		get_tree().quit(2)
		return
	await _wait_until(func() -> bool: return started[0])
	_build_farm()
	var session := _main.get_node("CoopSession") as CoopSession
	_check(await _wait_until(session.has_farm), "joiner: receives the host's farm")
	_player.global_position = JOINER_SPOT
	_check(Game.gold == START_GOLD, "joiner: has the host's gold")
	_check(Game.remote_call.is_valid() and not _farm.is_processing(), "joiner: purchases are requests and the farm does not grow by itself")
	_world.woke.connect(func(text: String) -> void: _woke_text = [text, true])
	var waiting := [-1]
	_world.sleep_waiting.connect(func(missing: int) -> void: waiting[0] = missing)

	# Things a joiner must not be able to do.
	_world.send_tool(Player.Tool.HOE, FAR_CELL, false, Vector2.DOWN, "carrot", "")
	_world._game_call.rpc_id(Net.HOST_ID, "add_gold", [999])
	_world._game_call.rpc_id(Net.HOST_ID, "buy_seed", ["nope"])

	await _act(Player.Tool.HOE, Vector2.DOWN)
	_check(await _wait_until(func() -> bool: return _farm.is_tilled(CELL_A)), "joiner: the hoe tilled the soil (it came back from the host)")
	await _act(Player.Tool.WATER, Vector2.DOWN)
	_check(await _wait_until(func() -> bool: return _farm.is_wet(CELL_A)), "joiner: the can wet the soil")
	await _act(Player.Tool.SEEDS, Vector2.DOWN)
	_check(await _wait_until(func() -> bool: return _farm.get_crop(CELL_A) != null), "joiner: the seed is planted")
	_check(await _wait_until(func() -> bool: return Game.seed_count("carrot") == 5), "joiner: one carrot seed was used up (shared bag)")
	_check(await _wait_until(func() -> bool: return _farm.get_crop(CELL_A) != null and _farm.get_crop(CELL_A).is_ripe()), "joiner: sees the crop the host grew")

	await _act(Player.Tool.HOE, Vector2.DOWN)  # a farming tool on a ripe crop harvests it
	_check(await _wait_until(func() -> bool: return _farm.get_crop(CELL_A) == null and Game.crop_count("carrot") == 1), "joiner: harvested the carrot")
	Game.sell_crops()
	_check(await _wait_until(func() -> bool: return Game.gold == START_GOLD + 15 and Game.crop_count("carrot") == 0), "joiner: sold the carrot for gold")
	Game.buy_seed("radish")
	_check(await _wait_until(func() -> bool: return Game.seed_count("radish") == 1 and Game.gold == START_GOLD + 12), "joiner: bought a radish seed")
	Game.restore("well")
	_check(await _wait_until(func() -> bool: return Game.is_restored("well") and Game.gold == START_GOLD - 138), "joiner: restored the well")
	var building := (_main.get("_buildings") as Buildings).get_building("well")
	_check(await _wait_until(func() -> bool: return building.restored), "joiner: the well is drawn as restored")

	await _act(Player.Tool.FENCE, Vector2.RIGHT)
	_check(await _wait_until(func() -> bool: return _fences.has_fence(CELL_B) and Game.fence_pieces == 2), "joiner: built a fence")
	_check(await _wait_until(func() -> bool: return not _fences.has_fence(CELL_B)), "joiner: sees the host's slimes break the fence")

	var herd := _main.get("_herd") as Herd
	_check(await _wait_until(func() -> bool: return herd.animals().size() == 1 and herd.animals()[0].puppet), "joiner: sees the host's chicken")
	_check(await _wait_until(func() -> bool: return _slime_puppets().size() == 1), "joiner: sees the host's slime as a copy")
	await _act(Player.Tool.SWORD, Vector2.RIGHT, 0.9)
	_check(await _wait_until(func() -> bool: return Game.gold == START_GOLD - 138 - 40 + 1), "joiner: the sword killed the host's slime and the gold is shared")
	_check(await _wait_until(func() -> bool: return _slime_puppets().is_empty()), "joiner: the slime copy is gone")
	var gayle := _main.get("_gayle") as Gayle
	_check(gayle.puppet and await _wait_until(func() -> bool: return gayle.global_position.distance_to(HOST_SPOT) < 60.0, 15.0), "joiner: Gayle is a copy that walks with the host")

	Game.set_ui_open(true)
	_check(not get_tree().paused and Game.ui_open, "joiner: a menu does not pause the world online")
	Game.set_ui_open(false)

	_check(await _wait_until(func() -> bool: return Game.is_night), "joiner: the host's night comes to the joiner's clock")
	_world.set_sleeping(true)
	_check(await _wait_until(func() -> bool: return waiting[0] == 1), "joiner: told to wait for 1 more")
	_check(await _wait_until(func() -> bool: return _woke_text[1]), "joiner: everybody in bed, the morning comes")
	_check(Game.day == 2 and not Game.is_night, "joiner: it is day 2")
	_check(str(_woke_text[0]).begins_with("Day 2"), "joiner: gets the morning text")

	await _pause(1.5)
	FileAccess.open(_log_dir + "/coop_world_joiner.sig", FileAccess.WRITE).store_string(_signature())
	print("client done (%d checks, %d failed)" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# --- host process ---

func _run_host() -> void:
	await get_tree().process_frame
	if not await _start_relay():
		print("FAIL: relay did not start")
		_failures += 1
		_finish()
		return
	SaveGame.path = "user://test_save_coopworld_host.json"
	SaveGame.delete()
	Game.reset()
	Game.intro_seen = true
	Game.gold = START_GOLD
	Net.relay_url = "ws://127.0.0.1:%d" % _port
	var code := await Net.host("Hosty")
	_check(code.length() == 6, "host: opens a room")
	var joined: Array[int] = []
	Net.player_joined.connect(func(id: int, _name: String) -> void: joined.append(id))
	var log_path := _log_dir + "/coop_world_client.log"
	var pid := _spawn(_project_args() + ["res://tests/coop_world_test.tscn", "--log-file", log_path, "--", "--role=client", "--relay=ws://127.0.0.1:%d" % _port, "--code=" + code])
	_check(await _wait_until(func() -> bool: return joined.size() == 1), "host: the joiner arrives in the lobby")
	_build_farm()
	_player.global_position = HOST_SPOT
	var coop := _main.get_node("CoopSession") as CoopSession
	_world.woke.connect(func(text: String) -> void: _woke_text = [text, true])
	_check(await _wait_until(func() -> bool: return coop.farmer_position(2).distance_to(JOINER_SPOT) < 4.0), "host: sees the joiner's farmer in place")

	_check(await _wait_until(func() -> bool: return _farm.is_tilled(CELL_A)), "host: the joiner's hoe tilled the soil")
	_check(await _wait_until(func() -> bool: return _farm.is_wet(CELL_A)), "host: the joiner's can wet the soil")
	_check(await _wait_until(func() -> bool: return _farm.get_crop(CELL_A) != null), "host: the joiner planted a seed")
	_check(Game.seed_count("carrot") == 5, "host: the seed came out of the shared bag")
	for i in 3:  # the crop grows on the host only (the joiner's farm does not tick)
		_farm.water(CELL_A)
		_farm.grow_all()
	_check(_farm.get_crop(CELL_A).is_ripe(), "host: the carrot is ripe")
	_check(await _wait_until(func() -> bool: return _farm.get_crop(CELL_A) == null and Game.crop_count("carrot") == 1), "host: the joiner harvested it")
	_check(await _wait_until(func() -> bool: return Game.gold == START_GOLD + 15 and Game.crop_count("carrot") == 0), "host: the joiner sold the bag")
	_check(await _wait_until(func() -> bool: return Game.seed_count("radish") == 1 and Game.gold == START_GOLD + 12), "host: the joiner bought a seed")
	_check(await _wait_until(func() -> bool: return Game.is_restored("well") and Game.gold == START_GOLD - 138), "host: the joiner restored the well")
	_check(await _wait_until(func() -> bool: return _fences.has_fence(CELL_B)), "host: the joiner built a fence")
	await _pause(1.0)  # long enough for the joiner to see it
	_check(_fences.damage(CELL_B, 99) and not _fences.has_fence(CELL_B), "host: the fence breaks")
	Game.restored["chicken_coop"] = true
	_check(Game.buy_animal("chicken"), "host: buys a chicken")

	var spawner := _main.get("_spawner") as Spawner
	var slime := spawner.spawn("small", coop.farmer_position(2) + Vector2(14, 0))
	_check(await _wait_until(func() -> bool: return get_tree().get_nodes_in_group("enemies").is_empty() and Game.gold == START_GOLD - 138 - 40 + 1), "host: the joiner's sword killed the slime")
	_check(not is_instance_valid(slime) or not slime.is_in_group("enemies"), "host: the slime is dead")

	Game.set_ui_open(true)
	_check(not get_tree().paused, "host: a menu does not pause the world online")
	Game.set_ui_open(false)

	Game.time_left = 0.2  # dusk
	_check(await _wait_until(func() -> bool: return Game.is_night), "host: night falls")
	_check(await _wait_until(func() -> bool: return _world._asleep.has(2)), "host: the joiner is in bed")
	await _pause(1.5)
	_check(Game.day == 1 and Game.is_night, "host: one player in bed does not skip the night")
	_world.set_sleeping(true)
	_check(_woke_text[1] and Game.day == 2 and not Game.is_night, "host: everybody in bed, it is day 2")
	_check(str(_woke_text[0]).begins_with("Day 2"), "host: gets the morning text")

	_check(not _farm.is_tilled(FAR_CELL) and Game.gold == START_GOLD - 138 - 40 + 1, "host: a far tool use and add_gold from a joiner did nothing")
	await _pause(1.5)
	var host_signature := _signature()
	var done := await _wait_until(func() -> bool: return not OS.is_process_running(pid), 30.0)
	_check(done and OS.get_process_exit_code(pid) == 0, "joiner process finished with every check passing")
	if not done or OS.get_process_exit_code(pid) != 0:
		print("--- joiner log (tail) ---\n%s" % _tail(log_path))
	var joiner_signature := FileAccess.get_file_as_string(_log_dir + "/coop_world_joiner.sig")
	_check(joiner_signature != "" and joiner_signature == host_signature, "both worlds are identical (soil, crops, fences, gold, bags, buildings)")
	if joiner_signature != host_signature:
		print("host:   " + host_signature + "\njoiner: " + joiner_signature)
	Net.leave()
	_finish()


func _tail(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "(no log)"
	var lines := FileAccess.get_file_as_string(path).split("\n")
	return "\n".join(lines.slice(maxi(0, lines.size() - 30)))


func _start_relay() -> bool:
	for attempt in 5:
		_port = randi_range(20000, 40000)
		var relay_pid := _spawn(_project_args() + ["--script", "res://server/relay.gd", "--", "--port=%d" % _port])
		for i in RELAY_START_TRIES:
			await get_tree().create_timer(0.25).timeout
			var socket := WebSocketPeer.new()
			socket.connect_to_url("ws://127.0.0.1:%d" % _port)
			var end := Time.get_ticks_msec() + 500
			while Time.get_ticks_msec() < end and socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
				socket.poll()
				await get_tree().process_frame
			var up := socket.get_ready_state() == WebSocketPeer.STATE_OPEN
			socket.close()
			if up:
				return true
			if not OS.is_process_running(relay_pid):
				break
		OS.kill(relay_pid)
	return false
