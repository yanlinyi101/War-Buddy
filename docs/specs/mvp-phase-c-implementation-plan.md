# Phase C — Squad Puppets + Dev Validation Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build SquadUnit puppets and a debug-build-only drag-box selection + right-click order tool that proves the order interface is correct, leaving Phase D's deputy a small seam to plug into.

**Architecture:** Two new GDScript modules under `godot/scripts/squads/` (SquadUnit, SelectionSet) and one under `godot/scripts/dev/` (DevSquadController). Bootstrap spawns 3 SquadUnits offset from the Hero; in debug builds it also adds the dev controller. No new autoloads — SelectionSet is held by reference from `bootstrap.gd`. Squad units mirror Hero combat parameters but expose only an order API (`order_move / order_attack / stop`) and have no HP.

**Tech Stack:** Godot 4.6.x, GDScript, GUT 9.6.0 (already in repo at `godot/addons/gut/`).

---

## File Structure

### New files
- `godot/scripts/squads/selection_set.gd` — `RefCounted`, list of selected SquadUnits with `add/remove/clear/contains/get_units/size` and a `changed` signal.
- `godot/scripts/squads/squad_unit.gd` — `CharacterBody3D` with `order_move / order_attack / stop / set_selected`. Mirrors Hero combat code; no input handling.
- `godot/scenes/squad_unit.tscn` — instantiable scene with mesh, collision, NavigationAgent3D, selection-ring Decal.
- `godot/scripts/dev/dev_squad_controller.gd` — `Node` registered in debug builds only. Implements `_input` for drag-box select + right-click orders. Stores camera + world refs via `setup(...)`.
- `godot/tests/test_selection_set.gd` — GUT cases for SelectionSet.
- `godot/tests/test_squad_unit.gd` — GUT cases for SquadUnit order interface.

### Modified files
- `godot/scripts/bootstrap.gd` — spawn 3 SquadUnits, instantiate SelectionSet, instantiate DevSquadController in debug builds, call `hud.show_dev_label()`.
- `godot/scripts/hud_root.gd` — add `show_dev_label()` method that flips a hidden Label visible.
- `godot/scenes/main.tscn` — add `DevModeLabel` Label inside HudRoot, `visible = false` by default, anchored top-right.
- `docs/specs/05-godot-smoke-test-checklist.md` — append "Squad puppets (debug build)" section.
- `CHANGELOG.md` — `[v0.2.0]` entry.

---

## Task 1: SelectionSet — pure logic, TDD friendly

**Files:**
- Create: `godot/tests/test_selection_set.gd`
- Create: `godot/scripts/squads/selection_set.gd`

- [ ] **Step 1: Create the test file with all 5 cases**

`godot/tests/test_selection_set.gd`:
```gdscript
extends "res://addons/gut/test.gd"

const SelectionSetScript = preload("res://scripts/squads/selection_set.gd")

# Use a stub that satisfies the SquadUnit duck-type SelectionSet calls
class FakeSquadUnit:
    extends Node
    var selected := false
    func set_selected(value: bool) -> void:
        selected = value

func _make_unit(id: String) -> FakeSquadUnit:
    var u := FakeSquadUnit.new()
    u.name = id
    add_child_autofree(u)
    return u

func test_add_then_contains_returns_true():
    var ss = SelectionSetScript.new()
    var u = _make_unit("a")
    ss.add(u)
    assert_true(ss.contains(u))
    assert_eq(ss.size(), 1)
    assert_true(u.selected)

func test_add_same_unit_twice_does_not_duplicate():
    var ss = SelectionSetScript.new()
    var u = _make_unit("a")
    ss.add(u)
    ss.add(u)
    assert_eq(ss.size(), 1)

func test_remove_after_add_empties_and_deselects():
    var ss = SelectionSetScript.new()
    var u = _make_unit("a")
    ss.add(u)
    ss.remove(u)
    assert_false(ss.contains(u))
    assert_eq(ss.size(), 0)
    assert_false(u.selected)

func test_clear_deselects_all_members():
    var ss = SelectionSetScript.new()
    var a = _make_unit("a")
    var b = _make_unit("b")
    ss.add(a)
    ss.add(b)
    ss.clear()
    assert_eq(ss.size(), 0)
    assert_false(a.selected)
    assert_false(b.selected)

func test_changed_signal_emit_count_matches_mutations():
    var ss = SelectionSetScript.new()
    watch_signals(ss)
    var a = _make_unit("a")
    var b = _make_unit("b")
    ss.add(a)        # +1
    ss.add(a)        # noop, no emit
    ss.add(b)        # +1
    ss.remove(a)     # +1
    ss.clear()       # +1 (still had b)
    assert_signal_emit_count(ss, "changed", 4)
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
cd "D:/War Buddy"
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```
Expected: parse / load error on `selection_set.gd` (file does not exist yet) or assertion failures.

