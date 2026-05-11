extends "res://addons/gut/test.gd"

# NavRecovery isolation tests — we don't spin up a real NavigationServer3D
# map (that requires a full scene + region). Instead we exercise the
# state-machine portion (frame buffer, threshold, no-op when nav map is
# missing).

const NavRecoveryScript = preload("res://scripts/nav_recovery.gd")

func _make_recovery() -> Node:
	var r = NavRecoveryScript.new()
	add_child_autofree(r)
	return r

func test_no_target_does_not_crash():
	var r = _make_recovery()
	r._physics_process(0.016)
	# If it didn't crash, we're good.
	pass_test("no-target path is a no-op")

func test_no_nav_map_no_op():
	var r = _make_recovery()
	var target = Node3D.new()
	add_child_autofree(target)
	r.bind_to(target)
	# Default RID is empty — _physics_process should bail without snapping.
	r._physics_process(0.016)
	assert_eq(r.recover_count(), 0)

func test_teleport_bumps_recover_count():
	var r = _make_recovery()
	r.warn_on_recover = false
	var target = Node3D.new()
	add_child_autofree(target)
	target.global_position = Vector3(99, 0, 99)
	r.bind_to(target)
	r._teleport_to(Vector3(0, 0, 0))
	assert_eq(r.recover_count(), 1)
	assert_eq(target.global_position, Vector3.ZERO)

func test_frame_buffer_default_three():
	var r = _make_recovery()
	assert_eq(r.frame_buffer, 3)
	assert_almost_eq(r.displacement_threshold, 1.5, 1e-6)
