## A 3D unit in the sandbox, driven by its roster profile (roster.gd) and its
## clips' sidecar: any rigged model the art pipeline exports (FBX or GLB, with
## its clips named as in the sidecar, maybe behind an "Armature|" prefix). The
## footman has his own controller (footman_unit.gd) with the same interface:
##   order_move(points, then)   walk a route (world points on the ground)
##   strike(target, i)          turn to a target and play attack i of the profile
##   strike_at(target)          a squad's man's blow: an attack that reaches it
##   take_hit(from, lethal)     the hit reaction, or the death
##   play_clip(name)            any clip once (a loop until the next order)
##   die() revive() stop() is_dead() actions() clip_names()
##   set_look(mode, outline) set_outline_width(m) playback height_m()
## A profile's `face` picks the sidecar's face variants (`faces`) the unit
## wears; the other faces' meshes go. Its `kit` picks the sidecar's gear
## variants (`kit`), whose `hide` meshes go.
## Every model faces +Z: a direction d on the ground is the yaw atan2(d.x, d.z).
## The sandbox sets the height of the ground under the unit after it moves.
## A view of motion only: the sandbox decides who is hit and who falls.
extends Node3D

signal impact(target: Node3D, landed: bool, reach: float)
## A ranged attack lets go (the sandbox flies its missile).
signal release(target: Node3D, kind: String)
signal clip_event(name: String)

const OUTLINE := preload("res://prototypes/footman_anim/shaders/outline3d.gdshader")
const WhipFX = preload("res://prototypes/footman_anim/scripts/whip_fx.gd")
const BLEND := 0.2
## Turning on the spot and on the march (radians a second).
const TURN_RATE := deg_to_rad(420.0)
const STEER_RATE := deg_to_rad(300.0)
## A blow lands within its reach and this far off the striker's facing.
const HIT_ARC := 80.0
## Events that mark a blow or a shot leaving, whatever a sidecar calls them.
const HIT_EVENTS := ["contact", "strike", "strikes", "strike_left", "strike_right", "shot", "release", "fire", "impact"]

var profile: Dictionary
var meta: Dictionary
## Clip name -> {anim, length, loop, speed, events: [[t, name], ...]}.
var clips := {}
var model: Node3D
var player: AnimationPlayer
var skeleton: Skeleton3D
var fx: Node3D
var faction := "player"
var state := "idle"
var path: Array = []
var stance := ""
var speed_now := 0.0
var last_impact := ""
var playback := 1.0:
	set(v):
		playback = v
		if player:
			player.speed_scale = v
var _clip := ""
var _target: Node3D
var _attack: Dictionary
var _hits: Array = []
var _then := Callable()
var _yaw_goal := NAN
var _after_turn := Callable()
var _prev_t := 0.0
var _ev_i := 0
var _variant_in := 0.0
var _rng := RandomNumberGenerator.new()
var _outline: ShaderMaterial
var _outline_thin: ShaderMaterial
var _surfaces: Array = []


func setup(p: Dictionary) -> void:
	profile = p
	faction = p.get("faction", "player")


