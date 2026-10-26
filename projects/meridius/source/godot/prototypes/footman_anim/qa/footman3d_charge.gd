## Drive the 3D footman's charge in the sandbox from several distances and
## headings, saving stills and printing what was measured (time to the blow,
## where he struck from, foot slide, the largest one-frame jump at each change).
##   tools/godot.sh --path . --resolution 1600x900 --audio-driver Dummy --fixed-fps 30 \
##     --write-movie tests/visual/out/footman3d/charge.avi -s res://prototypes/footman_anim/qa/footman3d_charge.gd
## With `-- strip` only the close filmstrip of the stab (charge_strip_close_stab.png),
## with `-- lunge` only that of the lunge (charge_strip_close_lunge.png).
## Writes tests/visual/out/footman3d/charge_<name>.png
extends SceneTree

var sb: Node3D
var fm: Node3D
var out := ""
var _frame := 0
var _done := false


func _initialize() -> void:
	_run.call_deferred()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _shot(name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(out + "/charge_" + name + ".png")
	print("SHOT ", name, " state=", fm.state, " clip=", fm.player.current_animation, " t=", snappedf(fm.player.current_animation_position, 0.01))


func _until(cond: Callable, limit: float) -> void:
	var t := 0.0
	while not cond.call() and t < limit:
		await process_frame
		t += 1.0 / 30.0


## Every state change with its movie frame, and the largest one-frame jump of
## any bone (in his own space) in the three frames after it (as the tour).
func _watch() -> void:
	var last := ""
	var prev := {}
	var pending := []
	while not _done:
		await process_frame
		_frame += 1
		var sk: Skeleton3D = fm.skeleton
		var cur := {}
		var jump := 0.0
		for i in sk.get_bone_count():
			cur[i] = sk.get_bone_global_pose(i).origin
			if prev.has(i):
				jump = maxf(jump, cur[i].distance_to(prev[i]))
		prev = cur
		for e in pending:
			e.jump = maxf(e.jump, jump)
		var keep := []
		for e in pending:
			if _frame - e.f < 3:
				keep.append(e)
			else:
				print("STATE f%d %s -> %s (%s) jump %.1f cm" % [e.f, e.from, e.to, e.clip, e.jump * 100.0])
		pending = keep
		if fm.state != last:
			pending.append({"f": _frame, "from": last, "to": fm.state, "clip": fm.player.current_animation, "jump": 0.0})
			last = fm.state


## Stand him `tiles` from the dummy, toward `from_deg` (0 = straight down-left
## of it on screen), turned `turn_deg` away from facing it.
func _place(tiles: float, from_deg: float, turn_deg: float) -> void:
	var d: Vector3 = Vector3(sin(deg_to_rad(from_deg)), 0, cos(deg_to_rad(from_deg)))
	fm.position = sb.dummy.position + d * tiles * sb.tile_m
	fm.rotation.y = fm.yaw_of(-d) + deg_to_rad(turn_deg)
	fm.path.clear()
	fm.state = "idle"
	fm._play("idle", 0.0, true)
	fm.slides.clear()
	sb.focus = (fm.position + sb.dummy.position) * 0.5 + Vector3(0, 0.85, 0)


func _charge(label: String, tiles: float, from_deg: float, turn_deg: float, shots: bool) -> void:
	_place(tiles, from_deg, turn_deg)
	await _wait(0.8)
	var t0 := _frame
	var charged: bool = fm.charge(sb.dummy)
	var hits0: int = sb.dummy.hits
	if shots:
		await _wait(0.35)
		await _shot(label + "_1_setting_off")
		await _until(func(): return fm.state == "charge" and fm.speed_now > 3.5, 3.0)
		await _shot(label + "_2_running")
	await _until(func(): return fm.state == "charge_hit", 6.0)
	var t_hit := _frame
	if shots:
		await _until(func(): return fm.player.current_animation_position >= 0.3, 1.0)
		await _shot(label + "_3_braking")
	await _until(func(): return fm.last_impact != "" and fm.state in ["charge_hit", "attack", "idle"] and _frame > t_hit, 3.0)
	await _until(func(): return fm.player.current_animation_position >= float(fm.meta.clips.charge_hit.events.contact) or fm.state != "charge_hit", 2.0)
	var t_blow := _frame
	if shots:
		await _shot(label + "_4_contact")
	await _until(func(): return fm.state == "idle", 4.0)
	var to: Vector3 = sb.dummy.position - fm.position
	to.y = 0
	var s := []
	for x in fm.slides:
		s.append("%s %.1f(%s)" % [x[0].substr(0, 1), x[1] * 100.0, x[2]])
	var clip: String = fm._attack.clip
	print("CHARGE %s: from %.1f tiles, turned %d deg; charged=%s (%s); braking at %.2f s, blow at %.2f s after the order; %s; rests %.2f m from the dummy (aim %.2f); hits +%d; slides_cm=%s" % [
		label, tiles, int(turn_deg), charged, clip, (t_hit - t0) / 30.0, (t_blow - t0) / 30.0, fm.last_impact,
		to.length(), fm.strike_dist(clip), sb.dummy.hits - hits0, s])
	fm.last_impact = ""
	await _wait(0.6)


## A close filmstrip of one charge: the camera following him at 3x, every
## `step` frames from the order until he is back in his guard, each frame
## cropped `box` px square around him, in rows of `per_row`.
func _filmstrip(label: String, tiles: float, from_deg: float, turn_deg: float, step: int, box: int, per_row: int) -> void:
	_place(tiles, from_deg, turn_deg)
	sb._set_zoom(3.0)
	sb.follow = true
	await _wait(1.2)
	fm.charge(sb.dummy)
	if label.ends_with("stab"):
		fm._charge_pref = "charge_stab"
	elif label.ends_with("lunge"):
		fm._charge_pref = "charge_thrust"
	var frames := []
	var n := 0
	while n < 200 and not (fm.state == "idle" and n > 30):
		await process_frame
		if n % step == 0:
			var img: Image = root.get_texture().get_image()
			# Camera coordinates are in the viewport's base size; the image is the window's.
			var k := Vector2(img.get_size()) / sb.get_viewport().get_visible_rect().size
			var c: Vector2 = sb.cam.unproject_position(fm.position + Vector3(0, 0.9, 0)) * k
			var r := Rect2i(int(c.x) - box / 2, int(c.y) - box / 2, box, box)
			frames.append(img.get_region(r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))))
		n += 1
	var rows := ceili(frames.size() / float(per_row))
	var sheet := Image.create(box * per_row, box * rows, false, Image.FORMAT_RGBA8)
	for i in frames.size():
		var f: Image = frames[i]
		f.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(f, Rect2i(Vector2i.ZERO, f.get_size()), Vector2i((i % per_row) * box, (i / per_row) * box))
	sheet.save_png(out + "/charge_strip_" + label + ".png")
	print("STRIP ", label, " frames ", frames.size(), " every ", step)
	sb.follow = false


