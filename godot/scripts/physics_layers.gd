class_name PhysicsLayers
extends Object

# Spec 11 §2.1 — central registry of physics layer indices and the
# bitmasks built from them. Used by scenes (for documentation / cross-
# reference) and by code that needs to compose collision masks at
# runtime (raycasts, areas, projectile filters).
#
# IMPORTANT: layer indices here must match the bit positions used in
# project.godot's `[layer_names]` section and the collision_layer /
# collision_mask values in the .tscn scenes. Changing a number here
# requires updating all three.

# --- Layer indices (1-based as Godot's editor displays them) ---
const LAYER_TERRAIN            := 1
const LAYER_ENEMY_STRUCTURE    := 2
const LAYER_FRIENDLY_UNIT      := 3
const LAYER_HERO               := 4
const LAYER_ENEMY_UNIT         := 5
const LAYER_FRIENDLY_STRUCTURE := 6
const LAYER_CORPSE             := 7
const LAYER_SOUL               := 8
const LAYER_ATTACK_PLAYER      := 9
const LAYER_ATTACK_ENEMY       := 10
const LAYER_CURSOR_PICK        := 11

# --- Bit masks (Godot expects 0-based bit positions). ---
const BIT_TERRAIN            := 1 << 0
const BIT_ENEMY_STRUCTURE    := 1 << 1
const BIT_FRIENDLY_UNIT      := 1 << 2
const BIT_HERO               := 1 << 3
const BIT_ENEMY_UNIT         := 1 << 4
const BIT_FRIENDLY_STRUCTURE := 1 << 5
const BIT_CORPSE             := 1 << 6
const BIT_SOUL               := 1 << 7
const BIT_ATTACK_PLAYER      := 1 << 8
const BIT_ATTACK_ENEMY       := 1 << 9
const BIT_CURSOR_PICK        := 1 << 10

# --- Composed masks used by current MVP scenes ---
# Hero collides with terrain + enemy structures (the only "hard wall"
# entities in graybox v0.8.x).
const MASK_HERO_COLLISION := BIT_TERRAIN | BIT_ENEMY_STRUCTURE

# Squad units collide with terrain + enemy structures. Soft-collide
# among friendlies is deferred until friendly units exist beyond the
# v0.2 dev-squad puppets.
const MASK_FRIENDLY_UNIT_COLLISION := BIT_TERRAIN | BIT_ENEMY_STRUCTURE

# Mouse-pick raycast (hero left-click) should hit terrain + enemy
# structures + friendly units (selectable). Cursor-pick layer is
# reserved for future selectable entities.
const MASK_MOUSE_PICK := BIT_TERRAIN | BIT_ENEMY_STRUCTURE | BIT_FRIENDLY_UNIT
