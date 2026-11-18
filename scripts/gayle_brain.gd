class_name GayleBrain
extends RefCounted
## Pure decisions for Gayle (no nodes, no autoloads, so they are easy to test).

## Gayle waters crops this many tiles away from her (and so from Imogen, who she follows).
const WATER_REACH := 4
## At night she only goes for slimes within this many pixels of Imogen when following,
## and of her own spot when told to stay.
const FIGHT_RANGE := 150.0
const STAY_FIGHT_RANGE := 40.0
const NO_CELL := Vector2i(-1, -1)
## Same as Slime.EAT_RANGE + 1 (not referenced: Slime needs the Audio autoload, which --script tests lack).
const EATING_DISTANCE := 7.0


## The tilled, dry cell with a crop that is closest to `world_pos` and within WATER_REACH
## tiles of `own_cell`. Returns NO_CELL when nothing needs water.
static func dry_crop_cell(farm: Farm, own_cell: Vector2i, world_pos: Vector2) -> Vector2i:
	var best := NO_CELL
	var best_distance := INF
	for dy in range(-WATER_REACH, WATER_REACH + 1):
		for dx in range(-WATER_REACH, WATER_REACH + 1):
			var cell := own_cell + Vector2i(dx, dy)
			if farm.get_crop(cell) == null or not farm.can_water(cell):
				continue
			var distance := farm.cell_center(cell).distance_squared_to(world_pos)
			if distance < best_distance:
				best = cell
				best_distance = distance
	return best


## True when `enemy` is standing at a crop (it is eating it).
static func is_eating(enemy: Node2D, farm: Farm) -> bool:
	var crop := farm.nearest_crop(enemy.global_position)
	return crop != null and crop.global_position.distance_to(enemy.global_position) <= EATING_DISTANCE


## The enemy eating a crop that is closest to `from`, within `max_distance` of `anchor`.
## Returns null when there is none.
static func eating_enemy(enemies: Array, farm: Farm, from: Vector2, anchor: Vector2, max_distance: float) -> Node2D:
	var best: Node2D = null
	var best_distance := INF
	for enemy: Node2D in enemies:
		if not is_eating(enemy, farm) or enemy.global_position.distance_to(anchor) > max_distance:
			continue
		var distance := enemy.global_position.distance_to(from)
		if distance < best_distance:
			best = enemy
			best_distance = distance
	return best
