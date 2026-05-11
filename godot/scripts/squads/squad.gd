class_name Squad
extends Resource

# Doc 09 §8 — squad-level metadata. A squad's category is determined by
# the regulars it contains; the captain persona must declare that
# category in its `eligible_categories`. v0.9.5 lands the data + the
# binding validation; runtime squad instances spawn alongside the
# production pipeline (v0.10).

@export var squad_id: StringName = &""
@export var category: StringName = &""             # one of doc 09 §3.1 categories
@export var captain_persona_id: StringName = &""
@export var member_unit_ids: Array[String] = []
@export var rally_point: Vector3 = Vector3.ZERO

# Doc 09 §8.1 — enforce category match between captain and squad.
# Returns { ok: bool, reason: StringName }.
static func validate_binding(persona: Resource, category: StringName) -> Dictionary:
	if persona == null:
		return {"ok": false, "reason": &"missing_persona"}
	if not persona.has_method("can_lead_category"):
		return {"ok": false, "reason": &"persona_missing_api"}
	if not persona.can_lead_category(category):
		return {"ok": false, "reason": &"category_mismatch"}
	return {"ok": true, "reason": &""}
