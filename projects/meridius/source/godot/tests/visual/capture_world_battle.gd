## Windowed capture of battle grounds at 1920x1080 with the world renderer
## only (the battle view itself belongs to the battle-view agent): the
## terrain layer, the outer forest baked into it with TerrainLayer.bake()
## exactly as battleScene.bakeOuter does, the grid props drawn plainly (no
## units, no fading), the battle water shimmer, cloud shadows and the grade,
## at the camera the original opened the battle with
## (tests/fixtures/render/battle_maps.json). Night fights use the flat night
## tint (the battle view draws its own torch-lit mask over it).
##
##   tools/godot.sh --path . --resolution 1920x1080 -s res://tests/visual/capture_world_battle.gd -- [names]
##
## Writes tests/visual/out/world_battle_<name>.png and prints frame times.
extends SceneTree

const Iso = preload("res://scripts/render/iso.gd")
const Rng = preload("res://scripts/core/rng.gd")
const JS = preload("res://scripts/core/js.gd")
const DB = preload("res://scripts/data/db.gd")
const Camera = preload("res://scripts/render/camera.gd")
const Terrain = preload("res://scripts/render/terrain.gd")
const Atmosphere = preload("res://scripts/render/atmosphere.gd")
const Assets = preload("res://scripts/render/assets.gd")
const WorldCanvas = preload("res://scripts/render/world_canvas.gd")
const OUT := "res://tests/visual/out/"


func _initialize() -> void:
	_run()


func _wait(secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		await process_frame


func _sprite_key(prop: String) -> String:
	var p: Dictionary = DB.PROPS.get(prop, {})
	return p.get("sprite", prop)


## battleScene.bakeOuter through the TerrainLayer bake API.
func _bake_outer(layer: Node2D, m: Dictionary) -> void:
	var outer: Array = JS.sort(m.outer.duplicate(), func(a, b): return (a.x + a.y) - (b.x + b.y))
	layer.bake(func(ci: CanvasItem) -> void:
		for o in outer:
			var s := Assets.sprite(_sprite_key(o.prop), int(o.v))
			var px: float = Iso.iso_x(o.x, o.y) + (Rng.hash2(o.x, o.y, 5) - 0.5) * 40
			var py: float = Iso.iso_y(o.x, o.y, o.h) + (Rng.hash2(o.x, o.y, 6) - 0.5) * 20
			var flip: bool = not s.get("noShadow", false) and Rng.hash2(o.x, o.y, 9) > 0.5
			var sc: float = 0.9 + Rng.hash2(o.x, o.y, 3) * 0.35
			Assets.draw_cast_shadow(ci, s, px, py, flip, sc, 0.2 if str(o.prop).begins_with("tree") else 0.16)
			Assets.draw_sprite(ci, s, px, py, flip, sc))


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var maps: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/render/battle_maps.json"))
	var names: PackedStringArray = OS.get_cmdline_user_args()
	if names.is_empty():
		names = PackedStringArray(maps.keys())
	for name in names:
		var f: Dictionary = maps[name]
		var m: Dictionary = f.map
		var root2 := Node2D.new()
		root.add_child(root2)
		var bg := WorldCanvas.new(func(ci: CanvasItem) -> void: ci.draw_rect(Rect2(0, 0, 1920, 1080), Color8(0x1b, 0x28, 0x12)), "Bg")
		root2.add_child(bg)
		var world := Node2D.new()
		root2.add_child(world)
		var cam = Camera.new(f.cam.x, f.cam.y, f.cam.zoom)
		world.transform = cam.transform(Vector2(1920, 1080))
		var t0 := Time.get_ticks_usec()
		var layer: Node2D = Terrain.build_terrain(f.terrainInput)
		_bake_outer(layer, m)
		world.add_child(layer)
		var water: Node2D = layer.make_water_node("battle")
		water.cam = cam
		world.add_child(water)
		var atmo = Atmosphere.new(m.seed)
		atmo.night = f.night
		world.add_child(atmo.make_clouds_node(Iso.iso_x(m.w / 2.0, m.h / 2.0), Iso.iso_y(m.w / 2.0, m.h / 2.0)))
		var props: Array = []
		for t in m.tiles:
			if t.get("prop", "") != "":
				props.append(t)
		props = JS.sort(props, func(a, b): return (a.x + a.y) - (b.x + b.y))
		var props_node := WorldCanvas.new(func(ci: CanvasItem) -> void:
			for t in props:
				var s := Assets.sprite(_sprite_key(t.prop), int(t.get("v", 0)))
				var px := Iso.iso_x(t.x, t.y)
				var py := Iso.iso_y(t.x, t.y, t.h)
				var flip: bool = not s.get("noShadow", false) and Rng.hash2(t.x, t.y, 9) > 0.5
				Assets.draw_cast_shadow(ci, s, px, py, flip, 1.0, 0.2 if str(t.prop).begins_with("tree") else 0.16)
				Assets.draw_sprite(ci, s, px, py, flip, 1.0), "Props")
		world.add_child(props_node)
		root2.add_child(atmo.make_grade_node())
		await layer.built
		var ready_ms := (Time.get_ticks_usec() - t0) / 1000.0
		var time := 0.0
		var tw := Time.get_ticks_msec()
		var frames := 0
		while Time.get_ticks_msec() - tw < 1800:
			await process_frame
			time += 1.0 / 60.0
			frames += 1
			atmo.update(1.0 / 60.0, 1920, 1080)
			water.time = time
			atmo.redraw(Vector2(1920, 1080), time)
		var ms := 1800.0 / frames
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(OUT + "world_battle_%s.png" % name))
		print("%s: ground ready after %.0f ms (cpu %.0f ms), %.2f ms/frame" % [name, ready_ms, layer.build_ms, ms])
		root2.queue_free()
		await process_frame
	quit(0)
