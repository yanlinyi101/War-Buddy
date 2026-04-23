extends "res://addons/gut/test.gd"

const MatchStateScript = preload("res://scripts/match_state.gd")

var match_state: Node

class FakeBuilding:
	extends Node
	signal destroyed(building_id: String)
	var id: String
	func _init(p_id: String) -> void:
		id = p_id
		set_meta("building_id", p_id)
	func kill() -> void:
		destroyed.emit(id)

func before_each() -> void:
	match_state = MatchStateScript.new()
	add_child_autofree(match_state)

func _make_building(id: String) -> FakeBuilding:
	var b = FakeBuilding.new(id)
	add_child_autofree(b)
	return b

func test_register_increments_remaining_count() -> void:
	match_state.register_enemy_building(_make_building("a"))
	match_state.register_enemy_building(_make_building("b"))
	assert_eq(match_state.enemy_buildings_remaining, 2)

func test_duplicate_register_is_noop() -> void:
	var b = _make_building("a")
	match_state.register_enemy_building(b)
	match_state.register_enemy_building(b)
	assert_eq(match_state.enemy_buildings_remaining, 1)

func test_victory_triggers_when_all_destroyed() -> void:
	watch_signals(match_state)
	var a = _make_building("a")
	var b = _make_building("b")
	match_state.register_enemy_building(a)
	match_state.register_enemy_building(b)
	a.kill()
	assert_false(match_state.is_victory)
	b.kill()
	assert_true(match_state.is_victory)
	assert_signal_emit_count(match_state, "victory_triggered", 1)

func test_victory_fires_only_once() -> void:
	watch_signals(match_state)
	var a = _make_building("a")
	match_state.register_enemy_building(a)
	a.kill()
	match_state.trigger_victory()
	match_state.trigger_victory()
	assert_signal_emit_count(match_state, "victory_triggered", 1)

func test_match_locks_after_victory() -> void:
	var a = _make_building("a")
	match_state.register_enemy_building(a)
	a.kill()
	assert_true(match_state.is_match_locked)
