class_name Fences
extends Node
## Fence pieces the player builds, addressed by tile cell (Vector2i), like Farm.
## The player walks through fences; slimes can't, they stop and chew (see Slime).
## Every fence has HP and disappears when it reaches 0.
## Fence cells are also put in farm.blocked so the hoe can't till under a fence.
## No Game/Audio calls in here, so the tests can run this script headless.

const TILE := 16
const MAX_HP := 8
const TEXTURE := preload("res://assets/cute_fantasy/Outdoor decoration/Fences.png")

## Which fenced neighbours a cell has (N=1, E=2, S=4, W=8) -> atlas cell in Fences.png
## (16x16 cells, see docs/ASSETS.md).
const AUTOTILE := {
	0: Vector2i(0, 3),
	4: Vector2i(0, 0), 5: Vector2i(0, 1), 1: Vector2i(0, 2),
	2: Vector2i(1, 0), 10: Vector2i(2, 0), 8: Vector2i(3, 0),
	6: Vector2i(1, 1), 14: Vector2i(2, 1), 12: Vector2i(3, 1),
	7: Vector2i(1, 2), 15: Vector2i(2, 2), 13: Vector2i(3, 2),
	3: Vector2i(1, 3), 11: Vector2i(2, 3), 9: Vector2i(3, 3),
}
const NEIGHBOURS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
## The fence's feet (y-sort point) inside its tile, same as crops and trees.
const FEET := Vector2(TILE / 2.0, TILE - 2.0)
const HIT_COLOR := Color(1.0, 0.55, 0.55)
const CHIP_COLOR := Color(0.55, 0.33, 0.2)

## Placement rules (bounds, blocked, tilled) come from the farm. Set by Main.
var farm: Farm
## The y-sorted node fence sprites are added to. Set by Main.
var fence_parent: Node2D

var _sprites := {}  # Vector2i -> Sprite2D
var _hp := {}  # Vector2i -> int


func cell_at(world_pos: Vector2) -> Vector2i:
	return Vector2i((world_pos / TILE).floor())


func has_fence(cell: Vector2i) -> bool:
	return _sprites.has(cell)


func hp_at(cell: Vector2i) -> int:
	return _hp.get(cell, 0)


func count() -> int:
	return _sprites.size()


## A fence fits on grass inside the farm area: not tilled, not a tree/stall, not a fence.
func can_place(cell: Vector2i) -> bool:
	return farm.can_till(cell)


## True when moving from `from` to `to` would step onto a fence tile.
## Leaving the tile you are standing on is always allowed (e.g. after a knockback).
func blocks(from: Vector2, to: Vector2) -> bool:
	var to_cell := cell_at(to)
	return to_cell != cell_at(from) and has_fence(to_cell)


func place(cell: Vector2i) -> bool:
	if not can_place(cell):
		return false
	var sprite := Sprite2D.new()
	sprite.texture = TEXTURE
	sprite.region_enabled = true
	sprite.centered = false
	sprite.offset = -FEET  # the 16x16 piece covers its tile exactly
	sprite.position = fence_parent.to_local(Vector2(cell * TILE) + FEET)
	fence_parent.add_child(sprite)
	_sprites[cell] = sprite
	_hp[cell] = MAX_HP
	farm.blocked[cell] = true
	_repaint_around(cell)
	return true


## Picks the fence back up (the player gets the piece back). Returns false if there was none.
func remove(cell: Vector2i) -> bool:
	if not has_fence(cell):
		return false
	(_sprites[cell] as Sprite2D).queue_free()
	_forget(cell)
	return true


## Hurts the fence on `cell`. Returns true when this broke it.
func damage(cell: Vector2i, amount: int) -> bool:
	if not has_fence(cell):
		return false
	_hp[cell] -= amount
	var sprite: Sprite2D = _sprites[cell]
	if _hp[cell] > 0:
		_flash(sprite)
		return false
	_burst_chips(sprite.position)
	sprite.queue_free()
	_forget(cell)
	return true


func to_save() -> Dictionary:
	var pieces := []
	for cell: Vector2i in _sprites:
		pieces.append([cell.x, cell.y, _hp[cell]])
	return {"fences": pieces}


## Replaces all fences with the saved ones (load the farm first: placing checks its rules).
func from_save(data: Dictionary) -> void:
	for cell: Vector2i in _sprites.keys():
		remove(cell)
	for entry: Variant in SaveUtil.list(data.get("fences")):
		if SaveUtil.is_entry(entry, 3):
			var cell := Vector2i(int(entry[0]), int(entry[1]))
			if place(cell):
				_hp[cell] = clampi(int(entry[2]), 1, MAX_HP)


## Atlas cell for a fence, based on which neighbours have fences.
func autotile_coords(cell: Vector2i) -> Vector2i:
	var mask := 0
	for i in NEIGHBOURS.size():
		if has_fence(cell + NEIGHBOURS[i]):
			mask |= 1 << i
	return AUTOTILE[mask]


func _forget(cell: Vector2i) -> void:
	_sprites.erase(cell)
	_hp.erase(cell)
	farm.blocked.erase(cell)
	_repaint_around(cell)


func _repaint_around(cell: Vector2i) -> void:
	for target: Vector2i in [cell, cell + Vector2i.UP, cell + Vector2i.RIGHT, cell + Vector2i.DOWN, cell + Vector2i.LEFT]:
		if has_fence(target):
			var sprite: Sprite2D = _sprites[target]
			sprite.region_rect = Rect2(Vector2(autotile_coords(target) * TILE), Vector2(TILE, TILE))


## Short red tint and wobble when a slime bites the fence.
func _flash(sprite: Sprite2D) -> void:
	sprite.modulate = HIT_COLOR
	sprite.rotation = 0.12
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "rotation", 0.0, 0.15)
	tween.parallel().tween_property(sprite, "modulate", Color.WHITE, 0.25)


## A puff of wood chips where a fence broke.
func _burst_chips(at: Vector2) -> void:
	var chips := CPUParticles2D.new()
	chips.position = at + Vector2(0, -6)
	chips.one_shot = true
	chips.explosiveness = 1.0
	chips.amount = 10
	chips.lifetime = 0.5
	chips.direction = Vector2.UP
	chips.spread = 80.0
	chips.initial_velocity_min = 25.0
	chips.initial_velocity_max = 55.0
	chips.gravity = Vector2(0, 160)
	chips.scale_amount_min = 1.0
	chips.scale_amount_max = 2.0
	chips.color = CHIP_COLOR
	fence_parent.add_child(chips)
	chips.emitting = true
	get_tree().create_timer(chips.lifetime + 0.2).timeout.connect(chips.queue_free)
