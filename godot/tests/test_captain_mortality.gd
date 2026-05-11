extends "res://addons/gut/test.gd"

const CaptainScript = preload("res://scripts/ai/captain.gd")
const CaptainPersonaScript = preload("res://scripts/ai/captain_persona.gd")
const CaptainMemoryScript = preload("res://scripts/ai/captain_memory.gd")
const CommandBusScript = preload("res://scripts/command/command_bus.gd")
const RegistryScript = preload("res://scripts/command/order_type_registry.gd")
const ControlPolicyScript = preload("res://scripts/command/control_policy.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")
const ActionPlanScript = preload("res://scripts/command/action_plan.gd")

# Stand-in body that emits the same `died(unit_id)` signal as SquadUnit.
class FakeBody extends Node:
	signal died(unit_id: String)
	var unit_id := "fake_body"
	func kill() -> void:
		died.emit(unit_id)

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
	cap.bind_memory(CaptainMemoryScript.new())
	add_child_autofree(cap)
	return cap

func _make_plan_with_move() -> Resource:
	var p = ActionPlanScript.new()
	p.id = &"plan_t"
	p.deputy = &"deputy"
	p.tier = ActionPlanScript.Tier.TACTICAL
	p.rationale = "go"
	var o = TacticalOrderScript.new()
	o.id = &"o_t"
	o.type_id = &"move"
	o.origin = TacticalOrderScript.Origin.TACTICAL_VOICE
	o.issuer = TacticalOrderScript.Issuer.DEPUTY
	o.deputy = &"deputy"
	o.target_kind = TacticalOrderScript.TARGET_KIND_POSITION
	o.target_position = Vector3(2, 0, 2)
	p.orders = [o] as Array[Resource]
	p.apply_invariants()
	return p

func test_starts_alive():
	var bus = _make_bus()
	var cap = _make_captain(bus)
	assert_true(cap.alive)

func test_body_death_kills_captain():
	var bus = _make_bus()
	var cap = _make_captain(bus)
	var body = FakeBody.new()
	add_child_autofree(body)
	cap.bind_body(body)
	body.kill()
	assert_false(cap.alive)

func test_dead_captain_rejects_plans():
	var bus = _make_bus()
	var cap = _make_captain(bus)
	var body = FakeBody.new()
	add_child_autofree(body)
	cap.bind_body(body)
	body.kill()
	watch_signals(cap)
	cap.handle_plan(_make_plan_with_move())
	assert_signal_emit_count(cap, "plan_rejected_locally", 1)

func test_body_death_increments_memory_deaths():
	var bus = _make_bus()
	var cap = _make_captain(bus)
	cap.memory.deaths = 0
	var body = FakeBody.new()
	add_child_autofree(body)
	cap.bind_body(body)
	body.kill()
	assert_eq(cap.memory.deaths, 1)

func test_body_death_publishes_event_bus():
	var bus = _make_bus()
	var cap = _make_captain(bus)
	var body = FakeBody.new()
	add_child_autofree(body)
	cap.bind_body(body)
	var got: Array = []
	EventBus.unit_destroyed.connect(func(p): got.append(p))
	body.kill()
	for c in EventBus.unit_destroyed.get_connections():
		EventBus.unit_destroyed.disconnect(c["callable"])
	# Captain death uses faction_id="captain" to distinguish from regulars.
	var seen_cap := false
	for p in got:
		if p.get("faction_id", "") == "captain":
			seen_cap = true
			break
	assert_true(seen_cap)

func test_double_body_kill_is_idempotent():
	var bus = _make_bus()
	var cap = _make_captain(bus)
	cap.memory.deaths = 0
	var body = FakeBody.new()
	add_child_autofree(body)
	cap.bind_body(body)
	body.kill()
	body.kill()
	assert_eq(cap.memory.deaths, 1)
	assert_false(cap.alive)

func test_dead_captain_skips_autonomous_tick():
	var bus = _make_bus()
	var cap = _make_captain(bus)
	cap.enable_autonomous_tick(true)
	var body = FakeBody.new()
	add_child_autofree(body)
	cap.bind_body(body)
	body.kill()
	watch_signals(cap)
	cap._on_building_destroyed({"building_id": "X"})
	assert_signal_emit_count(cap, "autonomous_tick_skipped", 1)
	assert_signal_emit_count(cap, "autonomous_tick_fired", 0)
