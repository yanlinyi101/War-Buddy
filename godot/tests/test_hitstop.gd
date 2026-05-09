extends "res://addons/gut/test.gd"

const HitstopScript = preload("res://scripts/feel/hitstop.gd")

func _make_hitstop() -> Node:
	var h = HitstopScript.new()
	add_child_autofree(h)
	return h

func _make_node() -> Node:
	var n = Node.new()
	n.process_mode = Node.PROCESS_MODE_INHERIT
	add_child_autofree(n)
	return n

func test_request_hit_freezes_both_nodes():
	var h = _make_hitstop()
	var atk = _make_node()
	var vic = _make_node()
	h.request_hit(atk, vic, 200)
	assert_eq(atk.process_mode, Node.PROCESS_MODE_DISABLED)
	assert_eq(vic.process_mode, Node.PROCESS_MODE_DISABLED)
	assert_eq(h.active_freeze_count(), 2)

func test_zero_duration_is_noop():
	var h = _make_hitstop()
	var atk = _make_node()
	var vic = _make_node()
	h.request_hit(atk, vic, 0)
	assert_eq(atk.process_mode, Node.PROCESS_MODE_INHERIT)
	assert_eq(h.active_freeze_count(), 0)

func test_invalid_node_skipped():
	var h = _make_hitstop()
	var vic = _make_node()
	# Pass null as attacker; victim should still freeze.
	h.request_hit(null, vic, 100)
	assert_eq(vic.process_mode, Node.PROCESS_MODE_DISABLED)
	assert_eq(h.active_freeze_count(), 1)

func test_double_hit_extends_deadline_does_not_double_freeze():
	var h = _make_hitstop()
	var n = _make_node()
	h.request_hit(n, n, 100)
	# Same node passed twice — should not double-register.
	assert_eq(h.active_freeze_count(), 1)
	# Second hit shorter than first should not shrink the deadline.
	h.request_hit(n, n, 10)
	assert_eq(h.active_freeze_count(), 1)
