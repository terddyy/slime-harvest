class_name RelayPeer
extends MultiplayerPeerExtension
## A multiplayer peer that talks to server/relay.gd over a WebSocket (works in the browser too).
## Godot's normal RPC runs on top of it: the host is peer 1, joiners get 2, 3, ...
## See the top of server/relay.gd for the messages. Net (scripts/net.gd) creates and owns this.

signal room_ready(code: String)  ## the relay accepted us (created or joined a room)
signal relay_error(reason: String)  ## could not connect, or the relay refused (reason code)

const CODE_LENGTH := 6
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # keep in sync with server/relay.gd
const MAX_NAME_LENGTH := 16
const BUFFER_SIZE := 1 << 21
const CONNECT_TIMEOUT_MS := 10000
const MAX_PACKET_SIZE := 1 << 20

## player id -> name, for everybody in the room (not including us).
var names := {}
var room_code := ""

var _socket := WebSocketPeer.new()
var _hello := {}
var _status := MultiplayerPeer.CONNECTION_DISCONNECTED
var _unique_id := 0
var _incoming: Array[Dictionary] = []  # {from: int, data: PackedByteArray}
var _target_peer := 0
var _transfer_channel := 0
var _transfer_mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _started_ms := 0
var _hello_sent := false


## Only letters and digits that a room code can contain; "" if it is not a valid code.
static func clean_code(raw: String) -> String:
	var code := raw.strip_edges().to_upper()
	if code.length() != CODE_LENGTH:
		return ""
	for character in code:
		if not CODE_CHARS.contains(character):
			return ""
	return code


## A name with only printable ASCII, at most MAX_NAME_LENGTH long. Empty becomes "Farmer".
static func clean_name(raw: String) -> String:
	var clean := ""
	for character in raw.strip_edges():
		if character.unicode_at(0) >= 32 and character.unicode_at(0) < 127:
			clean += character
	clean = clean.substr(0, MAX_NAME_LENGTH).strip_edges()
	return clean if clean != "" else "Farmer"


func create_room(url: String, player_name: String) -> Error:
	return _connect(url, {"t": "create", "name": clean_name(player_name)})


func join_room(url: String, code: String, player_name: String) -> Error:
	return _connect(url, {"t": "join", "code": clean_code(code), "name": clean_name(player_name)})


func _connect(url: String, hello: Dictionary) -> Error:
	_socket = WebSocketPeer.new()
	_socket.inbound_buffer_size = BUFFER_SIZE
	_socket.outbound_buffer_size = BUFFER_SIZE
	var error := _socket.connect_to_url(url)
	if error != OK:
		return error
	_hello = hello
	_hello_sent = false
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	_started_ms = Time.get_ticks_msec()
	return OK


# --- MultiplayerPeerExtension: what Godot's RPC system asks of a peer ---

func _poll() -> void:
	if _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and not _hello_sent:
		_hello_sent = true
		_socket.send_text(JSON.stringify(_hello))
	while _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		if _socket.was_string_packet():
			_on_message(packet.get_string_from_utf8())
		elif packet.size() >= 4:
			_incoming.append({"from": packet.decode_s32(0), "data": packet.slice(4)})
		if _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			return
	if state == WebSocketPeer.STATE_CLOSED:
		_connection_ended()
	elif _status == MultiplayerPeer.CONNECTION_CONNECTING and Time.get_ticks_msec() - _started_ms > CONNECT_TIMEOUT_MS:
		_fail("unreachable")


func _on_message(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return
	var message: Dictionary = parsed
	match str(message.get("t", "")):
		"created":
			_enter_room(str(message.get("code", "")), int(message.get("id", 1)))
		"joined":
			_enter_room(str(message.get("code", "")), int(message.get("id", 0)))
			var peers: Array = message.get("peers", [])
			for peer: Variant in peers:
				if peer is Dictionary:
					_add_peer(int(peer.get("id", 0)), str(peer.get("name", "")))
		"peer_joined":
			_add_peer(int(message.get("id", 0)), str(message.get("name", "")))
		"peer_left":
			_remove_peer(int(message.get("id", 0)))
		"host_left":
			_connection_ended()
		"error":
			_fail(str(message.get("reason", "unknown")))


func _enter_room(code: String, id: int) -> void:
	room_code = code
	_unique_id = id
	_status = MultiplayerPeer.CONNECTION_CONNECTED
	room_ready.emit(code)


func _add_peer(id: int, peer_name: String) -> void:
	if id <= 0 or id == _unique_id or names.has(id):
		return
	names[id] = peer_name
	peer_connected.emit(id)


func _remove_peer(id: int) -> void:
	if names.erase(id):
		peer_disconnected.emit(id)


## The relay closed or the host left: everybody is gone, the host (peer 1) last.
func _connection_ended() -> void:
	var was_connected := _status == MultiplayerPeer.CONNECTION_CONNECTED
	var ids := names.keys()
	ids.sort()
	ids.reverse()
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_socket.close()
	for id: int in ids:
		peer_disconnected.emit(id)
	names.clear()
	# Joiners learn about a dropped relay from the host's peer_disconnected above.
	if not was_connected:
		relay_error.emit("unreachable")
	elif _unique_id == 1:
		relay_error.emit("lost")


func _fail(reason: String) -> void:
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_socket.close()
	relay_error.emit(reason)


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	return _incoming.pop_front()["data"]


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNCONFIGURED
	var out := PackedByteArray()
	out.resize(4)
	out.encode_s32(0, _target_peer)
	out.append_array(buffer)
	return _socket.send(out)


func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_max_packet_size() -> int:
	return MAX_PACKET_SIZE


func _get_packet_peer() -> int:
	return _incoming[0]["from"] if not _incoming.is_empty() else 0


func _get_packet_channel() -> int:
	return 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return MultiplayerPeer.TRANSFER_MODE_RELIABLE


func _set_target_peer(peer: int) -> void:
	_target_peer = peer


func _set_transfer_channel(channel: int) -> void:
	_transfer_channel = channel


func _get_transfer_channel() -> int:
	return _transfer_channel


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_transfer_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _transfer_mode


func _set_refuse_new_connections(_enable: bool) -> void:
	pass  # the relay decides who may join


func _is_refusing_new_connections() -> bool:
	return false


func _is_server() -> bool:
	return _unique_id == 1


func _is_server_relay_supported() -> bool:
	return false


func _get_unique_id() -> int:
	return _unique_id


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status


func _disconnect_peer(_peer: int, _force: bool) -> void:
	pass  # kicking players is not part of the co-op rules


func _close() -> void:
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_socket.close()
	names.clear()
	_incoming.clear()
