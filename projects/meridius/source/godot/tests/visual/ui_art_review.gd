## Native review of the Nordmark interface; reuses the real UI capture scenarios.
## tools/godot.sh --path . --resolution 1920x1080 -s res://tests/visual/ui_art_review.gd
## Isolated save, muted audio bus, restored preferences. No physical input.
extends "res://tests/visual/ui_capture.gd"

const REVIEW_OUT := "res://tests/visual/out/ui-art-review"
const REVIEW_SHOTS := ["title", "base", "welcome", "barracks", "roster", "soldier", "memorial2",
	"command", "training", "armoury", "infirmary2", "quartermaster", "manual", "prep", "report",
	"menu", "hover", "tooltip", "tip", "confirm", "campaign", "battle", "battle_live"]

class ReviewErrors extends Logger:
	var errors: Array = []
	var mutex := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		mutex.lock()
		errors.append("%s:%d %s" % [file, line, rationale if rationale != "" else code])
		mutex.unlock()

var review_errors := ReviewErrors.new()
var review_log: Array = []


func _run() -> void:
	OS.add_logger(review_errors)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REVIEW_OUT))
	app = root.get_node("App")
	app.save_path = "user://ui_art_review_save.json"
	var Prefs = load("res://scripts/core/prefs.gd")
	var previous: Dictionary = Prefs.prefs().duplicate(true)
	Prefs.set_pref("manualSeen", true)
	AudioServer.set_bus_mute(0, true)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(10)
	for shot in REVIEW_SHOTS:
		app.game = load("res://scripts/meta/game.gd").new_game(1234)
		app.save()
		await _prepare("battle" if shot == "battle_live" else shot)
		if shot == "battle_live":
			app.battle_view.begin()
			await create_timer(2.0).timeout
		await _review_shot(shot)
	# Desktop aspect checks: the game uses a 1920 x 1080 minimum logical canvas.
	for resolution in [Vector2i(1440, 900), Vector2i(2560, 1080)]:
		DisplayServer.window_set_size(resolution)
		await _frames(8)
		for shot in ["title", "roster", "prep", "battle_live"]:
			app.game = load("res://scripts/meta/game.gd").new_game(1234)
			await _prepare("battle" if shot == "battle_live" else shot)
			if shot == "battle_live":
				app.battle_view.begin()
				await create_timer(2.0).timeout
			await _review_shot("%s-%dx%d" % [shot, resolution.x, resolution.y])
	Prefs.set_prefs(previous)
	for error in review_errors.errors:
		review_log.append("ERROR " + str(error))
	review_log.append("Captured %d scenarios; %d rendering/runtime errors." % [REVIEW_SHOTS.size() + 8, review_errors.errors.size()])
	var f := FileAccess.open(REVIEW_OUT + "/review.txt", FileAccess.WRITE)
	f.store_string("\n".join(review_log) + "\n")
	f.close()
	print(review_log[-1])
	quit(0 if review_errors.errors.is_empty() else 1)


func _review_shot(shot: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(REVIEW_OUT + "/" + shot + ".png")
	var line := "%s: native framebuffer %dx%d; logical viewport %s" % [shot, img.get_width(), img.get_height(), root.get_visible_rect().size]
	review_log.append(line)
	print(line)
