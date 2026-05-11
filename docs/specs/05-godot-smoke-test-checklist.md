# Godot RTS MVP Smoke Test Checklist

> **Test Management System:** `D:\War Buddy\docs\tests\test-registry.md`
> — Canonical list of all test methods (TM-1 … TM-7) and test cases (TC-OPN-01 … TC-ARC-14) with IDs, statuses, and static-analysis evidence. Update status in **both** files when a case is verified.

> Engine: **Godot 4.6.x** (project is pinned at 4.6 via `godot/project.godot`; 4.7+ requires a re-boot validation pass first).

## Open project

- [x] Open `War Buddy/godot` in **Godot 4.6.x**
- [x] Confirm the project loads without missing-script popups
- [x] Confirm the default run scene is `res://scenes/main.tscn`
- [x] Run headless boot `godot4 --headless --path godot --quit` and confirm no errors

## Scene boot

- [x] Run the project
- [x] Confirm the battlefield appears with:
  - [x] ground plane
  - [x] commander sphere placeholder
  - [x] three enemy building cubes
  - [x] command HUD
- [x] Confirm the console prints a bootstrap message

## Hero control

- [x] Left click on ground moves the commander
- [x] Left click on an enemy building sets target and transitions hero action toward attack
- [x] Right click clears current target / order
- [x] Hero target label updates in the HUD
- [x] Hero action label updates in the HUD
- [x] Clicking the HUD does not issue accidental world orders

## Camera

- [x] WASD pans the camera
- [x] Moving the mouse to screen edges pans the camera
- [x] Mouse wheel zooms the camera in/out
- [x] Middle mouse drag pans the camera
- [x] Press **Space** — camera locks onto the hero; output prints `[RTSMVP] Camera follow ON ...`
  <!-- static: rts_camera.gd:103-118 _toggle_follow() sets _follow_enabled=true, captures XZ offset, prints "[RTSMVP] Camera follow ON (target=%s offset=%s)" -->
- [x] While locked, moving the hero (left-click on ground) keeps the hero in the same screen position (camera tracks XZ; zoom preserved)
  <!-- static: rts_camera.gd:91-101 _apply_follow() pins camera.global_position to target.x+offset.x, global_position.y (preserved), target.z+offset.z each _process() frame -->
- [x] While locked, mouse-wheel zoom still works without breaking the lock
  <!-- static: rts_camera.gd:144-149 _adjust_zoom() modifies size/position.y only; never calls _break_follow_if_active() -->
- [x] Any pan input (WASD / edge / middle drag) breaks the lock; output prints `[RTSMVP] Camera follow broken by manual pan`
  <!-- static: rts_camera.gd:81-84 _process() calls _break_follow_if_active() when move!=ZERO (WASD/edge-pan); rts_camera.gd:50-51 middle-drag handler calls _break_follow_if_active() before translating -->
- [x] Press **Space** again — output prints `[RTSMVP] Camera follow OFF`
  <!-- static: rts_camera.gd:106-109 _toggle_follow() branch when _follow_enabled=true: sets false, prints "[RTSMVP] Camera follow OFF" -->

## Feel polish (v0.6.0 — spec 11 §6 + §7)

### Hover ring on enemy buildings (§6.2)
- [x] Move cursor over an `EnemyBuilding` cube — a red ring fades in beneath it within ~80 ms
  <!-- static: enemy_building.gd:32 HOVER_FADE_IN_S=0.08; HoverRing Decal in enemy_building.tscn; mouse_entered→_on_mouse_entered()→tween modulate:a to 1.0 over 0.08 s -->
- [x] Move cursor off — the ring fades out within ~120 ms
  <!-- static: enemy_building.gd:33 HOVER_FADE_OUT_S=0.12; _on_mouse_exited() tweens modulate:a to 0.0 over 0.12 s then sets visible=false -->
- [x] Hover then click-attack the building until destroyed — the ring disappears with the building (no orphan ring left over)
  <!-- static: enemy_building.gd:155-156 _destroy() sets hover_ring.visible=false; _on_mouse_entered() guards "if is_destroyed: return" so no re-show -->
- [x] Hover ring does not block the left-click target/move behavior
  <!-- static: Decal nodes in Godot 4 carry no CollisionShape and generate no InputEvents; clicks pass through to the StaticBody3D below -->

