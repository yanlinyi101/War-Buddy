# 06 — Phase C Design: Squad Puppets + Dev Validation Mode

**Status:** design approved 2026-04-26, awaiting implementation plan.
**Engine:** Godot 4.6.x. GDScript only.
**Milestone:** v0.2.

## 1. Context & Goal

v0.1.1 closes the commander-on-field MVP. The next milestone (v0.2) introduces **Squad units** as a new class of in-world entity, separate from the Hero, that will eventually be driven by an AI deputy in v0.3 (Phase D). Phase C's job is to land the *executor* side of that future seam: the Squad units themselves, their order interface, and a way to verify the interface works **without** building the deputy yet.

Per spec 03 §6, SquadAgent's role is to *consume* `Move / Attack / UseSkill / Retreat` orders, not to make decisions. Therefore:

- **Squad units in v0.2 are pure puppets.** They do nothing on their own. They have a method-level interface (`order_move(pos)`, `order_attack(target)`, `stop()`) and execute when called.
- **Players cannot command them in v0.2.** All player input still goes to the Hero. (Phase D will plug `command_log_model` → deputy → squad orders.)
- **A debug-build-only "validation mode"** lets the developer drag-box-select Squad units and right-click order them, exclusively to verify the order interface and execution wire up correctly.

Out of scope this phase: actual deputy / AI decision making, Squad unit death, named Squad groupings (`Squad` class with members[]), economy, production, networking. The LoL/WASD Hero control rework is also deferred — see `docs/future-features.md`.

## 2. Architecture

### 2.1 New modules

```
godot/scripts/squads/
  squad_unit.gd          # CharacterBody3D, NavigationAgent3D, attack code
  selection_set.gd       # RefCounted; list of currently-selected SquadUnit refs
godot/scripts/dev/
  dev_squad_controller.gd  # input handler: drag-box select + right-click order; debug build only

godot/scenes/
  squad_unit.tscn        # CapsuleMesh + Capsule shape + NavigationAgent3D + selection-ring Decal
```

`squad.gd` (the named-group abstraction in spec 03 §7) is intentionally **not** introduced this phase. v0.2 has only `SquadUnit` instances and a flat `SelectionSet`. The `Squad` class lands in Phase D when deputy commands need to address group identities.

### 2.2 Modified modules

