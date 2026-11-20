class_name Hud
extends CanvasLayer
## On-screen UI: clock, gold/seeds/crops, tool hotbar, hints, banners, restoration progress, ending screen.
## Positions are in the 480x270 base resolution.

const SCREEN := Vector2(480, 270)
const TOOL_ICONS := preload("res://assets/cute_fantasy/Icons/Outline/Tool_Icons_Outline.png")
const FOOD_ICONS := preload("res://assets/cute_fantasy/Icons/Outline/Food_Icons_Outline.png")
const RESOURCE_ICONS := preload("res://assets/cute_fantasy/Icons/Outline/Resources_Icons_Outline.png")
const FENCE_ICONS := preload("res://assets/cute_fantasy/Outdoor decoration/Fences.png")
## 16x16 cells: wool, sprinkler (tools/gen_late_game_icons.py).
const LATE_ICONS := preload("res://assets/generated/late_game_icons.png")
## Hotbar icon per Player.Tool, in enum order: [texture, cell]. The seeds slot changes
## to the selected seed type at runtime.
const HOTBAR_ICONS := [
	[TOOL_ICONS, Vector2i(5, 0)],
	[TOOL_ICONS, Vector2i(6, 0)],
	[FOOD_ICONS, Vector2i(3, 4)],
	[TOOL_ICONS, Vector2i(4, 0)],
	[FENCE_ICONS, Vector2i(2, 0)],
	[LATE_ICONS, Vector2i(1, 0)],
]
const SLOT_SIZE := 20
const DAY_BAR_COLOR := Color(1.0, 0.82, 0.3)
const NIGHT_BAR_COLOR := Color(0.45, 0.55, 1.0)
## The clock and time bar pulse towards this colour just before night (Game.is_night_coming).
const WARNING_COLOR := Color(1.0, 0.35, 0.25)
const WARNING_PULSE_SPEED := 6.0

## The goal tracker was clicked (Main opens the inventory on its Goals page).
signal goals_requested
## The bag button next to the hotbar was clicked (Main toggles the inventory).
signal inventory_requested

var _root := Control.new()
var _clock_label := Label.new()
var _time_bar := ProgressBar.new()
var _bar_fill := StyleBoxFlat.new()
var _gold_label := Label.new()
var _seed_label := Label.new()
var _crop_label := Label.new()
var _hint_label := Label.new()
var _banner_label := Label.new()
var _slots: Array[Panel] = []
var _seed_icon: TextureRect  # icon in the seeds slot
var _seed_count := Label.new()  # seeds left of the selected type, in the seeds slot
var _fence_count := Label.new()  # fence pieces left, in the fence slot
var _sprinkler_count := Label.new()  # sprinklers in the bag, in the sprinkler slot
var _player: Player
var _restore_label := Label.new()  # "Farm 2/6" under the clock
var _goal_label := Label.new()  # "Next: Restore the Well 80/150g" under it
var _end_screen := ColorRect.new()
var _end_label := Label.new()
var _credits := Credits.new()
var _keep_button := UiStyle.make_button("Keep playing")


## The icon sheet a product's icon cell is in (see AnimalTypes.PRODUCTS).
static func product_sheet(product: Dictionary) -> Texture2D:
	return LATE_ICONS if product.get("sheet", "food") == "late" else FOOD_ICONS


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps working while the game is paused
	_root.size = SCREEN
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)
	_build_status()
	_build_counters()
	_build_hotbar()
	_build_messages()
	_build_end_screen()
	Game.stats_changed.connect(_refresh_counters)
	Game.farm_restored.connect(_on_farm_restored)
	Game.project_restored.connect(_on_project_restored)
	_refresh_counters()


func setup(player: Player) -> void:
	_player = player
	player.tool_changed.connect(_select_slot)
	player.seed_changed.connect(_on_seed_changed)
	_select_slot(player.tool)
	_on_seed_changed(player.seed_id)


func _process(_delta: float) -> void:
	var phase := "Night" if Game.is_night else "Day"
	_clock_label.text = "Day %d  %s" % [Game.day, phase]
	_time_bar.value = 1.0 - Game.phase_progress()
	_bar_fill.bg_color = NIGHT_BAR_COLOR if Game.is_night else DAY_BAR_COLOR
	_pulse_clock()
	# The first-day tips box sits in the same corner, so the tracker waits until it is gone.
	_goal_label.visible = Tutorial.is_finished


func set_hint(text: String) -> void:
	if _hint_label.text != text:
		_hint_label.text = text


