## Combat feedback: particles, floating text, projectiles, shockwaves,
## lightning and tendrils, and persistent ground marks. All positions are in
## world pixels. Port of src/render/fx.ts (class Fx).
##
##   var fx = Fx.new()
##   fx.burst(x, y, z, n, {shape: "puff"|"spark"|"dot"|"leaf"|"glow", color: "rgba(210,210,205,1)",
##            speed: 6, vz: 40, gravity: -8, size: 10, max: 3, drag: 0.2, colors: [...]})
##   fx.text(x, y, "12", "#ffd76a", {size, bold, delay, life})
##   fx.shoot({x0, y0, x1, y1, t: 0, dur, arc, kind: "bolt"|"arrow"|"orb"|"fireball"|"stone"|"shard",
##             onHit: Callable, stick: bool, scale: float, color: css})
##   fx.ring(x, y, max, color, life = 0.7)
##   fx.lightning(x0, y0, x1, y1, {color, core, width, life, jag, branches})
##   fx.tendril(x0, y0, x1, y1, {color, core, dark, width, life, amp})
##   fx.mark(x, y, "scorch"|"crater"|"frost", scale = 1, life = 30)
##   fx.busy                      true while projectiles fly
##   fx.update(dt)
##   fx.draw_ground(ci)           marks and rings (world transform)
##   fx.draw_air(ci)              particles, lightning and projectiles (world transform)
##   fx.draw_texts(ci, zoom)      floating texts; `ci` draws in world px under
##                                the camera transform (zoom), text stays crisp
## Colours may be CSS strings (as in the original) or Color values.
## Particles, texts, projectiles, marks, rings and arcs are Dictionaries with
## the original field names (an arc's `pts` and `branches` are PackedVector2Arrays).
##
## Glow particles, lightning and magic missiles are light: the original draws
## them 'lighter' (additive). With `additive` set, those draws carry ADD in
## their red channel and the drawing CanvasItem's material
## (scenes/battle/battle_fx.gdshader) adds them, in order with the ordinary
## draws; without it they fall back to ordinary blending.
extends RefCounted

const WD = preload("res://scripts/render/world_draw.gd")

## Red channel offset of an additive ('lighter') draw (battle_fx.gdshader).
const ADD := 4.0

var particles: Array = []
var texts: Array = []
var projectiles: Array = []
var marks: Array = []
var rings: Array = []
var arcs: Array = []
## The drawing CanvasItem adds ADD-flagged colours (see the header).
var additive := false

var busy: bool:
	get:
		return projectiles.size() > 0

static var _grad := {}


## A jagged line from a to b: midpoint displacement, `jag` world pixels at the coarsest level.
static func jagged(x0: float, y0: float, x1: float, y1: float, jag: float, depth := 5) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(x0, y0), Vector2(x1, y1)])
	var amp := jag
	for d in depth:
		var next := PackedVector2Array([pts[0]])
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			var dx := b.x - a.x
			var dy := b.y - a.y
			var len := sqrt(dx * dx + dy * dy)
			if len == 0.0:
				len = 1.0
			var off := (randf() - 0.5) * amp
			next.append(Vector2((a.x + b.x) / 2 - (dy / len) * off, (a.y + b.y) / 2 + (dx / len) * off))
			next.append(b)
		pts = next
		amp *= 0.55
	return pts


## Lightning (or a tendril) from one point to another. It flickers: each
## frame of its short life redraws a fresh jagged path.
func lightning(x0: float, y0: float, x1: float, y1: float, opts: Dictionary = {}) -> void:
	var len := Vector2(x0, y0).distance_to(Vector2(x1, y1))
	var jag: float = float(opts.get("jag", minf(60.0, len * 0.22)))
	var pts := jagged(x0, y0, x1, y1, jag)
	var branches: Array = []
	for i in int(opts.get("branches", 2)):
		var p := pts[floori(pts.size() * (0.25 + randf() * 0.5))]
		var ang := atan2(y1 - y0, x1 - x0) + (randf() - 0.5) * 2.2
		var l := len * (0.12 + randf() * 0.18)
		branches.append(jagged(p.x, p.y, p.x + cos(ang) * l, p.y + sin(ang) * l, jag * 0.5, 3))
	var life: float = float(opts.get("life", 0.32))
	arcs.append({
		"pts": pts,
		"branches": branches,
		"life": life,
		"max": life,
		"color": WD.css(opts.get("color", "rgba(120,170,255,1)")),
		"core": WD.css(opts.get("core", "#f4f8ff")),
		"width": float(opts.get("width", 3.0)),
	})


