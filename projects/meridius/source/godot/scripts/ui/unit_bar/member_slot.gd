## One man of the selected squad in the bar's squad grid (Warcraft III's group
## selection): his headshot (HeadPortrait.still of his own 3D figure; the type's
## baked portrait until it is taken), his health under it. The focused man sits
## raised in a glowing gold frame; a fallen man is greyed with a skull and a
## crack; a man out of sight (a foe in the fog) shows "?". Click: `picked`.
##
##   var m = preload("res://scripts/ui/unit_bar/member_slot.gd").new()
##   m.set_man({hp, hp_max, alive, hidden, lead, figure, type_id, variant}, focused)
extends Control

signal picked

const Style = preload("res://scripts/ui/unit_bar/bar_style.gd")
const HeadPortrait = preload("res://scripts/ui/unit_bar/head_portrait.gd")
const Assets = preload("res://scripts/render/assets.gd")
const Tip = preload("res://scripts/ui/widgets/tip.gd")
const BarTips = preload("res://scripts/ui/unit_bar/bar_tips.gd")
const ValueBar = preload("res://scripts/ui/unit_bar/value_bar.gd")

var man: Dictionary = {}
var focused := false
var faction := "player"
var face := 54.0:
	set(v):
		face = v
		if _pic != null:
			_place()
var _pic: TextureRect
var _bar: Control
var _hovered := false
var _pressed := false
var _key := ""
var _lift := 0.0
var _flash := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_build()


## Its pieces, made with it (it works before it is in the tree, as in the headless tests).
func _build() -> void:
	_pic = TextureRect.new()
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_pic.material = Style.icon_material()
	add_child(_pic)
	_bar = ValueBar.new()
	_bar.numbers = false
	add_child(_bar)
	Tip.attach(self, func(): return BarTips.man(man, faction))
	mouse_entered.connect(func():
		_hovered = true
		Style.sound(self, "hover", {"volume_db": -10.0})
		queue_redraw())
	mouse_exited.connect(func():
		_hovered = false
		_pressed = false
		queue_redraw())


func _ready() -> void:
	var st := HeadPortrait.studio(self)
	if st != null and not st.still_ready.is_connected(_on_still):
		st.still_ready.connect(_on_still)
	_place()
	if not man.is_empty():
		set_man(man, focused)


func set_man(m: Dictionary, is_focused: bool) -> void:
	var was_alive := bool(man.get("alive", true))
	var hp_before := float(man.get("hp", -1))
	man = m
	focused = is_focused
	if _pic == null:
		return
	_bar.set_value(float(m.get("hp", 0)), float(m.get("hp_max", 1)), hp_before >= 0.0)
	if hp_before >= 0.0 and float(m.get("hp", 0)) < hp_before and bool(m.get("alive", true)):
		_flash = 1.0
	_picture()
	var mat := _pic.material as ShaderMaterial
	var dead := not bool(m.get("alive", true))
	mat.set_shader_parameter("gray", 1.0 if dead else 0.0)
	mat.set_shader_parameter("bright", 0.55 if dead else 1.0)
	_bar.visible = not dead and not bool(m.get("hidden", false))
	if was_alive and dead:
		_flash = 1.0
	queue_redraw()


func _picture() -> void:
	var fig: Variant = man.get("figure")
	_key = HeadPortrait.still_key(fig) if fig != null else ""
	var tex: Texture2D = HeadPortrait.still(fig, self) if fig != null else null
	if tex == null:
		var s := Assets.sprite("portrait_" + String(man.get("type_id", "")), int(man.get("variant", 0)))
		if not s.is_empty() and s.get("tex") != null:
			var at := AtlasTexture.new()
			at.atlas = s.tex
			at.region = s.region
			tex = at
	_pic.texture = tex
	_pic.visible = not bool(man.get("hidden", false))


func _on_still(key: String) -> void:
	if key == _key and is_instance_valid(self):
		_picture()


func _place() -> void:
	custom_minimum_size = Vector2(face + 8, face + 18)
	_pic.position = Vector2(4, 4 - _lift)
	_pic.size = Vector2(face, face)
	_bar.position = Vector2(4, face + 9 - _lift)
	_bar.size = Vector2(face, 6)


