extends Node
## Co-op edge cases (run as a scene, exit 1 on failure):
##   godot --headless --path . res://tests/coop_edge_test.tscn
## The host process starts a relay, checks the lobby messages (relay down, wrong code), then plays alone:
## it is NIGHT, a slime is out, the host stands in the farmhouse room and is already in bed.
## Only then a joiner process arrives. The joiner must get the farm, the night clock, the slime,
## must not see the host's farmer (indoors), must be told to wait for 1 more, and its bed brings the morning.
## Joiner logs go to $TEMP/sh_sprint3/ and the log is printed when the joiner fails.

const HOST_SPOT := Vector2(640, 400)
const JOINER_SPOT := Vector2(520, 520)
const START_GOLD := 321
const WAIT := 20.0
const RELAY_START_TRIES := 40

var _failures := 0
var _checks := 0
var _port := 0
var _pids: Array[int] = []
var _main: Node
var _player: Player
var _world: CoopWorld
var _log_dir := ""


func _ready() -> void:
	_log_dir = OS.get_environment("TEMP") + "/sh_sprint3"
	DirAccess.make_dir_recursive_absolute(_log_dir)
	if "--role=client" in OS.get_cmdline_user_args():
		_run_client(OS.get_cmdline_user_args())
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
	_player = _main.get_node("Entities/Player") as Player
	_world = _main.get_node("CoopWorld") as CoopWorld


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


# --- joiner process (arrives in the middle of the night) ---

func _run_client(args: PackedStringArray) -> void:
	var code := ""
	for arg in args:
		if arg.begins_with("--code="):
			code = arg.trim_prefix("--code=")
	SaveGame.path = "user://test_save_coopedge_client.json"
	SaveGame.delete()
	Game.reset()
	var started := [false]
	Net.game_start.connect(func() -> void: started[0] = true)
	if not await Net.join(code, "Late"):
		print("client: join failed")
		get_tree().quit(2)
		return
	await _wait_until(func() -> bool: return started[0])
	_build_farm()
	var session := _main.get_node("CoopSession") as CoopSession
	_check(await _wait_until(session.has_farm), "joiner: receives the farm in the middle of the night")
	_player.global_position = JOINER_SPOT
	_check(Game.gold == START_GOLD, "joiner: has the host's gold")
	_check(await _wait_until(func() -> bool: return Game.is_night and Game.day == 3), "joiner: it is night on day 3 like on the host")
	_check(await _wait_until(func() -> bool: return not _slime_puppets().is_empty()), "joiner: sees the slimes that were already out")
	var host_farmer := _main.get_node("Entities/Remote1") as RemoteFarmer
	_check(await _wait_until(func() -> bool: return host_farmer.global_position.x > 3900.0), "joiner: the host's farmer is in the farmhouse room")
	await _pause(0.3)
	_check(not host_farmer.visible, "joiner: the farmer indoors is out of sight")

	var waiting := [-1]
	var woke := ["", false]
	_world.sleep_waiting.connect(func(missing: int) -> void: waiting[0] = missing)
	_world.woke.connect(func(text: String) -> void:
		woke[0] = text
		woke[1] = true)
	_world.set_sleeping(true)
	_check(await _wait_until(func() -> bool: return waiting[0] == 1), "joiner: in bed, told to wait for the host")
	_check(await _wait_until(func() -> bool: return woke[1]), "joiner: both in bed, the morning comes")
	_check(Game.day == 4 and not Game.is_night, "joiner: it is day 4")
	_check(await _wait_until(func() -> bool: return host_farmer.global_position.distance_to(HOST_SPOT) < 40.0), "joiner: the host's farmer walked out of the house")
	await _pause(0.3)
	_check(host_farmer.visible, "joiner: the farmer outside is visible again")
	print("client done (%d checks, %d failed)" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# --- host process ---

func _lobby_messages() -> void:
	var lobby := Lobby.new()
	add_child(lobby)
	lobby.open()
	Net.relay_url = "ws://127.0.0.1:1"
	lobby._name_field.text = "Hosty"
	await lobby._host_room()
	_check(lobby._start_message.text == Net.REASONS["unreachable"] and lobby._start_page.visible, "lobby: relay down shows the friendly message on the first page")
	Net.relay_url = "ws://127.0.0.1:%d" % _port
	lobby._show_join_page()
	lobby._code_field.text = "ABC"
	await lobby._join_room()
	_check(lobby._join_message.text == Net.REASONS["bad_code"], "lobby: a short code is refused")
	lobby._code_field.text = "ZZZZZZ"
	await lobby._join_room()
	_check(lobby._join_message.text == Net.REASONS["no_room"] and not lobby._go_button.disabled, "lobby: a wrong code says so and the button works again")
	lobby.close()
	lobby.queue_free()


func _run_host() -> void:
	await get_tree().process_frame
	if not await _start_relay():
		print("FAIL: relay did not start")
		_failures += 1
		_finish()
		return
	SaveGame.path = "user://test_save_coopedge_host.json"
	SaveGame.delete()
	Game.reset()
	Game.intro_seen = true
	Net.relay_url = "ws://127.0.0.1:%d" % _port
	await _lobby_messages()

	Game.gold = START_GOLD
	Game.day = 3
	var code := await Net.host("Hosty")
	_check(code.length() == 6, "host: opens a room")
	_build_farm()
	_player.global_position = HOST_SPOT
	var coop := _main.get_node("CoopSession") as CoopSession
	var spawner := _main.get("_spawner") as Spawner
	Game.time_left = 0.1
	_check(await _wait_until(func() -> bool: return Game.is_night), "host: night falls")
	await _pause(0.5)
	spawner.spawn("small", HOST_SPOT + Vector2(200, 0))
	_player.walk_bounds = Rect2(Farmhouse.WALK_RECT.position + Farmhouse.ROOM_ORIGIN, Farmhouse.WALK_RECT.size)  # as inside the house
	_player.global_position = Farmhouse.ROOM_ORIGIN + Farmhouse.INSIDE_DOOR + Vector2(0, -6)
	var log_path := _log_dir + "/coop_edge_client.log"
	var pid := _spawn(_project_args() + ["res://tests/coop_edge_test.tscn", "--log-file", log_path, "--", "--role=client", "--relay=ws://127.0.0.1:%d" % _port, "--code=" + code])
	_check(await _wait_until(func() -> bool: return coop.farmer_position(2).distance_to(JOINER_SPOT) < 4.0), "host: the late joiner is in place")
	var joiner_farmer := _main.get_node("Entities/Remote2") as RemoteFarmer
	_check(joiner_farmer.visible == false, "host: the joiner outside is out of sight while the host is indoors")
	Game.time_left = 20.0  # still night, so bed is allowed
	var woke := ["", false]
	_world.woke.connect(func(text: String) -> void:
		woke[0] = text
		woke[1] = true)
	_check(await _wait_until(func() -> bool: return _world._asleep.has(2)), "host: the joiner is in bed")
	_check(Game.day == 3, "host: one player in bed does not skip the night")
	_world.set_sleeping(true)
	_check(woke[1] and Game.day == 4 and not Game.is_night, "host: both in bed, it is day 4")
	_player.walk_bounds = Rect2()
	_player.global_position = HOST_SPOT  # walks out of the house
	var done := await _wait_until(func() -> bool: return not OS.is_process_running(pid), 30.0)
	_check(done and OS.get_process_exit_code(pid) == 0, "joiner process finished with every check passing")
	if not done or OS.get_process_exit_code(pid) != 0:
		print("--- joiner log (tail) ---\n%s" % _tail(log_path))
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
