# Godot vs Unity RTS MVP parity checklist

Date: 2026-04-23
Repo: `war-of-agents`

## What was audited

Unity reference sources inspected:
- `unity/SharedOfficeWars/README.md`
- `unity/SharedOfficeWars/docs/rts-mvp-scene-hookup-checklist.md`
- `assets/architecture/UNITY_RTS_ARCH_v0.1.md`
- `docs/superpowers/specs/2026-04-01-rts-mvp-design.md`
- `docs/superpowers/plans/2026-04-02-rts-mvp-implementation.md`
- `unity/SharedOfficeWars/Assets/Scripts/RTSMVP/*`
- broader Unity RTS scaffold under `unity/SharedOfficeWars/Assets/Scripts/*`

## Important scope call

Unity contains two layers:
1. a **bigger RTS scaffold** (selection, squads, workers, resources, production, building placement)
2. the **RTS MVP commander slice** used for the migration target

This Godot parity pass targets the **commander-on-field RTS MVP slice** first, because that is the explicitly approved MVP in the repo docs. The larger Unity economy/production sandbox remains future work rather than a blocker for MVP parity.

## Unity MVP feature points

### Core MVP slice
- [x] Single controllable commander hero
- [x] Mouse-first move / target / attack loop
- [x] Text command console with two channels: combat + economy
- [x] Command records with lifecycle states: submitted / received / pending execution
- [x] Visible voice-command placeholder
- [x] Enemy building registry with destructible targets
- [x] Victory when all enemy buildings are destroyed
- [x] Post-victory input lock
- [x] Minimal hero state shown in HUD
- [x] Initialization/bootstrap path with visible validation hooks

### User-visible niceties present or implied in Unity MVP docs
- [x] HUD clicks should not issue world orders
- [x] Some hybrid control extensibility beyond a single raw click path
- [x] Clear target/action feedback
- [x] Clear placeholder messaging for voice input
- [x] One authoritative match-state path
- [x] Debug-visible command and victory events

## Godot status after this pass

### Achieved parity for the MVP slice
- [x] Graybox battlefield boots from `godot/scenes/main.tscn`
- [x] Commander hero can left-click move on ground
- [x] Commander hero can left-click enemy buildings to target and attack
- [x] Right-click cancels current target/order
- [x] HUD shows hero HP, target, and action
- [x] HUD offers Combat Squad Leader and Economy Officer channels
- [x] Text command submission works
- [x] Command history is authoritative and status progression now advances over time instead of instantly jumping
- [x] Voice placeholder is explicit and non-deceptive
- [x] Enemy buildings register into match state and are destroyed exactly once
- [x] Buildings remaining counter updates correctly
- [x] Victory overlay appears when the final enemy building is destroyed
- [x] Hero input locks after victory
- [x] HUD interaction no longer leaks through into world movement/attack clicks
- [x] Camera now supports RTS-friendly pan/zoom controls (WASD, edge pan, middle-drag, wheel zoom)
- [x] Enemy buildings now expose visible HP feedback in-world

### Still not at parity with the broader Unity sandbox
These exist in the larger Unity RTS scaffold, but are **not implemented in Godot yet** and were not required for the commander MVP acceptance slice:
- [ ] multi-unit selection / drag-box selection
- [ ] squad assignment and recall hotkeys
- [ ] workers, gather/return loop, depots, resource nodes
- [ ] player economy storage and costs
- [ ] production queues and rally points
- [ ] building placement ghost / construction sites
- [ ] stop/hold/attack-move order vocabulary
- [ ] faction-wide RTS HUD panels for selected units/buildings

## Files changed in this parity pass
- `godot/project.godot`
- `godot/scenes/enemy_building.tscn`
- `godot/scenes/main.tscn`
- `godot/scenes/world.tscn`
- `godot/scripts/bootstrap.gd`
- `godot/scripts/command_log_model.gd`
- `godot/scripts/enemy_building.gd`
- `godot/scripts/hero_controller.gd`
- `godot/scripts/hud_root.gd`
- `godot/scripts/rts_camera.gd`

## Validation run

Headless validation performed with:
```bash
godot4 --headless --path godot --quit
```

Observed result:
- project booted successfully
- bootstrap completed without missing-script errors

## Bottom line

Godot now matches the **documented Unity RTS MVP commander loop** closely enough for a serious parity pass: direct hero control, deputy command UI, fake-PVP building destruction, and victory closure all exist in the Godot path, with a few usability gaps cleaned up.

If the next milestone is parity with the **full legacy Unity RTS sandbox** rather than the approved MVP slice, the next major chunk is the economy/production/building systems. That is a materially bigger migration, not a tiny follow-up patch pretending to be humble.
