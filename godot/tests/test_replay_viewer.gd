extends "res://addons/gut/test.gd"

const ReplayViewerScene = preload("res://scenes/replay_viewer.tscn")
const LOG_DIR := "user://order_log"

var _match_id := ""

func before_each():
	_match_id = "test_viewer_%d" % Time.get_ticks_msec()

func after_each():
	for ext in [".events.ndjson", ".ndjson", ".plans.ndjson", ".manifest.json"]:
		var p = "%s/%s%s" % [LOG_DIR, _match_id, ext]
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func _write_event(payload: Dictionary, kind: String) -> void:
	if not DirAccess.dir_exists_absolute(LOG_DIR):
		DirAccess.make_dir_recursive_absolute(LOG_DIR)
	var p = "%s/%s.events.ndjson" % [LOG_DIR, _match_id]
	var f = FileAccess.open(p, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(p, FileAccess.WRITE)
	f.seek_end()
	var entry := payload.duplicate(true)
	entry["kind"] = kind
	entry["at_ms"] = int(entry.get("at_ms", 0))
	f.store_line(JSON.stringify(entry))
	f.close()

func _write_manifest() -> void:
	if not DirAccess.dir_exists_absolute(LOG_DIR):
		DirAccess.make_dir_recursive_absolute(LOG_DIR)
	var p = "%s/%s.manifest.json" % [LOG_DIR, _match_id]
	var f = FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"match_id": _match_id,
		"started_at": "2026-05-10T00:00:00",
		"ended_at": "2026-05-10T00:00:42",
		"outcome": "victory",
		"deputy_persona": "deputy_test",
		"map_id": "graybox",
		"schema_version": 1,
	}))
	f.close()

func test_viewer_loads_empty_match_without_crashing():
	var v = ReplayViewerScene.instantiate()
	add_child_autofree(v)
	var n = v.load_match(_match_id)
	assert_eq(n, 0)

func test_viewer_loads_events_and_renders_count():
	_write_event({"at_ms": 100, "building_id": "EnemyBuildingA"}, "building_destroyed")
	_write_event({"at_ms": 200, "unit_id": "squad_a"}, "unit_destroyed")
	_write_manifest()
	var v = ReplayViewerScene.instantiate()
	add_child_autofree(v)
	var n = v.load_match(_match_id)
	assert_eq(n, 2)

func test_viewer_summary_includes_manifest_outcome():
	_write_event({"at_ms": 50, "building_id": "B"}, "building_destroyed")
	_write_manifest()
	var v = ReplayViewerScene.instantiate()
	add_child_autofree(v)
	v.load_match(_match_id)
	assert_true(v._summary.text.find("victory") >= 0)
	assert_true(v._summary.text.find("graybox") >= 0)
