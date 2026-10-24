## Bakes motion/<facing>.json (tools/bake_motion.py) into Godot AnimationPlayer
## tracks: motion/<facing>.tres (an AnimationLibrary, one Animation per clip) and
## motion/<facing>_rig.json (rest pose, clip metadata the runtime needs: root
## velocity, events, blade samples for the formation checks).
##
##   tools/godot.sh --headless --path . -s res://prototypes/footman_anim/bake/build_anims.gd
##
## Tracks per clip: every bone's position and rotation (30 keys a second,
## linear, angles by the short way), the limb stretch nodes' scale, the sword's
## layer (discrete) and a method track with the clip's events: `_ev_impact` on
## the weapon-contact frame, `_ev_step(side)` on each foot contact.
extends SceneTree

const Rig = preload("res://prototypes/footman_anim/scripts/footman_rig.gd")
const DIR := "res://prototypes/footman_anim/motion/"


func _initialize() -> void:
	var failed := false
	for facing in ["se", "sw", "ne", "nw"]:
		var path: String = DIR + facing + ".json"
		if not FileAccess.file_exists(path):
			print("skip ", facing, " (not baked)")
			continue
		var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var lib := AnimationLibrary.new()
		var meta := {"facing": facing, "view": doc.view, "mirror": doc.mirror, "swap": doc.swap,
			"rest": doc.rest, "scale_leg": doc.scale_leg, "part_shift": doc.get("part_shift", {}),
			"layers": doc.get("layers", {}), "clips": {}}
		for clip_name in doc.clips:
			var c: Dictionary = doc.clips[clip_name]
			lib.add_animation(clip_name, _animation(c, doc.rest))
			meta.clips[clip_name] = {"frames": c.frames, "fps": c.fps, "loop": c.loop,
				"length": _length(c), "root_velocity": c.root_velocity,
				"root_velocity_m": c.get("root_velocity_m", [0, 0]), "events": c.events,
				"contact": c.contact, "blade_m": c.get("blade_m", []),
				"feet": {"r": c.gpos["foot_r"], "l": c.gpos["foot_l"]},
				"tip": _tip_track(c, doc.rest), "root_jump": c.get("root_jump", [0, 0])}
		var err := ResourceSaver.save(lib, DIR + facing + ".tres")
		if err != OK:
			push_error("build_anims: cannot save %s (%d)" % [facing, err])
			failed = true
		var f := FileAccess.open(DIR + facing + "_rig.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(meta))
		f.close()
		print("baked ", facing, ": ", lib.get_animation_list())
	quit(1 if failed else 0)


static func _length(c: Dictionary) -> float:
	var n: int = c.frames
	return float(n) / c.fps if c.loop else float(n - 1) / c.fps


## Sword tip in view px per frame (for the smear and the QA traces).
static func _tip_track(c: Dictionary, rest: Dictionary) -> Array:
	var out := []
	var r: Dictionary = rest["sword"]
	var tip_len: float = r.len
	var stretch: Array = c.stretch.get("sword", [])
	for i in c.frames:
		var g: Array = c.gpos["sword"][i]
		var a: float = c.gang["sword"][i]
		var s: float = stretch[i] if i < stretch.size() else 1.0
		out.append([g[0] + cos(a) * tip_len * s, g[1] + sin(a) * tip_len * s])
	return out


static func _animation(c: Dictionary, rest: Dictionary) -> Animation:
	var anim := Animation.new()
	var n: int = c.frames
	var fps: float = c.fps
	anim.length = _length(c)
	anim.loop_mode = Animation.LOOP_LINEAR if c.loop else Animation.LOOP_NONE
	anim.step = 1.0 / fps
	for bone in Rig.BONES:
		var name: String = bone[0]
		var parent: String = bone[1]
		if not c.gpos.has(name):
			continue
		var path: String = Rig.bone_path(name)
		var rest_lr: float = float(rest[name].ang) - (float(rest[parent].ang) if parent != "" else 0.0)
		var pos_t := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(pos_t, NodePath(path + ":position"))
		anim.track_set_interpolation_type(pos_t, Animation.INTERPOLATION_CUBIC)
		var rot_t := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(rot_t, NodePath(path + ":rotation"))
		# Plain linear keys, unwrapped and kept within +-pi of the rest angle:
		# the mixer cross-fades rotation as numbers, so every clip must use the
		# same representation or a blend spins the bone the long way round.
		anim.track_set_interpolation_type(rot_t, Animation.INTERPOLATION_CUBIC)
		var prev_r := rest_lr
		var st: Array = c.stretch.get(name, [])
		var str_t := -1
		if not st.is_empty() and name in Rig.STRETCH_BONES:
			str_t = anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(str_t, NodePath(path + "/S:scale"))
			anim.track_set_interpolation_type(str_t, Animation.INTERPOLATION_LINEAR)
		for i in n:
			var t := i / fps
			var gp: Array = c.gpos[name][i]
			var ga: float = c.gang[name][i]
			var lp: Vector2
			var lr: float
			if parent == "":
				lp = Vector2(gp[0], gp[1])
				lr = ga
			else:
				var pp: Array = c.gpos[parent][i]
				var pa: float = c.gang[parent][i]
				lp = (Vector2(gp[0], gp[1]) - Vector2(pp[0], pp[1])).rotated(-pa)
				lr = ga - pa
			anim.track_insert_key(pos_t, t, lp)
			var rv := rest_lr + wrapf(lr - rest_lr, -PI, PI)
			if i > 0:
				rv = prev_r + wrapf(rv - prev_r, -PI, PI)
			prev_r = rv
			anim.track_insert_key(rot_t, t, rv)
			if str_t >= 0:
				anim.track_insert_key(str_t, t, Vector2(float(st[i]), 1.0))
	var sl: Array = c.get("sword_layer", [])
	if not sl.is_empty():
		var z_t := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(z_t, NodePath(".:sword_layer"))
		anim.value_track_set_update_mode(z_t, Animation.UPDATE_DISCRETE)
		var last = null
		for i in n:
			if sl[i] != last:
				anim.track_insert_key(z_t, i / fps, int(sl[i]))
				last = sl[i]
	if not c.events.is_empty():
		var m_t := anim.add_track(Animation.TYPE_METHOD)
		anim.track_set_path(m_t, NodePath("."))
		for e in c.events:
			var t: float = clampf(float(e.frame) / fps, 0.0, anim.length)
			if e.name == "impact":
				anim.track_insert_key(m_t, t, {"method": "_ev_impact", "args": []})
			elif e.name == "footstep":
				anim.track_insert_key(m_t, t, {"method": "_ev_step", "args": [e.side]})
	return anim
