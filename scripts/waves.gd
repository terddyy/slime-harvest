class_name Waves
extends RefCounted
## The night wave table: what spawns each night, how many, and how fast.
## Pure data + helpers (no nodes, no Game autoload) so tests/run_tests.gd can check it.

## Enemy kinds the Spawner knows how to make.
const KINDS: Array[String] = ["small", "medium", "big"]

## Seconds from nightfall to the first spawn.
const FIRST_DELAY := 2.0

## One entry per night (index 0 = night 1). "counts" = how many of each kind,
## "interval" = seconds between spawns. Nights past the table are built by `_scaled()`.
const NIGHTS := [
	{"counts": {"small": 4, "medium": 4}, "interval": 4.5},
	{"counts": {"small": 5, "medium": 5}, "interval": 3.6},
	{"counts": {"small": 4, "medium": 6, "big": 1}, "interval": 3.2},
	{"counts": {"small": 6, "medium": 6, "big": 2}, "interval": 2.6},
	{"counts": {"small": 6, "medium": 7, "big": 2}, "interval": 2.4},
	{"counts": {"small": 6, "medium": 8, "big": 3}, "interval": 2.1},
	{"counts": {"small": 8, "medium": 9, "big": 4}, "interval": 1.7},
]


## Past the table, the extra nights past the last one add enemies; the cap keeps it playable.
const MAX_EXTRA_NIGHTS := 20
## Seconds after FIRST_DELAY in which a scaled wave must finish spawning (night is 45 s).
const SPAWN_WINDOW := 34.0


## The wave for night 1, 2, 3, ... (endless: later nights are scaled from night 7).
static func wave(night: int) -> Dictionary:
	if night <= NIGHTS.size():
		return NIGHTS[maxi(night, 1) - 1]
	return _scaled(night)


## Night 7 plus: +1 small and +1 medium every 2 nights, +1 big every 2 nights.
## The spawn interval shrinks so every enemy still appears before dawn.
static func _scaled(night: int) -> Dictionary:
	var base: Dictionary = NIGHTS[NIGHTS.size() - 1]["counts"]
	var extra := mini(night - NIGHTS.size(), MAX_EXTRA_NIGHTS)
	var counts := {
		"small": base["small"] + extra / 2,
		"medium": base["medium"] + (extra + 1) / 2,
		"big": base["big"] + (extra + 1) / 2,
	}
	var total := 0
	for kind: String in counts:
		total += counts[kind]
	var interval := minf(NIGHTS[NIGHTS.size() - 1]["interval"], SPAWN_WINDOW / (total - 1))
	return {"counts": counts, "interval": interval}


static func interval(night: int) -> float:
	return wave(night)["interval"]


## Every enemy of the night in a random order, e.g. ["small", "big", "medium", ...].
static func build_queue(night: int) -> Array[String]:
	var queue: Array[String] = []
	var counts: Dictionary = wave(night)["counts"]
	for kind: String in counts:
		for i in counts[kind]:
			queue.append(kind)
	queue.shuffle()
	return queue
