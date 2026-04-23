extends CharacterBody3D
class_name HeroController

signal target_selected(target)

const MOVE_SPEED := 9.0
const ATTACK_RANGE := 2.8
const ATTACK_DAMAGE := 20
const ATTACK_INTERVAL := 0.75

@export var ground_collision_mask := 1
@export var target_collision_mask := 2

@onready var hero_state = $HeroState
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var camera: Camera3D = get_viewport().get_camera_3d()

var move_target := Vector3.ZERO
var has_move_target := false
var target_building = null
var attack_cooldown := 0.0
var input_locked := false

func _ready() -> void:
	move_target = global_position
	nav_agent.target_position = global_position

func _unhandled_input(event: InputEvent) -> void:
	if input_locked:
		return
	if get_viewport().gui_get_hovered_control() != null:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_primary_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			clear_target()
			has_move_target = false
			hero_state.set_action("Idle")

func _physics_process(delta: float) -> void:
	if input_locked:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	if is_instance_valid(target_building) and not target_building.is_destroyed:
		move_target = target_building.global_position
		has_move_target = true
		var distance := global_position.distance_to(target_building.global_position)
		if distance <= ATTACK_RANGE:
			has_move_target = false
			velocity = Vector3.ZERO
			hero_state.set_action("Attacking")
			if attack_cooldown <= 0.0:
				target_building.take_damage(ATTACK_DAMAGE)
				attack_cooldown = ATTACK_INTERVAL
		else:
			hero_state.set_action("Closing")
	elif has_move_target:
		hero_state.set_action("Moving")

	if has_move_target:
		var flat_target := Vector3(move_target.x, global_position.y, move_target.z)
		if nav_agent.target_position.distance_to(flat_target) > 0.01:
			nav_agent.target_position = flat_target
		if nav_agent.is_navigation_finished():
			has_move_target = false
			velocity = Vector3.ZERO
			if not is_instance_valid(target_building):
				hero_state.set_action("Idle")
		else:
			var next_point := nav_agent.get_next_path_position()
			var offset := next_point - global_position
			offset.y = 0.0
			if offset.length() <= 0.001:
				velocity = Vector3.ZERO
			else:
				velocity = offset.normalized() * MOVE_SPEED
	else:
		velocity = Vector3.ZERO

	move_and_slide()
	if velocity.length() > 0.1:
		look_at(global_position + velocity, Vector3.UP)

func _handle_primary_click(screen_position: Vector2) -> void:
	var from := camera.project_ray_origin(screen_position)
	var to := from + camera.project_ray_normal(screen_position) * 500.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return
	var collider = result.get("collider")
	if collider != null and collider.is_in_group("enemy_buildings"):
		target_building = collider
		has_move_target = true
		hero_state.set_target(collider.name)
		target_selected.emit(collider)
		print("[RTSMVP] Hero input: target %s at %s" % [collider.name, collider.global_position])
	else:
		clear_target()
		move_target = result.get("position", global_position)
		has_move_target = true
		print("[RTSMVP] Hero input: move to %s" % move_target)

func clear_target() -> void:
	target_building = null
	hero_state.set_target("None")

func set_input_locked(locked: bool) -> void:
	input_locked = locked
	if locked:
		clear_target()
		has_move_target = false
		velocity = Vector3.ZERO
		hero_state.set_action("Victory Lock")
