# 07 — Command System Specification

**Status:** design approved 2026-04-27, awaiting implementation plan.
**Vision anchor:** `06-full-gameplay-vision.md` §2.4 (three command tiers), §4 (spatial vocabulary).
**Sibling spec:** `08-ai-deputy-architecture.md` (consumes this schema as the AI tool-calling contract).
**Engine:** Godot 4.6.x. GDScript only.

## 1. Purpose & scope

Vision §2.4 names "the tactical-order schema" as the keystone of the post-MVP architecture:
the single data shape every authored command — pre-plan, in-match tactical, in-match
strategic — flattens into before reaching the executor. Spec 07 defines that shape and
the bus that distributes it. Spec 08 defines the AI side that produces it. Spec 09
defines the executor side that consumes it.

**In scope:**
- `TacticalOrder` Resource — the universal command record.
- `ActionPlan` Resource — the LLM-emitted wrapper that bundles orders with deputy
  reasoning and provenance.
- `CommandBus` autoload — single ingress for all orders/plans.
- `OrderTypeRegistry` autoload — extension point for spec 09 to declare new order
  types without recompiling 07.
- `PrePlan` and `PrePlanRunner` — the war-room artifact format and its runtime
  evaluator (war-room **UI** is doc 10).
- `ControlPolicy` — the access-rule layer that decides who may issue what.
- Spatial-vocabulary glue between 07's targeting fields and the doc 09 entity registry.
- Provenance and replay: every order is traceable to the utterance / pre-plan /
  script that produced it.

**Out of scope:**
- Behavior trees and order *execution* semantics (doc 09).
- LLM provider, prompts, snapshot building, deputy persona files (doc 08).
- War-room UI (doc 10).
- Voice (deferred sub-doc).

## 2. The pipeline (one diagram, two diagram)

```
                            ┌─────────────────────────────┐
   Player utterance ─────►  │ ClassifierRouter (08)       │
   (text/voice/HUD)         │   single LLM tool-call:     │
                            │     submit_plan(json)       │
                            │   returns ActionPlan{       │
                            │     deputy, tier,           │
                            │     rationale, orders[],    │
                            │     ...                     │
                            │   }                         │
                            └────────────┬────────────────┘
                                         │
   PrePlanRunner ─────► submit_orders   ▼
   (event-triggered)        ┌─────────────────────────────┐
                            │ CommandBus (autoload, 07)   │
                            │   validate (schema +        │
                            │             ControlPolicy + │
                            │             target exists)  │
                            │   route to OrderQueue       │
                            │   emit order_issued /       │
                            │        plan_issued signals  │
                            └────────────┬────────────────┘
                                         │
                            ┌────────────▼────────────────┐
                            │ Executor (09)               │
                            │   per-unit/squad behavior   │
                            │   trees consume queue       │
                            └─────────────────────────────┘
```

The bus has exactly two ingress methods: `submit_plan(plan)` (deputies, post-LLM) and
`submit_orders(orders)` (pre-plans, scripted events, dev tools). Anything that issues
commands goes through one of these. No alternative paths.

**Strict A-chain enforcement (vision §2.4):** every player-issued plan addresses the
single Deputy seat. The Deputy decomposes complex plans by re-emitting `submit_plan`
calls with `issuer = DEPUTY` and the target captain's `target_squad_id` (each captain
leads exactly one squad). Captains in turn issue `submit_orders` (not plans) to their
own squad units with `issuer = CAPTAIN`. The bus does not police this hierarchy —
that is `ControlPolicy`'s job (§9) — but the canonical flow is:

```
Player utterance ──► ClassifierRouter ──► submit_plan (issuer=PLAYER, deputy="deputy")
                                          │
                       Deputy.handle_plan ──► submit_plan (issuer=DEPUTY, target_squad_id=captain_id)
                                              │
                          Captain.handle_plan ──► submit_orders (issuer=CAPTAIN, target_unit_ids=[...])
                                                  │
                                            Executor (09)
```

## 3. `TacticalOrder` Resource