## A tendril of blood magic reaching from one point to another: a smooth,
## writhing curve in dark flesh and blood colours with a bright vein.
func tendril(x0: float, y0: float, x1: float, y1: float, opts: Dictionary) -> void:
	var life: float = float(opts.get("life", 0.5))
	arcs.append({
		"pts": PackedVector2Array(),
		"branches": [],
		"life": life,
		"max": life,
		"color": WD.css(opts.color),
		"core": WD.css(opts.core),
		"width": float(opts.get("width", 3.0)),
		"tendril": {"x0": x0, "y0": y0, "x1": x1, "y1": y1, "amp": float(opts.get("amp", 14.0)), "seed": randf() * 10, "dark": WD.css(opts.dark)},
	})


## A mark left on the ground by a spell or a stone (scorch, crater, frost).
func mark(x: float, y: float, kind: String, scale := 1.0, life := 30.0) -> void:
	marks.append({"x": x, "y": y, "angle": 0.0, "kind": kind, "life": life, "scale": scale})


func burst(x: float, y: float, z: float, n: int, opts: Dictionary = {}) -> void:
	var colors: Array = opts.get("colors", [])
	var base_color := WD.css(opts.get("color", "#fff"))
	for i in n:
		var a := randf() * PI * 2.0
		var sp: float = float(opts.get("speed", 80.0)) * (0.4 + randf() * 0.8)
		var life: float = float(opts.get("max", 0.6)) * (0.6 + randf() * 0.6)
		particles.append({
			"x": x,
			"y": y,
			"z": z,
			"vx": cos(a) * sp,
			"vy": sin(a) * sp * 0.5,
			"vz": float(opts.get("vz", 90.0)) * (0.5 + randf()),
			"life": life,
			"max": life,
			"size": float(opts.get("size", 3.0)) * (0.6 + randf() * 0.8),
			"color": WD.css(colors[i % colors.size()]) if colors.size() > 0 else base_color,
			"gravity": float(opts.get("gravity", 300.0)),
			"drag": float(opts.get("drag", 1.5)),
			"shape": str(opts.get("shape", "dot")),
		})


func text(x: float, y: float, txt: String, color: Variant, opts: Dictionary = {}) -> void:
	# Stack texts that spawn at the same spot.
	var near := 0
	for t in texts:
		if absf(t.x - x) < 30 and t.life > t.max - 0.35 and absf(t.y - y) < 40:
			near += 1
	var life: float = float(opts.get("life", 1.3))
	texts.append({
		"x": x,
		"y": y - near * 18,
		"text": txt,
		"color": WD.css(color),
		"size": float(opts.get("size", 20.0)),
		"life": life,
		"max": life,
		"vy": -34.0,
		"bold": bool(opts.get("bold", true)),
		"delay": float(opts.get("delay", 0.0)),
	})


func shoot(p: Dictionary) -> void:
	if not p.has("t"):
		p["t"] = 0.0
	projectiles.append(p)


func ring(x: float, y: float, max_r: float, color: Variant, life: float = 0.7) -> void:
	rings.append({"x": x, "y": y, "r": 4.0, "max": max_r, "life": life, "color": WD.css(color)})


