## Grid helpers (scripts/rules/grid.gd, port of src/battle/grid.ts).
extends "res://tests/unit/test_battle_base.gd"


func _field() -> Dictionary:
	return open_field(41)


func test_keys_round_trip_including_points_off_the_field() -> void:
	for p in [[0, 0], [13, 11], [5, 0], [0, 7], [999, 3], [-2, 4]]:
		var k := Grid.key(p[0], p[1])
		assert_eq(k, p[1] * 1000 + p[0])
		if p[0] >= 0:
			assert_eq(Grid.unkey(k), {"x": p[0], "y": p[1]}, str(p))
	# JS: { x: k % 1000, y: Math.floor(k / 1000) } for a negative key.
	assert_eq(Grid.unkey(-2995), {"x": -995, "y": -3})


func test_hypot_is_bit_exact_with_v8() -> void:
	# Math.hypot(2, 3) in V8 is 3.6055512754639896; sqrt(13) is 3.605551275463989.
	assert_true(Grid.hypot(2, 3) == 3.6055512754639896, "hypot(2,3) = %.17f" % Grid.hypot(2, 3))
	assert_true(Grid.hypot(3, 2) == 3.6055512754639896)
	assert_true(Grid.hypot(-2, 3) == 3.6055512754639896)
	assert_true(Grid.hypot(5, 12) == 13.0)
	assert_true(Grid.hypot(3, 7) == 7.615773105863909)
	assert_true(Grid.hypot(0.5, 1.5) == 1.5811388300841898)
	assert_eq(Grid.hypot(0, 0), 0.0)
	assert_eq(Grid.dist({"x": 1, "y": 1}, {"x": 4, "y": 5}), 5.0)


func test_manhattan_and_dir_to() -> void:
	assert_eq(Grid.manhattan({"x": 1, "y": 2}, {"x": 4, "y": 0}), 5)
	assert_eq(Grid.dir_to({"x": 0, "y": 0}, {"x": 3, "y": 1}), 0)
	assert_eq(Grid.dir_to({"x": 0, "y": 0}, {"x": 1, "y": 3}), 1)
	assert_eq(Grid.dir_to({"x": 0, "y": 0}, {"x": -3, "y": 1}), 2)
	assert_eq(Grid.dir_to({"x": 0, "y": 0}, {"x": 1, "y": -3}), 3)
	# Ties go along x; staying put faces +x.
	assert_eq(Grid.dir_to({"x": 0, "y": 0}, {"x": 2, "y": 2}), 0)
	assert_eq(Grid.dir_to({"x": 0, "y": 0}, {"x": -2, "y": -2}), 2)
	assert_eq(Grid.dir_to({"x": 4, "y": 4}, {"x": 4, "y": 4}), 0)
	# Fractional targets (the centre of several foes).
	assert_eq(Grid.dir_to({"x": 2, "y": 2}, {"x": 2.4, "y": 5.5}), 1)
	for d in 4:
		assert_eq(Grid.dir_to({"x": 0, "y": 0}, Grid.DIRS[d]), d)
		assert_eq([Grid.DX[d], Grid.DY[d]], [Grid.DIRS[d].x, Grid.DIRS[d].y])


func test_bounds_neighbours_and_edges() -> void:
	var m := _field()
	assert_eq([m.w, m.h], [14, 12])
	assert_eq(Grid.tile_at(m, 3, 4), m.tiles[4 * 14 + 3])
	assert_eq(Grid.tile_at(m, -1, 0), null)
	assert_eq(Grid.tile_at(m, 14, 0), null)
	assert_eq(Grid.tile_at(m, 0, 12), null)
	assert_true(Grid.in_bounds(m, 13, 11))
	assert_false(Grid.in_bounds(m, 13, 12))
	assert_eq(Grid.neighbors(m, {"x": 0, "y": 0}), [{"x": 1, "y": 0}, {"x": 0, "y": 1}])
	assert_eq(Grid.neighbors(m, {"x": 5, "y": 5}).size(), 4)
	assert_true(Grid.is_edge(m, {"x": 0, "y": 5}))
	assert_true(Grid.is_edge(m, {"x": 13, "y": 5}))
	assert_true(Grid.is_edge(m, {"x": 5, "y": 11}))
	assert_false(Grid.is_edge(m, {"x": 5, "y": 5}))


