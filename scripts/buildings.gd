class_name Buildings
extends Node
## Puts every restorable building and the restoration board into the world and keeps them in
## step with Game.restored. Main sets `entities` (the y-sorted node) before adding this to the tree,
## and moves it in front of the entities so its flat ghosts are drawn under them.

const SIGNS := preload("res://assets/cute_fantasy/Outdoor decoration/Signs.png")
const BOARD_REGION := Rect2(48, 16, 16, 32)  # a post with two boards
const BOARD_RANGE := 30.0
const RUIN_MARGIN := 12.0  # pixels around a ruined plot that still count as "near"

var entities: Node2D
var board_position := Vector2.ZERO
var _buildings := {}  # project id -> Building
var _underlay := Node2D.new()


func _ready() -> void:
	add_child(_underlay)
	for id in Restoration.ids():
		var building := Building.new()
		building.id = id
		building.ghost_parent = _underlay
		entities.add_child(building)
		_buildings[id] = building
	_place_board()
	Game.stats_changed.connect(_sync.bind(false))
	Game.project_restored.connect(func(_id: String) -> void: _sync(true))


func get_building(id: String) -> Building:
	return _buildings.get(id)


func is_near_board(world_pos: Vector2) -> bool:
	return world_pos.distance_to(board_position) < BOARD_RANGE


## The id of the unrestored building whose plot (plus a small margin) the position is in, or "".
func ruin_near(world_pos: Vector2) -> String:
	for id: String in _buildings:
		if Game.is_restored(id):
			continue
		var plot := WorldLayout.area(BuildingData.spec(id)["plot"])
		var rect := Rect2(plot.position * BuildingData.TILE, plot.size * BuildingData.TILE).grow(RUIN_MARGIN)
		if rect.has_point(world_pos):
			return id
	return ""


## Repairs whatever changed. Loading a save goes through stats_changed (no animation).
func _sync(animate: bool) -> void:
	for id: String in _buildings:
		var building: Building = _buildings[id]
		if building.restored != Game.is_restored(id):
			building.set_restored(Game.is_restored(id), animate)


## The restoration board: a signpost beside the farmhouse. E on it opens the board panel (Main).
func _place_board() -> void:
	var body := StaticBody2D.new()
	body.position = Vector2(WorldLayout.BOARD_CELL * BuildingData.TILE) + Vector2(8, 14)
	var sprite := Sprite2D.new()
	sprite.texture = SIGNS
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = BOARD_REGION
	sprite.position = Vector2(-8, -30)
	body.add_child(sprite)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(8, 5)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = Vector2(0, -3)
	body.add_child(collider)
	entities.add_child(body)
	board_position = body.global_position
