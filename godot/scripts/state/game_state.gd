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

const FactionStateScript = preload("res://scripts/state/faction_state.gd")
const GROUP_SQUAD_UNITS := "squad_units"
const GROUP_ENEMY_BUILDINGS := "enemy_buildings"

var _match_start_ms: int = 0
var _victory_triggered: bool = false
var _factions: Dictionary = {}        # StringName -> FactionState

# --- Match clock --------------------------------------------------------------

func mark_match_started() -> void:
	_match_start_ms = Time.get_ticks_msec()
	_victory_triggered = false
	# Seed the default player faction so snapshot calls have something to
	# read on match start. Doc 09 §10.5 starting conditions: 50 mineral,
	# 0 gas, 1 hq (supply +10), 6 worker_basic (6 supply used), 1
	# hero_commander (0 supply). Worker/HQ aren't physically spawned in
	# the graybox yet — buildings_completed = [hq] and supply_used = 6
	# is the data-only seed so snapshots read correctly.
	if not _factions.has(&"player"):
		var f = FactionStateScript.new()
		f.faction_id = &"player"
		f.minerals = 50
		f.gas = 0
		f.supply_used = 6          # spec 09 §10.5 — 6 starting workers
		f.supply_max = 10          # 1 HQ provides +10
		f.current_tier = 1
		f.buildings_completed = [&"hq"] as Array[StringName]
		_factions[&"player"] = f

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

func resource_nodes(resource_type: StringName) -> Array:
	# v0.15.0 — scene-group-backed query for ResourceNodeBody instances.
	# `resource_type` is "mineral" or "gas"; pass &"" for all.
	if resource_type == &"mineral":
		return get_tree().get_nodes_in_group("resource_nodes_mineral")
	if resource_type == &"gas":
		return get_tree().get_nodes_in_group("resource_nodes_gas")
	return get_tree().get_nodes_in_group("resource_nodes")

func enemy_buildings_alive() -> int:
	var n := 0
	for b in all_enemy_buildings():
		if b.has_method("get") and not b.get("is_destroyed"):
			n += 1
	return n

# --- Faction state (doc 09 §11) ---

func get_faction(faction_id: StringName):
	return _factions.get(faction_id, null)

func all_factions() -> Array:
	return _factions.values()

func current_tier(faction_id: StringName) -> int:
	var f = get_faction(faction_id)
	if f == null:
		return 0
	return f.current_tier

func is_unit_buildable(faction_id: StringName, _unit_id: StringName) -> Dictionary:
	# v0.9.3 minimal: faction must exist + have supply headroom.
	# Full prereq + cost check lands with the UnitDef library load.
	var f = get_faction(faction_id)
	if f == null:
		return {"ok": false, "missing_prereqs": [], "missing_supply": 1, "missing_resources": {}}
	var supply_ok = f.supply_available() > 0
	return {
		"ok": supply_ok,
		"missing_prereqs": [],
		"missing_supply": 0 if supply_ok else 1,
		"missing_resources": {},
	}

# v0.13.0 — spec 09 §6 tier-up trigger. Called when a building enters
# `buildings_completed`. Bumps current_tier if the building is a tech
# building with a higher tech_tier than the faction currently holds.
# Forge (T2) and Arcanum (T3) are the canonical tier-up triggers.
func register_completed_building(faction_id: StringName, build_id: StringName) -> Dictionary:
	var f = get_faction(faction_id)
	if f == null:
		return {"ok": false, "reason": &"unknown_faction"}
	if not f.buildings_completed.has(build_id):
		f.buildings_completed.append(build_id)
	# Look up via EntityLibrary if available; fall back to tier-1 if not.
	var t = get_tree()
	var promoted_to: int = f.current_tier
	if t != null:
		var lib = t.root.get_node_or_null("EntityLibrary")
		if lib != null:
			var bdef = lib.building(build_id)
			if bdef != null:
				# Apply supply provided + deposit_point side-effects.
				if int(bdef.supply_provided) > 0:
					f.supply_max += int(bdef.supply_provided)
				# Tier-up only for tech-category buildings of higher tier.
				if String(bdef.category) == "tech" and int(bdef.tech_tier) > f.current_tier:
					f.current_tier = int(bdef.tech_tier)
					promoted_to = f.current_tier
	return {"ok": true, "tier": f.current_tier, "promoted_to": promoted_to}

# --- Test helper ---
func _reset_for_test() -> void:
	_factions.clear()
	_match_start_ms = 0
	_victory_triggered = false
