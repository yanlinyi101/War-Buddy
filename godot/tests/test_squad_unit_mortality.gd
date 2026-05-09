extends "res://addons/gut/test.gd"

const SquadUnitScene = preload("res://scenes/squad_unit.tscn")

func _make_unit() -> Node:
	var u = SquadUnitScene.instantiate()
	add_child_autofree(u)
	return u

func test_initial_hp_equals_max_hp():
	var u = _make_unit()
	assert_eq(u.hp, u.max_hp)
	assert_false(u.is_dead)

func test_take_damage_subtracts_hp_and_emits_signal():
	var u = _make_unit()
	watch_signals(u)
	u.take_damage(30)
	assert_eq(u.hp, u.max_hp - 30)
	assert_signal_emit_count(u, "hp_changed", 1)
	assert_false(u.is_dead)

func test_zero_or_negative_damage_is_noop():
	var u = _make_unit()
	u.take_damage(0)
	u.take_damage(-5)
	assert_eq(u.hp, u.max_hp)

func test_damage_exceeding_hp_clamps_at_zero_and_dies():
	var u = _make_unit()
	watch_signals(u)
	u.take_damage(u.max_hp + 50)
	assert_eq(u.hp, 0)
	assert_true(u.is_dead)
	assert_signal_emit_count(u, "died", 1)

func test_died_signal_publishes_to_event_bus():
	var u = _make_unit()
	# Capture EventBus.unit_destroyed payloads.
	var payloads: Array = []
	var cb = func(p): payloads.append(p)
	EventBus.unit_destroyed.connect(cb)
	u.take_damage(u.max_hp)
	# Disconnect via the same Callable.
	for c in EventBus.unit_destroyed.get_connections():
		EventBus.unit_destroyed.disconnect(c["callable"])
	assert_eq(payloads.size(), 1)
	assert_eq(payloads[0]["unit_id"], u.unit_id)

func test_double_kill_is_idempotent():
	var u = _make_unit()
	u.take_damage(u.max_hp)
	watch_signals(u)
	u.take_damage(50)   # already dead
	assert_signal_emit_count(u, "died", 0)
	assert_signal_emit_count(u, "hp_changed", 0)

func test_dead_unit_leaves_squad_units_group():
	var u = _make_unit()
	u.add_to_group("squad_alpha")
	u.take_damage(u.max_hp)
	# died() removes from "squad_units"; the squad_alpha group is left
	# untouched (managed by bootstrap, not the unit) — but the canonical
	# group lookup should not pick up a dying unit.
	assert_false(u.is_in_group("squad_units"))
