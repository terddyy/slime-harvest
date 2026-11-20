class_name LoadingScreen
extends Control
## Shown between the title and the farm: loads the game scene on a thread, shows a bar and a tip.
## Game.enter_farm() changes to this scene; it then switches to Game.MAIN_SCENE when ready.

const BAR_SIZE := Vector2(200, 10)
const MIN_SECONDS := 0.4  # keep it on screen long enough to read, even when loading is instant

var _bar := ProgressBar.new()
var _elapsed := 0.0
var _done := false


func _ready() -> void:
	size = UiStyle.SCREEN
	theme = UiStyle.make_theme()
	var backdrop := ColorRect.new()
	backdrop.color = UiStyle.OUTLINE_COLOR
	backdrop.size = UiStyle.SCREEN
	add_child(backdrop)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size = UiStyle.SCREEN
	add_child(column)
	var logo := TextureRect.new()
	logo.texture = preload("res://assets/generated/logo.png")
	logo.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	column.add_child(logo)
	column.add_child(UiStyle.make_label("Loading...", 10))

	_bar.custom_minimum_size = BAR_SIZE
	_bar.show_percentage = false
	_bar.add_theme_stylebox_override("background", _bar_box(UiStyle.PANEL_COLOR))
	_bar.add_theme_stylebox_override("fill", _bar_box(UiStyle.HIGHLIGHT))
	var bar_row := CenterContainer.new()
	bar_row.add_child(_bar)
	column.add_child(bar_row)

	var tip := UiStyle.make_label(LoadingTips.tip(randi()), UiStyle.TEXT_SIZE)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(320, 0)
	var tip_row := CenterContainer.new()
	tip_row.add_child(tip)
	column.add_child(tip_row)

	ResourceLoader.load_threaded_request(Game.MAIN_SCENE)


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(Game.MAIN_SCENE, progress)
	_bar.value = LoadingTips.percent(progress)
	if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		push_error("Could not load %s" % Game.MAIN_SCENE)
		_done = true
		Game.go_to_title()
	elif status == ResourceLoader.THREAD_LOAD_LOADED and _elapsed >= MIN_SECONDS:
		_bar.value = 100
		_done = true
		var scene := ResourceLoader.load_threaded_get(Game.MAIN_SCENE) as PackedScene
		get_tree().change_scene_to_packed(scene)


static func _bar_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = UiStyle.PANEL_BORDER
	box.set_border_width_all(0)
	return box
