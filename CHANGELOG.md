# Changelog

All notable changes to War Buddy are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project follows semantic versioning loosely — pre-1.0 minor bumps may break save-format or API assumptions.

## [v0.4.1] — 2026-04-27

### Changed
- **DeepSeek is now the primary LLM provider for the deputy.** DeepSeek's API is OpenAI-compatible (chat-completions endpoint, function-tool wrapper) and roughly an order of magnitude cheaper per million tokens than Anthropic Sonnet at comparable quality for the deputy's structured-tool-call workload — see `docs/specs/08-ai-deputy-architecture.md` for rationale.
- `bootstrap.gd::_make_llm_client` provider precedence is now **DeepSeek → Anthropic → Mock**. `DEEPSEEK_API_KEY` is the primary env var; `ANTHROPIC_API_KEY` continues to work as a fallback for parity testing.
- `data/personas/deputy_veteran.tres` and `DeputyPersona`'s default `preferred_model` / `consolidation_model` switched to `deepseek-chat` (DeepSeek's always-current chat alias; resolves to V4 on accounts with V4 enabled).

### Added
- `godot/scripts/ai/deepseek_client.gd` — `DeepseekClient` extends `DeputyLLMClient`. Uses DeepSeek's OpenAI-compatible `/v1/chat/completions` endpoint with the standard function-tool wrapper. Parses `choices[0].message.tool_calls[0].function.arguments` (which arrives as a JSON-encoded string, unlike Anthropic's pre-parsed Dictionary) and feeds the result through the same `apply_invariants()` / `validate_invariants()` pipeline as Anthropic.
- Smoke checklist gains `Manual — DeepSeek` and `Manual — Anthropic` subsections so each provider is tested independently.

### Notes
- `AnthropicClient` is intentionally retained, not removed. Provider switching is a single env-var change; keeping both implementations validates the abstraction (and gives us an escape hatch if DeepSeek has an outage).
- No tests added for `DeepseekClient` (live-API tests have cost/non-determinism per spec 08 §13). The MockClient continues to drive automated coverage; manual smoke validates the live path.

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

## [v0.3.0] — 2026-04-27

### Added
- **Command-system skeleton** — first concrete implementation of the keystone artifacts in `docs/specs/07-command-system.md`. Skeleton ships even though there is no executor for the orders yet; doc 09 will land that.
- **`TacticalOrder` Resource** — universal order data class with `to_dict / from_dict` for LLM JSON round-trip; provenance fields (`origin`, `issuer`, `parent_intent_id`, `confidence`, `rationale`) included from day one. Issuer enum aligns with vision §2.4 strict A-chain: `{ PLAYER, DEPUTY, CAPTAIN, SCRIPT }`.
- **`ActionPlan` Resource** — wraps the LLM-emitted plan-level rationale + confidence + orders[] with `apply_invariants()` and `validate_invariants()` helpers so deputies never silently emit malformed plans.
- **`OrderTypeRegistry` autoload** — extension point for future entity / economy specs (doc 09) to register order types (`move`, `attack`, `gather`, `train`, etc.) without touching command-system internals.
- **`CommandBus` autoload** — single ingress with six-step validation (status / unique id / registered type / param shape / control policy / target presence), accepted/rejected split, ring buffers, and append-only ndjson persistence under `user://order_log/<match_id>.{ndjson,rejected.ndjson,plans.ndjson}`.
- **`ControlPolicy` family** — `FullControl` (default), `HeroOnly`, `AssistMode`, `ArchonControl`. The fourth implements vision §2.5's archon mode by rejecting AI Deputy plans for whichever seat a human has taken.
- **`PrePlan` + `PrePlanTrigger` Resources** with a small condition DSL (`within_seconds_of_start`, `enemy_count_at_least`, `player_resource_below`).
- **`PrePlanRunner` Node** with `notify_event(name, payload)` API (intentional stand-in until `EventBus` lands in doc 09). Bootstrap fires `match_start` on boot with one inline sample plan.
- **Tests** — seven new GUT files (`test_tactical_order`, `test_action_plan`, `test_order_type_registry`, `test_control_policy`, `test_command_bus`, `test_pre_plan`, `test_pre_plan_runner`) bring the total green count to 64.

### Notes
- Orders sit in `pending` forever in v0.3.0 — that is intentional. Doc 09 (entities / combat / economy) will introduce executors that consume them via the `order_issued` signal.
- No LLM integration yet; that's doc 08's milestone (v0.4.0 plan).
- v0.3.0 keeps the v0.2 dev-mode squad selection intact — both systems coexist on the bus side without conflicting.
- `.tres` pre-plan authoring is deferred to doc 10 (war-room UI). The shipped `data/preplans/` folder is a placeholder; the inline sample plan in `bootstrap.gd` proves the pipeline.

## [v0.2.0] — 2026-04-26

