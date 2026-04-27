extends "res://addons/gut/test.gd"

const PrePlanRunnerScript = preload("res://scripts/command/pre_plan_runner.gd")
const PrePlanScript = preload("res://scripts/command/pre_plan.gd")
const CommandBusScript = preload("res://scripts/command/command_bus.gd")
const RegistryScript = preload("res://scripts/command/order_type_registry.gd")
const ControlPolicyScript = preload("res://scripts/command/control_policy.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

func _make_bus() -> Node:
	var registry = RegistryScript.new()
	var def = RegistryScript.TypeDef.new()
	def.id = &"move"
	registry.register(def)
	add_child_autofree(registry)
	var bus = CommandBusScript.new()
	bus.set_registry(registry)
	bus.set_policy(ControlPolicyScript.FullControlPolicy.new())
	bus.persistence_enabled = false
	add_child_autofree(bus)
	return bus

func _make_runner(bus: Node) -> Node:
	var r = PrePlanRunnerScript.new()
	r.set_command_bus(bus)
	add_child_autofree(r)
	return r

func _make_plan_with_event(event: StringName) -> Resource:
	var trigger = PrePlanScript.PrePlanTrigger.new()
	trigger.event = event
	var p = PrePlanScript.PrePlan.new()
	p.name = "test_plan"
	p.deputy = &"deputy"
	p.trigger = trigger
	var o = TacticalOrderScript.new()
	o.id = &"ord_pp_1"
	o.type_id = &"move"
	o.origin = TacticalOrderScript.Origin.PRE_PLAN
	o.issuer = TacticalOrderScript.Issuer.PLAYER
	o.target_position = Vector3(7, 0, 7)
	p.orders = [o] as Array[Resource]
	return p

func test_notify_event_fires_matching_plan():
	var bus = _make_bus()
	var runner = _make_runner(bus)
	runner.add_plan(_make_plan_with_event(&"match_start"))
	runner.notify_event(&"match_start", {})
	assert_eq(bus.get_recent_orders().size(), 1)

func test_notify_event_skips_non_matching():
	var bus = _make_bus()
	var runner = _make_runner(bus)
	runner.add_plan(_make_plan_with_event(&"match_start"))
	runner.notify_event(&"unit_died", {})
	assert_eq(bus.get_recent_orders().size(), 0)

func test_one_shot_plan_disables_after_first_fire():
	var bus = _make_bus()
	var runner = _make_runner(bus)
	var plan = _make_plan_with_event(&"match_start")
	runner.add_plan(plan)
	runner.notify_event(&"match_start", {})
	# Reset the order id so the second fire wouldn't be deduped at bus level
	plan.orders[0].id = &"ord_pp_2"
	runner.notify_event(&"match_start", {})
	assert_eq(bus.get_recent_orders().size(), 1)
	assert_false(plan.enabled)

func test_repeat_plan_respects_cooldown():
	var bus = _make_bus()
	var runner = _make_runner(bus)
	var plan = _make_plan_with_event(&"sighting")
	plan.repeat = true
	plan.cooldown_seconds = 60.0
	runner.add_plan(plan)
	runner.notify_event(&"sighting", {})
	# Same tick — should NOT fire again
	plan.orders[0].id = &"ord_pp_3"
	runner.notify_event(&"sighting", {})
	assert_eq(bus.get_recent_orders().size(), 1)
	# Simulate cooldown passing
	plan.last_fired_ms -= 70 * 1000
	plan.orders[0].id = &"ord_pp_4"
	runner.notify_event(&"sighting", {})
	assert_eq(bus.get_recent_orders().size(), 2)

func test_disabled_plan_never_fires():
	var bus = _make_bus()
	var runner = _make_runner(bus)
	var plan = _make_plan_with_event(&"match_start")
	plan.enabled = false
	runner.add_plan(plan)
	runner.notify_event(&"match_start", {})
	assert_eq(bus.get_recent_orders().size(), 0)
