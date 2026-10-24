## Automated review of the prototype footman (working order + the 6-point
## review). Renders and logs every clip x facing, a transition script and the
## squad scenarios; tools/review_report.py turns the log into pass/fail.
##   tools/godot.sh --path . --audio-driver Dummy -s res://prototypes/footman_anim/qa/review.gd -- [part=clips,transitions,squad]
## Writes tests/visual/out/footman_proto/review/ : review.json + figure-alone
## PNGs (transparent, for the seam / gap scan) per clip x facing.
extends SceneTree

const Footman = preload("res://prototypes/footman_anim/scripts/footman.gd")
const Rig = preload("res://prototypes/footman_anim/scripts/footman_rig.gd")
const Squad = preload("res://prototypes/footman_anim/scripts/squad.gd")
const Dummy = preload("res://prototypes/footman_anim/scripts/dummy.gd")
const FX = preload("res://prototypes/footman_anim/scripts/fx.gd")
const Formation = preload("res://prototypes/footman_anim/scripts/formation.gd")

const CLIPS := ["idle", "walk", "attack", "block", "hit", "death", "step_lane"]
const STEP := 1.0 / 30.0
const JOINTS := ["hips", "spine", "head", "upper_r", "fore_r", "hand_r", "sword", "upper_l", "fore_l", "hand_l", "shield",
	"thigh_r", "shin_r", "foot_r", "thigh_l", "shin_l", "foot_l"]

