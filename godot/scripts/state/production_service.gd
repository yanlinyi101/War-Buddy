# ProductionService — registered as `ProductionService` autoload via project.godot.
# class_name omitted to avoid colliding with the autoload symbol.
#
# Doc 09 §5.4 (construction) + §6 (tech tree) + §7.4 (supply). Handles
# the `train` and (later) `build` / `research` order types from spec 09 §9.
#
# v0.10.2 scope:
#   - In-memory production queues keyed by building instance id.
#   - validate_train(faction, build_id, unit_id) checks cost / supply /
#     tier / prerequisites / `produces` list.
#   - enqueue_train(building_id, faction, unit_id) deducts cost and
#     pushes onto the queue; returns reason if rejected.
#   - tick(delta) advances build progress on the head of each queue;
#     completion publishes EventBus.order_completed and pops the queue.
#   - No physical unit spawn yet (the graybox map has no spawn point).
#     v0.10.3+ wires spawn locations + nav agents.

extends Node

signal training_completed(faction_id: StringName, building_id: int, unit_id: StringName)
signal training_failed(faction_id: StringName, building_id: int, reason: StringName)

class Job:
	extends RefCounted
	var unit_id: StringName
	var build_time_remaining: float
	var build_time_total: float
	func _init(uid: StringName, time: float) -> void:
		unit_id = uid
		build_time_total = time
		build_time_remaining = time

# building_instance_id (int) → Array[Job]
var _queues: Dictionary = {}

func validate_train(faction: Resource, building_def: Resource, unit_id: StringName) -> Dictionary:
	if faction == null:
		return {"ok": false, "reason": &"no_faction"}
	if building_def == null:
		return {"ok": false, "reason": &"no_building"}
	var unit_def: Resource = null
	var t = get_tree()
	if t != null:
		var lib = t.root.get_node_or_null("EntityLibrary")
		if lib != null:
			unit_def = lib.unit(unit_id)
	if unit_def == null:
		return {"ok": false, "reason": &"unknown_unit"}
	if not building_def.produces.has(unit_id):
		return {"ok": false, "reason": &"building_cannot_produce_unit"}
	# Tier gating
	if unit_def.tech_tier > faction.current_tier:
		return {"ok": false, "reason": &"tier_locked"}
	for prereq in unit_def.prerequisites:
		if not faction.buildings_completed.has(prereq):
			return {"ok": false, "reason": &"missing_prerequisite"}
	# Supply cap
	if faction.supply_used + unit_def.supply_cost > faction.supply_max:
		return {"ok": false, "reason": &"supply_blocked"}
	# Cost
	if not faction.has_resources(unit_def.mineral_cost, unit_def.gas_cost):
		return {"ok": false, "reason": &"insufficient_resources"}
	return {"ok": true, "reason": &"", "unit_def": unit_def}

func enqueue_train(faction: Resource, building_id: int, building_def: Resource,
		unit_id: StringName) -> Dictionary:
	var v = validate_train(faction, building_def, unit_id)
	if not v["ok"]:
		training_failed.emit(faction.faction_id, building_id, v["reason"])
		return v
	var unit_def: Resource = v["unit_def"]
	# Spend resources + reserve supply on enqueue (SC2 convention — the
	# moment you click train, the cost is gone; cancel refunds 75%).
	if not faction.spend(unit_def.mineral_cost, unit_def.gas_cost):
		return {"ok": false, "reason": &"insufficient_resources"}
	faction.supply_used += unit_def.supply_cost
	var q: Array = _queues.get(building_id, [])
	var job := Job.new(unit_id, unit_def.build_time_seconds)
	q.append(job)
	_queues[building_id] = q
	return {"ok": true, "reason": &""}

func cancel_head(faction: Resource, building_id: int) -> Dictionary:
	var q: Array = _queues.get(building_id, [])
	if q.is_empty():
		return {"ok": false, "reason": &"empty_queue"}
	var job: Job = q.pop_front()
	_queues[building_id] = q
	# 75% refund per spec §5.4.
	var lib = get_tree().root.get_node_or_null("EntityLibrary")
	if lib != null:
		var unit_def = lib.unit(job.unit_id)
		if unit_def != null:
			faction.refund(int(unit_def.mineral_cost * 0.75), int(unit_def.gas_cost * 0.75))
			faction.supply_used = maxi(0, faction.supply_used - unit_def.supply_cost)
	return {"ok": true, "reason": &""}

func tick(faction: Resource, delta: float) -> void:
	# Iterate over a snapshot of keys so we can safely mutate.
	for building_id in _queues.keys():
		var q: Array = _queues[building_id]
		if q.is_empty():
			continue
		var head: Job = q[0]
		head.build_time_remaining = maxf(0.0, head.build_time_remaining - delta)
		if head.build_time_remaining <= 0.0:
			q.pop_front()
			_queues[building_id] = q
			# No physical spawn yet — emit event so future spawn code
			# can hook in. Faction's running supply was already debited
			# at enqueue; nothing to refund here.
			training_completed.emit(faction.faction_id, building_id, head.unit_id)

func queue_length(building_id: int) -> int:
	var q: Array = _queues.get(building_id, [])
	return q.size()

func queue_unit_ids(building_id: int) -> Array:
	var out: Array = []
	for job in _queues.get(building_id, []):
		out.append(String(job.unit_id))
	return out

func _reset_for_test() -> void:
	_queues.clear()