- [ ] **Step 3: Implement `selection_set.gd`**

`godot/scripts/squads/selection_set.gd`:
```gdscript
class_name SelectionSet
extends RefCounted

signal changed(units: Array)

var _units: Array = []

func add(unit) -> void:
    if unit == null or _units.has(unit):
        return
    _units.append(unit)
    if unit.has_method("set_selected"):
        unit.set_selected(true)
    changed.emit(get_units())

func remove(unit) -> void:
    if not _units.has(unit):
        return
    _units.erase(unit)
    if unit != null and unit.has_method("set_selected"):
        unit.set_selected(false)
    changed.emit(get_units())

func clear() -> void:
    if _units.is_empty():
        return
    var snapshot := _units.duplicate()
    _units.clear()
    for unit in snapshot:
        if unit != null and unit.has_method("set_selected"):
            unit.set_selected(false)
    changed.emit(get_units())

func contains(unit) -> bool:
    return _units.has(unit)

func get_units() -> Array:
    return _units.duplicate()

func size() -> int:
    return _units.size()
```

- [ ] **Step 4: Run tests to confirm green**

```bash
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```
Expected: previous 10 tests still green + 5 new green = `Passing Tests 15`.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/squads/selection_set.gd godot/tests/test_selection_set.gd
git commit -m "feat(godot): add SelectionSet for Squad units"
```

---

## Task 2: SquadUnit script — order interface + combat mirror

**Files:**
- Create: `godot/tests/test_squad_unit.gd`
- Create: `godot/scripts/squads/squad_unit.gd`
- Create: `godot/scenes/squad_unit.tscn` (in step 6 below)

- [ ] **Step 1: Write the failing test for order_move**

`godot/tests/test_squad_unit.gd`:
```gdscript
extends "res://addons/gut/test.gd"

const SquadUnitScene = preload("res://scenes/squad_unit.tscn")

class FakeBuilding:
    extends Node3D
    var is_destroyed := false
    var damage_log: Array = []
    func take_damage(amount: int) -> void:
        damage_log.append(amount)
        if damage_log.size() >= 3:
            is_destroyed = true

func _make_unit() -> Node:
    var u = SquadUnitScene.instantiate()
    add_child_autofree(u)
    return u

func test_order_move_sets_nav_agent_target():
    var u = _make_unit()
    u.order_move(Vector3(5, 0, 5))
    assert_almost_eq(u.nav_agent.target_position.x, 5.0, 0.01)
    assert_almost_eq(u.nav_agent.target_position.z, 5.0, 0.01)
    assert_true(u._has_move_target)

func test_order_attack_sets_target_and_clears_when_destroyed():
    var u = _make_unit()
    var b = FakeBuilding.new()
    add_child_autofree(b)
    b.global_position = u.global_position + Vector3(1.5, 0, 0)  # within ATTACK_RANGE 2.8
    u.order_attack(b)
    assert_eq(u._attack_target, b)

    # Force three physics frames so cooldown allows three hits
    u._attack_cooldown = 0.0
    for i in 4:
        u._physics_process(0.8)  # 0.8 > ATTACK_INTERVAL 0.75 so each tick fires
    assert_true(b.is_destroyed)
    assert_null(u._attack_target)

func test_stop_clears_targets_and_zeros_velocity():
    var u = _make_unit()
    u.order_move(Vector3(5, 0, 5))
    u.stop()
    assert_false(u._has_move_target)
    assert_null(u._attack_target)
    assert_eq(u.velocity, Vector3.ZERO)

func test_set_selected_toggles_ring_visibility():
    var u = _make_unit()
    assert_false(u.selection_ring.visible)
    u.set_selected(true)
    assert_true(u.selection_ring.visible)
    u.set_selected(false)
    assert_false(u.selection_ring.visible)
```

- [ ] **Step 2: Run tests to confirm they fail (script + scene missing)**

```bash
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```
Expected: parse error on missing `res://scenes/squad_unit.tscn`.

- [ ] **Step 3: Implement `squad_unit.gd`**

