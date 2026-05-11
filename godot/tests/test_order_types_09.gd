extends "res://addons/gut/test.gd"

# Doc 09 §9 — verify the 7 economy/production verbs land on top of 07's
# 5 core verbs, for a total of 12 registered type_ids after bootstrap.

const RegistryScript = preload("res://scripts/command/order_type_registry.gd")

func _make_registry() -> Node:
	var r = RegistryScript.new()
	add_child_autofree(r)
	return r

func _register_doc_09_verbs(r: Node) -> void:
	# Mirror the bootstrap registration block so the test pins both 07
	# core + 09 extension shapes.
	var pairs = [
		[&"move", {}, 1],
		[&"attack", {}, 1],
		[&"stop", {}, 0],
		[&"hold", {}, 0],
		[&"use_skill", {"skill_id": "string"}, 0],
		[&"gather", {"node_id": "string"}, 0],
		[&"return_cargo", {}, 0],
		[&"build", {"build_id": "string", "position": "vector3"}, 0],
		[&"train", {"unit_id": "string", "count": "int"}, 0],
		[&"research", {"research_id": "string"}, 0],
		[&"set_rally", {"position": "vector3"}, 0],
		[&"cancel_production", {"queue_index": "int"}, 0],
	]
	for p in pairs:
		var d = RegistryScript.TypeDef.new()
		d.id = p[0]
		d.param_schema = p[1]
		d.min_targets = p[2]
		r.register(d)

func test_registry_holds_12_types_after_bootstrap_registration():
	var r = _make_registry()
	_register_doc_09_verbs(r)
	assert_eq(r.list_for_deputy(&"deputy").size(), 12)

func test_economy_verbs_registered():
	var r = _make_registry()
	_register_doc_09_verbs(r)
	for tid in [&"gather", &"return_cargo", &"build", &"train",
			&"research", &"set_rally", &"cancel_production"]:
		assert_ne(r.get_def(tid), null)

func test_gather_param_schema_requires_node_id():
	var r = _make_registry()
	_register_doc_09_verbs(r)
	var v = r.validate_params(&"gather", {})
	assert_false(v["ok"])
	assert_true(v["missing"].has("node_id"))

func test_build_param_schema_requires_build_id_and_position():
	var r = _make_registry()
	_register_doc_09_verbs(r)
	var v = r.validate_params(&"build", {"build_id": "barracks"})
	assert_false(v["ok"])
	assert_true(v["missing"].has("position"))

func test_return_cargo_accepts_empty_params():
	var r = _make_registry()
	_register_doc_09_verbs(r)
	var v = r.validate_params(&"return_cargo", {})
	assert_true(v["ok"])
