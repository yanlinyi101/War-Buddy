class_name PrePlanResource
extends Resource

# Top-level Resource (v0.11.0). Name avoids colliding with the inner
# `pre_plan.gd::PrePlan` class that's still used by older callers in
# bootstrap.gd's sample plan.

@export var name: String = ""
@export var deputy: StringName = &""
@export var trigger: Resource = null    # PrePlanTrigger
@export var orders: Array[Resource] = []  # TacticalOrder
@export var enabled: bool = true
@export var repeat: bool = false
@export var cooldown_seconds: float = 0.0

# Runtime mutable state — not part of the saved schema.
var last_fired_ms: int = 0