func update(dt: float) -> void:
	for p in particles:
		p.life -= dt
		p.x += p.vx * dt
		p.y += p.vy * dt
		p.z += p.vz * dt
		p.vz -= p.gravity * dt
		var d := exp(-p.drag * dt)
		p.vx *= d
		p.vy *= d
		if p.z < 0:
			p.z = 0.0
			p.vz *= -0.3
			p.vx *= 0.6
			p.vy *= 0.6
	particles = particles.filter(func(p): return p.life > 0)
	for t in texts:
		if t.delay > 0:
			t.delay -= dt
			continue
		t.life -= dt
		t.y += t.vy * dt
		t.vy *= exp(-2.2 * dt)
	texts = texts.filter(func(t): return t.life > 0)
	for p in projectiles:
		p.t += dt
		# Magic and fire leave a trail of light behind them.
		var kind: String = p.kind
		if kind == "orb" or kind == "fireball" or kind == "shard":
			p["trailT"] = float(p.get("trailT", 0.0)) + dt
			var every := 0.012 if kind == "fireball" else 0.022
			var fire := kind == "fireball"
			var sc: float = float(p.get("scale", 1.0)) if p.get("scale") != null else 1.0
			while p.trailT > every:
				p.trailT -= every
				var f := minf(1.0, p.t / p.dur)
				var x: float = p.x0 + (p.x1 - p.x0) * f
				var y: float = p.y0 + (p.y1 - p.y0) * f - sin(f * PI) * p.arc
				var col: Color
				if fire:
					col = WD.css("#ffb030" if randf() < 0.5 else "#ff6a20")
				else:
					col = WD.css(p.get("color") if p.get("color") != null else "#9fd8ff")
				particles.append({
					"x": x + (randf() - 0.5) * 4,
					"y": y + (randf() - 0.5) * 4,
					"z": 0.0,
					"vx": (randf() - 0.5) * 20,
					"vy": (randf() - 0.5) * 20 - (10.0 if fire else 0.0),
					"vz": 0.0,
					"life": 0.45 if fire else 0.3,
					"max": 0.45 if fire else 0.3,
					"size": (7.0 if fire else 4.0) * sc * (0.7 + randf() * 0.6),
					"color": col,
					"gravity": 0.0,
					"drag": 2.0,
					"shape": "glow",
				})
		if p.t >= p.dur:
			var hit: Variant = p.get("onHit")
			if hit is Callable and hit.is_valid():
				hit.call()
			if p.get("stick", false) and (kind == "bolt" or kind == "arrow"):
				var ang := atan2(p.y1 - p.y0, p.x1 - p.x0)
				marks.append({"x": p.x1, "y": p.y1, "angle": ang, "kind": kind, "life": 40.0, "scale": p.get("scale", 1.0)})
	projectiles = projectiles.filter(func(p): return p.t < p.dur)
	for a in arcs:
		a.life -= dt
	arcs = arcs.filter(func(a): return a.life > 0)
	for r in rings:
		r.life -= dt
		r.r += (r.max - r.r) * minf(1.0, dt * 6.0)
	rings = rings.filter(func(r): return r.life > 0)
	for m in marks:
		m.life -= dt
	marks = marks.filter(func(m): return m.life > 0)
	while marks.size() > 90:
		marks.pop_front()


## A colour drawn as light ('lighter'): flagged for the additive material.
func _light(c: Color, a: float) -> Color:
	if additive:
		return Color(c.r + ADD, c.g, c.b, c.a * a)
	return Color(c.r, c.g, c.b, c.a * a)


