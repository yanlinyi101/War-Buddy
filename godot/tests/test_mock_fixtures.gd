extends "res://addons/gut/test.gd"

# Spec 12 §6.3 — verify the mock-plan fixture library loads, holds the
# right shape, and round-trips through to_dict/from_dict so a future
# spec 07 schema change immediately breaks the fixtures (visible in CI).

const ActionPlanScript = preload("res://scripts/command/action_plan.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

const PATHS := [
	"res://tests/fixtures/mock_plans/attack_b4.tres",
	"res://tests/fixtures/mock_plans/eco_boost.tres",
	"res://tests/fixtures/mock_plans/refusal_hold_fire.tres",
]

func test_all_fixtures_load():
	for p in PATHS:
		var r = load(p)
		assert_ne(r, null, "fixture failed to load: %s" % p)

func test_attack_fixture_targets_landmark():
	var p = load("res://tests/fixtures/mock_plans/attack_b4.tres")
	assert_eq(p.id, &"fix_plan_attack_b4")
	assert_eq(p.orders.size(), 1)
	var o = p.orders[0]
	assert_eq(o.type_id, &"attack")
	assert_eq(o.target_landmark, &"EnemyBuildingA")

func test_eco_fixture_carries_build_id_in_params():
	var p = load("res://tests/fixtures/mock_plans/eco_boost.tres")
	var o = p.orders[0]
	assert_eq(o.type_id, &"build")
	assert_eq(String(o.params.get("build_id", "")), "supply_depot")

func test_refusal_fixture_has_no_orders():
	var p = load("res://tests/fixtures/mock_plans/refusal_hold_fire.tres")
	assert_eq(p.orders.size(), 0)
	assert_gt(p.rationale.length(), 0)

func test_attack_fixture_round_trips_through_to_dict():
	var p = load("res://tests/fixtures/mock_plans/attack_b4.tres")
	var d = p.to_dict()
	var p2 = ActionPlanScript.from_dict(d)
	assert_eq(p2.id, p.id)
	assert_eq(p2.orders.size(), p.orders.size())
	assert_eq(p2.orders[0].type_id, p.orders[0].type_id)