`godot/scripts/squads/squad_unit.gd`:
```gdscript
class_name SquadUnit
extends CharacterBody3D

const MOVE_SPEED := 9.0
const ATTACK_RANGE := 2.8
const ATTACK_DAMAGE := 20
const ATTACK_INTERVAL := 0.75

@export var unit_id := "squad_unit"

var _move_target: Vector3 = Vector3.ZERO
var _has_move_target := false
var _attack_target: Node = null
var _attack_cooldown := 0.0
var _is_selected := false

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var selection_ring: Decal = $SelectionRing

func _ready() -> void:
    _move_target = global_position
    nav_agent.target_position = global_position
    selection_ring.visible = false
    add_to_group("squad_units")

# --- Public order interface ---

func order_move(world_pos: Vector3) -> void:
    _attack_target = null
    _move_target = Vector3(world_pos.x, global_position.y, world_pos.z)
    _has_move_target = true
    nav_agent.target_position = _move_target
    print("[RTSMVP] SquadUnit %s ordered move %s" % [unit_id, world_pos])

func order_attack(target: Node) -> void:
    if target == null:
        return
    _attack_target = target
    _has_move_target = true
    print("[RTSMVP] SquadUnit %s ordered attack %s" % [unit_id, target.name])

func stop() -> void:
    _attack_target = null
    _has_move_target = false
    velocity = Vector3.ZERO
    print("[RTSMVP] SquadUnit %s stopped" % unit_id)

func set_selected(value: bool) -> void:
    _is_selected = value
    if selection_ring != null:
        selection_ring.visible = value

# --- Tick ---

func _physics_process(delta: float) -> void:
    _attack_cooldown = maxf(0.0, _attack_cooldown - delta)

    # Resolve attack target into a move goal
    if is_instance_valid(_attack_target) and not _attack_target.is_destroyed:
        _move_target = _attack_target.global_position
        _has_move_target = true
        var distance: float = global_position.distance_to(_attack_target.global_position)
        if distance <= ATTACK_RANGE:
            _has_move_target = false
            velocity = Vector3.ZERO
            if _attack_cooldown <= 0.0:
                _attack_target.take_damage(ATTACK_DAMAGE)
                _attack_cooldown = ATTACK_INTERVAL
    elif _attack_target != null:
        # Target destroyed or freed — return to idle
        _attack_target = null
        _has_move_target = false

    # Drive the navigation agent
    if _has_move_target:
        var flat_target := Vector3(_move_target.x, global_position.y, _move_target.z)
        if nav_agent.target_position.distance_to(flat_target) > 0.01:
            nav_agent.target_position = flat_target
        if nav_agent.is_navigation_finished():
            _has_move_target = false
            velocity = Vector3.ZERO
        else:
            var next_point := nav_agent.get_next_path_position()
            var offset := next_point - global_position
            offset.y = 0.0
            if offset.length() <= 0.001:
                velocity = Vector3.ZERO
            else:
                velocity = offset.normalized() * MOVE_SPEED
    elif _attack_target == null:
        velocity = Vector3.ZERO

    move_and_slide()
    if velocity.length() > 0.1:
        look_at(global_position + velocity, Vector3.UP)
```

- [ ] **Step 4: Build the scene file**

`godot/scenes/squad_unit.tscn`:
```
[gd_scene load_steps=7 format=3 uid="uid://squadunit"]

[ext_resource type="Script" path="res://scripts/squads/squad_unit.gd" id="1_squad"]

[sub_resource type="CapsuleMesh" id="CapsuleMesh_body"]
height = 1.4
radius = 0.4

[sub_resource type="CapsuleShape3D" id="CapsuleShape3D_body"]
radius = 0.4
height = 1.4

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_body"]
albedo_color = Color(0.3, 0.5, 1, 1)

[sub_resource type="GradientTexture2D" id="GradientTexture2D_ring"]
width = 64
height = 64
fill = 1
fill_from = Vector2(0.5, 0.5)
fill_to = Vector2(1, 0.5)

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_body_with_color"]
resource_local_to_scene = true
albedo_color = Color(0.3, 0.5, 1, 1)

[node name="SquadUnit" type="CharacterBody3D"]
script = ExtResource("1_squad")
collision_layer = 4
collision_mask = 3

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
shape = SubResource("CapsuleShape3D_body")

[node name="MeshInstance3D" type="MeshInstance3D" parent="."]
mesh = SubResource("CapsuleMesh_body")
material_override = SubResource("StandardMaterial3D_body_with_color")

[node name="NavigationAgent3D" type="NavigationAgent3D" parent="."]
path_desired_distance = 0.4
target_desired_distance = 0.3
radius = 0.5
height = 1.5
avoidance_enabled = true

[node name="SelectionRing" type="Decal" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.65, 0)
size = Vector3(1.6, 1, 1.6)
texture_albedo = SubResource("GradientTexture2D_ring")
modulate = Color(0.6, 0.9, 1, 1)
visible = false
```

