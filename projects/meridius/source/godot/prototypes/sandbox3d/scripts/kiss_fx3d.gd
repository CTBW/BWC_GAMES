## The succubus's Sovereign Kiss in the 3D sandbox (fx3d.gd's "kiss"): a pink
## fog heart, ported from the Blender study art/succubus_3d/tools/kiss_heart.py
## (its README section "Sovereign Kiss (fog heart)"), whose constants these are.
## It starts at her clip's kiss_breath event, five frames before kiss_release:
##   breath   puffs gather at her lips; over the last three frames the heart
##            forms there (0.06 to 0.25 m wide)
##   flight   from kiss_release it leaves at 4 m/s, reaches 10 m/s within
##            0.12 s and flies straight at the target's chest (following it),
##            growing to 1.2 m wide when its middle reaches it; a wake streams
##            from its point
##   contact  `land` is called with the target; a veil of fog washes over its
##            chest and the enthrall mark fades in over its head
##   dissolve it flies on through the target, slowing to 1.5 m/s and growing
##            to 1.8 m, eroding into wisps, gone 0.5 s after the contact
## The enthrall mark is a placeholder for the status: it follows the target
## for MARK_HOLD seconds and goes if the target dies. The heart is five cards
## a few centimetres apart towards the camera, so it passes partly in front of
## the target and partly behind it; the puffs are cards too, from a bounded
## pool, and all share two materials (shaders/fog_heart.gdshader). The kiss
## keeps its caster's playback (the sandbox's speed), so it stays on her clip
## in slow motion. A cast cut short before the release lets the heart go.
## A view only: the sandbox decides what the kiss does.
extends Node3D

const SHADER := preload("res://prototypes/sandbox3d/shaders/fog_heart.gdshader")
const HEART_SDF := preload("res://prototypes/sandbox3d/art3d/kiss_heart_sdf.png")
const PUFF_SDF := preload("res://prototypes/sandbox3d/art3d/kiss_puff_sdf.png")

const FPS := 30.0
## Before kiss_release: the breath starts gathering (kiss_breath), and the heart forms.
const BREATH := 5.0 / FPS
const FORM := 3.0 / FPS
const SPEED := 10.0
## m/s as it leaves her lips, and the seconds to reach SPEED.
const LAUNCH := Vector2(4.0, 0.12)
const W_FORM := 0.06
const W_RELEASE := 0.25
const W_HIT := 1.2
const W_END := 1.8
const DISSOLVE := 0.5
const END_SPEED := 1.5
## The fraction of DISSOLVE before it erodes (its back has passed the target).
const ERODE_FROM := 0.12
## Depth step towards the camera: density.
const SLICES := [[-2, 0.35], [-1, 0.45], [0, 0.55], [1, 0.45], [2, 0.35]]
## A depth step, of its width.
const SLICE_GAP := 0.07
## Card width / heart width (room for the halo).
const PAD := 1.45
## Where it passes through the target, of its height (the study's 1.2 m on a 1.8 m stand-in).
const CHEST := 0.67
## KissSocket's length: from her lips to where the heart leaves (shot_from).
const SOCKET := 0.12
## The enthrall mark: how far over the target's head, its width, how long it shows, its fade.
const MARK_UP := 0.35
const MARK_W := 0.34
const MARK_HOLD := 4.0
const MARK_FADE := 0.2
## The contact veil: [seconds after the contact, density, width, erosion].
const VEIL := [[0.0, 0.55, 1.15, 0.25], [1.0 / FPS, 0.5, 1.25, 0.3], [6.0 / FPS, 0.0, 1.5, 0.7]]
const VEIL_NEAR := 0.45
const MAX_CARDS := 260
## The handoff's palette (blender-handoff-fog.md), sRGB.
const PINK := {"raspberry": "#C82777", "rose": "#F44C9D", "main": "#FF82C2", "blush": "#FFC0DF", "pale": "#FFE3F1"}

var _heart_mat: ShaderMaterial
var _puff_mat: ShaderMaterial
var _quad: QuadMesh
var _kisses: Array = []
var _puffs: Array = []
var _marks: Array = []
var _veils: Array = []
var _spare: Array = []
var _cards := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	_heart_mat = _material(HEART_SDF, [[0.0, "raspberry"], [0.06, "raspberry"], [0.12, "rose"], [0.5, "rose"],
		[0.58, "main"], [0.84, "main"], [0.92, "blush"], [1.0, "blush"]], 0.3, Vector2(0.025, 0.035), 0.5, true)
	_puff_mat = _material(PUFF_SDF, [[0.0, "rose"], [0.35, "rose"], [0.6, "main"], [0.95, "blush"], [1.0, "blush"]],
		0.7, Vector2(0.1, 0.18), 0.0, false)


