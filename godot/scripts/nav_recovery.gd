class_name NavRecovery
extends Node

# Spec 11 §8.1 — off-nav-mesh teleport recovery.
#
# Attaches to a CharacterBody3D (or any Node3D with a NavigationAgent3D
# sibling) and, every physics frame, checks displacement from the nearest
# nav-mesh point. If displacement exceeds threshold for > frame_buffer
# frames, snaps the body back to the nearest valid nav-mesh point.
#
# A 3-frame buffer prevents false positives during legitimate
# ragdoll-push events (spec note).

@export var displacement_threshold: float = 1.5
@export var frame_buffer: int = 3
@export var warn_on_recover: bool = true

var _target: Node3D = null
var _nav_map: RID
var _frames_out: int = 0
var _recover_count: int = 0

func bind_to(target: Node3D) -> void:
	_target = target

func set_nav_map(map: RID) -> void:
	_nav_map = map

func _physics_process(_delta: float) -> void:
	if _target == null:
		return
	if _nav_map == RID():
		# Auto-pick the default 3D nav map if not explicitly set. In
		# headless / GUT contexts root.world_3d can be null — bail safely.
		var t := get_tree()
		if t == null or t.root == null:
			return
		var world: World3D = t.root.world_3d
		if world == null:
			return
		_nav_map = world.navigation_map
		if _nav_map == RID():
			return
	# Skip queries until the map has been synchronized at least once —
	# otherwise NavigationServer3D logs a "map query before sync" error,
	# which is benign here but pollutes test output and CI signal.
	if NavigationServer3D.map_get_iteration_id(_nav_map) == 0:
		return
	var closest := NavigationServer3D.map_get_closest_point(_nav_map, _target.global_position)
	var displacement := _target.global_position.distance_to(closest)
	if displacement > displacement_threshold:
		_frames_out += 1
		if _frames_out > frame_buffer:
			_teleport_to(closest)
			_frames_out = 0
	else:
		_frames_out = 0

func _teleport_to(point: Vector3) -> void:
	_target.global_position = point
	_recover_count += 1
	if warn_on_recover:
		push_warning("[RTSMVP] NavRecovery: snapped %s back to nav mesh (count=%d)" % [
			_target.name if _target != null else "<?>", _recover_count])

func recover_count() -> int:
	return _recover_count
