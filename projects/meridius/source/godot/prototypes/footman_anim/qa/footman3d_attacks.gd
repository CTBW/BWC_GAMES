## Drive the 3D footman's attacks in the sandbox: the slash and now and then the
## stab, in place and walking up, and counters (a blow taken, then struck back),
## with close filmstrips of a stab and of a counter behind the shield. Prints each
## blow: which attack, from how far, hit or missed.
##   tools/godot.sh --path . --resolution 1600x900 --audio-driver Dummy --fixed-fps 30 \
##     --write-movie tests/visual/out/footman3d/attacks.avi -s res://prototypes/footman_anim/qa/footman3d_attacks.gd
## Writes tests/visual/out/footman3d/attacks_strip_<name>.png
extends SceneTree

var sb: Node3D
var fm: Node3D
var out := ""


func _initialize() -> void:
	_run.call_deferred()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _until(cond: Callable, limit: float) -> void:
	var t := 0.0
	while not cond.call() and t < limit:
		await process_frame
		t += 1.0 / 30.0


func _place(dist: float, from_deg: float) -> void:
	var d := Vector3(sin(deg_to_rad(from_deg)), 0, cos(deg_to_rad(from_deg)))
	fm.position = sb.dummy.position + d * dist
	fm.rotation.y = fm.yaw_of(-d)
	fm.path.clear()
	fm.state = "idle"
	fm._play("idle", 0.0, true)


func _blow(label: String) -> void:
	fm.last_impact = ""
	await _until(func(): return fm.last_impact != "", 6.0)
	print("BLOW %s: %s (%s)" % [label, fm.last_impact, fm.player.current_animation])
	await _until(func(): return fm.state in ["idle", "block"], 4.0)
	await _wait(0.4)


## Every `step` frames from now until he is back at rest, cropped around him.
func _strip(label: String, start: Callable, step: int, box: int, per_row: int) -> void:
	start.call()
	var frames := []
	var n := 0
	while n < 150 and not (fm.state in ["idle", "block"] and n > 20):
		await process_frame
		if n % step == 0:
			var img: Image = root.get_texture().get_image()
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
	sheet.save_png(out + "/attacks_strip_" + label + ".png")
	print("STRIP ", label, " frames ", frames.size())


func _run() -> void:
	out = ProjectSettings.globalize_path("res://tests/visual/out/footman3d")
	DirAccess.make_dir_recursive_absolute(out)
	sb = load("res://prototypes/footman_anim/scenes/footman3d_sandbox.tscn").instantiate()
	root.add_child(sb)
	if sb.footman == null:
		return  # his export is not on disk: the lab has quit
	sb.set_process_unhandled_input(false)
	fm = sb.footman
	fm._rng.seed = 20261024
	print("ATTACKS slash stands %.2f m off (tip %.2f m), stab %.2f m off (tip %.2f m); stab share %.2f" % [
		fm.strike_dist("attack"), fm.meta.clips.attack.tip_reach_m, fm.strike_dist("attack_stab"), fm.meta.clips.attack_stab.tip_reach_m, fm._share("attack_stab")])
	sb._set_zoom(2.4)
	sb.follow = true
	# In place at the slash's distance: the stab only when it reaches.
	_place(fm.strike_dist("attack"), 30.0)
	await _wait(1.0)
	for i in 8:
		fm.attack(sb.dummy)
		await _blow("in place %d" % (i + 1))
	# Walking up from about two tiles: he stops where the attack he picked reaches.
	for i in 4:
		_place(5.0, -40.0 + 30.0 * i)
		await _wait(0.6)
		fm.attack_target(sb.dummy)
		await _until(func(): return fm.state == "attack", 10.0)
		var to: Vector3 = sb.dummy.position - fm.position
		print("WALKUP %d: %s from %.2f m (stands for it at %.2f)" % [i + 1, fm._attack.clip, Vector2(to.x, to.z).length(), fm.strike_dist(fm._attack.clip)])
		await _blow("walk up %d" % (i + 1))
	# Counters: the blow taken (on the shield when it is up), then struck back.
	_place(fm.strike_dist("attack"), 0.0)
	await _wait(0.8)
	for i in 3:
		fm.counter(sb.dummy)
		await _until(func(): return fm.state == "attack", 3.0)
		await _blow("counter %d" % (i + 1))
	fm.set_block(true)
	await _wait(0.8)
	for i in 2:
		fm.counter(sb.dummy)
		await _until(func(): return fm.state == "attack", 3.0)
		await _blow("counter behind the shield %d" % (i + 1))
	fm.set_block(false)
	await _wait(0.6)
	# Close strips.
	sb._set_zoom(3.0)
	_place(fm.strike_dist("attack_stab"), 25.0)
	await _wait(1.2)
	await _strip("stab", func(): fm.attack(sb.dummy, "attack_stab"), 2, 360, 12)
	_place(fm.strike_dist("attack"), 25.0)
	fm.set_block(true)
	await _wait(1.2)
	fm._rng.seed = 3  # a stab for this one's answer
	await _strip("counter_block", func(): fm.counter(sb.dummy), 2, 360, 12)
	fm.set_block(false)
	print("ATTACKS_DONE")
	quit()
