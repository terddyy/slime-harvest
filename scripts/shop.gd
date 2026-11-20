class_name Shop
extends CanvasLayer
## Market stall shop: sell crops, buy seeds, buy upgrades. Main opens it with E at the stall.
## The game is paused while it is open. Arrow keys + Enter or the mouse pick an item;
## Esc or E closes it. Prices and upgrade rules live in Game and Crop.TYPES.

const SCREEN := Vector2(480, 270)
const ROW_SIZE := Vector2(172, 15)
const TOOL_ICONS := preload("res://assets/cute_fantasy/Icons/Outline/Tool_Icons_Outline.png")
const FOOD_ICONS := preload("res://assets/cute_fantasy/Icons/Outline/Food_Icons_Outline.png")
const RESOURCE_ICONS := preload("res://assets/cute_fantasy/Icons/Outline/Resources_Icons_Outline.png")
const FENCE_ICONS := preload("res://assets/cute_fantasy/Outdoor decoration/Fences.png")
const FENCE_ICON := Vector2i(2, 0)  # in Fences.png
const GOLD_ICON := Vector2i(2, 2)  # in Resources_Icons_Outline.png

const TEXT_COLOR := Color(1.0, 0.95, 0.85)
const DIM_COLOR := Color(0.62, 0.56, 0.5)
const GOLD_COLOR := Color(1.0, 0.85, 0.3)
const PANEL_COLOR := Color(0.22, 0.16, 0.11)
const BORDER_COLOR := Color(0.1, 0.07, 0.05)

## Upgrade id (see Game.UPGRADE_PRICES) -> [name, icon texture, icon cell]
const UPGRADES := {
	"sword": ["Sword", TOOL_ICONS, Vector2i(4, 0)],
	"can": ["Watering can", TOOL_ICONS, Vector2i(6, 0)],
}
## Fruit icons (16x16 cells of Fruit_Trees_Fruit_Objects.png) for the sapling rows, by tree id.
const FRUIT_ICONS := preload("res://assets/cute_fantasy/Crops/Fruit_Trees_Fruit_Objects.png")
const SAPLING_ICON_CELLS := InventoryRows.FRUIT_CELLS
const SAPLING_PREFIX := "sapling_"
const CAN_AREAS := ["1 tile", "row of 3", "3x3"]  # by watering can level

var _gold_label := Label.new()
var _info_label := Label.new()
var _buttons := {}  # item id -> Button
var _prices := {}  # item id -> Label on the right side of the button


func _ready() -> void:
	layer = 5  # above the HUD
	process_mode = Node.PROCESS_MODE_ALWAYS  # works while the game is paused
	visible = false
	_build()
	Game.stats_changed.connect(_refresh)


func open() -> void:
	visible = true
	get_tree().paused = true
	_refresh()
	(_buttons["sell"] as Button).grab_focus()


func close() -> void:
	visible = false
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		# Mark the key as used so Main doesn't reopen the shop with the same press.
		get_viewport().set_input_as_handled()
		close()


# --- Buying and selling -----------------------------------------------------

func _sell() -> void:
	var earned := Game.sell_crops()
	_info_label.text = "Sold for %dg!" % earned if earned > 0 else "Your bag is empty."
	Audio.play_sfx("sell" if earned > 0 else "error")


func _buy_seed(crop_id: String) -> void:
	if Game.buy_seed(crop_id):
		_info_label.text = "Bought 1 %s seed." % Crop.TYPES[crop_id]["name"]
		Audio.play_sfx("buy")
	else:
		_info_label.text = _seed_block_text(crop_id)
		Audio.play_sfx("error")


func _seed_block_text(crop_id: String) -> String:
	if not Crop.is_unlocked(crop_id, Game.restored):
		return "Needs the %s." % _requirement_name(crop_id)
	return "Not enough gold."


func _requirement_name(crop_id: String) -> String:
	return String(Restoration.project(Crop.TYPES[crop_id]["requires"])["name"]).to_lower()


