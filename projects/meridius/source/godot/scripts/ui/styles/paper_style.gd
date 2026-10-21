@tool
## A StyleBox that paints the original stylesheet's layered CSS backgrounds
## (src/ui/styles.css): a linear-gradient fill, tiled texture layers (the paper
## grain and blotches), a border with rounded corners, inset rings
## (`box-shadow: inset 0 0 0 Npx`), an inset glow (`inset 0 0 Npx`), 1 px inset
## highlight lines and an outer drop shadow / ring / glow. Godot's StyleBoxFlat
## has no gradients, textures or inset shadows, so the parchment and leather
## panels, buttons, cards and bars of the original are drawn with this.
##
## Used by scripts/ui/theme_builder.gd; every property is exported so the theme
## can be saved to assets/ui/theme.tres.
extends StyleBox

## Fill under everything (CSS background-color).
@export var bg_color := Color(0, 0, 0, 0)
## CSS linear-gradient over the fill; null for none.
@export var gradient: Gradient
## CSS gradient angle in degrees (180 = top to bottom, 170 = the panels' slant).
@export var gradient_angle := 180.0
## Textures tiled over the gradient, bottom to top (CSS lists them top first).
@export var layers: Array[Texture2D] = []
@export var corner_radius := 0.0
@export var border_color := Color(0, 0, 0, 0)
@export var border_left := 0.0
@export var border_top := 0.0
@export var border_right := 0.0
@export var border_bottom := 0.0
## Inset rings, innermost drawing last: [[width, Color], …] in CSS order (first is on top).
@export var rings: Array = []
## CSS `inset 0 0 <glow_size>px <glow_color>`.
@export var glow_size := 0.0
@export var glow_color := Color(0, 0, 0, 0)
## CSS `inset 0 1px 0 <top_line>` and `inset 0 -1px 0 <bottom_line>`.
@export var top_line := Color(0, 0, 0, 0)
@export var bottom_line := Color(0, 0, 0, 0)
## CSS outer `box-shadow: <shadow_offset> <shadow_blur>px <shadow_color>`.
@export var shadow_color := Color(0, 0, 0, 0)
@export var shadow_offset := Vector2.ZERO
@export var shadow_blur := 0.0
## CSS `box-shadow: 0 0 0 <outer_ring_width>px <outer_ring_color>`.
@export var outer_ring_width := 0.0
@export var outer_ring_color := Color(0, 0, 0, 0)
## CSS `box-shadow: 0 0 <outer_glow_size>px <outer_glow_color>`.
@export var outer_glow_size := 0.0
@export var outer_glow_color := Color(0, 0, 0, 0)
## A dashed 1 px bottom border (the soldier name field; dotted with dash 1 / gap 1).
@export var dash_bottom := Color(0, 0, 0, 0)
@export var dash_len := 3.0
@export var dash_gap := 3.0
## Draw offset (a pressed button sits 1 px lower).
@export var offset := Vector2.ZERO

const SEGS := 6

static var _grad_cache: Dictionary = {}


func _get_draw_rect(rect: Rect2) -> Rect2:
	var grow := maxf(maxf(shadow_blur + absf(shadow_offset.x), shadow_blur + absf(shadow_offset.y)), maxf(outer_ring_width, outer_glow_size))
	return rect.grow(grow)


