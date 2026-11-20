class_name Lobby
extends Control
## "Play Together" panel on the title screen: host a farm (room code, who has joined, Start) or
## join one (code + name). The farm itself is loaded by Main once everybody is in; see
## CoopSession. Call open(); emits `closed` on Back or Esc (after leaving any room).

signal closed

const CODE_LENGTH := RelayPeer.CODE_LENGTH
const ERROR_COLOR := Color(1.0, 0.55, 0.45)
const CODE_COLOR := Color(1.0, 0.85, 0.4)
const FIELD_SIZE := Vector2(110, 16)

## Remembered while the game runs, so a second try doesn't ask for the name again.
static var last_name := ""

var _pages: Array[Control] = []
var _start_page := Control.new()
var _room_page := Control.new()  # hosting or waiting for the host: code + who is here
var _join_page := Control.new()
var _name_field := LineEdit.new()
var _code_field := LineEdit.new()
var _start_message := UiStyle.make_label("", UiStyle.TEXT_SIZE, ERROR_COLOR)
var _join_message := UiStyle.make_label("", UiStyle.TEXT_SIZE, ERROR_COLOR)
var _room_label := UiStyle.make_label("", 16, CODE_COLOR)
var _roster_label := UiStyle.make_label("")
var _hint_label := UiStyle.make_label("")
var _host_button := UiStyle.make_button("Host a Farm")
var _join_button := UiStyle.make_button("Join with a Code")
var _back_button := UiStyle.make_button("Back")
var _start_button := UiStyle.make_button("Start")
var _leave_button := UiStyle.make_button("Cancel")
var _go_button := UiStyle.make_button("Join")
var _join_back_button := UiStyle.make_button("Back")
var _busy := false  # waiting for the room server


func _ready() -> void:
	size = UiStyle.SCREEN
	visible = false
	_build_start_page()
	_build_room_page()
	_build_join_page()
	Net.failed.connect(_on_failed)
	Net.player_joined.connect(_refresh_roster.unbind(2))
	Net.player_left.connect(_refresh_roster.unbind(1))
	Net.host_left.connect(_on_host_left)
	Net.game_start.connect(_enter_farm_as_joiner)


func open() -> void:
	_start_message.text = ""
	_name_field.text = last_name
	visible = true
	_show_page(_start_page)
	_host_button.grab_focus()


func close() -> void:
	if not visible:
		return
	Net.leave()
	_busy = false
	visible = false
	closed.emit()


# --- Pages -------------------------------------------------------------------

func _build_start_page() -> void:
	var column := _new_page(_start_page)
	column.add_child(UiStyle.make_label("Play Together", 12, UiStyle.HIGHLIGHT))
	column.add_child(UiStyle.make_label("Friends join your farm with a room code.\nGold, seeds and the bag are shared."))
	_setup_field(_name_field, "Your name", RelayPeer.MAX_NAME_LENGTH)
	column.add_child(_name_field)
	for button in [_host_button, _join_button, _back_button]:
		column.add_child(button)
	column.add_child(_start_message)
	_host_button.pressed.connect(_host_room)
	_join_button.pressed.connect(_show_join_page)
	_back_button.pressed.connect(close)


func _build_room_page() -> void:
	var column := _new_page(_room_page)
	column.add_child(UiStyle.make_label("Room code"))
	column.add_child(_room_label)
	column.add_child(_roster_label)
	column.add_child(_hint_label)
	column.add_child(_start_button)
	column.add_child(_leave_button)
	_start_button.pressed.connect(_start_hosted_game)
	_leave_button.pressed.connect(_leave_room)


func _build_join_page() -> void:
	var column := _new_page(_join_page)
	column.add_child(UiStyle.make_label("Join a farm", 12, UiStyle.HIGHLIGHT))
	_setup_field(_code_field, "Room code", CODE_LENGTH)
	_code_field.text_changed.connect(_upper_case_code)
	_code_field.text_submitted.connect(_join_room.unbind(1))
	column.add_child(_code_field)
	column.add_child(_go_button)
	column.add_child(_join_back_button)
	column.add_child(_join_message)
	_go_button.pressed.connect(_join_room)
	_join_back_button.pressed.connect(_leave_room)


