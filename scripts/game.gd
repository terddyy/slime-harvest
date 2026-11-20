extends Node
## Global game state (autoload "Game"): day/night clock, money, seeds and crops per type,
## upgrade levels, the restoration goal. Days never end: there is no win or lose state.
## Gameplay nodes read these values and listen to the signals; only this script changes them.

signal phase_changed(is_night: bool)
signal stats_changed
## A restoration project was paid for (see Restoration.PROJECTS).
signal project_restored(id: String)
## Emitted once, when the last project gets restored. The game keeps going afterwards.
signal farm_restored
## Emitted when crops were sold for gold (the tutorial listens for it).
signal crops_sold(earned: int)
## Imogen slept through to the next morning (the tutorial listens for it).
signal slept
## An animal was bought (the Herd spawns it).
signal animal_bought(id: String)

const DAY_LENGTH := 90.0
const NIGHT_LENGTH := 45.0
## In the last seconds of the day the HUD clock pulses and "Night is coming!" shows.
const NIGHT_WARNING_TIME := 10.0
## Crop prices and grow speeds live in Crop.TYPES (scripts/crop.gd).
const START_SEEDS := {"carrot": 6}
## Upgrade id -> price of each next level. The level is how many you bought (starts at 0).
##   sword: damage 1 -> 2 -> 3
##   can: waters 1 tile -> a row of 3 -> a 3x3 square
const UPGRADE_PRICES := {
	"sword": [50, 120],
	"can": [60, 150],
}
## Fence pieces (see scripts/fences.gd) are sold in bundles.
const START_FENCES := 3
const FENCE_BUNDLE := 5
const FENCE_BUNDLE_PRICE := 10
## A night is never saved: a save made at night resumes just before the next dusk.
const NIGHT_RESUME_TIME := 3.0
const TITLE_SCENE := "res://scenes/title.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const LOADING_SCENE := "res://scenes/loading.tscn"

## Action name -> keys. Registered in code so the bindings are easy to read in one place.
const KEY_BINDINGS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"use_tool": [KEY_SPACE, KEY_J],
	"interact": [KEY_E],
	"cycle_seed": [KEY_Q],
	"tool_1": [KEY_1],
	"tool_2": [KEY_2],
	"tool_3": [KEY_3],
	"tool_4": [KEY_4],
	"tool_5": [KEY_5],
	"restart": [KEY_R],
	"skip_phase": [KEY_N],
	"zoom_in": [KEY_EQUAL, KEY_KP_ADD],
	"zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT],
	"pause": [KEY_ESCAPE],
	"to_title": [KEY_T],
	"hide_tips": [KEY_F1],
	"goals": [KEY_G],
	"inventory": [KEY_TAB],
}

var day := 1
var is_night := false
var time_left := DAY_LENGTH
var gold := 0
var seeds: Dictionary = START_SEEDS.duplicate()  # crop id -> count
var crops_in_bag := {}  # crop id -> count
var fruit_in_bag := {}  # fruit tree id (Orchard.TYPES) -> count
var saplings := {}  # fruit tree id -> count, ready to plant in the orchard
var upgrades := {}  # upgrade id -> level bought
var fence_pieces := START_FENCES  # fences in the bag, ready to build
var restored := {}  # project id -> true, for every repaired building
var animals := {}  # animal id -> how many you own (see AnimalTypes)
var products_in_bag := {}  # product id (egg, milk) -> count, sold with the crops
var milestones := {}  # firsts for the farm goals (FarmGoals.MILESTONES) -> true


func _ready() -> void:
	_register_inputs()


func reset() -> void:
	day = 1
	is_night = false
	time_left = DAY_LENGTH
	gold = 0
	seeds = START_SEEDS.duplicate()
	crops_in_bag = {}
	fruit_in_bag = {}
	saplings = {}
	upgrades = {}
	fence_pieces = START_FENCES
	restored = {}
	animals = {}
	products_in_bag = {}
	milestones = {}


