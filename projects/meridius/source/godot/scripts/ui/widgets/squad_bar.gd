## Port of common.tsx `SquadBar` and `RosterSquadBar`.
##
## Segmented HP bar for a squad: one segment per soldier of the full squad.
## Living soldiers' segments fill from the shared pool in order (the last one may
## be part-filled); fallen soldiers' segments are crossed with dark stripes.
##
##   const SquadBar = preload("res://scripts/ui/widgets/squad_bar.gd")
##   SquadBar.make(hp: float, hp_per: float, size: int, alive: int, height := 9, label := "") -> Control
##       label: hover text; default "<hp>/<per*size> HP · <alive>/<size> standing".
##   SquadBar.roster(so: Dictionary, height := 9) -> Control
##       RosterSquadBar for a roster squad (Soldier dict; uses scripts/meta/soldier.gd).
##   bar.set_values(hp, hp_per, size, alive, label := "")   update in place (HUDs)
## Expands horizontally; give it a width through its container.
extends Control

const JS = preload("res://scripts/core/js.gd")
const DB = preload("res://scripts/data/db.gd")
const Deps = preload("res://scripts/ui/deps.gd")

var hp := 0.0
var hp_per := 1.0
var squad_size := 6
var alive := 6
var label := ""


static func make(hp_: float, hp_per_: float, size_: int, alive_: int, height := 9, label_ := "") -> Control:
	var b: Control = load("res://scripts/ui/widgets/squad_bar.gd").new()
	b.custom_minimum_size = Vector2(24, height)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.set_values(hp_, hp_per_, size_, alive_, label_)
	return b


static func roster(so: Dictionary, height := 9) -> Control:
	var Soldier = Deps.soldier()
	var per: int = 1
	var cap: int = 0
	if Soldier != null:
		per = Soldier.soldier_stats(so).hp
		cap = Soldier.squad_hp_cap(so)
	var size_ := DB.squad_size(so.typeId)
	return make(so.hp, per, size_, so.men, height, "HP %d/%d (%d per soldier) · %d/%d soldiers" % [so.hp, cap, per, so.men, size_])


func set_values(hp_: float, hp_per_: float, size_: int, alive_: int, label_ := "") -> void:
	hp = hp_
	hp_per = maxf(1.0, hp_per_)
	squad_size = size_
	alive = alive_
	label = label_
	tooltip_text = label if label != "" else "%d/%s HP · %d/%d standing" % [maxi(0, JS.rnd(hp)), JS.num_str(hp_per * squad_size), alive, squad_size]
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	# Container: padding 1, gap 1, dark trough.
	draw_rect(Rect2(0, 0, w, h), Color(18 / 255.0, 10 / 255.0, 4 / 255.0, 0.8))
	draw_rect(Rect2(0, 0, w, 1), Color(0, 0, 0, 0.3))
	var n := maxi(1, squad_size)
	var low := hp / (hp_per * maxf(1.0, float(squad_size))) < 0.35
	var top := Color("#f0b450") if low else Color("#7fd36f")
	var bottom := Color("#c87a20") if low else Color("#3f9a33")
	var seg_w := (w - 2.0 - float(n - 1)) / n
	for i in n:
		var x := 1.0 + i * (seg_w + 1.0)
		var r := Rect2(x, 1.0, seg_w, h - 2.0)
		var fallen := i >= alive
		if fallen:
			_stripes(r)
			continue
		draw_rect(r, Color(70 / 255.0, 48 / 255.0, 26 / 255.0, 0.75))
		var f := clampf((hp - i * hp_per) / hp_per, 0.0, 1.0)
		if f > 0.0:
			var fr := Rect2(r.position, Vector2(r.size.x * f, r.size.y))
			draw_polygon(PackedVector2Array([fr.position, Vector2(fr.end.x, fr.position.y), fr.end, Vector2(fr.position.x, fr.end.y)]),
				PackedColorArray([top, top, bottom, bottom]))
			draw_rect(Rect2(fr.position, Vector2(fr.size.x, 1)), Color(1, 1, 1, 0.3))


## repeating-linear-gradient(135deg, rgba(8,4,2,.95) 0 2px, rgba(34,20,10,.95) 2px 4px)
func _stripes(r: Rect2) -> void:
	draw_rect(r, Color(8 / 255.0, 4 / 255.0, 2 / 255.0, 0.95))
	var light := Color(34 / 255.0, 20 / 255.0, 10 / 255.0, 0.95)
	var dir := Vector2(1, 1).normalized()
	var perp := Vector2(1, -1).normalized()
	var rect_poly := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var span := (r.size.x + r.size.y) * 0.7072 + 4.0
	var t := 2.0
	while t < span:
		var a := r.position + dir * t
		var b := r.position + dir * (t + 2.0)
		var band := PackedVector2Array([a - perp * 40.0, a + perp * 40.0, b + perp * 40.0, b - perp * 40.0])
		for poly in Geometry2D.intersect_polygons(band, rect_poly):
			draw_colored_polygon(poly, light)
		t += 4.0
