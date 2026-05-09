# GameState — registered as `GameState` autoload via project.godot.
# class_name omitted to avoid colliding with the autoload symbol of the same name.
#
# Doc 09 §11 names this as the single authoritative read source for the LLM
# snapshot. v0.7.0 lands the lean v1: match clock, victory flag, and
# scene-tree-group-backed proximity queries. Faction state, minerals/gas,
# production queues, and tech tree are deferred until doc 09's economy
# section actually ships.
#
# The point of doing this now (before economy) is so BattlefieldSnapshotBuilder
# stops querying scene-tree groups directly and instead routes through one
# stable seam — that way the LLM-side prompt format won't churn when 09's
# real fields land.

extends Node

const GROUP_SQUAD_UNITS := "squad_units"
const GROUP_ENEMY_BUILDINGS := "enemy_buildings"

var _match_start_ms: int = 0
var _victory_triggered: bool = false

# --- Match clock --------------------------------------------------------------

func mark_match_started() -> void:
	_match_start_ms = Time.get_ticks_msec()
	_victory_triggered = false

func mark_victory() -> void:
	_victory_triggered = true

func is_victory_triggered() -> bool:
	return _victory_triggered

func match_elapsed_seconds() -> float:
	if _match_start_ms == 0:
		return 0.0
	return (Time.get_ticks_msec() - _match_start_ms) / 1000.0

# --- Entity queries (spec 09 §11) --------------------------------------------
# v1 implementation backed by scene-tree groups; the API is the contract,
# the storage is replaceable.

func units_in_radius(center: Vector3, radius: float, _faction_id: StringName = &"") -> Array:
	var out: Array = []
	if radius <= 0.0:
		return out
	for u in get_tree().get_nodes_in_group(GROUP_SQUAD_UNITS):
		if u is Node3D and (u as Node3D).global_position.distance_to(center) <= radius:
			out.append(u)
	return out

func buildings_in_radius(center: Vector3, radius: float, _faction_id: StringName = &"") -> Array:
	var out: Array = []
	if radius <= 0.0:
		return out
	for b in get_tree().get_nodes_in_group(GROUP_ENEMY_BUILDINGS):
		if b is Node3D and (b as Node3D).global_position.distance_to(center) <= radius:
			out.append(b)
	return out

func all_squad_units() -> Array:
	return get_tree().get_nodes_in_group(GROUP_SQUAD_UNITS)

func all_enemy_buildings() -> Array:
	return get_tree().get_nodes_in_group(GROUP_ENEMY_BUILDINGS)

func enemy_buildings_alive() -> int:
	var n := 0
	for b in all_enemy_buildings():
		if b.has_method("get") and not b.get("is_destroyed"):
			n += 1
	return n
