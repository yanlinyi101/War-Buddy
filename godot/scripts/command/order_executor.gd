class_name OrderExecutor
extends Node

# OrderExecutor — minimal v0.5.0 bridge between CommandBus and existing
# scene-tree units. Doc 09 (entities/combat/economy) will replace this with
# a proper resolver + behavior-tree executor; this is a focused stub that
# closes the strict A-chain so Deputy/Captain plans actually move SquadUnits.
#
# Scope (v0.5.0):
#   - Translate accepted `move`, `attack`, `stop`, `hold` orders into
#     SquadUnit.order_*() calls when targeted at a squad (target_squad_id)
#     or a unit list (target_unit_ids resolved by unit_id string match).
#   - Hero direct control stays in hero_controller.gd; orders with
#     target_kind=hero or issuer=PLAYER+empty deputy are ignored here.
#   - Landmarks resolved by name in scene-tree group "enemy_buildings".
#
# Out of scope (deferred to doc 09):
#   - target_grid, target_landmark for non-buildings, target_param.
#   - posture / priority / queue_mode semantics.
#   - status progression beyond emitting one print.

const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

signal order_executed(order: Resource, outcome: StringName)

var _bus: Node = null

func bind_bus(bus: Node) -> void:
	_bus = bus
	if bus.has_signal("order_issued"):
		bus.order_issued.connect(_on_order_issued)

func _on_order_issued(order: Resource) -> void:
	if order == null:
		return
	# Hero direct orders are handled by hero_controller; skip them here so
	# we don't double-fire.
	if order.target_kind == TacticalOrderScript.TARGET_KIND_HERO:
		return
	# Per strict A-chain (vision §2.4 / spec 08 §11.6): DEPUTY-issued orders
	# are intent — they get re-emitted by a Captain as CAPTAIN-issued before
	# physical execution. Skip them here to avoid double-execution.
	if order.issuer == TacticalOrderScript.Issuer.DEPUTY:
		return
	var outcome := _execute(order)
	order_executed.emit(order, outcome)
	if outcome != &"ok":
		print("[RTSMVP] OrderExecutor skipped %s (%s)" % [String(order.type_id), String(outcome)])

func _execute(order: Resource) -> StringName:
	var units := _resolve_units(order)
	match String(order.type_id):
		"move":
			var pos: Variant = _resolve_position(order)
			if pos == null:
				return &"no_position"
			if units.is_empty():
				return &"no_units"
			for u in units:
				if u.has_method("order_move"):
					u.order_move(pos)
			return &"ok"
		"attack":
			var target: Node = _resolve_attack_target(order)
			if target == null:
				# Fall back to position-attack if a position was supplied.
				var pos: Variant = _resolve_position(order)
				if pos == null:
					return &"no_target"
				if units.is_empty():
					return &"no_units"
				for u in units:
					if u.has_method("order_move"):
						u.order_move(pos)
				return &"ok"
			if units.is_empty():
				return &"no_units"
			for u in units:
				if u.has_method("order_attack"):
					u.order_attack(target)
			return &"ok"
		"stop", "hold":
			if units.is_empty():
				return &"no_units"
			for u in units:
				if u.has_method("stop"):
					u.stop()
			return &"ok"
		_:
			return &"unsupported_type"

func _resolve_units(order: Resource) -> Array:
	# Squad target: scene-tree group convention "squad_<id>".
	if order.target_squad_id != &"":
		return get_tree().get_nodes_in_group("squad_%s" % String(order.target_squad_id))
	# Unit-id list: match SquadUnit.unit_id.
	if not order.target_unit_ids.is_empty():
		var by_id: Array = []
		for u in get_tree().get_nodes_in_group("squad_units"):
			# target_unit_ids is Array[int]; squad_unit.unit_id is a string like "squad_a".
			# We accept either int suffix or whole-string match for v0.5.0.
			for tid in order.target_unit_ids:
				if String(tid) == String(u.unit_id):
					by_id.append(u)
					break
		return by_id
	return []

func _resolve_position(order: Resource) -> Variant:
	if order.target_position != Vector3.ZERO:
		return order.target_position
	if order.target_landmark != &"":
		var lm := _resolve_landmark(order.target_landmark)
		if lm != null:
			return lm.global_position
	return null

func _resolve_attack_target(order: Resource) -> Node:
	if order.target_landmark != &"":
		return _resolve_landmark(order.target_landmark)
	if order.target_unit_ref != "":
		# v0.5.0: match against enemy_buildings group by node name.
		for b in get_tree().get_nodes_in_group("enemy_buildings"):
			if String(b.name) == order.target_unit_ref:
				return b
	return null

func _resolve_landmark(name: StringName) -> Node:
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if String(b.name) == String(name):
			return b
	return null
