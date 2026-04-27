# 07 — Command System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the keystone command-system substrate from `07-command-system.md` — Resources for `TacticalOrder` and `ActionPlan`, the `CommandBus` and `OrderTypeRegistry` autoloads, four `ControlPolicy` implementations, the `PrePlan` artifact and `PrePlanRunner` node — fully covered by GUT tests, then wire bootstrap and tag v0.3.0.

**Architecture:** New module group under `godot/scripts/command/`. Two new autoloads (`CommandBus`, `OrderTypeRegistry`) registered in `project.godot`. PrePlanRunner subscribes to a small `notify_event(name, payload)` API on itself rather than introducing `EventBus`; spec 09 will route real events through this same API when `EventBus` lands. v0.3.0 ships a working command pipeline that *accepts and persists* orders even though no executor consumes them — that is intentional skeleton scope per vision §7.

**Tech Stack:** Godot 4.6.x, GDScript only, GUT 9.6.0 already at `godot/addons/gut/`.

---

## File Structure

### New files (created by tasks 1–7)

| Path | Responsibility |
|---|---|
| `godot/scripts/command/tactical_order.gd` | `TacticalOrder` Resource — order data class + to_dict/from_dict. |
| `godot/scripts/command/action_plan.gd` | `ActionPlan` Resource — wraps orders[] with deputy/tier/rationale. |
| `godot/scripts/command/order_type_registry.gd` | Autoload Node — type registration, param-shape validation, deputy filtering. |
| `godot/scripts/command/control_policy.gd` | Base `ControlPolicy` (RefCounted) + four concrete impls in the same file. |
| `godot/scripts/command/command_bus.gd` | Autoload Node — `submit_plan` / `submit_orders` ingress, validation, signals, ring buffer, ndjson persistence. |
| `godot/scripts/command/pre_plan.gd` | `PrePlan` + `PrePlanTrigger` Resources. |
| `godot/scripts/command/pre_plan_runner.gd` | Node — loads `*.tres` preplans, listens for `notify_event(name, payload)`, fires matching plans into `CommandBus.submit_orders`. |
| `godot/data/preplans/sample_match_start.tres` | Sample shipped pre-plan that fires on `match_start`. |
| `godot/tests/test_tactical_order.gd` | GUT cases for §1 below. |
| `godot/tests/test_action_plan.gd` | GUT cases for §2 below. |
| `godot/tests/test_order_type_registry.gd` | GUT cases for §3 below. |
| `godot/tests/test_control_policy.gd` | GUT cases for §4 below. |
| `godot/tests/test_command_bus.gd` | GUT cases for §5 below. |
| `godot/tests/test_pre_plan.gd` | GUT cases for §6 below (Resource serialization, trigger evaluation). |
| `godot/tests/test_pre_plan_runner.gd` | GUT cases for §7 below. |

### Modified files

| Path | What changes |
|---|---|
| `godot/project.godot` | Register two new autoloads: `OrderTypeRegistry` (loaded first), then `CommandBus` (depends on registry). |
| `godot/scripts/bootstrap.gd` | Register v1 core order types, instantiate `PrePlanRunner`, load `res://data/preplans/`, fire `notify_event("match_start", {})` once. |
| `docs/specs/05-godot-smoke-test-checklist.md` | Append "Command system (debug build)" section after Squad puppets section. |
| `CHANGELOG.md` | `[v0.3.0]` entry. |

---

## Task 1: `TacticalOrder` Resource

**Files:**
- Create: `godot/scripts/command/tactical_order.gd`
- Create: `godot/tests/test_tactical_order.gd`

- [ ] **Step 1: Create the test file**

`godot/tests/test_tactical_order.gd`:
```gdscript
extends "res://addons/gut/test.gd"

const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

func _make_basic() -> Resource:
	var o = TacticalOrderScript.new()
	o.id = &"ord_001"
	o.type_id = &"move"
	o.origin = TacticalOrderScript.Origin.TACTICAL_VOICE
	o.issuer = TacticalOrderScript.Issuer.PLAYER
	o.deputy = &"deputy"
	o.target_position = Vector3(5, 0, 5)
	o.timestamp_ms = 1000
	return o

func test_to_dict_round_trip_preserves_all_fields():
	var o = _make_basic()
	o.params = {"speed_mult": 0.5}
	o.target_unit_ids = [101, 102]
	o.rationale = "flank east"
	o.confidence = 0.82
	o.parent_intent_id = &"plan_42"
	o.expires_at_ms = 5000
	var d = o.to_dict()
	var restored = TacticalOrderScript.from_dict(d)
	assert_eq(restored.id, &"ord_001")
	assert_eq(restored.type_id, &"move")
	assert_eq(restored.origin, TacticalOrderScript.Origin.TACTICAL_VOICE)
	assert_eq(restored.issuer, TacticalOrderScript.Issuer.PLAYER)
	assert_eq(restored.deputy, &"deputy")
	assert_almost_eq(restored.target_position.x, 5.0, 0.001)
	assert_eq(restored.target_unit_ids, [101, 102])
	assert_eq(restored.params, {"speed_mult": 0.5})
	assert_eq(restored.rationale, "flank east")
	assert_almost_eq(restored.confidence, 0.82, 0.001)
	assert_eq(restored.parent_intent_id, &"plan_42")
	assert_eq(restored.expires_at_ms, 5000)

func test_is_targeted_returns_true_when_position_set():
	var o = _make_basic()
	assert_true(o.is_targeted())

func test_is_targeted_returns_true_when_only_unit_ids_set():
	var o = TacticalOrderScript.new()
	o.id = &"ord_002"
	o.type_id = &"attack"
	o.target_unit_ids = [200]
	assert_true(o.is_targeted())

func test_is_targeted_returns_false_when_nothing_set():
	var o = TacticalOrderScript.new()
	o.id = &"ord_003"
	o.type_id = &"stop"
	assert_false(o.is_targeted())

func test_is_expired_when_now_exceeds_expires_at():
	var o = _make_basic()
	o.expires_at_ms = 5000
	assert_false(o.is_expired(4999))
	assert_true(o.is_expired(5000))
	assert_true(o.is_expired(5001))

func test_is_expired_zero_means_never():
	var o = _make_basic()
	o.expires_at_ms = 0
	assert_false(o.is_expired(99999999))

func test_default_status_is_pending():
	var o = TacticalOrderScript.new()
	assert_eq(o.status, &"pending")
```

