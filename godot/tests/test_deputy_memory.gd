extends "res://addons/gut/test.gd"

const MemoryStoreScript = preload("res://scripts/ai/memory_store.gd")
const DeputyMemoryScript = preload("res://scripts/ai/deputy_memory.gd")

var _store: Node = null

func before_each():
	_store = MemoryStoreScript.new()
	add_child_autofree(_store)
	# Use a temp path so each test starts clean
	_store.base_dir = "user://deputies_test"
	# Wipe any leftover
	_clean_test_dir()

func _clean_test_dir():
	var d = DirAccess.open("user://deputies_test")
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)

func test_load_returns_default_when_file_missing():
	var m = _store.load_memory(&"deputy_a")
	assert_eq(m.deputy_id, &"deputy_a")
	assert_eq(m.total_matches, 0)
	assert_eq(m.relationship_traits, {})

func test_save_then_load_preserves_fields():
	var m = DeputyMemoryScript.new()
	m.deputy_id = &"deputy_a"
	m.total_matches = 5
	m.wins = 3
	m.relationship_traits = {"trust": 0.6}
	m.match_anecdotes = ["played chess opening twice", "lost a captain to ambush"] as Array[String]
	_store.save_memory(m)
	var loaded = _store.load_memory(&"deputy_a")
	assert_eq(loaded.total_matches, 5)
	assert_eq(loaded.wins, 3)
	assert_almost_eq(loaded.relationship_traits["trust"], 0.6, 0.001)
	assert_eq(loaded.match_anecdotes.size(), 2)

func test_snapshot_for_returns_jsonable_dict():
	var m = DeputyMemoryScript.new()
	m.deputy_id = &"deputy_a"
	m.total_matches = 7
	m.relationship_traits = {"trust": 0.8}
	_store.save_memory(m)
	var snap = _store.snapshot_for(&"deputy_a")
	assert_eq(snap["total_matches"], 7)
	assert_almost_eq(snap["relationship_traits"]["trust"], 0.8, 0.001)
	# Round-trip through JSON
	var j = JSON.stringify(snap)
	var parsed = JSON.parse_string(j)
	assert_eq(parsed["total_matches"], 7)
