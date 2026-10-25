## The succubus's whip-slash effects, for the sandbox (a look test, not the
## game's fx). Each strike of her attack (the sidecar's events.strikes) leaves:
##   slash  the crescent the outer half of the lash sweeps round the strike, laid
##          in world space as the clip passes it: widest at the strike, pointed
##          at both ends; each piece closes onto the outer edge (the tip's path)
##          as it fades, the oldest first (SMEAR_LIFE)
##   crack  at the tip at the strike: a cel star, a shock ring and streaks
##   slap   where the tip touches the ground within 0.12 s of a strike: a dust
##          ring and puffs (none in the current attack: both cracks are in the air)
## and a short trail behind the tip while the lash is out and fast.
## The lash's path is sampled from the clip once (PATH_HZ) and shared by every
## succubus, so the shapes follow the frames on screen at any playback speed,
## and a held pose (preview) shows exactly what live play shows at that time.
## Lifecycle: nothing spawns unless the attack clip plays past it; another clip
## stops it at once and what is out fades where it is; a replay starts clean.
## Timing is clip time: the effects slow down with the playback speed.
## One immediate mesh, rebuilt only while something is alive.
extends MeshInstance3D

const SHADER := preload("res://prototypes/footman_anim/shaders/whip_fx.gdshader")
const PATH_HZ := 240.0
const SEG := 0.125          # a lash bone's length (rig_succubus.py LASH_L / LASH_N)
const INNER_U := 0.5        # the crescent's inner edge, of the lash from the hand
const LEAD_MAX := 0.12      # the sweep before and after a strike, at most (s);
const TAIL_MAX := 0.06      #   it stops where the tip turns back
const SMEAR_LIFE := 0.22    # from a piece of the crescent being laid to closed (s)
const MIN_W := 0.3          # the crescent's least width across its path on screen (m),
                            #   for a sweep seen edge-on
const STAR_R := 0.4
const STAR_LIFE := 0.16
const RING_R := Vector2(0.12, 0.65)
const RING_LIFE := 0.24
const STREAKS := 6
const STREAK_LIFE := 0.16
const GROUND_H := 0.25      # the tip this low after a strike slaps the ground (m)
const DUST_LIFE := 0.42
const TRAIL_S := 0.05
const TRAIL_W := 0.035
const TRAIL_SPEED := 15.0   # the trail shows above this tip speed (m/s)

## One sampled path per animation, shared: {anim: {t0, inner, tip, vel, shown, strikes}}.
static var _cache := {}

var enabled := true
var who: Node3D
var player: AnimationPlayer
var clip := ""
var path := {}
var _clock := 0.0
var _last_t := -1.0
var _trail_t := -1.0
var _frozen := false
var _drawn := false
var _rev: Array = []        # per strike: the last path sample laid, -1 none
var _done: Array = []       # per strike: [crack spawned, slap spawned]
var _live := {}             # strike -> its growing slash
var _slashes: Array = []    # {pts: [[time, inner, outer, width], ...]}
var _bursts: Array = []     # {kind: "crack" | "slap", born, at, dir, rays}
var _rng := RandomNumberGenerator.new()


func setup(owner_node: Node3D, sk: Skeleton3D, ap: AnimationPlayer, anim: String, events: Dictionary, fps := 30.0) -> void:
	who = owner_node
	player = ap
	clip = anim
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = ImmediateMesh.new()
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.render_priority = 1
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	process_priority = 1    # after the AnimationPlayer has posed her this frame
	_rng.seed = 5501
	if not _cache.has(anim):
		_cache[anim] = _sample(sk, events, fps)
	path = _cache[anim]
	_reset_strikes()


