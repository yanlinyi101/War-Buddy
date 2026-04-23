extends StaticBody3D
class_name EnemyBuilding

signal destroyed(building_id: String)
signal hp_changed(current_hp: int, max_hp: int)

@export var building_id := "enemy_building"
@export var max_hp := 60
@export var faction := "enemy"

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var hp_label: Label3D = $HpLabel3D

var hp := 60
var is_destroyed := false

func _ready() -> void:
	hp = max_hp
	set_meta("building_id", building_id)
	_update_visuals()
	hp_changed.emit(hp, max_hp)

func take_damage(amount: int) -> void:
	if is_destroyed:
		return
	hp = maxi(0, hp - amount)
	_update_visuals()
	hp_changed.emit(hp, max_hp)
	if hp == 0:
		_destroy()

func _update_visuals() -> void:
	if hp_label != null:
		hp_label.text = "%s HP %d/%d" % [building_id, hp, max_hp]
	var ratio := float(hp) / float(max_hp)
	if mesh_instance != null:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.25 + ratio * 0.45, 0.25 + ratio * 0.25)
		mesh_instance.material_override = material

func _destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	if has_node("CollisionShape3D"):
		$CollisionShape3D.disabled = true
	destroyed.emit(building_id)
