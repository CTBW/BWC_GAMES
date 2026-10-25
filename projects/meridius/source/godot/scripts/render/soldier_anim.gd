## Frame-by-frame soldiers: pixel-art figures with frames of their own
## (assets/sprites/anim/<type>.json and .png; the footman's built from the
## Higgsfield keyframes by tools/anim/build_footman.py, the other squads' by
## tools/anim/squadgen.py). A figure without a table keeps the original's
## single poses from assets.gd.
##
## Each man of a squad keeps his own rhythm: he breathes, steps and strikes on
## a beat of his own taken from his `phase`, starts and stops marching a moment
## apart from his mates and trails the squad's anchor a little when it moves,
## so six men read as a drilled squad, not one cut-out. Presentation only:
## nothing here feeds back into the rules.
##
## Use through `const SoldierAnim = preload("res://scripts/render/soldier_anim.gd")`.
##   SoldierAnim.animated(type)             this figure has frames
##   SoldierAnim.pose(uv, m, time)          {ms, bob, lean, sx, sy, dx, dy, breath, bend} for a standing soldier
##   SoldierAnim.gait(type)                 the type's walk and idle values (assets/sprites/anim/_gait.json)
##   SoldierAnim.fall(uv, m)                {ms, next, mix} for a falling one
##   SoldierAnim.corpse(type, v), corpse_flip(facing)
##   SoldierAnim.melee_beat(i, front, m)    one man's timing in a melee blow
##   SoldierAnim.step_drift(uv, dt, at)     the men's lag behind a moving anchor
##   SoldierAnim.footfalls(uv, m, dt)       feet he set down in the last dt of the march (sound)
## `ms` is the array battle_draw blits: [sprite, flip, tex, rect, region, scale]
## (frame_ms), built once per frame when the frames load.
extends RefCounted

const Rng = preload("res://scripts/core/rng.gd")
const Formation = preload("res://scripts/render/formation.gd")

const DIR := "res://assets/sprites/anim/"
const GAIT_FILE := "res://assets/sprites/anim/_gait.json"

## Seconds a breath frame shows (the loop is 0 1 2 1).
const IDLE_FRAME := 0.42
## Seconds for one walk cycle (two steps) on the march, and the routers' haste.
const STRIDE := 0.44
const ROUT_HASTE := 1.45
## World px the body rises over the passing step.
const BOB := 2.6
## Seconds from the blow to lying still.
const DEATH := 0.95
## Fractions of the fall: still standing (the recoil), kneeling, then down.
const RECOIL := 0.1
const KNEEL := 0.42
## From behind, the slump settles into the body left on the field over this last part.
const SETTLE := 0.72
## How quickly a man catches up with the anchor (1/s): the range across the squad.
const CATCH_UP := Vector2(16.0, 30.0)
const MAX_DRIFT := 14.0

static var _sets: Dictionary = {}
static var _has: Dictionary = {}
static var _gaits: Dictionary = {}
static var _gait_doc: Variant = null


## How a figure walks and stands: assets/sprites/anim/_gait.json's "default",
## then the type's entry ("like" copies another type's first). Cached.
static func gait(type: String) -> Dictionary:
	var g: Variant = _gaits.get(type)
	if g != null:
		return g
	if _gait_doc == null:
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(GAIT_FILE)) if FileAccess.file_exists(GAIT_FILE) else null
		_gait_doc = doc if doc is Dictionary else {"default": {}, "types": {}}
	var out: Dictionary = {"stride": STRIDE, "pace": 1.0, "bounce": BOB, "waddle": 0.03, "squash": 0.035, "stretch": 0.02,
		"surge": 2.4, "lean": 0.035, "kick": 0.07, "jitter": 0.0, "tempo": 0.1, "stomp": 0.3, "spring": 240.0, "damp": 0.5,
		"breath": 0.016, "breath_rate": 0.28, "sway": 0.8, "bend": 0.006, "fidget": 9.0, "dust": 1.0,
		"march": 1.0, "rig": 1.0, "duty": 0.6, "step": 0.16, "lift": 0.035, "hip": 0.45, "knee": 0.14}
	out.merge(_gait_doc.get("default", {}), true)
	var types: Dictionary = _gait_doc.get("types", {})
	var own: Dictionary = types.get(type, {})
	var like = own.get("like")
	if like != null and types.has(like):
		out.merge(types[like], true)
	out.merge(own, true)
	out.erase("like")
	for k in out.keys():
		out[k] = float(out[k])
	_gaits[type] = out
	return out


