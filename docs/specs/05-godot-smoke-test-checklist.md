# Godot RTS MVP Smoke Test Checklist

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

### Manual — Anthropic (fallback, requires `ANTHROPIC_API_KEY` and **no** `DEEPSEEK_API_KEY`)
- [ ] Unset `DEEPSEEK_API_KEY`, set `ANTHROPIC_API_KEY`, then F5
- [ ] Boot prints `llm=AnthropicClient`
- [ ] Same utterance behavior as DeepSeek section
