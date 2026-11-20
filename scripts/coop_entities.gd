class_name CoopEntities
extends Node
## Online co-op: slimes, animals and Gayle. Only the host simulates them. About 10 times a second
## the host sends where they all are; a joiner keeps copies ("puppets") that glide to those spots
## and play the same animation. A joiner's sword never touches its puppets: the swing goes to the
## host (CoopWorld) and the host's slimes take the hit.
## Every RPC here lives on /root/Main/CoopEntities.

## Joiner: the host says a slime died here and paid this much gold (Main shows "+3g").
signal enemy_killed(world_pos: Vector2, gold: int)

const SEND_INTERVAL := 0.1

var coop: CoopSession
var entities: Node2D
var spawner: Spawner
var herd: Herd
var gayle: Gayle

var _puppets := {}  # joiner: the host's slime id -> our copy
var _timer := 0.0


func _ready() -> void:
	name = "CoopEntities"
	if Net.is_host():
		spawner.enemy_killed.connect(func(world_pos: Vector2, gold: int) -> void: coop.send(self, "_slime_died", [world_pos, gold]))
	else:
		herd.puppet = true
		gayle.puppet = true


func _process(delta: float) -> void:
	if not Net.is_host():
		return
	_timer += delta
	if _timer < SEND_INTERVAL:
		return
	_timer = 0.0
	var slimes := []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is Slime:
			slimes.append(enemy.to_state())
	coop.send(self, "_entities", [slimes, herd.to_states(), gayle.to_state()])


## Host -> joiner: every slime as Slime.to_state(), every animal as Animal.to_state(), Gayle as Gayle.to_state().
@rpc("authority", "call_remote", "unreliable")
func _entities(slimes: Array, animals: Array, gayle_state: Array) -> void:
	if not coop.has_farm():
		return
	var seen := {}
	for state: Variant in slimes:
		if state is Array and state.size() >= 6:
			var id := int(state[0])
			seen[id] = true
			_show_slime(id, state)
	for id: int in _puppets.keys():
		if not seen.has(id):  # gone from the host's night: killed, or it vanished at dawn
			_puppets[id].vanish()
			_puppets.erase(id)
	herd.apply_states(animals)
	if gayle_state.size() >= 5:
		gayle.show_state(Vector2(float(gayle_state[0]), float(gayle_state[1])), Vector2(float(gayle_state[2]), float(gayle_state[3])), str(gayle_state[4]))


@rpc("authority", "call_remote", "reliable")
func _slime_died(world_pos: Vector2, gold: int) -> void:
	enemy_killed.emit(world_pos, gold)


func _show_slime(id: int, state: Array) -> void:
	var at := Vector2(float(state[2]), float(state[3]))
	if not _puppets.has(id):
		var slime := Slime.new()
		slime.puppet = true
		slime.size = clampi(int(state[1]), 0, Slime.Size.BIG) as Slime.Size
		slime.position = at
		entities.add_child(slime)
		_puppets[id] = slime
	_puppets[id].show_state(at, str(state[4]), state[5] == true)