## Indices of gait_values().
enum G { STRIDE, BOUNCE, WADDLE, SQUASH, STRETCH, SURGE, LEAN, KICK, JITTER, TEMPO, BREATH, BREATH_RATE, SWAY, BEND, FIDGET, RIG, DUTY, STEP, LIFT }
static var _gvals: Dictionary = {}


## The gait as a packed array (G indices) for pose(), which runs for every soldier every frame.
static func gait_values(type: String) -> PackedFloat64Array:
	var v: Variant = _gvals.get(type)
	if v != null:
		return v
	var g := gait(type)
	var a := PackedFloat64Array([g.stride, g.bounce, g.waddle, g.squash, g.stretch, g.surge, g.lean, g.kick, g.jitter,
		g.tempo, g.breath, g.breath_rate, g.sway, g.bend, g.fidget, g.rig, g.duty, g.step, g.lift])
	_gvals[type] = a
	return a


static func animated(type: String) -> bool:
	var h: Variant = _has.get(type)
	if h == null:
		# The table and its imported atlas: a freshly built atlas has import settings
		# but no imported texture until tools/import.sh runs.
		h = type != "" and FileAccess.file_exists(DIR + type + ".json") and _imported(DIR + type + ".png")
		_has[type] = h
	return h


static func _imported(png: String) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(png + ".import") != OK:
		return false
	var dest := String(cfg.get_value("remap", "path", ""))
	return dest != "" and FileAccess.file_exists(dest)


static func death_duration(type: String) -> float:
	return DEATH if animated(type) else 0.5


## A frame of one soldier (0..5) as an assets.gd sprite dictionary.
static func frame(type: String, name: String, soldier: int) -> Dictionary:
	var list: Array = _table(type).frames.get(name, [])
	if list.is_empty():
		push_error("SoldierAnim: no frame '%s' for %s" % [name, type])
		return {}
	return list[absi(soldier) % list.size()]


## The same frame as the array battle_draw blits, mirrored or not.
static func frame_ms(type: String, name: String, soldier: int, flip: bool) -> Array:
	var list: Array = _table(type).blits.get(name, [])
	if list.is_empty():
		push_error("SoldierAnim: no frame '%s' for %s" % [name, type])
		return [{}, flip, null, Rect2(), Rect2(), 1.0]
	return list[absi(soldier) % list.size()][1 if flip else 0]


## Load a type's frames now (the atlas otherwise loads on first use).
static func warm(type: String) -> void:
	if animated(type):
		_table(type)


