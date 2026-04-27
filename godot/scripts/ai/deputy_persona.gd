class_name DeputyPersona
extends Resource

@export var persona_id: StringName = &"deputy_default"
@export var display_name: String = "Deputy"
@export var archetype: StringName = &"veteran"
@export var voice_style: String = "calm, terse"
@export_multiline var system_prompt_template: String = ""
@export var priority_traits: Dictionary = {}
@export var quirks: Array[String] = []
@export var allowed_type_ids: Array[StringName] = []
@export var refusal_patterns: Array[String] = []
@export var preferred_model: StringName = &"deepseek-chat"
@export var consolidation_model: StringName = &"deepseek-chat"

# Autonomy axis (doc 07 §7, doc 08 §11.8). Range [0.0, 1.0].
#   ≤ 0.3 — always clarify on ambiguity / missing units; wait for player.
#   0.3..0.7 — act on best interpretation AND emit a parallel clarification
#              event ("I'm sending alpha to B4 — confirm?"), don't block.
#   ≥ 0.7 — act; clarification only on novel/dangerous situations.
# Across all settings, repeated player error degrades clarification frequency
# (doc 08 §11.8 decay function).
@export_range(0.0, 1.0, 0.05) var deputy_autonomy: float = 0.5
