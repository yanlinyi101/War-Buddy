extends "res://addons/gut/test.gd"

const RegistryScript = preload("res://scripts/command/order_type_registry.gd")

func _make_registry() -> Node:
	var r = RegistryScript.new()
	add_child_autofree(r)
	return r

func _make_def(id: StringName, schema: Dictionary, deputies: Array[StringName] = [] as Array[StringName]) -> RegistryScript.TypeDef:
	var d = RegistryScript.TypeDef.new()
	d.id = id
	d.description = "test"
	d.param_schema = schema
	d.allowed_deputies = deputies
	return d

func test_register_then_get_def_returns_match():
	var r = _make_registry()
	var def = _make_def(&"move", {"speed_mult": "float"})
	r.register(def)
	assert_eq(r.get_def(&"move"), def)

func test_get_def_returns_null_for_unknown():
	var r = _make_registry()
	assert_null(r.get_def(&"nope"))

func test_validate_params_ok_with_correct_keys():
	var r = _make_registry()
	r.register(_make_def(&"use_skill", {"skill_id": "string", "charges": "int"}))
	var result = r.validate_params(&"use_skill", {"skill_id": "fireball", "charges": 1})
	assert_true(result["ok"])
	assert_eq(result["missing"], [])
	assert_eq(result["extra"], [])

func test_validate_params_reports_missing():
	var r = _make_registry()
	r.register(_make_def(&"use_skill", {"skill_id": "string"}))
	var result = r.validate_params(&"use_skill", {})
	assert_false(result["ok"])
	assert_eq(result["missing"], ["skill_id"])

func test_validate_params_reports_extra():
	var r = _make_registry()
	r.register(_make_def(&"move", {}))
	var result = r.validate_params(&"move", {"unwanted": 5})
	assert_false(result["ok"])
	assert_eq(result["extra"], ["unwanted"])

func test_validate_params_unknown_type_returns_error():
	var r = _make_registry()
	var result = r.validate_params(&"ghost", {})
	assert_false(result["ok"])
	assert_string_contains(result["error"], "unknown_type_id")

func test_list_for_deputy_filters_by_allowed_deputies():
	var r = _make_registry()
	r.register(_make_def(&"move", {}))                                  # any deputy
	r.register(_make_def(&"build", {}, [&"deputy"] as Array[StringName]))
	r.register(_make_def(&"melee_only", {}, [&"captain_combat"] as Array[StringName]))
	var got = r.list_for_deputy(&"deputy")
	assert_true(got.has(&"move"))
	assert_true(got.has(&"build"))
	assert_false(got.has(&"melee_only"))
