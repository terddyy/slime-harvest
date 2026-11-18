class_name Farm
extends TileMapLayer
## Tilled soil, watering and crops. Everything is addressed by tile cell (Vector2i).

## Emitted after each successful action (used by the tutorial and the particle effects).
signal tilled(cell: Vector2i)
signal untilled(cell: Vector2i)
signal watered(cell: Vector2i)
signal planted(cell: Vector2i)
signal crop_ripened(cell: Vector2i)
signal harvested(cell: Vector2i)

const TILE := 16
const GROW_INTERVAL := 8.0
const DRY_SOURCE := 0
const WET_SOURCE := 1
const DRY_TEXTURE := preload("res://assets/cute_fantasy/Tiles/FarmLand/FarmLand_Tile.png")
const WET_TEXTURE := preload("res://assets/cute_fantasy/Tiles/FarmLand/FarmLand_Wet_Tile.png")

## Which tilled neighbours a cell has (N=1, E=2, S=4, W=8) -> atlas cell in FarmLand_Tile.png.
const AUTOTILE := {
	0: Vector2i(0, 0),
	4: Vector2i(0, 1), 5: Vector2i(0, 2), 1: Vector2i(0, 3),
	2: Vector2i(1, 3), 10: Vector2i(2, 3), 8: Vector2i(3, 3),
	6: Vector2i(1, 0), 14: Vector2i(2, 0), 12: Vector2i(3, 0),
	7: Vector2i(1, 1), 15: Vector2i(2, 1), 13: Vector2i(3, 1),
	3: Vector2i(1, 2), 11: Vector2i(2, 2), 9: Vector2i(3, 2),
}
const NEIGHBOURS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

## Cells outside this rect can't be tilled. Set by Main.
var bounds := Rect2i(0, 0, 0, 0)
## Cells with trees/buildings (Vector2i -> true). Set by Main.
var blocked := {}
## The y-sorted node crops are added to. Set by Main.
var crop_parent: Node2D

var _wet := {}  # Vector2i -> bool. Every tilled cell has an entry.
var _crops := {}  # Vector2i -> Crop
var _grow_timer := 0.0


func _ready() -> void:
	tile_set = _build_tile_set()


func _process(delta: float) -> void:
	_grow_timer += delta
	if _grow_timer < GROW_INTERVAL:
		return
	_grow_timer = 0.0
	grow_all()


func grow_all() -> void:
	for cell: Vector2i in _crops:
		var crop: Crop = _crops[cell]
		if crop.tick(_wet[cell]):
			_wet[cell] = false
			_paint(cell)
			if crop.is_ripe():
				crop_ripened.emit(cell)


func cell_at(world_pos: Vector2) -> Vector2i:
	return local_to_map(to_local(world_pos))


func cell_center(cell: Vector2i) -> Vector2:
	return to_global(map_to_local(cell))


func is_tilled(cell: Vector2i) -> bool:
	return _wet.has(cell)


func is_wet(cell: Vector2i) -> bool:
	return _wet.get(cell, false)


func get_crop(cell: Vector2i) -> Crop:
	return _crops.get(cell)


func can_till(cell: Vector2i) -> bool:
	return bounds.has_point(cell) and not blocked.has(cell) and not is_tilled(cell)


func can_water(cell: Vector2i) -> bool:
	return is_tilled(cell) and not is_wet(cell)


func can_plant(cell: Vector2i) -> bool:
	return is_tilled(cell) and not _crops.has(cell)


func till(cell: Vector2i) -> bool:
	if not can_till(cell):
		return false
	_wet[cell] = false
	_paint(cell)
	for dir in NEIGHBOURS:
		if is_tilled(cell + dir):
			_paint(cell + dir)
	tilled.emit(cell)
	return true


## Hoe on empty soil: back to grass. Soil with a crop is never changed.
func can_untill(cell: Vector2i) -> bool:
	return is_tilled(cell) and not _crops.has(cell)


func untill(cell: Vector2i) -> bool:
	if not can_untill(cell):
		return false
	_wet.erase(cell)
	erase_cell(cell)
	for dir in NEIGHBOURS:
		if is_tilled(cell + dir):
			_paint(cell + dir)
	untilled.emit(cell)
	return true


