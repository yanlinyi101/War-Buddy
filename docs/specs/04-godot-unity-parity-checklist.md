# Godot Migration Parity Checklist — Unity → Godot 4.x

Date: 2026-04-23 (migration close-out)
Repo: `War Buddy` (extracted from `war-of-agents`)

## Status

**Migration complete for the RTS MVP commander slice.** Godot 4.6.x is now the sole implementation path. The Unity tree has been removed from this repo and survives only as historical spec text (see `03-godot-rts-architecture-reference.md`, whose gameplay architecture is engine-agnostic).

## What was audited during the final pass

The following historical Unity sources were compared against the current Godot implementation:
- the original Unity MVP scaffold (no longer in this repo)
- the original `rts-mvp-scene-hookup-checklist.md`
- `docs/specs/01-rts-mvp-design.md`
- `docs/specs/02-rts-mvp-implementation-plan.md`
- the live Godot code under `godot/scripts/*` and `godot/scenes/*`

## Scope call

The Unity codebase historically contained two layers:
1. a **bigger RTS scaffold** (selection, squads, workers, resources, production, building placement)
2. the **RTS MVP commander slice** used as the migration target

This migration delivered parity with **layer 2** — the explicitly approved commander MVP. Layer 1 remains future work; it was never the blocker for the approved MVP.

## Unity MVP feature points — confirmed covered in Godot

### Core MVP slice
- [x] Single controllable commander hero — `godot/scripts/hero_controller.gd` + `scenes/commander_hero.tscn`
- [x] Mouse-first move / target / attack loop — `hero_controller.gd`
- [x] Text command console with two channels (combat + economy) — `hud_root.gd` + `command_log_model.gd`
- [x] Command records with lifecycle states: submitted / received / pending execution — `command_log_model.gd`
- [x] Visible voice-command placeholder — `hud_root.gd`
- [x] Enemy building registry with destructible targets — `match_state.gd` + `enemy_building.gd`
- [x] Victory when all enemy buildings are destroyed — `match_state.gd`
- [x] Post-victory input lock — `bootstrap.gd` + `hero_controller.gd`
- [x] Minimal hero state shown in HUD — `hero_state.gd` + `hud_root.gd`
- [x] Bootstrap path with visible validation hooks — `bootstrap.gd`

### User-visible niceties
- [x] HUD clicks do not leak into world orders
- [x] Hybrid control extensibility beyond a single raw click path
- [x] Clear target / action feedback in the HUD
- [x] Non-deceptive placeholder messaging for voice input
- [x] Single authoritative match-state path (`match_state.gd`)
- [x] Debug-visible command and victory events
- [x] RTS-friendly camera (WASD, edge pan, middle-drag, wheel zoom) — `rts_camera.gd`
- [x] In-world enemy building HP feedback

## Still out of scope (inherited from the old Unity sandbox, not blockers)

These lived in the broader Unity RTS scaffold, are **not yet implemented in Godot**, and were explicitly not required for the commander MVP acceptance slice:
- [ ] multi-unit selection / drag-box selection
- [ ] squad assignment and recall hotkeys
- [ ] workers, gather/return loop, depots, resource nodes
- [ ] player economy storage and costs
- [ ] production queues and rally points
- [ ] building placement ghost / construction sites
- [ ] stop / hold / attack-move order vocabulary
- [ ] faction-wide RTS HUD panels for selected units / buildings
- [ ] `NavigationAgent3D` pathfinding (currently direct-move raycast — see task 1 in the implementation plan)

## Files that define the current Godot surface
- `godot/project.godot`
- `godot/scenes/main.tscn`
- `godot/scenes/world.tscn`
- `godot/scenes/commander_hero.tscn`
- `godot/scenes/enemy_building.tscn`
- `godot/scripts/bootstrap.gd`
- `godot/scripts/hero_controller.gd`
- `godot/scripts/hero_state.gd`
- `godot/scripts/command_log_model.gd`
- `godot/scripts/match_state.gd`
- `godot/scripts/enemy_building.gd`
- `godot/scripts/hud_root.gd`
- `godot/scripts/rts_camera.gd`

## Validation

Headless boot:
```bash
godot4 --headless --path godot --quit
```
Expected: project boots, bootstrap completes, no missing-script errors.

Manual acceptance: run through every item in `05-godot-smoke-test-checklist.md` against `main.tscn`.

## Bottom line

The documented Unity RTS MVP commander loop is fully represented in the Godot path: direct hero control, deputy command UI, fake-PVP building destruction, and victory closure all exist in Godot 4.6.x with usability gaps from the first port cleaned up.

If the next milestone targets parity with the **full legacy Unity RTS sandbox** rather than the approved MVP slice, the next major chunk is economy / production / building systems. That is a materially bigger piece of work, not a minor follow-up.
