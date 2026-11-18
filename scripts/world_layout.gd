class_name WorldLayout
extends RefCounted
## The map described as data: size, named areas, ponds, dirt paths and where trees and
## rocks go. Main builds the world from this. Cells are Vector2i, areas are Rect2i.
## To add something to the map, add or change an entry here, not code in Main.
##
## Rough picture (80 x 50 cells, 1 cell = 16 px):
##   north row: barn | farmhouse + well | greenhouse | windmill, all facing the east-west road
##   west: cow pen and chicken coop + pen     centre: home field, south field
##   east: market stall (plaza road), east field, orchard in the south-east, pond in the south-west

const MAP_SIZE := Vector2i(80, 50)
## Cells you can till and build on (the map edge is a ring of trees).
const PLAY_AREA := Rect2i(2, 3, 76, 45)
const PLAYER_START := Vector2i(34, 25)
const STALL_CELL := Vector2i(50, 19)
## Cells around the stall the player can't walk into (x -1..1, y -2..0).
const STALL_FOOTPRINT := Rect2i(49, 17, 3, 3)
## The restoration board, a signpost just west of the farmhouse plot (see Buildings).
const BOARD_CELL := Vector2i(26, 13)

## Farming land. Tillable like everywhere else; the names are for tutorial text and Phase 2.
const FIELDS := {
	&"home_field": Rect2i(24, 18, 20, 14),
	&"south_field": Rect2i(24, 35, 20, 10),
	&"east_field": Rect2i(58, 18, 14, 12),
}

## Places that are built on or fenced in. Not tillable. Each Phase 2 ticket fills in its own:
## B1 the *_plot areas, B2 the farmhouse door (bottom middle of its plot), B3 the pens,
## B5 the orchard.
const PLOTS := {
	&"barn_plot": Rect2i(8, 6, 10, 8),
	&"farmhouse_plot": Rect2i(28, 6, 10, 8),
	&"well_plot": Rect2i(41, 10, 3, 3),
	&"greenhouse_plot": Rect2i(48, 6, 8, 8),
	&"windmill_plot": Rect2i(60, 6, 8, 8),
	&"coop_plot": Rect2i(6, 26, 6, 5),
	&"pen_cows": Rect2i(6, 17, 14, 7),
	&"pen_chickens": Rect2i(13, 26, 8, 6),
	&"orchard": Rect2i(47, 34, 16, 10),
}

## Water. Plain rectangles (the water tileset has a rounded 3x3 rectangle). Not walkable.
const PONDS: Array[Rect2i] = [Rect2i(10, 36, 10, 8)]

## Dirt paths, all joined to the main east-west road along the top of the fields.
const PATHS: Array[Rect2i] = [
	Rect2i(8, 14, 60, 2),   # main road, under the buildings
	Rect2i(22, 16, 2, 28),  # west road down the left of the fields
	Rect2i(44, 16, 2, 28),  # east road down the right of the fields, towards the orchard
	Rect2i(46, 20, 10, 2),  # plaza in front of the stall
	Rect2i(53, 16, 2, 4),   # road to the plaza
]

const ROCK_COUNT := 14
const TREE_COUNT := 48
const TREE_SEED := 11
const ROCK_SEED := 23
const BORDER_TREE_STEP := 3
## Free cells kept around every area when scattering trees and rocks.
const SCATTER_MARGIN := 2


static func area(area_name: StringName) -> Rect2i:
	if FIELDS.has(area_name):
		return FIELDS[area_name]
	if PLOTS.has(area_name):
		return PLOTS[area_name]
	return Rect2i()


static func area_names() -> Array[StringName]:
	var names: Array[StringName] = []
	names.append_array(FIELDS.keys())
	names.append_array(PLOTS.keys())
	return names


static func is_water(cell: Vector2i) -> bool:
	return _in_any(PONDS, cell)


static func is_path(cell: Vector2i) -> bool:
	return _in_any(PATHS, cell)


