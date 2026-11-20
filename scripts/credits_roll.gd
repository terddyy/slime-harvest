class_name CreditsRoll
extends CanvasLayer
## Scrolling end credits shown after the ending panels. The text comes from Credits.roll_lines().
## Click / E / Space / Esc skips to the end. Runs while the tree is paused.

signal finished

const LAYER := 20
const SCROLL_SPEED := 22.0  # pixels per second
const LINE_SIZE := 10
const TEXT_WIDTH := 360.0
const BACKGROUND := Color(0.08, 0.05, 0.04)

var _label := UiStyle.make_label("", LINE_SIZE)
var _scrolling := false


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var root := ColorRect.new()
	root.color = BACKGROUND
	root.size = UiStyle.SCREEN
	root.theme = UiStyle.make_theme()
	root.clip_contents = true
	add_child(root)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # before the text, so the width stays fixed
	_label.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
	_label.size = Vector2(TEXT_WIDTH, 0)
	_label.position.x = (UiStyle.SCREEN.x - TEXT_WIDTH) / 2.0
	_label.text = "\n".join(Credits.roll_lines())
	root.add_child(_label)


func play() -> void:
	visible = true
	_scrolling = true
	get_tree().paused = true
	_label.size.y = 0.0
	_label.position.y = UiStyle.SCREEN.y - 40.0  # the first lines show right away


func _process(delta: float) -> void:
	if not _scrolling:
		return
	_label.position.y -= SCROLL_SPEED * delta
	if _label.position.y + _label.size.y < 0.0:
		_finish()


func _input(event: InputEvent) -> void:
	if not _scrolling:
		return
	var skip := event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact") \
			or event.is_action_pressed("ui_accept")
	if event is InputEventMouseButton:
		skip = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if skip:
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	_scrolling = false
	visible = false
	finished.emit()