```gdscript
class_name TacticalOrder
extends Resource

# --- Identity & classification ---
@export var id: StringName                # unique (UUID-ish), assigned at construction
@export var type_id: StringName = &""     # registered key, e.g. &"move", &"attack"; see §7
@export var origin: Origin                # which vision §2.4 lane authored this
@export var issuer: Issuer                # who reasoned about it
@export var deputy: StringName = &""      # which deputy executes; "" = hero or scripted

enum Origin { PRE_PLAN, TACTICAL_VOICE, STRATEGIC_DECOMPOSITION, SCRIPT, HERO_DIRECT }
enum Issuer { PLAYER, DEPUTY, CAPTAIN, SCRIPT }

# --- Targeting (vision §4 spatial vocabulary) ---
# Tagged-union semantics layered over parallel fields. `target_kind` is the
# canonical discriminator; the matching parallel field carries the value.
@export var target_kind: StringName = &""              # see §3.3 kinds table
@export var target_unit_ids: Array[int] = []
@export var target_squad_id: StringName = &""
@export var target_grid: Vector2i = Vector2i(-1, -1)   # (-1,-1) = unset
@export var target_landmark: StringName = &""
@export var target_position: Vector3 = Vector3.ZERO    # zero vector treated as unset
@export var target_unit_ref: String = ""               # namespaced ref, e.g. "captain:alpha"
@export var target_param: StringName = &""             # pre-plan placeholder, see §8.4
@export var target_ambiguous_candidates: Array[String] = []   # for kind="ambiguous"
# Fallback resolution when target_kind is unset (legacy):
#   target_position > target_landmark > target_grid > target_squad_id > target_unit_ids

# --- Type-specific bag ---
@export var params: Dictionary = {}        # per-type schema documented in OrderTypeRegistry

# --- Engagement modifier (SC2-style stance triad, see §3.5) ---
@export var posture: StringName = &"aggressive"   # aggressive | stand_ground | hold_fire

# --- Queue & lifecycle ---
@export var priority: int = 0              # use PRIORITY_ROUTINE/HIGH/EMERGENCY constants, see §3.7
@export var queue_mode: StringName = &"replace"   # replace | append | insert
@export var timestamp_ms: int = 0
@export var expires_at_ms: int = 0          # 0 = never (per vision §2.4 duration semantics)

# --- AI provenance ---
@export var rationale: String = ""          # micro-rationale; HUD bubbles use plan.rationale primarily
@export var confidence: float = 1.0         # 1.0 = pre-plan/script; <1.0 = LLM-derived
@export var parent_intent_id: StringName = &""  # ActionPlan.id if this came from a plan; "" otherwise

# --- Mutable status (executor writes only; see §4 lifecycle) ---
@export var status: StringName = &"pending"
# Canonical values (8-state lifecycle, linear, no rollback):
#   pending → classifying → dispatched → executing →
#       { completed | failed | canceled | expired }
```

### 3.3 `target_kind` discriminator (tagged-union semantics)

The spatial-vocabulary brainstorm landed on a tagged-union shape (`{kind, value}`) for clarity in LLM tool-call output and for the `ambiguous` case the parallel-fields encoding cannot represent. Implementation keeps the parallel `target_*` fields for backward compatibility and adds `target_kind` as the canonical discriminator.

| `target_kind` | Carrier field | Notes |
|---|---|---|
| `""` (empty) | (legacy fallback chain) | Fallback resolution priority position > landmark > grid > squad > units |
| `position` | `target_position` | World-space coordinate |
| `landmark` | `target_landmark` | Designer-named landmark (resolves via 09 OrderResolver) |
| `grid` | `target_grid` | A1–H8 cell as Vector2i |
| `squad` | `target_squad_id` | Whole squad |
| `units` | `target_unit_ids` | Numeric ids; fast-path for executor |
| `unit_ref` | `target_unit_ref` | Namespaced string, e.g. `captain:alpha`, `enemy_structure:hq_1` |
| `ambiguous` | `target_ambiguous_candidates` | Multiple landmark/region candidates; deputy autonomy (§7 / 08 §11.8) decides resolution |
| `self` | (none) | The deputy itself ("focus on yourself") |
| `hero` | (none) | The commander's hero unit |
| `param` | `target_param` | Pre-plan parametric placeholder, see §8.4 |

### 3.4 `target_unit_ref` namespace

The namespaced string form is preferred for any LLM-emitted reference to a named entity (because the LLM emits text, not numeric ids). Resolver (09) maps to the runtime `target_unit_ids` at execution time.

```
captain:<id>             # named friendly captain
enemy_unit:<id>          # named/identified enemy unit
enemy_structure:<id>     # enemy building
friendly_structure:<id>  # friendly building
```

Anonymous regulars are addressed via `squad`, `grid`, or `landmark`, never directly by `unit_ref`.

### 3.5 `posture` — SC2-style stance triad

Three values, copied from Starcraft 2:

