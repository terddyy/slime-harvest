class_name GroundBuilder
extends RefCounted
## Paints the ground TileMapLayer from WorldLayout: grass with tufts, dirt paths, ponds.

const TILE := 16
const GRASS_PLAIN := preload("res://assets/cute_fantasy/Tiles/Grass/Grass_1_Middle.png")
const GRASS_TILES := preload("res://assets/cute_fantasy/Tiles/Grass/Grass_Tiles_1.png")
const WATER_TILES := preload("res://assets/cute_fantasy/Tiles/Water/Water_Tile_1.png")
const GRASS_TUFTS: Array[Vector2i] = [Vector2i(5, 9), Vector2i(6, 9), Vector2i(7, 9)]
## 3x3 block of dirt (with a grass border) in Grass_Tiles_1.png, top-left cell.
const DIRT_ORIGIN := Vector2i(0, 5)
## 3x3 block of pond (with a grass border) in Water_Tile_1.png starts at its top-left cell.
const WATER_ORIGIN := Vector2i.ZERO
const TUFT_CHANCE := 0.08
const GRASS_SEED := 7  # same map every run


static func build(ground: TileMapLayer) -> void:
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(TILE, TILE)
	var plain := _atlas(GRASS_PLAIN)
	plain.create_tile(Vector2i.ZERO)
	var plain_id := tiles.add_source(plain)
	var grass := _atlas(GRASS_TILES)
	for coords in GRASS_TUFTS:
		grass.create_tile(coords)
	for column in 3:
		for row in 3:
			grass.create_tile(DIRT_ORIGIN + Vector2i(column, row))
	var grass_id := tiles.add_source(grass)
	var water := _atlas(WATER_TILES)
	for column in 3:
		for row in 3:
			water.create_tile(WATER_ORIGIN + Vector2i(column, row))
	var water_id := tiles.add_source(water)
	ground.tile_set = tiles

	var rng := RandomNumberGenerator.new()
	rng.seed = GRASS_SEED
	for x in WorldLayout.MAP_SIZE.x:
		for y in WorldLayout.MAP_SIZE.y:
			var cell := Vector2i(x, y)
			# Always draw the random number so the tufts don't move when paths change.
			var is_tuft := rng.randf() < TUFT_CHANCE
			var tuft: Vector2i = GRASS_TUFTS[rng.randi() % GRASS_TUFTS.size()]
			if WorldLayout.is_water(cell):
				var water_cell := WorldLayout.edge_tile(cell, WorldLayout.is_water)
				ground.set_cell(cell, water_id, WATER_ORIGIN + water_cell)
			elif WorldLayout.is_path(cell):
				var dirt_cell := WorldLayout.edge_tile(cell, WorldLayout.is_path)
				ground.set_cell(cell, grass_id, DIRT_ORIGIN + dirt_cell)
			elif is_tuft:
				ground.set_cell(cell, grass_id, tuft)
			else:
				ground.set_cell(cell, plain_id, Vector2i.ZERO)


static func _atlas(texture: Texture2D) -> TileSetAtlasSource:
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE, TILE)
	return source
