extends SceneTree
## Headless tests, no addons needed. Run:
##   godot --headless --path . --script res://tests/run_tests.gd
## Exits with code 1 if any check fails.

var _failures := 0
var _checks := 0


func _initialize() -> void:
	await process_frame  # let autoloads (Game) finish _ready
	_test_economy()
	_test_loading_tips()
	_test_settings()
	_test_crop_data()
	_test_inventory_per_type()
	_test_upgrades()
	_test_tilling_and_autotile()
	_test_untilling()
	_test_watering_and_planting()
	_test_crop_growth()
	_test_slow_crop_growth()
	_test_slime_eats_crop()
	_test_wave_table()
	_test_restoration()
	_test_building_data()
	_test_endless_days()
	_test_sleep_rules()
	_test_fence_economy()
	_test_fence_placement()
	_test_fence_autotile()
	_test_fence_damage_and_blocking()
	_test_farm_signals()
	_test_tutorial_steps()
	_test_effects()
	_test_shopkeeper()
	_test_world_layout()
	_test_orchard()
	_test_plant_cycle()
	_test_save_roundtrip()
	_test_save_file()
	_test_save_bad_data()
	_test_animals()
	_test_gayle_brain()
	_test_farm_goals()
	_test_inventory_rows()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("FAIL: " + label)


func _game() -> Node:
	return root.get_node("Game")


func _new_farm() -> Farm:
	var farm := Farm.new()
	farm.bounds = Rect2i(0, 0, 20, 20)
	var crops := Node2D.new()
	root.add_child(crops)
	farm.crop_parent = crops
	root.add_child(farm)
	return farm


func _test_economy() -> void:
	var game := _game()
	game.reset()
	_check(not game.buy_seed("carrot"), "can't buy a seed with 0 gold")
	game.add_crop("carrot")
	game.add_crop("carrot")
	var carrot_price: int = Crop.TYPES["carrot"]["sell_price"]
	_check(game.sell_crops() == 2 * carrot_price, "selling 2 carrots pays 2x the carrot price")
	_check(game.total(game.crops_in_bag) == 0, "bag is empty after selling")
	var seeds_before: int = game.seed_count("carrot")
	_check(game.buy_seed("carrot"), "can buy a seed with enough gold")
	_check(game.seed_count("carrot") == seeds_before + 1, "buying adds a seed")
	_check(game.gold == 2 * carrot_price - int(Crop.TYPES["carrot"]["seed_price"]), "buying costs the seed price")
	game.reset()


func _test_crop_data() -> void:
	var ids := Crop.TYPES.keys()
	_check(ids.size() == 10 and ids[0] == "radish" and ids[-1] == "chili", "ten crop types in shop order")
	var previous: Dictionary = {}
	for crop_id: String in ids:
		var data: Dictionary = Crop.TYPES[crop_id]
		for key in ["name", "row", "grow_ticks", "seed_price", "sell_price", "icon", "seed_icon"]:
			_check(data.has(key), "%s has %s" % [crop_id, key])
		_check(data["sell_price"] > data["seed_price"], "%s sells for more than its seed" % crop_id)
		_check(data["grow_ticks"] >= 1, "%s grows at least every tick" % crop_id)
		_check(int(data["row"]) * Crop.BAND.y < Crop.TEXTURE.get_height(), "%s row is inside Crops.png" % crop_id)
		if not previous.is_empty():
			_check(data["seed_price"] > previous["seed_price"], "%s seeds cost more than the previous crop" % crop_id)
			_check(data["grow_ticks"] >= previous["grow_ticks"], "%s grows no faster than the previous crop" % crop_id)
			_check(data["sell_price"] > previous["sell_price"], "%s sells for more than the previous crop" % crop_id)
		var needed: String = data.get("requires", "")
		_check(needed == "" or not Restoration.project(needed).is_empty(), "%s requirement is a real project" % crop_id)
		previous = data
	_check(not Crop.is_unlocked("chili", {}) and Crop.is_unlocked("chili", {"greenhouse": true}), "chili needs the greenhouse")
	_check(Crop.is_unlocked("carrot", {}), "carrot is open from the start")
	var game := _game()
	game.gold = 1000
	_check(not game.buy_seed("strawberry") and game.gold == 1000, "locked seeds can't be bought")
	game.restored["greenhouse"] = true
	_check(game.buy_seed("strawberry"), "seeds can be bought once the building is restored")
	game.reset()


func _test_inventory_per_type() -> void:
	var game := _game()
	game.reset()
	_check(game.seed_count("carrot") > 0, "start with carrot seeds")
	_check(game.total(game.seeds) == game.seed_count("carrot"), "start with carrot seeds only")
	_check(not game.use_seed("tomato"), "can't use a seed type you don't have")
	_check(game.use_seed("carrot"), "can use a carrot seed")
	game.add_crop("carrot")
	game.add_crop("pumpkin")
	game.add_crop("pumpkin")
	_check(game.crop_count("pumpkin") == 2 and game.crop_count("carrot") == 1, "crops are counted per type")
	var expected: int = Crop.TYPES["carrot"]["sell_price"] + 2 * int(Crop.TYPES["pumpkin"]["sell_price"])
	_check(game.bag_value() == expected, "bag value adds up each type's price")
	_check(game.sell_crops() == expected, "selling pays the bag value")
	_check(game.gold == expected, "selling adds the gold")
	_check(game.buy_seed("corn"), "can buy corn seeds")
	_check(game.seed_count("corn") == 1, "corn seed added to its own count")
	game.reset()
	_check(game.seed_count("corn") == 0 and game.gold == 0, "reset clears seeds and gold")
	_check(game.seed_count("carrot") == game.START_SEEDS["carrot"], "reset gives the starting seeds again")


func _test_upgrades() -> void:
	var game := _game()
	game.reset()
	for upgrade_id: String in game.UPGRADE_PRICES:
		var prices: Array = game.UPGRADE_PRICES[upgrade_id]
		for i in range(1, prices.size()):
			_check(prices[i] > prices[i - 1], "%s gets more expensive each level" % upgrade_id)
	_check(not game.UPGRADE_PRICES.has("hearts"), "no hearts upgrade: the player has no health")
	_check(game.upgrade_level("sword") == 0, "upgrades start at level 0")
	_check(not game.buy_upgrade("sword"), "can't buy an upgrade without gold")
	game.add_gold(1000)
	var first_price: int = game.upgrade_price("sword")
	_check(game.buy_upgrade("sword"), "can buy a sword upgrade")
	_check(game.gold == 1000 - first_price, "upgrade costs its price")
	_check(game.upgrade_level("sword") == 1, "sword is level 1 after buying")
	_check(game.upgrade_price("sword") > first_price, "next sword level costs more")
	_check(game.buy_upgrade("sword"), "can buy the second sword upgrade")
	_check(game.upgrade_price("sword") == -1, "maxed upgrade has no price")
	_check(not game.buy_upgrade("sword"), "can't buy past the max level")
	var gold_before: int = game.gold
	_check(game.spend(10) and game.gold == gold_before - 10, "spend takes the gold")
	game.reset()
	_check(game.upgrade_level("sword") == 0, "reset clears upgrades")
	_check(not game.spend(1), "can't spend gold you don't have")


func _test_tilling_and_autotile() -> void:
	var farm := _new_farm()
	farm.blocked[Vector2i(9, 9)] = true
	_check(farm.till(Vector2i(5, 5)), "can till grass")
	_check(not farm.till(Vector2i(5, 5)), "can't till twice")
	_check(not farm.till(Vector2i(9, 9)), "can't till a blocked cell")
	_check(not farm.till(Vector2i(25, 5)), "can't till outside bounds")
	_check(farm.autotile_coords(Vector2i(5, 5)) == Vector2i(0, 0), "lone tile uses the isolated piece")
	farm.till(Vector2i(6, 5))
	_check(farm.autotile_coords(Vector2i(5, 5)) == Vector2i(1, 3), "left end of a row")
	_check(farm.autotile_coords(Vector2i(6, 5)) == Vector2i(3, 3), "right end of a row")
	_check(farm.get_cell_atlas_coords(Vector2i(5, 5)) == Vector2i(1, 3), "neighbour was repainted")
	farm.queue_free()