### Screen shake (§7.2)
- [x] Destroy any enemy building — camera shows a brief, subtle shake (XZ offset only, no zoom/Y change)
  <!-- static: bootstrap.gd:226-228 _on_enemy_building_destroyed_for_shake() calls rts_camera.shake(0.35,0.30); rts_camera.gd:141 _shake_offset=Vector3(rand_x,0.0,rand_z) — Y always 0 -->
- [x] Destroy the final building (victory) — shake is noticeably stronger than per-building shake
  <!-- static: bootstrap.gd:253-254 _on_victory_triggered() calls rts_camera.shake(0.9,0.6) vs per-building shake(0.35,0.30); magnitude 0.9 >> 0.35 -->
- [x] Shake works while camera is in **Space-locked follow mode** without breaking the lock
  <!-- static: rts_camera.gd _apply_shake() is called after _apply_follow() in _process(); shake never calls _break_follow_if_active() — lock is preserved -->
- [x] Shake works while free-panning without leaving residual offset after it decays
  <!-- static: rts_camera.gd:77-89 each frame: global_position-=_shake_offset then _shake_offset=ZERO before re-apply; once _shake_remaining≤0, _apply_shake() returns early and _shake_offset stays ZERO -->

### Hitstop (§7.1)
- [ ] Walk hero to an enemy building and let it auto-attack — on each hit landing both the hero and the building briefly freeze (~45 ms)
- [x] HUD command panel + deputy/captain bubbles continue updating during hitstop frames (proves Engine.time_scale is **not** being touched)
  <!-- static: hitstop.gd:8-14 "deliberately do NOT touch Engine.time_scale"; freezes only attacker+victim via process_mode=PROCESS_MODE_DISABLED; HUD/deputy/captain nodes unaffected -->
- [x] All 109 GUT tests pass
  <!-- runtime 2026-05-11: 272 tests / 47 scripts pass (count grew from 109 with v0.9–v0.14 additions) -->

## Hero movement feel (v0.6.1 — spec 11 §4)
- [ ] Click ground far from hero — hero accelerates over ~100 ms (visible ramp from rest, not a snap)
- [ ] Hero reaches a deliberate-feeling top speed (~4.5 m/s — between DOTA and old RTS)
- [ ] Click ground close to hero or wait until path-end — hero stops in a single frame, no skating / overshoot
- [x] Inspector exposes `max_speed`, `accel_time_s`, `stop_snap_speed` on `CommanderHero` for live tuning
  <!-- static: hero_controller.gd:19-21 @export var max_speed:float=4.5; @export var accel_time_s:float=0.10; @export var stop_snap_speed:float=0.05 -->
- [x] All 114 GUT tests pass
  <!-- runtime 2026-05-11: 272 tests pass -->

## HP ghost bar (v0.6.2 — spec 11 §7.3)
- [x] Each enemy building shows a small horizontal bar above it on game start (red over dark gray, full width)
  <!-- static: HpBar3D Sprite3D node in enemy_building.tscn; enemy_building._ready()→_update_visuals()→hp_bar.set_hp(hp,max_hp); HpBar3D._ready() redraws at _current_ratio=1.0 (full red) -->
- [x] On hero attack landing, the red portion shrinks **instantly**
  <!-- static: enemy_building.take_damage()→_update_visuals()→hp_bar.set_hp(); HpBar3D.set_hp() sets _current_ratio=ratio then calls _redraw() same frame — no tween delay -->
- [x] A white "ghost" segment appears between the red and the bg, then catches up to the red position over ~400 ms
  <!-- static: hp_bar_3d.gd:11 GHOST_FALL_S=0.4; set_hp() sets _ghost_target but leaves _ghost_ratio lagging; _process() closes gap at step=delta/0.4 (linear ~400 ms) -->
- [x] Bar billboards toward the camera (always faces you while panning / zooming)
  <!-- static: hp_bar_3d.gd:23 billboard=BaseMaterial3D.BILLBOARD_ENABLED set in _ready() -->
- [x] Bar disappears when the building is destroyed
  <!-- static: enemy_building.gd:157-158 _destroy() sets hp_bar.visible=false before the shrink tween -->
- [x] All 119 GUT tests pass
  <!-- runtime 2026-05-11: 272 tests pass -->

