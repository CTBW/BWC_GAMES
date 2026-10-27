## Native 3D motion blocking. New isolated preview; does not run battle logic.
## tools/godot.sh --path . -s res://tests/visual/footman_motion_study.gd -- [capture] [stills] [clip=attack]
## Interactive: 1-4 clips, Space pause, arrows frame-step, S half speed, R replay.
extends SceneTree
const Motion = preload("res://tools/motion_study/motion.gd")
const Proxy = preload("res://tools/motion_study/proxy.gd")
const OUT := "res://tests/visual/out/motion-study/"
const TITLES := {"move": "01   MOVE", "attack": "02   SWORD ATTACK", "shield_bash": "03   SHIELD BASH", "charge": "04   CHARGE"}
const NOTES := {"move": "Contact before travel. Weight over the supporting leg.", "attack": "Plant. Turn through the cut. Recover behind the shield.", "shield_bash": "Load the rear leg. Drive the shield. Absorb the contact.", "charge": "Build momentum. Shorten the final steps. Brace before contact."}
var clip := "move"
var time := 0.0
var playback_paused := false
var speed := 1.0
var capturing := false
var stage: Node3D
var actor: Node3D
var defender: Node3D
var views: Array[SubViewport] = []
var cameras: Array[Camera3D] = []
var title: Label
var note: Label
var phase_label: Label
var clock_label: Label
var contact_label: Label
var progress: ProgressBar
var contact_flash: ColorRect
var errors: Array = []

class Catcher extends Logger:
	var sink: Array
	func _log_error(fn: String, file: String, line: int, code: String, rationale: String, notify: bool, kind: int, trace: Array[ScriptBacktrace]) -> void:
		if kind != ERROR_TYPE_WARNING: sink.append("%s (%s:%d)" % [rationale if rationale != "" else code, file, line])

func _initialize() -> void:
	var logger := Catcher.new()
	logger.sink = errors
	OS.add_logger(logger)
	_run.call_deferred()

func label(text: String, pos: Vector2, size: int, color := Color("e2e7ec")) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	root.add_child(l)
	return l

func rect(pos: Vector2, size: Vector2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = size
	r.color = color
	root.add_child(r)
	return r

func _run() -> void:
	root.content_scale_size = Vector2i(1600, 900)
	root.size = Vector2i(1600, 900)
	root.title = "Meridius | Footman motion study"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("clip="): clip = arg.substr(5)
	if not Motion.CLIPS.has(clip):
		push_error("Unknown clip: " + clip)
		quit(1)
		return
	capturing = OS.get_cmdline_user_args().has("capture") or OS.get_cmdline_user_args().has("stills")
	_build()
	_update_pose()
	await process_frame
	await process_frame
	if capturing:
		await _capture(OS.get_cmdline_user_args().has("stills"))
	else:
		process_frame.connect(_tick)
		root.window_input.connect(_input)

func _build() -> void:
	rect(Vector2.ZERO, Vector2(1600, 900), Color("101820"))
	label("MERIDIUS   /   FOOTMAN MOTION LAB", Vector2(42, 22), 17, Color("b9a176"))
	title = label("", Vector2(40, 52), 38)
	note = label("", Vector2(42, 102), 18, Color("b4c0ca"))
	label("AUTHORED BLOCKING  /  v01", Vector2(1270, 27), 15, Color("8799aa"))
	stage = Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("1b2731")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b3c6d8")
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color("fff0d4")
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	stage.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-28, 135, 0)
	fill.light_color = Color("9fc4ed")
	fill.light_energy = 0.30
	stage.add_child(fill)
	add_box(Vector3(0, -0.06, 0), Vector3(12, 0.10, 8), Proxy.material("283842"))
	var grid_mat := Proxy.material("3b4d57")
	for x in range(-10, 11):
		add_box(Vector3(x * 0.5, -0.003, 0), Vector3(0.009, 0.006, 6), grid_mat)
	for z in range(-6, 7):
		add_box(Vector3(0, -0.003, z * 0.5), Vector3(10, 0.006, 0.009), grid_mat)
	add_box(Vector3(0, 0.002, 0), Vector3(8, 0.006, 0.018), Proxy.material("8a7859"))
	actor = Proxy.new()
	stage.add_child(actor)
	actor.build()
	defender = Proxy.new()
	stage.add_child(defender)
	defender.build(true)
	defender.rotation.y = PI
	for i in 2:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(944, 592) if i == 0 else Vector2i(544, 592)
		viewport.world_3d = root.world_3d
		viewport.msaa_3d = Viewport.MSAA_4X
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		views.append(viewport)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.current = true
		viewport.add_child(camera)
		cameras.append(camera)
		var frame := TextureRect.new()
		frame.position = Vector2(40 if i == 0 else 1016, 172)
		frame.size = Vector2(viewport.size)
		frame.texture = viewport.get_texture()
		root.add_child(frame)
	label("THREE-QUARTER  /  FIXED CAMERA", Vector2(54, 184), 14, Color("b5c5d0"))
	label("SIDE  /  CONTACT CHECK", Vector2(1030, 184), 14, Color("b5c5d0"))
	label("0.5 m grid   |   teal: planted   /   amber: swinging", Vector2(54, 735), 14, Color("b5c5d0"))
	phase_label = label("", Vector2(44, 787), 23)
	clock_label = label("", Vector2(1278, 787), 21, Color("c8b68e"))
	contact_label = label("", Vector2(44, 824), 15, Color("91cbbd"))
	progress = ProgressBar.new()
	progress.position = Vector2(40, 862)
	progress.size = Vector2(1520, 5)
	progress.show_percentage = false
	root.add_child(progress)
	contact_flash = rect(Vector2(1518, 132), Vector2(40, 6), Color("e4b463"))
	label("1-4 clips   SPACE pause   ARROWS frame   S speed   R replay", Vector2(44, 139), 14, Color("8799aa"))

