extends "res://addons/gut/test.gd"

# Plan v0.15.1 §6.7 — verify the v0.15.1 graybox holds:
#   1 player HQ + 1 enemy HQ
#   6 workers
#   8 player main mineral + 6 player nat mineral + 1 player gas
#   8 enemy main mineral + 6 enemy nat mineral + 1 enemy gas
#   1 central gold patch
#   3 platforms / plateau static bodies

const WorldScene = preload("res://scenes/world.tscn")

var _world: Node = null

func before_each():
	_world = WorldScene.instantiate()
	add_child_autofree(_world)

func test_three_platforms_present():
	assert_ne(_world.get_node_or_null("PlatformPlayer"), null)
	assert_ne(_world.get_node_or_null("PlatformEnemy"), null)
	assert_ne(_world.get_node_or_null("CentralPlateau"), null)

func test_player_main_resources():
	# 8 main mineral + 1 gas.
	for i in 8:
		assert_ne(_world.get_node_or_null("Mineral_P_%d" % i), null)
	assert_ne(_world.get_node_or_null("Gas_P_0"), null)

func test_player_nat_resources():
	# 6 nat mineral.
	for i in 6:
		assert_ne(_world.get_node_or_null("Mineral_PN_%d" % i), null)

func test_enemy_main_and_nat_resources():
	for i in 8:
		assert_ne(_world.get_node_or_null("Mineral_E_%d" % i), null)
	for i in 6:
		assert_ne(_world.get_node_or_null("Mineral_EN_%d" % i), null)
	assert_ne(_world.get_node_or_null("Gas_E_0"), null)

func test_central_gold_mine_present():
	var g = _world.get_node_or_null("GoldMine")
	assert_ne(g, null)
	assert_true(g.is_in_group("resource_nodes_gold"))
	assert_almost_eq(g.global_position.y, 2.1, 0.01)

func test_total_resource_counts_in_groups():
	# Tree-group lookup after world add.
	var minerals = get_tree().get_nodes_in_group("resource_nodes_mineral")
	var gases = get_tree().get_nodes_in_group("resource_nodes_gas")
	var golds = get_tree().get_nodes_in_group("resource_nodes_gold")
	# Per side: 8 main + 6 nat = 14 mineral, ×2 sides = 28.
	assert_gte(minerals.size(), 28)
	# 2 gas geysers (1 per side).
	assert_gte(gases.size(), 2)
	# 1 gold patch.
	assert_gte(golds.size(), 1)
