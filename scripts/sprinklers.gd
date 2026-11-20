class_name Sprinklers
extends Node
## Sprinklers the player places (late-game item). Every morning each one waters the 3x3 tiles
## around it, so a field next to a few sprinklers looks after itself. Addressed by tile cell like
## Fences. Slimes ignore them (they are never enemies or obstacles); only the hoe is blocked on
## their tile (farm.blocked). No Game/Audio calls in here, so the tests can run it headless.

## A sprinkler was placed or picked up. Co-op sends the new state to the joiners.
signal changed(cell: Vector2i)

const TILE := 16
const PRICE := 90
## Restoration project that has to be repaired before Azy sells sprinklers (the last one).
const REQUIRES := "greenhouse"
const RADIUS := 1  # 1 = 3x3
const TEXTURE := preload("res://assets/generated/late_game_icons.png")
const SPRITE_CELL := 2  # in late_game_icons.png
## The sprinkler's feet (y-sort point) inside its tile, same as fences and crops.
const FEET := Vector2(TILE / 2.0, TILE - 2.0)

## Placement rules (bounds, blocked, tilled) and the soil to water come from the farm. Set by Main.
var farm: Farm
## The y-sorted node sprinkler sprites are added to. Set by Main.
var sprinkler_parent: Node2D

var _sprites := {}  # Vector2i -> Sprite2D


## Why a sprinkler can't be bought right now, or "" when it can. `restored` is Game.restored.
static func block_reason(restored: Dictionary, gold: int) -> String:
	if not restored.has(REQUIRES):
		return "Restore the %s first." % String(Restoration.project(REQUIRES)["name"]).to_lower()
	if gold < PRICE:
		return "Not enough gold."
	return ""


## The tiles a sprinkler on `cell` waters (itself included).
static func area_cells(cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dy in range(-RADIUS, RADIUS + 1):
		for dx in range(-RADIUS, RADIUS + 1):
			cells.append(cell + Vector2i(dx, dy))
	return cells


func has_sprinkler(cell: Vector2i) -> bool:
	return _sprites.has(cell)


func count() -> int:
	return _sprites.size()


## Same rule as a fence: grass inside the farm area, not tilled, not a tree/stall/fence.
func can_place(cell: Vector2i) -> bool:
	return farm.can_till(cell)


func place(cell: Vector2i) -> bool:
	if not can_place(cell):
		return false
	_add(cell)
	return true


## Joiner: makes `cell` match the host's (a sprinkler there or not).
func apply_cell(cell: Vector2i, present: bool) -> void:
	if present and not has_sprinkler(cell):
		_add(cell)
	elif not present:
		remove(cell)


func _add(cell: Vector2i) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = TEXTURE
	sprite.region_enabled = true
	sprite.region_rect = Rect2(SPRITE_CELL * TILE, 0, TILE, TILE)
	sprite.centered = false
	sprite.offset = -FEET
	sprite.position = sprinkler_parent.to_local(Vector2(cell * TILE) + FEET)
	sprinkler_parent.add_child(sprite)
	_sprites[cell] = sprite
	farm.blocked[cell] = true
	changed.emit(cell)


## Picks the sprinkler back up. Returns false if there was none.
func remove(cell: Vector2i) -> bool:
	if not has_sprinkler(cell):
		return false
	(_sprites[cell] as Sprite2D).queue_free()
	_sprites.erase(cell)
	farm.blocked.erase(cell)
	changed.emit(cell)
	return true


## The morning watering: wets every dry tilled tile near a sprinkler. Returns how many it wet.
func water_all() -> int:
	var wetted := 0
	for cell: Vector2i in _sprites:
		for target in area_cells(cell):
			if farm.water(target):
				wetted += 1
	return wetted


func to_save() -> Dictionary:
	var cells := []
	for cell: Vector2i in _sprites:
		cells.append([cell.x, cell.y])
	return {"sprinklers": cells}


## Replaces all sprinklers with the saved ones (load the farm first: placing checks its rules).
func from_save(data: Dictionary) -> void:
	for cell: Vector2i in _sprites.keys():
		remove(cell)
	for entry: Variant in SaveUtil.list(data.get("sprinklers")):
		if SaveUtil.is_entry(entry, 2):
			place(Vector2i(int(entry[0]), int(entry[1])))
