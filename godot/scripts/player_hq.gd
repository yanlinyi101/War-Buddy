extends StaticBody3D
class_name PlayerHq

# v0.15.0 spec §2.4 / §4.2 — Player HQ. Friendly structure, destroyable
# in theory but no current code path damages it. Registers itself with
# FactionState on _ready so GameState.is_unit_buildable + supply_max
# pick up the +10 supply contribution.
#
# Distinct from enemy HQ (which reuses EnemyBuilding.gd to keep
# defensive-attack + victory-on-destroyed behavior).

@export var faction_id: StringName = &"player"
@export var building_def_id: StringName = &"hq"

var building_def: Resource = null

func _ready() -> void:
	add_to_group("friendly_structures")
	# Look up BuildingDef and tell GameState. EntityLibrary may not be
	# mounted in some isolated tests; bail gracefully if so.
	var t = get_tree()
	if t == null:
		return
	var lib = t.root.get_node_or_null("EntityLibrary")
	if lib != null:
		building_def = lib.building(building_def_id)
	var gs = t.root.get_node_or_null("GameState")
	if gs != null and gs.has_method("register_completed_building"):
		gs.register_completed_building(faction_id, building_def_id)
