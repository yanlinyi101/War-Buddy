class_name ArchonController
extends Node

# Spec 08 §11.7 — local-only archon takeover at the deputy seat.
# When attached, the AI Deputy goes silent for that seat (LLM path
# disabled) and a human can submit utterances that flow through the
# normal classifier as if they were the deputy.
#
# v0.5.0 scope:
#   - attach/detach API + signals
#   - Swap CommandBus policy to ArchonControlPolicy(seat) on attach
#   - Restore prior policy on detach
#   - F2 toggle in debug builds; release builds ignore the action
#
# Deferred (v0.6.0+):
#   - Networked second-player input (doc 12 territory)
#   - Soft-handoff suggestion plans on archon idle (08+1)

const ControlPolicyScript = preload("res://scripts/command/control_policy.gd")

signal archon_attached(deputy_id: StringName, player_id: StringName)
signal archon_detached(deputy_id: StringName)

var _bus: Node = null
var _deputy: Node = null
var _attached_seat: StringName = &""
var _attached_player: StringName = &""
var _prior_policy: RefCounted = null

func bind(bus: Node, deputy: Node) -> void:
	_bus = bus
	_deputy = deputy

func is_attached() -> bool:
	return _attached_seat != &""

func attached_seat() -> StringName:
	return _attached_seat

func attach(deputy_id: StringName, player_id: StringName = &"local") -> bool:
	if is_attached():
		return false
	_attached_seat = deputy_id
	_attached_player = player_id
	if _bus != null and _bus.has_method("set_policy"):
		# Capture current policy for restore via reflective get on the var.
		_prior_policy = _bus.get("_policy")
		var policy = ControlPolicyScript.ArchonControlPolicy.new(deputy_id)
		_bus.set_policy(policy)
	if _deputy != null and _deputy.has_method("speak"):
		_deputy.speak("Handing the baton — archon active.")
	archon_attached.emit(deputy_id, player_id)
	print("[RTSMVP] Archon attached: seat=%s player=%s" % [String(deputy_id), String(player_id)])
	return true

func detach() -> void:
	if not is_attached():
		return
	var seat := _attached_seat
	_attached_seat = &""
	_attached_player = &""
	if _bus != null and _bus.has_method("set_policy"):
		var restored: RefCounted = _prior_policy
		if restored == null:
			restored = ControlPolicyScript.FullControlPolicy.new()
		_bus.set_policy(restored)
	_prior_policy = null
	if _deputy != null and _deputy.has_method("speak"):
		_deputy.speak("Resuming command.")
	archon_detached.emit(seat)
	print("[RTSMVP] Archon detached: seat=%s" % String(seat))

func toggle(deputy_id: StringName) -> void:
	if is_attached():
		detach()
	else:
		attach(deputy_id)

func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2:
			var seat: StringName = &"deputy"
			if is_attached():
				seat = _attached_seat
			elif _deputy != null:
				seat = _deputy.deputy_id
			toggle(seat)
