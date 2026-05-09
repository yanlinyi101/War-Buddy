# EventBus — registered as `EventBus` autoload via project.godot.
# class_name omitted to avoid colliding with the autoload symbol of the same name.
#
# Doc 09 §12 names "EventBus-style signals" as the report-back channel for
# behavior trees and as the seam Captains will subscribe to for autonomous
# tick reactions (spec 08 §11.6 "tick_observe"). v0.7.0 lands the channel
# itself; consumers come online incrementally.
#
# All payloads are Dictionaries (not typed signal args) so adding fields is
# additive and never breaks existing listeners.

extends Node

signal match_started(payload: Dictionary)
signal match_ended(payload: Dictionary)             # { reason: "victory" | "defeat" | "abort" }
signal unit_spawned(payload: Dictionary)            # { unit_id, faction_id, agency_tier, position }
signal unit_destroyed(payload: Dictionary)          # { unit_id, faction_id, killer_id }
signal building_destroyed(payload: Dictionary)      # { building_id, faction_id }
signal hp_changed(payload: Dictionary)              # { entity_id, current_hp, max_hp }
signal order_completed(payload: Dictionary)         # { order_id, unit_id, outcome }
signal order_failed(payload: Dictionary)            # { order_id, unit_id, reason }
signal order_progress(payload: Dictionary)          # { order_id, unit_id, fraction }

# --- Convenience publishers (so callers don't all duplicate `.emit()` calls). ---

func publish_match_started(payload: Dictionary = {}) -> void:
	match_started.emit(payload)

func publish_match_ended(reason: String, extra: Dictionary = {}) -> void:
	var p := extra.duplicate(true)
	p["reason"] = reason
	match_ended.emit(p)

func publish_building_destroyed(building_id: String, faction_id: StringName = &"enemy") -> void:
	building_destroyed.emit({"building_id": building_id, "faction_id": String(faction_id)})

func publish_unit_destroyed(unit_id: String, faction_id: StringName = &"", killer_id: String = "") -> void:
	unit_destroyed.emit({
		"unit_id": unit_id,
		"faction_id": String(faction_id),
		"killer_id": killer_id,
	})

func publish_hp_changed(entity_id: String, current_hp: int, max_hp: int) -> void:
	hp_changed.emit({"entity_id": entity_id, "current_hp": current_hp, "max_hp": max_hp})

func publish_order_completed(order_id: StringName, unit_id: String, outcome: StringName = &"ok") -> void:
	order_completed.emit({
		"order_id": String(order_id),
		"unit_id": unit_id,
		"outcome": String(outcome),
	})

func publish_order_failed(order_id: StringName, unit_id: String, reason: StringName) -> void:
	order_failed.emit({
		"order_id": String(order_id),
		"unit_id": unit_id,
		"reason": String(reason),
	})
