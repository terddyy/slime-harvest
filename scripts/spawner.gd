class_name Spawner
extends Node
## Spawns the night's slimes (see Waves for the table) at the map edges, away from
## the player, and clears them at dawn. Main creates it and sets the vars below.

## Re-emitted from every enemy's `killed` signal (the enemy already added the gold).
signal enemy_killed(world_pos: Vector2, gold: int)

const MIN_PLAYER_DISTANCE := 120.0
const SPLIT_OFFSET := 10.0

var farm: Farm
var fences: Fences
var player: Player
## Enemies are added here (the y-sorted Entities node).
var entities: Node2D
## Map size in pixels.
var map_size := Vector2.ZERO

var _queue: Array[String] = []
var _interval := 0.0
var _timer := 0.0
var _rng := RandomNumberGenerator.new()


func _process(delta: float) -> void:
	if _queue.is_empty():
		return
	_timer -= delta
	if _timer <= 0.0:
		spawn(_queue.pop_front(), _edge_position())
		_timer = _interval


func start_night(night: int) -> void:
	_queue = Waves.build_queue(night)
	_interval = Waves.interval(night)
	_timer = Waves.FIRST_DELAY


## Stops spawning and makes every enemy still alive vanish (no gold).
func end_night() -> void:
	_queue.clear()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.vanish()


## Creates one enemy of `kind` (one of Waves.KINDS) standing at `at`.
func spawn(kind: String, at: Vector2) -> Node2D:
	var enemy: Node2D
	match kind:
		"small":
			enemy = _new_slime(Slime.Size.SMALL)
		"big":
			enemy = _new_slime(Slime.Size.BIG)
		_:
			enemy = _new_slime(Slime.Size.MEDIUM)
	enemy.position = at
	entities.add_child(enemy)
	return enemy


func _new_slime(size: Slime.Size) -> Slime:
	var slime := Slime.new()
	slime.size = size
	slime.farm = farm
	slime.fences = fences
	slime.killed.connect(enemy_killed.emit)
	slime.split.connect(_on_slime_split)
	return slime


## A big slime died: two small slimes pop out and get pushed apart.
func _on_slime_split(world_pos: Vector2) -> void:
	for side in [-1.0, 1.0]:
		var small := spawn("small", world_pos + Vector2(side * SPLIT_OFFSET, 0)) as Slime
		small.knock_back(world_pos)


## A random point on the inner edge of the map that isn't right next to the player.
func _edge_position() -> Vector2:
	var position_on_edge := player.global_position
	for _attempt in 10:
		var side := _rng.randi_range(0, 3)
		var along := _rng.randf()
		match side:
			0: position_on_edge = Vector2(along * map_size.x, 40)
			1: position_on_edge = Vector2(along * map_size.x, map_size.y - 24)
			2: position_on_edge = Vector2(32, along * map_size.y)
			3: position_on_edge = Vector2(map_size.x - 32, along * map_size.y)
		position_on_edge = position_on_edge.clamp(Vector2(32, 40), map_size - Vector2(32, 24))
		if position_on_edge.distance_to(player.global_position) > MIN_PLAYER_DISTANCE:
			break
	return position_on_edge
