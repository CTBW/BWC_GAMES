## Native picture + Master-bus sound through Godot's Movie Maker.
## Run with --write-movie tests/visual/out/camp_audio/camp.avi --fixed-fps 24
## and --resolution 1920x1080. The JSON gives frame ranges for the two clips.
## Uses the production scene, real saved mix and real ambience schedules.
## Never writes player preferences or the player's campaign save.
extends SceneTree

const OUT := "res://tests/visual/out/camp_audio/"
const Prefs = preload("res://scripts/core/prefs.gd")
const FPS := 24

var report := {"fps": FPS, "clips": [], "checks": [], "failures": []}


func _initialize() -> void:
	root.size = Vector2i(1920, 1080)
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	report.checks.append(label)
	if not ok:
		report.failures.append(label)
	print("CAMP_AUDIO %s: %s" % ["PASS" if ok else "FAIL", label])


func _frames(count: int) -> void:
	for i in count:
		await RenderingServer.frame_post_draw


func _hash(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app := root.get_node("App")
	var sound := root.get_node("Sfx")
	var player_save: String = app.save_path
	var save_before := _hash(player_save)
	var prefs_before := _hash(Prefs.PATH)
	app.save_path = OUT + "review_save.json"
	_check(not Prefs.DEFAULTS.muted, "fresh game defaults to sound on")
	_check(not sound.is_muted(), "saved game starts with sound on")
	_check(not AudioServer.is_bus_mute(0), "Master output is unmuted")
	_check(sound.volume("master") > 0 and sound.volume("ambience") > 0, "Master and Ambience volumes are audible")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 240:
		await process_frame
		if app.screen == "title":
			break
	_check(app.screen == "title", "production game booted")
	sound.ambience().rng.seed = 17
	app.new_game(7)
	await _frames(2)
	var welcome_button := main.find_child("ToWork", true, false) as Button
	if welcome_button != null:
		welcome_button.pressed.emit()
	await _frames(FPS * 4)
	_check(main.find_child("WelcomeModal", true, false) == null, "welcome dismissed before recording")
	var view: Node2D = app.base_view
	_check(view != null and view.has_method("set_night"), "production woodland camp loaded")
	var state_before := var_to_str(app.game)
	for lighting in ["day", "night"]:
		if lighting == "night":
			view.set_night(true)
			await _frames(FPS * 7)
		view.time = 1.0
		view._refresh_view()
		await _frames(1)
		var count := 288 if lighting == "day" else 144
		var clip := {"lighting": lighting, "startFrame": Engine.get_frames_drawn(), "frames": count,
			"seconds": float(count) / FPS, "ambience": sound.ambience_id(),
			"beds": sound.ambience().bed_keys(), "shotsBefore": sound.ambience().shots_played}
		_check(not clip.beds.is_empty(), lighting + " has live ambience beds")
		await _frames(count)
		clip["shotsAfter"] = sound.ambience().shots_played
		report.clips.append(clip)
	_check(var_to_str(app.game) == state_before, "capture leaves campaign state unchanged")
	_check(_hash(player_save) == save_before, "player save unchanged")
	_check(_hash(Prefs.PATH) == prefs_before, "player preferences unchanged")
	report["capture"] = "Godot Movie Maker: native picture and Master-bus audio at 24 fps"
	report["viewport"] = [root.size.x, root.size.y]
	report["soundDefault"] = Prefs.DEFAULTS.muted == false
	report["savedSoundOn"] = not sound.is_muted()
	var f := FileAccess.open(OUT + "review.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	app.go_title()
	# Give the mixer frames to release active stream playback before engine exit.
	sound.ambience().beds.clear()
	sound.ambience().loops.clear()
	sound.ambience()._stop_shots()
	sound.music_deck().clear()
	for voice in sound.voices():
		sound._halt(voice)
	await _frames(8)
	quit(0 if report.failures.is_empty() else 1)
