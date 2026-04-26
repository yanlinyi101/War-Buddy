# RTS MVP Implementation Plan (Godot 4.x)

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to work through remaining tasks. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Maintain and extend the minimum playable commander-on-field RTS MVP inside the Godot graybox scene (`godot/scenes/main.tscn`) where the player controls one hero, submits deputy text commands, destroys enemy buildings, and triggers victory.

**Architecture:** Five focused Godot 4.6.x modules, each one a dedicated `.gd` script under `godot/scripts/`, wired together by `bootstrap.gd` in the root scene. Scenes live in `godot/scenes/`. The earlier Unity C# scaffold has been retired; the `unity/` tree is no longer a source of truth.

**Tech Stack:** Godot 4.6.x, GDScript, built-in signals, `CharacterBody3D` / `StaticBody3D` / `Camera3D` / `CanvasLayer`. No Unity / C# dependencies.

---

## File Structure

### Primary scripts (already present)
- `godot/scripts/bootstrap.gd` — scene-level wiring, validation, signal plumbing
- `godot/scripts/hero_controller.gd` — mouse-first move / target / attack loop (`CharacterBody3D`)
- `godot/scripts/hero_state.gd` — HUD-facing hero state model (health, target, action)
- `godot/scripts/command_log_model.gd` — authoritative deputy command store with timed status progression
- `godot/scripts/match_state.gd` — enemy building registry + one-shot victory trigger
- `godot/scripts/enemy_building.gd` — destructible `StaticBody3D` with HP + `destroyed` / `hp_changed` signals
- `godot/scripts/hud_root.gd` — `CanvasLayer` HUD: hero status, command panel, voice placeholder, victory overlay
- `godot/scripts/rts_camera.gd` — RTS pan/zoom camera (`Camera3D`)

### Primary scenes (already present)
- `godot/scenes/main.tscn` — root bootstrap scene (entry point)
- `godot/scenes/world.tscn` — graybox battlefield with ground plane, hero instance, enemy buildings
- `godot/scenes/commander_hero.tscn` — player-controlled commander placeholder
- `godot/scenes/enemy_building.tscn` — destructible structure placeholder

### Project config
- `godot/project.godot` — engine 4.6, main scene set to `res://scenes/main.tscn`, input map defines `command_submit`, `hero_stop`, `camera_pan_*`

---

## Status Summary

The MVP slice is **functionally complete** in Godot. See [`04-godot-unity-parity-checklist.md`](04-godot-unity-parity-checklist.md) for the migration outcome. The tasks below cover the remaining hardening and post-MVP work.

---

## Task 1: Replace direct raycast movement with `NavigationAgent3D`

**Files:**
- Modify: `godot/scripts/hero_controller.gd`
- Modify: `godot/scenes/world.tscn` (bake `NavigationRegion3D`)
- Modify: `godot/scenes/commander_hero.tscn` (add `NavigationAgent3D` child)

- [x] **Step 1: Add `NavigationRegion3D` covering the ground plane in `world.tscn` and bake the navmesh** — runtime bake via `bootstrap.gd`
- [x] **Step 2: Add `NavigationAgent3D` as a child of the commander hero**
- [x] **Step 3: Replace the direct `velocity = (target - position).normalized() * speed` path with `nav_agent.set_target_position(...)` and use `nav_agent.get_next_path_position()` per tick**
- [x] **Step 4: Smoke test** — headless boot clean; manual left-click path verification pending editor run
- [x] **Step 5: Commit**

```bash
git add godot/scripts/hero_controller.gd godot/scenes/commander_hero.tscn godot/scenes/world.tscn
git commit -m "feat(godot): switch hero movement to NavigationAgent3D"
```

---

## Task 2: Add headless command-lifecycle and match-state tests (GUT or built-in)

**Files:**
- Create: `godot/tests/test_command_log_model.gd`
- Create: `godot/tests/test_match_state.gd`
- Modify: `godot/project.godot` (register GUT plugin or a lightweight runner)

