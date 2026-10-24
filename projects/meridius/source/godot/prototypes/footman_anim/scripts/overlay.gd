## Sandbox overlay: each soldier's body circle (on the ground, as an iso
## ellipse), his blade samples now, his formation slot, and every current
## overlap in red (Formation.overlaps).
extends Node2D

const Formation = preload("res://prototypes/footman_anim/scripts/formation.gd")

var sandbox: Node2D
var current: Array = []


func _draw() -> void:
	if sandbox == null:
		return
	var hot := {}
	for o in current:
		hot[o.b] = true
		if o.kind == "body":
			hot[o.a] = true
	for s in sandbox.soldiers():
		if s.dead:
			continue
		var c: Vector2 = s.position
		var r := Formation.BODY_R
		var col := Color(1, 0.2, 0.15, 0.9) if hot.has(s) else Color(0.4, 0.9, 1.0, 0.8)
		_ground_circle(c, r, col)
		for p in Formation.blade_now(s):
			var w := Formation.iso(p[0])
			draw_circle(w - Vector2(0, float(p[1]) * 14.0), 1.2, Color(1, 1, 0.3, 0.8))
			draw_line(w, w - Vector2(0, float(p[1]) * 14.0), Color(1, 1, 0.3, 0.25), 1.0)
	if sandbox.squad:
		for i in sandbox.squad.members.size():
			var w: Vector2 = sandbox.squad.slot_world(i)
			draw_line(w - Vector2(3, 0), w + Vector2(3, 0), Color(1, 1, 1, 0.6), 1.0)
			draw_line(w - Vector2(0, 2), w + Vector2(0, 2), Color(1, 1, 1, 0.6), 1.0)
	if sandbox.dummy:
		_ground_circle(sandbox.dummy.position, 0.13, Color(1, 0.8, 0.3, 0.8))


func _ground_circle(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var a := TAU * i / 32.0
		pts.append(c + Formation.iso(Vector2(cos(a), sin(a)) * r))
	draw_polyline(pts, col, 1.2)
