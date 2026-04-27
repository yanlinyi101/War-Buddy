# 08 — AI Deputy Architecture Implementation Plan (v0.4.0 slice)

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the LLM-driven Deputy seat from `08-ai-deputy-architecture.md` — `DeputyLLMClient` interface + `MockClient` (for tests/replay) + `AnthropicClient` (real LLM) + `Deputy` Node + `ClassifierRouter` + `BattlefieldSnapshotBuilder` + `DeputyMemory` / `MemoryStore` + `DeputyPersona` + HUD speech bubble. Skip Captain and Archon — those follow as a v0.5.0 plan.

**Architecture:** New module group under `godot/scripts/ai/`. One new autoload (`MemoryStore`). Anthropic integration via Godot's built-in `HTTPRequest` and the Messages API tool-use endpoint. CI / no-key environments fall back to `MockClient` automatically. Snapshot builder stubs against scene-tree groups today; will switch to `GameState` autoload when doc 09 lands.

**Tech Stack:** Godot 4.6.x, GDScript only, Anthropic Messages API (`https://api.anthropic.com/v1/messages`), GUT 9.6.0, ANTHROPIC_API_KEY env var.

---

## File Structure

### New files

| Path | Responsibility |
|---|---|
| `godot/scripts/ai/deputy_llm_client.gd` | Abstract `DeputyLLMClient` + `SubmitPlanRequest` / `SubmitPlanResponse` data classes. |
| `godot/scripts/ai/mock_client.gd` | `MockClient` that returns canned plans by utterance keyword — drives all tests + serves as fallback when no API key. |
| `godot/scripts/ai/anthropic_client.gd` | Real Anthropic Messages-API client with single-tool `submit_plan` schema, async `await`. |
| `godot/scripts/ai/deputy_persona.gd` | `DeputyPersona` Resource — name, archetype, voice style, system-prompt template, traits, quirks. |
| `godot/scripts/ai/deputy_memory.gd` | `DeputyMemory` Resource — total_matches, wins, losses, traits, anecdotes. |
| `godot/scripts/ai/memory_store.gd` | Autoload — load/save/snapshot DeputyMemory under `user://deputies/`. |
| `godot/scripts/ai/battlefield_snapshot_builder.gd` | Builds the cropped Dictionary observation. v1 stub queries scene-tree groups; doc 09 swaps to `GameState`. |
| `godot/scripts/ai/deputy.gd` | `Deputy` Node — handle_plan, speak, persona binding, short-term memory. Off-field per vision §2.3. |
| `godot/scripts/ai/classifier_router.gd` | Single front door — `handle_utterance` invokes the LLM client, routes plan to Deputy. |
| `godot/data/personas/deputy_veteran.tres` | Sample persona shipped with the build. |
| `godot/scripts/hud/message_bubble_hud.gd` | Listens for `Deputy.spoke`, renders a transient bubble. |
| `godot/tests/test_mock_client.gd` | GUT cases for `MockClient`. |
| `godot/tests/test_deputy.gd` | GUT cases for `Deputy.handle_plan` validation, persona-allowed filter, speak signal. |
| `godot/tests/test_classifier_router.gd` | End-to-end: utterance → MockClient → ActionPlan → CommandBus. |
| `godot/tests/test_deputy_memory.gd` | Resource I/O, missing-file fallback, snapshot_for shape. |
| `godot/tests/test_battlefield_snapshot_builder.gd` | Group-query stub, dict shape, tier crop. |

### Modified files

| Path | What changes |
|---|---|
| `godot/project.godot` | Register `MemoryStore` autoload. |
| `godot/scripts/bootstrap.gd` | Instantiate Deputy + ClassifierRouter; bind to HUD; hook end-of-match consolidation. |
| `godot/scripts/hud_root.gd` | New signal route: `command_submitted` → `ClassifierRouter.handle_utterance`; expose `MessageBubbleHud` reference. |
| `godot/scenes/main.tscn` | Add `MessageBubbleHud` Control under `HudRoot`. |
| `docs/specs/05-godot-smoke-test-checklist.md` | Append "AI Deputy" section. |
| `CHANGELOG.md` | `[v0.4.0]` entry. |

---

## Task 1: `DeputyLLMClient` interface + request/response data classes

**Files:**
- Create: `godot/scripts/ai/deputy_llm_client.gd`
- Create: `godot/tests/test_mock_client.gd` (placeholder file referenced in T2 — created here only for compilation)

The interface file holds three public types: the abstract client base, plus
`SubmitPlanRequest` and `SubmitPlanResponse` as inner classes (kept together because
they only have meaning relative to each other). The interface doesn't have its own
test — `MockClient` (T2) exercises it.

- [ ] **Step 1: Create the directory**

```bash
mkdir -p "D:/War Buddy/godot/scripts/ai"
```

- [ ] **Step 2: Implement the interface file**

`godot/scripts/ai/deputy_llm_client.gd`:
```gdscript
class_name DeputyLLMClient
extends RefCounted

# All concrete implementations are async via Godot's `await`. The base method
# below is synchronous because GDScript can't declare an abstract `async` method;
# subclasses redeclare with `await` in their bodies.
func submit_plan(_req: SubmitPlanRequest) -> SubmitPlanResponse:
	push_error("DeputyLLMClient.submit_plan is abstract")
	return null

class SubmitPlanRequest:
	extends RefCounted
	var persona: Resource = null              # DeputyPersona (typed loosely to dodge cyclic preload)
	var memory_snapshot: Dictionary = {}
	var observation: Dictionary = {}
	var utterance: String = ""
	var tier_hint: StringName = &""           # &"" | &"tactical" | &"strategic"
	var timeout_seconds: float = 5.0
	var available_type_ids: Array[StringName] = []

class SubmitPlanResponse:
	extends RefCounted
	var plans: Array[Resource] = []           # ActionPlan
	var raw_text: String = ""
	var error: StringName = &""               # &"" | &"timeout" | &"network" | &"schema_violation" | &"refusal" | &"no_api_key"
	var elapsed_seconds: float = 0.0
	var token_usage: Dictionary = {}          # {input, output}
```

- [ ] **Step 3: Run headless boot to verify the file parses**

```bash
cd "D:/War Buddy" && godot --headless --path godot --quit-after 3 2>&1 | tail -3
```

Expected: clean boot with no `SCRIPT ERROR: Parse Error` lines.

- [ ] **Step 4: Commit**

```bash
git add godot/scripts/ai/deputy_llm_client.gd && git commit -m "feat(godot): add DeputyLLMClient base interface + request/response types

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 2: `MockClient` — keyword-driven canned ActionPlans

**Files:**
- Create: `godot/scripts/ai/mock_client.gd`
- Create: `godot/tests/test_mock_client.gd`

`MockClient` is the workhorse: every test runs against it, and CI without an API
key uses it as fallback. It maps utterances to canned plans by simple keyword
match — sufficient to prove the end-to-end pipeline.

- [ ] **Step 1: Write the failing test**

`godot/tests/test_mock_client.gd`:
```gdscript
extends "res://addons/gut/test.gd"