- `aggressive` — pursue and engage enemies in range
- `stand_ground` — hold position, return fire only, do not chase
- `hold_fire` — do not engage even if attacked

Posture modifies engagement rules during execution of any verb. It is orthogonal to `type_id`: a `defend B4 + aggressive` and a `defend B4 + stand_ground` are both valid and meaningfully different. Default `aggressive`.

### 3.6 `priority` — three semantic anchors

`priority: int` stays open-integer for future growth, but the canonical values to use:

| Constant | Value | Meaning |
|---|---|---|
| `PRIORITY_ROUTINE` | 0 | Default. Same-priority on same captain replaces existing (existing → `canceled`). |
| `PRIORITY_HIGH` | 10 | Interrupts any `routine` command immediately. |
| `PRIORITY_EMERGENCY` | 20 | Interrupts both `routine` and `high`; deputy may reallocate across captains to comply. |

Sub-commands generated by deputy decomposition inherit parent priority unless explicitly overridden.

### 3.7 `parent_intent_id` and command tree

When the strategic LLM decomposes intent into multiple sub-orders, all share the parent `ActionPlan.id`. Deputy → captain fan-out also uses `parent_intent_id`. Replay, HUD aggregation ("3 of 5 sub-commands complete"), and post-match analysis all key off this tree. The lifecycle state machine (§4) operates on individual orders; aggregate states for UI are derived.

Methods on `TacticalOrder`:

```gdscript
func to_dict() -> Dictionary       # Resource → JSON-friendly dict, for LLM I/O & save state
static func from_dict(d: Dictionary) -> TacticalOrder
func is_targeted() -> bool          # true if any targeting field is set
func is_expired(now_ms: int) -> bool
```

**Field-set rationale:**
- `type_id` is a `StringName` not an `enum` — see §7. The MVP enum we built in Phase C
  for `SquadUnit.order_*` is method-level direct dispatch and is *not* the same thing;
  `type_id` is the registry key.
- `target_position` and `target_landmark` accept *either* — landmark is named-resolved
  to a position by `OrderResolver`, an executor-side helper (doc 09). 07 only stores;
  09 resolves.
- `parent_intent_id` is the plan's `id`. This makes it trivial to re-render the plan
  → orders relationship for HUD or replay.
- `status` is the only mutable field. The bus refuses to accept already-mutated
  Resources (incoming `status` must be `&"pending"`).

## 4. Lifecycle state machine

Eight states, linear with terminal branching. No rollback — once a state advances it cannot revert. Re-dispatching to a different captain is modeled as `cancel + new submit` with `parent_intent_id` linking, not as a backward transition.

```
                                              ┌→ completed
                                              │
[pending] → [classifying] → [dispatched] → [executing] ┼→ failed
                                              │
                                              ├→ canceled
                                              │
                                              └→ expired
```

| State | Meaning |
|---|---|
| `pending` | Resource constructed, `id` assigned, awaiting validation/routing |
| `classifying` | LLM call in flight (tactical or strategic). Pre-plan and script orders skip this. |
| `dispatched` | Bus-validated, routed to deputy/captain, awaiting executor pickup |
| `executing` | Behavior tree (09) is acting on it |
| `completed` | Terminal: success |
| `failed` | Terminal: unrecoverable error during execution |
| `canceled` | Terminal: superseded by player or higher-priority command |
| `expired` | Terminal: `expires_at_ms` elapsed; captain reverts to default behavior, no player notification |

**Transition rules:**
- Each transition emits `command_status_changed(order_id, new_state)` on `CommandBus`.
- A `canceled` transition while still in `classifying` (e.g. player retracts before LLM finishes) is permitted; the LLM result is discarded on arrival.
- Pre-plan orders go directly `pending → dispatched` (skip `classifying`).
- Strategic orders may sit in `classifying` for several seconds during LLM decomposition.

**Migration from MVP `CommandLogModel`:** the legacy three-state model (`submitted` / `received` / `pending_execution`) maps as `submitted→pending`, `received→dispatched`, `pending_execution→executing`. The new states (`classifying`, `completed`, `failed`, `canceled`, `expired`) are additive.

## 5. `ActionPlan` Resource

