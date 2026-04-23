extends Node
class_name MatchState

signal buildings_remaining_changed(remaining: int)
signal victory_triggered

var enemy_buildings_remaining := 0
var is_victory := false
var is_match_locked := false
var _registered_buildings: Dictionary = {}

func register_enemy_building(building: Node) -> void:
	if building == null:
		push_error("Tried to register null enemy building")
		return
	var building_id: String = str(building.get_meta("building_id", building.name))
	if _registered_buildings.has(building_id):
		return
	_registered_buildings[building_id] = building
	enemy_buildings_remaining = _registered_buildings.size()
	if not building.is_connected("destroyed", Callable(self, "_on_enemy_building_destroyed")):
		building.destroyed.connect(_on_enemy_building_destroyed)
	buildings_remaining_changed.emit(enemy_buildings_remaining)

func _on_enemy_building_destroyed(building_id: String) -> void:
	if not _registered_buildings.has(building_id):
		push_warning("Destroyed building was not registered: %s" % building_id)
		return
	_registered_buildings.erase(building_id)
	enemy_buildings_remaining = _registered_buildings.size()
	buildings_remaining_changed.emit(enemy_buildings_remaining)
	if enemy_buildings_remaining <= 0:
		trigger_victory()

func trigger_victory() -> void:
	if is_victory:
		return
	is_victory = true
	is_match_locked = true
	victory_triggered.emit()
