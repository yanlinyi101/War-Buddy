class_name PrePlanTrigger
extends Resource

# Top-level Resource (v0.11.0 promotion from the pre_plan.gd inner
# class). Top-level form is required for .tres authoring — Godot can't
# instantiate inner-class Resources from .tres files.

@export var event: StringName = &""
@export var conditions: Dictionary = {}

func matches(payload: Dictionary) -> bool:
	if payload.get("event", &"") != event:
		return false
	# Whitelisted condition keys; unknown keys are ignored for forward-compat.
	if conditions.has("within_seconds_of_start"):
		var max_s: float = float(conditions["within_seconds_of_start"])
		if float(payload.get("elapsed_s", 0)) > max_s:
			return false
	if conditions.has("enemy_count_at_least"):
		var min_n: int = int(conditions["enemy_count_at_least"])
		if int(payload.get("enemy_count", 0)) < min_n:
			return false
	if conditions.has("player_resource_below"):
		var below: Dictionary = conditions["player_resource_below"]
		var have: Dictionary = payload.get("resources", {})
		for k in below.keys():
			if int(have.get(k, 0)) >= int(below[k]):
				return false
	return true