```gdscript
class_name ActionPlan
extends Resource

enum Tier { TACTICAL, STRATEGIC }    # PRE_PLAN does NOT go through ActionPlan; it
                                     # calls CommandBus.submit_orders directly.

@export var id: StringName
@export var deputy: StringName              # combat | economy
@export var tier: Tier
@export var rationale: String               # plan-level "why" — the HUD bubble text
@export var confidence: float = 1.0
@export var orders: Array[TacticalOrder] = []
@export var triggering_utterance: String = ""   # raw player text/transcribed voice
@export var timestamp_ms: int = 0

func to_dict() -> Dictionary
static func from_dict(d: Dictionary) -> ActionPlan
```

Constraints:
- Every order in `orders[]` must have its `parent_intent_id == this.id` and its
  `origin == TACTICAL_VOICE` (when `tier == TACTICAL`) or
  `STRATEGIC_DECOMPOSITION` (when `tier == STRATEGIC`).
- `deputy` must match every order's `deputy` field (a plan does not address two
  deputies; if the player utterance straddles, the classifier-router emits two
  `ActionPlan`s).
- Deserialization sets these invariants automatically; constructors should fail
  loudly when LLM output violates them.

## 6. `CommandBus` autoload

```gdscript
class_name CommandBus
extends Node     # autoload

signal plan_issued(plan: ActionPlan)
signal order_issued(order: TacticalOrder)
signal order_rejected(order: TacticalOrder, reason: StringName)

# Ingress
func submit_plan(plan: ActionPlan) -> Dictionary
    # returns { accepted: Array[TacticalOrder], rejected: Array[Dictionary] }
    # Validates plan invariants (§5) then forwards to submit_orders.

func submit_orders(orders: Array[TacticalOrder]) -> Dictionary
    # for pre-plan, script, hero-direct, dev tools.
    # Validates each order against:
    #   1. schema (id present, type_id registered, origin valid)
    #   2. ControlPolicy (issuer is permitted to issue this type)
    #   3. target existence (unit_ids resolve, landmark known, etc.)
    # On failure, the order is queued in the rejected[] with a reason StringName.

# Read
func get_recent_plans(limit: int = 20) -> Array[ActionPlan]
func get_recent_orders(limit: int = 50) -> Array[TacticalOrder]
```

The bus owns:
- An in-memory ring buffer of recent plans / orders for HUD + replay.
- `ControlPolicy` reference (defaults to `FullControl`; vision-mode can swap to
  `HeroOnly` / `AssistMode` per §8 of `03-godot-rts-architecture-reference.md`).
- Order-log persistence to `user://order_log/<match_id>.ndjson` for replay.

The bus does **not** own:
- Order *queues* per unit. It hands the validated order to whichever executor module
  the order's targeting resolves to. The queue is doc 09's concern.
- Behavior tree state, retry logic, target re-acquisition. Doc 09.

### Validation order (fail fast)

```gdscript
1. order.status must be "pending"
2. order.id must be unique vs recent buffer
3. order.type_id must be registered in OrderTypeRegistry
4. params must satisfy registry's per-type schema
5. ControlPolicy.can_issue(order.issuer, order.deputy, order.type_id)
6. Targeting must resolve (at least one of position/landmark/grid/squad/units valid)
```

First failure short-circuits with a stable reason `StringName` (e.g.
`&"unknown_type_id"`, `&"control_policy_denied"`, `&"target_not_found"`).

## 7. `OrderTypeRegistry` autoload

```gdscript
class_name OrderTypeRegistry
extends Node

class TypeDef:
    var id: StringName
    var description: String
    var param_schema: Dictionary       # {key: type_string, ...}
    var allowed_deputies: Array[StringName] = []   # empty = any
    var min_targets: int = 1
    var max_targets: int = -1           # -1 = unlimited

func register(type_def: TypeDef) -> void
func get_def(id: StringName) -> TypeDef
func validate_params(id: StringName, params: Dictionary) -> Dictionary  # {ok: bool, missing: [], extra: []}
func list_for_deputy(deputy: StringName) -> Array[StringName]
```

v1 ships with a small core registered at autoload boot:

```
move          target: position|landmark|grid|squad|units
attack        target: units
stop          target: squad|units
hold          target: squad|units
use_skill     params: {skill_id: StringName, ...}
```

Doc 09 extends this with `gather`, `return_cargo`, `build`, `train`, `research`, etc.,
without touching 07.

## 8. Pre-plan format

```gdscript
class_name PrePlan
extends Resource

@export var name: String
@export var deputy: StringName              # combat | economy
@export var trigger: PrePlanTrigger
@export var orders: Array[TacticalOrder]    # all with origin = PRE_PLAN
@export var enabled: bool = true

class_name PrePlanTrigger
extends Resource

@export var event: StringName               # event the runner subscribes to
@export var conditions: Dictionary = {}     # interpreted per-event by PrePlanRunner
```

