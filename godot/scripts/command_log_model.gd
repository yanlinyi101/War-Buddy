extends Node
class_name CommandLogModel

signal command_added(command: Dictionary)
signal command_status_changed(command_id: String, new_status: String)

const STATUS_SUBMITTED := "submitted"
const STATUS_RECEIVED := "received"
const STATUS_PENDING_EXECUTION := "pending_execution"

const CHANNEL_COMBAT := "combat"
const CHANNEL_ECONOMY := "economy"

var _commands: Array[Dictionary] = []
var _next_id := 1

func submit_command(channel: String, text: String) -> Dictionary:
	var sanitized := text.strip_edges()
	if sanitized.is_empty():
		push_warning("Ignored empty command submission")
		return {}

	var command := {
		"id": "cmd_%03d" % _next_id,
		"channel": channel,
		"text": sanitized.left(140),
		"created_at": Time.get_datetime_string_from_system(true, true),
		"status": STATUS_SUBMITTED,
	}
	_next_id += 1
	_commands.push_front(command)
	command_added.emit(command)
	_call_lifecycle(command["id"])
	return command

func _call_lifecycle(command_id: String) -> void:
	_advance_status_async.call_deferred(command_id)

func _advance_status_async(command_id: String) -> void:
	await get_tree().create_timer(0.35).timeout
	set_command_status(command_id, STATUS_RECEIVED)
	await get_tree().create_timer(0.8).timeout
	set_command_status(command_id, STATUS_PENDING_EXECUTION)

func set_command_status(command_id: String, new_status: String) -> void:
	for index in _commands.size():
		if _commands[index]["id"] == command_id:
			_commands[index]["status"] = new_status
			command_status_changed.emit(command_id, new_status)
			return
	push_warning("Unknown command id: %s" % command_id)

func get_recent_commands(limit: int = 6) -> Array[Dictionary]:
	return _commands.slice(0, mini(limit, _commands.size()))

func get_all_commands() -> Array[Dictionary]:
	return _commands.duplicate(true)
