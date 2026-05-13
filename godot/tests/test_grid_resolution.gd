extends "res://addons/gut/test.gd"

# Plan v0.15.1 §6.6 — MapGrid world ↔ cell math. Origin (-30, 0, -30),
# 12×12 grid, cell_size 5m.

const MapGridScript = preload("res://scripts/state/map_grid.gd")

func _grid() -> Resource:
	return load("res://data/maps/graybox/map_grid.tres")

func test_grid_loads():
	var g = _grid()
	assert_ne(g, null)
	assert_eq(g.columns, 12)
	assert_eq(g.rows, 12)
	assert_almost_eq(g.cell_size.x, 5.0, 1e-6)

func test_world_to_cell_player_main():
	var g = _grid()
	# Player main HQ at (-22, 3, 22) — col_idx = (-22+30)/5 = 1.6 → 1 → B;
	# row_idx = (22+30)/5 = 10.4 → 10 → row 11. Cell = "B11".
	assert_eq(g.world_to_cell(Vector3(-22, 3, 22)), "B11")

func test_world_to_cell_central_plateau():
	var g = _grid()
	# (0, 1.5, 0): col = 6 → G, row = 6 → row 7. Cell = "G7".
	assert_eq(g.world_to_cell(Vector3(0, 1.5, 0)), "G7")

func test_world_to_cell_enemy_main():
	var g = _grid()
	# (22, 3, -22): col = 10 → K, row = 1 → row 2. Cell = "K2".
	assert_eq(g.world_to_cell(Vector3(22, 3, -22)), "K2")

func test_cell_to_world_round_trip():
	var g = _grid()
	# Cell "G7" → world ~ (2.5, 0, 2.5) (center of cell). Wait: col_idx 6,
	# row_idx 6, center at origin + (6.5, 0, 6.5) × 5 = (-30+32.5, 0, -30+32.5)
	# = (2.5, 0, 2.5).
	var w = g.cell_to_world("G7")
	assert_almost_eq(w.x, 2.5, 0.01)
	assert_almost_eq(w.z, 2.5, 0.01)

func test_cell_to_world_invalid_returns_zero():
	var g = _grid()
	assert_eq(g.cell_to_world("Z99"), Vector3.ZERO)
	assert_eq(g.cell_to_world("X"), Vector3.ZERO)