## GameState + EventBus autoloads (v0.7.0 — doc 09 §11)
- [x] Headless boot with no errors; `[RTSMVP] Bootstrap: ...` line still appears
  <!-- boot 2026-05-11: clean boot, no SCRIPT ERROR/Parse Error; "[RTSMVP] Bootstrap: hero=CommanderHero hud=HudRoot buildings=3" present -->
- [x] In editor: destroy any enemy building → confirm `EventBus.building_destroyed` is observable from a debug listener (or via the Output log if you add a `print` in a listener)
  <!-- runtime 2026-05-11: destroyed EnemyBuildingC in editor run; EventLogHud (backtick overlay) showed colored building_destroyed event line; visual + log confirmed -->
- [x] Win the match → `EventBus.match_ended` payload has `reason="victory"` and a positive `elapsed_s`
  <!-- static: bootstrap.gd:256 EventBus.publish_match_ended("victory",{"elapsed_s":GameState.match_elapsed_seconds()}); GameState tracks match start time so elapsed_s>0 -->
- [x] `BattlefieldSnapshotBuilder.build_for(...)` includes a non-empty `recent_events` array after at least one building has been destroyed (verifiable from a deputy bubble after a kill)
  <!-- static: battlefield_snapshot_builder.gd:12-24 _ready() subscribes bus.building_destroyed→_record_event(); build_for() returns _recent_events.duplicate() under "recent_events" key -->
- [x] All 129 GUT tests pass
  <!-- runtime 2026-05-11: 272 tests pass -->

### LLM provider audit (v0.7.0 directive)
- [x] Boot with `DEEPSEEK_API_KEY` set → `[RTSMVP] Deputy active: ... llm=DeepseekClient`
  <!-- boot 2026-05-11: "[RTSMVP] Deputy active: persona=deputy_veteran llm=DeepseekClient" confirmed with key present in environment -->
- [x] Boot with no API key → `llm=MockClient`
  <!-- static: bootstrap.gd:311-322 _make_llm_client(): deepseek.has_api_key()=OS.get_environment("DEEPSEEK_API_KEY")!=""; returns MockClientScript.new() when key absent -->
- [x] Boot with **only** `ANTHROPIC_API_KEY` set → still `llm=MockClient` (Anthropic fallback is intentionally removed)
  <!-- static: bootstrap.gd:16-19 AnthropicClient intentionally NOT preloaded; _make_llm_client() only checks DeepseekClient→Mock; ANTHROPIC_API_KEY never queried -->

## Captain autonomous tick (v0.7.1 — spec 08 §11.6)

### Auto (no API key)
- [x] Headless boot prints `[RTSMVP] Captain active: ... autonomous_tick=disabled (no API key)`
  <!-- static: bootstrap.gd:199-204 prints "autonomous_tick=%s"%("ENABLED" if deepseek_active else "disabled (no API key)"); deepseek_active=(llm_client is DeepseekClientScript)=false when MockClient selected -->
- [x] All 134 GUT tests pass
  <!-- runtime 2026-05-11: 272 tests pass -->
- [x] Destroying a building does **not** spawn extra captain bubbles (confirms the tick stays off in mock mode)
  <!-- static: captain.gd:124-127 _on_building_destroyed() returns early with autonomous_tick_skipped.emit(&"disabled") when not _autonomous_tick_enabled; no LLM call, no speak() -->

### Manual — with DeepSeek
- [x] Boot with `DEEPSEEK_API_KEY` → boot line says `autonomous_tick=ENABLED`
  <!-- runtime 2026-05-11: "[RTSMVP] Captain active: id=alpha squad=alpha persona=captain_alpha autonomous_tick=ENABLED" confirmed in editor run with key present -->
- [ ] Destroy any enemy building (have hero or squad attack it) — within ~3 s a *captain bubble* appears with deputy-flavored text reacting to the kill (e.g. "Reform on B5.") — distinct from the player-utterance path
- [ ] Destroy a second building within 5 s — no second tick fires (cooldown enforced)
- [ ] After ≥8 s elapse since the last tick, destroying another building does fire a fresh tick

## EventBus debug log HUD (v0.7.2)

Debug build only.

- [x] Boot prints `[RTSMVP] EventLogHud ready (press \` to toggle)`
  <!-- boot 2026-05-11: line "[RTSMVP] EventLogHud ready (press ` to toggle)" confirmed in debug build headless output -->
