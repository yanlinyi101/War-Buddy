# Changelog

All notable changes to War Buddy are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project follows semantic versioning loosely — pre-1.0 minor bumps may break save-format or API assumptions.

## [v0.8.2] — 2026-05-10

### Added
- **Off-nav-mesh recovery (spec 11 §8.1)** — `NavRecovery` Node attaches to any Node3D and, each physics frame, snaps the target back to the nearest valid nav-mesh point if displacement exceeds 1.5 m for > 3 frames. The 3-frame buffer prevents false positives during legitimate ragdoll-push events. Pushes a warning to console on each recover so authoring bugs surface early.
- Auto-picks the default 3D nav map; skips queries until the map's iteration_id > 0 (prevents "map query before sync" log spam during headless boot).
- Bootstrap attaches a `NavRecovery` to the hero on `_ready`.
- 4 new GUT cases (`test_nav_recovery`) covering no-target, no-nav-map, teleport bookkeeping, and default tunables. Total: **152/152** green.

### Notes
- §8.2 (isolated-island fallback) and §8.3 (empty-path warn) are out-of-the-box behaviors of Godot's `NavigationAgent3D` plus its `path_postprocessing` mode — no extra code needed in v0.8.2. The smoke checklist covers them as manual checks.
- Squad units don't get a NavRecovery in v0.8.2 — they're confined to flat terrain by the graybox map. If we add terrain seams or cliffs they'll need one too.

## [v0.8.1] — 2026-05-10

### Added
- **Captain mortality (spec 08 §11.6, vision §2.3)** — Captain "embodies" a `SquadUnit` body via `bind_body(body)`. When that unit's `died` signal fires, captain `alive` flips to false, `CaptainMemory.deaths` increments, `MemoryStore.save_captain` persists it to `user://captains/<persona_id>.json`, and `EventBus.unit_destroyed` broadcasts with `faction_id="captain"` so the debug HUD shows captain deaths distinctly.
- Dead captain rejects new plans (`plan_rejected_locally` reason `"captain_dead"`) and skips autonomous tick (`autonomous_tick_skipped` reason `"dead"`).
- Bootstrap binds captain alpha to squad unit `squad_a` on `_ready` — so K-damaging that capsule three times kills the captain alongside it.
- 7 new GUT cases (`test_captain_mortality`). Total: **148/148** green.

### Notes
- Memory survives the captain's death by design (vision §2.3 lock-in) — re-loading `user://captains/captain_alpha.json` in a fresh match shows the prior `deaths` count carried forward.
- The body binding is one-way: captain reacts to body death, but does not yet drive the body's movement directly (the body is still controlled by `Captain → CommandBus → OrderExecutor → SquadUnit.order_*`). That's correct for the strict A-chain — the captain "is" the body for mortality, but plans still flow through the chain.

## [v0.8.0] — 2026-05-10

First slice of doc 09 — SquadUnits gain real HP, can die, and announce themselves through `EventBus`. The v0.2.0 dev-mode invariant ("squads never lose HP, never die") is intentionally broken; the matching smoke-checklist line is now annotated.

### Added
- **SquadUnit mortality** — `max_hp` (default 100, `@export`), `hp`, `is_dead`, `take_damage(amount, source = null)`, `_die()`. New signals: `hp_changed(current, maximum)` and `died(unit_id)`.
- **HP bar** above each squad unit, reusing `HpBar3D` from v0.6.2 (instant red drop + 400 ms ghost catch-up + automatic billboard). Bar hides on death.
- **Death pipeline** — collision shape disabled, removed from the `squad_units` group on death (so `OrderExecutor` and snapshot queries stop pointing at a dying unit), `EventBus.publish_unit_destroyed` fires before the visual fade so consumers see the death on the same frame, then a 0.4 s scale-down tween into `queue_free`.
- **Debug damage tool (debug builds only)** — `DevSquadController` listens for **K** and applies 25 damage to each currently-selected squad unit. Lets us verify HP bars + death + EventBus plumbing without needing real enemy combat yet.
- 7 new GUT cases (`test_squad_unit_mortality`) covering: initial HP, take_damage decrement + signal, zero/negative noop, lethal damage clamps at zero + dies, EventBus publish on death, double-kill idempotency, group cleanup. Total: **141/141** green.

