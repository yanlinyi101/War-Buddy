# Autoload as `OrderTypeRegistry` via project.godot.
# class_name omitted to avoid colliding with the autoload symbol of the same name.
extends Node

class TypeDef:
	extends RefCounted
	var id: StringName = &""
	var description: String = ""
	var param_schema: Dictionary = {}     # {key: type_string, ...}
	var allowed_deputies: Array[StringName] = []
	var min_targets: int = 1
	var max_targets: int = -1

var _defs: Dictionary = {}    # StringName -> TypeDef

func register(type_def: TypeDef) -> void:
	if type_def == null or type_def.id == &"":
		push_error("OrderTypeRegistry.register: missing id")
		return
	_defs[type_def.id] = type_def

func get_def(id: StringName):
	return _defs.get(id, null)

func validate_params(id: StringName, params: Dictionary) -> Dictionary:
	var def = get_def(id)
	if def == null:
		return {"ok": false, "error": "unknown_type_id", "missing": [], "extra": []}
	var missing: Array[String] = []
	var extra: Array[String] = []
	for required_key in def.param_schema.keys():
		if not params.has(required_key):
			missing.append(String(required_key))
	for got_key in params.keys():
		if not def.param_schema.has(got_key):
			extra.append(String(got_key))
	return {"ok": missing.is_empty() and extra.is_empty(),
	        "missing": missing,
	        "extra": extra}

func list_for_deputy(deputy: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for type_id in _defs.keys():
		var def: TypeDef = _defs[type_id]
		if def.allowed_deputies.is_empty() or def.allowed_deputies.has(deputy):
			out.append(type_id)
	return out

func clear() -> void:
	_defs.clear()
