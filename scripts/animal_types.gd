class_name AnimalTypes
extends RefCounted
## Farm animals and what they give, as pure data (no nodes) so tests can check it.
## Animal ids: chicken, cow, sheep. Product ids: egg, milk, wool. Each animal gives one product a day.
## Sheet layouts are in docs/ASSETS.md ("Animals").

const TYPES := {
	"chicken": {
		"name": "Chicken", "requires": "chicken_coop", "pen": &"pen_chickens",
		"price": 40, "max": 4, "product": "egg",
		"sheet": "res://assets/cute_fantasy/Animals/Chicken/Chicken_01.png",
		"feet": Vector2(16, 24), "faces_left": false, "speed": 14.0,
		"idle_row": 0, "idle_frames": 2, "walk_row": 1, "walk_frames": 6,
	},
	"cow": {
		"name": "Cow", "requires": "barn", "pen": &"pen_cows",
		"price": 120, "max": 3, "product": "milk",
		"sheet": "res://assets/cute_fantasy/Animals/Cow/Cow_01.png",
		"feet": Vector2(16, 27), "faces_left": true, "speed": 10.0,
		"idle_row": 0, "idle_frames": 2, "walk_row": 3, "walk_frames": 8,
	},
	# Late game: needs the last restored building. Shares the cows' pen.
	"sheep": {
		"name": "Sheep", "requires": "greenhouse", "pen": &"pen_cows",
		"price": 200, "max": 3, "product": "wool",
		"sheet": "res://assets/cute_fantasy/Animals/Sheep/Sheep_01.png",
		"feet": Vector2(16, 24), "faces_left": true, "speed": 11.0,
		"idle_row": 0, "idle_frames": 2, "walk_row": 3, "walk_frames": 8,
	},
}

## Product id -> name, sell price and icon cell. The icon is in Icons/Outline/Food_Icons_Outline.png,
## or in assets/generated/late_game_icons.png when "sheet" is "late" (see Hud.product_sheet).
const PRODUCTS := {
	"egg": {"name": "Egg", "sell_price": 6, "icon": Vector2i(6, 1)},
	"milk": {"name": "Milk", "sell_price": 18, "icon": Vector2i(7, 0)},
	"wool": {"name": "Wool", "sell_price": 30, "icon": Vector2i(0, 0), "sheet": "late"},
}


static func ids() -> Array:
	return TYPES.keys()


static func product_ids() -> Array:
	return PRODUCTS.keys()


## Why an animal can't be bought right now, or "" when it can. `restored` is Game.restored,
## `owned` how many of this animal you have.
static func block_reason(id: String, restored: Dictionary, owned: int, gold: int) -> String:
	if not TYPES.has(id):
		return "Unknown animal."
	var data: Dictionary = TYPES[id]
	if not restored.has(data["requires"]):
		var building: String = Restoration.project(data["requires"]).get("name", "building")
		return "Restore the %s first." % building.to_lower()
	if owned >= int(data["max"]):
		return "The pen is full."
	if gold < int(data["price"]):
		return "Not enough gold."
	return ""
