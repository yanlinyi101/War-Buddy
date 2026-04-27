class_name MockClient
extends DeputyLLMClient

const ActionPlanScript = preload("res://scripts/command/action_plan.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

var _id_counter: int = 0

func submit_plan(req: SubmitPlanRequest) -> SubmitPlanResponse:
	# Simulated async — yield one frame so callers can `await`.
	await Engine.get_main_loop().process_frame
	var resp = SubmitPlanResponse.new()
	resp.elapsed_seconds = 0.0
	if req.utterance.begins_with("TIMEOUT"):
		resp.error = &"timeout"
		return resp
	var lower := req.utterance.to_lower()
	var plan = ActionPlanScript.new()
	plan.id = StringName("mock_plan_%d" % _id_counter)
	_id_counter += 1
	plan.deputy = &"deputy"
	plan.tier = ActionPlanScript.Tier.TACTICAL
	plan.triggering_utterance = req.utterance
	plan.timestamp_ms = Time.get_ticks_msec()
	if "attack" in lower or "focus fire" in lower or "kill" in lower:
		plan.rationale = "Engaging the requested target."
		plan.confidence = 0.85
		plan.orders = [_make_order(plan.id, &"attack", &"deputy", 1, 0, 1)] as Array[Resource]
	elif "move" in lower or "rally" in lower or "advance" in lower:
		plan.rationale = "Repositioning forces."
		plan.confidence = 0.90
		plan.orders = [_make_order(plan.id, &"move", &"deputy", 5, 0, 5)] as Array[Resource]
	else:
		# Conversational — no plan, just a raw text echo.
		resp.raw_text = "Mock deputy heard: %s" % req.utterance
		return resp
	plan.apply_invariants()
	resp.plans = [plan] as Array[Resource]
	resp.raw_text = plan.rationale
	return resp

func _make_order(plan_id: StringName, type_id: StringName, deputy: StringName,
		x: float, y: float, z: float) -> Resource:
	var o = TacticalOrderScript.new()
	o.id = StringName("mock_ord_%d" % _id_counter)
	_id_counter += 1
	o.type_id = type_id
	o.origin = TacticalOrderScript.Origin.TACTICAL_VOICE
	o.issuer = TacticalOrderScript.Issuer.DEPUTY
	o.deputy = deputy
	o.target_position = Vector3(x, y, z)
	o.parent_intent_id = plan_id
	o.timestamp_ms = Time.get_ticks_msec()
	return o