func water(cell: Vector2i) -> bool:
	if not can_water(cell):
		return false
	_wet[cell] = true
	_paint(cell)
	watered.emit(cell)
	return true


func plant(cell: Vector2i, crop_id := "carrot") -> bool:
	if not can_plant(cell):
		return false
	_spawn_crop(cell, crop_id)
	planted.emit(cell)
	return true


func harvest(cell: Vector2i) -> bool:
	var crop := get_crop(cell)
	if crop == null or not crop.is_ripe():
		return false
	remove_crop(cell)
	harvested.emit(cell)
	return true


func remove_crop(cell: Vector2i) -> void:
	var crop := get_crop(cell)
	if crop == null:
		return
	_crops.erase(cell)
	crop.queue_free()


## Cells that have a crop (for the sleep rule).
func crop_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.assign(_crops.keys())
	return cells


func crop_count() -> int:
	return _crops.size()


## The crop closest to world_pos, or null if nothing is planted.
func nearest_crop(world_pos: Vector2) -> Crop:
	var best: Crop = null
	var best_distance := INF
	for crop: Crop in _crops.values():
		var distance := crop.global_position.distance_squared_to(world_pos)
		if distance < best_distance:
			best = crop
			best_distance = distance
	return best


func to_save() -> Dictionary:
	var soil := []
	for cell: Vector2i in _wet:
		soil.append([cell.x, cell.y, 1 if _wet[cell] else 0])
	var plants := []
	for cell: Vector2i in _crops:
		plants.append([cell.x, cell.y, (_crops[cell] as Crop).to_save()])
	return {"soil": soil, "crops": plants}


## Replaces all soil and crops with the saved ones. Skips entries that are damaged,
## outside `bounds`, or crops that aren't on tilled soil. Emits no gameplay signals.
func from_save(data: Dictionary) -> void:
	for cell: Vector2i in _crops.keys():
		remove_crop(cell)
	for cell: Vector2i in _wet:
		erase_cell(cell)
	_wet.clear()
	_grow_timer = 0.0
	for entry: Variant in SaveUtil.list(data.get("soil")):
		if SaveUtil.is_entry(entry, 3):
			var cell := Vector2i(int(entry[0]), int(entry[1]))
			if bounds.has_point(cell) and not blocked.has(cell):
				_wet[cell] = int(entry[2]) == 1
	for cell: Vector2i in _wet:
		_paint(cell)
	for entry: Variant in SaveUtil.list(data.get("crops")):
		if not SaveUtil.is_entry(entry, 2) or entry.size() < 3 or not entry[2] is Dictionary:
			continue
		var cell := Vector2i(int(entry[0]), int(entry[1]))
		var crop_data: Dictionary = entry[2]
		if can_plant(cell) and Crop.TYPES.has(crop_data.get("id")):
			_spawn_crop(cell, crop_data["id"]).from_save(crop_data)


func _spawn_crop(cell: Vector2i, crop_id: String) -> Crop:
	var crop := Crop.new()
	crop.cell = cell
	crop.crop_id = crop_id
	crop.position = crop_parent.to_local(cell_center(cell)) + Vector2(0, TILE / 2.0 - 2.0)
	crop_parent.add_child(crop)
	_crops[cell] = crop
	return crop


## Atlas cell for a tilled cell, based on which neighbours are tilled.
func autotile_coords(cell: Vector2i) -> Vector2i:
	var mask := 0
	for i in NEIGHBOURS.size():
		if is_tilled(cell + NEIGHBOURS[i]):
			mask |= 1 << i
	return AUTOTILE[mask]


func _paint(cell: Vector2i) -> void:
	var source := WET_SOURCE if _wet[cell] else DRY_SOURCE
	set_cell(cell, source, autotile_coords(cell))


func _build_tile_set() -> TileSet:
	var soil_tiles := TileSet.new()
	soil_tiles.tile_size = Vector2i(TILE, TILE)
	for texture: Texture2D in [DRY_TEXTURE, WET_TEXTURE]:
		var source := TileSetAtlasSource.new()
		source.texture = texture
		source.texture_region_size = Vector2i(TILE, TILE)
		for coords: Vector2i in AUTOTILE.values():
			source.create_tile(coords)
		soil_tiles.add_source(source)
	return soil_tiles
