extends "res://addons/gut/test.gd"

# EntityLibrary is loaded at autoload time. These tests verify the 7
# units + 9 buildings from doc 09 §3.3 / §7.3 are present.

func test_all_seven_units_loaded():
	for uid in [&"worker_basic", &"frontline_basic", &"ranged_basic",
			&"siege_basic", &"caster_basic", &"scout_basic", &"hero_commander"]:
		var u = EntityLibrary.unit(uid)
		assert_ne(u, null, "missing unit: " + String(uid))
		assert_eq(u.unit_id, uid)

func test_all_nine_buildings_loaded():
	for bid in [&"hq", &"supply_depot", &"barracks", &"forge", &"factory",
			&"arcanum", &"temple", &"refinery", &"turret"]:
		var b = EntityLibrary.building(bid)
		assert_ne(b, null, "missing building: " + String(bid))
		assert_eq(b.build_id, bid)

func test_unit_categories_balanced():
	# Spec §3.1: one unit per category (hero counts separately).
	for cat in [&"worker", &"frontline", &"ranged", &"siege", &"caster", &"scout", &"hero"]:
		var units = EntityLibrary.units_by_category(cat)
		assert_eq(units.size(), 1, "category %s should have exactly 1 v1 unit" % String(cat))

func test_frontline_basic_pinned_numbers():
	# Spec §3.3 row.
	var f = EntityLibrary.unit(&"frontline_basic")
	assert_eq(f.max_hp, 125)
	assert_eq(f.armor, 1)
	assert_eq(f.armor_class, &"heavy")
	assert_eq(f.dmg, 10)
	assert_eq(f.dmg_type, &"normal")
	assert_almost_eq(f.move_speed, 3.15, 1e-4)
	assert_eq(f.supply_cost, 2)
	assert_eq(f.tech_tier, 1)

func test_hero_commander_pinned_numbers():
	var h = EntityLibrary.unit(&"hero_commander")
	assert_eq(h.max_hp, 600)
	assert_eq(h.armor_class, &"hero")
	assert_eq(h.dmg, 25)
	assert_eq(h.supply_cost, 0)
	assert_eq(h.agency_tier, &"hero")

func test_hq_provides_supply_and_acts_as_deposit():
	var hq = EntityLibrary.building(&"hq")
	assert_eq(hq.supply_provided, 10)
	assert_true(hq.deposit_point)
	assert_true(hq.produces.has(&"worker_basic"))

func test_turret_is_defensive_with_piercing_dmg():
	var t = EntityLibrary.building(&"turret")
	assert_true(t.defensive)
	assert_eq(t.defensive_dmg, 12)
	assert_eq(t.defensive_dmg_type, &"piercing")
	assert_almost_eq(t.defensive_range, 7.0, 1e-4)
	assert_eq(t.tech_tier, 2)

func test_siege_basic_requires_forge():
	var s = EntityLibrary.unit(&"siege_basic")
	assert_eq(s.tech_tier, 2)
	assert_true(s.prerequisites.has(&"forge"))

func test_caster_basic_requires_arcanum_and_tier_3():
	var c = EntityLibrary.unit(&"caster_basic")
	assert_eq(c.tech_tier, 3)
	assert_true(c.prerequisites.has(&"arcanum"))
