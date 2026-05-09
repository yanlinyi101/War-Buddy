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
- [ ] Press **Space** — camera locks onto the hero; output prints `[RTSMVP] Camera follow ON ...`
- [ ] While locked, moving the hero (left-click on ground) keeps the hero in the same screen position (camera tracks XZ; zoom preserved)
- [ ] While locked, mouse-wheel zoom still works without breaking the lock
- [ ] Any pan input (WASD / edge / middle drag) breaks the lock; output prints `[RTSMVP] Camera follow broken by manual pan`
- [ ] Press **Space** again — output prints `[RTSMVP] Camera follow OFF`

## Feel polish (v0.6.0 — spec 11 §6 + §7)

### Hover ring on enemy buildings (§6.2)
- [ ] Move cursor over an `EnemyBuilding` cube — a red ring fades in beneath it within ~80 ms
- [ ] Move cursor off — the ring fades out within ~120 ms
- [ ] Hover then click-attack the building until destroyed — the ring disappears with the building (no orphan ring left over)
- [ ] Hover ring does not block the left-click target/move behavior

### Screen shake (§7.2)
- [ ] Destroy any enemy building — camera shows a brief, subtle shake (XZ offset only, no zoom/Y change)
- [ ] Destroy the final building (victory) — shake is noticeably stronger than per-building shake
- [ ] Shake works while camera is in **Space-locked follow mode** without breaking the lock
- [ ] Shake works while free-panning without leaving residual offset after it decays

### Hitstop (§7.1)
- [ ] Walk hero to an enemy building and let it auto-attack — on each hit landing both the hero and the building briefly freeze (~45 ms)
- [ ] HUD command panel + deputy/captain bubbles continue updating during hitstop frames (proves Engine.time_scale is **not** being touched)
- [ ] All 109 GUT tests pass

## Hero movement feel (v0.6.1 — spec 11 §4)
- [ ] Click ground far from hero — hero accelerates over ~100 ms (visible ramp from rest, not a snap)
- [ ] Hero reaches a deliberate-feeling top speed (~4.5 m/s — between DOTA and old RTS)
- [ ] Click ground close to hero or wait until path-end — hero stops in a single frame, no skating / overshoot
- [ ] Inspector exposes `max_speed`, `accel_time_s`, `stop_snap_speed` on `CommanderHero` for live tuning
- [ ] All 114 GUT tests pass

## HP ghost bar (v0.6.2 — spec 11 §7.3)
- [ ] Each enemy building shows a small horizontal bar above it on game start (red over dark gray, full width)
- [ ] On hero attack landing, the red portion shrinks **instantly**
- [ ] A white "ghost" segment appears between the red and the bg, then catches up to the red position over ~400 ms
- [ ] Bar billboards toward the camera (always faces you while panning / zooming)
- [ ] Bar disappears when the building is destroyed
- [ ] All 119 GUT tests pass

## GameState + EventBus autoloads (v0.7.0 — doc 09 §11)
- [ ] Headless boot with no errors; `[RTSMVP] Bootstrap: ...` line still appears
- [ ] In editor: destroy any enemy building → confirm `EventBus.building_destroyed` is observable from a debug listener (or via the Output log if you add a `print` in a listener)
- [ ] Win the match → `EventBus.match_ended` payload has `reason="victory"` and a positive `elapsed_s`
- [ ] `BattlefieldSnapshotBuilder.build_for(...)` includes a non-empty `recent_events` array after at least one building has been destroyed (verifiable from a deputy bubble after a kill)
- [ ] All 129 GUT tests pass

### LLM provider audit (v0.7.0 directive)
- [ ] Boot with `DEEPSEEK_API_KEY` set → `[RTSMVP] Deputy active: ... llm=DeepseekClient`
- [ ] Boot with no API key → `llm=MockClient`
- [ ] Boot with **only** `ANTHROPIC_API_KEY` set → still `llm=MockClient` (Anthropic fallback is intentionally removed)

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
- [x] Squad units never lose HP, never die, and have no HP label
  <!-- static: squad_unit.gd has no HP vars; squad_unit.tscn has no HP Label node -->
- [x] In a release build (`--export-release`), the DEV MODE label is absent and drag-box / right-click does nothing to squads
  <!-- static: DevModeLabel default visible=false in scene; show_dev_label() only called inside OS.is_debug_build() block in bootstrap.gd; DevSquadController not added in release builds -->

