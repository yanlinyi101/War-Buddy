class_name Captain
extends Node

# Captain — spec 08 §11.6 (vision §2.3 agent-tier ladder).
#
# v0.5.0 scope:
#   - Receives ActionPlans addressed to its captain_id or squad_id (router
#     calls handle_plan).
#   - Re-tags orders with target_squad_id = own squad and submits to
#     CommandBus as issuer=CAPTAIN. This validates the strict A-chain
#     (player → deputy → captain → squad units) without yet making
#     autonomous LLM calls.
#   - Speak signal so HUD can show captain bubbles.
#   - Cross-match memory plumbed via MemoryStore (read-only at v0.5.0).
#
# Deferred (v0.6.0+):
#   - Periodic tick_observe() autonomous LLM calls.
#   - Stat reinforcement application (doc 09 territory).
#   - LLM-driven sub-order decomposition.

const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

signal spoke(text: String, captain_id: StringName)
signal plan_received(plan: Resource)
signal plan_rejected_locally(plan: Resource, reason: StringName)

@export var captain_id: StringName = &"captain_default"
@export var squad_id: StringName = &"alpha"
@export var persona: Resource = null      # CaptainPersona
@export var agency_tier: StringName = &"captain"

var memory: Resource = null                # CaptainMemory
var short_term_memory: Array[Resource] = []  # last N plans this match
var _bus: Node = null

func bind_command_bus(bus: Node) -> void:
	_bus = bus

func bind_memory(m: Resource) -> void:
	memory = m

func bind_squad(sid: StringName) -> void:
	squad_id = sid

func handle_plan(plan: Resource) -> void:
	if plan == null:
		return
	plan_received.emit(plan)
	# Persona filter
	if persona != null and not persona.allowed_type_ids.is_empty():
		for o in plan.orders:
			if not persona.allowed_type_ids.has(o.type_id):
				plan_rejected_locally.emit(plan, &"persona_disallowed_type")
				speak("Negative — outside my squad's mandate.")
				return
	speak(_callsign_ack(plan))
	# Re-tag orders to this captain's squad and emit as CAPTAIN-issued.
	# v0.5.0: simple passthrough — keep type_id, copy targeting, set
	# issuer=CAPTAIN, target_squad_id=own squad if absent. This is the
	# A-chain leaf path in spec 07 §2 (captains submit_orders, not
	# submit_plan).
	var sub_orders: Array[Resource] = []
	for o in plan.orders:
		var sub = _retarget_to_squad(o)
		sub_orders.append(sub)
	if _bus != null and not sub_orders.is_empty():
		_bus.submit_orders(sub_orders)
	short_term_memory.append(plan)
	if short_term_memory.size() > 6:
		short_term_memory.pop_front()

func _retarget_to_squad(parent: Resource) -> Resource:
	var dup := TacticalOrderScript.from_dict(parent.to_dict())
	# New unique id (parent stays in plan history); chain via parent_intent_id.
	dup.id = StringName("cap_%s_%d" % [String(captain_id), Time.get_ticks_msec()])
	# Some platforms reuse ticks_msec; salt with hash of parent.id for uniqueness.
	if parent.id != &"":
		dup.id = StringName("%s_p%s" % [String(dup.id), String(parent.id).substr(0, 4)])
	dup.issuer = TacticalOrderScript.Issuer.CAPTAIN
	dup.deputy = &""
	dup.parent_intent_id = parent.id
	dup.status = TacticalOrderScript.STATUS_PENDING
	# If the parent didn't address a specific squad, address ours.
	if dup.target_squad_id == &"" and dup.target_unit_ids.is_empty():
		dup.target_squad_id = squad_id
		dup.target_kind = TacticalOrderScript.TARGET_KIND_SQUAD
	return dup

func _callsign_ack(plan: Resource) -> String:
	var verb := "moving"
	if not plan.orders.is_empty():
		match String(plan.orders[0].type_id):
			"attack": verb = "engaging"
			"stop", "hold": verb = "holding"
			"move", _: verb = "moving"
	return "Captain %s, %s." % [String(captain_id), verb]

func speak(text: String) -> void:
	if text.is_empty():
		return
	spoke.emit(text, captain_id)

func snapshot_short_term() -> Dictionary:
	var out: Array = []
	for p in short_term_memory:
		out.append({"id": String(p.id), "rationale": p.rationale})
	return {"squad_id": String(squad_id), "recent_plans": out}
