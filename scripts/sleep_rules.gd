class_name SleepRules
extends RefCounted
## Rules for sleeping through the night (pure logic, tested without the scene).
## Sleeping skips to the next morning. Every crop that is not enclosed by fences has
## EAT_CHANCE to be eaten by the slimes while you sleep.

const EAT_CHANCE := 0.3
## You can go to bed once this fraction of the day has passed, or at any time at night.
const SLEEP_FROM_DAY_PROGRESS := 0.5
const NEIGHBOURS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


static func can_sleep(is_night: bool, day_progress: float) -> bool:
	return is_night or day_progress >= SLEEP_FROM_DAY_PROGRESS


## True when a flood fill from `cell` can't reach the edge of `bounds` without crossing
## a fence. `has_fence` is a Callable(Vector2i) -> bool.
static func is_enclosed(cell: Vector2i, has_fence: Callable, bounds: Rect2i) -> bool:
	return _region_is_closed(cell, has_fence, bounds, {})


## The crops (cells) that get eaten. `rng` is passed in so tests can seed it.
static func eaten_crops(crop_cells: Array[Vector2i], has_fence: Callable, bounds: Rect2i, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var eaten: Array[Vector2i] = []
	var seen := {}  # cell -> bool (region closed), shared so each region is filled once
	for cell in crop_cells:
		if not seen.has(cell):
			_region_is_closed(cell, has_fence, bounds, seen)
		if not seen[cell] and rng.randf() < EAT_CHANCE:
			eaten.append(cell)
	return eaten


## Fills the region around `start` and stores its result for every cell in `seen`.
static func _region_is_closed(start: Vector2i, has_fence: Callable, bounds: Rect2i, seen: Dictionary) -> bool:
	var region: Array[Vector2i] = [start]
	var visited := {start: true}
	var closed := true
	var index := 0
	while index < region.size():
		var cell := region[index]
		index += 1
		for dir in NEIGHBOURS:
			var next := cell + dir
			if visited.has(next) or has_fence.call(next):
				continue
			if not bounds.has_point(next):
				closed = false
				continue
			visited[next] = true
			region.append(next)
	for cell in region:
		seen[cell] = closed
	return closed
