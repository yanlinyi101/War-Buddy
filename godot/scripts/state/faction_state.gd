class_name FactionState
extends Resource

# Doc 09 §11. Per-faction authoritative state — the LLM snapshot reads
# from these; behavior trees and production code mutate them.

@export var faction_id: StringName = &"shared"
@export var minerals: int = 0
@export var gas: int = 0
@export var supply_used: int = 0
@export var supply_max: int = 10            # starts at the default HQ supply
@export var current_tier: int = 1
@export var alive_units: Array[int] = []     # node ids (instance_id) of alive units
@export var alive_buildings: Array[int] = [] # node ids of standing buildings
@export var research_complete: Array[StringName] = []
@export var production_queues: Dictionary = {}    # build_id -> Array[unit_id]
@export var buildings_completed: Array[StringName] = []

func has_resources(mineral_cost: int, gas_cost: int) -> bool:
	return minerals >= mineral_cost and gas >= gas_cost

func spend(mineral_cost: int, gas_cost: int) -> bool:
	if not has_resources(mineral_cost, gas_cost):
		return false
	minerals -= mineral_cost
	gas -= gas_cost
	return true

func refund(mineral_cost: int, gas_cost: int) -> void:
	minerals += mineral_cost
	gas += gas_cost

func supply_available() -> int:
	return maxi(0, supply_max - supply_used)

func tech_state_snapshot() -> Dictionary:
	# Doc 09 §6.3 — shaped for BattlefieldSnapshotBuilder.
	return {
		"current_tier": current_tier,
		"buildings_completed": _stringify_array(buildings_completed),
		"research_complete": _stringify_array(research_complete),
		"next_unlock_eta_seconds": 0,    # populated by production runtime when it exists
	}

func _stringify_array(a: Array) -> Array:
	var out: Array = []
	for s in a:
		out.append(String(s))
	return out

func to_dict() -> Dictionary:
	return {
		"faction_id": String(faction_id),
		"minerals": minerals,
		"gas": gas,
		"supply_used": supply_used,
		"supply_max": supply_max,
		"current_tier": current_tier,
		"research_complete": _stringify_array(research_complete),
		"buildings_completed": _stringify_array(buildings_completed),
	}
