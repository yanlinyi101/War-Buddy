extends Node

const CommandLogModelScript = preload("res://scripts/command_log_model.gd")
const MatchStateScript = preload("res://scripts/match_state.gd")
const SquadUnitScene = preload("res://scenes/squad_unit.tscn")
const SelectionSetScript = preload("res://scripts/squads/selection_set.gd")
const DevSquadControllerScript = preload("res://scripts/dev/dev_squad_controller.gd")

@onready var world: Node3D = $World
@onready var hero = $World/CommanderHero
@onready var hud = $HudRoot
@onready var navigation_region: NavigationRegion3D = $World/NavigationRegion3D

var command_log = null
var match_state = null
var selection_set = null
var dev_controller = null

func _ready() -> void:
	match_state = MatchStateScript.new()
	match_state.name = "MatchState"
	add_child(match_state)

	command_log = CommandLogModelScript.new()
	command_log.name = "CommandLog"
	add_child(command_log)

	if hero == null:
		push_error("Commander hero binding failed during bootstrap")
		return

	if navigation_region != null:
		navigation_region.bake_navigation_mesh(false)

	hud.bind_hero_state(hero.hero_state)
	hud.command_submitted.connect(_on_command_submitted)
	hud.voice_placeholder_clicked.connect(_on_voice_placeholder_clicked)
	command_log.command_added.connect(_refresh_command_log)
	command_log.command_status_changed.connect(_on_command_status_changed)
	match_state.buildings_remaining_changed.connect(hud.update_buildings_remaining)
	match_state.victory_triggered.connect(_on_victory_triggered)

	_register_enemy_buildings()
	_refresh_command_log()
	hud.update_buildings_remaining(match_state.enemy_buildings_remaining)
	print("[RTSMVP] Bootstrap: hero=%s hud=%s buildings=%d" % [hero.name, hud.name, match_state.enemy_buildings_remaining])

	selection_set = SelectionSetScript.new()
	_spawn_squad_units()
	if OS.is_debug_build():
		dev_controller = DevSquadControllerScript.new()
		dev_controller.name = "DevSquadController"
		dev_controller.setup(selection_set, get_viewport().get_camera_3d(), world)
		add_child(dev_controller)
		hud.show_dev_label()
		print("[RTSMVP] Bootstrap: dev squad controller active (debug build)")

func _register_enemy_buildings() -> void:
	for node in get_tree().get_nodes_in_group("enemy_buildings"):
		match_state.register_enemy_building(node)

func _on_command_submitted(channel: String, text: String) -> void:
	if match_state.is_match_locked:
		return
	command_log.submit_command(channel, text)
	print("[RTSMVP] Command submitted: %s -> %s" % [channel, text])

func _refresh_command_log(_payload = null, _extra = null) -> void:
	hud.refresh_command_log(command_log.get_recent_commands())

func _on_command_status_changed(command_id: String, new_status: String) -> void:
	_refresh_command_log()
	print("[RTSMVP] Command status updated: %s -> %s" % [command_id, new_status])

func _on_voice_placeholder_clicked() -> void:
	print("[RTSMVP] Voice placeholder clicked")

func _on_victory_triggered() -> void:
	hud.show_victory()
	hero.set_input_locked(true)
	print("[RTSMVP] Victory triggered")

func _spawn_squad_units() -> void:
	if hero == null:
		return
	var offsets := [Vector3(-3, 0, 0), Vector3(3, 0, 0), Vector3(0, 0, 3)]
	for i in offsets.size():
		var unit = SquadUnitScene.instantiate()
		unit.unit_id = "squad_%s" % char(97 + i)  # squad_a, squad_b, squad_c
		unit.position = hero.global_position + offsets[i]
		world.add_child(unit)
