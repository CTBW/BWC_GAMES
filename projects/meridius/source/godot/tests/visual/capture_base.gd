## Windowed capture of the garrison view at 1920x1080 for comparison with the
## original (tests/visual/out/ref/base_new.png, base_upgraded.png, base_dim.png,
## world only, from tools/parity/render_fixtures_browser.ts).
##
##   tools/godot.sh --path . --resolution 1920x1080 -s res://tests/visual/capture_base.gd
##
## Writes tests/visual/out/base_new.png, base_upgraded.png, base_dim.png,
## base_hover.png and prints frame times.
extends SceneTree

const OUT := "res://tests/visual/out/"


static func load_json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _initialize() -> void:
	_run()


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + name))
	print("saved ", name, " ", img.get_size())


func _wait(secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		await process_frame


func _measure(label: String, frames: int) -> void:
	var t0 := Time.get_ticks_usec()
	for i in frames:
		await process_frame
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / frames
	print("%s: %.2f ms/frame (%.0f fps) over %d frames" % [label, ms, 1000.0 / ms, frames])


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var fresh: Dictionary = load_json("res://tests/fixtures/render/base_new.json")
	var upgraded: Dictionary = load_json("res://tests/fixtures/render/base_upgraded.json")
	var game: Dictionary = fresh.game
	var view: Node2D = load("res://scenes/base/base_view.tscn").instantiate()
	view.setup(func() -> Variant: return game)
	root.add_child(view)
	# The original's capture waits 1.8 s after the garrison opens.
	await _wait(1.8)
	await _shot("base_new.png")
	await _measure("base view", 300)
	# Hover a building (the barracks sprite).
	var b: Dictionary = {}
	for x in view.DB.BUILDINGS:
		if x.id == "barracks":
			b = x
	var sp: Vector2 = view.cam.to_screen(Vector2(view.Iso.iso_x(b.pos[0], b.pos[1]), view.Iso.iso_y(b.pos[0], b.pos[1]) - 60), Vector2(1920, 1080))
	view.pointer_move(sp.x, sp.y)
	print("hover: ", view.ui.get("hover"))
	await _shot("base_hover.png")
	# Upgraded garrison.
	game["buildings"] = upgraded.game.buildings
	await _wait(1.5)
	await _shot("base_upgraded.png")
	view.dim = true
	view.pointer_move(sp.x, sp.y)
	await _wait(0.6)
	await _shot("base_dim.png")
	quit(0)
