## Camera controller (scripts/render/camera.gd): exact picking maths, the
## world transform, zoom limits, drag and keyboard pan, and picking through a
## node placed under an arbitrary canvas transform (window resize / stretch).
extends "res://tests/test_case.gd"

const Camera = preload("res://scripts/render/camera.gd")


func test_round_trip_under_zoom() -> void:
	for z in [0.22, 0.4, 0.62, 1.0, 1.6]:
		for view in [Vector2(1920, 1080), Vector2(2560, 1080), Vector2(1920, 1440), Vector2(800, 600)]:
			var c = Camera.new(-113.92, 1529.12, z)
			for p in [Vector2(0, 0), Vector2(17, 1000), Vector2(1919, 3), Vector2(960, 540)]:
				var w: Vector2 = c.to_world(p, view)
				var s: Vector2 = c.to_screen(w, view)
				assert_almost(s.x, p.x, 1e-3, "x z=%s" % z)
				assert_almost(s.y, p.y, 1e-3, "y z=%s" % z)
			# The view centre is the camera position.
			var mid: Vector2 = c.to_world(view / 2.0, view)
			assert_almost(mid.x, c.x, 1e-3)
			assert_almost(mid.y, c.y, 1e-3)


func test_transform_matches_world_to_screen() -> void:
	var c = Camera.new(448.0, 784.58, 0.658)
	var view := Vector2(1920, 1080)
	var xf: Transform2D = c.transform(view)
	for w in [Vector2(0, 0), Vector2(-2436, -604), Vector2(1000, 1500)]:
		var a: Vector2 = xf * w
		var b: Vector2 = c.to_screen(w, view)
		assert_almost(a.x, b.x, 1e-2)
		assert_almost(a.y, b.y, 1e-2)
	# Shake offsets the screen position only.
	var xs: Transform2D = c.transform(view, 3.0, -2.0)
	assert_almost((xs * Vector2.ZERO).x, (xf * Vector2.ZERO).x + 3.0, 1e-3)


func test_wheel_limits() -> void:
	var c = Camera.new(0, 0, 0.62)
	for i in 40:
		c.wheel(100, 0.4, 1.3)
	assert_almost(c.tzoom, 0.4, 1e-9, "zoom out stops at the limit")
	for i in 40:
		c.wheel(-100, 0.4, 1.3)
	assert_almost(c.tzoom, 1.3, 1e-9, "zoom in stops at the limit")
	c.tzoom = 0.62
	c.wheel(-100, 0.25, 1.2)
	assert_almost(c.tzoom, 0.62 * 1.1, 1e-9)
	c.wheel(100, 0.25, 1.2)
	assert_almost(c.tzoom, 0.62 * 1.1 * 0.9, 1e-9)


func test_drag_moves_target_and_camera() -> void:
	var c = Camera.new(100, 50, 0.5)
	c.drag(10, -20)
	assert_almost(c.tx, 80.0)
	assert_almost(c.ty, 90.0)
	assert_almost(c.x, 80.0)
	assert_almost(c.y, 90.0)


func test_drag_events() -> void:
	var host := Node2D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	var c = Camera.new(0, 0, 1.0)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = Vector2(100, 100)
	assert_true(c.drag_input(press, host), "right press starts a drag")
	var mv := InputEventMouseMotion.new()
	mv.position = Vector2(130, 90)
	c.drag_motion(mv, host)
	assert_almost(c.x, -30.0)
	assert_almost(c.y, 10.0)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_RIGHT
	rel.pressed = false
	c.drag_motion(rel, host)
	assert_false(c.dragging, "release ends the drag")
	var left := InputEventMouseButton.new()
	left.button_index = MOUSE_BUTTON_LEFT
	left.pressed = true
	assert_false(c.drag_input(left, host), "left press does not drag")
	host.free()


func test_picking_through_canvas_transform() -> void:
	# A view placed under a scaled, offset parent (as in a stretched or
	# letterboxed host): event positions map back to the view's own pixels.
	var parent := Node2D.new()
	parent.position = Vector2(40, 25)
	parent.scale = Vector2(0.8, 0.8)
	var view := Node2D.new()
	parent.add_child(view)
	(Engine.get_main_loop() as SceneTree).root.add_child(parent)
	var local := Vector2(500, 300)
	var event_pos: Vector2 = view.get_global_transform_with_canvas() * local
	var back: Vector2 = Camera.view_local(view, event_pos)
	assert_almost(back.x, local.x, 1e-3)
	assert_almost(back.y, local.y, 1e-3)
	var c = Camera.new(200, 300, 0.75)
	var w: Vector2 = c.to_world(back, Vector2(1920, 1080))
	assert_almost(w.x, (500 - 960) / 0.75 + 200, 1e-3)
	assert_almost(w.y, (300 - 540) / 0.75 + 300, 1e-3)
	parent.free()


func test_pan_keys_speed() -> void:
	var c = Camera.new(0, 0, 0.5)
	Input.action_press("cam_right")
	Input.action_press("cam_up")
	c.pan_keys(0.1, 600.0)
	Input.action_release("cam_right")
	Input.action_release("cam_up")
	assert_almost(c.tx, 120.0, 1e-9, "600 * dt / zoom")
	assert_almost(c.ty, -120.0, 1e-9)
