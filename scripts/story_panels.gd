class_name StoryPanels
extends CanvasLayer
## Illustrated story panels: one picture, a text box, click / interact / Space / Enter for the
## next panel, Esc skips the rest. Used for the intro (new game) and the ending (farm restored).
## Runs while the tree is paused. The panel texts and pictures are the two lists below.

## Emitted after the last panel, or when Esc skips them.
signal finished

const LAYER := 20  # above every other panel
const IMAGE_SIZE := Vector2(320, 180)
const IMAGE_TOP := 12.0
const TEXT_WIDTH := 380.0
const HINT := "Click / E / Space: next      Esc: skip"
const BACKGROUND := Color(0.08, 0.05, 0.04)

const INTRO: Array[Dictionary] = [
	{
		"image": "res://assets/generated/story_intro_1.png",
		"text": "Imogen and Gayle needed a fresh start. A letter said the old family farm was theirs, if they could bring it back to life.",
	},
	{
		"image": "res://assets/generated/story_intro_2.png",
		"text": "It was worse than the letter said. The barn had fallen in, the fields were all weeds, and slimes had moved into the tall grass.",
	},
	{
		"image": "res://assets/generated/story_intro_3.png",
		"text": "Slimes love crops, and they come out at night. Imogen and Gayle had six carrot seeds and plenty of hope. Time to start planting.",
	},
]
const ENDING: Array[Dictionary] = [
	{
		"image": "res://assets/generated/story_ending_1.png",
		"text": "Building by building, the farm came back. The fields are full, the barn is busy and the orchard is heavy with fruit.",
	},
	{
		"image": "res://assets/generated/story_ending_2.png",
		"text": "Imogen and Gayle sit on the porch with a basket of the harvest. It is the home they hoped for.",
	},
	{
		"image": "res://assets/generated/story_ending_3.png",
		"text": "The slimes still come when the sun goes down. But the fences hold and the lights stay on. Welcome home.",
	},
]

var _panels: Array[Dictionary] = []
var _index := 0
var _picture := TextureRect.new()
var _text := UiStyle.make_label("", UiStyle.TEXT_SIZE)
var _counter := UiStyle.make_label("", UiStyle.TEXT_SIZE, UiStyle.HIGHLIGHT)


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var root := ColorRect.new()
	root.color = BACKGROUND
	root.size = UiStyle.SCREEN
	root.theme = UiStyle.make_theme()
	add_child(root)

	_picture.position = Vector2((UiStyle.SCREEN.x - IMAGE_SIZE.x) / 2.0, IMAGE_TOP)
	_picture.size = IMAGE_SIZE
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_picture)
	var frame := Panel.new()  # border around the picture
	frame.position = _picture.position - Vector2(2, 2)
	frame.size = IMAGE_SIZE + Vector2(4, 4)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border := StyleBoxFlat.new()
	border.draw_center = false
	border.border_color = UiStyle.PANEL_BORDER
	border.set_border_width_all(2)
	frame.add_theme_stylebox_override("panel", border)
	root.add_child(frame)

	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.position = Vector2((UiStyle.SCREEN.x - TEXT_WIDTH) / 2.0, IMAGE_TOP + IMAGE_SIZE.y + 10)
	_text.size = Vector2(TEXT_WIDTH, 26)
	root.add_child(_text)
	_counter.position = Vector2(0, UiStyle.SCREEN.y - 14)
	_counter.size = Vector2(UiStyle.SCREEN.x, 12)
	root.add_child(_counter)


func is_open() -> bool:
	return visible


## Shows `panels` (each {image, text}) from the first one. Pauses the game until finished.
func play(panels: Array[Dictionary]) -> void:
	if panels.is_empty():
		finished.emit()
		return
	_panels = panels
	_index = 0
	visible = true
	get_tree().paused = true
	_show_current()


## Takes input before everything else so Esc / E never reach the pause menu or the world.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_finish()
	elif _is_advance(event):
		get_viewport().set_input_as_handled()
		_next()


func _is_advance(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	return event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")


func _next() -> void:
	_index += 1
	if _index >= _panels.size():
		_finish()
	else:
		_show_current()


func _show_current() -> void:
	var panel := _panels[_index]
	_picture.texture = load(panel["image"]) as Texture2D
	_text.text = panel["text"]
	_counter.text = "%d / %d      %s" % [_index + 1, _panels.size(), HINT]


func _finish() -> void:
	visible = false
	finished.emit()