func _test_untilling() -> void:
	var farm := _new_farm()
	var events: Array[String] = []
	farm.untilled.connect(func(_cell: Vector2i) -> void: events.append("untilled"))
	_check(not farm.untill(Vector2i(5, 5)), "can't untill grass")
	farm.till(Vector2i(5, 5))
	farm.till(Vector2i(6, 5))
	farm.water(Vector2i(6, 5))
	_check(farm.untill(Vector2i(6, 5)), "can untill empty soil")
	_check(not farm.is_tilled(Vector2i(6, 5)) and not farm.is_wet(Vector2i(6, 5)), "untilled cell is grass and dry")
	_check(farm.get_cell_source_id(Vector2i(6, 5)) == -1, "untilled cell has no tile painted")
	_check(farm.autotile_coords(Vector2i(5, 5)) == Vector2i(0, 0), "neighbour becomes a lone tile again")
	_check(farm.get_cell_atlas_coords(Vector2i(5, 5)) == Vector2i(0, 0), "neighbour was repainted")
	_check(events == ["untilled"], "untill emits once, only on success")
	_check(farm.till(Vector2i(6, 5)), "can till the cell again")
	farm.plant(Vector2i(6, 5))
	_check(not farm.untill(Vector2i(6, 5)) and farm.is_tilled(Vector2i(6, 5)), "soil with a crop is never untilled")
	var saved := farm.to_save()
	farm.untill(Vector2i(5, 5))
	farm.from_save(farm.to_save())
	_check(not farm.is_tilled(Vector2i(5, 5)) and farm.is_tilled(Vector2i(6, 5)), "untilled cells are gone after save/load")
	farm.from_save(saved)
	_check(farm.is_tilled(Vector2i(5, 5)), "loading an older save brings its soil back")
	farm.queue_free()


func _test_watering_and_planting() -> void:
	var farm := _new_farm()
	var cell := Vector2i(3, 3)
	_check(not farm.water(cell), "can't water grass")
	_check(not farm.plant(cell), "can't plant on grass")
	farm.till(cell)
	_check(farm.water(cell), "can water tilled soil")
	_check(farm.is_wet(cell), "watered soil is wet")
	_check(farm.plant(cell), "can plant on tilled soil")
	_check(not farm.plant(cell), "can't plant twice")
	_check(farm.get_crop(cell) != null and farm.get_crop(cell).stage == 0, "new crop starts at stage 0")
	farm.queue_free()


func _test_crop_growth() -> void:
	var farm := _new_farm()
	var cell := Vector2i(4, 4)
	farm.till(cell)
	farm.plant(cell)
	var crop := farm.get_crop(cell)
	farm.grow_all()
	_check(crop.stage == 0, "dry crop doesn't grow")
	farm.water(cell)
	farm.grow_all()
	_check(crop.stage == 1, "watered crop grows one stage")
	_check(not farm.is_wet(cell), "growing uses up the water")
	for i in Crop.STAGES + 2:
		farm.water(cell)
		farm.grow_all()
	_check(crop.stage == Crop.STAGES - 1, "crop stops at the ripe stage")
	_check(crop.is_ripe(), "crop is ripe")
	_check(farm.harvest(cell), "ripe crop can be harvested")
	_check(farm.get_crop(cell) == null, "harvest removes the crop")
	farm.queue_free()


func _test_slow_crop_growth() -> void:
	var farm := _new_farm()
	var cell := Vector2i(6, 6)
	farm.till(cell)
	_check(farm.plant(cell, "pumpkin"), "can plant a pumpkin")
	var crop := farm.get_crop(cell)
	_check(crop.crop_id == "pumpkin", "planted crop has the chosen type")
	var ticks: int = Crop.TYPES["pumpkin"]["grow_ticks"]
	farm.water(cell)
	for i in ticks - 1:
		farm.grow_all()
	_check(crop.stage == 0, "pumpkin hasn't grown before its grow_ticks")
	_check(farm.is_wet(cell), "soil stays wet while the pumpkin waits")
	farm.grow_all()
	_check(crop.stage == 1, "pumpkin grows after grow_ticks wet ticks")
	_check(not farm.is_wet(cell), "growing used the water")
	for i in ticks:
		farm.grow_all()
	_check(crop.stage == 1, "dry pumpkin doesn't grow")
	farm.queue_free()


func _test_slime_eats_crop() -> void:
	var farm := _new_farm()
	var cell := Vector2i(2, 2)
	farm.till(cell)
	farm.plant(cell)
	var crop := farm.get_crop(cell)
	var eaten := false
	for i in Crop.BITES_TO_EAT:
		eaten = crop.bite()
	_check(eaten, "crop is eaten after BITES_TO_EAT bites")
	_check(farm.nearest_crop(Vector2.ZERO) == crop, "nearest_crop finds the crop")
	farm.queue_free()


func _test_wave_table() -> void:
	var game := _game()
	var previous_total := 0
	for night in range(1, 41):
		var counts: Dictionary = Waves.wave(night)["counts"]
		var total := 0
		for kind: String in counts:
			_check(kind in Waves.KINDS, "night %d: '%s' is a known enemy kind" % [night, kind])
			total += counts[kind]
		_check(Waves.build_queue(night).size() == total, "night %d: queue holds every enemy" % night)
		_check(total >= previous_total, "night %d: never fewer enemies than the night before" % night)
		previous_total = total
		var last_spawn := Waves.FIRST_DELAY + (total - 1) * Waves.interval(night)
		_check(last_spawn < game.NIGHT_LENGTH * 0.85, "night %d: last enemy spawns before dawn" % night)
	_check(not Waves.KINDS.has("skeleton"), "skeletons are gone (slimes only)")
	_check(Waves.wave(8)["counts"]["medium"] > Waves.wave(7)["counts"]["medium"], "night 8 is harder than night 7")
	_check(Waves.wave(99) == Waves.wave(Waves.NIGHTS.size() + Waves.MAX_EXTRA_NIGHTS), "very late nights stop growing")


func _test_restoration() -> void:
	var game := _game()
	game.reset()
	var ids := Restoration.ids()
	_check(ids.size() == Restoration.PROJECTS.size() and ids.size() > 0, "restoration projects exist")
	for entry in Restoration.PROJECTS:
		_check(int(entry["cost"]) > 0 and not String(entry["name"]).is_empty(), "%s has a name and a cost" % entry["id"])
	_check(Restoration.project("nope").is_empty(), "unknown project id gives an empty entry")
	var seen := []
	game.project_restored.connect(func(id: String) -> void: seen.append(id))
	var farm_done := [false]
	game.farm_restored.connect(func() -> void: farm_done[0] = true)
	_check(not game.restore(ids[0]), "can't restore without gold")
	_check(not game.is_restored(ids[0]), "unaffordable project stays unrestored")
	game.gold = Restoration.total_cost() + 7
	_check(not game.restore("nope"), "unknown project can't be restored")
	_check(game.restore(ids[0]), "restore with enough gold works")
	_check(game.gold == Restoration.total_cost() + 7 - int(Restoration.project(ids[0])["cost"]), "restoring costs the project's gold")
	_check(not game.restore(ids[0]), "a project can only be restored once")
	_check(game.restored_count() == 1 and not game.all_restored(), "one project done is not all done")
	_check(not farm_done[0], "farm_restored not emitted early")
	for id in ids:
		game.restore(id)
	_check(game.all_restored(), "all projects restored")
	_check(farm_done[0], "farm_restored emitted at the end")
	_check(seen == ids, "project_restored emitted once per project, in order")
	_check(game.gold == 7, "total cost was paid")
	game.reset()
	_check(game.restored_count() == 0, "reset clears restored projects")
	_check(Restoration.gold_short("well", 100) == 50, "gold_short: well with 100g needs 50 more")
	_check(Restoration.gold_short("well", 500) == 0 and Restoration.gold_short("nope", 0) == 0, "gold_short: never negative, unknown is 0")
	_check(Restoration.cheapest_unrestored({}) == "well", "cheapest unrestored is the well")
	_check(Restoration.cheapest_unrestored({"well": true}) == "farmhouse", "cheapest skips restored ones")
	var everything := {}
	for id in ids:
		everything[id] = true
	_check(Restoration.cheapest_unrestored(everything) == "", "nothing left when all restored")
	_check(Restoration.affordable_next({}, 149) == "" and Restoration.affordable_next({}, 150) == "well", "affordable_next needs the full price")
	_check(Restoration.affordable_next(everything, 99999) == "", "affordable_next empty when all restored")


