## Native review of the production camp and its real UI. Reuses the established
## synthetic input/filter helpers; no facility action bypasses normal input.
## The player's save is untouched, preferences are recoverable and restored,
## and sound is muted. The parent task runs this after import/unit checks.
## tools/godot.sh --path . --resolution 1920x1080 --audio-driver Dummy
##   -s res://tests/visual/camp_remodel_review.gd
## Add -- --camp-motion for 120 night frames, played back at 24 fps.
extends "res://tests/visual/playthrough.gd"

const REVIEW_OUT := "res://tests/visual/out/camp_remodel/"
const REVIEW_SAVE := "user://camp_remodel_review_save.json"
const REVIEW_PREFS_BACKUP := "user://prefs.camp-remodel-backup.json"

var _review_prefs := {}
var _player_save_path := ""
var _player_save_hash := ""
var _input_accumulation := true
var _finishing := false
var _captures: Array = []
var _motion_frames := 0
var _atmosphere_data := {}


func _process(delta: float) -> bool:
	super._process(delta)
	if t_start > 0 and not _finishing and Time.get_ticks_msec() - t_start > 180000:
		check(false, "review watchdog: completed within three minutes")
		_finish()
	return false


func _run() -> void:
	t_start = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REVIEW_OUT))
	_hovered_api = root.has_method("gui_get_hovered_control")
	_input_accumulation = Input.use_accumulated_input
	Input.use_accumulated_input = false
	# An interrupted previous review preserves the original existence/content.
	if FileAccess.file_exists(REVIEW_PREFS_BACKUP):
		var recovered: Variant = JSON.parse_string(FileAccess.get_file_as_string(REVIEW_PREFS_BACKUP))
		if recovered is Dictionary:
			_review_prefs = recovered
	if _review_prefs.is_empty():
		_review_prefs = {"existed": FileAccess.file_exists(PREFS), "text": FileAccess.get_file_as_string(PREFS) if FileAccess.file_exists(PREFS) else ""}
		var backup := FileAccess.open(REVIEW_PREFS_BACKUP, FileAccess.WRITE)
		backup.store_string(JSON.stringify(_review_prefs))
		backup.close()
	var prefs_file := FileAccess.open(PREFS, FileAccess.WRITE)
	prefs_file.store_string(JSON.stringify({"muted": true, "battleSpeed": 1, "manualSeen": true}))
	prefs_file.close()
	var sound := root.get_node_or_null("Sfx")
	if sound != null and sound.has_method("set_muted"):
		sound.set_muted(true)
	app = root.get_node("App")
	_player_save_path = app.save_path
	_player_save_hash = _file_hash(_player_save_path)
	app.save_path = REVIEW_SAVE
	if FileAccess.file_exists(REVIEW_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REVIEW_SAVE))
	filter.name = "CampReviewInputFilter"
	filter.mark = MARK
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	root.add_child(filter)
	await frames(2)
	if not await _title():
		_finish()
		return
	var view: Node2D = app.base_view
	if not check(view.has_method("building_world_position"), "production painted camp loaded"):
		_finish()
		return
	set_phase("camp-day")
	await press("FrameCamp", "frame the complete camp")
	await settle(view.cam)
	await move_mouse(Vector2(40, 500))
	await wait(.5)
	await shot("day_1920x1080")
	if OS.get_cmdline_user_args().has("--camp-atmosphere"):
		await _record_atmosphere(view)
	var game_before := var_to_str(app.game)
	# Real mouse clicks on all six painted facilities, then their modal close.
	for building in DB.BUILDINGS:
		var id := str(building.id)
		if await click_building(id):
			check(find("BuildingPanel_" + id) != null, "painted %s opens its existing panel" % id)
			check(view.dim, "panel dims and blocks painted camp")
			if id == "armoury":
				await shot("armoury_panel")
			if id == "barracks":
				await shot("barracks")
			await key(KEY_ESCAPE)
			await until(func(): return app.panel == null, 3.0, "close " + id)
			check(not view.dim, "closing %s restores world input" % id)
		else:
			_finish()
			return
	# The service rail is a second route to exactly the same six panels.
	for building in DB.BUILDINGS:
		var id := str(building.id)
		if await press("Service_" + id, "service button " + id):
			await until(func(): return app.panel == id, 3.0, "service opens " + id)
			check(find("BuildingPanel_" + id) != null, "service panel " + id)
			await key(KEY_ESCAPE)
			await until(func(): return app.panel == null, 3.0, "service closes " + id)
	var training: Vector2 = view.building_world_position("training")
	var training_screen: Vector2 = view.cam.world_to_screen(training.x, training.y, view._w, view._h)
	await move_mouse(local_to_vp(view, training_screen))
	check(view.ui.get("hover") == "training", "yard hover follows actual painted ground")
	await shot("training_hover")
	await press("CampNight", "night lighting")
	await until(func(): return view.night_target and view.night_blend > .999, 6.0, "night transition finishes")
	await move_mouse(Vector2(40, 500))
	set_phase("camp-night")
	await shot("night_1920x1080")
	if OS.get_cmdline_user_args().has("--camp-motion"):
		await _record_motion(view)
	check(var_to_str(app.game) == game_before, "visits, lighting and camera leave campaign data unchanged")
	# Re-check a painted interaction after the full night transition.
	await click_building("command")
	await key(KEY_ESCAPE)
	await until(func(): return app.panel == null, 3.0, "night command panel closes")
	await press("CampDay", "restore daylight")
	await until(func(): return not view.night_target and view.night_blend < .001, 6.0, "day transition finishes")
	set_phase("camp-camera")
	var at: Variant = free_point()
	if at != null:
		for i in 6:
			await wheel_at(at, false)
		await settle(view.cam)
		await key_hold(KEY_D, .4)
		await settle(view.cam)
		check(view.cam.zoom > maxf(view._w / 2752.0, view._h / 1536.0) * 1.1, "mouse wheel zooms the painting")
		await shot("zoomed_camp")
	await press("FrameCamp", "return to full enclosure")
	await settle(view.cam)
	check(absf(view.cam.x - 1376.0) < 1.0 and absf(view.cam.y - 768.0) < 1.0, "Frame Camp restores the source center")
	check(absf(view.cam.zoom - maxf(view._w / 2752.0, view._h / 1536.0)) < .003, "Frame Camp restores cover zoom")
	await press("Roster", "open roster")
	await until(func(): return app.panel == "roster", 3.0, "roster opened")
	await key(KEY_ESCAPE)
	await until(func(): return app.panel == null, 3.0, "roster closed")
	await press("PlanExpedition", "plan an expedition from camp")
	await until(func(): return app.screen == "prep", 5.0, "expedition preparation opened")
	await shot("expedition_preparation")
	await press("BackToCamp", "return from expedition preparation")
	await until(func(): return app.screen == "base", 5.0, "returned to camp")
	view = app.base_view
	set_phase("camp-wide")
	root.size = Vector2i(2560, 1080)
	await frames(12)
	await press("FrameCamp", "frame wide desktop")
	await settle(view.cam)
	await move_mouse(Vector2(40, 500))
	await shot("day_2560x1080")
	check(view._w / view._h > 2.2, "wide desktop aspect exercised")
	for building in DB.BUILDINGS:
		var anchor: Vector2 = view.building_world_position(building.id)
		var p: Vector2 = view.cam.world_to_screen(anchor.x, anchor.y, view._w, view._h)
		check(on_screen(local_to_vp(view, p)), "wide desktop keeps %s accessible" % building.id)
	# One real painted click at the second aspect catches transform drift.
	await click_building("barracks")
	await key(KEY_ESCAPE)
	await until(func(): return app.panel == null, 3.0, "wide barracks closes")
	_finish()


func shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var start := Time.get_ticks_usec()
	var img := root.get_texture().get_image()
	var path := REVIEW_OUT + label + ".png"
	var result := img.save_png(ProjectSettings.globalize_path(path))
	check(result == OK, "capture " + label)
	_captures.append({"file": label + ".png", "width": img.get_width(), "height": img.get_height(), "phase": phase})
	say("shot " + label)
	_excl_us += Time.get_ticks_usec() - start


func _file_hash(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"


## Same camera and clock for OFF/ON stills, then twelve seconds of native motion.
## Real-time samples are separate from the fixed-step image encoding sequence.
func _record_atmosphere(view: Node2D) -> void:
	var before := var_to_str(app.game)
	view.set_process(false)
	view.time = 7.0
	view.atmosphere_enabled = false
	view._refresh_view()
	check(view.ambient_birds.is_empty(), "atmosphere-off clears birds immediately")
	await shot("atmosphere_off")
	view.atmosphere_enabled = true
	view._refresh_view()
	await shot("atmosphere_on")
	check(view.ambient_birds.size() >= 3, "daytime flock visible in production view")
	for flock in [1, 2]:
		view.time = 7.0 + float(flock) * 32.0
		view._refresh_view()
		await shot("bird_roost_%d" % (flock + 1))
		check(view.ambient_birds.size() >= 3, "flock lifts off from roost %d" % (flock + 1))
	view.time = 7.0
	view._refresh_view()
	_atmosphere_data = {"birdsMax": 0, "nodesBefore": view.get_child_count(), "dayFrames": 0, "nightFrames": 0}
	# Profile ordinary frame progression without reading pixels or writing files.
	view.set_process(true)
	set_phase("camp-atmosphere-realtime")
	await frames(20)
	var draw_calls := 0.0
	var process_ms := 0.0
	for i in 90:
		await process_frame
		draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_atmosphere_data["realTimeFrames"] = 90
	_atmosphere_data["meanSceneDrawCalls"] = draw_calls / 90.0
	_atmosphere_data["meanEngineProcessMs"] = process_ms / 90.0
	_atmosphere_data["performanceScope"] = "90 native frames, whole scene including UI; no readback/encoding; not isolated GPU effect timing"
	view.set_process(false)
	set_phase("camp-atmosphere-fixed-step")
	for lighting in ["day", "night"]:
		var directory: String = REVIEW_OUT + "atmosphere_" + lighting + "/"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		view.night_blend = 0.0 if lighting == "day" else 1.0
		view.set_night(lighting == "night")
		view.time = 1.0
		var count := 288 if lighting == "day" else 144
		for frame in count:
			view.time += 1.0 / 24.0
			view.update(1.0 / 24.0)
			view._refresh_view()
			_atmosphere_data.birdsMax = maxi(_atmosphere_data.birdsMax, view.ambient_birds.size())
			await RenderingServer.frame_post_draw
			var result := root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path(directory + "frame_%04d.jpg" % frame), .90)
			if result != OK:
				check(false, "atmosphere frame saved")
				break
			_atmosphere_data[lighting + "Frames"] += 1
	check(_atmosphere_data.dayFrames == 288 and _atmosphere_data.nightFrames == 144, "12 s day and 6 s night native motion captured")
	check(_atmosphere_data.birdsMax <= 5, "native flock stays bounded")
	check(view.ambient_birds.is_empty(), "night has no daytime bird flights")
	check(view.get_child_count() == _atmosphere_data.nodesBefore, "no scene nodes accumulate")
	check(var_to_str(app.game) == before, "atmosphere capture leaves campaign unchanged")
	view.set_night(false)
	view.night_blend = 0.0
	view.set_process(true)
	view._refresh_view()
	set_phase("camp-day")


