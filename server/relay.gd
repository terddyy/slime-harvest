extends SceneTree
## Room relay for online co-op. Standalone: it does not use any other game script.
## Run it with:
##   godot --headless --script res://server/relay.gd -- --port=9080
## Options after "--": --port=N (default 9080), --bind=ADDRESS (default 127.0.0.1, nginx sits in front).
##
## What it does: players connect with a WebSocket. The first message (text, JSON) is
##   {"t":"create","name":"..."}            -> {"t":"created","code":"K7M2QX","id":1}
##   {"t":"join","code":"...","name":"..."} -> {"t":"joined","code":"...","id":2,"peers":[{"id":1,"name":".."}]}
##                                             or {"t":"error","reason":"no_room"|"full"|"bad_code"|"bad_hello"}
## Then the relay tells the room {"t":"peer_joined","id":2,"name":".."} and {"t":"peer_left","id":2}.
## When the host leaves, joiners get {"t":"host_left"} and the room is closed.
## Game packets are binary: the sender writes [target:int32][payload]. The relay sends
## [from:int32][payload] to the target. target 0 = everybody else, > 0 = that player,
## < 0 = everybody except that player (and the sender).
## The host is always player 1, joiners get 2, 3, ...

const DEFAULT_PORT := 9080
const MAX_PLAYERS := 4  # per room, the host included
const MAX_ROOMS := 200
const MAX_CONNECTIONS := 600
const CODE_LENGTH := 6
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # keep in sync with RelayPeer.CODE_CHARS
const MAX_NAME_LENGTH := 16
const BUFFER_SIZE := 1 << 21  # a world snapshot is bigger than WebSocketPeer's 64 KB default
const HELLO_TIMEOUT_MS := 10000  # a connection must say what it wants within this time
const REFUSED_LINGER_MS := 1000  # a refused client (or one whose host left) gets this long to read the message before we close
const MAX_FPS := 120

class Client:
	var socket := WebSocketPeer.new()
	var connected_ms := 0
	var room := ""  # room code once the hello was accepted
	var refused_ms := 0  # when we sent it an error (0 = not refused)
	var id := 0
	var player_name := ""


class Room:
	var clients := {}  # id -> Client
	var next_id := 2


var _tcp := TCPServer.new()
var _clients: Array[Client] = []
var _rooms := {}  # code -> Room
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.randomize()
	Engine.max_fps = MAX_FPS  # headless would otherwise spin a whole CPU core
	var port := DEFAULT_PORT
	var bind := "127.0.0.1"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--bind="):
			bind = arg.trim_prefix("--bind=")
	var error := _tcp.listen(port, bind)
	if error != OK:
		printerr("relay: cannot listen on %s:%d (error %d)" % [bind, port, error])
		quit(1)
		return
	print("relay: listening on %s:%d" % [bind, port])


func _process(_delta: float) -> bool:
	_accept_new_connections()
	for client in _clients.duplicate():
		_poll_client(client)
	return false


func _accept_new_connections() -> void:
	while _tcp.is_connection_available():
		var stream := _tcp.take_connection()
		if _clients.size() >= MAX_CONNECTIONS:
			stream.disconnect_from_host()
			continue
		var client := Client.new()
		client.socket.inbound_buffer_size = BUFFER_SIZE
		client.socket.outbound_buffer_size = BUFFER_SIZE
		client.socket.accept_stream(stream)
		client.connected_ms = Time.get_ticks_msec()
		_clients.append(client)


func _poll_client(client: Client) -> void:
	client.socket.poll()
	var state := client.socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while client.socket.get_available_packet_count() > 0:
			var packet := client.socket.get_packet()
			if client.socket.was_string_packet():
				_on_text(client, packet.get_string_from_utf8())
			else:
				_on_binary(client, packet)
			if client.socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
				break
		var now := Time.get_ticks_msec()
		if client.room == "" and client.refused_ms == 0 and now - client.connected_ms > HELLO_TIMEOUT_MS:
			client.socket.close(1008, "no hello")
		elif client.refused_ms > 0 and now - client.refused_ms > REFUSED_LINGER_MS:
			client.socket.close(1000, "refused")
	elif state == WebSocketPeer.STATE_CLOSED:
		_remove_client(client)


