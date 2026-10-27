## The `.flourish` divider: a hairline fading in and out at the ends with a dot
## in the middle (height 10, margin 8 above and below).
##
##   const Flourish = preload("res://scripts/ui/widgets/flourish.gd")
##   Flourish.make(margin := 8) -> Control
extends Control

var margin := 8.0


static func make(margin_ := 8) -> Control:
	var f: Control = load("res://scripts/ui/widgets/flourish.gd").new()
	f.margin = margin_
	f.custom_minimum_size = Vector2(0, 10 + margin_ * 2)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return f


func _draw() -> void:
	var w := size.x
	var y := floorf(size.y * 0.5)
	var c := Color("#a58d5f")
	var clear := Color(c, 0.0)
	var xs := [0.0, w * 0.2, w * 0.8, w]
	var cs := [clear, c, c, clear]
	for i in 3:
		var a: float = xs[i]
		var b: float = xs[i + 1]
		draw_polygon(PackedVector2Array([Vector2(a, y), Vector2(b, y), Vector2(b, y + 1), Vector2(a, y + 1)]),
			PackedColorArray([cs[i], cs[i + 1], cs[i + 1], cs[i]]))
	# Engraved lozenges, with a dark recess under the central brass facet.
	for i in [-1, 0, 1]:
		var p := Vector2(w * 0.5 + i * 12, y)
		var radius := 4.0 if i == 0 else 2.0
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -radius), p + Vector2(radius * 1.6, 0),
			p + Vector2(0, radius), p + Vector2(-radius * 1.6, 0)]), Color("#9b814f"))
		draw_line(p + Vector2(-radius * 1.6, 0), p + Vector2(0, -radius), Color("#e1c996"), 1, true)
