## Native review of the supplied Mixamo attacks. Runtime-loads GLBs outside
## res:// so the review assets never enter the production sprite import.
extends SceneTree

const Proxy = preload("res://tools/motion_study/proxy.gd")
const Motion = preload("res://tools/motion_study/motion.gd")
var delivery: String
var clip := "stab"
var time := 0.0
var playback_paused := false
var rate := 1.0
var players: Array[AnimationPlayer] = []
var actors: Array[Node3D] = []
var viewports: Array[SubViewport] = []
var caption: Label
var title: Label
var status: Label
var meta: Dictionary
var target_point: Vector3
var errors: Array = []

func _initialize() -> void:
	delivery = ProjectSettings.globalize_path("res://../../../../workspace/2026-10-20_meridius/motion-study/mixamo/")
	_run.call_deferred()

func text_label(value: String, pos: Vector2, font_size: int, color := Color("dbe6ed")) -> Label:
	var l := Label.new()
	l.text = value
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	root.add_child(l)
	return l

func _run() -> void:
	root.content_scale_size = Vector2i(1600, 900)
	root.size = Vector2i(1600, 900)
	root.title = "Meridius | Mixamo attack study"
	var bg := ColorRect.new()
	bg.color = Color("111c25")
	bg.size = Vector2(1600, 900)
	root.add_child(bg)
	text_label("MERIDIUS  /  FOOTMAN ATTACKS  /  MIXAMO v02", Vector2(38, 24), 17, Color("ceb68c"))
	title = text_label("", Vector2(36, 59), 38)
	text_label("Your FBX motion. Original speed. Right-hand sword. Left-hand shield.", Vector2(39, 111), 19)
	caption = text_label("", Vector2(40, 786), 22)
	status = text_label("", Vector2(40, 828), 16, Color("9bb3c3"))
	text_label("1 Stab   2 Slash   SPACE pause   ARROWS frame   S half speed   R replay", Vector2(40, 866), 14, Color("91a4b2"))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("clip="): clip = arg.substr(5)
	_load_clip()
	await process_frame
	await process_frame
	if OS.get_cmdline_user_args().has("stills") or OS.get_cmdline_user_args().has("capture"):
		await _capture(OS.get_cmdline_user_args().has("stills"))
	else:
		process_frame.connect(func():
			if not playback_paused:
				time += root.get_process_delta_time() * rate
				if time > float(meta.duration) + 0.6: time = 0
			_pose())
		root.window_input.connect(_input)

func _load_clip() -> void:
	for viewport in viewports: viewport.free()
	viewports.clear()
	players.clear()
	actors.clear()
	for n in root.get_children():
		if n is TextureRect: n.free()
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(delivery + "manifest.json"))
	for entry in document.clips:
		if entry.id == clip: meta = entry
	var samples: Array = JSON.parse_string(FileAccess.get_file_as_string(delivery + clip + "_samples.json"))
	var tip: Array = samples[int(meta.contact_frame) - 1].sword_tip
	target_point = Vector3(tip[0], tip[2], -tip[1])
	for i in 3:
		_build_view(i)
	time = 0
	title.text = "01 / THE STAB" if clip == "stab" else "02 / THE OUTWARD SLASH"
	_pose()

func box(parent: Node3D, at: Vector3, size: Vector3, color: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = Proxy.material(color)
	node.position = at
	parent.add_child(node)
	return node

func _build_view(index: int) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(944, 600) if index == 0 else Vector2i(544, 290)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	viewports.append(vp)
	var stage := Node3D.new()
	vp.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("263844")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("bfd8eb")
	env.environment.ambient_light_energy = 0.65
	stage.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45,-30,0)
	light.shadow_enabled = true
	light.light_energy = 1.1
	stage.add_child(light)
	box(stage, Vector3(0,-0.045,0), Vector3(8,.08,8), "304652")
	for k in range(-8,9):
		box(stage, Vector3(k*.5,0,0), Vector3(.009,.006,8), "45616c")
		box(stage, Vector3(0,0,k*.5), Vector3(8,.006,.009), "45616c")
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var path := delivery + clip + ("_source" if index == 2 else "") + ".glb"
	var result := gltf.append_from_file(path, state)
	assert(result == OK, "Failed to read " + path)
	var actor := gltf.generate_scene(state)
	stage.add_child(actor)
	actors.append(actor)
	var player := actor.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(player != null)
	var animation := String(player.get_animation_list()[0])
	player.play(animation)
	player.pause()
	players.append(player)
	if index == 0:
		# A fixed training target reveals reach without moving the attacker.
		box(stage, Vector3(target_point.x,.55,target_point.z+.05), Vector3(.09,1.1,.09), "7d6750")
		box(stage, target_point + Vector3(0,0,.045), Vector3(.38,.46,.07), "aa7660")
		box(stage, target_point + Vector3(0,0,.003), Vector3(.06,.32,.015), "d5be91")
		box(stage, target_point + Vector3(0,0,.001), Vector3(.26,.055,.018), "d5be91")
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.35 if index == 0 else 2.65
	stage.add_child(camera)
	var focus := Vector3(0,.88,.45 if index == 0 else .1)
	camera.position = focus + (Vector3(4,2.5,5) if index == 0 else (Vector3(6,.35,0) if index == 1 else Vector3(3,2,5)))
	camera.look_at(focus)
	var image := TextureRect.new()
	image.texture = vp.get_texture()
	image.position = Vector2(40,166) if index == 0 else Vector2(1016,166 + 310 * (index-1))
	image.size = vp.size
	root.add_child(image)
	var label := Label.new()
	label.text = ["ADAPTED  /  FIXED TARGET", "ADAPTED  /  SIDE VIEW", "ORIGINAL FBX  /  UNEDITED MOTION"][index]
	label.position = Vector2(14,10)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("dce9ed"))
	image.add_child(label)
	print("LOADED ", clip, " view=", index, " animation=", animation, " length=", player.current_animation_length)