var out := ""
var vp: SubViewport
var world: Node2D
var log := {"clips": {}, "transitions": {}, "squad": {}, "errors": []}
var available := []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {"part": "clips,transitions,squad", "png": "1"}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	out = ProjectSettings.globalize_path("res://tests/visual/out/footman_proto/review")
	DirAccess.make_dir_recursive_absolute(out)
	for k in Footman.FACING_KEYS:
		if FileAccess.file_exists("res://prototypes/footman_anim/motion/%s.tres" % k):
			available.append(k)
	vp = SubViewport.new()
	vp.size = Vector2i(300, 300)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	root.add_child(vp)
	world = Node2D.new()
	vp.add_child(world)
	var cam := Camera2D.new()
	cam.zoom = Vector2.ONE * 3.0
	cam.position = Vector2(0, -38)
	world.add_child(cam)
	cam.make_current()
	var parts := String(args.part).split(",")
	if "clips" in parts:
		await _review_clips(args.png == "1")
	if "transitions" in parts:
		await _review_transitions()
	if "squad" in parts:
		await _review_squad()
	var f := FileAccess.open(out + "/review.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(log))
	f.close()
	print("REVIEW_DONE ", out)
	quit()


## Per-frame record of one soldier: equipment, layering, handedness, feet, bounds.
func _frame(s: Node2D) -> Dictionary:
	var r: Node2D = s.rig
	var swords := 0
	var shields := 0
	var helmets := 0
	var sword_visible := false
	var shield_visible := false
	for k in s.rigs:
		var rr: Node2D = s.rigs[k]
		if not rr.visible:
			continue
		for p in rr.parts:
			var spr: Sprite2D = p.sprite
			if not spr.visible or spr.modulate.a < 0.5:
				continue
			if p.name == "sword":
				swords += 1
				sword_visible = true
			elif p.name == "shield":
				shields += 1
				shield_visible = true
			elif p.name == "head":
				helmets += 1
	var joints := {}
	for j in JOINTS:
		var g: Vector2 = s.to_global(r.joint(j))
		joints[j] = [snappedf(g.x, 0.01), snappedf(g.y, 0.01)]
	var tip: Vector2 = s.to_global(r.bone_tip("sword"))
	# Handedness: the sword hangs off the right hand's bone chain, the shield
	# off the left; and on screen the sword's grip is where the right hand is.
	var sword_bone := ""
	var shield_bone := ""
	for p in r.parts:
		if p.name == "sword":
			sword_bone = p.bone
		elif p.name == "shield":
			shield_bone = p.bone
	var grip: Vector2 = s.to_global(r.joint("sword"))
	var hand_r: Vector2 = s.to_global(r.joint("hand_r"))
	var scales := {}
	var bbox := Rect2()
	var first := true
	for p in r.parts:
		var spr: Sprite2D = p.sprite
		var xf: Transform2D = spr.get_global_transform()
		scales[p.name] = [snappedf(xf.get_scale().x, 0.0001), snappedf(xf.get_scale().y, 0.0001)]
		var rect := Rect2(Vector2.ZERO, spr.texture.get_size())
		var pts := [xf * rect.position, xf * Vector2(rect.end.x, rect.position.y), xf * rect.end, xf * Vector2(rect.position.x, rect.end.y)]
		if p.name in ["sword", "shield"]:
			continue
		for q in pts:
			if first:
				bbox = Rect2(q, Vector2.ZERO)
				first = false
			else:
				bbox = bbox.expand(q)
	var sword_i: int = r.part_index("sword")
	var chest_i: int = r.part_index("chest")
	var shield_i: int = r.part_index("shield")
	var hand_i: int = r.part_index("hand_r")
	return {
		"anim": r.player.current_animation, "t": snappedf(r.player.current_animation_position, 0.0001), "state": s.state,
		"pos": [snappedf(s.position.x, 0.01), snappedf(s.position.y, 0.01)],
		"swords": swords, "shields": shields, "heads": helmets, "sword_vis": sword_visible, "shield_vis": shield_visible,
		"sword_bone": sword_bone, "shield_bone": shield_bone, "grip_hand_d": snappedf(grip.distance_to(hand_r), 0.01),
		"order": {"sword": sword_i, "chest": chest_i, "shield": shield_i, "hand_r": hand_i},
		"sword_layer": r.sword_layer, "joints": joints, "tip": [snappedf(tip.x, 0.01), snappedf(tip.y, 0.01)],
		"scales": scales, "bbox": [snappedf(bbox.position.x, 0.1), snappedf(bbox.position.y, 0.1), snappedf(bbox.size.x, 0.1), snappedf(bbox.size.y, 0.1)],
		"hitstop": s.hitstop > 0.0, "impacts": s.impacts,
	}


func _new_soldier(f: int) -> Node2D:
	var s := Footman.new()
	world.add_child(s)
	s.setup(available, f)
	s.set_process(false)
	return s


func _review_clips(png: bool) -> void:
	for fkey in available:
		var f := Footman.FACING_KEYS.find(fkey)
		for clip in CLIPS:
			var s := _new_soldier(f)
			s.rig.player.play(clip, 0.0)
			s.state = clip
			if clip == "attack":
				s._smear_window = s._swing_window()
			s.rig.player.seek(0.0, true)
			s.rig.reset_springs()
			s.rig.update_parts(0.0)
			var anim: Animation = s.rig.player.get_animation(clip)
			var n := int(round(anim.length / STEP)) + 1
			if clip == "walk" or clip == "idle":
				n = int(round(anim.length / STEP)) * (2 if clip == "walk" else 1)
			var frames := []
			var dir := out + "/%s_%s" % [fkey, clip]
			if png:
				DirAccess.make_dir_recursive_absolute(dir)
			for i in n:
				if i > 0:
					s._advance(STEP)
					if clip in ["attack", "hit", "step_lane", "death"] and not s.rig.player.is_playing():
						break
				frames.append(_frame(s))
				if png and (clip != "idle" or i % 3 == 0):
					s.queue_redraw()
					await process_frame
					await process_frame
					vp.get_texture().get_image().save_png(dir + "/%04d.png" % i)
			var meta: Dictionary = s.clip_meta(clip)
			log.clips["%s_%s" % [fkey, clip]] = {"facing": fkey, "clip": clip, "frames": frames,
				"contact": meta.get("contact", {}), "root_velocity": [s.clip_velocity(clip).x, s.clip_velocity(clip).y],
				"loop": meta.get("loop", false), "impacts": s.impacts, "events": meta.get("events", [])}
			s.queue_free()
			await process_frame
			print("REVIEW clip ", fkey, " ", clip, " ", frames.size())


## The state machine across transitions, with real blends, at 60 Hz.
func _review_transitions() -> void:
	var scripts := {
		"idle_walk_stop_attack_idle": [["idle", 0.6], ["walk_to", 1.6], ["wait", 0.6], ["attack", 1.8], ["wait", 0.6]],
		"hit_from_idle": [["idle", 0.5], ["hit", 1.2]],
		"hit_from_walk": [["walk", 0.7], ["hit", 1.2]],
		"hit_from_block": [["block", 0.7], ["hit", 1.2]],
		"hit_from_attack": [["attack", 0.55], ["hit", 1.2]],
		"death_from_idle": [["idle", 0.4], ["death", 2.8]],
		"death_from_walk": [["walk", 0.6], ["death", 2.8]],
		"death_from_attack": [["attack", 0.6], ["death", 2.8]],
		"block_attack_block": [["block", 0.8], ["attack", 1.7], ["block", 0.8]],
		"facing_switch_mid_attack": [["attack", 0.5], ["face+1", 0.3], ["face+1", 0.3], ["face+1", 1.0]],
	}
	for fkey in available:
		var f := Footman.FACING_KEYS.find(fkey)
		for name in scripts:
			var s := _new_soldier(f)
			s.position = Vector2.ZERO
			var frames := []
			for stepi in scripts[name]:
				var what: String = stepi[0]
				var secs: float = stepi[1]
				match what:
					"idle": s.idle()
					"walk": s.walk_in_place()
					"walk_to": s.walk_toward(Footman.screen_dir(f) * 0.9)
					"attack": s.attack()
					"block": s.guard()
					"hit": s.hit()
					"death": s.die()
					"face+1": s.set_facing(s.facing + 1)
				var n := int(round(secs * 60.0))
				for i in n:
					s._advance(1.0 / 60.0)
					var fr := _frame(s)
					fr["script_step"] = what
					frames.append(fr)
			log.transitions["%s_%s" % [fkey, name]] = {"facing": fkey, "frames": frames}
			s.queue_free()
			await process_frame
		print("REVIEW transitions ", fkey)


## Squad scenarios: formation idle, march into a tile and stop, attack loop.
func _review_squad() -> void:
	for fkey in available:
		var f := Footman.FACING_KEYS.find(fkey)
		for scenario in ["formation", "march", "attack"]:
			var holder := Node2D.new()
			world.add_child(holder)
			var fx := FX.new()
			holder.add_child(fx)
			var squad := Squad.new()
			holder.add_child(squad)
			squad.fx = fx
			squad.sound = false
			var dirv: Vector2 = Formation.GRID_DIRS[f]
			squad.spawn(available, -dirv * 2.0 if scenario == "march" else Vector2.ZERO, f, 20261023)
			for m in squad.members:
				m.set_process(false)
			squad.set_process(false)
			fx.set_process(false)
			var dummy: Node2D = null
			if scenario == "attack":
				dummy = Dummy.new()
				dummy.position = Formation.iso(dirv)
				dummy.fx = fx
				holder.add_child(dummy)
				dummy.set_process(false)
				squad.attack(dummy, true)
			if scenario == "march":
				squad.march_to(Vector2.ZERO)
			var frames := []
			var secs := 8.0 if scenario != "march" else 7.0
			var n := int(secs * 60.0)
			var worst := []
			for i in n:
				for m in squad.members:
					m._process(1.0 / 60.0)
				squad._process(1.0 / 60.0)
				if dummy:
					dummy._process(1.0 / 60.0)
				fx._process(1.0 / 60.0)
				# Timers (march delays) run on the tree.
				if i % 1 == 0:
					await process_frame
				var ov := Formation.overlaps(squad.members)
				var rec := {"ov": ov.size(), "kinds": ov.map(func(o): return o.kind), "pairs": ov.map(func(o): return [o.a.label, o.b.label, snappedf(o.depth, 0.001)])}
				var feet := []
				for m in squad.members:
					feet.append({"state": m.state, "pos": [snappedf(m.position.x, 0.01), snappedf(m.position.y, 0.01)],
						"fr": snappedf(m.to_global(m.rig.joint("foot_r")).x, 0.01), "fry": snappedf(m.to_global(m.rig.joint("foot_r")).y, 0.01),
						"fl": snappedf(m.to_global(m.rig.joint("foot_l")).x, 0.01), "fly": snappedf(m.to_global(m.rig.joint("foot_l")).y, 0.01),
						"anim": m.rig.player.current_animation, "t": snappedf(m.rig.player.current_animation_position, 0.0001),
						"impacts": m.impacts, "swords": 1 if m.rig.part_sprite("sword").visible else 0})
				rec["m"] = feet
				frames.append(rec)
			var slots := []
			for i in squad.members.size():
				slots.append([squad.slot_world(i).x, squad.slot_world(i).y])
			log.squad["%s_%s" % [fkey, scenario]] = {"facing": fkey, "frames": frames, "slots": slots,
				"blows": squad.damage_ticks, "dummy_hits": dummy.hits if dummy else 0, "file_gap": squad.file_gap}
			holder.queue_free()
			await process_frame
		print("REVIEW squad ", fkey)
