## Sandbox ground: a small field of iso tiles (game size 128 x 64) in the
## bright grass of the battle map, the squad's tile picked out.
extends Node2D

const Formation = preload("res://prototypes/footman_anim/scripts/formation.gd")

var focus_tile := Vector2.ZERO
var radius := 4


func _draw() -> void:
	for gx in range(-radius, radius + 1):
		for gy in range(-radius, radius + 1):
			var c := Formation.iso(Vector2(gx, gy))
			var pts := PackedVector2Array([c + Vector2(0, -32), c + Vector2(64, 0), c + Vector2(0, 32), c + Vector2(-64, 0)])
			var shade := 0.03 * float((gx + gy) % 2)
			var col := Color(0.47 + shade, 0.6 + shade, 0.3 + shade * 0.5)
			draw_colored_polygon(pts, col)
			pts.append(pts[0])
			draw_polyline(pts, Color(0.32, 0.43, 0.2, 0.55), 1.0)
	var f := Formation.iso(focus_tile)
	var q := PackedVector2Array([f + Vector2(0, -32), f + Vector2(64, 0), f + Vector2(0, 32), f + Vector2(-64, 0), f + Vector2(0, -32)])
	draw_polyline(q, Color(1, 0.95, 0.7, 0.6), 1.5)
