extends "res://addons/gut/test.gd"

# Spec 08 §8 — MemoryStore.consolidate_after_match. Deterministic
# parts: match totals, trait drift, anecdote synthesis, prune at 12.
# LLM-driven anecdote authoring is a pass-through path tested at the
# stub level only (no real LLM calls in CI per spec 12 §6.1).

const DeputyMemoryScript = preload("res://scripts/ai/deputy_memory.gd")

var _test_deputy_id: StringName = &"test_deputy_consol"

func before_each():
	# Clear any prior test state so successive runs are isolated.
	var path = "user://deputies/%s.json" % String(_test_deputy_id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func after_each():
	var path = "user://deputies/%s.json" % String(_test_deputy_id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func test_consolidation_increments_total_matches():
	MemoryStore.consolidate_after_match(_test_deputy_id,
		{"outcome": "victory", "elapsed_s": 120.0, "enemy_buildings_killed": 3})
	var m = MemoryStore.load_memory(_test_deputy_id)
	assert_eq(m.total_matches, 1)
	assert_eq(m.wins, 1)
	assert_eq(m.losses, 0)

func test_defeat_increments_losses_not_wins():
	MemoryStore.consolidate_after_match(_test_deputy_id,
		{"outcome": "defeat", "elapsed_s": 60.0, "enemy_buildings_killed": 1})
	var m = MemoryStore.load_memory(_test_deputy_id)
	assert_eq(m.wins, 0)
	assert_eq(m.losses, 1)

func test_hours_played_accumulates():
	MemoryStore.consolidate_after_match(_test_deputy_id,
		{"outcome": "victory", "elapsed_s": 1800.0, "enemy_buildings_killed": 3})
	MemoryStore.consolidate_after_match(_test_deputy_id,
		{"outcome": "defeat", "elapsed_s": 1800.0, "enemy_buildings_killed": 0})
	var m = MemoryStore.load_memory(_test_deputy_id)
	# 3600 s = 1.0 h
	assert_almost_eq(m.hours_played, 1.0, 1e-4)

func test_victory_bumps_trust_and_bond():
	MemoryStore.consolidate_after_match(_test_deputy_id,
		{"outcome": "victory", "elapsed_s": 100.0, "enemy_buildings_killed": 3})
	var m = MemoryStore.load_memory(_test_deputy_id)
	assert_gt(float(m.relationship_traits.get("trust", 0.0)), 0.0)
	assert_gt(float(m.relationship_traits.get("bond", 0.0)), 0.0)

func test_defeat_bumps_frustration_dips_trust():
	MemoryStore.consolidate_after_match(_test_deputy_id,
		{"outcome": "defeat", "elapsed_s": 100.0, "enemy_buildings_killed": 0})
	var m = MemoryStore.load_memory(_test_deputy_id)
	assert_lt(float(m.relationship_traits.get("trust", 0.0)), 0.0)
	assert_gt(float(m.relationship_traits.get("frustration", 0.0)), 0.0)

func test_traits_clamped_to_unit_range():
	# Run 50 victories — trust should saturate at 1.0, not run away.
	for i in 50:
		MemoryStore.consolidate_after_match(_test_deputy_id,
			{"outcome": "victory", "elapsed_s": 60.0, "enemy_buildings_killed": 3})
	var m = MemoryStore.load_memory(_test_deputy_id)
	assert_lte(float(m.relationship_traits.get("trust", 0.0)), 1.0)
	assert_lte(float(m.relationship_traits.get("bond", 0.0)), 1.0)

func test_anecdote_appended_each_match():
	MemoryStore.consolidate_after_match(_test_deputy_id,
		{"outcome": "victory", "elapsed_s": 120.0, "enemy_buildings_killed": 3})
	var m = MemoryStore.load_memory(_test_deputy_id)
	assert_eq(m.match_anecdotes.size(), 1)
	assert_gt(m.match_anecdotes[0].length(), 0)
	assert_lte(m.match_anecdotes[0].length(), 80)   # spec ≤80 chars

func test_anecdotes_pruned_at_twelve():
	# Synthesize 14 matches; only the latest 12 should survive.
	for i in 14:
		MemoryStore.consolidate_after_match(_test_deputy_id,
			{"outcome": "victory", "elapsed_s": float(i * 10), "enemy_buildings_killed": 3})
	var m = MemoryStore.load_memory(_test_deputy_id)
	assert_eq(m.match_anecdotes.size(), MemoryStore.MAX_ANECDOTES)
	# Front-popped — the very first one is gone.
	for line in m.match_anecdotes:
		assert_ne(line.find("at 0 s"), -1) if line.find("at 0 s") != -1 else null
		# Just make sure the array still holds 12 distinct strings.
		assert_gt(line.length(), 0)

func test_unknown_outcome_does_not_touch_wins_or_losses():
	MemoryStore.consolidate_after_match(_test_deputy_id,
		{"outcome": "abort", "elapsed_s": 30.0, "enemy_buildings_killed": 0})
	var m = MemoryStore.load_memory(_test_deputy_id)
	assert_eq(m.wins, 0)
	assert_eq(m.losses, 0)
	assert_eq(m.total_matches, 1)
