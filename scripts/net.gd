extends Node
## Online co-op connection (autoload "Net"). Solo play never touches it.
## The host plays their own game; friends join with a 6-character room code through the
## relay (server/relay.gd). Game code then uses normal @rpc calls with the host as peer 1.
##   var code := await Net.host("Imogen")   # "" if it failed (see signal failed)
##   var ok := await Net.join("K7M2QX", "Sam")
##   Net.leave()
## Local test relay: add "-- --relay=ws://127.0.0.1:9080" to the command line.

signal room_created(code: String)  ## we are the host and the room is open
signal joined(code: String)  ## we are a joiner and the host accepted us
signal player_joined(id: int, player_name: String)  ## somebody else arrived (joiners also get this for the host)
signal player_left(id: int)
signal failed(reason: String)  ## friendly text: could not connect, wrong code, full room...
signal host_left  ## we are a joiner and the host is gone
signal game_start  ## we are a joiner and the host's farm is running: load it (see announce_start)

const DEFAULT_RELAY_URL := "wss://slimeharvest.imogen.dev/relay"
const HOST_ID := 1
## Reason codes from the relay (and RelayPeer) -> text for the player.
const REASONS := {
	"unreachable": "Can't reach the room server. Check your internet and try again.",
	"no_room": "No room with that code.",
	"bad_code": "Room codes have 6 letters and numbers.",
	"full": "That room is full.",
	"bad_hello": "The room server did not understand us.",
	"lost": "Lost the connection to the room server.",
}

var relay_url := DEFAULT_RELAY_URL
var room_code := ""
## player id -> name, everybody in the room including us.
var players := {}
## Host only: the farm scene is running, so a joiner who arrives gets sent straight in.
var game_started := false

var _peer: RelayPeer
var _my_name := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--relay="):
			relay_url = arg.trim_prefix("--relay=")
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


## Opens a room. Returns the room code, or "" if it failed (failed is emitted).
func host(player_name: String) -> String:
	if not _start():
		return ""
	_my_name = RelayPeer.clean_name(player_name)
	var error := _peer.create_room(relay_url, _my_name)
	if error != OK:
		_give_up("unreachable")
		return ""
	_attach_peer()
	return await _wait_for_room()


## Joins a room. Returns true when the host accepted us.
func join(code: String, player_name: String) -> bool:
	var clean := RelayPeer.clean_code(code)
	if clean == "":
		failed.emit(REASONS["bad_code"])
		return false
	if not _start():
		return false
	_my_name = RelayPeer.clean_name(player_name)
	var error := _peer.join_room(relay_url, clean, _my_name)
	if error != OK:
		_give_up("unreachable")
		return false
	_attach_peer()
	return await _wait_for_room() != ""


func leave() -> void:
	if _peer == null:
		return
	multiplayer.multiplayer_peer = null
	_peer.close()
	_reset()


## True while we are in a room, as host or joiner.
func is_online() -> bool:
	return _peer != null and room_code != ""


## Host only: the farm is built (Main calls this). Tells every joiner in the room to load it,
## and anybody who joins later too.
func announce_start() -> void:
	if not is_host():
		return
	game_started = true
	_go.rpc()


func is_host() -> bool:
	return is_online() and multiplayer.get_unique_id() == HOST_ID


func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else HOST_ID


func player_name(id: int) -> String:
	return players.get(id, "Farmer")


func _start() -> bool:
	if _peer != null:
		failed.emit("You are already in a room.")
		return false
	_peer = RelayPeer.new()
	_peer.room_ready.connect(_on_room_ready)
	_peer.relay_error.connect(_give_up)
	return true


## Called right after create_room/join_room started connecting: from now on the tree polls the peer.
func _attach_peer() -> void:
	multiplayer.multiplayer_peer = _peer


## Waits until the relay answered: returns the code, or "" when the attempt failed.
func _wait_for_room() -> String:
	var peer := _peer
	while peer != null and peer == _peer and room_code == "":
		await get_tree().process_frame
	return room_code if peer == _peer else ""


func _on_room_ready(code: String) -> void:
	room_code = code
	players[multiplayer.get_unique_id()] = _my_name
	if multiplayer.get_unique_id() == HOST_ID:
		room_created.emit(code)
	else:
		joined.emit(code)


func _on_peer_connected(id: int) -> void:
	if _peer == null:
		return
	players[id] = _peer.names.get(id, "Farmer")
	player_joined.emit(id, players[id])
	if game_started and is_host():
		_go.rpc_id(id)


func _on_peer_disconnected(id: int) -> void:
	if _peer == null:
		return
	players.erase(id)
	player_left.emit(id)
	if id == HOST_ID and multiplayer.get_unique_id() != HOST_ID:
		leave.call_deferred()  # we are inside the multiplayer poll, so leave after it
		host_left.emit()


## Connecting failed, the relay refused us, or the relay connection dropped.
func _give_up(reason: String) -> void:
	leave.call_deferred()  # we are inside the multiplayer poll, so leave after it
	failed.emit(REASONS.get(reason, "Could not connect."))


## Host -> joiner: the farm is running, go in.
@rpc("authority", "call_remote", "reliable")
func _go() -> void:
	game_start.emit()


func _reset() -> void:
	_peer = null
	room_code = ""
	game_started = false
	players.clear()
