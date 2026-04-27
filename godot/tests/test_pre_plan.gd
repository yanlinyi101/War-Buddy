extends "res://addons/gut/test.gd"

const PrePlanScript = preload("res://scripts/command/pre_plan.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

func test_trigger_match_with_no_conditions_passes():
	var t = PrePlanScript.PrePlanTrigger.new()
	t.event = &"match_start"
	assert_true(t.matches({"event": &"match_start"}))

func test_trigger_within_seconds_of_start_pass():
	var t = PrePlanScript.PrePlanTrigger.new()
	t.event = &"match_start"
	t.conditions = {"within_seconds_of_start": 60}
	assert_true(t.matches({"event": &"match_start", "elapsed_s": 30}))
	assert_false(t.matches({"event": &"match_start", "elapsed_s": 61}))

func test_trigger_event_mismatch_fails():
	var t = PrePlanScript.PrePlanTrigger.new()
	t.event = &"match_start"
	assert_false(t.matches({"event": &"unit_died"}))

func test_trigger_enemy_count_at_least_pass():
	var t = PrePlanScript.PrePlanTrigger.new()
	t.event = &"sighting"
	t.conditions = {"enemy_count_at_least": 3}
	assert_true(t.matches({"event": &"sighting", "enemy_count": 4}))
	assert_false(t.matches({"event": &"sighting", "enemy_count": 2}))

func test_trigger_unknown_condition_is_ignored():
	var t = PrePlanScript.PrePlanTrigger.new()
	t.event = &"match_start"
	t.conditions = {"made_up_key": "value"}
	# Unknown keys are ignored (forward-compat); event match alone passes.
	assert_true(t.matches({"event": &"match_start"}))

func test_pre_plan_has_default_enabled_true():
	var p = PrePlanScript.PrePlan.new()
	assert_true(p.enabled)
