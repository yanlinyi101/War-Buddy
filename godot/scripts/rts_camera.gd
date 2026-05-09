extends Camera3D
class_name RtsCamera

@export var pan_speed := 18.0
@export var edge_pan_margin := 18.0
@export var zoom_step := 2.5
@export var min_ortho_size := 8.0
@export var max_ortho_size := 36.0
@export var drag_pan_speed := 0.04
@export var bounds_min := Vector2(-18.0, -18.0)
@export var bounds_max := Vector2(18.0, 18.0)

var _dragging := false

# --- Hero-follow mode (Space toggles) -------------------------------------
# Locks the camera to the hero's XZ position while preserving the current
# camera offset, so the user's chosen pan + zoom feel carries over. Zoom
# still works in follow mode; any pan input (WASD, edge-pan, middle drag)
# breaks the lock — LoL-style "Y to lock / move to break" UX.
var _follow_target: Node3D = null
var _follow_enabled: bool = false
var _follow_offset: Vector3 = Vector3.ZERO   # camera.global_position - target.global_position at lock time

# --- Screen shake (spec 11 §7.2) -----------------------------------------
# Applied as an additive XZ offset on top of pan/follow logic so it doesn't
# fight the player's framing. Magnitude decays linearly over duration.
var _shake_magnitude: float = 0.0
var _shake_remaining: float = 0.0
var _shake_duration: float = 0.0
var _shake_offset: Vector3 = Vector3.ZERO

func set_follow_target(target: Node3D) -> void:
	_follow_target = target

func is_following() -> bool:
	return _follow_enabled and _follow_target != null

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_follow_toggle"):
		_toggle_follow()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_zoom(-zoom_step)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_zoom(zoom_step)
	elif event is InputEventMouseMotion and _dragging:
		_break_follow_if_active()
		global_position += Vector3(-event.relative.x * drag_pan_speed, 0.0, -event.relative.y * drag_pan_speed)
		_clamp_to_bounds()

func _process(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_action_pressed("camera_pan_left"):
		move.x -= 1.0
	if Input.is_action_pressed("camera_pan_right"):
		move.x += 1.0
	if Input.is_action_pressed("camera_pan_up"):
		move.z -= 1.0
	if Input.is_action_pressed("camera_pan_down"):
		move.z += 1.0

	var mouse_pos := get_viewport().get_mouse_position()
	var viewport_rect := get_viewport().get_visible_rect()
	if mouse_pos.x <= edge_pan_margin:
		move.x -= 1.0
	elif mouse_pos.x >= viewport_rect.size.x - edge_pan_margin:
		move.x += 1.0
	if mouse_pos.y <= edge_pan_margin:
		move.z -= 1.0
	elif mouse_pos.y >= viewport_rect.size.y - edge_pan_margin:
		move.z += 1.0

	# Remove last frame's shake offset before any pan/follow updates so it
	# doesn't accumulate, then re-apply at the end with the decayed value.
	global_position -= _shake_offset
	_shake_offset = Vector3.ZERO

	if move != Vector3.ZERO:
		_break_follow_if_active()
		move = move.normalized() * pan_speed * delta
		global_position += Vector3(move.x, 0.0, move.z)
		_clamp_to_bounds()
	else:
		_apply_follow()

	_apply_shake(delta)

func _apply_follow() -> void:
	if not is_following():
		return
	# Pin to hero (XZ only — preserve camera height + zoom).
	var target_pos := _follow_target.global_position
	global_position = Vector3(
		target_pos.x + _follow_offset.x,
		global_position.y,
		target_pos.z + _follow_offset.z,
	)
	_clamp_to_bounds()

func _toggle_follow() -> void:
	if _follow_target == null:
		return
	if _follow_enabled:
		_follow_enabled = false
		print("[RTSMVP] Camera follow OFF")
		return
	# Lock — capture current offset on the XZ plane so the player's chosen
	# framing carries over instead of snapping the hero to dead-center.
	_follow_offset = Vector3(
		global_position.x - _follow_target.global_position.x,
		0.0,
		global_position.z - _follow_target.global_position.z,
	)
	_follow_enabled = true
	print("[RTSMVP] Camera follow ON (target=%s offset=%s)" % [_follow_target.name, _follow_offset])

func _break_follow_if_active() -> void:
	if _follow_enabled:
		_follow_enabled = false
		print("[RTSMVP] Camera follow broken by manual pan")

func shake(magnitude: float, duration: float = 0.25) -> void:
	# Spec 11 §7.2: subtle, rare, scales with severity. magnitude is in
	# world units (XZ). Max-clamped so a buggy caller can't fling the
	# camera off-map.
	if magnitude <= 0.0 or duration <= 0.0:
		return
	_shake_magnitude = clampf(magnitude, 0.0, 2.0)
	_shake_duration = duration
	_shake_remaining = duration

func _apply_shake(_delta: float) -> void:
	if _shake_remaining <= 0.0:
		return
	_shake_remaining = maxf(0.0, _shake_remaining - _delta)
	var envelope := _shake_remaining / _shake_duration   # linear decay 1 → 0
	var amp := _shake_magnitude * envelope
	_shake_offset = Vector3(randf_range(-amp, amp), 0.0, randf_range(-amp, amp))
	global_position += _shake_offset

func _adjust_zoom(amount: float) -> void:
	if projection == PROJECTION_ORTHOGONAL:
		size = clampf(size + amount, min_ortho_size, max_ortho_size)
	else:
		position.y = clampf(position.y + amount, min_ortho_size, max_ortho_size)
		_clamp_to_bounds()

func _clamp_to_bounds() -> void:
	position.x = clampf(position.x, bounds_min.x, bounds_max.x)
	position.z = clampf(position.z, bounds_min.y, bounds_max.y)
