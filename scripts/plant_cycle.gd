class_name PlantCycle
extends RefCounted
## What the Seeds tool can hold: seed types, then fruit tree saplings, only the ones you own.
## An item is a key like "seed:carrot" or "sapling:apple". Pure data so tests can check it.


static func key(kind: String, id: String) -> String:
	return "%s:%s" % [kind, id]


## Owned items in cycling order (crop order, then shop order for saplings).
static func choices(seeds: Dictionary, saplings: Dictionary) -> Array[String]:
	var items: Array[String] = []
	for crop_id: String in Crop.TYPES:
		if int(seeds.get(crop_id, 0)) > 0:
			items.append(key("seed", crop_id))
	for tree_id: String in Orchard.TYPES:
		if int(saplings.get(tree_id, 0)) > 0:
			items.append(key("sapling", tree_id))
	return items


## The owned item after `current` (wraps around). `current` may be one you no longer own.
## Returns `current` when there is nothing else to switch to.
static func next(current: String, seeds: Dictionary, saplings: Dictionary) -> String:
	var all: Array[String] = []
	for crop_id: String in Crop.TYPES:
		all.append(key("seed", crop_id))
	for tree_id: String in Orchard.TYPES:
		all.append(key("sapling", tree_id))
	var owned := choices(seeds, saplings)
	var start := all.find(current)
	for step in range(1, all.size() + 1):
		var candidate: String = all[(start + step) % all.size()]
		if candidate != current and owned.has(candidate):
			return candidate
	return current
