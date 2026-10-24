## Isometric projection and camera maths (src/render/iso.ts) against values
## from the original (tests/fixtures/render/render_values.json).
extends "res://tests/test_case.gd"

const Iso = preload("res://scripts/render/iso.gd")

var V: Dictionary


func before_all() -> void:
	V = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/render/render_values.json"))


func test_constants() -> void:
	assert_eq(Iso.TW, 128)
	assert_eq(Iso.TH, 64)
	assert_eq(Iso.LH, 26)


func test_projection_matches_original() -> void:
	for r in V.iso:
		assert_almost(Iso.iso_x(r[0], r[1]), r[3], 1e-9, "iso_x %s" % [r])
		assert_almost(Iso.iso_y(r[0], r[1], r[2]), r[4], 1e-9, "iso_y %s" % [r])
		var p := Iso.iso(r[0], r[1], r[2])
		assert_almost(p.x, r[3], 1e-3)
		assert_almost(p.y, r[4], 1e-3)
	for r in V.inv:
		var g := Iso.from_iso(r[0], r[1])
		assert_almost(g.x, r[2], 1e-4, "from_iso x")
		assert_almost(g.y, r[3], 1e-4, "from_iso y")


func test_from_iso_round_trip() -> void:
	for x in [-7.0, 0.0, 3.25, 13.0, 40.5]:
		for y in [-3.0, 0.0, 6.5, 21.0]:
			var g := Iso.from_iso(Iso.iso_x(x, y), Iso.iso_y(x, y))
			assert_almost(g.x, x, 1e-4)
			assert_almost(g.y, y, 1e-4)


func test_easing_and_helpers() -> void:
	assert_almost(Iso.ease_out_cubic(0.0), 0.0)
	assert_almost(Iso.ease_out_cubic(1.0), 1.0)
	assert_almost(Iso.ease_out_cubic(0.5), 0.875)
	assert_almost(Iso.ease_in_out_quad(0.25), 0.125)
	assert_almost(Iso.ease_in_out_quad(0.75), 0.875)
	assert_almost(Iso.clamp(5.0, 0.0, 1.0), 1.0)
	assert_almost(Iso.clamp(-5.0, 0.0, 1.0), 0.0)
	assert_almost(Iso.lerp(2.0, 4.0, 0.25), 2.5)


func test_camera_smoothing_matches_original() -> void:
	var cam = Iso.make_camera(100, 200, 1)
	cam.tx = 400
	cam.ty = -50
	cam.tzoom = 0.5
	cam.shake = 0.5
	for i in 10:
		Iso.update_camera(cam, 1.0 / 60.0)
		var s: Array = V.cameraSteps[i]
		assert_almost(cam.x, s[0], 1e-9, "x step %d" % i)
		assert_almost(cam.y, s[1], 1e-9, "y step %d" % i)
		assert_almost(cam.zoom, s[2], 1e-12, "zoom step %d" % i)
		assert_almost(cam.shake, s[3], 1e-12, "shake step %d" % i)
	var a := Iso.world_to_screen(cam, 321, -45, 1920, 1080)
	assert_almost(a.x, V.proj[0].x, 1e-3)
	assert_almost(a.y, V.proj[0].y, 1e-3)
	var b := Iso.screen_to_world(cam, 17, 1000, 1920, 1080)
	assert_almost(b.x, V.proj[1].x, 1e-3)
	assert_almost(b.y, V.proj[1].y, 1e-3)
