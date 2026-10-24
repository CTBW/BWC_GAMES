## Prototype effects, drawn by one node from plain arrays: no node is created
## per effect, so a squad hitting for minutes allocates nothing new.
##   spark(at, dir)  cel hit star (white core, gold rim, ink outline), streaks, ground ring
##   dust(at, dir)   footstep puffs kicked back from the stride
##   straw(at, dir)  bits of straw from the training dummy
## Shake: trauma-based, squared falloff, capped so six staggered blows read as
## a squad's rhythm rather than an earthquake.
extends Node2D

const INK := Color(0.16, 0.12, 0.1, 1.0)
const CAP := 160

var sparks: Array = []
var streaks: Array = []
var rings: Array = []
var puffs: Array = []
var bits: Array = []
var trauma := 0.0
var playback := 1.0
var enabled := true
var rng := RandomNumberGenerator.new()
var spawned := 0


func _ready() -> void:
	rng.seed = 7071


func spark(at: Vector2, dir: Vector2) -> void:
	if not enabled:
		return
	spawned += 1
	dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	sparks.append({"p": at, "t": 0.0, "life": 0.17, "rot": rng.randf() * TAU, "size": rng.randf_range(13.0, 16.0)})
	rings.append({"p": at + Vector2(0, 6), "t": 0.0, "life": 0.24})
	for i in 7:
		var a := dir.angle() + rng.randf_range(-1.1, 1.1)
		var v := Vector2.from_angle(a) * rng.randf_range(90.0, 210.0) + Vector2(0, -40)
		streaks.append({"p": at, "v": v, "t": 0.0, "life": rng.randf_range(0.12, 0.22)})
	_trim()
	add_trauma(0.32)


func dust(at: Vector2, dir: Vector2) -> void:
	if not enabled:
		return
	spawned += 1
	var back := -dir.normalized() if dir.length() > 0.01 else Vector2.ZERO
	for i in 3:
		var off := Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-1.0, 1.0))
		puffs.append({"p": at + off, "v": back * rng.randf_range(8.0, 18.0) + Vector2(off.x * 2.0, -rng.randf_range(4.0, 9.0)),
			"t": 0.0, "life": rng.randf_range(0.3, 0.42), "r": rng.randf_range(1.3, 2.2)})
	_trim()


func straw(at: Vector2, dir: Vector2) -> void:
	if not enabled:
		return
	for i in 6:
		var a := dir.angle() + rng.randf_range(-0.9, 0.9)
		bits.append({"p": at + Vector2(rng.randf_range(-4, 4), rng.randf_range(-6, 6)),
			"v": Vector2.from_angle(a) * rng.randf_range(40.0, 120.0) + Vector2(0, -60), "t": 0.0,
			"life": rng.randf_range(0.45, 0.7), "rot": rng.randf() * TAU, "spin": rng.randf_range(-9, 9)})
	_trim()


func add_trauma(v: float) -> void:
	trauma = minf(0.6, trauma + v)


## Camera offset for this frame (world px); call once per frame.
func shake_offset(dt: float) -> Vector2:
	trauma = maxf(0.0, trauma - dt * 2.4)
	var k := trauma * trauma
	return Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 7.0 * k


func clear() -> void:
	sparks.clear()
	streaks.clear()
	rings.clear()
	puffs.clear()
	bits.clear()
	trauma = 0.0


func live_count() -> int:
	return sparks.size() + streaks.size() + rings.size() + puffs.size() + bits.size()


func _trim() -> void:
	for arr in [sparks, streaks, rings, puffs, bits]:
		while arr.size() > CAP:
			arr.pop_front()


func _process(dt: float) -> void:
	var d := dt * playback
	for arr in [sparks, rings]:
		for e in arr:
			e.t += d
	for e in streaks:
		e.t += d
		e.v.y += 420.0 * d
		e.p += e.v * d
	for e in puffs:
		e.t += d
		e.p += e.v * d
		e.v *= pow(0.04, d)
	for e in bits:
		e.t += d
		e.v.y += 360.0 * d
		e.p += e.v * d
		e.rot += e.spin * d
	for arr in [sparks, streaks, rings, puffs, bits]:
		var i := 0
		while i < arr.size():
			if arr[i].t >= arr[i].life:
				arr.remove_at(i)
			else:
				i += 1
	queue_redraw()


func _draw() -> void:
	for e in rings:
		var u: float = e.t / e.life
		var r := lerpf(4.0, 22.0, 1.0 - pow(1.0 - u, 3.0))
		_ellipse(e.p, Vector2(r, r * 0.5), Color(1, 0.95, 0.75, 0.55 * (1.0 - u)), 1.6)
	for e in puffs:
		var u: float = e.t / e.life
		var r: float = e.r * (1.0 + u * 1.6)
		var a := 0.5 * (1.0 - u * u)
		draw_circle(e.p, r + 0.9, Color(INK.r, INK.g, INK.b, a * 0.45))
		draw_circle(e.p, r, Color(0.86, 0.78, 0.6, a))
		draw_circle(e.p + Vector2(-r * 0.3, -r * 0.3), r * 0.45, Color(0.97, 0.92, 0.8, a))
	for e in streaks:
		var u: float = e.t / e.life
		var tail: Vector2 = e.p - (e.v as Vector2).normalized() * lerpf(9.0, 3.0, u)
		draw_line(tail, e.p, Color(INK.r, INK.g, INK.b, 0.6 * (1.0 - u)), 3.0)
		draw_line(tail, e.p, Color(1.0, 0.93, 0.55, 1.0 - u), 1.6)
	for e in sparks:
		var u: float = e.t / e.life
		# Pops to full size in two frames, then shrinks: a hard, quick flash.
		var grow := minf(1.0, u / 0.18)
		var size: float = e.size * grow * (1.0 - 0.55 * maxf(0.0, (u - 0.18) / 0.82))
		_star(e.p, size + 2.2, 0.36, e.rot, INK, 8)
		_star(e.p, size, 0.38, e.rot, Color(1.0, 0.72, 0.18), 8)
		_star(e.p, size * 0.62, 0.42, e.rot + 0.2, Color(1.0, 0.97, 0.78), 8)
		if u < 0.3:
			draw_circle(e.p, size * 0.5 * (1.0 - u / 0.3), Color(1, 1, 1, 0.9))
	for e in bits:
		var u: float = e.t / e.life
		var d := Vector2.from_angle(e.rot) * 2.6
		draw_line(e.p - d, e.p + d, Color(INK.r, INK.g, INK.b, 0.7 * (1.0 - u)), 2.2)
		draw_line(e.p - d, e.p + d, Color(0.95, 0.82, 0.42, 1.0 - u), 1.1)


func _star(c: Vector2, r: float, inner: float, rot: float, col: Color, n: int) -> void:
	var pts := PackedVector2Array()
	for i in n * 2:
		var rr := r if i % 2 == 0 else r * inner
		pts.append(c + Vector2.from_angle(rot + PI * i / n) * rr)
	draw_colored_polygon(pts, col)


func _ellipse(c: Vector2, r: Vector2, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for i in 25:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_polyline(pts, col, w, true)
