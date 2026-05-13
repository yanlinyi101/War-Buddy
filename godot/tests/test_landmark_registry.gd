extends "res://addons/gut/test.gd"

# Plan v0.15.1 §6.5 — LandmarkRegistry autoload loads 10 landmarks
# from res://data/maps/graybox/landmarks and indexes by id + aliases.

func test_ten_landmarks_loaded():
	assert_eq(LandmarkRegistry.count(), 10)

func test_lookup_by_id():
	var pm = LandmarkRegistry.get_landmark(&"player_main")
	assert_ne(pm, null)
	assert_eq(pm.landmark_id, &"player_main")
	# Player HQ world center matches v0.15.1 plan §3.2.1.
	assert_almost_eq(pm.world_center.x, -22.0, 0.01)
	assert_almost_eq(pm.world_center.z, 22.0, 0.01)

func test_resolve_alias_chinese():
	# "中央" should resolve to central_plateau via the alias index.
	var lm = LandmarkRegistry.resolve_alias("中央")
	assert_ne(lm, null)
	assert_eq(lm.landmark_id, &"central_plateau")

func test_resolve_alias_english():
	var lm = LandmarkRegistry.resolve_alias("gold")
	assert_ne(lm, null)
	assert_eq(lm.landmark_id, &"gold_mine")

func test_snapshot_shape():
	var snap = LandmarkRegistry.snapshot()
	assert_eq(snap.size(), 10)
	for entry in snap:
		assert_true(entry.has("landmark_id"))
		assert_true(entry.has("display_name"))
		assert_true(entry.has("grid_cells"))
		assert_true(entry.has("world_center"))