- [ ] **Step 5: Run tests to confirm green**

```bash
godot --headless --path godot --import
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```
Expected: `Passing Tests 19` (15 prior + 4 new).

- [ ] **Step 6: Commit**

```bash
git add godot/scripts/squads/squad_unit.gd godot/scenes/squad_unit.tscn godot/tests/test_squad_unit.gd
git commit -m "feat(godot): add SquadUnit puppet with order_move/order_attack/stop"
```

---

## Task 3: DevSquadController — drag-box + right-click orders

**Files:**
- Create: `godot/scripts/dev/dev_squad_controller.gd`

The controller can't be unit-tested easily (it depends on viewport + camera + screen-space projection); manual smoke covers it.

- [ ] **Step 1: Implement `dev_squad_controller.gd`**

`godot/scripts/dev/dev_squad_controller.gd`:
```gdscript
extends Node

const DRAG_THRESHOLD_PX := 8.0
const ENEMY_GROUP := "enemy_buildings"
const SQUAD_GROUP := "squad_units"

var _selection: RefCounted = null  # SelectionSet
var _camera: Camera3D = null
var _world: Node3D = null

var _press_screen_pos: Vector2 = Vector2.ZERO
var _is_pressed := false
var _is_dragging := false

func setup(selection_set, camera: Camera3D, world: Node3D) -> void:
    _selection = selection_set
    _camera = camera
    _world = world

func _input(event: InputEvent) -> void:
    if _selection == null or _camera == null or _world == null:
        return
    if get_viewport().gui_get_hovered_control() != null:
        return

    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            _handle_left_button(event)
        elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
            _handle_right_click(event)
    elif event is InputEventMouseMotion and _is_pressed and not _is_dragging:
        if event.position.distance_to(_press_screen_pos) >= DRAG_THRESHOLD_PX:
            _is_dragging = true
    elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        _selection.clear()
        get_viewport().set_input_as_handled()

func _handle_left_button(event: InputEventMouseButton) -> void:
    if event.pressed:
        _press_screen_pos = event.position
        _is_pressed = true
        _is_dragging = false
        return

    # Released
    if _is_dragging:
        var rect := Rect2(_press_screen_pos, Vector2.ZERO).expand(event.position).abs()
        var hits: Array = []
        for unit in get_tree().get_nodes_in_group(SQUAD_GROUP):
            var screen := _camera.unproject_position(unit.global_position)
            if rect.has_point(screen):
                hits.append(unit)
        if not Input.is_key_pressed(KEY_SHIFT):
            _selection.clear()
        for unit in hits:
            _selection.add(unit)
        get_viewport().set_input_as_handled()
    # else: click without drag — let Hero see it

    _is_pressed = false
    _is_dragging = false

func _handle_right_click(event: InputEventMouseButton) -> void:
    if _selection.size() == 0:
        return  # let Hero handle right-click
    var hit := _raycast(event.position)
    if hit.is_empty():
        return
    var collider = hit.get("collider")
    if collider != null and collider.is_in_group(ENEMY_GROUP):
        for unit in _selection.get_units():
            unit.order_attack(collider)
    else:
        var pos: Vector3 = hit.get("position", Vector3.ZERO)
        for unit in _selection.get_units():
            unit.order_move(pos)
    get_viewport().set_input_as_handled()

func _raycast(screen_pos: Vector2) -> Dictionary:
    var from := _camera.project_ray_origin(screen_pos)
    var to := from + _camera.project_ray_normal(screen_pos) * 500.0
    var query := PhysicsRayQueryParameters3D.create(from, to)
    query.collide_with_bodies = true
    query.collide_with_areas = false
    return _world.get_world_3d().direct_space_state.intersect_ray(query)
```

- [ ] **Step 2: Headless boot test (no GUT case — manual smoke covers behavior)**

