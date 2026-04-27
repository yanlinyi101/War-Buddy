extends "res://addons/gut/test.gd"

const CommandBusScript = preload("res://scripts/command/command_bus.gd")
const RegistryScript = preload("res://scripts/command/order_type_registry.gd")
const ControlPolicyScript = preload("res://scripts/command/control_policy.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")
const ActionPlanScript = preload("res://scripts/command/action_plan.gd")

func _make_bus() -> Node:
	var registry = RegistryScript.new()
	var def = RegistryScript.TypeDef.new()
	def.id = &"move"
	def.param_schema = {}
	def.min_targets = 1
	registry.register(def)

	var bus = CommandBusScript.new()
	bus.set_registry(registry)
	bus.set_policy(ControlPolicyScript.FullControlPolicy.new())
	add_child_autofree(registry)
	add_child_autofree(bus)
	# Disable file persistence in tests
	bus.persistence_enabled = false
	return bus

func _make_order(id: StringName) -> Resource:
	var o = TacticalOrderScript.new()
	o.id = id
	o.type_id = &"move"
	o.origin = TacticalOrderScript.Origin.SCRIPT
	o.issuer = TacticalOrderScript.Issuer.PLAYER
	o.target_position = Vector3(1, 0, 1)
	return o

func test_submit_orders_accepts_valid_order_emits_signal():
	var bus = _make_bus()
	watch_signals(bus)
	var result = bus.submit_orders([_make_order(&"ord_1")])
	assert_eq(result["accepted"].size(), 1)
	assert_eq(result["rejected"].size(), 0)
	assert_signal_emit_count(bus, "order_issued", 1)

func test_submit_orders_rejects_unknown_type_id():
	var bus = _make_bus()
	var o = _make_order(&"ord_2")
	o.type_id = &"ghost"
	var result = bus.submit_orders([o])
	assert_eq(result["accepted"].size(), 0)
	assert_eq(result["rejected"].size(), 1)
	assert_eq(result["rejected"][0]["reason"], &"unknown_type_id")

func test_submit_orders_rejects_untargeted_when_min_targets_required():
	var bus = _make_bus()
	var o = TacticalOrderScript.new()
	o.id = &"ord_3"
	o.type_id = &"move"
	o.origin = TacticalOrderScript.Origin.SCRIPT
	# no targeting fields set
	var result = bus.submit_orders([o])
	assert_eq(result["rejected"].size(), 1)
	assert_eq(result["rejected"][0]["reason"], &"target_required")

func test_submit_orders_rejects_duplicate_id():
	var bus = _make_bus()
	bus.submit_orders([_make_order(&"ord_4")])
	var result = bus.submit_orders([_make_order(&"ord_4")])
	assert_eq(result["rejected"].size(), 1)
	assert_eq(result["rejected"][0]["reason"], &"duplicate_id")

func test_submit_orders_rejects_when_status_not_pending():
	var bus = _make_bus()
	var o = _make_order(&"ord_5")
	o.status = &"executing"
	var result = bus.submit_orders([o])
	assert_eq(result["rejected"][0]["reason"], &"non_pending_status")

func test_submit_orders_rejects_when_policy_denies():
	var bus = _make_bus()
	bus.set_policy(ControlPolicyScript.HeroOnlyPolicy.new())
	var o = _make_order(&"ord_6")
	o.deputy = &"deputy"
	var result = bus.submit_orders([o])
	assert_eq(result["rejected"][0]["reason"], &"control_policy_denied")

func test_submit_plan_validates_invariants_then_dispatches():
	var bus = _make_bus()
	watch_signals(bus)
	var p = ActionPlanScript.new()
	p.id = &"plan_1"
	p.deputy = &"deputy"
	p.tier = ActionPlanScript.Tier.TACTICAL
	var o = _make_order(&"ord_7")
	o.deputy = &"deputy"
	o.origin = TacticalOrderScript.Origin.TACTICAL_VOICE
	o.issuer = TacticalOrderScript.Issuer.DEPUTY
	p.orders = [o] as Array[Resource]
	p.apply_invariants()
	var result = bus.submit_plan(p)
	assert_eq(result["accepted"].size(), 1)
	assert_signal_emit_count(bus, "plan_issued", 1)
	assert_signal_emit_count(bus, "order_issued", 1)

func test_submit_plan_rejects_when_invariants_violated():
	var bus = _make_bus()
	var p = ActionPlanScript.new()
	p.id = &"plan_2"
	p.deputy = &"deputy"
	p.tier = ActionPlanScript.Tier.TACTICAL
	var o = _make_order(&"ord_8")
	o.deputy = &"someone_else"  # mismatch
	p.orders = [o] as Array[Resource]
	var result = bus.submit_plan(p)
	assert_eq(result["accepted"].size(), 0)
	assert_eq(result["plan_rejected"], true)

func test_recent_buffers_preserve_order_and_truncate():
	var bus = _make_bus()
	for i in 5:
		bus.submit_orders([_make_order(StringName("ord_b%d" % i))])
	var got = bus.get_recent_orders(3)
	assert_eq(got.size(), 3)
	# Most recent first
	assert_eq(got[0].id, &"ord_b4")
	assert_eq(got[2].id, &"ord_b2")
