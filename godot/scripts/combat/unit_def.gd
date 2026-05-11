class_name UnitDef
extends Resource

# Doc 09 §3.2 — canonical UnitDef. Used by the future spawner +
# behavior trees. v0.9.1 lands the data shape; per-unit .tres files
# ship alongside the roster pass.

# Identity
@export var unit_id: StringName
@export var display_name: String
@export var faction_id: StringName = &"shared"
@export var category: StringName              # worker | frontline | ranged | siege | caster | scout | hero
@export var agency_tier: StringName = &"regular"  # hero | captain | regular

# Combat
@export var max_hp: int = 50
@export var armor: int = 0
@export var armor_class: StringName = &"light"   # light | medium | heavy | structure | hero
@export var dmg: int = 5
@export var dmg_type: StringName = &"normal"     # normal | piercing | siege | magic
@export var attack_range: float = 0.0
@export var attack_period_seconds: float = 1.0
@export var splash_radius: float = 0.0

# Movement
@export var move_speed: float = 3.0
@export var turn_speed_deg: float = 720.0

# Vision & detection
@export var sight_range: float = 8.0
@export var detection: bool = false

# Production
@export var produced_at: StringName = &""
@export var supply_cost: int = 1
@export var mineral_cost: int = 50
@export var gas_cost: int = 0
@export var build_time_seconds: float = 12.0
@export var tech_tier: int = 1
@export var prerequisites: Array[StringName] = []

# Behavior hooks
@export var auto_engage_range: float = 0.0
@export var auto_pursuit_range: float = 0.0
@export var idle_behavior: StringName = &"hold"
