## Native input, appearance and save-isolation review. Does not write a save.
## tools/godot.sh --path . --resolution 1920x1080 --audio-driver Dummy
##   -s res://tests/visual/unit_playground_review.gd
extends SceneTree

const OUT := "res://tests/visual/out/playground/"
const Lab = preload("res://scripts/render/unit_playground.gd")
var errors: Array = []
var checks: Array = []
var main
var screen
var _pointer_inside := false

class Catcher extends Logger:
	var errors: Array
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			errors.append("%s (%s:%d)" % [rationale if rationale != "" else code, file, line])


func _initialize() -> void:
	var catcher := Catcher.new()
	catcher.errors = errors
	OS.add_logger(catcher)
	root.mouse_entered.connect(func(): _pointer_inside = true)
	root.mouse_exited.connect(func(): _pointer_inside = false)
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(value: bool, label: String) -> void:
	checks.append(("PASS " if value else "FAIL ") + label)
	if not value:
		errors.append(label)


func _click(control: Control) -> void:
	await _click_at(control.get_global_rect().get_center())


func _click_at(at: Vector2) -> void:
	at = root.get_final_transform() * at
	if not _pointer_inside:
		root.notify_mouse_entered()
		_pointer_inside = true
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	Input.parse_input_event(move)
	await _frames(3)
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = at
		click.global_position = at
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		click.pressed = down
		Input.parse_input_event(click)
		await _frames(3)


func _key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + name + ".png"))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app = root.get_node("App")
	var save_before := FileAccess.get_sha256(app.save_path) if FileAccess.file_exists(app.save_path) else "absent"
	var game_before := var_to_str(app.game)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 600:
		await process_frame
		if app.screen == "title":
			break
	_check(app.screen == "title", "boot to title")
	# Run the renderer-dependent regression cases with the actual GL backend.
	var test = load("res://tests/unit/test_unit_playground.gd").new()
	for method in test.get_method_list():
		if String(method.name).begins_with("test_"):
			test._failures.clear()
			test.before_each()
			test.call(method.name)
			test.after_each()
			_check(test._failures.is_empty(), method.name)
			for failure in test._failures:
				errors.append(failure)
	await _frames(4)
	await _shot("title")
	await _click(main.find_child("UnitPlayground", true, false))
	await _frames(12)
	_check(app.screen == "playground", "title button opens playground")
	screen = main._screen
	var view = screen.view
	await _shot("field")
	await _click(screen.pause_button)
	var t: float = view.time
	await _frames(8)
	_check(view.time == t, "pause freezes animation")
	await _click(screen.find_child("StepFrame", true, false))
	_check(is_equal_approx(view.time - t, 1.0 / 60.0), "frame step advances exactly 1/60 second")
	await _click(screen.find_child("ClipAttack", true, false))
	_check(view.clip == "Attack" and view.b.unit(Lab.SUBJECT).x == Lab.HOME.x, "UI click selects clip without field movement")
	await _click(screen.pause_button)
	await _frames(150)
	_check(view.views[Lab.TARGET].alive == 1, "dummy survives repeated attacks")
	_check(Vector2i(view.views[Lab.SUBJECT].x, view.views[Lab.SUBJECT].y) == Vector2i(8, 10), "melee unit approaches dummy")
	await _click(screen.find_child("Closeup", true, false))
	await _shot("attack_close")
	await _click(screen.find_child("ClipIdle", true, false))
	await _key(KEY_Q)
	_check(view.facing == 0, "Q turns unit")
	await _key(KEY_E)
	_check(view.facing == 1, "E turns unit")
	await _click(screen.find_child("Battlezoom", true, false))
	var field_at: Vector2 = screen.field.global_position
	var dest := Vector2i(6, 8)
	var p: Vector2 = view.cam.to_screen(view.Iso.iso(dest.x, dest.y), screen.field.size)
	await _click_at(field_at + p)
	await _frames(90)
	_check(Vector2i(view.views[Lab.SUBJECT].x, view.views[Lab.SUBJECT].y) == dest, "field click walks to chosen tile")
	var dummy: Vector2 = view.cam.to_screen(view.Iso.iso(8, 11) + Vector2(0, -30), screen.field.size)
	await _click_at(field_at + dummy)
	_check(view.clip == "Attack", "clicking dummy queues approach and attack")
	await _frames(150)
	await _key(KEY_SPACE)
	_check(not view.playing, "Space pauses after world interaction")
	# PopupMenu choices use their native id_pressed signal; the OS-owned popup
	# does not receive Input.parse_input_event's root-window keyboard events.
	screen.unit_picker.select(1)
	screen.unit_picker.item_selected.emit(1)
	_check(view.unit_type == screen.unit_picker.get_item_metadata(1), "unit dropdown chooses displayed model")
	await _click(screen.find_child("Grid", true, false))
	_check(view.ui.showGrid, "grid toggle")
	await _click(screen.find_child("Night", true, false))
	_check(view.atmo.night, "night toggle")
	await _shot("night")
	await _click(screen.find_child("Grid", true, false))
	await _click(screen.find_child("Night", true, false))
	_check(not view.ui.showGrid and not view.atmo.night, "grid and night switch off while paused")
	screen.comparison_picker.select(1)
	screen.comparison_picker.item_selected.emit(1)
	view.frame_subject(2.0)
	await _shot("comparison")
	_check(view.views.has(Lab.COMPARISON), "comparison displayed beside independent dummy")
	screen.comparison_picker.select(0)
	screen.comparison_picker.item_selected.emit(0)
	# Every asset is drawn natively, including crews and specialist models.
	for i in screen.unit_picker.item_count:
		screen.unit_picker.select(i)
		screen.unit_picker.item_selected.emit(i)
		view.choose_clip("Idle")
		view.frame_subject(2.4)
		screen._refresh_info()
		await _frames(3)
		for facing in 4:
			view.set_facing(facing)
			view.tick(0.0, true)
			await _frames(2)
		await _shot("model_" + view.unit_type)
	view.choose_unit("footman")
	screen.unit_picker.select(0)
	view.choose_clip("Attack")
	view.playing = true
	view.looping = true
	view.frame_subject(2.4)
	screen._refresh_info()
	screen.set_process(false)
	# Fixed-time native frames for a short motion review, with the same renderer.
	for i in 120:
		view.tick(1.0 / 30.0)
		screen.status.text = "Attack dummy · %.2fs · 1× playback" % view.elapsed
		await _shot("motion_%04d" % i)
	screen.set_process(true)
	await _key(KEY_ESCAPE)
	_check(app.screen == "title", "Esc returns to title")
	await _frames(5)
	await _click(main.find_child("UnitPlayground", true, false))
	await _frames(5)
	screen = main._screen
	_check(screen.view.views.size() == 2, "reopening creates a clean field")
	root.size = Vector2i(1280, 720)
	await _frames(10)
	await _shot("desktop_1280")
	await _click(screen.find_child("BackToTitle", true, false))
	_check(app.screen == "title", "Back button returns to title")
	var save_after := FileAccess.get_sha256(app.save_path) if FileAccess.file_exists(app.save_path) else "absent"
	_check(save_before == save_after and game_before == var_to_str(app.game), "save bytes and company state unchanged")
	await _frames(5)
	var report := "\n".join(checks) + "\nErrors: %d\n" % errors.size() + "\n".join(errors)
	FileAccess.open(OUT + "review.txt", FileAccess.WRITE).store_string(report)
	print(report)
	quit(0 if errors.is_empty() else 1)
