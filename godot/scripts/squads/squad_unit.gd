class_name SquadUnit
extends CharacterBody3D

signal hp_changed(current: int, maximum: int)
signal died(unit_id: String)

const MOVE_SPEED := 9.0
const ATTACK_RANGE := 2.8
const ATTACK_DAMAGE := 20
const ATTACK_INTERVAL := 0.75
const DEATH_FADE_S := 0.4

@export var unit_id := "squad_unit"
@export var max_hp: int = 100
# Doc 09 §3.3 / §4.2 — the v0.2 dev capsule maps closest to `frontline_basic`
# (heavy / normal). Exposed so each squad can drift to a different class
# when the roster pass lands.
@export var armor_class: StringName = &"heavy"
@export var armor: int = 1
@export var dmg_type: StringName = &"normal"
@export var debug_log_enabled := true
const DEBUG_LOG_EVERY_N_FRAMES := 3  # ~20Hz at 60Hz physics

var hp: int = 100
var is_dead: bool = false
var _move_target: Vector3 = Vector3.ZERO
var _has_move_target := false
var _attack_target: Node = null
var _attack_cooldown := 0.0
var _is_selected := false
var _ground_y := 0.0
var _frame_counter := 0
var _last_logged_pos: Vector3 = Vector3.ZERO
var _last_has_move_target := false
var _last_nav_finished := true
var _last_in_range := false

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var selection_ring: Decal = $SelectionRing
@onready var hp_bar: Sprite3D = get_node_or_null("HpBar3D")

func _ready() -> void:
	hp = max_hp
	_ground_y = global_position.y
	_move_target = global_position
	nav_agent.target_position = global_position
	selection_ring.visible = false
	add_to_group("squad_units")
	_last_logged_pos = global_position
	if hp_bar != null and hp_bar.has_method("set_hp"):
		hp_bar.set_hp(hp, max_hp)
	hp_changed.emit(hp, max_hp)
	_dlog_event("ready", "pos=%s ground_y=%.3f hp=%d" % [_v2s(global_position), _ground_y, hp])

# --- Mortality (v0.8.0) ---

func take_damage(amount: int, source: Node = null) -> void:
	if is_dead or amount <= 0:
		return
	hp = maxi(0, hp - amount)
	_last_damage_source = source
	if hp_bar != null and hp_bar.has_method("set_hp"):
		hp_bar.set_hp(hp, max_hp)
	hp_changed.emit(hp, max_hp)
	# Forward to EventBus so the snapshot builder + debug HUD pick it up.
	var t = get_tree()
	if t != null:
		var bus = t.root.get_node_or_null("EventBus")
		if bus != null:
			bus.publish_hp_changed(unit_id, hp, max_hp)
	if hp == 0:
		_die()

var _last_damage_source: Node = null

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	_attack_target = null
	_has_move_target = false
	velocity = Vector3.ZERO
	if has_node("CollisionShape3D"):
		$CollisionShape3D.disabled = true
	if selection_ring != null:
		selection_ring.visible = false
	if hp_bar != null:
		hp_bar.visible = false
	died.emit(unit_id)
	# Publish via EventBus before the visual fade so consumers (Captain
	# memory, future BTs) see the death on the same frame.
	var t = get_tree()
	if t != null:
		var bus = t.root.get_node_or_null("EventBus")
		if bus != null:
			var killer_id := ""
			if _last_damage_source != null and is_instance_valid(_last_damage_source):
				if _last_damage_source.get("building_id") != null:
					killer_id = String(_last_damage_source.building_id)
				elif _last_damage_source.get("unit_id") != null:
					killer_id = String(_last_damage_source.unit_id)
				else:
					killer_id = _last_damage_source.name
			bus.publish_unit_destroyed(unit_id, &"friendly", killer_id)
	# Remove from the group so OrderExecutor and snapshot queries stop
	# pointing at a dying unit.
	if is_in_group("squad_units"):
		remove_from_group("squad_units")
	# Visual fade then free.
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, DEATH_FADE_S)
	tween.chain().tween_callback(queue_free)
	print("[RTSMVP] SquadUnit %s died" % unit_id)

# --- Public order interface ---

func order_move(world_pos: Vector3) -> void:
	_attack_target = null
	_move_target = Vector3(world_pos.x, _ground_y, world_pos.z)
	_has_move_target = true
	nav_agent.target_position = _move_target
	print("[RTSMVP] SquadUnit %s ordered move %s" % [unit_id, world_pos])
	_dlog_event("order_move", "pos=%s mt=%s" % [_v2s(world_pos), _v2s(_move_target)])

