class_name WorldActions
extends Node
## What a tool, E or a click does to the farm, in one place. The player runs these directly
## (solo, or as the host); in online play the host also runs them for a joiner's request
## (CoopWorld), so the rules are the same for everybody.
## Every action returns a result Dictionary and plays nothing itself: {"sfx", "variation"} for the
## sound, and for a pickup also {"text", "pos", "color"} for the floating "+1 carrot".
## An empty Dictionary means nothing happened.

const CROP_COLOR := Color(1, 0.7, 0.3)
const PRODUCT_COLOR := Color(1, 0.95, 0.6)

## Set by Main.
var farm: Farm
var fences: Fences
var sprinklers: Sprinklers
var orchard: Orchard
var herd: Herd


## The tiles the watering can wets when aimed at `cell`: level 0 just that tile, level 1 a row of 3
## across the facing direction, level 2 a 3x3 square that starts at `cell`.
static func water_area(cell: Vector2i, facing: Vector2, can_level: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [cell]
	if can_level == 0:
		return cells
	var ahead := Vector2i(facing)
	var side := Vector2i(ahead.y, ahead.x)
	var depth := 3 if can_level >= 2 else 1
	cells.clear()
	for d in depth:
		for s in range(-1, 2):
			cells.append(cell + ahead * d + side * s)
	return cells


## The selected tool hits `cell` (the sword swings from `origin`). `untill` is the hoe's mode for this hold.
func use_tool(tool: Player.Tool, cell: Vector2i, untill: bool, facing: Vector2, seed_id: String, sapling_id: String, origin: Vector2) -> Dictionary:
	match tool:
		Player.Tool.HOE:
			return _result("till" if (farm.untill(cell) if untill else farm.till(cell)) else "error", 0.1)
		Player.Tool.WATER:
			var watered := false
			for target in water_area(cell, facing, Game.upgrade_level("can")):
				watered = farm.water(target) or watered
			return _result("water" if watered else "error", 0.1)
		Player.Tool.SEEDS:
			return _plant_sapling(cell, sapling_id) if sapling_id != "" else _plant_seed(cell, seed_id)
		Player.Tool.SWORD:
			return _swing_sword(origin, facing)
		Player.Tool.FENCE:
			return _use_fence(cell)
		Player.Tool.SPRINKLER:
			return _use_sprinkler(cell)
	return {}


## Picks a ripe crop. Empty when there is none.
func harvest(cell: Vector2i) -> Dictionary:
	var crop := farm.get_crop(cell)
	if crop == null or not farm.harvest(cell):
		return {}
	Game.add_crop(crop.crop_id)
	var result := _result("harvest", 0.05)
	result["text"] = "+1 " + String(Crop.TYPES[crop.crop_id]["name"]).to_lower()
	result["pos"] = farm.cell_center(cell)
	result["color"] = CROP_COLOR
	return result


## E away from the stall, board, door and Gayle: collect from an animal, pick fruit, plant a
## sapling or harvest. `sapling_id` is the sapling E would plant ("" = none). `farmer_pos` is who pressed E.
## A collected product comes back as {"herd": true} (Herd already played its sound and popup).
func interact(cell: Vector2i, farmer_pos: Vector2, sapling_id: String) -> Dictionary:
	if herd.collect_near(farmer_pos):
		return {"herd": true}
	if orchard.has_fruit(cell):
		var tree_id := orchard.harvest(cell)
		Game.add_fruit(tree_id, Orchard.FRUIT_PER_TREE)
		var result := _result("harvest", 0.05)
		result["text"] = "+%d %s" % [Orchard.FRUIT_PER_TREE, String(Orchard.TYPES[tree_id]["name"]).to_lower()]
		result["pos"] = Vector2(cell * Farm.TILE) + Vector2(Farm.TILE / 2.0, Farm.TILE)
		result["color"] = CROP_COLOR
		return result
	if sapling_id != "" and Game.sapling_count(sapling_id) > 0 and orchard.can_plant(cell):
		orchard.plant(cell, sapling_id)
		Game.use_sapling(sapling_id)
		return _result("plant")
	return harvest(cell)


## The "+1 egg" result for the product Herd collected last (a joiner asked, so it needs the text).
func product_result() -> Dictionary:
	var result := _result("harvest", 0.05)
	result["text"] = "+1 " + String(AnimalTypes.PRODUCTS[herd.last_product]["name"]).to_lower()
	result["pos"] = herd.last_position
	result["color"] = PRODUCT_COLOR
	return result


func _plant_seed(cell: Vector2i, seed_id: String) -> Dictionary:
	if Game.seed_count(seed_id) > 0 and farm.plant(cell, seed_id):
		Game.use_seed(seed_id)
		return _result("plant", 0.1)
	return _result("error")


## Plants the sapling on `cell` if it is a free spot in the orchard.
func _plant_sapling(cell: Vector2i, sapling_id: String) -> Dictionary:
	if Game.sapling_count(sapling_id) > 0 and orchard.can_plant(cell) and orchard.plant(cell, sapling_id):
		Game.use_sapling(sapling_id)
		return _result("plant", 0.1)
	return _result("error")


## Builds a fence on `cell`, or picks up the fence that is already there.
func _use_fence(cell: Vector2i) -> Dictionary:
	if fences.remove(cell):
		Game.return_fence()
		return _result("harvest", 0.1)
	if Game.fence_pieces > 0 and fences.place(cell):
		Game.use_fence()
		return _result("till", 0.1)
	return _result("error")


## Places a sprinkler on `cell`, or picks up the one that is already there.
func _use_sprinkler(cell: Vector2i) -> Dictionary:
	if sprinklers.remove(cell):
		Game.return_sprinkler()
		return _result("harvest", 0.1)
	if Game.sprinkler_pieces > 0 and sprinklers.place(cell):
		Game.use_sprinkler()
		return _result("till", 0.1)
	return _result("error")


## Hits every slime in front of `origin`, or right next to it (the sword rules are in Player).
func _swing_sword(origin: Vector2, facing: Vector2) -> Dictionary:
	var body := origin + Vector2(0, -6)
	var damage := Player.SWORD_DAMAGE + Game.upgrade_level("sword")
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var to_enemy: Vector2 = enemy.body_center() - body
		var distance := to_enemy.length()
		var in_arc := distance <= Player.SWORD_RANGE and facing.dot(to_enemy.normalized()) >= Player.SWORD_ARC
		if distance <= Player.SWORD_HUG or in_arc:
			enemy.take_hit(damage, origin)
	return _result("sword_swing", 0.1)


func _result(sfx: String, variation := 0.0) -> Dictionary:
	return {"sfx": sfx, "variation": variation}
