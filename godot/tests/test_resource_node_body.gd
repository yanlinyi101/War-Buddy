extends "res://addons/gut/test.gd"

const MineralPatchScene = preload("res://scenes/mineral_patch.tscn")
const GasGeyserScene = preload("res://scenes/gas_geyser.tscn")

func test_mineral_patch_joins_resource_nodes_mineral_group():
	var n = MineralPatchScene.instantiate()
	add_child_autofree(n)
	assert_true(n.is_in_group("resource_nodes"))
	assert_true(n.is_in_group("resource_nodes_mineral"))
	assert_false(n.is_in_group("resource_nodes_gas"))

func test_mineral_patch_def_has_expected_initial_amount():
	var n = MineralPatchScene.instantiate()
	add_child_autofree(n)
	assert_ne(n.def, null)
	assert_eq(n.def.initial_amount, 1500)
	assert_eq(n.def.current_amount, 1500)
	assert_true(n.def.depletes)

func test_gas_geyser_does_not_deplete():
	var g = GasGeyserScene.instantiate()
	add_child_autofree(g)
	assert_true(g.is_in_group("resource_nodes_gas"))
	assert_false(g.def.depletes)
	# Gas harvest returns the cycle amount regardless of current_amount.
	assert_eq(g.harvest(), g.def.harvest_amount_per_cycle)
	assert_false(g.is_depleted())

func test_mineral_patch_harvest_decrements():
	var n = MineralPatchScene.instantiate()
	add_child_autofree(n)
	var pre = n.def.current_amount
	var taken = n.harvest()
	assert_eq(taken, 5)
	assert_eq(n.def.current_amount, pre - 5)
