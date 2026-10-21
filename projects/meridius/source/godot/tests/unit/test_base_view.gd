## Garrison view (src/render/baseScene.ts) against the original's scene data
## (tests/fixtures/render/base_new.json): ground, palisade, forest and decor
## layout, walkers, camera framing, picking, hover/dim rules and the click signal.
extends "res://tests/test_case.gd"

const BaseView = preload("res://scripts/render/base_view.gd")
const Terrain = preload("res://scripts/render/terrain.gd")
const Iso = preload("res://scripts/render/iso.gd")
const DB = preload("res://scripts/data/db.gd")

var fx: Dictionary
var up: Dictionary


func before_all() -> void:
	fx = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/render/base_new.json"))
	up = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/render/base_upgraded.json"))


func _view(game: Dictionary) -> Node2D:
	var v: Node2D = load("res://scenes/base/base_view.tscn").instantiate()
	v.setup(func() -> Variant: return game)
	(Engine.get_main_loop() as SceneTree).root.add_child(v)
	v._w = 1920.0
	v._h = 1080.0
	return v


func test_layout_matches_original() -> void:
	var l := BaseView.layout()
	assert_eq(l.stakes, fx.stakes, "palisade stakes")
	assert_eq(l.props.size(), fx.props.size(), "props count")
	assert_eq(l.props, fx.props, "forest and decor props (Rng order)")


func test_terrain_matches_original_layer() -> void:
	var layer: Node2D = Terrain.build_terrain(BaseView.terrain_input())
	assert_eq(layer.ox, int(fx.layer.ox))
	assert_eq(layer.oy, int(fx.layer.oy))
	assert_eq(layer.width, int(fx.layer.w))
	assert_eq(layer.height, int(fx.layer.h))
	layer.free()


func test_walkers_spawn_like_original() -> void:
	var v := _view(fx.game)
	assert_eq(v.walkers.size(), fx.walkers.size())
	for i in v.walkers.size():
		assert_eq(v.walkers[i].type, fx.walkers[i].type)
		assert_eq(v.walkers[i].variant, fx.walkers[i].variant)
	v.free()


func test_camera_framing() -> void:
	var v := _view(fx.game)
	v._frame(fx.game, 1920, 1080)
	assert_almost(v.cam.x, fx.cam.x, 1e-6, "home x")
	assert_almost(v.cam.y, fx.cam.y, 1e-6, "home y")
	assert_almost(v.cam.zoom, fx.cam.zoom, 1e-9, "home zoom")
	# A short viewport raises the camera / zooms out until the camp fits.
	v._frame(fx.game, 1920, 400)
	assert_true(v.cam.ty < fx.cam.y or v.cam.tzoom < fx.cam.zoom, "short viewport reframes")
	v._frame(up.game, 1920, 1080)
	assert_almost(v.cam.ty, up.cam.y, 1e-6, "upgraded camp framing y")
	assert_almost(v.cam.tzoom, up.cam.zoom, 1e-9, "upgraded camp framing zoom")
	v.free()


func _screen_of(v: Node2D, wx: float, wy: float) -> Vector2:
	return v.cam.world_to_screen(wx, wy, 1920, 1080)


func test_picking_buildings() -> void:
	var v := _view(fx.game)
	v._frame(fx.game, 1920, 1080)
	for b in DB.BUILDINGS:
		# A point on the building's body, 60 px above its anchor.
		var p := _screen_of(v, Iso.iso_x(b.pos[0], b.pos[1]), Iso.iso_y(b.pos[0], b.pos[1]) - 40)
		assert_eq(v.building_at(p.x, p.y), b.id, "pick %s" % b.id)
	# Far outside the camp: nothing.
	var far := _screen_of(v, Iso.iso_x(-6, -6), Iso.iso_y(-6, -6))
	assert_eq(v.building_at(far.x, far.y), null)
	# Under zoom the same world point still picks the same building.
	v.cam.zoom = 1.2
	for b in DB.BUILDINGS:
		var p := _screen_of(v, Iso.iso_x(b.pos[0], b.pos[1]), Iso.iso_y(b.pos[0], b.pos[1]) - 40)
		assert_eq(v.building_at(p.x, p.y), b.id, "pick %s at zoom 1.2" % b.id)
	v.free()


func test_nameplate_pick_wins() -> void:
	var v := _view(fx.game)
	v.plates["command"] = {"x": -10000.0, "y": -10000.0, "w": 20000.0, "h": 20000.0}
	assert_eq(v.building_at(5, 5), "command", "nameplates are hit-tested first")
	v.free()


func test_hover_click_and_dim() -> void:
	var v := _view(fx.game)
	v._frame(fx.game, 1920, 1080)
	var clicked: Array = []
	var changes := [0]
	v.building_clicked.connect(func(id: String) -> void: clicked.append(id))
	v.changed.connect(func() -> void: changes[0] += 1)
	var b: Dictionary = DB.building_by_id("barracks")
	var p := _screen_of(v, Iso.iso_x(b.pos[0], b.pos[1]), Iso.iso_y(b.pos[0], b.pos[1]) - 40)
	v.pointer_move(p.x, p.y)
	assert_eq(v.ui.get("hover"), "barracks")
	assert_eq(changes[0], 1, "hover change notifies")
	v.pointer_down(p.x, p.y, MOUSE_BUTTON_LEFT)
	assert_eq(clicked, ["barracks"])
	v.pointer_down(p.x, p.y, MOUSE_BUTTON_RIGHT)
	assert_eq(clicked.size(), 1, "right click does not open")
	v.dim = true
	v.pointer_move(p.x, p.y)
	assert_false(v.ui.has("hover"), "no hover behind a panel")
	v.pointer_down(p.x, p.y, MOUSE_BUTTON_LEFT)
	assert_eq(clicked.size(), 1, "no clicks behind a panel")
	v.free()


func test_wheel_zoom_limits() -> void:
	var v := _view(fx.game)
	for i in 30:
		v.wheel(1)
	assert_almost(v.cam.tzoom, 0.4, 1e-9)
	for i in 30:
		v.wheel(-1)
	assert_almost(v.cam.tzoom, 1.3, 1e-9)
	v.free()


func test_update_moves_walkers() -> void:
	var v := _view(fx.game)
	var x0: float = v.walkers[0].x
	for i in 300:
		v.update(1.0 / 60.0)
	var moved := false
	for w in v.walkers:
		if absf(w.x - x0) > 0.01 or w.wait > 0:
			moved = true
	assert_true(moved)
	assert_true(v.fx.particles.size() > 0, "campfire smoke")
	v.free()
