## Render one rig clip frame by frame in a real window (Godot's own drawing).
##   tools/godot.sh --path . --resolution 900x700 -s res://prototypes/footman_anim/qa/rig_frames.gd -- facing=se clip=attack zoom=2 out=res://tests/visual/out/footman_proto/rig
extends SceneTree

const Rig = preload("res://prototypes/footman_anim/scripts/footman_rig.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {"facing": "se", "clip": "attack", "zoom": "2", "out": "res://tests/visual/out/footman_proto/rig", "every": "2"}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	root.size = Vector2i(900, 700)
	var bg := ColorRect.new()
	bg.color = Color("#c4ba96")
	bg.size = Vector2(900, 700)
	root.add_child(bg)
	var holder := Node2D.new()
	holder.position = Vector2(450, 560)
	holder.scale = Vector2.ONE * float(args.zoom)
	root.add_child(holder)
	var rig := Rig.new()
	holder.add_child(rig)
	rig.setup(args.facing, 0.6)
	rig.player.play(args.clip)
	rig.player.advance(0.0)
	rig.update_parts(0.0)
	var out := ProjectSettings.globalize_path(args.out + "/" + args.facing + "_" + args.clip)
	DirAccess.make_dir_recursive_absolute(out)
	var anim := rig.player.get_animation(args.clip)
	var n := int(round(anim.length * 30.0)) + 1
	var every := int(args.every)
	for f in n:
		if f > 0:
			rig.player.advance(1.0 / 30.0)
			rig.update_parts(1.0 / 30.0)
		if f % every == 0:
			await process_frame
			await process_frame
			var img := root.get_texture().get_image()
			img.save_png(out + "/%03d.png" % f)
	print("RIG_FRAMES ", out, " ", n)
	quit()