func _test_building_data() -> void:
	for id in Restoration.ids():
		var data := BuildingData.spec(id)
		_check(not data.is_empty(), "buildings: %s has art data" % id)
		if data.is_empty():
			continue
		var plot := WorldLayout.area(data["plot"])
		_check(plot.size != Vector2i.ZERO, "buildings: %s plot exists in the layout" % id)
		_check(ResourceLoader.exists(data["texture"]), "buildings: %s texture exists" % id)
		var foot := BuildingData.foot_position(id)
		var plot_px := Rect2(plot.position * BuildingData.TILE, plot.size * BuildingData.TILE)
		_check(plot_px.has_point(foot), "buildings: %s stands inside its plot" % id)
		_check(is_equal_approx(foot.x, plot_px.get_center().x), "buildings: %s is centred on its plot" % id)
		_check(Rect2(Vector2.ZERO, (data["region"] as Rect2).size).has_point(data["foot"]), "buildings: %s foot is inside its sprite" % id)
	_check(BuildingData.SPECS.size() == Restoration.PROJECTS.size(), "buildings: one spec per restoration project")
	_check(BuildingData.spec("nope").is_empty(), "buildings: unknown id has no spec")
	var board := WorldLayout.BOARD_CELL
	_check(WorldLayout.area_at(board) == &"" and WorldLayout.blocked_cells().has(board), "buildings: the board cell is open ground, not tillable")
	_check(not WorldLayout.is_path(board), "buildings: the board is not on a road")


func _test_endless_days() -> void:
	var game := _game()
	game.reset()
	for i in 40:
		game.skip_phase()
		game._process(0.0)
	_check(game.day == 21, "days keep going past day 7 (day %d after 40 phases)" % game.day)
	game.reset()


func _test_sleep_rules() -> void:
	_check(SleepRules.can_sleep(true, 0.0), "can sleep at night")
	_check(SleepRules.can_sleep(false, 0.6), "can sleep in the late day")
	_check(not SleepRules.can_sleep(false, 0.1), "can't sleep in the early day")

	var bounds := Rect2i(0, 0, 20, 20)
	var ring := {}  # a fence ring around cells (5..7, 5..7)
	for i in range(4, 9):
		for edge: Vector2i in [Vector2i(i, 4), Vector2i(i, 8), Vector2i(4, i), Vector2i(8, i)]:
			ring[edge] = true
	var has_fence := func(cell: Vector2i) -> bool: return ring.has(cell)
	_check(SleepRules.is_enclosed(Vector2i(6, 6), has_fence, bounds), "crop inside a fence ring is enclosed")
	_check(not SleepRules.is_enclosed(Vector2i(2, 2), has_fence, bounds), "crop outside the ring is exposed")
	ring.erase(Vector2i(6, 4))
	_check(not SleepRules.is_enclosed(Vector2i(6, 6), has_fence, bounds), "a gap in the ring exposes the crop")
	ring[Vector2i(6, 4)] = true
	# A fence that only closes against the map edge counts: the edge of the play area is open.
	_check(not SleepRules.is_enclosed(Vector2i(0, 0), has_fence, bounds), "play area edge is open")

	var inside: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 6), Vector2i(7, 7)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	_check(SleepRules.eaten_crops(inside, has_fence, bounds, rng).is_empty(), "fenced crops are never eaten")
	var exposed: Array[Vector2i] = []
	for x in 10:
		for y in 10:
			exposed.append(Vector2i(10 + x, 10 + y))
	var eaten := SleepRules.eaten_crops(exposed, has_fence, bounds, rng).size()
	_check(eaten > 15 and eaten < 45, "about 30%% of 100 exposed crops are eaten (%d)" % eaten)
	var rng_all := RandomNumberGenerator.new()
	rng_all.seed = 2
	var mixed: Array[Vector2i] = [Vector2i(6, 6), Vector2i(15, 15)]
	var counts := 0
	for i in 200:
		counts += SleepRules.eaten_crops(mixed, has_fence, bounds, rng_all).size()
	_check(counts > 40 and counts < 80, "only the exposed crop can be eaten, ~30%% of 200 (%d)" % counts)

	var game := _game()
	game.reset()
	game.day = 3
	game.is_night = true
	game.time_left = 10.0
	var phases := []
	game.phase_changed.connect(func(night: bool) -> void: phases.append(night))
	game.sleep_to_morning()
	_check(game.day == 4 and not game.is_night and game.time_left == game.DAY_LENGTH, "sleeping starts the next morning")
	_check(phases == [false], "sleeping emits phase_changed(false) once")
	game.reset()


func _new_fences(farm: Farm) -> Fences:
	var fences := Fences.new()
	fences.farm = farm
	fences.fence_parent = farm.crop_parent
	root.add_child(fences)
	return fences


func _test_fence_economy() -> void:
	var game := _game()
	game.reset()
	_check(game.fence_pieces == game.START_FENCES, "start with START_FENCES fence pieces")
	_check(not game.buy_fences(), "can't buy fences without gold")
	game.add_gold(game.FENCE_BUNDLE_PRICE)
	_check(game.buy_fences(), "can buy a fence bundle")
	_check(game.gold == 0, "a fence bundle costs FENCE_BUNDLE_PRICE")
	_check(game.fence_pieces == game.START_FENCES + game.FENCE_BUNDLE, "a bundle adds FENCE_BUNDLE pieces")
	_check(game.use_fence(), "can use a fence piece")
	game.return_fence()
	_check(game.fence_pieces == game.START_FENCES + game.FENCE_BUNDLE, "picking a fence up refunds the piece")
	game.fence_pieces = 0
	_check(not game.use_fence(), "can't build without fence pieces")
	game.reset()
	_check(game.fence_pieces == game.START_FENCES, "reset gives the starting fences again")


func _test_fence_placement() -> void:
	var farm := _new_farm()
	var fences := _new_fences(farm)
	farm.blocked[Vector2i(9, 9)] = true
	farm.till(Vector2i(4, 4))
	_check(fences.place(Vector2i(5, 5)), "can build a fence on grass")
	_check(fences.has_fence(Vector2i(5, 5)), "the fence is there")
	_check(fences.hp_at(Vector2i(5, 5)) == Fences.MAX_HP, "a new fence has full HP")
	_check(not fences.place(Vector2i(5, 5)), "can't build two fences on one tile")
	_check(not fences.place(Vector2i(4, 4)), "can't build on tilled soil")
	_check(not fences.place(Vector2i(9, 9)), "can't build on a blocked tile (tree, stall)")
	_check(not fences.place(Vector2i(25, 5)), "can't build outside the farm bounds")
	_check(not farm.till(Vector2i(5, 5)), "can't till under a fence")
	_check(fences.remove(Vector2i(5, 5)), "can pick a fence back up")
	_check(not fences.has_fence(Vector2i(5, 5)), "picked-up fence is gone")
	_check(not fences.remove(Vector2i(5, 5)), "nothing to pick up on an empty tile")
	_check(farm.till(Vector2i(5, 5)), "can till where a fence was picked up")
	fences.queue_free()
	farm.queue_free()