func _material(sdf: Texture2D, stops: Array, depth: float, edge: Vector2, halo: float, heart: bool) -> ShaderMaterial:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(stops.map(func(s): return s[0]))
	g.colors = PackedColorArray(stops.map(func(s): return Color(PINK[s[1]])))
	var bands := GradientTexture1D.new()
	bands.gradient = g
	bands.width = 256
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("sdf", sdf)
	m.set_shader_parameter("bands", bands)
	m.set_shader_parameter("depth", depth)
	m.set_shader_parameter("edge", edge)
	m.set_shader_parameter("halo_k", halo)
	m.set_shader_parameter("heart", heart)
	for c in ["rose", "raspberry", "pale"]:
		var col := Color(PINK[c])
		m.set_shader_parameter(c, Vector3(col.r, col.g, col.b))
	return m


## The heart from `who` (a unit whose sidecar says where it leaves) at
## `target`; `land` is called with the target at the contact.
func launch(who: Node3D, target: Node3D, land: Callable) -> void:
	var from: Vector3 = who.call("missile_from") if who.has_method("missile_from") else Vector3.INF
	if from == Vector3.INF:
		var h: float = who.height_m() if who.has_method("height_m") else 1.8
		from = _at(who) + Vector3(0, h * 0.9, 0) + _facing(who) * 0.3
	var slices := []
	for s in SLICES:
		var n := _card(_heart_mat)
		if n == null:
			break
		slices.append({"node": n, "k": float(s[0]), "w": float(s[1]), "seed": _rng.randf()})
	var k := {"who": who, "target": target, "land": land, "from": from, "t": 0.0, "tick": 0.0, "dist": 0.0,
		"hit": -1.0, "to": _chest(target, who, from), "flat": _facing(who), "pos": from, "prev": from,
		"slices": slices, "w": W_FORM, "d": 0.0, "e": 0.0}
	_kisses.append(k)


func clear() -> void:
	for e in _kisses:
		for s in e.slices:
			_give(s.node)
	for list in [_puffs, _marks, _veils]:
		for e in list:
			_give(e.node)
		list.clear()
	_kisses.clear()


func _process(dt: float) -> void:
	for k in _kisses.duplicate():
		_fly(k, dt * _playback(k.who))
	for p in _puffs.duplicate():
		p.t += dt * p.rate
		var u: float = p.t / p.life
		if u >= 1.0:
			_give(p.node)
			_puffs.erase(p)
			continue
		p.node.position = p.pos + p.vel * p.t
		p.node.scale = Vector3.ONE * lerpf(p.s0, p.s1, 1.0 - (1.0 - u) * (1.0 - u))
		_shade(p.node, p.dens * smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.35, 1.0, u)), lerpf(p.e0, p.e1, u), p.seed)
	for v in _veils.duplicate():
		v.t += dt * v.rate
		if v.t >= VEIL[-1][0]:
			_give(v.node)
			_veils.erase(v)
			continue
		var i := 0
		while v.t > VEIL[i + 1][0]:
			i += 1
		var a: Array = VEIL[i]
		var b: Array = VEIL[i + 1]
		var f: float = (v.t - a[0]) / (b[0] - a[0])
		v.node.position = v.at + _toward_camera() * VEIL_NEAR
		v.node.scale = Vector3.ONE * lerpf(a[2], b[2], f)
		_shade(v.node, lerpf(a[1], b[1], f), lerpf(a[3], b[3], f), 0.37)
	for m in _marks.duplicate():
		m.t += dt * m.rate
		var tg: Node3D = m.target
		if not is_instance_valid(tg) or (tg.has_method("is_dead") and tg.is_dead()) or m.t >= MARK_HOLD:
			_give(m.node)
			_marks.erase(m)
			continue
		var a: float = maxf(m.t, 0.0)
		m.node.visible = m.t >= 0.0
		m.node.position = _at(tg) + Vector3.UP * (_height(tg) + MARK_UP)
		m.node.scale = Vector3.ONE * PAD * MARK_W * (1.0 + 0.06 * sin(TAU * 1.2 * a))
		_shade(m.node, 0.85 * smoothstep(0.0, 0.2, a) * (1.0 - smoothstep(MARK_HOLD - MARK_FADE, MARK_HOLD, m.t)), 0.0, 0.61)


