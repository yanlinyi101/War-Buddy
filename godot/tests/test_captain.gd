extends "res://addons/gut/test.gd"

const CaptainScript = preload("res://scripts/ai/captain.gd")
const CaptainPersonaScript = preload("res://scripts/ai/captain_persona.gd")
const CaptainMemoryScript = preload("res://scripts/ai/captain_memory.gd")
const CommandBusScript = preload("res://scripts/command/command_bus.gd")
const RegistryScript = preload("res://scripts/command/order_type_registry.gd")
const ControlPolicyScript = preload("res://scripts/command/control_policy.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")
const ActionPlanScript = preload("res://scripts/command/action_plan.gd")

func _make_bus() -> Node:
	var registry = RegistryScript.new()
	for tid in [&"move", &"attack", &"stop"]:
		var def = RegistryScript.TypeDef.new()
		def.id = tid
		def.param_schema = {}
		def.min_targets = 1 if tid != &"stop" else 0
		registry.register(def)
	var bus = CommandBusScript.new()
	bus.set_registry(registry)
	bus.set_policy(ControlPolicyScript.FullControlPolicy.new())
	bus.persistence_enabled = false
	add_child_autofree(registry)
	add_child_autofree(bus)
	return bus

func _make_captain(bus: Node) -> Node:
	var persona = CaptainPersonaScript.new()
	persona.persona_id = &"captain_test"
	persona.allowed_type_ids = [&"move", &"attack", &"stop"] as Array[StringName]
	var cap = CaptainScript.new()
	cap.captain_id = &"alpha"
	cap.squad_id = &"alpha"
	cap.persona = persona
	cap.bind_command_bus(bus)
	add_child_autofree(cap)
	return cap

func _make_plan_with_move() -> Resource:
	var p = ActionPlanScript.new()
	p.id = &"plan_test"
	p.deputy = &"deputy"
	p.tier = ActionPlanScript.Tier.TACTICAL
	p.rationale = "advance to mid"
	var o = TacticalOrderScript.new()
	o.id = &"o_dep"
	o.type_id = &"move"
	o.origin = TacticalOrderScript.Origin.TACTICAL_VOICE
	o.issuer = TacticalOrderScript.Issuer.DEPUTY
	o.deputy = &"deputy"
	o.target_kind = TacticalOrderScript.TARGET_KIND_POSITION
	o.target_position = Vector3(3, 0, 3)
	p.orders = [o] as Array[Resource]
	p.apply_invariants()
	return p

func test_captain_handle_plan_emits_speak_and_submits_captain_orders():
	var bus = _make_bus()
	var cap = _make_captain(bus)
	watch_signals(cap)
	watch_signals(bus)
	cap.handle_plan(_make_plan_with_move())
	assert_signal_emit_count(cap, "spoke", 1)
	# Bus should have accepted at least one CAPTAIN-issued order.
	var recent = bus.get_recent_orders(5)
	assert_true(recent.size() >= 1)
	assert_eq(recent[0].issuer, TacticalOrderScript.Issuer.CAPTAIN)

func test_captain_retags_orders_to_own_squad():
	var bus = _make_bus()
	var cap = _make_captain(bus)
	cap.handle_plan(_make_plan_with_move())
	var recent = bus.get_recent_orders(5)
	assert_eq(recent[0].target_squad_id, &"alpha")
	assert_eq(recent[0].deputy, &"")  # captain orders don't carry a deputy seat

func test_captain_persona_filter_rejects_disallowed_type():
	var bus = _make_bus()
	var cap = _make_captain(bus)
	cap.persona.allowed_type_ids = [&"move"] as Array[StringName]   # disallow attack
	var p = ActionPlanScript.new()
	p.id = &"plan_atk"
	p.deputy = &"deputy"
	p.tier = ActionPlanScript.Tier.TACTICAL
	var o = TacticalOrderScript.new()
	o.id = &"o_atk"
	o.type_id = &"attack"
	o.origin = TacticalOrderScript.Origin.TACTICAL_VOICE
	o.issuer = TacticalOrderScript.Issuer.DEPUTY
	o.deputy = &"deputy"
	o.target_kind = TacticalOrderScript.TARGET_KIND_LANDMARK
	o.target_landmark = &"EnemyBuildingA"
	p.orders = [o] as Array[Resource]
	p.apply_invariants()
	watch_signals(cap)
	cap.handle_plan(p)
	assert_signal_emit_count(cap, "plan_rejected_locally", 1)

func test_captain_memory_clamps_reinforcement_at_15_percent():
	var m = CaptainMemoryScript.new()
	m.captain_persona_id = &"captain_test"
	m.reinforcement_pct = 0.42
	m.clamp_reinforcement()
	assert_eq(m.reinforcement_pct, CaptainMemoryScript.MAX_REINFORCEMENT)

func test_captain_memory_roundtrip():
	var m = CaptainMemoryScript.new()
	m.captain_persona_id = &"cap_x"
	m.match_appearances = 3
	m.preferred_axis = &"dps"
	m.reinforcement_pct = 0.1
	m.match_anecdotes = ["held the line at B4"] as Array[String]
	var d = m.to_dict()
	var m2 = CaptainMemoryScript.from_dict(d)
	assert_eq(m2.captain_persona_id, &"cap_x")
	assert_eq(m2.match_appearances, 3)
	assert_eq(m2.preferred_axis, &"dps")
	assert_almost_eq(m2.reinforcement_pct, 0.1, 1e-6)
	assert_eq(m2.match_anecdotes.size(), 1)
