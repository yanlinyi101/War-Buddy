extends "res://addons/gut/test.gd"

const CaptainScript = preload("res://scripts/ai/captain.gd")
const CaptainPersonaScript = preload("res://scripts/ai/captain_persona.gd")
const CommandBusScript = preload("res://scripts/command/command_bus.gd")
const RegistryScript = preload("res://scripts/command/order_type_registry.gd")
const ControlPolicyScript = preload("res://scripts/command/control_policy.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")
const ActionPlanScript = preload("res://scripts/command/action_plan.gd")
const SnapshotBuilderScript = preload("res://scripts/ai/battlefield_snapshot_builder.gd")
const DeputyLLMClientScript = preload("res://scripts/ai/deputy_llm_client.gd")

# Test-only LLM that always returns a single-order move plan when called.
class StubLLM extends DeputyLLMClientScript:
	var call_count: int = 0
	func submit_plan(req):
		await Engine.get_main_loop().process_frame
		call_count += 1
		var resp = DeputyLLMClientScript.SubmitPlanResponse.new()
		var plan = ActionPlanScript.new()
		plan.id = StringName("stub_plan_%d" % call_count)
		plan.deputy = &"deputy"
		plan.tier = ActionPlanScript.Tier.TACTICAL
		plan.rationale = "Reform on B5."
		plan.triggering_utterance = req.utterance
		plan.timestamp_ms = Time.get_ticks_msec()
		var o = TacticalOrderScript.new()
		o.id = StringName("stub_ord_%d" % call_count)
		o.type_id = &"move"
		o.origin = TacticalOrderScript.Origin.TACTICAL_VOICE
		o.issuer = TacticalOrderScript.Issuer.DEPUTY
		o.deputy = &"deputy"
		o.target_position = Vector3(5, 0, 5)
		plan.orders = [o] as Array[Resource]
		plan.apply_invariants()
		resp.plans = [plan] as Array[Resource]
		resp.raw_text = plan.rationale
		return resp

class EmptyLLM extends DeputyLLMClientScript:
	func submit_plan(_req):
		await Engine.get_main_loop().process_frame
		var resp = DeputyLLMClientScript.SubmitPlanResponse.new()
		resp.raw_text = "thinking..."
		return resp

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
	persona.autonomous_tick_seconds = 0.05  # short so cooldown is testable
	var cap = CaptainScript.new()
	cap.captain_id = &"alpha"
	cap.squad_id = &"alpha"
	cap.persona = persona
	cap.bind_command_bus(bus)
	add_child_autofree(cap)
	return cap

func _make_snapshot_builder() -> Node:
	var sb = SnapshotBuilderScript.new()
	add_child_autofree(sb)
	return sb

func test_disabled_tick_skips_with_reason():
	var bus = _make_bus()
	var cap = _make_captain(bus)
	watch_signals(cap)
	cap._on_building_destroyed({"building_id": "X"})
	assert_signal_emit_count(cap, "autonomous_tick_skipped", 1)

func test_unbound_deps_skip_with_reason():
	var bus = _make_bus()
	var cap = _make_captain(bus)
	cap.enable_autonomous_tick(true)
	watch_signals(cap)
	cap._on_building_destroyed({"building_id": "X"})
	assert_signal_emit_count(cap, "autonomous_tick_skipped", 1)

func test_tick_fires_when_event_arrives():
	var bus = _make_bus()
	var cap = _make_captain(bus)
	var sb = _make_snapshot_builder()
	var llm = StubLLM.new()
	cap.bind_autonomous_deps(llm, sb, bus._registry)
	cap.enable_autonomous_tick(true)
	watch_signals(cap)
	cap._on_building_destroyed({"building_id": "X"})
	# StubLLM yields one process frame; await it here.
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(llm.call_count, 1)
	assert_signal_emit_count(cap, "autonomous_tick_fired", 1)

func test_cooldown_blocks_rapid_double_tick():
	var bus = _make_bus()
	var cap = _make_captain(bus)
	cap.persona.autonomous_tick_seconds = 60.0   # long cooldown
	var sb = _make_snapshot_builder()
	var llm = StubLLM.new()
	cap.bind_autonomous_deps(llm, sb, bus._registry)
	cap.enable_autonomous_tick(true)
	cap._on_building_destroyed({"building_id": "X"})
	await get_tree().process_frame
	await get_tree().process_frame
	# Second event arrives well within cooldown — should be skipped.
	watch_signals(cap)
	cap._on_building_destroyed({"building_id": "Y"})
	assert_signal_emit_count(cap, "autonomous_tick_skipped", 1)
	assert_eq(llm.call_count, 1)

func test_empty_plan_response_skipped():
	var bus = _make_bus()
	var cap = _make_captain(bus)
	var sb = _make_snapshot_builder()
	cap.bind_autonomous_deps(EmptyLLM.new(), sb, bus._registry)
	cap.enable_autonomous_tick(true)
	watch_signals(cap)
	cap._on_building_destroyed({"building_id": "X"})
	await get_tree().process_frame
	await get_tree().process_frame
	assert_signal_emit_count(cap, "autonomous_tick_skipped", 1)
	assert_signal_emit_count(cap, "autonomous_tick_fired", 0)