## The lash's hand-side point (INNER_U) and tip per PATH_HZ step over the time
## it is out, in her own space, and each strike's sweep: from where the tip
## starts towards the strike's direction to where it turns away (at most
## LEAD_MAX / TAIL_MAX), and when it comes within GROUND_H of the ground in
## the 0.12 s after it, if it does.
## Strike times are put back on the clip's frames (the sidecar rounds them).
func _sample(sk: Skeleton3D, events: Dictionary, fps: float) -> Dictionary:
	var bones: Array = []
	for i in 16:
		bones.append(sk.find_bone("Lash_%d" % (i + 1)))
	var strikes: Array = events.get("strikes", [])
	if bones.has(-1) or strikes.is_empty():
		return {}
	var to_her := who.global_transform.affine_inverse() * sk.global_transform
	var t0 := float(events.get("lash_out", strikes[0])) - 0.2
	var t1 := float(events.get("lash_in", strikes[-1])) + 0.3
	var n := int((t1 - t0) * PATH_HZ) + 1
	var inner := PackedVector3Array()
	var tip := PackedVector3Array()
	var shown := PackedFloat32Array()
	player.play(clip, 0.0)
	for j in n:
		player.seek(t0 + j / PATH_HZ, true)
		var pts := PackedVector3Array()
		for b in bones:
			pts.append(to_her * sk.get_bone_global_pose(b).origin)
		var last := sk.get_bone_global_pose(bones[15])
		pts.append(to_her * (last.origin + last.basis.y * SEG))
		var k := INNER_U * 16.0
		inner.append(pts[int(k)].lerp(pts[int(k) + 1], k - int(k)))
		tip.append(pts[16])
		shown.append(sk.get_bone_pose_scale(bones[0]).x)
	player.stop()
	var vel := PackedVector3Array()
	for j in n:
		vel.append((tip[mini(j + 1, n - 1)] - tip[maxi(j - 1, 0)]) * PATH_HZ / float(mini(j + 1, n - 1) - maxi(j - 1, 0)))
	var out: Array = []
	for c0 in strikes:
		var c := roundf(float(c0) * fps) / fps
		var i := clampi(roundi((c - t0) * PATH_HZ), 1, n - 2)
		var vc := vel[i].normalized()
		var a := i
		while a > 1 and (i - a + 1) / PATH_HZ <= LEAD_MAX and vel[a - 1].dot(vc) > 0.0:
			a -= 1
		var b := i
		while b < n - 2 and (b + 1 - i) / PATH_HZ <= TAIL_MAX and vel[b + 1].dot(vc) > 0.0:
			b += 1
		var g := -1
		for j in range(i, mini(n, i + int(0.12 * PATH_HZ))):
			if tip[j].y < GROUND_H:
				g = j
				break
		out.append({"at": c, "i": i, "a": a, "b": b, "g": g})
	return {"t0": t0, "inner": inner, "tip": tip, "vel": vel, "shown": shown, "strikes": out}


func _time(j: int) -> float:
	return path.t0 + j / PATH_HZ


func _reset_strikes() -> void:
	_rev = []
	_done = []
	_live = {}
	for s in path.get("strikes", []):
		_rev.append(-1)
		_done.append([false, false])


## Her clip changed (succubus3d.play): a new attack starts clean; any other clip
## stops what is growing, and what is out fades where it is.
func on_play(anim: String) -> void:
	_frozen = false
	_last_t = -1.0
	_trail_t = -1.0
	_reset_strikes()


## The effects at a held time of a clip (succubus3d.pose_at), as live play
## would show them at that moment.
func preview(anim: String, t: float) -> void:
	clear()
	_frozen = true
	if anim != clip or not enabled or path.is_empty():
		return
	_reset_strikes()
	_clock = t
	_advance(t, true)
	_trail_t = t
	_build()


func clear() -> void:
	_slashes.clear()
	_bursts.clear()
	_live = {}
	_trail_t = -1.0
	(mesh as ImmediateMesh).clear_surfaces()
	_drawn = false


func _process(dt: float) -> void:
	if path.is_empty() or _frozen:
		return
	_clock += dt * player.speed_scale
	var t := -1.0
	if enabled and player.is_playing() and player.current_animation == clip:
		t = player.current_animation_position
		_advance(t, false)
	else:
		_live = {}
	_trail_t = t
	_last_t = t
	_build()


## Lay the sweep up to clip time t and spawn the cracks and slaps it has passed.
## Live, a spawn is dropped if the clip is already well past it (a seek);
## catching up for a preview, it is kept while it would still show.
func _advance(t: float, catch_up: bool) -> void:
	var xf := who.global_transform
	var late := DUST_LIFE if catch_up else 0.1
	var strikes: Array = path.strikes
	for k in strikes.size():
		var s: Dictionary = strikes[k]
		var upto := mini(s.b, int(floor((t - path.t0) * PATH_HZ)))
		if upto >= s.a and _rev[k] < s.b and t - _time(s.b) < SMEAR_LIFE:
			if not _live.has(k):
				_live[k] = {"pts": []}
				_slashes.append(_live[k])
			for j in range(maxi(_rev[k] + 1, s.a), upto + 1):
				var u := float(j - s.a) / maxi(s.b - s.a, 1)
				_live[k].pts.append([_clock - (t - _time(j)), xf * path.inner[j], xf * path.tip[j], pow(sin(PI * u), 0.7)])
			_rev[k] = upto
		if not _done[k][0] and t >= s.at and t - s.at < late:
			_done[k][0] = true
			_burst("crack", _clock - (t - s.at), xf * path.tip[s.i], xf.basis * path.vel[s.i])
		if s.g >= 0 and not _done[k][1] and t >= _time(s.g) and t - _time(s.g) < late:
			_done[k][1] = true
			var p: Vector3 = xf * path.tip[s.g]
			_burst("slap", _clock - (t - _time(s.g)), Vector3(p.x, xf.origin.y + 0.02, p.z), xf.basis * path.vel[s.g])


