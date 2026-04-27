extends Control

const FADE_HOLD_S := 4.0
const FADE_DURATION_S := 1.0

@onready var label: Label = $Bubble/Label

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func display(text: String, deputy_id: StringName) -> void:
	if label == null:
		return
	label.text = "[%s] %s" % [String(deputy_id), text]
	visible = true
	modulate.a = 1.0
	# Cancel any in-flight tween by overwriting modulate via a fresh tween
	var tween := create_tween()
	tween.tween_interval(FADE_HOLD_S)
	tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION_S)
	tween.tween_callback(func(): visible = false)
