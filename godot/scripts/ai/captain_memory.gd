class_name CaptainMemory
extends Resource

# Persistent captain memory per spec 08 §11.6 (vision §2.3 lock-in).
# Captains carry memory across matches even after death; reinforcement_pct
# is clamped at 0.15 here at write time (the cap lives in 08, not in 09).

const MAX_REINFORCEMENT := 0.15

@export var captain_persona_id: StringName = &""
@export var match_appearances: int = 0
@export var matches_won_alongside: int = 0
@export var deaths: int = 0
@export var preferred_axis: StringName = &""
@export var reinforcement_pct: float = 0.0
@export var match_anecdotes: Array[String] = []
@export var schema_version: int = 1

func clamp_reinforcement() -> void:
	reinforcement_pct = clampf(reinforcement_pct, 0.0, MAX_REINFORCEMENT)

func to_dict() -> Dictionary:
	clamp_reinforcement()
	return {
		"captain_persona_id": String(captain_persona_id),
		"match_appearances": match_appearances,
		"matches_won_alongside": matches_won_alongside,
		"deaths": deaths,
		"preferred_axis": String(preferred_axis),
		"reinforcement_pct": reinforcement_pct,
		"match_anecdotes": match_anecdotes.duplicate(),
		"schema_version": schema_version,
	}

static func from_dict(d: Dictionary) -> CaptainMemory:
	var m := CaptainMemory.new()
	m.captain_persona_id = StringName(d.get("captain_persona_id", ""))
	m.match_appearances = int(d.get("match_appearances", 0))
	m.matches_won_alongside = int(d.get("matches_won_alongside", 0))
	m.deaths = int(d.get("deaths", 0))
	m.preferred_axis = StringName(d.get("preferred_axis", ""))
	m.reinforcement_pct = float(d.get("reinforcement_pct", 0.0))
	var raw_anec: Array = d.get("match_anecdotes", [])
	var typed_anec: Array[String] = []
	for s in raw_anec:
		typed_anec.append(String(s))
	m.match_anecdotes = typed_anec
	m.schema_version = int(d.get("schema_version", 1))
	m.clamp_reinforcement()
	return m
