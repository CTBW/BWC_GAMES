## The portrait's readouts (health, morale) and the men's slim bars: a bar in a
## dark inked track with the numbers over it, Warcraft III style. A loss snaps
## the bar to its new value and leaves a lighter "ghost" that drains down after
## it; a gain fills with a bright sweep. Health shifts green → yellow → red;
## its numbers stay pale over the bar until it is below half, then take its colour.
##
##   var b = preload("res://scripts/ui/unit_bar/value_bar.gd").new()
##   b.kind = "hp"            # "hp" (colour by fraction) | "morale" (blue) | "plain"
##   b.numbers = true         # "184 / 192" over the bar
##   b.set_value(184, 192)    # animated from the last value; b.set_value(v, m, false) at once
##   b.count_up()             # the numbers tick up from zero (the bar opening)
extends Control

const Style = preload("res://scripts/ui/unit_bar/bar_style.gd")

const GHOST_HOLD := 0.35
const GHOST_RATE := 0.55

var kind := "hp"
var numbers := true
var number_size := 20
var bar_height := 8.0
var value := 0.0
var max_value := 1.0
## The ghost's fraction, draining down to the value's.
var _ghost := 0.0
var _ghost_wait := 0.0
var _sweep := -1.0
var _shown := 0.0
var _label: Label
var _pulse := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	if numbers:
		_label = Style.number("", number_size, Style.TEXT)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_label)
	_update_label()


func fraction() -> float:
	return clampf(value / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0


func set_value(v: float, m: float, animate := true) -> void:
	var before := fraction()
	value = v
	max_value = maxf(1.0, m)
	var now := fraction()
	if not animate:
		_ghost = now
		_shown = v
		_sweep = -1.0
	elif now < before - 1e-4:
		_ghost = maxf(_ghost, before)
		_ghost_wait = GHOST_HOLD
		_shown = v
	elif now > before + 1e-4:
		_sweep = 0.0
		_ghost = minf(_ghost, now)
		_shown = v
	_update_label()
	queue_redraw()


## The numbers count up from nothing to the value (the bar opening).
func count_up(time := 0.3) -> void:
	_shown = 0.0
	var t := create_tween()
	t.tween_method(func(x: float):
		_shown = x
		_update_label(), 0.0, value, time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func color() -> Color:
	match kind:
		"hp":
			return Style.hp_color(fraction())
		"morale":
			return Style.MORALE
	return Style.BRASS


func _update_label() -> void:
	if _label == null:
		return
	_label.text = "%d / %d" % [roundi(_shown), roundi(max_value)]
	var warn := kind == "hp" and fraction() < 0.5
	_label.add_theme_color_override("font_color", color().lightened(0.2) if warn else Style.TEXT)


func _process(dt: float) -> void:
	var busy := false
	if _ghost_wait > 0.0:
		_ghost_wait -= dt
		busy = true
	elif _ghost > fraction() + 1e-4:
		_ghost = maxf(fraction(), _ghost - GHOST_RATE * dt)
		busy = true
	if _sweep >= 0.0:
		_sweep += dt * 2.2
		if _sweep > 1.4:
			_sweep = -1.0
		busy = true
	# A low health pulse on the numbers.
	if kind == "hp" and fraction() < 0.25 and value > 0 and _label:
		_pulse += dt * 6.0
		_label.modulate = Color(1, 1, 1).lerp(Color(1.6, 0.7, 0.6), (sin(_pulse) * 0.5 + 0.5) * 0.6)
	elif _label and _label.modulate != Color.WHITE:
		_label.modulate = Color.WHITE
	if busy:
		queue_redraw()


func _draw() -> void:
	var h := minf(bar_height, size.y)
	var r := Rect2(0, (size.y - h) * 0.5, size.x, h) if numbers else Rect2(0, 0, size.x, size.y)
	draw_rect(r.grow(1.5), Style.INK)
	draw_rect(r, Color("#1d1814"))
	var inner := r.grow(-1.0)
	var c := color()
	if _ghost > fraction():
		draw_rect(Rect2(inner.position, Vector2(inner.size.x * _ghost, inner.size.y)), Color(1.0, 0.93, 0.78, 0.85))
	var fw := inner.size.x * fraction()
	if fw > 0.0:
		draw_rect(Rect2(inner.position, Vector2(fw, inner.size.y)), c.darkened(0.25))
		draw_rect(Rect2(inner.position, Vector2(fw, inner.size.y * 0.5)), c)
		draw_rect(Rect2(inner.position, Vector2(fw, maxf(1.0, inner.size.y * 0.18))), c.lightened(0.45))
		if _sweep >= 0.0:
			var x := inner.position.x + fw * _sweep
			for i in 6:
				var a := (1.0 - float(i) / 6.0) * 0.6
				var xx := x - float(i) * 3.0
				if xx > inner.position.x and xx < inner.position.x + fw:
					draw_rect(Rect2(xx, inner.position.y, 3.0, inner.size.y), Color(1, 1, 0.85, a))
	# Notches every tenth of the bar (only on the long readouts).
	if numbers and inner.size.x > 80:
		for i in range(1, 10):
			var x := inner.position.x + inner.size.x * i / 10.0
			draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), Color(0, 0, 0, 0.3), 1.0)