static func _table(type: String) -> Dictionary:
	var table: Variant = _sets.get(type)
	if table != null:
		return table
	var path := DIR + type + ".json"
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	table = {"frames": {}, "blits": {}, "shield": true, "by_facing": [[[], [], [], [], [], []], [[], [], [], [], [], []], [[], [], [], [], [], []], [[], [], [], [], [], []]]}
	if not doc is Dictionary:
		push_error("SoldierAnim: cannot read %s" % path)
		_sets[type] = table
		return table
	var file := String(doc.file)
	var tex := load(file) as Texture2D
	var scale := float(doc.scale)
	# Figures without a shield have no drawings of their own for the mirrored facings.
	table.shield = (doc.get("facings", ["f", "fs", "b", "bs"]) as Array).has("fs")
	for name in doc.frames:
		var list: Array = []
		var blits: Array = []
		var i := 0
		for e in doc.frames[name]:
			var r: Array = e.region
			var sp := {
				"key": "%s_%s" % [type, name], "v": i, "file": file, "tex": tex,
				"region": Rect2(r[0], r[1], r[2], r[3]), "ax": float(e.ax), "ay": float(e.ay),
				"scale": scale * float(e.get("k", 1.0)), "w": int(r[2]), "h": int(r[3]), "noShadow": false, "art": true,
			}
			list.append(sp)
			var rect := Rect2(-sp.ax, -sp.ay, sp.w, sp.h)
			# The frame's middle row in atlas UV: the breathing shader tells its top from its feet by it.
			var mid_v: float = (float(r[1]) + float(r[3]) * 0.5) / maxf(1.0, float(tex.get_height())) if tex != null else 0.5
			# A standing back view walks its own legs (pose(), battle_draw._blit_rig).
			var mesh: Variant = _rig_mesh(e.rig, rect, sp.region, tex.get_size(), gait(type)) if e.has("rig") and tex != null else null
			blits.append([[sp, false, tex, rect, sp.region, sp.scale, mid_v, mesh], [sp, true, tex, rect, sp.region, sp.scale, mid_v, mesh]])
			i += 1
		table.frames[name] = list
		table.blits[name] = blits
	# The frames pose() picks from, by facing (0..3, the game's grid facings),
	# so the hot path builds no names: [idle, walk 0..2, wind, hit] blit lists
	# with the mirroring already chosen.
	var by_facing: Array = []
	for f in 4:
		var suf := ("f" if Formation.faces_camera(f) else "b") + ("s" if flip_of(f) and table.shield else "")
		var flip := 1 if flip_of(f) else 0
		var pick := func(n: String) -> Array:
			var b: Array = table.blits.get(n, [])
			var out: Array = []
			for e in b:
				out.append(e[flip])
			return out
		by_facing.append([pick.call("idle_%s_0" % suf), pick.call("walk_%s_0" % suf), pick.call("walk_%s_1" % suf),
			pick.call("walk_%s_2" % suf), pick.call("strike_%s_wind" % suf), pick.call("strike_%s_hit" % suf)])
	table.by_facing = by_facing
	_sets[type] = table
	return table


## Half the width of the seam between the legs, over which the two sides'
## motions blend (source px), and how far beyond the feet the cloth still
## follows them fully and then not at all (shares of the figure's height):
## a spear's butt or a staff's foot further out stays where it is.
const RIG_SEAM := 3.0
const RIG_MARGIN := 0.07
const RIG_RAMP := 0.07


