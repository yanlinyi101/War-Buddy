extends "res://addons/gut/test.gd"

const DamageMatrixScript = preload("res://scripts/combat/damage_matrix.gd")

func test_default_matrix_normal_vs_heavy_counters():
	var m = DamageMatrixScript.default_matrix()
	assert_almost_eq(m.multiplier(&"normal", &"heavy"), 1.25, 1e-6)

func test_default_matrix_piercing_vs_light_counters():
	var m = DamageMatrixScript.default_matrix()
	assert_almost_eq(m.multiplier(&"piercing", &"light"), 1.25, 1e-6)

func test_default_matrix_siege_vs_structure_counters():
	var m = DamageMatrixScript.default_matrix()
	assert_almost_eq(m.multiplier(&"siege", &"structure"), 1.25, 1e-6)

func test_unknown_dmg_type_defaults_to_one():
	var m = DamageMatrixScript.default_matrix()
	assert_almost_eq(m.multiplier(&"ghost", &"heavy"), 1.0, 1e-6)

func test_compute_applies_multiplier_then_armor():
	var m = DamageMatrixScript.default_matrix()
	# normal 10 vs heavy 1.25× = 12.5 → 12 after round; minus armor 2 = 10
	assert_eq(m.compute(10, &"normal", &"heavy", 2), 10)

func test_compute_floors_at_zero():
	var m = DamageMatrixScript.default_matrix()
	# 1 dmg piercing vs heavy 0.5× = 0.5 → 0 after round; minus armor 3 = -3 → 0
	assert_eq(m.compute(1, &"piercing", &"heavy", 3), 0)

func test_compute_with_zero_armor_just_uses_multiplier():
	var m = DamageMatrixScript.default_matrix()
	# 20 magic vs light 1.25× = 25
	assert_eq(m.compute(20, &"magic", &"light", 0), 25)

# --- CombatService autoload sanity ---

func test_combat_service_loads_matrix():
	assert_ne(CombatService.matrix(), null)

class FakeAttacker:
	extends Object
	var dmg: int = 10
	var dmg_type: StringName = &"normal"

class FakeTarget:
	extends Object
	var armor_class: StringName = &"heavy"
	var armor: int = 1

func test_combat_service_resolve_damage_uses_matrix():
	var a = FakeAttacker.new()
	var t = FakeTarget.new()
	# normal 10 vs heavy 1.25 = 12.5 → 12 → minus armor 1 = 11
	var got = CombatService.resolve_damage(a, t)
	assert_eq(got, 11)
	a.free()
	t.free()
