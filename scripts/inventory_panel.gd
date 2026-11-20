class_name InventoryPanel
extends CanvasLayer
## The inventory: a panel that slides up above the hotbar. Tab (or the bag button next to the
## hotbar) toggles it, Left / Right or a click on a tab switches pages, Esc closes it.
##   Backpack = things you use (click seeds or fences to equip them)
##   Storage  = things you sell at Azy's stall, with their value
##   Goals    = the farm goals list (G opens it on this page)
## Pauses the game while open (like the shop); the music keeps playing.

enum Page { BACKPACK, STORAGE, GOALS }


const PAGE_NAMES := ["Backpack", "Storage", "Goals"]
const PANEL_SIZE := Vector2(320, 170)
## The panel's top edge when open: its bottom stays just above the hotbar (see Hud).
const OPEN_Y := UiStyle.SCREEN.y - 28.0 - 170.0
const SLIDE_TIME := 0.18
const EMPTY_TEXT := {
	Page.BACKPACK: "Nothing here yet - buy seeds at Azy's stall.",
	Page.STORAGE: "Nothing here yet - harvest crops to sell.",
}
const DIM_COLOR := Color(0.62, 0.56, 0.5)
const SHEETS := {
	"food": Hud.FOOD_ICONS,
	"fruit": Shop.FRUIT_ICONS,
	"fence": Hud.FENCE_ICONS,
	"late": Hud.LATE_ICONS,
}

var player: Player

var _page := Page.BACKPACK
var _is_open := false
var _tween: Tween
var _panel := PanelContainer.new()
var _tabs: Array[Button] = []
var _scroll := ScrollContainer.new()
var _pages: Array[Control] = []
var _backpack := VBoxContainer.new()
var _storage := VBoxContainer.new()
var _goals := GoalsList.new()
var _footer := UiStyle.make_label("", 8, UiStyle.HIGHLIGHT)


func _ready() -> void:
	layer = 5  # above the HUD
	process_mode = Node.PROCESS_MODE_ALWAYS  # works while the game is paused
	visible = false
	_build()


func is_open() -> bool:
	return _is_open


## Does nothing while something else (shop, board, pause menu...) has the game paused.
func open(page := Page.BACKPACK) -> void:
	if _is_open:
		show_page(page)
		return
	if Game.is_paused():
		return
	_is_open = true
	Game.set_ui_open(true)
	show_page(page)
	visible = true
	_slide_to(OPEN_Y)


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	Game.set_ui_open(false)
	_slide_to(UiStyle.SCREEN.y).finished.connect(_hide_if_closed)


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


## Opens on the Goals page (or closes if it is already showing). For G and the HUD tracker.
func toggle_goals() -> void:
	if _is_open and _page == Page.GOALS:
		close()
	else:
		open(Page.GOALS)


func show_page(page: Page) -> void:
	_page = page
	for i in _pages.size():
		_pages[i].visible = i == page
		_tabs[i].set_pressed_no_signal(i == page)
	_fill_backpack()
	_fill_storage()
	_footer.text = _footer_text()
	_scroll.scroll_vertical = 0
	if page == Page.GOALS:
		_goals.refresh()
		_scroll_to_current_goal.call_deferred()


## Tab is read in _input so a focused button can't swallow it as "next control".
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		if _is_open or not Game.is_paused():
			get_viewport().set_input_as_handled()
			toggle()
	elif _is_open and event.is_action_pressed("ui_left"):
		get_viewport().set_input_as_handled()
		show_page(((_page + Page.size() - 1) % Page.size()) as Page)
	elif _is_open and event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		show_page(((_page + 1) % Page.size()) as Page)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("goals"):
		if _is_open or not Game.is_paused():
			get_viewport().set_input_as_handled()
			toggle_goals()
	elif _is_open and event.is_action_pressed("ui_cancel"):
		# Marked as used so the Esc pause menu doesn't open on the same press.
		get_viewport().set_input_as_handled()
		close()


func _slide_to(y: float) -> Tween:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "position:y", y, SLIDE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return _tween


func _hide_if_closed() -> void:
	if not _is_open:
		visible = false


func _scroll_to_current_goal() -> void:
	var row := _goals.current_row()
	if row != null:
		_scroll.ensure_control_visible(row)


# --- Pages ------------------------------------------------------------------

func _fill_backpack() -> void:
	_clear(_backpack)
	var rows := InventoryRows.backpack(Game.inventory_state())
	if rows.is_empty():
		_backpack.add_child(UiStyle.make_label(EMPTY_TEXT[Page.BACKPACK], 8, DIM_COLOR))
		return
	_backpack.add_child(UiStyle.make_label("Click to equip", 6, DIM_COLOR))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 2)
	_backpack.add_child(grid)
	for row in rows:
		grid.add_child(_backpack_button(row))


