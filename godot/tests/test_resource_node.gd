extends "res://addons/gut/test.gd"

const ResourceNodeDefScript = preload("res://scripts/state/resource_node.gd")

func _make_mineral() -> Resource:
	var n = ResourceNodeDefScript.new()
	n.node_id = &"mineral_a1"
	n.resource_type = &"mineral"
	n.initial_amount = 100
	n.current_amount = 100
	n.harvest_amount_per_cycle = 5
	n.max_concurrent_workers = 3
	n.depletes = true
	return n

func _make_gas() -> Resource:
	var g = ResourceNodeDefScript.new()
	g.node_id = &"gas_a1"
	g.resource_type = &"gas"
	g.initial_amount = 0
	g.current_amount = 0
	g.harvest_amount_per_cycle = 4
	g.max_concurrent_workers = 3
	g.depletes = false
	return g

func test_mineral_harvest_decrements_current_amount():
	var n = _make_mineral()
	assert_eq(n.harvest(), 5)
	assert_eq(n.current_amount, 95)

func test_mineral_harvest_clamps_at_remaining():
	var n = _make_mineral()
	n.current_amount = 3
	assert_eq(n.harvest(), 3)
	assert_eq(n.current_amount, 0)
	assert_true(n.is_depleted())

func test_gas_harvest_does_not_deplete():
	var g = _make_gas()
	g.harvest()
	g.harvest()
	assert_eq(g.current_amount, 0)
	assert_false(g.is_depleted())

func test_saturation_below_max():
	var n = _make_mineral()
	assert_almost_eq(n.saturation_for(1), 1.0 / 3.0, 1e-6)

func test_saturation_at_max_caps_at_one():
	var n = _make_mineral()
	assert_almost_eq(n.saturation_for(10), 1.0, 1e-6)

func test_to_dict_shape():
	var n = _make_mineral()
	var d = n.to_dict()
	assert_eq(d["node_id"], "mineral_a1")
	assert_eq(d["resource_type"], "mineral")
	assert_eq(d["current_amount"], 100)
	assert_true(d["depletes"])
