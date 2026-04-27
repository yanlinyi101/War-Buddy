# 08 — AI Deputy Architecture

**Status:** design approved 2026-04-27, awaiting implementation plan.
**Vision anchor:** `06-full-gameplay-vision.md` §2.2 (two deputies), §2.3 (deputy as
character), §2.4 (three command tiers).
**Sibling spec:** `07-command-system.md` (consumer of this spec's `ActionPlan` output).
**Engine:** Godot 4.6.x + LLM provider HTTPS (Anthropic Messages API default).

## 1. Purpose & scope

Vision §2.2 says the player commands two deputies — a combat squad leader and an
economy officer — and §2.3 names "deputy as character" as a co-equal pillar with the
RTS gameplay loop. Spec 08 defines the AI side: how a player utterance becomes a
validated `ActionPlan` (07's keystone artifact), where the LLM lives, what the
deputy "sees", what persists across matches, and how a deputy's personality is
specified so two deputies feel different.

**In scope:**
- `Deputy` Node — the per-deputy runtime entity (one for combat, one for economy).
- `ClassifierRouter` — the single LLM tool-call front door that turns an utterance
  into an `ActionPlan`.
- `DeputyLLMClient` interface + `AnthropicClient` default implementation.
- `BattlefieldSnapshotBuilder` — produces the cropped observation passed to the LLM.
- Tier latency policy (vision §2.4).
- `DeputyMemory` Resource and `MemoryStore` autoload — cross-match persistence
  (vision §2.3 character pillar).
- `DeputyPersona` Resource — name, archetype, voice style, system-prompt template,
  trait scalars, quirks.
- `Deputy.speak(text)` interface for HUD bubbles; voice TTS wired later.
- Failure modes and fallbacks (timeout, network down, LLM hallucination, schema
  violation).

**Out of scope:**
- Schema for `ActionPlan` / `TacticalOrder` (doc 07).
- Behavior tree execution of orders (doc 09).
- War-room UI for pre-plan authoring (doc 10).
- Voice STT/TTS pipeline — deferred to a sub-doc (likely 08.1) or doc 11. v1
  is text-only.
- Deputy "growth" as game mechanic (deputy gets numerically stronger with use) —
  vision §2.3 describes it but the design is doc 08+1.

## 2. Pipeline (player utterance → orders)

```
   ┌──────────────────────────────────────────────────────────────┐
   │ HUD CommandPanel                                             │
   │   user types/speaks "我们去打中路"                            │
   └────────────────────┬─────────────────────────────────────────┘
                        │ utterance_submitted(text, source)
                        ▼
   ┌──────────────────────────────────────────────────────────────┐
   │ ClassifierRouter                                             │
   │   build snapshot via BattlefieldSnapshotBuilder              │
   │   pick which deputy to address (or both)                     │
   │   call DeputyLLMClient.submit_plan(                          │
   │     persona = combat_persona,                                │
   │     memory = combat_memory_snapshot,                         │
   │     observation = snapshot,                                  │
   │     utterance = "我们去打中路"                                │
   │   )                                                          │
   │   await Anthropic Messages API                               │
   │   parse single tool-call → ActionPlan                        │
   └────────────────────┬─────────────────────────────────────────┘
                        │ plan
                        ▼
   ┌──────────────────────────────────────────────────────────────┐
   │ Deputy.handle_plan(plan)                                     │
   │   validate against persona's allowed type set                │
   │   call CommandBus.submit_plan(plan)  ─── (07)                │
   │   speak(plan.rationale) → HUD bubble                         │
   │   write plan.id to short-term memory                         │
   └──────────────────────────────────────────────────────────────┘
```

A single utterance produces *zero or more* `ActionPlan`s. The classifier-router can:
- Issue **one** plan to one deputy (typical case).
- Issue **two** plans, one per deputy (utterance straddled both).
- Issue **zero** plans (utterance was conversational, e.g. "good job"). The deputy
  still speaks but emits no orders.

## 3. `Deputy` Node

```gdscript
class_name Deputy
extends Node

signal spoke(text: String, deputy_id: StringName)
signal plan_received(plan: ActionPlan)
signal plan_failed(reason: StringName, details: Dictionary)

@export var deputy_id: StringName            # &"combat" or &"economy"
@export var persona: DeputyPersona

var memory: DeputyMemory = null
var _short_term: Array[ActionPlan] = []      # last N plans this match

func bind_memory(m: DeputyMemory) -> void    # bootstrap calls this with MemoryStore.load(deputy_id)
func handle_plan(plan: ActionPlan) -> void
func speak(text: String) -> void             # emits `spoke`; HUD subscribes
func snapshot_short_term() -> Dictionary     # for prompt injection
```

The `Deputy` does **not** hold its own `DeputyLLMClient` — only `ClassifierRouter` and
`MemoryStore` (during consolidation) need the client. The `Deputy` is a thin
character-and-validation layer between `ClassifierRouter`'s LLM output and the
`CommandBus`. Persona-level filtering (allowed type ids, refusal patterns) happens
in `handle_plan` before forwarding to the bus.

Two `Deputy` instances are added to the scene tree by `bootstrap.gd` (or by an
autoload `DeputyRegistry` if convenient): one with `deputy_id = &"combat"`, one with
`deputy_id = &"economy"`. Both are addressed by the same `ClassifierRouter` (which
holds the single `DeputyLLMClient`) but receive different personas and different
memories.

`bootstrap.gd` also subscribes to `MatchState.victory_triggered` /
`match_lost` (when 09 introduces it) and calls
`MemoryStore.consolidate_after_match(deputy_id, summary, llm_client)` for each
deputy at end-of-match — the only cross-match write site.

## 4. `ClassifierRouter`

```gdscript
class_name ClassifierRouter
extends Node

signal plan_emitted(plan: ActionPlan)
signal classification_failed(utterance: String, reason: StringName)

func handle_utterance(text: String, source: StringName) -> void
    # source = &"text_input" | &"voice" | &"dev_console"
    # 1. build snapshot
    # 2. pick deputy candidate set (default: both — let LLM decide which to address)
    # 3. call llm_client.submit_plan() once
    # 4. on response:
    #      for each plan in plans:
    #          deputy = registry.get(plan.deputy)
    #          deputy.handle_plan(plan)
    #          plan_emitted.emit(plan)
    # 5. on timeout/error: classification_failed.emit + each addressed deputy
    #    speaks a fallback line ("嗯…脑子转不动，你再说一次？")
```

The router never issues orders directly. It only routes plans into the right
`Deputy`, which in turn pushes to the `CommandBus`. This keeps deputy persona
filters between LLM output and order dispatch.

## 5. `DeputyLLMClient` interface

```gdscript
class_name DeputyLLMClient
extends RefCounted

# All implementations are async via Godot's `await`.
func submit_plan(req: SubmitPlanRequest) -> SubmitPlanResponse:
    push_error("abstract")
    return null

class_name SubmitPlanRequest
extends RefCounted
var persona: DeputyPersona
var memory_snapshot: Dictionary       # output of MemoryStore.snapshot_for(deputy_id)
var observation: Dictionary           # battlefield snapshot
var utterance: String
var tier_hint: StringName = &""       # &"" | &"tactical" | &"strategic"  (optional player tag)
var timeout_seconds: float = 5.0
var available_type_ids: Array[StringName] = []   # filled from OrderTypeRegistry

class_name SubmitPlanResponse
extends RefCounted
var plans: Array[ActionPlan] = []
var raw_text: String = ""             # the deputy's "speech" if no orders emitted
var error: StringName = &""           # &"" | &"timeout" | &"network" | &"schema_violation" | &"refusal"
var elapsed_seconds: float = 0.0
var token_usage: Dictionary = {}      # {input, output} for cost telemetry
```

### v1 implementations

- `AnthropicClient` (default): `HTTPRequest` node + Anthropic Messages API,
  tool-use enabled. Single tool: `submit_plan` with the JSON schema generated from
  `ActionPlan.to_dict()` + `OrderTypeRegistry`. `ANTHROPIC_API_KEY` env var.
  Model: `claude-sonnet-4-5-20250929` or current latest sonnet (configured per
  persona).
- `OllamaClient` (dev): same interface, points at local `http://localhost:11434`,
  uses an OpenAI-compatible tool-use shim. For free dev/testing.
- `RelayClient` (ship — deferred): same interface, points at our own backend that
  proxies to provider. v1 stubs this with NotImplementedError; the binding lives so
  doc 08 doesn't have to be revisited at ship time.

The client never sees `Deputy` or `CommandBus`. It is a pure I/O wrapper.

## 6. Tier & latency policy

Vision §2.4:

| Tier | Soft timeout | Hard timeout | Behavior on miss |
|---|---|---|---|
| Tactical | 2 s | 5 s | Deputy speaks "嗯…等等"; emit empty plan; player utterance logged for retry |
| Strategic | 10 s | 30 s | Same as above, but with a longer "thinking..." ellipsis bubble that ticks visibly |
| Pre-plan | n/a | n/a | Pure local — no LLM call. Latency = next physics tick. |

Tier is decided **inside the LLM call**: the model emits `tier` as part of
`ActionPlan`. The router doesn't pre-classify. This means a single API call always
runs with the strategic timeout budget (30s hard) — the model just commits to its
chosen tier in the response. If we observe the model wasting strategic latency on
trivial utterances, a small pre-classifier (rule-based regex or a tiny model like
`claude-haiku`) gets added in 08+1.

**Streaming:** Anthropic supports SSE. The HUD bubble shows tokens as they arrive
when the deputy chooses to "narrate" before committing the tool-call. This is
purely cosmetic (the orders only land when the tool-call finalizes), but it is
critical for the character pillar: the player sees the deputy thinking.

## 7. `BattlefieldSnapshotBuilder`

```gdscript
class_name BattlefieldSnapshotBuilder
extends Node

func build_for(deputy_id: StringName, tier_hint: StringName = &"") -> Dictionary
```

Output shape (every key required, order stable for caching):

```jsonc
{
  "match_meta": {
    "tick": 12345,
    "elapsed_s": 240,
    "score": { "buildings_killed": 1, "units_lost": 0 }
  },
  "you": {
    "deputy_id": "combat",
    "last_plan_id": "plan_42",
    "recent_orders": [
      // last 5 orders this deputy issued, summarized
      { "id": "ord_120", "type": "move", "status": "executing", "elapsed_s": 3 }
    ]
  },
  "units": [
    // friendly units the deputy commands; cropped per tier
    { "id": 1001, "kind": "squad_unit", "pos_grid": "C4", "hp_pct": 1.0,
      "squad_id": "alpha", "current_order_type": "move" }
  ],
  "enemies": [
    // visible enemies; cropped to last-known-position for fog-aware tiers
    { "id": 2001, "kind": "enemy_building", "pos_grid": "F6", "hp_pct": 0.6,
      "last_seen_tick": 12300 }
  ],
  "recent_events": [
    // last 10 EventBus events, normalized
    { "tick": 12340, "type": "unit_died", "subject": 1003 }
  ],
  "player_signals": {
    "last_utterance": "我们去打中路",
    "mouse_focus_grid": "D5",
    "selected_landmark": null
  },
  "available_orders": [
    // from OrderTypeRegistry.list_for_deputy("combat")
    "move", "attack", "stop", "hold", "use_skill"
  ]
}
```

Cropping rules:
- **Tactical hint:** only units within a 3-grid radius of the player's mouse focus
  or last interacted unit, plus all enemies within attack range of those.
- **Strategic hint:** all units the deputy commands + all visible enemies +
  match-wide score summary.
- **Empty hint (default):** strategic crop (LLM picks tier from full context).

The builder reads only from the (future) `GameState` autoload; it never reaches
into individual node trees. Until `GameState` lands (doc 09), the v1 stub queries
the scene tree directly via groups (`squad_units`, `enemy_buildings`, etc.).

## 8. `DeputyMemory` & `MemoryStore`

```gdscript
class_name DeputyMemory
extends Resource

@export var deputy_id: StringName
@export var total_matches: int = 0
@export var wins: int = 0
@export var losses: int = 0
@export var hours_played: float = 0.0
@export var relationship_traits: Dictionary = {}   # StringName -> float in [-1, 1]
    # examples:
    #   trust:        does the deputy think the player commands competently
    #   frustration:  does the player ignore the deputy's advice
    #   bond:         shared-victory affinity
@export var match_anecdotes: Array[String] = []    # 0-12 short, deputy-flavored memories
@export var preferred_phrases: Array[String] = []  # phrases the deputy has adopted from the player
@export var schema_version: int = 1                # for migration
```

```gdscript
class_name MemoryStore
extends Node     # autoload

func load(deputy_id: StringName) -> DeputyMemory   # returns a default if missing
func save(memory: DeputyMemory) -> void
func snapshot_for(deputy_id: StringName) -> Dictionary
    # JSON-friendly dict for prompt injection — strips internal-only fields
func consolidate_after_match(deputy_id: StringName,
                              match_summary: Dictionary,
                              llm_client: DeputyLLMClient) -> void
    # Optional LLM call: summarize this match into an anecdote, decay traits
    # toward equilibrium, prune anecdotes if >12.
```

Memory file path: `user://deputies/<deputy_id>.tres`.

**Match-time invariants:**
- Memory is loaded at match start, snapshotted into prompts, and **never
  written to during a match**. This prevents in-flight LLM responses from
  poisoning persistent state.
- `consolidate_after_match` is called once when the match ends, after victory
  / defeat is committed. This is the only mutation point. It can itself call
  the LLM (a smaller "memory consolidation" model, e.g. `claude-haiku`).

**Anecdote authoring** is itself an LLM call with a tight system prompt:
> "You are summarizing this match for the deputy's diary. Output ≤ 80 chars,
> in-character, written from the deputy's perspective. No game stats."

## 9. `DeputyPersona`

```gdscript
class_name DeputyPersona
extends Resource

@export var persona_id: StringName
@export var display_name: String
@export var archetype: StringName               # &"veteran" | &"aggressive" | &"econ_nerd" | ...
@export var voice_style: String                 # short style guide, used in prompts
@export var system_prompt_template: String      # has {{traits}}, {{memory}}, {{snapshot}} slots
@export var priority_traits: Dictionary = {}    # {aggression: 0.7, caution: 0.3, ...}
@export var quirks: Array[String] = []          # short colorful tics
@export var allowed_type_ids: Array[StringName] = []   # subset of OrderTypeRegistry
@export var refusal_patterns: Array[String] = []       # things this deputy won't do, in-character
@export var preferred_model: StringName = &"claude-sonnet-4-5-20250929"
@export var consolidation_model: StringName = &"claude-haiku-4-20251022"
```

v1 ships three personas as `.tres`:
- `combat_veteran.tres` — calm, terse, uses chess metaphors, refuses suicide
  charges.
- `combat_aggro.tres` — bold, profane, tolerates losses for tempo.
- `economy_nerd.tres` — pedantic, optimistic about long-term, suspicious of
  early aggression.

Persona is selected at match-start (doc 10's lobby), defaults to `combat_veteran`
+ `economy_nerd`.

The system prompt is assembled per-call:

```
{{persona.system_prompt_template
  .replace("{{traits}}", json(persona.priority_traits))
  .replace("{{memory}}", json(memory.snapshot_for(deputy_id)))
  .replace("{{quirks}}", join(persona.quirks, "\n  - "))
  .replace("{{allowed_orders}}", join(persona.allowed_type_ids, ", "))
}}
```

Memory and snapshot are passed as separate `messages` rather than baked into the
system prompt — this lets Anthropic prompt-cache the persona system prompt across
many calls within a match (cost reduction).

## 10. Voice (deferred)

The `Deputy.speak(text)` interface is the seam. v1 implementation: emit `spoke`
signal; HUD `MessageBubbleHud` listens, shows text bubble, fades out.

Future doc 08+1 (or doc 11) replaces the bubble with TTS:
- Add `voice_id` to `DeputyPersona`.
- Add `TTSClient` interface; default impl pipes to ElevenLabs / OpenAI TTS / local
  Coqui depending on persona's `voice_id`.
- HUD bubble remains as a transcription overlay.

Inbound voice (STT → utterance) similarly slots in upstream of `ClassifierRouter.
handle_utterance` without changing the interface.

## 11. Failure modes

| Failure | Detection | Reaction |
|---|---|---|
| LLM timeout | `await` exceeds tier hard timeout | Deputy speaks fallback ("脑子转不动…"), emits empty plan, logs retry intent |
| Network unreachable | `HTTPRequest` error code | Deputy speaks offline-ish line per persona, persists utterance to retry queue |
| Tool-call schema violation | `ActionPlan.from_dict` raises | Deputy speaks "我没听懂", logs raw response to `user://llm_dropouts/`, retries with corrective system message (1 retry max) |
| Order rejected by `CommandBus` | `submit_plan` returns rejected[] | Deputy speaks rejection rationale ("不行，那个目标已经死了"), removes rejected orders from short-term memory |
| LLM output references unknown unit/landmark | `target_*` resolution fails in 09 | 09 emits `order_failed`; deputy listens, speaks "他们已经不在那儿了", may issue replan |
| LLM refuses (safety / content filter) | response field flagged | Deputy speaks "我不能那样做" in-character, no plan emitted |
| Hallucinated `type_id` not in registry | `OrderTypeRegistry.get_def` returns null | Order rejected at bus; same path as previous row |

Every failure path produces a `[RTSMVP] Deputy <id> failure: <kind>` log line and a
HUD bubble. No silent failures.

## 12. Boundaries

- **08 ↔ 07:** `Deputy.handle_plan` calls `CommandBus.submit_plan`. Spec 08 imports
  no other 07 internals.
- **08 ↔ 09:** `BattlefieldSnapshotBuilder` reads from doc 09's `GameState`
  (or, in v1, group queries). 08 listens to 09's `order_failed` signal to drive
  replans.
- **08 ↔ 10:** Persona selection UI, memory inspector, and HUD bubble rendering
  live in doc 10. 08 only emits `spoke` and exposes `DeputyMemory` for read.
- **08 ↔ 12:** Replay must support `replay_mode = true` that disables LLM calls
  and replays recorded plans from order log. `DeputyLLMClient` gets a `MockClient`
  used during replay; same interface.

## 13. Files

### New files
- `godot/scripts/ai/deputy.gd`
- `godot/scripts/ai/classifier_router.gd`
- `godot/scripts/ai/deputy_llm_client.gd` — base interface
- `godot/scripts/ai/anthropic_client.gd`
- `godot/scripts/ai/ollama_client.gd`
- `godot/scripts/ai/relay_client.gd` — stub
- `godot/scripts/ai/mock_client.gd` — for replay/tests
- `godot/scripts/ai/battlefield_snapshot_builder.gd`
- `godot/scripts/ai/deputy_memory.gd` — Resource
- `godot/scripts/ai/memory_store.gd` — autoload
- `godot/scripts/ai/deputy_persona.gd` — Resource
- `godot/data/personas/combat_veteran.tres`
- `godot/data/personas/combat_aggro.tres`
- `godot/data/personas/economy_nerd.tres`
- `godot/tests/test_classifier_router.gd` — uses `MockClient`
- `godot/tests/test_deputy.gd` — handle_plan validation, speak signal
- `godot/tests/test_battlefield_snapshot_builder.gd`
- `godot/tests/test_deputy_memory.gd` — load/save/migrate
- `godot/tests/test_anthropic_client.gd` — only with `ANTHROPIC_API_KEY`
  set; CI skips by default

### Modified files
- `godot/project.godot` — register `MemoryStore` autoload.
- `godot/scripts/bootstrap.gd` — instantiate `ClassifierRouter`, two `Deputy`
  instances with default personas, wire `HudRoot` ↔ `Deputy.spoke`.
- `godot/scripts/hud_root.gd` — add `MessageBubbleHud` (deputy bubbles) and a
  text input route to `ClassifierRouter.handle_utterance`.
- `godot/scenes/main.tscn` — add `MessageBubbleHud` Control under `HudRoot`.
- `docs/specs/05-godot-smoke-test-checklist.md` — extend with deputy-pipeline
  smoke section after implementation.
- `CHANGELOG.md` — version entry when impl ships.

## 14. Verification (skeleton)

08 is "skeleton-complete" when:
1. All Resources / autoloads / nodes parse without error in headless boot.
2. GUT tests in §13 pass (with `MockClient` standing in for live LLM).
3. With `ANTHROPIC_API_KEY` exported, a manual smoke: type "我们去打中路" in HUD,
   see deputy bubble appear, see `plan_issued` signal on `CommandBus` carrying
   a syntactically valid `ActionPlan`. Orders won't execute (doc 09 not done) —
   that's expected.
4. `MemoryStore` survives a match cycle: start match → consolidate_after_match
   stub → next match's prompt includes `total_matches=1`.
5. Persona swap visibly changes deputy's bubble voice (manual, eyeball test).
6. Forced timeout (set hard timeout to 0.1s) produces the fallback bubble and
   no plan emitted.

## 15. Cost & telemetry

Each LLM call is logged to `user://llm_telemetry.ndjson`:
```
{ ts, deputy_id, model, tier, in_tokens, out_tokens, latency_ms, error }
```

This file is the input for cost dashboards (deferred) and for tuning persona
prompt size (vision §2.4 mentions cost being a real constraint, not just latency).

Hard ceiling for v1: **2000 input tokens per call** (snapshot + memory + persona
must fit). If the snapshot threatens to exceed, BattlefieldSnapshotBuilder elides
the lowest-priority sections (`recent_events` first, then `enemies` farthest from
focus, then `units` farthest from focus).
