class_name CoopRules
extends RefCounted
## Pure rules for online co-op (no nodes, so they are unit tested): farmer colours, where a
## joiner starts, which parts of the host's save a joiner takes, and checking what a joiner
## says about itself before the host believes it.

const TILE := 16
## One shirt colour per slot (the room has at most 4 players; the host is slot 0).
const FARMER_TINTS: Array[Color] = [
	Color(1.0, 1.0, 1.0),
	Color(0.55, 0.75, 1.0),
	Color(1.0, 0.6, 0.6),
	Color(0.6, 1.0, 0.65),
]
## The host's own position and camera are not the joiner's: these save sections stay out of a snapshot.
const SNAPSHOT_SKIP := ["player", "camera"]
## Everywhere a farmer can be, including the farmhouse room that sits far off the map (Farmhouse.ROOM_ORIGIN).
const WORLD_BOUNDS := Rect2(0, 0, 4400, 1400)
const FACINGS: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
## Players closer to the screen centre than this are not pushed apart (see start_offset).
const START_SPACING := 20.0


## Room player ids are 1 (host), 2, 3, 4: the id decides the slot.
static func slot(id: int) -> int:
	return clampi(id - 1, 0, FARMER_TINTS.size() - 1)


static func tint(id: int) -> Color:
	return FARMER_TINTS[slot(id)]


## A joiner starts next to the host's start spot, one step further right for each slot.
static func start_offset(id: int) -> Vector2:
	return Vector2(START_SPACING * slot(id), 0)


## The snapshot without the host-only sections.
static func joiner_sections(sections: Dictionary) -> Dictionary:
	var kept := {}
	for key: String in sections:
		if not SNAPSHOT_SKIP.has(key):
			kept[key] = sections[key]
	return kept


## Snapshot text -> sections, or {} when the text is not a JSON object.
static func parse_snapshot(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {}
	return json.data


## A joiner's report of where it is: a position inside `bounds`, one of the four facings and a
## name from `anims` (Player.ANIMS.keys()). Anything else is replaced, so a bad packet can't move anybody off the map.
static func clean_state(position: Vector2, facing: Vector2, anim: String, bounds: Rect2, anims: Array) -> Dictionary:
	var safe_position := position
	if not is_finite(position.x) or not is_finite(position.y):
		safe_position = bounds.get_center()
	return {
		"position": safe_position.clamp(bounds.position, bounds.end),
		"facing": facing if FACINGS.has(facing) else Vector2.DOWN,
		"anim": anim if anims.has(anim) else "idle",
	}
