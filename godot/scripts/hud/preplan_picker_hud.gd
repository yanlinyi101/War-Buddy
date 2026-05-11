class_name PrePlanPickerHud
extends Control

# Doc 10 §4 minimal slice (v0.14.0). Debug-only overlay that lists every
# preplan loaded by PrePlanRunner. Click a row to manually fire its
# trigger (simulating the matching event). Useful for playtesting
# preplan responses without waiting for the real event.
#
# Full war-room UI (form editor, region painter, share-code import) is
# multi-day work; this panel is the smallest piece that gives designers
# a verifiable round-trip from .tres → in-game effect.

signal preplan_fired(plan_name: String)

@onready var _title: Label = $Panel/VBox/Title
@onready var _list: VBoxContainer = $Panel/VBox/ScrollContainer/List

var _runner: Node = null

func bind_runner(runner: Node) -> void:
	_runner = runner
	_refresh()

func _ready() -> void:
	visible = false
	if _title != null:
		_title.text = "PrePlans (press P to toggle)"

func _refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	if _runner == null:
		return
	# Duck-type: PrePlanRunner has _plans Array (no public accessor; v0.14.0
	# adds one if missing in v0.14.1).
	var plans: Array = _runner.get("_plans") if _runner.get("_plans") != null else []
	if plans.is_empty():
		var empty = Label.new()
		empty.text = "(no preplans loaded)"
		_list.add_child(empty)
		return
	for p in plans:
		var row = HBoxContainer.new()
		var name_label = Label.new()
		name_label.text = "%s   [event=%s]" % [
			p.get("name") if p.get("name") != null else "(unnamed)",
			p.get("trigger") and p.trigger.get("event") if p.get("trigger") != null else "?"
		]
		name_label.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(name_label)
		var btn = Button.new()
		btn.text = "Fire"
		btn.pressed.connect(_on_fire_pressed.bind(p))
		row.add_child(btn)
		_list.add_child(row)

func _on_fire_pressed(plan: Resource) -> void:
	if _runner == null or plan == null or plan.trigger == null:
		return
	# Synthesize a minimal payload that matches the trigger's event so the
	# trigger.matches() filter accepts it. Conditions on payload (elapsed_s,
	# enemy_count) are passed as zeros — they'll pass within_seconds_of_start
	# and fail enemy_count_at_least, which is the right "manual test" mode:
	# only fires if conditions allow zero-state to satisfy.
	_runner.notify_event(plan.trigger.event, {"elapsed_s": 0, "enemy_count": 0})
	preplan_fired.emit(String(plan.get("name") if plan.get("name") != null else "(unnamed)"))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			visible = not visible
			if visible:
				_refresh()
