class_name Herd
extends Node
## All the farm animals. Spawns one when Game.buy_animal() succeeds, lets Imogen collect
## products (E near an animal, or a click on it), and saves/loads positions and the
## last collected day. How many animals you own is Game.animals; this node makes them visible.

signal collected(world_pos: Vector2, product_id: String)

const COLLECT_RANGE := 30.0  # E: player to animal
const CLICK_RANGE := 14.0  # click: mouse to animal
const CLICK_PLAYER_RANGE := 56.0  # a click only collects if Imogen is this close
const PEN_MARGIN := 8.0  # keeps feet away from the pen edge, in pixels

var entities: Node2D
var player: Node2D

var _animals: Array[Animal] = []


func _ready() -> void:
	Game.animal_bought.connect(_on_animal_bought)


func animals() -> Array[Animal]:
	return _animals


## The closest animal with a product within `reach` of `pos`, or null.
func animal_ready_near(pos: Vector2, reach: float = COLLECT_RANGE) -> Animal:
	var best: Animal = null
	var best_distance := reach
	for animal in _animals:
		var distance := animal.body_center().distance_to(pos)
		if animal.has_product() and distance <= best_distance:
			best = animal
			best_distance = distance
	return best


## E: collects from the nearest ready animal. False if none is in reach.
func collect_near(pos: Vector2) -> bool:
	var animal := animal_ready_near(pos)
	return animal != null and _collect(animal)


func spawn(type_id: String, at := Vector2.INF, last_collected := Game.day) -> Animal:
	var animal := Animal.new()
	animal.type_id = type_id
	animal.pen = pen_rect(type_id)
	animal.collected_day = last_collected
	animal.position = _clamp_to_pen(at, animal.pen) if at != Vector2.INF else _random_in(animal.pen)
	entities.add_child(animal)
	_animals.append(animal)
	return animal


## The pen of an animal type in pixels, shrunk a little so feet don't touch the edge.
static func pen_rect(type_id: String) -> Rect2:
	var area := WorldLayout.area(AnimalTypes.TYPES[type_id]["pen"])
	return Rect2(Vector2(area.position) * 16.0, Vector2(area.size) * 16.0).grow(-PEN_MARGIN)


func to_save() -> Dictionary:
	var list: Array = []
	for animal in _animals:
		list.append(animal.to_save())
	return {"animals": list}


## Rebuilds the herd. Game.animals (already loaded) says how many of each there are;
## saved positions are used up to that count, any missing animal appears at a random spot.
func from_save(data: Dictionary) -> void:
	_clear()
	var made := {}
	for entry: Variant in SaveUtil.list(data.get("animals")):
		if not entry is Dictionary:
			continue
		var type_id: Variant = entry.get("type")
		if not type_id is String or not AnimalTypes.TYPES.has(type_id) or made.get(type_id, 0) >= Game.animal_count(type_id):
			continue
		var at := Vector2(SaveUtil.number(entry, "x", INF), SaveUtil.number(entry, "y", INF))
		var day := int(SaveUtil.number(entry, "day", Game.day))
		spawn(type_id, at if at.is_finite() else Vector2.INF, mini(day, Game.day))
		made[type_id] = made.get(type_id, 0) + 1
	for type_id: String in Game.animals:
		for i in Game.animal_count(type_id) - int(made.get(type_id, 0)):
			spawn(type_id)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if player == null or not entities.is_inside_tree():
		return
	var animal := animal_ready_near(entities.get_global_mouse_position(), CLICK_RANGE)
	if animal != null and animal.body_center().distance_to(player.global_position) <= CLICK_PLAYER_RANGE and _collect(animal):
		get_viewport().set_input_as_handled()


func _collect(animal: Animal) -> bool:
	var product_id := animal.collect()
	if product_id == "":
		return false
	Game.add_product(product_id)
	Audio.play_sfx("harvest", 0.05)
	collected.emit(animal.body_center(), product_id)
	return true


func _on_animal_bought(id: String) -> void:
	spawn(id)


func _clear() -> void:
	for animal in _animals:
		animal.queue_free()
	_animals.clear()


func _random_in(rect: Rect2) -> Vector2:
	return Vector2(randf_range(rect.position.x, rect.end.x), randf_range(rect.position.y, rect.end.y))


func _clamp_to_pen(pos: Vector2, rect: Rect2) -> Vector2:
	return Vector2(clampf(pos.x, rect.position.x, rect.end.x), clampf(pos.y, rect.position.y, rect.end.y))
