## The headshot's frame (Warcraft III's portrait frame, in the company's
## iron and brass): the council frame's painted master (painted_frames.gd;
## its corners whole, its rails stretched) round the portrait, a crest over
## the top rail (a lapis lozenge between brass scrolls on an iron plate), a
## clasp under the bottom rail and clamps on the side rails. A foe's frame is
## grim instead, the same size: split timber in rusted iron straps, corner
## blocks of cracked stone set in iron with a ruby (foe-frame.png), one of
## those blocks for its crest and a smaller one for its clasp; where that
## painting is not on disk, the company's frame with its lapis turned ruby. The portrait
## sits sunk under the rails, shadowed at the top (no glass sheen: its black
## stays flat). No heraldry: lines, scrolls, rivets and lozenges only.
## `sheen()` runs a light along the company's brass (a new unit in the frame);
## the crest's gem sparkles now and then.
##
##   var f = preload("res://scripts/ui/unit_bar/portrait_frame.gd").new()
##   f.unit = 1.0                        # its scale (1 at 1080p)
##   f.set_opening(Vector2(176, 156))     # the portrait's size: the frame's follows
##   f.portrait.show_figure(...)          # the HeadPortrait inside
##   f.faction = "enemy"
## The crest stands CREST_RISE * unit above the frame's rect.
extends Control

const Style = preload("res://scripts/ui/unit_bar/bar_style.gd")
const HeadPortrait = preload("res://scripts/ui/unit_bar/head_portrait.gd")
const Painted = preload("res://scripts/ui/styles/painted_frames.gd")

## The master's frame (source pixels): its rect, its corners, the inner edges
## of its rails from the rect's sides (left, top, right, bottom) and the rails'
## middles. The council frame's set the frame's size, a foe's too.
const SRC := Rect2(37, 49, 1462, 916)
const CORNER := Vector2(275, 238)
const INSET := [131.0, 120.0, 130.0, 126.0]
const RAIL_MID := [81.5, 79.5, 80.5, 83.0]
## A foe's grim master (art/ui/epic/README.md), the same measures, fitted into
## the council frame's rect (_fit); its corner block (stone in iron) and the
## middle of the ruby in it (a fraction of the block). Loaded when it is on disk.
const FOE_PATH := "res://assets/ui/epic/foe-frame.png"
const FOE_SRC := Rect2(4.8, 4.8, 1434.4, 902.3)
const FOE_CORNER := Vector2(238, 230)
const FOE_INSET := [136.0, 140.0, 134.0, 129.0]
const FOE_RAIL_MID := [79.5, 86.0, 78.0, 78.0]
const FOE_BLOCK := Rect2(6, 5, 180, 176)
const FOE_GEM := Vector2(0.41, 0.43)
## Display pixels per source pixel at unit 1, and the half size the runtime
## copy is made at (mipmapped: the master has none, and is drawn small).
const SCALE := 0.135
const COPY := 0.5
## How far the portrait reaches under the rails, and the crest above the frame.
const TUCK := 3.0
const CREST_RISE := 13.0

const BRASS_DEEP := Color("#4a3418")
const BRASS_DARK := Color("#725126")
const BRASS_MID := Color("#ad7d43")
const BRASS_LIGHT := Color("#dbb063")
const BRASS_SHINE := Color("#f6dc96")
const IRON_LIGHT := Color("#4b545e")
const IRON := Color("#33363c")
const IRON_DARK := Color("#1d1f23")
const LAPIS_DEEP := Color("#0c1a58")
const LAPIS := Color("#2443a6")
const LAPIS_LIGHT := Color("#4f72d8")
const LAPIS_SHINE := Color("#b9ccff")

const SHADER := """
shader_type canvas_item;
// The frame's metal: lapis turned ruby (a foe's, without its own frame), and a light run along the brass.
uniform float ruby = 0.0;
uniform float sheen = -1.0;
uniform vec2 extent = vec2(200.0, 180.0);
varying vec2 local;
vec3 hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}
vec3 rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}
void vertex() {
	local = VERTEX;
}
void fragment() {
	// COLOR comes in as the texture times the vertex colour.
	vec4 c = COLOR;
	vec3 h = hsv(c.rgb);
	if (ruby > 0.0) {
		float lapis = step(0.55, h.x) * step(h.x, 0.76) * smoothstep(0.42, 0.62, h.y);
		c.rgb = mix(c.rgb, rgb(vec3(0.99, h.y, min(1.0, h.z * 1.3 + 0.04))), lapis * ruby);
	}
	if (sheen > -0.5) {
		float brass = step(0.05, h.x) * step(h.x, 0.17) * smoothstep(0.3, 0.5, h.y);
		float d = local.x / extent.x + local.y / extent.y * 0.6 - sheen * 2.2 + 0.3;
		c.rgb += vec3(1.0, 0.9, 0.62) * brass * smoothstep(0.1, 0.0, abs(d)) * 0.6;
	}
	COLOR = c;
}
"""