func _setup_field(field: LineEdit, placeholder: String, max_length: int) -> void:
	field.placeholder_text = placeholder
	field.max_length = max_length
	field.custom_minimum_size = FIELD_SIZE
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER


func _new_page(page: Control) -> VBoxContainer:
	page.size = UiStyle.SCREEN
	page.visible = false
	add_child(page)
	_pages.append(page)
	return UiStyle.make_centered_panel(page, 5)


func _show_page(page: Control) -> void:
	for other in _pages:
		other.visible = other == page


func _show_join_page() -> void:
	_join_message.text = ""
	_show_page(_join_page)
	_set_joining(false)
	_code_field.grab_focus()


func _set_joining(joining: bool) -> void:
	_go_button.text = "Joining..." if joining else "Join"
	_go_button.disabled = joining
	_code_field.editable = not joining


func _upper_case_code(text: String) -> void:
	var cursor := _code_field.caret_column
	_code_field.text = text.to_upper()
	_code_field.caret_column = cursor


# --- Hosting -------------------------------------------------------------------

func _host_room() -> void:
	if _busy:
		return
	_busy = true
	last_name = RelayPeer.clean_name(_name_field.text)
	_start_message.text = ""
	_host_button.text = "Opening a room..."
	var code := await Net.host(last_name)
	_busy = false
	_host_button.text = "Host a Farm"
	if code == "":
		return  # _on_failed showed why
	_room_label.text = code
	_leave_button.text = "Cancel"
	_hint_label.text = "Friends pick Join with a Code and type this."
	_start_button.text = "Start (continue your farm)" if SaveGame.has_save() else "Start (new farm)"
	_refresh_roster()
	_show_page(_room_page)
	_start_button.grab_focus()


## The host's farm (a save if there is one) loads; Main tells the joiners when it is ready.
func _start_hosted_game() -> void:
	Game.reset()
	SaveGame.load_requested = SaveGame.has_save()
	Game.enter_farm()


# --- Joining ---------------------------------------------------------------------

func _join_room() -> void:
	if _busy:
		return
	_busy = true
	last_name = RelayPeer.clean_name(_name_field.text)
	_join_message.text = ""
	_set_joining(true)
	var joined := await Net.join(_code_field.text, last_name)
	_busy = false
	_set_joining(false)
	if not joined:
		return  # _on_failed showed why
	_room_label.text = Net.room_code
	_hint_label.text = "Waiting for the host to start..."
	_leave_button.text = "Leave"
	_refresh_roster()
	_show_page(_room_page)
	_leave_button.grab_focus()


## The host's farm is running: load it (Main asks the host for the snapshot).
func _enter_farm_as_joiner() -> void:
	Game.reset()
	SaveGame.load_requested = false
	Game.enter_farm()


# --- Room events -------------------------------------------------------------------

func _refresh_roster() -> void:
	var lines: Array[String] = []
	var ids := Net.players.keys()
	ids.sort()
	for id: int in ids:
		var tag := " (host)" if id == Net.HOST_ID else ""
		tag += " (you)" if id == Net.my_id() else ""
		lines.append(Net.players[id] + tag)
	_roster_label.text = "\n".join(lines)
	_start_button.visible = Net.is_host()


## Can't connect, wrong code, full room, or the connection dropped: say why where the player looks.
func _on_failed(reason: String) -> void:
	_busy = false
	_host_button.text = "Host a Farm"
	if not visible:
		return
	if _join_page.visible:
		_set_joining(false)
		_join_message.text = reason
		return
	_start_message.text = reason
	_show_page(_start_page)
	_host_button.grab_focus()


func _on_host_left() -> void:
	_on_failed("The host closed the room.")


## Back out of a room (or the join page) to the first page.
func _leave_room() -> void:
	Net.leave()
	_start_message.text = ""
	_leave_button.text = "Cancel"
	_show_page(_start_page)
	_host_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _start_page.visible:
			close()
		else:
			_leave_room()
