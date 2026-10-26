## Drive the 3D footman sandbox through every order in a real window, saving
## stills and printing what was measured (foot slide, hits, timings).
##   tools/godot.sh --path . --resolution 1600x900 --audio-driver Dummy --fixed-fps 30 \
##     --write-movie tests/visual/out/footman3d/tour.avi -s res://prototypes/footman_anim/qa/footman3d_tour.gd
## Writes tests/visual/out/footman3d/<name>.png
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
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("SHOT ", name, " state=", fm.state, " clip=", fm.player.current_animation, " t=", snappedf(fm.player.current_animation_position, 0.01))


func _until(cond: Callable, limit: float) -> void:
	var t := 0.0
	while not cond.call() and t < limit:
		await create_timer(0.1).timeout
		t += 0.1


## Every state change with its movie frame, and the largest one-frame jump of
## any bone (in his own space) in the three frames after it: a pop in a
## cross-fade shows as a jump well above the clip's own motion.
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


## How far from the tile's centre he came to rest.
func _arrived(tile: Vector2i) -> void:
	var c: Vector3 = Vector3(tile.x, 0, tile.y) * sb.tile_m
	print("ARRIVED tile ", tile, " off centre %.1f cm" % (Vector2(fm.position.x - c.x, fm.position.z - c.z).length() * 100.0))


func _report(label: String) -> void:
	var s := []
	for x in fm.slides:
		s.append("%s %.1f(%s)" % [x[0].substr(0, 1), x[1] * 100.0, x[2]])
	print("REPORT ", label, " slides_cm=", s, " hits=", sb.dummy.hits, " last=", fm.last_impact)
	fm.slides.clear()


func _run() -> void:
	out = ProjectSettings.globalize_path("res://tests/visual/out/footman3d")
	DirAccess.make_dir_recursive_absolute(out)
	sb = load("res://prototypes/footman_anim/scenes/footman3d_sandbox.tscn").instantiate()
	root.add_child(sb)
	if sb.footman == null:
		return  # his export is not on disk: the lab has quit
	# Only the tour drives it: a real mouse over the window must not zoom or click.
	sb.set_process_unhandled_input(false)
	fm = sb.footman
	_watch()
	print("SCALE ppu=", snappedf(sb.ppu, 0.01), " tile_m=", snappedf(sb.tile_m, 0.01), " walk_speed=", snappedf(fm.walk_speed(), 0.01))
	sb._set_zoom(3.0)
	await _wait(1.5)
	await _shot("01_idle_close")
	sb._set_zoom(1.0)
	await _wait(1.0)
	await _shot("02_idle_game_zoom")
	sb._set_zoom(3.0)
	await _wait(0.6)
	# March two tiles toward SW: he sets off turning as he goes, then stops on the tile.
	sb.march_to_tile(Vector2i(0, 2))
	await _wait(0.45)
	await _shot("03_start_turning")
	await _wait(1.6)
	await _shot("04_walk_close")
	await _until(func(): return fm.state == "stop", 12.0)
	await _wait(0.9)
	await _shot("04b_stop_settling")
	await _until(func(): return fm.state == "idle", 6.0)
	_arrived(Vector2i(0, 2))
	_report("march 2 tiles (start, walk, stop)")
	await _wait(0.6)
	# At game zoom: march an L back to the start.
	sb._set_zoom(1.0)
	sb.march_to_tile(Vector2i(-1, 0))
	await _wait(2.0)
	await _shot("05_walk_game_zoom")
	await _until(func(): return fm.state == "idle", 14.0)
	_arrived(Vector2i(-1, 0))
	_report("march L at game zoom")
	# The other start: a turn clip in place first, then off.
	sb._set_step_turns(true)
	sb.march_to_tile(Vector2i(-1, 2))
	await _wait(0.4)
	await _shot("05b_turn_then_walk")
	await _until(func(): return fm.state == "idle", 14.0)
	_arrived(Vector2i(-1, 2))
	_report("march with a turn in place first")
	sb._set_step_turns(false)
	sb._set_zoom(3.0)
	await _wait(0.5)
	# Attack the dummy: walk up, face it, strike.
	sb.click(sb.cam.unproject_position(sb.dummy.position + Vector3(0, 1.0, 0)))
	await _until(func(): return fm.state == "attack", 12.0)
	await _until(func(): return fm.player.current_animation_position >= 0.4, 2.0)
	await _shot("06_attack_windup")
	await _until(func(): return fm.player.current_animation_position >= fm.meta.clips.attack.events.contact, 2.0)
	await _shot("07_attack_contact")
	await _until(func(): return fm.state == "idle", 3.0)
	_report("approach and attack")
	await _wait(0.3)
	sb._attack()
	await _until(func(): return fm.state == "idle", 3.0)
	sb._attack()
	await _until(func(): return fm.state == "idle", 3.0)
	_report("two more swings")
	# Block, take a blow while blocking, lower the shield.
	fm.set_block(true)
	await _wait(1.0)
	await _shot("08_block")
	fm.hit()
	await _wait(0.15)
	await _shot("09_hit_on_shield")
	await _until(func(): return fm.state == "block", 2.0)
	await _wait(0.8)
	fm.set_block(false)
	await _wait(0.6)
	# Step into the lane on his right, turn left, right and about.
	var lane_from := fm.position
	fm.step_lane(sb.FILE * sb.tile_m)
	await _wait(0.6)
	await _shot("10_step_lane")
	await _until(func(): return fm.state == "idle", 3.0)
	print("LANE moved %.1f cm (asked %.1f)" % [fm.position.distance_to(lane_from) * 100.0, sb.FILE * sb.tile_m * 100.0])
	_report("step lane")
	fm.face(fm.rotation.y + PI / 2)
	await _until(func(): return fm.state == "idle", 3.0)
	await _wait(0.4)
	fm.face(fm.rotation.y - PI / 2)
	await _until(func(): return fm.state == "idle", 3.0)
	await _wait(0.4)
	fm.face(fm.rotation.y + PI)
	await _wait(0.4)
	await _shot("11_turn_180_mid")
	await _until(func(): return fm.state == "idle", 3.0)
	_report("turns left, right, about")
	await _wait(0.5)
	# The game's pace: 0.26 s a tile, the walk cycle sped to the game's stride.
	sb._set_zoom(1.0)
	sb._set_pace("game")
	sb.march_to_tile(Vector2i(3, -2))
	await _wait(0.5)
	await _shot("12_game_pace")
	await _until(func(): return fm.state == "idle", 8.0)
	_report("game pace march")
	sb._set_pace("walk")
	await _wait(0.8)
	sb._set_zoom(3.0)
	await _wait(0.6)
	fm.die()
	await _wait(1.2)
	await _shot("13_death_fall")
	await _wait(3.0)
	await _shot("14_dead")
	fm.revive()
	await _wait(1.0)
	# Looks: flat (the Mixar previews) and the import's own PBR, then back.
	sb._set_look("flat")
	await _wait(0.3)
	await _shot("15_look_flat")
	sb._set_look("pbr")
	await _wait(0.3)
	await _shot("16_look_pbr")
	sb._set_look("toon")
	sb._set_zoom(1.0)
	await _wait(0.8)
	await _shot("17_game_zoom_end")
	_done = true
	print("TOUR_DONE frames ", _frame)
	quit()
