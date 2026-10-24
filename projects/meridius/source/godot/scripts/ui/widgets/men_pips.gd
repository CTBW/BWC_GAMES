## Port of common.tsx `MenPips`: squad strength as pips (filled: serving,
## hollow: fallen), optionally followed by "5/6".
##
##   const MenPips = preload("res://scripts/ui/widgets/men_pips.gd")
##   MenPips.make(men: int, size: int, count := true, title := "", color := Color(0,0,0,0)) -> Control
##       Colour: `color`, else the theme colour MenPips/font_color (ink on parchment,
##       #e9d8ae inside a dark panel). Title default "<men> of <size> soldiers
##       is/are still serving". Pips 6×7 px, gap 2; count in Alegreya 700 11 px.
##   pips.set_men(men, size)   update in place
extends Control

const UI = preload("res://scripts/ui/ui.gd")

const PIP := Vector2(6, 7)
const FONT_SIZE := 11

var men := 0
var squad_size := 6
var show_count := true
var colour := Color(0, 0, 0, 0)


static func make(men_: int, size_: int, count := true, title := "", color := Color(0, 0, 0, 0)) -> Control:
	var p: Control = load("res://scripts/ui/widgets/men_pips.gd").new()
	p.show_count = count
	p.colour = color
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.set_men(men_, size_, title)
	return p


func set_men(men_: int, size_: int, title := "") -> void:
	men = men_
	squad_size = size_
	tooltip_text = title if title != "" else "%d of %d soldiers %s still serving" % [men, squad_size, "is" if men == 1 else "are"]
	update_minimum_size()
	queue_redraw()


func _font() -> Font:
	return UI.font("alegreya", 700)


func _count_text() -> String:
	return "%d/%d" % [men, squad_size]


func _get_minimum_size() -> Vector2:
	var w := squad_size * PIP.x + maxi(0, squad_size - 1) * 2.0
	var h := PIP.y
	if show_count:
		var ts := _font().get_string_size(_count_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		w += 4.0 + ts.x
		h = maxf(h, ts.y - 2.0)
	return Vector2(ceilf(w), ceilf(h))


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func _draw() -> void:
	var c := colour if colour.a > 0.0 else get_theme_color("font_color", "MenPips")
	var y := floorf((size.y - PIP.y) * 0.5)
	for i in squad_size:
		var r := Rect2(i * (PIP.x + 2.0), y, PIP.x, PIP.y)
		var on := i < men
		var sb := StyleBoxFlat.new()
		sb.corner_radius_top_left = 2
		sb.corner_radius_top_right = 2
		sb.corner_radius_bottom_left = 3
		sb.corner_radius_bottom_right = 3
		sb.corner_detail = 3
		sb.anti_aliasing = true
		sb.anti_aliasing_size = 0.6
		sb.set_border_width_all(1)
		sb.border_color = c if on else Color(c, c.a * 0.55)
		sb.bg_color = c if on else Color(0, 0, 0, 0)
		sb.draw_center = on
		draw_style_box(sb, r)
	if show_count:
		var f := _font()
		var x := squad_size * PIP.x + maxi(0, squad_size - 1) * 2.0 + 4.0
		var asc := f.get_ascent(FONT_SIZE)
		var desc := f.get_descent(FONT_SIZE)
		var baseline := (size.y - (asc + desc)) * 0.5 + asc
		draw_string(f, Vector2(x, baseline), _count_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, c)