`PrePlanRunner` is a `Node` instantiated by `bootstrap.gd`:
- Loads all `*.tres` PrePlan resources from a designer-controlled folder
  (e.g. `user://preplans/` for player-authored, `res://data/preplans/` for shipped).
- Subscribes to `EventBus` per `trigger.event`.
- On match, evaluates `conditions` (a small pure-data DSL — no scripting).
- On match, calls `CommandBus.submit_orders(plan.orders)` and disables the plan
  if `trigger.conditions.repeat == false` (default).

The pre-plan **DSL is intentionally tiny** for v1:
```
conditions: {
  within_seconds_of_start: 60,        # event must fire within first 60s
  enemy_count_at_least: 3,            # gate on visible enemy count
  player_resource_below: { mineral: 100 },
  cooldown_seconds: 30                # if repeat=true
}
```
Anything not in this list is ignored. Doc 10 (war-room UI) can extend the DSL with
authoring guardrails.

### 8.4 Parametric placeholders

Pre-plan orders may reference values resolved at trigger time rather than at authoring time. These let one plan be re-usable across different match starts (mirror map, randomized spawns, etc.). Placeholders are written as the plan order's `target_kind = &"param"` plus `target_param = &"<placeholder_name>"`.

The four supported placeholders:

| Placeholder | Resolves to |
|---|---|
| `<my_main_base>` | The main base structure of the player's faction at trigger time |
| `<closest_enemy_base>` | Nearest known enemy base from the player's hero position |
| `<hero_position>` | The current grid cell of the hero |
| `<deputy_focus>` | The deputy's current attention focus (08 §7 specifies how this is computed) |

These are the **only** placeholders allowed. No general expression language. If a pre-plan needs richer runtime logic, the player should author it as a strategic intent (LLM-driven) at authoring time instead of as a structured pre-plan.

`PrePlanRunner` resolves placeholders to concrete `target_*` values immediately before calling `CommandBus.submit_orders`. The resolved orders carry the new values, not the placeholders, so the bus and downstream replay see deterministic targeting.

### 8.5 Share codes (deferred implementation)

Pre-plans are shareable via opaque alphanumeric codes. The share-code subsystem:

- Encodes a `PrePlan` resource (and any required private regions) into a base32 / base58 string
- Validates on import: schema version must match; bound map must be a known map; private regions are imported into the importing player's region set with conflict resolution (rename on collision)
- Versioning: codes carry a schema version prefix so old codes can be rejected with a useful error rather than mis-interpreted
- v1 ships only the validation hooks and a schema-version field on `PrePlan`; the encoder/decoder is a separate task

The share-code feature is the social surface of the war-room — designed in 07 so the resource format doesn't have to be re-thought when it ships. Implementation is deferred; doc 10 (war-room UI) will surface the import/export UI when the encoder/decoder lands.

## 9. `ControlPolicy`

A small interface; default impl is `FullControl` (no restrictions):

```gdscript
class_name ControlPolicy
extends RefCounted

func can_issue(issuer: TacticalOrder.Issuer,
               deputy: StringName,
               type_id: StringName) -> bool
```

v1 ships four policies:
- `FullControlPolicy` — accept everything (default for development).
- `HeroOnlyPolicy` — player can only issue `origin = HERO_DIRECT`; deputies' plans
  rejected. Used for "I want to play a pure RTS" mode.
- `AssistModePolicy` — accept deputy plans but log them as "suggestion only" and
  don't dispatch. Used for tutorial / training.
- `ArchonControlPolicy` — vision §2.5 archon mode. Identical to `FullControl` but
  **rejects** any plan whose `deputy == archon_attached_seat` and `issuer != PLAYER`.
  In other words, when a human is wearing the deputy seat, the LLM Deputy's plans
  for that seat are denied with reason `&"archon_attached"`. Doc 08 §11.7 owns the
  attach/detach lifecycle; 07 owns this policy implementation.

Vision §2.5 hints the player picks the policy via Settings; that's doc 10's HUD work.
07 only owns the interface and its four implementations.

## 10. Provenance & replay

Every accepted order is appended to `user://order_log/<match_id>.ndjson` with
`to_dict()` plus `accepted_at_ms`. Every rejected order goes to a sibling
`<match_id>.rejected.ndjson`. Plans serialize to a sibling `.plans.ndjson`.

