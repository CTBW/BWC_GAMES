## Symbol-free edge metalwork for the title screen.
## Decorative only. Does not intercept mouse input or create game state.
extends Control

const Forged = preload("res://scripts/ui/styles/forged_style.gd")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func _draw() -> void:
	var mid := size.x * 0.5
	# Fine outer architectural frame. The centre of each edge stays quiet.
	var rect := Rect2(Vector2(24, 24), size - Vector2(48, 48))
	var frame := Forged.new()
	frame.artwork = 1
	frame.art_scale = 1.35
	frame.metal_width = 5
	frame.ornament = 2
	frame.metal_color = Color("#8b7856")
	frame.draw(get_canvas_item(), rect)
	for side in [-1, 1]:
		var x: float = mid + side * 110
		draw_line(Vector2(x, 45), Vector2(mid + side * 390, 45), Color("#736345"), 1, true)
		for j in 3:
			var p := Vector2(mid + side * (95 + j * 8), 45)
			_diamond(p, Vector2(2, 2), Color("#b39b67"))


func _diamond(p: Vector2, r: Vector2, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r.y), p + Vector2(r.x, 0),
		p + Vector2(0, r.y), p + Vector2(-r.x, 0)]), color)
