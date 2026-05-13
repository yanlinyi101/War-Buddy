extends "res://addons/gut/test.gd"

# Plan v0.15.1 §6.4 — gold patch joins `resource_nodes_gold` group,
# carries the 3000-amount / 8-cycle premium per the spec.

const GoldPatchScene = preload("res://scenes/gold_patch.tscn")

func test_gold_patch_joins_gold_group():
	var g = GoldPatchScene.instantiate()
	add_child_autofree(g)
	assert_true(g.is_in_group("resource_nodes_gold"))
	assert_true(g.is_in_group("resource_nodes"))
	# NOT in the regular mineral group.
	assert_false(g.is_in_group("resource_nodes_mineral"))

func test_gold_patch_has_premium_stats():
	var g = GoldPatchScene.instantiate()
	add_child_autofree(g)
	assert_eq(g.initial_amount, 3000)
	assert_eq(g.harvest_amount_per_cycle, 8)
	assert_eq(g.def.initial_amount, 3000)
	assert_eq(g.def.harvest_amount_per_cycle, 8)
	assert_true(g.def.depletes)