## The soft radial patches of the ground marks (createRadialGradient): white
## discs whose alpha and colour fall off as the original's stops.
static func _gradient(kind: String) -> Texture2D:
	var t: Texture2D = _grad.get(kind)
	if t != null:
		return t
	var g := Gradient.new()
	if kind == "frost":
		# createRadialGradient(0, 0, 4, 0, 0, 46): stops at 0, 0.6, 1 of the 4…46 ramp.
		g.offsets = PackedFloat32Array([4.0 / 46.0, (4.0 + 0.6 * 42.0) / 46.0, 1.0])
		g.colors = PackedColorArray([Color8(235, 248, 255, 191), Color8(170, 215, 245, 115), Color8(170, 215, 245, 0)])
	elif kind == "scorch":
		g.offsets = PackedFloat32Array([3.0 / 40.0, (3.0 + 0.7 * 37.0) / 40.0, 1.0])
		g.colors = PackedColorArray([Color8(25, 15, 8, 204), Color8(45, 28, 14, 115), Color8(45, 28, 14, 0)])
	else:
		g.offsets = PackedFloat32Array([3.0 / 40.0, (3.0 + 0.7 * 37.0) / 40.0, 1.0])
		g.colors = PackedColorArray([Color8(40, 30, 20, 191), Color8(80, 62, 40, 102), Color8(45, 28, 14, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 96
	tex.height = 96
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_grad[kind] = tex
	return tex


func draw_ground(ci: CanvasItem) -> void:
	for m in marks:
		var kind: String = m.kind
		if kind == "scorch" or kind == "crater" or kind == "frost":
			# Flat on the ground: a burnt patch, a stone's crater, a skin of frost.
			var a := minf(1.0, m.life / 4.0)
			var sc: float = m.scale
			ci.draw_set_transform(Vector2(m.x, m.y), 0.0, Vector2(sc, sc * 0.5))
			var R := 46.0 if kind == "frost" else 40.0
			ci.draw_texture_rect(_gradient(kind), Rect2(-R, -R, R * 2, R * 2), false, Color(1, 1, 1, a))
			if kind == "crater":
				ci.draw_arc(Vector2.ZERO, 22, PI * 0.9, PI * 2.1, 24, Color(150 / 255.0, 125 / 255.0, 90 / 255.0, 0.55 * a), 3.0, true)
			continue
		var a := minf(1.0, m.life / 3.0)
		var sc: float = m.scale if m.scale else 1.0
		ci.draw_set_transform(Vector2(m.x, m.y), m.angle, Vector2(sc, sc))
		ci.draw_line(Vector2(-12, -6), Vector2.ZERO, Color(0x5a / 255.0, 0x3a / 255.0, 0x22 / 255.0, a), 2.2, true)
		var c := Color8(0xa3, 0x26, 0x1c) if kind == "arrow" else Color8(0xe8, 0xe2, 0xd0)
		c.a = a
		ci.draw_rect(Rect2(-14, -8, 4, 3), c)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	for r in rings:
		var a := maxf(0.0, r.life / 0.7) * 0.8
		var pts := WD.ellipse(r.x, r.y, r.r, r.r * 0.5, 0.0, 48)
		pts.append(pts[0])
		ci.draw_polyline(pts, WD.with_alpha(r.color, a), 4.0, true)


func draw_air(ci: CanvasItem) -> void:
	var glowing := false
	for p in particles:
		var a := maxf(0.0, p.life / p.max)
		var y: float = p.y - p.z
		var col: Color = p.color
		if p.shape == "glow":
			# Additive soft light: drawn in its own pass below.
			glowing = true
			continue
		if p.shape == "puff":
			var s: float = p.size * (1.6 - a * 0.6)
			WD.fill_circle(ci, Vector2(p.x, y), s, WD.with_alpha(col, a * 0.45))
		elif p.shape == "spark":
			ci.draw_line(Vector2(p.x, y), Vector2(p.x - p.vx * 0.03, y - (p.vy - p.vz) * 0.03), WD.with_alpha(col, a), p.size * 0.6, true)
		elif p.shape == "leaf":
			ci.draw_set_transform(Vector2(p.x, y), p.life * 6.0, Vector2.ONE)
			ci.draw_rect(Rect2(-p.size, -p.size * 0.4, p.size * 2.0, p.size * 0.8), WD.with_alpha(col, a))
			ci.draw_set_transform_matrix(Transform2D.IDENTITY)
		else:
			ci.draw_rect(Rect2(p.x - p.size / 2.0, y - p.size / 2.0, p.size, p.size), WD.with_alpha(col, a))
	if glowing:
		for p in particles:
			if p.shape != "glow":
				continue
			var a := maxf(0.0, p.life / p.max)
			var c := Vector2(p.x, p.y - p.z)
			WD.fill_circle(ci, c, p.size * 1.8, _light(p.color, a * 0.35))
			WD.fill_circle(ci, c, p.size * 0.7, _light(p.color, a * 0.8))
	for arc in arcs:
		_draw_arc(ci, arc)
	for p in projectiles:
		var f := minf(1.0, p.t / p.dur)
		var x: float = p.x0 + (p.x1 - p.x0) * f
		var y_lin: float = p.y0 + (p.y1 - p.y0) * f
		var y: float = y_lin - sin(f * PI) * p.arc
		var f2 := minf(1.0, f + 0.02)
		var x2: float = p.x0 + (p.x1 - p.x0) * f2
		var y2: float = p.y0 + (p.y1 - p.y0) * f2 - sin(f2 * PI) * p.arc
		var ang := atan2(y2 - y, x2 - x)
		if p.kind != "bolt" and p.kind != "arrow":
			_draw_missile(ci, p, x, y, ang, f)
			continue
		var sc: float = p.get("scale", 1.0) if p.get("scale", 0.0) else 1.0
		ci.draw_set_transform(Vector2(x, y), ang, Vector2(sc, sc))
		ci.draw_line(Vector2(-34, 0), Vector2(-8, 0), Color(1.0, 250 / 255.0, 220 / 255.0, 0.35), 2.0, true)
		ci.draw_line(Vector2(-16, 0), Vector2(6, 0), Color8(0x4a, 0x2f, 0x1c), 2.6, true)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(10, 0), Vector2(4, -3), Vector2(4, 3)]), Color8(0xd8, 0xdc, 0xe0))
		ci.draw_rect(Rect2(-18, -3, 5, 6), Color8(0xa3, 0x26, 0x1c) if p.kind == "arrow" else Color8(0xef, 0xe8, 0xd4))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## The 7-sided outline of a catapult stone (radius 9 before scaling).
