## The 3D footman at rest: his standing idle (`idle`), the guard idle played once
## from it (`idle_guard`, idle's variant, its wait shortened here), and his way
## back to the stand after a march, a slash and a blow. Filmstrips of each, and
## per frame the largest move of any bone (cm, in his own space): a pop at a
## hand-over shows as a spike over the frames around it.
##   tools/godot.sh --path . --resolution 1600x900 --audio-driver Dummy --fixed-fps 30 \
##     -s res://prototypes/footman_anim/qa/footman3d_idle.gd [-- zoom=4 box=360 facing=SW]
## Writes tests/visual/out/footman3d/idle_strip_<name>.png
extends SceneTree

var sb: Node3D
var fm: Node3D
var out := ""
var _prev := []
var _log := []
## A cut made by this script (a clip started with no blend): not a hand-over.
var _cut := false
var args := {"zoom": "4", "box": "360", "facing": "SW"}


func _initialize() -> void:
	_run.call_deferred()


## The largest move of any bone since last frame, in his own space: [cm, bone].
func _jump() -> Array:
	var sk: Skeleton3D = fm.skeleton
	var now := []
	var most := 0.0
	var who := ""
	for i in sk.get_bone_count():
		now.append(sk.get_bone_global_pose(i).origin)
		if _prev.size() == sk.get_bone_count() and (now[i] - _prev[i]).length() > most:
			most = (now[i] - _prev[i]).length()
			who = sk.get_bone_name(i).trim_prefix("mixamorig_").trim_prefix("mixamorig:")
	_prev = now
	return [100.0 * most, who]


func _frame() -> void:
	await process_frame
	var j := _jump()
	_log.append([fm.state, String(fm.player.current_animation), j[0], _cut, j[1], fm.player.current_animation_position])
	_cut = false


## Frames until `cond`, at most `limit` seconds.
func _until(cond: Callable, limit: float) -> void:
	var n := 0
	while not cond.call() and n < int(limit * 30.0):
		await _frame()
		n += 1


