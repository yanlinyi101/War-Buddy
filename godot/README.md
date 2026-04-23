# Godot RTS MVP

This directory is now the **primary implementation path** for the RTS MVP in `war-of-agents`.

## Direction

- **Godot 4.6.x is the active game client path**
- **Unity is legacy reference only**
- Existing Unity assets/code can still inform behavior and spec details, but they are no longer the source of truth for implementation

In plain English: the Unity house is still standing, but only so we can point at it and say, "don't rebuild that plumbing mistake."

## Current skeleton

- `project.godot` — Godot project entry
- `scenes/main.tscn` — root bootstrap scene
- `scenes/world.tscn` — graybox battlefield with hero + enemy buildings
- `scenes/commander_hero.tscn` — player-controlled commander placeholder
- `scenes/enemy_building.tscn` — destructible enemy structure placeholder
- `scripts/bootstrap.gd` — top-level scene wiring
- `scripts/hero_controller.gd` — mouse-first move / target / attack loop
- `scripts/hero_state.gd` — hero HUD-facing state model
- `scripts/command_log_model.gd` — deputy command submission + status tracking
- `scripts/match_state.gd` — enemy building registry + victory locking
- `scripts/hud_root.gd` — HUD bindings, command panel, voice placeholder, victory overlay

## MVP behavior in this phase

This skeleton already covers the minimum validation loop in graybox form:

1. Open the project in Godot 4.6.x
2. Run `main.tscn`
3. Left click ground to move the commander
4. Left click an enemy building to target and attack it
5. Submit a combat/economy text command in the HUD
6. Watch command history advance through placeholder statuses
7. Destroy all enemy buildings to trigger victory overlay and match lock

## Known limitations

This is now a **playable graybox MVP slice**, not just a bare scaffold.

Still not done:
- proper pathfinding/navigation
- polished art/assets beyond grayboxes
- real deputy AI execution
- voice input
- economy simulation
- production/build menus
- automated gameplay tests beyond smoke boot

Implemented in this parity pass:
- RTS camera pan/zoom controls
- HUD-safe click handling
- delayed command status progression
- in-world enemy building HP feedback
- victory input lock

## Next recommended steps

1. Replace direct raycast movement with `NavigationAgent3D`
2. Decide whether the next migration target is the documented MVP slice or the bigger Unity economy/production sandbox
3. If aiming beyond MVP parity, add resource nodes + workers + depots first
4. Add production/build menus after economy primitives exist
5. Add a small headless smoke harness that exercises command lifecycle timers and victory logic