## The masters' runtime copies (_master), by master.
static var _copies := {}
static var _shader: Shader
static var _foe_master: Texture2D

var unit := 1.0
var faction := "player":
	set(v):
		faction = v
		if portrait:
			portrait.faction = v
		if _over:
			(_over.material as ShaderMaterial).set_shader_parameter("ruby", 1.0 if v != "player" and not _grim() else 0.0)
			_over.queue_redraw()
var portrait: Control
var _over: Control
var _opening := Vector2(176, 156)
var _sheen := -1.0
var _spark := -1.0
var _spark_in := 2.5


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


## Its pieces, made with it (it works before it is in the tree, as in the headless tests).
func _build() -> void:
	portrait = HeadPortrait.new()
	portrait.faction = faction
	add_child(portrait)
	_over = Control.new()
	_over.name = "Frame"
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("ruby", 1.0 if faction != "player" and not _grim() else 0.0)
	_over.material = m
	_over.draw.connect(_draw_frame)
	add_child(_over)
	set_opening(_opening)


## Sizes the frame round a portrait of `opening` pixels.
func set_opening(opening: Vector2) -> void:
	_opening = opening
	var s := SCALE * unit
	size = opening + Vector2(INSET[0] + INSET[2], INSET[1] + INSET[3]) * s - Vector2(TUCK, TUCK) * 2.0 * unit
	custom_minimum_size = size
	if portrait == null:
		return
	portrait.position = Vector2(INSET[0], INSET[1]) * s - Vector2(TUCK, TUCK) * unit
	portrait.size = opening
	_over.size = size
	(_over.material as ShaderMaterial).set_shader_parameter("extent", size)
	queue_redraw()
	_over.queue_redraw()


## The portrait's rect inside the frame (the rails' inner edges).
func opening_rect() -> Rect2:
	var s := SCALE * unit
	return Rect2(Vector2(INSET[0], INSET[1]) * s, size - Vector2(INSET[0] + INSET[2], INSET[1] + INSET[3]) * s)


## A light runs along the brass (a new unit in the frame); a foe's has none.
func sheen() -> void:
	if not _grim():
		_sheen = 0.0


## A foe's frame: the grim one (when its painting is on disk).
func _grim() -> bool:
	return faction != "player" and _foe() != null


## The grim master, or null where it is not on disk.
static func _foe() -> Texture2D:
	if _foe_master == null and ResourceLoader.exists(FOE_PATH):
		_foe_master = load(FOE_PATH)
	return _foe_master


func _process(dt: float) -> void:
	var m := _over.material as ShaderMaterial
	if _sheen >= 0.0:
		_sheen += dt * 1.5
		if _sheen > 1.3:
			_sheen = -1.0
		m.set_shader_parameter("sheen", _sheen)
	_spark_in -= dt
	if _spark_in <= 0.0:
		_spark = 0.0
		_spark_in = randf_range(4.0, 8.0)
	if _spark >= 0.0:
		_spark += dt * 2.2
		if _spark > 1.0:
			_spark = -1.0
		_over.queue_redraw()


# --- Drawing ----------------------------------------------------------------------------------

## Behind the portrait: the frame's shadow on the console.
func _draw() -> void:
	var u := unit
	var r := Rect2(Vector2.ZERO, size)
	for i in 6:
		var g := float(i) * 1.6 * u
		draw_rect(Rect2(r.position + Vector2(2, 4) * u - Vector2(g, g), r.size + Vector2(g, g) * 2.0), Color(0, 0, 0, 0.1))


func _draw_frame() -> void:
	var u := unit
	var o := opening_rect()
	_recess(o)
	_nine(Rect2(Vector2.ZERO, size))
	if _grim():
		var f := _fit(true) * u
		_block(Vector2(size.x * 0.5, FOE_RAIL_MID[1] * f.y), 32.0 * u)
		_block(Vector2(size.x * 0.5, size.y - FOE_RAIL_MID[3] * f.y), 21.0 * u)
		return
	var s := SCALE * unit
	var mid_y := size.y * 0.5
	_strap(Vector2(RAIL_MID[0] * s, mid_y), u)
	_strap(Vector2(size.x - RAIL_MID[2] * s, mid_y), u)
	_clasp(Vector2(size.x * 0.5, size.y - RAIL_MID[3] * s), u)
	_crest(Vector2(size.x * 0.5, RAIL_MID[1] * s), u)


