## Reference pack capture: the single footman (the real soldier script, cloth
## springs and smear included) in every state x facing, stepped at exactly
## 1/30 s, rendered by Godot into a fixed-size SubViewport.
##   tools/godot.sh --path . --audio-driver Dummy -s res://prototypes/footman_anim/qa/capture_pack.gd -- [facings=se,sw,nw,ne] [clips=...] [twos=1] [size=360] [zoom=3.2] [out=...]
## Frames: tests/visual/out/footman_proto/pack/<facing>_<clip>[_twos]/0000.png
extends SceneTree

const Footman = preload("res://prototypes/footman_anim/scripts/footman.gd")
const Ground = preload("res://prototypes/footman_anim/scripts/ground.gd")

var vp: SubViewport
var soldier: Node2D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {"facings": "se,sw,nw,ne", "clips": "idle,walk,attack,block,hit,death,step_lane", "twos": "0",
		"size": "360", "zoom": "3.2", "out": "res://tests/visual/out/footman_proto/pack", "idle_secs": "3.0"}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var size: int = int(args.size)
	vp = SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	root.add_child(vp)
	var world := Node2D.new()
	vp.add_child(world)
	var ground := Ground.new()
	ground.radius = 2
	world.add_child(ground)
	var cam := Camera2D.new()
	cam.zoom = Vector2.ONE * float(args.zoom)
	cam.position = Vector2(0, -34)
	world.add_child(cam)
	cam.make_current()
	var available := []
	for k in Footman.FACING_KEYS:
		if FileAccess.file_exists("res://prototypes/footman_anim/motion/%s.tres" % k):
			available.append(k)
	var twos: bool = args.twos == "1"
	var step := 1.0 / 12.0 if twos else 1.0 / 30.0
	var report := {}
	for fkey in String(args.facings).split(","):
		var f := Footman.FACING_KEYS.find(fkey)
		for clip in String(args.clips).split(","):
			if soldier != null:
				soldier.queue_free()
				await process_frame
			soldier = Footman.new()
			world.add_child(soldier)
			soldier.setup(available, f)
			soldier.set_process(false)
			match clip:
				"idle": soldier.idle(0.0)
				"walk": soldier.walk_in_place()
				"attack": soldier.attack()
				"block": soldier.guard()
				"hit": soldier.hit()
				"death": soldier.die()
				"step_lane": soldier.step_lane(Vector2.ZERO)
			# Start exactly at the clip's first frame (no blend from idle).
			soldier.rig.player.play(clip, 0.0)
			soldier.rig.player.seek(0.0, true)
			soldier.rig.reset_springs()
			soldier.rig.update_parts(0.0)
			# The fall needs room: frame the death wider.
			cam.zoom = Vector2.ONE * (float(args.zoom) * 0.72 if clip == "death" else float(args.zoom))
			cam.position = Vector2(0, -18) if clip == "death" else Vector2(0, -34)
			var length: float = soldier.rig.player.get_animation(clip).length
			var secs := length
			if clip == "idle":
				secs = float(args.idle_secs)
			elif clip == "walk":
				secs = length * 2.0
			elif clip == "death":
				secs = length + 0.5
			var n := int(ceil(secs / step))
			var dir := ProjectSettings.globalize_path("%s/%s_%s%s" % [args.out, fkey, clip, "_twos" if twos else ""])
			DirAccess.make_dir_recursive_absolute(dir)
			for i in n:
				if i > 0:
					soldier._advance(step)
				soldier.queue_redraw()
				await process_frame
				await process_frame
				vp.get_texture().get_image().save_png(dir + "/%04d.png" % i)
			report["%s_%s" % [fkey, clip]] = {"frames": n, "step": step, "impacts": soldier.impacts, "steps": soldier.steps}
			print("PACK ", fkey, " ", clip, " ", n)
	var f2 := FileAccess.open(ProjectSettings.globalize_path(args.out + "/pack%s.json" % ("_twos" if twos else "")), FileAccess.WRITE)
	f2.store_string(JSON.stringify(report, " "))
	f2.close()
	quit()
