extends StaticBody3D
class_name EnemyBuilding

signal destroyed(building_id: String)
signal hp_changed(current_hp: int, max_hp: int)
signal attacked_target(target_id: String, damage: int)

@export var building_id := "enemy_building"
@export var max_hp := 60
@export var faction := "enemy"

# v0.9.0 — defensive turret attack (spec 09 §7 + §4). Buildings now
# fire at the nearest friendly squad unit within attack_range every
# attack_interval seconds, dealing attack_damage. Damage source is
# recorded so unit death events name the attacker.
@export var attack_range: float = 6.0
@export var attack_damage: int = 10
@export var attack_interval: float = 0.85
@export var attack_enabled: bool = true
# Doc 09 §4 — building defensive shot defaults to `normal` (matches §7.3's
# `turret` row). Armor class for the building itself is `structure`.
@export var armor_class: StringName = &"structure"
@export var armor: int = 1
@export var dmg: int = 10
@export var dmg_type: StringName = &"normal"

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var hp_label: Label3D = $HpLabel3D
@onready var hover_ring: Decal = get_node_or_null("HoverRing")
@onready var hp_bar: Sprite3D = get_node_or_null("HpBar3D")

const HOVER_FADE_IN_S := 0.08    # spec 11 §6.2: ≤80 ms
const HOVER_FADE_OUT_S := 0.12

var hp := 60
var is_destroyed := false
var _hover_tween: Tween = null
var _attack_cooldown: float = 0.0

func _ready() -> void:
	hp = max_hp
	set_meta("building_id", building_id)
	_update_visuals()
	hp_changed.emit(hp, max_hp)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func take_damage(amount: int) -> void:
	if is_destroyed:
		return
	hp = maxi(0, hp - amount)
	_update_visuals()
	hp_changed.emit(hp, max_hp)
	if hp == 0:
		_destroy()

func _process(delta: float) -> void:
	if is_destroyed or not attack_enabled:
		return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	if _attack_cooldown > 0.0:
		return
	var victim := _find_nearest_friendly_in_range()
	if victim == null:
		return
	if not victim.has_method("take_damage"):
		return
	# Doc 09 §4.4 — route through CombatService for the matrix + armor formula.
	# Falls back to attack_damage if CombatService autoload isn't mounted
	# (e.g. isolated GUT tests). dmg field mirrors attack_damage so the
	# matrix sees the canonical base.
	var final_dmg: int = attack_damage
	var t = get_tree()
	if t != null:
		var svc = t.root.get_node_or_null("CombatService")
		if svc != null and svc.has_method("resolve_damage"):
			# Pass attack_damage as the explicit base so the @export dmg
			# field is authoritative even if a future copy diverges.
			dmg = attack_damage
			final_dmg = svc.resolve_damage(self, victim, attack_damage)
	victim.take_damage(final_dmg, self)
	_attack_cooldown = attack_interval
	attacked_target.emit(String(victim.get("unit_id")) if victim.get("unit_id") != null else victim.name, final_dmg)

func _find_nearest_friendly_in_range() -> Node:
	# v0.9.0 simple targeting: nearest squad unit within attack_range;
	# v0.12.2: fall back to hero (in "heroes" group) when no squad in
	# range. Hero-priority is intentionally low so squads tank by default
	# — vision §2.2 "main character feel".
	var best: Node = null
	var best_d := attack_range
	for u in get_tree().get_nodes_in_group("squad_units"):
		if u == null or not is_instance_valid(u):
			continue
		if u.get("is_dead") != null and u.is_dead:
			continue
		if u is Node3D:
			var d: float = (u as Node3D).global_position.distance_to(global_position)
			if d < best_d:
				best_d = d
				best = u
	if best != null:
		return best
	# Hero fallback.
	for h in get_tree().get_nodes_in_group("heroes"):
		if h == null or not is_instance_valid(h):
			continue
		if h.get("is_dead") != null and h.is_dead:
			continue
		if h is Node3D:
			var d: float = (h as Node3D).global_position.distance_to(global_position)
			if d <= attack_range:
				return h
	return null

func _on_mouse_entered() -> void:
	if is_destroyed or hover_ring == null:
		return
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	hover_ring.visible = true
	_hover_tween = create_tween()
	_hover_tween.tween_property(hover_ring, "modulate:a", 1.0, HOVER_FADE_IN_S)

func _on_mouse_exited() -> void:
	if hover_ring == null:
		return
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(hover_ring, "modulate:a", 0.0, HOVER_FADE_OUT_S)
	_hover_tween.tween_callback(func(): if hover_ring != null: hover_ring.visible = false)

func _update_visuals() -> void:
	if hp_label != null:
		hp_label.text = "%s HP %d/%d" % [building_id, hp, max_hp]
	if hp_bar != null and hp_bar.has_method("set_hp"):
		hp_bar.set_hp(hp, max_hp)
	var ratio := float(hp) / float(max_hp)
	if mesh_instance != null:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.25 + ratio * 0.45, 0.25 + ratio * 0.25)
		mesh_instance.material_override = material

const DESTROY_TWEEN_DURATION := 0.35

func _destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	if has_node("CollisionShape3D"):
		$CollisionShape3D.disabled = true
	if has_node("NavigationObstacle3D"):
		$NavigationObstacle3D.avoidance_enabled = false
	if hover_ring != null:
		hover_ring.visible = false
	if hp_bar != null:
		hp_bar.visible = false
	# Emit before the tween so match-state / victory reacts on the same frame
	# as the killing blow, not after the visual settles.
	destroyed.emit(building_id)
	print("[RTSMVP] Enemy building destroyed: %s" % building_id)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, DESTROY_TWEEN_DURATION)
	if hp_label != null:
		tween.tween_property(hp_label, "modulate:a", 0.0, DESTROY_TWEEN_DURATION)
	if mesh_instance != null and mesh_instance.material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = mesh_instance.material_override
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tween.tween_property(mat, "albedo_color:a", 0.0, DESTROY_TWEEN_DURATION)
	tween.chain().tween_callback(queue_free)
