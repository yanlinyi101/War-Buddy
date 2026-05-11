# CombatService — registered as `CombatService` autoload via project.godot.
# class_name omitted to avoid colliding with the autoload symbol.
#
# Doc 09 §4 — single source of truth for damage resolution. Attackers
# call `resolve_damage(attacker_node, target_node, base_dmg)` and pass
# the resulting int to `target.take_damage(...)`. Direct matrix access
# via `matrix()` is also exposed for tests and edge cases.

extends Node

const DamageMatrixScript = preload("res://scripts/combat/damage_matrix.gd")
const DEFAULT_MATRIX_PATH := "res://data/combat/damage_matrix.tres"

var _matrix: Resource = null

func _ready() -> void:
	_load_or_seed_matrix()

func _load_or_seed_matrix() -> void:
	if ResourceLoader.exists(DEFAULT_MATRIX_PATH):
		_matrix = load(DEFAULT_MATRIX_PATH)
	if _matrix == null:
		_matrix = DamageMatrixScript.default_matrix()

func matrix() -> Resource:
	return _matrix

# Resolve damage between two entities. `attacker` is expected to expose
# `dmg`, `dmg_type` properties (or fall back to base_dmg + "normal").
# `target` is expected to expose `armor_class`, `armor` (or fall back
# to "light" / 0).
func resolve_damage(attacker: Object, target: Object, base_dmg: int = -1) -> int:
	var attacker_dmg: int = base_dmg
	var dmg_type: StringName = &"normal"
	if attacker != null:
		if base_dmg < 0 and attacker.get("dmg") != null:
			attacker_dmg = int(attacker.dmg)
		if attacker.get("dmg_type") != null:
			dmg_type = StringName(attacker.dmg_type)
	if attacker_dmg < 0:
		attacker_dmg = 0
	var armor_class: StringName = &"light"
	var flat_armor: int = 0
	if target != null:
		if target.get("armor_class") != null:
			armor_class = StringName(target.armor_class)
		if target.get("armor") != null:
			flat_armor = int(target.armor)
	return _matrix.compute(attacker_dmg, dmg_type, armor_class, flat_armor)