func _on_text(client: Client, text: String) -> void:
	if client.room != "" or client.refused_ms > 0:
		return  # after the hello only binary game packets are expected
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		_refuse(client, "bad_hello")
		return
	var hello: Dictionary = parsed
	var player_name := _clean_name(str(hello.get("name", "")))
	match str(hello.get("t", "")):
		"create":
			_create_room(client, player_name)
		"join":
			_join_room(client, str(hello.get("code", "")).strip_edges().to_upper(), player_name)
		_:
			_refuse(client, "bad_hello")


func _create_room(client: Client, player_name: String) -> void:
	if _rooms.size() >= MAX_ROOMS:
		_refuse(client, "full")
		return
	var code := _new_code()
	var room := Room.new()
	client.room = code
	client.id = 1
	client.player_name = player_name
	room.clients[1] = client
	_rooms[code] = room
	_send_json(client, {"t": "created", "code": code, "id": 1})
	print("relay: room %s created by %s (%d rooms)" % [code, player_name, _rooms.size()])


func _join_room(client: Client, code: String, player_name: String) -> void:
	if code.length() != CODE_LENGTH:
		_refuse(client, "bad_code")
		return
	if not _rooms.has(code):
		_refuse(client, "no_room")
		return
	var room: Room = _rooms[code]
	if room.clients.size() >= MAX_PLAYERS:
		_refuse(client, "full")
		return
	var peers: Array = []
	for other: Client in room.clients.values():
		peers.append({"id": other.id, "name": other.player_name})
	client.room = code
	client.id = room.next_id
	client.player_name = player_name
	room.next_id += 1
	room.clients[client.id] = client
	_send_json(client, {"t": "joined", "code": code, "id": client.id, "peers": peers})
	for other: Client in room.clients.values():
		if other != client:
			_send_json(other, {"t": "peer_joined", "id": client.id, "name": player_name})
	print("relay: %s joined room %s as player %d" % [player_name, code, client.id])


func _on_binary(client: Client, packet: PackedByteArray) -> void:
	if client.room == "" or packet.size() < 4 or not _rooms.has(client.room):
		return
	var target := packet.decode_s32(0)
	var out := PackedByteArray()
	out.resize(4)
	out.encode_s32(0, client.id)
	out.append_array(packet.slice(4))
	var room: Room = _rooms[client.room]
	if target > 0:
		if room.clients.has(target):
			room.clients[target].socket.send(out)
		return
	for other: Client in room.clients.values():
		if other != client and other.id != -target:
			other.socket.send(out)


func _remove_client(client: Client) -> void:
	_clients.erase(client)
	if client.room == "" or not _rooms.has(client.room):
		return
	var room: Room = _rooms[client.room]
	room.clients.erase(client.id)
	if client.id == 1:
		# The host is the world: without it the room is over.
		for other: Client in room.clients.values():
			_send_json(other, {"t": "host_left"})
			other.room = ""
			other.refused_ms = Time.get_ticks_msec()  # closed after a moment, like a refusal
		_rooms.erase(client.room)
		print("relay: room %s closed, host left (%d rooms)" % [client.room, _rooms.size()])
	else:
		for other: Client in room.clients.values():
			_send_json(other, {"t": "peer_left", "id": client.id})
		print("relay: player %d left room %s" % [client.id, client.room])


func _refuse(client: Client, reason: String) -> void:
	# Closing right away can drop the message, so the error is sent and the close comes later.
	_send_json(client, {"t": "error", "reason": reason})
	client.refused_ms = Time.get_ticks_msec()


func _send_json(client: Client, message: Dictionary) -> void:
	client.socket.send_text(JSON.stringify(message))


func _new_code() -> String:
	while true:
		var code := ""
		for i in CODE_LENGTH:
			code += CODE_CHARS[_rng.randi_range(0, CODE_CHARS.length() - 1)]
		if not _rooms.has(code):
			return code
	return ""


## Letters, digits, spaces and a few marks only, so a name can't carry control characters.
func _clean_name(raw: String) -> String:
	var clean := ""
	for character in raw.strip_edges():
		if character.unicode_at(0) >= 32 and character.unicode_at(0) < 127:
			clean += character
	clean = clean.substr(0, MAX_NAME_LENGTH).strip_edges()
	return clean if clean != "" else "Farmer"