const MockClientScript = preload("res://scripts/ai/mock_client.gd")
const DeputyLLMClientScript = preload("res://scripts/ai/deputy_llm_client.gd")
const ActionPlanScript = preload("res://scripts/command/action_plan.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

func _make_request(utterance: String) -> RefCounted:
	var req = DeputyLLMClientScript.SubmitPlanRequest.new()
	req.utterance = utterance
	return req

func test_returns_attack_plan_for_attack_keyword():
	var c = MockClientScript.new()
	var resp = await c.submit_plan(_make_request("focus fire on enemy_a"))
	assert_eq(resp.error, &"")
	assert_eq(resp.plans.size(), 1)
	assert_eq(resp.plans[0].orders.size(), 1)
	assert_eq(resp.plans[0].orders[0].type_id, &"attack")

func test_returns_move_plan_for_move_keyword():
	var c = MockClientScript.new()
	var resp = await c.submit_plan(_make_request("move to mid"))
	assert_eq(resp.plans[0].orders[0].type_id, &"move")

func test_returns_empty_plan_for_conversational_utterance():
	var c = MockClientScript.new()
	var resp = await c.submit_plan(_make_request("good job"))
	assert_eq(resp.plans.size(), 0)
	assert_string_contains(resp.raw_text, "good job")

func test_response_satisfies_action_plan_invariants_after_apply():
	var c = MockClientScript.new()
	var resp = await c.submit_plan(_make_request("attack the building"))
	var plan = resp.plans[0]
	plan.apply_invariants()
	var inv = plan.validate_invariants()
	assert_true(inv["ok"])

func test_simulated_timeout_when_utterance_starts_with_TIMEOUT():
	var c = MockClientScript.new()
	var resp = await c.submit_plan(_make_request("TIMEOUT please"))
	assert_eq(resp.error, &"timeout")
	assert_eq(resp.plans.size(), 0)
```

- [ ] **Step 2: Run tests — expect parse error (mock_client missing)**

```bash
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -8
```

Expected: ERROR loading `res://scripts/ai/mock_client.gd`.

- [ ] **Step 3: Implement `mock_client.gd`**

`godot/scripts/ai/mock_client.gd`:
```gdscript
extends "res://scripts/ai/deputy_llm_client.gd"

const ActionPlanScript = preload("res://scripts/command/action_plan.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

var _id_counter: int = 0

func submit_plan(req) -> Variant:
	# Simulated async — yield one frame so callers can `await`.
	await Engine.get_main_loop().process_frame
	var resp = SubmitPlanResponse.new()
	resp.elapsed_seconds = 0.0
	if req.utterance.begins_with("TIMEOUT"):
		resp.error = &"timeout"
		return resp
	var lower := req.utterance.to_lower()
	var plan = ActionPlanScript.new()
	plan.id = StringName("mock_plan_%d" % _id_counter)
	_id_counter += 1
	plan.deputy = &"deputy"
	plan.tier = ActionPlanScript.Tier.TACTICAL
	plan.triggering_utterance = req.utterance
	plan.timestamp_ms = Time.get_ticks_msec()
	if "attack" in lower or "focus fire" in lower or "kill" in lower:
		plan.rationale = "Engaging the requested target."
		plan.confidence = 0.85
		plan.orders = [_make_order(plan.id, &"attack", &"deputy", 1, 0, 1)] as Array[Resource]
	elif "move" in lower or "go" in lower or "rally" in lower:
		plan.rationale = "Repositioning forces."
		plan.confidence = 0.90
		plan.orders = [_make_order(plan.id, &"move", &"deputy", 5, 0, 5)] as Array[Resource]
	else:
		# Conversational — no plan, just a raw text echo.
		resp.raw_text = "Mock deputy heard: %s" % req.utterance
		return resp
	plan.apply_invariants()
	resp.plans = [plan] as Array[Resource]
	resp.raw_text = plan.rationale
	return resp

func _make_order(plan_id: StringName, type_id: StringName, deputy: StringName,
		x: float, y: float, z: float) -> Resource:
	var o = TacticalOrderScript.new()
	o.id = StringName("mock_ord_%d" % _id_counter)
	_id_counter += 1
	o.type_id = type_id
	o.origin = TacticalOrderScript.Origin.TACTICAL_VOICE
	o.issuer = TacticalOrderScript.Issuer.DEPUTY
	o.deputy = deputy
	o.target_position = Vector3(x, y, z)
	o.parent_intent_id = plan_id
	o.timestamp_ms = Time.get_ticks_msec()
	return o
```

- [ ] **Step 4: Re-import and run tests — expect 64 (existing) + 5 (new) = 69 green**

```bash
godot --headless --path godot --import 2>&1 | tail -2
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -8
```

Expected: `Passing Tests 69`.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/ai/mock_client.gd godot/tests/test_mock_client.gd && git commit -m "feat(godot): add MockClient — keyword-driven canned ActionPlans for tests

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 3: `DeputyPersona` Resource + `deputy_veteran.tres`

**Files:**
- Create: `godot/scripts/ai/deputy_persona.gd`
- Create: `godot/data/personas/deputy_veteran.tres`

The persona Resource has no behavior; tests aren't required for v0.4.0. The
`.tres` ships as a single sample; full Aggro / Pedant variants come in v0.5.0.

- [ ] **Step 1: Implement the Resource**

`godot/scripts/ai/deputy_persona.gd`:
```gdscript
class_name DeputyPersona
extends Resource

@export var persona_id: StringName = &"deputy_default"
@export var display_name: String = "Deputy"
@export var archetype: StringName = &"veteran"
@export var voice_style: String = "calm, terse"
@export_multiline var system_prompt_template: String = ""
@export var priority_traits: Dictionary = {}
@export var quirks: Array[String] = []
@export var allowed_type_ids: Array[StringName] = []
@export var refusal_patterns: Array[String] = []
@export var preferred_model: StringName = &"claude-sonnet-4-5-20250929"
@export var consolidation_model: StringName = &"claude-haiku-4-5-20251022"
```

- [ ] **Step 2: Create the sample `.tres`**

```bash
mkdir -p "D:/War Buddy/godot/data/personas"
```

`godot/data/personas/deputy_veteran.tres`:
```
[gd_resource type="Resource" load_steps=2 format=3 uid="uid://deputyveteran"]

[ext_resource type="Script" path="res://scripts/ai/deputy_persona.gd" id="1_persona"]

[resource]
script = ExtResource("1_persona")
persona_id = &"deputy_veteran"
display_name = "Deputy"
archetype = &"veteran"
voice_style = "calm, terse, uses chess metaphors"
system_prompt_template = "You are a veteran field deputy. Style: {{voice_style}}. Quirks:\n  - {{quirks}}\nMatch memory: {{memory}}\nObservation: {{snapshot}}\nAvailable orders: {{allowed_orders}}\nPlayer just said: {{utterance}}\nReply by calling submit_plan with at most 3 tactical orders, OR speak conversationally with no orders."
priority_traits = {
"aggression": 0.45,
"caution": 0.55,
"economy_focus": 0.5
}
quirks = ["uses chess openings as analogies", "prefers single-line summaries"]
allowed_type_ids = [&"move", &"attack", &"stop", &"hold", &"use_skill"]
refusal_patterns = ["suicide charge", "leave hero exposed"]
preferred_model = &"claude-sonnet-4-5-20250929"
consolidation_model = &"claude-haiku-4-5-20251022"
```

- [ ] **Step 3: Run headless boot to verify the file parses and `.tres` loads**

```bash
godot --headless --path godot --import 2>&1 | tail -2
godot --headless --path godot --quit-after 3 2>&1 | tail -3
```

Expected: no SCRIPT ERROR / Parse Error.

- [ ] **Step 4: Commit**

```bash
git add godot/scripts/ai/deputy_persona.gd godot/data/personas/deputy_veteran.tres && git commit -m "feat(godot): add DeputyPersona Resource + deputy_veteran.tres

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 4: `DeputyMemory` Resource + `MemoryStore` autoload

**Files:**
- Create: `godot/scripts/ai/deputy_memory.gd`
- Create: `godot/scripts/ai/memory_store.gd`
- Create: `godot/tests/test_deputy_memory.gd`
- Modify: `godot/project.godot` (autoload added in Task 9 along with the rest)

- [ ] **Step 1: Write the failing test**

`godot/tests/test_deputy_memory.gd`:
```gdscript
extends "res://addons/gut/test.gd"

const MemoryStoreScript = preload("res://scripts/ai/memory_store.gd")
const DeputyMemoryScript = preload("res://scripts/ai/deputy_memory.gd")

var _store: Node = null

func before_each():
	_store = MemoryStoreScript.new()
	add_child_autofree(_store)
	# Use a temp path so each test starts clean
	_store.base_dir = "user://deputies_test"
	# Wipe any leftover
	var d = DirAccess.open("user://")
	if d != null and d.dir_exists("deputies_test"):
		_clean_test_dir()

func _clean_test_dir():
	var d = DirAccess.open("user://deputies_test")
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute("user://deputies_test")

func test_load_returns_default_when_file_missing():
	var m = _store.load_memory(&"deputy_a")
	assert_eq(m.deputy_id, &"deputy_a")
	assert_eq(m.total_matches, 0)
	assert_eq(m.relationship_traits, {})

func test_save_then_load_preserves_fields():
	var m = DeputyMemoryScript.new()
	m.deputy_id = &"deputy_a"
	m.total_matches = 5
	m.wins = 3
	m.relationship_traits = {"trust": 0.6}
	m.match_anecdotes = ["played chess opening twice", "lost a captain to ambush"]
	_store.save_memory(m)
	var loaded = _store.load_memory(&"deputy_a")
	assert_eq(loaded.total_matches, 5)
	assert_eq(loaded.wins, 3)
	assert_almost_eq(loaded.relationship_traits["trust"], 0.6, 0.001)
	assert_eq(loaded.match_anecdotes.size(), 2)

func test_snapshot_for_returns_jsonable_dict():
	var m = DeputyMemoryScript.new()
	m.deputy_id = &"deputy_a"
	m.total_matches = 7
	m.relationship_traits = {"trust": 0.8}
	_store.save_memory(m)
	var snap = _store.snapshot_for(&"deputy_a")
	assert_eq(snap["total_matches"], 7)
	assert_almost_eq(snap["relationship_traits"]["trust"], 0.8, 0.001)
	# Round-trip through JSON
	var j = JSON.stringify(snap)
	var parsed = JSON.parse_string(j)
	assert_eq(parsed["total_matches"], 7)
```

- [ ] **Step 2: Run tests — expect parse error**

```bash
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```

Expected: ERROR loading `res://scripts/ai/memory_store.gd`.

- [ ] **Step 3: Implement `deputy_memory.gd`**

`godot/scripts/ai/deputy_memory.gd`:
```gdscript
class_name DeputyMemory
extends Resource

@export var deputy_id: StringName = &""
@export var total_matches: int = 0
@export var wins: int = 0
@export var losses: int = 0
@export var hours_played: float = 0.0
@export var relationship_traits: Dictionary = {}    # StringName -> float in [-1, 1]
@export var match_anecdotes: Array[String] = []     # 0-12 short, deputy-flavored memories
@export var preferred_phrases: Array[String] = []
@export var schema_version: int = 1

func to_dict() -> Dictionary:
	return {
		"deputy_id": String(deputy_id),
		"total_matches": total_matches,
		"wins": wins,
		"losses": losses,
		"hours_played": hours_played,
		"relationship_traits": relationship_traits.duplicate(true),
		"match_anecdotes": match_anecdotes.duplicate(),
		"preferred_phrases": preferred_phrases.duplicate(),
		"schema_version": schema_version,
	}

static func from_dict(d: Dictionary) -> DeputyMemory:
	var m := DeputyMemory.new()
	m.deputy_id = StringName(d.get("deputy_id", ""))
	m.total_matches = int(d.get("total_matches", 0))
	m.wins = int(d.get("wins", 0))
	m.losses = int(d.get("losses", 0))
	m.hours_played = float(d.get("hours_played", 0.0))
	m.relationship_traits = (d.get("relationship_traits", {}) as Dictionary).duplicate(true)
	var raw_anec: Array = d.get("match_anecdotes", [])
	var typed_anec: Array[String] = []
	for s in raw_anec:
		typed_anec.append(String(s))
	m.match_anecdotes = typed_anec
	var raw_phr: Array = d.get("preferred_phrases", [])
	var typed_phr: Array[String] = []
	for s in raw_phr:
		typed_phr.append(String(s))
	m.preferred_phrases = typed_phr
	m.schema_version = int(d.get("schema_version", 1))
	return m
```

- [ ] **Step 4: Implement `memory_store.gd`**

`godot/scripts/ai/memory_store.gd`:
```gdscript
# Autoload as `MemoryStore` via project.godot.
extends Node

const DeputyMemoryScript = preload("res://scripts/ai/deputy_memory.gd")

var base_dir: String = "user://deputies"

func _ready() -> void:
	if not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)

func _path_for(deputy_id: StringName) -> String:
	return "%s/%s.json" % [base_dir, String(deputy_id)]

func load_memory(deputy_id: StringName) -> DeputyMemoryScript:
	if not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)
	var path = _path_for(deputy_id)
	if not FileAccess.file_exists(path):
		var fresh = DeputyMemoryScript.new()
		fresh.deputy_id = deputy_id
		return fresh
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		var fresh2 = DeputyMemoryScript.new()
		fresh2.deputy_id = deputy_id
		return fresh2
	var text = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		var fresh3 = DeputyMemoryScript.new()
		fresh3.deputy_id = deputy_id
		return fresh3
	return DeputyMemoryScript.from_dict(parsed)

func save_memory(memory: DeputyMemoryScript) -> void:
	if not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)
	var path = _path_for(memory.deputy_id)
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("MemoryStore: cannot write %s" % path)
		return
	f.store_string(JSON.stringify(memory.to_dict()))
	f.close()

func snapshot_for(deputy_id: StringName) -> Dictionary:
	return load_memory(deputy_id).to_dict()
```

> JSON instead of `.tres` for memory: makes the file diff-friendly and lets us
> hand-edit during testing. Persona files stay `.tres` (designer-authored,
> editor-ergonomic).

- [ ] **Step 5: Re-import and run tests — expect 69 + 3 = 72 green**

```bash
godot --headless --path godot --import 2>&1 | tail -2
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```

Expected: `Passing Tests 72`.

- [ ] **Step 6: Commit**

```bash
git add godot/scripts/ai/deputy_memory.gd godot/scripts/ai/memory_store.gd godot/tests/test_deputy_memory.gd && git commit -m "feat(godot): add DeputyMemory Resource + MemoryStore JSON persistence

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 5: `BattlefieldSnapshotBuilder`

**Files:**
- Create: `godot/scripts/ai/battlefield_snapshot_builder.gd`
- Create: `godot/tests/test_battlefield_snapshot_builder.gd`

v1 stub queries `squad_units` and `enemy_buildings` groups directly. Doc 09 will
swap to `GameState`.

- [ ] **Step 1: Write the failing test**

`godot/tests/test_battlefield_snapshot_builder.gd`:
```gdscript
extends "res://addons/gut/test.gd"

const BuilderScript = preload("res://scripts/ai/battlefield_snapshot_builder.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

# Lightweight fakes that satisfy the group-query stub
class FakeUnit:
	extends Node3D
	var unit_id: StringName = &"unit_a"
	func get_unit_id() -> StringName:
		return unit_id

class FakeBuilding:
	extends Node3D
	var building_id: StringName = &"enemy_a"
	var hp: int = 30
	var max_hp: int = 60
	func get_building_id() -> StringName:
		return building_id

func _make_builder() -> Node:
	var b = BuilderScript.new()
	add_child_autofree(b)
	return b

func test_snapshot_dict_has_required_top_level_keys():
	var b = _make_builder()
	var snap = b.build_for(&"deputy", &"")
	for key in ["match_meta", "you", "units", "enemies", "recent_events",
	            "player_signals", "available_orders"]:
		assert_true(snap.has(key), "missing top-level key: %s" % key)

func test_units_section_picks_up_squad_units_group():
	var b = _make_builder()
	var u = FakeUnit.new()
	u.add_to_group("squad_units")
	u.global_position = Vector3(2, 0, 3)
	add_child_autofree(u)
	var snap = b.build_for(&"deputy", &"")
	assert_eq(snap["units"].size(), 1)
	assert_eq(snap["units"][0]["id"], "unit_a")

func test_enemies_section_picks_up_enemy_buildings_group():
	var b = _make_builder()
	var e = FakeBuilding.new()
	e.add_to_group("enemy_buildings")
	e.global_position = Vector3(8, 0, 8)
	add_child_autofree(e)
	var snap = b.build_for(&"deputy", &"")
	assert_eq(snap["enemies"].size(), 1)
	assert_eq(snap["enemies"][0]["id"], "enemy_a")

func test_snapshot_is_json_round_trippable():
	var b = _make_builder()
	var snap = b.build_for(&"deputy", &"")
	var j = JSON.stringify(snap)
	var parsed = JSON.parse_string(j)
	assert_not_null(parsed)
	assert_true(parsed.has("match_meta"))
```

- [ ] **Step 2: Run tests — expect parse error**

```bash
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```

Expected: ERROR loading `res://scripts/ai/battlefield_snapshot_builder.gd`.

- [ ] **Step 3: Implement**

`godot/scripts/ai/battlefield_snapshot_builder.gd`:
```gdscript
class_name BattlefieldSnapshotBuilder
extends Node

# v1 stub — reads scene-tree groups directly. Doc 09 swaps this to GameState.

func build_for(deputy_id: StringName, _tier_hint: StringName = &"") -> Dictionary:
	return {
		"match_meta": _build_match_meta(),
		"you": _build_self_view(deputy_id),
		"units": _build_units(),
		"enemies": _build_enemies(),
		"recent_events": [],   # populated when EventBus lands
		"player_signals": _build_player_signals(),
		"available_orders": _available_orders(deputy_id),
	}

func _build_match_meta() -> Dictionary:
	return {
		"tick": Engine.get_physics_frames(),
		"elapsed_s": int(Time.get_ticks_msec() / 1000.0),
		"score": {"buildings_killed": 0, "units_lost": 0},
	}

func _build_self_view(deputy_id: StringName) -> Dictionary:
	return {
		"deputy_id": String(deputy_id),
		"last_plan_id": "",
		"recent_orders": [],
	}

func _build_units() -> Array:
	var out: Array = []
	if get_tree() == null:
		return out
	for u in get_tree().get_nodes_in_group("squad_units"):
		var entry = {"id": "", "kind": "squad_unit", "pos_grid": _grid(u.global_position)}
		if u.has_method("get_unit_id"):
			entry["id"] = String(u.get_unit_id())
		elif u.has_method("get") and u.get("unit_id") != null:
			entry["id"] = String(u.unit_id)
		else:
			entry["id"] = u.name
		out.append(entry)
	return out

func _build_enemies() -> Array:
	var out: Array = []
	if get_tree() == null:
		return out
	for e in get_tree().get_nodes_in_group("enemy_buildings"):
		var entry = {"id": "", "kind": "enemy_building", "pos_grid": _grid(e.global_position)}
		if e.has_method("get_building_id"):
			entry["id"] = String(e.get_building_id())
		elif e.has_method("get") and e.get("building_id") != null:
			entry["id"] = String(e.building_id)
		else:
			entry["id"] = e.name
		entry["hp_pct"] = 1.0
		if e.get("hp") != null and e.get("max_hp") != null and int(e.max_hp) > 0:
			entry["hp_pct"] = float(e.hp) / float(e.max_hp)
		out.append(entry)
	return out

func _build_player_signals() -> Dictionary:
	return {
		"last_utterance": "",
		"mouse_focus_grid": "",
		"selected_landmark": "",
	}

func _available_orders(_deputy_id: StringName) -> Array:
	if not Engine.has_singleton("OrderTypeRegistry"):
		# Autoload is not a singleton in this lookup form; resolve via tree
		pass
	var registry = _resolve_registry()
	if registry == null:
		return []
	var ids: Array[StringName] = registry.list_for_deputy(&"deputy")
	var out: Array = []
	for sn in ids:
		out.append(String(sn))
	return out

func _resolve_registry():
	# Autoload is mounted on the SceneTree's root.
	var t = get_tree()
	if t == null:
		return null
	return t.root.get_node_or_null("OrderTypeRegistry")

func _grid(pos: Vector3) -> String:
	# Trivial A1..H8 mapping centered on origin, 4 units per cell.
	var col_idx = clampi(int((pos.x + 16) / 4), 0, 7)
	var row_idx = clampi(int((pos.z + 16) / 4), 0, 7)
	var col = "ABCDEFGH"[col_idx]
	return "%s%d" % [col, row_idx + 1]
```

- [ ] **Step 4: Re-import and run tests — expect 72 + 4 = 76 green**

```bash
godot --headless --path godot --import 2>&1 | tail -2
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```

Expected: `Passing Tests 76`.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/ai/battlefield_snapshot_builder.gd godot/tests/test_battlefield_snapshot_builder.gd && git commit -m "feat(godot): add BattlefieldSnapshotBuilder with scene-group stub

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 6: `Deputy` Node

**Files:**
- Create: `godot/scripts/ai/deputy.gd`
- Create: `godot/tests/test_deputy.gd`

- [ ] **Step 1: Write the failing test**

`godot/tests/test_deputy.gd`:
```gdscript
extends "res://addons/gut/test.gd"

const DeputyScript = preload("res://scripts/ai/deputy.gd")
const PersonaScript = preload("res://scripts/ai/deputy_persona.gd")
const ActionPlanScript = preload("res://scripts/command/action_plan.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")
const RegistryScript = preload("res://scripts/command/order_type_registry.gd")
const ControlPolicyScript = preload("res://scripts/command/control_policy.gd")
const CommandBusScript = preload("res://scripts/command/command_bus.gd")

func _make_persona(allowed: Array[StringName]) -> Resource:
	var p = PersonaScript.new()
	p.persona_id = &"deputy_test"
	p.display_name = "Test Deputy"
	p.allowed_type_ids = allowed
	return p

func _make_bus_with_move() -> Node:
	var registry = RegistryScript.new()
	var def = RegistryScript.TypeDef.new()
	def.id = &"move"
	registry.register(def)
	var def2 = RegistryScript.TypeDef.new()
	def2.id = &"attack"
	registry.register(def2)
	add_child_autofree(registry)
	var bus = CommandBusScript.new()
	bus.set_registry(registry)
	bus.set_policy(ControlPolicyScript.FullControlPolicy.new())
	bus.persistence_enabled = false
	add_child_autofree(bus)
	return bus

func _make_plan(deputy: StringName, type_id: StringName) -> Resource:
	var plan = ActionPlanScript.new()
	plan.id = &"plan_t1"
	plan.deputy = deputy
	plan.tier = ActionPlanScript.Tier.TACTICAL
	plan.rationale = "test"
	var o = TacticalOrderScript.new()
	o.id = &"ord_t1"
	o.type_id = type_id
	o.origin = TacticalOrderScript.Origin.TACTICAL_VOICE
	o.issuer = TacticalOrderScript.Issuer.DEPUTY
	o.deputy = deputy
	o.target_position = Vector3(1, 0, 1)
	plan.orders = [o] as Array[Resource]
	plan.apply_invariants()
	return plan

func test_handle_plan_speaks_rationale_then_dispatches_to_bus():
	var bus = _make_bus_with_move()
	var d = DeputyScript.new()
	d.deputy_id = &"deputy"
	d.persona = _make_persona([&"move", &"attack"] as Array[StringName])
	d.bind_command_bus(bus)
	add_child_autofree(d)
	watch_signals(d)
	var plan = _make_plan(&"deputy", &"move")
	d.handle_plan(plan)
	assert_signal_emit_count(d, "spoke", 1)
	assert_eq(bus.get_recent_orders().size(), 1)

func test_handle_plan_filters_orders_by_persona_allowed_types():
	var bus = _make_bus_with_move()
	var d = DeputyScript.new()
	d.deputy_id = &"deputy"
	d.persona = _make_persona([&"move"] as Array[StringName])
	d.bind_command_bus(bus)
	add_child_autofree(d)
	watch_signals(d)
	# Plan asks for attack, persona forbids it → reject locally without hitting bus
	var plan = _make_plan(&"deputy", &"attack")
	d.handle_plan(plan)
	assert_eq(bus.get_recent_orders().size(), 0)
	assert_signal_emit_count(d, "plan_rejected_locally", 1)

func test_speak_emits_spoke_signal_with_text():
	var d = DeputyScript.new()
	d.deputy_id = &"deputy"
	add_child_autofree(d)
	watch_signals(d)
	d.speak("Hello commander.")
	assert_signal_emit_count(d, "spoke", 1)
	assert_signal_emitted_with_parameters(d, "spoke",
		["Hello commander.", &"deputy"])
```

- [ ] **Step 2: Run tests — expect parse error**

```bash
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```

Expected: ERROR loading `res://scripts/ai/deputy.gd`.

- [ ] **Step 3: Implement**

`godot/scripts/ai/deputy.gd`:
```gdscript
class_name Deputy
extends Node

signal spoke(text: String, deputy_id: StringName)
signal plan_received(plan: Resource)
signal plan_rejected_locally(plan: Resource, reason: StringName)

@export var deputy_id: StringName = &"deputy"
@export var persona: Resource = null     # DeputyPersona

var memory: Resource = null               # DeputyMemory
var _short_term: Array[Resource] = []     # ActionPlans
var _bus: Node = null

func bind_command_bus(bus: Node) -> void:
	_bus = bus

func bind_memory(m: Resource) -> void:
	memory = m

func handle_plan(plan: Resource) -> void:
	if plan == null:
		return
	plan_received.emit(plan)
	# Persona filter: drop plans whose orders include disallowed types.
	if persona != null and not persona.allowed_type_ids.is_empty():
		for o in plan.orders:
			if not persona.allowed_type_ids.has(o.type_id):
				plan_rejected_locally.emit(plan, &"persona_disallowed_type")
				speak("I can't do that — outside my training.")
				return
	# Speak first, dispatch second — character feel before machine action.
	speak(plan.rationale)
	if _bus != null:
		var result = _bus.submit_plan(plan)
		if result.get("plan_rejected", false):
			plan_rejected_locally.emit(plan, &"bus_invariants")
			return
	_short_term.append(plan)
	if _short_term.size() > 6:
		_short_term.pop_front()

func speak(text: String) -> void:
	if text.is_empty():
		return
	spoke.emit(text, deputy_id)

func snapshot_short_term() -> Dictionary:
	var out: Array = []
	for p in _short_term:
		out.append({"id": String(p.id), "rationale": p.rationale})
	return {"recent_plans": out}
```

- [ ] **Step 4: Re-import and run tests — expect 76 + 3 = 79 green**

```bash
godot --headless --path godot --import 2>&1 | tail -2
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```

Expected: `Passing Tests 79`.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/ai/deputy.gd godot/tests/test_deputy.gd && git commit -m "feat(godot): add Deputy node with persona-filtered plan handling

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 7: `ClassifierRouter`

**Files:**
- Create: `godot/scripts/ai/classifier_router.gd`
- Create: `godot/tests/test_classifier_router.gd`

End-to-end: utterance → MockClient → ActionPlan → Deputy.handle_plan → bus.

- [ ] **Step 1: Write the failing test**

`godot/tests/test_classifier_router.gd`:
```gdscript
extends "res://addons/gut/test.gd"

const ClassifierRouterScript = preload("res://scripts/ai/classifier_router.gd")
const DeputyScript = preload("res://scripts/ai/deputy.gd")
const PersonaScript = preload("res://scripts/ai/deputy_persona.gd")
const MockClientScript = preload("res://scripts/ai/mock_client.gd")
const BuilderScript = preload("res://scripts/ai/battlefield_snapshot_builder.gd")
const RegistryScript = preload("res://scripts/command/order_type_registry.gd")
const ControlPolicyScript = preload("res://scripts/command/control_policy.gd")
const CommandBusScript = preload("res://scripts/command/command_bus.gd")

func _wire_full_pipeline() -> Dictionary:
	# Bus + registry
	var registry = RegistryScript.new()
	for type_id in [&"move", &"attack", &"stop", &"hold", &"use_skill"]:
		var def = RegistryScript.TypeDef.new()
		def.id = type_id
		registry.register(def)
	add_child_autofree(registry)
	var bus = CommandBusScript.new()
	bus.set_registry(registry)
	bus.set_policy(ControlPolicyScript.FullControlPolicy.new())
	bus.persistence_enabled = false
	add_child_autofree(bus)

	# Deputy
	var p = PersonaScript.new()
	p.persona_id = &"deputy_test"
	p.allowed_type_ids = [&"move", &"attack", &"stop", &"hold", &"use_skill"] as Array[StringName]
	var d = DeputyScript.new()
	d.deputy_id = &"deputy"
	d.persona = p
	d.bind_command_bus(bus)
	add_child_autofree(d)

	# Snapshot builder
	var b = BuilderScript.new()
	add_child_autofree(b)

	# Router with Mock client
	var r = ClassifierRouterScript.new()
	r.bind(d, MockClientScript.new(), b, registry)
	add_child_autofree(r)
	return {"router": r, "deputy": d, "bus": bus}

func test_handle_utterance_routes_attack_to_deputy_and_bus():
	var w = _wire_full_pipeline()
	watch_signals(w["deputy"])
	await w["router"].handle_utterance("attack the building", &"text_input")
	assert_signal_emit_count(w["deputy"], "spoke", 1)
	assert_eq(w["bus"].get_recent_orders().size(), 1)
	assert_eq(w["bus"].get_recent_orders()[0].type_id, &"attack")

func test_handle_utterance_with_conversational_input_emits_speech_only():
	var w = _wire_full_pipeline()
	watch_signals(w["deputy"])
	await w["router"].handle_utterance("good job", &"text_input")
	# The Mock returns no plan; router should make the deputy speak the raw_text
	assert_signal_emit_count(w["deputy"], "spoke", 1)
	assert_eq(w["bus"].get_recent_orders().size(), 0)

func test_handle_utterance_emits_classification_failed_on_timeout():
	var w = _wire_full_pipeline()
	watch_signals(w["router"])
	await w["router"].handle_utterance("TIMEOUT please", &"text_input")
	assert_signal_emit_count(w["router"], "classification_failed", 1)
```

- [ ] **Step 2: Run tests — expect parse error**

```bash
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```

Expected: ERROR on classifier_router.gd.

- [ ] **Step 3: Implement**

`godot/scripts/ai/classifier_router.gd`:
```gdscript
class_name ClassifierRouter
extends Node

signal plan_emitted(plan: Resource)
signal classification_failed(utterance: String, reason: StringName)

const DeputyLLMClientScript = preload("res://scripts/ai/deputy_llm_client.gd")

var _deputy: Node = null
var _llm: RefCounted = null
var _snapshot_builder: Node = null
var _registry: Node = null

func bind(deputy: Node, llm_client: RefCounted, snapshot_builder: Node,
		registry: Node) -> void:
	_deputy = deputy
	_llm = llm_client
	_snapshot_builder = snapshot_builder
	_registry = registry

func handle_utterance(text: String, _source: StringName) -> void:
	if _deputy == null or _llm == null or _snapshot_builder == null:
		push_error("ClassifierRouter: not bound")
		return
	var req = DeputyLLMClientScript.SubmitPlanRequest.new()
	req.persona = _deputy.persona
	req.observation = _snapshot_builder.build_for(_deputy.deputy_id, &"")
	req.utterance = text
	if _registry != null:
		req.available_type_ids = _registry.list_for_deputy(_deputy.deputy_id)
	var resp = await _llm.submit_plan(req)
	if resp.error != &"":
		classification_failed.emit(text, resp.error)
		_deputy.speak("Sorry — couldn't process that. (%s)" % String(resp.error))
		return
	if resp.plans.is_empty():
		# Conversational utterance — deputy still speaks
		_deputy.speak(resp.raw_text if resp.raw_text != "" else "...")
		return
	for plan in resp.plans:
		_deputy.handle_plan(plan)
		plan_emitted.emit(plan)
```

- [ ] **Step 4: Re-import and run tests — expect 79 + 3 = 82 green**

```bash
godot --headless --path godot --import 2>&1 | tail -2
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```

Expected: `Passing Tests 82`.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/ai/classifier_router.gd godot/tests/test_classifier_router.gd && git commit -m "feat(godot): add ClassifierRouter — utterance to ActionPlan front door

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 8: `AnthropicClient` (real LLM, key-gated)

**Files:**
- Create: `godot/scripts/ai/anthropic_client.gd`

No GUT tests for this in v0.4.0 — running tests against a live API has cost and
non-determinism. Manual smoke covers it (Task 11).

- [ ] **Step 1: Implement**

`godot/scripts/ai/anthropic_client.gd`:
```gdscript
extends "res://scripts/ai/deputy_llm_client.gd"

const ActionPlanScript = preload("res://scripts/command/action_plan.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")

const API_URL := "https://api.anthropic.com/v1/messages"
const API_VERSION := "2023-06-01"
const DEFAULT_MAX_TOKENS := 1024

@export var api_key_env_var: String = "ANTHROPIC_API_KEY"

func has_api_key() -> bool:
	return OS.get_environment(api_key_env_var) != ""

func submit_plan(req) -> Variant:
	var resp = SubmitPlanResponse.new()
	if not has_api_key():
		resp.error = &"no_api_key"
		return resp
	var key := OS.get_environment(api_key_env_var)
	var model := "claude-sonnet-4-5-20250929"
	if req.persona != null and req.persona.preferred_model != &"":
		model = String(req.persona.preferred_model)
	var system_prompt := _build_system_prompt(req)
	var user_msg := _build_user_message(req)
	var tool_schema := _build_tool_schema(req.available_type_ids)
	var body = {
		"model": model,
		"max_tokens": DEFAULT_MAX_TOKENS,
		"system": system_prompt,
		"messages": [{"role": "user", "content": user_msg}],
		"tools": [tool_schema],
		"tool_choice": {"type": "tool", "name": "submit_plan"},
	}
	var http = HTTPRequest.new()
	add_child(http)
	var headers = [
		"x-api-key: %s" % key,
		"anthropic-version: %s" % API_VERSION,
		"content-type: application/json",
	]
	var t0 = Time.get_ticks_msec()
	var err = http.request(API_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		resp.error = &"network"
		http.queue_free()
		return resp
	var args = await http.request_completed
	resp.elapsed_seconds = (Time.get_ticks_msec() - t0) / 1000.0
	http.queue_free()
	# request_completed signals (result, response_code, headers, body)
	var result_code := int(args[0])
	var status_code := int(args[1])
	var raw: PackedByteArray = args[3]
	if result_code != HTTPRequest.RESULT_SUCCESS:
		resp.error = &"network"
		return resp
	if status_code < 200 or status_code >= 300:
		resp.error = &"network"
		resp.raw_text = raw.get_string_from_utf8()
		return resp
	var parsed = JSON.parse_string(raw.get_string_from_utf8())
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		resp.error = &"schema_violation"
		return resp
	resp.token_usage = parsed.get("usage", {})
	# Find the tool_use block
	var content: Array = parsed.get("content", [])
	for block in content:
		if block.get("type", "") == "tool_use" and block.get("name", "") == "submit_plan":
			var input: Dictionary = block.get("input", {})
			var plan = _plan_from_tool_input(input, req)
			if plan != null:
				plan.apply_invariants()
				var inv = plan.validate_invariants()
				if not inv["ok"]:
					resp.error = &"schema_violation"
					return resp
				resp.plans = [plan] as Array[Resource]
				resp.raw_text = plan.rationale
				return resp
		elif block.get("type", "") == "text":
			resp.raw_text += String(block.get("text", ""))
	# No tool use — treat as conversational
	return resp

func _build_system_prompt(req) -> String:
	var template := ""
	if req.persona != null and req.persona.system_prompt_template != "":
		template = req.persona.system_prompt_template
	else:
		template = "You are an AI deputy. Respond by calling submit_plan."
	# Inject snapshot + memory + utterance via simple substitution
	var snapshot_str := JSON.stringify(req.observation)
	var memory_str := JSON.stringify(req.memory_snapshot)
	var utterance_str := req.utterance
	var quirks_str := ""
	if req.persona != null:
		quirks_str = "\n  - ".join(req.persona.quirks)
	var allowed_str := ""
	if req.persona != null:
		var arr: Array[String] = []
		for sn in req.persona.allowed_type_ids:
			arr.append(String(sn))
		allowed_str = ", ".join(arr)
	return template \
		.replace("{{snapshot}}", snapshot_str) \
		.replace("{{memory}}", memory_str) \
		.replace("{{utterance}}", utterance_str) \
		.replace("{{quirks}}", quirks_str) \
		.replace("{{allowed_orders}}", allowed_str) \
		.replace("{{voice_style}}", req.persona.voice_style if req.persona != null else "")

func _build_user_message(req) -> String:
	return req.utterance

func _build_tool_schema(available_type_ids: Array[StringName]) -> Dictionary:
	var allowed: Array[String] = []
	for sn in available_type_ids:
		allowed.append(String(sn))
	if allowed.is_empty():
		allowed = ["move", "attack", "stop", "hold", "use_skill"]
	return {
		"name": "submit_plan",
		"description": "Submit a tactical plan with a list of orders, plan-level rationale, and confidence.",
		"input_schema": {
			"type": "object",
			"properties": {
				"deputy": {"type": "string", "description": "The deputy seat (always 'deputy' for now)."},
				"tier": {"type": "string", "enum": ["tactical", "strategic"]},
				"rationale": {"type": "string", "description": "One short sentence explaining the plan."},
				"confidence": {"type": "number", "minimum": 0.0, "maximum": 1.0},
				"orders": {
					"type": "array",
					"items": {
						"type": "object",
						"properties": {
							"type_id": {"type": "string", "enum": allowed},
							"target_position": {"type": "array", "items": {"type": "number"}, "minItems": 3, "maxItems": 3},
							"target_landmark": {"type": "string"},
							"rationale": {"type": "string"},
						},
						"required": ["type_id"],
					},
				},
			},
			"required": ["deputy", "tier", "rationale", "orders"],
		},
	}

func _plan_from_tool_input(input: Dictionary, req) -> Resource:
	var plan = ActionPlanScript.new()
	plan.id = StringName("anthropic_plan_%d" % Time.get_ticks_msec())
	plan.deputy = StringName(input.get("deputy", "deputy"))
	plan.tier = ActionPlanScript.Tier.TACTICAL
	if input.get("tier", "tactical") == "strategic":
		plan.tier = ActionPlanScript.Tier.STRATEGIC
	plan.rationale = String(input.get("rationale", ""))
	plan.confidence = float(input.get("confidence", 0.7))
	plan.triggering_utterance = req.utterance
	plan.timestamp_ms = Time.get_ticks_msec()
	var raw_orders: Array = input.get("orders", [])
	var orders: Array[Resource] = []
	var i = 0
	for o_dict in raw_orders:
		var o = TacticalOrderScript.new()
		o.id = StringName("anthropic_ord_%d_%d" % [Time.get_ticks_msec(), i])
		o.type_id = StringName(o_dict.get("type_id", ""))
		o.origin = TacticalOrderScript.Origin.TACTICAL_VOICE
		if plan.tier == ActionPlanScript.Tier.STRATEGIC:
			o.origin = TacticalOrderScript.Origin.STRATEGIC_DECOMPOSITION
		o.issuer = TacticalOrderScript.Issuer.DEPUTY
		o.deputy = plan.deputy
		o.parent_intent_id = plan.id
		o.timestamp_ms = Time.get_ticks_msec()
		o.rationale = String(o_dict.get("rationale", ""))
		var pos_arr: Array = o_dict.get("target_position", [0, 0, 0])
		if pos_arr.size() >= 3:
			o.target_position = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		o.target_landmark = StringName(String(o_dict.get("target_landmark", "")))
		orders.append(o)
		i += 1
	plan.orders = orders
	return plan
```

- [ ] **Step 2: Headless boot to verify the file parses**

```bash
godot --headless --path godot --quit-after 3 2>&1 | tail -3
```

Expected: clean boot, no Parse Error.

- [ ] **Step 3: Commit**

```bash
git add godot/scripts/ai/anthropic_client.gd && git commit -m "feat(godot): add AnthropicClient for real LLM ActionPlan generation

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 9: HUD `MessageBubbleHud` + main.tscn wiring

**Files:**
- Create: `godot/scripts/hud/message_bubble_hud.gd`
- Modify: `godot/scenes/main.tscn`

- [ ] **Step 1: Create `MessageBubbleHud` script**

```bash
mkdir -p "D:/War Buddy/godot/scripts/hud"
```

`godot/scripts/hud/message_bubble_hud.gd`:
```gdscript
extends Control

const FADE_HOLD_S := 4.0
const FADE_DURATION_S := 1.0

@onready var label: Label = $Bubble/Label

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func display(text: String, deputy_id: StringName) -> void:
	if label == null:
		return
	label.text = "[%s] %s" % [String(deputy_id), text]
	visible = true
	modulate.a = 1.0
	# Cancel any in-flight tween by overwriting modulate via a fresh tween
	var tween := create_tween()
	tween.tween_interval(FADE_HOLD_S)
	tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION_S)
	tween.tween_callback(func(): visible = false)
```

- [ ] **Step 2: Add the bubble to `main.tscn`**

Open `godot/scenes/main.tscn` and insert a new node under `HudRoot` after the
existing `DevModeLabel` and before `VictoryOverlay`. The simplest stable
placement is bottom-center.

Add the following block after the `DevModeLabel` section in `main.tscn`:
```
[node name="MessageBubbleHud" type="Control" parent="HudRoot" unique_id=394820711]
unique_name_in_owner = true
script = ExtResource("4_bubble")
anchor_left = 0.5
anchor_top = 1.0
anchor_right = 0.5
anchor_bottom = 1.0
offset_left = -300.0
offset_top = -240.0
offset_right = 300.0
offset_bottom = -180.0
mouse_filter = 2

[node name="Bubble" type="PanelContainer" parent="HudRoot/MessageBubbleHud" unique_id=394820712]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 2

[node name="Label" type="Label" parent="HudRoot/MessageBubbleHud/Bubble" unique_id=394820713]
layout_mode = 2
text = ""
autowrap_mode = 3
horizontal_alignment = 1
vertical_alignment = 1
mouse_filter = 2
```

Also add the `ExtResource` reference at the top of `main.tscn` (the file's
`load_steps` count goes up by 1):
```
[ext_resource type="Script" path="res://scripts/hud/message_bubble_hud.gd" id="4_bubble"]
```

- [ ] **Step 3: Headless boot to verify the scene parses**

```bash
godot --headless --path godot --quit-after 3 2>&1 | tail -5
```

Expected: clean boot, including the existing `[RTSMVP] ...` lines, no SCRIPT
ERROR.

- [ ] **Step 4: Commit**

```bash
git add godot/scripts/hud/message_bubble_hud.gd godot/scenes/main.tscn && git commit -m "feat(godot): add MessageBubbleHud for deputy speech display

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 10: Bootstrap wiring + autoload

**Files:**
- Modify: `godot/project.godot`
- Modify: `godot/scripts/bootstrap.gd`
- Modify: `godot/scripts/hud_root.gd`

- [ ] **Step 1: Register `MemoryStore` autoload**

Edit `godot/project.godot`. The `[autoload]` section already has
`OrderTypeRegistry` and `CommandBus`. Add `MemoryStore` *before* `CommandBus`
isn't required (no init dependency) — append at the end of the section:

```
[autoload]

OrderTypeRegistry="*res://scripts/command/order_type_registry.gd"
CommandBus="*res://scripts/command/command_bus.gd"
MemoryStore="*res://scripts/ai/memory_store.gd"
```

- [ ] **Step 2: Add a `dispatch_utterance(text)` helper to `hud_root.gd`**

Open `godot/scripts/hud_root.gd`. After `command_submitted.emit(channel, text)`
near the end of `_submit_current_command()`, add a parallel signal that
bootstrap will use to drive the deputy:

```gdscript
signal utterance_submitted(text: String)
```

Place this signal declaration alongside `command_submitted` near the top of the
file. Then, inside `_submit_current_command()`, after the existing
`command_submitted.emit(channel, text)` line, add:

```gdscript
	utterance_submitted.emit(text)
```

This keeps the legacy `command_submitted` signal (still consumed by
`command_log_model`) and adds the new path for the deputy.

- [ ] **Step 3: Wire bootstrap**

In `godot/scripts/bootstrap.gd`, add new preloads near the top:

```gdscript
const DeputyScript = preload("res://scripts/ai/deputy.gd")
const ClassifierRouterScript = preload("res://scripts/ai/classifier_router.gd")
const MockClientScript = preload("res://scripts/ai/mock_client.gd")
const AnthropicClientScript = preload("res://scripts/ai/anthropic_client.gd")
const SnapshotBuilderScript = preload("res://scripts/ai/battlefield_snapshot_builder.gd")
const PersonaScript = preload("res://scripts/ai/deputy_persona.gd")
```

Add member fields:

```gdscript
var deputy = null
var classifier_router = null
var snapshot_builder = null
var llm_client: RefCounted = null
```

At the end of `_ready()` (after the `pre_plan_runner.notify_event(...)` call),
append:

```gdscript

	# --- Deputy + classifier wiring ---
	snapshot_builder = SnapshotBuilderScript.new()
	snapshot_builder.name = "BattlefieldSnapshotBuilder"
	add_child(snapshot_builder)

	var persona: Resource = load("res://data/personas/deputy_veteran.tres")
	if persona == null:
		push_error("Bootstrap: deputy_veteran.tres failed to load")
	deputy = DeputyScript.new()
	deputy.name = "Deputy"
	deputy.deputy_id = &"deputy"
	deputy.persona = persona
	deputy.bind_command_bus(CommandBus)
	deputy.bind_memory(MemoryStore.load_memory(&"deputy"))
	add_child(deputy)
	deputy.spoke.connect(_on_deputy_spoke)

	llm_client = _make_llm_client()
	classifier_router = ClassifierRouterScript.new()
	classifier_router.name = "ClassifierRouter"
	classifier_router.bind(deputy, llm_client, snapshot_builder, OrderTypeRegistry)
	add_child(classifier_router)

	hud.utterance_submitted.connect(classifier_router.handle_utterance.bind(&"text_input"))
	print("[RTSMVP] Deputy active: persona=%s llm=%s" % [
		String(persona.persona_id) if persona != null else "<none>",
		_llm_kind_name(llm_client),
	])
```

Add helper methods at the end of the file:

```gdscript
func _make_llm_client() -> RefCounted:
	var anthropic = AnthropicClientScript.new()
	if anthropic.has_api_key():
		return anthropic
	# Fallback: Mock client when no key is configured.
	return MockClientScript.new()

func _llm_kind_name(client: RefCounted) -> String:
	if client == null:
		return "<none>"
	if client is AnthropicClientScript:
		return "AnthropicClient"
	if client is MockClientScript:
		return "MockClient"
	return "<unknown>"

func _on_deputy_spoke(text: String, deputy_id: StringName) -> void:
	if hud != null and hud.has_method("show_deputy_bubble"):
		hud.show_deputy_bubble(text, deputy_id)
	print("[RTSMVP] Deputy %s: %s" % [String(deputy_id), text])
```

- [ ] **Step 4: Add `show_deputy_bubble` to `hud_root.gd`**

In `godot/scripts/hud_root.gd`, after the `@onready var dev_mode_label`
declaration, add:

```gdscript
@onready var message_bubble_hud: Control = %MessageBubbleHud
```

After the `show_dev_label` function, add:

```gdscript
func show_deputy_bubble(text: String, deputy_id: StringName) -> void:
	if message_bubble_hud != null and message_bubble_hud.has_method("display"):
		message_bubble_hud.display(text, deputy_id)
```

The router's `handle_utterance` overload — note that `bind` was called with the
source argument so the signal-forwarded utterance call shape becomes
`handle_utterance(text, &"text_input")`. That matches the signature.

- [ ] **Step 5: Run headless boot — expect new line**

```bash
godot --headless --path godot --quit-after 5 2>&1 | tail -10
```

Expected output includes:
```
[RTSMVP] OrderTypeRegistry: registered 5 core types
[RTSMVP] Bootstrap: hero=CommanderHero hud=HudRoot buildings=3
[RTSMVP] Bootstrap: dev squad controller active (debug build)
[RTSMVP] PrePlanRunner loaded 0 preplans from res://data/preplans
[RTSMVP] PrePlanRunner: notified match_start
[RTSMVP] Deputy active: persona=deputy_veteran llm=MockClient
```
(or `llm=AnthropicClient` if `ANTHROPIC_API_KEY` is set in the environment).
No SCRIPT ERROR.

- [ ] **Step 6: Run all GUT tests**

```bash
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```

Expected: `Passing Tests 82`, all green.

- [ ] **Step 7: Commit**

```bash
git add godot/project.godot godot/scripts/bootstrap.gd godot/scripts/hud_root.gd && git commit -m "feat(godot): bootstrap wires Deputy + ClassifierRouter + MemoryStore autoload

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 11: Smoke checklist + CHANGELOG + tag v0.4.0

**Files:**
- Modify: `docs/specs/05-godot-smoke-test-checklist.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Append "AI Deputy" section to `05-godot-smoke-test-checklist.md`**

After the existing "Command system" section, append:

```markdown

## AI Deputy (v0.4.0)

### Auto (no API key required)
- [ ] Headless boot prints `[RTSMVP] Deputy active: persona=deputy_veteran llm=MockClient`
- [ ] All 82 GUT tests pass
- [ ] In editor F5: type `move to mid` in the command panel and submit — a bubble appears at bottom-center reading something like `[deputy] Repositioning forces.`
- [ ] After the bubble fires, `CommandBus.get_recent_orders()` shows a new `move` order (verify via `Output` log line `[RTSMVP] Deputy deputy: ...`)
- [ ] Type `good job` — bubble appears with no order added to the bus
- [ ] Type `TIMEOUT please` — bubble shows the failure text, no orders dispatched

### Manual (requires `ANTHROPIC_API_KEY`)
- [ ] Set `ANTHROPIC_API_KEY` in the environment, then run from editor F5
- [ ] Boot prints `llm=AnthropicClient`
- [ ] Type `focus fire on the central building` — within ~3 s, a bubble appears with deputy-flavored text and at least one `attack` or `move` order lands in the bus
- [ ] No orders sit in the rejected ndjson (`user://order_log/<match_id>.rejected.ndjson` should be missing or empty)
- [ ] Persona voice style is detectable (calm, terse, chess metaphors per `deputy_veteran.tres`)
```

- [ ] **Step 2: Append `[v0.4.0]` block to `CHANGELOG.md`**

Insert above `## [v0.3.0]`:

```markdown
## [v0.4.0] — 2026-04-27

### Added
- **AI Deputy core (vision §2.2 + §2.3)** — single off-field deputy seat with a real LLM-driven plan pipeline. Doc 08 skeleton lands; Captain and Archon follow in v0.5.0.
- **`DeputyLLMClient` interface** — abstract async `submit_plan(req) -> resp` with `SubmitPlanRequest` / `SubmitPlanResponse` data classes.
- **`MockClient`** — keyword-routed canned ActionPlans driving every test and serving as the no-API-key fallback.
- **`AnthropicClient`** — real Anthropic Messages API integration via `HTTPRequest`, single-tool `submit_plan` with JSON schema generated from `OrderTypeRegistry`. Defaults to `claude-sonnet-4-5-20250929`; configurable per persona. `ANTHROPIC_API_KEY` env var; key absence falls back to `MockClient`.
- **`Deputy` Node** — off-field per vision §2.3; `handle_plan` validates persona-allowed type ids, speaks plan-level rationale via `spoke` signal, dispatches orders to `CommandBus`. No CharacterBody3D, no HP, cannot die.
- **`ClassifierRouter`** — single front door; one LLM call per utterance returns an `ActionPlan` (vision §2.4 strict A-chain — never directly addressable to captains).
- **`BattlefieldSnapshotBuilder`** — produces the cropped Dictionary observation (`match_meta`, `you`, `units`, `enemies`, `recent_events`, `player_signals`, `available_orders`). v1 stub queries scene-tree groups; doc 09 swaps to `GameState`.
- **`DeputyMemory` Resource + `MemoryStore` autoload** — JSON persistence under `user://deputies/<id>.json`. Match-time read-only; mutations only at end-of-match consolidation (consolidate path lands when 09's match_end signal lands).
- **`DeputyPersona` Resource + `deputy_veteran.tres`** — persona schema with system-prompt template, allowed type ids, refusal patterns, preferred / consolidation models.
- **HUD `MessageBubbleHud`** — bottom-center transient bubble; 4 s hold + 1 s fade; listens for `Deputy.spoke`.
- **Tests** — 18 new GUT cases (`test_mock_client`, `test_deputy_memory`, `test_battlefield_snapshot_builder`, `test_deputy`, `test_classifier_router`) bring total green count to 82.

### Notes
- Captain and Archon deferred to v0.5.0 — both are designed in spec 08 §11.6 / §11.7 and waiting on a dedicated implementation plan.
- Snapshot builder won't see `recent_events` until `EventBus` lands in doc 09. Memory consolidation is wired but is a no-op until match-end events exist.
- Streaming HUD bubble (token-by-token narration during LLM thinking) is not in v0.4.0 — current behavior is "wait for the tool call, then show full rationale". Streaming lands when the LoL/voice rework or doc 11 ships.
- Orders still don't actually move units (doc 09's executors not built yet). The deputy speaks, the bus accepts the orders, the orders sit in `pending` — that's expected v0.4.0 scope.
```

- [ ] **Step 3: Run the full pipeline once more**

```bash
godot --headless --path godot --quit-after 5 2>&1 | tail -8
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -6
```

Expected: bootstrap clean, `Passing Tests 82`.

- [ ] **Step 4: Commit docs**

```bash
git add docs/specs/05-godot-smoke-test-checklist.md CHANGELOG.md && git commit -m "docs: v0.4.0 smoke section + changelog entry

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

