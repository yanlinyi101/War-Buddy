# Changelog

All notable changes to War Buddy are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project follows semantic versioning loosely — pre-1.0 minor bumps may break save-format or API assumptions.

## [v0.10.2] — 2026-05-10

### Added
- **`ProductionService` autoload (doc 09 §5.4 / §6 / §7.4)** — owns the production queue runtime for the `train` order verb.
  - `validate_train(faction, building_def, unit_id)` enforces: building's `produces` list, tier gating, prerequisite buildings, supply headroom, resource cost. Returns `{ok, reason, unit_def}`.
  - `enqueue_train(faction, building_id, building_def, unit_id)` deducts resources + reserves supply on enqueue (SC2 convention) and pushes onto the queue.
  - `tick(faction, delta)` advances each queue head's `build_time_remaining`; completion fires `training_completed(faction_id, building_id, unit_id)` and pops.
  - `cancel_head(faction, building_id)` returns 75 % of the unit's mineral + gas cost and frees the reserved supply (spec §5.4 partial refund).
- 12 new GUT cases (`test_production_service`). Total: **238/238** green.

### Notes
- No physical unit spawn yet — the graybox map has no spawn point for a player HQ. `training_completed` is the seam: when v0.11+ wires a player HQ scene node, the spawn callback subscribes here and instantiates the actual CharacterBody3D.
- Cost / supply gating is single-faction, single-pass — multi-faction validation lands with 09+1.
- `set_rally` / `cancel_production` order verbs from spec 09 §9 are registered (v0.9.2) but not yet routed into this service. Hooking the `CommandBus.order_issued` → `ProductionService.enqueue_train` bridge waits on a `production_building.gd` scene node that exposes its `building_def` + instance id.

## [v0.10.1] — 2026-05-10

### Added
- **`ResourceNodeDef` Resource (doc 09 §5.2)** — `node_id`, `resource_type` (mineral / gas), `initial_amount`, `current_amount`, `harvest_amount_per_cycle`, `max_concurrent_workers`, `depletes`. Helpers: `harvest()` returns the actual taken amount (clamped against `current_amount`; gas always returns the cycle amount); `is_depleted()`; `saturation_for(active_workers)` returns 0.0–1.0 for the LLM snapshot.
- 6 new GUT cases (`test_resource_node`). Total: **226/226** green.

### Notes
- The runtime `ResourceNode` scene node + the in-world placement at game start are deferred to the same slice as the production runtime (v0.10.2) — they all need an HQ + worker spawn pipeline to be useful. v0.10.1 just lands the data class so worker BTs can already call `harvest()` against test stubs.
- The class is named `ResourceNodeDef` to dodge Godot 4's built-in `Resource` symbol clash; the spec name "ResourceNode" maps directly.

## [v0.10.0] — 2026-05-10

### Added
- **Behavior-tree contract (doc 09 §12)** — `scripts/bt/behavior_tree.gd` is the abstract base. Subscribes to `CommandBus.order_issued`, filters by `target_unit_ids` containing self's `unit_id`. Reports back through `EventBus.order_completed / order_failed / order_progress`. Two helpers (`report_completed`, `report_failed`, `report_progress`) keep emit sites tidy.
- **`WorkerBT` skeleton** (`scripts/bt/worker_bt.gd`) — routes `move`/`gather`/`return_cargo`/`build`/`stop` to a small state machine (`idle / moving / harvesting / returning / building`). Unsupported `type_id`s self-report as `order_failed` with reason `unsupported_type_id`.
- 7 new GUT cases (`test_behavior_tree_contract`). Total: **220/220** green.

### Notes
- v0.10.0 ships the contract shape only. The real worker gather animation cycle + ResourceNode + deposit point land in v0.10.1.
- Per spec 09 §12: "BT internals (selectors, sequences, decorators) are an implementation choice." v0.10.0 uses a flat state-machine because no concrete BT yet needs nested control flow. When a BT does, it can swap in a real tree library or roll a small one without touching the contract.

## [v0.9.6] — 2026-05-10

### Added
- **Captain stat reinforcement (doc 09 §8.3, closes spec 08 §11.6 loop)** — `scripts/combat/captain_reinforcement.gd` exposes `CaptainReinforcement.apply(unit_def, memory)` which duplicates the UnitDef and applies one axis (`hp` / `dps` / `sight` / `speed`) according to `CaptainMemory.preferred_axis` × `reinforcement_pct`. The DPS axis bumps `dmg` *and* shrinks `attack_period_seconds` (both directions contribute). The returned UnitDef gets `agency_tier=captain`; the library row stays pristine.
- 9 new GUT cases (`test_captain_reinforcement`). Total: **213/213** green.

### Notes
- The cap (`reinforcement_pct ≤ 0.15`) lives in `CaptainMemory.clamp_reinforcement` per spec 08 §11.6 — v0.9.6 trusts its input.
- No spawner consumes the helper yet. The production pipeline (v0.10) will call `apply()` when summoning a captain alongside its squad. Until then, captain alpha still rides squad_a with vanilla stats.

## [v0.9.5] — 2026-05-10

