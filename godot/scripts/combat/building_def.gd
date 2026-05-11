class_name BuildingDef
extends Resource

# Doc 09 §7.1 — canonical BuildingDef. v0.9.1 ships the schema; 7.3's
# 9-entry building roster lands as .tres files in the economy slice
# (v0.9.3+).

@export var build_id: StringName
@export var display_name: String
@export var faction_id: StringName = &"shared"
@export var category: StringName              # hq | supply | production | tech | resource | defense
@export var max_hp: int = 500
@export var armor: int = 1
@export var armor_class: StringName = &"structure"

# Construction
@export var mineral_cost: int = 100
@export var gas_cost: int = 0
@export var build_time_seconds: float = 30.0
@export var tech_tier: int = 1
@export var prerequisites: Array[StringName] = []
@export var size_grid: Vector2i = Vector2i(2, 2)

# Production / function
@export var produces: Array[StringName] = []
@export var supply_provided: int = 0
@export var deposit_point: bool = false
@export var research_options: Array[StringName] = []
@export var defensive: bool = false
@export var defensive_range: float = 0.0
@export var defensive_dmg: int = 0
@export var defensive_dmg_type: StringName = &"normal"
