extends CharacterBody3D
class_name HeroController

signal target_selected(target)
signal hp_changed(current: int, maximum: int)
signal died(unit_id: String)
signal respawned()

# Movement tunables (spec 11 §4) — exposed on the inspector so playtest
# values can be iterated without touching code.
#   max_speed:         §4.1 — current map diagonal ~50 m; 4.5 m/s ≈ 11 s
#                      across, between DOTA-deliberate and old-RTS-sluggish.
#                      Spec target is ~45 s across (≈1.1 m/s) but at graybox
#                      that feels glacial; 4.5 is the working compromise.
#   accel_time_s:      §4.2 — 0 → top in 80–120 ms; 0.10 s default.
#   stop_snap_speed:   §4.4 — below this magnitude, velocity snaps to 0
#                      in a single frame (instant deceleration on stop /
#                      path-end). Avoids skating.
@export var max_speed: float = 4.5
@export var accel_time_s: float = 0.10
@export var stop_snap_speed: float = 0.05

const ATTACK_RANGE := 2.8
const ATTACK_DAMAGE := 20
const ATTACK_INTERVAL := 0.75

@export var ground_collision_mask := 1
@export var target_collision_mask := 2

# v0.12.2 — hero mortality (spec 09 §3.3 / §10.3). HP & combat-math
# fields mirror SquadUnit so CombatService routes uniformly.
@export var max_hp: int = 600
@export var armor: int = 2
@export var armor_class: StringName = &"hero"
@export var dmg_type: StringName = &"normal"
@export var dmg: int = 25
@export var respawn_seconds: float = 30.0

var hp: int = 600
var is_dead: bool = false
var _respawn_timer: float = 0.0
var _spawn_position: Vector3 = Vector3.ZERO

@onready var hero_state = $HeroState
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var camera: Camera3D = get_viewport().get_camera_3d()

var move_target := Vector3.ZERO
var has_move_target := false
var target_building = null
var attack_cooldown := 0.0
var input_locked := false
var _hitstop = null   # injected by bootstrap; spec 11 §7.1

func set_hitstop(h) -> void:
	_hitstop = h

func _ready() -> void:
	move_target = global_position
	nav_agent.target_position = global_position
	hp = max_hp
	_spawn_position = global_position
	add_to_group("heroes")
	hp_changed.emit(hp, max_hp)

# --- Mortality (v0.12.2, spec 09 §10.3) ---

var _camera_for_shake: Camera3D = null    # injected by bootstrap

func set_shake_camera(cam: Camera3D) -> void:
	_camera_for_shake = cam

func take_damage(amount: int, source: Node = null) -> void:
	if is_dead or amount <= 0 or input_locked:
		return
	hp = maxi(0, hp - amount)
	hp_changed.emit(hp, max_hp)
	# Spec 11 §7.2 — big screen shake on hero taking >10 % max HP in one hit.
	var hit_fraction := float(amount) / float(maxi(1, max_hp))
	if _camera_for_shake != null and _camera_for_shake.has_method("shake") and hit_fraction > 0.10:
		_camera_for_shake.shake(0.6, 0.35)
	# EventBus broadcast
	var t = get_tree()
	if t != null:
		var bus = t.root.get_node_or_null("EventBus")
		if bus != null:
			bus.publish_hp_changed("hero_commander", hp, max_hp)
	# Source param accepted for future killer attribution
	var _src = source
	if hp == 0:
		_die()

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	input_locked = true
	clear_target()
	has_move_target = false
	velocity = Vector3.ZERO
	_respawn_timer = respawn_seconds
	visible = false
	if has_node("CollisionShape3D"):
		$CollisionShape3D.disabled = true
	died.emit("hero_commander")
	var t = get_tree()
	if t != null:
		var bus = t.root.get_node_or_null("EventBus")
		if bus != null:
			bus.publish_unit_destroyed("hero_commander", &"hero", "")
	if _camera_for_shake != null and _camera_for_shake.has_method("shake"):
		_camera_for_shake.shake(1.2, 0.8)
	print("[RTSMVP] Hero died — respawning in %.1fs" % respawn_seconds)

func _try_respawn(delta: float) -> void:
	if not is_dead:
		return
	_respawn_timer = maxf(0.0, _respawn_timer - delta)
	if _respawn_timer <= 0.0:
		_respawn()

func _respawn() -> void:
	is_dead = false
	input_locked = false
	hp = max_hp
	visible = true
	if has_node("CollisionShape3D"):
		$CollisionShape3D.disabled = false
	global_position = _spawn_position
	nav_agent.target_position = global_position
	hp_changed.emit(hp, max_hp)
	respawned.emit()
	print("[RTSMVP] Hero respawned at %s" % _spawn_position)

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
	if is_dead:
		_try_respawn(delta)
		return
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
				if _hitstop != null and _hitstop.has_method("request_hit"):
					_hitstop.request_hit(self, target_building)
		else:
			hero_state.set_action("Closing")
	elif has_move_target:
		hero_state.set_action("Moving")

	# Compute desired horizontal velocity, then ease toward it (spec 11 §4.2)
	# or snap to zero on stop (§4.4).
	var desired := Vector3.ZERO
	if has_move_target:
		var flat_target := Vector3(move_target.x, global_position.y, move_target.z)
		if nav_agent.target_position.distance_to(flat_target) > 0.01:
			nav_agent.target_position = flat_target
		if nav_agent.is_navigation_finished():
			has_move_target = false
			if not is_instance_valid(target_building):
				hero_state.set_action("Idle")
		else:
			var next_point := nav_agent.get_next_path_position()
			var offset := next_point - global_position
			offset.y = 0.0
			if offset.length() > 0.001:
				desired = offset.normalized() * max_speed

	velocity = step_velocity_toward(velocity, desired, max_speed, accel_time_s, stop_snap_speed, delta)
	move_and_slide()
	if velocity.length() > 0.1:
		look_at(global_position + velocity, Vector3.UP)

# Pure helper (static so tests can call without scene tree). Spec 11 §4.2 / §4.4.
static func step_velocity_toward(
	current: Vector3,
	desired: Vector3,
	top_speed: float,
	accel_seconds: float,
	snap_threshold: float,
	delta: float
) -> Vector3:
	# §4.4 — instant deceleration when target is zero (slow start, hard stop).
	if desired == Vector3.ZERO:
		return Vector3(0.0, current.y, 0.0)
	# §4.2 — accelerate at top_speed / accel_seconds up to top_speed.
	var accel := top_speed / maxf(accel_seconds, 0.001)
	var flat := Vector3(current.x, 0.0, current.z)
	var step := desired - flat
	var step_len := step.length()
	var max_step := accel * delta
	if step_len > max_step:
		step = step.normalized() * max_step
	flat += step
	# Snap tiny residuals to zero so we don't wiggle around the target.
	if flat.length() < snap_threshold and desired.length() < snap_threshold:
		flat = Vector3.ZERO
	return Vector3(flat.x, current.y, flat.z)

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
