class_name PauseMenu
extends CanvasLayer
## Esc pauses the game and shows Resume / Restart / How to Play / Quit to Title.
## Runs while the tree is paused. Never opens over the ending screen.

const LAYER := 10  # above the HUD
const DIM_COLOR := Color(0, 0, 0, 0.5)

var _dim := ColorRect.new()
var _menu := Control.new()
var _how_to_play := HowToPlay.new()
var _settings_menu := SettingsMenu.new()
var _resume_button := UiStyle.make_button("Resume")
var _how_button := UiStyle.make_button("How to Play")
var _settings_button := UiStyle.make_button("Settings")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = LAYER
	var root := Control.new()
	root.size = UiStyle.SCREEN
	root.theme = UiStyle.make_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_dim.color = DIM_COLOR
	_dim.size = UiStyle.SCREEN
	root.add_child(_dim)

	_menu.size = UiStyle.SCREEN
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_menu)
	var column := UiStyle.make_centered_panel(_menu)
	column.add_child(UiStyle.make_label("Paused", 12, UiStyle.HIGHLIGHT))
	var restart_button := UiStyle.make_button("Restart")
	var title_button := UiStyle.make_button("Quit to Title")
	for button in [_resume_button, restart_button, _how_button, _settings_button, title_button]:
		column.add_child(button)
	restart_button.visible = not Net.is_online()  # a new game would drop the friends' farm
	_resume_button.pressed.connect(close)
	restart_button.pressed.connect(Game.start_new_game)
	_how_button.pressed.connect(_open_how_to_play)
	_settings_button.pressed.connect(_open_settings)
	title_button.pressed.connect(_quit_to_title)

	_how_to_play.closed.connect(_close_how_to_play)
	root.add_child(_how_to_play)
	_settings_menu.closed.connect(_close_settings)
	root.add_child(_settings_menu)

	Game.farm_restored.connect(_on_farm_restored)
	_set_shown(false)


# Quit, Restart and the ending reload or leave the scene: never leave the music frozen.
func _exit_tree() -> void:
	Audio.set_music_paused(false)


func _quit_to_title() -> void:
	SaveGame.save()
	Game.go_to_title()


func is_open() -> bool:
	return _dim.visible


func open() -> void:
	# Something else (the shop) already paused the game and owns Esc.
	if is_open() or Game.is_paused():
		return
	Game.set_ui_open(true)
	Audio.set_music_paused(true)
	_set_shown(true)
	_resume_button.grab_focus()


func close() -> void:
	if not is_open():
		return
	_how_to_play.visible = false
	_settings_menu.close()
	_set_shown(false)
	Audio.set_music_paused(false)
	Game.set_ui_open(false)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	get_viewport().set_input_as_handled()
	if is_open():
		close()
	else:
		open()


func _set_shown(shown: bool) -> void:
	_dim.visible = shown
	_menu.visible = shown


func _open_how_to_play() -> void:
	_menu.visible = false
	_how_to_play.open()


func _close_how_to_play() -> void:
	_menu.visible = true
	_how_button.grab_focus()


func _open_settings() -> void:
	_menu.visible = false
	_settings_menu.open()


func _close_settings() -> void:
	_menu.visible = true
	_settings_button.grab_focus()


## The farm can be saved while the menu is open: the ending screen wins.
## The HUD keeps the tree paused, so only hide the menu here.
func _on_farm_restored() -> void:
	_how_to_play.visible = false
	_settings_menu.close()
	_set_shown(false)
	Audio.set_music_paused(false)
	Game.ui_open = false  # the tree stays paused (HUD), but the menu is no longer what blocks the farmer