- [x] **Step 1: Pick a runner** — [GUT 9.6.0](https://github.com/bitwes/Gut) installed at `godot/addons/gut/`, enabled in `project.godot`
- [x] **Step 2: Write tests**

```gdscript
# test_command_log_model.gd
extends "res://addons/gut/test.gd"

func test_submit_creates_ordered_record_with_submitted_status():
    var model = preload("res://scripts/command_log_model.gd").new()
    var record = model.submit("combat", "focus fire on enemy hq")
    assert_eq(record.status, "submitted")
    assert_eq(model.recent.size(), 1)

func test_empty_text_is_rejected():
    var model = preload("res://scripts/command_log_model.gd").new()
    assert_false(model.submit("combat", "   "))
```

```gdscript
# test_match_state.gd
extends "res://addons/gut/test.gd"

func test_destroy_last_building_triggers_victory_once():
    var match_state = preload("res://scripts/match_state.gd").new()
    match_state.register_enemy_building("hq")
    match_state.register_enemy_building("tower")
    match_state.mark_destroyed("hq")
    match_state.mark_destroyed("tower")
    match_state.mark_destroyed("tower") # duplicate, must not retrigger
    assert_eq(match_state.enemy_buildings_remaining, 0)
    assert_true(match_state.is_victory)
    assert_eq(match_state.victory_trigger_count, 1)
```

- [x] **Step 3: Run headlessly** — `godot4 --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit` (wired into CI)
- [x] **Step 4: Implement any missing guards in `command_log_model.gd` / `match_state.gd` to make the tests pass** — existing code already passed
- [x] **Step 5: Commit**

```bash
git add godot/tests godot/project.godot
git commit -m "test(godot): add headless command + match state tests"
```

---

## Task 3: Harden HUD input routing

**Files:**
- Modify: `godot/scripts/hud_root.gd`
- Modify: `godot/scripts/hero_controller.gd`

- [x] **Step 1: Audit every `Control` in the HUD and confirm `mouse_filter = MOUSE_FILTER_STOP` on interactive widgets and `MOUSE_FILTER_IGNORE` on decorative containers** — v0.1.1 補完了 PanelContainer 漏審計（曾遺漏 `mouse_filter` 且因 `size_flags_vertical = 3` 撐滿，灰底既遮 3D 又吞點擊）
- [x] **Step 2: In `hero_controller.gd`, gate raycast input on `get_viewport().gui_get_hovered_control() == null`** — `hero_controller.gd:31`
- [x] **Step 3: Smoke test** — 手工 05 checklist 通過 (v0.1.1)
- [x] **Step 4: Commit**

---

## Task 4: In-world combat feedback polish

**Files:**
- Modify: `godot/scripts/enemy_building.gd`
- Modify: `godot/scenes/enemy_building.tscn`

- [x] **Step 1: Add a `Label3D` or `ProgressBar3D` child showing HP, driven by the `hp_changed` signal** — `enemy_building.tscn` 已挂 `HpLabel3D`，`enemy_building.gd::_update_visuals` 接 `hp_changed`
- [x] **Step 2: On `destroyed`, play a brief tween (scale-down / fade) before `queue_free()` so the destruction reads clearly** — `enemy_building.gd::_destroy` 0.35s scale + alpha tween
- [x] **Step 3: Smoke test** — 手工 05 checklist 通過 (v0.1.0)
- [x] **Step 4: Commit**

---

## Task 5: Minimum debug log sweep

**Files:**
- Modify: `godot/scripts/hero_controller.gd`
- Modify: `godot/scripts/command_log_model.gd`
- Modify: `godot/scripts/match_state.gd`
- Modify: `godot/scripts/bootstrap.gd`

- [x] **Step 1: Ensure each of the following prints exactly once at the right place:**

```gdscript
print("[RTSMVP] Hero input: move/target accepted at ", target_pos)
print("[RTSMVP] Command submitted: %s -> %s" % [channel, text])
print("[RTSMVP] Command status updated: %s -> %s" % [id, status])
print("[RTSMVP] Enemy building destroyed: ", building_id)
print("[RTSMVP] Victory triggered")
print("[RTSMVP] Bootstrap: hero=%s hud=%s buildings=%d" % [hero, hud, count])
```

- [x] **Step 2: Run the full manual acceptance flow from the smoke-test checklist and confirm the log stream reads cleanly**
- [x] **Step 3: Commit**

---

## Task 6: Final acceptance pass

- [x] Run headless boot: `godot4 --headless --path godot --quit` → no errors
- [x] Run headless tests (once Task 2 lands) → all green
- [x] Run manual acceptance per [`05-godot-smoke-test-checklist.md`](05-godot-smoke-test-checklist.md) → all items pass (v0.1.1: zoom + grey-panel patches re-pass)
- [x] Verify acceptance criteria 1-8 from [`01-rts-mvp-design.md`](01-rts-mvp-design.md) §10

---

## Open Questions / Preconditions

1. Decide whether the next migration target is further MVP polish or the larger economy/production sandbox (see parity checklist §"Still not at parity").
2. Decide on test framework (GUT vs hand-rolled `SceneTree` runner) before writing tests in Task 2.
3. Confirm target Godot patch version — project is currently pinned at 4.6.x via `project.godot`; bumping to 4.7.x requires a re-boot validation.

## Acceptance Mapping

- **Hero control module:** `hero_controller.gd`, `hero_state.gd` — Tasks 1, 3
- **Command console module:** `command_log_model.gd`, HUD bindings in `hud_root.gd` — Tasks 2, 3, 5
- **Match state module:** `match_state.gd`, `enemy_building.gd` — Tasks 2, 4, 5
- **Scene bootstrap module:** `bootstrap.gd` — Task 5
- **MVP HUD/UI layer:** `hud_root.gd` — Tasks 3, 4
- **Final acceptance:** Task 6