func _ready() -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string(profile.meta))
	model = (load(profile.model) as PackedScene).instantiate()
	if profile.has("scale"):
		model.scale = Vector3.ONE * float(profile.scale)
	add_child(model)
	player = model.find_children("*", "AnimationPlayer", true, false)[0]
	var sks := model.find_children("*", "Skeleton3D", true, false)
	skeleton = sks[0] if not sks.is_empty() else null
	_read_clips()
	# Roles the sidecar names (the spearman's and crossbowman's exports) fill
	# what the profile leaves open.
	var roles: Dictionary = meta.get("roles", {})
	for k in ["idle", "walk", "hit"]:
		if not profile.has(k) and roles.has(k):
			profile[k] = roles[k]
	if not profile.has("death") and roles.has("death"):
		profile["death"] = roles.death[0] if roles.death is Array else roles.death
		if roles.death is Array:
			profile["deaths"] = roles.death
	if not profile.has("attacks") and roles.has("attack"):
		var list := []
		for c in (roles.attack if roles.attack is Array else [roles.attack]):
			var atk: Dictionary = profile.get("attack_defaults", {}).duplicate()
			atk["clip"] = c
			# The defaults' label names the first attack only; the profile's labels any.
			var label: String = atk.get("label", "") if list.is_empty() else ""
			atk["label"] = profile.get("labels", {}).get(c, label if label != "" else String(c).capitalize())
			list.append(atk)
		profile["attacks"] = list
	if not profile.has("extras") and roles.has("extra"):
		profile["extras"] = roles.extra
	player.animation_finished.connect(_on_finished)
	player.speed_scale = playback
	_outline = ShaderMaterial.new()
	_outline.shader = OUTLINE
	_outline_thin = ShaderMaterial.new()
	_outline_thin.shader = OUTLINE
	_dress(profile.get("face", []) + profile.get("kit", []))
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if _named(mi, profile.get("full_detail", [])):
			mi.lod_bias = 128.0
		for i in mi.mesh.get_surface_count():
			_surfaces.append([mi, i, mi.get_active_material(i)])
	if profile.get("fx", "") == "whip" and skeleton:
		fx = WhipFX.new()
		fx.name = "WhipFX"
		add_child(fx)
		var atk: Dictionary = clips.get("attack", {})
		fx.setup(self, skeleton, player, atk.get("anim", "attack"), meta.clips.get("attack", {}).get("events", {}), float(meta.get("fps", 30.0)))
	set_look("toon", true)
	_rng.randomize()
	_play(idle_clip(), 0.0)
	player.seek(_rng.randf() * float(clips.get(idle_clip(), {}).get("length", 1.0)), true)


## Wears the sidecar's faces and kit named in `chosen`: the meshes the other
## faces show go, and so do the meshes a chosen variant's `hide` names (the
## brute's pauldrons); a chosen face's `albedo` swaps a mesh's base colour for
## that file next to the sidecar (the brute's scar is painted into his body's).
func _dress(chosen: Array) -> void:
	var variants: Dictionary = meta.get("faces", {}).merged(meta.get("kit", {}))
	if variants.is_empty():
		return
	var shown := {}
	var hidden := {}
	var albedo := {}
	for f in chosen:
		var v: Dictionary = variants.get(f, {})
		for m in v.get("show", []):
			shown[m] = true
		for m in v.get("hide", []):
			hidden[m] = true
		albedo.merge(v.get("albedo", {}), true)
	for f in variants:
		for m in variants[f].get("show", []):
			if not shown.has(m):
				hidden[m] = true
	for m in hidden:
		var mi := model.find_child(m, true, false) as MeshInstance3D
		if mi:
			mi.get_parent().remove_child(mi)
			mi.free()
	for m in albedo:
		var mi := model.find_child(m, true, false) as MeshInstance3D
		var tex: Texture2D = load(String(profile.meta).get_base_dir().path_join(albedo[m]))
		if mi == null or tex == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i) as StandardMaterial3D
			if src:
				var mat: StandardMaterial3D = src.duplicate()
				mat.albedo_texture = tex
				mi.set_surface_override_material(i, mat)


## The sidecar's clips matched to the model's animations, with the sidecar's
## lengths and loops put back (the importer adds a held last frame and drops
## the loop flags).
func _read_clips() -> void:
	var names := player.get_animation_list()
	for c in meta.clips:
		var info: Dictionary = meta.clips[c]
		var anim := ""
		for n in names:
			if String(n) == c or String(n).ends_with("|" + c) or String(n).ends_with("/" + c):
				anim = n
				break
		if anim == "":
			for n in names:
				if String(n).to_lower() == String(c).to_lower() or String(n).to_lower().ends_with("|" + String(c).to_lower()):
					anim = n
					break
		if anim == "":
			continue
		var a := player.get_animation(anim)
		var length := float(info.get("length", info.get("duration_seconds", a.length)))
		var loop := bool(info.get("loop", false))
		if length > 0.05 and length < a.length:
			a.length = length
		a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		var speed := float(info.get("speed_mps", info.get("walk_speed_m_s", 0.0)))
		if speed <= 0.0 and info.get("root_vel") is Array:
			var v: Array = info.root_vel
			speed = Vector3(v[0], v[1], v[2]).length()
		clips[c] = {"anim": anim, "length": a.length, "loop": loop, "speed": speed, "events": _events(info.get("events", []))}