func _pose() -> void:
	for player in players:
		player.seek(minf(time, float(meta.duration)), true)
		player.advance(0)
	var contact := float(meta.contact_seconds)
	var phase := "PREPARE" if time < contact - .22 else ("DELIVER" if time < contact else ("FOLLOW THROUGH" if time < contact + .3 else "RECOVER"))
	caption.text = "%s     %.2f / %.2f s     %s" % [phase, minf(time,float(meta.duration)), meta.duration, "playback_paused" if playback_paused else ("0.5x" if rate < 1 else "1x")]
	status.text = "30 fps  |  source frames %d-%d  |  proposed contact %.2f s  |  no added body lunge  |  study mannequin" % [meta.frames[0],meta.frames[1],contact]

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_1, KEY_2:
			clip = "stab" if event.keycode == KEY_1 else "slash"
			_load_clip()
		KEY_SPACE: playback_paused = not playback_paused
		KEY_S: rate = 0.5 if rate == 1 else 1.0
		KEY_R: time = 0
		KEY_LEFT:
			playback_paused = true
			time = maxf(0,time-1.0/30)
		KEY_RIGHT:
			playback_paused = true
			time = minf(meta.duration,time+1.0/30)
		KEY_ESCAPE: quit()
	_pose()

func _capture(stills: bool) -> void:
	var audit: Dictionary = {}
	for name in ["stab", "slash"]:
		clip = name
		_load_clip()
		var out := ProjectSettings.globalize_path("res://tests/visual/out/mixamo-attack/" + clip)
		DirAccess.make_dir_recursive_absolute(out)
		var count := int(meta.samples)
		var frames: Array = [0,14,int(meta.contact_frame)-1,35,count-1] if stills else range(count)
		for f in frames:
			time = float(f)/30
			_pose()
			await process_frame
			await process_frame
			RenderingServer.force_draw(false)
			assert(root.get_texture().get_image().save_png(out+"/%04d.png" % f) == OK)
		print("MIXAMO_CAPTURE ", clip, " ", frames.size())
		audit[clip] = _audit_export()
	var file := FileAccess.open(delivery + "godot-checks.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(audit,"  "))
	quit()

func _audit_export() -> Dictionary:
	var samples: Array = JSON.parse_string(FileAccess.get_file_as_string(delivery + clip + "_samples.json"))
	var skeleton := actors[0].find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var max_error := 0.0
	var max_weapon_error := 0.0
	var blade := actors[0].find_child("Sword_blade", true, false) as Node3D
	if blade == null: blade = actors[0].find_child("Swordblade", true, false) as Node3D
	if blade == null: blade = actors[0].find_child("Sword blade", true, false) as Node3D
	assert(blade != null)
	for sample in samples:
		time = sample.time
		_pose()
		skeleton.force_update_all_bone_transforms()
		for side in ["Left", "Right"]:
			var bone := skeleton.find_bone("mixamorig_" + side + "Foot")
			if bone < 0: bone = skeleton.find_bone("mixamorig:" + side + "Foot")
			assert(bone >= 0)
			var actual: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
			var p: Array = sample.feet[side]
			max_error = maxf(max_error, actual.distance_to(Vector3(p[0],p[2],-p[1])))
		var tip: Array = sample.sword_tip
		var blade_tip := blade.global_transform * Vector3(0,0,.37)
		max_weapon_error = maxf(max_weapon_error, blade_tip.distance_to(Vector3(tip[0],tip[2],-tip[1])))
	assert(max_error < .001, "Imported ankle motion differs from source")
	assert(max_weapon_error < .001, "Imported sword tip differs from Blender")
	assert(absf(players[0].current_animation_length - float(meta.duration)) < .001)
	return {"bone_count":skeleton.get_bone_count(),"duration":players[0].current_animation_length,
		"max_ankle_export_error_m":max_error,"max_sword_tip_export_error_m":max_weapon_error,
		"samples_checked":samples.size(),"production_integration":false}
