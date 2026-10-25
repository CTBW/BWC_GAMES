## The battle ground's relief: one continuous surface over the tile heights,
## so raised ground reads as hills with slopes instead of stacked blocks.
## Godot only (the original drew plateaus with vertical cliff faces).
##
## Rules keep integer tile heights. The lab's separate surface_h samples
## describe broad rolling landforms. Catmull-Rom interpolation passes through
## every tile centre and keeps the slope continuous across them, so hills
## round off instead of creasing along the grid (bilinear did), and a
## one-level step between tiles becomes a bank about a tile wide.
##
## The same function runs in two places and must stay identical:
##   surface() here       (feet of soldiers, props, highlights: CPU)
##   surf() in assets/shaders/terrain_relief.gdshader (the ground mesh: GPU)
## Its inputs are the padded height grid and four warp phases from the seed.
##
##   var r := Relief.new(w, h, border, tiles, seed)
##   r.surface(x, y)        height in levels at grid point (x, y)
##   r.height_image()       the padded grid as an RF image (shader input)
##   r.mesh(sub)            the ground mesh, grid UVs, drawn back to front
extends RefCounted

const Iso = preload("res://scripts/render/iso.gd")

## Zero warp keeps visual heights and integer-centre picking aligned.
const WARP := 0.0
## No flat patch: the authored continuous height samples already define hills.
const FLAT := 0.0

var gw := 0
var gh := 0
var b := 0
var heights := PackedFloat32Array()
var phase := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var max_h := 0.0


func _init(w: int, h: int, border: int, tiles: Array, seed: int) -> void:
	b = border
	gw = w + 2 * border
	gh = h + 2 * border
	heights.resize(gw * gh)
	for t in tiles:
		var gx := int(t.x) + b
		var gy := int(t.y) + b
		if gx < 0 or gy < 0 or gx >= gw or gy >= gh:
			continue
		var hh := clampf(float(t.get("surface_h", t.h)), 0.0, 255.0)
		heights[gy * gw + gx] = hh
		max_h = maxf(max_h, hh)
	# Phases from the seed, as floats the shader receives unchanged.
	var s := absi(seed) % 100003
	for i in 4:
		phase[i] = fposmod(float(s) * (0.6180339 + i * 0.2718281), TAU)


## Height of tile (x, y); outside the padded grid the edge tile's.
func tile(x: int, y: int) -> float:
	return heights[clampi(y + b, 0, gh - 1) * gw + clampi(x + b, 0, gw - 1)]


## Catmull-Rom weights of the four samples around fraction t.
static func _cr(t: float) -> Vector4:
	var t2 := t * t
	var t3 := t2 * t
	return Vector4(-0.5 * t3 + t2 - 0.5 * t, 1.5 * t3 - 2.5 * t2 + 1.0, -1.5 * t3 + 2.0 * t2 + 0.5 * t, 0.5 * t3 - 0.5 * t2)


## The ground's height in levels at grid point (x, y) (tile centres are integers).
func surface(x: float, y: float) -> float:
	var wx := x + WARP * (0.6 * sin(x * 0.91 + y * 0.37 + phase[0]) + 0.4 * sin(x * 0.23 - y * 1.31 + phase[1]))
	var wy := y + WARP * (0.6 * sin(y * 0.87 - x * 0.41 + phase[2]) + 0.4 * sin(y * 0.29 + x * 1.17 + phase[3]))
	var ix := floori(wx)
	var iy := floori(wy)
	var wxs := _cr(wx - ix)
	var wys := _cr(wy - iy)
	var first := tile(ix - 1, iy - 1)
	var same := true
	var sum := 0.0
	for j in 4:
		var row := 0.0
		for i in 4:
			var hh := tile(ix - 1 + i, iy - 1 + j)
			same = same and hh == first
			row += wxs[i] * hh
		sum += wys[j] * row
	# Flat ground returns its level exactly (no rounding drift for the feet).
	return first if same else sum


## The padded height grid, one float per tile (the shader's h_tex).
func height_image() -> Image:
	return Image.create_from_data(gw, gh, false, Image.FORMAT_RF, heights.to_byte_array())


## World-to-grid on the test fields' non-overhanging slopes. Ray runs along
## x-y = constant. Bisection is stable where screen-y increases toward camera.
func unproject(world: Vector2) -> Vector2:
	var d := world.x / (Iso.TW / 2.0)
	var lo := -float(b) - 1.0 - maxf(0.0, d)
	var hi := float(gh - b) + maxf(0.0, -d) + 1.0
	for i in 28:
		var y := (lo + hi) * 0.5
		var py := Iso.iso_y(y + d, y, surface(y + d, y))
		if py < world.y:
			lo = y
		else:
			hi = y
	return Vector2((lo + hi) * 0.5 + d, (lo + hi) * 0.5)


## The ground mesh over the padded grid, `sub` cells per tile side. Vertices
## sit on the flat projection (world px relative to `origin`); the shader
## lifts them by the surface. UV is the grid point. Triangles run back to
## front (by x + y), so with no depth buffer a hill hides what is behind it.
func mesh(sub: int, origin: Vector2) -> ArrayMesh:
	var nx := gw * sub + 1
	var ny := gh * sub + 1
	var x0 := -b - 0.5
	var y0 := -b - 0.5
	var step := 1.0 / sub
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	verts.resize(nx * ny)
	uvs.resize(nx * ny)
	var hw := Iso.TW / 2.0
	var hh := Iso.TH / 2.0
	var i := 0
	for j in ny:
		var gy := y0 + j * step
		for k in nx:
			var gx := x0 + k * step
			uvs[i] = Vector2(gx, gy)
			verts[i] = Vector2((gx - gy) * hw - origin.x, (gx + gy) * hh - origin.y)
			i += 1
	var cx := nx - 1
	var cy := ny - 1
	var idx := PackedInt32Array()
	idx.resize(cx * cy * 6)
	var n := 0
	for d in cx + cy - 1:
		for k in range(maxi(0, d - (cy - 1)), mini(cx - 1, d) + 1):
			var j := d - k
			var a := j * nx + k
			# The far triangle (top, right, left corners), then the near one.
			idx[n] = a
			idx[n + 1] = a + 1
			idx[n + 2] = a + nx
			idx[n + 3] = a + 1
			idx[n + 4] = a + nx + 1
			idx[n + 5] = a + nx
			n += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