## Events as [[seconds, name], ...] in time order, from any of the sidecar
## forms: {name: t}, {name: [t, t]}, {name: [[t, label], ...]}, or
## [{name, time | seconds}, ...].
static func _events(src: Variant) -> Array:
	var out := []
	if src is Dictionary:
		for k in src:
			var v: Variant = src[k]
			if v is float or v is int:
				out.append([float(v), k])
			elif v is Array:
				for e in v:
					if e is Array and e.size() >= 2:
						out.append([float(e[0]), "%s:%s" % [k, e[1]]])
					elif e is float or e is int:
						out.append([float(e), k])
	elif src is Array:
		for e in src:
			if e is Dictionary:
				out.append([float(e.get("time", e.get("seconds", 0.0))), String(e.get("name", ""))])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out


func _named(mi: Node, parts: Array) -> bool:
	for p in parts:
		if String(mi.name).contains(p):
			return true
	return false


# --- Look ---------------------------------------------------------------------------

## "toon" (hard light and shadow bands), "flat" (texture only) or "pbr" (the
## import as it is); the ink outline on or off (footman3d.gd set_look).
func set_look(mode: String, outline: bool) -> void:
	for s in _surfaces:
		var src: Material = s[2]
		var m: StandardMaterial3D = src.duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		if _named(s[0], profile.get("two_sided", [])):
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if profile.get("opaque", true):
			m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		match mode:
			"toon":
				m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				m.metallic = 0.0
				m.roughness = 1.0
			"flat":
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var line: ShaderMaterial = null
		if outline and not _named(s[0], profile.get("no_outline", [])):
			line = _outline_thin if _named(s[0], profile.get("thin_outline", [])) else _outline
		m.next_pass = line
		s[0].set_surface_override_material(s[1], m)


func set_outline_width(metres: float) -> void:
	_outline.set_shader_parameter("width", metres)
	_outline_thin.set_shader_parameter("width", metres * 0.35)


func height_m() -> float:
	return float(meta.get("height_m", profile.get("height", 1.8))) * float(profile.get("scale", 1.0))


func title() -> String:
	return profile.get("title", name)


# --- Clips ----------------------------------------------------------------------------

func idle_clip() -> String:
	return stance if stance != "" else profile.get("idle", "idle")


## Metres a second on the walk clip (a model scaled up strides farther).
func walk_speed() -> float:
	return maxf(float(clips.get(profile.get("walk", "walk"), {}).get("speed", 1.0)), 0.3) * float(profile.get("scale", 1.0))


func clip_names() -> Array:
	var out := clips.keys()
	out.sort()
	return out


func has_clip(c: String) -> bool:
	return clips.has(c)


func _play(c: String, blend := BLEND) -> void:
	if not clips.has(c):
		return
	_clip = c
	_ev_i = 0
	_prev_t = 0.0
	player.speed_scale = playback
	player.play(clips[c].anim, blend)
	if fx:
		fx.on_play(clips[c].anim)
	if c == idle_clip() and stance == "":
		var every: Array = meta.get("variants", {}).get("idle", {}).get("every_s", profile.get("variant_every", [9.0, 22.0]))
		_variant_in = _rng.randf_range(every[0], every[1])


## What the panel offers: the profile's attacks, stances and its other clips.
func actions() -> Array:
	var out := []
	var atks: Array = profile.get("attacks", [])
	for i in atks.size():
		if clips.has(atks[i].clip):
			out.append({"id": "attack:%d" % i, "label": atks[i].get("label", atks[i].clip), "target": true})
	for s in profile.get("stances", []):
		if clips.has(s):
			out.append({"id": "stance:" + s, "label": String(s).capitalize(), "toggle": true})
	return out


