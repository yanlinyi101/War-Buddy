extends "res://addons/gut/test.gd"

const ActionPlanScript = preload("res://scripts/command/action_plan.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

func _make_order(id: StringName, deputy: StringName, origin: int) -> Resource:
	var o = TacticalOrderScript.new()
	o.id = id
	o.type_id = &"move"
	o.origin = origin
	o.issuer = TacticalOrderScript.Issuer.DEPUTY
	o.deputy = deputy
	o.target_position = Vector3(1, 0, 1)
	return o

func test_to_dict_round_trip():
	var p = ActionPlanScript.new()
	p.id = &"plan_001"
	p.deputy = &"deputy"
	p.tier = ActionPlanScript.Tier.TACTICAL
	p.rationale = "flank"
	p.confidence = 0.9
	p.triggering_utterance = "go east"
	p.timestamp_ms = 5000
	p.orders = [_make_order(&"ord_a", &"deputy", TacticalOrderScript.Origin.TACTICAL_VOICE)] as Array[Resource]
	var d = p.to_dict()
	var r = ActionPlanScript.from_dict(d)
	assert_eq(r.id, &"plan_001")
	assert_eq(r.deputy, &"deputy")
	assert_eq(r.tier, ActionPlanScript.Tier.TACTICAL)
	assert_eq(r.rationale, "flank")
	assert_almost_eq(r.confidence, 0.9, 0.001)
	assert_eq(r.triggering_utterance, "go east")
	assert_eq(r.timestamp_ms, 5000)
	assert_eq(r.orders.size(), 1)
	assert_eq(r.orders[0].id, &"ord_a")

func test_validate_invariants_passes_for_consistent_plan():
	var p = ActionPlanScript.new()
	p.id = &"plan_002"
	p.deputy = &"deputy"
	p.tier = ActionPlanScript.Tier.TACTICAL
	var o = _make_order(&"ord_a", &"deputy", TacticalOrderScript.Origin.TACTICAL_VOICE)
	o.parent_intent_id = &"plan_002"
	p.orders = [o] as Array[Resource]
	var result = p.validate_invariants()
	assert_true(result["ok"])
	assert_eq(result["violations"].size(), 0)

func test_validate_invariants_fails_when_order_deputy_mismatches():
	var p = ActionPlanScript.new()
	p.id = &"plan_003"
	p.deputy = &"deputy"
	p.tier = ActionPlanScript.Tier.TACTICAL
	var o = _make_order(&"ord_a", &"someone_else", TacticalOrderScript.Origin.TACTICAL_VOICE)
	o.parent_intent_id = &"plan_003"
	p.orders = [o] as Array[Resource]
	var result = p.validate_invariants()
	assert_false(result["ok"])
	assert_string_contains(result["violations"][0], "deputy")

func test_validate_invariants_fails_when_origin_mismatches_tier():
	var p = ActionPlanScript.new()
	p.id = &"plan_004"
	p.deputy = &"deputy"
	p.tier = ActionPlanScript.Tier.STRATEGIC
	var o = _make_order(&"ord_a", &"deputy", TacticalOrderScript.Origin.TACTICAL_VOICE)
	o.parent_intent_id = &"plan_004"
	p.orders = [o] as Array[Resource]
	var result = p.validate_invariants()
	assert_false(result["ok"])
	assert_string_contains(result["violations"][0], "origin")

func test_validate_invariants_fails_when_parent_intent_id_missing():
	var p = ActionPlanScript.new()
	p.id = &"plan_005"
	p.deputy = &"deputy"
	p.tier = ActionPlanScript.Tier.TACTICAL
	var o = _make_order(&"ord_a", &"deputy", TacticalOrderScript.Origin.TACTICAL_VOICE)
	# leave parent_intent_id blank
	p.orders = [o] as Array[Resource]
	var result = p.validate_invariants()
	assert_false(result["ok"])
	assert_string_contains(result["violations"][0], "parent_intent_id")

func test_apply_invariants_fixes_parent_intent_id_in_place():
	var p = ActionPlanScript.new()
	p.id = &"plan_006"
	p.deputy = &"deputy"
	p.tier = ActionPlanScript.Tier.TACTICAL
	var o = _make_order(&"ord_a", &"deputy", TacticalOrderScript.Origin.TACTICAL_VOICE)
	# leave parent_intent_id blank
	p.orders = [o] as Array[Resource]
	p.apply_invariants()
	assert_eq(p.orders[0].parent_intent_id, &"plan_006")
	assert_true(p.validate_invariants()["ok"])
