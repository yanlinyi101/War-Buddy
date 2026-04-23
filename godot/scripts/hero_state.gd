extends Node
class_name HeroState

signal health_changed(current_health: int, max_health: int)
signal target_changed(target_name: String)
signal action_changed(action_name: String)

@export var max_health := 100
var current_health := 100
var current_target_name := "None"
var current_action := "Idle"

func _ready() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)
	target_changed.emit(current_target_name)
	action_changed.emit(current_action)

func set_target(target_name: String) -> void:
	current_target_name = target_name
	target_changed.emit(current_target_name)

func set_action(action_name: String) -> void:
	current_action = action_name
	action_changed.emit(current_action)

func apply_damage(amount: int) -> void:
	current_health = maxi(0, current_health - amount)
	health_changed.emit(current_health, max_health)