static var _stone_pts := PackedVector2Array()


## Magic missiles, fireballs, ice shards and catapult stones in flight.
func _draw_missile(ci: CanvasItem, p: Dictionary, x: float, y: float, ang: float, f: float) -> void:
	var s: float = float(p.get("scale", 1.0)) if p.get("scale") != null else 1.0
	if p.kind == "stone":
		# A tumbling stone, its shadow racing along the ground below it.
		var gy: float = p.y0 + (p.y1 - p.y0) * f
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
		ci.draw_texture_rect(WD.disc(), Rect2(x - 9 * s, gy - 4 * s, 18 * s, 8 * s), false, Color(0x14 / 255.0, 0x10 / 255.0, 0x08 / 255.0, 0.25))
		if _stone_pts.is_empty():
			for i in 7:
				var a := (i / 7.0) * PI * 2
				var k := 9.0 * (0.78 + ((i * 37) % 10) / 30.0)
				_stone_pts.append(Vector2(cos(a) * k, sin(a) * k))
		ci.draw_set_transform(Vector2(x, y), p.t * 9, Vector2(s, s))
		ci.draw_colored_polygon(_stone_pts, WD.css(p.get("color") if p.get("color") != null else "#8a8378"))
		var outline := _stone_pts.duplicate()
		outline.append(_stone_pts[0])
		ci.draw_polyline(outline, Color8(0x2a, 0x1d, 0x14), 2.0, true)
		WD.fill_circle(ci, Vector2(-3, -3), 3, Color(1.0, 245 / 255.0, 220 / 255.0, 0.35))
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
		return
	if p.kind == "shard":
		ci.draw_set_transform(Vector2(x, y), ang, Vector2(s, s))
		ci.draw_texture_rect(WD.disc(), Rect2(-4 - 16, -6, 32, 12), false, _light(Color(160 / 255.0, 215 / 255.0, 1.0), 0.5))
		var body := PackedVector2Array([Vector2(12, 0), Vector2(0, -4), Vector2(-10, 0), Vector2(0, 4)])
		ci.draw_colored_polygon(body, Color8(0xe8, 0xf6, 0xff))
		var edge := body.duplicate()
		edge.append(body[0])
		ci.draw_polyline(edge, Color8(0x5a, 0x8a, 0xb8), 1.2, true)
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
		return
	var fire: bool = p.kind == "fireball"
	var r := (11.0 if fire else 6.0) * s
	var col := WD.css("#ff7a1c") if fire else WD.css(p.get("color") if p.get("color") != null else "#9fd8ff")
	var flick := 1 + sin(p.t * 40) * 0.08
	var c := Vector2(x, y)
	WD.fill_circle(ci, c, r * 2.4 * flick, _light(col, 0.28))
	WD.fill_circle(ci, c, r * 1.35, _light(col, 0.6))
	WD.fill_circle(ci, c, r * 0.65, _light(WD.css("#ffe9a0") if fire else Color.WHITE, 1.0))


