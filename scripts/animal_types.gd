class_name AnimalTypes
extends RefCounted
## Farm animals and what they give, as pure data (no nodes) so tests can check it.
## Animal ids: chicken, cow. Product ids: egg, milk. Each animal gives one product a day.
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
}

## Product id -> name, sell price and icon cell in Icons/Outline/Food_Icons_Outline.png.
const PRODUCTS := {
	"egg": {"name": "Egg", "sell_price": 6, "icon": Vector2i(6, 1)},
	"milk": {"name": "Milk", "sell_price": 18, "icon": Vector2i(7, 0)},
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
