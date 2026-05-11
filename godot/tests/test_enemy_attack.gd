extends "res://addons/gut/test.gd"

const EnemyBuildingScene = preload("res://scenes/enemy_building.tscn")
const SquadUnitScene = preload("res://scenes/squad_unit.tscn")

func _make_building(pos: Vector3) -> Node:
	var b = EnemyBuildingScene.instantiate()
	add_child_autofree(b)
	b.global_position = pos
	return b

func _make_unit(pos: Vector3) -> Node:
	var u = SquadUnitScene.instantiate()
	add_child_autofree(u)
	u.global_position = pos
	return u

func test_finds_nearest_friendly_in_range():
	var b = _make_building(Vector3.ZERO)
	var u_near = _make_unit(Vector3(2, 0, 0))
	var u_far = _make_unit(Vector3(20, 0, 0))
	var got = b._find_nearest_friendly_in_range()
	assert_eq(got, u_near)

func test_returns_null_when_no_unit_in_range():
	var b = _make_building(Vector3.ZERO)
	var u_far = _make_unit(Vector3(20, 0, 0))   # > attack_range (6.0 default)
	var got = b._find_nearest_friendly_in_range()
	assert_null(got)

func test_skips_dead_units():
	var b = _make_building(Vector3.ZERO)
	var u = _make_unit(Vector3(2, 0, 0))
	u.take_damage(u.max_hp)   # kill it
	assert_true(u.is_dead)
	# After death, u removes itself from "squad_units" group → no targeting.
	var got = b._find_nearest_friendly_in_range()
	assert_null(got)

func test_attack_tick_damages_unit():
	var b = _make_building(Vector3.ZERO)
	var u = _make_unit(Vector3(2, 0, 0))
	var initial_hp = u.hp
	b._attack_cooldown = 0.0
	b._process(0.1)   # one tick — should fire and damage
	assert_lt(u.hp, initial_hp)
	assert_gt(b._attack_cooldown, 0.0)   # cooldown set after fire

func test_cooldown_blocks_rapid_fire():
	var b = _make_building(Vector3.ZERO)
	var u = _make_unit(Vector3(2, 0, 0))
	b._attack_cooldown = 0.0
	b._process(0.1)
	var hp_after_first = u.hp
	b._process(0.05)   # well under attack_interval
	assert_eq(u.hp, hp_after_first)   # no double-tap

func test_disabling_attack_stops_fire():
	var b = _make_building(Vector3.ZERO)
	var u = _make_unit(Vector3(2, 0, 0))
	b.attack_enabled = false
	b._attack_cooldown = 0.0
	b._process(0.1)
	assert_eq(u.hp, u.max_hp)

func test_destroyed_building_stops_attacking():
	var b = _make_building(Vector3.ZERO)
	var u = _make_unit(Vector3(2, 0, 0))
	b._destroy()
	b._attack_cooldown = 0.0
	b._process(0.1)
	assert_eq(u.hp, u.max_hp)
