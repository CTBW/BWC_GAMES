## One active effect on the selected unit: its icon in a frame coloured by its
## kind (buff green, debuff red, state gold), a turn counter at the bottom
## right and a stack count at the top right when it has them. New effects pop
## in; an effect that ends fades out (`expire()`, which frees it). Hover: name,
## description, duration and source (BarTips.status).
##
##   var s = preload("res://scripts/ui/unit_bar/status_icon.gd").new()
##   s.set_effect({id, name, icon, kind: "buff" | "debuff" | "state", turns: -1, stacks: 0, desc, source})
extends Control

const Style = preload("res://scripts/ui/unit_bar/bar_style.gd")
const Icon = preload("res://scripts/ui/widgets/icon.gd")
const Tip = preload("res://scripts/ui/widgets/tip.gd")
const BarTips = preload("res://scripts/ui/unit_bar/bar_tips.gd")

const SIZE := 34.0

var effect: Dictionary = {}
var _icon: TextureRect
var _turns: Label
var _stacks: Label
var _hovered := false
var _going := false


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_PASS
	pivot_offset = Vector2(SIZE, SIZE) * 0.5
	_build()


## Its pieces, made with it (it works before it is in the tree, as in the headless tests).
func _build() -> void:
	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.position = Vector2(5, 5)
	_icon.size = Vector2(SIZE - 10, SIZE - 10)
	add_child(_icon)
	_turns = Style.number("", 13, Style.TEXT)
	_turns.position = Vector2(SIZE - 14, SIZE - 19)
	add_child(_turns)
	_stacks = Style.number("", 12, Style.BRASS_LIGHT)
	_stacks.position = Vector2(SIZE - 12, -4)
	add_child(_stacks)
	Tip.attach(self, func(): return BarTips.status(effect))
	mouse_entered.connect(func():
		_hovered = true
		Style.sound(self, "hover", {"volume_db": -10.0})
		queue_redraw())
	mouse_exited.connect(func():
		_hovered = false
		queue_redraw())
	set_effect(effect)


func set_effect(e: Dictionary) -> void:
	effect = e
	if _icon == null:
		return
	_icon.texture = Icon.painted(String(e.get("icon", "missing")))
	var turns := int(e.get("turns", -1))
	_turns.text = str(turns) if turns > 0 else ""
	var stacks := int(e.get("stacks", 0))
	_stacks.text = "×%d" % stacks if stacks > 1 else ""
	queue_redraw()


func frame_color() -> Color:
	match String(effect.get("kind", "state")):
		"buff":
			return Style.BUFF
		"debuff":
			return Style.DEBUFF
	return Style.STATE


func pop_in(delay := 0.0) -> void:
	scale = Vector2(0.2, 0.2)
	modulate.a = 0.0
	var t := create_tween()
	t.tween_interval(delay)
	t.tween_property(self, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "modulate:a", 1.0, 0.12)


## Fades out and frees itself.
func expire() -> void:
	if _going:
		return
	_going = true
	# Its name is free at once for the effect's next icon.
	name = "Ended_" + String(name)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.3)
	t.parallel().tween_property(self, "scale", Vector2(0.6, 0.6), 0.3)
	t.tween_callback(queue_free)


func is_expiring() -> bool:
	return _going


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var c := frame_color()
	draw_rect(r.grow(1), Style.INK)
	Style.bevel(self, r, 3.0, c.lightened(0.3), c.darkened(0.5), c)
	draw_rect(r.grow(-3), Style.INK)
	draw_rect(r.grow(-4), Color("#15120f"))
	if _hovered:
		draw_rect(r.grow(2), Color(c, 0.55), false, 2.0)
	if int(effect.get("turns", -1)) > 0:
		draw_circle(Vector2(SIZE - 7, SIZE - 9), 8.0, Style.INK)
		draw_circle(Vector2(SIZE - 7, SIZE - 9), 6.8, c.darkened(0.55))
