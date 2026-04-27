extends "res://addons/gut/test.gd"

const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

func _make_basic() -> Resource:
	var o = TacticalOrderScript.new()
	o.id = &"ord_001"
	o.type_id = &"move"
	o.origin = TacticalOrderScript.Origin.TACTICAL_VOICE
	o.issuer = TacticalOrderScript.Issuer.PLAYER
	o.deputy = &"deputy"
	o.target_position = Vector3(5, 0, 5)
	o.timestamp_ms = 1000
	return o

func test_to_dict_round_trip_preserves_all_fields():
	var o = _make_basic()
	o.params = {"speed_mult": 0.5}
	o.target_unit_ids = [101, 102] as Array[int]
	o.rationale = "flank east"
	o.confidence = 0.82
	o.parent_intent_id = &"plan_42"
	o.expires_at_ms = 5000
	var d = o.to_dict()
	var restored = TacticalOrderScript.from_dict(d)
	assert_eq(restored.id, &"ord_001")
	assert_eq(restored.type_id, &"move")
	assert_eq(restored.origin, TacticalOrderScript.Origin.TACTICAL_VOICE)
	assert_eq(restored.issuer, TacticalOrderScript.Issuer.PLAYER)
	assert_eq(restored.deputy, &"deputy")
	assert_almost_eq(restored.target_position.x, 5.0, 0.001)
	assert_eq(restored.target_unit_ids, [101, 102])
	assert_eq(restored.params, {"speed_mult": 0.5})
	assert_eq(restored.rationale, "flank east")
	assert_almost_eq(restored.confidence, 0.82, 0.001)
	assert_eq(restored.parent_intent_id, &"plan_42")
	assert_eq(restored.expires_at_ms, 5000)

func test_is_targeted_returns_true_when_position_set():
	var o = _make_basic()
	assert_true(o.is_targeted())

func test_is_targeted_returns_true_when_only_unit_ids_set():
	var o = TacticalOrderScript.new()
	o.id = &"ord_002"
	o.type_id = &"attack"
	o.target_unit_ids = [200] as Array[int]
	assert_true(o.is_targeted())

func test_is_targeted_returns_false_when_nothing_set():
	var o = TacticalOrderScript.new()
	o.id = &"ord_003"
	o.type_id = &"stop"
	assert_false(o.is_targeted())

func test_is_expired_when_now_exceeds_expires_at():
	var o = _make_basic()
	o.expires_at_ms = 5000
	assert_false(o.is_expired(4999))
	assert_true(o.is_expired(5000))
	assert_true(o.is_expired(5001))

func test_is_expired_zero_means_never():
	var o = _make_basic()
	o.expires_at_ms = 0
	assert_false(o.is_expired(99999999))

func test_default_status_is_pending():
	var o = TacticalOrderScript.new()
	assert_eq(o.status, &"pending")
