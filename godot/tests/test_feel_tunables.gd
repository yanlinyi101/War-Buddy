extends "res://addons/gut/test.gd"

const FeelTunablesScript = preload("res://scripts/feel/feel_tunables.gd")

func test_defaults_match_spec_table():
	var t = FeelTunablesScript.new()
	assert_almost_eq(t.hero_acceleration_time_seconds, 0.10, 1e-6)
	assert_almost_eq(t.hero_stop_time_seconds, 0.0, 1e-6)
	assert_almost_eq(t.feedback_hover_ring_fade_in_seconds, 0.08, 1e-6)
	assert_almost_eq(t.combat_hitstop_duration_seconds, 0.045, 1e-6)
	assert_almost_eq(t.combat_shake_hp_threshold, 0.10, 1e-6)
	assert_almost_eq(t.hp_bar_ghost_delay_seconds, 0.40, 1e-6)
	assert_almost_eq(t.nav_off_mesh_displacement_max_m, 1.5, 1e-6)
	assert_eq(t.nav_off_mesh_grace_frames, 3)
	assert_almost_eq(t.corpse_default_lifetime_seconds, 60.0, 1e-6)
	assert_almost_eq(t.camera_follow_break_threshold_diag, 1.5, 1e-6)

func test_shipped_tres_loads_with_canonical_values():
	var t = FeelTunablesScript.default_tunables()
	assert_ne(t, null)
	assert_almost_eq(t.hero_cross_map_time_seconds, 45.0, 1e-6)
	assert_almost_eq(t.camera_pitch_degrees, 75.0, 1e-6)