This trio is the input format for:
- HUD replay overlay (doc 10).
- Deputy training data extraction (doc 08, future iterations).
- Bug repro: `--replay <match_id>` boot mode reissues every accepted order at
  recorded timestamps. (Stretch — doc 12 territory.)

## 11. Spatial-vocabulary integration

Doc 06 §4 introduces three layers:
1. **Grid** — A1..H8 letterbox map (e.g. 16x16 cells across the playfield).
2. **Designer landmarks** — named keypoints loaded from a Resource registry.
3. **Player-named regions** — *deferred to v1+1*; field omitted from `TacticalOrder`.

`OrderResolver` (doc 09) is the executor-side helper that turns a partially-targeted
order into a concrete world position:

```gdscript
func resolve_target(order: TacticalOrder, world: Node3D) -> Vector3
```

Spec 07 only needs to declare the *shape* of the targeting fields; spec 09 owns the
resolution logic (handles "what if the landmark moved?", "what if a unit died between
plan emit and execution?").

## 12. Boundaries

- **07 ↔ 08:** `ActionPlan` is the LLM tool's structured-output shape. The tool's
  JSON schema is generated from `ActionPlan.to_dict()` keys + `OrderTypeRegistry`
  param shapes. 08 owns the LLM client; 07 owns the data classes the client emits.
- **07 ↔ 09:** Orders flow into 09 via `order_issued` signal. 09 attaches behavior
  trees per-unit/squad that consume the order's `params` and `target_*` fields.
  Doc 09 declares its types via `OrderTypeRegistry.register()` at boot.
- **07 ↔ 10:** War-room UI authors `PrePlan` resources by serializing to `.tres`.
  HUD overlay reads `CommandBus.get_recent_plans()` to render bubbles.
- **07 ↔ 12:** The `.ndjson` order log is replayable by 12's test harness; replays
  push a deterministic stream into `submit_orders()`.

## 13. Files

### New files (this spec defines)
- `godot/scripts/command/tactical_order.gd` — `TacticalOrder` Resource.
- `godot/scripts/command/action_plan.gd` — `ActionPlan` Resource.
- `godot/scripts/command/command_bus.gd` — autoload.
- `godot/scripts/command/order_type_registry.gd` — autoload.
- `godot/scripts/command/control_policy.gd` — interface + 3 impls.
- `godot/scripts/command/pre_plan.gd` — `PrePlan` and `PrePlanTrigger` Resources.
- `godot/scripts/command/pre_plan_runner.gd` — Node, instantiated by bootstrap.
- `godot/data/preplans/` — folder for shipped pre-plans (sample only at first).
- `godot/tests/test_tactical_order.gd` — to_dict/from_dict round-trip; targeting
  precedence; expiry.
- `godot/tests/test_action_plan.gd` — invariants (deputy match, parent_intent_id
  fill, tier↔origin consistency).
- `godot/tests/test_command_bus.gd` — validation order, accepted/rejected split,
  signals, ring buffer.
- `godot/tests/test_order_type_registry.gd` — register/validate_params/list.
- `godot/tests/test_pre_plan_runner.gd` — trigger evaluation, repeat semantics,
  cooldown.

### Modified files
- `godot/project.godot` — register `CommandBus` and `OrderTypeRegistry` as autoloads.
- `godot/scripts/bootstrap.gd` — instantiate `PrePlanRunner` and load shipped
  pre-plans.
- `docs/specs/05-godot-smoke-test-checklist.md` — extend with command-system
  smoke section after the implementation lands.

## 14. Verification (skeleton)

A 07 implementation is "skeleton-complete" when:
1. All Resources / autoloads / runner classes parse without error in headless boot.
2. GUT: every test file in §13 passes.
3. A trivial integration test: `submit_orders([move_to_grid_a3])` makes the
   `order_issued` signal fire with the matching order, and the order appears in
   `get_recent_orders()`.
4. A trivial pre-plan integration test: a sample `.tres` with
   `trigger.event = "match_start"` issues its orders via the bus on match start;
   they appear in the recent buffer.
5. Headless run produces an `.ndjson` log file under `user://order_log/`.
6. Doc 08's later "submit_plan" call (mocked LLM output) round-trips through
   `submit_plan` → `order_issued` per order.

The order *executes nothing* in 07-only land. Doc 09 provides actual movement /
attack execution. Until 09 lands, all orders sit in `pending` forever; that is
expected and not a 07 bug.
