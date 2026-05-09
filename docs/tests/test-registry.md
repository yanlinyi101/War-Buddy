# War Buddy — Test Registry

> **Absolute path:** `D:\War Buddy\docs\tests\test-registry.md`
> **Source checklist:** `D:\War Buddy\docs\specs\05-godot-smoke-test-checklist.md`
> **Project root:** `D:\War Buddy\`

This file is the single source of truth for all test methods and test cases.
The smoke-test checklist links here for traceability; status updates belong in **both** files.

---

## Test Methods

| ID   | Name                    | Trigger                                                                                     | Requires         |
|------|-------------------------|---------------------------------------------------------------------------------------------|------------------|
| TM-1 | Static Analysis         | Read source files, grep patterns, check scene/resource contents                             | Nothing          |
| TM-2 | Headless Boot           | `godot4 --headless --path godot --quit-after 120`                                           | Godot 4.6 CLI    |
| TM-3 | GUT Automated Tests     | `godot4 --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit` | Godot 4.6 CLI    |
| TM-4 | Editor Debug (F5)       | Open `godot/` in Godot 4.6 editor → Run (F5) — debug build, OS.is_debug_build() = true     | Godot 4.6 editor |
| TM-5 | Editor Release Export   | `godot4 --headless --path godot --export-release "Linux/X11" build/…`                     | Godot 4.6 + templates |
| TM-6 | API Manual — DeepSeek   | Set `DEEPSEEK_API_KEY` env var, then TM-4                                                   | DeepSeek API key |
| TM-7 | API Manual — Anthropic  | Unset `DEEPSEEK_API_KEY`, set `ANTHROPIC_API_KEY`, then TM-4                               | Anthropic API key |

**Status legend:**

| Symbol | Meaning                                      |
|--------|----------------------------------------------|
| ✅     | Verified — passed                            |
| ⬛     | Pending — not yet executed                   |
| 🔑     | Pending — requires API key or special env    |
| ❌     | Failed — needs fix before shipping           |

---

## Test Cases

### Group: Open Project (OPN)

| ID        | Description                                                   | Method | Status | Evidence / Notes                                                   |
|-----------|---------------------------------------------------------------|--------|--------|--------------------------------------------------------------------|
| TC-OPN-01 | Open `War Buddy/godot` in Godot 4.6.x without crash          | TM-4   | ✅     | Checklist confirmed                                                |
| TC-OPN-02 | Project loads with no missing-script popups                   | TM-4   | ✅     | Checklist confirmed                                                |
| TC-OPN-03 | Default run scene is `res://scenes/main.tscn`                 | TM-1   | ✅     | `project.godot` line 14: `run/main_scene="res://scenes/main.tscn"` |
| TC-OPN-04 | Headless boot exits with no errors                            | TM-2   | ✅     | Checklist confirmed                                                |

### Group: Scene Boot (SCN)

| ID        | Description                                                   | Method | Status | Evidence / Notes                        |
|-----------|---------------------------------------------------------------|--------|---------|-----------------------------------------|
| TC-SCN-01 | Project runs (F5 or headless)                                 | TM-4   | ✅     | Checklist confirmed                     |
| TC-SCN-02 | Ground plane present in battlefield                           | TM-4   | ✅     | Checklist confirmed                     |
| TC-SCN-03 | Commander sphere placeholder present                          | TM-4   | ✅     | Checklist confirmed                     |
| TC-SCN-04 | Three enemy building cubes present                            | TM-4   | ✅     | Checklist confirmed                     |
| TC-SCN-05 | Command HUD visible                                           | TM-4   | ✅     | Checklist confirmed                     |
| TC-SCN-06 | Console prints bootstrap message on startup                   | TM-4   | ✅     | Checklist confirmed                     |

### Group: Hero Control (HRO)

| ID        | Description                                                         | Method | Status | Evidence / Notes    |
|-----------|---------------------------------------------------------------------|--------|--------|---------------------|
| TC-HRO-01 | Left click on ground issues move order to commander                 | TM-4   | ✅     | Checklist confirmed |
| TC-HRO-02 | Left click on enemy building sets target and starts attack action   | TM-4   | ✅     | Checklist confirmed |
| TC-HRO-03 | Right click clears current target / cancels order                   | TM-4   | ✅     | Checklist confirmed |
| TC-HRO-04 | Hero target label in HUD updates on target change                   | TM-4   | ✅     | Checklist confirmed |
| TC-HRO-05 | Hero action label in HUD updates on action change                   | TM-4   | ✅     | Checklist confirmed |
| TC-HRO-06 | Clicking HUD elements does NOT issue accidental world-space orders  | TM-4   | ✅     | Checklist confirmed |

### Group: Camera (CAM)

