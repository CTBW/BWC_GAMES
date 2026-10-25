extends "res://tests/test_case.gd"

const Fields = preload("res://scripts/rules/terrain_test_fields.gd")
const Relief = preload("res://scripts/render/relief.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const Iso = preload("res://scripts/render/iso.gd")

const BLUFF := 4


func _step_map() -> Array:
	# A one-level plateau on flat ground, as the rules' integer heights make.
	var tiles: Array = []
	for y in 8:
		for x in 8:
			tiles.append({"x": x, "y": y, "h": 1 if x >= 2 and x <= 5 and y >= 2 and y <= 5 else 0})
	return tiles


func test_surface_passes_through_tiles_and_flat_ground_is_exact() -> void:
	var r = Relief.new(8, 8, 2, _step_map(), 5)
	for x in 8:
		for y in 8:
			assert_almost(r.surface(x, y), r.tile(x, y), 0.00001)
	# Two tiles from the step the ground is exactly level (the feet sit still).
	assert_eq(r.surface(7.4, 0.3), 0.0)
	assert_eq(r.surface(3.5, 3.5), 1.0)


func test_a_one_level_step_is_a_smooth_bank_not_a_wall() -> void:
	var r = Relief.new(8, 8, 2, _step_map(), 5)
	# Across the plateau's camera-facing edge (x 5 -> 6) the ground falls
	# smoothly: monotone, with its slope peaking in the middle.
	var prev: float = r.surface(5.0, 3.5)
	var steepest := 0.0
	for i in range(1, 21):
		var h: float = r.surface(5.0 + i / 20.0, 3.5)
		assert_true(h <= prev + 0.00001, "the bank falls monotonically")
		steepest = maxf(steepest, (prev - h) * 20.0)
		prev = h
	assert_true(steepest > 1.2 and steepest < 1.6, "a bank about a tile wide: %f" % steepest)
	# The slope is continuous across a tile centre (no crease, unlike bilinear).
	var e := 0.001
	var left: float = (r.surface(5.0, 3.5) - r.surface(5.0 - e, 3.5)) / e
	var right: float = (r.surface(5.0 + e, 3.5) - r.surface(5.0, 3.5)) / e
	assert_almost(left, right, 0.01)


func test_bluff_field_has_banks_a_ramp_and_a_connected_patrol_area() -> void:
	var setup: Dictionary = Fields.make(BLUFF)
	var m: Dictionary = setup.map
	assert_eq(m.name, Fields.NAMES[BLUFF])
	var r = Relief.new(m.w, m.h, m.border, m.tiles + m.outerGround, m.seed)
	# Banks: ground steeper than 1.2 levels per tile falling toward the camera
	# (+x, +y), where the shader exposes earth (it starts near 0.85).
	var banks := 0
	for t in m.tiles:
		for d in [Vector2(-0.25, -0.25), Vector2(0.25, -0.25), Vector2(-0.25, 0.25), Vector2(0.25, 0.25)]:
			var p: Vector2 = Vector2(t.x, t.y) + d
			var gx: float = (r.surface(p.x + 0.05, p.y) - r.surface(p.x - 0.05, p.y)) / 0.1
			var gy: float = (r.surface(p.x, p.y + 0.05) - r.surface(p.x, p.y - 0.05)) / 0.1
			var slope := sqrt(gx * gx + gy * gy)
			if slope > 1.2 and -(gx + gy) / (slope * 1.41421) > 0.3:
				banks += 1
	assert_true(banks >= 40, "camera-facing bank samples: %d" % banks)
	var first: Dictionary = setup.units[0]
	var todo: Array = [{"x": first.x, "y": first.y}]
	var seen := {Grid.key(first.x, first.y): true}
	var i := 0
	while i < todo.size():
		var a: Dictionary = todo[i]
		i += 1
		for b in Grid.neighbors(m, a):
			var key := Grid.key(b.x, b.y)
			if not seen.has(key) and Grid.tile_passable(m, b.x, b.y) and Grid.can_step(m, a, b):
				seen[key] = true
				todo.append(b)
	assert_true(todo.size() > 250, "useful connected patrol area: %d" % todo.size())
	assert_true(seen.has(Grid.key(20, 12)), "east exit reachable")
	assert_true(seen.has(Grid.key(10, 8)), "the bluff's top is reachable by its ramp")
	assert_true(Grid.tile_at(m, 10, 8).h >= 3, "the bluff stands three levels high")


func test_bluff_picking_round_trips_on_the_banks() -> void:
	var m: Dictionary = Fields.make(BLUFF).map
	var r = Relief.new(m.w, m.h, m.border, m.tiles + m.outerGround, m.seed)
	for t in m.tiles:
		var p := Vector2(t.x + 0.23, t.y - 0.31)
		var wp := Iso.iso(p.x, p.y, r.surface(p.x, p.y))
		assert_true(r.unproject(wp).distance_to(p) < 0.001, "picking round-trips at %s" % p)
