extends "res://addons/gut/test.gd"

const HeroControllerScript = preload("res://scripts/hero_controller.gd")

const MAX_SPEED := 4.5
const ACCEL_S := 0.10
const SNAP := 0.05

func test_zero_desired_snaps_velocity_to_zero():
	var v = HeroControllerScript.step_velocity_toward(
		Vector3(3, 0, 3), Vector3.ZERO, MAX_SPEED, ACCEL_S, SNAP, 0.016
	)
	assert_eq(v, Vector3.ZERO)

func test_acceleration_does_not_overshoot_max_speed_in_one_frame():
	# Start from rest; one 16 ms frame of acceleration toward top speed
	# should yield a value strictly between 0 and max_speed.
	var v = HeroControllerScript.step_velocity_toward(
		Vector3.ZERO, Vector3(MAX_SPEED, 0, 0), MAX_SPEED, ACCEL_S, SNAP, 0.016
	)
	var flat = Vector3(v.x, 0, v.z)
	assert_lt(flat.length(), MAX_SPEED)
	assert_gt(flat.length(), 0.0)

func test_acceleration_reaches_max_speed_within_accel_time():
	var v = Vector3.ZERO
	# 12 × 16 ms = 192 ms, well past accel_time_s = 100 ms.
	for _i in 12:
		v = HeroControllerScript.step_velocity_toward(
			v, Vector3(MAX_SPEED, 0, 0), MAX_SPEED, ACCEL_S, SNAP, 0.016
		)
	assert_almost_eq(Vector3(v.x, 0, v.z).length(), MAX_SPEED, 0.05)

func test_stop_snap_kicks_in_for_tiny_residuals():
	var v = HeroControllerScript.step_velocity_toward(
		Vector3(0.01, 0, 0.01), Vector3(0.001, 0, 0.001), MAX_SPEED, ACCEL_S, SNAP, 0.016
	)
	assert_eq(v, Vector3.ZERO)

func test_y_component_preserved_through_helper():
	# The helper must never overwrite Y — gravity / vertical state lives
	# elsewhere and the helper only shapes horizontal motion.
	var v = HeroControllerScript.step_velocity_toward(
		Vector3(0, 5.0, 0), Vector3(MAX_SPEED, 0, 0), MAX_SPEED, ACCEL_S, SNAP, 0.016
	)
	assert_almost_eq(v.y, 5.0, 0.0001)
