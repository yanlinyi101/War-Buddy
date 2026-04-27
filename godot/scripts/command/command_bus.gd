# Autoload as `CommandBus` via project.godot.
# class_name omitted to avoid colliding with the autoload symbol of the same name.
extends Node

const TacticalOrder = preload("res://scripts/command/tactical_order.gd")
const ActionPlan = preload("res://scripts/command/action_plan.gd")
const ControlPolicy = preload("res://scripts/command/control_policy.gd")
const OrderTypeRegistry = preload("res://scripts/command/order_type_registry.gd")

signal plan_issued(plan: Resource)
signal order_issued(order: Resource)
signal order_rejected(order: Resource, reason: StringName)

const RING_BUFFER_SIZE := 200
const LOG_DIR := "user://order_log"

var _registry: Node = null     # OrderTypeRegistry
var _policy: ControlPolicy = null
var _seen_ids: Dictionary = {}      # StringName -> true; for dup detection across recent buffer
var _recent_orders: Array[Resource] = []
var _recent_plans: Array[Resource] = []
var match_id: String = ""           # set by bootstrap; default empty disables file output
var persistence_enabled: bool = true

func _ready() -> void:
	if _policy == null:
		_policy = ControlPolicy.FullControlPolicy.new()

func set_registry(reg: Node) -> void:
	_registry = reg

func set_policy(policy: ControlPolicy) -> void:
	_policy = policy

func get_recent_orders(limit: int = 50) -> Array[Resource]:
	var n = mini(limit, _recent_orders.size())
	var out: Array[Resource] = []
	for i in n:
		out.append(_recent_orders[_recent_orders.size() - 1 - i])
	return out

func get_recent_plans(limit: int = 20) -> Array[Resource]:
	var n = mini(limit, _recent_plans.size())
	var out: Array[Resource] = []
	for i in n:
		out.append(_recent_plans[_recent_plans.size() - 1 - i])
	return out

func submit_plan(plan: Resource) -> Dictionary:
	var inv = plan.validate_invariants()
	if not inv["ok"]:
		return {"accepted": [], "rejected": [], "plan_rejected": true,
		        "violations": inv["violations"]}
	_recent_plans.append(plan)
	_trim(_recent_plans, RING_BUFFER_SIZE)
	plan_issued.emit(plan)
	_persist_plan(plan)
	var order_result = submit_orders(plan.orders)
	order_result["plan_rejected"] = false
	return order_result

func submit_orders(orders: Array) -> Dictionary:
	var accepted: Array[Resource] = []
	var rejected: Array = []
	for o in orders:
		var reason := _validate_order(o)
		if reason != &"":
			rejected.append({"order": o, "reason": reason})
			order_rejected.emit(o, reason)
			_persist_rejected(o, reason)
			continue
		_seen_ids[o.id] = true
		_recent_orders.append(o)
		_trim(_recent_orders, RING_BUFFER_SIZE)
		order_issued.emit(o)
		accepted.append(o)
		_persist_order(o)
	return {"accepted": accepted, "rejected": rejected}

func _validate_order(o: Resource) -> StringName:
	if o == null:
		return &"null_order"
	if o.status != &"pending":
		return &"non_pending_status"
	if o.id == &"" or _seen_ids.has(o.id):
		return &"duplicate_id"
	if _registry == null:
		return &"registry_not_set"
	var def = _registry.get_def(o.type_id)
	if def == null:
		return &"unknown_type_id"
	var p_check = _registry.validate_params(o.type_id, o.params)
	if not p_check["ok"]:
		return &"invalid_params"
	if not _policy.can_issue(o.issuer, o.deputy, o.type_id):
		return &"control_policy_denied"
	if def.min_targets > 0 and not o.is_targeted():
		return &"target_required"
	return &""

func _trim(buf: Array, max_size: int) -> void:
	while buf.size() > max_size:
		buf.pop_front()

# --- Persistence (best-effort, never blocks) ---

func _ensure_log_dir() -> void:
	if not DirAccess.dir_exists_absolute(LOG_DIR):
		DirAccess.make_dir_recursive_absolute(LOG_DIR)

func _persist_order(o: Resource) -> void:
	if not persistence_enabled or match_id == "":
		return
	_ensure_log_dir()
	var path = "%s/%s.ndjson" % [LOG_DIR, match_id]
	var f = FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	var entry = o.to_dict()
	entry["accepted_at_ms"] = Time.get_ticks_msec()
	f.store_line(JSON.stringify(entry))
	f.close()

func _persist_rejected(o: Resource, reason: StringName) -> void:
	if not persistence_enabled or match_id == "":
		return
	_ensure_log_dir()
	var path = "%s/%s.rejected.ndjson" % [LOG_DIR, match_id]
	var f = FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	var entry = o.to_dict()
	entry["reason"] = String(reason)
	entry["rejected_at_ms"] = Time.get_ticks_msec()
	f.store_line(JSON.stringify(entry))
	f.close()

func _persist_plan(p: Resource) -> void:
	if not persistence_enabled or match_id == "":
		return
	_ensure_log_dir()
	var path = "%s/%s.plans.ndjson" % [LOG_DIR, match_id]
	var f = FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	var entry = p.to_dict()
	entry["accepted_at_ms"] = Time.get_ticks_msec()
	f.store_line(JSON.stringify(entry))
	f.close()
