## Combat feedback: particles, floating text, projectiles, shockwaves and
## persistent ground marks. All positions are in world pixels.
## Port of src/render/fx.ts (class Fx).
##
##   var fx = Fx.new()
##   fx.burst(x, y, z, n, {shape: "puff", color: "rgba(210,210,205,1)", speed: 6,
##            vz: 40, gravity: -8, size: 10, max: 3, drag: 0.2, colors: [...]})
##   fx.text(x, y, "12", "#ffd76a", {size, bold, delay, life})
##   fx.shoot({x0, y0, x1, y1, t: 0, dur, arc, kind: "bolt"|"arrow",
##             onHit: Callable, stick: bool, scale: float})
##   fx.ring(x, y, max, color, life = 0.7)
##   fx.busy                      true while projectiles fly
##   fx.update(dt)
##   fx.draw_ground(ci)           marks and rings (world transform)
##   fx.draw_air(ci)              particles and projectiles (world transform)
##   fx.draw_texts(ci, zoom)      floating texts; `ci` draws in world px under
##                                the camera transform (zoom), text stays crisp
## Colours may be CSS strings (as in the original) or Color values.
## Particles, texts, projectiles, marks and rings are Dictionaries with the
## original field names.
extends RefCounted

const WD = preload("res://scripts/render/world_draw.gd")

var particles: Array = []
var texts: Array = []
var projectiles: Array = []
var marks: Array = []
var rings: Array = []

var busy: bool:
	get:
		return projectiles.size() > 0


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
		if p.t >= p.dur:
			var hit: Variant = p.get("onHit")
			if hit is Callable and hit.is_valid():
				hit.call()
			if p.get("stick", false):
				var ang := atan2(p.y1 - p.y0, p.x1 - p.x0)
				marks.append({"x": p.x1, "y": p.y1, "angle": ang, "kind": p.kind, "life": 40.0, "scale": p.get("scale", 1.0)})
	projectiles = projectiles.filter(func(p): return p.t < p.dur)
	for r in rings:
		r.life -= dt
		r.r += (r.max - r.r) * minf(1.0, dt * 6.0)
	rings = rings.filter(func(r): return r.life > 0)
	for m in marks:
		m.life -= dt
	marks = marks.filter(func(m): return m.life > 0)
	while marks.size() > 90:
		marks.pop_front()


func draw_ground(ci: CanvasItem) -> void:
	for m in marks:
		var a := minf(1.0, m.life / 3.0)
		var sc: float = m.scale if m.scale else 1.0
		ci.draw_set_transform(Vector2(m.x, m.y), m.angle, Vector2(sc, sc))
		ci.draw_line(Vector2(-12, -6), Vector2.ZERO, Color(0x5a / 255.0, 0x3a / 255.0, 0x22 / 255.0, a), 2.2, true)
		var c := Color8(0xa3, 0x26, 0x1c) if m.kind == "arrow" else Color8(0xe8, 0xe2, 0xd0)
		c.a = a
		ci.draw_rect(Rect2(-14, -8, 4, 3), c)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	for r in rings:
		var a := maxf(0.0, r.life / 0.7) * 0.8
		var pts := WD.ellipse(r.x, r.y, r.r, r.r * 0.5, 0.0, 48)
		pts.append(pts[0])
		ci.draw_polyline(pts, WD.with_alpha(r.color, a), 4.0, true)


func draw_air(ci: CanvasItem) -> void:
	for p in particles:
		var a := maxf(0.0, p.life / p.max)
		var y: float = p.y - p.z
		var col: Color = p.color
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
	for p in projectiles:
		var f := minf(1.0, p.t / p.dur)
		var x: float = p.x0 + (p.x1 - p.x0) * f
		var y_lin: float = p.y0 + (p.y1 - p.y0) * f
		var y: float = y_lin - sin(f * PI) * p.arc
		var f2 := minf(1.0, f + 0.02)
		var x2: float = p.x0 + (p.x1 - p.x0) * f2
		var y2: float = p.y0 + (p.y1 - p.y0) * f2 - sin(f2 * PI) * p.arc
		var ang := atan2(y2 - y, x2 - x)
		var sc: float = p.get("scale", 1.0) if p.get("scale", 0.0) else 1.0
		ci.draw_set_transform(Vector2(x, y), ang, Vector2(sc, sc))
		ci.draw_line(Vector2(-34, 0), Vector2(-8, 0), Color(1.0, 250 / 255.0, 220 / 255.0, 0.35), 2.0, true)
		ci.draw_line(Vector2(-16, 0), Vector2(6, 0), Color8(0x4a, 0x2f, 0x1c), 2.6, true)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(10, 0), Vector2(4, -3), Vector2(4, 3)]), Color8(0xd8, 0xdc, 0xe0))
		ci.draw_rect(Rect2(-18, -3, 5, 6), Color8(0xa3, 0x26, 0x1c) if p.kind == "arrow" else Color8(0xef, 0xe8, 0xd4))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


func draw_texts(ci: CanvasItem, zoom: float) -> void:
	for t in texts:
		if t.delay > 0:
			continue
		var a := minf(1.0, t.life / 0.35) * minf(1.0, (t.max - t.life) / 0.08 + 0.2)
		var pop := 1.0 + maxf(0.0, 0.25 - (t.max - t.life)) * 1.6
		var s: float = (t.size * pop) / maxf(0.6, zoom)
		WD.draw_text(ci, t.x, t.y, t.text, s, WD.with_alpha(t.color, a), zoom, s * 0.22, Color(25 / 255.0, 16 / 255.0, 10 / 255.0, 0.9 * a))
