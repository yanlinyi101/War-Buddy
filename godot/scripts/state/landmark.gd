class_name Landmark
extends Resource

# Doc 07 §3.2 + plan v0.15.1 §4.2. Designer-authored named region of the
# map. Deputy LLM resolves utterances ("守住坡口", "去中央拿金矿") against
# these by matching display_name + aliases.
#
# `grid_cells` stores the strings (e.g. ["F6", "G6"]); cell→world math
# lives on MapGrid so a Landmark stays a pure data record.

@export var landmark_id: StringName = &""
@export var display_name: String = ""
@export var aliases: Array[String] = []
@export var grid_cells: Array[String] = []
@export var world_center: Vector3 = Vector3.ZERO
