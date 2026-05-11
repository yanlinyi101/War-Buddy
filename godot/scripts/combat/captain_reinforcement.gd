class_name CaptainReinforcement
extends Object

# Doc 09 §8.3 — applies CaptainMemory's preferred_axis + reinforcement_pct
# (already clamped ≤0.15 in spec 08 §11.6) to a UnitDef instance at
# captain-spawn time. Returns a NEW UnitDef rather than mutating the
# library copy so the same `frontline_basic.tres` can host both captain
# and regular versions.
#
# Only one axis at a time. Unknown axis = no-op.

const UnitDefScript = preload("res://scripts/combat/unit_def.gd")

static func apply(def: Resource, memory: Resource) -> Resource:
	if def == null:
		return null
	# Shallow clone via duplicate() so the library copy stays pristine.
	var clone: Resource = def.duplicate(true)
	if memory == null:
		return clone
	var axis: StringName = StringName(memory.preferred_axis) if memory.get("preferred_axis") != null else &""
	var pct: float = float(memory.reinforcement_pct) if memory.get("reinforcement_pct") != null else 0.0
	if axis == &"" or pct <= 0.0:
		return clone
	# Captain unit gets agency_tier=captain (spec note) — the regular UnitDef
	# row stays "regular".
	clone.agency_tier = &"captain"
	var multiplier := 1.0 + pct
	match String(axis):
		"hp":
			clone.max_hp = int(round(float(clone.max_hp) * multiplier))
		"dps":
			# DPS axis bumps damage AND shrinks attack period (both directions
			# contribute to DPS). Spec §8.3 row is explicit.
			clone.dmg = int(round(float(clone.dmg) * multiplier))
			clone.attack_period_seconds = clone.attack_period_seconds / multiplier
		"sight":
			clone.sight_range = clone.sight_range * multiplier
		"speed":
			clone.move_speed = clone.move_speed * multiplier
		_:
			pass
	return clone
