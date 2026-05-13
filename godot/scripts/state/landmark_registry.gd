# LandmarkRegistry — registered as `LandmarkRegistry` autoload via project.godot.
# class_name omitted to avoid colliding with the autoload symbol.
#
# Plan v0.15.1 §6.5. Scans `res://data/maps/graybox/landmarks/` at boot
# and indexes Landmark resources by id + every alias. BattlefieldSnapshot
# Builder pulls from here for the snapshot's `landmarks` field.

extends Node

const LANDMARKS_DIR := "res://data/maps/graybox/landmarks"

var _by_id: Dictionary = {}        # StringName -> Landmark
var _by_alias: Dictionary = {}     # String (lower) -> StringName landmark_id

func _ready() -> void:
	_load_dir(LANDMARKS_DIR)
	print("[RTSMVP] LandmarkRegistry: %d landmarks loaded" % _by_id.size())

func _load_dir(dir_path: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		# Missing dir is non-fatal: pre-v0.15.1 boots still work.
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if not d.current_is_dir() and name.ends_with(".tres"):
			var path := "%s/%s" % [dir_path, name]
			var res = load(path)
			if res != null and res.get("landmark_id") != null:
				var lid: StringName = StringName(res.landmark_id)
				_by_id[lid] = res
				# Index display_name + aliases (lowercased) for utterance match.
				if String(res.display_name) != "":
					_by_alias[String(res.display_name).to_lower()] = lid
				for a in res.aliases:
					_by_alias[String(a).to_lower()] = lid
		name = d.get_next()
	d.list_dir_end()

func get_landmark(landmark_id: StringName) -> Resource:
	return _by_id.get(landmark_id, null)

func resolve_alias(text: String) -> Resource:
	# Returns the Landmark whose name / alias matches `text`, or null.
	var key := text.to_lower().strip_edges()
	var lid: Variant = _by_alias.get(key, null)
	if lid == null:
		return null
	return _by_id.get(lid, null)

func all_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in _by_id.keys():
		out.append(k)
	return out

func count() -> int:
	return _by_id.size()

func snapshot() -> Array:
	# Serialized list for the BattlefieldSnapshotBuilder's `landmarks` field.
	var out: Array = []
	for lid in _by_id.keys():
		var l: Resource = _by_id[lid]
		out.append({
			"landmark_id": String(lid),
			"display_name": String(l.display_name),
			"grid_cells": l.grid_cells.duplicate(),
			"world_center": [l.world_center.x, l.world_center.y, l.world_center.z],
		})
	return out

# Test helper.
func _reset_for_test() -> void:
	_by_id.clear()
	_by_alias.clear()
