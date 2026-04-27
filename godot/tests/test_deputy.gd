extends "res://addons/gut/test.gd"

const DeputyScript = preload("res://scripts/ai/deputy.gd")
const PersonaScript = preload("res://scripts/ai/deputy_persona.gd")
const ActionPlanScript = preload("res://scripts/command/action_plan.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")
const RegistryScript = preload("res://scripts/command/order_type_registry.gd")
const ControlPolicyScript = preload("res://scripts/command/control_policy.gd")
const CommandBusScript = preload("res://scripts/command/command_bus.gd")

func _make_persona(allowed: Array[StringName]) -> Resource:
	var p = PersonaScript.new()
	p.persona_id = &"deputy_test"
	p.display_name = "Test Deputy"
	p.allowed_type_ids = allowed
	return p

func _make_bus_with_move() -> Node:
	var registry = RegistryScript.new()
	var def = RegistryScript.TypeDef.new()
	def.id = &"move"
	registry.register(def)
	var def2 = RegistryScript.TypeDef.new()
	def2.id = &"attack"
	registry.register(def2)
	add_child_autofree(registry)
	var bus = CommandBusScript.new()
	bus.set_registry(registry)
	bus.set_policy(ControlPolicyScript.FullControlPolicy.new())
	bus.persistence_enabled = false
	add_child_autofree(bus)
	return bus

func _make_plan(deputy: StringName, type_id: StringName) -> Resource:
	var plan = ActionPlanScript.new()
	plan.id = &"plan_t1"
	plan.deputy = deputy
	plan.tier = ActionPlanScript.Tier.TACTICAL
	plan.rationale = "test"
	var o = TacticalOrderScript.new()
	o.id = &"ord_t1"
	o.type_id = type_id
	o.origin = TacticalOrderScript.Origin.TACTICAL_VOICE
	o.issuer = TacticalOrderScript.Issuer.DEPUTY
	o.deputy = deputy
	o.target_position = Vector3(1, 0, 1)
	plan.orders = [o] as Array[Resource]
	plan.apply_invariants()
	return plan

func test_handle_plan_speaks_rationale_then_dispatches_to_bus():
	var bus = _make_bus_with_move()
	var d = DeputyScript.new()
	d.deputy_id = &"deputy"
	d.persona = _make_persona([&"move", &"attack"] as Array[StringName])
	d.bind_command_bus(bus)
	add_child_autofree(d)
	watch_signals(d)
	var plan = _make_plan(&"deputy", &"move")
	d.handle_plan(plan)
	assert_signal_emit_count(d, "spoke", 1)
	assert_eq(bus.get_recent_orders().size(), 1)

func test_handle_plan_filters_orders_by_persona_allowed_types():
	var bus = _make_bus_with_move()
	var d = DeputyScript.new()
	d.deputy_id = &"deputy"
	d.persona = _make_persona([&"move"] as Array[StringName])
	d.bind_command_bus(bus)
	add_child_autofree(d)
	watch_signals(d)
	# Plan asks for attack, persona forbids it → reject locally without hitting bus
	var plan = _make_plan(&"deputy", &"attack")
	d.handle_plan(plan)
	assert_eq(bus.get_recent_orders().size(), 0)
	assert_signal_emit_count(d, "plan_rejected_locally", 1)

func test_speak_emits_spoke_signal_with_text():
	var d = DeputyScript.new()
	d.deputy_id = &"deputy"
	add_child_autofree(d)
	watch_signals(d)
	d.speak("Hello commander.")
	assert_signal_emit_count(d, "spoke", 1)
	assert_signal_emitted_with_parameters(d, "spoke",
		["Hello commander.", &"deputy"])
