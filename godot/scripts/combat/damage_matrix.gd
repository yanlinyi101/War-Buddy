class_name DamageMatrix
extends Resource

# Doc 09 §4.3 — the 4 dmg_type × 5 armor_class multiplier table.
# Stored as Dictionary-of-Dictionaries so a future .tres can override.

@export var multipliers: Dictionary = {}

func multiplier(dmg_type: StringName, armor_class: StringName) -> float:
	var row: Dictionary = multipliers.get(dmg_type, {})
	return float(row.get(armor_class, 1.0))

# Doc 09 §4.4 — final_damage = max(0, base_dmg * matrix - armor).
# Multiplier applies BEFORE flat armor subtraction so flat armor
# doesn't trivialize the counter table.
func compute(base_dmg: int, dmg_type: StringName, armor_class: StringName,
		flat_armor: int) -> int:
	# Multiplier first, then flat armor subtraction. Floored at zero
	# (never heals). Truncate fractions instead of rounding so a
	# 10 × 1.25 − 1 = 11.5 lands at 11, matching the natural "armor
	# eats a chunk" reading from the spec.
	var raw := float(base_dmg) * multiplier(dmg_type, armor_class) - float(flat_armor)
	return maxi(0, int(raw))

# Factory for the canonical v1 matrix (doc 09 §4.3). Used to seed
# `damage_matrix.tres` and tests.
static func default_matrix() -> DamageMatrix:
	var m := DamageMatrix.new()
	m.multipliers = {
		&"normal":   {&"light": 1.0,  &"medium": 1.0,  &"heavy": 1.25, &"structure": 0.75, &"hero": 1.0},
		&"piercing": {&"light": 1.25, &"medium": 1.0,  &"heavy": 0.5,  &"structure": 0.5,  &"hero": 1.0},
		&"siege":    {&"light": 0.5,  &"medium": 0.75, &"heavy": 1.0,  &"structure": 1.25, &"hero": 0.5},
		&"magic":    {&"light": 1.25, &"medium": 1.0,  &"heavy": 1.0,  &"structure": 0.5,  &"hero": 0.75},
	}
	return m
