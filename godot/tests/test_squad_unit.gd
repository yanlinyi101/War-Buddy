extends "res://addons/gut/test.gd"

const SquadUnitScene = preload("res://scenes/squad_unit.tscn")

class FakeBuilding:
	extends Node3D
	var is_destroyed := false
	var damage_log: Array = []
	func take_damage(amount: int) -> void:
		damage_log.append(amount)
		if damage_log.size() >= 3:
			is_destroyed = true

func _make_unit() -> Node:
	var u = SquadUnitScene.instantiate()
	add_child_autofree(u)
	return u

func test_order_move_sets_nav_agent_target():
	var u = _make_unit()
	u.order_move(Vector3(5, 0, 5))
	assert_almost_eq(u.nav_agent.target_position.x, 5.0, 0.01)
	assert_almost_eq(u.nav_agent.target_position.z, 5.0, 0.01)
	assert_true(u._has_move_target)

func test_order_attack_sets_target_and_clears_when_destroyed():
	var u = _make_unit()
	var b = FakeBuilding.new()
	add_child_autofree(b)
	b.global_position = u.global_position + Vector3(1.5, 0, 0)  # within ATTACK_RANGE 2.8
	u.order_attack(b)
	assert_eq(u._attack_target, b)

	# Force four physics frames so cooldown allows three hits then null clear
	u._attack_cooldown = 0.0
	for i in 4:
		u._physics_process(0.8)  # 0.8 > ATTACK_INTERVAL 0.75 so each tick fires
	assert_true(b.is_destroyed)
	assert_null(u._attack_target)

func test_stop_clears_targets_and_zeros_velocity():
	var u = _make_unit()
	u.order_move(Vector3(5, 0, 5))
	u.stop()
	assert_false(u._has_move_target)
	assert_null(u._attack_target)
	assert_eq(u.velocity, Vector3.ZERO)

func test_set_selected_toggles_ring_visibility():
	var u = _make_unit()
	assert_false(u.selection_ring.visible)
	u.set_selected(true)
	assert_true(u.selection_ring.visible)
	u.set_selected(false)
	assert_false(u.selection_ring.visible)