## The mesh a standing back view is drawn with on the march (tools/anim/rig.py
## measured its feet): [columns x, rows y, left weights, right weights, row
## weights, uvs, indices], in the frame's local px (feet at 0, 0). Above the
## hips the body is carried whole; from the hips to the knees each side comes
## to follow its own foot; below the knees it goes with the foot entirely.
static func _rig_mesh(rig: Dictionary, rect: Rect2, region: Rect2, tex_size: Vector2, g: Dictionary) -> Array:
	var seam: float = rig.seam
	var lo: float = float(rig.span[0])
	var hi: float = float(rig.span[1])
	var h := rect.size.y
	var mg := RIG_MARGIN * h
	var rp := RIG_RAMP * h
	var x0 := rect.position.x
	var x1 := rect.end.x
	var want := [x0, lo - mg - rp, lo - mg, seam - RIG_SEAM, seam + RIG_SEAM, hi + mg, hi + mg + rp, x1]
	var xs := PackedFloat32Array()
	var wl := PackedFloat32Array()
	var wr := PackedFloat32Array()
	for x in want:
		# Inside the frame and in order: columns past its edge fold onto it.
		var cx := clampf(x, x0, x1)
		if not xs.is_empty() and cx <= xs[xs.size() - 1]:
			cx = xs[xs.size() - 1] + 0.01
		xs.append(cx)
		var out_l := clampf((cx - (lo - mg - rp)) / rp, 0.0, 1.0)
		var out_r := clampf(((hi + mg + rp) - cx) / rp, 0.0, 1.0)
		var side := clampf((seam + RIG_SEAM - cx) / (2.0 * RIG_SEAM), 0.0, 1.0)
		wl.append(out_l * side)
		wr.append(out_r * (1.0 - side))
	var bottom := rect.end.y
	var hip := bottom - h * float(g.hip)
	var knee := bottom - h * float(g.knee)
	var ys := PackedFloat32Array([rect.position.y, hip, lerpf(hip, knee, 1.0 / 3.0), lerpf(hip, knee, 2.0 / 3.0), knee, bottom])
	var fr := PackedFloat32Array([0.0, 0.0, smoothstep(0.0, 1.0, 1.0 / 3.0), smoothstep(0.0, 1.0, 2.0 / 3.0), 1.0, 1.0])
	var uvs := PackedVector2Array()
	for y in ys:
		for x in xs:
			uvs.append((region.position + Vector2(x, y) - rect.position) / tex_size)
	var idx := PackedInt32Array()
	var nc := xs.size()
	for r in ys.size() - 1:
		for c in nc - 1:
			var i := r * nc + c
			idx.append_array([i, i + 1, i + nc + 1, i, i + nc + 1, i + nc])
	return [xs, ys, wl, wr, fr, uvs, idx]


## A frame of the type's per-facing table (see _table): F_IDLE, F_WALK + 0..2, F_WIND, F_HIT.
const F_IDLE := 0
const F_WALK := 1
const F_WIND := 4
const F_HIT := 5


## Frame-name suffix and mirroring for a facing: +y shows the front (true
## south-west), -y the back (north-east); +x and -x are mirrored, with the
## shield-leading drawings where the figure has them (battle_view.pose_key's rule).
static func suffix(facing: int, type: String) -> String:
	var flip := facing == 0 or facing == 2
	return ("f" if Formation.faces_camera(facing) else "b") + ("s" if flip and _table(type).shield else "")


static func flip_of(facing: int) -> bool:
	return facing == 0 or facing == 2


## The way a man is drawn turned: toward the enemy he fights, else his squad's facing.
static func facing_of(uv, m) -> int:
	return m.face if m.face >= 0 else uv.facing


## Turn the men toward a grid facing for a blow or a volley, each on his own beat
## (front of `order` first); turn_back() returns them to the squad's facing.
static func turn_to(uv, order: Array, facing: int) -> void:
	if facing == uv.facing:
		return
	for i in order.size():
		var m = order[i]
		m.face_next = facing
		m.face_t = 0.0
		m.face_wait = 0.015 + 0.03 * i + fposmod(m.phase * 0.53, 0.03)


static func turn_back(order: Array) -> void:
	for i in order.size():
		var m = order[i]
		m.face_wait = 0.0
		if m.face >= 0:
			# One by one, as they step back into the line.
			m.face_t = 0.12 + 0.07 * i + fposmod(m.phase * 0.37, 0.12)


## A soldier's own beat: x = tempo (around 1, spread by the gait's `tempo`),
## y = offset in a cycle (0..1), z = the moment he joins a march or a halt (0..1).
## Cached on the member with his gait.
static func rhythm(m) -> Vector3:
	if m.gv.is_empty():
		_prime(m)
	return m.rh


## Indices of a member's own idle constants (m.pc).
const P_FIDGET := 0
const P_BREATH := 1
const P_SWAY := 2