### Added
- **SquadUnit puppets** — three blue capsule units spawn near the hero. They expose a method-level order interface (`order_move / order_attack / stop`) but do nothing on their own. Combat parameters mirror the hero (20 dmg, 0.75 s cooldown, 2.8 unit range). They have no HP and cannot die — invincible by design until the deputy AI lands.
- **SelectionSet** — `RefCounted` container of currently-selected squad units, with selection-ring visual feedback via `Decal`.
- **DevSquadController** (debug builds only) — drag-box left-click selection plus right-click move / attack orders. Provides the validation harness for the squad order interface ahead of Phase D's deputy execution. `OS.is_debug_build()` gates registration so release builds carry no dev surface.
- **HUD `DEV MODE` indicator** — orange top-right label visible only when the dev controller is active.
- **Tests** — five new GUT cases for SelectionSet plus four for SquadUnit (order interface, attack target lifecycle, selection-ring toggle). Total green count: 19.

### Notes
- No new autoloads. SelectionSet is held by reference from `bootstrap.gd`; `EventBus` / `CommandBus` / `GameState` remain deferred to Phase D when the deputy makes them necessary.
- The `Squad` named-group abstraction (spec 03 §7) is intentionally **not** yet introduced; v0.2 has only flat `SquadUnit` instances.
- Hero controls unchanged from v0.1.1. The LoL/WASD dual-input rework is captured in `docs/future-features.md`.

## [v0.1.1] — 2026-04-26

### Fixed
- HUD `PanelContainer` no longer covers the 3D viewport or swallows mouse clicks. Added `mouse_filter = 2` and removed `size_flags_vertical = 3` so the panel sizes to its content instead of expanding across the screen. World orders now reach the ground / enemy buildings under the command-panel area as intended.
- Mouse-wheel zoom on the orthographic RTS camera now actually zooms by adjusting `Camera3D.size`. Previous code modified `position.y`, which only translates an oblique orthographic view diagonally — looked like a pan, not a zoom. `_adjust_zoom` now branches on `projection`; perspective fallback retained for future use.

### Docs
- Synced `docs/specs/02-rts-mvp-implementation-plan.md` checkboxes (T3–T6) with the v0.1.0 reality and the v0.1.1 patch.

## [v0.1.0] — 2026-04-23

First public cut of the RTS MVP commander slice, fully ported to Godot 4.6.x.

### Added
- **Commander-on-field gameplay loop** — single hero controlled by mouse, raycast-targeted move / attack, enemy building HP feedback, one-shot victory trigger when all three enemy buildings are destroyed.
- **Deputy command console** — two-channel (combat / economy) text command input with a lifecycle state machine (`submitted` → `received` → `pending_execution`) driven by `command_log_model.gd`.
- **Voice placeholder** — visible "Voice (Soon)" button that logs its click without pretending to record.
- **RTS camera** — WASD / screen-edge pan, middle-mouse drag, mouse-wheel zoom (`rts_camera.gd`).
- **Navigation** — `NavigationAgent3D` pathfinding with runtime-baked `NavigationRegion3D`; per-building `NavigationObstacle3D` so the hero actually routes around live buildings.
- **HUD input routing** — explicit `mouse_filter` pass on decorative Controls so clicks fall through to world orders; interactive controls block.
- **Destruction feedback** — 0.35s scale + alpha tween on `EnemyBuilding._destroy()`, with `destroyed` signal emitted before the tween so the victory check fires on the killing-blow frame.
- **`[RTSMVP]` debug log prefix** — every bootstrap, hero input, command, and victory event uses a common prefix for grep-friendly debugging.
- **Headless tests** — [GUT 9.6.0](https://github.com/bitwes/Gut) addon at `godot/addons/gut/`, 10 cases covering command log submission/status lifecycle and match-state one-shot victory invariants.
- **CI/CD**
  - `.github/workflows/ci.yml` — on every push/PR: headless boot + `SCRIPT ERROR` gate + GUT tests + docs-lint that forbids reintroducing Unity artifacts.
  - `.github/workflows/release.yml` — on `v*` tag: matrix export for Linux / Windows / Web, attached to a GitHub Release.
- **Project docs** — `CLAUDE.md` at repo root, five-file `docs/specs/` set covering design, implementation plan, architecture reference, Unity parity outcome, and smoke-test checklist.

### Known issues / intentionally deferred
- **Multi-unit selection, drag-box, squads** — deferred to v0.2+.
- **Economy, workers, production queues, building placement ghosts** — out of scope for the commander MVP slice.
- **Voice input** — UI placeholder only; no real speech recognition.
- **Art assets** — everything is graybox. Visual pass is a v0.2+ concern.

### Migration note
The earlier Unity C# scaffold has been retired from this repo. Only engine-agnostic design text survives in the specs. See [`docs/specs/04-godot-unity-parity-checklist.md`](docs/specs/04-godot-unity-parity-checklist.md) for the close-out audit.