func attack_info(i: int) -> Dictionary:
	var atks: Array = profile.get("attacks", [])
	return atks[i] if i >= 0 and i < atks.size() else {}


## Where to stand to strike with attack i (centre to centre, metres), and
## whether it is shot from afar.
func reach(i: int) -> float:
	return float(attack_info(i).get("reach", profile.get("reach", 1.5)))


func is_ranged(i: int) -> bool:
	return attack_info(i).has("missile")


## The attacks a squad's man uses (indices): those whose clips are in `names`
## (all of his, if it is empty) and that he has.
func squad_attacks(names: Array = []) -> Array:
	var out := []
	var atks: Array = profile.get("attacks", [])
	for i in atks.size():
		if clips.has(atks[i].clip) and (names.is_empty() or atks[i].clip in names):
			out.append(i)
	return out


## One of his squad's attacks (`names`, see squad_attacks) that reaches
## `target` from where he stands, at random; the first of them if none does.
func pick_attack(target: Node3D, names: Array = []) -> int:
	var all := squad_attacks(names)
	if all.is_empty():
		return 0
	if target == null:
		return all[0]
	var d := Vector2(target.position.x - position.x, target.position.z - position.z).length()
	var fit := all.filter(func(i): return d <= reach(i) + (0.0 if is_ranged(i) else 0.45))
	return fit[_rng.randi_range(0, fit.size() - 1)] if not fit.is_empty() else all[0]


## Seconds from the start of attack i to its first blow or shot, at his playback.
func hit_lead(i: int) -> float:
	var a := attack_info(i)
	if a.is_empty() or not clips.has(a.clip):
		return 0.0
	var c: Dictionary = clips[a.clip]
	var names: Array = a.get("hits", HIT_EVENTS)
	var t: float = float(c.length) * float(a.get("hit_at", 0.45))
	for e in c.events:
		if String(e[1]) in names or String(e[1]).get_slice(":", 0) in names:
			t = e[0]
			break
	return t / maxf(playback, 0.05)


## A blow or a shot at `target`, as a squad's man strikes: attack i, or one
## of his that reaches it (pick_attack).
func strike_at(target: Node3D, i := -1) -> void:
	if is_dead() or target == null:
		return
	strike(target, i if i >= 0 else pick_attack(target))


## Where attack i's missile leaves (the current attack's when i < 0), in the
## world: the sidecar's `shot_from` for its clip (the middle of the archer's
## arrow as he looses, in the model's axes), or Vector3.INF where it has none.
func missile_from(i := -1) -> Vector3:
	var a: Dictionary = attack_info(i) if i >= 0 else _attack
	var p: Variant = meta.get("clips", {}).get(a.get("clip", ""), {}).get("shot_from")
	if not (p is Array and p.size() == 3):
		return Vector3.INF
	var local: Vector3 = model.transform * Vector3(p[0], p[1], p[2])
	return global_transform * local if is_inside_tree() else transform * local


# --- Orders ---------------------------------------------------------------------------

func is_dead() -> bool:
	return state == "dead"


func stop() -> void:
	if is_dead():
		return
	path.clear()
	_then = Callable()
	_yaw_goal = NAN
	state = "idle"
	_play(idle_clip())


## Walk the route (points on the ground), then `then`.
func order_move(points: Array, then := Callable()) -> void:
	if is_dead():
		return
	path = points.duplicate()
	_then = then
	stance = ""
	if path.is_empty():
		_arrive()
		return
	if state != "walk":
		state = "walk"
		_play(profile.get("walk", "walk"), 0.18)


func _arrive() -> void:
	path.clear()
	speed_now = 0.0
	state = "idle"
	_play(idle_clip(), 0.25)
	var t := _then
	_then = Callable()
	if t.is_valid():
		t.call()


