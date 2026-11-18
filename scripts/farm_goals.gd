class_name FarmGoals
extends RefCounted
## The farm goals: an ordered list of recommendations that leads the player through the whole
## restoration, like quests. Nothing here blocks or rewards anything.
## Pure logic (no nodes, no Game) so tests can check it: build() turns a state snapshot
## (Game.goal_state()) into the list. Goal = {id, text, progress, target, done, where}.
## "where" names a guide arrow target (see Main._guide_point), or "" for nowhere.

## One-off things that can't be derived from the current state, saved in Game.milestones.
const MILESTONES: Array[String] = ["harvested", "sold", "slept", "fruit_tree", "fenced"]

const SAVED_TEXT := "All goals done - the farm is saved!"


## The state keys read: gold, restored (id -> true), chickens, cows, saplings (in the bag),
## milestones (id -> true). Missing keys count as empty.
static func build(state: Dictionary) -> Array[Dictionary]:
	var gold := int(state.get("gold", 0))
	var restored: Dictionary = state.get("restored", {})
	var marks: Dictionary = state.get("milestones", {})
	var goals: Array[Dictionary] = []
	goals.append(_goal("harvest", "Plant and harvest a crop", int(marks.has("harvested")), 1, ""))
	goals.append(_goal("sell", "Sell your crops to Azy", int(marks.has("sold")), 1, "stall"))
	goals.append(_restore("well", restored, gold))
	goals.append(_restore("farmhouse", restored, gold))
	goals.append(_goal("sleep", "Sleep in the farmhouse", int(marks.has("slept")), 1, "house"))
	goals.append(_restore("chicken_coop", restored, gold))
	goals.append(_goal("chicken", "Buy a chicken from Azy", int(state.get("chickens", 0)), 1, "stall"))
	goals.append(_restore("barn", restored, gold))
	goals.append(_goal("cow", "Buy a cow from Azy", int(state.get("cows", 0)), 1, "stall"))
	# With a sapling in the bag the next step is the orchard; without one, Azy sells them.
	var has_sapling := int(state.get("saplings", 0)) > 0
	goals.append(_goal("orchard", "Plant a fruit sapling in the orchard" if has_sapling or marks.has("fruit_tree") else "Buy a fruit sapling from Azy",
			int(marks.has("fruit_tree")), 1, "orchard" if has_sapling else "stall"))
	goals.append(_goal("fence", "Build a fence around your crops", int(marks.has("fenced")), 1, ""))
	goals.append(_restore("windmill", restored, gold))
	goals.append(_restore("greenhouse", restored, gold))
	var total := Restoration.PROJECTS.size()
	var count := mini(restored.size(), total)
	goals.append(_goal("saved", "Farm saved!" if count >= total else "Save the farm %d/%d" % [count, total], count, total, ""))
	return goals


## The first goal not done yet, or an empty Dictionary when everything is done.
static func current(goals: Array[Dictionary]) -> Dictionary:
	for goal in goals:
		if not goal["done"]:
			return goal
	return {}


## The one line the HUD shows under the "Farm 0/6" counter.
static func tracker_text(goals: Array[Dictionary]) -> String:
	var goal := current(goals)
	return SAVED_TEXT if goal.is_empty() else "Next: " + String(goal["text"])


static func _goal(id: String, text: String, progress: int, target: int, where: String) -> Dictionary:
	return {"id": id, "text": text, "progress": mini(progress, target), "target": target,
			"done": progress >= target, "where": where}


## "Restore the Well 80/150g", or "- go to the board!" once the gold is there.
static func _restore(id: String, restored: Dictionary, gold: int) -> Dictionary:
	var project := Restoration.project(id)
	var cost := int(project["cost"])
	var text := "Restore the %s" % project["name"]
	var goal_id := "restore_" + id
	if restored.has(id):
		return _goal(goal_id, text, cost, cost, "")
	if gold >= cost:
		var ready := _goal(goal_id, text + " - go to the board!", cost, cost, "board")
		ready["done"] = false
		return ready
	return _goal(goal_id, "%s %d/%dg" % [text, gold, cost], gold, cost, "")