func test_passability_cost_and_steps() -> void:
	var m := _field()
	assert_true(Grid.tile_passable(m, 2, 2))
	assert_false(Grid.tile_passable(m, -1, 2))
	m.tiles[2 * 14 + 2].terrain = "water"
	assert_false(Grid.tile_passable(m, 2, 2))
	m.tiles[2 * 14 + 3]["prop"] = "tree_oak"
	assert_false(Grid.tile_passable(m, 3, 2))
	m.tiles[2 * 14 + 4]["prop"] = "gate"
	assert_true(Grid.tile_passable(m, 4, 2), "a gateway can be walked through")
	m.tiles[2 * 14 + 5].terrain = "forest"
	assert_eq(Grid.move_cost(m, 5, 2), 2)
	assert_eq(Grid.move_cost(m, 6, 2), 1)
	m.tiles[3 * 14 + 6].h = 1
	m.tiles[4 * 14 + 6].h = 3
	assert_true(Grid.can_step(m, {"x": 6, "y": 2}, {"x": 6, "y": 3}))
	assert_false(Grid.can_step(m, {"x": 6, "y": 3}, {"x": 6, "y": 4}))
	assert_false(Grid.can_step(m, {"x": 0, "y": 0}, {"x": -1, "y": 0}))


func test_unit_at_sees_only_squads_on_the_field() -> void:
	var units := [
		{"uid": "a", "x": 1, "y": 1, "status": "dead"},
		{"uid": "b", "x": 1, "y": 1, "status": "active"},
		{"uid": "c", "x": 2, "y": 1, "status": "routing"},
		{"uid": "d", "x": 3, "y": 1, "status": "reserve"},
		{"uid": "e", "x": 4, "y": 1, "status": "fled"},
		{"uid": "f", "x": 5, "y": 1, "status": "downed"},
	]
	assert_eq(Grid.unit_at(units, 1, 1).uid, "b")
	assert_eq(Grid.unit_at(units, 2, 1).uid, "c")
	for x in [3, 4, 5, 6]:
		assert_eq(Grid.unit_at(units, x, 1), null)


func test_line_of_sight() -> void:
	var m := _field()
	var a := {"x": 1, "y": 5}
	var b := {"x": 7, "y": 5}
	var los := Grid.line_of_sight(m, a, b)
	assert_false(los.blocked)
	assert_eq(los.partial, 0)
	assert_eq(los.tiles, [{"x": 2, "y": 5}, {"x": 3, "y": 5}, {"x": 4, "y": 5}, {"x": 5, "y": 5}, {"x": 6, "y": 5}])
	# A bush half-hides; a tree blocks.
	m.tiles[5 * 14 + 3]["prop"] = "bush"
	los = Grid.line_of_sight(m, a, b)
	assert_false(los.blocked)
	assert_eq(los.partial, 1)
	m.tiles[5 * 14 + 4]["prop"] = "tree_pine"
	los = Grid.line_of_sight(m, a, b)
	assert_true(los.blocked)
	assert_eq(los.tiles.back(), {"x": 4, "y": 5})
	m.tiles[5 * 14 + 3].erase("prop")
	m.tiles[5 * 14 + 4].erase("prop")
	# One wooded tile obscures; two block (0.75 + 0.75 >= 1).
	m.tiles[5 * 14 + 3].terrain = "forest"
	los = Grid.line_of_sight(m, a, b)
	assert_eq([los.blocked, los.partial], [false, 1])
	m.tiles[5 * 14 + 5].terrain = "forest"
	assert_true(Grid.line_of_sight(m, a, b).blocked)
	m.tiles[5 * 14 + 3].terrain = "grass"
	m.tiles[5 * 14 + 5].terrain = "grass"
	# A hill between blocks; the shooter's own height lets him see over it.
	m.tiles[5 * 14 + 4].h = 2
	assert_true(Grid.line_of_sight(m, a, b).blocked)
	m.tiles[5 * 14 + 1].h = 2
	m.tiles[5 * 14 + 7].h = 2
	assert_false(Grid.line_of_sight(m, a, b).blocked)