## Cache on the member what pose() would otherwise work out every frame: his
## gait, beat, idle constants and the frames of his type by facing.
static func _prime(m) -> void:
	var gv := gait_values(m.type)
	var p: float = m.phase
	m.gv = gv
	m.rh = Vector3(1.0 + gv[G.TEMPO] * (2.0 * fposmod(p * 1.731, 1.0) - 1.0), fposmod(p / TAU + m.id * 0.37, 1.0), fposmod(p * 2.917 + m.id * 0.23, 1.0))
	# His fidget interval, breathing rate and sway speed.
	m.pc = PackedFloat64Array([gv[G.FIDGET] * (0.7 + 0.6 * fposmod(p * 0.913, 1.0)),
		gv[G.BREATH_RATE] * (0.85 + 0.3 * fposmod(p * 0.618, 1.0)), 0.5 + 0.25 * fposmod(p * 0.37, 1.0)])
	m.fb = _table(m.type).by_facing


## Where a man is in his stride: cycles of two steps since the march began, on
## his own tempo and offset, unevenly for scrambling figures (jitter). Each step
## (half a cycle) lands at a quarter of it: u = 0.25.
static func gait_phase(uv, m, clock: float) -> float:
	var r := rhythm(m)
	var gv: PackedFloat64Array = m.gv
	var g: float = clock / gv[G.STRIDE] * r.x * (ROUT_HASTE if uv.routing else 1.0) + r.y
	var jit: float = gv[G.JITTER]
	if jit > 0:
		# Scrambling: steps come early and late (never backwards: the slope stays positive).
		g += jit * 0.045 * (sin(clock * 9.7 + m.phase * 3.1) + 0.6 * sin(clock * 15.3 + m.phase * 1.7))
	return g


## Facing a man glances toward in an idle fidget: the drawing turned the other way.
const GLANCE := [1, 0, 3, 2]
const NO_FRAME := [{}, false, null, Rect2(), Rect2(), 1.0, 0.5]


