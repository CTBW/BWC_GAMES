## Frame rate of the battle view at 1920×1080 in the root window (vsync off),
## the way the game shows it: the last stand played live by the AI on both
## sides (enemy turns resolved on the worker thread), the full horde in view.
## Reports fps, the worst frame and the 99th percentile per phase, plus the
## rules timings, to tests/visual/out/battle_fps.txt.
##
##   tools/godot.sh --path . -s res://tests/visual/battle_fps.gd [-- turns]
extends SceneTree

const JS = preload("res://scripts/core/js.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const Ai = preload("res://scripts/rules/ai.gd")
const OUT := "res://tests/visual/out/"

var view
var lines: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_position(Vector2i.ZERO)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	Engine.max_fps = 0
	for i in 5:
		await process_frame
	var args := OS.get_cmdline_user_args()
	var turns := int(args[0]) if args.size() > 0 else 6
	var f := FileAccess.open("res://tests/fixtures/battle_view/setups/last_stand.json", FileAccess.READ)
	var setup: Dictionary = JS.normalize(JSON.parse_string(f.get_as_text())).setup
	var t0 := Time.get_ticks_usec()
	view = load("res://scenes/battle/battle_view.tscn").instantiate()
	view.setup(Battle.new(setup))
	var t1 := Time.get_ticks_usec()
	root.add_child(view)
	var t2 := Time.get_ticks_usec()
	var first: Array = []
	var last := t2
	for i in 6:
		await process_frame
		var now := Time.get_ticks_usec()
		first.append(snappedf((now - last) / 1000.0, 0.1))
		last = now
	lines.append("window %s, view %s, screen %s" % [DisplayServer.window_get_size(), view._view_size(), DisplayServer.screen_get_size()])
	lines.append("battle opens: setup %.0f ms, add_child %.0f ms, first frames %s ms" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, first])
	lines.append("opening (deployment): %s" % await _measure(func() -> bool: return false, 4.0))
	view.begin()
	await _measure(func() -> bool: return not view.busy(), 30.0)
	for t in turns:
		if view.b.phase != "player":
			break
		view.run_rules(Ai.run_player_auto)
		var rc := await _measure(func() -> bool: return not view.busy() and not view.rules_running(), 120.0)
		lines.append("turn %d company (AI on the worker %.0f ms): %s" % [t + 1, view.last_rules_ms, rc])
		if view.b.phase != "player":
			break
		view.end_turn()
		var r := await _measure(func() -> bool: return not view.busy() and not view.rules_running(), 180.0)
		lines.append("turn %d enemy (rules on the worker %.0f ms, snapshot %.1f ms): %s; %d enemy squads on the field" % [t + 1, view.last_rules_ms, view.last_snapshot_ms, r, view.b.active("enemy").size()])
	# The whole field in view (zoomed out as far as it goes), idle.
	view.cam.tzoom = view.min_zoom
	await _measure(func() -> bool: return false, 1.5)
	lines.append("whole field, zoomed out: %s" % await _measure(func() -> bool: return false, 5.0))
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + "battle_fps_field.png"))
	lines.append("danger overlay (Alt) on: %s" % await _danger())
	var out := FileAccess.open(ProjectSettings.globalize_path(OUT + "battle_fps.txt"), FileAccess.WRITE)
	out.store_string("\n".join(lines) + "\n")
	for l in lines:
		print(l)
	quit()


func _danger() -> String:
	view._danger_cache = null
	view.key_action("show_danger", true)
	var r := await _measure(func() -> bool: return false, 2.0)
	view.key_action("show_danger", false)
	return r


## Real frames until `done()` (or `max_s`): fps, worst frame, 99th percentile.
func _measure(done: Callable, max_s: float) -> String:
	var times: Array = []
	var t0 := Time.get_ticks_usec()
	var last := t0
	while (Time.get_ticks_usec() - t0) / 1e6 < max_s:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		if done.call():
			break
	var secs := (Time.get_ticks_usec() - t0) / 1e6
	var sorted := times.duplicate()
	sorted.sort()
	if sorted.is_empty():
		return "no frames"
	var p99: float = sorted[mini(sorted.size() - 1, int(sorted.size() * 0.99))]
	return "%.1f fps over %.1f s (worst %.1f ms, p99 %.1f ms)" % [times.size() / maxf(secs, 1e-6), secs, sorted[-1], p99]
