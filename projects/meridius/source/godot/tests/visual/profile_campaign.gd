## Frame-time breakdown of the campaign view: frame time with each layer
## hidden in turn, plus CPU time of update() and the per-frame refresh.
##   tools/godot.sh --path . --resolution 1920x1080 -s res://tests/visual/profile_campaign.gd
extends SceneTree


func _initialize() -> void:
	_run()


func _frames(n: int) -> float:
	var t0 := Time.get_ticks_usec()
	var proc := 0.0
	var calls := 0.0
	var cpu := 0.0
	var gpu := 0.0
	var vp := root.get_viewport_rid()
	for i in n:
		await process_frame
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
	print("    frame %.2f ms | process %.2f ms | render cpu %.2f ms | gpu %.2f ms | draw calls %.0f" % [ms, proc / n, cpu / n, gpu / n, calls / n])
	return ms


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var fx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/render/campaign_start.json"))
	var game: Dictionary = fx.game
	var ex: Dictionary = game.expedition
	var t0 := Time.get_ticks_usec()
	var w: Dictionary = load("res://scripts/render/campaign_view.gd").world_for(ex)
	print("world_for %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	var view: Node2D = load("res://scenes/campaign/campaign_view.tscn").instantiate()
	view.setup(ex, func() -> Variant: return game.get("expedition"))
	root.add_child(view)
	print("intro (on the host): %.2f ms" % await _frames(120))
	var t2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t2 < 5500:
		await process_frame
	print("all (muster point): %.2f ms" % await _frames(200))
	var WC = load("res://scripts/render/world_canvas.gd")
	WC.profile = {}
	var tp := Time.get_ticks_usec()
	var proc_us := 0
	for i in 100:
		await process_frame
	for k in WC.profile:
		print("    draw %s: %.2f ms" % [k, WC.profile[k] / 100000.0])
	WC.profile = null
	var t1 := Time.get_ticks_usec()
	for i in 50:
		view.update(1.0 / 60.0)
	print("update(): %.2f ms" % ((Time.get_ticks_usec() - t1) / 1000.0 / 50))
	t1 = Time.get_ticks_usec()
	for i in 50:
		view._refresh_view()
	print("refresh(): %.2f ms" % ((Time.get_ticks_usec() - t1) / 1000.0 / 50))
	for k in view._nodes:
		var n: CanvasItem = view._nodes[k]
		n.visible = false
		print("without %s: %.2f ms" % [k, await _frames(200)])
		n.visible = true
	quit(0)