## Which named area a cell is in (an empty name for open ground).
static func area_at(cell: Vector2i) -> StringName:
	for area_name in area_names():
		if area(area_name).has_point(cell):
			return area_name
	return &""


## Cells nobody can till, fence or plant on: building plots, pens, the orchard, ponds,
## paths and the stall. Trees and rocks are added by Main as it places them.
static func blocked_cells() -> Dictionary:
	var cells := {}
	for plot: Rect2i in PLOTS.values():
		_add_rect(cells, plot)
	for rect in PONDS:
		_add_rect(cells, rect)
	for rect in PATHS:
		_add_rect(cells, rect)
	_add_rect(cells, STALL_FOOTPRINT)
	cells[BOARD_CELL] = true
	return cells


## The big oaks along the map edge: [cell, ...]. Same ring the 48x30 map had.
static func border_trees() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(0, MAP_SIZE.x + 1, BORDER_TREE_STEP):
		cells.append(Vector2i(x, 1))
		cells.append(Vector2i(x, MAP_SIZE.y))
	for y in range(4, MAP_SIZE.y, BORDER_TREE_STEP):
		cells.append(Vector2i(0, y))
		cells.append(Vector2i(MAP_SIZE.x - 1, y))
	return cells


## Medium oaks scattered over open ground. Same result every run.
static func scatter_trees() -> Array[Vector2i]:
	return _scatter(TREE_COUNT, TREE_SEED, {})


## Boulders scattered over open ground, never on a tree cell.
static func scatter_rocks() -> Array[Vector2i]:
	var taken := {}
	for cell in scatter_trees():
		taken[cell] = true
	return _scatter(ROCK_COUNT, ROCK_SEED, taken)


## Which of the 3x3 pond / dirt tiles a cell uses (column, row 0..2), looking at the four
## neighbours: no neighbour above = top row, none to the left = left column, and so on.
static func edge_tile(cell: Vector2i, in_set: Callable) -> Vector2i:
	var column := 1
	if not in_set.call(cell + Vector2i.LEFT):
		column = 0
	elif not in_set.call(cell + Vector2i.RIGHT):
		column = 2
	var row := 1
	if not in_set.call(cell + Vector2i.UP):
		row = 0
	elif not in_set.call(cell + Vector2i.DOWN):
		row = 2
	return Vector2i(column, row)


static func _scatter(count: int, rng_seed: int, taken: Dictionary) -> Array[Vector2i]:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var keep_clear := _keep_clear_cells()
	var cells: Array[Vector2i] = []
	var attempts := 0
	while cells.size() < count and attempts < count * 200:
		attempts += 1
		var cell := Vector2i(
			rng.randi_range(PLAY_AREA.position.x + 1, PLAY_AREA.end.x - 2),
			rng.randi_range(PLAY_AREA.position.y + 2, PLAY_AREA.end.y - 1))
		if keep_clear.has(cell) or taken.has(cell):
			continue
		taken[cell] = true
		cells.append(cell)
	return cells


## Every area, pond and path grown by SCATTER_MARGIN, plus the player's start.
static func _keep_clear_cells() -> Dictionary:
	var cells := {}
	var rects: Array[Rect2i] = []
	rects.append_array(FIELDS.values())
	rects.append_array(PLOTS.values())
	rects.append_array(PONDS)
	rects.append_array(PATHS)
	rects.append(STALL_FOOTPRINT)
	rects.append(Rect2i(BOARD_CELL, Vector2i.ONE))
	for rect in rects:
		_add_rect(cells, rect.grow(SCATTER_MARGIN))
	_add_rect(cells, Rect2i(PLAYER_START, Vector2i.ONE).grow(SCATTER_MARGIN))
	return cells


static func _add_rect(cells: Dictionary, rect: Rect2i) -> void:
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			cells[Vector2i(x, y)] = true


static func _in_any(rects: Array[Rect2i], cell: Vector2i) -> bool:
	for rect in rects:
		if rect.has_point(cell):
			return true
	return false