func add_box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var n := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	n.mesh = mesh
	n.material_override = mat
	n.position = pos
	stage.add_child(n)

func _update_pose() -> void:
	var p := Motion.sample(clip, time)
	actor.set_pose(p)
	defender.visible = clip != "move"
	if defender.visible:
		defender.position = Motion.target_position(clip)
		defender.set_pose(Motion.defender(clip, time))
	var moving := clip == "move" or clip == "charge"
	var focus := Vector3(-0.40 if clip == "charge" else 0.0, 0.75, -0.05)
	cameras[0].position = focus + Vector3(3.9, 3.0, 6.4)
	cameras[0].look_at(focus)
	cameras[0].size = 4.4 if moving else 3.30
	# Fixed side camera makes actual travel and planted foot contacts visible.
	cameras[1].position = focus + Vector3(0, 0.45, 8)
	cameras[1].look_at(focus)
	cameras[1].size = 5.1 if moving else 3.6
	title.text = TITLES[clip]
	note.text = NOTES[clip]
	phase_label.text = p.phase
	clock_label.text = "%05.2f / %.2f s   %s" % [time, Motion.LENGTHS[clip], "1x" if capturing else ("PAUSED" if playback_paused else ("0.5x" if speed < 1 else "1x"))]
	contact_label.text = "LEFT  %s      RIGHT  %s" % ["PLANTED" if p.left_down else "SWING", "PLANTED" if p.right_down else "SWING"]
	if clip != "move":
		var distance: float = (Motion.target_position(clip) + Vector3(-Motion.defender(clip, time).root.x, 0, 0) - Vector3(p.root.x, 0, p.root.z)).length()
		contact_label.text += "      BODY CENTRES  %.2f m      CONTACT  %.2f s" % [distance, Motion.IMPACTS[clip]]
	else:
		contact_label.text += "      TRAVEL  %.2f m      ROOT FOLLOWS THE PLANNED STRIDE" % [p.root.x + 1.5]
	progress.value = time / float(Motion.LENGTHS[clip]) * 100
	contact_flash.visible = p.impact