func _process(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		_next_phase()


func skip_phase() -> void:
	time_left = 0.0


## 0.0 at the start of the current day or night, 1.0 at its end.
func phase_progress() -> float:
	var length := NIGHT_LENGTH if is_night else DAY_LENGTH
	return clampf(1.0 - time_left / length, 0.0, 1.0)


## True in the last NIGHT_WARNING_TIME seconds of a day.
func is_night_coming() -> bool:
	return not is_night and time_left <= NIGHT_WARNING_TIME


func seed_count(crop_id: String) -> int:
	return seeds.get(crop_id, 0)


func crop_count(crop_id: String) -> int:
	return crops_in_bag.get(crop_id, 0)


## Adds up a "crop id -> count" dictionary, e.g. total(seeds).
func total(counts: Dictionary) -> int:
	var sum := 0
	for count: int in counts.values():
		sum += count
	return sum


func add_crop(crop_id: String) -> void:
	crops_in_bag[crop_id] = crop_count(crop_id) + 1
	mark("harvested")
	stats_changed.emit()


func add_fruit(tree_id: String, amount := 1) -> void:
	fruit_in_bag[tree_id] = fruit_in_bag.get(tree_id, 0) + amount
	stats_changed.emit()


## Crops, fruit and animal products in the bag together.
func bag_total() -> int:
	return total(crops_in_bag) + total(fruit_in_bag) + total(products_in_bag)


## Gold you would get for everything in the bag.
func bag_value() -> int:
	var value := 0
	for crop_id: String in crops_in_bag:
		value += crop_count(crop_id) * int(Crop.TYPES[crop_id]["sell_price"])
	for product_id: String in products_in_bag:
		value += int(products_in_bag[product_id]) * int(AnimalTypes.PRODUCTS[product_id]["sell_price"])
	for tree_id: String in fruit_in_bag:
		value += int(fruit_in_bag[tree_id]) * int(Orchard.TYPES[tree_id]["fruit_price"])
	return value


## Sells every crop and animal product in the bag. Returns the gold earned.
func sell_crops() -> int:
	var earned := bag_value()
	gold += earned
	crops_in_bag = {}
	products_in_bag = {}
	fruit_in_bag = {}
	if earned > 0:
		mark("sold")
	stats_changed.emit()
	if earned > 0:
		crops_sold.emit(earned)
	return earned


func animal_count(animal_id: String) -> int:
	return animals.get(animal_id, 0)


func add_product(product_id: String) -> void:
	products_in_bag[product_id] = int(products_in_bag.get(product_id, 0)) + 1
	stats_changed.emit()


## Buys an animal. Needs its building restored, room in the pen and the gold.
func buy_animal(animal_id: String) -> bool:
	if AnimalTypes.block_reason(animal_id, restored, animal_count(animal_id), gold) != "":
		return false
	gold -= int(AnimalTypes.TYPES[animal_id]["price"])
	animals[animal_id] = animal_count(animal_id) + 1
	stats_changed.emit()
	animal_bought.emit(animal_id)
	return true


func buy_seed(crop_id: String) -> bool:
	var price: int = Crop.TYPES[crop_id]["seed_price"]
	if gold < price:
		return false
	gold -= price
	seeds[crop_id] = seed_count(crop_id) + 1
	stats_changed.emit()
	return true


func buy_sapling(tree_id: String) -> bool:
	if not spend(int(Orchard.TYPES[tree_id]["sapling_price"])):
		return false
	saplings[tree_id] = sapling_count(tree_id) + 1
	stats_changed.emit()
	return true


func sapling_count(tree_id: String) -> int:
	return saplings.get(tree_id, 0)


## Takes one sapling of this type out of the bag to plant it.
func use_sapling(tree_id: String) -> bool:
	if sapling_count(tree_id) <= 0:
		return false
	saplings[tree_id] -= 1
	mark("fruit_tree")
	stats_changed.emit()
	return true


## The first tree id (shop order) you have a sapling for, or "".
func next_sapling() -> String:
	for tree_id: String in Orchard.TYPES:
		if sapling_count(tree_id) > 0:
			return tree_id
	return ""


func use_seed(crop_id: String) -> bool:
	if seed_count(crop_id) <= 0:
		return false
	seeds[crop_id] -= 1
	stats_changed.emit()
	return true


func upgrade_level(upgrade_id: String) -> int:
	return upgrades.get(upgrade_id, 0)


## Price of the next level, or -1 when the upgrade is maxed out.
func upgrade_price(upgrade_id: String) -> int:
	var prices: Array = UPGRADE_PRICES[upgrade_id]
	var level := upgrade_level(upgrade_id)
	return prices[level] if level < prices.size() else -1


func buy_upgrade(upgrade_id: String) -> bool:
	var price := upgrade_price(upgrade_id)
	if price < 0 or gold < price:
		return false
	gold -= price
	upgrades[upgrade_id] = upgrade_level(upgrade_id) + 1
	stats_changed.emit()
	return true


## Pays `amount` gold if you have enough. For one-off purchases.
func spend(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	stats_changed.emit()
	return true


## Buys FENCE_BUNDLE fence pieces for FENCE_BUNDLE_PRICE.
func buy_fences() -> bool:
	if gold < FENCE_BUNDLE_PRICE:
		return false
	gold -= FENCE_BUNDLE_PRICE
	fence_pieces += FENCE_BUNDLE
	stats_changed.emit()
	return true


## Takes one fence piece out of the bag to build it.
func use_fence() -> bool:
	if fence_pieces <= 0:
		return false
	fence_pieces -= 1
	mark("fenced")
	stats_changed.emit()
	return true


## A fence was picked back up.
func return_fence() -> void:
	fence_pieces += 1
	stats_changed.emit()


func add_gold(amount: int) -> void:
	gold += amount
	stats_changed.emit()


func is_restored(id: String) -> bool:
	return restored.has(id)


func restored_count() -> int:
	return restored.size()


## Remembers a first (FarmGoals.MILESTONES) for the farm goals; goals stay ticked afterwards.
func mark(milestone: String) -> void:
	if milestones.has(milestone):
		return
	milestones[milestone] = true
	stats_changed.emit()


## What FarmGoals.build() needs to know.
func goal_state() -> Dictionary:
	return {
		"gold": gold,
		"restored": restored,
		"chickens": animal_count("chicken"),
		"cows": animal_count("cow"),
		"saplings": total(saplings),
		"milestones": milestones,
	}


## What InventoryRows needs to know.
func inventory_state() -> Dictionary:
	return {
		"gold": gold,
		"seeds": seeds,
		"saplings": saplings,
		"fences": fence_pieces,
		"crops": crops_in_bag,
		"fruit": fruit_in_bag,
		"products": products_in_bag,
	}


func all_restored() -> bool:
	return restored.size() >= Restoration.PROJECTS.size()


## Pays for a project. False if the id is unknown, it is already done or you can't afford it.
func restore(id: String) -> bool:
	var project := Restoration.project(id)
	if project.is_empty() or is_restored(id) or not spend(int(project["cost"])):
		return false
	restored[id] = true
	project_restored.emit(id)
	if all_restored():
		farm_restored.emit()
	return true


func to_save() -> Dictionary:
	return {
		"day": day,
		"time_left": NIGHT_RESUME_TIME if is_night else time_left,
		"gold": gold,
		"seeds": seeds.duplicate(),
		"crops_in_bag": crops_in_bag.duplicate(),
		"fruit_in_bag": fruit_in_bag.duplicate(),
		"saplings": saplings.duplicate(),
		"upgrades": upgrades.duplicate(),
		"fence_pieces": fence_pieces,
		"restored": restored.keys(),
		"animals": animals.duplicate(),
		"products_in_bag": products_in_bag.duplicate(),
		"milestones": milestones.keys(),
	}


## Loads a saved game. Bad values fall back to the new-game ones. Never emits
## farm_restored, so loading a finished farm doesn't show the ending again.
func from_save(data: Dictionary) -> void:
	reset()
	day = maxi(1, int(SaveUtil.number(data, "day", 1)))
	time_left = clampf(SaveUtil.number(data, "time_left", DAY_LENGTH), 1.0, DAY_LENGTH)
	gold = maxi(0, int(SaveUtil.number(data, "gold", 0)))
	seeds = SaveUtil.counts(data.get("seeds"), Crop.TYPES.keys())
	crops_in_bag = SaveUtil.counts(data.get("crops_in_bag"), Crop.TYPES.keys())
	fruit_in_bag = SaveUtil.counts(data.get("fruit_in_bag"), Orchard.TYPES.keys())
	saplings = SaveUtil.counts(data.get("saplings"), Orchard.TYPES.keys())
	var levels := SaveUtil.counts(data.get("upgrades"), UPGRADE_PRICES.keys())
	for id: String in levels:
		upgrades[id] = mini(levels[id], UPGRADE_PRICES[id].size())
	fence_pieces = maxi(0, int(SaveUtil.number(data, "fence_pieces", START_FENCES)))
	for id: Variant in SaveUtil.list(data.get("restored")):
		if id is String and not Restoration.project(id).is_empty():
			restored[id] = true
	animals = SaveUtil.counts(data.get("animals"), AnimalTypes.ids())
	for id: String in animals:
		animals[id] = mini(animals[id], int(AnimalTypes.TYPES[id]["max"]))
	products_in_bag = SaveUtil.counts(data.get("products_in_bag"), AnimalTypes.product_ids())
	_load_milestones(data)
	stats_changed.emit()


## Saves from before the farm goals have no list: anyone who restored something has
## harvested and sold, and slept once the farmhouse is back and a day has passed.
func _load_milestones(data: Dictionary) -> void:
	for id: Variant in SaveUtil.list(data.get("milestones")):
		if id is String and FarmGoals.MILESTONES.has(id):
			milestones[id] = true
	if data.has("milestones"):
		return
	if not restored.is_empty() or not animals.is_empty():
		milestones["harvested"] = true
		milestones["sold"] = true
	if restored.has("farmhouse") and day > 1:
		milestones["slept"] = true


## Starts a fresh run (used by the title screen and pause menu).
func start_new_game() -> void:
	reset()
	enter_farm()


## Title / restart -> farm, through the loading screen (it loads MAIN_SCENE on a thread).
func enter_farm() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(LOADING_SCENE)


func go_to_title() -> void:
	reset()
	get_tree().paused = false
	get_tree().change_scene_to_file(TITLE_SCENE)


## Sleeping: skips whatever is left of the day / night and starts the next morning.
func sleep_to_morning() -> void:
	day += 1
	is_night = false
	time_left = DAY_LENGTH
	mark("slept")
	phase_changed.emit(false)
	slept.emit()


func _next_phase() -> void:
	if is_night:
		day += 1
		is_night = false
		time_left = DAY_LENGTH
	else:
		is_night = true
		time_left = NIGHT_LENGTH
	phase_changed.emit(is_night)


func _register_inputs() -> void:
	for action: String in KEY_BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: int in KEY_BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key as Key
			InputMap.action_add_event(action, event)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("use_tool", click)
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("interact", right_click)