- [ ] **Step 5: Tag and push**

```bash
git tag v0.4.0
git push origin main v0.4.0
```

Verify:
- `git log --oneline -12` shows the eleven task commits.
- GitHub Actions `ci.yml` goes green on the push (no API key needed — Mock fallback).
- `release.yml` produces Linux / Windows / Web artifacts.

---

## Acceptance for v0.4.0

The milestone is "done" when **all** of:
1. Headless boot clean: prints all six `[RTSMVP] ...` lines, zero SCRIPT ERROR.
2. GUT: 82 / 82 passing.
3. Manual smoke from §"AI Deputy (v0.4.0)" auto subsection: every box checked.
4. Manual smoke with `ANTHROPIC_API_KEY` set produces a deputy-flavored bubble within 3 s for a typical utterance, plus an order in the bus.
5. v0.3.0 command system + v0.2.0 squad puppets + v0.1.x hero controls all continue to work (regression).
6. CI green; release.yml succeeds.

## Out of scope (do not introduce)

- Captain Node and CaptainMemory (v0.5.0).
- ArchonController and the second-player input plumbing (v0.5.0).
- Streaming HUD bubble during LLM thinking (later).
- Voice STT / TTS (deferred, spec 08 §10).
- Memory consolidation LLM call wiring (waits for `match_end` event in doc 09).
- `EventBus` autoload (doc 09).
- Order execution by units (doc 09).
- War-room pre-plan authoring UI (doc 10).
