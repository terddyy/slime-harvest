extends Node
## Automated full-run playtest. A simple bot farms, keeps animals and an orchard, spends its gold
## on restoring the farm (in the order of Restoration.PROJECTS) and (in "defend" mode) fights at
## night. Prints balance numbers per night and the day the farm was saved. Catches crashes that
## only show up on later nights and checks the economy (ticket P1).
##
## Run (headless, as fast as the CPU allows):
##   godot --headless --path . res://tests/playthrough.tscn --fixed-fps 60 -- --mode=defend
##   godot --headless --path . res://tests/playthrough.tscn --fixed-fps 60 -- --mode=idle
## defend: the bot walks to the nearest enemy and swings the sword.
## idle:   the bot stays at the stall; shows how fast enemies eat an undefended field.
##         It only plays IDLE_NIGHTS nights and does not need to restore the farm.
## defend: plays until every project is restored (exit 0) or MAX_DAYS pass (exit 1).
## Run with --quit-after 400000 or more: a full run is ~15-25 game days (135 s each).
##
## Human model: the bot waters the whole field for free but may only plant or harvest
## ACTIONS_PER_PASS tiles every FARM_EVERY seconds (a person walks, tills, waters and sells).

const IDLE_NIGHTS := 7  # idle mode stops after this many nights
const MAX_DAYS := 40  # defend mode gives up here (balance is broken if it gets this far)
const FIELD := Rect2i(-4, -4, 8, 3)  # crop block, relative to the player's start cell
const FARM_EVERY := 6.0  # seconds between bot farming passes
const ACTIONS_PER_PASS := 1  # tiles the bot may plant or harvest in one pass
const SAPLINGS_TO_PLANT := 4
const ATTACK_RANGE := 14.0
const GOLD_RESERVE := 20  # the bot keeps this much before buying upgrades

var _mode := "defend"
var _main: Node
var _farm: Farm
var _player: Player
var _start_cell := Vector2i.ZERO
var _farm_timer := 0.0
var _night_stats := {}
var _harvested_cells := {}
var _report: Array[String] = []
var _restored_on_day := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			_mode = arg.trim_prefix("--mode=")
	SaveGame.path = "user://test_save_playthrough.json"  # dawn autosaves must not touch the real save
	SaveGame.delete()
	Game.reset()
	Game.intro_seen = true  # no story panels over the bot
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_farm = _main.get_node("Farm")
	_player = _main.get_node("Entities/Player")
	_start_cell = _farm.cell_at(_player.global_position)
	_main.get_node("Entities").child_entered_tree.connect(_on_entity_added)
	_main._spawner.enemy_killed.connect(func(_pos: Vector2, _gold: int) -> void: _night_stats["kills"] += 1)
	Game.phase_changed.connect(_on_phase_changed)
	Game.project_restored.connect(func(id: String) -> void: _restored_on_day[id] = Game.day)
	Game.farm_restored.connect(_on_farm_restored)
	_reset_night_stats()
	print("playthrough mode=%s" % _mode)


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_farm_timer -= delta
	if _farm_timer <= 0.0:
		_farm_timer = FARM_EVERY
		_tend_field()
		_collect_animals_and_fruit()
		_shop()
	if Game.is_night and _mode == "defend":
		_fight(delta)
	elif _mode == "idle":
		_player.position = _main._stall_position + Vector2(0, 12)


# --- Bot behaviour ------------------------------------------------------------

func _field_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(FIELD.position.x, FIELD.end.x):
		for y in range(FIELD.position.y, FIELD.end.y):
			cells.append(_start_cell + Vector2i(x, y))
	return cells


## Water every field tile, then harvest ripe crops and plant empty tiles (ACTIONS_PER_PASS of them).
func _tend_field() -> void:
	var actions := ACTIONS_PER_PASS
	for cell in _field_cells():
		_farm.till(cell)
		_farm.water(cell)
	for cell in _field_cells():
		if actions <= 0:
			return
		var crop := _farm.get_crop(cell)
		if crop != null and crop.is_ripe():
			Game.add_crop(crop.crop_id)
			_harvested_cells[cell] = true
			_farm.harvest(cell)
			actions -= 1
	for cell in _field_cells():
		if actions <= 0:
			return
		var best := _best_seed()
		if _farm.get_crop(cell) == null and best != "" and Game.use_seed(best):
			_farm.plant(cell, best)
			actions -= 1


## The seed type the bot plants: the best-selling crop it owns seeds for.
func _best_seed() -> String:
	var best := ""
	for crop_id: String in Crop.TYPES:
		if Game.seed_count(crop_id) > 0 and (best == "" or Crop.TYPES[crop_id]["sell_price"] > Crop.TYPES[best]["sell_price"]):
			best = crop_id
	return best


## Walks past every animal and tree (instantly) and takes what is ready.
func _collect_animals_and_fruit() -> void:
	for animal in _main._herd.animals():
		_main._herd.collect_near(animal.global_position)
	var orchard: Orchard = _main._orchard
	for cell in _orchard_cells():
		if orchard.has_fruit(cell):
			Game.add_fruit(orchard.harvest(cell))


