extends "res://addons/gut/test.gd"

const OrderExecutorScript = preload("res://scripts/command/order_executor.gd")
const CommandBusScript = preload("res://scripts/command/command_bus.gd")
const RegistryScript = preload("res://scripts/command/order_type_registry.gd")
const ControlPolicyScript = preload("res://scripts/command/control_policy.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

class FakeUnit extends Node:
	var unit_id: String = "fake"
	var moved_to: Vector3 = Vector3.ZERO
	var move_count: int = 0
	var attacked: Node = null
	var stopped: bool = false
	func order_move(p: Vector3) -> void:
		moved_to = p
		move_count += 1
	func order_attack(t: Node) -> void:
		attacked = t
	func stop() -> void:
		stopped = true

class FakeBuilding extends Node:
	pass

func _make_bus() -> Node:
	var registry = RegistryScript.new()
	for tid in [&"move", &"attack", &"stop", &"hold"]:
		var def = RegistryScript.TypeDef.new()
		def.id = tid
		def.param_schema = {}
		def.min_targets = 1 if tid == &"move" or tid == &"attack" else 0
		registry.register(def)
	var bus = CommandBusScript.new()
	bus.set_registry(registry)
	bus.set_policy(ControlPolicyScript.FullControlPolicy.new())
	bus.persistence_enabled = false
	add_child_autofree(registry)
	add_child_autofree(bus)
	return bus

func _make_order(id: StringName, type_id: StringName) -> Resource:
	var o = TacticalOrderScript.new()
	o.id = id
	o.type_id = type_id
	o.origin = TacticalOrderScript.Origin.SCRIPT
	o.issuer = TacticalOrderScript.Issuer.PLAYER
	return o

func test_executor_moves_squad_units_when_target_squad_id_set():
	var bus = _make_bus()
	var executor = OrderExecutorScript.new()
	add_child_autofree(executor)
	executor.bind_bus(bus)
	var unit_a = FakeUnit.new()
	unit_a.unit_id = "alpha_a"
	var unit_b = FakeUnit.new()
	unit_b.unit_id = "alpha_b"
	add_child_autofree(unit_a)
	add_child_autofree(unit_b)
	unit_a.add_to_group("squad_alpha")
	unit_b.add_to_group("squad_alpha")

	var o = _make_order(&"m1", &"move")
	o.target_kind = TacticalOrderScript.TARGET_KIND_POSITION
	o.target_position = Vector3(5, 0, 5)
	o.target_squad_id = &"alpha"
	bus.submit_orders([o])

	assert_eq(unit_a.move_count, 1)
	assert_eq(unit_b.move_count, 1)
	assert_eq(unit_a.moved_to, Vector3(5, 0, 5))

func test_executor_skips_deputy_issued_orders():
	var bus = _make_bus()
	var executor = OrderExecutorScript.new()
	add_child_autofree(executor)
	executor.bind_bus(bus)
	var unit = FakeUnit.new()
	add_child_autofree(unit)
	unit.add_to_group("squad_alpha")

	var o = _make_order(&"m2", &"move")
	o.target_kind = TacticalOrderScript.TARGET_KIND_POSITION
	o.target_position = Vector3(2, 0, 2)
	o.target_squad_id = &"alpha"
	o.issuer = TacticalOrderScript.Issuer.DEPUTY
	o.deputy = &"deputy"
	bus.submit_orders([o])

	# Deputy-issued orders are intent — captain re-emits them as CAPTAIN.
	# Executor must skip to avoid double-execution.
	assert_eq(unit.move_count, 0)

func test_executor_attacks_landmark_node():
	var bus = _make_bus()
	var executor = OrderExecutorScript.new()
	add_child_autofree(executor)
	executor.bind_bus(bus)
	var unit = FakeUnit.new()
	add_child_autofree(unit)
	unit.add_to_group("squad_alpha")
	var building = FakeBuilding.new()
	building.name = "EnemyBuildingA"
	add_child_autofree(building)
	building.add_to_group("enemy_buildings")

	var o = _make_order(&"a1", &"attack")
	o.target_kind = TacticalOrderScript.TARGET_KIND_LANDMARK
	o.target_landmark = &"EnemyBuildingA"
	o.target_squad_id = &"alpha"
	bus.submit_orders([o])

	assert_eq(unit.attacked, building)

func test_executor_stops_units():
	var bus = _make_bus()
	var executor = OrderExecutorScript.new()
	add_child_autofree(executor)
	executor.bind_bus(bus)
	var unit = FakeUnit.new()
	add_child_autofree(unit)
	unit.add_to_group("squad_alpha")

	var o = _make_order(&"s1", &"stop")
	o.target_kind = TacticalOrderScript.TARGET_KIND_SQUAD
	o.target_squad_id = &"alpha"
	bus.submit_orders([o])

	assert_true(unit.stopped)

func test_executor_skips_hero_targeted_orders():
	var bus = _make_bus()
	var executor = OrderExecutorScript.new()
	add_child_autofree(executor)
	executor.bind_bus(bus)
	var unit = FakeUnit.new()
	add_child_autofree(unit)
	unit.add_to_group("squad_alpha")

	var o = _make_order(&"h1", &"move")
	o.target_kind = TacticalOrderScript.TARGET_KIND_HERO
	o.target_position = Vector3(1, 0, 1)
	bus.submit_orders([o])

	# hero-targeted orders are owned by hero_controller, not executor.
	assert_eq(unit.move_count, 0)
