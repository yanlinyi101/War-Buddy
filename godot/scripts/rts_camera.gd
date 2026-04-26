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

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_zoom(-zoom_step)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_zoom(zoom_step)
	elif event is InputEventMouseMotion and _dragging:
		translate(Vector3(-event.relative.x * drag_pan_speed, 0.0, -event.relative.y * drag_pan_speed))
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

	if move != Vector3.ZERO:
		move = move.normalized() * pan_speed * delta
		translate(Vector3(move.x, 0.0, move.z))
		_clamp_to_bounds()

func _adjust_zoom(amount: float) -> void:
	if projection == PROJECTION_ORTHOGONAL:
		size = clampf(size + amount, min_ortho_size, max_ortho_size)
	else:
		position.y = clampf(position.y + amount, min_ortho_size, max_ortho_size)
		_clamp_to_bounds()

func _clamp_to_bounds() -> void:
	position.x = clampf(position.x, bounds_min.x, bounds_max.x)
	position.z = clampf(position.z, bounds_min.y, bounds_max.y)
