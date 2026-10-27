## One of the six inventory slots: a bevelled socket; empty, a faint carved
## ring (the empty socket); filled, the item's icon over an inner glow in its
## rarity's colour, and its count or charges in the corner; hidden (a foe's
## pack), "?". Hover: the item's tooltip (BarTips.item). Read-only in battle.
##
##   var s = preload("res://scripts/ui/unit_bar/item_slot.gd").new()
##   s.set_item({id, name, icon, rarity, count: -1, desc, lines})   {} empty, {"hidden": true}
extends Control

const Style = preload("res://scripts/ui/unit_bar/bar_style.gd")
const Icon = preload("res://scripts/ui/widgets/icon.gd")
const Tip = preload("res://scripts/ui/widgets/tip.gd")
const BarTips = preload("res://scripts/ui/unit_bar/bar_tips.gd")

const SIZE := Vector2(52, 44)

var item: Dictionary = {}
var _icon: TextureRect
var _count: Label
var _hovered := false
var _glint := -1.0


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS
	pivot_offset = SIZE * 0.5
	_build()


## Its pieces, made with it (it works before it is in the tree, as in the headless tests).
func _build() -> void:
	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.material = Style.icon_material()
	_icon.position = Vector2(9, 6)
	_icon.size = SIZE - Vector2(18, 12)
	add_child(_icon)
	_count = Style.number("", 13, Style.TEXT)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.position = Vector2(SIZE.x - 30, SIZE.y - 21)
	_count.size = Vector2(26, 18)
	add_child(_count)
	Tip.attach(self, func(): return BarTips.item(item))
	mouse_entered.connect(func():
		_hovered = true
		if not item.is_empty():
			Style.sound(self, "ability_hover", {"volume_db": -8.0})
			_glint = 0.0
		queue_redraw())
	mouse_exited.connect(func():
		_hovered = false
		queue_redraw())
	set_item(item)


func set_item(it: Dictionary) -> void:
	item = it if it != null else {}
	if _icon == null:
		return
	var hidden := bool(item.get("hidden", false))
	_icon.texture = Icon.painted(String(item.icon)) if item.has("icon") and not hidden else null
	var n := int(item.get("count", -1))
	_count.text = str(n) if n >= 0 else ""
	mouse_filter = Control.MOUSE_FILTER_PASS if not item.is_empty() else Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _process(dt: float) -> void:
	if _glint >= 0.0:
		_glint += dt * 1.6
		(_icon.material as ShaderMaterial).set_shader_parameter("sweep", _glint if _glint < 1.2 else -1.0)
		if _glint >= 1.2:
			_glint = -1.0


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var empty := item.is_empty()
	Style.socket(self, r, 0.8 if _hovered and not empty else 0.0, 3.0, Color("#12161b"))
	var inner := r.grow(-4)
	if bool(item.get("hidden", false)):
		draw_string(get_theme_default_font(), inner.get_center() + Vector2(-7, 10), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Style.MUTED)
		return
	if empty:
		# The empty socket: a faint carved ring and its shadow.
		var c := inner.get_center()
		draw_arc(c + Vector2(0, 1), 12.0, 0, TAU, 32, Color(1, 1, 1, 0.06), 3.0, true)
		draw_arc(c, 12.0, 0, TAU, 32, Color(0, 0, 0, 0.55), 2.0, true)
		draw_circle(c, 3.0, Color(0, 0, 0, 0.35))
		return
	var col: Color = Style.RARITY.get(String(item.get("rarity", "common")), Style.RARITY.common)
	# The rarity's inner glow, strongest at the rim.
	for i in 5:
		draw_rect(inner.grow(-float(i) * 2.5), Color(col, 0.16 - i * 0.025), false, 2.5)
	draw_rect(inner, Color(col, 0.5 if _hovered else 0.32), false, 1.5)