func _burst(kind: String, born: float, at: Vector3, dir: Vector3) -> void:
	var rays: Array = []
	for i in (STREAKS if kind == "crack" else 4):
		rays.append([_rng.randf_range(-1.1, 1.1) + (0.0 if kind == "crack" else i * TAU / 4.0), _rng.randf_range(0.7, 1.3)])
	_bursts.append({"kind": kind, "born": born, "at": at, "dir": dir.normalized() if dir.length() > 1e-4 else Vector3.RIGHT, "rays": rays})


# --- Mesh ---------------------------------------------------------------------

func _build() -> void:
	var im := mesh as ImmediateMesh
	_slashes = _slashes.filter(func(s): return s.pts.size() > 0 and _clock - s.pts[-1][0] < SMEAR_LIFE)
	_bursts = _bursts.filter(func(b): return _clock - b.born < (DUST_LIFE if b.kind == "slap" else RING_LIFE))
	var trail := _trail()
	if _slashes.is_empty() and _bursts.is_empty() and trail.size() < 2:
		if _drawn:
			im.clear_surfaces()
			_drawn = false
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cb := cam.global_basis
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in _slashes:
		_smear(im, s.pts, cb.z)
	_ribbon(im, trail, cb.z)
	for b in _bursts:
		if b.kind == "crack":
			_crack(im, b, cb)
		else:
			_slap(im, b, cb)
	im.surface_end()
	_drawn = true


## The crescent: from each laid sample's outer point (the tip) towards its inner
## point, by its place in the sweep (widest at the strike) and its age, and at
## least MIN_W of that across the tip's path as the camera sees it.
func _smear(im: ImmediateMesh, pts: Array, toward: Vector3) -> void:
	var n := pts.size()
	if n < 2:
		return
	var inner := PackedVector3Array()
	var side := PackedVector3Array()
	var f := PackedFloat32Array()
	var fade := PackedFloat32Array()
	var lean := 0.0
	for j in n:
		var age := _clock - float(pts[j][0])
		var w: float = (1.0 - smoothstep(0.0, SMEAR_LIFE, age)) * pts[j][3]
		var o: Vector3 = pts[j][2]
		var along: Vector3 = pts[mini(j + 1, n - 1)][2] - pts[maxi(j - 1, 0)][2]
		var sd := along.cross(toward).normalized()
		var i: Vector3 = o.lerp(pts[j][1], w)
		inner.append(i)
		side.append(sd * w)
		lean += (i - o).dot(sd)
		f.append(float(j) / (n - 1))
		fade.append(1.0 - smoothstep(SMEAR_LIFE * 0.55, SMEAR_LIFE, age))
	var sgn := 1.0 if lean >= 0.0 else -1.0
	for j in n:
		var o: Vector3 = pts[j][2]
		var d := (inner[j] - o).dot(side[j].normalized()) * sgn
		var least := MIN_W * side[j].length()
		if d < least:
			inner[j] += side[j].normalized() * sgn * (least - d)
	for j in n - 1:
		var h0 := smoothstep(0.7, 1.0, f[j])
		var h1 := smoothstep(0.7, 1.0, f[j + 1])
		_quad(im, [inner[j], pts[j][2], pts[j + 1][2], inner[j + 1]],
			[Vector2(f[j], 0), Vector2(f[j], 1), Vector2(f[j + 1], 1), Vector2(f[j + 1], 0)],
			[Color(0, h0, 0, fade[j]), Color(0, h0, 0, fade[j]), Color(0, h1, 0, fade[j + 1]), Color(0, h1, 0, fade[j + 1])])


## The tip's last TRAIL_S of path, [point, fade] from old to new.
func _trail() -> Array:
	if _trail_t < 0.0 or path.is_empty():
		return []
	var xf := who.global_transform
	var j1 := int(floor((_trail_t - path.t0) * PATH_HZ))
	var j0 := j1 - int(TRAIL_S * PATH_HZ)
	var out: Array = []
	for j in range(maxi(j0, 0), mini(j1, path.tip.size() - 1) + 1):
		var a: float = clampf((path.vel[j].length() - TRAIL_SPEED) / 20.0, 0.0, 1.0) * clampf(path.shown[j] * 2.0 - 1.0, 0.0, 1.0)
		out.append([xf * path.tip[j], a])
	return out


