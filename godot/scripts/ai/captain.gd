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
const DeputyLLMClientScript = preload("res://scripts/ai/deputy_llm_client.gd")

signal spoke(text: String, captain_id: StringName)
signal plan_received(plan: Resource)
signal plan_rejected_locally(plan: Resource, reason: StringName)
signal autonomous_tick_fired(plan: Resource)
signal autonomous_tick_skipped(reason: StringName)

@export var captain_id: StringName = &"captain_default"
@export var squad_id: StringName = &"alpha"
@export var persona: Resource = null      # CaptainPersona
@export var agency_tier: StringName = &"captain"

# v0.8.1 — Captain mortality. Captain "embodies" a single SquadUnit
# (spec 08 §11.6, vision §2.3 "lighter LLM agent embodied as a
# battlefield unit"). When that body dies, captain stops responding,
# CaptainMemory.deaths increments, and EventBus broadcasts.
var _body: Node = null
var alive: bool = true

var memory: Resource = null                # CaptainMemory
var short_term_memory: Array[Resource] = []  # last N plans this match
var _bus: Node = null

# --- Autonomous tick (spec 08 §11.6) ---
var _llm: RefCounted = null
var _snapshot_builder: Node = null
var _registry: Node = null
var _last_tick_ms: int = 0
var _autonomous_tick_enabled: bool = false

func bind_command_bus(bus: Node) -> void:
	_bus = bus

func bind_memory(m: Resource) -> void:
	memory = m

func bind_squad(sid: StringName) -> void:
	squad_id = sid

func bind_body(body: Node) -> void:
	# Captain rides a specific squad unit as its "body". When that unit
	# dies (SquadUnit.died), captain dies too — mortality lifecycle per
	# spec 08 §11.6 / vision §2.3.
	if _body == body:
		return
	_body = body
	if body == null:
		return
	if body.has_signal("died") and not body.died.is_connected(_on_body_died):
		body.died.connect(_on_body_died)

func _on_body_died(_unit_id: String) -> void:
	if not alive:
		return
	alive = false
	# Persist the death — CaptainMemory survives across matches per
	# vision §2.3 lock-in. Use MemoryStore autoload via tree lookup so
	# tests without the autoload still pass.
	if memory != null:
		memory.deaths = memory.deaths + 1
		var t = get_tree()
		if t != null:
			var store = t.root.get_node_or_null("MemoryStore")
			if store != null and store.has_method("save_captain"):
				store.save_captain(memory)
	# Announce. The Captain bubble fires "Down. Reform." so the player
	# sees the death in-channel, not just in the event log.
	speak("Down. Hold position.")
	# Forward to EventBus so future doc-09 consumers (faction roster,
	# Deputy consolidation) see the captain death distinctly.
	var t2 = get_tree()
	if t2 != null:
		var bus = t2.root.get_node_or_null("EventBus")
		if bus != null:
			# captain-distinct event — uses unit_destroyed channel with
			# faction_id="captain" so debug HUD shows the difference.
			bus.publish_unit_destroyed("captain_%s" % String(captain_id), &"captain", "")

func bind_autonomous_deps(llm: RefCounted, snapshot_builder: Node, registry: Node) -> void:
	# Captain calls LLM directly with tier_hint = "tactical" — it does NOT
	# go through ClassifierRouter (that's for player utterances per spec 08
	# §11.6). The LLM still returns ActionPlan(s); captain treats each plan's
	# orders as proposed sub-orders for its own squad.
	_llm = llm
	_snapshot_builder = snapshot_builder
	_registry = registry

func enable_autonomous_tick(enabled: bool = true) -> void:
	_autonomous_tick_enabled = enabled

func subscribe_to_event_bus(event_bus: Node) -> void:
	# v0.7.1 wire: react to building_destroyed events. Future channels
	# (unit_destroyed, hp_changed thresholds) drop in alongside.
	if event_bus == null:
		return
	if not event_bus.building_destroyed.is_connected(_on_building_destroyed):
		event_bus.building_destroyed.connect(_on_building_destroyed)

func _on_building_destroyed(_payload: Dictionary) -> void:
	if not alive:
		autonomous_tick_skipped.emit(&"dead")
		return
	if not _autonomous_tick_enabled:
		autonomous_tick_skipped.emit(&"disabled")
		return
	if _llm == null or _snapshot_builder == null:
		autonomous_tick_skipped.emit(&"unbound")
		return
	# Cooldown — spec 08 §11.6 caps at one autonomous LLM call per K
	# seconds. Persona's autonomous_tick_seconds wins, default 8 s.
	var min_interval_ms := 8000
	if persona != null and persona.has_method("get") and persona.get("autonomous_tick_seconds") != null:
		min_interval_ms = int(float(persona.autonomous_tick_seconds) * 1000.0)
	var now := Time.get_ticks_msec()
	if _last_tick_ms != 0 and now - _last_tick_ms < min_interval_ms:
		autonomous_tick_skipped.emit(&"cooldown")
		return
	_last_tick_ms = now
	_run_autonomous_tick()

func _run_autonomous_tick() -> void:
	var req = DeputyLLMClientScript.SubmitPlanRequest.new()
	req.persona = persona
	# Captain's snapshot is the deputy's seat snapshot for v0.7.1 (smaller
	# crop arrives with doc 09's faction-scoped queries).
	req.observation = _snapshot_builder.build_for(StringName("captain_%s" % String(captain_id)), &"tactical")
	req.utterance = ""
	req.tier_hint = &"tactical"
	if _registry != null:
		req.available_type_ids = _registry.list_for_deputy(&"deputy")
	var resp = await _llm.submit_plan(req)
	if resp == null or resp.error != &"":
		autonomous_tick_skipped.emit(&"llm_error" if resp == null else resp.error)
		return
	if resp.plans.is_empty():
		# Empty plan = "do nothing" is a valid LLM response per spec.
		autonomous_tick_skipped.emit(&"empty_plan")
		return
	# Apply only the first plan; subsequent plans within one tick are
	# discarded to keep cost predictable.
	var plan = resp.plans[0]
	autonomous_tick_fired.emit(plan)
	# Captain's existing handle_plan() handles persona-filter + retag +
	# submit_orders + speak — single source of truth for plan ingestion.
	handle_plan(plan)

func handle_plan(plan: Resource) -> void:
	if plan == null:
		return
	if not alive:
		plan_rejected_locally.emit(plan, &"captain_dead")
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