func _buy_upgrade(upgrade_id: String) -> void:
	if Game.upgrade_price(upgrade_id) < 0:
		_info_label.text = "Already at the best level."
		Audio.play_sfx("error")
	elif Game.buy_upgrade(upgrade_id):
		_info_label.text = "Upgraded!"
		Audio.play_sfx("buy")
	else:
		_info_label.text = "Not enough gold."
		Audio.play_sfx("error")
	_refresh()


func _buy_sapling(tree_id: String) -> void:
	if Game.buy_sapling(tree_id):
		_info_label.text = "Bought a %s sapling. Equip it (3 / Q / Tab), then plant it in the orchard." % Orchard.TYPES[tree_id]["name"].to_lower()
		Audio.play_sfx("buy")
	else:
		_info_label.text = "Not enough gold."
		Audio.play_sfx("error")


func _buy_fences() -> void:
	if Game.buy_fences():
		_info_label.text = "Bought %d fences." % Game.FENCE_BUNDLE
		Audio.play_sfx("buy")
	else:
		_info_label.text = "Not enough gold."
		Audio.play_sfx("error")


func _buy_sprinkler() -> void:
	var blocked := Sprinklers.block_reason(Game.restored, Game.gold)
	if blocked == "" and Game.buy_sprinkler():
		_info_label.text = "Bought a sprinkler. Equip it (6 / Tab), then place it on the farm."
		Audio.play_sfx("buy")
	else:
		_info_label.text = blocked
		Audio.play_sfx("error")


func _buy_animal(animal_id: String) -> void:
	var blocked := AnimalTypes.block_reason(animal_id, Game.restored, Game.animal_count(animal_id), Game.gold)
	if blocked == "" and Game.buy_animal(animal_id):
		_info_label.text = "Bought a %s." % String(AnimalTypes.TYPES[animal_id]["name"]).to_lower()
		Audio.play_sfx("buy")
	else:
		_info_label.text = blocked
		Audio.play_sfx("error")


## The line under the buttons that explains the selected item.
func _describe(item: String) -> String:
	if item == "sell":
		return "Sell everything in your bag (%d items)." % Game.bag_total()
	if AnimalTypes.TYPES.has(item):
		var data: Dictionary = AnimalTypes.TYPES[item]
		var product: Dictionary = AnimalTypes.PRODUCTS[data["product"]]
		var building: String = Restoration.project(data["requires"])["name"]
		return "Gives 1 %s a day (%dg). Needs the %s." % [String(product["name"]).to_lower(), product["sell_price"], building.to_lower()]
	if Crop.TYPES.has(item):
		var data: Dictionary = Crop.TYPES[item]
		var seconds := int(data["grow_ticks"] * Farm.GROW_INTERVAL)
		if not Crop.is_unlocked(item, Game.restored):
			return "%s: sells for %dg. Needs the %s first." % [data["name"], data["sell_price"], _requirement_name(item)]
		return "%s: sells for %dg. Needs %d s of wet soil per stage." % [data["name"], data["sell_price"], seconds]
	if UPGRADES.has(item):
		var level := Game.upgrade_level(item)
		if Game.upgrade_price(item) < 0:
			return "%s is fully upgraded." % UPGRADES[item][0]
		return "%s: %s -> %s" % [UPGRADES[item][0], _upgrade_effect(item, level), _upgrade_effect(item, level + 1)]
	if item.begins_with(SAPLING_PREFIX):
		var data: Dictionary = Orchard.TYPES[item.trim_prefix(SAPLING_PREFIX)]
		return "%s tree: grows in %d days, then %d fruit every %d days (%dg each)." % [
			data["name"], Orchard.MATURE_DAYS, Orchard.FRUIT_PER_TREE, Orchard.FRUIT_DAYS, data["fruit_price"]]
	if item == "sprinkler":
		return "Waters the 3x3 tiles around it every morning (%dg). Needs the %s." % [
			Sprinklers.PRICE, String(Restoration.project(Sprinklers.REQUIRES)["name"]).to_lower()]
	if item == "fences":
		return "Slimes must chew through a fence (%d HP). Build with 5." % Fences.MAX_HP
	return "Esc or E also closes the shop."


