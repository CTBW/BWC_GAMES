## Native rendering and UI smoke test. No company state is created or saved.
extends SceneTree

const SCREEN_PATH := "res://scripts/ui/screens/terrain_lab.gd"
const ThemeBuilder = preload("res://scripts/ui/theme_builder.gd")
const OUT := "res://tests/visual/out/terrain_lab/"
var screen
var errors: Array = []
var checks: Array = []
var pointer_inside := false

class Catcher extends Logger:
	var sink: Array
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			sink.append("%s (%s:%d)" % [rationale if rationale != "" else code, file, line])


func _initialize() -> void:
	var catcher := Catcher.new()
	catcher.sink = errors
	OS.add_logger(catcher)
	root.mouse_entered.connect(func(): pointer_inside = true)
	root.mouse_exited.connect(func(): pointer_inside = false)
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var test = load("res://tests/unit/test_terrain_lab.gd").new()
	for method in test.get_method_list():
		if String(method.name).begins_with("test_"):
			test._failures.clear()
			test.call(method.name)
			_check(test._failures.is_empty(), method.name)
			errors.append_array(test._failures)
	screen = load(SCREEN_PATH).new()
	screen.theme = ThemeBuilder.theme()
	root.add_child(screen)
	await process_frame
	await process_frame
	for which in 3:
		screen.field_index = which
		screen._load_field()
		screen.view.auto_step = false
		await _settle()
		await _shot("field_%d_day" % which)
		screen.view.atmo.night = true
		screen.night_button.set_pressed_no_signal(true)
		await _settle()
		await _shot("field_%d_night" % which)
		screen.view.atmo.night = false
		screen.night_button.set_pressed_no_signal(false)
		if which == 0:
			screen.view.frame_field(true)
			await _shot("meadow_close")
			var moved: bool = screen.view.move_patrol("terrain-0", 6, 11)
			if not moved:
				errors.append("Patrol route to meadow crest was rejected")
			for i in 75:
				screen.view.step_frame(1.0 / 60.0)
			await _shot("meadow_march")
		if which == 1:
			screen.view.ui.showGrid = true
			screen.grid_button.set_pressed_no_signal(true)
			await _shot("ford_grid")
		if which == 2:
			screen.view.terrain.show_height_contours(true)
			screen.contour_button.set_pressed_no_signal(true)
			await _shot("ridge_heights")
	screen.smooth_terrain = false
	screen.field_index = 0
	screen._load_field()
	screen.view.auto_step = false
	await _settle()
	await _shot("meadow_classic")
	await _verify_entry_and_input()
	var f := FileAccess.open(OUT + "result.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"errors": errors, "checks": checks, "renderer": RenderingServer.get_current_rendering_method(), "fields": 3}, "\t"))
	print("Terrain lab native capture: ", errors.size(), " errors")
	for e in errors.slice(0, 12):
		print(e)
	quit(0 if errors.is_empty() else 1)


func _check(ok: bool, label: String) -> void:
	checks.append(("PASS " if ok else "FAIL ") + label)
	if not ok:
		errors.append(label)


func _click_at(at: Vector2) -> void:
	if not pointer_inside:
		root.notify_mouse_entered()
		pointer_inside = true
	at = root.get_final_transform() * at
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	await process_frame
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = at
		click.global_position = at
		click.button_index = MOUSE_BUTTON_LEFT
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		click.pressed = pressed
		Input.parse_input_event(click)
		await process_frame


func _verify_entry_and_input() -> void:
	screen.queue_free()
	await process_frame
	var app = root.get_node("App")
	var before := FileAccess.get_sha256(app.save_path) if FileAccess.file_exists(app.save_path) else "absent"
	var game_before := var_to_str(app.game)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 600:
		await process_frame
		if app.screen == "title":
			break
	_check(app.screen == "title", "boot to title")
	var button = main.find_child("TerrainTestFields", true, false)
	_check(button != null, "terrain button on title")
	if button == null:
		return
	await _click_at(button.get_global_rect().get_center())
	for i in 15:
		await process_frame
	_check(app.screen == "terrain_lab", "title click opens terrain lab")
	if app.screen != "terrain_lab":
		return
	screen = main._screen
	screen.view.auto_step = false
	var dest := Vector2i(6, 13)
	var point: Vector2 = screen.view.Iso.iso(dest.x, dest.y, screen.view._tile_h(dest.x, dest.y))
	var at: Vector2 = screen.view.cam.to_screen(point, screen.field.size) + screen.field.global_position
	await _click_at(at)
	for i in 240:
		screen.view.advance(1.0 / 60.0)
	var u: Dictionary = screen.view.b.unit("terrain-0")
	_check(Vector2i(u.x, u.y) == dest, "native field click moves patrol")
	await _click_at(screen.night_button.get_global_rect().get_center())
	_check(screen.view.atmo.night, "native night toggle")
	await _click_at(screen.contour_button.get_global_rect().get_center())
	await _settle()
	_check(screen.contours, "native height toggle")
	# Reload while height mode is active: cached layer must rebuild cleanly.
	screen.field_index = 1
	screen._load_field()
	screen.view.auto_step = false
	await _settle()
	_check(screen.view.b.map.id == "terrain_test_1", "field switching with contours active")
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.physical_keycode = KEY_ESCAPE
		key.pressed = pressed
		Input.parse_input_event(key)
		await process_frame
	_check(app.screen == "title", "Escape returns to title")
	var after := FileAccess.get_sha256(app.save_path) if FileAccess.file_exists(app.save_path) else "absent"
	_check(before == after and game_before == var_to_str(app.game), "company and save untouched")
	main.queue_free()
	screen = null
	for i in 5:
		await process_frame


func _settle() -> void:
	for i in 5:
		screen.view.step_frame(0.0)
		await process_frame
		RenderingServer.force_draw(false)


func _shot(label: String) -> void:
	await _settle()
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + label + ".png"))
	print("Captured ", label)
