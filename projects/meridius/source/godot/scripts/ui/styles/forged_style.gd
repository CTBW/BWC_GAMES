@tool
## Nordmark UI: bevelled iron, brass inlay and engraved corner fittings.
## Geometry stays in screen pixels: corners are never stretched with the panel.
extends "res://scripts/ui/styles/paper_style.gd"

const Painted = preload("res://scripts/ui/styles/painted_frames.gd")

@export var metal_width := 8.0
@export var metal_color := Color("#a79263")
@export_enum("Plain", "Corners", "Regalia") var ornament := 1
@export var accent := Color("#34536a")
@export_enum("Procedural", "Council", "Command", "Banner", "Button") var artwork := 0
@export var art_scale := 1.0
@export var art_tint := Color.WHITE


func _draw(ci: RID, rect: Rect2) -> void:
	var compact := artwork == 2 and minf(get_margin(SIDE_TOP), get_margin(SIDE_LEFT)) < 12
	if artwork > 0 and not compact and (ornament > 0 or artwork >= 3):
		# The opaque backing preserves contrast even at almost-transparent PNG pixels.
		# Cloth already contains its full surface; do not fill behind its ribbon tails.
		if artwork != 3:
			super._draw(ci, rect.grow(-4.0) if artwork == 1 else rect)
		var art_rect := rect
		art_rect.position += offset
		if artwork == 1:
			art_rect = art_rect.grow(6.0)
		var scale := art_scale
		if artwork == 1 and content_margin_top >= 0:
			scale *= minf(1.0, maxf(0.6, content_margin_top / 25.0))
		Painted.draw_frame(ci, art_rect, artwork, scale, art_tint)
		return
	super._draw(ci, rect)
	if rect.size.x < 8 or rect.size.y < 8:
		return
	rect.position += offset
	var w := maxf(4.0, minf(metal_width, minf(rect.size.x, rect.size.y) * 0.2))
	# Black seam, cold steel, warm raised lip, recessed inner edge.
	_strip(ci, rect, 2, 0, 1, Color("#080b0d"), Color("#080b0d"))
	_strip(ci, rect, 2, 1, 2, metal_color.lightened(0.22), metal_color)
	_strip(ci, rect, 2, 2, maxf(2.5, w - 2), Color("#353a39"), Color("#171d21"))
	_strip(ci, rect, 2, maxf(2.5, w - 2), w - 1, metal_color.darkened(0.15), metal_color.darkened(0.4))
	_strip(ci, rect, 2, w - 1, w, Color("#080d11"), Color("#080d11"))
	var left := rect.position.x
	var top := rect.position.y
	var right := rect.end.x
	var bottom := rect.end.y
	_line(ci, Vector2(left + w, top + w), Vector2(right - w, top + w), Color(0, 0, 0, 0.55))
	_line(ci, Vector2(left + w, bottom - w), Vector2(right - w, bottom - w), Color(metal_color, 0.35))
	if ornament == 0 or minf(rect.size.x, rect.size.y) < 28:
		return
	var reach := maxf(w + 7.0, minf(27.0 if ornament == 2 else 15.0, minf(rect.size.x, rect.size.y) * 0.4))
	for c in [[Vector2(left, top), Vector2(1, 1)], [Vector2(right, top), Vector2(-1, 1)],
			[Vector2(right, bottom), Vector2(-1, -1)], [Vector2(left, bottom), Vector2(1, -1)]]:
		_corner(ci, c[0], c[1], reach, w)
	if ornament == 2 and rect.size.x > 240 and rect.size.y > 150:
		for y in [top + w * 0.48, bottom - w * 0.48]:
			var center := Vector2(rect.get_center().x, y)
			_diamond(ci, center, Vector2(19, 4), Color("#0c1218"))
			_diamond(ci, center, Vector2(12, 3), metal_color)
			_diamond(ci, center, Vector2(6, 2), accent)
			for side in [-1, 1]:
				_line(ci, center + Vector2(side * 24, 0), center + Vector2(side * 76, 0), Color(metal_color, 0.65))


func _corner(ci: RID, origin: Vector2, direction: Vector2, reach: float, w: float) -> void:
	var points := PackedVector2Array()
	for p in [Vector2(2, 2), Vector2(reach, 2), Vector2(reach - 5, 5), Vector2(w, w),
			Vector2(5, reach - 5), Vector2(2, reach)]:
		points.append(origin + p * direction)
	RenderingServer.canvas_item_add_polygon(ci, points, PackedColorArray([metal_color.darkened(0.28)]))
	_line(ci, origin + Vector2(3, reach - 2) * direction, origin + Vector2(3, 3) * direction, metal_color.lightened(0.3))
	_line(ci, origin + Vector2(3, 3) * direction, origin + Vector2(reach - 2, 3) * direction, metal_color.lightened(0.3))
	var rivet := origin + Vector2(w * 0.52, w * 0.52) * direction
	RenderingServer.canvas_item_add_circle(ci, rivet + Vector2(0, 1), 2.4, Color("#070c10"))
	RenderingServer.canvas_item_add_circle(ci, rivet, 1.5, metal_color)
	RenderingServer.canvas_item_add_circle(ci, rivet - Vector2(0.4, 0.5), 0.6, Color("#ecddb4"))
	if ornament == 2:
		var inner := origin + Vector2(w + 4, w + 4) * direction
		_line(ci, inner + Vector2(0, 11) * direction, inner, Color(metal_color, 0.7))
		_line(ci, inner, inner + Vector2(11, 0) * direction, Color(metal_color, 0.7))
		_diamond(ci, inner + Vector2(3, 3) * direction, Vector2(2, 2), metal_color)


static func _line(ci: RID, a: Vector2, b: Vector2, c: Color, width := 1.0) -> void:
	RenderingServer.canvas_item_add_line(ci, a, b, c, width, true)


static func _diamond(ci: RID, center: Vector2, radius: Vector2, color: Color) -> void:
	RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([
		center + Vector2(0, -radius.y), center + Vector2(radius.x, 0),
		center + Vector2(0, radius.y), center + Vector2(-radius.x, 0)]), PackedColorArray([color]))
