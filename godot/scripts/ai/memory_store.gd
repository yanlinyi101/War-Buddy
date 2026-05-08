# Autoload as `MemoryStore` via project.godot.
# class_name omitted to avoid collision with the autoload symbol of the same name.
extends Node

const DeputyMemoryScript = preload("res://scripts/ai/deputy_memory.gd")
const CaptainMemoryScript = preload("res://scripts/ai/captain_memory.gd")

var base_dir: String = "user://deputies"
var captain_dir: String = "user://captains"

func _ready() -> void:
	if not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)
	if not DirAccess.dir_exists_absolute(captain_dir):
		DirAccess.make_dir_recursive_absolute(captain_dir)

func _path_for(deputy_id: StringName) -> String:
	return "%s/%s.json" % [base_dir, String(deputy_id)]

func _captain_path_for(persona_id: StringName) -> String:
	return "%s/%s.json" % [captain_dir, String(persona_id)]

func load_memory(deputy_id: StringName) -> DeputyMemoryScript:
	if not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)
	var path = _path_for(deputy_id)
	if not FileAccess.file_exists(path):
		var fresh = DeputyMemoryScript.new()
		fresh.deputy_id = deputy_id
		return fresh
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		var fresh2 = DeputyMemoryScript.new()
		fresh2.deputy_id = deputy_id
		return fresh2
	var text = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		var fresh3 = DeputyMemoryScript.new()
		fresh3.deputy_id = deputy_id
		return fresh3
	return DeputyMemoryScript.from_dict(parsed)

func save_memory(memory: DeputyMemoryScript) -> void:
	if not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)
	var path = _path_for(memory.deputy_id)
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("MemoryStore: cannot write %s" % path)
		return
	f.store_string(JSON.stringify(memory.to_dict()))
	f.close()

func snapshot_for(deputy_id: StringName) -> Dictionary:
	return load_memory(deputy_id).to_dict()

# --- Captain memory (spec 08 §11.6) ---

func load_captain(persona_id: StringName) -> CaptainMemoryScript:
	if not DirAccess.dir_exists_absolute(captain_dir):
		DirAccess.make_dir_recursive_absolute(captain_dir)
	var path = _captain_path_for(persona_id)
	if not FileAccess.file_exists(path):
		var fresh = CaptainMemoryScript.new()
		fresh.captain_persona_id = persona_id
		return fresh
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		var fresh2 = CaptainMemoryScript.new()
		fresh2.captain_persona_id = persona_id
		return fresh2
	var text = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		var fresh3 = CaptainMemoryScript.new()
		fresh3.captain_persona_id = persona_id
		return fresh3
	return CaptainMemoryScript.from_dict(parsed)

func save_captain(memory: CaptainMemoryScript) -> void:
	if not DirAccess.dir_exists_absolute(captain_dir):
		DirAccess.make_dir_recursive_absolute(captain_dir)
	memory.clamp_reinforcement()
	var path = _captain_path_for(memory.captain_persona_id)
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("MemoryStore: cannot write %s" % path)
		return
	f.store_string(JSON.stringify(memory.to_dict()))
	f.close()

func snapshot_captain_for(persona_id: StringName) -> Dictionary:
	return load_captain(persona_id).to_dict()