## Five seconds of native scene motion at normal 24 fps playback. Fixed logical
## steps exclude JPEG encoding time, so this proves motion rather than runtime
## performance. The renderer, camera, shader and walker code are unchanged.
func _record_motion(view: Node2D) -> void:
	var directory := REVIEW_OUT + "motion/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	set_phase("camp-motion-fixed-step")
	say("recording 120 native frames at 1/24 s logical steps; normal playback at 24 fps, not a performance measurement")
	view.set_process(false)
	for frame in 120:
		view.time += 1.0 / 24.0
		view.update(1.0 / 24.0)
		view._refresh_view()
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path(directory + "frame_%04d.jpg" % frame), .88)
		if result != OK:
			check(false, "motion frame %d saved" % frame)
			break
		_motion_frames += 1
	view.set_process(true)
	check(_motion_frames == 120, "120 fixed-step native motion frames saved")
	set_phase("camp-night")


func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	Input.use_accumulated_input = _input_accumulation
	if _review_prefs.get("existed", false):
		var restored := FileAccess.open(PREFS, FileAccess.WRITE)
		restored.store_string(str(_review_prefs.get("text", "")))
		restored.close()
	elif FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	check(FileAccess.file_exists(PREFS) == bool(_review_prefs.get("existed", false)), "original preference existence restored")
	if _review_prefs.get("existed", false):
		check(FileAccess.get_file_as_string(PREFS) == str(_review_prefs.get("text", "")), "original preference bytes restored")
	if FileAccess.file_exists(REVIEW_PREFS_BACKUP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REVIEW_PREFS_BACKUP))
	if FileAccess.file_exists(REVIEW_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REVIEW_SAVE))
	check(_file_hash(_player_save_path) == _player_save_hash, "player save unchanged")
	catcher.mutex.lock()
	var runtime_errors: Array = catcher.errors.duplicate()
	var runtime_warnings: Array = catcher.warnings.duplicate()
	catcher.mutex.unlock()
	for message in runtime_errors:
		say("ERROR " + str(message))
	for message in runtime_warnings:
		say("WARNING " + str(message))
	for p in frame_ms:
		say(_stats(p, frame_ms[p]))
	say("%d checks; %d failed; %d runtime errors; physical input dropped: %d" % [steps, failures.size(), runtime_errors.size(), filter.dropped])
	var report := FileAccess.open(REVIEW_OUT + "review.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({
		"scenario": "Production woodland camp; synthetic physical-equivalent mouse and keyboard input",
		"checks": steps, "failures": failures, "runtimeErrors": runtime_errors,
		"warnings": runtime_warnings, "captures": _captures,
		"motion": {"frames": _motion_frames, "fps": 24, "directory": "motion", "type": "fixed-step native rendering at normal playback; not a performance measurement"},
		"atmosphere": _atmosphere_data,
		"sourceDay": "camp_small_woodland__take-02.png",
		"sourceNight": "camp_small_woodland_night__take-01.png",
		"physicalInputDropped": filter.dropped, "elapsedSeconds": (Time.get_ticks_msec() - t_start) / 1000.0,
	}, "\t"))
	report.close()
	var log_file := FileAccess.open(REVIEW_OUT + "review.txt", FileAccess.WRITE)
	log_file.store_string("\n".join(lines) + "\n")
	log_file.close()
	quit(0 if failures.is_empty() and runtime_errors.is_empty() else 1)