func _draw(ci: RID, rect: Rect2) -> void:
	rect.position += offset
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var rs := RenderingServer
	var r := minf(corner_radius, minf(rect.size.x, rect.size.y) * 0.5)
	# Outer effects (behind the box).
	if shadow_color.a > 0.0:
		_blur_box(ci, Rect2(rect.position + shadow_offset, rect.size), r, shadow_blur, shadow_color, true)
	if outer_glow_color.a > 0.0 and outer_glow_size > 0.0:
		_blur_box(ci, rect, r, outer_glow_size, outer_glow_color, false)
	if outer_ring_color.a > 0.0 and outer_ring_width > 0.0:
		_strip(ci, rect, r, -outer_ring_width, 0.0, outer_ring_color, outer_ring_color)
	# Fill: background colour, gradient, texture layers.
	var bw := Vector4(border_left, border_top, border_right, border_bottom)
	var fill_rect := Rect2(rect.position + Vector2(bw.x, bw.y) * 0.5, rect.size - Vector2(bw.x + bw.z, bw.y + bw.w) * 0.5)
	var pts := contour(fill_rect, maxf(r - maxf(bw.x, bw.y) * 0.5, 0.0))
	if bg_color.a > 0.0:
		rs.canvas_item_add_polygon(ci, pts, PackedColorArray([bg_color]))
	if gradient != null:
		var tex := _gradient_texture(gradient)
		var uvs := PackedVector2Array()
		uvs.resize(pts.size())
		var ang := deg_to_rad(gradient_angle)
		var dir := Vector2(sin(ang), -cos(ang))
		var length := absf(rect.size.x * dir.x) + absf(rect.size.y * dir.y)
		var c := rect.get_center()
		for i in pts.size():
			var t := clampf((pts[i] - c).dot(dir) / maxf(length, 0.001) + 0.5, 0.0, 1.0)
			uvs[i] = Vector2((0.5 + t * 254.0) / 256.0, 0.5)
		rs.canvas_item_add_polygon(ci, pts, PackedColorArray([Color.WHITE]), uvs, tex.get_rid())
	for layer in layers:
		if layer != null:
			_tile(ci, rect, r, layer)
	# Inset shadows, inside the border.
	var inner := Rect2(rect.position + Vector2(bw.x, bw.y), rect.size - Vector2(bw.x + bw.z, bw.y + bw.w))
	var ri := maxf(r - maxf(bw.x, bw.y), 0.0)
	if glow_color.a > 0.0 and glow_size > 0.0:
		_inset_glow(ci, inner, ri, glow_size, glow_color)
	for i in range(rings.size() - 1, -1, -1):
		var ring: Array = rings[i]
		_strip(ci, inner, ri, 0.0, float(ring[0]), ring[1], ring[1])
	if top_line.a > 0.0:
		rs.canvas_item_add_rect(ci, Rect2(inner.position.x + ri * 0.5, inner.position.y, inner.size.x - ri, 1.0), top_line)
	if bottom_line.a > 0.0:
		rs.canvas_item_add_rect(ci, Rect2(inner.position.x + ri * 0.5, inner.end.y - 1.0, inner.size.x - ri, 1.0), bottom_line)
	# Border.
	if border_color.a > 0.0 and (bw.x > 0 or bw.y > 0 or bw.z > 0 or bw.w > 0):
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.border_color = border_color
		sb.border_width_left = int(bw.x)
		sb.border_width_top = int(bw.y)
		sb.border_width_right = int(bw.z)
		sb.border_width_bottom = int(bw.w)
		sb.set_corner_radius_all(int(r))
		sb.corner_detail = 6
		sb.anti_aliasing = true
		sb.draw(ci, rect)
	if dash_bottom.a > 0.0:
		var x := rect.position.x
		while x < rect.end.x:
			rs.canvas_item_add_rect(ci, Rect2(x, rect.end.y - 1.0, minf(dash_len, rect.end.x - x), 1.0), dash_bottom)
			x += dash_len + dash_gap


## Points of a rounded rectangle, clockwise from the top-left corner, with a
## fixed number of points per corner (so contours of one box can be stitched).
static func contour(rect: Rect2, radius: float, segs := SEGS) -> PackedVector2Array:
	var out := PackedVector2Array()
	var rr := maxf(minf(radius, minf(rect.size.x, rect.size.y) * 0.5), 0.0)
	var centers := [
		Vector2(rect.position.x + rr, rect.position.y + rr),
		Vector2(rect.end.x - rr, rect.position.y + rr),
		Vector2(rect.end.x - rr, rect.end.y - rr),
		Vector2(rect.position.x + rr, rect.end.y - rr),
	]
	var start := [PI, PI * 1.5, 0.0, PI * 0.5]
	for k in 4:
		for i in segs + 1:
			var a: float = start[k] + (PI * 0.5) * float(i) / segs
			out.append(centers[k] + Vector2(cos(a), sin(a)) * rr)
	return out


## The contour inset by d (negative: grown outward).
static func _inset_contour(rect: Rect2, radius: float, d: float) -> PackedVector2Array:
	var rr := Rect2(rect.position + Vector2(d, d), rect.size - Vector2(d, d) * 2.0)
	if rr.size.x < 0.0:
		rr.position.x = rect.get_center().x
		rr.size.x = 0.0
	if rr.size.y < 0.0:
		rr.position.y = rect.get_center().y
		rr.size.y = 0.0
	return contour(rr, maxf(radius - d, 0.0))


## A band between the contour inset by d0 and by d1, coloured c0 → c1.
func _strip(ci: RID, rect: Rect2, radius: float, d0: float, d1: float, c0: Color, c1: Color) -> void:
	var a := _inset_contour(rect, radius, d0)
	var b := _inset_contour(rect, radius, d1)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var n := a.size()
	pts.append_array(a)
	pts.append_array(b)
	for i in n:
		cols.append(c0)
	for i in n:
		cols.append(c1)
	for i in n:
		var j := (i + 1) % n
		idx.append_array([i, j, n + j, i, n + j, n + i])
	RenderingServer.canvas_item_add_triangle_array(ci, idx, pts, cols)


