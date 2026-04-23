# Godot RTS MVP Smoke Test Checklist

> Engine: **Godot 4.6.x** (project is pinned at 4.6 via `godot/project.godot`; 4.7+ requires a re-boot validation pass first).

## Open project

- [ ] Open `War Buddy/godot` in **Godot 4.6.x**
- [ ] Confirm the project loads without missing-script popups
- [ ] Confirm the default run scene is `res://scenes/main.tscn`
- [ ] Run headless boot `godot4 --headless --path godot --quit` and confirm no errors

## Scene boot

- [ ] Run the project
- [ ] Confirm the battlefield appears with:
  - [ ] ground plane
  - [ ] commander sphere placeholder
  - [ ] three enemy building cubes
  - [ ] command HUD
- [ ] Confirm the console prints a bootstrap message

## Hero control

- [ ] Left click on ground moves the commander
- [ ] Left click on an enemy building sets target and transitions hero action toward attack
- [ ] Right click clears current target / order
- [ ] Hero target label updates in the HUD
- [ ] Hero action label updates in the HUD
- [ ] Clicking the HUD does not issue accidental world orders

## Camera

- [ ] WASD pans the camera
- [ ] Moving the mouse to screen edges pans the camera
- [ ] Mouse wheel zooms the camera in/out
- [ ] Middle mouse drag pans the camera

## Command panel

- [ ] Channel selector offers **Combat Squad Leader** and **Economy Officer**
- [ ] Entering text and pressing **Submit** adds a command to history
- [ ] Submitted command shows a status string in the log
- [ ] Empty command submission is rejected with a visible message
- [ ] Clicking **Voice (Soon)** shows the placeholder text-only notice

## Match / victory

- [ ] Enemy buildings can be attacked repeatedly until destroyed
- [ ] Buildings remaining count decreases when each enemy structure is destroyed
- [ ] Destroying all enemy buildings shows the victory overlay
- [ ] After victory, hero control is effectively locked

## Repo hygiene

- [ ] All engine code lives under `godot/`
- [ ] No `unity/` tree remains in this repo (migration complete)
- [ ] `godot/README.md` states Godot is the primary implementation path
- [ ] `docs/specs/` refers to Godot nodes / scripts / signals, not Unity `MonoBehaviour` / scenes
