extends "res://addons/gut/test.gd"

# Doc 09 §8 — captain↔squad category binding.

const SquadScript = preload("res://scripts/squads/squad.gd")

func test_combat_captain_can_lead_frontline():
	var p = load("res://data/personas/captain_combat.tres")
	assert_ne(p, null)
	assert_true(p.can_lead_category(&"frontline"))
	assert_true(p.can_lead_category(&"ranged"))
	assert_true(p.can_lead_category(&"siege"))
	assert_true(p.can_lead_category(&"caster"))

func test_combat_captain_rejects_worker():
	var p = load("res://data/personas/captain_combat.tres")
	assert_false(p.can_lead_category(&"worker"))

func test_econ_captain_only_workers():
	var p = load("res://data/personas/captain_econ.tres")
	assert_true(p.can_lead_category(&"worker"))
	assert_false(p.can_lead_category(&"frontline"))
	assert_false(p.can_lead_category(&"scout"))

func test_scout_captain_only_scouts():
	var p = load("res://data/personas/captain_scout.tres")
	assert_true(p.can_lead_category(&"scout"))
	assert_false(p.can_lead_category(&"frontline"))

func test_empty_eligible_categories_allows_all():
	# captain_alpha.tres has no eligible_categories declared
	# (defaults to empty array → unrestricted, see CaptainPersona).
	var p = load("res://data/personas/captain_alpha.tres")
	assert_ne(p, null)
	assert_true(p.can_lead_category(&"frontline"))
	assert_true(p.can_lead_category(&"worker"))

# --- Squad.validate_binding ---

func test_validate_binding_ok_when_persona_eligible():
	var p = load("res://data/personas/captain_combat.tres")
	var r = SquadScript.validate_binding(p, &"frontline")
	assert_true(r["ok"])

func test_validate_binding_rejects_category_mismatch():
	var p = load("res://data/personas/captain_econ.tres")
	var r = SquadScript.validate_binding(p, &"frontline")
	assert_false(r["ok"])
	assert_eq(r["reason"], &"category_mismatch")

func test_validate_binding_rejects_null_persona():
	var r = SquadScript.validate_binding(null, &"frontline")
	assert_false(r["ok"])
	assert_eq(r["reason"], &"missing_persona")
