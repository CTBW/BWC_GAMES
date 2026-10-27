## Production woodland camp: painting-space input, camera bounds, presentation
## isolation, authored walker routes and current building names. Original iso
## geometry remains covered separately by test_base_view.gd.
extends "res://tests/test_case.gd"

const Camp = preload("res://scripts/render/woodland_camp.gd")
const DB = preload("res://scripts/data/db.gd")
const Wildlife = preload("res://scripts/render/camp_wildlife.gd")


func test_wildlife_is_bounded_and_clears_between_flocks_and_at_night() -> void:
	var peak := 0
	var quiet := 0
	# Ten minutes, including many re-entries into the repeating flight schedule.
	for tick in 2400:
		var elapsed := float(tick) * .25
		var birds := Wildlife.sample(elapsed, 0.0)
		peak = maxi(peak, birds.size())
		if birds.is_empty():
			quiet += 1
		assert_true(birds.size() <= 5, "bounded ambient flock")
		assert_true(Wildlife.sample(elapsed, 1.0).is_empty(), "songbirds settle at night")
		for bird in birds:
			assert_true(bird.p.is_finite(), "flight position is finite")
			assert_true(bird.alpha >= 0.0 and bird.alpha <= 1.0, "flight fades stay bounded")
	assert_true(peak >= 3, "daytime flocks actually launch")
	assert_true(quiet > 1500, "quiet intervals dominate the scene")
	assert_eq(Wildlife.sample(7.0, 0.0), Wildlife.sample(7.0, 0.0), "capture clock reproduces the same flock")


func _game() -> Dictionary:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/render/base_new.json"))
	return fixture.game.duplicate(true)


func _view(game: Dictionary) -> Node2D:
	var view: Node2D = load("res://scenes/base/base_view.tscn").instantiate()
	view.setup(func() -> Variant: return game)
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	view.set_process(false)
	view._w = 1920.0
	view._h = 1080.0
	view._frame(game, view._w, view._h)
	view.frame_camp()
	for i in 100:
		view.update(0.05)
	return view


func _screen(view: Node2D, point: Vector2) -> Vector2:
	return view.cam.world_to_screen(point.x, point.y, view._w, view._h)


func test_production_scene_uses_woodland_camp() -> void:
	var view := _view(_game())
	assert_eq(view.get_script(), Camp, "production scene uses the remodel")
	assert_eq(Camp.ART_SIZE, Vector2(2752, 1536), "source aspect is preserved")
	assert_eq(Camp.ZONES.size(), DB.BUILDINGS.size(), "all existing facilities have a painted zone")
	for building in DB.BUILDINGS:
		assert_true(Camp.ZONES.has(building.id), "zone for %s" % building.id)
		assert_true(Camp.ANCHORS.has(building.id), "anchor for %s" % building.id)
	view.free()


func test_painted_zone_picking_survives_zoom_and_pan() -> void:
	var view := _view(_game())
	var home_zoom: float = view.cam.zoom
	for state in [Vector3(1376, 768, home_zoom), Vector3(1490, 690, home_zoom * 1.4)]:
		view.cam.x = state.x
		view.cam.y = state.y
		view.cam.zoom = state.z
		for building in DB.BUILDINGS:
			var wp: Vector2 = view.building_world_position(building.id)
			assert_true(Geometry2D.is_point_in_polygon(wp / Camp.ART_SIZE, PackedVector2Array(Camp.ZONES[building.id])), "anchor lies inside %s" % building.id)
			var p := _screen(view, wp)
			assert_eq(view.building_at(p.x, p.y), building.id, "painting-space pick for %s" % building.id)
		for uv in [Vector2(.08, .20), Vector2(.90, .15), Vector2(.90, .85), Vector2(.10, .82)]:
			var p := _screen(view, uv * Camp.ART_SIZE)
			assert_eq(view.building_at(p.x, p.y), null, "forest has no facility hit")
	view.free()


func test_hover_click_and_modal_exclusion() -> void:
	var view := _view(_game())
	var clicked: Array = []
	var changes := [0]
	view.building_clicked.connect(func(id: String): clicked.append(id))
	view.changed.connect(func(): changes[0] += 1)
	for building in DB.BUILDINGS:
		var p := _screen(view, view.building_world_position(building.id))
		view.pointer_move(p.x, p.y)
		assert_eq(view.ui.get("hover"), building.id, "hover %s" % building.id)
		view.pointer_down(p.x, p.y, MOUSE_BUTTON_LEFT)
		assert_eq(clicked[-1], building.id, "click %s" % building.id)
	assert_eq(clicked.size(), 6)
	assert_eq(changes[0], 6, "only changed hovers notify")
	var p := _screen(view, view.building_world_position("command"))
	view.pointer_down(p.x, p.y, MOUSE_BUTTON_RIGHT)
	assert_eq(clicked.size(), 6, "right button cannot open a facility")
	view.dim = true
	view.pointer_move(p.x, p.y)
	view.pointer_down(p.x, p.y, MOUSE_BUTTON_LEFT)
	assert_eq(view.ui.get("hover"), null, "modal removes world hover")
	assert_eq(clicked.size(), 6, "modal blocks world clicks")
	view.free()


