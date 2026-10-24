## Atmosphere (src/render/atmosphere.ts): cloud layout from hash2, drift and
## wrap, mote population, and the nodes it makes.
extends "res://tests/test_case.gd"

const Atmosphere = preload("res://scripts/render/atmosphere.gd")

var values: Dictionary


func before_all() -> void:
	values = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/render/render_values.json"))


func test_clouds_match_original() -> void:
	for seed in values.clouds:
		var a = Atmosphere.new(float(seed))
		var want: Array = values.clouds[seed]
		assert_eq(a.clouds.size(), 7)
		for i in 7:
			for k in ["x", "y", "r", "s"]:
				assert_almost(a.clouds[i][k], want[i][k], 1e-9, "seed %s cloud %d %s" % [seed, i, k])


func test_clouds_drift_and_wrap() -> void:
	var a = Atmosphere.new(77)
	a.clouds[0].x = 2199.0
	var y0: float = a.clouds[1].y
	a.update(1.0, 1920, 1080)
	assert_almost(a.clouds[0].x, -2200.0, 1e-9, "wraps past 2200")
	assert_almost(a.clouds[1].y, y0 + 5.0 * a.clouds[1].s, 1e-9)


func test_motes_population() -> void:
	var a = Atmosphere.new(1)
	a.update(0.016, 1920, 1080)
	assert_between(a.motes.size(), 30, 34)
	for m in a.motes:
		assert_true(m.kind == "pollen" or m.kind == "leaf")
	a.night = true
	a.motes.clear()
	a.update(0.016, 1920, 1080)
	assert_eq(a.motes.size(), 26)
	for m in a.motes:
		assert_eq(m.kind, "firefly")


func test_nodes_build_and_draw() -> void:
	var a = Atmosphere.new(3)
	var root := Node2D.new()
	root.add_child(a.make_clouds_node(0, 0))
	root.add_child(a.make_grade_node())
	(Engine.get_main_loop() as SceneTree).root.add_child(root)
	a.update(0.1, 1920, 1080)
	a.redraw(Vector2(1920, 1080), 1.0)
	a.night = true
	a.redraw(Vector2(1920, 1080), 1.1)
	root.free()