### Changed
- `take_damage` also forwards an `EventBus.publish_hp_changed` event on every hit so the debug log HUD and the snapshot builder's `recent_events` ring see the bleed in real time.
- 05 smoke-checklist line "Squad units never lose HP, never die, and have no HP label" is annotated as a broken-invariant pointer to the new mortality section.

### Notes
- No combat source attacks SquadUnits in v0.8.0 — enemy buildings are still passive targets. The K-key tool is the only damage source. Real enemy units land alongside doc 09's faction roster.
- Captain mortality is the next slice. `CaptainMemory.deaths` field is already plumbed (v0.5.0) — we just need to wire `Captain` to a CharacterBody3D body and connect the same death pipeline.
- Ragdoll / soul VFX (spec 11 §3) deferred — current "fade + scale-down" is the placeholder.

## [v0.7.2] — 2026-05-10

### Added
- **EventBus debug log HUD** (`scripts/hud/event_log_hud.gd` + `scenes/event_log_hud.tscn`) — debug-only overlay that subscribes to all `EventBus` channels and renders a 24-line scrolling log with timestamps and color-coded event kinds. Toggle visibility with the **backtick (`)** key. Bootstrap spawns it only inside `if OS.is_debug_build()`, so release builds never carry it.
- Each line is shaped `<elapsed_s> <kind> k1=v1 k2=v2 ...` — a quick way to verify v0.7.0/0.7.1 plumbing during the manual smoke pass without rolling a custom listener.

### Notes
- The HUD is read-only — it doesn't drive any subscriptions itself; it only mirrors what `EventBus` already broadcasts. Adding a channel to `event_bus.gd` requires also wiring it into `event_log_hud.bind_event_bus`.
- 134 tests still green (no new test cases — the HUD is purely visual; its correctness is a manual smoke check).

## [v0.7.1] — 2026-05-10

### Added
- **Captain autonomous tick (spec 08 §11.6, vision §2.3)** — Captains now react to `EventBus` events on their own LLM call, separate from the player-utterance path. v0.7.1 ships one channel: `building_destroyed` triggers a rate-limited tactical-tier LLM call. The first ActionPlan returned is fed through Captain's existing `handle_plan` (persona filter → retag to own squad → `submit_orders` as `CAPTAIN`).
- Cooldown — at most one autonomous LLM call per captain per `persona.autonomous_tick_seconds` (default 8 s, persona-tunable). Fast event bursts collapse into a single tick. Spec 08 §11.6 cost containment.
- `Captain` API surface: `bind_autonomous_deps(llm, snapshot_builder, registry)`, `enable_autonomous_tick(bool)`, `subscribe_to_event_bus(EventBus)`. Two new signals — `autonomous_tick_fired(plan)` and `autonomous_tick_skipped(reason)` — make the path observable from tests and from a future debug HUD without polling.
- **Bootstrap auto-enables the tick only when DeepseekClient is the active LLM** (i.e. `DEEPSEEK_API_KEY` is set). MockClient runs leave the tick disabled — no point burning mock tokens on background reactions, and CI/headless smoke stays cost-free.
- 5 new GUT cases (`test_captain_autonomous`) using a stub LLM subclass to verify: disabled-state skip, unbound-deps skip, real fire on event, cooldown blocks rapid double-tick, empty-plan response is a valid skip. Total: **134/134** green.

### Notes
- Other EventBus channels (`unit_destroyed`, `hp_changed` thresholds) wire in alongside `Captain` reactions to those events. v0.7.1 deliberately ships only `building_destroyed` so we can eyeball cost in real DeepSeek runs before turning on more triggers.
- The autonomous-tick path uses captain's persona, not the deputy's. The persona's `system_prompt_template` and `voice_style` shape the bubble; persona's `allowed_type_ids` filters disallowed orders before bus submission. So Captain Alpha can react in Alpha's voice, distinct from the deputy.
- `BattlefieldSnapshotBuilder` is reused as-is — captain gets the same observation as deputy. Captain-specific snapshot crop (smaller spatial scope, captain's own squad only) is deferred until doc 09's faction-scoped queries land.

## [v0.7.0] — 2026-05-09

The structural lever — `GameState` and `EventBus` autoloads from doc 09 §11 land. Captain autonomous tick, real match-event audit, and behavior-tree report-back channel all sit on these.

### Added
- **`GameState` autoload** (`scripts/state/game_state.gd`) — match clock (`mark_match_started` / `match_elapsed_seconds`), victory flag (`mark_victory` / `is_victory_triggered`), and proximity queries (`units_in_radius` / `buildings_in_radius` / `all_squad_units` / `all_enemy_buildings` / `enemy_buildings_alive`). v1 implementation backed by scene-tree groups; the API is the contract, the storage is replaceable when doc 09's faction state lands.
- **`EventBus` autoload** (`scripts/state/event_bus.gd`) — match-level signal channel: `match_started`, `match_ended`, `unit_spawned`, `unit_destroyed`, `building_destroyed`, `hp_changed`, `order_completed`, `order_failed`, `order_progress`. All payloads are Dictionaries so adding fields is additive. Convenience publishers (`publish_match_ended` etc.) keep emit sites concise.
- **`BattlefieldSnapshotBuilder` upgrade** — now reads `match_meta.elapsed_s` from `GameState`, and subscribes to `EventBus.{building_destroyed, unit_destroyed, match_ended}` to populate `recent_events` (ring buffer, 20-deep). Falls back to scene-tree groups when autoloads aren't mounted (used by GUT tests that instantiate the builder in isolation).
- **Bootstrap wiring** — `GameState.mark_match_started` + `EventBus.publish_match_started` fire on `_ready`; enemy-building destruction publishes to `EventBus`; victory marks `GameState` and publishes `match_ended`.
- 10 new GUT cases (`test_game_state`, `test_event_bus`). Total: **129/129** green.

### Changed
- **DeepSeek is now the only API-keyed LLM provider in the runtime path.** `bootstrap._make_llm_client` precedence simplified to **DeepSeek → Mock**. The `AnthropicClient` script remains in `scripts/ai/anthropic_client.gd` for parity tests / future re-enable, but `ANTHROPIC_API_KEY` is no longer consulted. The `Manual — Anthropic` smoke section in `05-godot-smoke-test-checklist.md` is marked REMOVED.

### Notes
- Captain autonomous LLM tick is now unblocked: it can subscribe to `EventBus.building_destroyed` and react. Deferred to a follow-up because the prompt budget and tick rate warrant a dedicated brainstorm before turning it on.
- Faction state, minerals/gas, supply, and production queues from spec 09 §11 are deferred — they belong with the economy slice. v0.7.0 ships the channel + minimal queries; the schema can grow without breaking subscribers.
- Behavior-tree subscribers to `EventBus.order_*` will land alongside `OrderExecutor`'s upgrade path in v0.8.x once unit mortality is in.

## [v0.6.2] — 2026-05-09

### Added
- **Two-layer HP bar on enemy buildings (spec 11 §7.3)** — `scripts/feel/hp_bar_3d.gd` + `HpBar3D` Sprite3D node added to `enemy_building.tscn`. Renders a 64×8 dynamic image with three stripes: dark background, white "ghost" damage indicator, red current HP. The current bar drops instantly on damage; the ghost catches up over 400 ms — the standard MOBA "I see *that* I took damage now, *how much* a moment later" cue. Sprite3D billboards toward the camera for free.
- 5 new GUT cases (`test_hp_bar_3d`) covering instant red drop, ghost lag, ghost catch-up within 400 ms, heal snap-up, and zero-max-hp guard. Total: **119/119** green.

### Changed
- `enemy_building.gd::_update_visuals()` now drives the HpBar3D alongside the existing Label3D text and the body's tint material. Bar auto-hides on `_destroy()` along with the hover ring.

### Notes
- Hero HP still uses the v0.1.0 HUD label; porting the hero's HP to the same widget is deferred — the HUD-side widget is a Control, not a Sprite3D, so it'll be a near-duplicate `hp_bar_2d.gd` rather than a reuse.
- SquadUnit / Captain still don't have HP bars because they don't have HP — that lands with v0.6.3+ (doc 09 unit mortality).

## [v0.6.1] — 2026-05-09

### Changed
- **Hero movement feel (spec 11 §4)** — replaces the v0.1.0 "instant top-speed, instant stop" motion with the spec-defined "responsive but grounded" curve.
  - `max_speed`: 9.0 → 4.5 m/s. The previous value crossed the 36×36 graybox in ~4 s, which read as arcade-twitchy. 4.5 m/s sits between DOTA-deliberate and old-RTS-sluggish per §4.1's intent. The full spec target (~45 s diagonal ≈ 1.1 m/s) felt glacial in graybox; 4.5 is the working compromise — tunable from the inspector now.
  - Acceleration: 0 → top speed in 100 ms (§4.2). Hero no longer teleports to top speed on click.
  - Stop: instant snap to zero on path-end / stop command (§4.4). Asymmetry — slow start, hard stop — is the signature.
  - All three values exposed as `@export` on `HeroController`: `max_speed`, `accel_time_s`, `stop_snap_speed`.

### Added
- `HeroController.step_velocity_toward()` — pure static helper extracted so the velocity-shaping math is testable without a scene tree.
- 5 new GUT cases in `test_hero_movement.gd` covering snap-stop, no-overshoot, accel-reaches-max-within-window, residual snap, and Y-preservation. Total: **114/114** green.

### Notes
- Visual rotation easing (§4.3, "mesh visual rotation eases over ~100 ms to logical facing") is deferred — the hero is currently a sphere and has no visible facing. Re-add when a non-spherical mesh lands.
- SquadUnit movement still uses its v0.2.0 direct-velocity model — that's fine for v0.6.1 because the squad units are AI-driven and don't need input-feel polish. Revisit only if their motion looks wrong next to the hero's new curve.

## [v0.6.0] — 2026-05-09

First "feel polish" slice off doc 11 (`docs/specs/11-mvp-physics-and-feel.md`). All three additions are visible in the editor F5 run; none touch architecture or save format.

### Added
- **Enemy-building hover ring (spec 11 §6.2)** — moving the cursor over an `EnemyBuilding` fades a red ring decal in beneath it (~80 ms fade-in, ~120 ms fade-out). The building's `StaticBody3D` gains `input_ray_pickable = true`; hover state is wired through Godot's built-in `mouse_entered` / `mouse_exited` signals so it doesn't conflict with the existing left-click raycast in `hero_controller.gd`. Ring auto-hides on destruction.
- **Camera screen shake (spec 11 §7.2)** — `RtsCamera.shake(magnitude, duration)` adds a decaying additive XZ offset on top of the pan/follow logic. `bootstrap.gd` triggers a subtle shake (`0.35 / 0.30 s`) on every enemy structure destruction and a bigger one (`0.9 / 0.6 s`) on victory. Magnitude is clamped at 2.0 m so a buggy caller can't fling the camera off-map.
- **Hitstop driver (spec 11 §7.1)** — `scripts/feel/hitstop.gd` exposes `request_hit(attacker, victim, duration_ms)` and freezes the participants by toggling `process_mode = PROCESS_MODE_DISABLED` for the requested window (default 45 ms). We deliberately do **not** use `Engine.time_scale` — that would freeze HUD bubbles, deputy LLM tweens, and the mock client's `await`, all of which we want running through a hitstop. Hero-vs-building melee hits now request hitstop on every connect.
- Tests — 8 new GUT cases (`test_hitstop` + shake assertions in `test_rts_camera_follow`). Total green count: **109/109**.

### Notes
- The HP bar two-layer ghost animation from spec 11 §7.3 is still pending; the existing Label3D HP text continues to work and isn't worth an in-place rewrite until we have a real HP-bar widget. Tracked for v0.6.1.
- Hero-side hitstop currently fires on melee landing only. SquadUnit / Captain attacks don't request hitstop yet — partly because their attacks are continuous DPS-style ticks rather than discrete hits, and partly because freezing 3 squad units mid-engagement felt worse in eyeballing than letting them keep going. Revisit when doc 09's discrete-attack model lands.
- Shake works in both follow and free-pan modes — the offset is removed and re-applied each frame so it composes cleanly with hero-follow.

## [v0.5.1] — 2026-05-08

### Added
- **Hero-follow camera** — pressing **Space** locks the RTS camera onto the hero, preserving the player's current pan offset and zoom (no jarring snap-to-center). Mouse-wheel zoom continues to work in follow mode. Any manual pan (WASD / edge-pan / middle-drag) breaks the lock automatically — LoL-style "Y to lock / move to break" UX. Press Space again to toggle off.
- New input action `camera_follow_toggle` (Space) registered in `project.godot`.
- `RtsCamera.set_follow_target(target)` / `is_following()` / internal `_apply_follow()` API; bootstrap binds the hero as the follow target on `_ready`.
- Tests — 4 new GUT cases in `test_rts_camera_follow.gd`. Total green count: **101/101**.

### Notes
- Follow mode is XZ-only; the camera's Y (zoom level) is never overwritten by the hero's Y, so the player's chosen zoom always wins.
- Edge-pan triggered by mouse at the screen border still breaks follow — that's intentional. If the player wants to look elsewhere with the mouse alone, they should briefly leave follow mode.

## [v0.5.0] — 2026-05-08

### Added
- **A-chain finally closes** — `OrderExecutor` listens on `CommandBus.order_issued` and translates accepted `move` / `attack` / `stop` / `hold` orders into the existing `SquadUnit.order_*` calls. Plans the deputy emits now actually move units. (Minimal stub for doc 09 territory; the full executor + behavior tree still lands with 09.)
- **Captain layer (spec 08 §11.6, vision §2.3)** — `Captain` Node + `CaptainPersona` + `CaptainMemory` + `data/personas/captain_alpha.tres`. One captain (`alpha`) is bound to the existing 3 SquadUnits via the new `squad_alpha` group. Captain receives Deputy plans through `CommandBus.plan_issued`, persona-filters, retags orders to its squad, and resubmits as `issuer = CAPTAIN`. `OrderExecutor` skips DEPUTY-issued orders so the same physical action isn't double-executed — the strict A-chain (player → deputy → captain → squad units) is now load-bearing.
- **`CaptainMemory`** — cross-match persistence at `user://captains/<persona_id>.json` with the ≤15 % per-axis reinforcement clamp enforced at write time (the cap lives in 08, not in 09). `MemoryStore` gains `load_captain` / `save_captain` / `snapshot_captain_for`.
- **`ArchonController` (spec 08 §11.7)** — `attach(seat, player)` swaps the `CommandBus` policy to `ArchonControlPolicy(seat)` (already in 07), silencing AI Deputy plans for that seat while leaving `PLAYER`-issued plans accepted. `detach()` restores the prior policy. F2 toggles attach/detach in debug builds; release builds ignore the toggle. Networked second-player input is still doc 12 territory and remains deferred.
- **HUD captain bubble** — `Captain.spoke` is wired into the same `MessageBubbleHud` channel the deputy uses, prefixed by the captain id so it's visually distinguishable.
- **Tests** — 15 new GUT cases (`test_order_executor`, `test_captain`, `test_archon_controller`) bring total green count to **97/97**.

### Changed
- `bootstrap.gd::_spawn_squad_units` adds spawned `SquadUnit` nodes to the `squad_alpha` scene-tree group so `OrderExecutor._resolve_units` can find them by `target_squad_id`.
- `OrderExecutor` skips orders whose `issuer == DEPUTY` (intent-only) and orders whose `target_kind == hero` (owned by `hero_controller`). This is the rule that lets deputy plans flow through a captain without double-execution.

### Notes
- Captain still does **not** make autonomous LLM calls — `tick_observe` is a no-op at v0.5.0. Periodic K-second snapshot calls land alongside doc 09 (we want a real `EventBus` and combat HP feed first; without those the captain has nothing useful to react to).
- LLM-driven sub-order decomposition inside Captain is still a passthrough (re-tags but does not split or reorder). Real LLM inside Captain is gated on cost-budget telemetry per spec 08 §15 / vision §2.4.
- Stat reinforcement (`CaptainMemory.reinforcement_pct`) is plumbed but not yet read at unit-spawn time; that seam is doc 09's responsibility per spec 08 §11.6.
- 05 smoke checklist gains a v0.5.0 section covering: A-chain visible, captain bubble appears, F2 archon toggle blocks AI deputy.

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