func _assert_covered(view: Node2D, label: String) -> void:
	var top_left: Vector2 = view.cam.screen_to_world(0, 0, view._w, view._h)
	var bottom_right: Vector2 = view.cam.screen_to_world(view._w, view._h, view._w, view._h)
	assert_true(top_left.x >= -0.1 and top_left.y >= -0.1, label + ": no blank top/left")
	assert_true(bottom_right.x <= Camp.ART_SIZE.x + 0.1 and bottom_right.y <= Camp.ART_SIZE.y + 0.1, label + ": no blank bottom/right")


func test_desktop_framing_and_camera_clamp_cover_the_canvas() -> void:
	var game := _game()
	var view := _view(game)
	for size in [Vector2(1920, 1080), Vector2(2560, 1440), Vector2(2560, 1080), Vector2(1920, 1200)]:
		view._w = size.x
		view._h = size.y
		view._frame(game, size.x, size.y)
		view.frame_camp()
		for i in 100:
			view.update(.05)
		var cover := maxf(size.x / Camp.ART_SIZE.x, size.y / Camp.ART_SIZE.y)
		_assert_covered(view, "%s home" % size)
		for i in 80:
			view.wheel(1)
		assert_almost(view.cam.tzoom, cover, .0001, "zoom-out stops at cover")
		for i in 80:
			view.wheel(-1)
		assert_almost(view.cam.tzoom, cover * 1.65, .0001, "zoom-in is bounded")
		for corner in [Vector2(-50000, -50000), Vector2(50000, 50000)]:
			view.cam.x = corner.x
			view.cam.y = corner.y
			view.cam.tx = corner.x
			view.cam.ty = corner.y
			for i in 100:
				view.update(.05)
			_assert_covered(view, "%s clamp %s" % [size, corner])
	view.free()


func test_night_changes_presentation_without_changing_campaign() -> void:
	var game := _game()
	var before := game.duplicate(true)
	var view := _view(game)
	view.set_night(true)
	for i in 200:
		view.update(.05)
	assert_true(view.night_target, "night target")
	assert_almost(view.night_blend, 1.0, .001, "night blend reaches its destination")
	for building in DB.BUILDINGS:
		var p := _screen(view, view.building_world_position(building.id))
		assert_eq(view.building_at(p.x, p.y), building.id, "night keeps the same target")
	view.set_night(false)
	for i in 200:
		view.update(.05)
	assert_false(view.night_target)
	assert_almost(view.night_blend, 0.0, .001)
	assert_eq(game, before, "lighting and walkers do not mutate campaign state")
	view.free()


func test_authored_routes_do_not_cross_painted_roofs() -> void:
	assert_true(Camp.ROUTES.size() > 0, "authored routes exist")
	for route_i in Camp.ROUTES.size():
		var route: Array = Camp.ROUTES[route_i]
		assert_true(route.size() >= 2, "route needs two points")
		for segment in range(route.size() - 1):
			var a: Vector2 = route[segment]
			var b: Vector2 = route[segment + 1]
			var samples := maxi(2, ceili(((b - a) * Camp.ART_SIZE).length() / 4.0))
			for sample in range(samples + 1):
				var p := a.lerp(b, float(sample) / samples)
				for id in Camp.ZONES:
					if id == "training":
						continue # This facility is open ground.
					assert_false(Geometry2D.is_point_in_polygon(p, PackedVector2Array(Camp.ZONES[id])), "route %d segment %d avoids %s" % [route_i, segment, id])


func test_walkers_remain_on_their_authored_route() -> void:
	var view := _view(_game())
	assert_true(view.walkers.size() > 0, "new company has camp walkers")
	var initial: Vector2 = view.walkers[0].p
	var moved := false
	for frame in 600:
		view.update(.05)
		for walker in view.walkers:
			var route: Array = Camp.ROUTES[walker.route]
			var distance := INF
			for segment in range(route.size() - 1):
				var a: Vector2 = route[segment] * Camp.ART_SIZE
				var b: Vector2 = route[segment + 1] * Camp.ART_SIZE
				distance = minf(distance, walker.p.distance_to(Geometry2D.get_closest_point_to_segment(walker.p, a, b)))
			assert_true(distance < .15, "walker remains on authored ground")
		if view.walkers[0].p.distance_to(initial) > 1.0:
			moved = true
	assert_true(moved, "walkers animate")
	view.free()


func test_upgraded_labels_follow_database_without_moving_facilities() -> void:
	var game := _game()
	var view := _view(game)
	var positions := {}
	for building in DB.BUILDINGS:
		positions[building.id] = view.building_world_position(building.id)
	for level in range(1, 4):
		for building in DB.BUILDINGS:
			game.buildings[building.id] = level
			assert_eq(view.building_label(building.id), building.levels[level - 1].name, "current DB name for %s level %d" % [building.id, level])
			assert_eq(view.building_world_position(building.id), positions[building.id], "upgrades keep painted anchor")
	view.free()
