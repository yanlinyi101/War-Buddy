extends Node

# Deprecated host (v0.11.0). The inner classes were promoted to top-level
# Resources so they can be authored as .tres files. Existing callers
# can still access them via PrePlanScript.PrePlanTrigger / .PrePlan via
# these aliases, but new code should use:
#   - PrePlanTrigger    (top level, res://scripts/command/pre_plan_trigger.gd)
#   - PrePlanResource   (top level, res://scripts/command/pre_plan_resource.gd)

const PrePlanTrigger = preload("res://scripts/command/pre_plan_trigger.gd")
const PrePlan = preload("res://scripts/command/pre_plan_resource.gd")