func order_attack(target: Node) -> void:
	if target == null:
		return
	_attack_target = target
	_has_move_target = true
	print("[RTSMVP] SquadUnit %s ordered attack %s" % [unit_id, target.name])
	_dlog_event("order_attack", "target=%s tgt_pos=%s self_pos=%s" % [target.name, _v2s(target.global_position), _v2s(global_position)])

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
	_frame_counter += 1
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	velocity.y = 0.0

	var distance_to_attack := -1.0
	var in_range := false

	# Resolve attack target into a move goal
	if is_instance_valid(_attack_target) and not _attack_target.is_destroyed:
		_move_target = _attack_target.global_position
		_has_move_target = true
		distance_to_attack = global_position.distance_to(_attack_target.global_position)
		if distance_to_attack <= ATTACK_RANGE:
			in_range = true
			_has_move_target = false
			velocity = Vector3.ZERO
			if _attack_cooldown <= 0.0:
				_attack_target.take_damage(ATTACK_DAMAGE)
				_attack_cooldown = ATTACK_INTERVAL
	elif _attack_target != null:
		# Target destroyed or freed — return to idle
		_attack_target = null
		_has_move_target = false

	if in_range != _last_in_range:
		_dlog_event("attack_range", "in=%s dist=%.3f" % [str(in_range), distance_to_attack])
		_last_in_range = in_range
	if _has_move_target != _last_has_move_target:
		_dlog_event("has_move_target", "value=%s" % str(_has_move_target))
		_last_has_move_target = _has_move_target

	var nav_finished := true
	var next_point := global_position
	var offset_len := 0.0

	# Direct horizontal steering toward _move_target — no NavigationAgent3D pathing
	# (graybox map has no obstacles; the agent's 3D path_desired_distance was deadlocking
	#  on a ~1.9m y-mismatch between unit and navmesh, causing perpetual overshoot.)
	if _has_move_target:
		var flat_offset := Vector3(_move_target.x - global_position.x, 0.0, _move_target.z - global_position.z)
		offset_len = flat_offset.length()
		next_point = Vector3(_move_target.x, _ground_y, _move_target.z)
		if offset_len <= 0.05:
			nav_finished = true
			_has_move_target = false
			velocity = Vector3.ZERO
		else:
			nav_finished = false
			velocity = flat_offset.normalized() * MOVE_SPEED
	elif _attack_target == null:
		velocity = Vector3.ZERO

	if nav_finished != _last_nav_finished:
		_dlog_event("nav_finished", "value=%s" % str(nav_finished))
		_last_nav_finished = nav_finished

	var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var moved := false
	if flat_velocity.length() > 0.1:
		# Clamp per-frame step so we never overshoot the target (overshoot was flipping vel sign every frame).
		var step := flat_velocity * delta
		var step_len := step.length()
		if step_len > offset_len and offset_len > 0.0:
			step = step.normalized() * offset_len
		global_position += step
		global_position.y = _ground_y
		look_at(global_position + flat_velocity, Vector3.UP)
		moved = true

	if debug_log_enabled and _frame_counter % DEBUG_LOG_EVERY_N_FRAMES == 0 and (_has_move_target or _attack_target != null or moved):
		var dpos := global_position - _last_logged_pos
		var atk_name: String = "-"
		if is_instance_valid(_attack_target):
			atk_name = String(_attack_target.name)
		print("[RTSDBG] %s f=%05d pos=%s dpos=%s vel=%s hmt=%s mt=%s atk=%s dist=%.3f navtgt=%s navfin=%s next=%s ofslen=%.3f rot_y=%.2f" % [
			unit_id,
			_frame_counter,
			_v2s(global_position),
			_v2s(dpos),
			_v2s(flat_velocity),
			str(_has_move_target),
			_v2s(_move_target),
			atk_name,
			distance_to_attack,
			_v2s(nav_agent.target_position),
			str(nav_finished),
			_v2s(next_point),
			offset_len,
			rad_to_deg(rotation.y),
		])
		_last_logged_pos = global_position

func _v2s(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]

func _dlog_event(tag: String, body: String) -> void:
	if not debug_log_enabled:
		return
	print("[RTSDBG-EVT] %s f=%05d %s | %s" % [unit_id, _frame_counter, tag, body])