func _tick() -> void:
	if not playback_paused:
		time += root.get_process_delta_time() * speed
		if time > float(Motion.LENGTHS[clip]) + 0.6: time = 0
	_update_pose()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4:
			clip = Motion.CLIPS[event.keycode - KEY_1]
			time = 0
		KEY_SPACE: playback_paused = not playback_paused
		KEY_S: speed = 0.5 if speed == 1.0 else 1.0
		KEY_R: time = 0
		KEY_LEFT:
			playback_paused = true
			time = maxf(0, time - 1.0 / 30.0)
		KEY_RIGHT:
			playback_paused = true
			time = minf(Motion.LENGTHS[clip], time + 1.0 / 30.0)
		KEY_ESCAPE: quit()
	_update_pose()

func _capture(stills: bool) -> void:
	var args := OS.get_cmdline_user_args()
	var clips: Array = [clip] if Array(args).any(func(a): return a.begins_with("clip=")) else Motion.CLIPS
	for name in clips:
		clip = name
		var path := ProjectSettings.globalize_path(OUT + clip)
		DirAccess.make_dir_recursive_absolute(path)
		var count := ceili(float(Motion.LENGTHS[clip]) * 30.0)
		var indices: Array = [0, int(count * 0.24), int(count * 0.45), int(count * 0.72), count - 1] if stills else range(count)
		if stills and Motion.IMPACTS.has(clip): indices.append(roundi(float(Motion.IMPACTS[clip]) * 30.0))
		for index in indices:
			time = index / 30.0
			_update_pose()
			await process_frame
			await process_frame
			RenderingServer.force_draw(false)
			var error := root.get_texture().get_image().save_png(path + "/%04d.png" % index)
			if error != OK: errors.append("Failed to save frame %s/%s" % [clip, index])
		print("CAPTURED ", clip, " ", indices.size(), " frames")
	_write_manifest()
	print("MOTION STUDY errors: ", errors)
	quit(0 if errors.is_empty() else 1)

func _write_manifest() -> void:
	var manifest := {"version": 1, "status": "authored proposal; not integrated or user-approved", "units": "metres, seconds", "forward": "+X", "up": "+Y", "left": "-Z", "capture_fps": 30, "audit_hz": 240, "engine": Engine.get_version_info().string, "clips": {}}
	for name in Motion.CLIPS:
		var max_slip := 0.0
		var max_leg := 0.0
		var max_arm := 0.0
		var min_gap := INF
		var flight_frames := 0
		var previous := Motion.sample(name, 0)
		for frame in range(1, ceili(Motion.LENGTHS[name] * 240)):
			var t := frame / 240.0
			var p := Motion.sample(name, t)
			var torso := Basis(Vector3.UP, p.twist) * Basis(Vector3.BACK, -p.lean)
			for side in ["left", "right"]:
				var s := -1.0 if side == "left" else 1.0
				if p[side + "_down"] and previous[side + "_down"]:
					max_slip = maxf(max_slip, p[side].distance_to(previous[side]) * 240)
				var h: Vector3 = p.root + Vector3(0, -0.025, s * 0.135)
				max_leg = maxf(max_leg, h.distance_to(p[side]))
				max_arm = maxf(max_arm, (torso * Vector3(0, 0.45, s * 0.265)).distance_to(p["hand_l" if side == "left" else "hand_r"]))
			if not p.left_down and not p.right_down: flight_frames += 1
			if name != "move":
				var target := Motion.target_position(name) - Vector3(Motion.defender(name, t).root.x, 0, 0)
				min_gap = minf(min_gap, target.distance_to(Vector3(p.root.x, 0, p.root.z)))
			previous = p
		manifest.clips[name] = {"duration_s": Motion.LENGTHS[name], "loop": false, "frames_at_30fps": ceili(Motion.LENGTHS[name] * 30),
			"contact_s": Motion.IMPACTS.get(name), "contact_frame_at_30fps": float(Motion.IMPACTS[name]) * 30 if Motion.IMPACTS.has(name) else null,
			"max_planted_foot_speed_m_s": max_slip, "max_hip_ankle_distance_m": max_leg, "leg_length_m": 0.89,
			"max_shoulder_hand_distance_m": max_arm, "arm_length_m": 0.59, "min_body_centre_gap_m": min_gap if min_gap < INF else null,
			"flight_duration_s": flight_frames / 240.0, "root_translation": "authored world-space; never add to controller displacement", "footsteps": Motion.footsteps(name)}
	var file := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  "))
