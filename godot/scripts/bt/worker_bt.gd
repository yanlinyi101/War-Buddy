class_name WorkerBT
extends BehaviorTree

# Doc 09 §12 + §5.3 worker gather loop. v0.10.0 ships the order-type
# routing only (gather / return_cargo / build / move / stop). The
# actual mining + deposit animation cycle lands in v0.10.1 alongside
# the ResourceNode runtime.

const STATE_IDLE := &"idle"
const STATE_MOVING := &"moving"
const STATE_HARVESTING := &"harvesting"
const STATE_RETURNING := &"returning"
const STATE_BUILDING := &"building"

@export var state: StringName = STATE_IDLE
@export var cargo_amount: int = 0       # mineral units carried
@export var cargo_max: int = 5

func on_new_order(order: Resource) -> void:
	match String(order.type_id):
		"move":
			state = STATE_MOVING
		"gather":
			state = STATE_MOVING   # transitions to HARVESTING on arrival
		"return_cargo":
			state = STATE_RETURNING
		"build":
			state = STATE_BUILDING
		"stop":
			state = STATE_IDLE
			report_completed()
		_:
			report_failed(&"unsupported_type_id")