static func _phi(x: float) -> float:
	# Standard normal CDF (Abramowitz–Stegun erf approximation).
	var z := absf(x) / sqrt(2.0)
	var t := 1.0 / (1.0 + 0.3275911 * z)
	var y := 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-z * z)
	return 0.5 * (1.0 + (y if x >= 0.0 else -y))


## CSS inset blur: the shadow of the outside, blurred (sigma = blur / 2), seen inside.
func _inset_glow(ci: RID, rect: Rect2, radius: float, blur: float, color: Color) -> void:
	var steps := 8
	var sigma := blur * 0.5
	var prev_d := 0.0
	var prev_a := color.a * (1.0 - _phi(0.0))
	for k in range(1, steps + 1):
		var d := blur * float(k) / steps
		var a := color.a * (1.0 - _phi(d / maxf(sigma, 0.001)))
		if k == steps:
			a = 0.0
		_strip(ci, rect, radius, prev_d, d, Color(color, prev_a), Color(color, a))
		prev_d = d
		prev_a = a


## CSS outer blur shadow (or glow) around a box: solid inside (when `fill`),
## fading over ±blur at the edge.
func _blur_box(ci: RID, rect: Rect2, radius: float, blur: float, color: Color, fill: bool) -> void:
	if blur <= 0.0:
		RenderingServer.canvas_item_add_polygon(ci, contour(rect, radius), PackedColorArray([color]))
		return
	var sigma := blur * 0.5
	var steps := 8
	# Signed distance s from the box edge: negative inside, positive outside.
	var prev_s := -blur
	var prev_a := color.a * (1.0 - _phi(prev_s / sigma))
	if fill:
		RenderingServer.canvas_item_add_polygon(ci, _inset_contour(rect, radius, blur), PackedColorArray([Color(color, prev_a)]))
	for k in range(1, steps * 2 + 1):
		var s := -blur + blur * float(k) / steps
		var a := color.a * (1.0 - _phi(s / sigma))
		if k == steps * 2:
			a = 0.0
		_strip(ci, rect, radius, -prev_s, -s, Color(color, prev_a), Color(color, a))
		prev_s = s
		prev_a = a


## Tiles a texture over the box, clipping the tiles at the rounded corners.
func _tile(ci: RID, rect: Rect2, radius: float, tex: Texture2D) -> void:
	var ts := Vector2(tex.get_width(), tex.get_height())
	if ts.x < 1.0 or ts.y < 1.0:
		return
	var rid := tex.get_rid()
	var origin := rect.position + Vector2(border_left, border_top)
	var shape := contour(rect, radius)
	# Tiles start at the padding box like a CSS background; step back to cover the border.
	var x0 := origin.x - ceilf((origin.x - rect.position.x) / ts.x) * ts.x
	var y0 := origin.y - ceilf((origin.y - rect.position.y) / ts.y) * ts.y
	var y := y0
	while y < rect.end.y:
		var x := x0
		while x < rect.end.x:
			var tile := Rect2(Vector2(x, y), ts)
			var vis := tile.intersection(rect)
			if vis.has_area():
				var near_corner := radius > 0.0 and (
					(vis.position.x < rect.position.x + radius or vis.end.x > rect.end.x - radius)
					and (vis.position.y < rect.position.y + radius or vis.end.y > rect.end.y - radius))
				if near_corner:
					var poly := PackedVector2Array([vis.position, Vector2(vis.end.x, vis.position.y), vis.end, Vector2(vis.position.x, vis.end.y)])
					for clipped in Geometry2D.intersect_polygons(poly, shape):
						var uvs := PackedVector2Array()
						for p in clipped:
							uvs.append((p - tile.position) / ts)
						RenderingServer.canvas_item_add_polygon(ci, clipped, PackedColorArray([Color.WHITE]), uvs, rid)
				else:
					RenderingServer.canvas_item_add_texture_rect_region(ci, vis, rid, Rect2(vis.position - tile.position, vis.size))
			x += ts.x
		y += ts.y


static func _gradient_texture(g: Gradient) -> ImageTexture:
	var key := g.get_instance_id()
	var cached: Array = _grad_cache.get(key, [])
	# Rebuild when the gradient changed (compared by its colours and offsets).
	var sig := str(g.colors) + str(g.offsets)
	if cached.size() == 2 and cached[0] == sig:
		return cached[1]
	var img := Image.create(256, 1, false, Image.FORMAT_RGBA8)
	for i in 256:
		img.set_pixel(i, 0, g.sample(clampf(float(i) / 254.0, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_grad_cache[key] = [sig, tex]
	return tex
