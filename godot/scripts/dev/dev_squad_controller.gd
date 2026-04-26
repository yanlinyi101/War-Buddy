extends Node

const DRAG_THRESHOLD_PX := 8.0
const ENEMY_GROUP := "enemy_buildings"
const SQUAD_GROUP := "squad_units"

var _selection: RefCounted = null  # SelectionSet
var _camera: Camera3D = null
var _world: Node3D = null

var _press_screen_pos: Vector2 = Vector2.ZERO
var _is_pressed := false
var _is_dragging := false

func setup(selection_set, camera: Camera3D, world: Node3D) -> void:
	_selection = selection_set
	_camera = camera
	_world = world

func _input(event: InputEvent) -> void:
	if _selection == null or _camera == null or _world == null:
		return
	if get_viewport().gui_get_hovered_control() != null:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_button(event)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_handle_right_click(event)
	elif event is InputEventMouseMotion and _is_pressed and not _is_dragging:
		if event.position.distance_to(_press_screen_pos) >= DRAG_THRESHOLD_PX:
			_is_dragging = true
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_selection.clear()
		get_viewport().set_input_as_handled()

func _handle_left_button(event: InputEventMouseButton) -> void:
	if event.pressed:
		_press_screen_pos = event.position
		_is_pressed = true
		_is_dragging = false
		return

	# Released
	if _is_dragging:
		var rect := Rect2(_press_screen_pos, Vector2.ZERO).expand(event.position).abs()
		var hits: Array = []
		for unit in get_tree().get_nodes_in_group(SQUAD_GROUP):
			var screen := _camera.unproject_position(unit.global_position)
			if rect.has_point(screen):
				hits.append(unit)
		if not Input.is_key_pressed(KEY_SHIFT):
			_selection.clear()
		for unit in hits:
			_selection.add(unit)
		get_viewport().set_input_as_handled()
	# else: click without drag — let Hero see it

	_is_pressed = false
	_is_dragging = false

func _handle_right_click(event: InputEventMouseButton) -> void:
	if _selection.size() == 0:
		return  # let Hero handle right-click
	var hit := _raycast(event.position)
	if hit.is_empty():
		return
	var collider = hit.get("collider")
	if collider != null and collider.is_in_group(ENEMY_GROUP):
		for unit in _selection.get_units():
			unit.order_attack(collider)
	else:
		var pos: Vector3 = hit.get("position", Vector3.ZERO)
		for unit in _selection.get_units():
			unit.order_move(pos)
	get_viewport().set_input_as_handled()

func _raycast(screen_pos: Vector2) -> Dictionary:
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 500.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return _world.get_world_3d().direct_space_state.intersect_ray(query)
