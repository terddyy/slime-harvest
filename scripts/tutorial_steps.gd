class_name TutorialSteps
extends RefCounted
## The first-day tutorial as plain data plus a step counter, so it can be tested on its own.
## Each step ends with one event ("tilled", "watered", ...). Steps that send the player somewhere
## also name a "target" ("stall", "board", "gayle", "house") for the guide arrow (GuideArrow).
## Events that happen early are remembered: planting before watering still counts once the planting step comes up.
## Tutorial (tutorial.gd) shows the text and feeds the events in.

const STEPS := [
	{"event": "tilled", "text": "Press 1 for the hoe, face the grass and press Space to till it."},
	{"event": "watered", "text": "Press 2 for the watering can and press Space on the soil."},
	{"event": "planted", "text": "Press 3 for carrot seeds and press Space to plant one."},
	{"event": "ripened",
		"text": "Crops only grow on wet soil. Water again (2) each time it dries, until it's ripe."},
	{"event": "harvested", "text": "Your carrot is ripe and sparkling! Click it (or face it and press E) to harvest."},
	{"event": "sold", "target": "stall",
		"text": "Follow the yellow arrow to Azy at the market stall and press E to sell."},
	{"event": "board", "target": "board",
		"text": "Restore the farm: follow the arrow to the signpost by the farmhouse and press E."},
	{"event": "talked", "target": "gayle",
		"text": "Gayle waters crops and chases slimes. Stand next to her and press E to talk."},
	{"event": "slept", "target": "house",
		"text": "In the evening, go through the farmhouse door and press E at the bed to sleep until morning."},
]
## Shown after the last step, then the tips hide.
const NIGHT_TIP := "Night comes at the end of the day - slimes will try to eat your crops. Use the sword (4)!"
## Shown instead of the current step while it is night; the step comes back in the morning.
const NIGHT_NOW := "Night! Slimes want your crops. Press 4 for the sword, Space to swing."

## Index of the current step in STEPS. Equals STEPS.size() when every step is done.
var index := 0

var _seen := {}  # event -> true


## Records that `event` happened. Returns true if this moved the tutorial on.
func record(event: String) -> bool:
	_seen[event] = true
	var before := index
	while not is_done() and _seen.has(STEPS[index]["event"]):
		index += 1
	return index != before


func is_done() -> bool:
	return index >= STEPS.size()


## Where the current step sends the player ("" = nowhere in particular, or all done).
func target() -> String:
	return "" if is_done() else str(STEPS[index].get("target", ""))


func text() -> String:
	return NIGHT_TIP if is_done() else STEPS[index]["text"]
