class_name InventoryRows
extends RefCounted
## What the inventory panel lists, as pure data (no nodes, no Game) so tests can check it.
## Game.inventory_state() gives the snapshot. A row is
## {kind, id, name, count, sheet, cell, each}: `sheet` says which icon sheet `cell` is in
## ("food", "fruit", "fence" or "late"), `each` is the sell price of one (0 for backpack rows).

## Cells of Fruit_Trees_Fruit_Objects.png by fruit tree id (sapling and fruit icons).
const FRUIT_CELLS := {"apple": 1, "pear": 2, "peach": 3, "cherry": 4}
const FENCE_CELL := Vector2i(2, 0)  # in Fences.png
const SPRINKLER_CELL := Vector2i(1, 0)  # in late_game_icons.png (sheet "late")


## Things you use: seeds per crop type, saplings per tree type, fence pieces. Empty ones are left out.
static func backpack(state: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var seeds: Dictionary = state.get("seeds", {})
	for crop_id: String in Crop.TYPES:
		var count := int(seeds.get(crop_id, 0))
		if count > 0:
			var cell: Vector2i = Crop.TYPES[crop_id]["seed_icon"]
			rows.append(_row("seed", crop_id, "%s seeds" % Crop.TYPES[crop_id]["name"], count, "food", cell, 0))
	var saplings: Dictionary = state.get("saplings", {})
	for tree_id: String in Orchard.TYPES:
		var count := int(saplings.get(tree_id, 0))
		if count > 0:
			var cell := Vector2i(FRUIT_CELLS[tree_id], 0)
			rows.append(_row("sapling", tree_id, "%s sapling" % Orchard.TYPES[tree_id]["name"], count, "fruit", cell, 0))
	var fences := int(state.get("fences", 0))
	if fences > 0:
		rows.append(_row("fence", "fence", "Fence pieces", fences, "fence", FENCE_CELL, 0))
	var sprinklers := int(state.get("sprinklers", 0))
	if sprinklers > 0:
		rows.append(_row("sprinkler", "sprinkler", "Sprinklers", sprinklers, "late", SPRINKLER_CELL, 0))
	return rows


## Things you sell at the stall: crops, fruit, eggs and milk with their price each.
static func storage(state: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var crops: Dictionary = state.get("crops", {})
	for crop_id: String in Crop.TYPES:
		var count := int(crops.get(crop_id, 0))
		if count > 0:
			var data: Dictionary = Crop.TYPES[crop_id]
			rows.append(_row("crop", crop_id, data["name"], count, "food", data["icon"], int(data["sell_price"])))
	var fruit: Dictionary = state.get("fruit", {})
	for tree_id: String in Orchard.TYPES:
		var count := int(fruit.get(tree_id, 0))
		if count > 0:
			var data: Dictionary = Orchard.TYPES[tree_id]
			rows.append(_row("fruit", tree_id, data["name"], count, "fruit", Vector2i(FRUIT_CELLS[tree_id], 0), int(data["fruit_price"])))
	var products: Dictionary = state.get("products", {})
	for product_id: String in AnimalTypes.PRODUCTS:
		var count := int(products.get(product_id, 0))
		if count > 0:
			var data: Dictionary = AnimalTypes.PRODUCTS[product_id]
			rows.append(_row("product", product_id, data["name"], count, String(data.get("sheet", "food")), data["icon"], int(data["sell_price"])))
	return rows


## Gold for selling every storage row.
static func storage_total(rows: Array[Dictionary]) -> int:
	var total := 0
	for row in rows:
		total += int(row["count"]) * int(row["each"])
	return total


static func _row(kind: String, id: String, name: String, count: int, sheet: String, cell: Vector2i, each: int) -> Dictionary:
	return {"kind": kind, "id": id, "name": name, "count": count, "sheet": sheet, "cell": cell, "each": each}
