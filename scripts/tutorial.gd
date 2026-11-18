class_name Tutorial
extends CanvasLayer
## First-day tips: a small box at the top of the screen that walks a new player through
## till -> water -> plant -> grow -> harvest -> sell, then warns about the night and hides.
## Each tip moves on when the real thing happens (Farm signals, Game.crops_sold).
## The steps and their texts live in TutorialSteps; this node shows them.
## F1 hides the tips. Once finished or hidden they stay off until the game is closed:
## a restart from the pause menu doesn't show them again.

const BOX_WIDTH := 290.0
const BOX_TOP := 4.0
const NIGHT_TIP_TIME := 8.0  # seconds the last tip stays up
const FADE_TIME := 0.5
const DIM_COLOR := Color(0.7, 0.64, 0.56)

## True once the tips were finished or hidden. Static, so it survives a restart
## (main.tscn is rebuilt) but not closing the game.
static var is_finished := false

var _steps := TutorialSteps.new()
var _panel := PanelContainer.new()
var _counter_label := Label.new()
var _text_label := Label.new()
var _night_tip_left := 0.0


func _ready() -> void:
	visible = not is_finished
	_build()
	_show_current()


## Main calls this once; the tips listen to the farm and the clock from here on.
func setup(farm: Farm, board: RestorationBoard, gayle_talk: GayleTalk) -> void:
	# bind() adds the event name after the signal's own `cell` argument.
	farm.tilled.connect(_on_farm_event.bind("tilled"))
	farm.watered.connect(_on_farm_event.bind("watered"))
	farm.planted.connect(_on_farm_event.bind("planted"))
	farm.crop_ripened.connect(_on_farm_event.bind("ripened"))
	farm.harvested.connect(_on_farm_event.bind("harvested"))
	board.opened.connect(_record.bind("board"))
	gayle_talk.opened.connect(_record.bind("talked"))
	Game.slept.connect(_record.bind("slept"))
	Game.crops_sold.connect(_on_crops_sold)
	Game.phase_changed.connect(_on_phase_changed)
	Game.farm_restored.connect(_on_farm_restored)


## What the guide arrow should point at for the tip on screen ("" = nothing). At night the box
## shows the night tip instead, so there is no target then.
func guide_target() -> String:
	if is_finished or not visible or Game.is_night:
		return ""
	return _steps.target()


func _process(delta: float) -> void:
	if _night_tip_left <= 0.0:
		return
	_night_tip_left -= delta
	if _night_tip_left <= 0.0:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("hide_tips"):
		get_viewport().set_input_as_handled()
		_finish()


func _record(event: String) -> void:
	if is_finished or not _steps.record(event):
		return
	_show_current()
	# A quick bright flash so the player notices the tip changed.
	_panel.modulate = Color(1.6, 1.6, 1.6)
	_panel.create_tween().tween_property(_panel, "modulate", Color.WHITE, 0.3)


func _show_current() -> void:
	var step_count := TutorialSteps.STEPS.size()
	if _steps.is_done():
		_counter_label.text = "Last tip"
		_text_label.text = _steps.text()
		if _night_tip_left <= 0.0:
			_night_tip_left = NIGHT_TIP_TIME
	elif Game.is_night:
		_counter_label.text = "Night"
		_text_label.text = TutorialSteps.NIGHT_NOW
	else:
		_counter_label.text = "Tip %d/%d" % [_steps.index + 1, step_count]
		_text_label.text = _steps.text()


func _finish() -> void:
	if is_finished:
		return
	is_finished = true
	_night_tip_left = 0.0
	var tween := _panel.create_tween()
	tween.tween_property(_panel, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(hide)


func _on_farm_event(_cell: Vector2i, event: String) -> void:
	_record(event)


func _on_crops_sold(_earned: int) -> void:
	_record("sold")


func _on_phase_changed(_is_night: bool) -> void:
	if not is_finished:
		_show_current()


func _on_farm_restored() -> void:
	hide()  # don't draw over the ending screen


func _build() -> void:
	var root := Control.new()
	root.size = UiStyle.SCREEN
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiStyle.make_theme()
	add_child(root)

	var style := UiStyle.panel_style()
	style.bg_color.a = 0.9
	style.set_content_margin_all(4)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.position = Vector2((UiStyle.SCREEN.x - BOX_WIDTH) / 2.0, BOX_TOP)
	_panel.custom_minimum_size.x = BOX_WIDTH
	root.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	_panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_counter_label.add_theme_color_override("font_color", UiStyle.HIGHLIGHT)
	_counter_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_counter_label)
	var skip_label := Label.new()
	skip_label.text = "F1: hide tips"
	skip_label.add_theme_color_override("font_color", DIM_COLOR)
	header.add_child(skip_label)

	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size.x = BOX_WIDTH - 8.0
	column.add_child(_text_label)