- [ ] **Step 2: Run tests — expect parse error (script missing)**

```bash
cd "D:/War Buddy"
godot --headless --path godot --import 2>&1 | tail -2
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -10
```
Expected: ERROR loading `res://scripts/command/tactical_order.gd`.

- [ ] **Step 3: Create the directory and implement**

```bash
mkdir -p "D:/War Buddy/godot/scripts/command"
```

`godot/scripts/command/tactical_order.gd`:
```gdscript
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
```

- [ ] **Step 4: Run tests — expect 19 (existing) + 7 (new) = 26 green**

```bash
godot --headless --path godot --import 2>&1 | tail -2
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -8
```
Expected: `Passing Tests 26`.

- [ ] **Step 5: Commit**

```bash
cd "D:/War Buddy" && git add godot/scripts/command/tactical_order.gd godot/tests/test_tactical_order.gd && git commit -m "feat(godot): add TacticalOrder Resource with to_dict/from_dict round-trip

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 2: `ActionPlan` Resource

**Files:**
- Create: `godot/scripts/command/action_plan.gd`
- Create: `godot/tests/test_action_plan.gd`

- [ ] **Step 1: Write the failing test**

`godot/tests/test_action_plan.gd`:
```gdscript
extends "res://addons/gut/test.gd"

const ActionPlanScript = preload("res://scripts/command/action_plan.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

func _make_order(id: StringName, deputy: StringName, origin: int) -> Resource:
	var o = TacticalOrderScript.new()
	o.id = id
	o.type_id = &"move"
	o.origin = origin
	o.issuer = TacticalOrderScript.Issuer.DEPUTY
	o.deputy = deputy
	o.target_position = Vector3(1, 0, 1)
	return o

func test_to_dict_round_trip():
	var p = ActionPlanScript.new()
	p.id = &"plan_001"
	p.deputy = &"deputy"
	p.tier = ActionPlanScript.Tier.TACTICAL
	p.rationale = "flank"
	p.confidence = 0.9
	p.triggering_utterance = "go east"
	p.timestamp_ms = 5000
	p.orders = [_make_order(&"ord_a", &"deputy", TacticalOrderScript.Origin.TACTICAL_VOICE)]
	var d = p.to_dict()
	var r = ActionPlanScript.from_dict(d)
	assert_eq(r.id, &"plan_001")
	assert_eq(r.deputy, &"deputy")
	assert_eq(r.tier, ActionPlanScript.Tier.TACTICAL)
	assert_eq(r.rationale, "flank")
	assert_almost_eq(r.confidence, 0.9, 0.001)
	assert_eq(r.triggering_utterance, "go east")
	assert_eq(r.timestamp_ms, 5000)
	assert_eq(r.orders.size(), 1)
	assert_eq(r.orders[0].id, &"ord_a")

func test_validate_invariants_passes_for_consistent_plan():
	var p = ActionPlanScript.new()
	p.id = &"plan_002"
	p.deputy = &"deputy"
	p.tier = ActionPlanScript.Tier.TACTICAL
	var o = _make_order(&"ord_a", &"deputy", TacticalOrderScript.Origin.TACTICAL_VOICE)
	o.parent_intent_id = &"plan_002"
	p.orders = [o]
	var result = p.validate_invariants()
	assert_true(result["ok"])
	assert_eq(result["violations"].size(), 0)

func test_validate_invariants_fails_when_order_deputy_mismatches():
	var p = ActionPlanScript.new()
	p.id = &"plan_003"
	p.deputy = &"deputy"
	p.tier = ActionPlanScript.Tier.TACTICAL
	var o = _make_order(&"ord_a", &"someone_else", TacticalOrderScript.Origin.TACTICAL_VOICE)
	o.parent_intent_id = &"plan_003"
	p.orders = [o]
	var result = p.validate_invariants()
	assert_false(result["ok"])
	assert_string_contains(result["violations"][0], "deputy")

func test_validate_invariants_fails_when_origin_mismatches_tier():
	var p = ActionPlanScript.new()
	p.id = &"plan_004"
	p.deputy = &"deputy"
	p.tier = ActionPlanScript.Tier.STRATEGIC
	var o = _make_order(&"ord_a", &"deputy", TacticalOrderScript.Origin.TACTICAL_VOICE)
	o.parent_intent_id = &"plan_004"
	p.orders = [o]
	var result = p.validate_invariants()
	assert_false(result["ok"])
	assert_string_contains(result["violations"][0], "origin")

func test_validate_invariants_fails_when_parent_intent_id_missing():
	var p = ActionPlanScript.new()
	p.id = &"plan_005"
	p.deputy = &"deputy"
	p.tier = ActionPlanScript.Tier.TACTICAL
	var o = _make_order(&"ord_a", &"deputy", TacticalOrderScript.Origin.TACTICAL_VOICE)
	# leave parent_intent_id blank
	p.orders = [o]
	var result = p.validate_invariants()
	assert_false(result["ok"])
	assert_string_contains(result["violations"][0], "parent_intent_id")

func test_apply_invariants_fixes_parent_intent_id_in_place():
	var p = ActionPlanScript.new()
	p.id = &"plan_006"
	p.deputy = &"deputy"
	p.tier = ActionPlanScript.Tier.TACTICAL
	var o = _make_order(&"ord_a", &"deputy", TacticalOrderScript.Origin.TACTICAL_VOICE)
	# leave parent_intent_id blank
	p.orders = [o]
	p.apply_invariants()
	assert_eq(p.orders[0].parent_intent_id, &"plan_006")
	assert_true(p.validate_invariants()["ok"])
```

- [ ] **Step 2: Run tests — expect parse error**

```bash
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```
Expected: ERROR on missing action_plan.gd.

- [ ] **Step 3: Implement `action_plan.gd`**

`godot/scripts/command/action_plan.gd`:
```gdscript
class_name ActionPlan
extends Resource

const TacticalOrder = preload("res://scripts/command/tactical_order.gd")

enum Tier { TACTICAL, STRATEGIC }

@export var id: StringName = &""
@export var deputy: StringName = &""
@export var tier: Tier = Tier.TACTICAL
@export var rationale: String = ""
@export var confidence: float = 1.0
@export var orders: Array[Resource] = []
@export var triggering_utterance: String = ""
@export var timestamp_ms: int = 0

func _expected_origin_for_tier() -> int:
	match tier:
		Tier.TACTICAL:
			return TacticalOrder.Origin.TACTICAL_VOICE
		Tier.STRATEGIC:
			return TacticalOrder.Origin.STRATEGIC_DECOMPOSITION
	return TacticalOrder.Origin.SCRIPT

func validate_invariants() -> Dictionary:
	var violations: Array[String] = []
	var expected_origin := _expected_origin_for_tier()
	for o in orders:
		if o.deputy != deputy:
			violations.append("order %s deputy=%s mismatches plan deputy=%s"
				% [String(o.id), String(o.deputy), String(deputy)])
		if o.origin != expected_origin:
			violations.append("order %s origin=%d does not match expected %d for tier"
				% [String(o.id), o.origin, expected_origin])
		if o.parent_intent_id != id:
			violations.append("order %s parent_intent_id=%s does not match plan id=%s"
				% [String(o.id), String(o.parent_intent_id), String(id)])
	return {"ok": violations.is_empty(), "violations": violations}

func apply_invariants() -> void:
	# Auto-fix the trivial fields the LLM reliably forgets.
	# Does not auto-fix `deputy` mismatches — those are real schema violations.
	var expected_origin := _expected_origin_for_tier()
	for o in orders:
		if o.parent_intent_id == &"":
			o.parent_intent_id = id
		if o.origin != expected_origin and o.origin == TacticalOrder.Origin.SCRIPT:
			o.origin = expected_origin

func to_dict() -> Dictionary:
	var order_dicts: Array = []
	for o in orders:
		order_dicts.append(o.to_dict())
	return {
		"id": String(id),
		"deputy": String(deputy),
		"tier": int(tier),
		"rationale": rationale,
		"confidence": confidence,
		"orders": order_dicts,
		"triggering_utterance": triggering_utterance,
		"timestamp_ms": timestamp_ms,
	}

static func from_dict(d: Dictionary) -> ActionPlan:
	var p := ActionPlan.new()
	p.id = StringName(d.get("id", ""))
	p.deputy = StringName(d.get("deputy", ""))
	p.tier = int(d.get("tier", Tier.TACTICAL))
	p.rationale = String(d.get("rationale", ""))
	p.confidence = float(d.get("confidence", 1.0))
	p.triggering_utterance = String(d.get("triggering_utterance", ""))
	p.timestamp_ms = int(d.get("timestamp_ms", 0))
	var raw_orders: Array = d.get("orders", [])
	var typed: Array[Resource] = []
	for od in raw_orders:
		typed.append(TacticalOrder.from_dict(od))
	p.orders = typed
	return p
```

- [ ] **Step 4: Run tests — expect 26 + 6 = 32 green**

```bash
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```
Expected: `Passing Tests 32`.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/command/action_plan.gd godot/tests/test_action_plan.gd && git commit -m "feat(godot): add ActionPlan Resource with invariant validation

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 3: `OrderTypeRegistry` autoload

**Files:**
- Create: `godot/scripts/command/order_type_registry.gd`
- Create: `godot/tests/test_order_type_registry.gd`
- Modify: `godot/project.godot` (added in Task 8)

- [ ] **Step 1: Write the failing test**

`godot/tests/test_order_type_registry.gd`:
```gdscript
extends "res://addons/gut/test.gd"

const RegistryScript = preload("res://scripts/command/order_type_registry.gd")

func _make_registry() -> Node:
	var r = RegistryScript.new()
	add_child_autofree(r)
	return r

func _make_def(id: StringName, schema: Dictionary, deputies: Array[StringName] = []) -> RegistryScript.TypeDef:
	var d = RegistryScript.TypeDef.new()
	d.id = id
	d.description = "test"
	d.param_schema = schema
	d.allowed_deputies = deputies
	return d

func test_register_then_get_def_returns_match():
	var r = _make_registry()
	var def = _make_def(&"move", {"speed_mult": "float"})
	r.register(def)
	assert_eq(r.get_def(&"move"), def)

func test_get_def_returns_null_for_unknown():
	var r = _make_registry()
	assert_null(r.get_def(&"nope"))

func test_validate_params_ok_with_correct_keys():
	var r = _make_registry()
	r.register(_make_def(&"use_skill", {"skill_id": "string", "charges": "int"}))
	var result = r.validate_params(&"use_skill", {"skill_id": "fireball", "charges": 1})
	assert_true(result["ok"])
	assert_eq(result["missing"], [])
	assert_eq(result["extra"], [])

func test_validate_params_reports_missing():
	var r = _make_registry()
	r.register(_make_def(&"use_skill", {"skill_id": "string"}))
	var result = r.validate_params(&"use_skill", {})
	assert_false(result["ok"])
	assert_eq(result["missing"], ["skill_id"])

func test_validate_params_reports_extra():
	var r = _make_registry()
	r.register(_make_def(&"move", {}))
	var result = r.validate_params(&"move", {"unwanted": 5})
	assert_false(result["ok"])
	assert_eq(result["extra"], ["unwanted"])

func test_validate_params_unknown_type_returns_error():
	var r = _make_registry()
	var result = r.validate_params(&"ghost", {})
	assert_false(result["ok"])
	assert_string_contains(result["error"], "unknown_type_id")

func test_list_for_deputy_filters_by_allowed_deputies():
	var r = _make_registry()
	r.register(_make_def(&"move", {}))                                  # any deputy
	r.register(_make_def(&"build", {}, [&"deputy"] as Array[StringName]))
	r.register(_make_def(&"melee_only", {}, [&"captain_combat"] as Array[StringName]))
	var got = r.list_for_deputy(&"deputy")
	assert_true(got.has(&"move"))
	assert_true(got.has(&"build"))
	assert_false(got.has(&"melee_only"))
```

- [ ] **Step 2: Run tests — expect parse error**

```bash
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```
Expected: ERROR on missing order_type_registry.gd.

- [ ] **Step 3: Implement**

`godot/scripts/command/order_type_registry.gd`:
```gdscript
class_name OrderTypeRegistry
extends Node

class TypeDef:
	extends RefCounted
	var id: StringName = &""
	var description: String = ""
	var param_schema: Dictionary = {}     # {key: type_string, ...}
	var allowed_deputies: Array[StringName] = []
	var min_targets: int = 1
	var max_targets: int = -1

var _defs: Dictionary = {}    # StringName -> TypeDef

func register(type_def: TypeDef) -> void:
	if type_def == null or type_def.id == &"":
		push_error("OrderTypeRegistry.register: missing id")
		return
	_defs[type_def.id] = type_def

func get_def(id: StringName):
	return _defs.get(id, null)

func validate_params(id: StringName, params: Dictionary) -> Dictionary:
	var def = get_def(id)
	if def == null:
		return {"ok": false, "error": "unknown_type_id", "missing": [], "extra": []}
	var missing: Array[String] = []
	var extra: Array[String] = []
	for required_key in def.param_schema.keys():
		if not params.has(required_key):
			missing.append(String(required_key))
	for got_key in params.keys():
		if not def.param_schema.has(got_key):
			extra.append(String(got_key))
	return {"ok": missing.is_empty() and extra.is_empty(),
	        "missing": missing,
	        "extra": extra}

func list_for_deputy(deputy: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for type_id in _defs.keys():
		var def: TypeDef = _defs[type_id]
		if def.allowed_deputies.is_empty() or def.allowed_deputies.has(deputy):
			out.append(type_id)
	return out

func clear() -> void:
	_defs.clear()
```

- [ ] **Step 4: Run tests — expect 32 + 7 = 39 green**

```bash
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```
Expected: `Passing Tests 39`.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/command/order_type_registry.gd godot/tests/test_order_type_registry.gd && git commit -m "feat(godot): add OrderTypeRegistry for extensible order types

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 4: `ControlPolicy` interface + four impls

**Files:**
- Create: `godot/scripts/command/control_policy.gd`
- Create: `godot/tests/test_control_policy.gd`

- [ ] **Step 1: Write the failing test**

`godot/tests/test_control_policy.gd`:
```gdscript
extends "res://addons/gut/test.gd"

const ControlPolicyScript = preload("res://scripts/command/control_policy.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

func test_full_control_accepts_everything():
	var p = ControlPolicyScript.FullControlPolicy.new()
	assert_true(p.can_issue(TacticalOrderScript.Issuer.PLAYER, &"deputy", &"move"))
	assert_true(p.can_issue(TacticalOrderScript.Issuer.DEPUTY, &"deputy", &"attack"))

func test_hero_only_accepts_only_player_with_empty_deputy():
	var p = ControlPolicyScript.HeroOnlyPolicy.new()
	assert_true(p.can_issue(TacticalOrderScript.Issuer.PLAYER, &"", &"move"))
	assert_false(p.can_issue(TacticalOrderScript.Issuer.PLAYER, &"deputy", &"move"))
	assert_false(p.can_issue(TacticalOrderScript.Issuer.DEPUTY, &"", &"attack"))

func test_assist_mode_accepts_player_and_logs_deputy_as_suggestion():
	var p = ControlPolicyScript.AssistModePolicy.new()
	assert_true(p.can_issue(TacticalOrderScript.Issuer.PLAYER, &"", &"move"))
	# Deputy plans are still rejected at can_issue level — `assist` semantics in the
	# bus simply log them; the policy says no.
	assert_false(p.can_issue(TacticalOrderScript.Issuer.DEPUTY, &"deputy", &"attack"))

func test_archon_rejects_llm_deputy_for_attached_seat():
	var p = ControlPolicyScript.ArchonControlPolicy.new(&"deputy")
	# Human archon as PLAYER on attached seat = OK
	assert_true(p.can_issue(TacticalOrderScript.Issuer.PLAYER, &"deputy", &"move"))
	# LLM deputy on the attached seat = blocked
	assert_false(p.can_issue(TacticalOrderScript.Issuer.DEPUTY, &"deputy", &"move"))
	# LLM deputy on an unattached seat (e.g. captain) = OK
	assert_true(p.can_issue(TacticalOrderScript.Issuer.DEPUTY, &"deputy_other", &"move"))

func test_archon_with_empty_attached_seat_behaves_like_full_control():
	var p = ControlPolicyScript.ArchonControlPolicy.new(&"")
	assert_true(p.can_issue(TacticalOrderScript.Issuer.DEPUTY, &"deputy", &"move"))
```

- [ ] **Step 2: Run tests — expect parse error**

```bash
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```
Expected: ERROR on missing control_policy.gd.

- [ ] **Step 3: Implement**

`godot/scripts/command/control_policy.gd`:
```gdscript
class_name ControlPolicy
extends RefCounted

const TacticalOrder = preload("res://scripts/command/tactical_order.gd")

func can_issue(issuer: int, deputy: StringName, type_id: StringName) -> bool:
	push_error("ControlPolicy.can_issue is abstract")
	return false

# --- Concrete implementations as inner classes for grouped distribution ---

class FullControlPolicy:
	extends ControlPolicy

	func can_issue(_issuer: int, _deputy: StringName, _type_id: StringName) -> bool:
		return true

class HeroOnlyPolicy:
	extends ControlPolicy

	func can_issue(issuer: int, deputy: StringName, _type_id: StringName) -> bool:
		# Player issuing without a deputy seat is the hero direct case.
		return issuer == TacticalOrder.Issuer.PLAYER and deputy == &""

class AssistModePolicy:
	extends ControlPolicy

	func can_issue(issuer: int, _deputy: StringName, _type_id: StringName) -> bool:
		return issuer == TacticalOrder.Issuer.PLAYER

class ArchonControlPolicy:
	extends ControlPolicy

	var attached_seat: StringName

	func _init(seat: StringName = &"") -> void:
		attached_seat = seat

	func can_issue(issuer: int, deputy: StringName, _type_id: StringName) -> bool:
		if attached_seat == &"":
			return true
		# Block AI deputy plans for the attached seat
		if deputy == attached_seat and issuer != TacticalOrder.Issuer.PLAYER:
			return false
		return true
```

- [ ] **Step 4: Run tests — expect 39 + 5 = 44 green**

```bash
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```
Expected: `Passing Tests 44`.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/command/control_policy.gd godot/tests/test_control_policy.gd && git commit -m "feat(godot): add ControlPolicy with Full/HeroOnly/Assist/Archon impls

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 5: `CommandBus` autoload

**Files:**
- Create: `godot/scripts/command/command_bus.gd`
- Create: `godot/tests/test_command_bus.gd`

- [ ] **Step 1: Write the failing test**

`godot/tests/test_command_bus.gd`:
```gdscript
extends "res://addons/gut/test.gd"

const CommandBusScript = preload("res://scripts/command/command_bus.gd")
const RegistryScript = preload("res://scripts/command/order_type_registry.gd")
const ControlPolicyScript = preload("res://scripts/command/control_policy.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")
const ActionPlanScript = preload("res://scripts/command/action_plan.gd")

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
	add_child_autofree(registry)
	add_child_autofree(bus)
	# Disable file persistence in tests
	bus.persistence_enabled = false
	return bus

func _make_order(id: StringName) -> Resource:
	var o = TacticalOrderScript.new()
	o.id = id
	o.type_id = &"move"
	o.origin = TacticalOrderScript.Origin.SCRIPT
	o.issuer = TacticalOrderScript.Issuer.PLAYER
	o.target_position = Vector3(1, 0, 1)
	return o

func test_submit_orders_accepts_valid_order_emits_signal():
	var bus = _make_bus()
	watch_signals(bus)
	var result = bus.submit_orders([_make_order(&"ord_1")])
	assert_eq(result["accepted"].size(), 1)
	assert_eq(result["rejected"].size(), 0)
	assert_signal_emit_count(bus, "order_issued", 1)

func test_submit_orders_rejects_unknown_type_id():
	var bus = _make_bus()
	var o = _make_order(&"ord_2")
	o.type_id = &"ghost"
	var result = bus.submit_orders([o])
	assert_eq(result["accepted"].size(), 0)
	assert_eq(result["rejected"].size(), 1)
	assert_eq(result["rejected"][0]["reason"], &"unknown_type_id")

func test_submit_orders_rejects_untargeted_when_min_targets_required():
	var bus = _make_bus()
	var o = TacticalOrderScript.new()
	o.id = &"ord_3"
	o.type_id = &"move"
	o.origin = TacticalOrderScript.Origin.SCRIPT
	# no targeting fields set
	var result = bus.submit_orders([o])
	assert_eq(result["rejected"].size(), 1)
	assert_eq(result["rejected"][0]["reason"], &"target_required")

func test_submit_orders_rejects_duplicate_id():
	var bus = _make_bus()
	bus.submit_orders([_make_order(&"ord_4")])
	var result = bus.submit_orders([_make_order(&"ord_4")])
	assert_eq(result["rejected"].size(), 1)
	assert_eq(result["rejected"][0]["reason"], &"duplicate_id")

func test_submit_orders_rejects_when_status_not_pending():
	var bus = _make_bus()
	var o = _make_order(&"ord_5")
	o.status = &"executing"
	var result = bus.submit_orders([o])
	assert_eq(result["rejected"][0]["reason"], &"non_pending_status")

func test_submit_orders_rejects_when_policy_denies():
	var bus = _make_bus()
	bus.set_policy(ControlPolicyScript.HeroOnlyPolicy.new())
	var o = _make_order(&"ord_6")
	o.deputy = &"deputy"
	var result = bus.submit_orders([o])
	assert_eq(result["rejected"][0]["reason"], &"control_policy_denied")

func test_submit_plan_validates_invariants_then_dispatches():
	var bus = _make_bus()
	watch_signals(bus)
	var p = ActionPlanScript.new()
	p.id = &"plan_1"
	p.deputy = &"deputy"
	p.tier = ActionPlanScript.Tier.TACTICAL
	var o = _make_order(&"ord_7")
	o.deputy = &"deputy"
	o.origin = TacticalOrderScript.Origin.TACTICAL_VOICE
	o.issuer = TacticalOrderScript.Issuer.DEPUTY
	p.orders = [o]
	p.apply_invariants()
	var result = bus.submit_plan(p)
	assert_eq(result["accepted"].size(), 1)
	assert_signal_emit_count(bus, "plan_issued", 1)
	assert_signal_emit_count(bus, "order_issued", 1)

func test_submit_plan_rejects_when_invariants_violated():
	var bus = _make_bus()
	var p = ActionPlanScript.new()
	p.id = &"plan_2"
	p.deputy = &"deputy"
	p.tier = ActionPlanScript.Tier.TACTICAL
	var o = _make_order(&"ord_8")
	o.deputy = &"someone_else"  # mismatch
	p.orders = [o]
	var result = bus.submit_plan(p)
	assert_eq(result["accepted"].size(), 0)
	assert_eq(result["plan_rejected"], true)

func test_recent_buffers_preserve_order_and_truncate():
	var bus = _make_bus()
	for i in 5:
		bus.submit_orders([_make_order(StringName("ord_b%d" % i))])
	var got = bus.get_recent_orders(3)
	assert_eq(got.size(), 3)
	# Most recent first
	assert_eq(got[0].id, &"ord_b4")
	assert_eq(got[2].id, &"ord_b2")
```

- [ ] **Step 2: Run tests — expect parse error**

```bash
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```
Expected: ERROR on missing command_bus.gd.

- [ ] **Step 3: Implement**

`godot/scripts/command/command_bus.gd`:
```gdscript
class_name CommandBus
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
```

- [ ] **Step 4: Run tests — expect 44 + 9 = 53 green**

```bash
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```
Expected: `Passing Tests 53`.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/command/command_bus.gd godot/tests/test_command_bus.gd && git commit -m "feat(godot): add CommandBus with validation, signals, and ndjson persistence

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 6: `PrePlan` and `PrePlanTrigger` Resources

**Files:**
- Create: `godot/scripts/command/pre_plan.gd`
- Create: `godot/tests/test_pre_plan.gd`

- [ ] **Step 1: Write the failing test**

`godot/tests/test_pre_plan.gd`:
```gdscript
extends "res://addons/gut/test.gd"

const PrePlanScript = preload("res://scripts/command/pre_plan.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

func test_trigger_match_with_no_conditions_passes():
	var t = PrePlanScript.PrePlanTrigger.new()
	t.event = &"match_start"
	assert_true(t.matches({"event": &"match_start"}))

func test_trigger_within_seconds_of_start_pass():
	var t = PrePlanScript.PrePlanTrigger.new()
	t.event = &"match_start"
	t.conditions = {"within_seconds_of_start": 60}
	assert_true(t.matches({"event": &"match_start", "elapsed_s": 30}))
	assert_false(t.matches({"event": &"match_start", "elapsed_s": 61}))

func test_trigger_event_mismatch_fails():
	var t = PrePlanScript.PrePlanTrigger.new()
	t.event = &"match_start"
	assert_false(t.matches({"event": &"unit_died"}))

func test_trigger_enemy_count_at_least_pass():
	var t = PrePlanScript.PrePlanTrigger.new()
	t.event = &"sighting"
	t.conditions = {"enemy_count_at_least": 3}
	assert_true(t.matches({"event": &"sighting", "enemy_count": 4}))
	assert_false(t.matches({"event": &"sighting", "enemy_count": 2}))

func test_trigger_unknown_condition_is_ignored():
	var t = PrePlanScript.PrePlanTrigger.new()
	t.event = &"match_start"
	t.conditions = {"made_up_key": "value"}
	# Unknown keys are ignored (forward-compat); event match alone passes.
	assert_true(t.matches({"event": &"match_start"}))

func test_pre_plan_has_default_enabled_true():
	var p = PrePlanScript.PrePlan.new()
	assert_true(p.enabled)
```

- [ ] **Step 2: Run tests — expect parse error**

```bash
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```
Expected: ERROR on missing pre_plan.gd.

- [ ] **Step 3: Implement**

`godot/scripts/command/pre_plan.gd`:
```gdscript
extends Node    # parsing-only host; the real classes are below

class PrePlanTrigger:
	extends Resource

	@export var event: StringName = &""
	@export var conditions: Dictionary = {}

	func matches(payload: Dictionary) -> bool:
		if payload.get("event", &"") != event:
			return false
		# Whitelisted condition keys; unknown keys are ignored for forward-compat.
		if conditions.has("within_seconds_of_start"):
			var max_s: float = float(conditions["within_seconds_of_start"])
			if float(payload.get("elapsed_s", 0)) > max_s:
				return false
		if conditions.has("enemy_count_at_least"):
			var min_n: int = int(conditions["enemy_count_at_least"])
			if int(payload.get("enemy_count", 0)) < min_n:
				return false
		if conditions.has("player_resource_below"):
			var below: Dictionary = conditions["player_resource_below"]
			var have: Dictionary = payload.get("resources", {})
			for k in below.keys():
				if int(have.get(k, 0)) >= int(below[k]):
					return false
		return true

class PrePlan:
	extends Resource

	@export var name: String = ""
	@export var deputy: StringName = &""
	@export var trigger: Resource          # PrePlanTrigger
	@export var orders: Array[Resource] = []   # TacticalOrders, all origin = PRE_PLAN
	@export var enabled: bool = true
	@export var repeat: bool = false
	@export var cooldown_seconds: float = 0.0

	var last_fired_ms: int = 0
```

> Note: GDScript inner classes inside an `extends Node` host parse cleanly and
> `preload(...).PrePlanTrigger.new()` works. The host does not need to be
> instantiated.

- [ ] **Step 4: Run tests — expect 53 + 6 = 59 green**

```bash
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```
Expected: `Passing Tests 59`.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/command/pre_plan.gd godot/tests/test_pre_plan.gd && git commit -m "feat(godot): add PrePlan and PrePlanTrigger Resources with condition DSL

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 7: `PrePlanRunner` Node + sample `.tres`

**Files:**
- Create: `godot/scripts/command/pre_plan_runner.gd`
- Create: `godot/data/preplans/sample_match_start.tres`
- Create: `godot/tests/test_pre_plan_runner.gd`

- [ ] **Step 1: Write the failing test**

`godot/tests/test_pre_plan_runner.gd`:
```gdscript
extends "res://addons/gut/test.gd"

const PrePlanRunnerScript = preload("res://scripts/command/pre_plan_runner.gd")
const PrePlanScript = preload("res://scripts/command/pre_plan.gd")
const CommandBusScript = preload("res://scripts/command/command_bus.gd")
const RegistryScript = preload("res://scripts/command/order_type_registry.gd")
const ControlPolicyScript = preload("res://scripts/command/control_policy.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

func _make_bus() -> Node:
	var registry = RegistryScript.new()
	var def = RegistryScript.TypeDef.new()
	def.id = &"move"
	registry.register(def)
	add_child_autofree(registry)
	var bus = CommandBusScript.new()
	bus.set_registry(registry)
	bus.set_policy(ControlPolicyScript.FullControlPolicy.new())
	bus.persistence_enabled = false
	add_child_autofree(bus)
	return bus

func _make_runner(bus: Node) -> Node:
	var r = PrePlanRunnerScript.new()
	r.set_command_bus(bus)
	add_child_autofree(r)
	return r

func _make_plan_with_event(event: StringName) -> Resource:
	var trigger = PrePlanScript.PrePlanTrigger.new()
	trigger.event = event
	var p = PrePlanScript.PrePlan.new()
	p.name = "test_plan"
	p.deputy = &"deputy"
	p.trigger = trigger
	var o = TacticalOrderScript.new()
	o.id = &"ord_pp_1"
	o.type_id = &"move"
	o.origin = TacticalOrderScript.Origin.PRE_PLAN
	o.issuer = TacticalOrderScript.Issuer.PLAYER
	o.target_position = Vector3(7, 0, 7)
	p.orders = [o]
	return p

func test_notify_event_fires_matching_plan():
	var bus = _make_bus()
	var runner = _make_runner(bus)
	runner.add_plan(_make_plan_with_event(&"match_start"))
	runner.notify_event(&"match_start", {})
	assert_eq(bus.get_recent_orders().size(), 1)

func test_notify_event_skips_non_matching():
	var bus = _make_bus()
	var runner = _make_runner(bus)
	runner.add_plan(_make_plan_with_event(&"match_start"))
	runner.notify_event(&"unit_died", {})
	assert_eq(bus.get_recent_orders().size(), 0)

func test_one_shot_plan_disables_after_first_fire():
	var bus = _make_bus()
	var runner = _make_runner(bus)
	var plan = _make_plan_with_event(&"match_start")
	runner.add_plan(plan)
	runner.notify_event(&"match_start", {})
	# Reset the order id so the second fire wouldn't be deduped at bus level
	plan.orders[0].id = &"ord_pp_2"
	runner.notify_event(&"match_start", {})
	assert_eq(bus.get_recent_orders().size(), 1)
	assert_false(plan.enabled)

func test_repeat_plan_respects_cooldown():
	var bus = _make_bus()
	var runner = _make_runner(bus)
	var plan = _make_plan_with_event(&"sighting")
	plan.repeat = true
	plan.cooldown_seconds = 60.0
	runner.add_plan(plan)
	runner.notify_event(&"sighting", {})
	# Same tick — should NOT fire again
	plan.orders[0].id = &"ord_pp_3"
	runner.notify_event(&"sighting", {})
	assert_eq(bus.get_recent_orders().size(), 1)
	# Simulate cooldown passing
	plan.last_fired_ms -= 70 * 1000
	plan.orders[0].id = &"ord_pp_4"
	runner.notify_event(&"sighting", {})
	assert_eq(bus.get_recent_orders().size(), 2)

func test_disabled_plan_never_fires():
	var bus = _make_bus()
	var runner = _make_runner(bus)
	var plan = _make_plan_with_event(&"match_start")
	plan.enabled = false
	runner.add_plan(plan)
	runner.notify_event(&"match_start", {})
	assert_eq(bus.get_recent_orders().size(), 0)
```

- [ ] **Step 2: Run tests — expect parse error**

```bash
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```
Expected: ERROR on missing pre_plan_runner.gd.

- [ ] **Step 3: Implement**

`godot/scripts/command/pre_plan_runner.gd`:
```gdscript
class_name PrePlanRunner
extends Node

const PrePlan = preload("res://scripts/command/pre_plan.gd")

var _bus: Node = null
var _plans: Array[Resource] = []

func set_command_bus(bus: Node) -> void:
	_bus = bus

func add_plan(plan: Resource) -> void:
	_plans.append(plan)

func load_from_directory(dir_path: String) -> int:
	var d = DirAccess.open(dir_path)
	if d == null:
		push_warning("PrePlanRunner: cannot open dir %s" % dir_path)
		return 0
	var loaded = 0
	d.list_dir_begin()
	var entry = d.get_next()
	while entry != "":
		if entry.ends_with(".tres"):
			var full = "%s/%s" % [dir_path, entry]
			var res = load(full)
			if res != null:
				add_plan(res)
				loaded += 1
		entry = d.get_next()
	d.list_dir_end()
	print("[RTSMVP] PrePlanRunner loaded %d preplans from %s" % [loaded, dir_path])
	return loaded

func notify_event(event_name: StringName, payload: Dictionary) -> void:
	if _bus == null:
		return
	var augmented = payload.duplicate()
	augmented["event"] = event_name
	for plan in _plans:
		if not plan.enabled:
			continue
		if plan.trigger == null:
			continue
		if not plan.trigger.matches(augmented):
			continue
		var now_ms = Time.get_ticks_msec()
		if plan.repeat:
			if plan.last_fired_ms != 0:
				var since = now_ms - plan.last_fired_ms
				if since < int(plan.cooldown_seconds * 1000):
					continue
		_bus.submit_orders(plan.orders)
		plan.last_fired_ms = now_ms
		if not plan.repeat:
			plan.enabled = false
```

- [ ] **Step 4: Run tests — expect 59 + 5 = 64 green**

```bash
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```
Expected: `Passing Tests 64`.

- [ ] **Step 5: Create the sample preplan resource**

```bash
mkdir -p "D:/War Buddy/godot/data/preplans"
```

`godot/data/preplans/sample_match_start.tres`:
```
[gd_resource type="Resource" load_steps=4 format=3 uid="uid://samplepreplan"]

[ext_resource type="Script" path="res://scripts/command/pre_plan.gd" id="1_pp"]

[sub_resource type="Resource" id="trigger"]
script = ExtResource("1_pp")
event = &"match_start"
conditions = {}

[sub_resource type="Resource" id="order_1"]
script = ExtResource("1_pp")

[resource]
script = ExtResource("1_pp")
name = "Sample: open with reconnaissance"
deputy = &"deputy"
trigger = SubResource("trigger")
orders = []
enabled = true
repeat = false
cooldown_seconds = 0.0
```

> The orders list is empty in the sample to keep it dependency-free at v1; the
> intent is just "fires on match_start, gets logged in the bus's plans buffer".
> Real orders need authoring tooling (doc 10) which lands later.

- [ ] **Step 6: Commit**

```bash
git add godot/scripts/command/pre_plan_runner.gd godot/data/preplans/sample_match_start.tres godot/tests/test_pre_plan_runner.gd && git commit -m "feat(godot): add PrePlanRunner with notify_event API and sample preplan

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 8: Bootstrap wiring + project.godot autoloads

**Files:**
- Modify: `godot/project.godot`
- Modify: `godot/scripts/bootstrap.gd`

- [ ] **Step 1: Register autoloads in `project.godot`**

Add a new `[autoload]` section. Edit `godot/project.godot`. Locate the line that
starts `[input]` and insert ABOVE it:

```
[autoload]

OrderTypeRegistry="*res://scripts/command/order_type_registry.gd"
CommandBus="*res://scripts/command/command_bus.gd"

```

The `*` prefix tells Godot to instantiate the script as a Node singleton. The
ordering matters: `OrderTypeRegistry` first because `CommandBus._ready` must be
able to find it.

- [ ] **Step 2: Wire bootstrap to register types and instantiate runner**

In `godot/scripts/bootstrap.gd`, add a new preload near the top alongside the
existing ones:

```gdscript
const PrePlanRunnerScript = preload("res://scripts/command/pre_plan_runner.gd")
const RegistryScript = preload("res://scripts/command/order_type_registry.gd")
```

Add a member field:

```gdscript
var pre_plan_runner = null
```

At the top of `_ready()`, before any other setup, add:

```gdscript
	_register_core_order_types()
	CommandBus.set_registry(OrderTypeRegistry)
	CommandBus.match_id = "match_%d" % Time.get_unix_time_from_system()
```

Append at the end of `_ready()` (after the dev squad controller block):

```gdscript

	pre_plan_runner = PrePlanRunnerScript.new()
	pre_plan_runner.name = "PrePlanRunner"
	pre_plan_runner.set_command_bus(CommandBus)
	add_child(pre_plan_runner)
	pre_plan_runner.load_from_directory("res://data/preplans")
	pre_plan_runner.notify_event(&"match_start", {"elapsed_s": 0})
	print("[RTSMVP] PrePlanRunner: notified match_start")
```

Add the helper method at the end of the file:

```gdscript
func _register_core_order_types() -> void:
	var defs = [
		_make_def(&"move", {}, [], 1),
		_make_def(&"attack", {}, [], 1),
		_make_def(&"stop", {}, [], 0),
		_make_def(&"hold", {}, [], 0),
		_make_def(&"use_skill", {"skill_id": "string"}, [], 0),
	]
	for d in defs:
		OrderTypeRegistry.register(d)
	print("[RTSMVP] OrderTypeRegistry: registered %d core types" % defs.size())

func _make_def(id: StringName, schema: Dictionary, deputies: Array, min_targets: int):
	var d = RegistryScript.TypeDef.new()
	d.id = id
	d.description = "core"
	d.param_schema = schema
	var typed_deps: Array[StringName] = []
	for dep in deputies:
		typed_deps.append(dep)
	d.allowed_deputies = typed_deps
	d.min_targets = min_targets
	return d
```

- [ ] **Step 3: Run headless boot — expect bootstrap lines + no errors**

```bash
godot --headless --path godot --quit-after 5 2>&1 | tail -10
```
Expected output includes (order may vary):
```
[RTSMVP] OrderTypeRegistry: registered 5 core types
[RTSMVP] Bootstrap: hero=CommanderHero hud=HudRoot buildings=3
[RTSMVP] Bootstrap: dev squad controller active (debug build)
[RTSMVP] PrePlanRunner loaded 1 preplans from res://data/preplans
[RTSMVP] PrePlanRunner: notified match_start
```
No SCRIPT ERROR lines.

- [ ] **Step 4: Run all GUT tests**

```bash
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -8
```
Expected: `Passing Tests 64`, all green.

- [ ] **Step 5: Inspect the order log**

```bash
ls -la "$APPDATA/Godot/app_userdata/War of Agents RTS MVP/order_log/" 2>/dev/null || ls -la ~/.local/share/godot/app_userdata/"War of Agents RTS MVP"/order_log/ 2>/dev/null
```
Expected: a `.plans.ndjson` file appears (the sample plan was logged). Empty
`.ndjson` is fine (sample preplan ships with no orders).

- [ ] **Step 6: Commit**

```bash
git add godot/project.godot godot/scripts/bootstrap.gd && git commit -m "feat(godot): wire CommandBus autoloads + PrePlanRunner into bootstrap

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 9: Smoke checklist + CHANGELOG + tag v0.3.0

**Files:**
- Modify: `docs/specs/05-godot-smoke-test-checklist.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Append "Command system" section to `05-godot-smoke-test-checklist.md`**

After the existing "Squad puppets (debug build only)" section, append:

```markdown

## Command system (any build)

Run from any build (release or debug). Verify the bus + registry skeleton.

- [ ] Headless boot prints `[RTSMVP] OrderTypeRegistry: registered 5 core types`
- [ ] Headless boot prints `[RTSMVP] PrePlanRunner loaded N preplans from res://data/preplans` where N >= 1
- [ ] Headless boot prints `[RTSMVP] PrePlanRunner: notified match_start`
- [ ] No SCRIPT ERROR / Parse Error lines in the boot output
- [ ] After a brief run, `user://order_log/<match_id>.plans.ndjson` exists with one JSON line for the sample preplan
- [ ] All 64 GUT tests pass
- [ ] Hero left-click and Squad dev-mode interactions still work (Phase C regression check)
```

- [ ] **Step 2: Append `[v0.3.0]` block to `CHANGELOG.md`**

Insert a new section above `## [v0.2.0]`:

```markdown
## [v0.3.0] — 2026-04-27

### Added
- **Command-system skeleton** — first concrete implementation of the keystone artifacts in `docs/specs/07-command-system.md`. Skeleton ships even though there is no executor for the orders yet; doc 09 will land that.
- **`TacticalOrder` Resource** — universal order data class with `to_dict / from_dict` for LLM JSON round-trip; provenance fields (`origin`, `issuer`, `parent_intent_id`, `confidence`, `rationale`) included from day one.
- **`ActionPlan` Resource** — wraps the LLM-emitted plan-level rationale + confidence + orders[] with auto-fix and validate-invariants helpers so deputies never silently emit malformed plans.
- **`OrderTypeRegistry` autoload** — extension point for future entity / economy specs (doc 09) to register order types (`move`, `attack`, `gather`, `train`, etc.) without touching command-system internals.
- **`CommandBus` autoload** — single ingress with six-step validation (status / unique id / registered type / param shape / control policy / target presence), accepted/rejected split, ring buffers, and append-only ndjson persistence under `user://order_log/`.
- **`ControlPolicy` family** — `FullControl` (default), `HeroOnly`, `AssistMode`, `ArchonControl`. The fourth implements vision §2.5's archon mode by rejecting AI Deputy plans for whichever seat a human has taken.
- **`PrePlan` + `PrePlanTrigger` Resources** with a small condition DSL (`within_seconds_of_start`, `enemy_count_at_least`, `player_resource_below`).
- **`PrePlanRunner` Node** with `notify_event(name, payload)` API. Bootstrap fires `match_start` on boot.
- **Sample preplan** at `godot/data/preplans/sample_match_start.tres`.
- **Tests** — six new GUT files (`test_tactical_order`, `test_action_plan`, `test_order_type_registry`, `test_control_policy`, `test_command_bus`, `test_pre_plan`, `test_pre_plan_runner`) bring the total green count to 64.

### Notes
- Orders sit in `pending` forever in v0.3.0; that is intentional. Doc 09 (entities / combat / economy) will introduce executors that consume them via the `order_issued` signal.
- No LLM integration yet; that's doc 08's milestone (v0.4.0).
- v0.3.0 keeps the v0.2 dev-mode squad selection intact — both systems coexist on the bus side without conflicting.
```

- [ ] **Step 3: Run the full test pipeline once more**

```bash
godot --headless --path godot --quit-after 5 2>&1 | tail -8
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```
Expected: bootstrap clean, `Passing Tests 64`.

- [ ] **Step 4: Commit docs**

```bash
git add docs/specs/05-godot-smoke-test-checklist.md CHANGELOG.md && git commit -m "docs: v0.3.0 smoke section + changelog entry

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

- [ ] **Step 5: Tag and push**

```bash
git tag v0.3.0
git push origin main v0.3.0
```

Verify:
- `git log --oneline -10` shows the nine task commits.
- GitHub Actions `ci.yml` goes green.
- `release.yml` produces Linux / Windows / Web artifacts attached to a v0.3.0 release.

---

## Acceptance for v0.3.0

The milestone is "done" when **all** of:
1. Headless boot clean: prints all five `[RTSMVP] ...` lines, zero SCRIPT ERROR.
2. GUT: 64 / 64 passing.
3. Manual smoke from the new "Command system" checklist: every box checked.
4. v0.2.0 squad puppets continue to work (regression).
5. CI green; release.yml succeeds.

## Out of scope (do not introduce)

- Behavior trees / order execution (doc 09).
- LLM integration (doc 08 / next plan).
- War-room UI for pre-plan authoring (doc 10).
- Real `EventBus` autoload — the `notify_event` API is intentionally a stand-in
  and will be replaced when doc 09's `EventBus` lands.
- Voice input / TTS.