## Every `step` frames for `frames` frames (or until `stop`), cropped around him.
func _strip(label: String, start: Callable, frames: int, step: int, per_row: int = 10, stop: Callable = Callable()) -> void:
	var box := int(args.box)
	start.call()
	var shots := []
	for n in frames:
		await _frame()
		if n % step == 0:
			var img: Image = root.get_texture().get_image()
			var k := Vector2(img.get_size()) / sb.get_viewport().get_visible_rect().size
			var c: Vector2 = sb.cam.unproject_position(fm.position + Vector3(0, 0.9, 0)) * k
			var r := Rect2i(int(c.x) - box / 2, int(c.y) - box / 2, box, box)
			shots.append(img.get_region(r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))))
		if stop.is_valid() and stop.call():
			break
	var rows := ceili(shots.size() / float(per_row))
	var sheet := Image.create(box * per_row, box * rows, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var f: Image = shots[i]
		f.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(f, Rect2i(Vector2i.ZERO, f.get_size()), Vector2i((i % per_row) * box, (i / per_row) * box))
	sheet.save_png(out + "/idle_strip_" + label + ".png")
	print("STRIP ", label, " frames ", shots.size())


## The hand-overs in the log: where the clip changes, the largest bone move over
## the three frames on each side against the largest over the clip around it.
func _report() -> void:
	var worst := 0.0
	for i in range(1, _log.size()):
		if _log[i][1] == _log[i - 1][1] or _log[i][3]:
			continue
		var near := 0.0
		var who := ""
		for j in range(maxi(1, i - 3), mini(_log.size(), i + 4)):
			if _log[j][2] > near:
				near = _log[j][2]
				who = _log[j][4]
		var around := 0.0
		for j in range(maxi(1, i - 30), mini(_log.size(), i + 31)):
			if absi(j - i) > 3 and not _log[j][3]:
				around = maxf(around, _log[j][2])
		print("HANDOVER %s -> %s (%s): %.2f cm a frame at it (%s), %.2f cm around it" % [_log[i - 1][1], _log[i][1], _log[i][0], near, who, around])
		var row := []
		for j in range(maxi(1, i - 4), mini(_log.size(), i + 5)):
			row.append("%s%.1f %s @%.3f" % ["| " if j == i else "", _log[j][2], _log[j][4], _log[j][5]])
		print("  ", ", ".join(row))
		if _log[i][1] == "idle" or _log[i - 1][1] == "idle":
			worst = maxf(worst, near - around)
	print("IDLE_HANDOVERS worst spike over the motion around it: %.2f cm" % worst)


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	out = ProjectSettings.globalize_path("res://tests/visual/out/footman3d")
	DirAccess.make_dir_recursive_absolute(out)
	sb = load("res://prototypes/footman_anim/scenes/footman3d_sandbox.tscn").instantiate()
	root.add_child(sb)
	if sb.footman == null:
		return  # his export is not on disk: the lab has quit
	sb.set_process_unhandled_input(false)
	sb.ui.visible = false
	sb.sprite.visible = false
	fm = sb.footman
	fm._rng.seed = 20261025
	fm.meta.variants.idle.every_s = [1.5, 1.5]
	fm._variant_in = 1.5
	sb.zoom = float(args.zoom)
	sb._zoom_goal = float(args.zoom)
	sb._apply_look()
	fm.rotation.y = fm.yaw_of(sb.FACINGS[args.facing])
	var g: Animation = fm.player.get_animation("idle_guard")
	var s: Animation = fm.player.get_animation("idle")
	print("IDLES stand %.2f s (loop %d), guard %.2f s (loop %d), wait %s" % [s.length, s.loop_mode, g.length, g.loop_mode, str(fm.meta.variants.idle.every_s)])
	for i in 6:
		await _frame()
	# At rest: the stand, the guard idle once as the stand comes round, back to the stand.
	await _strip("rest_guard", func(): pass, 30 * 14, 10, 12, func(): return false)
	# The hand-overs themselves, frame by frame: into the guard idle (from the
	# stand's last frames, the wait run out) and back.
	fm._play("idle", 0.0, true)
	_cut = true
	var cur := func(): return String(fm.player.current_animation)
	await _until(func(): return fm._variant_in <= 0.0 and cur.call() == "idle" and fm.player.current_animation_position > fm.player.current_animation_length - 0.2, 8.0)
	await _strip("into_guard", func(): pass, 16, 1, 8)
	await _until(func(): return cur.call() == "idle_guard" and fm.player.current_animation_position > fm.player.current_animation_length - 0.2, 9.0)
	await _strip("out_of_guard", func(): pass, 20, 1, 10)
	# A march and stop, a slash and a blow, each back to the stand.
	fm.meta.variants.idle.every_s = [60.0, 60.0]
	var to: Vector3 = fm.position + fm.forward() * sb.tile_m * 2.0
	fm.order_move([to])
	await _until(func(): return fm.state == "stop", 12.0)
	print("MARCH stop at %.2f m from the target" % Vector2(to.x - fm.position.x, to.z - fm.position.z).length())
	await _strip("stop_to_stand", func(): pass, 30 * 4, 2, 12, func(): return fm.state == "idle" and fm.player.current_animation_position > 1.0)
	print("MARCH at rest %.2f m from the target" % Vector2(to.x - fm.position.x, to.z - fm.position.z).length())
	fm.position = sb.dummy.position - sb.FACINGS.SW.normalized() * fm.strike_dist("attack")
	fm.rotation.y = fm.yaw_of(sb.dummy.position - fm.position)
	fm.state = "idle"
	fm._play("idle", 0.0, true)
	_cut = true
	for i in 10:
		await _frame()
	await _strip("slash_to_stand", func(): fm.attack(sb.dummy, "attack"), 30 * 5, 3, 12, func(): return fm.state == "idle" and fm.player.current_animation_position > 1.0)
	await _strip("hit_to_stand", func(): fm.hit(), 30 * 4, 3, 12, func(): return fm.state == "idle" and fm.player.current_animation_position > 1.0)
	_report()
	quit()
