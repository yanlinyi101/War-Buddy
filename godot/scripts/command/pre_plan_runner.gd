class_name PrePlanRunner
extends Node

const PrePlan = preload("res://scripts/command/pre_plan.gd")

var _bus: Node = null
var _plans: Array[Resource] = []

func set_command_bus(bus: Node) -> void:
	_bus = bus

func add_plan(plan: Resource) -> void:
	_plans.append(plan)

func load_from_directory(dir_path: String) -> int:
	var d = DirAccess.open(dir_path)
	if d == null:
		push_warning("PrePlanRunner: cannot open dir %s" % dir_path)
		return 0
	var loaded = 0
	d.list_dir_begin()
	var entry = d.get_next()
	while entry != "":
		if entry.ends_with(".tres"):
			var full = "%s/%s" % [dir_path, entry]
			var res = load(full)
			if res != null:
				add_plan(res)
				loaded += 1
		entry = d.get_next()
	d.list_dir_end()
	print("[RTSMVP] PrePlanRunner loaded %d preplans from %s" % [loaded, dir_path])
	return loaded

func notify_event(event_name: StringName, payload: Dictionary) -> void:
	if _bus == null:
		return
	var augmented = payload.duplicate()
	augmented["event"] = event_name
	for plan in _plans:
		if not plan.enabled:
			continue
		if plan.trigger == null:
			continue
		if not plan.trigger.matches(augmented):
			continue
		var now_ms = Time.get_ticks_msec()
		if plan.repeat:
			if plan.last_fired_ms != 0:
				var since = now_ms - plan.last_fired_ms
				if since < int(plan.cooldown_seconds * 1000):
					continue
		_bus.submit_orders(plan.orders)
		plan.last_fired_ms = now_ms
		if not plan.repeat:
			plan.enabled = false