## What an upgrade does at a level, e.g. "damage 2" or "row of 3".
func _upgrade_effect(upgrade_id: String, level: int) -> String:
	match upgrade_id:
		"sword":
			return "damage %d" % (Player.SWORD_DAMAGE + level)
		"can":
			return CAN_AREAS[level]
	return ""


func _refresh() -> void:
	_gold_label.text = str(Game.gold)
	var value := Game.bag_value()
	_set_row("sell", "Sell goods (%d)" % Game.bag_total(), "+%dg" % value, value > 0)
	for animal_id: String in AnimalTypes.TYPES:
		var data: Dictionary = AnimalTypes.TYPES[animal_id]
		var owned := Game.animal_count(animal_id)
		var open := AnimalTypes.block_reason(animal_id, Game.restored, owned, Game.gold) == ""
		var label := "%s (%d/%d)" % [data["name"], owned, data["max"]]
		_set_row(animal_id, label, "%dg" % int(data["price"]), open)
	for crop_id: String in Crop.TYPES:
		var data: Dictionary = Crop.TYPES[crop_id]
		var seed_price: int = data["seed_price"]
		_set_row(crop_id, "%s seeds x%d" % [data["name"], Game.seed_count(crop_id)], "%dg" % seed_price,
			Game.gold >= seed_price and Crop.is_unlocked(crop_id, Game.restored))
	for upgrade_id: String in UPGRADES:
		var price := Game.upgrade_price(upgrade_id)
		var label := "%s (%s)" % [UPGRADES[upgrade_id][0], _upgrade_effect(upgrade_id, Game.upgrade_level(upgrade_id))]
		if price < 0:
			_set_row(upgrade_id, label, "MAX", false)
		else:
			_set_row(upgrade_id, label, "%dg" % price, Game.gold >= price)
	for tree_id: String in Orchard.TYPES:
		var price: int = Orchard.TYPES[tree_id]["sapling_price"]
		_set_row(SAPLING_PREFIX + tree_id, "%s sapling x%d" % [Orchard.TYPES[tree_id]["name"], Game.sapling_count(tree_id)], "%dg" % price, Game.gold >= price)
	var can_sprinkle := Sprinklers.block_reason(Game.restored, Game.gold) == ""
	_set_row("sprinkler", "Sprinkler (have %d)" % Game.sprinkler_pieces, "%dg" % Sprinklers.PRICE, can_sprinkle)
	_set_row("fences", "%d fences (have %d)" % [Game.FENCE_BUNDLE, Game.fence_pieces], "%dg" % Game.FENCE_BUNDLE_PRICE, Game.gold >= Game.FENCE_BUNDLE_PRICE)


func _set_row(item: String, text: String, price: String, can_buy: bool) -> void:
	(_buttons[item] as Button).text = text
	var price_label: Label = _prices[item]
	price_label.text = price
	price_label.add_theme_color_override("font_color", GOLD_COLOR if can_buy else DIM_COLOR)