### Added
- **Doc 09 §8 captain↔squad category binding.**
  - `CaptainPersona.eligible_categories: Array[StringName]` + `can_lead_category(cat) -> bool`. Empty array means unrestricted (back-compat with `captain_alpha.tres`).
  - Three new persona files matching spec §8.2:
    - `captain_combat.tres` — leads `frontline / ranged / siege / caster`.
    - `captain_econ.tres` — leads `worker` only.
    - `captain_scout.tres` — leads `scout` only.
  - `Squad` Resource with `Squad.validate_binding(persona, category) -> {ok, reason}` for spawn-time enforcement.
- 8 new GUT cases (`test_captain_squad_binding`). Total: **204/204** green.

### Notes
- No runtime Squad instances yet — the `Squad` Resource is the data shape only. Spawn-time binding fires when the production pipeline (v0.10) summons a captain alongside its squad.
- `captain_alpha.tres` (v0.5.0) is now considered the "untyped tutorial captain" since it ships without `eligible_categories`. The new typed personas are what live captains will use.

## [v0.9.4] — 2026-05-10

### Added
- **Doc 09 §3.3 unit roster (7 .tres files)** — `worker_basic`, `frontline_basic`, `ranged_basic`, `siege_basic`, `caster_basic`, `scout_basic`, `hero_commander`. Stats pinned to the §3.3 table (Marauder-class frontline 125 HP / heavy / 10 normal, etc.).
- **Doc 09 §7.3 building roster (9 .tres files)** — `hq`, `supply_depot`, `barracks`, `forge`, `factory`, `arcanum`, `temple`, `refinery`, `turret`. Stats per §7.3 table.
- **`EntityLibrary` autoload** (`scripts/combat/entity_library.gd`) — scans `data/units/` and `data/buildings/` at boot, indexes by `unit_id` / `build_id`. Lookups: `unit(id)`, `building(id)`, `all_unit_ids()`, `all_building_ids()`, `units_by_category(cat)`, `buildings_by_category(cat)`. Boot log: `[RTSMVP] EntityLibrary: 7 units, 9 buildings loaded`.
- 9 new GUT cases (`test_entity_library`) pin presence + key stat fields. Total: **196/196** green.

### Notes
- Loading is greedy at autoload `_ready`; the 16-file roster takes ~5 ms in the headless boot trace.
- No spawner consumes these defs yet. v0.9.5+ wires UnitDef → CharacterBody3D spawn factory; production buildings (v0.10) read BuildingDef for cost / supply / produces lists.

## [v0.9.3] — 2026-05-10

### Added
- **`FactionState` Resource (doc 09 §11)** — `faction_id`, `minerals`, `gas`, `supply_used`, `supply_max`, `current_tier`, `alive_units`, `alive_buildings`, `research_complete`, `production_queues`, `buildings_completed`. Helpers: `has_resources`, `spend`, `refund`, `supply_available`, `tech_state_snapshot`, `to_dict`.
- **`GameState` autoload extended with faction registry** — `get_faction(id)`, `all_factions()`, `current_tier(faction_id)`, `is_unit_buildable(faction_id, unit_id)`. `mark_match_started` now seeds a default `player` faction (50 minerals, 10 supply cap, tier 1) so the LLM snapshot has something to read on the first frame.
- **`BattlefieldSnapshotBuilder` now surfaces `tech_state` and `economy`** — the deputy can finally see "do we tech up or push now?" data per vision §2.2.
- 10 new GUT cases (`test_faction_state` covers Resource helpers + GameState autoload integration). Total: **187/187** green.

### Notes
- No production runtime yet — the `production_queues` dict and `is_unit_buildable` will gain real prereq + cost validation when worker construction + factory buildings ship (v0.9.4+).
- v1 vision §2 says "shared mirror roster" — only one faction (`player`) is seeded at runtime. Multi-faction splitting is doc 09+1.

## [v0.9.2] — 2026-05-10

### Added
- **Doc 09 §9 OrderTypeRegistry extension** — 7 new order types registered on bootstrap: `gather` (worker → resource node), `return_cargo`, `build` (worker → place a building), `train` (production building → queue a unit), `research`, `set_rally`, `cancel_production`. Combined with spec 07's 5 core verbs, the registry now holds **12** order types.
- Each new type ships its param schema (e.g. `build` requires `build_id: string` and `position: vector3`; `gather` requires `node_id: string`) so `CommandBus.submit_orders` rejects malformed orders before they hit any executor.
- 5 new GUT cases (`test_order_types_09`). Total: **177/177** green.
- Headless boot log line updated from "registered 5 core types" to **"registered 12 order types"**.

### Notes
- No executor exists yet for the 7 new verbs — `OrderExecutor` only handles `move`/`attack`/`stop`/`hold`. Submitting `gather` or `build` accepts at the bus and emits `order_issued`, but executors no-op. v0.9.3 adds the worker gather loop; `train` / `research` / `set_rally` / `cancel_production` ship with the production-building runtime in v0.9.3+.

## [v0.9.1] — 2026-05-10

