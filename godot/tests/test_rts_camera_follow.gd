extends "res://addons/gut/test.gd"

const RtsCameraScript = preload("res://scripts/rts_camera.gd")

func _make_camera() -> Camera3D:
	var cam: Camera3D = RtsCameraScript.new()
	add_child_autofree(cam)
	cam.global_position = Vector3(10, 12, 10)
	return cam

func _make_hero() -> Node3D:
	var hero := Node3D.new()
	hero.name = "Hero"
	add_child_autofree(hero)
	hero.global_position = Vector3(0, 0, 0)
	return hero

func test_follow_disabled_without_target():
	var cam = _make_camera()
	cam._toggle_follow()
	assert_false(cam.is_following())

func test_follow_toggle_on_off():
	var cam = _make_camera()
	var hero = _make_hero()
	cam.set_follow_target(hero)
	cam._toggle_follow()
	assert_true(cam.is_following())
	cam._toggle_follow()
	assert_false(cam.is_following())

func test_follow_preserves_xz_offset():
	var cam = _make_camera()
	var hero = _make_hero()
	cam.set_follow_target(hero)
	cam._toggle_follow()
	# Move the hero — camera should track on XZ while keeping its Y.
	hero.global_position = Vector3(5, 0, -3)
	# Apply the follow update directly (avoids _process's mouse-edge pan
	# branch firing in headless tests where the mouse is at (0,0)).
	cam._apply_follow()
	assert_almost_eq(cam.global_position.x, 15.0, 0.01)
	assert_almost_eq(cam.global_position.z, 7.0, 0.01)
	assert_almost_eq(cam.global_position.y, 12.0, 0.01)  # zoom preserved

func test_manual_pan_breaks_follow():
	var cam = _make_camera()
	var hero = _make_hero()
	cam.set_follow_target(hero)
	cam._toggle_follow()
	assert_true(cam.is_following())
	cam._break_follow_if_active()
	assert_false(cam.is_following())
