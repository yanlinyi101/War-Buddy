extends "res://addons/gut/test.gd"

const SelectionSetScript = preload("res://scripts/squads/selection_set.gd")

# Use a stub that satisfies the SquadUnit duck-type SelectionSet calls
class FakeSquadUnit:
	extends Node
	var selected := false
	func set_selected(value: bool) -> void:
		selected = value

func _make_unit(id: String) -> FakeSquadUnit:
	var u := FakeSquadUnit.new()
	u.name = id
	add_child_autofree(u)
	return u

func test_add_then_contains_returns_true():
	var ss = SelectionSetScript.new()
	var u = _make_unit("a")
	ss.add(u)
	assert_true(ss.contains(u))
	assert_eq(ss.size(), 1)
	assert_true(u.selected)

func test_add_same_unit_twice_does_not_duplicate():
	var ss = SelectionSetScript.new()
	var u = _make_unit("a")
	ss.add(u)
	ss.add(u)
	assert_eq(ss.size(), 1)

func test_remove_after_add_empties_and_deselects():
	var ss = SelectionSetScript.new()
	var u = _make_unit("a")
	ss.add(u)
	ss.remove(u)
	assert_false(ss.contains(u))
	assert_eq(ss.size(), 0)
	assert_false(u.selected)

func test_clear_deselects_all_members():
	var ss = SelectionSetScript.new()
	var a = _make_unit("a")
	var b = _make_unit("b")
	ss.add(a)
	ss.add(b)
	ss.clear()
	assert_eq(ss.size(), 0)
	assert_false(a.selected)
	assert_false(b.selected)

func test_changed_signal_emit_count_matches_mutations():
	var ss = SelectionSetScript.new()
	watch_signals(ss)
	var a = _make_unit("a")
	var b = _make_unit("b")
	ss.add(a)        # +1
	ss.add(a)        # noop, no emit
	ss.add(b)        # +1
	ss.remove(a)     # +1
	ss.clear()       # +1 (still had b)
	assert_signal_emit_count(ss, "changed", 4)
