class_name MapGrid
extends Resource

# Plan v0.15.1 §6.6. Re-bake the 60×60 graybox into a 12×12 designer
# grid (A1–L12), 5 m per cell. World ↔ cell conversion helpers used by
# the snapshot builder for `pos_grid` strings and by the landmark
# resolution when player utterances reference cells.

@export var columns: int = 12
@export var rows: int = 12
@export var cell_size: Vector2 = Vector2(5.0, 5.0)
@export var origin_world: Vector3 = Vector3(-30.0, 0.0, -30.0)   # SW corner of the map

const COL_LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

# Convert a world position to a cell string like "F6". Columns are
# letters (A = west, L = east at 12 columns); rows are 1-based ints
# (1 = south at origin_world.z, 12 = north).
func world_to_cell(pos: Vector3) -> String:
	if cell_size.x <= 0.0 or cell_size.y <= 0.0:
		return ""
	var col_idx := int(floor((pos.x - origin_world.x) / cell_size.x))
	var row_idx := int(floor((pos.z - origin_world.z) / cell_size.y))
	col_idx = clampi(col_idx, 0, columns - 1)
	row_idx = clampi(row_idx, 0, rows - 1)
	if col_idx >= COL_LETTERS.length():
		return ""
	return "%s%d" % [COL_LETTERS[col_idx], row_idx + 1]

# Convert a cell string like "F6" to the world position at the *center*
# of that cell. Returns Vector3.ZERO if the string is malformed.
func cell_to_world(cell: String) -> Vector3:
	if cell.length() < 2:
		return Vector3.ZERO
	var col_letter := cell.substr(0, 1).to_upper()
	var col_idx := COL_LETTERS.find(col_letter)
	if col_idx < 0 or col_idx >= columns:
		return Vector3.ZERO
	var row_str := cell.substr(1, cell.length() - 1)
	if not row_str.is_valid_int():
		return Vector3.ZERO
	var row_idx := row_str.to_int() - 1
	if row_idx < 0 or row_idx >= rows:
		return Vector3.ZERO
	var x = origin_world.x + (float(col_idx) + 0.5) * cell_size.x
	var z = origin_world.z + (float(row_idx) + 0.5) * cell_size.y
	return Vector3(x, origin_world.y, z)

func is_valid_cell(cell: String) -> bool:
	return cell_to_world(cell) != Vector3.ZERO or cell == "A1"
