extends "res://addons/gut/test.gd"

# Hero mortality (v0.12.2, spec 09 §10.3). Uses the live hero scene
# from main.tscn? No — instantiate via the script class because
# main.tscn has many siblings. We exercise take_damage / _die / _respawn
# on a stand-in Node3D minimally because HeroController inherits
# CharacterBody3D and needs scene children.
#
# Strategy: instantiate the commander_hero.tscn (which already has
# HeroState + NavigationAgent3D + CollisionShape3D children).

const HeroScene = preload("res://scenes/commander_hero.tscn")

func _make_hero() -> Node:
	var h = HeroScene.instantiate()
	add_child_autofree(h)
	return h

func test_hero_starts_alive_with_full_hp():
	var h = _make_hero()
	assert_eq(h.hp, h.max_hp)
	assert_false(h.is_dead)
	assert_true(h.is_in_group("heroes"))

func test_take_damage_decrements_hp():
	var h = _make_hero()
	h.take_damage(100, null)
	assert_eq(h.hp, h.max_hp - 100)
	assert_false(h.is_dead)

func test_take_damage_lethal_kills_hero():
	var h = _make_hero()
	watch_signals(h)
	h.take_damage(h.max_hp + 100, null)
	assert_true(h.is_dead)
	assert_eq(h.hp, 0)
	assert_signal_emit_count(h, "died", 1)

func test_dead_hero_ignores_further_damage():
	var h = _make_hero()
	h.take_damage(h.max_hp)
	watch_signals(h)
	h.take_damage(50)
	assert_signal_emit_count(h, "hp_changed", 0)

func test_respawn_after_timer():
	var h = _make_hero()
	h.respawn_seconds = 0.05
	h.take_damage(h.max_hp)
	assert_true(h.is_dead)
	# Drive enough physics frames to elapse the timer.
	for _i in 5:
		h._physics_process(0.02)
	assert_false(h.is_dead)
	assert_eq(h.hp, h.max_hp)

func test_input_locked_blocks_damage():
	var h = _make_hero()
	h.set_input_locked(true)
	h.take_damage(100)
	# Input lock is set after death too; what we want is that damage
	# applied during a forced lock (e.g. victory pause) doesn't progress
	# kill state. v0.12.2 keeps it simple: lock blocks damage entirely.
	assert_eq(h.hp, h.max_hp)
