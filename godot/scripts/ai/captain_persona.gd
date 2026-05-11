class_name CaptainPersona
extends Resource

# CaptainPersona — lighter sibling of DeputyPersona for spec 08 §11.6.
# Per the locked vision, captains use a smaller model, a tighter prompt,
# and carry persistent memory with ≤15% per-axis stat reinforcement.

@export var persona_id: StringName = &"captain_default"
@export var display_name: String = "Captain"
@export var archetype: StringName = &"infantry"
@export var voice_style: String = "terse, callsign-driven"
@export_multiline var system_prompt_template: String = ""
@export var quirks: Array[String] = []
@export var allowed_type_ids: Array[StringName] = []
@export var preferred_axis: StringName = &"hp"   # which stat axis this captain bonds into
@export var preferred_model: StringName = &"deepseek-chat"
@export var snapshot_token_ceiling: int = 500    # vs Deputy's 2000 (spec 08 §11.6)
@export var autonomous_tick_seconds: float = 8.0 # default K=8s for tick_observe

# Doc 09 §8.2 — categories this persona may lead. Empty = unrestricted.
@export var eligible_categories: Array[StringName] = []

func can_lead_category(category: StringName) -> bool:
	if eligible_categories.is_empty():
		return true
	return eligible_categories.has(category)
