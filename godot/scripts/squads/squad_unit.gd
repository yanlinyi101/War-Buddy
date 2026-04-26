class_name SquadUnit
extends CharacterBody3D

const MOVE_SPEED := 9.0
const ATTACK_RANGE := 2.8
const ATTACK_DAMAGE := 20
const ATTACK_INTERVAL := 0.75

@export var unit_id := "squad_unit"

var _move_target: Vector3 = Vector3.ZERO
var _has_move_target := false
var _attack_target: Node = null
var _attack_cooldown := 0.0
var _is_selected := false

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var selection_ring: Decal = $SelectionRing

func _ready() -> void:
	_move_target = global_position
	nav_agent.target_position = global_position
	selection_ring.visible = false
	add_to_group("squad_units")

# --- Public order interface ---

func order_move(world_pos: Vector3) -> void:
	_attack_target = null
	_move_target = Vector3(world_pos.x, global_position.y, world_pos.z)
	_has_move_target = true
	nav_agent.target_position = _move_target
	print("[RTSMVP] SquadUnit %s ordered move %s" % [unit_id, world_pos])

func order_attack(target: Node) -> void:
	if target == null:
		return
	_attack_target = target
	_has_move_target = true
	print("[RTSMVP] SquadUnit %s ordered attack %s" % [unit_id, target.name])

func stop() -> void:
	_attack_target = null
	_has_move_target = false
	velocity = Vector3.ZERO
	print("[RTSMVP] SquadUnit %s stopped" % unit_id)

func set_selected(value: bool) -> void:
	_is_selected = value
	if selection_ring != null:
		selection_ring.visible = value

# --- Tick ---

func _physics_process(delta: float) -> void:
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)

	# Resolve attack target into a move goal
	if is_instance_valid(_attack_target) and not _attack_target.is_destroyed:
		_move_target = _attack_target.global_position
		_has_move_target = true
		var distance: float = global_position.distance_to(_attack_target.global_position)
		if distance <= ATTACK_RANGE:
			_has_move_target = false
			velocity = Vector3.ZERO
			if _attack_cooldown <= 0.0:
				_attack_target.take_damage(ATTACK_DAMAGE)
				_attack_cooldown = ATTACK_INTERVAL
	elif _attack_target != null:
		# Target destroyed or freed — return to idle
		_attack_target = null
		_has_move_target = false

	# Drive the navigation agent
	if _has_move_target:
		var flat_target := Vector3(_move_target.x, global_position.y, _move_target.z)
		if nav_agent.target_position.distance_to(flat_target) > 0.01:
			nav_agent.target_position = flat_target
		if nav_agent.is_navigation_finished():
			_has_move_target = false
			velocity = Vector3.ZERO
		else:
			var next_point := nav_agent.get_next_path_position()
			var offset := next_point - global_position
			offset.y = 0.0
			if offset.length() <= 0.001:
				velocity = Vector3.ZERO
			else:
				velocity = offset.normalized() * MOVE_SPEED
	elif _attack_target == null:
		velocity = Vector3.ZERO

	move_and_slide()
	if velocity.length() > 0.1:
		look_at(global_position + velocity, Vector3.UP)