func _test_fence_autotile() -> void:
	var farm := _new_farm()
	var fences := _new_fences(farm)
	fences.place(Vector2i(5, 5))
	_check(fences.autotile_coords(Vector2i(5, 5)) == Vector2i(0, 3), "lone fence is a single post")
	fences.place(Vector2i(6, 5))
	fences.place(Vector2i(7, 5))
	_check(fences.autotile_coords(Vector2i(5, 5)) == Vector2i(1, 0), "left end of a row")
	_check(fences.autotile_coords(Vector2i(6, 5)) == Vector2i(2, 0), "middle of a row")
	_check(fences.autotile_coords(Vector2i(7, 5)) == Vector2i(3, 0), "right end of a row")
	fences.place(Vector2i(5, 6))
	_check(fences.autotile_coords(Vector2i(5, 5)) == Vector2i(1, 1), "top-left corner")
	_check(fences.autotile_coords(Vector2i(5, 6)) == Vector2i(0, 2), "bottom end of a column")
	fences.place(Vector2i(6, 4))
	fences.place(Vector2i(6, 6))
	_check(fences.autotile_coords(Vector2i(6, 5)) == Vector2i(2, 2), "crossing in all 4 directions")
	fences.remove(Vector2i(6, 4))
	_check(fences.autotile_coords(Vector2i(6, 5)) == Vector2i(2, 1), "T piece after removing the top")
	fences.queue_free()
	farm.queue_free()


func _test_fence_damage_and_blocking() -> void:
	var farm := _new_farm()
	var fences := _new_fences(farm)
	var cell := Vector2i(5, 5)
	fences.place(cell)
	var inside := Vector2(cell * Fences.TILE) + Vector2(8, 8)
	var above := inside + Vector2(0, -16)
	_check(fences.cell_at(inside) == cell, "cell_at finds the fence tile")
	_check(fences.blocks(above, inside), "stepping onto a fence is blocked")
	_check(not fences.blocks(inside, above), "leaving a fence tile is allowed")
	_check(not fences.blocks(inside, inside + Vector2(2, 2)), "moving inside a fence tile is allowed")
	_check(not fences.blocks(above, above + Vector2(16, 0)), "walking past a fence is allowed")
	_check(not fences.damage(cell, Fences.MAX_HP - 1), "a fence survives less than MAX_HP damage")
	_check(fences.hp_at(cell) == 1, "damage lowers the fence HP")
	_check(fences.damage(cell, 1), "the last point of damage breaks the fence")
	_check(not fences.has_fence(cell), "a broken fence is gone")
	_check(not fences.blocks(above, inside), "a broken fence no longer blocks")
	_check(not farm.blocked.has(cell), "a broken fence frees its tile")
	_check(not fences.damage(cell, 1), "can't damage a fence that isn't there")
	fences.queue_free()
	farm.queue_free()


func _test_farm_signals() -> void:
	var farm := _new_farm()
	var events: Array[String] = []
	farm.tilled.connect(func(_cell: Vector2i) -> void: events.append("tilled"))
	farm.watered.connect(func(_cell: Vector2i) -> void: events.append("watered"))
	farm.planted.connect(func(_cell: Vector2i) -> void: events.append("planted"))
	farm.crop_ripened.connect(func(_cell: Vector2i) -> void: events.append("ripened"))
	farm.harvested.connect(func(_cell: Vector2i) -> void: events.append("harvested"))
	var cell := Vector2i(7, 7)
	farm.water(cell)
	_check(events.is_empty(), "a failed action emits nothing")
	farm.till(cell)
	farm.plant(cell)
	for i in Crop.STAGES - 1:
		farm.water(cell)
		farm.grow_all()
	farm.harvest(cell)
	_check(events.count("tilled") == 1 and events.count("planted") == 1, "till and plant emit once")
	_check(events.count("watered") == Crop.STAGES - 1, "each successful watering emits")
	_check(events.count("ripened") == 1, "crop_ripened emits once, on the last stage")
	_check(events.back() == "harvested", "harvest emits last")
	farm.queue_free()


func _test_tutorial_steps() -> void:
	var steps := TutorialSteps.new()
	_check(steps.index == 0 and not steps.is_done(), "tutorial starts at the first step")
	_check(steps.text() == TutorialSteps.STEPS[0]["text"], "first tip is the tilling tip")
	_check(not steps.record("harvested"), "a later event doesn't skip ahead")
	_check(steps.record("tilled") and steps.index == 1, "tilling finishes step 1")
	_check(not steps.record("tilled"), "repeating an event does nothing")
	_check(not steps.record("planted"), "planting before watering waits")
	_check(steps.record("watered") and steps.index == 3, "watering also counts the earlier planting")
	_check(steps.record("ripened") and steps.index == 5, "ripening counts the earlier harvest")
	_check(steps.record("sold") and steps.index == 6 and not steps.is_done(), "selling moves on to the board tip")
	_check(not steps.record("slept"), "sleeping before the board and Gayle waits")
	_check(steps.record("board") and steps.index == 7, "opening the board moves on to Gayle")
	_check(steps.record("talked") and steps.is_done(), "talking to Gayle also counts the earlier sleep")
	_check(steps.text() == TutorialSteps.NIGHT_TIP, "night tip shows after the last step")
	var events := []
	for step: Dictionary in TutorialSteps.STEPS:
		_check(not str(step["text"]).is_empty(), "every step has a text")
		events.append(step["event"])
	_check(events == ["tilled", "watered", "planted", "ripened", "harvested", "sold", "board", "talked", "slept"], "steps in play order")
	var targets := []
	for step: Dictionary in TutorialSteps.STEPS:
		targets.append(step.get("target", ""))
	_check(targets == ["", "", "", "", "", "stall", "board", "gayle", "house"], "go-somewhere steps name a guide target")
	var fresh := TutorialSteps.new()
	_check(fresh.target() == "", "the first step has no guide target")
	for event: String in ["tilled", "watered", "planted", "ripened", "harvested"]:
		fresh.record(event)
	_check(fresh.target() == "stall", "the selling step points the guide at the stall")
	for event: String in ["sold", "board", "talked", "slept"]:
		fresh.record(event)
	_check(fresh.is_done() and fresh.target() == "", "no guide target once the tips are done")
	var area := Rect2(10, 46, 460, 190)
	_check(Effects.edge_point(area, Vector2(100, 100)) == Vector2(100, 100), "an arrow target inside the area stays put")
	_check(Effects.edge_point(area, Vector2(1000, 141)) == Vector2(470, 141), "a target far right clamps to the right edge")
	_check(is_equal_approx(Effects.edge_point(area, Vector2(240, -500)).y, 46.0), "a target far above clamps to the top edge")


func _test_shopkeeper() -> void:
	_check(Shopkeeper.NPC_NAME == "Azy", "the shopkeeper is called Azy")
	_check(Shopkeeper.frame_region(0) == Rect2(0, 0, 64, 64), "idle frame 0 is the first cell of row 0")
	_check(Shopkeeper.frame_region(5) == Rect2(320, 0, 64, 64), "idle frame 5 is the sixth cell")
	_check(Shopkeeper.frame_region(6) == Shopkeeper.frame_region(0), "idle frames wrap around")
	var sheet := Shopkeeper.SHEET.get_size()
	_check(sheet.x >= Shopkeeper.IDLE_FRAMES * Shopkeeper.CELL.x, "sheet is wide enough for the idle frames")


func _test_effects() -> void:
	var parent := Node2D.new()
	root.add_child(parent)
	var puff := Effects.burst(parent, Vector2(5, 5), Effects.DIRT, 8)
	_check(puff.get_parent() == parent and puff.one_shot and puff.amount == 8, "burst adds a one-shot puff")
	_check(puff.color_initial_ramp.get_point_count() == Effects.DIRT.size(), "puff uses every palette colour")
	_check(Effects.SLIME_COLORS.size() == 3, "one particle palette per slime size")
	var farm := _new_farm()
	var cell := Vector2i(8, 8)
	farm.till(cell)
	farm.plant(cell)
	var crop := farm.get_crop(cell)
	for i in Crop.STAGES:
		crop.try_grow(true)
	_check(crop.get_children().any(func(child: Node) -> bool: return child is CPUParticles2D), "ripe crop sparkles")
	parent.queue_free()
	farm.queue_free()


# --- Saving -----------------------------------------------------------------

## A JSON round trip like the real file: ints come back as floats, arrays as Arrays.
func _through_json(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))


