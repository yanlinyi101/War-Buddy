extends "res://addons/gut/test.gd"

const WorkerScene = preload("res://scenes/worker.tscn")

func _spawn_worker() -> Node:
	var w = WorkerScene.instantiate()
	add_child_autofree(w)
	return w

func test_worker_loads_stats_from_unit_def():
	var w = _spawn_worker()
	# worker_basic.tres pins: hp=45, armor=0, light/normal.
	assert_eq(w.max_hp, 45)
	assert_eq(w.hp, 45)
	assert_eq(w.armor, 0)
	assert_eq(w.armor_class, &"light")
	assert_eq(w.dmg_type, &"normal")
	assert_eq(w.unit_def_id, &"worker_basic")

func test_worker_joins_squad_units_group():
	var w = _spawn_worker()
	assert_true(w.is_in_group("squad_units"))

func test_worker_has_hp_bar_and_emits_hp_changed_on_spawn():
	var w = _spawn_worker()
	# HpBar3D Sprite3D child exists.
	assert_ne(w.get_node_or_null("HpBar3D"), null)
