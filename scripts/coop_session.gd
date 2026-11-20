class_name CoopSession
extends Node
## Online co-op inside the farm scene (Main adds it only while Net is online). Host-authoritative:
## the host's world is the real one. This node
##  - tells the joiners the farm is ready (host) / asks the host for the farm and loads it (joiner),
##  - sends our farmer's position, facing and animation about 15 times a second,
##  - draws everybody else as RemoteFarmer and shows "joined" / "left" banners,
##  - sends a joiner back to the title when the host leaves.
## Joiners talk only to the host; the host passes positions on to the other joiners.
## Every RPC here lives on the node /root/Main/CoopSession (same path on every machine).

signal snapshot_applied  ## joiner: the host's farm is loaded
signal leaving(message: String)  ## joiner: the title screen follows in LEAVE_DELAY seconds

const SEND_INTERVAL := 1.0 / 15.0
const SNAPSHOT_RETRY := 1.5  # seconds between asking the host again (it may still be loading)
const SNAPSHOT_TRIES := 6
const LEAVE_DELAY := 2.5  # how long "The host left" stays up before the title appears

var player: Player
var entities: Node2D
var hud: Hud

var _farmers := {}  # player id -> RemoteFarmer
var _send_time := 0.0
var _got_snapshot := false
var _tries := 0
var _leaving := false
var _cover := ColorRect.new()
var _cover_label := UiStyle.make_label("", 10)


func _ready() -> void:
	name = "CoopSession"
	process_mode = Node.PROCESS_MODE_ALWAYS  # positions keep flowing while a menu has the game paused
	Net.player_joined.connect(_on_player_joined)
	Net.player_left.connect(_on_player_left)
	Net.host_left.connect(_on_host_left)
	Net.failed.connect(_on_failed)
	for id: int in Net.players:
		if id != Net.my_id():
			_show_farmer(id)
	if Net.is_host():
		Net.announce_start()
	else:
		_build_cover()
		_ask_for_snapshot()


func is_joiner() -> bool:
	return not Net.is_host()


## Joiner: the host's farm has been loaded.
func has_farm() -> bool:
	return _got_snapshot


func _process(delta: float) -> void:
	if not Net.is_online() or player == null:
		return
	_send_time += delta
	if _send_time < SEND_INTERVAL:
		return
	_send_time = 0.0
	if Net.is_host():
		_show_state.rpc(Net.HOST_ID, player.global_position, player.facing, player.current_anim())
	elif _got_snapshot:
		_report_state.rpc_id(Net.HOST_ID, player.global_position, player.facing, player.current_anim())


# --- Joining: the host's farm as a snapshot ---------------------------------

func _ask_for_snapshot() -> void:
	while not _got_snapshot and Net.is_online() and _tries < SNAPSHOT_TRIES:
		_tries += 1
		_request_snapshot.rpc_id(Net.HOST_ID)
		await get_tree().create_timer(SNAPSHOT_RETRY).timeout
	if not _got_snapshot and Net.is_online():
		_leave("Could not load the host's farm.")


## Joiner -> host: "send me the farm".
@rpc("any_peer", "call_remote", "reliable")
func _request_snapshot() -> void:
	if not Net.is_host():
		return
	var text := JSON.stringify(SaveGame.snapshot())
	_receive_snapshot.rpc_id(multiplayer.get_remote_sender_id(), text)


## Host -> joiner: the whole farm, in the same format as the save file.
@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(text: String) -> void:
	if _got_snapshot:
		return
	var sections := CoopRules.parse_snapshot(text)
	if sections.is_empty():
		return
	SaveGame.apply(CoopRules.joiner_sections(sections))
	_got_snapshot = true
	_cover.visible = false
	hud.show_banner("Joined %s's farm - Day %d" % [Net.player_name(Net.HOST_ID), Game.day])
	snapshot_applied.emit()


func _build_cover() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_cover.color = UiStyle.OUTLINE_COLOR
	_cover.size = UiStyle.SCREEN
	layer.add_child(_cover)
	_cover_label.text = "Getting %s's farm..." % Net.player_name(Net.HOST_ID)
	_cover_label.size = UiStyle.SCREEN
	_cover_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cover.add_child(_cover_label)


# --- Other players ------------------------------------------------------------

## Joiner -> host: where I am. The host checks it, then passes it on to everybody else.
@rpc("any_peer", "call_remote", "unreliable")
func _report_state(world_position: Vector2, facing: Vector2, anim: String) -> void:
	if not Net.is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if not Net.players.has(id):
		return
	var state := _clean(world_position, facing, anim)
	_apply_state(id, state)
	for other: int in Net.players:
		if other != id and other != Net.HOST_ID:
			_show_state.rpc_id(other, id, state["position"], state["facing"], state["anim"])


## Host -> joiners: where player `id` is.
@rpc("authority", "call_remote", "unreliable")
func _show_state(id: int, world_position: Vector2, facing: Vector2, anim: String) -> void:
	if id == Net.my_id() or not Net.players.has(id):
		return
	_apply_state(id, _clean(world_position, facing, anim))


func _clean(world_position: Vector2, facing: Vector2, anim: String) -> Dictionary:
	return CoopRules.clean_state(world_position, facing, anim, CoopRules.WORLD_BOUNDS, Player.ANIMS.keys())


func _apply_state(id: int, state: Dictionary) -> void:
	if not _farmers.has(id):
		_show_farmer(id)
	_farmers[id].set_state(state["position"], state["facing"], state["anim"])


func _show_farmer(id: int) -> void:
	if _farmers.has(id) or entities == null:
		return
	var farmer := RemoteFarmer.new()
	farmer.setup(id, Net.player_name(id))
	entities.add_child(farmer)
	_farmers[id] = farmer


func _on_player_joined(id: int, player_name: String) -> void:
	_show_farmer(id)
	if id != Net.HOST_ID:
		hud.show_banner("%s joined" % player_name)


## Net has already dropped the player when this arrives, so the name comes from the farmer.
func _on_player_left(id: int) -> void:
	var left_name := "A farmer"
	if _farmers.has(id):
		left_name = (_farmers[id] as RemoteFarmer).player_name
		_farmers[id].queue_free()
		_farmers.erase(id)
	if id != Net.HOST_ID:
		hud.show_banner("%s left" % left_name)


# --- Leaving ---------------------------------------------------------------------

func _on_host_left() -> void:
	_leave("The host left")


## The room server dropped us. A joiner can't play without the host; the host just carries on alone.
func _on_failed(reason: String) -> void:
	if is_joiner():
		_leave(reason)
	else:
		hud.show_banner(reason)


func _leave(message: String) -> void:
	if _leaving:
		return
	_leaving = true
	leaving.emit(message)
	hud.show_banner(message)
	_cover.visible = true
	_cover_label.text = message
	await get_tree().create_timer(LEAVE_DELAY).timeout
	Game.go_to_title()
