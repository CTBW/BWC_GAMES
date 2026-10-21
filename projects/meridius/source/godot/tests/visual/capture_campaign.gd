## Windowed capture of the campaign map at 1920x1080 for comparison with the
## original (tests/visual/out/ref/campaign_intro.png at 0.8 s, campaign_start.png
## at 6.4 s, world only, from tools/parity/render_fixtures_browser.ts).
##
##   tools/godot.sh --path . --resolution 1920x1080 -s res://tests/visual/capture_campaign.gd
##
## Writes tests/visual/out/campaign_intro.png, campaign_start.png,
## campaign_hover.png, campaign_march.png, campaign_after.png and prints frame times.
extends SceneTree

const OUT := "res://tests/visual/out/"


func _initialize() -> void:
	_run()


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + name))
	print("saved ", name)


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
	var fx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/render/campaign_start.json"))
	var game: Dictionary = fx.game
	var ex: Dictionary = game.expedition
	var view: Node2D = load("res://scenes/campaign/campaign_view.tscn").instantiate()
	var t0 := Time.get_ticks_usec()
	view.setup(ex, func() -> Variant: return game.get("expedition"))
	root.add_child(view)
	await process_frame
	print("campaign setup %.0f ms (terrain cpu %.0f ms)" % [(Time.get_ticks_usec() - t0) / 1000.0, view.terrain.build_ms])
	await _wait(0.8)
	await _shot("campaign_intro.png")
	await _wait(5.6)
	await _shot("campaign_start.png")
	await _measure("campaign view", 300)
	# Hover the first reachable node.
	var n: Dictionary = view.next_nodes(ex)[0]
	var sp: Vector2 = view.cam.to_screen(Vector2(view.Iso.iso_x(n.tx, n.ty), view.Iso.iso_y(n.tx, n.ty) - 30), Vector2(1920, 1080))
	view.pointer_move(sp.x, sp.y)
	print("hover: ", view.ui.get("hover"))
	await _shot("campaign_hover.png")
	# March to it (the rules would do this; here the state is edited directly).
	ex.current = n.id
	ex.path.append(n.id)
	ex.marches = 1
	n.visited = true
	await _wait(0.9)
	await _shot("campaign_march.png")
	await _wait(2.0)
	await _shot("campaign_after.png")
	quit(0)
