extends "res://addons/gut/test.gd"

const ClassifierRouterScript = preload("res://scripts/ai/classifier_router.gd")
const DeputyScript = preload("res://scripts/ai/deputy.gd")
const PersonaScript = preload("res://scripts/ai/deputy_persona.gd")
const MockClientScript = preload("res://scripts/ai/mock_client.gd")
const BuilderScript = preload("res://scripts/ai/battlefield_snapshot_builder.gd")
const RegistryScript = preload("res://scripts/command/order_type_registry.gd")
const ControlPolicyScript = preload("res://scripts/command/control_policy.gd")
const CommandBusScript = preload("res://scripts/command/command_bus.gd")

func _wire_full_pipeline() -> Dictionary:
	# Bus + registry
	var registry = RegistryScript.new()
	for type_id in [&"move", &"attack", &"stop", &"hold", &"use_skill"]:
		var def = RegistryScript.TypeDef.new()
		def.id = type_id
		registry.register(def)
	add_child_autofree(registry)
	var bus = CommandBusScript.new()
	bus.set_registry(registry)
	bus.set_policy(ControlPolicyScript.FullControlPolicy.new())
	bus.persistence_enabled = false
	add_child_autofree(bus)

	# Deputy
	var p = PersonaScript.new()
	p.persona_id = &"deputy_test"
	p.allowed_type_ids = [&"move", &"attack", &"stop", &"hold", &"use_skill"] as Array[StringName]
	var d = DeputyScript.new()
	d.deputy_id = &"deputy"
	d.persona = p
	d.bind_command_bus(bus)
	add_child_autofree(d)

	# Snapshot builder
	var b = BuilderScript.new()
	add_child_autofree(b)

	# Router with Mock client
	var r = ClassifierRouterScript.new()
	r.bind(d, MockClientScript.new(), b, registry)
	add_child_autofree(r)
	return {"router": r, "deputy": d, "bus": bus}

func test_handle_utterance_routes_attack_to_deputy_and_bus():
	var w = _wire_full_pipeline()
	watch_signals(w["deputy"])
	await w["router"].handle_utterance("attack the building", &"text_input")
	assert_signal_emit_count(w["deputy"], "spoke", 1)
	assert_eq(w["bus"].get_recent_orders().size(), 1)
	assert_eq(w["bus"].get_recent_orders()[0].type_id, &"attack")

func test_handle_utterance_with_conversational_input_emits_speech_only():
	var w = _wire_full_pipeline()
	watch_signals(w["deputy"])
	await w["router"].handle_utterance("good job", &"text_input")
	# The Mock returns no plan; router should make the deputy speak the raw_text
	assert_signal_emit_count(w["deputy"], "spoke", 1)
	assert_eq(w["bus"].get_recent_orders().size(), 0)

func test_handle_utterance_emits_classification_failed_on_timeout():
	var w = _wire_full_pipeline()
	watch_signals(w["router"])
	await w["router"].handle_utterance("TIMEOUT please", &"text_input")
	assert_signal_emit_count(w["router"], "classification_failed", 1)
