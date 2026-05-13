extends StaticBody3D
class_name ResourceNodeBody

# v0.15.0 — runtime scene node wrapping a `ResourceNodeDef` (v0.10.1).
# Joins one of the canonical resource groups so GameState can query
# without scene-graph crawling.

const ResourceNodeDefScript = preload("res://scripts/state/resource_node.gd")

@export var node_id: StringName = &""
@export var resource_type: StringName = &"mineral"  # "mineral" | "gas" | "gold"
@export var initial_amount: int = 1500              # 1500 mineral / 0 gas / 3000 gold
@export var harvest_amount_per_cycle: int = 5       # gold uses 8
@export var max_concurrent_workers: int = 3

var def: Resource = null

func _ready() -> void:
	def = ResourceNodeDefScript.new()
	def.node_id = node_id
	def.resource_type = resource_type
	def.initial_amount = initial_amount
	def.current_amount = initial_amount
	def.harvest_amount_per_cycle = harvest_amount_per_cycle
	def.max_concurrent_workers = max_concurrent_workers
	# Mineral + gold deplete; gas is cycle-only.
	def.depletes = (resource_type != &"gas")
	# Group by type so GameState.resource_nodes(type) finds us.
	add_to_group("resource_nodes")
	if resource_type == &"gold":
		add_to_group("resource_nodes_gold")
	elif resource_type == &"gas":
		add_to_group("resource_nodes_gas")
	else:
		add_to_group("resource_nodes_mineral")

func harvest() -> int:
	if def == null:
		return 0
	return def.harvest()

func is_depleted() -> bool:
	return def != null and def.is_depleted()