func _process(dt: float) -> void:
	var goal := 3.0 if focused else (1.5 if _hovered else 0.0)
	if _pressed:
		goal = -1.0
	var busy := false
	if absf(_lift - goal) > 0.01:
		_lift = move_toward(_lift, goal, dt * 30.0)
		_place()
		busy = true
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - dt * 3.5)
		(_pic.material as ShaderMaterial).set_shader_parameter("flash", _flash * 0.7)
		busy = true
	if busy or focused:
		queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_pressed = e.pressed
		if not e.pressed and _hovered:
			picked.emit()
		accept_event()
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2(2, 2 - _lift), Vector2(face + 4, face + 4))
	var dead := not bool(man.get("alive", true))
	if focused:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
		draw_rect(r.grow(5), Color(Style.BRASS_LIGHT, 0.18 + 0.14 * pulse))
		draw_rect(r.grow(3), Color(Style.BRASS_LIGHT, 0.35 + 0.2 * pulse))
	# His shadow when raised.
	if _lift > 0.5:
		draw_rect(Rect2(r.position + Vector2(2, _lift + 3), r.size), Color(0, 0, 0, 0.35))
	var tint := Style.BRASS if not dead else Color("#6b6358")
	if faction != "player" and not dead:
		tint = Style.ENEMY.lightened(0.25)
	Style.socket(self, r, 1.0 if focused else (0.5 if _hovered else 0.0), 2.0 if not focused else 3.0,
		Style.PLAYER.darkened(0.6) if faction == "player" else Style.ENEMY.darkened(0.6), tint)
	if bool(man.get("hidden", false)):
		var q := Style.INK
		draw_string(get_theme_default_font(), r.get_center() + Vector2(-6, 9), "?", HORIZONTAL_ALIGNMENT_CENTER, -1, 26, Style.MUTED)
		return
	if bool(man.get("lead", false)) and not dead:
		# The captain's mark: a small gold lozenge at the top.
		var c := Vector2(r.get_center().x, r.position.y + 1)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)]), Style.INK)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -3.5), c + Vector2(3.5, 0), c + Vector2(0, 3.5), c + Vector2(-3.5, 0)]), Style.BRASS_LIGHT)


## Drawn over the picture (the skull and crack on a fallen man).
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAW and _pic != null and not bool(man.get("alive", true)):
		_over.call_deferred()


func _over() -> void:
	if not has_node("Fallen"):
		var o := Control.new()
		o.name = "Fallen"
		o.mouse_filter = Control.MOUSE_FILTER_IGNORE
		o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		o.draw.connect(func():
			if bool(man.get("alive", true)):
				return
			var r := Rect2(Vector2(4, 4), Vector2(face, face))
			var c := r.get_center()
			# The crack across the glass.
			var crack := PackedVector2Array([r.position + Vector2(face * 0.15, 2), c + Vector2(-4, -6), c + Vector2(3, 2),
				c + Vector2(-2, 10), r.end - Vector2(face * 0.3, 2)])
			o.draw_polyline(crack, Color(0, 0, 0, 0.7), 3.0, true)
			o.draw_polyline(crack, Color(1, 1, 1, 0.45), 1.0, true)
			# The skull.
			var s := face * 0.2
			o.draw_circle(c + Vector2(0, -2), s + 2, Style.INK)
			o.draw_circle(c + Vector2(0, -2), s, Color("#e8dcc0"))
			o.draw_rect(Rect2(c + Vector2(-s * 0.6, s * 0.5), Vector2(s * 1.2, s * 0.7)), Color("#e8dcc0"))
			o.draw_rect(Rect2(c + Vector2(-s * 0.6, s * 0.5), Vector2(s * 1.2, s * 0.7)), Style.INK, false, 1.5)
			o.draw_circle(c + Vector2(-s * 0.4, -2), s * 0.28, Style.INK)
			o.draw_circle(c + Vector2(s * 0.4, -2), s * 0.28, Style.INK))
		add_child(o)
	get_node("Fallen").queue_redraw()
