extends "res://addons/gut/test.gd"

const BuilderScript = preload("res://scripts/ai/battlefield_snapshot_builder.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

# Lightweight fakes that satisfy the group-query stub
class FakeUnit:
	extends Node3D
	var unit_id: StringName = &"unit_a"
	func get_unit_id() -> StringName:
		return unit_id

class FakeBuilding:
	extends Node3D
	var building_id: StringName = &"enemy_a"
	var hp: int = 30
	var max_hp: int = 60
	func get_building_id() -> StringName:
		return building_id

func _make_builder() -> Node:
	var b = BuilderScript.new()
	add_child_autofree(b)
	return b

func test_snapshot_dict_has_required_top_level_keys():
	var b = _make_builder()
	var snap = b.build_for(&"deputy", &"")
	for key in ["match_meta", "you", "units", "enemies", "recent_events",
	            "player_signals", "available_orders"]:
		assert_true(snap.has(key), "missing top-level key: %s" % key)

func test_units_section_picks_up_squad_units_group():
	var b = _make_builder()
	var u = FakeUnit.new()
	add_child_autofree(u)
	u.add_to_group("squad_units")
	u.global_position = Vector3(2, 0, 3)
	var snap = b.build_for(&"deputy", &"")
	assert_eq(snap["units"].size(), 1)
	assert_eq(snap["units"][0]["id"], "unit_a")

func test_enemies_section_picks_up_enemy_buildings_group():
	var b = _make_builder()
	var e = FakeBuilding.new()
	add_child_autofree(e)
	e.add_to_group("enemy_buildings")
	e.global_position = Vector3(8, 0, 8)
	var snap = b.build_for(&"deputy", &"")
	assert_eq(snap["enemies"].size(), 1)
	assert_eq(snap["enemies"][0]["id"], "enemy_a")

func test_snapshot_is_json_round_trippable():
	var b = _make_builder()
	var snap = b.build_for(&"deputy", &"")
	var j = JSON.stringify(snap)
	var parsed = JSON.parse_string(j)
	assert_not_null(parsed)
	assert_true(parsed.has("match_meta"))
