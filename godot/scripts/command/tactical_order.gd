class_name TacticalOrder
extends Resource

# --- Enums --------------------------------------------------------------------

enum Origin { PRE_PLAN, TACTICAL_VOICE, STRATEGIC_DECOMPOSITION, SCRIPT, HERO_DIRECT }
enum Issuer { PLAYER, DEPUTY, CAPTAIN, SCRIPT }

# --- Status string constants (doc 07 §4 lifecycle, 8 states) -----------------
# `status` is a StringName for forward-compat; these constants name the canonical
# values. Linear advance, no rollback per doc 07 §4.2.
const STATUS_PENDING := &"pending"
const STATUS_CLASSIFYING := &"classifying"   # LLM call in flight; only relevant for plans, not raw orders
const STATUS_DISPATCHED := &"dispatched"     # accepted by bus, routed to deputy/captain, not yet executing
const STATUS_EXECUTING := &"executing"
const STATUS_COMPLETED := &"completed"
const STATUS_FAILED := &"failed"
const STATUS_CANCELED := &"canceled"
const STATUS_EXPIRED := &"expired"

# --- Priority (doc 07 §3.7, three semantic tiers) ----------------------------
# `priority: int` stays an open integer for future expansion, but these three
# constants are the canonical anchors LLM and pre-plans should use.
const PRIORITY_ROUTINE := 0
const PRIORITY_HIGH := 10
const PRIORITY_EMERGENCY := 20

# --- Posture (doc 07 §3.5, SC2 stance triad) ---------------------------------
# `posture` modifies engagement rules orthogonally to verb. Defaults to
# `aggressive` to match current MVP behavior (units pursue and engage in range).
const POSTURE_AGGRESSIVE := &"aggressive"
const POSTURE_STAND_GROUND := &"stand_ground"
const POSTURE_HOLD_FIRE := &"hold_fire"

# --- Target kind discriminator (doc 07 §3.3, tagged-union semantics) ---------
# Layered on top of the parallel target_* fields for backward compat.
# When set, identifies which target_* field is canonical, and supports the
# `ambiguous` mode that the parallel-fields encoding cannot represent.
const TARGET_KIND_NONE := &""
const TARGET_KIND_POSITION := &"position"
const TARGET_KIND_LANDMARK := &"landmark"
const TARGET_KIND_GRID := &"grid"
const TARGET_KIND_SQUAD := &"squad"
const TARGET_KIND_UNITS := &"units"
const TARGET_KIND_UNIT_REF := &"unit_ref"        # namespaced string ref, e.g. "captain:alpha"
const TARGET_KIND_AMBIGUOUS := &"ambiguous"      # value in target_ambiguous_candidates
const TARGET_KIND_SELF := &"self"
const TARGET_KIND_HERO := &"hero"
const TARGET_KIND_PARAM := &"param"               # pre-plan parametric placeholder, see PrePlan §6.3

# --- Identity & classification ------------------------------------------------

@export var id: StringName = &""
@export var type_id: StringName = &""
@export var origin: Origin = Origin.SCRIPT
@export var issuer: Issuer = Issuer.PLAYER
@export var deputy: StringName = &""

# --- Targeting ---------------------------------------------------------------
# Parallel fields kept for backward compatibility. New code should set
# `target_kind` to the canonical kind and write the matching field. Resolution
# in OrderResolver (doc 09) prefers `target_kind` when set, else falls back to
# the parallel-field priority (position > landmark > grid > squad > units).

@export var target_kind: StringName = TARGET_KIND_NONE
@export var target_unit_ids: Array[int] = []
@export var target_squad_id: StringName = &""
@export var target_grid: Vector2i = Vector2i(-1, -1)
@export var target_landmark: StringName = &""
@export var target_position: Vector3 = Vector3.ZERO
@export var target_unit_ref: String = ""                           # namespaced, e.g. "captain:alpha", "enemy_structure:hq_1"
@export var target_param: StringName = &""                          # pre-plan placeholder name, e.g. &"<my_main_base>"
@export var target_ambiguous_candidates: Array[String] = []         # for kind=ambiguous; deputy autonomy decides resolution

# --- Type-specific bag -------------------------------------------------------

@export var params: Dictionary = {}

# --- Engagement modifier -----------------------------------------------------

@export var posture: StringName = POSTURE_AGGRESSIVE

# --- Queue & lifecycle -------------------------------------------------------

@export var priority: int = PRIORITY_ROUTINE
@export var queue_mode: StringName = &"replace"
@export var timestamp_ms: int = 0
@export var expires_at_ms: int = 0

# --- AI provenance -----------------------------------------------------------

@export var rationale: String = ""
@export var confidence: float = 1.0
@export var parent_intent_id: StringName = &""

# --- Mutable status ----------------------------------------------------------

@export var status: StringName = STATUS_PENDING

# --- Methods -----------------------------------------------------------------

func is_targeted() -> bool:
	if target_kind == TARGET_KIND_AMBIGUOUS and not target_ambiguous_candidates.is_empty():
		return true
	if target_kind == TARGET_KIND_SELF or target_kind == TARGET_KIND_HERO:
		return true
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
	if target_unit_ref != "":
		return true
	if target_param != &"":
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
		"target_kind": String(target_kind),
		"target_unit_ids": target_unit_ids.duplicate(),
		"target_squad_id": String(target_squad_id),
		"target_grid": [target_grid.x, target_grid.y],
		"target_landmark": String(target_landmark),
		"target_position": [target_position.x, target_position.y, target_position.z],
		"target_unit_ref": target_unit_ref,
		"target_param": String(target_param),
		"target_ambiguous_candidates": target_ambiguous_candidates.duplicate(),
		"params": params.duplicate(true),
		"posture": String(posture),
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
	o.origin = int(d.get("origin", Origin.SCRIPT)) as Origin
	o.issuer = int(d.get("issuer", Issuer.PLAYER)) as Issuer
	o.deputy = StringName(d.get("deputy", ""))
	o.target_kind = StringName(d.get("target_kind", ""))
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
	o.target_unit_ref = String(d.get("target_unit_ref", ""))
	o.target_param = StringName(d.get("target_param", ""))
	var raw_amb: Array = d.get("target_ambiguous_candidates", [])
	var typed_amb: Array[String] = []
	for v in raw_amb:
		typed_amb.append(String(v))
	o.target_ambiguous_candidates = typed_amb
	o.params = (d.get("params", {}) as Dictionary).duplicate(true)
	o.posture = StringName(d.get("posture", POSTURE_AGGRESSIVE))
	o.priority = int(d.get("priority", PRIORITY_ROUTINE))
	o.queue_mode = StringName(d.get("queue_mode", "replace"))
	o.timestamp_ms = int(d.get("timestamp_ms", 0))
	o.expires_at_ms = int(d.get("expires_at_ms", 0))
	o.rationale = String(d.get("rationale", ""))
	o.confidence = float(d.get("confidence", 1.0))
	o.parent_intent_id = StringName(d.get("parent_intent_id", ""))
	o.status = StringName(d.get("status", STATUS_PENDING))
	return o
