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
# AnthropicClient is intentionally NOT preloaded — per user directive,
# DeepSeek is the only API-keyed LLM provider in the runtime path. The
# AnthropicClient script remains in-tree for parity tests and possible
# future re-enable, but is not reachable from `_make_llm_client`.
const SnapshotBuilderScript = preload("res://scripts/ai/battlefield_snapshot_builder.gd")
const OrderExecutorScript = preload("res://scripts/command/order_executor.gd")
const CaptainScript = preload("res://scripts/ai/captain.gd")
const ArchonControllerScript = preload("res://scripts/ai/archon_controller.gd")
const HitstopScript = preload("res://scripts/feel/hitstop.gd")
const EventLogHudScene = preload("res://scenes/event_log_hud.tscn")
const NavRecoveryScript = preload("res://scripts/nav_recovery.gd")

@onready var world: Node3D = $World
@onready var hero = $World/CommanderHero
@onready var hud = $HudRoot
@onready var navigation_region: NavigationRegion3D = $World/NavigationRegion3D
@onready var rts_camera: Camera3D = $World/Camera3D

var command_log = null
var match_state = null
var selection_set = null
var dev_controller = null
var pre_plan_runner = null
var deputy = null
var classifier_router = null
var snapshot_builder = null
var llm_client: RefCounted = null
var order_executor = null
var captain = null
var archon_controller = null
var hitstop = null
var hero_nav_recovery = null

func _ready() -> void:
	_register_core_order_types()
	CommandBus.set_registry(OrderTypeRegistry)
	CommandBus.match_id = "match_%d" % Time.get_unix_time_from_system()
	GameState.mark_match_started()
	EventBus.publish_match_started({"match_id": CommandBus.match_id})

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

	# Bind hero as the camera follow target (Space toggles follow mode).
	if rts_camera != null and rts_camera.has_method("set_follow_target"):
		rts_camera.set_follow_target(hero)

	# Hitstop driver (spec 11 §7.1) — exposed so attackers can request a
	# brief freeze on hit landing.
	hitstop = HitstopScript.new()
	hitstop.name = "Hitstop"
	add_child(hitstop)
	if hero.has_method("set_hitstop"):
		hero.set_hitstop(hitstop)

	# v0.8.2: Hero off-nav-mesh recovery (spec 11 §8.1) — guards against
	# the hero ending up outside the nav mesh from physics edge cases.
	hero_nav_recovery = NavRecoveryScript.new()
	hero_nav_recovery.name = "HeroNavRecovery"
	add_child(hero_nav_recovery)
	hero_nav_recovery.bind_to(hero)

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

	# --- v0.5.0: Order executor + Captain + Archon ---
	order_executor = OrderExecutorScript.new()
	order_executor.name = "OrderExecutor"
	add_child(order_executor)
	order_executor.bind_bus(CommandBus)

	var captain_persona: Resource = load("res://data/personas/captain_alpha.tres")
	captain = CaptainScript.new()
	captain.name = "CaptainAlpha"
	captain.captain_id = &"alpha"
	captain.squad_id = &"alpha"
	captain.persona = captain_persona
	captain.bind_command_bus(CommandBus)
	captain.bind_memory(MemoryStore.load_captain(&"captain_alpha"))
	add_child(captain)
	captain.spoke.connect(_on_captain_spoke)
	# v0.8.1: Bind captain to a squad unit as its body. squad_a is the
	# captain's "embodiment"; if it dies, the captain dies (and
	# CaptainMemory.deaths increments).
	var body_unit = _find_squad_unit_by_id("squad_a")
	if body_unit != null:
		captain.bind_body(body_unit)
		print("[RTSMVP] Captain alpha embodied in %s" % String(body_unit.unit_id))
	# Route Deputy plans through the Captain. CommandBus.plan_issued fires
	# after the deputy's submit_plan is accepted; we dispatch the plan to
	# the captain whose squad is addressed (single captain at v0.5.0).
	CommandBus.plan_issued.connect(_on_plan_issued_route_to_captain)

	# v0.7.1: Captain autonomous tick. Subscribes to EventBus channels and
	# fires a rate-limited LLM plan in response. Disabled when LLM is the
	# Mock client (no point spending mock tokens on background ticks).
	captain.bind_autonomous_deps(llm_client, snapshot_builder, OrderTypeRegistry)
	captain.subscribe_to_event_bus(EventBus)
	var deepseek_active := llm_client is DeepseekClientScript
	captain.enable_autonomous_tick(deepseek_active)

	archon_controller = ArchonControllerScript.new()
	archon_controller.name = "ArchonController"
	archon_controller.bind(CommandBus, deputy)
	add_child(archon_controller)

	print("[RTSMVP] Captain active: id=%s squad=%s persona=%s autonomous_tick=%s" % [
		String(captain.captain_id),
		String(captain.squad_id),
		String(captain_persona.persona_id) if captain_persona != null else "<none>",
		"ENABLED" if deepseek_active else "disabled (no API key)",
	])
	print("[RTSMVP] OrderExecutor + ArchonController ready (F2 toggles archon in debug builds)")

	# v0.7.2: EventBus debug log (debug builds only — release never spawns it).
	if OS.is_debug_build():
		var event_log = EventLogHudScene.instantiate()
		hud.add_child(event_log)
		event_log.bind_event_bus(EventBus)
		print("[RTSMVP] EventLogHud ready (press ` to toggle)")