func _test_world_layout() -> void:
	var map_rect := Rect2i(Vector2i.ZERO, WorldLayout.MAP_SIZE)
	_check(map_rect.encloses(WorldLayout.PLAY_AREA), "layout: play area is inside the map")
	var rects: Array[Rect2i] = []
	for area_name in WorldLayout.area_names():
		var rect := WorldLayout.area(area_name)
		_check(WorldLayout.PLAY_AREA.encloses(rect), "layout: %s is inside the play area" % area_name)
		for other in rects:
			_check(not rect.intersects(other), "layout: %s overlaps another area" % area_name)
		rects.append(rect)
	for pond in WorldLayout.PONDS:
		_check(WorldLayout.PLAY_AREA.encloses(pond), "layout: pond inside the play area")
		for other in rects:
			_check(not pond.intersects(other), "layout: pond overlaps an area")
	for path in WorldLayout.PATHS:
		_check(WorldLayout.PLAY_AREA.encloses(path), "layout: path inside the play area")
		for other in rects:
			_check(not path.intersects(other), "layout: path overlaps an area")
		for pond in WorldLayout.PONDS:
			_check(not path.intersects(pond), "layout: path crosses a pond")
	_check(not WorldLayout.STALL_FOOTPRINT.intersects(WorldLayout.area(&"home_field")), "layout: stall is off the home field")
	_check(WorldLayout.area_at(WorldLayout.PLAYER_START) == &"home_field", "layout: the player starts in the home field")
	_check(WorldLayout.area_at(Vector2i(0, 0)) == &"", "layout: map corner is open ground")
	_check(WorldLayout.is_water(Vector2i(12, 38)) and not WorldLayout.is_water(Vector2i(30, 25)), "layout: pond cells are water")
	_check(WorldLayout.is_path(Vector2i(30, 14)) and not WorldLayout.is_path(Vector2i(30, 25)), "layout: path cells")

	var blocked := WorldLayout.blocked_cells()
	_check(blocked.has(Vector2i(12, 38)) and blocked.has(Vector2i(30, 14)) and blocked.has(Vector2i(30, 10)), "layout: pond, path and plot cells are blocked")
	_check(not blocked.has(WorldLayout.PLAYER_START), "layout: the start cell is free")
	var field_blocked := 0
	for field_name in WorldLayout.FIELDS:
		var field: Rect2i = WorldLayout.FIELDS[field_name]
		for x in range(field.position.x, field.end.x):
			for y in range(field.position.y, field.end.y):
				if blocked.has(Vector2i(x, y)):
					field_blocked += 1
	_check(field_blocked == 0, "layout: no field cell is blocked")

	var trees := WorldLayout.scatter_trees()
	var rocks := WorldLayout.scatter_rocks()
	_check(trees.size() == WorldLayout.TREE_COUNT and rocks.size() == WorldLayout.ROCK_COUNT, "layout: all trees and rocks found a spot")
	_check(trees == WorldLayout.scatter_trees(), "layout: trees are the same every call")
	var used := {}
	for cell in trees + rocks:
		_check(not blocked.has(cell) and not used.has(cell), "layout: tree/rock %s is on free ground" % cell)
		used[cell] = true
		_check(WorldLayout.area_at(cell) == &"", "layout: tree/rock %s is not inside an area" % cell)
	for cell in WorldLayout.border_trees():
		_check(cell.x <= 0 or cell.y <= 1 or cell.x >= WorldLayout.MAP_SIZE.x - 1 or cell.y >= WorldLayout.MAP_SIZE.y, "layout: border tree %s is on the edge" % cell)

	var in_rect := func(cell: Vector2i) -> bool: return Rect2i(0, 0, 3, 3).has_point(cell)
	_check(WorldLayout.edge_tile(Vector2i(0, 0), in_rect) == Vector2i(0, 0), "layout: edge tile top-left corner")
	_check(WorldLayout.edge_tile(Vector2i(1, 1), in_rect) == Vector2i(1, 1), "layout: edge tile centre")
	_check(WorldLayout.edge_tile(Vector2i(2, 2), in_rect) == Vector2i(2, 2), "layout: edge tile bottom-right corner")
	_check(WorldLayout.edge_tile(Vector2i(1, 0), in_rect) == Vector2i(1, 0), "layout: edge tile top edge")


func _test_save_roundtrip() -> void:
	var game := _game()
	game.reset()
	game.day = 5
	game.time_left = 40.0
	game.gold = 321
	game.seeds = {"carrot": 2, "corn": 4}
	game.crops_in_bag = {"tomato": 3}
	game.upgrades = {"sword": 1, "can": 2}
	game.fence_pieces = 9
	game.restored = {"well": true, "barn": true}
	var saved: Dictionary = _through_json(game.to_save())
	game.reset()
	game.from_save(saved)
	_check(game.day == 5 and is_equal_approx(game.time_left, 40.0) and game.gold == 321, "game: day, time and gold round trip")
	_check(game.seeds == {"carrot": 2, "corn": 4} and game.crops_in_bag == {"tomato": 3}, "game: seeds and bag round trip")
	_check(game.upgrades == {"sword": 1, "can": 2} and game.fence_pieces == 9, "game: upgrades and fences round trip")
	_check(game.restored == {"well": true, "barn": true}, "game: restored buildings round trip")
	_check(not game.is_night, "game: a loaded game starts in the day")
	game.is_night = true
	_check(game.to_save()["time_left"] == game.NIGHT_RESUME_TIME, "game: a night is saved as just before dusk")
	game.reset()
	var all := {}
	for id: String in Restoration.ids():
		all[id] = true
	game.restored = all
	var emitted := []
	game.farm_restored.connect(func() -> void: emitted.append(1))
	game.from_save(_through_json(game.to_save()))
	_check(game.all_restored() and emitted.is_empty(), "loading a finished farm doesn't re-emit farm_restored")
	game.reset()

	var farm := _new_farm()
	for cell in [Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3)]:
		farm.till(cell)
	farm.water(Vector2i(4, 3))
	farm.plant(Vector2i(3, 3), "pumpkin")
	farm.plant(Vector2i(4, 3), "corn")
	farm.get_crop(Vector2i(4, 3)).try_grow(true)
	farm.get_crop(Vector2i(4, 3)).tick(true)
	farm.get_crop(Vector2i(3, 3)).bite()
	var farm_data: Dictionary = _through_json(farm.to_save())
	var other := _new_farm()
	other.till(Vector2i(9, 9))  # must be wiped by from_save
	other.from_save(farm_data)
	_check(other.is_tilled(Vector2i(5, 3)) and not other.is_tilled(Vector2i(9, 9)), "farm: soil replaced by the saved soil")
	_check(other.is_wet(Vector2i(4, 3)) == farm.is_wet(Vector2i(4, 3)) and not other.is_wet(Vector2i(3, 3)), "farm: wet flags round trip")
	_check(other.crop_count() == 2 and other.get_crop(Vector2i(3, 3)).crop_id == "pumpkin", "farm: crops and types round trip")
	_check(other.get_crop(Vector2i(4, 3)).stage == 1, "farm: crop stage round trip")
	_check(other.get_crop(Vector2i(3, 3)).to_save() == farm.get_crop(Vector2i(3, 3)).to_save(), "farm: bites and wet ticks round trip")
	_check(other.autotile_coords(Vector2i(4, 3)) == farm.autotile_coords(Vector2i(4, 3)), "farm: autotile repainted")

	var fences := Fences.new()
	fences.farm = other
	fences.fence_parent = other.crop_parent
	root.add_child(fences)
	fences.place(Vector2i(10, 10))
	fences.place(Vector2i(11, 10))
	fences.damage(Vector2i(11, 10), 3)
	var fence_data: Dictionary = _through_json(fences.to_save())
	fences.from_save({})  # the first set must give up its cells (they block placing)
	var fences2 := Fences.new()
	fences2.farm = other
	fences2.fence_parent = other.crop_parent
	root.add_child(fences2)
	fences2.from_save(fence_data)
	_check(fences2.count() == 2 and fences2.has_fence(Vector2i(10, 10)), "fences: cells round trip")
	_check(fences2.hp_at(Vector2i(11, 10)) == Fences.MAX_HP - 3 and fences2.hp_at(Vector2i(10, 10)) == Fences.MAX_HP, "fences: hp round trip")
	fences2.from_save({})
	_check(fences2.count() == 0, "fences: loading replaces what was there")
	farm.queue_free()
	other.queue_free()
	fences.queue_free()
	fences2.queue_free()


