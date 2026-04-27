extends Node

const CommandLogModelScript = preload("res://scripts/command_log_model.gd")
const MatchStateScript = preload("res://scripts/match_state.gd")
const SquadUnitScene = preload("res://scenes/squad_unit.tscn")
const SelectionSetScript = preload("res://scripts/squads/selection_set.gd")
const DevSquadControllerScript = preload("res://scripts/dev/dev_squad_controller.gd")
const PrePlanRunnerScript = preload("res://scripts/command/pre_plan_runner.gd")
const RegistryScript = preload("res://scripts/command/order_type_registry.gd")
const PrePlanScript = preload("res://scripts/command/pre_plan.gd")
const TacticalOrderScript = preload("res://scripts/command/tactical_order.gd")
const DeputyScript = preload("res://scripts/ai/deputy.gd")
const ClassifierRouterScript = preload("res://scripts/ai/classifier_router.gd")
const MockClientScript = preload("res://scripts/ai/mock_client.gd")
const DeepseekClientScript = preload("res://scripts/ai/deepseek_client.gd")
const AnthropicClientScript = preload("res://scripts/ai/anthropic_client.gd")
const SnapshotBuilderScript = preload("res://scripts/ai/battlefield_snapshot_builder.gd")

@onready var world: Node3D = $World
@onready var hero = $World/CommanderHero
@onready var hud = $HudRoot
@onready var navigation_region: NavigationRegion3D = $World/NavigationRegion3D

var command_log = null
var match_state = null
var selection_set = null
var dev_controller = null
var pre_plan_runner = null
var deputy = null
var classifier_router = null
var snapshot_builder = null
var llm_client: RefCounted = null

func _ready() -> void:
	_register_core_order_types()
	CommandBus.set_registry(OrderTypeRegistry)
	CommandBus.match_id = "match_%d" % Time.get_unix_time_from_system()

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

	pre_plan_runner = PrePlanRunnerScript.new()
	pre_plan_runner.name = "PrePlanRunner"
	pre_plan_runner.set_command_bus(CommandBus)
	add_child(pre_plan_runner)
	pre_plan_runner.load_from_directory("res://data/preplans")
	# Inline sample plan (until doc 10 ships .tres authoring): match_start trigger,
	# zero orders. Verifies the runner pipeline + plan-buffer persistence.
	pre_plan_runner.add_plan(_make_sample_match_start_plan())
	pre_plan_runner.notify_event(&"match_start", {"elapsed_s": 0})
	print("[RTSMVP] PrePlanRunner: notified match_start")

	# --- Deputy + classifier wiring ---
	snapshot_builder = SnapshotBuilderScript.new()
	snapshot_builder.name = "BattlefieldSnapshotBuilder"
	add_child(snapshot_builder)

	var persona: Resource = load("res://data/personas/deputy_veteran.tres")
	if persona == null:
		push_error("Bootstrap: deputy_veteran.tres failed to load")
	deputy = DeputyScript.new()
	deputy.name = "Deputy"
	deputy.deputy_id = &"deputy"
	deputy.persona = persona
	deputy.bind_command_bus(CommandBus)
	deputy.bind_memory(MemoryStore.load_memory(&"deputy"))
	add_child(deputy)
	deputy.spoke.connect(_on_deputy_spoke)

	llm_client = _make_llm_client()
	classifier_router = ClassifierRouterScript.new()
	classifier_router.name = "ClassifierRouter"
	classifier_router.bind(deputy, llm_client, snapshot_builder, OrderTypeRegistry)
	add_child(classifier_router)

	hud.utterance_submitted.connect(classifier_router.handle_utterance.bind(&"text_input"))
	print("[RTSMVP] Deputy active: persona=%s llm=%s" % [
		String(persona.persona_id) if persona != null else "<none>",
		_llm_kind_name(llm_client),
	])

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

func _register_core_order_types() -> void:
	var defs = [
		_make_def(&"move", {}, [], 1),
		_make_def(&"attack", {}, [], 1),
		_make_def(&"stop", {}, [], 0),
		_make_def(&"hold", {}, [], 0),
		_make_def(&"use_skill", {"skill_id": "string"}, [], 0),
	]
	for d in defs:
		OrderTypeRegistry.register(d)
	print("[RTSMVP] OrderTypeRegistry: registered %d core types" % defs.size())

func _make_def(id: StringName, schema: Dictionary, deputies: Array, min_targets: int):
	var d = RegistryScript.TypeDef.new()
	d.id = id
	d.description = "core"
	d.param_schema = schema
	var typed_deps: Array[StringName] = []
	for dep in deputies:
		typed_deps.append(dep)
	d.allowed_deputies = typed_deps
	d.min_targets = min_targets
	return d

func _make_llm_client() -> RefCounted:
	# Provider precedence (cost-first ordering):
	#   1. DeepSeek — primary, cheapest, OpenAI-compatible tool-use.
	#   2. Anthropic — fallback when DEEPSEEK_API_KEY missing but ANTHROPIC_API_KEY present.
	#   3. Mock     — final fallback for CI / offline dev.
	var deepseek = DeepseekClientScript.new()
	deepseek.attach_to(self)
	if deepseek.has_api_key():
		return deepseek
	var anthropic = AnthropicClientScript.new()
	anthropic.attach_to(self)
	if anthropic.has_api_key():
		return anthropic
	return MockClientScript.new()

func _llm_kind_name(client: RefCounted) -> String:
	if client == null:
		return "<none>"
	if client is DeepseekClientScript:
		return "DeepseekClient"
	if client is AnthropicClientScript:
		return "AnthropicClient"
	if client is MockClientScript:
		return "MockClient"
	return "<unknown>"

func _on_deputy_spoke(text: String, deputy_id: StringName) -> void:
	if hud != null and hud.has_method("show_deputy_bubble"):
		hud.show_deputy_bubble(text, deputy_id)
	print("[RTSMVP] Deputy %s: %s" % [String(deputy_id), text])

func _make_sample_match_start_plan() -> Resource:
	var trigger = PrePlanScript.PrePlanTrigger.new()
	trigger.event = &"match_start"
	var plan = PrePlanScript.PrePlan.new()
	plan.name = "Sample: opening invocation"
	plan.deputy = &"deputy"
	plan.trigger = trigger
	plan.orders = [] as Array[Resource]
	return plan
