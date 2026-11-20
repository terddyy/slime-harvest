class_name HowToPlay
extends Control
## "How to Play" panel: the goal plus the controls table from docs/GDD.md.
## Used by the title screen and the pause menu. Call open(); emits `closed` on Back or Esc.

signal closed

## [keys, action]. {name} is replaced by the current main key of that action (settings can
## change it); {move} is the four move keys. Keep in sync with the Controls table in docs/GDD.md.
const CONTROLS := [
	["{move} / arrows", "Move"],
	["{tool_1} / {tool_2} / {tool_3} / {tool_4} / {tool_5} / {tool_6}", "Hoe / Watering can / Seeds / Sword / Fence / Sprinkler"],
	["Mouse", "Point at a tile (up to 2 tiles) to aim; wheel or hotbar click: tool"],
	["Left click / {use_tool}", "Use the tool (hold + drag: many tiles); ripe crop: harvest"],
	["{cycle_seed}, or {tool_3} again", "Seeds selected: next seed / sapling"],
	["{interact} / right click", "Harvest, collect, talk to Azy / Gayle, use the board, door, bed"],
	["Shop / board", "Arrows + Enter or mouse to buy or restore; Esc or {interact} to close"],
	["Esc / {hide_tips}", "Pause / hide the first-day tips"],
	["{inventory} / {goals}", "Inventory (backpack, storage, goals) / farm goals"],
	["{zoom_in} / {zoom_out} or Ctrl+wheel", "Zoom in / out (touchpad: pinch)"],
	["{skip_phase}", "Debug: skip to the next day/night phase"],
]
const KEY_COLOR := Color(1.0, 0.85, 0.4)

var _back_button := UiStyle.make_button("Back")
var _key_labels: Array[Label] = []  # the two columns, rewritten on open() in case keys changed
var _action_labels: Array[Label] = []


func _ready() -> void:
	size = UiStyle.SCREEN
	visible = false
	var column := UiStyle.make_centered_panel(self, 6)
	column.add_child(UiStyle.make_label("How to Play", 12, KEY_COLOR))

	var goal := UiStyle.make_label(
			"Imogen and Gayle are fixing up the family farm. Till, plant and water crops,
"
			+ "sell them to Azy at the stall, and fight off the slimes that eat them at night.
"
			+ "Earn gold to restore every building at the board by the farmhouse.
"
			+ "Gayle helps; sleeping in the farmhouse skips the night. The game autosaves.")
	column.add_child(goal)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 1)
	for row: Array in CONTROLS:
		var key := UiStyle.make_label("", UiStyle.TEXT_SIZE, KEY_COLOR)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(key)
		_key_labels.append(key)
		var action := UiStyle.make_label("")
		_action_labels.append(action)
		action.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(action)
	column.add_child(grid)

	_back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back_button.pressed.connect(close)
	column.add_child(_back_button)


func open() -> void:
	for i in CONTROLS.size():
		_key_labels[i].text = Game.settings.fill_keys(CONTROLS[i][0])
		_action_labels[i].text = Game.settings.fill_keys(CONTROLS[i][1])
	visible = true
	_back_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
