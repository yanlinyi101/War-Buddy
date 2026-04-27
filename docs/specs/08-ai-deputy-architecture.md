# 08 — AI Deputy Architecture

**Status:** design approved 2026-04-27, awaiting implementation plan.
**Vision anchors:** `06-full-gameplay-vision.md` §2.2 (LLM-driven AI deputies as
primary input), §2.3 (agent-tier ladder Hero → Deputy → Captain → Regular), §2.4
(three command tiers), §2.5 (hybrid deputy modes: AI primary, human archon
secondary).
**Sibling spec:** `07-command-system.md` (consumer of this spec's `ActionPlan` output).
**Engine:** Godot 4.6.x + LLM provider HTTPS. Provider precedence (cost-first):
1. **DeepSeek** (default — OpenAI-compatible API at `https://api.deepseek.com/v1/chat/completions`; `DEEPSEEK_API_KEY` env var; ~10× cheaper per 1M tokens than Anthropic Sonnet at comparable quality for this kind of structured-tool-call workload).
2. **Anthropic Messages API** (fallback when DEEPSEEK_API_KEY absent but ANTHROPIC_API_KEY present).
3. **Mock** (final fallback for CI / offline dev).

## 1. Purpose & scope

Vision §2.3 names a four-tier agent ladder, and vision §7 explicitly says **doc 08
covers the whole ladder, not just the deputy**. Spec 08 therefore defines:

- The **Deputy** layer (top-tier LLM agent, single seat per faction, persistent
  identity across matches).
- The **Captain** layer (lighter LLM agents, multiple per match, shorter bond, in-match
  memory only at v1).
- The hybrid **Archon mode** at the deputy seat — a human player taking the seat
  in place of the LLM, sharing controls Starcraft-2-Archon-style.
- The shared infrastructure used by both LLM tiers: `DeputyLLMClient`,
  `BattlefieldSnapshotBuilder`, `ClassifierRouter`, `MemoryStore`, `DeputyPersona`,
  failure-mode policy.

Regular units carry no agency in 08; doc 09 owns their `agency_tier` field and
behavior trees.

**In scope:**
- `Deputy` Node — the per-deputy runtime entity (one seat per faction; vision §2.5
  collapses combat-officer + economy-officer into a single deputy seat).
  **Off-field per vision §2.3** — the Deputy has no `CharacterBody3D`, no collision,
  no HP. Its presence on-screen is a HUD portrait + name + voice bubble. It cannot
  be attacked or killed; the player's risk surface with the Deputy is purely
  cognitive ("is my deputy understanding me right now?").
- `Captain` Node — lighter LLM agent embodied as a battlefield unit; multiple per
  match.
- `ArchonController` — human takeover layer at the deputy seat (vision §2.5).
- `ClassifierRouter` — the single LLM tool-call front door that turns an utterance
  into an `ActionPlan` (used by both Deputy and any addressable Captain).
- `DeputyLLMClient` interface + `DeepseekClient` default + `AnthropicClient` fallback, shared by
  Deputy and Captain agents at different model tiers.
- `BattlefieldSnapshotBuilder` — produces the cropped observation passed to the LLM,
  cropped further for Captain (smaller spatial scope than Deputy).
- Tier latency policy (vision §2.4) — pre-plan / tactical / strategic — applies to
  both Deputy and Captain calls.
- `DeputyMemory` Resource and `MemoryStore` autoload — cross-match persistence for
  Deputy and Captains. Per vision §2.3, captains carry **persistent memory + ≤15%
  per-axis stat reinforcement + full mortality**; the memory layer is owned by 08
  (this spec) and the stat reinforcement layer is owned by 09 (which queries the
  memory). Captain memory survives a captain's death — when the same captain
  persona is summoned again in a later match, its memory carries forward.
- `DeputyPersona` and `CaptainPersona` Resources — name, archetype, voice style,
  system-prompt template, trait scalars, quirks. Captain persona is lighter
  (smaller prompt, smaller model, smaller anecdote allowance).
- `Agent.speak(text)` shared interface for HUD bubbles (Deputy, Captain, and even
  Hero ragdoll-soul utterances per vision §2.3 death treatment); voice TTS wired
  later.
- Failure modes and fallbacks (timeout, network down, LLM hallucination, schema
  violation, archon-disconnect).

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
   │   address the single Deputy ONLY (strict A-chain, vision §2.4)│
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

@export var deputy_id: StringName            # canonical &"deputy"; the field exists so multi-faction matches address each side's deputy independently (e.g. &"deputy_blue", &"deputy_red")
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

One `Deputy` instance is added to the scene tree per faction by `bootstrap.gd`
(default single-faction MVP: one `Deputy` with `deputy_id = &"deputy"`). The
`Deputy` holds a single persona and a single `DeputyMemory`; specialization
(combat tempo vs economy upkeep vs scouting) lives at the Captain layer below
(§11.6), not at the Deputy seat itself.

`bootstrap.gd` also subscribes to `MatchState.victory_triggered` /
`match_lost` (when 09 introduces it) and calls
`MemoryStore.consolidate_after_match(deputy_id, summary, llm_client)` for the
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
    # 2. address the single Deputy seat (strict A-chain per vision §2.4 —
    #    captains are NEVER directly addressable by the player)
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

- `DeepseekClient` (**default — primary provider**): `HTTPRequest` node + DeepSeek's
  OpenAI-compatible chat-completions API at `https://api.deepseek.com/v1/chat/completions`.
  Single tool `submit_plan` with parameters JSON schema generated from
  `ActionPlan.to_dict()` + `OrderTypeRegistry`. `DEEPSEEK_API_KEY` env var.
  Default model alias `deepseek-chat` (always-current chat model; on accounts with
  DeepSeek V4 enabled this resolves to V4). Override per persona via
  `preferred_model`.
- `AnthropicClient` (**fallback**): same role as DeepseekClient via Anthropic Messages
  API. `ANTHROPIC_API_KEY` env var. Default model `claude-sonnet-4-5-20250929`.
  Used only when DeepSeek key absent — kept for parity testing and to validate the
  abstraction.
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
    "deputy_id": "deputy",
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
@export var preferred_model: StringName = &"deepseek-chat"
@export var consolidation_model: StringName = &"claude-haiku-4-20251022"
```

v1 ships three Deputy personas as `.tres`. All three fill the **single deputy
seat** — they're archetype variants of the same role, not specialists for separate
seats:
- `deputy_veteran.tres` — calm, terse, uses chess metaphors, refuses suicide
  charges; balanced economy/military weighting.
- `deputy_aggro.tres` — bold, profane, tolerates losses for tempo; biases plans
  toward attack timing windows.
- `deputy_pedant.tres` — optimistic about long-term, suspicious of early
  aggression, narrates economy decisions in detail.

Persona is selected at match-start (doc 10's lobby), defaults to `deputy_veteran`.

A separate `CaptainPersona` Resource ships with role-specialized presets used by
captains spawned during a match — these *do* split by specialization:
- `captain_combat.tres` — squad leader for combat squads.
- `captain_econ.tres` — overseer for worker groups / depots.
- `captain_scout.tres` — recon / vision captain.

CaptainPersona shares the schema (name, archetype, voice_style, etc.) but uses
`preferred_model = &"claude-haiku-4-20251022"` and a tighter prompt template; see
§11.6.

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

## 11.5. Agent ladder summary (vision §2.3 mapping)

08 implements three of the four ladder tiers; 09 owns the fourth.

| Tier | Module(s) in 08 | Embodiment | LLM model class | Memory horizon | Mortality |
|---|---|---|---|---|---|
| **Hero** | `Agent.speak` only (death-line utterances per §2.3) | On-field unit | none — player-controlled | n/a | full mortality, ragdoll + soul |
| **Deputy** | `Deputy`, `MemoryStore`, full `DeputyPersona`, full snapshot | **Off-field** — HUD portrait + voice | top-tier (Sonnet) | persistent: matches, anecdotes, traits, phrases | **invulnerable** (cognitive failure surface only) |
| **Captain** | `Captain`, `CaptainMemory`, `CaptainPersona`, narrowed snapshot | On-field unit | mid-tier (Haiku or equivalent) | persistent across matches; per-captain `.tres`; ≤15%/axis reinforcement | full mortality, ragdoll + soul |
| **Regular** | — (doc 09: behavior trees, no agent layer) | On-field unit | n/a | n/a | full mortality, ragdoll only |

The shared infrastructure (`ClassifierRouter`, `DeputyLLMClient`,
`BattlefieldSnapshotBuilder`) parameterizes by agent tier — same code paths, different
budgets.

## 11.6. Captain (`captain.gd`)

Vision §2.3 calls Captains "smaller LLM agents the player can bond with". They
spawn during a match as squad leaders for groups of regulars, accept tactical orders
from the deputy or directly from the player, and make their own micro-decisions
within those orders.

```gdscript
class_name Captain
extends Agent       # shared base with Deputy

@export var captain_id: StringName               # unique within match, e.g. &"alpha"
@export var persona: CaptainPersona
@export var squad_id: StringName                 # the squad this captain leads (07 §3 target_squad_id)
@export var agency_tier: StringName = &"captain" # synced with doc 09's unit definition

var short_term_memory: Array[ActionPlan] = []   # last N plans this match; no persistence at v1

func bind_squad(squad_id: StringName) -> void
func handle_plan(plan: ActionPlan) -> void
func tick_observe(snapshot: Dictionary) -> void   # called every K seconds for autonomous decisions
```

**How Captain calls the LLM:**

A Captain wakes up in two situations:
1. **Receives an ActionPlan addressed to its `captain_id` or `squad_id`** — same
   path as Deputy (router routes plan to Captain's `handle_plan`). The Captain
   may issue sub-orders to its own squad's units via `CommandBus.submit_orders`
   with `issuer = CAPTAIN` (07's `Issuer` enum already includes this — see strict
   A-chain in spec 07 §2). Captain-issued orders to its own squad units flow
   directly through `submit_orders`, not through another `submit_plan`, because
   captains are not LLM planners; they are the leaf agent in the strict A-chain.
2. **Periodic tick** — every K seconds (default 8s, configurable per persona),
   Captain calls `ClassifierRouter` with no utterance and a `tier_hint = &"tactical"`,
   asking the LLM "anything you want to do, given current state?" The LLM may emit
   an empty plan (do nothing) or a small plan to react to something.

**Cost containment:**

- Captain uses a smaller model (Haiku-class) per its `CaptainPersona.preferred_model`.
- Captain's snapshot crops aggressively: only its own squad + enemies in vision range
  + the deputy's current high-level intent (one-line summary). 500-token ceiling vs
  Deputy's 2000.
- Captains are rate-limited: at most one autonomous LLM call per Captain per K
  seconds, plus one on-demand call when ordered. A faction with 5 Captains running
  K=8s autonomous = ~37 LLM calls/minute for autonomous + reactive on top. Vision
  §2.4 names this as a real budget constraint; doc 12 must measure it.

**Captain memory (vision §2.3):**

Per the locked-in vision, Captains carry **persistent memory + ≤15% per-axis stat
reinforcement + full mortality**. Memory survives the captain's death — when the
same captain persona is summoned again in a later match, its memory carries
forward.

```gdscript
class_name CaptainMemory
extends Resource

@export var captain_persona_id: StringName       # links to a CaptainPersona resource
@export var match_appearances: int = 0
@export var matches_won_alongside: int = 0
@export var deaths: int = 0                      # cumulative across matches; lifecycle metric
@export var preferred_axis: StringName = &""     # which stat axis this captain bonded into (e.g. &"hp", &"dps", &"sight")
@export var reinforcement_pct: float = 0.0       # 0.0..0.15 — clamped at 0.15 per vision §2.3
@export var match_anecdotes: Array[String] = []  # 0-12 short, captain-flavored memories
@export var schema_version: int = 1
```

Storage: `user://captains/<captain_persona_id>.tres`. `MemoryStore` (already an
autoload) gains parallel methods:

```gdscript
func load_captain(persona_id: StringName) -> CaptainMemory
func save_captain(memory: CaptainMemory) -> void
func snapshot_captain_for(persona_id: StringName) -> Dictionary
func consolidate_captain_after_match(
    persona_id: StringName,
    match_summary: Dictionary,
    llm_client: DeputyLLMClient
) -> void
```

**Reinforcement seam to doc 09:** Doc 09 owns combat stats. When 09 spawns a
captain, it queries `MemoryStore.snapshot_captain_for(persona_id)` and applies the
`reinforcement_pct` to the chosen `preferred_axis` at unit-instantiation time. The
clamp `0.15` is enforced in 08 at write time, not in 09. This keeps the cap in one
place.

**LLM-call snapshot:** Captain's last 6 plans + the events around them remain in
RAM short-term as before; the persistent layer is in addition, not in place of.

## 11.7. Archon mode (`archon_controller.gd`)

Vision §2.5: a human player may take the deputy seat. Same faction, same hero,
same captains — but the LLM that would normally fill the deputy seat is replaced
by another player typing/speaking commands as if they were the deputy.

```gdscript
class_name ArchonController
extends Node

signal archon_attached(deputy_id: StringName, player_id: StringName)
signal archon_detached(deputy_id: StringName)

func attach(deputy_id: StringName, player_id: StringName) -> void
    # The named Deputy node disables its LLM path; ClassifierRouter no longer
    # routes utterances at deputy-seat to the LLM. Instead, ArchonController
    # exposes a parallel input channel (HUD text input dedicated to the archon)
    # whose utterances translate via the normal classifier to ActionPlans.
    # The classifier still runs — it just runs against the archon's typed text,
    # not against the LLM's autonomous reasoning. Persona is unchanged (the
    # archon "wears" the persona's voice style).

func detach(deputy_id: StringName) -> void
    # Re-enables the LLM path. Persona/memory continuity preserved across the
    # archon session — from the deputy's perspective the archon period is just
    # a stretch of matches with different "thinking".
```