# --- Building the UI --------------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.size = SCREEN
	root.theme = _make_theme()
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.size = SCREEN
	root.add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(PANEL_COLOR, BORDER_COLOR, 2, 6))
	# Anchored to the screen centre and growing both ways = centred whatever its size.
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = "Market stall"
	title.add_theme_font_size_override("font_size", 12)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var gold_icon := TextureRect.new()
	gold_icon.texture = _icon(RESOURCE_ICONS, GOLD_ICON)
	header.add_child(gold_icon)
	_gold_label.add_theme_color_override("font_color", GOLD_COLOR)
	header.add_child(_gold_label)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 8)
	box.add_child(columns)
	var left := _add_column(columns, "Crops & seeds")
	var right := _add_column(columns, "Upgrades")

	_add_row(left, "sell", _icon(RESOURCE_ICONS, GOLD_ICON), _sell)
	for crop_id: String in Crop.TYPES:
		_add_row(left, crop_id, _icon(FOOD_ICONS, Crop.TYPES[crop_id]["seed_icon"]), _buy_seed.bind(crop_id))
	for upgrade_id: String in UPGRADES:
		var icon := _icon(UPGRADES[upgrade_id][1], UPGRADES[upgrade_id][2])
		_add_row(right, upgrade_id, icon, _buy_upgrade.bind(upgrade_id))
	_add_row(right, "fences", _icon(FENCE_ICONS, FENCE_ICON), _buy_fences)
	for animal_id: String in AnimalTypes.TYPES:
		var product: Dictionary = AnimalTypes.PRODUCTS[AnimalTypes.TYPES[animal_id]["product"]]
		_add_row(right, animal_id, _icon(Hud.product_sheet(product), product["icon"]), _buy_animal.bind(animal_id))
	_add_row(right, "sprinkler", _icon(Hud.LATE_ICONS, InventoryRows.SPRINKLER_CELL), _buy_sprinkler)
	for tree_id: String in Orchard.TYPES:
		_add_row(right, SAPLING_PREFIX + tree_id, _icon(FRUIT_ICONS, Vector2i(SAPLING_ICON_CELLS[tree_id], 0)), _buy_sapling.bind(tree_id))
	_add_row(right, "leave", null, close)
	(_buttons["leave"] as Button).text = "Leave"

	_info_label.custom_minimum_size = Vector2(0, 12)
	box.add_child(_info_label)
	var keys := Label.new()
	keys.text = "Arrows + Enter or click: buy      Esc / E: close"
	keys.add_theme_color_override("font_color", DIM_COLOR)
	keys.add_theme_font_size_override("font_size", 6)
	box.add_child(keys)


func _add_column(parent: Container, heading: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	parent.add_child(column)
	var label := Label.new()
	label.text = heading
	label.add_theme_color_override("font_color", DIM_COLOR)
	column.add_child(label)
	return column


## One shop item: a button with an icon and text, and the price on its right side.
func _add_row(column: VBoxContainer, item: String, icon: Texture2D, on_press: Callable) -> void:
	var button := Button.new()
	button.icon = icon
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = ROW_SIZE
	button.pressed.connect(on_press)
	button.focus_entered.connect(func() -> void: _info_label.text = _describe(item))
	button.mouse_entered.connect(button.grab_focus)  # mouse and keyboard share one highlight
	column.add_child(button)
	_buttons[item] = button

	var price := Label.new()
	price.set_anchors_preset(Control.PRESET_FULL_RECT)
	price.offset_right = -4
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(price)
	_prices[item] = price


func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 8
	theme.set_color("font_color", "Label", TEXT_COLOR)
	theme.set_color("font_outline_color", "Label", BORDER_COLOR)
	theme.set_constant("outline_size", "Label", 3)
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		theme.set_color(state, "Button", TEXT_COLOR)
	var normal := _box(Color(0.14, 0.1, 0.07, 0.9), BORDER_COLOR, 1, 2)
	var focus := _box(Color(0.32, 0.24, 0.15, 0.95), GOLD_COLOR, 1, 2)
	for style in [normal, focus]:
		style.content_margin_top = 0  # keeps rows at ROW_SIZE so the long seed list fits the screen
		style.content_margin_bottom = 0
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", focus)
	theme.set_stylebox("pressed", "Button", focus)
	theme.set_stylebox("focus", "Button", focus)
	return theme


func _box(fill: Color, border: Color, border_width: int, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_content_margin_all(margin)
	return style


func _icon(texture: Texture2D, cell: Vector2i) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(cell * 16, Vector2(16, 16))
	return atlas
