extends "res://addons/gut/test.gd"

# v0.11.0 — verifies the top-level PrePlanResource + PrePlanTrigger
# classes (promoted from inner classes to support .tres authoring).

const PrePlanTriggerScript = preload("res://scripts/command/pre_plan_trigger.gd")
const PrePlanResourceScript = preload("res://scripts/command/pre_plan_resource.gd")
const PrePlanRunnerScript = preload("res://scripts/command/pre_plan_runner.gd")
const CommandBusScript = preload("res://scripts/command/command_bus.gd")
const RegistryScript = preload("res://scripts/command/order_type_registry.gd")
const ControlPolicyScript = preload("res://scripts/command/control_policy.gd")

func test_top_level_trigger_matches_event():
	var t = PrePlanTriggerScript.new()
	t.event = &"match_start"
	assert_true(t.matches({"event": &"match_start", "elapsed_s": 5.0}))

func test_top_level_trigger_filters_by_within_seconds():
	var t = PrePlanTriggerScript.new()
	t.event = &"match_start"
	t.conditions = {"within_seconds_of_start": 10.0}
	assert_true(t.matches({"event": &"match_start", "elapsed_s": 5.0}))
	assert_false(t.matches({"event": &"match_start", "elapsed_s": 15.0}))

func test_sample_preplan_tres_loads():
	var p = load("res://data/preplans/sample_opening.tres")
	assert_ne(p, null)
	assert_eq(p.name, "Sample Opening")
	assert_eq(p.deputy, &"deputy")
	assert_ne(p.trigger, null)
	assert_eq(p.trigger.event, &"match_start")
	assert_true(p.enabled)

func test_runner_loads_dir_picks_up_sample():
	var r = PrePlanRunnerScript.new()
	add_child_autofree(r)
	# Runner's _bus must be set before notify_event, but load_from_directory
	# doesn't require it.
	var n = r.load_from_directory("res://data/preplans")
	assert_gt(n, 0)
