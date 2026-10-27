## Port of common.tsx `Portrait`: the head-and-shoulders portrait of a unit type
## on a blue (player) or red (enemy) gradient with a dark vignette, in a wooden
## frame (`.portrait`: 2 px border, gold inner line, drop shadow). `dead`
## renders it in greyscale (the Fallen list).
##
##   const Portrait = preload("res://scripts/ui/widgets/portrait.gd")
##   Portrait.make(type_id: String, variant := 0, size := 56, dead := false) -> Control
##   portrait.set_unit(type_id, variant, dead := false)   change it in place
## The sprite comes from scripts/render/assets.gd: Assets.sprite("portrait_<type>", variant)
## (dict with tex + region). Until that registry exists only the backdrop is drawn.
extends Control

const DB = preload("res://scripts/data/db.gd")
const Deps = preload("res://scripts/ui/deps.gd")
const PaperStyle = preload("res://scripts/ui/styles/paper_style.gd")
const ForgedStyle = preload("res://scripts/ui/styles/forged_style.gd")

const SHADER := """
shader_type canvas_item;
uniform bool gray = false;
uniform vec2 box_size = vec2(56.0);
uniform float radius = 3.0;
varying vec2 local;
void vertex() { local = VERTEX; }
void fragment() {
	vec4 c = COLOR;
	if (gray) {
		float l = dot(c.rgb, vec3(0.3, 0.59, 0.11));
		c.rgb = vec3(l);
	}
	vec2 q = abs(local - box_size * 0.5) - (box_size * 0.5 - radius);
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	c.a *= clamp(0.5 - d, 0.0, 1.0);
	COLOR = c;
}
"""

static var _shader: Shader
static var _frame: StyleBox

var type_id := "footman"
var variant := 0
var dead := false
var _content: Control


static func make(type_id_: String, variant_ := 0, size_ := 56, dead_ := false) -> Control:
	var p: Control = load("res://scripts/ui/widgets/portrait.gd").new()
	p.custom_minimum_size = Vector2(size_, size_)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.set_unit(type_id_, variant_, dead_)
	return p


func _init() -> void:
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.position = Vector2(4, 4)
	_content.draw.connect(_draw_content)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	_content.material = m
	add_child(_content)
	resized.connect(_on_resized)


func set_unit(type_id_: String, variant_ := 0, dead_ := false) -> void:
	type_id = type_id_
	variant = variant_
	dead = dead_
	(_content.material as ShaderMaterial).set_shader_parameter("gray", dead)
	queue_redraw()
	_content.queue_redraw()


func _on_resized() -> void:
	_content.size = size - Vector2(8, 8)
	(_content.material as ShaderMaterial).set_shader_parameter("box_size", _content.size)
	_content.queue_redraw()


static func _frame_style() -> StyleBox:
	if _frame == null:
		var s := ForgedStyle.new()
		s.corner_radius = 1.0
		s.metal_width = 4.0
		s.ornament = 0
		s.metal_color = Color("#9f9274")
		s.border_left = 2
		s.border_top = 2
		s.border_right = 2
		s.border_bottom = 2
		s.border_color = Color("#3a2414")
		s.rings = [[1.0, Color(201 / 255.0, 154 / 255.0, 60 / 255.0, 0.5)]]
		s.shadow_color = Color(0, 0, 0, 0.4)
		s.shadow_offset = Vector2(0, 2)
		s.shadow_blur = 5.0
		s.bg_color = Color("#3a2a1a")
		_frame = s
	return _frame


func _draw() -> void:
	# Frame behind; the content draws over its centre, the ring and border on top.
	var s := _frame_style()
	draw_style_box(s, Rect2(Vector2.ZERO, size))


func _draw_content() -> void:
	var c := _content
	var sz := c.size
	var enemy: bool = DB.UNIT_TYPES.get(type_id, {}).get("faction", "") == "enemy"
	var top := Color("#6a2a1e") if enemy else Color("#3c5a9a")
	var bottom := Color("#2a120c") if enemy else Color("#1a2440")
	c.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(sz.x, 0), sz, Vector2(0, sz.y)]), PackedColorArray([top, top, bottom, bottom]))
	var A = Deps.assets()
	if A != null and FileAccess.file_exists("res://assets/sprites.json"):
		var spr: Dictionary = A.sprite("portrait_" + type_id, variant)
		if not spr.is_empty():
			A.draw_sprite_rect(c, spr, Rect2(Vector2.ZERO, sz), Color.WHITE)
	# Vignette: radial from 0.3 to 0.75 of the size, clear to 45 % black.
	var center := sz * 0.5
	var r0 := sz.x * 0.3
	var r1 := sz.x * 0.75
	var steps := 10
	for i in steps:
		var ra := lerpf(r0, r1, float(i) / steps)
		var rb := lerpf(r0, r1, float(i + 1) / steps)
		var aa := 0.45 * float(i) / steps
		var ab := 0.45 * float(i + 1) / steps
		_ring(c, center, ra, rb, Color(0, 0, 0, aa), Color(0, 0, 0, ab))
	# The outer radius (0.75) lies beyond the corners (0.707), so the ramp covers
	# the whole square; the shader clips it to the frame's inner radius.


func _ring(c: Control, center: Vector2, ra: float, rb: float, ca: Color, cb: Color) -> void:
	var n := 32
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for k in n:
		var a := TAU * k / n
		var d := Vector2(cos(a), sin(a))
		pts.append(center + d * ra)
		pts.append(center + d * rb)
		cols.append(ca)
		cols.append(cb)
	for k in n:
		var i0 := k * 2
		var i1 := ((k + 1) % n) * 2
		idx.append_array([i0, i1, i1 + 1, i0, i1 + 1, i0 + 1])
	RenderingServer.canvas_item_add_triangle_array(c.get_canvas_item(), idx, pts, cols)