## The portrait sunk under the rails: an ink lip, a shadow from the top rail
## and the sides (no sheen over it: its black stays flat, in its steps).
func _recess(o: Rect2) -> void:
	var u := unit
	var dark := Color(0, 0, 0, 0.6)
	var clear := Color(0, 0, 0, 0)
	_band(Rect2(o.position, Vector2(o.size.x, 12 * u)), dark, dark, clear, clear)
	_band(Rect2(o.position, Vector2(7 * u, o.size.y)), Color(0, 0, 0, 0.45), clear, clear, Color(0, 0, 0, 0.45))
	_band(Rect2(Vector2(o.end.x - 5 * u, o.position.y), Vector2(5 * u, o.size.y)), clear, Color(0, 0, 0, 0.35), Color(0, 0, 0, 0.35), clear)
	_over.draw_rect(o, Color(0, 0, 0, 0.8), false, 1.5 * u)


## A rect filled with a colour per corner (top left, top right, bottom right, bottom left).
func _band(r: Rect2, tl: Color, tr: Color, br: Color, bl: Color) -> void:
	_over.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([tl, tr, br, bl]))


## The painted frame: corners at their own proportions, rails stretched, no centre.
func _nine(r: Rect2) -> void:
	var grim := _grim()
	var master: Texture2D = _foe() if grim else Painted.COUNCIL
	var tex := _master(master)
	var k := 1.0 if tex == master else COPY
	var src_rect: Rect2 = FOE_SRC if grim else SRC
	var src := Rect2(src_rect.position * k, src_rect.size * k)
	var c: Vector2 = (FOE_CORNER if grim else CORNER) * k
	var corner: Vector2 = (FOE_CORNER if grim else CORNER) * _fit(grim) * unit
	var sx := [src.position.x, src.position.x + c.x, src.end.x - c.x, src.end.x]
	var sy := [src.position.y, src.position.y + c.y, src.end.y - c.y, src.end.y]
	var dx := [r.position.x, r.position.x + corner.x, r.end.x - corner.x, r.end.x]
	var dy := [r.position.y, r.position.y + corner.y, r.end.y - corner.y, r.end.y]
	for y in 3:
		for x in 3:
			if x == 1 and y == 1:
				continue
			var dest := Rect2(dx[x], dy[y], dx[x + 1] - dx[x], dy[y + 1] - dy[y])
			if dest.has_area():
				_over.draw_texture_rect_region(tex, dest, Rect2(sx[x], sy[y], sx[x + 1] - sx[x], sy[y + 1] - sy[y]))


## Display pixels per source pixel at unit 1 (x and y): the council frame's
## SCALE, or what fits a foe's master into the same rect round the same opening.
static func _fit(grim: bool) -> Vector2:
	if not grim:
		return Vector2(SCALE, SCALE)
	return Vector2((INSET[0] + INSET[2]) / (FOE_INSET[0] + FOE_INSET[2]),
		(INSET[1] + INSET[3]) / (FOE_INSET[1] + FOE_INSET[3])) * SCALE


