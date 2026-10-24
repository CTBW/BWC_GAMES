## Frames of one clip of the 3D footman in place, from the battle camera, for
## a filmstrip: every `step` frames, one facing, close zoom.
##   tools/godot.sh --path . --resolution 1600x900 --audio-driver Dummy \
##     -s res://prototypes/footman_anim/qa/footman3d_strip.gd -- clip=walk facing=SW step=3 zoom=4 tag=before
## Writes tests/visual/out/footman3d/strip_<tag>_<clip>_<facing>/NNNN.png (a `box` px square around him, default 420).
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {"clip": "walk", "facing": "SW", "step": "3", "zoom": "4", "tag": "now", "box": "420"}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var sb: Node3D = load("res://prototypes/footman_anim/scenes/footman3d_sandbox.tscn").instantiate()
	root.add_child(sb)
	sb.set_process_unhandled_input(false)
	sb.sprite.visible = false
	sb.dummy.visible = false
	var fm: Node3D = sb.footman
	fm.rotation.y = fm.yaw_of(sb.FACINGS[args.facing])
	sb._zoom_goal = float(args.zoom)
	sb.zoom = float(args.zoom)
	sb._apply_look()
	fm.set_process(false)
	var out := ProjectSettings.globalize_path("res://tests/visual/out/footman3d/strip_%s_%s_%s" % [args.tag, args.clip, args.facing])
	DirAccess.make_dir_recursive_absolute(out)
	var clip: String = args.clip
	var L: float = fm.player.get_animation(clip).length
	fm.player.play(clip, 0.0)
	fm.player.speed_scale = 0.0
	for i in 12:
		await process_frame
	var n := 0
	var f := 0
	while f / 30.0 <= L + 0.001:
		fm.player.seek(f / 30.0, true)
		await process_frame
		await process_frame
		var img := root.get_texture().get_image()
		var bx := int(args.box)
		var c := Vector2i(img.get_width() / 2, img.get_height() / 2 - bx / 20)
		img.get_region(Rect2i(c.x - bx / 2, c.y - bx / 2, bx, bx)).save_png("%s/%04d.png" % [out, n])
		n += 1
		f += int(args.step)
	print("STRIP_DONE ", out, " ", n)
	quit()
