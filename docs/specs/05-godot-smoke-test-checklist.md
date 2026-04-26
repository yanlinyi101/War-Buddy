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

- [ ] HUD shows orange "DEV MODE" label in the top-right
- [ ] Three blue capsules are present around the hero sphere
- [ ] Drag a left-click box around all three capsules — each gets a faint ring beneath it
- [ ] Right-click on `EnemyBuildingA` while units are selected — all three units walk to it
- [ ] All three units attack the building together; HP drops faster than the hero alone
- [ ] When the building is destroyed, the units stop and rings remain visible
- [ ] Press ESC — rings disappear; selection set is empty
- [ ] Click without dragging — hero left-click move still works (event fell through)
- [ ] Right-click on empty ground without a selection — hero target clears (event fell through)
- [ ] Squad units never lose HP, never die, and have no HP label
- [ ] In a release build (`--export-release`), the DEV MODE label is absent and drag-box / right-click does nothing to squads
