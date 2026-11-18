class_name Restoration
extends RefCounted
## The farm restoration goal: the buildings Imogen repairs with gold.
## Pure data + helpers (no nodes) so tests can check it. `Game.restored` holds the ids done.
## Costs are a first guess; ticket P1 balances them against income.

## One entry per project, in the order they show on the restoration board.
## "unlocks" is the text the board shows for what the repair gives you.
const PROJECTS: Array[Dictionary] = [
	{"id": "well", "name": "Well", "cost": 150, "unlocks": "Clean water near the field"},
	{"id": "farmhouse", "name": "Farmhouse", "cost": 300, "unlocks": "A home to sleep in"},
	{"id": "chicken_coop", "name": "Chicken coop", "cost": 450, "unlocks": "Chickens and eggs"},
	{"id": "barn", "name": "Barn", "cost": 800, "unlocks": "Cows and milk"},
	{"id": "windmill", "name": "Windmill", "cost": 1000, "unlocks": "Grinds the harvest into flour"},
	{"id": "greenhouse", "name": "Greenhouse", "cost": 1400, "unlocks": "Grow crops all year"},
]


## The project with this id, or an empty Dictionary when there is none.
static func project(id: String) -> Dictionary:
	for entry in PROJECTS:
		if entry["id"] == id:
			return entry
	return {}


static func ids() -> Array[String]:
	var result: Array[String] = []
	for entry in PROJECTS:
		result.append(entry["id"])
	return result


## Gold still missing for a project (0 when you can afford it or the id is unknown).
static func gold_short(id: String, gold: int) -> int:
	var entry := project(id)
	if entry.is_empty():
		return 0
	return maxi(0, int(entry["cost"]) - gold)


## The cheapest project not in `restored` yet, or "" when everything is restored.
static func cheapest_unrestored(restored: Dictionary) -> String:
	var best := ""
	for entry in PROJECTS:
		if restored.has(entry["id"]):
			continue
		if best == "" or int(entry["cost"]) < int(project(best)["cost"]):
			best = entry["id"]
	return best


## The cheapest unrestored project when `gold` pays for it, else "". Used for the "you can restore" banner.
static func affordable_next(restored: Dictionary, gold: int) -> String:
	var id := cheapest_unrestored(restored)
	if id != "" and gold_short(id, gold) == 0:
		return id
	return ""


static func total_cost() -> int:
	var sum := 0
	for entry in PROJECTS:
		sum += int(entry["cost"])
	return sum