## A flickering bolt: a wide soft glow under a bright core, redrawn jagged every few frames.
func _draw_arc(ci: CanvasItem, a: Dictionary) -> void:
	var k := maxf(0.0, a.life / a.max)
	if a.has("tendril"):
		_draw_tendril(ci, a, k)
		return
	# Re-jag now and then so the bolt crackles instead of hanging still.
	var pts: PackedVector2Array = a.pts
	if randf() < 0.35 and pts.size() > 2:
		var first := pts[0]
		var last := pts[pts.size() - 1]
		var len := first.distance_to(last)
		a.pts = jagged(first.x, first.y, last.x, last.y, minf(60.0, len * 0.22))
		pts = a.pts
	var w: float = a.width
	for ps in [[w * 5, 0.18, a.color], [w * 2.2, 0.45, a.color], [w, 1.0, a.core]]:
		var col := _light(ps[2], ps[1] * k)
		ci.draw_polyline(pts, col, ps[0], true)
		for b in a.branches:
			ci.draw_polyline(b, col, ps[0] * 0.55, true)


## A tendril lashes out (grows from the caster in its first fifth), writhes, then withers.
func _draw_tendril(ci: CanvasItem, a: Dictionary, k: float) -> void:
	var t: Dictionary = a.tendril
	var age: float = a.max - a.life
	var reach := minf(1.0, age / (a.max * 0.22))
	if reach <= 0.001:
		return
	var dx: float = t.x1 - t.x0
	var dy: float = t.y1 - t.y0
	var len := sqrt(dx * dx + dy * dy)
	if len == 0.0:
		len = 1.0
	var nx := -dy / len
	var ny := dx / len
	var pts := PackedVector2Array()
	var n := 22
	for i in n + 1:
		var f := (float(i) / n) * reach
		# Two waves travelling along the tendril, pinned at both ends.
		var wv := sin(f * PI * 3 - age * 14 + t.seed) * 0.7 + sin(f * PI * 5 + age * 9 + t.seed * 2) * 0.3
		var off: float = wv * t.amp * sin(f * PI)
		pts.append(Vector2(t.x0 + dx * f + nx * off, t.y0 + dy * f + ny * off))
	var fade := minf(1.0, k * 2.5)
	var w: float = a.width
	# A faint glow of its own colour around it, then the dark sinew, the flesh and a bright vein.
	ci.draw_polyline(pts, _light(a.color, 0.22 * fade), w * 4.5, true)
	for ps in [[w * 2.3, t.dark, 0.95], [w * 1.5, a.color, 1.0], [w * 0.45, a.core, 0.9]]:
		WD.stroke_round(ci, pts, WD.with_alpha(ps[1], ps[2] * fade), ps[0])


func draw_texts(ci: CanvasItem, zoom: float) -> void:
	for t in texts:
		if t.delay > 0:
			continue
		var a := minf(1.0, t.life / 0.35) * minf(1.0, (t.max - t.life) / 0.08 + 0.2)
		var pop := 1.0 + maxf(0.0, 0.25 - (t.max - t.life)) * 1.6
		var s: float = (t.size * pop) / maxf(0.6, zoom)
		WD.draw_text(ci, t.x, t.y, t.text, s, WD.with_alpha(t.color, a), zoom, s * 0.22, Color(25 / 255.0, 16 / 255.0, 10 / 255.0, 0.9 * a))
