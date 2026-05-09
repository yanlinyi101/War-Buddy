class_name Hitstop
extends Node

# Hitstop — spec 11 §7.1.
# v0.6.0 minimal impl: when an attacker lands a melee hit, the attacker
# and victim freeze their _physics_process and _process for 30–60 ms
# (default 45 ms). We deliberately do NOT touch Engine.time_scale —
# that would freeze HUD bubbles, tweens, and the deputy's network
# requests, which is much worse than missing a hitstop.
#
# Implementation:
#   request_hit(attacker, victim, duration_ms) sets process_mode =
#   PROCESS_MODE_DISABLED on both nodes, then on a one-shot timer
#   restores their original process_mode.

const DEFAULT_DURATION_MS := 45

var _restore_queue: Array = []  # [{node, mode, deadline_ms}]

func _process(_delta: float) -> void:
	if _restore_queue.is_empty():
		return
	var now := Time.get_ticks_msec()
	# Iterate in reverse so we can remove finished entries safely.
	for i in range(_restore_queue.size() - 1, -1, -1):
		var entry: Dictionary = _restore_queue[i]
		if now >= int(entry["deadline_ms"]):
			var n: Node = entry["node"]
			if is_instance_valid(n):
				n.process_mode = int(entry["mode"])
			_restore_queue.remove_at(i)

func request_hit(attacker: Node, victim: Node, duration_ms: int = DEFAULT_DURATION_MS) -> void:
	if duration_ms <= 0:
		return
	var deadline_ms := Time.get_ticks_msec() + duration_ms
	_freeze(attacker, deadline_ms)
	_freeze(victim, deadline_ms)

func _freeze(node: Node, deadline_ms: int) -> void:
	if not is_instance_valid(node):
		return
	# Already frozen by a prior hit? Keep the later deadline; don't double
	# capture the original mode.
	for entry in _restore_queue:
		if entry["node"] == node:
			entry["deadline_ms"] = maxi(int(entry["deadline_ms"]), deadline_ms)
			return
	var prior_mode := node.process_mode
	node.process_mode = Node.PROCESS_MODE_DISABLED
	_restore_queue.append({"node": node, "mode": prior_mode, "deadline_ms": deadline_ms})

func active_freeze_count() -> int:
	return _restore_queue.size()
