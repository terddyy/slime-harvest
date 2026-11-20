class_name SettingsMenu
extends Control
## Settings panel: volumes, fullscreen and key rebinding. Edits Game.settings and saves it
## when closed. Used by the title screen and the pause menu. Call open(); emits `closed`
## on Back or Esc. While waiting for a key, Esc cancels instead of closing.

signal closed

const VOLUME_ROWS := [["master", "Master"], ["music", "Music"], ["sfx", "Effects"]]
const VOLUME_STEP := 0.1
const LIST_HEIGHT := 92
const KEY_BUTTON_SIZE := Vector2(64, 13)
const SLIDER_WIDTH := 120
const MESSAGE_COLOR := Color(1.0, 0.85, 0.4)

var _back_button := UiStyle.make_button("Back")
var _message := UiStyle.make_label("")
var _fullscreen_box := CheckBox.new()
var _sliders := {}  # bus -> HSlider
var _key_buttons := {}  # "action:slot" -> Button
var _waiting_action := ""  # action waiting for a key press ("" = not rebinding)
var _waiting_slot := 0


func _ready() -> void:
	size = UiStyle.SCREEN
	visible = false
	var column := UiStyle.make_centered_panel(self, 4)
	column.add_child(UiStyle.make_label("Settings", 12, UiStyle.HIGHLIGHT))
	column.add_child(_build_volumes())
	_fullscreen_box.text = "Fullscreen"
	_fullscreen_box.focus_mode = Control.FOCUS_ALL
	_fullscreen_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_fullscreen_box.visible = not OS.has_feature("web")  # a browser tab has no window mode
	_fullscreen_box.toggled.connect(_on_fullscreen_toggled)
	column.add_child(_fullscreen_box)
	column.add_child(UiStyle.make_label("Controls: click a key, then press the new one (Esc cancels)", UiStyle.TEXT_SIZE, UiStyle.HIGHLIGHT))
	column.add_child(_build_key_list())
	_message.custom_minimum_size.y = 10
	column.add_child(_message)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 6)
	var reset_button := UiStyle.make_button("Reset keys")
	reset_button.pressed.connect(_on_reset_pressed)
	_back_button.pressed.connect(close)
	buttons.add_child(reset_button)
	buttons.add_child(_back_button)
	column.add_child(buttons)


func open() -> void:
	_refresh()
	_set_waiting("")
	_message.text = ""
	visible = true
	_back_button.grab_focus()


func close() -> void:
	if not visible:
		return
	_set_waiting("")
	visible = false
	Game.settings.save_file()
	closed.emit()


func _build_volumes() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 2)
	for row: Array in VOLUME_ROWS:
		var bus: String = row[0]
		var label := UiStyle.make_label(row[1])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.custom_minimum_size.x = 50
		grid.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = VOLUME_STEP
		slider.custom_minimum_size = Vector2(SLIDER_WIDTH, 10)
		slider.focus_mode = Control.FOCUS_ALL
		slider.value_changed.connect(_on_volume_changed.bind(bus))
		_sliders[bus] = slider
		grid.add_child(slider)
	return grid


func _build_key_list() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(240, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 1)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for action: String in Settings.ACTION_LABELS:
		var label := UiStyle.make_label(Settings.ACTION_LABELS[action])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)
		for slot in (Settings.DEFAULT_BINDINGS[action] as Array).size():
			var button := UiStyle.make_button("")
			button.custom_minimum_size = KEY_BUTTON_SIZE
			button.add_theme_font_size_override("font_size", UiStyle.TEXT_SIZE)
			button.pressed.connect(_on_key_pressed.bind(action, slot))
			_key_buttons["%s:%d" % [action, slot]] = button
			grid.add_child(button)
		if (Settings.DEFAULT_BINDINGS[action] as Array).size() == 1:
			grid.add_child(Control.new())  # keep the three columns aligned
	return scroll


## Shows the current settings in the widgets.
func _refresh() -> void:
	for bus: String in _sliders:
		(_sliders[bus] as HSlider).set_value_no_signal(Game.settings.volume(bus))
	_fullscreen_box.set_pressed_no_signal(Game.settings.fullscreen)
	for action: String in Settings.ACTION_LABELS:
		for slot in (Settings.DEFAULT_BINDINGS[action] as Array).size():
			(_key_buttons["%s:%d" % [action, slot]] as Button).text = Settings.key_label(Game.settings.key_for(action, slot))


func _on_volume_changed(value: float, bus: String) -> void:
	Game.settings.set_volume(bus, value)
	Audio.apply_settings(Game.settings)
	if bus != "music":
		Audio.play_sfx("ui_select")  # lets you hear the level you just picked


func _on_fullscreen_toggled(pressed: bool) -> void:
	Game.settings.fullscreen = pressed
	Game.apply_display()


func _on_key_pressed(action: String, slot: int) -> void:
	_set_waiting(action, slot)


func _on_reset_pressed() -> void:
	Game.settings.reset_bindings()
	Game.apply_key_bindings()
	_set_waiting("")
	_refresh()
	_show_message("Keys reset to defaults.")


func _set_waiting(action: String, slot := 0) -> void:
	if _waiting_action != "":
		var old: Button = _key_buttons["%s:%d" % [_waiting_action, _waiting_slot]]
		old.text = Settings.key_label(Game.settings.key_for(_waiting_action, _waiting_slot))
	_waiting_action = action
	_waiting_slot = slot
	if action != "":
		(_key_buttons["%s:%d" % [action, slot]] as Button).text = "Press a key..."
		_show_message("")


func _show_message(text: String) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", MESSAGE_COLOR)


## While waiting for a key this sees every key press before the buttons do.
func _input(event: InputEvent) -> void:
	if not visible or _waiting_action == "":
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo or key_event.physical_keycode == KEY_NONE:
		return
	get_viewport().set_input_as_handled()
	if key_event.physical_keycode == KEY_ESCAPE:
		_set_waiting("")
		return
	var result := Game.settings.rebind(_waiting_action, _waiting_slot, key_event.physical_keycode as int)
	_set_waiting("")
	if result["ok"]:
		Game.apply_key_bindings()
		_refresh()
	_show_message(result["message"])
	if not result["ok"]:
		Audio.play_sfx("error")


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