func _run() -> void:
	out = ProjectSettings.globalize_path("res://tests/visual/out/footman3d")
	DirAccess.make_dir_recursive_absolute(out)
	sb = load("res://prototypes/footman_anim/scenes/footman3d_sandbox.tscn").instantiate()
	root.add_child(sb)
	if sb.footman == null:
		return  # his export is not on disk: the lab has quit
	sb.set_process_unhandled_input(false)
	fm = sb.footman
	sb.follow = false
	_watch()
	print("CHARGE_CLIPS run %.2f m/s (%.2f s a tile), strike travels %.2f m, contact %.3f s after it takes over" % [
		fm.run_speed(), sb.tile_m / fm.run_speed(), fm.travel_of("charge_hit"), float(fm.meta.clips.charge_hit.events.contact)])
	fm._rng.seed = 20261024
	if "strip" in OS.get_cmdline_user_args():
		await _filmstrip("close_stab", 2.3, 20.0, 0.0, 2, 360, 10)
		_done = true
		quit()
		return
	if "lunge" in OS.get_cmdline_user_args():
		await _filmstrip("close_lunge", 2.0, 130.0, 10.0, 2, 520, 8)
		_done = true
		quit()
		return
	sb._set_zoom(1.6)
	await _wait(1.0)
	await _charge("straight", 2.3, 20.0, 0.0, true)
	await _charge("long", 3.6, -30.0, 0.0, false)
	await _charge("side", 3.0, 70.0, 90.0, true)
	await _charge("about", 4.0, 0.0, 180.0, false)
	await _charge("min", 2.0, 40.0, 10.0, false)
	await _charge("near", 1.2, 0.0, 0.0, false)
	sb._set_zoom(1.0)
	await _charge("game_zoom", 2.6, 10.0, 0.0, true)
	await _filmstrip("close", 2.3, 20.0, 0.0, 3, 420, 8)
	await _filmstrip("close_lunge", 2.0, 130.0, 10.0, 3, 520, 8)
	_done = true
	print("CHARGE_DONE frames ", _frame)
	quit()
