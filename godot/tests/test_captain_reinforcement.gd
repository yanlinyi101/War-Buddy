extends "res://addons/gut/test.gd"

const CaptainReinforcement = preload("res://scripts/combat/captain_reinforcement.gd")
const CaptainMemoryScript = preload("res://scripts/ai/captain_memory.gd")

func _frontline_def() -> Resource:
	# Clone the canonical frontline so other tests don't drift.
	return load("res://data/units/frontline_basic.tres").duplicate(true)

func _memory(axis: StringName, pct: float) -> Resource:
	var m = CaptainMemoryScript.new()
	m.preferred_axis = axis
	m.reinforcement_pct = pct
	return m

func test_no_memory_returns_clone_unchanged():
	var d = _frontline_def()
	var got = CaptainReinforcement.apply(d, null)
	assert_eq(got.max_hp, d.max_hp)
	assert_eq(got.dmg, d.dmg)
	# But still a different instance — never the library row.
	assert_ne(got, d)

func test_hp_axis_scales_max_hp():
	var d = _frontline_def()
	var m = _memory(&"hp", 0.10)
	var got = CaptainReinforcement.apply(d, m)
	# 125 * 1.10 = 137.5 → round = 138
	assert_eq(got.max_hp, 138)
	assert_eq(got.dmg, d.dmg)   # unchanged

func test_dps_axis_scales_damage_and_shrinks_period():
	var d = _frontline_def()
	var m = _memory(&"dps", 0.10)
	var got = CaptainReinforcement.apply(d, m)
	# dmg 10 * 1.10 = 11
	assert_eq(got.dmg, 11)
	# period 1.5 / 1.10 ≈ 1.3636
	assert_almost_eq(got.attack_period_seconds, 1.5 / 1.10, 1e-4)

func test_sight_axis_scales_sight_range():
	var d = _frontline_def()
	var m = _memory(&"sight", 0.10)
	var got = CaptainReinforcement.apply(d, m)
	assert_almost_eq(got.sight_range, 10.0 * 1.10, 1e-4)

func test_speed_axis_scales_move_speed():
	var d = _frontline_def()
	var m = _memory(&"speed", 0.10)
	var got = CaptainReinforcement.apply(d, m)
	assert_almost_eq(got.move_speed, 3.15 * 1.10, 1e-4)

func test_unknown_axis_is_noop():
	var d = _frontline_def()
	var m = _memory(&"luck", 0.10)
	var got = CaptainReinforcement.apply(d, m)
	assert_eq(got.max_hp, d.max_hp)
	assert_eq(got.dmg, d.dmg)

func test_zero_pct_is_noop_but_still_clones():
	var d = _frontline_def()
	var m = _memory(&"hp", 0.0)
	var got = CaptainReinforcement.apply(d, m)
	assert_eq(got.max_hp, d.max_hp)

func test_applied_def_tagged_captain_agency_tier():
	var d = _frontline_def()
	var m = _memory(&"hp", 0.10)
	var got = CaptainReinforcement.apply(d, m)
	assert_eq(got.agency_tier, &"captain")

func test_at_max_cap_15_percent():
	# 08 §11.6 cap is 0.15 — enforced at memory-write time. v0.9.6 trusts
	# the input. Verify the math at exactly 0.15.
	var d = _frontline_def()
	var m = _memory(&"hp", 0.15)
	var got = CaptainReinforcement.apply(d, m)
	# 125 * 1.15 = 143.75 → round = 144
	assert_eq(got.max_hp, 144)
