# Autoload as `MemoryStore` via project.godot.
# class_name omitted to avoid collision with the autoload symbol of the same name.
extends Node

const DeputyMemoryScript = preload("res://scripts/ai/deputy_memory.gd")

var base_dir: String = "user://deputies"

func _ready() -> void:
	if not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)

func _path_for(deputy_id: StringName) -> String:
	return "%s/%s.json" % [base_dir, String(deputy_id)]

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