**Implications for 07:**

- `CommandBus.submit_plan` accepts plans whose `issuer` is `PLAYER` *with*
  `deputy = "combat"`. This already works in the schema — no 07 change needed.
- A new `ArchonControlPolicy` is added to 07's policy set: identical to
  `FullControl` but **forbids** AI-tier Deputy plans for the seat the archon is
  attached to. CommandBus rejects them with `&"archon_attached"`.
- 07's `OrderTypeRegistry` gates which order types each issuer can use; archon
  inherits the deputy seat's allowed list (no special permissions).

**LLM cost during archon:** the deputy LLM is silent for the seat (zero tokens).
Captains continue to run normally because they're not at the deputy seat.

**Failure modes:**

| Archon failure | Reaction |
|---|---|
| Player drops connection mid-match | `ArchonController.detach()` fires; LLM Deputy resumes from where it was; HUD flashes "副官接管中" |
| Archon types nothing for >30s | Soft-handoff: LLM Deputy gets a "you're co-piloting" hint and emits suggestion plans the archon can confirm with a single click. Deferred to 08+1. |
| Two players try to archon the same seat | `attach` rejected with `&"seat_occupied"` |

**v1 implementation scope for archon:** the seat-attach interface and the
`ArchonControlPolicy` ship; the actual networked second-player input is doc 12
networking territory and is **deferred**. v1 archon mode is local-only (same
keyboard, "press F2 to take the seat" debug toggle), enough to validate the
control-policy plumbing.

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
- `godot/data/personas/deputy_veteran.tres`
- `godot/data/personas/deputy_aggro.tres`
- `godot/data/personas/deputy_pedant.tres`
- `godot/data/personas/captain_combat.tres`
- `godot/data/personas/captain_econ.tres`
- `godot/data/personas/captain_scout.tres`
- `godot/scripts/ai/captain.gd`
- `godot/scripts/ai/captain_persona.gd`
- `godot/scripts/ai/archon_controller.gd`
- `godot/tests/test_captain.gd`
- `godot/tests/test_archon_controller.gd`
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
3. With `DEEPSEEK_API_KEY` (or `ANTHROPIC_API_KEY` as fallback) exported, a manual
   smoke: type "我们去打中路" in HUD, see deputy bubble appear, see `plan_issued`
   signal on `CommandBus` carrying a syntactically valid `ActionPlan`. Orders
   won't execute (doc 09 not done) — that's expected.
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
