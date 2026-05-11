extends "res://addons/gut/test.gd"

const FactionStateScript = preload("res://scripts/state/faction_state.gd")

func before_each():
	ProductionService._reset_for_test()

func _player_faction() -> Resource:
	var f = FactionStateScript.new()
	f.faction_id = &"player"
	f.minerals = 1000
	f.gas = 200
	f.supply_used = 0
	f.supply_max = 20
	f.current_tier = 1
	f.buildings_completed = [&"hq", &"barracks"] as Array[StringName]
	return f

func _hq_def() -> Resource:
	return EntityLibrary.building(&"hq")

func _barracks_def() -> Resource:
	return EntityLibrary.building(&"barracks")

func _factory_def() -> Resource:
	return EntityLibrary.building(&"factory")

# --- validate_train ---

func test_validate_train_ok_for_worker_from_hq():
	var f = _player_faction()
	var r = ProductionService.validate_train(f, _hq_def(), &"worker_basic")
	assert_true(r["ok"])

func test_validate_train_rejects_unknown_unit():
	var f = _player_faction()
	var r = ProductionService.validate_train(f, _hq_def(), &"ghost_unit")
	assert_false(r["ok"])
	assert_eq(r["reason"], &"unknown_unit")

func test_validate_train_rejects_unit_not_in_produces():
	var f = _player_faction()
	# hq produces worker_basic; frontline isn't in hq.produces.
	var r = ProductionService.validate_train(f, _hq_def(), &"frontline_basic")
	assert_false(r["ok"])
	assert_eq(r["reason"], &"building_cannot_produce_unit")

func test_validate_train_rejects_tier_locked():
	var f = _player_faction()   # tier 1
	# siege_basic is tier 2 — barracks doesn't even produce it, but
	# even from factory it needs tier 2 unlocked.
	var r = ProductionService.validate_train(f, _factory_def(), &"siege_basic")
	assert_false(r["ok"])
	assert_eq(r["reason"], &"tier_locked")

func test_validate_train_rejects_missing_prerequisite():
	var f = _player_faction()
	f.current_tier = 2
	# siege_basic requires `forge` in buildings_completed.
	var r = ProductionService.validate_train(f, _factory_def(), &"siege_basic")
	assert_false(r["ok"])
	assert_eq(r["reason"], &"missing_prerequisite")

func test_validate_train_rejects_supply_blocked():
	var f = _player_faction()
	f.supply_used = 19   # +2 for frontline → 21 > 20 cap
	var r = ProductionService.validate_train(f, _barracks_def(), &"frontline_basic")
	assert_false(r["ok"])
	assert_eq(r["reason"], &"supply_blocked")

func test_validate_train_rejects_insufficient_resources():
	var f = _player_faction()
	f.minerals = 10
	var r = ProductionService.validate_train(f, _barracks_def(), &"frontline_basic")
	assert_false(r["ok"])
	assert_eq(r["reason"], &"insufficient_resources")

# --- enqueue_train ---

func test_enqueue_deducts_cost_and_reserves_supply():
	var f = _player_faction()
	var minerals_before = f.minerals
	var supply_before = f.supply_used
	var r = ProductionService.enqueue_train(f, 42, _barracks_def(), &"frontline_basic")
	assert_true(r["ok"])
	# frontline_basic costs 100 mineral / 25 gas / 2 supply.
	assert_eq(f.minerals, minerals_before - 100)
	assert_eq(f.gas, 200 - 25)
	assert_eq(f.supply_used, supply_before + 2)

func test_enqueue_appends_to_queue():
	var f = _player_faction()
	ProductionService.enqueue_train(f, 100, _barracks_def(), &"frontline_basic")
	ProductionService.enqueue_train(f, 100, _barracks_def(), &"ranged_basic")
	assert_eq(ProductionService.queue_length(100), 2)
	var names = ProductionService.queue_unit_ids(100)
	assert_eq(names[0], "frontline_basic")
	assert_eq(names[1], "ranged_basic")

# --- tick ---

func test_tick_completes_job_emits_signal():
	var f = _player_faction()
	ProductionService.enqueue_train(f, 200, _hq_def(), &"worker_basic")
	# worker_basic build_time is 12s — tick 13 to definitely complete.
	watch_signals(ProductionService)
	ProductionService.tick(f, 13.0)
	assert_eq(ProductionService.queue_length(200), 0)
	assert_signal_emit_count(ProductionService, "training_completed", 1)

func test_tick_in_progress_does_not_complete():
	var f = _player_faction()
	ProductionService.enqueue_train(f, 300, _hq_def(), &"worker_basic")
	ProductionService.tick(f, 1.0)
	assert_eq(ProductionService.queue_length(300), 1)

# --- cancel_head ---

func test_cancel_refunds_75_percent_and_returns_supply():
	var f = _player_faction()
	ProductionService.enqueue_train(f, 400, _barracks_def(), &"frontline_basic")
	var post_minerals = f.minerals
	var post_supply = f.supply_used
	ProductionService.cancel_head(f, 400)
	# Refund: int(100 * 0.75) = 75 minerals; int(25 * 0.75) = 18 gas.
	assert_eq(f.minerals, post_minerals + 75)
	assert_eq(f.gas, 200 - 25 + 18)
	assert_eq(f.supply_used, post_supply - 2)
	assert_eq(ProductionService.queue_length(400), 0)