```bash
godot --headless --path godot --quit-after 5
```
Expected: still just the bootstrap line, no SCRIPT ERROR. (DevSquadController only takes effect once bootstrap wires it up in Task 4, but the file must parse cleanly.)

- [ ] **Step 3: Commit**

```bash
git add godot/scripts/dev/dev_squad_controller.gd
git commit -m "feat(godot): add DevSquadController for drag-box + right-click orders"
```

---

## Task 4: Bootstrap wiring — spawn squads, register dev controller

**Files:**
- Modify: `godot/scripts/bootstrap.gd`

- [ ] **Step 1: Edit `bootstrap.gd` — add preloads at top**

Insert after existing preloads (after line 4):
```gdscript
const SquadUnitScene = preload("res://scenes/squad_unit.tscn")
const SelectionSetScript = preload("res://scripts/squads/selection_set.gd")
const DevSquadControllerScript = preload("res://scripts/dev/dev_squad_controller.gd")
```

- [ ] **Step 2: Add member variables after the existing ones**

After line 12 (`var match_state = null`):
```gdscript
var selection_set = null
var dev_controller = null
```

- [ ] **Step 3: Append spawn + dev wiring at the end of `_ready()`**

After the existing `print("[RTSMVP] Bootstrap: ...")` line (currently line 41):
```gdscript

	selection_set = SelectionSetScript.new()
	_spawn_squad_units()
	if OS.is_debug_build():
		dev_controller = DevSquadControllerScript.new()
		dev_controller.name = "DevSquadController"
		dev_controller.setup(selection_set, get_viewport().get_camera_3d(), world)
		add_child(dev_controller)
		hud.show_dev_label()
		print("[RTSMVP] Bootstrap: dev squad controller active (debug build)")
```

- [ ] **Step 4: Add `_spawn_squad_units()` method at end of file**

```gdscript
func _spawn_squad_units() -> void:
	if hero == null:
		return
	var offsets := [Vector3(-3, 0, 0), Vector3(3, 0, 0), Vector3(0, 0, 3)]
	for i in offsets.size():
		var unit = SquadUnitScene.instantiate()
		unit.unit_id = "squad_%s" % char(97 + i)  # squad_a, squad_b, squad_c
		unit.position = hero.global_position + offsets[i]
		world.add_child(unit)
```

- [ ] **Step 5: Run headless boot to verify**

```bash
godot --headless --path godot --quit-after 5
```
Expected output includes:
```
[RTSMVP] Bootstrap: hero=CommanderHero hud=HudRoot buildings=3
[RTSMVP] Bootstrap: dev squad controller active (debug build)
```
No SCRIPT ERROR.

- [ ] **Step 6: Commit**

```bash
git add godot/scripts/bootstrap.gd
git commit -m "feat(godot): bootstrap spawns SquadUnits and dev controller"
```

---

## Task 5: HUD dev mode label

**Files:**
- Modify: `godot/scripts/hud_root.gd`
- Modify: `godot/scenes/main.tscn`

- [ ] **Step 1: Add the label node in `main.tscn`**

Insert as a child of `HudRoot`, after the `MarginContainer` block but before `VictoryOverlay` (around line 110 in `main.tscn`):
```
[node name="DevModeLabel" type="Label" parent="HudRoot" unique_id=782341900]
unique_name_in_owner = true
visible = false
anchor_left = 1.0
anchor_right = 1.0
offset_left = -160.0
offset_top = 16.0
offset_right = -16.0
offset_bottom = 40.0
text = "DEV MODE"
horizontal_alignment = 2
modulate = Color(1, 0.6, 0.2, 1)
mouse_filter = 2
```

- [ ] **Step 2: Add the `show_dev_label()` method to `hud_root.gd`**

After the existing `@onready` block (after line 16):
```gdscript
@onready var dev_mode_label: Label = %DevModeLabel
```

After `_ready()` (around line 28), add:
```gdscript
func show_dev_label() -> void:
	if dev_mode_label != null:
		dev_mode_label.visible = true
```

- [ ] **Step 3: Run headless boot to verify**

```bash
godot --headless --path godot --quit-after 5
```
Expected: bootstrap prints, no SCRIPT ERROR. Label is invisible in headless but is wired.

- [ ] **Step 4: Manual editor smoke (1 minute)**

