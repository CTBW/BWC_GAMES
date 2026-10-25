## Native captures of the relief ground (terrain_relief.gdshader) in the
## terrain test fields: each art field whole, then close views of the bluff's
## banks and the meadow at play zoom. No company state is created or saved.
##   tools/godot.sh --path . --resolution 1920x1080 --audio-driver Dummy -s res://tests/visual/terrain_relief_shots.gd
## Output: tests/visual/out/terrain_relief/*.png and result.json.
extends SceneTree

const SCREEN_PATH := "res://scripts/ui/screens/terrain_lab.gd"
const ThemeBuilder = preload("res://scripts/ui/theme_builder.gd")
const OUT := "res://tests/visual/out/terrain_relief/"
const FIELDS := [0, 1, 2, 4]
var screen
var errors: Array = []

class Catcher extends Logger:
	var sink: Array
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			sink.append("%s (%s:%d)" % [rationale if rationale != "" else code, file, line])


func _initialize() -> void:
	var catcher := Catcher.new()
	catcher.sink = errors
	OS.add_logger(catcher)
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	screen = load(SCREEN_PATH).new()
	screen.theme = ThemeBuilder.theme()
	root.add_child(screen)
	await process_frame
	await process_frame
	var only := OS.get_environment("RELIEF_FIELDS")
	var build_ms := {}
	for which in FIELDS:
		if only != "" and not only.split(",").has(str(which)):
			continue
		await _load(which)
		build_ms[which] = screen.view.terrain.build_ms
		await _shot("field_%d_day" % which)
		match which:
			0:
				screen.view.terrain.show_height_contours(true)
				await _shot("meadow_heights")
				screen.view.terrain.show_height_contours(false)
				_look(9.0, 9.5, 1.45)
				await _shot("meadow_close")
			2:
				_look(12.0, 11.0, 1.2)
				await _shot("ridge_close")
			4:
				_look(13.0, 11.0, 1.2)
				await _shot("bluff_banks")
				_look(15.0, 7.5, 1.45)
				await _shot("bluff_east_close")
				_look(7.0, 9.0, 1.0)
				await _shot("bluff_ramp")
				screen.view.atmo.night = true
				screen.night_button.set_pressed_no_signal(true)
				_look(11.5, 11.5, 0.8)
				await _shot("bluff_night")
				screen.view.atmo.night = false
				screen.night_button.set_pressed_no_signal(false)
	var f := FileAccess.open(OUT + "result.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"errors": errors, "build_ms": build_ms, "renderer": RenderingServer.get_current_rendering_method()}, "\t"))
	print("Relief capture: ", errors.size(), " errors")
	for e in errors.slice(0, 12):
		print(e)
	quit(0 if errors.is_empty() else 1)


func _load(which: int) -> void:
	screen.field_index = which
	screen._load_field()
	screen.view.auto_step = false
	await _settle()


## The camera on grid point (x, y) at `zoom` (as the lab's frame_field does).
func _look(x: float, y: float, zoom: float) -> void:
	var v = screen.view
	var p: Vector2 = v.Iso.iso(x, y, v._tile_h(x, y))
	v.cam.x = p.x
	v.cam.tx = p.x
	v.cam.y = p.y - 35
	v.cam.ty = v.cam.y
	v.cam.zoom = zoom
	v.cam.tzoom = zoom
	v._apply_camera()


func _settle() -> void:
	for i in 5:
		screen.view.step_frame(0.0)
		await process_frame
		RenderingServer.force_draw(false)


func _shot(label: String) -> void:
	await _settle()
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + label + ".png"))
	print("Captured ", label)
