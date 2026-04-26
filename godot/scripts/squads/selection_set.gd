class_name SelectionSet
extends RefCounted

signal changed(units: Array)

var _units: Array = []

func add(unit) -> void:
	if unit == null or _units.has(unit):
		return
	_units.append(unit)
	if unit.has_method("set_selected"):
		unit.set_selected(true)
	changed.emit(get_units())

func remove(unit) -> void:
	if not _units.has(unit):
		return
	_units.erase(unit)
	if unit != null and unit.has_method("set_selected"):
		unit.set_selected(false)
	changed.emit(get_units())

func clear() -> void:
	if _units.is_empty():
		return
	var snapshot := _units.duplicate()
	_units.clear()
	for unit in snapshot:
		if unit != null and unit.has_method("set_selected"):
			unit.set_selected(false)
	changed.emit(get_units())

func contains(unit) -> bool:
	return _units.has(unit)

func get_units() -> Array:
	return _units.duplicate()

func size() -> int:
	return _units.size()