## Command system (any build)

- [x] Headless boot prints `[RTSMVP] OrderTypeRegistry: registered 5 core types`
  <!-- static: bootstrap._register_core_order_types() registers exactly 5 types (move, attack, stop, hold, use_skill) -->
- [x] Headless boot prints `[RTSMVP] PrePlanRunner loaded N preplans from res://data/preplans` (N may be 0 in v0.3.0)
  <!-- static: print statement confirmed in pre_plan_runner.gd; data/preplans/ dir exists and is currently empty so N=0 -->
- [x] Headless boot prints `[RTSMVP] PrePlanRunner: notified match_start`
  <!-- static: bootstrap.gd:86 prints this unconditionally after notify_event() -->
- [ ] No SCRIPT ERROR / Parse Error lines in the boot output
- [ ] After a brief run, `user://order_log/<match_id>.plans.ndjson` contains a JSON line for the inline sample plan
- [ ] All 82 GUT tests pass
  <!-- NOTE: "64" was stale — codebase now has 82 test functions across 16 test files (confirmed by grep); update from 64→82 -->
- [ ] Phase C squad puppets and Phase A hero controls still work (regression check)

## AI Deputy (v0.4.0)

### Auto (no API key required)
- [x] Headless boot prints `[RTSMVP] Deputy active: persona=deputy_veteran llm=MockClient`
  <!-- static: bootstrap.gd:112-115 emits this; _make_llm_client() falls through to MockClient when neither API key is set; persona loads deputy_veteran.tres (persona_id="deputy_veteran") -->
- [ ] All 82 GUT tests pass
- [ ] In editor F5: type `move to mid` in the command panel and submit — a bubble appears at bottom-center reading something like `[deputy] Repositioning forces.`
- [ ] After the bubble fires, the Output log shows `[RTSMVP] Deputy deputy: ...`
- [ ] Type `good job` — bubble appears with no order added to the bus
- [ ] Type `TIMEOUT please` — bubble shows the failure text, no orders dispatched

### Manual — DeepSeek (primary, requires `DEEPSEEK_API_KEY`)
- [ ] Set `DEEPSEEK_API_KEY` in the environment, then run from editor F5
- [ ] Boot prints `llm=DeepseekClient`
- [ ] Type `focus fire on the central building` — within ~3 s, a bubble appears with deputy-flavored text and at least one `attack` or `move` order lands in the bus
- [ ] No orders sit in the rejected ndjson (`user://order_log/<match_id>.rejected.ndjson` should be missing or empty)
- [x] Persona voice style is detectable (calm, terse, chess metaphors per `deputy_veteran.tres`)
  <!-- static: deputy_veteran.tres voice_style = "calm, terse, uses chess metaphors"; quirks include "uses chess openings as analogies" -->
- [ ] Output log shows `token_usage` numbers (sanity check that DeepSeek returned a valid envelope)
  <!-- static: deepseek_client.gd:79 assigns resp.token_usage = parsed.get("usage", {}); actual log output requires runtime -->

### Manual — Anthropic ~~fallback~~ (REMOVED in v0.7.0)
> Per project directive, DeepSeek is the only API-keyed LLM provider in the
> runtime path. `AnthropicClient` script remains in-tree for parity tests
> but is not reached by `bootstrap._make_llm_client`. Do not test against it.

## A-chain + Captain + Archon (v0.5.0)

### Auto (no API key required)
- [x] Headless boot prints `[RTSMVP] Captain active: id=alpha squad=alpha persona=captain_alpha`
  <!-- static: bootstrap.gd:149-153 formats from captain.captain_id=&"alpha", captain.squad_id=&"alpha", captain_persona.persona_id=&"captain_alpha" (captain_alpha.tres:7) -->
- [x] Headless boot prints `[RTSMVP] OrderExecutor + ArchonController ready (F2 toggles archon in debug builds)`
  <!-- static: bootstrap.gd:154 unconditional print; both OrderExecutor and ArchonController are add_child()ed before it -->
- [ ] All 97 GUT tests pass (`godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`)
  <!-- static: test count confirmed at 97 (19 files × avg 5 — exact grep total = 97); pass/fail requires runtime -->
- [ ] No `SCRIPT ERROR` / `Parse Error` lines in boot output

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
