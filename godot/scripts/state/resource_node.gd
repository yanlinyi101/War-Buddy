class_name ResourceNodeDef
extends Resource

# Doc 09 §5.2. A ResourceNode represents a single mineral patch or gas
# geyser. The runtime ResourceNode scene node (TODO: scenes/resource_node.tscn)
# holds this Resource and exposes its state to BTs + the snapshot.
#
# Naming note: spec calls this "ResourceNode" but Godot 4 has a built-in
# Resource class — we suffix `Def` to keep type lookup unambiguous.

@export var node_id: StringName = &""
@export var resource_type: StringName = &"mineral"   # &"mineral" | &"gas"
@export var initial_amount: int = 1500
@export var current_amount: int = 1500
@export var harvest_amount_per_cycle: int = 5
@export var max_concurrent_workers: int = 3
@export var depletes: bool = true                    # mineral=true, gas=false

# Spec §5.3 — a worker's mining cycle pulls `harvest_amount_per_cycle`
# off the node. Returns the actual amount taken (clamped to current_amount).
func harvest() -> int:
	if not depletes:
		# Gas geysers never run out; always return full cycle amount.
		return harvest_amount_per_cycle
	var taken = mini(harvest_amount_per_cycle, current_amount)
	current_amount -= taken
	return taken

func is_depleted() -> bool:
	if not depletes:
		return false
	return current_amount <= 0

func saturation_for(active_workers: int) -> float:
	# Spec §5.3 saturation note. 2 per patch ≈ saturated. We return
	# 0.0–1.0 where 1.0 = fully saturated for telemetry / snapshot.
	if max_concurrent_workers <= 0:
		return 1.0
	return clampf(float(active_workers) / float(max_concurrent_workers), 0.0, 1.0)

func to_dict() -> Dictionary:
	return {
		"node_id": String(node_id),
		"resource_type": String(resource_type),
		"current_amount": current_amount,
		"initial_amount": initial_amount,
		"depletes": depletes,
	}
