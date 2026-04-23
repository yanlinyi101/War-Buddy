extends "res://addons/gut/test.gd"

const CommandLogModelScript = preload("res://scripts/command_log_model.gd")

var model: Node

func before_each() -> void:
	model = CommandLogModelScript.new()
	add_child_autofree(model)

func test_submit_creates_record_with_submitted_status() -> void:
	var record = model.submit_command("combat", "focus fire on enemy hq")
	assert_eq(record["status"], "submitted")
	assert_eq(record["channel"], "combat")
	assert_eq(record["text"], "focus fire on enemy hq")

func test_submit_prepends_to_recent_list() -> void:
	model.submit_command("combat", "first")
	model.submit_command("economy", "second")
	var recent = model.get_recent_commands()
	assert_eq(recent.size(), 2)
	assert_eq(recent[0]["text"], "second")
	assert_eq(recent[1]["text"], "first")

func test_empty_submission_is_ignored() -> void:
	var record = model.submit_command("combat", "   ")
	assert_eq(record.size(), 0)
	assert_eq(model.get_recent_commands().size(), 0)

func test_text_is_truncated_to_140_chars() -> void:
	var long_text = "a".repeat(200)
	var record = model.submit_command("combat", long_text)
	assert_eq(record["text"].length(), 140)

func test_status_changed_signal_fires_on_set_status() -> void:
	watch_signals(model)
	var record = model.submit_command("combat", "hold")
	model.set_command_status(record["id"], "pending_execution")
	assert_signal_emitted_with_parameters(model, "command_status_changed", [record["id"], "pending_execution"])
