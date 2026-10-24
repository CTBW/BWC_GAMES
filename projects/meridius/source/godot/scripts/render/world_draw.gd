## Small drawing utilities shared by the world views, atmosphere and FX:
## CSS colour strings (the original passes colours as CSS), the Cinzel font
## used for world text, ellipses, and canvas-style text with an outline drawn
## at screen resolution under a zoomed world transform.
extends RefCounted

const CINZEL_700 := "res://assets/fonts/cinzel-latin-700-normal.woff2"

static var _font: Font
static var _colors: Dictionary = {}
static var _disc: Texture2D


## The world text font (the original's `Cinzel, Georgia, serif`; weights 600
## and 700 both resolve to the 700 face the game loads).
static func cinzel() -> Font:
	if _font == null:
		if ResourceLoader.exists(CINZEL_700):
			_font = load(CINZEL_700)
		if _font == null:
			_font = ThemeDB.fallback_font
	return _font


## A CSS colour ("#rgb", "#rrggbb", "rgb(...)", "rgba(...)") or a Color.
static func css(v: Variant) -> Color:
	if v is Color:
		return v
	var s := str(v).strip_edges()
	if _colors.has(s):
		return _colors[s]
	var c := Color.WHITE
	if s.begins_with("#"):
		var h := s.substr(1)
		if h.length() == 3:
			h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
		c = Color8(h.substr(0, 2).hex_to_int(), h.substr(2, 2).hex_to_int(), h.substr(4, 2).hex_to_int())
	elif s.begins_with("rgb"):
		var inner := s.substr(s.find("(") + 1, s.rfind(")") - s.find("(") - 1)
		var parts := inner.split(",")
		if parts.size() >= 3:
			c = Color(float(parts[0]) / 255.0, float(parts[1]) / 255.0, float(parts[2]) / 255.0, float(parts[3]) if parts.size() > 3 else 1.0)
	elif Color.html_is_valid(s):
		c = Color.html(s)
	_colors[s] = c
	return c


static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


## Polygon of an ellipse (ctx.ellipse) centred at (cx, cy), rotated by rot.
static func ellipse(cx: float, cy: float, rx: float, ry: float, rot: float = 0.0, n: int = 32) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(n)
	var cr := cos(rot)
	var sr := sin(rot)
	for i in n:
		var a := TAU * i / n
		var ex := cos(a) * rx
		var ey := sin(a) * ry
		pts[i] = Vector2(cx + ex * cr - ey * sr, cy + ex * sr + ey * cr)
	return pts


static func text_width(text: String, size: float) -> float:
	return cinzel().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(1, roundi(size))).x


## Text centred on (x, y) (canvas textAlign center, alphabetic baseline) in a
## CanvasItem whose transform scales world px by `zoom`: `size` is in world
## px (as the original sets ctx.font under the world transform); the glyphs
## are rasterised at the screen size so they stay crisp. `outline` > 0 draws
## a stroke of that width (world px) behind, like strokeText with a round join.
static func draw_text(ci: CanvasItem, x: float, y: float, text: String, size: float, color: Color, zoom: float = 1.0, outline: float = 0.0, outline_color: Color = Color.BLACK) -> void:
	var font := cinzel()
	var px := maxi(1, roundi(size * zoom))
	var k := 1.0 / zoom
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	ci.draw_set_transform(Vector2(x, y), 0.0, Vector2(k, k))
	var pos := Vector2(-w / 2.0, 0.0)
	if outline > 0.0:
		ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(1, roundi(outline * zoom)), outline_color)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## A white anti-aliased disc (128 px, with mipmaps) for filled circles drawn
## in quantity: `fill_circle` is one textured quad instead of a polygon.
static func disc() -> Texture2D:
	if _disc == null:
		var n := 128
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var d := Vector2(x + 0.5 - n / 2.0, y + 0.5 - n / 2.0).length()
				img.set_pixel(x, y, Color(1, 1, 1, clampf(n / 2.0 - d + 0.5, 0.0, 1.0)))
		img.generate_mipmaps()
		_disc = ImageTexture.create_from_image(img)
	return _disc


## ctx.arc + fill: a filled, anti-aliased circle.
static func fill_circle(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	if r <= 0.0:
		return
	ci.draw_texture_rect(disc(), Rect2(c.x - r, c.y - r, r * 2.0, r * 2.0), false, color)


## A stroked polyline with round caps (lineCap 'round'): the caps are filled
## discs, so the ends match canvas strokes.
static func stroke_round(ci: CanvasItem, pts: PackedVector2Array, color: Color, width: float) -> void:
	if pts.size() < 2:
		return
	ci.draw_polyline(pts, color, width, true)
	fill_circle(ci, pts[0], width / 2.0, color)
	fill_circle(ci, pts[pts.size() - 1], width / 2.0, color)