func _register_enemy_buildings() -> void:
	for node in get_tree().get_nodes_in_group("enemy_buildings"):
		match_state.register_enemy_building(node)
		# Subtle shake on every enemy structure destruction (spec 11 §7.2).
		if node.has_signal("destroyed"):
			node.destroyed.connect(_on_enemy_building_destroyed_for_shake)

func _on_enemy_building_destroyed_for_shake(building_id: String) -> void:
	if rts_camera != null and rts_camera.has_method("shake"):
		rts_camera.shake(0.35, 0.30)
	# Forward to EventBus so AI agents (Captain tick, future deputy memory
	# consolidation) and BTs all see one canonical destruction event.
	EventBus.publish_building_destroyed(building_id, &"enemy")

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
	# Bigger shake for the victory pump (spec 11 §7.2).
	if rts_camera != null and rts_camera.has_method("shake"):
		rts_camera.shake(0.9, 0.6)
	GameState.mark_victory()
	EventBus.publish_match_ended("victory", {"elapsed_s": GameState.match_elapsed_seconds()})
	print("[RTSMVP] Victory triggered")

func _find_squad_unit_by_id(target_id: String) -> Node:
	for u in get_tree().get_nodes_in_group("squad_units"):
		if u.get("unit_id") != null and String(u.unit_id) == target_id:
			return u
	return null

func _spawn_squad_units() -> void:
	if hero == null:
		return
	var offsets := [Vector3(-3, 0, 0), Vector3(3, 0, 0), Vector3(0, 0, 3)]
	for i in offsets.size():
		var unit = SquadUnitScene.instantiate()
		unit.unit_id = "squad_%s" % char(97 + i)  # squad_a, squad_b, squad_c
		unit.position = hero.global_position + offsets[i]
		world.add_child(unit)
		# Group convention for OrderExecutor lookup (spec 08 §11.6: captain
		# leads `squad_id=alpha`).
		unit.add_to_group("squad_alpha")

func _register_core_order_types() -> void:
	# Spec 07 core verbs (5) + spec 09 §9 extensions (7) = 12 type_ids.
	var defs = [
		_make_def(&"move", {}, [], 1),
		_make_def(&"attack", {}, [], 1),
		_make_def(&"stop", {}, [], 0),
		_make_def(&"hold", {}, [], 0),
		_make_def(&"use_skill", {"skill_id": "string"}, [], 0),
		# --- 09 §9 economy / production verbs ---
		_make_def(&"gather", {"node_id": "string"}, [], 0),
		_make_def(&"return_cargo", {}, [], 0),
		_make_def(&"build", {"build_id": "string", "position": "vector3"}, [], 0),
		_make_def(&"train", {"unit_id": "string", "count": "int"}, [], 0),
		_make_def(&"research", {"research_id": "string"}, [], 0),
		_make_def(&"set_rally", {"position": "vector3"}, [], 0),
		_make_def(&"cancel_production", {"queue_index": "int"}, [], 0),
	]
	for d in defs:
		OrderTypeRegistry.register(d)
	print("[RTSMVP] OrderTypeRegistry: registered %d order types" % defs.size())

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
	# Provider precedence (per user directive — DeepSeek is the only
	# API-keyed provider used at runtime):
	#   1. DeepSeek — primary, OpenAI-compatible tool-use, ~10× cheaper
	#                 per 1M tokens than Anthropic Sonnet.
	#   2. Mock     — fallback for CI / offline dev when DEEPSEEK_API_KEY
	#                 is unset.
	var deepseek = DeepseekClientScript.new()
	deepseek.attach_to(self)
	if deepseek.has_api_key():
		return deepseek
	return MockClientScript.new()

func _llm_kind_name(client: RefCounted) -> String:
	if client == null:
		return "<none>"
	if client is DeepseekClientScript:
		return "DeepseekClient"
	if client is MockClientScript:
		return "MockClient"
	return "<unknown>"

func _on_deputy_spoke(text: String, deputy_id: StringName) -> void:
	if hud != null and hud.has_method("show_deputy_bubble"):
		hud.show_deputy_bubble(text, deputy_id)
	print("[RTSMVP] Deputy %s: %s" % [String(deputy_id), text])

func _on_captain_spoke(text: String, captain_id: StringName) -> void:
	if hud != null and hud.has_method("show_deputy_bubble"):
		hud.show_deputy_bubble("[%s] %s" % [String(captain_id), text], captain_id)
	print("[RTSMVP] Captain %s: %s" % [String(captain_id), text])

func _on_plan_issued_route_to_captain(plan: Resource) -> void:
	if plan == null or captain == null:
		return
	# v0.5.0 single-captain routing: forward any plan whose orders address
	# this captain's squad (or carry no targeting — captain claims it as a
	# default squad assignment). Plans purely for the hero are skipped.
	var hero_only := true
	for o in plan.orders:
		if o.target_kind != TacticalOrder.TARGET_KIND_HERO:
			hero_only = false
			break
	if hero_only:
		return
	captain.handle_plan(plan)

func _make_sample_match_start_plan() -> Resource:
	var trigger = PrePlanScript.PrePlanTrigger.new()
	trigger.event = &"match_start"
	var plan = PrePlanScript.PrePlan.new()
	plan.name = "Sample: opening invocation"
	plan.deputy = &"deputy"
	plan.trigger = trigger
	plan.orders = [] as Array[Resource]
	return plan
