extends Node    # parsing-only host; the real classes are below

class PrePlanTrigger:
	extends Resource

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

class PrePlan:
	extends Resource

	@export var name: String = ""
	@export var deputy: StringName = &""
	@export var trigger: Resource          # PrePlanTrigger
	@export var orders: Array[Resource] = []   # TacticalOrders, all origin = PRE_PLAN
	@export var enabled: bool = true
	@export var repeat: bool = false
	@export var cooldown_seconds: float = 0.0

	var last_fired_ms: int = 0
