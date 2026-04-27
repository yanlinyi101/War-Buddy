class_name ControlPolicy
extends RefCounted

const TacticalOrder = preload("res://scripts/command/tactical_order.gd")

func can_issue(issuer: int, deputy: StringName, type_id: StringName) -> bool:
	push_error("ControlPolicy.can_issue is abstract")
	return false

# --- Concrete implementations as inner classes for grouped distribution ---

class FullControlPolicy:
	extends ControlPolicy

	func can_issue(_issuer: int, _deputy: StringName, _type_id: StringName) -> bool:
		return true

class HeroOnlyPolicy:
	extends ControlPolicy

	func can_issue(issuer: int, deputy: StringName, _type_id: StringName) -> bool:
		# Player issuing without a deputy seat is the hero direct case.
		return issuer == TacticalOrder.Issuer.PLAYER and deputy == &""

class AssistModePolicy:
	extends ControlPolicy

	func can_issue(issuer: int, _deputy: StringName, _type_id: StringName) -> bool:
		return issuer == TacticalOrder.Issuer.PLAYER

class ArchonControlPolicy:
	extends ControlPolicy

	var attached_seat: StringName

	func _init(seat: StringName = &"") -> void:
		attached_seat = seat

	func can_issue(issuer: int, deputy: StringName, _type_id: StringName) -> bool:
		if attached_seat == &"":
			return true
		# Block AI deputy plans for the attached seat
		if deputy == attached_seat and issuer != TacticalOrder.Issuer.PLAYER:
			return false
		return true
