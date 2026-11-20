class_name CoopWorld
extends Node
## Online co-op: the farm itself. Host-authoritative: only the host changes the world.
##  - A joiner never farms by itself. Its tool use, harvesting, E, clicks on animals and purchases
##    go to the host as small requests ("intents"); the host checks them, runs the same code as for
##    its own player (WorldActions, Game) and answers with a sound/popup (_result).
##  - Whatever changes on the host is sent to the joiners: each changed farm / fence / sprinkler /
##    orchard cell, the shared gold and bags (Game.to_save), and the clock.
##  - Sleeping: everybody has to be in bed; the host then runs the morning.
## Slimes, animals and Gayle are in CoopEntities. Every RPC here lives on /root/Main/CoopWorld.

## Joiner: the host's answer to what we did: {"sfx", "variation"} and maybe {"text", "pos", "color"}.
signal result_received(result: Dictionary)
## Everybody: the night is over (text for the banner), or "" when this player got out of bed.
signal woke(text: String)
## Everybody: how many players are not in bed yet.
signal sleep_waiting(missing: int)

const CLOCK_INTERVAL := 1.0
const STATE_INTERVAL := 0.25  # the shared gold and bags are sent at most this often

var coop: CoopSession
var farm: Farm
var fences: Fences
var sprinklers: Sprinklers
var orchard: Orchard
var actions: WorldActions
## Host: sleeps through the night (eaten crops, new day) and returns the banner text. Set by Farmhouse.
var morning := Callable()

var _asleep := {}  # host: player id -> true
var _state_dirty := false
var _state_timer := 0.0
var _clock_timer := 0.0


func _ready() -> void:
	name = "CoopWorld"
	process_mode = Node.PROCESS_MODE_ALWAYS  # updates keep flowing while the host looks at an ending panel
	if Net.is_host():
		farm.cell_changed.connect(func(cell: Vector2i) -> void: coop.send(self, "_farm_cell", [cell, farm.cell_state(cell)]))
		fences.changed.connect(func(cell: Vector2i) -> void: coop.send(self, "_fence_cell", [cell, fences.hp_at(cell)]))
		sprinklers.changed.connect(func(cell: Vector2i) -> void: coop.send(self, "_sprinkler_cell", [cell, sprinklers.has_sprinkler(cell)]))
		orchard.changed.connect(func(cell: Vector2i) -> void: coop.send(self, "_tree_cell", [cell, orchard.tree_state(cell)]))
		Game.stats_changed.connect(func() -> void: _state_dirty = true)
		Game.phase_changed.connect(_on_phase_changed)
		Net.player_left.connect(_on_player_left)
	else:
		Game.remote_call = _ask_host_to_call
		farm.set_process(false)  # the host grows the crops


func _exit_tree() -> void:
	Game.remote_call = Callable()


func _process(delta: float) -> void:
	if not Net.is_host():
		return
	_state_timer += delta
	if _state_dirty and _state_timer >= STATE_INTERVAL:
		_state_dirty = false
		_state_timer = 0.0
		coop.send(self, "_game_state", [Game.to_save()])
	_clock_timer += delta
	if _clock_timer >= CLOCK_INTERVAL:
		_send_clock()


# --- Joiner -> host: what I did ---------------------------------------------

func send_tool(tool: int, cell: Vector2i, untill: bool, facing: Vector2, seed_id: String, sapling_id: String) -> void:
	_use_tool.rpc_id(Net.HOST_ID, tool, cell, untill, facing, seed_id, sapling_id)


func send_harvest(cell: Vector2i) -> void:
	_harvest.rpc_id(Net.HOST_ID, cell)


func send_interact(cell: Vector2i, sapling_id: String) -> void:
	_interact.rpc_id(Net.HOST_ID, cell, sapling_id)


func send_collect_click(world_pos: Vector2) -> void:
	_collect_click.rpc_id(Net.HOST_ID, world_pos)


## Game.remote_call on a joiner: "please run Game.method(args)" (buying, selling, restoring).
func _ask_host_to_call(method: String, args: Array) -> void:
	_game_call.rpc_id(Net.HOST_ID, method, args)


@rpc("any_peer", "call_remote", "reliable")
func _use_tool(tool: int, cell: Vector2i, untill: bool, facing: Vector2, seed_id: String, sapling_id: String) -> void:
	var id := _asker()
	if id == 0:
		return
	var from := coop.farmer_position(id)
	if CoopRules.tool_intent_ok(tool, cell, facing, seed_id, sapling_id, from, Player.Tool.size()):
		_answer(id, actions.use_tool(tool as Player.Tool, cell, untill, facing, seed_id, sapling_id, from))


@rpc("any_peer", "call_remote", "reliable")
func _harvest(cell: Vector2i) -> void:
	var id := _asker()
	if id != 0 and CoopRules.in_reach(coop.farmer_position(id), cell):
		_answer(id, actions.harvest(cell))