func _orchard_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var area := WorldLayout.area(&"orchard")
	for x in range(area.position.x + 1, area.end.x - 1, 2):
		for y in range(area.position.y + 1, area.end.y - 1, 2):
			cells.append(Vector2i(x, y))
	return cells


## Sell everything, then spend: the next restoration project first, then seeds for the field,
## animals, orchard saplings and sword upgrades (in that order, keeping GOLD_RESERVE).
func _shop() -> void:
	Game.sell_crops()
	for entry in Restoration.PROJECTS:
		if not Game.is_restored(entry["id"]):
			Game.restore(entry["id"])  # false when too poor; the bot just keeps saving
			break
	var best_crop := ""
	for crop_id: String in Crop.TYPES:
		if Crop.is_unlocked(crop_id, Game.restored) and int(Crop.TYPES[crop_id]["seed_price"]) * 4 <= Game.gold - GOLD_RESERVE:
			best_crop = crop_id
	var wanted: int = _field_cells().size() - _farm.crop_count()
	while best_crop != "" and Game.total(Game.seeds) < wanted and Game.gold - GOLD_RESERVE >= int(Crop.TYPES[best_crop]["seed_price"]) and Game.buy_seed(best_crop):
		pass
	for animal_id: String in AnimalTypes.TYPES:
		while Game.gold - GOLD_RESERVE >= int(AnimalTypes.TYPES[animal_id]["price"]) and Game.buy_animal(animal_id):
			pass
	_plant_saplings()
	var price := Game.upgrade_price("sword")
	if price > 0 and Game.gold - price >= GOLD_RESERVE:
		Game.buy_upgrade("sword")


func _plant_saplings() -> void:
	var orchard: Orchard = _main._orchard
	if orchard.tree_count() + Game.total(Game.saplings) >= SAPLINGS_TO_PLANT:
		return
	if Game.gold - GOLD_RESERVE >= int(Orchard.TYPES["apple"]["sapling_price"]):
		Game.buy_sapling("apple")
	var tree_id := Game.next_sapling()
	if tree_id == "":
		return
	for cell in _orchard_cells():
		if orchard.can_plant(cell) and Game.use_sapling(tree_id):
			orchard.plant(cell, tree_id)
			return


func _fight(delta: float) -> void:
	var target: Node2D = null
	var best := INF
	for enemy: Node2D in get_tree().get_nodes_in_group("enemies"):
		var d := enemy.global_position.distance_to(_player.global_position)
		if d < best:
			best = d
			target = enemy
	if target == null:
		return
	var to_enemy := target.global_position - _player.global_position
	if to_enemy.length() > ATTACK_RANGE:
		_player.position += to_enemy.normalized() * Player.SPEED * delta
	_player.facing = _player._snap_to_axis(to_enemy)
	if to_enemy.length() <= ATTACK_RANGE + 4.0 and not _player._is_busy():
		_player.set_tool(Player.Tool.SWORD)
		_player._start_action()


# --- Stats ------------------------------------------------------------------

func _reset_night_stats() -> void:
	_night_stats = {"spawned": 0, "kills": 0, "crops_lost": 0, "crops_at_dusk": 0}


func _on_entity_added(node: Node) -> void:
	if node is Crop:
		var crop := node as Crop
		crop.tree_exiting.connect(_on_crop_removed.bind(crop))
	elif node.has_method("take_hit"):
		_night_stats["spawned"] += 1


func _on_crop_removed(crop: Crop) -> void:
	if _harvested_cells.has(crop.cell):
		_harvested_cells.erase(crop.cell)
	else:
		_night_stats["crops_lost"] += 1


func _on_phase_changed(is_night: bool) -> void:
	if is_night:
		_reset_night_stats()
		_night_stats["crops_at_dusk"] = _farm.crop_count()
	else:
		_log_night(Game.day - 1)
		if _mode == "idle" and Game.day > IDLE_NIGHTS:
			_finish(0)
		elif Game.day > MAX_DAYS:
			print("FAILED: farm not restored after %d days (%d of %d projects)" % [
				MAX_DAYS, Game.restored_count(), Restoration.PROJECTS.size()])
			_finish(1)


func _on_farm_restored() -> void:
	for entry in Restoration.PROJECTS:
		print("restored %s on day %d" % [entry["name"], _restored_on_day.get(entry["id"], -1)])
	print("RESULT: farm saved on day %d (total cost %d gold)" % [Game.day, Restoration.total_cost()])
	_finish(0)


func _log_night(night: int) -> void:
	var line := "night %d: spawned %d, killed %d, crops %d -> lost %d | gold %d, sword lv %d" % [
		night, _night_stats["spawned"], _night_stats["kills"],
		_night_stats["crops_at_dusk"], _night_stats["crops_lost"],
		Game.gold, Game.upgrade_level("sword")]
	_report.append(line)
	print(line)


func _finish(code: int) -> void:
	print("RESULT: finished on day %d with %d gold" % [Game.day, Game.gold])
	SaveGame.delete()
	get_tree().quit(code)
