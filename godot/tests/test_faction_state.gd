extends "res://addons/gut/test.gd"

const FactionStateScript = preload("res://scripts/state/faction_state.gd")

func _make_faction() -> Resource:
	var f = FactionStateScript.new()
	f.faction_id = &"test"
	f.minerals = 200
	f.gas = 75
	f.supply_max = 12
	f.supply_used = 5
	f.current_tier = 1
	return f

func test_has_resources_true_when_enough():
	var f = _make_faction()
	assert_true(f.has_resources(150, 50))

func test_has_resources_false_when_short():
	var f = _make_faction()
	assert_false(f.has_resources(150, 100))

func test_spend_deducts_when_affordable():
	var f = _make_faction()
	assert_true(f.spend(150, 50))
	assert_eq(f.minerals, 50)
	assert_eq(f.gas, 25)

func test_spend_refuses_when_short():
	var f = _make_faction()
	assert_false(f.spend(999, 0))
	assert_eq(f.minerals, 200)

func test_refund_adds_back():
	var f = _make_faction()
	f.refund(75, 25)
	assert_eq(f.minerals, 275)
	assert_eq(f.gas, 100)

func test_supply_available():
	var f = _make_faction()
	assert_eq(f.supply_available(), 7)

func test_tech_state_snapshot_shape():
	var f = _make_faction()
	f.current_tier = 2
	f.buildings_completed = [&"hq", &"barracks"] as Array[StringName]
	var snap = f.tech_state_snapshot()
	assert_eq(snap["current_tier"], 2)
	assert_eq(snap["buildings_completed"].size(), 2)
	assert_true(snap["buildings_completed"].has("hq"))

# --- GameState autoload integration ---

func test_game_state_seeds_player_faction_on_mark_started():
	GameState._reset_for_test()
	GameState.mark_match_started()
	var f = GameState.get_faction(&"player")
	assert_ne(f, null)
	assert_eq(f.faction_id, &"player")
	assert_eq(f.current_tier, 1)

func test_game_state_current_tier_reads_faction():
	GameState._reset_for_test()
	GameState.mark_match_started()
	assert_eq(GameState.current_tier(&"player"), 1)
	GameState.get_faction(&"player").current_tier = 2
	assert_eq(GameState.current_tier(&"player"), 2)

func test_game_state_is_unit_buildable_respects_supply():
	GameState._reset_for_test()
	GameState.mark_match_started()
	var f = GameState.get_faction(&"player")
	f.supply_used = 10   # max = 10 → no headroom
	var r = GameState.is_unit_buildable(&"player", &"frontline_basic")
	assert_false(r["ok"])
	assert_eq(r["missing_supply"], 1)