@rpc("any_peer", "call_remote", "reliable")
func _interact(cell: Vector2i, sapling_id: String) -> void:
	var id := _asker()
	if id == 0 or not CoopRules.in_reach(coop.farmer_position(id), cell):
		return
	if sapling_id != "" and not Orchard.TYPES.has(sapling_id):
		return
	var result := actions.interact(cell, coop.farmer_position(id), sapling_id)
	_answer(id, actions.product_result() if result.has("herd") else result)


@rpc("any_peer", "call_remote", "reliable")
func _collect_click(world_pos: Vector2) -> void:
	var id := _asker()
	if id != 0 and world_pos.is_finite() and actions.herd.collect_click(world_pos, coop.farmer_position(id)):
		_answer(id, actions.product_result())


@rpc("any_peer", "call_remote", "reliable")
func _game_call(method: String, args: Array) -> void:
	var id := _asker()
	if id == 0 or not CoopRules.game_call_ok(method, args, Game.UPGRADE_PRICES.keys()):
		return
	var done: Variant = Game.callv(method, args)  # sell_crops returns the gold, the others true/false
	if done is bool and not done:
		_answer(id, {"sfx": "error", "variation": 0.0})


## Host: the joiner who sent the request being handled, or 0 when it can't be trusted (not the host, unknown player).
func _asker() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if Net.is_host() and id != Net.HOST_ID and coop.ready_joiners().has(id) else 0


func _answer(id: int, result: Dictionary) -> void:
	if not result.is_empty():
		_result.rpc_id(id, result)


## Host -> joiner: the sound and floating text for what the joiner just did.
@rpc("authority", "call_remote", "reliable")
func _result(result: Dictionary) -> void:
	result_received.emit(result)


# --- Host -> joiners: what changed -----------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _farm_cell(cell: Vector2i, state: Array) -> void:
	if coop.has_farm():
		farm.apply_cell_state(cell, state)


@rpc("authority", "call_remote", "reliable")
func _fence_cell(cell: Vector2i, hp: int) -> void:
	if coop.has_farm():
		fences.apply_cell(cell, hp)


@rpc("authority", "call_remote", "reliable")
func _sprinkler_cell(cell: Vector2i, present: bool) -> void:
	if coop.has_farm():
		sprinklers.apply_cell(cell, present)


@rpc("authority", "call_remote", "reliable")
func _tree_cell(cell: Vector2i, state: Array) -> void:
	if coop.has_farm():
		orchard.apply_tree(cell, state)


## The shared gold, seeds, bags, upgrades, buildings...
@rpc("authority", "call_remote", "reliable")
func _game_state(data: Dictionary) -> void:
	if coop.has_farm():
		Game.apply_shared(data)


func _send_clock() -> void:
	_clock_timer = 0.0
	coop.send(self, "_clock", [Game.day, Game.is_night, Game.time_left])


@rpc("authority", "call_remote", "reliable")
func _clock(day: int, is_night: bool, time_left: float) -> void:
	if coop.has_farm():
		Game.sync_clock(day, is_night, time_left)


func _on_phase_changed(is_night: bool) -> void:
	_send_clock()
	if not is_night and not _asleep.is_empty():  # dawn came while some players were still in bed
		_asleep.clear()
		_wake_all("")


# --- Sleeping: everybody in bed ---------------------------------------------------

## This player went to bed (true) or got up again (false).
func set_sleeping(asleep: bool) -> void:
	if Net.is_host():
		_set_asleep(Net.HOST_ID, asleep)
	else:
		_sleep_state.rpc_id(Net.HOST_ID, asleep)


## Gets this player out of bed without waiting for the others.
func cancel_sleep() -> void:
	set_sleeping(false)
	woke.emit("")


@rpc("any_peer", "call_remote", "reliable")
func _sleep_state(asleep: bool) -> void:
	var id := _asker()
	if id != 0:
		_set_asleep(id, asleep)


func _set_asleep(id: int, asleep: bool) -> void:
	if asleep and SleepRules.can_sleep(Game.is_night, Game.phase_progress()):
		_asleep[id] = true
	else:
		_asleep.erase(id)
	_check_sleepers()


## Everybody in bed: the host runs the morning. Otherwise tell all players who is still missing.
func _check_sleepers() -> void:
	var everybody: Array = [Net.HOST_ID] + coop.ready_joiners()
	if CoopRules.all_asleep(everybody, _asleep):
		_asleep.clear()
		_wake_all(morning.call() if morning.is_valid() else "")
		return
	var missing := CoopRules.sleepers_missing(everybody, _asleep)
	sleep_waiting.emit(missing)
	coop.send(self, "_sleep_wait", [missing])


func _wake_all(text: String) -> void:
	woke.emit(text)
	coop.send(self, "_wake", [text])


func _on_player_left(id: int) -> void:
	if _asleep.erase(id) and not _asleep.is_empty():
		_check_sleepers()


@rpc("authority", "call_remote", "reliable")
func _sleep_wait(missing: int) -> void:
	sleep_waiting.emit(missing)


@rpc("authority", "call_remote", "reliable")
func _wake(text: String) -> void:
	woke.emit(text)
