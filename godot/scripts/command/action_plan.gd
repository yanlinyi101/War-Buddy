class_name ActionPlan
extends Resource

const TacticalOrder = preload("res://scripts/command/tactical_order.gd")

enum Tier { TACTICAL, STRATEGIC }

@export var id: StringName = &""
@export var deputy: StringName = &""
@export var tier: Tier = Tier.TACTICAL
@export var rationale: String = ""
@export var confidence: float = 1.0
@export var orders: Array[Resource] = []
@export var triggering_utterance: String = ""
@export var timestamp_ms: int = 0

func _expected_origin_for_tier() -> int:
	match tier:
		Tier.TACTICAL:
			return TacticalOrder.Origin.TACTICAL_VOICE
		Tier.STRATEGIC:
			return TacticalOrder.Origin.STRATEGIC_DECOMPOSITION
	return TacticalOrder.Origin.SCRIPT

func validate_invariants() -> Dictionary:
	var violations: Array[String] = []
	var expected_origin := _expected_origin_for_tier()
	for o in orders:
		if o.deputy != deputy:
			violations.append("order %s deputy=%s mismatches plan deputy=%s"
				% [String(o.id), String(o.deputy), String(deputy)])
		if o.origin != expected_origin:
			violations.append("order %s origin=%d does not match expected %d for tier"
				% [String(o.id), o.origin, expected_origin])
		if o.parent_intent_id != id:
			violations.append("order %s parent_intent_id=%s does not match plan id=%s"
				% [String(o.id), String(o.parent_intent_id), String(id)])
	return {"ok": violations.is_empty(), "violations": violations}

func apply_invariants() -> void:
	# Auto-fix the trivial fields the LLM reliably forgets.
	# Does not auto-fix `deputy` mismatches — those are real schema violations.
	var expected_origin := _expected_origin_for_tier()
	for o in orders:
		if o.parent_intent_id == &"":
			o.parent_intent_id = id
		if o.origin != expected_origin and o.origin == TacticalOrder.Origin.SCRIPT:
			o.origin = expected_origin

func to_dict() -> Dictionary:
	var order_dicts: Array = []
	for o in orders:
		order_dicts.append(o.to_dict())
	return {
		"id": String(id),
		"deputy": String(deputy),
		"tier": int(tier),
		"rationale": rationale,
		"confidence": confidence,
		"orders": order_dicts,
		"triggering_utterance": triggering_utterance,
		"timestamp_ms": timestamp_ms,
	}

static func from_dict(d: Dictionary) -> ActionPlan:
	var p := ActionPlan.new()
	p.id = StringName(d.get("id", ""))
	p.deputy = StringName(d.get("deputy", ""))
	p.tier = int(d.get("tier", Tier.TACTICAL))
	p.rationale = String(d.get("rationale", ""))
	p.confidence = float(d.get("confidence", 1.0))
	p.triggering_utterance = String(d.get("triggering_utterance", ""))
	p.timestamp_ms = int(d.get("timestamp_ms", 0))
	var raw_orders: Array = d.get("orders", [])
	var typed: Array[Resource] = []
	for od in raw_orders:
		typed.append(TacticalOrder.from_dict(od))
	p.orders = typed
	return p
