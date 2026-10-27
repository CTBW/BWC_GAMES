## A stat plaque in the bar's middle field: the stat's icon in a small bevelled
## brass square, its name and its value; a value raised by gear shows green, one
## lowered by wounds red. Hover: the tooltip with the base value and every
## modifier (BarTips.stat).
##
##   var p = preload("res://scripts/ui/unit_bar/stat_plaque.gd").new()
##   p.set_stat({id, label, icon, value: "7–10", delta: 1, note, base, lines: ["Fine longsword +2"]})
##   p.tick()      the value ticks up into place (opening)
extends Control

const Style = preload("res://scripts/ui/unit_bar/bar_style.gd")
const Icon = preload("res://scripts/ui/widgets/icon.gd")
const Tip = preload("res://scripts/ui/widgets/tip.gd")
const BarTips = preload("res://scripts/ui/unit_bar/bar_tips.gd")

const SIZE := Vector2(120, 40)

var stat: Dictionary = {}
var hover := 0.0
var _name: Label
var _value: Label
var _icon: TextureRect
var _hovered := false


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()


## Its pieces, made with it (it works before it is in the tree, as in the headless tests).
func _build() -> void:
	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.position = Vector2(7, 7)
	_icon.size = Vector2(SIZE.y - 14, SIZE.y - 14)
	add_child(_icon)
	_name = Style.text("", 11, Style.MUTED, "sans")
	_name.position = Vector2(SIZE.y + 4, 2)
	add_child(_name)
	_value = Style.number("", 18, Style.TEXT)
	_value.position = Vector2(SIZE.y + 4, 13)
	add_child(_value)
	Tip.attach(self, func(): return BarTips.stat(stat))
	mouse_entered.connect(func():
		_hovered = true
		Style.sound(self, "hover", {"volume_db": -10.0})
		queue_redraw())
	mouse_exited.connect(func():
		_hovered = false
		queue_redraw())
	if not stat.is_empty():
		set_stat(stat)


func set_stat(s: Dictionary) -> void:
	stat = s
	if _value == null:
		return
	_name.text = String(s.get("label", "")).to_upper()
	_value.text = String(s.get("value", ""))
	var d := int(s.get("delta", 0))
	_value.add_theme_color_override("font_color", Style.BUFF if d > 0 else (Style.DEBUFF if d < 0 else Style.TEXT))
	_icon.texture = Icon.painted(String(s.get("icon", "missing")))
	queue_redraw()


## Numbers in the value tick up from zero (the opening).
func tick(time := 0.3) -> void:
	var text := String(stat.get("value", ""))
	var parts := []
	var rx := RegEx.create_from_string("\\d+(\\.\\d+)?")
	for m in rx.search_all(text):
		parts.append(m)
	if parts.is_empty():
		return
	var t := create_tween()
	t.tween_method(func(f: float):
		var out := text
		for i in range(parts.size() - 1, -1, -1):
			var m: RegExMatch = parts[i]
			var v := float(m.get_string()) * f
			var s := ("%.1f" % v) if m.get_string().contains(".") else str(roundi(v))
			out = out.substr(0, m.get_start()) + s + out.substr(m.get_end())
		_value.text = out, 0.0, 1.0, time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# The plaque: a dark slab with a fine brass edge, lit on hover.
	draw_rect(r, Style.INK)
	draw_rect(r.grow(-1), Style.WELL_2.lerp(Style.SOCKET, 0.6 if _hovered else 0.0))
	draw_rect(r.grow(-1), Color(Style.BRASS, 0.55 + (0.4 if _hovered else 0.0)), false, 1.0)
	draw_rect(Rect2(2, 2, size.x - 4, 8), Color(1, 1, 1, 0.04))
	Style.socket(self, Rect2(3, 3, size.y - 6, size.y - 6), 1.0 if _hovered else 0.0, 3.0, Color("#262019"))