## What a standing soldier shows this frame (one result per member, reused):
##   ms      the blit array            bob     world px up (the shadow stays down)
##   lean    radians (whole figure, about the feet)
##   sx, sy  squash and stretch about the feet
##   dx, dy  ground offset (the stride's surge, weight shifting): shadows follow it
##   breath  upper-body sink for the breathing shader (0 or negative), bend its lean
## It runs for every man in view every frame: keep it free of names and new
## dictionaries (the per-man constants come from _prime).
static func pose(uv, m, time: float) -> Dictionary:
	var out: Dictionary
	if m.pose_cache == null:
		out = {"ms": NO_FRAME, "bob": 0.0, "lean": 0.0, "sx": 1.0, "sy": 1.0, "dx": 0.0, "dy": 0.0, "breath": 0.0, "bend": 0.0,
			"rig": false, "legs": Vector4.ZERO, "lift": 0.0}
		m.pose_cache = out
	else:
		out = m.pose_cache
		if m.pose_t == time:
			return out
	m.pose_t = time
	if m.gv.is_empty():
		_prime(m)
	var r: Vector3 = m.rh
	var gv: PackedFloat64Array = m.gv
	var face: int = m.face
	var facing: int = face if face >= 0 else uv.facing
	var routing: bool = uv.routing
	var walking: float = uv.walking
	var heading: Vector2 = uv.heading
	var bob := 0.0
	var lean := 0.0
	var sx := 1.0
	var sy := 1.0
	var dx := 0.0
	var dy := 0.0
	var breath := 0.0
	var bend := 0.0
	var slot := F_IDLE
	var rigged := false
	var legs := Vector4.ZERO
	var lift := 0.0
	var fwd := signf(heading.x) if absf(heading.x) > 0.05 else (-1.0 if (facing == 1 or facing == 2) else 1.0)
	# Marching, or stepping into a new place in the ranks; each man joins the
	# march a moment after the order and halts a moment apart.
	var marching: bool = walking > 0.15 + 0.55 * r.z
	if m.pose == "atk":
		slot = F_WIND if m.key == "wind" else F_HIT
	elif marching or (m.t < 1 and m.dur > 0 and m.delay <= 0):
		var w: float = walking if marching else 1.0
		var g := gait_phase(uv, m, uv.walk_t if marching else time)
		var u := fposmod(g * 2.0, 1.0)
		if u >= 0.5:
			slot = F_WALK + 1
		else:
			slot = F_WALK + (2 if fposmod(g, 1.0) >= 0.5 else 0)
		# Two bounces a stride: lowest as a foot lands, highest as the other passes it.
		bob = gv[G.BOUNCE] * (0.5 - 0.5 * cos(TAU * (u - 0.25))) * w
		# Squash on the landing, stretch on the push-off.
		var e1 := (u - 0.25) / 0.075
		var e2 := (u - 0.6) / 0.11
		var land := exp(-e1 * e1) * w
		var push := exp(-e2 * e2) * w
		sy = 1.0 - gv[G.SQUASH] * land + gv[G.STRETCH] * push
		sx = 1.0 + 0.5 * gv[G.SQUASH] * land - 0.4 * gv[G.STRETCH] * push
		# Waddle toward the planted foot, a lean into the march.
		lean = gv[G.WADDLE] * cos(TAU * (g - 0.125)) * w + fwd * gv[G.LEAN] * w * (1.6 if routing else 1.0)
		# Each step pushes the body on: slowest at the landing, fastest at the passing.
		var surge: float = -gv[G.SURGE] * sin(TAU * (u - 0.25)) * w
		dx = heading.x * surge
		dy = heading.y * surge
		# Walking away from the camera, the standing figure walks its own legs
		# (battle_draw._blit_rig): each foot is planted as it lands and held on
		# the ground while the body passes over it, then swung on and lifted.
		if facing >= 2 and gv[G.RIG] > 0.0:
			var e := _pick(m.fb[facing][F_IDLE], m.variant)
			if e.size() > 7 and e[7] != null:
				rigged = true
				slot = F_IDLE
				var hgt: float = e[3].size.y * e[5]
				var duty: float = gv[G.DUTY]
				var reach: float = gv[G.STEP] * hgt
				var amp := reach * 0.4
				if marching:
					# Half the ground the body covers while a foot is down: then it stays put.
					var cyc: float = gv[G.STRIDE] / (r.x * (ROUT_HASTE if routing else 1.0))
					var vb := maxf(0.0, (uv.anchor_vel + m.drift_v).dot(heading))
					amp = minf(vb * duty * cyc * 0.5, reach)
				var up: float = gv[G.LIFT] * hgt
				var off: float = gv[G.SURGE] * w * sin(TAU * 2.0 * duty)
				var fa := _foot(fposmod(g - 0.125, 1.0), duty, amp, up, surge, off)
				var fb := _foot(fposmod(g - 0.625, 1.0), duty, amp, up, surge, off)
				legs = Vector4(heading.x * fa.x, heading.y * fa.x - fa.y, heading.x * fb.x, heading.y * fb.x - fb.y) * w
				# The body rises over the passing step; the feet stay down.
				lift = bob
				bob = 0.0
	else:
		var ph: float = m.phase
		var pc: PackedFloat64Array = m.pc
		# Fidgets, now and then and never together: a glance aside, a shuffle of the
		# feet, a shrug of the shield or weapon. The longest lasts 1.1 s, so most
		# of each man's interval needs no roll at all.
		var period: float = pc[P_FIDGET]
		if period > 0.0:
			var ft := time + ph * 7.0
			var n := floorf(ft / period)
			var lt := ft - n * period
			if lt <= 1.1:
				var fid := _fidget(m, n, lt)
				var kind := int(fid.x)
				if kind == 1:
					facing = GLANCE[facing]
				elif kind == 2:
					slot = F_WALK + (0 if fid.y < 0.5 else 2)
					bob = 1.2 * sin(PI * fid.y)
				elif kind == 3:
					sy = 1.0 - 0.035 * sin(PI * minf(1.0, fid.y * 2.0)) + 0.02 * sin(PI * maxf(0.0, fid.y * 2.0 - 1.0))
					bob = sin(PI * maxf(0.0, fid.y * 2.0 - 1.0))
		# Breathing (the shader sinks the upper body; feet stay put) at his own pace.
		breath = -gv[G.BREATH] * (0.5 - 0.5 * cos(TAU * time * pc[P_BREATH] + ph * 3.0))
		# Weight shifting: a slow sway over the hips, now and then a bigger shift.
		var shift := sin(time * 0.13 + ph * 5.1)
		var weight := sin(time * pc[P_SWAY] + ph * 2.3) * 0.6 + shift * shift * shift * 0.8
		dx = gv[G.SWAY] * weight
		bend = gv[G.BEND] * weight * (-1.0 if (facing == 0 or facing == 2) else 1.0)
		lean = 0.012 * weight
		if routing:
			# Shaken men tremble where they stand.
			lean += sin(time * 31.0 + ph * 5.0) * 0.02
			breath *= 1.8
	# The body lags the squad when it sets off and skids past at the halt: lean with it.
	var lag: Vector2 = m.drift
	if lag.length_squared() > 0.01:
		lean += fwd * clampf(-lag.dot(heading) / 8.0, -1.0, 1.0) * gv[G.KICK]
	# Struck: the body rocks back from the blow.
	var shake: float = m.shake
	if shake > 0:
		lean -= fwd * 0.1 * shake * shake
	out.ms = _pick(m.fb[facing][slot], m.variant)
	out.rig = rigged
	out.legs = legs
	out.lift = lift
	out.bob = bob
	out.lean = lean
	out.sx = sx
	out.sy = sy
	out.dx = dx
	out.dy = dy
	out.breath = breath
	out.bend = bend
	return out