- `godot/scripts/bootstrap.gd` — instantiate `SelectionSet`; spawn 3 SquadUnits next to Hero; if `OS.is_debug_build()`, instantiate `DevSquadController` and pass it the SelectionSet + camera + ground mask.
- `godot/scenes/world.tscn` — no direct change; SquadUnits are spawned at runtime in bootstrap (Hero's offset is determined at scene load, easier in code than in scene).
- `godot/scripts/match_state.gd` — already counts building destruction by listening to `EnemyBuilding.destroyed`; no change. SquadUnit-driven kills go through the same path.

### 2.3 No new autoloads

`EventBus`, `CommandBus`, `GameState` (spec 03 §3.3, §3.5) stay deferred to Phase D, when HUD ↔ deputy ↔ squad become three parties that need decoupling. v0.2 wires SelectionSet by direct reference from `bootstrap.gd`.

## 3. Components

### 3.1 SquadUnit (`squad_unit.gd`)

`CharacterBody3D`, mirrors most of `hero_controller.gd` but stripped of input handling.

```gdscript
class_name SquadUnit
extends CharacterBody3D

const MOVE_SPEED := 9.0
const ATTACK_RANGE := 2.8
const ATTACK_DAMAGE := 20
const ATTACK_INTERVAL := 0.75

@export var unit_id := "squad_unit"

var _move_target: Vector3
var _has_move_target := false
var _attack_target: Node = null  # EnemyBuilding
var _attack_cooldown := 0.0
var _is_selected := false

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var selection_ring: Decal = $SelectionRing  # hidden by default

# Public API — only entry points
func order_move(world_pos: Vector3) -> void
func order_attack(target: Node) -> void
func stop() -> void
func set_selected(value: bool) -> void

# Internals (mirror hero_controller._physics_process)
func _physics_process(delta: float) -> void
```

**Differences from `HeroController`:**
- No `_unhandled_input`. SquadUnit is order-driven, not click-driven.
- No HP, no `take_damage`. Invincible per design.
- `selection_ring` Decal toggled by `set_selected`.
- `unit_id` exposed for log lines (`[RTSMVP] SquadUnit %s ordered %s`).

**Visual:** CapsuleMesh height 1.4, radius 0.4. CapsuleShape3D matching. Albedo `Color(0.3, 0.5, 1.0)` — friendly blue. Selection ring = Decal with a circular texture, modulated white when visible, hidden via `visible = false` when not selected (cheaper than alpha animation; SC RTS standard look).

### 3.2 SelectionSet (`selection_set.gd`)

```gdscript
class_name SelectionSet
extends RefCounted

signal changed(units: Array[SquadUnit])

var _units: Array[SquadUnit] = []

func add(unit: SquadUnit) -> void
func remove(unit: SquadUnit) -> void
func clear() -> void
func contains(unit: SquadUnit) -> bool
func get_units() -> Array[SquadUnit]    # defensive copy
func size() -> int
```

`add` / `remove` call `unit.set_selected(...)` for visual feedback and emit `changed`.

### 3.3 DevSquadController (`dev_squad_controller.gd`)

Only registered when `OS.is_debug_build()` is true. Implements `_input(event)` — Godot's input pipeline always delivers `_input` before `_unhandled_input`, so this controller sees mouse events ahead of `hero_controller.gd`. It selectively calls `get_viewport().set_input_as_handled()` to consume an event (drag-box selection, right-click while units selected) and leaves it untouched otherwise (single click without drag, right-click with empty selection) so Hero still receives it.

Three behaviors:
1. **Drag-box select.** `MOUSE_BUTTON_LEFT` press → record start screen pos. Mouse motion past 8px threshold → enter "drag" state, render rectangle (Control overlay or a `Line2D` debug shape). Release → query all SquadUnits whose screen-projected position lies in the rect → replace SelectionSet (or shift+drag = additive).
2. **Click-without-drag fallthrough.** If release distance from press <8px, do **not** consume the event. Hero's `_unhandled_input` will receive it and execute the original left-click behavior.
3. **Right-click order on selected.** When SelectionSet non-empty: right-click ground → `order_move(world_pos)` for each; right-click `enemy_buildings` group → `order_attack(building)` for each.
4. **ESC** → SelectionSet.clear().

Signal: `dev_mode_active` always true while controller exists; HUD shows a "DEV MODE" label in the corner.

### 3.4 Bootstrap wiring (additions to `bootstrap.gd`)

Existing `bootstrap.gd` already binds `@onready var hero = $World/CommanderHero` and `@onready var world: Node3D = $World`. New code added at end of `_ready()`:

```gdscript
const SquadUnitScene = preload("res://scenes/squad_unit.tscn")
const DevSquadControllerScript = preload("res://scripts/dev/dev_squad_controller.gd")
const SelectionSetScript = preload("res://scripts/squads/selection_set.gd")

var selection_set = null
var dev_controller = null

func _ready() -> void:
    # ...existing setup unchanged through line 41...
    selection_set = SelectionSetScript.new()
    _spawn_squad_units()
    if OS.is_debug_build():
        dev_controller = DevSquadControllerScript.new()
        dev_controller.name = "DevSquadController"
        dev_controller.setup(selection_set, get_viewport().get_camera_3d(), world)
        add_child(dev_controller)
        hud.show_dev_label()  # adds "DEV MODE" indicator

func _spawn_squad_units() -> void:
    var offsets := [Vector3(-3, 0, 0), Vector3(3, 0, 0), Vector3(0, 0, 3)]
    for i in offsets.size():
        var unit = SquadUnitScene.instantiate()
        unit.unit_id = "squad_%c" % (97 + i)  # squad_a, squad_b, squad_c
        unit.position = hero.global_position + offsets[i]
        world.add_child(unit)
```

`DevSquadController.setup(selection_set, camera, world)` is a plain method (not a constructor); it stores references it needs at runtime. We avoid `_init` arguments so the script can also be instantiated by the editor.

## 4. Data Flow

### 4.1 Default play (release & debug)
```
Player left-click → hero_controller._unhandled_input → hero moves
Player right-click → hero_controller._unhandled_input → hero clears target
Squad units → idle (no `_process` decisions, no calls to order_* anywhere)
Hero attacks buildings → match_state ticks down → victory at 0
```

### 4.2 Validation mode (debug build only)
```
Player left-click drag → DevSquadController._input → SelectionSet.add(units in box)
                                                  → SquadUnit.set_selected(true) → ring shows
Player right-click on ground → DevSquadController._input
    → for each unit in SelectionSet: unit.order_move(point) → NavigationAgent3D paths
Player right-click on enemy_building → DevSquadController._input
    → for each unit in SelectionSet: unit.order_attack(building)
    → unit physics_process closes range → calls building.take_damage
    → building.hp_changed / building.destroyed propagate as before
    → match_state increments, unit.order_attack target now invalid → unit returns to idle
Player ESC → SelectionSet.clear() → set_selected(false) on all → rings hide
```

### 4.3 Hero / Squad coexistence
- Hero's `_unhandled_input` only sees the event if DevSquadController didn't consume it. Click-without-drag (release within 8px of press) is explicitly **not** consumed, preserving Hero's left-click move.
- Right-click is consumed by DevSquadController **only when SelectionSet is non-empty**. Otherwise it falls through to Hero's right-click cancel.

## 5. Error / Edge Handling

- **No SquadUnits in box.** SelectionSet.clear() runs anyway; new selection is empty; no orders dispatch on subsequent right-clicks (early return when `_units.is_empty()`).
- **Selected unit dies.** SquadUnits don't die in v0.2. The invariant holds: SelectionSet members are always valid.
- **Attack target destroyed mid-attack.** `SquadUnit._physics_process` checks `is_instance_valid(_attack_target) and not _attack_target.is_destroyed`. If false, sets `_attack_target = null` and stops; unit goes idle. (Mirrors hero_controller line 48.)
- **Hovering HUD during drag.** DevSquadController also gates on `get_viewport().gui_get_hovered_control() == null` like hero_controller.
- **Release build.** `OS.is_debug_build()` returns false in `--export-release` outputs; `dev_controller` stays null; players see SquadUnits but cannot command them. Hero still works.

## 6. Testing Plan

### 6.1 GUT (headless)

`godot/tests/test_squad_unit.gd`:
- `order_move` writes to `nav_agent.target_position`.
- `order_attack(building)` sets `_attack_target` and triggers physics process to close range (use a fake building stub in `add_child_autofree`).
- After fake building's `is_destroyed = true`, next `_physics_process` clears `_attack_target` and unit halts.
- `set_selected(true)` shows ring; `set_selected(false)` hides.
- Attack damage call: with stub building at ATTACK_RANGE - 0.1 and cooldown 0, after one tick `building.take_damage(20)` was invoked.

`godot/tests/test_selection_set.gd`:
- `add` then `contains` returns true.
- `add` same unit twice does not duplicate.
- `remove` after add empties.
- `clear` calls `set_selected(false)` on all members.
- `changed` signal emit count matches mutation count.

CI's existing GUT step picks these up automatically; we extend the assertion to "all 14+ tests passed."

### 6.2 Manual smoke (extension to `05-godot-smoke-test-checklist.md`)

New section "Squad puppets (debug build)":
- Boot `godot --path godot` (debug build) → see HUD "DEV MODE" indicator and 3 blue capsules around hero.
- Drag a box around all 3 → blue rings appear under each.
- Right-click on `EnemyBuildingA` → all 3 walk to it and start attacking; building HP drops at 3× rate.
- Building destroyed → all 3 stop, return to idle (rings still visible).
- Press ESC → rings hide; SelectionSet empty.
- Click without dragging → Hero left-click move still works (event fell through).
- Right-click without selection → Hero's clear-target still works.
- Run `--export-release` build → no "DEV MODE" indicator; left-click drag does nothing special; SquadUnits stand idle the whole match.

### 6.3 Verification of the milestone

v0.2 is "done" when:
1. Headless boot: zero SCRIPT ERROR (existing CI step).
2. GUT: all tests green including new squad / selection_set ones.
3. Manual smoke (debug): every item in §6.2 passes.
4. Release build verified: SquadUnits exist visually but are inert; no DEV mode UI.
5. CHANGELOG `[v0.2.0]` entry written; tag pushed; release.yml succeeds across Linux/Windows/Web.

## 7. Phase D handoff (preview, not in scope)

When deputy lands:
- `CommandLogModel.command_status_changed` → `submitted → received → pending_execution → executed` will gain a 5th transition.
- A new module `scripts/ai/deputy.gd` (or autoload `CommandBus`) parses pending commands into `Move(target_pos)` / `Attack(building_id)` and calls `SquadUnit.order_move/attack` directly.
- `DevSquadController` is **not** removed — it remains as a debugging tool to compare deputy behavior against hand-issued orders.

## 8. Critical Files

New:
- `godot/scripts/squads/squad_unit.gd`
- `godot/scripts/squads/selection_set.gd`
- `godot/scripts/dev/dev_squad_controller.gd`
- `godot/scenes/squad_unit.tscn`
- `godot/tests/test_squad_unit.gd`
- `godot/tests/test_selection_set.gd`

Modified:
- `godot/scripts/bootstrap.gd` (spawn squads, instantiate dev controller, dev-mode HUD label)
- `godot/scripts/hud_root.gd` (add `show_dev_label()`)
- `godot/scenes/main.tscn` (add the dev label Control inside HudRoot, hidden by default)
- `docs/specs/05-godot-smoke-test-checklist.md` (add "Squad puppets (debug build)" section)
- `CHANGELOG.md` (v0.2.0 entry)
- `docs/specs/02-rts-mvp-implementation-plan.md` or new `07-phase-c-implementation-plan.md` (the executable plan, written in the next step via writing-plans skill)