### Added
- **Doc 09 §3.2 / §7.1 Resource schemas** — `scripts/combat/unit_def.gd` (UnitDef) and `scripts/combat/building_def.gd` (BuildingDef). Per-unit / per-building .tres files ship alongside the roster pass (v0.9.3+); v0.9.1 lands the data shape only.
- **Doc 09 §4 combat math** — `scripts/combat/damage_matrix.gd` (DamageMatrix) holds the 4×5 dmg_type × armor_class multiplier table. `compute(base_dmg, dmg_type, armor_class, flat_armor)` follows `max(0, base × matrix − armor)` with truncate-toward-zero on the fractional result. `default_matrix()` factory seeds the canonical v1 numbers from §4.3.
- **`data/combat/damage_matrix.tres`** — seeded with the canonical matrix so designers can edit it without touching code.
- **`CombatService` autoload** (`scripts/combat/combat_service.gd`) — loads `damage_matrix.tres` on `_ready`; `resolve_damage(attacker, target, base_dmg = -1)` reads attacker `dmg`/`dmg_type` and target `armor_class`/`armor` and returns the final int.
- **`SquadUnit` / `EnemyBuilding` integration** — both gain `armor_class`, `armor`, `dmg_type`, `dmg` exports. Squad capsules default to `heavy` armor (closest to doc 09 §3.3 `frontline_basic`). Buildings default to `structure`. `EnemyBuilding`'s defensive attack now routes through `CombatService.resolve_damage` — so a turret firing `normal` at a `heavy` capsule gets the 1.25× counter bonus before flat armor subtraction.
- 9 new GUT cases (`test_damage_matrix` + CombatService sanity). Total: **172/172** green.

### Notes
- Hero is not yet annotated with `hero` armor class — it's still invincible (not in `squad_units` group). When hero damage lands (paired with spec 11 §7.2's "hero takes big hit → big shake"), it'll inherit the same export shape and route through `CombatService`.
- The 7-unit and 9-building rosters from doc 09 §3.3 + §7.3 are not yet `.tres` files. v0.9.1 ships the schema; the .tres pack ships when the spawner/economy layer needs them in v0.9.3.

## [v0.9.0] — 2026-05-10

### Added
- **Enemy buildings fight back (spec 09 §7 + §4 combat-math slice)** — `EnemyBuilding` gains `attack_range` (6 m), `attack_damage` (10), `attack_interval` (0.85 s), and `attack_enabled` (`@export`). Each frame the building scans `squad_units` group, picks the nearest alive friendly within range, and calls `take_damage(attack_damage, self)`. Cooldown enforced. New `attacked_target(target_id, damage)` signal.
- **Damage attribution** — `SquadUnit.take_damage(amount, source)` now records the attacker; on death the `EventBus.publish_unit_destroyed` payload's `killer_id` names the attacking entity (building_id, unit_id, or node name in that order).
- 7 new GUT cases (`test_enemy_attack`) covering nearest-target, out-of-range, dead-unit skip, attack tick, cooldown, attack_enabled flag, destroyed-building no-fire. Total: **163/163** green.

### Changed
- The combat loop is now real two-sided. Hero / squad attack a building → building deals 10 dmg every 0.85 s back at the closest squad unit in 6 m. Squad HP 100 vs building HP 60 with 20-dps hero + small squad means buildings still go down first, but units start showing damage and can die from extended exposure.

### Notes
- Targeting is purely range-based. No threat / aggro logic yet (spec 09 §4 hints at it but doesn't define one). When doc-09 §3 unit categories ship, this becomes a per-category targeting policy.
- No projectile travel — damage applies instantly on the firing tick. Visible muzzle flash / projectile arc deferred until art / VFX layer.
- Hero is currently invincible (not in `squad_units` group). Hero damage taken is spec 11 §7.2 territory and gates the "big screen shake on hero hit" trigger — paired work for a later slice.

## [v0.8.3] — 2026-05-10

### Added
- **Physics layer registry (spec 11 §2.1)** — `scripts/physics_layers.gd` is the canonical mapping from layer name → index (terrain=1, enemy_structure=2, friendly_unit=3, hero=4, enemy_unit=5, friendly_structure=6, corpse=7, soul=8, attack_player=9, attack_enemy=10, cursor_pick=11). Also exports pre-composed masks (`MASK_HERO_COLLISION`, `MASK_FRIENDLY_UNIT_COLLISION`, `MASK_MOUSE_PICK`) for code paths that need to build collision masks at runtime.
- `project.godot` `[layer_names]` block names the 11 layers so they're labeled in the editor's Inspector pickers instead of bare "Layer 5".
- 4 new GUT cases pin the index/bit contract — if any layer shifts, the test fails. Total: **156/156** green.

### Notes
- v0.8.3 is documentation + plumbing only. Existing scenes' numeric `collision_layer` / `collision_mask` values are unchanged, so no behavior moved.
- Layers `enemy_unit`, `friendly_structure`, `corpse`, `soul`, `attack_*` are pre-reserved but currently empty — they fill in as 09 ships unit / building / corpse / projectile types.

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