| ID        | Description                                           | Method | Status | Evidence / Notes                                                  |
|-----------|-------------------------------------------------------|--------|--------|-------------------------------------------------------------------|
| TC-CAM-01 | WASD keys pan the camera                              | TM-1   | ✅     | WASD input actions in `project.godot`; runtime confirmed in checklist |
| TC-CAM-02 | Mouse moved to screen edge pans the camera            | TM-4   | ✅     | Checklist confirmed                                               |
| TC-CAM-03 | Mouse wheel zooms camera in/out                       | TM-4   | ✅     | Checklist confirmed                                               |
| TC-CAM-04 | Middle mouse button drag pans the camera              | TM-4   | ✅     | Checklist confirmed                                               |

### Group: Command Panel (CMD)

| ID        | Description                                                         | Method | Status | Evidence / Notes                                                        |
|-----------|---------------------------------------------------------------------|--------|--------|-------------------------------------------------------------------------|
| TC-CMD-01 | Channel selector has "Combat Squad Leader" and "Economy Officer"    | TM-1   | ✅     | `hud_root.gd:22-23` adds both items                                     |
| TC-CMD-02 | Submitting text adds command to history log                         | TM-4   | ✅     | Checklist confirmed                                                     |
| TC-CMD-03 | Submitted command shows a status string in the log                  | TM-4   | ✅     | Checklist confirmed                                                     |
| TC-CMD-04 | Submitting empty input is rejected with a visible message           | TM-1   | ✅     | `hud_root.gd:71-74` strips text; empty → status label message           |
| TC-CMD-05 | Clicking "Voice (Soon)" shows placeholder text; no active recording | TM-1   | ✅     | `hud_root.gd:82`: sets text "Voice command coming soon…"; no state flip |

### Group: Match / Victory (VIC)

| ID        | Description                                                       | Method | Status | Evidence / Notes    |
|-----------|-------------------------------------------------------------------|--------|--------|---------------------|
| TC-VIC-01 | Enemy buildings absorb repeated attacks until HP reaches zero     | TM-4   | ✅     | Checklist confirmed |
| TC-VIC-02 | "Buildings remaining" HUD counter decreases when a building dies  | TM-4   | ✅     | Checklist confirmed |
| TC-VIC-03 | Destroying all buildings shows victory overlay                    | TM-4   | ✅     | Checklist confirmed |
| TC-VIC-04 | After victory, hero movement / targeting is locked                | TM-4   | ✅     | Checklist confirmed |

### Group: Repo Hygiene (HYG)

| ID        | Description                                                                | Method | Status | Evidence / Notes                                                       |
|-----------|----------------------------------------------------------------------------|--------|--------|------------------------------------------------------------------------|
| TC-HYG-01 | All engine code lives under `godot/`                                       | TM-1   | ✅     | Directory listing confirms                                             |
| TC-HYG-02 | No `unity/` directory remains in the repo                                  | TM-1   | ✅     | `ls D:\War Buddy\` — no `unity/` entry                                 |
| TC-HYG-03 | `godot/README.md` states Godot is the primary implementation path          | TM-1   | ✅     | First line: "This directory is now the **primary implementation path**" |
| TC-HYG-04 | `docs/specs/` uses Godot terminology; no Unity engine artifacts            | TM-1   | ✅     | grep for MonoBehaviour / UnityEngine in docs/specs — no matches        |

### Group: Squad Puppets — Debug Build (SQD)

| ID        | Description                                                                           | Method | Status | Evidence / Notes                                                                                     |
|-----------|---------------------------------------------------------------------------------------|--------|--------|------------------------------------------------------------------------------------------------------|
| TC-SQD-01 | HUD shows orange "DEV MODE" label in top-right in debug build                        | TM-4   | ✅     | Checklist confirmed                                                                                  |
| TC-SQD-02 | Three blue capsule squad units appear around hero sphere                              | TM-4   | ✅     | Checklist confirmed                                                                                  |
| TC-SQD-03 | Drag left-click box selects all three capsules (faint ring beneath each)              | TM-4   | ✅     | Checklist confirmed                                                                                  |
| TC-SQD-04 | Right-click on EnemyBuildingA with units selected → all three walk to it             | TM-4   | ✅     | Checklist confirmed                                                                                  |
| TC-SQD-05 | All three units attack together; enemy HP drops faster than hero alone                | TM-4   | ✅     | Checklist confirmed                                                                                  |
| TC-SQD-06 | When building destroyed, units stop; rings remain visible                             | TM-4   | ✅     | Checklist confirmed                                                                                  |
| TC-SQD-07 | ESC clears selection; rings disappear                                                 | TM-4   | ✅     | Checklist confirmed                                                                                  |
| TC-SQD-08 | Single left click (no drag) still moves hero (event falls through)                   | TM-4   | ✅     | Checklist confirmed                                                                                  |
| TC-SQD-09 | Right-click on empty ground with no selection clears hero target (event falls through)| TM-4   | ✅     | Checklist confirmed                                                                                  |
| TC-SQD-10 | Squad units never lose HP, never die, no HP label                                    | TM-1   | ✅     | `squad_unit.gd` has no HP vars; `squad_unit.tscn` has no HP Label node                              |
| TC-SQD-11 | Release build: DEV MODE label absent; drag-box / right-click to squads does nothing  | TM-1   | ✅     | `DevModeLabel` default `visible=false`; `show_dev_label()` only inside `OS.is_debug_build()` block; `DevSquadController` not added in release |

### Group: Command System (SYS)

| ID        | Description                                                                              | Method | Status | Evidence / Notes                                                                                          |
|-----------|------------------------------------------------------------------------------------------|--------|--------|-----------------------------------------------------------------------------------------------------------|
| TC-SYS-01 | Boot prints `[RTSMVP] OrderTypeRegistry: registered 5 core types`                       | TM-1   | ✅     | `bootstrap._register_core_order_types()` registers exactly 5: move, attack, stop, hold, use_skill        |
| TC-SYS-02 | Boot prints `[RTSMVP] PrePlanRunner loaded N preplans from res://data/preplans`          | TM-1   | ✅     | Print confirmed in `pre_plan_runner.gd`; `data/preplans/` is empty → N=0 at v0.3.0                       |
| TC-SYS-03 | Boot prints `[RTSMVP] PrePlanRunner: notified match_start`                               | TM-1   | ✅     | `bootstrap.gd:86` unconditional print after `notify_event()`                                             |
| TC-SYS-04 | No `SCRIPT ERROR` / `Parse Error` lines in headless boot output                         | TM-2   | ⬛     | Requires headless run                                                                                     |
| TC-SYS-05 | `user://order_log/<match_id>.plans.ndjson` written with a JSON line for the sample plan  | TM-2   | ⬛     | Requires headless run; `command_bus.gd:145` writes to this path                                           |
| TC-SYS-06 | All 97 GUT tests pass                                                                    | TM-3   | ⬛     | Test count confirmed at 97 by grep; pass/fail requires runner                                             |
| TC-SYS-07 | Phase C squad puppets and Phase A hero controls still work (regression)                  | TM-4   | ⬛     | Full manual regression run required                                                                       |

