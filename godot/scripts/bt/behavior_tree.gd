class_name BehaviorTree
extends Node

# Doc 09 §12 — BT contract surface. Subclasses subscribe to
# CommandBus.order_issued and filter for orders addressed to their
# bound unit (by `target_unit_ids` containing the unit's id). Progress
# and outcome flow back through EventBus.order_* channels.
#
# v0.10.0 ships the contract only. Selectors / sequences / decorators
# are an implementation choice deferred to each concrete BT
# (worker_bt.gd, frontline_bt.gd, …).

signal current_order_changed(order: Resource)

const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

@export var unit_id: String = ""

var _current_order: Resource = null
var _bus: Node = null         # CommandBus
var _event_bus: Node = null   # EventBus

func bind(unit_id_arg: String, command_bus: Node, event_bus: Node) -> void:
	unit_id = unit_id_arg
	_bus = command_bus
	_event_bus = event_bus
	if _bus != null and not _bus.order_issued.is_connected(_on_order_issued):
		_bus.order_issued.connect(_on_order_issued)

func _on_order_issued(order: Resource) -> void:
	if order == null:
		return
	if not _is_addressed_to_me(order):
		return
	_current_order = order
	current_order_changed.emit(order)
	# Subclasses override `on_new_order` to actually execute.
	on_new_order(order)

func _is_addressed_to_me(order: Resource) -> bool:
	# Concrete BTs typically match either by target_unit_ids (mapped to
	# unit_id via a string-keyed lookup) or by target_squad_id. v0.10.0
	# default: match if target_unit_ids list contains a hashed match for
	# our unit_id string. Subclasses can override for richer matching.
	if order.target_unit_ids != null and not order.target_unit_ids.is_empty():
		for tid in order.target_unit_ids:
			# Compare as string for robustness across int/string ids.
			if str(tid) == unit_id:
				return true
	return false

# --- Subclass hooks ---

func on_new_order(_order: Resource) -> void:
	# Override.
	pass

# --- Outcome reporting ---

func report_completed(outcome: StringName = &"ok") -> void:
	if _event_bus != null and _current_order != null and _event_bus.has_method("publish_order_completed"):
		_event_bus.publish_order_completed(_current_order.id, unit_id, outcome)
	_current_order = null

func report_failed(reason: StringName) -> void:
	if _event_bus != null and _current_order != null and _event_bus.has_method("publish_order_failed"):
		_event_bus.publish_order_failed(_current_order.id, unit_id, reason)
	_current_order = null

func report_progress(fraction: float) -> void:
	if _event_bus != null and _current_order != null:
		_event_bus.order_progress.emit({
			"order_id": String(_current_order.id),
			"unit_id": unit_id,
			"fraction": clampf(fraction, 0.0, 1.0),
		})

func current_order() -> Resource:
	return _current_order
