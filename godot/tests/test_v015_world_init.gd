extends "res://addons/gut/test.gd"

# v0.15.0 task 4.8 — load world.tscn headless and verify the canonical
# starting layout: 1 player HQ + 1 enemy HQ + 6 workers + 8 player
# mineral + 1 player gas + 8 enemy mineral + 1 enemy gas.

const WorldScene = preload("res://scenes/world.tscn")

var _world: Node = null

func before_each():
	_world = WorldScene.instantiate()
	add_child_autofree(_world)

func test_player_hq_exists():
	var phq = _world.get_node_or_null("PlayerHq")
	assert_ne(phq, null)
	assert_eq(phq.faction_id, &"player")

func test_enemy_hq_exists():
	var ehq = _world.get_node_or_null("EnemyHq")
	assert_ne(ehq, null)
	assert_true(ehq.is_in_group("enemy_buildings"))

func test_six_workers_spawned():
	var workers: int = 0
	for i in 6:
		if _world.get_node_or_null("Worker_%d" % i) != null:
			workers += 1
	assert_eq(workers, 6)

func test_eight_player_mineral_patches():
	var n: int = 0
	for i in 8:
		if _world.get_node_or_null("Mineral_P_%d" % i) != null:
			n += 1
	assert_eq(n, 8)

func test_one_player_gas_geyser():
	assert_ne(_world.get_node_or_null("Gas_P_0"), null)

func test_eight_enemy_mineral_patches():
	var n: int = 0
	for i in 8:
		if _world.get_node_or_null("Mineral_E_%d" % i) != null:
			n += 1
	assert_eq(n, 8)

func test_one_enemy_gas_geyser():
	assert_ne(_world.get_node_or_null("Gas_E_0"), null)

func test_total_resource_nodes_in_groups():
	# Tree-group lookup once everything's added.
	var minerals = get_tree().get_nodes_in_group("resource_nodes_mineral")
	var gases = get_tree().get_nodes_in_group("resource_nodes_gas")
	# 16 mineral patches + 2 gas geysers ship at world load.
	assert_gte(minerals.size(), 16)
	assert_gte(gases.size(), 2)
