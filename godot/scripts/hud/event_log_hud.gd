class_name EventLogHud
extends Control

# Debug-only EventBus log overlay (v0.7.2). Subscribes to all EventBus
# channels and renders the last N events in a scrolling RichTextLabel.
# Toggle visibility with the backtick (`) key.
#
# Wired only when OS.is_debug_build() — release builds never see this
# panel.

const MAX_LINES := 24
const TOGGLE_ACTION := "event_log_toggle"

var _lines: Array[String] = []
@onready var _label: RichTextLabel = $Panel/Margin/RichTextLabel

func _ready() -> void:
	visible = false
	_label.bbcode_enabled = true
	_redraw()

func bind_event_bus(bus: Node) -> void:
	if bus == null:
		return
	bus.match_started.connect(_on_event.bind("match_started", Color(0.6, 1.0, 0.6)))
	bus.match_ended.connect(_on_event.bind("match_ended", Color(1.0, 0.85, 0.4)))
	bus.building_destroyed.connect(_on_event.bind("building_destroyed", Color(1.0, 0.5, 0.5)))
	bus.unit_destroyed.connect(_on_event.bind("unit_destroyed", Color(1.0, 0.4, 0.4)))
	bus.hp_changed.connect(_on_event.bind("hp_changed", Color(0.7, 0.85, 1.0)))
	bus.order_completed.connect(_on_event.bind("order_completed", Color(0.7, 1.0, 0.85)))
	bus.order_failed.connect(_on_event.bind("order_failed", Color(1.0, 0.6, 0.4)))

func _on_event(payload: Dictionary, kind: String, color: Color) -> void:
	var ts := "%6.2f" % (Time.get_ticks_msec() / 1000.0)
	var summary := _summarize(payload)
	var hex := color.to_html(false)
	_lines.append("[color=#888]%s[/color] [color=#%s]%s[/color] %s" % [ts, hex, kind, summary])
	while _lines.size() > MAX_LINES:
		_lines.pop_front()
	_redraw()

func _summarize(payload: Dictionary) -> String:
	if payload.is_empty():
		return ""
	var parts: Array[String] = []
	for k in payload.keys():
		var v: Variant = payload[k]
		var s := str(v)
		if s.length() > 32:
			s = s.substr(0, 29) + "..."
		parts.append("%s=%s" % [String(k), s])
	return " ".join(parts)

func _redraw() -> void:
	if _label == null:
		return
	_label.text = "\n".join(_lines)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_QUOTELEFT:   # backtick
			visible = not visible
			print("[RTSMVP] EventLogHud: visible=%s" % str(visible))
