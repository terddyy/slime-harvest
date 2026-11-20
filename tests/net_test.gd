extends Node
## Multi-process test of the relay, RelayPeer and Net. Run it as a scene (exit 1 on failure):
##   godot --headless --path . res://tests/net_test.tscn
## The same scene runs two ways:
##   (no args)       the host: starts the relay and two joiner processes, checks everything
##   --role=client   a joiner process: joins, answers a ping, then leaves (--leave) or waits for the host to go
## Scripts run with --script can't use the Net autoload, which is why this is a scene.

const RELAY_START_TRIES := 40

var _failures := 0
var _checks := 0
var _port := 0
var _pids: Array[int] = []
var _probe: Node


class RawClient:
	## A bare WebSocket speaking the relay's text protocol, to test it without RelayPeer.
	var socket := WebSocketPeer.new()
	var messages: Array[Dictionary] = []
	var binaries: Array[PackedByteArray] = []  # game packets
	var hello_sent := false
	var hello := ""

	func _init(url: String, hello_message: Dictionary) -> void:
		hello = JSON.stringify(hello_message)
		socket.connect_to_url(url)

	func poll() -> void:
		socket.poll()
		if socket.get_ready_state() == WebSocketPeer.STATE_OPEN and not hello_sent:
			hello_sent = true
			socket.send_text(hello)
		while socket.get_available_packet_count() > 0:
			var packet := socket.get_packet()
			if socket.was_string_packet():
				messages.append(JSON.parse_string(packet.get_string_from_utf8()))
			else:
				binaries.append(packet)


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


func _finish(extra_failure := false) -> void:
	for pid in _pids:
		OS.kill(pid)
	print("\n%d checks, %d failed" % [_checks, _failures + (1 if extra_failure else 0)])
	get_tree().quit(1 if _failures > 0 or extra_failure else 0)


func _add_probe() -> void:
	_probe = load("res://tests/net_probe.gd").new()
	_probe.name = "NetProbe"
	get_tree().root.add_child.call_deferred(_probe)


