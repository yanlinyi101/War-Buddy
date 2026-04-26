extends CanvasLayer
class_name HudRoot

signal command_submitted(channel: String, text: String)
signal voice_placeholder_clicked

@onready var hero_status_label: Label = %HeroStatusLabel
@onready var hero_target_label: Label = %HeroTargetLabel
@onready var hero_action_label: Label = %HeroActionLabel
@onready var buildings_remaining_label: Label = %BuildingsRemainingLabel
@onready var command_input: LineEdit = %CommandInput
@onready var command_history: RichTextLabel = %CommandHistory
@onready var channel_selector: OptionButton = %ChannelSelector
@onready var voice_status_label: Label = %VoiceStatusLabel
@onready var victory_overlay: Control = %VictoryOverlay
@onready var help_label: Label = %HelpLabel
@onready var dev_mode_label: Label = %DevModeLabel

func _ready() -> void:
	channel_selector.clear()
	channel_selector.add_item("Combat Squad Leader", 0)
	channel_selector.add_item("Economy Officer", 1)
	command_history.text = "No commands yet."
	victory_overlay.visible = false
	help_label.text = "Camera: WASD / edge pan / middle drag / wheel zoom. Hero: left click move or attack, right click cancel."
	%SubmitButton.pressed.connect(_on_submit_pressed)
	%VoiceButton.pressed.connect(_on_voice_pressed)
	command_input.text_submitted.connect(_on_text_submitted)

func show_dev_label() -> void:
	if dev_mode_label != null:
		dev_mode_label.visible = true

func bind_hero_state(hero_state) -> void:
	hero_state.health_changed.connect(_on_hero_health_changed)
	hero_state.target_changed.connect(_on_hero_target_changed)
	hero_state.action_changed.connect(_on_hero_action_changed)
	_on_hero_health_changed(hero_state.current_health, hero_state.max_health)
	_on_hero_target_changed(hero_state.current_target_name)
	_on_hero_action_changed(hero_state.current_action)

func update_buildings_remaining(remaining: int) -> void:
	buildings_remaining_label.text = "Enemy structures remaining: %d" % remaining

func refresh_command_log(commands: Array[Dictionary]) -> void:
	if commands.is_empty():
		command_history.text = "No commands yet."
		return
	var lines: Array[String] = []
	for command in commands:
		lines.append("[%s] %s → %s (%s @ %s)" % [command["id"], command["channel"], command["text"], command["status"], command["created_at"]])
	command_history.text = "\n".join(lines)

func show_victory() -> void:
	victory_overlay.visible = true
	voice_status_label.text = "Match locked. The paperwork says you won."

func _on_submit_pressed() -> void:
	_submit_current_command()

func _on_text_submitted(_new_text: String) -> void:
	_submit_current_command()

func _submit_current_command() -> void:
	var text := command_input.text.strip_edges()
	if text.is_empty():
		voice_status_label.text = "Text command required. Empty orders are just managerial performance art."
		return
	voice_status_label.text = "Deputies are fake for now, but the command pipeline is alive."
	var channel := "combat" if channel_selector.selected == 0 else "economy"
	command_submitted.emit(channel, text)
	command_input.clear()

func _on_voice_pressed() -> void:
	voice_status_label.text = "Voice command coming soon. MVP supports text commands only."
	voice_placeholder_clicked.emit()

func _on_hero_health_changed(current_health: int, max_health: int) -> void:
	hero_status_label.text = "Hero HP: %d / %d" % [current_health, max_health]

func _on_hero_target_changed(target_name: String) -> void:
	hero_target_label.text = "Target: %s" % target_name

func _on_hero_action_changed(action_name: String) -> void:
	hero_action_label.text = "Action: %s" % action_name