static func _pick(list: Array, variant: int) -> Array:
	return list[absi(variant) % list.size()] if not list.is_empty() else NO_FRAME


## One foot `q` through its cycle (0 as it lands): planted for the first `duty`
## of it, going from `amp` ahead of the hips to `amp` behind them as the body
## passes over (less the stride's `surge`, so it keeps still on the ground),
## then swung forward and lifted `up` on the way, from where it left the
## ground (`off`: the surge as it lifts). Vector2(world px along the march, up).
static func _foot(q: float, duty: float, amp: float, up: float, surge: float, off: float) -> Vector2:
	if q < duty:
		return Vector2(amp * (1.0 - 2.0 * q / duty) - surge, 0.0)
	var k := (q - duty) / (1.0 - duty)
	return Vector2(lerpf(-amp + off, amp, k * k * (3.0 - 2.0 * k)), up * sin(PI * k))


## The idle fidget a man is in: Vector2(kind, k) (kind 0 none; 1 glance, 2
## shuffle, 3 shrug; k = 0..1 through it), `lt` seconds into his `n`th interval.
## Stateless but for a cache of the interval's roll: each man's windows come
## from his phase, at his own mean interval, so no two in a squad fidget together.
static func _fidget(m, n: float, lt: float) -> Vector2:
	var c: Vector3 = m.fid
	if c.x != n:
		var ph: float = m.phase
		var kind := 0
		if Rng.hash2(n * 3.0 + m.id, floorf(ph * 1000.0)) <= 0.62:
			kind = 1 + floori(Rng.hash2(n * 5.0 + 1.0, floorf(ph * 997.0)) * 3.0)
		c = Vector3(n, kind, 1.1 if kind == 1 else (0.34 if kind == 2 else 0.5))
		m.fid = c
	if c.y == 0.0 or lt > c.z:
		return Vector2.ZERO
	return Vector2(c.y, lt / c.z)


