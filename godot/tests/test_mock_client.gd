extends "res://addons/gut/test.gd"

const MockClientScript = preload("res://scripts/ai/mock_client.gd")
const DeputyLLMClientScript = preload("res://scripts/ai/deputy_llm_client.gd")
const ActionPlanScript = preload("res://scripts/command/action_plan.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

func _make_request(utterance: String) -> RefCounted:
	var req = DeputyLLMClientScript.SubmitPlanRequest.new()
	req.utterance = utterance
	return req

func test_returns_attack_plan_for_attack_keyword():
	var c = MockClientScript.new()
	var resp = await c.submit_plan(_make_request("focus fire on enemy_a"))
	assert_eq(resp.error, &"")
	assert_eq(resp.plans.size(), 1)
	assert_eq(resp.plans[0].orders.size(), 1)
	assert_eq(resp.plans[0].orders[0].type_id, &"attack")

func test_returns_move_plan_for_move_keyword():
	var c = MockClientScript.new()
	var resp = await c.submit_plan(_make_request("move to mid"))
	assert_eq(resp.plans[0].orders[0].type_id, &"move")

func test_returns_empty_plan_for_conversational_utterance():
	var c = MockClientScript.new()
	var resp = await c.submit_plan(_make_request("good job"))
	assert_eq(resp.plans.size(), 0)
	assert_string_contains(resp.raw_text, "good job")

func test_response_satisfies_action_plan_invariants_after_apply():
	var c = MockClientScript.new()
	var resp = await c.submit_plan(_make_request("attack the building"))
	var plan = resp.plans[0]
	plan.apply_invariants()
	var inv = plan.validate_invariants()
	assert_true(inv["ok"])

func test_simulated_timeout_when_utterance_starts_with_TIMEOUT():
	var c = MockClientScript.new()
	var resp = await c.submit_plan(_make_request("TIMEOUT please"))
	assert_eq(resp.error, &"timeout")
	assert_eq(resp.plans.size(), 0)