func show_banner(text: String) -> void:
	_banner_label.text = text
	_banner_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(1.8)
	tween.tween_property(_banner_label, "modulate:a", 0.0, 0.8)


func _pulse_clock() -> void:
	var warning := 0.0
	if Game.is_night_coming():
		warning = absf(sin(Time.get_ticks_msec() / 1000.0 * WARNING_PULSE_SPEED))
	var color := Color.WHITE.lerp(WARNING_COLOR, warning)
	_clock_label.modulate = color
	_time_bar.modulate = color


func _refresh_counters() -> void:
	_restore_label.text = "Farm %d/%d" % [Game.restored_count(), Restoration.PROJECTS.size()]
	_goal_label.text = FarmGoals.tracker_text(FarmGoals.build(Game.goal_state()))
	_gold_label.text = str(Game.gold)
	_seed_label.text = str(Game.total(Game.seeds))
	_crop_label.text = str(Game.bag_total())
	_fence_count.text = str(Game.fence_pieces)
	_sprinkler_count.text = str(Game.sprinkler_pieces)
	if _player != null:
		_seed_count.text = str(_player.held_count())


func _on_seed_changed(crop_id: String) -> void:
	if _player.sapling_id != "":
		_seed_icon.texture = _icon(Shop.FRUIT_ICONS, Vector2i(InventoryRows.FRUIT_CELLS[_player.sapling_id], 0))
	else:
		_seed_icon.texture = _icon(FOOD_ICONS, Crop.TYPES[crop_id]["seed_icon"])
	_refresh_counters()


func _select_slot(tool: Player.Tool) -> void:
	for i in _slots.size():
		var style := _slots[i].get_theme_stylebox("panel") as StyleBoxFlat
		style.border_color = Color(1.0, 0.85, 0.3) if i == tool else Color(0.1, 0.08, 0.06)


func _on_project_restored(id: String) -> void:
	_refresh_counters()
	show_banner("%s restored!" % Restoration.project(id)["name"])


## The last building is done: pause on the ending screen. "Keep playing" carries on.
func _on_farm_restored() -> void:
	get_tree().paused = true
	Audio.play_sfx("win")
	_end_label.text = "The farm is saved!\n\nImogen and Gayle have their home back.\nDay %d, %d gold" % [Game.day, Game.gold]
	_end_screen.visible = true
	_keep_button.grab_focus()


func _close_ending() -> void:
	_end_screen.visible = false
	get_tree().paused = false


# --- Building the UI --------------------------------------------------------

func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 8
	theme.set_color("font_outline_color", "Label", Color(0.1, 0.07, 0.05))
	theme.set_constant("outline_size", "Label", 3)
	return theme


func _build_status() -> void:
	_clock_label.position = Vector2(6, 4)
	_root.add_child(_clock_label)

	var bar_back := StyleBoxFlat.new()
	bar_back.bg_color = Color(0.1, 0.08, 0.06, 0.8)
	_bar_fill.bg_color = DAY_BAR_COLOR
	_time_bar.add_theme_stylebox_override("background", bar_back)
	_time_bar.add_theme_stylebox_override("fill", _bar_fill)
	_time_bar.show_percentage = false
	_time_bar.max_value = 1.0
	_time_bar.position = Vector2(6, 17)
	_time_bar.size = Vector2(80, 3)
	_root.add_child(_time_bar)
	_restore_label.position = Vector2(6, 22)
	_root.add_child(_restore_label)
	_goal_label.position = Vector2(6, 32)
	_goal_label.add_theme_color_override("font_color", UiStyle.HIGHLIGHT)
	_goal_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_goal_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_goal_label.gui_input.connect(_on_goal_input)
	_root.add_child(_goal_label)


func _build_counters() -> void:
	var rows := [
		[RESOURCE_ICONS, Vector2i(2, 2), _gold_label],
		[FOOD_ICONS, Vector2i(3, 4), _seed_label],
		[FOOD_ICONS, Vector2i(2, 4), _crop_label],
	]
	for i in rows.size():
		var icon := TextureRect.new()
		icon.texture = _icon(rows[i][0], rows[i][1])
		icon.position = Vector2(SCREEN.x - 50, 4 + i * 17)
		_root.add_child(icon)
		var label: Label = rows[i][2]
		label.position = Vector2(SCREEN.x - 32, 6 + i * 17)
		_root.add_child(label)


