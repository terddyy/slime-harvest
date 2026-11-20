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


# --- World sync (what the host accepts from a joiner) ---------------------------------

## Game methods a joiner may ask the host to run -> what their one argument is ("" = none).
const GAME_CALLS := {
	"sell_crops": "", "buy_fences": "", "buy_sprinkler": "",
	"buy_seed": "crop", "buy_sapling": "tree", "buy_upgrade": "upgrade", "buy_animal": "animal", "restore": "project",
}
## A joiner's tool use or click must be this many tiles from where its farmer was last seen.
## (Player.TOOL_REACH is 2; the rest is slack for lag.)
const INTENT_REACH_TILES := 5


## Is `method(args)` something a joiner may ask for, with a known id? `upgrade_ids` is Game.UPGRADE_PRICES.keys().
static func game_call_ok(method: String, args: Array, upgrade_ids: Array) -> bool:
	if not GAME_CALLS.has(method):
		return false
	var kind: String = GAME_CALLS[method]
	if kind == "":
		return args.is_empty()
	if args.size() != 1 or not args[0] is String:
		return false
	var id: String = args[0]
	match kind:
		"crop":
			return Crop.TYPES.has(id)
		"tree":
			return Orchard.TYPES.has(id)
		"upgrade":
			return upgrade_ids.has(id)
		"animal":
			return AnimalTypes.TYPES.has(id)
		"project":
			return not Restoration.project(id).is_empty()
	return false


## Is `cell` close enough to the farmer standing at `farmer_pos`?
static func in_reach(farmer_pos: Vector2, cell: Vector2i) -> bool:
	var farmer_cell := Vector2i((farmer_pos / TILE).floor())
	var offset := (cell - farmer_cell).abs()
	return maxi(offset.x, offset.y) <= INTENT_REACH_TILES


## A joiner's "use my tool on that cell" is believable: a real tool slot, a known seed (or empty),
## a known sapling (or empty), a real facing and a cell near the farmer.
static func tool_intent_ok(tool: int, cell: Vector2i, facing: Vector2, seed_id: String, sapling_id: String, farmer_pos: Vector2, tool_count: int) -> bool:
	if tool < 0 or tool >= tool_count or not FACINGS.has(facing) or not farmer_pos.is_finite():
		return false
	if not Crop.TYPES.has(seed_id) or (sapling_id != "" and not Orchard.TYPES.has(sapling_id)):
		return false
	return in_reach(farmer_pos, cell)


## True when every id in `ids` is in `asleep` (id -> true). Nobody to wait for counts as not asleep.
static func all_asleep(ids: Array, asleep: Dictionary) -> bool:
	for id: int in ids:
		if not asleep.has(id):
			return false
	return not ids.is_empty()


## How many of `ids` are not in bed yet.
static func sleepers_missing(ids: Array, asleep: Dictionary) -> int:
	var missing := 0
	for id: int in ids:
		if not asleep.has(id):
			missing += 1
	return missing
