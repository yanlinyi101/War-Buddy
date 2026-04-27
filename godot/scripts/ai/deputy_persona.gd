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
@export var preferred_model: StringName = &"claude-sonnet-4-5-20250929"
@export var consolidation_model: StringName = &"claude-haiku-4-5-20251022"