## Turn to face a point, then `then`.
func turn_to(at: Vector3, then := Callable()) -> void:
	var d := at - position
	if Vector2(d.x, d.z).length() < 1e-3:
		if then.is_valid():
			then.call()
		return
	_yaw_goal = atan2(d.x, d.z)
	_after_turn = then
	if absf(angle_difference(rotation.y, _yaw_goal)) < deg_to_rad(4.0):
		rotation.y = _yaw_goal
		_yaw_goal = NAN
		_after_turn = Callable()
		if then.is_valid():
			then.call()


## Face the target and play attack i; its blows land at the clip's events.
func strike(target: Node3D, i: int) -> void:
	if is_dead():
		return
	var a := attack_info(i)
	if a.is_empty() or not clips.has(a.clip):
		return
	path.clear()
	_then = Callable()
	stance = ""
	_target = target
	if target:
		turn_to(target.global_position, _swing.bind(i))
	else:
		_swing(i)


func _swing(i: int) -> void:
	if is_dead():
		return
	var a := attack_info(i)
	_attack = a
	_hits = []
	var c: Dictionary = clips[a.clip]
	var names: Array = a.get("hits", HIT_EVENTS)
	for e in c.events:
		if String(e[1]) in names or String(e[1]).get_slice(":", 0) in names:
			_hits.append(e[0])
	if _hits.is_empty():
		_hits.append(c.length * float(a.get("hit_at", 0.45)))
	state = "attack"
	_play(a.clip, 0.12)


func _strike_now() -> void:
	var a := _attack
	if a.has("missile"):
		last_impact = "%s loosed" % a.get("label", a.clip)
		release.emit(_target, String(a.missile))
		return
	if _target == null or not is_instance_valid(_target):
		last_impact = "%s at the air" % a.get("label", a.clip)
		impact.emit(null, false, 0.0)
		return
	var to := _target.global_position - global_position
	to.y = 0
	var r := float(a.get("reach", profile.get("reach", 1.5))) + 0.45
	var ang := rad_to_deg(absf(angle_difference(rotation.y, atan2(to.x, to.z))))
	var landed := to.length() <= r and ang <= HIT_ARC
	last_impact = "%s %s at %.2f m, %d° off the facing" % [a.get("label", a.clip), "lands" if landed else "misses", to.length(), int(ang)]
	impact.emit(_target, landed, to.length())


## A blow from `from` (a ground point): the hit reaction, or the death.
func take_hit(from: Vector3, lethal := false) -> void:
	if is_dead():
		return
	path.clear()
	_then = Callable()
	stance = ""
	var d := from - global_position
	if Vector2(d.x, d.z).length() > 0.05 and profile.get("face_blow", true):
		rotation.y = atan2(d.x, d.z)
	if lethal:
		die()
		return
	state = "hit"
	var c: String = profile.get("hit", "hit")
	if clips.has(c):
		_play(c, 0.08)
		player.seek(0.0, true)
		return
	# No hit clip (the wolf scout): the body rocks back from the blow and steadies.
	var p := maxf(playback, 0.1)
	var tw := create_tween()
	tw.tween_property(model, "rotation:x", -0.2, 0.08 / p).set_ease(Tween.EASE_OUT)
	tw.tween_property(model, "rotation:x", 0.0, 0.4 / p).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		if state == "hit":
			state = "idle")


func die() -> void:
	if is_dead():
		return
	path.clear()
	_then = Callable()
	_yaw_goal = NAN
	state = "dead"
	# One of its deaths, at random (the spearman falls three ways).
	var deaths: Array = profile.get("deaths", []).filter(func(c): return clips.has(c))
	_play(deaths[_rng.randi_range(0, deaths.size() - 1)] if not deaths.is_empty() else profile.get("death", "death"), 0.12)


func revive() -> void:
	state = "idle"
	path.clear()
	stance = ""
	_play(idle_clip(), 0.5)


