extends "res://addons/gut/test.gd"

# GameState is registered as an autoload, so we hit the live singleton here.
# We restore its match-clock state at end-of-test so other tests (e.g.
# snapshot_builder) don't see leaked state.

var _saved_start_ms: int
var _saved_victory: bool

func before_each():
	_saved_start_ms = GameState._match_start_ms
	_saved_victory = GameState._victory_triggered

func after_each():
	GameState._match_start_ms = _saved_start_ms
	GameState._victory_triggered = _saved_victory

func test_match_elapsed_zero_before_mark_started():
	GameState._match_start_ms = 0
	assert_eq(GameState.match_elapsed_seconds(), 0.0)

func test_mark_match_started_sets_clock_and_clears_victory():
	GameState._victory_triggered = true
	GameState.mark_match_started()
	assert_false(GameState.is_victory_triggered())
	assert_gt(GameState._match_start_ms, 0)

func test_mark_victory_flips_flag():
	GameState.mark_match_started()
	assert_false(GameState.is_victory_triggered())
	GameState.mark_victory()
	assert_true(GameState.is_victory_triggered())

class FakeNode3D extends Node3D:
	pass

func test_units_in_radius_filters_by_distance():
	var u_a = FakeNode3D.new()
	add_child_autofree(u_a)
	u_a.global_position = Vector3(0, 0, 0)
	u_a.add_to_group("squad_units")
	var u_b = FakeNode3D.new()
	add_child_autofree(u_b)
	u_b.global_position = Vector3(10, 0, 0)
	u_b.add_to_group("squad_units")

	var nearby: Array = GameState.units_in_radius(Vector3.ZERO, 5.0)
	# At least u_a in range; u_b out of range.
	var ids: Array = []
	for n in nearby: ids.append(n)
	assert_true(ids.has(u_a))
	assert_false(ids.has(u_b))

func test_units_in_radius_returns_empty_for_zero_radius():
	assert_eq(GameState.units_in_radius(Vector3.ZERO, 0.0).size(), 0)

func test_buildings_in_radius_filters_by_distance():
	var b = FakeNode3D.new()
	add_child_autofree(b)
	b.global_position = Vector3(2, 0, 2)
	b.add_to_group("enemy_buildings")
	var hits: Array = GameState.buildings_in_radius(Vector3.ZERO, 5.0)
	var present := false
	for n in hits:
		if n == b:
			present = true
			break
	assert_true(present)
