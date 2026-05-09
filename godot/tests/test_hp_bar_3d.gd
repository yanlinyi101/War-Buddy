extends "res://addons/gut/test.gd"

const HpBar3DScript = preload("res://scripts/feel/hp_bar_3d.gd")

func _make_bar():
	# Instantiate via the script (it extends Sprite3D, so .new() returns
	# a Sprite3D-typed object with the HpBar3D methods attached).
	var bar = HpBar3DScript.new()
	add_child_autofree(bar)
	return bar

func test_set_hp_drops_current_instantly():
	var bar = _make_bar()
	bar.set_hp(100, 100)
	bar.set_hp(50, 100)
	assert_almost_eq(bar._current_ratio, 0.5, 1e-6)

func test_ghost_lags_behind_after_damage():
	var bar = _make_bar()
	bar.set_hp(100, 100)
	# After damage, ghost should still hold the prior ratio (1.0) until
	# _process catches it down toward _ghost_target (0.4).
	bar.set_hp(40, 100)
	assert_almost_eq(bar._ghost_ratio, 1.0, 1e-6)
	assert_almost_eq(bar._ghost_target, 0.4, 1e-6)

func test_ghost_catches_up_within_fall_window():
	var bar = _make_bar()
	bar.set_hp(100, 100)
	bar.set_hp(20, 100)
	# Drive ~500 ms of process time (slightly past GHOST_FALL_S = 0.4).
	for _i in 32:
		bar._process(0.016)
	assert_almost_eq(bar._ghost_ratio, 0.2, 0.05)

func test_heal_snaps_ghost_up_so_it_doesnt_trail_wrong_way():
	var bar = _make_bar()
	bar.set_hp(20, 100)
	# Drive ghost down to 0.2 via _process (otherwise it's still at the
	# initial 1.0 from the var default, and the heal won't exceed it).
	for _i in 32:
		bar._process(0.016)
	assert_almost_eq(bar._ghost_ratio, 0.2, 0.05)
	# Now heal — ghost should snap up to 0.8 instantly so the white stripe
	# doesn't appear to "trail" the heal in the wrong direction.
	bar.set_hp(80, 100)
	assert_almost_eq(bar._ghost_ratio, 0.8, 1e-6)

func test_zero_max_hp_does_not_divide_by_zero():
	var bar = _make_bar()
	bar.set_hp(0, 0)
	assert_eq(bar._current_ratio, 0.0)
	assert_eq(bar._ghost_target, 0.0)
