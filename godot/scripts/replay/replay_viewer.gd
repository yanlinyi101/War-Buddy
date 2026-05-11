class_name ReplayViewer
extends Control

# Spec 12 §7.3 minimal viewer (v0.13.2). Reads a match's NDJSON files
# via ReplayLogger's static API and renders the merged timeline as a
# scrollable text list. Visual scrubbing / play-pause / map preview
# are deferred to a later UI polish pass.
#
# Invocation (spec §7.4): for now, programmatically:
#     var v = preload("res://scenes/replay_viewer.tscn").instantiate()
#     v.load_match("match_12345")
#     add_child(v)

const ReplayLoggerScript = preload("res://scripts/replay/replay_logger.gd")

@onready var _title: Label = $Panel/VBox/Title
@onready var _summary: Label = $Panel/VBox/Summary
@onready var _log: RichTextLabel = $Panel/VBox/ScrollContainer/EventLog

var _entries: Array = []
var _match_id: String = ""

func _ready() -> void:
	if _log != null:
		_log.bbcode_enabled = true

func load_match(match_id: String) -> int:
	_match_id = match_id
	_entries = ReplayLoggerScript.read_replay_timeline(match_id)
	_render_header()
	_render_timeline()
	return _entries.size()

func _render_header() -> void:
	var manifest = ReplayLoggerScript.read_manifest(_match_id)
	if _title != null:
		_title.text = "Replay — %s" % _match_id
	if _summary != null:
		if manifest.is_empty():
			_summary.text = "(no manifest)"
		else:
			_summary.text = "%s → %s   outcome=%s   persona=%s   map=%s   entries=%d" % [
				manifest.get("started_at", "?"),
				manifest.get("ended_at", "?"),
				manifest.get("outcome", "?"),
				manifest.get("deputy_persona", "?"),
				manifest.get("map_id", "?"),
				_entries.size(),
			]

func _render_timeline() -> void:
	if _log == null:
		return
	var lines: Array[String] = []
	for entry in _entries:
		var ts := int(entry.get("__ts", 0))
		var ch := String(entry.get("__channel", "?"))
		var color := _channel_color(ch)
		var summary := _entry_summary(entry, ch)
		lines.append("[color=#888]%8d ms[/color] [color=#%s]%-6s[/color] %s" %
			[ts, ch, color, summary])
	_log.text = "\n".join(lines)

func _channel_color(ch: String) -> String:
	match ch:
		"event": return "9fd2ff"
		"order": return "9fffb0"
		"plan":  return "ffd76a"
		_:       return "cccccc"

func _entry_summary(entry: Dictionary, channel: String) -> String:
	match channel:
		"plan":
			return "plan id=%s deputy=%s rationale=%s" % [
				entry.get("id", "?"), entry.get("deputy", "?"),
				entry.get("rationale", "")]
		"order":
			return "%s id=%s deputy=%s target=%s" % [
				entry.get("type_id", "?"), entry.get("id", "?"),
				entry.get("deputy", "?"),
				_target_summary(entry)]
		"event":
			var kind := String(entry.get("kind", "?"))
			var copy = entry.duplicate(true)
			copy.erase("__channel")
			copy.erase("__ts")
			copy.erase("kind")
			copy.erase("at_ms")
			return "%s %s" % [kind, JSON.stringify(copy)]
		_:
			return JSON.stringify(entry)

func _target_summary(o: Dictionary) -> String:
	if o.get("target_landmark", "") != "":
		return String(o["target_landmark"])
	if o.get("target_squad_id", "") != "":
		return "squad:" + String(o["target_squad_id"])
	if o.get("target_position", null) != null:
		var pos = o["target_position"]
		if pos is Array and pos.size() >= 3:
			return "pos:(%.1f,%.1f,%.1f)" % [float(pos[0]), float(pos[1]), float(pos[2])]
	return "—"
