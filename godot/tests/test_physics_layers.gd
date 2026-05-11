extends "res://addons/gut/test.gd"

# Spec 11 §2.1 physics layer registry — these tests pin the contract.
# If a layer index changes, every scene's collision_layer / collision_mask
# must also change AND project.godot's [layer_names] must update.

const PhysicsLayersScript = preload("res://scripts/physics_layers.gd")

func test_layer_indices_match_spec_table():
	assert_eq(PhysicsLayersScript.LAYER_TERRAIN, 1)
	assert_eq(PhysicsLayersScript.LAYER_ENEMY_STRUCTURE, 2)
	assert_eq(PhysicsLayersScript.LAYER_FRIENDLY_UNIT, 3)
	assert_eq(PhysicsLayersScript.LAYER_HERO, 4)
	assert_eq(PhysicsLayersScript.LAYER_ENEMY_UNIT, 5)
	assert_eq(PhysicsLayersScript.LAYER_FRIENDLY_STRUCTURE, 6)
	assert_eq(PhysicsLayersScript.LAYER_CORPSE, 7)
	assert_eq(PhysicsLayersScript.LAYER_SOUL, 8)
	assert_eq(PhysicsLayersScript.LAYER_ATTACK_PLAYER, 9)
	assert_eq(PhysicsLayersScript.LAYER_ATTACK_ENEMY, 10)
	assert_eq(PhysicsLayersScript.LAYER_CURSOR_PICK, 11)

func test_bits_match_layer_indices():
	assert_eq(PhysicsLayersScript.BIT_TERRAIN, 1 << 0)
	assert_eq(PhysicsLayersScript.BIT_ENEMY_STRUCTURE, 1 << 1)
	assert_eq(PhysicsLayersScript.BIT_FRIENDLY_UNIT, 1 << 2)
	assert_eq(PhysicsLayersScript.BIT_HERO, 1 << 3)
	assert_eq(PhysicsLayersScript.BIT_CURSOR_PICK, 1 << 10)

func test_hero_collision_mask_includes_terrain_and_enemy_structure():
	var m: int = PhysicsLayersScript.MASK_HERO_COLLISION
	assert_ne(m & PhysicsLayersScript.BIT_TERRAIN, 0)
	assert_ne(m & PhysicsLayersScript.BIT_ENEMY_STRUCTURE, 0)
	# But not friendly units (those should soft-collide, not hard).
	assert_eq(m & PhysicsLayersScript.BIT_FRIENDLY_UNIT, 0)

func test_friendly_unit_collision_mask_matches_current_squad_scene():
	# squad_unit.tscn ships with collision_mask = 3 (layers 1 + 2 =
	# terrain + enemy_structure). This pin makes a scene drift visible.
	assert_eq(PhysicsLayersScript.MASK_FRIENDLY_UNIT_COLLISION, 3)
