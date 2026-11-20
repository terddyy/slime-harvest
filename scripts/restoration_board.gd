class_name RestorationBoard
extends CanvasLayer
## The restoration board panel: every project with its price and what it unlocks.
## Pick one (arrows + Enter, or click) to pay for it with Game.restore(). Main opens it with E at
## the board next to the farmhouse. The game is paused while it is open; Esc or E closes it.

## Emitted each time the panel opens (the tutorial listens for it).
signal opened

const DIM_COLOR := Color(0.62, 0.56, 0.5)
const DONE_COLOR := Color(0.55, 0.9, 0.55)
const ROW_SIZE := Vector2(190, 18)
const UNLOCKS_WIDTH := 140.0

var _gold_label := Label.new()
var _info_label := Label.new()
var _buttons := {}  # project id -> Button
var _prices := {}  # project id -> Label on the right side of the button
var _leave := UiStyle.make_button("Leave")


func _ready() -> void:
	layer = 5  # above the HUD
	process_mode = Node.PROCESS_MODE_ALWAYS  # works while the game is paused
	visible = false
	_build()
	Game.stats_changed.connect(_refresh)


func open() -> void:
	opened.emit()
	visible = true
	Game.set_ui_open(true)
	_info_label.text = ""
	_refresh()
	var first := _leave
	for id in Restoration.ids():
		if not Game.is_restored(id):
			first = _buttons[id]
			break
	first.grab_focus()


func close() -> void:
	visible = false
	Game.set_ui_open(false)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		# Mark the key as used so Main doesn't reopen the board with the same press.
		get_viewport().set_input_as_handled()
		close()


func _restore(id: String) -> void:
	var project := Restoration.project(id)
	if Game.is_restored(id):
		_info_label.text = "%s is already restored." % project["name"]
		Audio.play_sfx("error")
	elif Game.restore(id):
		_info_label.text = "%s restored!" % project["name"]
		Audio.play_sfx("buy")
	else:
		_info_label.text = "Not enough gold (%dg needed)." % project["cost"]
		Audio.play_sfx("error")
	_refresh()


func _describe(id: String) -> String:
	var project := Restoration.project(id)
	return "%s: %s" % [project["name"], project["unlocks"]]


func _refresh() -> void:
	_gold_label.text = "%dg" % Game.gold
	for id: String in _buttons:
		var price: Label = _prices[id]
		if Game.is_restored(id):
			price.text = "Restored"
			price.add_theme_color_override("font_color", DONE_COLOR)
		else:
			var cost := int(Restoration.project(id)["cost"])
			var missing := Restoration.gold_short(id, Game.gold)
			price.text = "Need %dg more" % missing if missing > 0 else "Ready!"
			price.add_theme_color_override("font_color", UiStyle.HIGHLIGHT if Game.gold >= cost else DIM_COLOR)


func _build() -> void:
	var root := Control.new()
	root.size = UiStyle.SCREEN
	root.theme = UiStyle.make_theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.size = UiStyle.SCREEN
	root.add_child(dim)

	var column := UiStyle.make_centered_panel(root, 3)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := UiStyle.make_label("Restoration board", 12)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_gold_label.add_theme_color_override("font_color", UiStyle.HIGHLIGHT)
	header.add_child(_gold_label)

	for id in Restoration.ids():
		_add_row(column, id)

	_info_label.custom_minimum_size = Vector2(0, 12)
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_info_label)
	_leave.pressed.connect(close)
	_leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_leave)
	var keys := UiStyle.make_label("Arrows + Enter or click: restore      Esc / E: close", 6, DIM_COLOR)
	column.add_child(keys)


## A button with the name and price, and what the repair unlocks next to it.
func _add_row(column: VBoxContainer, id: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)

	var button := UiStyle.make_button("%s  %dg" % [Restoration.project(id)["name"], Restoration.project(id)["cost"]])
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = ROW_SIZE
	button.pressed.connect(_restore.bind(id))
	button.focus_entered.connect(func() -> void: _info_label.text = _describe(id))
	row.add_child(button)
	_buttons[id] = button

	var price := Label.new()
	price.set_anchors_preset(Control.PRESET_FULL_RECT)
	price.offset_right = -6
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(price)
	_prices[id] = price

	var unlocks := Label.new()
	unlocks.text = Restoration.project(id)["unlocks"]
	unlocks.custom_minimum_size = Vector2(UNLOCKS_WIDTH, 0)
	unlocks.add_theme_color_override("font_color", DIM_COLOR)
	unlocks.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(unlocks)
