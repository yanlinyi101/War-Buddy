class_name DeputyLLMClient
extends RefCounted

# All concrete implementations are async via Godot's `await`. The base method
# below is synchronous because GDScript can't declare an abstract `async` method;
# subclasses redeclare with `await` in their bodies.
func submit_plan(_req: SubmitPlanRequest) -> SubmitPlanResponse:
	push_error("DeputyLLMClient.submit_plan is abstract")
	return null

class SubmitPlanRequest:
	extends RefCounted
	var persona: Resource = null              # DeputyPersona (typed loosely to dodge cyclic preload)
	var memory_snapshot: Dictionary = {}
	var observation: Dictionary = {}
	var utterance: String = ""
	var tier_hint: StringName = &""           # &"" | &"tactical" | &"strategic"
	var timeout_seconds: float = 5.0
	var available_type_ids: Array[StringName] = []

class SubmitPlanResponse:
	extends RefCounted
	var plans: Array[Resource] = []           # ActionPlan
	var raw_text: String = ""
	var error: StringName = &""               # &"" | &"timeout" | &"network" | &"schema_violation" | &"refusal" | &"no_api_key"
	var elapsed_seconds: float = 0.0
	var token_usage: Dictionary = {}          # {input, output}