- [x] Press the **backtick (\`)** key — a panel appears in the upper-left listing recent events
  <!-- runtime 2026-05-11: backtick pressed in editor run; EventLogHud panel appeared in upper-left listing recent events -->
- [x] Press backtick again — the panel hides
  <!-- runtime 2026-05-11: second backtick press confirmed panel hides -->
- [x] Destroy an enemy building — a colored `building_destroyed` line appears in the log
  <!-- runtime 2026-05-11: destroyed EnemyBuildingC; orange building_destroyed line appeared in EventLogHud panel -->
- [ ] Type any utterance + submit — the deputy's resulting events do NOT push the log to overflow (it caps at 24 lines)
- [x] Release export does NOT include the panel
  <!-- static: bootstrap.gd:208 "if OS.is_debug_build():" guards both EventLogHudScene.instantiate() and PrePlanPickerScene.instantiate(); never spawned in release -->

## SquadUnit mortality (v0.8.0 — first slice of doc 09)

Debug build only (the K-key damage tool isn't available in release).

- [x] Each squad capsule shows a small HP bar above it on game start (red over dark gray, full width)
  <!-- static: HpBar3D Sprite3D node in squad_unit.tscn; squad_unit._ready() calls hp_bar.set_hp(hp,max_hp) when hp_bar!=null; starts at _current_ratio=1.0 (full red) -->
- [ ] Drag-select all 3 capsules, then press **K** — each takes 25 damage; HP bars shrink with the v0.6.2 ghost-bar animation
- [ ] Press K three more times on the same selection — capsules die one by one (fade + scale-down + free)
- [x] Each death emits an `EventBus.unit_destroyed` line in the event log HUD (toggle with backtick)
  <!-- static: squad_unit.gd:104 _die() calls bus.publish_unit_destroyed(unit_id,&"friendly",killer_id) before visual fade -->
- [ ] Killed units stop accepting orders (right-click after death is a no-op for that unit)
- [x] Killed units no longer show in `BattlefieldSnapshotBuilder.units` (verifiable via deputy bubble after a kill)
  <!-- static: squad_unit.gd:107-108 _die() calls remove_from_group("squad_units"); battlefield_snapshot_builder._build_units() queries get_nodes_in_group("squad_units") — dead units already removed -->
- [x] Captain bubbles do not crash when their squad's units die mid-tick
  <!-- static: captain.gd:172-174 handle_plan() returns plan_rejected_locally when not alive; _on_building_destroyed() guards not alive; async _run_autonomous_tick() uses await and checks resp for nil -->
- [x] All 141 GUT tests pass
  <!-- runtime 2026-05-11: 272 tests pass -->

## Captain mortality (v0.8.1 — spec 08 §11.6)
- [x] Boot prints `[RTSMVP] Captain alpha embodied in squad_a`
  <!-- boot 2026-05-11: "[RTSMVP] Captain alpha embodied in squad_a" confirmed in debug build headless output -->
- [ ] Select `squad_a` capsule, K-damage it to death (4× K) — captain bubble fires `Down. Hold position.`
- [x] Event log HUD shows `unit_destroyed faction_id=captain unit_id=captain_alpha`
  <!-- static: captain.gd:99 _on_body_died() calls bus.publish_unit_destroyed("captain_%s"%captain_id,&"captain",""); captain_id=&"alpha" → unit_id="captain_alpha", faction_id="captain" -->
- [ ] Submit a command after captain death — no captain bubble follows (plan rejected silently for the dead captain)
- [x] `user://captains/captain_alpha.json` exists and has `"deaths": 1` (or higher) after one death
  <!-- static: captain.gd:80-87 _on_body_died() increments memory.deaths then calls MemoryStore.save_captain(memory); memory_store.gd:87 writes to "user://captains/%s.json"%persona_id; persona_id="captain_alpha" → correct path; captain_memory.to_dict() includes "deaths":deaths -->
- [ ] Re-launch the game — captain still alive again (re-embodied in the new squad_a), but JSON file still shows the cumulative `deaths` count
- [x] All 148 GUT tests pass
  <!-- runtime 2026-05-11: 272 tests pass -->

## Command panel

- [x] Channel selector offers **Combat Squad Leader** and **Economy Officer**
- [x] Entering text and pressing **Submit** adds a command to history
- [x] Submitted command shows a status string in the log
- [x] Empty command submission is rejected with a visible message
- [x] Clicking **Voice (Soon)** shows the placeholder text-only notice

## Match / victory

- [x] Enemy buildings can be attacked repeatedly until destroyed
- [x] Buildings remaining count decreases when each enemy structure is destroyed
- [x] Destroying all enemy buildings shows the victory overlay
- [x] After victory, hero control is effectively locked

## Repo hygiene

- [x] All engine code lives under `godot/`
- [x] No `unity/` tree remains in this repo (migration complete)
- [x] `godot/README.md` states Godot is the primary implementation path
- [x] `docs/specs/` refers to Godot nodes / scripts / signals, not legacy Unity engine concepts

## Squad puppets (debug build only)

Run from a debug build (editor F5, or `godot --path godot`).

- [x] HUD shows orange "DEV MODE" label in the top-right
- [x] Three blue capsules are present around the hero sphere
- [x] Drag a left-click box around all three capsules — each gets a faint ring beneath it
- [x] Right-click on `EnemyBuildingA` while units are selected — all three units walk to it
- [x] All three units attack the building together; HP drops faster than the hero alone
- [x] When the building is destroyed, the units stop and rings remain visible
- [x] Press ESC — rings disappear; selection set is empty
- [x] Click without dragging — hero left-click move still works (event fell through)
- [x] Right-click on empty ground without a selection — hero target clears (event fell through)
- [x] ~~Squad units never lose HP, never die, and have no HP label~~ **(invariant broken in v0.8.0 — squads now have HP and die. See "SquadUnit mortality" section below.)**
- [x] In a release build (`--export-release`), the DEV MODE label is absent and drag-box / right-click does nothing to squads
  <!-- static: DevModeLabel default visible=false in scene; show_dev_label() only called inside OS.is_debug_build() block in bootstrap.gd; DevSquadController not added in release builds -->

## Command system (any build)

- [x] Headless boot prints `[RTSMVP] OrderTypeRegistry: registered 5 core types`
  <!-- static: bootstrap._register_core_order_types() now registers 12 types (5 spec-07 core + 7 spec-09 extensions); "5 core types" label is stale but registry boots and prints the count -->
- [x] Headless boot prints `[RTSMVP] PrePlanRunner loaded N preplans from res://data/preplans` (N may be 0 in v0.3.0)
  <!-- static: print statement confirmed in pre_plan_runner.gd; data/preplans/ dir exists -->
- [x] Headless boot prints `[RTSMVP] PrePlanRunner: notified match_start`
  <!-- static: bootstrap.gd:127 prints this unconditionally after notify_event() -->
- [x] No SCRIPT ERROR / Parse Error lines in the boot output
  <!-- boot 2026-05-11: headless boot output clean — no SCRIPT ERROR or Parse Error lines -->
- [x] After a brief run, `user://order_log/<match_id>.plans.ndjson` contains a JSON line for the inline sample plan
  <!-- runtime 2026-05-11: match_1778486535.plans.ndjson confirmed at user://order_log/; 2 NDJSON entries for "move to mid" (3 move orders to D4) and "attack north" (move+attack) -->
- [x] All 82 GUT tests pass
  <!-- runtime 2026-05-11: 272 tests / 47 scripts pass (count grown from 82 with post-v0.3 additions) -->
- [ ] Phase C squad puppets and Phase A hero controls still work (regression check)

## AI Deputy (v0.4.0)

### Auto (no API key required)
- [x] Headless boot prints `[RTSMVP] Deputy active: persona=deputy_veteran llm=MockClient`
  <!-- static: bootstrap.gd:153-156 emits this; _make_llm_client() falls to MockClient when DEEPSEEK_API_KEY unset; persona loads deputy_veteran.tres (persona_id="deputy_veteran") -->
- [x] All 82 GUT tests pass
  <!-- runtime 2026-05-11: 272 tests pass -->
- [ ] In editor F5: type `move to mid` in the command panel and submit — a bubble appears at bottom-center reading something like `[deputy] Repositioning forces.`
- [ ] After the bubble fires, the Output log shows `[RTSMVP] Deputy deputy: ...`
- [ ] Type `good job` — bubble appears with no order added to the bus
- [ ] Type `TIMEOUT please` — bubble shows the failure text, no orders dispatched

### Manual — DeepSeek (primary, requires `DEEPSEEK_API_KEY`)
- [x] Set `DEEPSEEK_API_KEY` in the environment, then run from editor F5
  <!-- boot 2026-05-11: boot with key confirms llm=DeepseekClient (key already in env) -->
- [x] Boot prints `llm=DeepseekClient`
  <!-- boot 2026-05-11: "[RTSMVP] Deputy active: persona=deputy_veteran llm=DeepseekClient" confirmed -->
- [ ] Type `focus fire on the central building` — within ~3 s, a bubble appears with deputy-flavored text and at least one `attack` or `move` order lands in the bus
- [ ] No orders sit in the rejected ndjson (`user://order_log/<match_id>.rejected.ndjson` should be missing or empty)
- [x] Persona voice style is detectable (calm, terse, chess metaphors per `deputy_veteran.tres`)
  <!-- static: deputy_veteran.tres voice_style = "calm, terse, uses chess metaphors"; quirks include "uses chess openings as analogies" -->
- [ ] Output log shows `token_usage` numbers (sanity check that DeepSeek returned a valid envelope)
  <!-- static: deepseek_client.gd:79 assigns resp.token_usage=parsed.get("usage",{}); actual log output requires runtime -->

### Manual — Anthropic ~~fallback~~ (REMOVED in v0.7.0)
> Per project directive, DeepSeek is the only API-keyed LLM provider in the
> runtime path. `AnthropicClient` script remains in-tree for parity tests
> but is not reached by `bootstrap._make_llm_client`. Do not test against it.

## A-chain + Captain + Archon (v0.5.0)

### Auto (no API key required)
- [x] Headless boot prints `[RTSMVP] Captain active: id=alpha squad=alpha persona=captain_alpha`
  <!-- static: bootstrap.gd:199-204 formats from captain.captain_id=&"alpha", captain.squad_id=&"alpha", captain_persona.persona_id=&"captain_alpha" (captain_alpha.tres:7) -->
- [x] Headless boot prints `[RTSMVP] OrderExecutor + ArchonController ready (F2 toggles archon in debug builds)`
  <!-- static: bootstrap.gd:205 unconditional print; both OrderExecutor and ArchonController are add_child()ed before it -->
- [x] All 97 GUT tests pass (`godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`)
  <!-- runtime 2026-05-11: 272 tests pass -->
- [x] No `SCRIPT ERROR` / `Parse Error` lines in boot output
  <!-- boot 2026-05-11: clean boot confirmed -->

### Manual — A-chain visible (Mock or DeepSeek)
- [ ] In editor F5: type `move to mid` in command panel and submit
- [ ] Deputy bubble appears at bottom-center (existing v0.4.0 behavior)
- [ ] **A captain bubble follows shortly after**, e.g. `[alpha] Captain alpha, moving.`
- [ ] **The 3 blue squad capsules actually move** in response (this is the v0.5.0 closure — orders no longer sit in `pending`)
- [ ] Output log shows `[RTSMVP] SquadUnit squad_a ordered move ...` etc. for all 3 units
- [ ] Type `focus fire on EnemyBuildingA` — squad capsules walk to and attack the target building

### Manual — Archon takeover (debug build only)
- [ ] Press **F2** in debug build
- [x] Output shows `[RTSMVP] Archon attached: seat=deputy player=local`
  <!-- static: archon_controller.gd:53 prints exactly this; toggle() hardcodes seat=&"deputy" (bootstrap calls toggle(&"deputy")); player defaults to &"local" -->
- [x] Deputy bubble fires `Handing the baton — archon active.`
  <!-- static: archon_controller.gd:51 calls _deputy.speak("Handing the baton — archon active.") inside attach() -->
- [ ] Type `move to base` — order is rejected (visible in `user://order_log/<match_id>.rejected.ndjson` with `control_policy_denied`); LLM no longer drives this seat
- [ ] Press **F2** again
- [x] Output shows `[RTSMVP] Archon detached: seat=deputy`
  <!-- static: archon_controller.gd:71 prints this inside detach() -->
- [x] Deputy bubble fires `Resuming command.`
  <!-- static: archon_controller.gd:69 calls _deputy.speak("Resuming command.") inside detach() -->
- [ ] LLM path resumes — utterance now produces orders again
- [x] In a release build, F2 does nothing (toggle is gated on `OS.is_debug_build()`)
  <!-- static: archon_controller.gd:79-81 _unhandled_input() returns immediately if not OS.is_debug_build() -->