## A master at half size with mipmaps (made once); the master itself where
## its pixels cannot be read (a headless run).
static func _master(master: Texture2D) -> Texture2D:
	if _copies.has(master):
		return _copies[master]
	var img: Image = master.get_image() if DisplayServer.get_name() != "headless" else null
	if img == null or img.is_empty():
		return master
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.resize(int(img.get_width() * COPY), int(img.get_height() * COPY), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	_copies[master] = ImageTexture.create_from_image(img)
	return _copies[master]


## A foe's crest or clasp: the master's corner block (stone in iron, its ruby),
## `width` wide, centred on `c`, its shadow under it; the ruby sparkles on the crest.
func _block(c: Vector2, width: float) -> void:
	var tex := _master(_foe())
	var k := 1.0 if tex == _foe() else COPY
	var sz := Vector2(width, width * FOE_BLOCK.size.y / FOE_BLOCK.size.x)
	var r := Rect2(c - sz * 0.5, sz)
	for i in 3:
		var g := (1.0 + i) * unit
		_over.draw_rect(Rect2(r.position + Vector2(1.5, 2.5) * unit - Vector2(g, g) * 0.5, r.size + Vector2(g, g)), Color(0, 0, 0, 0.16))
	_over.draw_texture_rect_region(tex, r, Rect2(FOE_BLOCK.position * k, FOE_BLOCK.size * k))
	if _spark >= 0.0 and width >= 30.0 * unit:
		_sparkle(r.position + sz * FOE_GEM - sz * Vector2(0.08, 0.1), unit)


## The crest over the top rail: an iron plate in an ogee arch, rimmed in brass,
## an engraved line inside it, brass scrolls either side of a lapis lozenge and
## a rivet at each end.
func _crest(c: Vector2, u: float) -> void:
	var shape := [Vector2(-36, 5), Vector2(-36, -1), Vector2(-28, -5), Vector2(-19, -7), Vector2(-12, -11),
		Vector2(-6.5, -17), Vector2(0, -23), Vector2(6.5, -17), Vector2(12, -11), Vector2(19, -7),
		Vector2(28, -5), Vector2(36, -1), Vector2(36, 5), Vector2(21, 8), Vector2(9, 10.5), Vector2(0, 13),
		Vector2(-9, 10.5), Vector2(-21, 8)]
	_plate(c, u, shape)
	for side in [-1.0, 1.0]:
		_scroll(c + Vector2(side * 20.0, -2.0) * u, side, u)
		_rivet(c + Vector2(side * 30.0, 1.0) * u, 2.2 * u)
	_lozenge(c + Vector2(0, -5) * u, Vector2(8.5, 12.5) * u, u)
	if _spark >= 0.0:
		_sparkle(c + Vector2(-3, -12) * u, u)


## The clasp under the bottom rail: a smaller inverted plate, a lozenge and two rivets.
func _clasp(c: Vector2, u: float) -> void:
	var shape := [Vector2(-21, -5), Vector2(-21, 1), Vector2(-13, 4), Vector2(-6, 7.5), Vector2(0, 12),
		Vector2(6, 7.5), Vector2(13, 4), Vector2(21, 1), Vector2(21, -5), Vector2(10, -7), Vector2(0, -8), Vector2(-10, -7)]
	_plate(c, u, shape)
	for side in [-1.0, 1.0]:
		_rivet(c + Vector2(side * 14.0, -1.0) * u, 1.9 * u)
	_lozenge(c + Vector2(0, 1.5) * u, Vector2(5.0, 7.0) * u, u)


## A clamp on a side rail: a small upright iron plate in brass, pointed top
## and bottom, a lozenge in it and a rivet over and under.
func _strap(c: Vector2, u: float) -> void:
	_plate(c, u, [Vector2(0, -17), Vector2(7.5, -10), Vector2(7.5, 10), Vector2(0, 17), Vector2(-7.5, 10), Vector2(-7.5, -10)])
	_lozenge(c, Vector2(3.4, 5.4) * u, u)
	for y in [-11.5, 11.5]:
		_rivet(c + Vector2(0, y) * u, 1.5 * u)


## An iron plate rimmed in brass: ink, the brass rim in three tones (dark
## under, mid, a light line on its upper edge), the iron lit from above, and an
## engraved line inside.
func _plate(c: Vector2, u: float, shape: Array) -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var top := 1e9
	var bottom := -1e9
	for p in shape:
		top = minf(top, p.y)
		bottom = maxf(bottom, p.y)
	for p in shape:
		pts.append(c + p * u)
		cols.append(IRON_LIGHT.lerp(IRON_DARK, inverse_lerp(top, bottom, p.y)))
	var loop := pts.duplicate()
	loop.append(pts[0])
	_over.draw_polyline(loop, Style.INK, 5.2 * u, true)
	_over.draw_polygon(pts, cols)
	_over.draw_polyline(loop, BRASS_DARK, 3.4 * u, true)
	_over.draw_polyline(loop, BRASS_MID, 2.0 * u, true)
	# The rim's light: its upper half, nudged up and left.
	var upper := PackedVector2Array()
	for i in pts.size():
		if shape[i].y <= 0.0:
			upper.append(pts[i] + Vector2(-0.4, -0.5) * u)
	if upper.size() > 1:
		_over.draw_polyline(upper, BRASS_SHINE, 0.9 * u, true)
	var inner := PackedVector2Array()
	for p in loop:
		inner.append(c + (p - c) * 0.74 + Vector2(0, 1.2) * u)
	_over.draw_polyline(inner, Color(0, 0, 0, 0.45), 1.0 * u, true)
	_over.draw_polyline(inner, Color(IRON_LIGHT, 0.35), 0.6 * u, true)


## A brass scroll: a spiral curling outward from the lozenge, and a leaf trailing to the plate's end.
func _scroll(at: Vector2, side: float, u: float) -> void:
	var curl := PackedVector2Array()
	var n := 22
	for i in n + 1:
		var t := float(i) / n
		var a := PI * 0.85 - t * TAU * 1.05
		var rad := 7.0 * (1.0 - 0.7 * t)
		curl.append(at + Vector2(cos(a) * side, sin(a)) * rad * u)
	var leaf := PackedVector2Array()
	for i in 9:
		var t := float(i) / 8.0
		leaf.append(at + Vector2(side * (2.0 + 13.0 * t), 5.5 - 3.5 * sin(t * PI) + 1.5 * t) * u)
	for line in [curl, leaf]:
		_over.draw_polyline(line, Style.INK, 4.2 * u, true)
		_over.draw_polyline(line, BRASS_DARK, 2.8 * u, true)
		_over.draw_polyline(line, BRASS_LIGHT, 1.3 * u, true)
	_over.draw_circle(curl[curl.size() - 1], 1.4 * u, BRASS_SHINE)


## A lozenge gem in a brass bezel: four facets lit from the top left, a table,
## a highlight.
func _lozenge(c: Vector2, half: Vector2, u: float) -> void:
	var t := c + Vector2(0, -half.y)
	var r := c + Vector2(half.x, 0)
	var b := c + Vector2(0, half.y)
	var l := c + Vector2(-half.x, 0)
	var g := 2.6 * u
	var bezel := PackedVector2Array([t + Vector2(0, -g * 1.4), r + Vector2(g, 0), b + Vector2(0, g * 1.4), l + Vector2(-g, 0)])
	_over.draw_colored_polygon(_grown(bezel, c, 1.3 * u), Style.INK)
	_over.draw_polygon(bezel, PackedColorArray([BRASS_LIGHT, BRASS_MID, BRASS_DEEP, BRASS_MID]))
	_over.draw_colored_polygon(_grown(PackedVector2Array([t, r, b, l]), c, 0.9 * u), Style.INK)
	_over.draw_colored_polygon(PackedVector2Array([t, r, c]), LAPIS)
	_over.draw_colored_polygon(PackedVector2Array([r, b, c]), LAPIS_DEEP)
	_over.draw_colored_polygon(PackedVector2Array([b, l, c]), LAPIS.darkened(0.3))
	_over.draw_colored_polygon(PackedVector2Array([l, t, c]), LAPIS_LIGHT)
	var k := 0.36
	_over.draw_colored_polygon(PackedVector2Array([c + (t - c) * k, c + (r - c) * k, c + (b - c) * k, c + (l - c) * k]), LAPIS.lerp(LAPIS_LIGHT, 0.45))
	_over.draw_line(l.lerp(t, 0.25) + Vector2(1.2, 0.6) * u, l.lerp(t, 0.7) + Vector2(1.2, 0.6) * u, LAPIS_SHINE, 1.2 * u, true)


## A polygon pushed out from `c` by `by` pixels.
static func _grown(pts: PackedVector2Array, c: Vector2, by: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + (p - c).normalized() * by)
	return out


## A domed brass rivet.
func _rivet(c: Vector2, rad: float) -> void:
	_over.draw_circle(c, rad + 1.0 * unit, Style.INK)
	_over.draw_circle(c, rad, BRASS_DARK)
	_over.draw_circle(c - Vector2(0.3, 0.3) * rad, rad * 0.7, BRASS_MID)
	_over.draw_circle(c - Vector2(0.4, 0.45) * rad, rad * 0.32, BRASS_SHINE)


## The gem's sparkle: a four-pointed star that flares and fades.
func _sparkle(c: Vector2, u: float) -> void:
	var a := sin(_spark * PI)
	var arm := (3.0 + 6.0 * a) * u
	var col := Color(1, 1, 1, a)
	_over.draw_line(c - Vector2(arm, 0), c + Vector2(arm, 0), col, 1.2 * u, true)
	_over.draw_line(c - Vector2(0, arm), c + Vector2(0, arm), col, 1.2 * u, true)
	_over.draw_circle(c, 1.6 * u * a, col)