func _new_orchard() -> Orchard:
	var orchard := Orchard.new()
	orchard.area = Rect2i(10, 10, 8, 4)
	root.add_child(orchard)
	return orchard


func _test_plant_cycle() -> void:
	var seeds := {"carrot": 1, "corn": 2}
	var saplings := {"pear": 1, "apple": 1}
	_check(PlantCycle.choices(seeds, saplings) == ["seed:carrot", "seed:corn", "sapling:apple", "sapling:pear"], "plant cycle: seeds first, then saplings in shop order")
	_check(PlantCycle.next("seed:corn", seeds, saplings) == "sapling:apple", "plant cycle: last seed goes on to the first sapling")
	_check(PlantCycle.next("sapling:pear", seeds, saplings) == "seed:carrot", "plant cycle: wraps back to the first seed")
	_check(PlantCycle.next("sapling:apple", {}, {"apple": 1}) == "sapling:apple", "plant cycle: stays put when nothing else is owned")
	_check(PlantCycle.next("sapling:cherry", seeds, saplings) == "sapling:pear", "plant cycle: a type you used up moves on to the next owned one")
	_check(PlantCycle.next("seed:carrot", {}, {}) == "seed:carrot", "plant cycle: nothing owned stays put")


func _test_orchard() -> void:
	var game := _game()
	game.reset()
	_check(not game.buy_sapling("apple"), "orchard: can't buy a sapling with 0 gold")
	game.gold = 500
	_check(game.buy_sapling("apple") and game.sapling_count("apple") == 1 and game.gold == 440, "orchard: sapling costs its price")
	_check(game.next_sapling() == "apple", "orchard: next sapling is the one you own")
	_check(game.use_sapling("apple") and not game.use_sapling("apple"), "orchard: a sapling is used up")

	var orchard := _new_orchard()
	var cell := Vector2i(11, 11)
	_check(not orchard.can_plant(Vector2i(2, 2)), "orchard: can't plant outside the orchard")
	_check(orchard.plant(cell, "apple") and orchard.has_tree(cell), "orchard: plant a tree")
	_check(not orchard.plant(cell, "pear"), "orchard: one tree per cell")
	_check(not orchard.can_plant(Vector2i(12, 11)) and orchard.can_plant(Vector2i(13, 11)), "orchard: trees keep one cell apart")
	_check(orchard.stage(cell) == 0 and not orchard.has_fruit(cell), "orchard: starts as a sapling")
	for day in Orchard.YOUNG_DAYS:
		orchard.new_day()
	_check(orchard.stage(cell) == 1, "orchard: young after YOUNG_DAYS")
	for day in Orchard.MATURE_DAYS - Orchard.YOUNG_DAYS:
		orchard.new_day()
	_check(orchard.stage(cell) == 2 and not orchard.has_fruit(cell), "orchard: grown but no fruit yet")
	for day in Orchard.FRUIT_DAYS - 1:
		orchard.new_day()
	_check(not orchard.has_fruit(cell), "orchard: fruit takes FRUIT_DAYS after growing up")
	orchard.new_day()
	_check(orchard.has_fruit(cell), "orchard: fruit appears")
	var data: Dictionary = _through_json(orchard.to_save())
	var other := _new_orchard()
	other.from_save(data)
	_check(other.tree_count() == 1 and other.has_fruit(cell) and other.stage(cell) == 2, "orchard: save round trip")
	_check(orchard.harvest(cell) == "apple" and not orchard.has_fruit(cell), "orchard: picking returns the tree id and empties it")
	_check(orchard.harvest(cell) == "", "orchard: nothing to pick twice")
	for day in Orchard.FRUIT_DAYS:
		orchard.new_day()
	_check(orchard.has_fruit(cell), "orchard: fruit grows back")
	other.from_save({"trees": [[11, 11, {"id": "bogus"}], [1, 1, {"id": "apple"}], "junk", [12, 12]]})
	_check(other.tree_count() == 0, "orchard: bad save entries are skipped")

	game.reset()
	game.add_fruit("pear", 2)
	game.add_crop("carrot")
	game.saplings = {"cherry": 1}
	_check(game.bag_total() == 3, "orchard: bag counts fruit and crops")
	var expected: int = 2 * int(Orchard.TYPES["pear"]["fruit_price"]) + int(Crop.TYPES["carrot"]["sell_price"])
	_check(game.bag_value() == expected, "orchard: bag value includes fruit")
	var saved: Dictionary = _through_json(game.to_save())
	game.reset()
	game.from_save(saved)
	_check(game.fruit_in_bag == {"pear": 2} and game.saplings == {"cherry": 1}, "orchard: bag fruit and saplings round trip")
	_check(game.sell_crops() == expected and game.bag_total() == 0, "orchard: selling empties fruit too")
	game.reset()
	orchard.queue_free()
	other.queue_free()


