class_name Deputy
extends Node

signal spoke(text: String, deputy_id: StringName)
signal plan_received(plan: Resource)
signal plan_rejected_locally(plan: Resource, reason: StringName)

@export var deputy_id: StringName = &"deputy"
@export var persona: Resource = null     # DeputyPersona

var memory: Resource = null               # DeputyMemory
var _short_term: Array[Resource] = []     # ActionPlans
var _bus: Node = null

func bind_command_bus(bus: Node) -> void:
	_bus = bus

func bind_memory(m: Resource) -> void:
	memory = m

func handle_plan(plan: Resource) -> void:
	if plan == null:
		return
	plan_received.emit(plan)
	# Persona filter: drop plans whose orders include disallowed types.
	if persona != null and not persona.allowed_type_ids.is_empty():
		for o in plan.orders:
			if not persona.allowed_type_ids.has(o.type_id):
				plan_rejected_locally.emit(plan, &"persona_disallowed_type")
				speak("I can't do that — outside my training.")
				return
	# Speak first, dispatch second — character feel before machine action.
	speak(plan.rationale)
	if _bus != null:
		var result = _bus.submit_plan(plan)
		if result.get("plan_rejected", false):
			plan_rejected_locally.emit(plan, &"bus_invariants")
			return
	_short_term.append(plan)
	if _short_term.size() > 6:
		_short_term.pop_front()

func speak(text: String) -> void:
	if text.is_empty():
		return
	spoke.emit(text, deputy_id)

func snapshot_short_term() -> Dictionary:
	var out: Array = []
	for p in _short_term:
		out.append({"id": String(p.id), "rationale": p.rationale})
	return {"recent_plans": out}
