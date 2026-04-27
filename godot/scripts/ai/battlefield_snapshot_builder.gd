class_name BattlefieldSnapshotBuilder
extends Node

# v1 stub — reads scene-tree groups directly. Doc 09 swaps this to GameState.

func build_for(deputy_id: StringName, _tier_hint: StringName = &"") -> Dictionary:
	return {
		"match_meta": _build_match_meta(),
		"you": _build_self_view(deputy_id),
		"units": _build_units(),
		"enemies": _build_enemies(),
		"recent_events": [],   # populated when EventBus lands
		"player_signals": _build_player_signals(),
		"available_orders": _available_orders(deputy_id),
	}

func _build_match_meta() -> Dictionary:
	return {
		"tick": Engine.get_physics_frames(),
		"elapsed_s": int(Time.get_ticks_msec() / 1000.0),
		"score": {"buildings_killed": 0, "units_lost": 0},
	}

func _build_self_view(deputy_id: StringName) -> Dictionary:
	return {
		"deputy_id": String(deputy_id),
		"last_plan_id": "",
		"recent_orders": [],
	}

func _build_units() -> Array:
	var out: Array = []
	if get_tree() == null:
		return out
	for u in get_tree().get_nodes_in_group("squad_units"):
		var entry = {"id": "", "kind": "squad_unit", "pos_grid": _grid(u.global_position)}
		if u.has_method("get_unit_id"):
			entry["id"] = String(u.get_unit_id())
		elif u.get("unit_id") != null:
			entry["id"] = String(u.unit_id)
		else:
			entry["id"] = u.name
		out.append(entry)
	return out

func _build_enemies() -> Array:
	var out: Array = []
	if get_tree() == null:
		return out
	for e in get_tree().get_nodes_in_group("enemy_buildings"):
		var entry = {"id": "", "kind": "enemy_building", "pos_grid": _grid(e.global_position)}
		if e.has_method("get_building_id"):
			entry["id"] = String(e.get_building_id())
		elif e.get("building_id") != null:
			entry["id"] = String(e.building_id)
		else:
			entry["id"] = e.name
		entry["hp_pct"] = 1.0
		if e.get("hp") != null and e.get("max_hp") != null and int(e.max_hp) > 0:
			entry["hp_pct"] = float(e.hp) / float(e.max_hp)
		out.append(entry)
	return out

func _build_player_signals() -> Dictionary:
	return {
		"last_utterance": "",
		"mouse_focus_grid": "",
		"selected_landmark": "",
	}

func _available_orders(_deputy_id: StringName) -> Array:
	# Autoload is mounted on the SceneTree's root.
	var t = get_tree()
	if t == null:
		return []
	var registry = t.root.get_node_or_null("OrderTypeRegistry")
	if registry == null:
		return []
	var ids: Array[StringName] = registry.list_for_deputy(&"deputy")
	var out: Array = []
	for sn in ids:
		out.append(String(sn))
	return out

func _grid(pos: Vector3) -> String:
	# Trivial A1..H8 mapping centered on origin, 4 units per cell.
	var col_idx = clampi(int((pos.x + 16) / 4), 0, 7)
	var row_idx = clampi(int((pos.z + 16) / 4), 0, 7)
	var col = "ABCDEFGH"[col_idx]
	return "%s%d" % [col, row_idx + 1]
