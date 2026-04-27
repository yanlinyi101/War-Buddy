class_name DeputyMemory
extends Resource

@export var deputy_id: StringName = &""
@export var total_matches: int = 0
@export var wins: int = 0
@export var losses: int = 0
@export var hours_played: float = 0.0
@export var relationship_traits: Dictionary = {}    # StringName -> float in [-1, 1]
@export var match_anecdotes: Array[String] = []     # 0-12 short, deputy-flavored memories
@export var preferred_phrases: Array[String] = []
@export var schema_version: int = 1

func to_dict() -> Dictionary:
	return {
		"deputy_id": String(deputy_id),
		"total_matches": total_matches,
		"wins": wins,
		"losses": losses,
		"hours_played": hours_played,
		"relationship_traits": relationship_traits.duplicate(true),
		"match_anecdotes": match_anecdotes.duplicate(),
		"preferred_phrases": preferred_phrases.duplicate(),
		"schema_version": schema_version,
	}

static func from_dict(d: Dictionary) -> DeputyMemory:
	var m := DeputyMemory.new()
	m.deputy_id = StringName(d.get("deputy_id", ""))
	m.total_matches = int(d.get("total_matches", 0))
	m.wins = int(d.get("wins", 0))
	m.losses = int(d.get("losses", 0))
	m.hours_played = float(d.get("hours_played", 0.0))
	m.relationship_traits = (d.get("relationship_traits", {}) as Dictionary).duplicate(true)
	var raw_anec: Array = d.get("match_anecdotes", [])
	var typed_anec: Array[String] = []
	for s in raw_anec:
		typed_anec.append(String(s))
	m.match_anecdotes = typed_anec
	var raw_phr: Array = d.get("preferred_phrases", [])
	var typed_phr: Array[String] = []
	for s in raw_phr:
		typed_phr.append(String(s))
	m.preferred_phrases = typed_phr
	m.schema_version = int(d.get("schema_version", 1))
	return m