Run `godot --editor --path godot`, press F5. Expected: top-right shows orange "DEV MODE" text; 3 blue capsules around the white hero sphere; left-click drag draws no visible box yet (Task 6 doesn't add a render — just behavior); release the drag while moving, then right-click on a building → all 3 capsules walk to it and start hitting it.

(The drag-box rectangle is intentionally invisible in v0.2 to keep scope small. Selection ring decals under capsules are the visual feedback. If feedback feels too thin, capture as a v0.2.x polish task.)

- [ ] **Step 5: Run all GUT tests**

```bash
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```
Expected: `Passing Tests 19`, all green.

- [ ] **Step 6: Commit**

```bash
git add godot/scripts/hud_root.gd godot/scenes/main.tscn
git commit -m "feat(godot): HUD shows DEV MODE indicator in debug builds"
```

---

## Task 6: Smoke checklist + CHANGELOG + tag v0.2.0

**Files:**
- Modify: `docs/specs/05-godot-smoke-test-checklist.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Append new section to `05-godot-smoke-test-checklist.md`**

After the `## Repo hygiene` block, add:
```markdown

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
```

- [ ] **Step 2: Append `[v0.2.0]` block to `CHANGELOG.md`**

Insert after the header paragraph and before `## [v0.1.1]`:
```markdown
## [v0.2.0] — 2026-04-26

### Added
- **SquadUnit puppets** — three blue capsule units spawn near the hero. They expose a method-level order interface (`order_move / order_attack / stop`) but do nothing on their own. Combat parameters mirror the hero (20 dmg, 0.75 s cooldown, 2.8 unit range). They have no HP and cannot die — invincible by design until the deputy AI lands.
- **SelectionSet** — `RefCounted` container of currently-selected squad units, with selection-ring visual feedback via `Decal`.
- **DevSquadController** (debug builds only) — drag-box left-click selection plus right-click move / attack orders. Provides the validation harness for the squad order interface ahead of Phase D's deputy execution. `OS.is_debug_build()` gates registration so release builds carry no dev surface.
- **HUD `DEV MODE` indicator** — orange top-right label visible only when the dev controller is active.
- **Tests** — five new GUT cases for SelectionSet plus four for SquadUnit (order interface, attack target lifecycle, selection-ring toggle). Total green count: 19.

### Notes
- No new autoloads. SelectionSet is held by reference from `bootstrap.gd`; `EventBus` / `CommandBus` / `GameState` remain deferred to Phase D when the deputy makes them necessary.
- The `Squad` named-group abstraction (spec 03 §7) is intentionally **not** yet introduced; v0.2 has only flat `SquadUnit` instances.
- Hero controls unchanged from v0.1.1. The LoL/WASD dual-input rework is captured in `docs/future-features.md`.
```

- [ ] **Step 3: Run the full pipeline once more**

```bash
godot --headless --path godot --quit-after 5
godot --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```
Expected: zero SCRIPT ERROR, `Passing Tests 19`.

- [ ] **Step 4: Manually walk through all items in §"Squad puppets (debug build only)"**

Run editor F5; tick each box. Note any failure as a follow-up issue, do not paper over.

- [ ] **Step 5: Commit docs**

```bash
git add docs/specs/05-godot-smoke-test-checklist.md CHANGELOG.md
git commit -m "docs: v0.2.0 smoke section + changelog entry"
```

- [ ] **Step 6: Tag and push**

```bash
git tag v0.2.0
git push origin main v0.2.0
```

Verify:
- `git log --oneline -8` shows the six commits in order plus the tag.
- GitHub Actions `ci.yml` goes green on the push.
- `release.yml` triggers on the tag and produces Linux / Windows / Web artifacts.

---

## Acceptance for v0.2.0

The milestone is "done" when **all** of:
1. Headless boot clean: `godot --headless --path godot --quit-after 5` shows two bootstrap lines, zero SCRIPT ERROR.
2. GUT: 19 / 19 passing.
3. Manual smoke for both the original 05 checklist (Hero / camera / command panel / victory) **and** the new "Squad puppets" section, all checked.
4. Release build (`--export-release` on Linux) has no DEV MODE label and no squad-controllable behavior.
5. CI green on the push of v0.2.0; release.yml produces all three platform artifacts.

## Out of scope (do not introduce)

- `Squad` class with `members[] / role / rally_point` (Phase D).
- `EventBus / CommandBus / GameState` autoloads (Phase D).
- Squad HP, squad death, squad selection persistence across reloads (later).
- Visible drag-box rectangle (v0.2.x polish if smoke-test feedback demands).
- Hero LoL/WASD rework (`docs/future-features.md`).