## Any clip, once (a looping clip until the next order).
func play_clip(c: String) -> void:
	if not clips.has(c):
		return
	path.clear()
	_then = Callable()
	_yaw_goal = NAN
	if c == profile.get("death", "death") or c in profile.get("deaths", []):
		path.clear()
		state = "dead"
		_play(c, 0.12)
		player.seek(0.0, true)
		return
	state = "clip"
	_play(c, 0.15)
	player.seek(0.0, true)


func toggle_stance(s: String) -> void:
	if is_dead() or not clips.has(s):
		return
	stance = "" if stance == s else s
	path.clear()
	state = "idle"
	_play(idle_clip(), 0.3)


## One frame of a clip, held (for review captures).
func pose_at(c: String, seconds: float) -> void:
	if not clips.has(c):
		return
	state = "pose"
	_clip = c
	player.play(clips[c].anim, 0.0)
	player.seek(seconds, true)
	player.pause()
	if fx:
		fx.preview(clips[c].anim, seconds)


func set_fx(on: bool) -> void:
	if fx:
		fx.enabled = on
		if not on:
			fx.clear()


func _on_finished(_anim: StringName) -> void:
	match state:
		"attack":
			# A shot is followed by its reload (the crossbowman's bolt comes back).
			var then := String(_attack.get("then", ""))
			if then != "" and clips.has(then):
				state = "clip"
				_play(then, 0.15)
			else:
				state = "idle"
				_play(idle_clip(), 0.25)
		"hit", "clip":
			state = "idle"
			_play(idle_clip(), 0.25)
		"idle":
			# An idle variant played out: back to the idle.
			if _clip != idle_clip():
				_play(idle_clip(), 0.3)


# --- Frame ------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if player == null or state == "pose":
		return
	var sdt := dt * playback
	if state != "walk":
		speed_now = 0.0
	_events_tick()
	if not is_nan(_yaw_goal):
		rotation.y = rotate_toward(rotation.y, _yaw_goal, TURN_RATE * sdt)
		if absf(angle_difference(rotation.y, _yaw_goal)) < 1e-3:
			_yaw_goal = NAN
			var t := _after_turn
			_after_turn = Callable()
			if t.is_valid():
				t.call()
	match state:
		"walk":
			_walk(sdt)
		"idle":
			if stance == "" and _clip == idle_clip():
				_variant_in -= sdt
				var variants: Array = meta.get("variants", {}).get("idle", {}).get("clips", profile.get("idle_variants", []))
				if _variant_in <= 0.0 and not variants.is_empty():
					var v: String = variants[_rng.randi_range(0, variants.size() - 1)]
					if clips.has(v):
						_play(v, 0.3)
					else:
						_variant_in = 30.0


func _events_tick() -> void:
	if not clips.has(_clip) or not player.is_playing():
		return
	var t := player.current_animation_position
	var evs: Array = clips[_clip].events
	if t < _prev_t:
		_ev_i = 0
	while _ev_i < evs.size() and t >= evs[_ev_i][0]:
		clip_event.emit(evs[_ev_i][1])
		_ev_i += 1
	if state == "attack":
		while not _hits.is_empty() and t >= _hits[0]:
			_hits.pop_front()
			_strike_now()
	_prev_t = t


func _walk(sdt: float) -> void:
	if path.is_empty():
		_arrive()
		return
	var to: Vector3 = path[0] - position
	to.y = 0
	var dist := to.length()
	if dist < 1e-3:
		path.pop_front()
		return
	var goal := atan2(to.x, to.z)
	rotation.y = rotate_toward(rotation.y, goal, STEER_RATE * sdt)
	# Sharp corners are turned nearly on the spot: no gliding sideways.
	var off := absf(angle_difference(rotation.y, goal))
	var spd := walk_speed() * clampf(1.0 - (off - 0.35) / 1.1, 0.12, 1.0)
	var step := spd * sdt
	if step >= dist:
		position = Vector3(path[0].x, position.y, path[0].z)
		path.pop_front()
		if path.is_empty():
			_arrive()
	else:
		position += to / dist * step
	speed_now = spd
	# The stride keeps pace with the ground covered.
	player.speed_scale = playback * clampf(spd / walk_speed(), 0.35, 1.0)
