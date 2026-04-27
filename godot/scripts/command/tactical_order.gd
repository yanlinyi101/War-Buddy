class_name TacticalOrder
extends Resource

enum Origin { PRE_PLAN, TACTICAL_VOICE, STRATEGIC_DECOMPOSITION, SCRIPT, HERO_DIRECT }
enum Issuer { PLAYER, DEPUTY, CAPTAIN, SCRIPT }

@export var id: StringName = &""
@export var type_id: StringName = &""
@export var origin: Origin = Origin.SCRIPT
@export var issuer: Issuer = Issuer.PLAYER
@export var deputy: StringName = &""

@export var target_unit_ids: Array[int] = []
@export var target_squad_id: StringName = &""
@export var target_grid: Vector2i = Vector2i(-1, -1)
@export var target_landmark: StringName = &""
@export var target_position: Vector3 = Vector3.ZERO

@export var params: Dictionary = {}

@export var priority: int = 0
@export var queue_mode: StringName = &"replace"
@export var timestamp_ms: int = 0
@export var expires_at_ms: int = 0

@export var rationale: String = ""
@export var confidence: float = 1.0
@export var parent_intent_id: StringName = &""

@export var status: StringName = &"pending"

func is_targeted() -> bool:
	if target_position != Vector3.ZERO:
		return true
	if target_landmark != &"":
		return true
	if target_grid != Vector2i(-1, -1):
		return true
	if target_squad_id != &"":
		return true
	if not target_unit_ids.is_empty():
		return true
	return false

func is_expired(now_ms: int) -> bool:
	if expires_at_ms == 0:
		return false
	return now_ms >= expires_at_ms

func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"type_id": String(type_id),
		"origin": int(origin),
		"issuer": int(issuer),
		"deputy": String(deputy),
		"target_unit_ids": target_unit_ids.duplicate(),
		"target_squad_id": String(target_squad_id),
		"target_grid": [target_grid.x, target_grid.y],
		"target_landmark": String(target_landmark),
		"target_position": [target_position.x, target_position.y, target_position.z],
		"params": params.duplicate(true),
		"priority": priority,
		"queue_mode": String(queue_mode),
		"timestamp_ms": timestamp_ms,
		"expires_at_ms": expires_at_ms,
		"rationale": rationale,
		"confidence": confidence,
		"parent_intent_id": String(parent_intent_id),
		"status": String(status),
	}

static func from_dict(d: Dictionary) -> TacticalOrder:
	var o := TacticalOrder.new()
	o.id = StringName(d.get("id", ""))
	o.type_id = StringName(d.get("type_id", ""))
	o.origin = int(d.get("origin", Origin.SCRIPT))
	o.issuer = int(d.get("issuer", Issuer.PLAYER))
	o.deputy = StringName(d.get("deputy", ""))
	var raw_uids: Array = d.get("target_unit_ids", [])
	var typed_uids: Array[int] = []
	for v in raw_uids:
		typed_uids.append(int(v))
	o.target_unit_ids = typed_uids
	o.target_squad_id = StringName(d.get("target_squad_id", ""))
	var grid_arr: Array = d.get("target_grid", [-1, -1])
	o.target_grid = Vector2i(int(grid_arr[0]), int(grid_arr[1]))
	o.target_landmark = StringName(d.get("target_landmark", ""))
	var pos_arr: Array = d.get("target_position", [0, 0, 0])
	o.target_position = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
	o.params = (d.get("params", {}) as Dictionary).duplicate(true)
	o.priority = int(d.get("priority", 0))
	o.queue_mode = StringName(d.get("queue_mode", "replace"))
	o.timestamp_ms = int(d.get("timestamp_ms", 0))
	o.expires_at_ms = int(d.get("expires_at_ms", 0))
	o.rationale = String(d.get("rationale", ""))
	o.confidence = float(d.get("confidence", 1.0))
	o.parent_intent_id = StringName(d.get("parent_intent_id", ""))
	o.status = StringName(d.get("status", "pending"))
	return o
