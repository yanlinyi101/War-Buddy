# ReplayLogger — registered as `ReplayLogger` autoload via project.godot.
# class_name omitted to avoid colliding with the autoload symbol.
#
# Doc 12 §7.2. Persists match-level events to NDJSON alongside the
# existing CommandBus order/plan logs, then writes a manifest at
# match end. Together with CommandBus's three existing files this
# gives the four files §7.2 lists:
#
#   user://order_log/<match_id>.ndjson         (orders, by CommandBus)
#   user://order_log/<match_id>.rejected.ndjson (rejections, by CommandBus)
#   user://order_log/<match_id>.plans.ndjson    (plans, by CommandBus)
#   user://order_log/<match_id>.events.ndjson   (EventBus events, by ReplayLogger)
#   user://order_log/<match_id>.manifest.json   (summary, by ReplayLogger)

extends Node

const LOG_DIR := "user://order_log"

var match_id: String = ""
var persistence_enabled: bool = true
var _started_at_iso: String = ""
var _ended_at_iso: String = ""
var _outcome: String = ""
var _deputy_persona: String = ""
var _map_id: String = ""

func _ready() -> void:
	# Hook EventBus on the next frame so the autoload order is stable.
	call_deferred("_attach_event_bus")

func _attach_event_bus() -> void:
	if EventBus == null:
		return
	EventBus.match_started.connect(_on_match_started)
	EventBus.match_ended.connect(_on_match_ended)
	EventBus.building_destroyed.connect(_append_event.bind("building_destroyed"))
	EventBus.unit_destroyed.connect(_append_event.bind("unit_destroyed"))
	EventBus.hp_changed.connect(_append_event.bind("hp_changed"))
	EventBus.order_completed.connect(_append_event.bind("order_completed"))
	EventBus.order_failed.connect(_append_event.bind("order_failed"))

func configure(deputy_persona_id: StringName, map_id: StringName) -> void:
	_deputy_persona = String(deputy_persona_id)
	_map_id = String(map_id)

func _on_match_started(payload: Dictionary) -> void:
	match_id = String(payload.get("match_id", match_id))
	_started_at_iso = Time.get_datetime_string_from_system(true)
	_outcome = ""
	_ended_at_iso = ""
	_append_event(payload, "match_started")

func _on_match_ended(payload: Dictionary) -> void:
	_ended_at_iso = Time.get_datetime_string_from_system(true)
	_outcome = String(payload.get("reason", "unknown"))
	_append_event(payload, "match_ended")
	_write_manifest()

func _append_event(payload: Dictionary, kind: String) -> void:
	if not persistence_enabled or match_id == "":
		return
	_ensure_dir()
	var path = "%s/%s.events.ndjson" % [LOG_DIR, match_id]
	var f = FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	var entry := payload.duplicate(true)
	entry["kind"] = kind
	entry["at_ms"] = Time.get_ticks_msec()
	f.store_line(JSON.stringify(entry))
	f.close()

func _write_manifest() -> void:
	if not persistence_enabled or match_id == "":
		return
	_ensure_dir()
	var path = "%s/%s.manifest.json" % [LOG_DIR, match_id]
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	var manifest = {
		"match_id": match_id,
		"started_at": _started_at_iso,
		"ended_at": _ended_at_iso,
		"outcome": _outcome,
		"schema_version": 1,
		"deputy_persona": _deputy_persona,
		"map_id": _map_id,
	}
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()

func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(LOG_DIR):
		DirAccess.make_dir_recursive_absolute(LOG_DIR)

# --- Reader API (spec 12 §7.3 — used by the future replay viewer) ---

static func read_manifest(match_id_arg: String) -> Dictionary:
	var path = "%s/%s.manifest.json" % [LOG_DIR, match_id_arg]
	if not FileAccess.file_exists(path):
		return {}
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

static func read_ndjson(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var out: Array = []
	while not f.eof_reached():
		var line = f.get_line()
		if line.is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if typeof(parsed) == TYPE_DICTIONARY:
			out.append(parsed)
	f.close()
	return out

static func read_replay_timeline(match_id_arg: String) -> Array:
	# Merges orders + plans + events into one timeline sorted by ms.
	var events := read_ndjson("%s/%s.events.ndjson" % [LOG_DIR, match_id_arg])
	var orders := read_ndjson("%s/%s.ndjson" % [LOG_DIR, match_id_arg])
	var plans := read_ndjson("%s/%s.plans.ndjson" % [LOG_DIR, match_id_arg])
	var combined: Array = []
	for e in events:
		var entry: Dictionary = (e as Dictionary).duplicate(true)
		entry["__channel"] = "event"
		entry["__ts"] = int(entry.get("at_ms", 0))
		combined.append(entry)
	for o in orders:
		var entry: Dictionary = (o as Dictionary).duplicate(true)
		entry["__channel"] = "order"
		entry["__ts"] = int(entry.get("accepted_at_ms", 0))
		combined.append(entry)
	for p in plans:
		var entry: Dictionary = (p as Dictionary).duplicate(true)
		entry["__channel"] = "plan"
		entry["__ts"] = int(entry.get("accepted_at_ms", 0))
		combined.append(entry)
	combined.sort_custom(func(a, b): return int(a["__ts"]) < int(b["__ts"]))
	return combined
