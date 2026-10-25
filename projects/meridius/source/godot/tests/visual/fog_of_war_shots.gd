extends SceneTree
const OUT := "res://tests/visual/out/fog_of_war/"
var screen
var errors: Array = []
var checks: Array = []
var frame := 0
class Catcher extends Logger:
	var sink: Array
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			sink.append("%s (%s:%d)" % [rationale if rationale != "" else code, file, line])
func _initialize() -> void:
	OS.low_processor_usage_mode = false
	Engine.max_fps = 60
	# Ignore physical mouse movement over the capture window: hover previews
	# would otherwise alter canopy fades and spoil the art comparison.
	root.gui_disable_input = true
	var catcher := Catcher.new()
	catcher.sink = errors
	OS.add_logger(catcher)
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks.append(("PASS " if ok else "FAIL ") + label)
	if not ok: errors.append(label)
func frames(count: int, record := false) -> void:
	paused = false
	for i in count:
		screen.view.step_frame(1.0 / 60.0)
		await process_frame
		await RenderingServer.frame_post_draw
		if record and i % 6 == 0:
			root.get_texture().get_image().save_png(OUT + "frames/%04d.png" % frame)
			frame += 1
func shot(name: String) -> void:
	print("Capturing ", name)
	await frames(3)
	root.get_texture().get_image().save_png(OUT + name + ".png")
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "frames"))
	var tests = load("res://tests/unit/test_fog_of_war.gd").new()
	for method in tests.get_method_list():
		if String(method.name).begins_with("test_"):
			tests._failures.clear()
			tests.call(method.name)
			check(tests._failures.is_empty(), method.name)
			errors.append_array(tests._failures)
	screen = load("res://scripts/ui/screens/terrain_lab.gd").new()
	screen.field_index = 3
	screen.theme = load("res://scripts/ui/theme_builder.gd").theme()
	root.add_child(screen)
	await process_frame
	await process_frame
	screen.view.auto_step = false
	await frames(30)
	var v = screen.view
	check(not v.unit_visible(v.b.unit("woodland-sentry")), "sentry concealed at start")
	await shot("scouting_start")
	v.b.setup.fogOfWar = false
	v.fog.refresh(1.0, true)
	await shot("scouting_fog_off")
	v.b.setup.fogOfWar = true
	v.fog.refresh(1.0, true)
	v.frame_field(true)
	await frames(30, true)
	for dest in [Vector2i(5, 8), Vector2i(6, 7)]:
		check(v.move_patrol("terrain-0", dest.x, dest.y), "real patrol route to %s" % dest)
		await frames(90, true)
		await shot("scouting_%d_%d" % [dest.x, dest.y])
	check(v.unit_visible(v.b.unit("woodland-sentry")), "sentry revealed on approach")
	var faded := false
	for prop in v._draw._prop_list():
		if prop != null and prop.get("fade", 1.0) < 0.65:
			faded = true
	check(faded, "canopy fades around visible squads")
	await shot("scouting_revealed")
	# Compare the same layout and camera with the painted kit and the old art.
	var map_before := JSON.stringify(v.b.map)
	var units_before := JSON.stringify(v.b.units)
	var painted_count := 0
	var ferns := 0
	for prop in v._draw._prop_list():
		if prop != null and prop.s.get("woodland", false):
			painted_count += 1
			if prop.s.key == "woodland_fern": ferns += 1
	check(painted_count > 25 and ferns > 15, "painted trees, shrubs and ground ferns share the production sorted pass")
	var kit = load("res://scripts/render/woodland_kit.gd")
	var assets = load("res://scripts/render/assets.gd")
	var masks_ok := true
	for kind in kit.SOURCES:
		var s: Dictionary = kit.sprite(kind)
		masks_ok = masks_ok and not assets.opaque_at(s, 4, 4)
		masks_ok = masks_ok and assets.opaque_at(s, s.w * 0.5, s.h * 0.65)
	check(masks_ok, "painted foliage alpha masks remove the backdrop and retain interiors")
	v.b.setup.fogOfWar = false
	v.fog.refresh(1.0, true)
	v.frame_field(true)
	await frames(30)
	await shot("woodland_painted_close")
	screen.woodland_button.button_pressed = false
	await frames(30)
	check(not v.painted_woodland, "painted woodland toggle reaches the native renderer")
	await shot("woodland_original_close")
	screen.woodland_button.button_pressed = true
	await frames(30)
	check(JSON.stringify(v.b.map) == map_before and JSON.stringify(v.b.units) == units_before, "art toggle leaves all terrain and unit rules unchanged")
	v.frame_field()
	await shot("woodland_painted_overview")
	v.atmo.night = true
	await frames(30)
	await shot("woodland_painted_night")
	v.atmo.night = false
	v.b.setup.fogOfWar = true
	v.fog.refresh(1.0, true)
	v.frame_field(true)
	v.atmo.night = true
	screen.night_button.set_pressed_no_signal(true)
	await frames(60)
	await shot("scouting_night")
	v.atmo.night = false
	screen.night_button.set_pressed_no_signal(false)
	for dest in [Vector2i(5, 8), Vector2i(5, 9), Vector2i(5, 10)]:
		check(v.move_patrol("terrain-0", dest.x, dest.y), "return route to %s" % dest)
		await frames(100, true)
	check(not v.unit_visible(v.b.unit("woodland-sentry")), "sentry hidden after withdrawal")
	check(v.fog.tile_state(7, 6) == 1, "explored ground remains in shroud")
	v.frame_field()
	await frames(30, true)
	await shot("scouting_explored")
	# Classic tile heights cache a different ground source. It must survive a
	# later art toggle, otherwise redrawing the exterior blanks the ground.
	screen.smooth_terrain = false
	screen._load_field()
	screen.view.auto_step = false
	await frames(30)
	v = screen.view
	check(is_instance_valid(v.terrain._field_vp), "classic ground retained for woodland comparison redraw")
	var classic_map := JSON.stringify(v.b.map)
	screen.woodland_button.button_pressed = false
	await frames(15)
	screen.woodland_button.button_pressed = true
	await frames(15)
	check(JSON.stringify(v.b.map) == classic_map, "classic woodland toggle preserves terrain rules")
	v.b.setup.fogOfWar = false
	v.fog.refresh(1.0, true)
	await shot("woodland_classic")
	# Exercise native normal-battle layers including HUD, minimap and night lights.
	screen.queue_free()
	await process_frame
	var setup = tests.fixture()
	setup.map.scale = "large"
	setup.units[1].x = 10
	var battle = load("res://scripts/rules/battle.gd").new(setup)
	battle.phase = "player"
	var view = load("res://scripts/render/battle_view.gd").new()
	view.threaded_rules = false
	view.setup(battle)
	view.auto_step = false
	view.set_process_input(false)
	view.set_process_unhandled_input(false)
	root.add_child(view)
	var hud = load("res://scripts/ui/battle_hud.gd").new()
	hud.theme = load("res://scripts/ui/theme_builder.gd").theme()
	root.add_child(hud)
	hud.setup(view)
	view.atmo.night = true
	view.night_level = 1.0
	for i in 60:
		view.step_frame(1.0 / 60.0)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "battle_night_hud.png")
	check(hud.enemy_counts().x == 1, "visible enemy counted in native HUD")
	view.views.sentry.x = 20
	battle.unit("sentry").x = 20
	view.fog.refresh(1.0)
	check(hud.enemy_counts().x == 0, "hidden enemy excluded from HUD count")
	view._play({"t": "log", "text": "hidden enemy secret", "witnesses": ["sentry"]})
	check(not view.ui.log.any(func(e): return e.text == "hidden enemy secret"), "hidden enemy log suppressed")
	view._redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "battle_hidden_hud.png")
	hud.queue_free()
	view.queue_free()
	await process_frame
	await process_frame
	var file := FileAccess.open(OUT + "result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"errors": errors, "checks": checks, "frames": frame, "fps": 10, "renderer": RenderingServer.get_current_rendering_method()}, "\t"))
	print("Fog native capture: ", errors.size(), " errors; ", checks.size(), " checks")
	for e in errors: print(e)
	quit(0 if errors.is_empty() else 1)
