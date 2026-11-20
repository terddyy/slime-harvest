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
## Co-op joiner: the animals are copies of the host's (see apply_states).
var puppet := false
## Co-op joiner: the CoopWorld a click on an animal is sent to ("collect that one").
var remote_world: CoopWorld
## What the last successful collect gave and where (co-op tells the joiner who asked).
var last_product := ""
var last_position := Vector2.ZERO


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
	animal.puppet = puppet
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


## Co-op host: every animal as Animal.to_state(), in order.
func to_states() -> Array:
	var list: Array = []
	for animal in _animals:
		list.append(animal.to_state())
	return list


## Co-op joiner: the host's animals. Missing ones are made, extra ones removed.
func apply_states(states: Array) -> void:
	while _animals.size() > states.size():
		_animals.pop_back().queue_free()
	for i in states.size():
		var state: Variant = states[i]
		if not state is Array or state.size() < 6 or not AnimalTypes.TYPES.has(str(state[0])):
			continue
		var at := Vector2(float(state[1]), float(state[2]))
		if i < _animals.size() and _animals[i].type_id != str(state[0]):
			_animals[i].queue_free()
			_animals[i] = spawn(str(state[0]), at)
			_animals.pop_back()
		elif i >= _animals.size():
			spawn(str(state[0]), at)
		_animals[i].show_state(at, state[3] == true, state[4] == true, state[5] == true)


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
	var mouse := entities.get_global_mouse_position()
	if remote_world != null:  # a joiner only asks; the host collects
		var wanted := animal_ready_near(mouse, CLICK_RANGE)
		if wanted != null and wanted.body_center().distance_to(player.global_position) <= CLICK_PLAYER_RANGE:
			remote_world.send_collect_click(mouse)
			get_viewport().set_input_as_handled()
		return
	if collect_click(mouse, player.global_position):
		get_viewport().set_input_as_handled()


## A click at `mouse` collects from the ready animal there if the farmer at `farmer_pos` is close enough.
func collect_click(mouse: Vector2, farmer_pos: Vector2) -> bool:
	var animal := animal_ready_near(mouse, CLICK_RANGE)
	return animal != null and animal.body_center().distance_to(farmer_pos) <= CLICK_PLAYER_RANGE and _collect(animal)


func _collect(animal: Animal) -> bool:
	var product_id := animal.collect()
	if product_id == "":
		return false
	Game.add_product(product_id)
	last_product = product_id
	last_position = animal.body_center()
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
