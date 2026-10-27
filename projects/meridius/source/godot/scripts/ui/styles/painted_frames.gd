@tool
## Original painted interface masters, sliced without altering their PNGs.
## Source corners retain their proportions; only straight rail spans stretch.
extends RefCounted

const COUNCIL = preload("res://assets/ui/epic/council-frame.png")
const COMMAND = preload("res://assets/ui/epic/command-panel.png")
const BANNER = preload("res://assets/ui/epic/company-banner.png")


static func draw_frame(ci: RID, rect: Rect2, kind: int, scale: float, tint: Color) -> void:
	match kind:
		1:
			_nine(ci, rect, COUNCIL, Rect2(37, 49, 1462, 916),
				Vector2(275, 238), Vector2(275, 238), Vector2(62, 54) * scale, false, tint)
		2:
			_nine(ci, rect, COMMAND, Rect2(25, 73, 2123, 570),
				Vector2(275, 205), Vector2(275, 205), Vector2(34, 25) * scale, true, tint)
		3:
			# Caps include the folds and clasps; the centre is the quiet woven cloth.
			_nine(ci, rect, BANNER, Rect2(23, 175, 2127, 356),
				Vector2(390, 75), Vector2(390, 90), Vector2(62, 17) * scale, true, tint)
		4:
			_nine(ci, rect, COMMAND, Rect2(25, 73, 2123, 570),
				Vector2(275, 205), Vector2(275, 205), Vector2(15, 11) * scale, false, tint)


static func _nine(ci: RID, rect: Rect2, texture: Texture2D, source: Rect2,
		left_top: Vector2, right_bottom: Vector2, corner: Vector2,
		center: bool, tint: Color) -> void:
	# Tiny controls still have ordered non-negative slices.
	corner.x = minf(corner.x, rect.size.x * 0.5)
	corner.y = minf(corner.y, rect.size.y * 0.5)
	var sx := [source.position.x, source.position.x + left_top.x, source.end.x - right_bottom.x, source.end.x]
	var sy := [source.position.y, source.position.y + left_top.y, source.end.y - right_bottom.y, source.end.y]
	var dx := [rect.position.x, rect.position.x + corner.x, rect.end.x - corner.x, rect.end.x]
	var dy := [rect.position.y, rect.position.y + corner.y, rect.end.y - corner.y, rect.end.y]
	for y in 3:
		for x in 3:
			if x == 1 and y == 1 and not center:
				continue
			var dest := Rect2(dx[x], dy[y], dx[x + 1] - dx[x], dy[y + 1] - dy[y])
			if not dest.has_area():
				continue
			RenderingServer.canvas_item_add_texture_rect_region(ci, dest, texture.get_rid(),
				Rect2(sx[x], sy[y], sx[x + 1] - sx[x], sy[y + 1] - sy[y]), tint)
