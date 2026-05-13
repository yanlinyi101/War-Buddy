extends "res://addons/gut/test.gd"

const PlayerHqScene = preload("res://scenes/player_hq.tscn")

func _spawn_hq() -> Node:
	var hq = PlayerHqScene.instantiate()
	add_child_autofree(hq)
	return hq

func test_player_hq_joins_friendly_structures_group():
	var hq = _spawn_hq()
	assert_true(hq.is_in_group("friendly_structures"))

func test_player_hq_has_correct_building_def_id():
	var hq = _spawn_hq()
	assert_eq(hq.building_def_id, &"hq")

func test_player_hq_resolves_building_def_via_library():
	var hq = _spawn_hq()
	assert_ne(hq.building_def, null)
	assert_eq(hq.building_def.build_id, &"hq")
	# Spec §7.3 row.
	assert_eq(hq.building_def.supply_provided, 10)
	assert_true(hq.building_def.deposit_point)
