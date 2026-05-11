# EntityLibrary — registered as `EntityLibrary` autoload via project.godot.
# class_name omitted to avoid collision with the autoload symbol.
#
# Loads UnitDef + BuildingDef .tres files at boot. Anywhere code needs
# "the canonical worker_basic stats", it asks EntityLibrary.unit(id).

extends Node

const UNITS_DIR := "res://data/units"
const BUILDINGS_DIR := "res://data/buildings"

var _units: Dictionary = {}        # StringName -> UnitDef
var _buildings: Dictionary = {}    # StringName -> BuildingDef

func _ready() -> void:
	_load_dir(UNITS_DIR, _units, "unit_id")
	_load_dir(BUILDINGS_DIR, _buildings, "build_id")
	print("[RTSMVP] EntityLibrary: %d units, %d buildings loaded" % [_units.size(), _buildings.size()])

func _load_dir(dir_path: String, into: Dictionary, key_field: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		push_error("EntityLibrary: cannot open %s" % dir_path)
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if not d.current_is_dir() and name.ends_with(".tres"):
			var path := "%s/%s" % [dir_path, name]
			var res = load(path)
			if res == null:
				push_warning("EntityLibrary: load failed for %s" % path)
			elif res.get(key_field) == null or String(res.get(key_field)) == "":
				push_warning("EntityLibrary: %s missing %s" % [path, key_field])
			else:
				into[StringName(res.get(key_field))] = res
		name = d.get_next()
	d.list_dir_end()

func unit(unit_id: StringName) -> Resource:
	return _units.get(unit_id, null)

func building(build_id: StringName) -> Resource:
	return _buildings.get(build_id, null)

func all_unit_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in _units.keys():
		out.append(k)
	return out

func all_building_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in _buildings.keys():
		out.append(k)
	return out

func units_by_category(category: StringName) -> Array:
	var out: Array = []
	for u in _units.values():
		if StringName(u.category) == category:
			out.append(u)
	return out

func buildings_by_category(category: StringName) -> Array:
	var out: Array = []
	for b in _buildings.values():
		if StringName(b.category) == category:
			out.append(b)
	return out