### Group: AI Deputy — v0.4.0 (DEP)

| ID        | Description                                                                                      | Method | Status | Evidence / Notes                                                                                                   |
|-----------|--------------------------------------------------------------------------------------------------|--------|--------|--------------------------------------------------------------------------------------------------------------------|
| TC-DEP-01 | Boot prints `[RTSMVP] Deputy active: persona=deputy_veteran llm=MockClient` (no API key)        | TM-1   | ✅     | `bootstrap.gd:112-115`; `_make_llm_client()` falls back to MockClient; `deputy_veteran.tres` persona_id confirmed  |
| TC-DEP-02 | All 97 GUT tests pass                                                                            | TM-3   | ⬛     | Requires runner                                                                                                    |
| TC-DEP-03 | Submitting "move to mid" via command panel shows deputy bubble at bottom-center                  | TM-4   | ⬛     | Requires editor run                                                                                                |
| TC-DEP-04 | After deputy bubble fires, Output log shows `[RTSMVP] Deputy deputy: …`                        | TM-4   | ⬛     | `bootstrap.gd:205` prints this via `_on_deputy_spoke`                                                              |
| TC-DEP-05 | Submitting "good job" shows deputy bubble; no order added to CommandBus                         | TM-4   | ⬛     | Requires editor run                                                                                                |
| TC-DEP-06 | Submitting "TIMEOUT please" shows failure bubble; no orders dispatched                          | TM-4   | ⬛     | Requires editor run (MockClient timeout simulation)                                                                |
| TC-DEP-07 | Boot prints `llm=DeepseekClient` when `DEEPSEEK_API_KEY` is set                                | TM-6   | 🔑     | `bootstrap._make_llm_client()`: DeepSeek checked first                                                             |
| TC-DEP-08 | "focus fire on the central building" → deputy bubble + at least one attack/move order in bus    | TM-6   | 🔑     | Requires DeepSeek API key + editor run                                                                             |
| TC-DEP-09 | Persona voice style: calm, terse, chess metaphors detectable in deputy responses                | TM-1   | ✅     | `deputy_veteran.tres`: `voice_style = "calm, terse, uses chess metaphors"`; quirks include chess openings          |
| TC-DEP-10 | DeepSeek response includes `token_usage` numbers in Output log                                  | TM-6   | 🔑     | `deepseek_client.gd:79` assigns `resp.token_usage = parsed.get("usage", {})`; visible in log at runtime           |
| TC-DEP-11 | Boot prints `llm=AnthropicClient` when `ANTHROPIC_API_KEY` set and `DEEPSEEK_API_KEY` unset    | TM-7   | 🔑     | `bootstrap._make_llm_client()`: Anthropic is second in fallback chain                                              |
| TC-DEP-12 | Same utterance behavior as DeepSeek (bubble + orders) via Anthropic client                      | TM-7   | 🔑     | Requires Anthropic API key + editor run                                                                            |