## Feet a marching man set down in the last `dt` seconds of the march (0, 1,
## at a big step 2): the landings of pose()'s stride (u = 0.25 of each step,
## his own tempo, offset and unevenness). The sound and dust of a squad's
## steps come from these, so they keep the beat the men are seen to walk.
## Call after `uv.walk_t` has advanced by `dt`.
static func footfalls(uv, m, dt: float) -> int:
	if dt <= 0.0 or m.pose == "atk":
		return 0
	var r := rhythm(m)
	if uv.walking <= 0.15 + 0.55 * r.z:
		return 0
	var g1 := gait_phase(uv, m, uv.walk_t)
	var g0 := gait_phase(uv, m, maxf(0.0, uv.walk_t - dt))
	return maxi(0, floori(g1 * 2.0 - 0.25) - floori(g0 * 2.0 - 0.25))


## A falling soldier: `ms` to blit, and for a fall from behind the body it
## settles into (`next`, blended in by `mix`).
static func fall(uv, m) -> Dictionary:
	var t: float = m.death_t
	var facing := facing_of(uv, m)
	var flip := flip_of(facing)
	var fac := "f" if Formation.faces_camera(facing) else "b"
	var name: String
	if t < RECOIL:
		name = "idle_%s_0" % suffix(facing, m.type)
	elif t < KNEEL:
		name = "death_%s_kneel" % fac
	else:
		name = "death_%s_down" % fac
	var out := {"ms": frame_ms(m.type, name, m.variant, flip), "next": null, "mix": 0.0}
	if fac == "b" and t > SETTLE:
		out.next = frame_ms(m.type, "death_f_down", m.variant, corpse_flip(facing))
		out.mix = (t - SETTLE) / (1.0 - SETTLE)
	return out


## The body left on the field: the front fall's last frame, head toward the
## way he faced (mirrored for south-east and north-east).
static func corpse(type: String, soldier: int) -> Dictionary:
	return frame(type, "death_f_down", soldier)


static func corpse_flip(facing: int) -> bool:
	return facing == 0 or facing == 3


## One man's part in a melee blow, in seconds from the order: when he starts,
## how long he winds up, the cut, how long he holds the blow and recovers.
## The front rank (the first `front` of the striking order) goes first, each
## man a little late or early on his own beat.
static func melee_beat(i: int, front: int, m) -> Dictionary:
	var a := Rng.hash2(m.id * 13 + 5, floori(m.phase * 1000))
	var b := Rng.hash2(m.id * 7 + 11, floori(m.phase * 977))
	var start := i * 0.045 + (0.06 if i >= front else 0.0) + a * 0.05
	return {"start": start, "wind": 0.15 + b * 0.07, "cut": 0.06, "hold": 0.13 + a * 0.06, "back": 0.22}


## Soldiers follow their squad's anchor on a damped spring, each with his own
## stiffness: they lag when it sets off, skid a little past it at the halt and
## settle back. `at` is the anchor in world px this frame; also keeps
## `uv.heading`, the march's screen direction.
static func step_drift(uv, dt: float, at: Vector2) -> void:
	var prev: Vector2 = uv.anchor_prev
	uv.anchor_prev = at
	if not prev.is_finite() or dt <= 0.0:
		return
	var d := at - prev
	# A jump (placed, pushed into view) is not a march.
	if d.length() > 40.0:
		uv.anchor_vel = Vector2.ZERO
		for m in uv.members:
			m.drift = Vector2.ZERO
			m.drift_v = Vector2.ZERO
		return
	var vel := d / dt
	var dv: Vector2 = vel - uv.anchor_vel
	uv.anchor_vel = vel
	if vel.length_squared() > 400.0:
		uv.heading = uv.heading.lerp(vel.normalized(), minf(1.0, dt * 14.0)).normalized()
	if uv.members.is_empty():
		return
	var ga := gait(uv.members[0].type)
	for m in uv.members:
		var r := rhythm(m)
		var k: float = ga.spring * (0.75 + 0.5 * r.z)
		var c: float = 2.0 * ga.damp * sqrt(k)
		# The anchor's change of speed is an impulse the body has to catch up with.
		var w: Vector2 = m.drift_v - dv
		w += (-k * m.drift - c * w) * dt
		m.drift_v = w
		m.drift = (m.drift + w * dt).limit_length(MAX_DRIFT)