## A camera-facing strip through `pts` ([point, fade]), tapering to its old end.
func _ribbon(im: ImmediateMesh, pts: Array, toward: Vector3) -> void:
	var n := pts.size()
	if n < 2:
		return
	var side := PackedVector3Array()
	for j in n:
		var d: Vector3 = pts[mini(j + 1, n - 1)][0] - pts[maxi(j - 1, 0)][0]
		side.append(d.cross(toward).normalized() * TRAIL_W * (float(j) / (n - 1)))
	for j in n - 1:
		var u0 := float(j) / (n - 1)
		var u1 := float(j + 1) / (n - 1)
		var c0 := Color(0.25, 0, 0, pts[j][1])
		var c1 := Color(0.25, 0, 0, pts[j + 1][1])
		_quad(im, [pts[j][0] - side[j], pts[j][0] + side[j], pts[j + 1][0] + side[j + 1], pts[j + 1][0] - side[j + 1]],
			[Vector2(u0, 0), Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0)], [c0, c0, c1, c1])


func _crack(im: ImmediateMesh, b: Dictionary, cb: Basis) -> void:
	var age: float = _clock - b.born
	var dx: Vector3 = b.dir - cb.z * b.dir.dot(cb.z)
	dx = dx.normalized() if dx.length() > 1e-4 else cb.x
	var dy := cb.z.cross(dx)
	if age < STAR_LIFE:
		var k := age / STAR_LIFE
		var size := STAR_R * (lerpf(0.8, 1.2, k / 0.2) if k < 0.2 else lerpf(1.2, 0.0, (k - 0.2) / 0.8))
		_card(im, b.at, dx * size, dy * size, Color(0.5, 0, 0, 1))
	var kr := age / RING_LIFE
	var r := lerpf(RING_R.x, RING_R.y, 1.0 - (1.0 - kr) * (1.0 - kr))
	_card(im, b.at, cb.x * r, cb.y * r, Color(0.75, lerpf(0.35, 0.08, kr), 0, 1.0 - smoothstep(0.5, 1.0, kr)))
	if age < STREAK_LIFE:
		var ks := age / STREAK_LIFE
		for ray in b.rays:
			var d := dx.rotated(cb.z, ray[0])
			var p0: Vector3 = b.at + d * (0.12 + 4.5 * ray[1] * age)
			var p1: Vector3 = p0 + d * 0.3 * ray[1] * (1.0 - ks)
			var w := d.cross(cb.z).normalized() * 0.018
			var c := Color(0.25, 0, 0, 1.0 - ks)
			_quad(im, [p0 - w, p0 + w, p1 + w, p1 - w], [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)], [c, c, c, c])


func _slap(im: ImmediateMesh, b: Dictionary, cb: Basis) -> void:
	var k: float = (_clock - b.born) / DUST_LIFE
	var ease := 1.0 - (1.0 - k) * (1.0 - k)
	var r := lerpf(0.1, 0.7, ease)
	_card(im, b.at, Vector3(r, 0, 0), Vector3(0, 0, r), Color(0.75, lerpf(0.5, 0.1, k), 0, 1.0 - smoothstep(0.55, 1.0, k)))
	for ray in b.rays:
		var d := Vector3(cos(ray[0]), 0, sin(ray[0]))
		var p: Vector3 = b.at + d * (0.15 + 0.9 * ease * ray[1]) + Vector3.UP * (0.08 + 0.25 * k)
		var pr := 0.11 * (1.0 + 0.6 * k) * (1.0 - smoothstep(0.7, 1.0, k))
		_card(im, p, cb.x * pr, cb.y * pr, Color(1, 0, 0, 1.0 - smoothstep(0.6, 1.0, k)))


## A quad centred on `at`, spanned by half-axes `ax` and `ay`, UV -1..1.
func _card(im: ImmediateMesh, at: Vector3, ax: Vector3, ay: Vector3, c: Color) -> void:
	_quad(im, [at - ax - ay, at + ax - ay, at + ax + ay, at - ax + ay],
		[Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)], [c, c, c, c])


func _quad(im: ImmediateMesh, p: Array, uv: Array, c: Array) -> void:
	for i in [0, 1, 2, 0, 2, 3]:
		im.surface_set_color(c[i])
		im.surface_set_uv(uv[i])
		im.surface_add_vertex(p[i])
