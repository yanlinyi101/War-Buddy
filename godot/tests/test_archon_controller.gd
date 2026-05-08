extends "res://addons/gut/test.gd"

const ArchonControllerScript = preload("res://scripts/ai/archon_controller.gd")
const CommandBusScript = preload("res://scripts/command/command_bus.gd")
const RegistryScript = preload("res://scripts/command/order_type_registry.gd")
const ControlPolicyScript = preload("res://scripts/command/control_policy.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")
const DeputyScript = preload("res://scripts/ai/deputy.gd")
const DeputyPersonaScript = preload("res://scripts/ai/deputy_persona.gd")

func _make_bus() -> Node:
	var registry = RegistryScript.new()
	var def = RegistryScript.TypeDef.new()
	def.id = &"move"
	def.param_schema = {}
	def.min_targets = 1
	registry.register(def)
	var bus = CommandBusScript.new()
	bus.set_registry(registry)
	bus.set_policy(ControlPolicyScript.FullControlPolicy.new())
	bus.persistence_enabled = false
	add_child_autofree(registry)
	add_child_autofree(bus)
	return bus

func _make_deputy() -> Node:
	var d = DeputyScript.new()
	d.deputy_id = &"deputy"
	d.persona = DeputyPersonaScript.new()
	add_child_autofree(d)
	return d

func _make_order(id: StringName, issuer: int, deputy: StringName) -> Resource:
	var o = TacticalOrderScript.new()
	o.id = id
	o.type_id = &"move"
	o.origin = TacticalOrderScript.Origin.SCRIPT
	o.issuer = issuer
	o.deputy = deputy
	o.target_position = Vector3(1, 0, 1)
	return o

func test_archon_attach_blocks_ai_deputy_orders():
	var bus = _make_bus()
	var dep = _make_deputy()
	var arc = ArchonControllerScript.new()
	add_child_autofree(arc)
	arc.bind(bus, dep)

	# Before attach: AI deputy orders accepted.
	var pre = bus.submit_orders([_make_order(&"pre", TacticalOrderScript.Issuer.DEPUTY, &"deputy")])
	assert_eq(pre["accepted"].size(), 1)

	arc.attach(&"deputy", &"local_player")
	assert_true(arc.is_attached())
	assert_eq(arc.attached_seat(), &"deputy")

	# After attach: same kind of order is rejected for the attached seat.
	var post = bus.submit_orders([_make_order(&"post", TacticalOrderScript.Issuer.DEPUTY, &"deputy")])
	assert_eq(post["accepted"].size(), 0)
	assert_eq(post["rejected"][0]["reason"], &"control_policy_denied")

func test_archon_attach_still_accepts_player_orders():
	var bus = _make_bus()
	var dep = _make_deputy()
	var arc = ArchonControllerScript.new()
	add_child_autofree(arc)
	arc.bind(bus, dep)
	arc.attach(&"deputy", &"local_player")

	var ok = bus.submit_orders([_make_order(&"pl", TacticalOrderScript.Issuer.PLAYER, &"deputy")])
	assert_eq(ok["accepted"].size(), 1)

func test_archon_detach_restores_prior_policy():
	var bus = _make_bus()
	var dep = _make_deputy()
	var arc = ArchonControllerScript.new()
	add_child_autofree(arc)
	arc.bind(bus, dep)

	arc.attach(&"deputy", &"local_player")
	arc.detach()
	assert_false(arc.is_attached())

	# After detach: AI deputy orders accepted again.
	var post = bus.submit_orders([_make_order(&"after_detach", TacticalOrderScript.Issuer.DEPUTY, &"deputy")])
	assert_eq(post["accepted"].size(), 1)

func test_archon_double_attach_returns_false():
	var bus = _make_bus()
	var dep = _make_deputy()
	var arc = ArchonControllerScript.new()
	add_child_autofree(arc)
	arc.bind(bus, dep)
	assert_true(arc.attach(&"deputy", &"p1"))
	assert_false(arc.attach(&"deputy", &"p2"))

func test_archon_toggle():
	var bus = _make_bus()
	var dep = _make_deputy()
	var arc = ArchonControllerScript.new()
	add_child_autofree(arc)
	arc.bind(bus, dep)
	arc.toggle(&"deputy")
	assert_true(arc.is_attached())
	arc.toggle(&"deputy")
	assert_false(arc.is_attached())