func _test_save_file() -> void:
	var save: Node = root.get_node("SaveGame")
	var real_path: String = save.path
	save.path = "user://test_save_unit.json"
	save.delete()
	_check(not save.has_save(), "no file means no save")
	_check(not save.save(), "nothing registered means nothing saved")
	var dummy := _Dummy.new()
	dummy.value = 7
	save.register("dummy", dummy)
	_check(save.save() and save.has_save(), "save writes a readable file")
	dummy.value = 0
	_check(save.load_game() and dummy.value == 7, "load gives the data back to the registered system")
	var file := FileAccess.open(save.path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 99, "sections": {"dummy": {"value": 1}}}))
	file.close()
	_check(not save.has_save() and not save.load_game(), "another version counts as no save")
	file = FileAccess.open(save.path, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	_check(not save.has_save() and not save.load_game(), "a damaged file counts as no save")
	file = FileAccess.open(save.path, FileAccess.WRITE)
	file.store_string("[1, 2]")
	file.close()
	_check(not save.has_save(), "a file that isn't an object counts as no save")
	save.delete()
	_check(not save.has_save(), "delete removes the save")
	save.unregister_all()
	save.path = real_path


func _test_save_bad_data() -> void:
	var game := _game()
	game.reset()
	game.from_save({"day": "x", "gold": -5, "seeds": {"nope": 3, "carrot": "a", "corn": 2}, "restored": ["well", "ghost", 4], "time_left": 9999})
	_check(game.day == 1 and game.gold == 0, "game: bad numbers fall back")
	_check(game.seeds == {"corn": 2}, "game: unknown seed ids and bad counts are dropped")
	_check(game.restored == {"well": true}, "game: unknown projects are dropped")
	_check(game.time_left == game.DAY_LENGTH, "game: time is clamped")
	game.reset()
	var farm := _new_farm()
	farm.from_save({"soil": [[1, 1, 0], [999, 999, 0], "x", [2, 2]], "crops": [[1, 1, {"id": "carrot", "stage": 99, "bites": 99}], [5, 5, {"id": "carrot"}], [1, 1, {"id": "bogus"}], [1]]})
	_check(farm.is_tilled(Vector2i(1, 1)) and not farm.is_tilled(Vector2i(999, 999)), "farm: out of bounds and damaged soil skipped")
	_check(farm.crop_count() == 1 and farm.get_crop(Vector2i(1, 1)).is_ripe(), "farm: bad crops skipped, stage clamped")
	farm.from_save({})
	_check(farm.crop_count() == 0 and not farm.is_tilled(Vector2i(1, 1)), "farm: empty data clears everything")
	farm.queue_free()


func _test_gayle_brain() -> void:
	var farm := _new_farm()
	var near := Vector2i(5, 5)
	var far := Vector2i(5, 5 + GayleBrain.WATER_REACH + 2)
	var wet := Vector2i(6, 5)
	for cell in [near, far, wet]:
		farm.till(cell)
		farm.plant(cell)
	farm.water(wet)
	var own := Vector2i(5, 6)
	var from := farm.cell_center(own)
	_check(GayleBrain.dry_crop_cell(farm, own, from) == near, "gayle waters the dry crop in reach, not the wet or far one")
	farm.water(near)
	_check(GayleBrain.dry_crop_cell(farm, own, from) == GayleBrain.NO_CELL, "gayle has nothing to water when all crops in reach are wet")
	farm.till(Vector2i(8, 6))  # soil without a crop is not worth watering
	_check(GayleBrain.dry_crop_cell(farm, own, from) == GayleBrain.NO_CELL, "gayle ignores empty soil")

	var crop_pos := farm.get_crop(near).global_position
	var eater := Node2D.new()
	eater.global_position = crop_pos + Vector2(2, 0)
	var walker := Node2D.new()
	walker.global_position = crop_pos + Vector2(60, 0)
	root.add_child(eater)
	root.add_child(walker)
	var enemies := [walker, eater]
	_check(GayleBrain.eating_enemy(enemies, farm, crop_pos, crop_pos, 150.0) == eater, "gayle picks the slime that is eating, not one walking")
	_check(GayleBrain.eating_enemy(enemies, farm, crop_pos, crop_pos + Vector2(500, 0), 150.0) == null, "gayle ignores slimes too far from her anchor")
	_check(GayleBrain.eating_enemy([walker], farm, crop_pos, crop_pos, 150.0) == null, "no one is eating: no target")
	eater.queue_free()
	walker.queue_free()
	farm.queue_free()


class _Dummy extends Node:
	var value := 0

	func to_save() -> Dictionary:
		return {"value": value}

	func from_save(data: Dictionary) -> void:
		value = int(data["value"])


func _test_animals() -> void:
	var game := _game()
	game.reset()
	for id: String in AnimalTypes.ids():
		var data: Dictionary = AnimalTypes.TYPES[id]
		_check(int(data["price"]) > 0 and int(data["max"]) > 0, "%s has a price and a pen limit" % id)
		_check(AnimalTypes.PRODUCTS.has(data["product"]), "%s gives a known product" % id)
		_check(not Restoration.project(data["requires"]).is_empty(), "%s needs a real restoration project" % id)
		_check(WorldLayout.area(data["pen"]).size != Vector2i.ZERO, "%s has a pen on the map" % id)
		_check(ResourceLoader.exists(data["sheet"]), "%s sprite sheet exists" % id)
	game.gold = 1000
	_check(not game.buy_animal("chicken"), "no chicken before the coop is restored")
	_check(AnimalTypes.block_reason("chicken", game.restored, 0, 1000) == "Restore the chicken coop first.", "reason names the coop")
	game.restored["chicken_coop"] = true
	var bought := []
	game.animal_bought.connect(func(id: String) -> void: bought.append(id))
	_check(not game.buy_animal("cow"), "no cow before the barn is restored")
	var price: int = AnimalTypes.TYPES["chicken"]["price"]
	_check(game.buy_animal("chicken") and game.gold == 1000 - price, "chicken costs its price")
	_check(game.animal_count("chicken") == 1 and bought == ["chicken"], "bought chicken is counted and announced")
	for i in int(AnimalTypes.TYPES["chicken"]["max"]) - 1:
		game.buy_animal("chicken")
	var gold_when_full: int = game.gold
	_check(not game.buy_animal("chicken") and game.gold == gold_when_full, "pen limit stops more chickens")
	game.gold = 1
	game.restored["barn"] = true
	_check(not game.buy_animal("cow"), "can't afford a cow")

	game.reset()
	game.add_crop("carrot")
	game.add_product("egg")
	game.add_product("egg")
	game.add_product("milk")
	var expected: int = int(Crop.TYPES["carrot"]["sell_price"]) + 2 * int(AnimalTypes.PRODUCTS["egg"]["sell_price"]) + int(AnimalTypes.PRODUCTS["milk"]["sell_price"])
	_check(game.bag_value() == expected, "bag value counts eggs and milk")
	_check(game.sell_crops() == expected and game.products_in_bag.is_empty(), "selling empties the products too")

	game.restored = {"chicken_coop": true, "barn": true}
	game.animals = {"chicken": 2, "cow": 1}
	game.products_in_bag = {"egg": 3}
	var saved: Dictionary = _through_json(game.to_save())
	game.reset()
	game.from_save(saved)
	_check(game.animals == {"chicken": 2, "cow": 1} and game.products_in_bag == {"egg": 3}, "animals and products round trip")
	game.from_save({"animals": {"chicken": 99, "dragon": 2, "cow": "x"}, "products_in_bag": {"egg": -4, "gold": 1}})
	_check(game.animals == {"chicken": AnimalTypes.TYPES["chicken"]["max"]} and game.products_in_bag.is_empty(), "bad animal data is cleaned up")
	game.reset()


func _test_farm_goals() -> void:
	var goals := FarmGoals.build({})
	var ids := []
	for goal in goals:
		ids.append(goal["id"])
	_check(ids.slice(0, 5) == ["harvest", "sell", "restore_well", "restore_farmhouse", "sleep"], "goals start with farm, sell, well, farmhouse, sleep")
	_check(ids.find("restore_chicken_coop") < ids.find("chicken") and ids.find("restore_barn") < ids.find("cow"), "an animal goal follows its building")
	_check(ids.find("restore_windmill") < ids.find("restore_greenhouse") and ids[ids.size() - 1] == "saved", "greenhouse is last before the saved goal")
	_check(FarmGoals.current(goals)["id"] == "harvest", "first goal is the current one on a new game")
	_check(FarmGoals.tracker_text(goals) == "Next: Plant and harvest a crop", "tracker names the first goal")

	var well := _goal_by_id(FarmGoals.build({"gold": 80, "milestones": {"harvested": true, "sold": true}}), "restore_well")
	_check(well["text"] == "Restore the Well 80/150g" and well["progress"] == 80 and well["target"] == 150 and not well["done"], "restore goal shows gold progress")
	_check(well["where"] == "", "no guide target while the gold is missing")
	var ready := FarmGoals.build({"gold": 150, "milestones": {"harvested": true, "sold": true}})
	_check(FarmGoals.current(ready)["id"] == "restore_well", "current goal is the well once farming goals are done")
	_check(FarmGoals.tracker_text(ready) == "Next: Restore the Well - go to the board!", "affordable restore says go to the board")
	_check(FarmGoals.current(ready)["where"] == "board", "affordable restore points at the board")
	var rich := _goal_by_id(FarmGoals.build({"gold": 9999}), "restore_barn")
	_check(rich["progress"] == 800 and not rich["done"], "progress is capped at the price")

	var after_well := FarmGoals.build({"gold": 0, "restored": {"well": true}, "milestones": {"harvested": true, "sold": true}})
	_check(_goal_by_id(after_well, "restore_well")["done"] and FarmGoals.current(after_well)["id"] == "restore_farmhouse", "done goals are ticked and the next one is current")
	_check(_goal_by_id(after_well, "saved")["text"] == "Save the farm 1/6", "saved goal counts restored buildings")

	var chicken := FarmGoals.build({"restored": {"chicken_coop": true}})
	_check(_goal_by_id(chicken, "chicken")["where"] == "stall" and not _goal_by_id(chicken, "chicken")["done"], "buy a chicken points at Azy")
	_check(_goal_by_id(FarmGoals.build({"chickens": 2}), "chicken")["done"], "owning a chicken ticks the goal")
	_check(_goal_by_id(FarmGoals.build({}), "orchard")["where"] == "stall", "no sapling: buy one at Azy")
	_check(_goal_by_id(FarmGoals.build({"saplings": 1}), "orchard")["where"] == "orchard", "sapling in the bag: go to the orchard")
	_check(_goal_by_id(FarmGoals.build({"milestones": {"fruit_tree": true}}), "orchard")["done"], "planting a tree ticks the orchard goal")
	_check(_goal_by_id(FarmGoals.build({"milestones": {"fenced": true}}), "fence")["done"], "building a fence ticks the fence goal")

	var everything := {"gold": 0, "chickens": 1, "cows": 1, "restored": {}, "milestones": {}}
	for id in Restoration.ids():
		everything["restored"][id] = true
	for id in FarmGoals.MILESTONES:
		everything["milestones"][id] = true
	var finished := FarmGoals.build(everything)
	_check(FarmGoals.current(finished).is_empty(), "no current goal when everything is done")
	_check(FarmGoals.tracker_text(finished) == FarmGoals.SAVED_TEXT, "tracker says the farm is saved")
	_check(_goal_by_id(finished, "saved")["text"] == "Farm saved!", "last goal reads Farm saved!")

	# Game side: firsts are remembered, saved and read back (old saves without the list are guessed).
	var game := _game()
	game.reset()
	game.add_crop("carrot")
	game.sell_crops()
	game.add_gold(10)
	_check(game.milestones.has("harvested") and game.milestones.has("sold"), "harvesting and selling are remembered")
	var saved: Dictionary = _through_json(game.to_save())
	game.reset()
	game.from_save(saved)
	_check(game.milestones.has("sold") and not game.milestones.has("slept"), "milestones round trip")
	game.from_save({"milestones": ["slept", "dragon", 4]})
	_check(game.milestones == {"slept": true}, "bad milestone data is cleaned up")
	game.from_save({"restored": ["well"]})
	_check(game.milestones.has("sold"), "an old save with a restored building counts as harvested and sold")
	game.reset()


func _test_inventory_rows() -> void:
	_check(InventoryRows.backpack({}).is_empty() and InventoryRows.storage({}).is_empty(), "empty state gives empty inventory pages")
	var state := {
		"seeds": {"carrot": 6, "tomato": 0, "corn": 2},
		"saplings": {"pear": 1},
		"fences": 3,
		"crops": {"pumpkin": 2, "carrot": 1},
		"fruit": {"apple": 3},
		"products": {"egg": 4, "milk": 1},
	}
	var pack := InventoryRows.backpack(state)
	var kinds: Array[String] = []
	for row in pack:
		kinds.append("%s:%s:%d" % [row["kind"], row["id"], row["count"]])
	_check(kinds == ["seed:carrot:6", "seed:corn:2", "sapling:pear:1", "fence:fence:3"], "backpack lists seeds, saplings and fences with counts, empty types left out")
	var stored := InventoryRows.storage(state)
	var ids: Array[String] = []
	for row in stored:
		ids.append(String(row["id"]))
	_check(ids == ["carrot", "pumpkin", "apple", "egg", "milk"], "storage lists crops, fruit, then products")
	var expected: int = int(Crop.TYPES["carrot"]["sell_price"]) + 2 * int(Crop.TYPES["pumpkin"]["sell_price"])
	expected += 3 * int(Orchard.TYPES["apple"]["fruit_price"])
	expected += 4 * int(AnimalTypes.PRODUCTS["egg"]["sell_price"]) + int(AnimalTypes.PRODUCTS["milk"]["sell_price"])
	_check(InventoryRows.storage_total(stored) == expected, "storage total adds up every sell price")
	var game := _game()
	game.reset()
	game.add_crop("carrot")
	game.add_fruit("pear", 2)
	game.add_product("egg")
	_check(InventoryRows.storage_total(InventoryRows.storage(game.inventory_state())) == game.bag_value(), "storage total matches Game.bag_value()")
	game.reset()


func _test_loading_tips() -> void:
	_check(not LoadingTips.TIPS.is_empty(), "there are loading tips")
	_check(LoadingTips.tip(0) == LoadingTips.TIPS[0], "tip 0 is the first tip")
	_check(LoadingTips.TIPS.has(LoadingTips.tip(-7)), "a negative number still gives a tip")
	_check(LoadingTips.tip(LoadingTips.TIPS.size()) == LoadingTips.TIPS[0], "tips wrap around")
	_check(LoadingTips.percent([]) == 0, "no progress data means 0 percent")
	_check(LoadingTips.percent([0.456]) == 46, "progress 0.456 is 46 percent")
	_check(LoadingTips.percent([3.0]) == 100, "progress is clamped to 100")


func _test_settings() -> void:
	var settings := Settings.new()
	_check(settings.master == 1.0 and settings.music == 1.0 and settings.sfx == 1.0, "volumes start at full")
	_check(settings.key_for("interact") == KEY_E, "E interacts by default")
	_check(settings.key_for("interact", 1) == -1, "interact has no second key")
	settings.set_volume("music", 3.0)
	_check(settings.music == 1.0, "volume is clamped to 1")
	settings.set_volume("sfx", -1.0)
	_check(settings.sfx == 0.0, "volume is clamped to 0")

	var free := settings.rebind("interact", 0, KEY_F)
	_check(free["ok"] and settings.key_for("interact") == KEY_F, "a free key can be bound")
	_check(settings.owner_of(KEY_E).is_empty(), "the old key is free again")
	var swapped := settings.rebind("cycle_seed", 0, KEY_F)
	_check(swapped["ok"] and settings.key_for("cycle_seed") == KEY_F, "the clashing key moves over")
	_check(settings.key_for("interact") == KEY_Q, "the other action gets the old key (swap)")
	_check(str(swapped["message"]).contains("swapped"), "a swap says so")
	_check(settings.rebind("interact", 0, KEY_ESCAPE)["ok"] == false, "Esc is reserved")
	_check(settings.rebind("interact", 0, KEY_ENTER)["ok"] == false, "Enter is reserved")
	_check(settings.rebind("pause", 0, KEY_P)["ok"] == false, "pause can't be rebound")
	_check(settings.rebind("interact", 3, KEY_P)["ok"] == false, "a missing slot is refused")
	_check(settings.rebind("move_up", 1, KEY_W)["ok"] and settings.key_for("move_up", 0) == KEY_UP, "swap works inside one action")
	var seen := {}
	var unique := true
	for action: String in settings.bindings:
		for key: int in settings.bindings[action]:
			unique = unique and not seen.has(key)
			seen[key] = true
	_check(unique, "no key is bound twice after rebinding")

	settings.reset_bindings()
	_check(settings.key_for("interact") == KEY_E and settings.key_for("move_up", 0) == KEY_W, "reset restores the defaults")
	_check(Settings.key_label(KEY_E) == "E" and Settings.key_label(KEY_ESCAPE) == "Esc", "key labels")
	_check(Settings.key_label(-1) == "-", "no key shows a dash")
	_check(settings.fill_keys("{interact} / {move}") == "E / W A S D", "how to play uses the current keys")

	var path := "user://settings_test.cfg"
	settings.master = 0.5
	settings.music = 0.3
	settings.sfx = 0.0
	settings.fullscreen = true
	settings.rebind("use_tool", 0, KEY_X)
	_check(settings.save_file(path), "settings are written")
	var loaded := Settings.new()
	loaded.load_file(path)
	_check(is_equal_approx(loaded.master, 0.5) and is_equal_approx(loaded.music, 0.3) and loaded.sfx == 0.0, "volumes load back")
	_check(loaded.fullscreen, "fullscreen loads back")
	_check(loaded.key_for("use_tool", 0) == KEY_X and loaded.key_for("use_tool", 1) == KEY_J, "bindings load back")
	var missing := Settings.new()
	missing.load_file("user://does_not_exist.cfg")
	_check(missing.master == 1.0 and missing.key_for("interact") == KEY_E, "a missing file leaves the defaults")

	var bad := ConfigFile.new()
	bad.set_value("audio", "master", "loud")
	bad.set_value("keys", "interact", [KEY_W])  # clashes with move_up
	bad.set_value("keys", "tool_1", "one")
	bad.save(path)
	var damaged := Settings.new()
	damaged.load_file(path)
	_check(damaged.master == 1.0, "a bad volume falls back to full")
	_check(damaged.key_for("interact") == KEY_E and damaged.key_for("tool_1") == KEY_1, "bad or clashing keys fall back to the defaults")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _goal_by_id(goals: Array[Dictionary], id: String) -> Dictionary:
	for goal in goals:
		if goal["id"] == id:
			return goal
	return {}
