extends Node
## Multi-process test of the co-op lobby flow with real farm scenes (run as a scene, exit 1 on failure):
##   godot --headless --path . res://tests/coop_test.tscn
## The host process starts a relay and two joiner processes (same scene, --role=client), builds
## its own farm and checks that
##   - the joiners get the host's farm as a snapshot (gold, tilled soil) and never write a save file,
##   - everybody sees everybody else's farmer at the right place,
##   - a farmer disappears when its player leaves,
##   - a joiner is told when the host leaves.
## Joiner logs go to $TEMP/sh_sprint3/ and are printed when a joiner fails.

const HOST_SPOT := Vector2(640, 400)
const JOINER_SPOTS := {"Anna": Vector2(500, 520), "Ben": Vector2(760, 540)}
const TILLED_CELL := Vector2i(30, 30)
const GOLD := 123
const NEAR := 4.0  # px: how close a remote farmer must be to the real one
const WAIT := 20.0
const RELAY_START_TRIES := 40

var _failures := 0
var _checks := 0
var _port := 0
var _pids: Array[int] = []
var _main: Node


func _ready() -> void:
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


func _wait_until(condition: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func _farmer(id: int) -> Node2D:
	return _main.get_node_or_null("Entities/Remote%d" % id) as Node2D


func _farmer_at(id: int, spot: Vector2) -> bool:
	var farmer := _farmer(id)
	return farmer != null and farmer.position.distance_to(spot) < NEAR


func _spawn(godot_args: Array) -> int:
	var pid := OS.create_process(OS.get_executable_path(), PackedStringArray(godot_args))
	_pids.append(pid)
	return pid


func _project_args() -> Array:
	return ["--headless", "--path", ProjectSettings.globalize_path("res://")]


func _finish() -> void:
	for pid in _pids:
		OS.kill(pid)
	print("\n%d checks, %d failed" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _build_farm() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)


# --- joiner process ---

func _run_client(args: PackedStringArray) -> void:
	var code := ""
	var player_name := "Anna"
	for arg in args:
		if arg.begins_with("--code="):
			code = arg.trim_prefix("--code=")
		elif arg.begins_with("--name="):
			player_name = arg.trim_prefix("--name=")
	var leave_early := player_name == "Anna"
	SaveGame.path = "user://test_save_coop_%s.json" % player_name
	SaveGame.delete()
	Game.reset()
	var started := [false]
	Net.game_start.connect(func() -> void: started[0] = true)
	if not await Net.join(code, player_name):
		print("client %s: join failed" % player_name)
		get_tree().quit(2)
		return
	_check(await _wait_until(func() -> bool: return started[0], WAIT), "%s is told the farm is running" % player_name)
	_build_farm()
	var session := _main.get_node("CoopSession") as CoopSession
	var left_message := [""]
	session.leaving.connect(func(message: String) -> void: left_message[0] = message)
	_check(await _wait_until(session.has_farm, WAIT), "%s receives the host's farm" % player_name)

	var farm := _main.get_node("Farm") as Farm
	var player := _main.get_node("Entities/Player") as Player
	_check(Game.gold == GOLD, "the joiner has the host's gold")
	_check(farm.is_tilled(TILLED_CELL), "the joiner has the host's tilled soil")
	_check(not SaveGame.save() and not FileAccess.file_exists(SaveGame.path), "a joiner never writes a save file")
	player.global_position = JOINER_SPOTS[player_name]

	_check(await _wait_until(func() -> bool: return _farmer_at(1, HOST_SPOT), WAIT), "%s sees the host's farmer in place" % player_name)
	_check(_farmer(1).get_child_count() > 1, "the host's farmer has its sprite layers and name tag")
	if leave_early:
		await get_tree().create_timer(1.5).timeout  # let the host see us first
		Net.leave()
		_check(not Net.is_online(), "Anna left")
	else:
		var anna_id := 2
		_check(await _wait_until(func() -> bool: return _farmer(anna_id) != null, WAIT), "Ben sees Anna's farmer")
		_check(await _wait_until(func() -> bool: return _farmer(anna_id) == null, WAIT), "Anna's farmer is gone after she left")
		_check(await _wait_until(func() -> bool: return left_message[0] != "", WAIT), "Ben is told when the host leaves")
		_check(left_message[0] == "The host left", "the message says the host left")
	print("client %s done (%d checks, %d failed)" % [player_name, _checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# --- host process ---

func _run_host() -> void:
	await get_tree().process_frame
	if not await _start_relay():
		print("FAIL: relay did not start")
		_failures += 1
		_finish()
		return
	SaveGame.path = "user://test_save_coop_host.json"
	SaveGame.delete()
	Game.reset()
	Game.intro_seen = true
	Game.gold = GOLD
	Net.relay_url = "ws://127.0.0.1:%d" % _port
	var code := await Net.host("Hosty")
	_check(code.length() == 6, "the host opens a room")
	var joined: Array[int] = []
	Net.player_joined.connect(func(id: int, _name: String) -> void: joined.append(id))
	var log_dir := OS.get_environment("TEMP") + "/sh_sprint3"
	DirAccess.make_dir_recursive_absolute(log_dir)
	var client_args := _project_args() + ["res://tests/coop_test.tscn"]
	var logs: Dictionary = {}
	var pids: Dictionary = {}
	for player_name: String in ["Anna", "Ben"]:
		logs[player_name] = "%s/coop_%s.log" % [log_dir, player_name]
		pids[player_name] = _spawn(client_args + ["--log-file", logs[player_name], "--", "--role=client", "--relay=ws://127.0.0.1:%d" % _port, "--code=" + code, "--name=" + player_name])
		var expected := joined.size() + 1
		_check(await _wait_until(func() -> bool: return joined.size() == expected, WAIT), "%s joins the lobby" % player_name)
	_check(Net.players.size() == 3, "the lobby lists three players")

	_build_farm()
	var farm := _main.get_node("Farm") as Farm
	var player := _main.get_node("Entities/Player") as Player
	_check(farm.till(TILLED_CELL), "the host tills a cell before the joiners load")
	player.global_position = HOST_SPOT
	_check(Net.game_started, "the host announced the start")

	_check(await _wait_until(func() -> bool: return _farmer_at(2, JOINER_SPOTS["Anna"]), WAIT), "the host sees Anna's farmer in place")
	_check(await _wait_until(func() -> bool: return _farmer_at(3, JOINER_SPOTS["Ben"]), WAIT), "the host sees Ben's farmer in place")
	_check(await _wait_until(func() -> bool: return _farmer(2) == null, WAIT), "Anna's farmer is removed when she leaves")
	_check(_farmer(3) != null, "Ben's farmer stays")
	_check(await _wait_until(func() -> bool: return Net.players.size() == 2, 5.0), "the lobby drops Anna")

	Net.leave()
	for player_name: String in pids:
		var done := await _wait_until(func() -> bool: return not OS.is_process_running(pids[player_name]), 30.0)
		_check(done and OS.get_process_exit_code(pids[player_name]) == 0, "%s's process finished with every check passing" % player_name)
		if not done or OS.get_process_exit_code(pids[player_name]) != 0:
			print("--- %s log (tail) ---\n%s" % [player_name, _tail(logs[player_name])])
	_finish()


func _tail(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "(no log)"
	var lines := FileAccess.get_file_as_string(path).split("\n")
	return "\n".join(lines.slice(maxi(0, lines.size() - 25)))


func _start_relay() -> bool:
	for attempt in 5:
		_port = randi_range(20000, 40000)
		var pid := _spawn(_project_args() + ["--script", "res://server/relay.gd", "--", "--port=%d" % _port])
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
			if not OS.is_process_running(pid):
				break
		OS.kill(pid)
	return false