## One kiss's frame: the breath and the forming heart at her lips, then its
## flight, the contact and the dissolve; its puffs every 1/30 s.
func _fly(k: Dictionary, dt: float) -> void:
	var who: Node3D = k.who
	# Before the release the cast can be cut short: the heart goes with it.
	if k.t < BREATH and (not is_instance_valid(who) or (who.has_method("is_dead") and who.is_dead())
			or String(who.get("state")) != "attack"):
		_end(k)
		return
	k.t += dt
	var up := Vector3.UP
	var tf: float = k.t - BREATH
	var fwd: Vector3 = (k.to - k.from).normalized() if k.to.distance_to(k.from) > 1e-3 else _facing(who)
	var phase := "breath"
	if tf < 0.0:
		var f: float = clampf((k.t - (BREATH - FORM)) / FORM, 0.0, 1.0)
		k.pos = k.from
		k.w = lerpf(W_FORM, W_RELEASE, f)
		k.d = f if k.t >= BREATH - FORM else 0.0
	else:
		phase = "flight" if k.hit < 0.0 else "dissolve"
		# The distance flown this frame (since the release), in small steps.
		var t0: float = maxf(tf - dt, 0.0)
		for i in 4:
			var st: float = lerpf(t0, tf, (i + 0.5) / 4.0)
			var v: float = lerpf(SPEED, END_SPEED, minf((st - k.hit) / DISSOLVE, 1.0))
			if k.hit < 0.0:
				v = lerpf(LAUNCH.x, SPEED, smoothstep(0.0, LAUNCH.y, st))
			k.dist += v * (tf - t0) / 4.0
		if k.hit < 0.0:
			var tg: Node3D = k.target
			if tg != null and is_instance_valid(tg):
				k.to = _chest(tg, who, k.from)
			var span: float = maxf(k.from.distance_to(k.to), 1e-3)
			var p: float = minf(k.dist / span, 1.0)
			k.pos = k.from.lerp(k.to, p)
			k.w = lerpf(W_RELEASE, W_HIT, 1.0 - pow(1.0 - p, 1.5))
			k.d = 1.0 - 0.08 * p
			k.e = 0.0
			if k.dist >= span:
				_contact(k, tf)
				phase = "dissolve"
		if k.hit >= 0.0:
			var span: float = k.from.distance_to(k.to)
			var q: float = (tf - k.hit) / DISSOLVE
			if q > 1.0:
				_end(k)
				return
			k.pos = k.to + k.flat * (k.dist - span) + up * 0.18 * q * q
			k.w = lerpf(W_HIT, W_END, 1.0 - (1.0 - q) * (1.0 - q))
			k.d = 0.92 * (1.0 - smoothstep(ERODE_FROM + 0.1, 1.0, q))
			k.e = smoothstep(ERODE_FROM, 0.95, q)
	var back := _toward_camera()
	for s in k.slices:
		var n: MeshInstance3D = s.node
		n.visible = k.d > 0.0
		n.position = k.pos + back * s.k * SLICE_GAP * k.w
		n.scale = Vector3.ONE * k.w * PAD * sqrt(1.0 - pow(s.k / 2.8, 2.0))
		_shade(n, k.d * s.w, k.e, s.seed)
	# The puffs, as the study keys them on each frame.
	var rate := _playback(who)
	k.tick += dt
	while k.tick >= 1.0 / FPS:
		k.tick -= 1.0 / FPS
		var lips: Vector3 = k.from - fwd * SOCKET
		var dirn: Vector3 = k.flat if phase == "dissolve" else fwd
		var w: float = k.w
		if phase == "breath":
			_puff(lips.lerp(k.from, 0.3), fwd * 0.3 + up * 0.1, 6, Vector2(0.05, 0.11), 0.3, Vector2(0.1, 0.6), rate)
		elif tf < 3.0 / FPS:
			# The breath's bridge to the leaving heart.
			for i in 2:
				_puff(lips.lerp(k.pos, _rng.randf_range(0.2, 0.9)), up * 0.15, 6, Vector2(0.09, 0.16), 0.35, Vector2(0.1, 0.6), rate)
		if phase == "flight" or (phase == "dissolve" and tf - k.hit <= 4.0 / FPS):
			# The wake: a tapering streak from its point back along its path.
			for i in 3:
				var at: Vector3 = k.prev.lerp(k.pos, (i + 1) / 3.0) - dirn * 0.3 * w - up * 0.15 * w + _jitter(0.06 * w)
				_puff(at, -dirn * 0.6 + up * 0.15 + _jitter(0.15), 7, Vector2(0.55 * w, 0.2 * w), 0.5 * k.d, Vector2(0.1, 0.5), rate)
		if phase == "dissolve" and k.e > 0.02:
			# The wisps it sheds.
			for i in 2:
				var j := _jitter(0.4 * w)
				_puff(k.pos + j, j * 1.2 + dirn * 1.2 + up * 0.35, 14, Vector2(0.35 * w, 0.7 * w), 0.32 * minf(1.0, 3.0 * k.e),
					Vector2(0.3, 0.9), rate)
		k.prev = k.pos