func _wait_until(condition: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func _spawn(godot_args: Array) -> int:
	var pid := OS.create_process(OS.get_executable_path(), PackedStringArray(godot_args))
	_pids.append(pid)
	return pid


func _project_args() -> Array:
	return ["--headless", "--path", ProjectSettings.globalize_path("res://")]


# --- joiner process ---

func _run_client(args: PackedStringArray) -> void:
	var code := ""
	var player_name := "Joiner"
	var leave_early := "--leave" in args
	for arg in args:
		if arg.begins_with("--code="):
			code = arg.trim_prefix("--code=")
		elif arg.begins_with("--name="):
			player_name = arg.trim_prefix("--name=")
	_add_probe()
	await get_tree().process_frame
	await get_tree().process_frame
	var answered := [false]
	_probe.ping_received.connect(func(_from: int, _value: int) -> void: answered[0] = true)
	var host_gone := [false]
	Net.host_left.connect(func() -> void: host_gone[0] = true)
	if not await Net.join(code, player_name):
		print("client %s: join failed" % player_name)
		get_tree().quit(2)
		return
	_check(not Net.is_host() and Net.is_online() and Net.my_id() >= 2, "client has a joiner id")
	_check(Net.players.get(1) == "Hosty", "client learns the host's name")
	if not await _wait_until(func() -> bool: return answered[0], 10.0):
		print("client %s: no ping" % player_name)
		get_tree().quit(3)
		return
	if leave_early:
		await get_tree().create_timer(0.3).timeout  # let the pong reach the host
		Net.leave()
		_check(not Net.is_online(), "client left")
		get_tree().quit(1 if _failures > 0 else 0)
		return
	var host_left_ok := await _wait_until(func() -> bool: return host_gone[0], 15.0)
	_check(host_left_ok, "client sees host_left")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not Net.is_online(), "client is offline after the host left")
	print("client %s done (%d checks, %d failed)" % [player_name, _checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# --- host process ---

func _run_host() -> void:
	_add_probe()
	await get_tree().process_frame
	await get_tree().process_frame
	if not await _start_relay():
		print("FAIL: relay did not start")
		_finish(true)
		return
	var url := "ws://127.0.0.1:%d" % _port
	Net.relay_url = url
	await _test_raw_protocol(url)
	await _test_net_round_trip()
	_finish()


func _start_relay() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):  # debugging: use a relay you started yourself
			_port = int(arg.trim_prefix("--port="))
			return true
	for attempt in 5:
		_port = randi_range(20000, 40000)
		var relay_args := _project_args() + ["--script", "res://server/relay.gd", "--", "--port=%d" % _port]
		var pid := _spawn(relay_args)
		for i in RELAY_START_TRIES:
			await get_tree().create_timer(0.25).timeout
			var probe := RawClient.new("ws://127.0.0.1:%d" % _port, {"t": "join", "code": "BADCOD"})
			var got := await _wait_until(func() -> bool:
				probe.poll()
				return not probe.messages.is_empty(), 0.5)
			if got:
				return true
			if not OS.is_process_running(pid):
				break
		OS.kill(pid)
	return false


func _raw_reply(client: RawClient) -> Dictionary:
	var got := await _wait_until(func() -> bool:
		client.poll()
		return not client.messages.is_empty(), 5.0)
	return client.messages.pop_front() if got else {}


func _has_message(client: RawClient, kind: String, id := -1) -> bool:
	client.poll()
	for message in client.messages:
		if message.get("t") == kind and (id < 0 or message.get("id") == id):
			return true
	return false


func _test_raw_protocol(url: String) -> void:
	var host := RawClient.new(url, {"t": "create", "name": "Raw Host"})
	var created := await _raw_reply(host)
	var code: String = created.get("code", "")
	_check(created.get("t") == "created" and code.length() == 6 and created.get("id") == 1, "relay creates a room, host is 1")
	_check(RelayPeer.clean_code(code) == code, "room code uses only the allowed characters")

	var joiners: Array[RawClient] = []
	for number in 3:
		var joiner := RawClient.new(url, {"t": "join", "code": code.to_lower(), "name": "J%d" % number})
		var reply := await _raw_reply(joiner)
		_check(reply.get("t") == "joined" and reply.get("id") == number + 2, "joiner %d gets id %d" % [number, number + 2])
		_check(reply.get("peers", []).size() == number + 1, "joiner %d is told who is in the room" % number)
		joiners.append(joiner)
	_check(await _wait_until(func() -> bool: return _has_message(host, "peer_joined", 2), 3.0), "the host is told about a new player")

	var fifth := RawClient.new(url, {"t": "join", "code": code, "name": "Late"})
	_check((await _raw_reply(fifth)).get("reason") == "full", "a fifth player is refused (room full)")
	var wrong := RawClient.new(url, {"t": "join", "code": "ZZZZZZ", "name": "X"})
	_check((await _raw_reply(wrong)).get("reason") == "no_room", "an unknown code is refused")
	var short := RawClient.new(url, {"t": "join", "code": "AB", "name": "X"})
	_check((await _raw_reply(short)).get("reason") == "bad_code", "a malformed code is refused")
	var nonsense := RawClient.new(url, {"t": "dance"})
	_check((await _raw_reply(nonsense)).get("reason") == "bad_hello", "an unknown hello is refused")

	# Packets: joiner 2 -> everybody else (target 0), then host -> joiner 3 only (target 3).
	joiners[0].socket.send(PackedByteArray([0, 0, 0, 0, 7, 8, 9]))
	_check(await _wait_until(func() -> bool:
		host.poll()
		return not host.binaries.is_empty(), 3.0), "broadcast packet reaches the host")
	var received: PackedByteArray = host.binaries[0] if not host.binaries.is_empty() else PackedByteArray()
	_check(received.size() == 7 and received.decode_s32(0) == 2 and received[4] == 7, "broadcast packet arrives with the sender id")
	_check(await _wait_until(func() -> bool:
		joiners[1].poll()
		return joiners[1].binaries.size() == 1, 3.0), "broadcast packet reaches the other joiners")
	host.socket.send(PackedByteArray([3, 0, 0, 0, 42]))
	_check(await _wait_until(func() -> bool:
		joiners[1].poll()
		return joiners[1].binaries.size() == 2, 3.0), "a packet to player 3 arrives at player 3")
	await get_tree().create_timer(0.3).timeout
	joiners[0].poll()
	_check(joiners[0].binaries.is_empty(), "a packet to player 3 does not reach player 2")

	# A joiner leaving is announced; the host leaving tells the joiners and closes the room.
	joiners[2].socket.close()
	_check(await _wait_until(func() -> bool: return _has_message(host, "peer_left", 4), 3.0), "the host is told a player left")
	host.socket.close()
	_check(await _wait_until(func() -> bool:
		host.poll()  # keeps the close handshake going
		return _has_message(joiners[0], "host_left"), 3.0), "joiners are told the host left")
	var reopened := RawClient.new(url, {"t": "join", "code": code, "name": "X"})
	_check((await _raw_reply(reopened)).get("reason") == "no_room", "the room is gone after the host leaves")
	for client in joiners:
		client.socket.close()


func _test_net_round_trip() -> void:
	var code := await Net.host("Hosty")
	_check(code.length() == 6 and Net.is_host() and Net.is_online(), "Net.host returns a room code")
	_check(Net.players == {1: "Hosty"}, "the host starts alone")
	var joined_ids: Array[int] = []
	var left_ids: Array[int] = []
	Net.player_joined.connect(func(id: int, _n: String) -> void: joined_ids.append(id))
	Net.player_left.connect(func(id: int) -> void: left_ids.append(id))
	var pongs := {}
	_probe.pong_received.connect(func(from: int, value: int) -> void: pongs[from] = value)

	var client_args := _project_args() + ["res://tests/net_test.tscn", "--", "--role=client", "--relay=ws://127.0.0.1:%d" % _port, "--code=" + code]
	var stayer := _spawn(client_args + ["--name=Stayer"])
	var leaver := _spawn(client_args + ["--name=Leaver", "--leave"])
	_check(await _wait_until(func() -> bool: return joined_ids.size() == 2, 30.0), "two joiners arrive (player_joined x2)")
	_check(Net.players.size() == 3, "Net.players lists all three")
	_check(Net.player_name(joined_ids[0]) in ["Stayer", "Leaver"], "player names come through")

	_probe.ping.rpc(21)
	_check(await _wait_until(func() -> bool: return pongs.size() == 2, 10.0), "both joiners answer the host's RPC")
	_check(pongs.values().all(func(v: int) -> bool: return v == 42), "the RPC arguments make the round trip")

	_check(await _wait_until(func() -> bool: return left_ids.size() == 1, 10.0), "player_left fires when a joiner disconnects")
	_check(Net.players.size() == 2, "Net.players drops the player who left")
	_check(await _wait_until(func() -> bool: return not OS.is_process_running(leaver), 5.0), "the leaving client exits")

	Net.leave()
	_check(not Net.is_online() and Net.players.is_empty(), "Net.leave goes offline")
	var stayer_done := await _wait_until(func() -> bool: return not OS.is_process_running(stayer), 15.0)
	_check(stayer_done, "the staying client noticed host_left and exited")
	if stayer_done:
		_check(OS.get_process_exit_code(stayer) == 0, "the staying client exited cleanly")

	# Errors through Net: an unknown code, a bad code, an unreachable relay.
	var reasons: Array[String] = []
	Net.failed.connect(func(reason: String) -> void: reasons.append(reason))
	_check(not await Net.join("ZZZZZZ", "X"), "joining an unknown room fails")
	_check(not reasons.is_empty() and reasons.back() == Net.REASONS["no_room"], "failed carries the friendly text")
	await get_tree().process_frame
	_check(not Net.is_online(), "a failed join leaves Net offline")
	_check(not await Net.join("nope", "X"), "a malformed code fails before connecting")
	Net.relay_url = "ws://127.0.0.1:1"
	_check(await Net.host("X") == "", "an unreachable relay fails")
	_check(reasons.back() == Net.REASONS["unreachable"], "unreachable relay gives the friendly text")
