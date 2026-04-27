class_name ClassifierRouter
extends Node

signal plan_emitted(plan: Resource)
signal classification_failed(utterance: String, reason: StringName)

const DeputyLLMClientScript = preload("res://scripts/ai/deputy_llm_client.gd")

var _deputy: Node = null
var _llm: RefCounted = null
var _snapshot_builder: Node = null
var _registry: Node = null

func bind(deputy: Node, llm_client: RefCounted, snapshot_builder: Node,
		registry: Node) -> void:
	_deputy = deputy
	_llm = llm_client
	_snapshot_builder = snapshot_builder
	_registry = registry

func handle_utterance(text: String, _source: StringName) -> void:
	if _deputy == null or _llm == null or _snapshot_builder == null:
		push_error("ClassifierRouter: not bound")
		return
	var req = DeputyLLMClientScript.SubmitPlanRequest.new()
	req.persona = _deputy.persona
	req.observation = _snapshot_builder.build_for(_deputy.deputy_id, &"")
	req.utterance = text
	if _registry != null:
		req.available_type_ids = _registry.list_for_deputy(_deputy.deputy_id)
	var resp = await _llm.submit_plan(req)
	if resp.error != &"":
		classification_failed.emit(text, resp.error)
		_deputy.speak("Sorry — couldn't process that. (%s)" % String(resp.error))
		return
	if resp.plans.is_empty():
		# Conversational utterance — deputy still speaks
		_deputy.speak(resp.raw_text if resp.raw_text != "" else "...")
		return
	for plan in resp.plans:
		_deputy.handle_plan(plan)
		plan_emitted.emit(plan)
