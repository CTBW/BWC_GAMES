## Animated water shimmer over a terrain layer, clipped to its water tiles.
## Ports battleScene.drawWater ("battle") and the shimmer block of
## campaignScene.render ("campaign"). Created by TerrainLayer.make_water_node();
## the view adds it to its world node (world pixels) after the ground and sets
## `time` (and for "battle" `cam` + `view_size`, used to skip tiles off screen)
## every frame before queue_redraw().
extends Node2D

const Iso = preload("res://scripts/render/iso.gd")
const Rng = preload("res://scripts/core/rng.gd")
const WaterShader = preload("res://assets/shaders/terrain_water.gdshader")

var style := "battle"
var time := 0.0
var cam: RefCounted = null
var view_size := Vector2(1920, 1080)
var _tiles: Array = [] # {x, y, cx, cy, h: [hash values]}


func setup(layer: Node2D, s: String) -> void:
	style = s
	name = "Water"
	var tiles: Array = layer.water_tiles
	if tiles.is_empty():
		visible = false
		return
	var x0 := 1 << 30
	var y0 := 1 << 30
	var x1 := -(1 << 30)
	var y1 := -(1 << 30)
	var max_h := 0
	for t in tiles:
		x0 = mini(x0, t.x)
		y0 = mini(y0, t.y)
		x1 = maxi(x1, t.x)
		y1 = maxi(y1, t.y)
		max_h = maxi(max_h, layer.h_at(t.x, t.y))
	var gw := x1 - x0 + 1
	var gh := y1 - y0 + 1
	var bytes := PackedByteArray()
	bytes.resize(gw * gh)
	for t in tiles:
		bytes[(t.y - y0) * gw + (t.x - x0)] = layer.h_at(t.x, t.y) + 1
		var hs := []
		for i in 11:
			hs.append(Rng.hash2(t.x, t.y, i))
		_tiles.append({"x": t.x, "y": t.y, "cx": Iso.iso_x(t.x, t.y), "cy": Iso.iso_y(t.x, t.y), "hs": hs, "h0": Rng.hash2(t.x, t.y)})
	var mat := ShaderMaterial.new()
	mat.shader = WaterShader
	mat.set_shader_parameter("water_tex", ImageTexture.create_from_image(Image.create_from_data(gw, gh, false, Image.FORMAT_R8, bytes)))
	mat.set_shader_parameter("gx0", x0)
	mat.set_shader_parameter("gy0", y0)
	mat.set_shader_parameter("gw", gw)
	mat.set_shader_parameter("gh", gh)
	mat.set_shader_parameter("max_h", max_h)
	material = mat


func _process(_dt: float) -> void:
	queue_redraw()


## quadraticCurveTo(cx, cy - 3, cx + half, cy) from (cx - half, cy), as
## eight segments appended to one batched multiline.
func _arc(pts: PackedVector2Array, cols: PackedColorArray, cx: float, cy: float, half: float, col: Color) -> void:
	var prev := Vector2(cx - half, cy)
	for i in range(1, 9):
		var t := i / 8.0
		var x := (1 - t) * (1 - t) * (cx - half) + 2 * (1 - t) * t * cx + t * t * (cx + half)
		var y := (1 - t) * (1 - t) * cy + 2 * (1 - t) * t * (cy - 3) + t * t * cy
		var p := Vector2(x, y)
		pts.append(prev)
		pts.append(p)
		cols.append(col)
		prev = p


func _draw() -> void:
	if _tiles.is_empty():
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	if style == "campaign":
		for t in _tiles:
			var ph: float = time * 0.7 + t.h0 * 6.0
			var a := 0.5 + 0.5 * sin(ph)
			_arc(pts, cols, t.cx + sin(ph) * 16.0, t.cy, 12.0, Color(220 / 255.0, 245 / 255.0, 1.0, 0.3 * a))
		if pts.size() > 0:
			draw_multiline_colors(pts, cols, 2.0, true)
		return
	var hw := 1e9
	var hh := 1e9
	var camx := 0.0
	var camy := 0.0
	if cam != null:
		hw = view_size.x / cam.zoom / 2.0 + 80.0
		hh = view_size.y / cam.zoom / 2.0 + 80.0
		camx = cam.x
		camy = cam.y
	for t in _tiles:
		if absf(t.cx - camx) > hw or absf(t.cy - camy) > hh:
			continue
		for i in 2:
			var ph: float = time * 0.8 + t.hs[i] * 6.0
			var cx: float = t.cx + sin(ph) * 20.0 + (t.hs[i + 7] - 0.5) * 60.0
			var cy: float = t.cy + (t.hs[i + 3] - 0.5) * 30.0
			var a := 0.5 + 0.5 * sin(ph * 1.3)
			_arc(pts, cols, cx, cy, 10.0, Color(220 / 255.0, 245 / 255.0, 1.0, 0.35 * a))
	if pts.size() > 0:
		draw_multiline_colors(pts, cols, 1.6, true)
