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

# --- Match-end consolidation (spec 08 §8) ---
#
# The single mutation point for DeputyMemory. Called once per match
# after the victory/defeat event commits. v0.15.0 implements the
# deterministic side (totals/traits/anecdote prune); the optional LLM
# anecdote generation is wired through `llm_client` and skipped if
# the client is null or returns an error.

const MAX_ANECDOTES := 12
const TRAIT_DECAY_RATE := 0.05      # toward 0 each match
const TRUST_WIN_BUMP := 0.08
const TRUST_LOSS_BUMP := -0.05
const FRUSTRATION_LOSS_BUMP := 0.04
const BOND_WIN_BUMP := 0.06

func consolidate_after_match(
	deputy_id: StringName,
	match_summary: Dictionary,
	llm_client: RefCounted = null
) -> Resource:
	# Load → mutate → save. Returns the saved memory for callers that
	# want to inspect the post-consolidation state.
	var memory = load_memory(deputy_id)
	_apply_match_totals(memory, match_summary)
	_apply_trait_drift(memory, match_summary)
	var anecdote := _build_anecdote(memory, match_summary, llm_client)
	if anecdote != "":
		memory.match_anecdotes.append(anecdote)
	_prune_anecdotes(memory)
	save_memory(memory)
	return memory

func _apply_match_totals(memory: Resource, summary: Dictionary) -> void:
	memory.total_matches += 1
	var outcome: String = String(summary.get("outcome", ""))
	if outcome == "victory":
		memory.wins += 1
	elif outcome == "defeat":
		memory.losses += 1
	memory.hours_played += float(summary.get("elapsed_s", 0.0)) / 3600.0

func _apply_trait_drift(memory: Resource, summary: Dictionary) -> void:
	# Decay every existing trait toward 0 (equilibrium), then nudge by
	# outcome-specific bumps. All values clamped to [-1, 1].
	var traits: Dictionary = memory.relationship_traits.duplicate(true)
	for k in traits.keys():
		var v: float = float(traits[k])
		# Decay magnitude proportional to current value (exponential-ish).
		v = v * (1.0 - TRAIT_DECAY_RATE)
		traits[k] = v
	var outcome: String = String(summary.get("outcome", ""))
	match outcome:
		"victory":
			traits["trust"] = clampf(float(traits.get("trust", 0.0)) + TRUST_WIN_BUMP, -1.0, 1.0)
			traits["bond"] = clampf(float(traits.get("bond", 0.0)) + BOND_WIN_BUMP, -1.0, 1.0)
		"defeat":
			traits["trust"] = clampf(float(traits.get("trust", 0.0)) + TRUST_LOSS_BUMP, -1.0, 1.0)
			traits["frustration"] = clampf(float(traits.get("frustration", 0.0)) + FRUSTRATION_LOSS_BUMP, -1.0, 1.0)
		_:
			pass
	memory.relationship_traits = traits

func _build_anecdote(memory: Resource, summary: Dictionary, llm_client: RefCounted) -> String:
	# v0.15.0 always synthesizes a deterministic anecdote line so even an
	# offline / MockClient run produces a memory entry. When llm_client is
	# present and exposes a `summarize_match` method, we'd prefer its
	# output; that path stays a TODO until an LLM is wired specifically
	# for anecdote generation (avoid extra DeepSeek token spend).
	var outcome := String(summary.get("outcome", "unknown"))
	var elapsed := float(summary.get("elapsed_s", 0.0))
	var ene_killed: int = int(summary.get("enemy_buildings_killed", 0))
	var line := ""
	match outcome:
		"victory":
			line = "Win at %d s. Took down %d structures." % [int(elapsed), ene_killed]
		"defeat":
			line = "Lost the line at %d s. Survived %d structures." % [int(elapsed), ene_killed]
		_:
			line = "Match ended at %d s — outcome %s." % [int(elapsed), outcome]
	# Spec ≤80 chars cap.
	if line.length() > 80:
		line = line.substr(0, 77) + "..."
	# llm_client passthrough — left as a future enhancement.
	var _client = llm_client
	return line

func _prune_anecdotes(memory: Resource) -> void:
	# Keep latest MAX_ANECDOTES; pop oldest from the front.
	while memory.match_anecdotes.size() > MAX_ANECDOTES:
		memory.match_anecdotes.pop_front()