func _backpack_button(row: Dictionary) -> Button:
	var button := Button.new()
	button.text = "%s  x%d" % [row["name"], row["count"]]
	button.icon = _icon(row)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(146, 18)
	button.add_theme_font_size_override("font_size", 8)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if _is_equipped(row):
		button.add_theme_color_override("font_color", UiStyle.HIGHLIGHT)
	button.pressed.connect(_on_backpack_pressed.bind(row))
	return button


func _is_equipped(row: Dictionary) -> bool:
	if player == null:
		return false
	match row["kind"]:
		"seed":
			return player.tool == Player.Tool.SEEDS and player.seed_id == row["id"]
		"fence":
			return player.tool == Player.Tool.FENCE
		"sprinkler":
			return player.tool == Player.Tool.SPRINKLER
		"sapling":
			return player.tool == Player.Tool.SEEDS and player.sapling_id == row["id"]
	return false


func _on_backpack_pressed(row: Dictionary) -> void:
	match row["kind"]:
		"seed":
			if player != null and player.equip_seed(row["id"]):
				close()
		"fence":
			if player != null:
				player.choose_slot(Player.Tool.FENCE)
				close()
		"sprinkler":
			if player != null:
				player.choose_slot(Player.Tool.SPRINKLER)
				close()
		"sapling":
			if player != null and player.equip_sapling(row["id"]):
				close()


func _fill_storage() -> void:
	_clear(_storage)
	var rows := InventoryRows.storage(Game.inventory_state())
	if rows.is_empty():
		_storage.add_child(UiStyle.make_label(EMPTY_TEXT[Page.STORAGE], 8, DIM_COLOR))
		return
	var grid := GridContainer.new()
	grid.columns = 8  # two entries side by side: icon, name, count, value
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 1)
	_storage.add_child(grid)
	for row in rows:
		var icon := TextureRect.new()
		icon.texture = _icon(row)
		grid.add_child(icon)
		grid.add_child(_cell_label(row["name"], 44, HORIZONTAL_ALIGNMENT_LEFT))
		grid.add_child(_cell_label("x%d" % row["count"], 20, HORIZONTAL_ALIGNMENT_RIGHT))
		grid.add_child(_cell_label("%dg" % (row["count"] * row["each"]), 30, HORIZONTAL_ALIGNMENT_RIGHT, UiStyle.HIGHLIGHT))
	if rows.size() % 2 == 1:
		for i in 4:
			grid.add_child(Control.new())  # fills the last half-row so the grid stays even


func _footer_text() -> String:
	match _page:
		Page.BACKPACK:
			return "Gold: %dg" % Game.gold
		Page.STORAGE:
			var total := InventoryRows.storage_total(InventoryRows.storage(Game.inventory_state()))
			return "Worth %dg - sell at Azy's stall" % total if total > 0 else "Nothing to sell yet"
	return "Just ideas - nothing is required"


func _cell_label(text: String, width: float, align: HorizontalAlignment, color := UiStyle.TEXT_COLOR) -> Label:
	var label := UiStyle.make_label(text, 8, color)
	label.custom_minimum_size.x = width
	label.horizontal_alignment = align
	return label


func _icon(row: Dictionary) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = SHEETS[row["sheet"]]
	atlas.region = Rect2(Vector2(row["cell"]) * 16.0, Vector2(16, 16))
	return atlas


func _clear(box: Control) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


# --- Building the UI --------------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.size = UiStyle.SCREEN
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiStyle.make_theme()
	add_child(root)

	_panel.custom_minimum_size = PANEL_SIZE
	_panel.size = PANEL_SIZE
	_panel.position = Vector2((UiStyle.SCREEN.x - PANEL_SIZE.x) / 2.0, UiStyle.SCREEN.y)
	root.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	_panel.add_child(column)

	var tab_row := HBoxContainer.new()
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_row.add_theme_constant_override("separation", 4)
	column.add_child(tab_row)
	var group := ButtonGroup.new()
	for i in PAGE_NAMES.size():
		var tab := Button.new()
		tab.text = PAGE_NAMES[i]
		tab.toggle_mode = true
		tab.button_group = group
		tab.focus_mode = Control.FOCUS_NONE
		tab.custom_minimum_size = Vector2(80, 16)
		tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tab.pressed.connect(show_page.bind(i))
		tab_row.add_child(tab)
		_tabs.append(tab)

	_scroll.custom_minimum_size = Vector2(PANEL_SIZE.x - 18, 100)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	var pages := VBoxContainer.new()
	_scroll.add_child(pages)
	for page: Control in [_backpack, _storage, _goals]:
		pages.add_child(page)
		_pages.append(page)

	column.add_child(_footer)
	column.add_child(UiStyle.make_label("Tab / Esc: close   Left / Right: switch page", 6, DIM_COLOR))
