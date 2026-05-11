extends "res://addons/gut/test.gd"

# Doc 09 §6 — tier-up via tech building completion. Forge unlocks T2,
# Arcanum unlocks T3. Non-tech buildings (barracks, hq) don't bump tier.

func before_each():
	GameState._reset_for_test()
	GameState.mark_match_started()

func test_starting_tier_is_one():
	assert_eq(GameState.current_tier(&"player"), 1)

func test_starting_seed_matches_spec_10_5():
	var f = GameState.get_faction(&"player")
	assert_eq(f.minerals, 50)
	assert_eq(f.supply_used, 6)
	assert_eq(f.supply_max, 10)
	assert_eq(f.current_tier, 1)
	assert_true(f.buildings_completed.has(&"hq"))

func test_register_forge_bumps_to_tier_2():
	GameState.register_completed_building(&"player", &"forge")
	assert_eq(GameState.current_tier(&"player"), 2)
	var f = GameState.get_faction(&"player")
	assert_true(f.buildings_completed.has(&"forge"))

func test_register_arcanum_bumps_to_tier_3():
	GameState.register_completed_building(&"player", &"forge")
	GameState.register_completed_building(&"player", &"arcanum")
	assert_eq(GameState.current_tier(&"player"), 3)

func test_register_non_tech_building_does_not_bump_tier():
	GameState.register_completed_building(&"player", &"barracks")
	assert_eq(GameState.current_tier(&"player"), 1)

func test_register_supply_depot_increases_supply_max():
	var pre = GameState.get_faction(&"player").supply_max
	GameState.register_completed_building(&"player", &"supply_depot")
	assert_eq(GameState.get_faction(&"player").supply_max, pre + 8)

func test_register_unknown_faction_returns_error():
	var r = GameState.register_completed_building(&"ghost", &"forge")
	assert_false(r["ok"])
	assert_eq(r["reason"], &"unknown_faction")

func test_register_same_building_twice_is_idempotent():
	GameState.register_completed_building(&"player", &"forge")
	GameState.register_completed_building(&"player", &"forge")
	var f = GameState.get_faction(&"player")
	# Only one `forge` entry.
	var count := 0
	for b in f.buildings_completed:
		if b == &"forge":
			count += 1
	assert_eq(count, 1)