### Group: A-chain + Captain + Archon — v0.5.0 (ARC)

| ID        | Description                                                                                     | Method | Status | Evidence / Notes                                                                                                      |
|-----------|-------------------------------------------------------------------------------------------------|--------|--------|-----------------------------------------------------------------------------------------------------------------------|
| TC-ARC-01 | Boot prints `[RTSMVP] Captain active: id=alpha squad=alpha persona=captain_alpha`               | TM-1   | ✅     | `bootstrap.gd:149-153`; `captain_alpha.tres` has `persona_id = &"captain_alpha"`                                     |
| TC-ARC-02 | Boot prints `[RTSMVP] OrderExecutor + ArchonController ready (F2 toggles archon in debug builds)` | TM-1 | ✅    | `bootstrap.gd:154` unconditional print after both `add_child()` calls                                                |
| TC-ARC-03 | All 97 GUT tests pass                                                                           | TM-3   | ⬛     | Test count confirmed at 97 by static grep; pass/fail requires runner                                                  |
| TC-ARC-04 | No `SCRIPT ERROR` / `Parse Error` lines in boot output                                         | TM-2   | ⬛     | Requires headless run                                                                                                 |
| TC-ARC-05 | "move to mid" → deputy bubble appears at bottom-center                                          | TM-4   | ⬛     | Existing v0.4.0 behavior; requires editor run                                                                         |
| TC-ARC-06 | Captain bubble follows deputy bubble (e.g. `[alpha] Captain alpha, moving.`)                   | TM-4   | ⬛     | Requires editor run                                                                                                   |
| TC-ARC-07 | Three squad capsules physically move in response to A-chain (v0.5.0 closure)                   | TM-4   | ⬛     | Output log must show `[RTSMVP] SquadUnit squad_a ordered move …` for all 3 units                                     |
| TC-ARC-08 | "focus fire on EnemyBuildingA" → capsules walk to and attack the building                       | TM-4   | ⬛     | Requires editor run                                                                                                   |
| TC-ARC-09 | Press F2 in debug build → Output shows `[RTSMVP] Archon attached: seat=deputy player=local`    | TM-1   | ✅     | `archon_controller.gd:53`; `toggle()` uses `&"deputy"`; player defaults `&"local"`                                   |
| TC-ARC-10 | After F2 attach → deputy bubble fires `Handing the baton — archon active.`                     | TM-1   | ✅     | `archon_controller.gd:51` calls `_deputy.speak("Handing the baton — archon active.")` inside `attach()`             |
| TC-ARC-11 | "move to base" while archon attached → order rejected with `control_policy_denied` in ndjson    | TM-4   | ⬛     | Requires editor run; `user://order_log/<match_id>.rejected.ndjson`                                                    |
| TC-ARC-12 | Press F2 again → Output shows `[RTSMVP] Archon detached: seat=deputy`; deputy bubble fires `Resuming command.` | TM-1 | ✅ | `archon_controller.gd:69-71` in `detach()`                                                              |
| TC-ARC-13 | LLM path resumes after archon detach — utterance produces orders again                          | TM-4   | ⬛     | Requires editor run                                                                                                   |
| TC-ARC-14 | Release build: F2 does nothing (archon toggle gated on `OS.is_debug_build()`)                  | TM-1   | ✅     | `archon_controller.gd:79-81`: `_unhandled_input()` returns immediately if not debug                                  |

---

## Summary

| Group              | Total | ✅ Verified | ⬛ Pending | 🔑 API |
|--------------------|-------|------------|-----------|--------|
| OPN — Open project | 4     | 4          | 0         | 0      |
| SCN — Scene boot   | 6     | 6          | 0         | 0      |
| HRO — Hero control | 6     | 6          | 0         | 0      |
| CAM — Camera       | 4     | 4          | 0         | 0      |
| CMD — Command panel| 5     | 5          | 0         | 0      |
| VIC — Victory      | 4     | 4          | 0         | 0      |
| HYG — Repo hygiene | 4     | 4          | 0         | 0      |
| SQD — Squad puppets| 11    | 11         | 0         | 0      |
| SYS — Cmd system   | 7     | 3          | 4         | 0      |
| DEP — AI Deputy    | 12    | 3          | 3         | 6      |
| ARC — Archon v0.5.0| 14    | 6          | 7         | 0      |
| **Total**          | **77**| **56**     | **14**    | **6**  |

*Last updated: 2026-05-08*
