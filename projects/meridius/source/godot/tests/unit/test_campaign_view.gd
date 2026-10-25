## Campaign map view (src/render/campaignScene.ts) against the original's
## scene data (tests/fixtures/render/campaign_start.json): roads, river and
## forest props, fog lattice, the camera, picking,
## the march animation, focus and signals.
extends "res://tests/test_case.gd"

const CampaignView = preload("res://scripts/render/campaign_view.gd")
const Terrain = preload("res://scripts/render/terrain.gd")
const Iso = preload("res://scripts/render/iso.gd")

var fx: Dictionary


func before_all() -> void:
	fx = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/render/campaign_start.json"))


func _view(ex: Dictionary) -> Node2D:
	var v: Node2D = load("res://scenes/campaign/campaign_view.tscn").instantiate()
	v.setup(ex, func() -> Variant: return ex)
	(Engine.get_main_loop() as SceneTree).root.add_child(v)
	v._w = 1920.0
	v._h = 1080.0
	return v


func test_world_matches_original() -> void:
	var ex: Dictionary = fx.game.expedition
	var w := CampaignView.world_for(ex)
	assert_eq(w.roads.size(), fx.roads.size(), "roads")
	for r in fx.roads:
		assert_eq(w.roads[r[0]], r[1], "road " + r[0])
	assert_eq(w.props.size(), fx.props.size(), "props count")
	assert_eq(w.props, fx.props, "props (Rng order, sorted by depth)")
	assert_eq(w.fog.size(), fx.fog.size(), "fog puffs")
	for i in w.fog.size():
		assert_almost(w.fog[i].x, fx.fog[i].x, 1e-9)
		assert_almost(w.fog[i].y, fx.fog[i].y, 1e-9)
		assert_almost(w.fog[i].r, fx.fog[i].r, 1e-9)
	var layer: Node2D = Terrain.build_terrain(w.terrain)
	assert_eq(layer.ox, int(fx.layer.ox))
	assert_eq(layer.oy, int(fx.layer.oy))
	assert_eq(layer.width, int(fx.layer.w))
	assert_eq(layer.height, int(fx.layer.h))
	assert_eq(layer.water_tiles, fx.layer.waterTiles, "river and shallows")
	layer.free()


func test_camera_opens_on_company() -> void:
	var ex: Dictionary = fx.game.expedition
	var v := _view(ex)
	assert_almost(v.cam.x, fx.cam.x, 1e-6, "cam x")
	assert_almost(v.cam.y, fx.cam.y, 1e-6, "cam y")
	assert_almost(v.cam.zoom, fx.cam.zoom, 1e-9, "cam zoom")
	v.free()


func test_picking_and_click() -> void:
	var ex: Dictionary = fx.game.expedition
	var v := _view(ex)
	var clicked: Array = []
	v.node_clicked.connect(func(id: String) -> void: clicked.append(id))
	for zoom in [0.25, 0.6, 1.2]:
		v.cam.zoom = zoom
		for n in ex.nodes:
			var p: Vector2 = v.cam.world_to_screen(Iso.iso_x(n.tx, n.ty), Iso.iso_y(n.tx, n.ty) - 30, 1920, 1080)
			var got: Variant = v.node_at(p.x, p.y)
			assert_eq(got.id if got != null else null, n.id, "pick %s at zoom %s" % [n.id, zoom])
	v.cam.zoom = 0.6
	var n0: Dictionary = ex.nodes[1]
	var sp: Vector2 = v.cam.world_to_screen(Iso.iso_x(n0.tx, n0.ty), Iso.iso_y(n0.tx, n0.ty) - 30, 1920, 1080)
	v.pointer_move(sp.x, sp.y)
	assert_eq(v.ui.get("hover"), n0.id)
	v.pointer_down(sp.x, sp.y, MOUSE_BUTTON_LEFT)
	assert_eq(clicked, [n0.id])
	v.free()


func test_march_and_focus() -> void:
	var ex: Dictionary = fx.game.expedition.duplicate(true)
	var v := _view(ex)
	var changes := [0]
	v.changed.connect(func() -> void: changes[0] += 1)
	var target: Dictionary = CampaignView.next_nodes(ex)[0]
	ex.current = target.id
	ex.path.append(target.id)
	ex.marches = 1
	v.update(1.0 / 60.0)
	assert_true(v.marching, "a march starts when the current node changes")
	assert_true(v.ui.marching)
	var clicked: Array = []
	v.node_clicked.connect(func(id: String) -> void: clicked.append(id))
	v.pointer_down(960, 540, MOUSE_BUTTON_LEFT)
	assert_eq(clicked.size(), 0, "no clicks while marching")
	for i in 120:
		v.update(1.0 / 60.0)
	assert_false(v.marching)
	assert_almost(v.token.x, float(target.tx), 1e-9)
	assert_almost(v.token.y, float(target.ty), 1e-9)
	assert_eq(changes[0], 2, "notified at the start and the end of the march")
	v.focus_current()
	var obj: Dictionary = CampaignView._node_of_type(ex, "objective")
	assert_almost(v.cam.tx, Iso.iso_x(target.tx + (obj.tx - target.tx) * 0.18, target.ty + (obj.ty - target.ty) * 0.18), 1e-9)
	v.free()


func test_wheel_limits() -> void:
	var v := _view(fx.game.expedition)
	for i in 40:
		v.wheel(1)
	assert_almost(v.cam.tzoom, 0.25, 1e-9)
	for i in 40:
		v.wheel(-1)
	assert_almost(v.cam.tzoom, 1.2, 1e-9)
	v.free()