func _build_hotbar() -> void:
	var width := HOTBAR_ICONS.size() * (SLOT_SIZE + 2) - 2
	var start := Vector2((SCREEN.x - width) / 2.0, SCREEN.y - SLOT_SIZE - 4)
	for i in HOTBAR_ICONS.size():
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.15, 0.1, 0.75)
		style.set_border_width_all(1)
		var slot := Panel.new()
		slot.add_theme_stylebox_override("panel", style)
		slot.position = start + Vector2(i * (SLOT_SIZE + 2), 0)
		slot.size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		slot.gui_input.connect(_on_slot_input.bind(i))
		_root.add_child(slot)
		_slots.append(slot)

		var icon := TextureRect.new()
		icon.texture = _icon(HOTBAR_ICONS[i][0], HOTBAR_ICONS[i][1])
		icon.position = Vector2(2, 2)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE  # let the slot get the click
		slot.add_child(icon)
		var number := Label.new()
		number.text = str(i + 1)
		number.add_theme_font_size_override("font_size", 6)
		number.position = Vector2(1, -2)
		slot.add_child(number)
		if i == Player.Tool.SEEDS:
			_seed_icon = icon
			_add_slot_count(slot, _seed_count)
		elif i == Player.Tool.FENCE:
			_add_slot_count(slot, _fence_count)
		elif i == Player.Tool.SPRINKLER:
			_add_slot_count(slot, _sprinkler_count)
	_build_bag_button(start + Vector2(width + 4, 0))


## Small "Bag / Tab" button right of the hotbar: opens and closes the inventory.
func _build_bag_button(at: Vector2) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.15, 0.1, 0.75)
	style.set_border_width_all(1)
	style.border_color = Color(0.1, 0.08, 0.06)
	var button := Panel.new()
	button.add_theme_stylebox_override("panel", style)
	button.position = at
	button.size = Vector2(SLOT_SIZE, SLOT_SIZE)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.gui_input.connect(_on_bag_input.bind(button))
	_root.add_child(button)
	var label := Label.new()
	label.text = "Bag"
	label.add_theme_font_size_override("font_size", 6)
	label.position = Vector2(3, 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	var key := Label.new()
	key.text = "Tab"
	key.add_theme_font_size_override("font_size", 6)
	key.add_theme_color_override("font_color", UiStyle.HIGHLIGHT)
	key.position = Vector2(3, 8)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(key)


## Unlike the hotbar this works while the inventory has the game paused: it closes it again.
func _on_bag_input(event: InputEvent, button: Panel) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		button.accept_event()
		inventory_requested.emit()


## Left click on a hotbar slot selects that tool. The slot keeps the click,
## so the player doesn't also use the tool.
func _on_slot_input(event: InputEvent, index: int) -> void:
	if get_tree().paused or _player == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_player.choose_slot(index)
		_slots[index].accept_event()


func _on_goal_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_goal_label.accept_event()
		goals_requested.emit()


## Small number in the bottom-right corner of a hotbar slot.
func _add_slot_count(slot: Panel, label: Label) -> void:
	label.add_theme_font_size_override("font_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.position = Vector2(0, SLOT_SIZE - 11)
	label.size = Vector2(SLOT_SIZE - 1, 8)
	slot.add_child(label)


func _build_messages() -> void:
	_hint_label.position = Vector2(0, SCREEN.y - SLOT_SIZE - 18)
	_hint_label.size = Vector2(SCREEN.x, 12)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_hint_label)

	_banner_label.position = Vector2(0, 60)
	_banner_label.size = Vector2(SCREEN.x, 20)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", 14)
	_banner_label.modulate.a = 0.0
	_root.add_child(_banner_label)


func _build_end_screen() -> void:
	_end_screen.color = Color(0, 0, 0, 0.65)
	_end_screen.size = SCREEN
	_end_screen.visible = false
	_end_screen.theme = UiStyle.make_theme()
	_root.add_child(_end_screen)
	var column := UiStyle.make_centered_panel(_end_screen, 6)
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_label.add_theme_font_size_override("font_size", 12)
	column.add_child(_end_label)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	column.add_child(buttons)
	var credits_button := UiStyle.make_button("Credits")
	credits_button.pressed.connect(_credits.open)
	buttons.add_child(credits_button)
	_keep_button.pressed.connect(_close_ending)
	buttons.add_child(_keep_button)
	var to_title := UiStyle.make_button("Quit to Title")
	to_title.pressed.connect(Game.go_to_title)
	buttons.add_child(to_title)
	_credits.closed.connect(_keep_button.grab_focus)
	_end_screen.add_child(_credits)


func _icon(texture: Texture2D, cell: Vector2i) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(cell * 16, Vector2(16, 16))
	return atlas
