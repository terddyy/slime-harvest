class_name GayleTalk
extends CanvasLayer
## The little dialog that opens when Imogen presses E next to Gayle: one short line and a
## Follow me / Stay here button. Pauses the game while open; Esc or E closes it.

## Emitted each time the dialog opens (the tutorial listens for it).
signal opened

const LAYER := 5  # above the HUD, like the shop
const LINES := [
	"Look at us, Imogen. A whole farm to fix up together.",
	"I'll keep the crops watered. You keep the slimes honest.",
	"Dinner will wait. The carrots won't.",
	"We can do this, Imogen. One building at a time.",
	"Tell me where you want me and I'll hold the spot.",
	"I like it here. Even with all the slimes.",
	"Careful out there at night. I'll watch the field.",
]

var gayle: Gayle

var _text := UiStyle.make_label("", 8)
var _toggle := UiStyle.make_button("")
var _line_index := 0


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var root := Control.new()
	root.size = UiStyle.SCREEN
	root.theme = UiStyle.make_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var column := UiStyle.make_centered_panel(root)
	column.add_child(UiStyle.make_label("Gayle", 12, UiStyle.HIGHLIGHT))
	_text.custom_minimum_size = Vector2(200, 0)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_text)
	column.add_child(_toggle)
	var bye := UiStyle.make_button("Bye")
	column.add_child(bye)
	_toggle.pressed.connect(_on_toggle)
	bye.pressed.connect(close)


func is_open() -> bool:
	return visible


func open() -> void:
	opened.emit()
	_line_index = (_line_index + 1) % LINES.size()
	_text.text = LINES[_line_index]
	_refresh_button()
	visible = true
	get_tree().paused = true
	_toggle.grab_focus()


func close() -> void:
	visible = false
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()  # so Main doesn't reopen the dialog with the same press
		close()


func _on_toggle() -> void:
	gayle.toggle_mode()
	Audio.play_sfx("ui_select")
	_text.text = "Okay, I'll follow you." if gayle.is_following() else "Okay, I'll stay right here."
	_refresh_button()


func _refresh_button() -> void:
	_toggle.text = "Stay here" if gayle.is_following() else "Follow me"
