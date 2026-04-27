class_name DeepseekClient
extends DeputyLLMClient

# DeepSeek's API is OpenAI-compatible (chat completions + tool-use).
# Endpoint: https://api.deepseek.com/v1/chat/completions
# Auth: Authorization: Bearer <key>
# Tool-use response shape: choices[0].message.tool_calls[i].function.arguments
#   is a JSON-encoded STRING (unlike Anthropic, which parses to Dictionary).

const ActionPlanScript = preload("res://scripts/command/action_plan.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

const API_URL := "https://api.deepseek.com/v1/chat/completions"
const DEFAULT_MAX_TOKENS := 1024

@export var api_key_env_var: String = "DEEPSEEK_API_KEY"

var _host: Node = null

func attach_to(host: Node) -> void:
	_host = host

func has_api_key() -> bool:
	return OS.get_environment(api_key_env_var) != ""

func submit_plan(req: SubmitPlanRequest) -> SubmitPlanResponse:
	var resp = SubmitPlanResponse.new()
	if not has_api_key():
		resp.error = &"no_api_key"
		return resp
	if _host == null:
		resp.error = &"network"
		return resp
	var key := OS.get_environment(api_key_env_var)
	var model := "deepseek-chat"
	if req.persona != null and req.persona.preferred_model != &"":
		model = String(req.persona.preferred_model)
	var system_prompt := _build_system_prompt(req)
	var tool_schema := _build_tool_schema(req.available_type_ids)
	var body = {
		"model": model,
		"max_tokens": DEFAULT_MAX_TOKENS,
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": req.utterance},
		],
		"tools": [tool_schema],
		"tool_choice": {"type": "function", "function": {"name": "submit_plan"}},
	}
	var http = HTTPRequest.new()
	_host.add_child(http)
	var headers = [
		"Authorization: Bearer %s" % key,
		"Content-Type: application/json",
	]
	var t0 = Time.get_ticks_msec()
	var err = http.request(API_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		resp.error = &"network"
		http.queue_free()
		return resp
	var args = await http.request_completed
	resp.elapsed_seconds = (Time.get_ticks_msec() - t0) / 1000.0
	http.queue_free()
	var result_code := int(args[0])
	var status_code := int(args[1])
	var raw: PackedByteArray = args[3]
	if result_code != HTTPRequest.RESULT_SUCCESS:
		resp.error = &"network"
		return resp
	if status_code < 200 or status_code >= 300:
		resp.error = &"network"
		resp.raw_text = raw.get_string_from_utf8()
		return resp
	var parsed = JSON.parse_string(raw.get_string_from_utf8())
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		resp.error = &"schema_violation"
		return resp
	resp.token_usage = parsed.get("usage", {})
	var choices: Array = parsed.get("choices", [])
	if choices.is_empty():
		resp.error = &"schema_violation"
		return resp
	var message: Dictionary = choices[0].get("message", {})
	# Capture any free text the model emitted alongside / instead of a tool call
	resp.raw_text = String(message.get("content", "") if message.get("content") != null else "")
	var tool_calls: Array = message.get("tool_calls", [])
	for tc in tool_calls:
		var fn: Dictionary = tc.get("function", {})
		if fn.get("name", "") != "submit_plan":
			continue
		var arg_str := String(fn.get("arguments", "{}"))
		var input = JSON.parse_string(arg_str)
		if input == null or typeof(input) != TYPE_DICTIONARY:
			resp.error = &"schema_violation"
			return resp
		var plan = _plan_from_tool_input(input, req)
		if plan != null:
			plan.apply_invariants()
			var inv = plan.validate_invariants()
			if not inv["ok"]:
				resp.error = &"schema_violation"
				return resp
			resp.plans = [plan] as Array[Resource]
			if resp.raw_text == "":
				resp.raw_text = plan.rationale
			return resp
	# No tool call — treat as conversational
	return resp

func _build_system_prompt(req: SubmitPlanRequest) -> String:
	var template := ""
	if req.persona != null and req.persona.system_prompt_template != "":
		template = req.persona.system_prompt_template
	else:
		template = "You are an AI deputy. Respond by calling submit_plan."
	var snapshot_str := JSON.stringify(req.observation)
	var memory_str := JSON.stringify(req.memory_snapshot)
	var utterance_str := req.utterance
	var quirks_str := ""
	if req.persona != null:
		quirks_str = "\n  - ".join(req.persona.quirks)
	var allowed_str := ""
	if req.persona != null:
		var arr: Array[String] = []
		for sn in req.persona.allowed_type_ids:
			arr.append(String(sn))
		allowed_str = ", ".join(arr)
	var voice_style := ""
	if req.persona != null:
		voice_style = req.persona.voice_style
	return template \
		.replace("{{snapshot}}", snapshot_str) \
		.replace("{{memory}}", memory_str) \
		.replace("{{utterance}}", utterance_str) \
		.replace("{{quirks}}", quirks_str) \
		.replace("{{allowed_orders}}", allowed_str) \
		.replace("{{voice_style}}", voice_style)

func _build_tool_schema(available_type_ids: Array[StringName]) -> Dictionary:
	var allowed: Array[String] = []
	for sn in available_type_ids:
		allowed.append(String(sn))
	if allowed.is_empty():
		allowed = ["move", "attack", "stop", "hold", "use_skill"]
	# OpenAI-compat function-tool wrapper: type=function + function{name,description,parameters}
	return {
		"type": "function",
		"function": {
			"name": "submit_plan",
			"description": "Submit a tactical plan with a list of orders, plan-level rationale, and confidence.",
			"parameters": {
				"type": "object",
				"properties": {
					"deputy": {"type": "string", "description": "The deputy seat (always 'deputy' for now)."},
					"tier": {"type": "string", "enum": ["tactical", "strategic"]},
					"rationale": {"type": "string", "description": "One short sentence explaining the plan."},
					"confidence": {"type": "number", "minimum": 0.0, "maximum": 1.0},
					"orders": {
						"type": "array",
						"items": {
							"type": "object",
							"properties": {
								"type_id": {"type": "string", "enum": allowed},
								"target_position": {"type": "array", "items": {"type": "number"}, "minItems": 3, "maxItems": 3},
								"target_landmark": {"type": "string"},
								"rationale": {"type": "string"},
							},
							"required": ["type_id"],
						},
					},
				},
				"required": ["deputy", "tier", "rationale", "orders"],
			},
		},
	}

func _plan_from_tool_input(input: Dictionary, req: SubmitPlanRequest) -> Resource:
	var plan = ActionPlanScript.new()
	plan.id = StringName("deepseek_plan_%d" % Time.get_ticks_msec())
	plan.deputy = StringName(input.get("deputy", "deputy"))
	plan.tier = ActionPlanScript.Tier.TACTICAL
	if input.get("tier", "tactical") == "strategic":
		plan.tier = ActionPlanScript.Tier.STRATEGIC
	plan.rationale = String(input.get("rationale", ""))
	plan.confidence = float(input.get("confidence", 0.7))
	plan.triggering_utterance = req.utterance
	plan.timestamp_ms = Time.get_ticks_msec()
	var raw_orders: Array = input.get("orders", [])
	var orders: Array[Resource] = []
	var i = 0
	for o_dict in raw_orders:
		var o = TacticalOrderScript.new()
		o.id = StringName("deepseek_ord_%d_%d" % [Time.get_ticks_msec(), i])
		o.type_id = StringName(o_dict.get("type_id", ""))
		o.origin = TacticalOrderScript.Origin.TACTICAL_VOICE
		if plan.tier == ActionPlanScript.Tier.STRATEGIC:
			o.origin = TacticalOrderScript.Origin.STRATEGIC_DECOMPOSITION
		o.issuer = TacticalOrderScript.Issuer.DEPUTY
		o.deputy = plan.deputy
		o.parent_intent_id = plan.id
		o.timestamp_ms = Time.get_ticks_msec()
		o.rationale = String(o_dict.get("rationale", ""))
		var pos_arr: Array = o_dict.get("target_position", [0, 0, 0])
		if pos_arr.size() >= 3:
			o.target_position = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		o.target_landmark = StringName(String(o_dict.get("target_landmark", "")))
		orders.append(o)
		i += 1
	plan.orders = orders
	return plan
