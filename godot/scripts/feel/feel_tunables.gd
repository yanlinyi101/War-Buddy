class_name FeelTunables
extends Resource

# Doc 11 §10 — consolidated playtest-tunable surface. Single Resource
# so designers can ship a .tres override without code edits. Default
# values from the spec table.
#
# Existing systems still ship their own @export defaults (hero_controller
# max_speed, etc.) but at boot can read from this Resource to override.
# v0.12.1 lands the data shape + one consumer wire (hero); other
# subsystems migrate as designers ask for tuning passes.

# --- Hero (spec 11 §4) ---
@export var hero_cross_map_time_seconds: float = 45.0
@export var hero_acceleration_time_seconds: float = 0.10
@export var hero_visual_turn_ease_seconds: float = 0.10
@export var hero_stop_time_seconds: float = 0.0

# --- Camera (spec 11 §5) ---
@export var camera_follow_break_threshold_diag: float = 1.5
@export var camera_pitch_degrees: float = 75.0

# --- Feedback (spec 11 §6 / §7) ---
@export var feedback_hover_ring_fade_in_seconds: float = 0.08
@export var combat_hitstop_duration_seconds: float = 0.045
@export var combat_shake_hp_threshold: float = 0.10
@export var hp_bar_ghost_delay_seconds: float = 0.40

# --- Navigation (spec 11 §8) ---
@export var nav_off_mesh_displacement_max_m: float = 1.5
@export var nav_off_mesh_grace_frames: int = 3

# --- Corpses (spec 11 §9) ---
@export var corpse_settle_time_seconds: float = 1.5
@export var corpse_default_lifetime_seconds: float = 60.0

const DEFAULT_PATH := "res://data/feel/feel_tunables.tres"

static func default_tunables() -> FeelTunables:
	# v0.12.1 — try loading the canonical .tres; fall back to in-memory
	# defaults if the file isn't present (e.g. fresh repo before the
	# data/feel/ dir is committed).
	if ResourceLoader.exists(DEFAULT_PATH):
		var loaded = load(DEFAULT_PATH)
		if loaded is FeelTunables:
			return loaded
	return FeelTunables.new()