## Its middle reaches the target's chest: the target is told, the veil
## washes over it and the mark follows it from 0.1 s on.
func _contact(k: Dictionary, tf: float) -> void:
	k.hit = tf
	var d: Vector3 = k.to - k.from
	k.flat = Vector3(d.x, 0, d.z).normalized() if Vector2(d.x, d.z).length() > 1e-3 else _facing(k.who)
	var rate := _playback(k.who)
	var veil := _card(_puff_mat)
	if veil:
		_veils.append({"node": veil, "t": 0.0, "at": k.to, "rate": rate})
	var tg: Node3D = k.target
	if tg != null and is_instance_valid(tg):
		for m in _marks.duplicate():
			if m.target == tg:
				_give(m.node)
				_marks.erase(m)
		var mark := _card(_heart_mat)
		if mark:
			mark.visible = false
			_marks.append({"node": mark, "target": tg, "t": -3.0 / FPS, "rate": rate})
		if k.land.is_valid():
			k.land.call(tg)


func _end(k: Dictionary) -> void:
	for s in k.slices:
		_give(s.node)
	_kisses.erase(k)


func _puff(at: Vector3, vel: Vector3, frames: int, size: Vector2, dens: float, ero: Vector2, rate: float) -> void:
	var n := _card(_puff_mat)
	if n == null:
		return
	n.position = at
	n.scale = Vector3.ONE * size.x
	_shade(n, 0.0, ero.x, 0.0)
	_puffs.append({"node": n, "t": 0.0, "life": frames / FPS, "pos": at, "vel": vel, "s0": size.x, "s1": size.y,
		"dens": dens, "e0": ero.x, "e1": ero.y, "seed": _rng.randf(), "rate": rate})


## A card from the pool (null when MAX_CARDS are out): a 1 m quad the shader
## turns to the camera.
func _card(mat: ShaderMaterial) -> MeshInstance3D:
	var n: MeshInstance3D
	if not _spare.is_empty():
		n = _spare.pop_back()
	elif _cards < MAX_CARDS:
		n = MeshInstance3D.new()
		n.mesh = _quad
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The quad's box is flat; turned to the camera it reaches out of it.
		n.extra_cull_margin = 0.75
		add_child(n)
		_cards += 1
	else:
		return null
	n.material_override = mat
	n.visible = true
	return n


func _give(n: MeshInstance3D) -> void:
	n.visible = false
	_spare.append(n)


func _shade(n: MeshInstance3D, density: float, erosion: float, seed: float) -> void:
	n.set_instance_shader_parameter("density", density)
	n.set_instance_shader_parameter("erosion", erosion)
	n.set_instance_shader_parameter("seed", seed)


func _chest(target: Node3D, who: Node3D, from: Vector3) -> Vector3:
	if target != null and is_instance_valid(target):
		return _at(target) + Vector3.UP * _height(target) * CHEST
	return from + _facing(who) * 5.0 + Vector3.DOWN * 0.4


func _height(n: Node3D) -> float:
	return n.height_m() if n.has_method("height_m") else 1.6


func _playback(who: Node3D) -> float:
	return maxf(float(who.get("playback")), 0.05) if is_instance_valid(who) and who.get("playback") != null else 1.0


func _toward_camera() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam.global_basis.z if cam else Vector3(0, 0.5, 0.866)


## Where a unit stands, and which way it faces (its own transform outside the tree).
func _at(n: Node3D) -> Vector3:
	return n.global_position if n.is_inside_tree() else n.position


func _facing(n: Node3D) -> Vector3:
	if not is_instance_valid(n):
		return Vector3.FORWARD
	var yaw := n.global_rotation.y if n.is_inside_tree() else n.rotation.y
	return Vector3(sin(yaw), 0, cos(yaw))


## A point in a ball of radius r.
func _jitter(r: float) -> Vector3:
	var v := Vector3.ONE
	while v.length() > 1.0:
		v = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
	return v * r
