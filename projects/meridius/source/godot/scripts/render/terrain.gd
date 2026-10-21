## Static terrain layer: a painted top-down colour field projected onto the
## isometric plane, raised plateaus with lit cliff faces, and ground decals.
## Port of src/render/terrain.ts (buildTerrain, fbm).
##
## The original paints the colour field per pixel on the CPU. Here the same
## algorithm runs on the GPU, once: the field is a fragment shader
## (assets/shaders/terrain_field.gdshader, bit-exact hash2/fbm) rendered into a
## SubViewport together with the painterly dabs; a second SubViewport projects
## it onto the iso plane with the plateaus, cliff faces, rims, bridges, the
## forest-edge shading and the decals. The result stays on the GPU as a
## ViewportTexture. Both viewports render in the first frame after the layer
## enters the tree (before the main viewport), so the ground is there in the
## first frame the view draws.
##
## ---------------------------------------------------------------- API
##   const Terrain = preload("res://scripts/render/terrain.gd")
##   var layer = Terrain.build_terrain({w, h, border, tiles: [{x, y, h, terrain}],
##       seed, palette: "summer"|"camp"|"base"|"map", roads?: [[{x, y}]],
##       decals?: bool, res?: int, scale?: float})
##   world.add_child(layer)          # REQUIRED: it renders once in the tree
##
## TerrainLayer (this node, a Node2D in world pixels):
##   layer.texture       Texture2D of the layer (TerrainLayer.canvas)
##   layer.layer_scale   texture px per world px (TerrainLayer.scale)
##   layer.ox, layer.oy  world coordinates of the texture origin
##   layer.width, layer.height   texture size in px
##   layer.water_tiles   [{x, y}] water, shallows and bridge tiles
##   layer.water         [PackedVector2Array] their diamonds in world px (the Path2D)
##   layer.is_built, signal built   the GPU pass has rendered
##   It draws itself at (ox, oy) with size (width, height) / layer_scale
##   (`ctx.drawImage(tl.canvas, tl.ox, tl.oy, w / scale, h / scale)`), with
##   bilinear filtering. Set `self_draw = false` and call `draw_ground(ci)`
##   from your own _draw to draw it elsewhere in your order.
##
##   layer.bake(func(ci: CanvasItem): ...)
##       Paints into the layer once, in world pixels (battleScene.bakeOuter:
##       `x.setTransform(scale, 0, 0, scale, -ox*scale, -oy*scale)`). Call any
##       time after build_terrain; it is drawn over the ground in call order.
##
##   layer.make_water_node(style)   -> Node2D for battleScene/campaignScene
##       drawWater: animated shimmer strokes clipped to the water.
##       style "battle": two arcs per tile, culled to the view (set
##       node.cam and node.view_size each frame); "campaign": one arc per tile.
##       Add it to the world node right after the ground; set node.time.
##
##   Terrain.fbm(x, y, seed, oct = 4)   the original's CPU fbm (campaign map).
extends Node2D

const Iso = preload("res://scripts/render/iso.gd")
const Rng = preload("res://scripts/core/rng.gd")
const JS = preload("res://scripts/core/js.gd")
const WD = preload("res://scripts/render/world_draw.gd")
const FieldShader = preload("res://assets/shaders/terrain_field.gdshader")
const DabShader = preload("res://assets/shaders/terrain_dab.gdshader")
const WaterNode = preload("res://scripts/render/world_water.gd")
const ASSETS_PATH := "res://scripts/render/assets.gd"

const TW := Iso.TW
const TH := Iso.TH
const LH := Iso.LH
const U32 := 0xFFFFFFFF

const CAT := ["grass", "dirt", "brush", "forest", "stone", "water", "shallows", "floor", "mud"]
const C_GRASS := 0
const C_DIRT := 1
const C_BRUSH := 2
const C_STONE := 4
const C_WATER := 5
const C_FLOOR := 7

signal built

## TerrainLayer.canvas
var texture: Texture2D
## TerrainLayer.scale
var layer_scale := 1.0
var ox := 0
var oy := 0
var width := 0
var height := 0
var water: Array = []
var water_tiles: Array = []
var is_built := false
## Draw the layer from this node's _draw (otherwise call draw_ground()).
var self_draw := true
## Seconds the CPU part of the last build took (profiling).
var build_ms := 0.0

var input: Dictionary
var max_h := 0
var _w := 0
var _h := 0
var _b := 0
var _r := 24
var _gw := 0
var _gh := 0
var _seed := 0
var _palette := "summer"
var _cats := PackedByteArray()
var _heights := {}
var _tiles: Array = []
var _field_vp: SubViewport
var _iso_vp: SubViewport
var _paint: Node2D
var _field_tex: Texture2D
var _decals: Array = []
var _decal_node: Node2D
var _rendered_once := false


static func _assets() -> Variant:
	if ResourceLoader.exists(ASSETS_PATH):
		return load(ASSETS_PATH)
	return null


# ---------------------------------------------------------------- noise


## Rng.hash2 for integer x, y and seed term sd = seed * 2147483647 (a double,
## as JS computes it). The sum is the same double JS sums; for an integral
## double below 2^63, ToUint32 is its low 32 bits. Falls back to Rng.hash2
## outside that range.
static func _hash_lattice(x: float, y: float, sd: float, seed: float) -> float:
	var v: float = x * 374761393.0 + y * 668265263.0 + sd
	if absf(v) >= 9.0e18:
		return Rng.hash2(x, y, seed)
	var h: int = int(v) & U32
	h = ((h ^ (h >> 13)) * 1274126177) & U32
	return float(h ^ (h >> 16)) / 4294967296.0


static func vnoise(x: float, y: float, seed: float) -> float:
	var xi := floorf(x)
	var yi := floorf(y)
	var xf := x - xi
	var yf := y - yi
	var sd := seed * 2147483647.0
	var a := _hash_lattice(xi, yi, sd, seed)
	var b := _hash_lattice(xi + 1.0, yi, sd, seed)
	var c := _hash_lattice(xi, yi + 1.0, sd, seed)
	var d := _hash_lattice(xi + 1.0, yi + 1.0, sd, seed)
	var u := xf * xf * (3.0 - 2.0 * xf)
	var v := yf * yf * (3.0 - 2.0 * yf)
	return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v


static func fbm(x: float, y: float, seed: float, oct: int = 4) -> float:
	var sum := 0.0
	var amp := 0.5
	var f := 1.0
	for i in oct:
		sum += amp * vnoise(x * f, y * f, seed + i * 17)
		f *= 2.03
		amp *= 0.5
	return sum / 0.9375


static func cat_of(t: String) -> int:
	if t == "road":
		return C_DIRT
	if t == "bridge":
		return C_WATER
	var i := CAT.find(t)
	return i if i >= 0 else C_GRASS


# ---------------------------------------------------------------- build


static func build_terrain(inp: Dictionary) -> Node2D:
	var layer: Node2D = load("res://scripts/render/terrain.gd").new()
	layer._build(inp)
	return layer


func _key(x: int, y: int) -> int:
	return y * 4096 + x


func h_at(x: int, y: int) -> int:
	return _heights.get(_key(x, y), 0)


## Category of a tile (padded area outside the tiles: 'grass' on the map, else 'floor').
func terr_at(x: int, y: int) -> int:
	var gx := x + _b
	var gy := y + _b
	if gx >= 0 and gy >= 0 and gx < _gw and gy < _gh:
		return _cats[gy * _gw + gx]
	return C_GRASS if _palette == "map" else C_FLOOR


func _build(inp: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	input = inp
	_w = int(inp.w)
	_h = int(inp.h)
	_b = int(inp.border)
	_seed = int(inp.seed)
	_palette = str(inp.get("palette", "summer"))
	_r = int(inp.get("res", 24))
	layer_scale = float(inp.get("scale", 1.0))
	_gw = _w + 2 * _b
	_gh = _h + 2 * _b
	_tiles = inp.tiles
	var tile_cat := {}
	for t in _tiles:
		var k := _key(int(t.x), int(t.y))
		_heights[k] = int(t.h)
		tile_cat[k] = cat_of(str(t.terrain))
		max_h = maxi(max_h, int(t.h))
	var outside := C_GRASS if _palette == "map" else C_FLOOR
	# 1. Category per tile of the padded grid (one-hot weights, sampled on the GPU).
	_cats.resize(_gw * _gh)
	for gy in _gh:
		for gx in _gw:
			_cats[gy * _gw + gx] = tile_cat.get(_key(gx - _b, gy - _b), outside)

	# 2. Projection box (same as the original).
	var corners := [[-_b - 0.5, -_b - 0.5], [_w + _b - 0.5, -_b - 0.5], [-_b - 0.5, _h + _b - 0.5], [_w + _b - 0.5, _h + _b - 0.5]]
	var xs: Array = []
	var ys: Array = []
	for c in corners:
		xs.append(Iso.iso_x(c[0], c[1]))
		ys.append(Iso.iso_y(c[0], c[1]))
	ox = floori(JS.min_of(xs)) - 4
	oy = floori(JS.min_of(ys)) - max_h * LH - 8
	width = ceili((JS.max_of(xs) - ox + 8) * layer_scale)
	height = ceili((JS.max_of(ys) - oy + 8) * layer_scale)

	# Water path for animation.
	for t in _tiles:
		if t.terrain == "water" or t.terrain == "shallows" or t.terrain == "bridge":
			water_tiles.append({"x": int(t.x), "y": int(t.y)})
			water.append(_diamond(int(t.x), int(t.y), int(t.h), Vector2.ZERO))

	_make_field()
	_make_iso()
	if inp.get("decals", true) != false:
		_make_decals()
		var A = _assets()
		if A != null:
			A.warm_async(["tuft", "flower", "pebble"])
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _make_field() -> void:
	var fw := _gw * _r
	var fh := _gh * _r
	_field_vp = SubViewport.new()
	_field_vp.name = "Field"
	_field_vp.size = Vector2i(fw, fh)
	_field_vp.transparent_bg = false
	_field_vp.disable_3d = true
	_field_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_field_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_field_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	var cat_img := Image.create_from_data(_gw, _gh, false, Image.FORMAT_R8, _cats)
	var mat := ShaderMaterial.new()
	mat.shader = FieldShader
	mat.set_shader_parameter("cat_tex", ImageTexture.create_from_image(cat_img))
	mat.set_shader_parameter("gw", _gw)
	mat.set_shader_parameter("gh", _gh)
	mat.set_shader_parameter("res", _r)
	mat.set_shader_parameter("field_w", fw)
	mat.set_shader_parameter("field_h", fh)
	mat.set_shader_parameter("seed", _seed)
	mat.set_shader_parameter("camp", _palette == "camp")
	var roads: Array = input.get("roads", [])
	var npts := 0
	for road in roads:
		npts = maxi(npts, road.size())
	if roads.size() > 0 and npts > 0:
		var data := PackedFloat32Array()
		data.resize(npts * roads.size() * 2)
		for ri in roads.size():
			var road: Array = roads[ri]
			for i in npts:
				var p: Dictionary = road[mini(i, road.size() - 1)]
				data[(ri * npts + i) * 2] = (float(p.x) + _b + 0.5) * _r
				data[(ri * npts + i) * 2 + 1] = (float(p.y) + _b + 0.5) * _r
		var img := Image.create_from_data(npts, roads.size(), false, Image.FORMAT_RGF, data.to_byte_array())
		mat.set_shader_parameter("road_tex", ImageTexture.create_from_image(img))
		mat.set_shader_parameter("road_count", roads.size())
		mat.set_shader_parameter("road_points", npts)
	else:
		mat.set_shader_parameter("road_count", 0)
	var rect := ColorRect.new()
	rect.size = Vector2(fw, fh)
	rect.material = mat
	_field_vp.add_child(rect)
	var dabs := MultiMeshInstance2D.new()
	dabs.multimesh = _make_dabs()
	var dmat := ShaderMaterial.new()
	dmat.shader = DabShader
	dabs.material = dmat
	_field_vp.add_child(dabs)
	_field_tex = _field_vp.get_texture()


## Painterly dabs: light and dark strokes across the meadow (exact Rng sequence).
func _make_dabs() -> MultiMesh:
	var rng := Rng.new(_seed + 1234)
	var st: int = rng.state
	var n := _gw * _gh * 22
	var buf := PackedFloat32Array()
	buf.resize(n * 16)
	var count := 0
	var k := _r / 24.0
	var gw := float(_gw)
	var gh := float(_gh)
	var cats := _cats
	var R := float(_r)
	for i in n:
		# Inlined mulberry32 (rng.gd next()) for speed: four draws per dab.
		st = (st + 0x6d2b79f5) & U32
		var t: int = st
		var a: int = t ^ (t >> 15)
		var b: int = t | 1
		t = ((a * (b & 0xFFFF)) + (((a * (b >> 16)) & 0xFFFF) << 16)) & U32
		a = t ^ (t >> 7)
		b = t | 61
		t = t ^ ((t + (((a * (b & 0xFFFF)) + (((a * (b >> 16)) & 0xFFFF) << 16)) & U32)) & U32)
		var u: float = float(t ^ (t >> 14)) / 4294967296.0 * gw
		st = (st + 0x6d2b79f5) & U32
		t = st
		a = t ^ (t >> 15)
		b = t | 1
		t = ((a * (b & 0xFFFF)) + (((a * (b >> 16)) & 0xFFFF) << 16)) & U32
		a = t ^ (t >> 7)
		b = t | 61
		t = t ^ ((t + (((a * (b & 0xFFFF)) + (((a * (b >> 16)) & 0xFFFF) << 16)) & U32)) & U32)
		var v: float = float(t ^ (t >> 14)) / 4294967296.0 * gh
		var cat: int = cats[int(v) * _gw + int(u)]
		if cat == C_WATER or cat == C_STONE:
			continue
		st = (st + 0x6d2b79f5) & U32
		t = st
		a = t ^ (t >> 15)
		b = t | 1
		t = ((a * (b & 0xFFFF)) + (((a * (b >> 16)) & 0xFFFF) << 16)) & U32
		a = t ^ (t >> 7)
		b = t | 61
		t = t ^ ((t + (((a * (b & 0xFFFF)) + (((a * (b >> 16)) & 0xFFFF) << 16)) & U32)) & U32)
		var light: bool = float(t ^ (t >> 14)) / 4294967296.0 < 0.5
		st = (st + 0x6d2b79f5) & U32
		t = st
		a = t ^ (t >> 15)
		b = t | 1
		t = ((a * (b & 0xFFFF)) + (((a * (b >> 16)) & 0xFFFF) << 16)) & U32
		a = t ^ (t >> 7)
		b = t | 61
		t = t ^ ((t + (((a * (b & 0xFFFF)) + (((a * (b >> 16)) & 0xFFFF) << 16)) & U32)) & U32)
		var s: float = (1.0 + float(t ^ (t >> 14)) / 4294967296.0 * 1.6) * k
		var o := count * 16
		# Identity 2D transform (rows: x.x y.x 0 origin.x / x.y y.y 0 origin.y).
		buf[o] = 1.0
		buf[o + 5] = 1.0
		# Colour.
		if cat == C_DIRT:
			if light:
				buf[o + 8] = 220.0 / 255.0; buf[o + 9] = 190.0 / 255.0; buf[o + 10] = 130.0 / 255.0; buf[o + 11] = 0.35
			else:
				buf[o + 8] = 90.0 / 255.0; buf[o + 9] = 70.0 / 255.0; buf[o + 10] = 40.0 / 255.0; buf[o + 11] = 0.25
		elif light:
			buf[o + 8] = 200.0 / 255.0; buf[o + 9] = 215.0 / 255.0; buf[o + 10] = 110.0 / 255.0; buf[o + 11] = 0.28
		else:
			buf[o + 8] = 40.0 / 255.0; buf[o + 9] = 70.0 / 255.0; buf[o + 10] = 25.0 / 255.0; buf[o + 11] = 0.22
		# Custom: the rect.
		buf[o + 12] = u * R
		buf[o + 13] = v * R
		buf[o + 14] = s * 2.2
		buf[o + 15] = s
		count += 1
	buf.resize(count * 16)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _unit_quad()
	mm.instance_count = count
	# Quads are placed by the shader: the real extent, so nothing is culled.
	mm.custom_aabb = AABB(Vector3(-2, -2, -1), Vector3(_gw * _r + 4, _gh * _r + 4, 2))
	if count > 0:
		mm.buffer = buf
	return mm


static func _unit_quad() -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _make_iso() -> void:
	_iso_vp = SubViewport.new()
	_iso_vp.name = "Layer"
	_iso_vp.size = Vector2i(width, height)
	_iso_vp.transparent_bg = true
	_iso_vp.disable_3d = true
	_iso_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_iso_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	# Sprites painted into the layer (decals, baked props) are minified: mipmaps.
	_iso_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# The field viewport is a child so it renders first.
	_iso_vp.add_child(_field_vp)
	_paint = Node2D.new()
	_paint.name = "Paint"
	_paint.scale = Vector2(layer_scale, layer_scale)
	# The field render target has no mipmaps: plain bilinear for it.
	_paint.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_paint.draw.connect(_paint_layer)
	_iso_vp.add_child(_paint)
	_decal_node = Node2D.new()
	_decal_node.name = "Decals"
	_decal_node.scale = Vector2(layer_scale, layer_scale)
	_decal_node.draw.connect(_paint_decals)
	_iso_vp.add_child(_decal_node)
	add_child(_iso_vp)
	texture = _iso_vp.get_texture()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func _ready() -> void:
	RenderingServer.frame_post_draw.connect(_on_drawn, CONNECT_ONE_SHOT)


func _on_drawn() -> void:
	if not is_instance_valid(self):
		return
	_rendered_once = true
	is_built = true
	# Everything is in the layer texture now: drop the field and the paint.
	_paint.visible = false
	_decal_node.visible = false
	if is_instance_valid(_field_vp) and not has_meta("keep_field"):
		_field_vp.queue_free()
	_iso_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	built.emit()


## The colour field (debug captures; needs meta "keep_field" set before the build renders).
func field_image() -> Image:
	if is_instance_valid(_field_vp):
		return _field_vp.get_texture().get_image()
	return null


## Paints into the layer in world pixels (see the header).
func bake(fn: Callable) -> void:
	var n := Node2D.new()
	n.name = "Bake%d" % _iso_vp.get_child_count()
	n.position = Vector2(-ox * layer_scale, -oy * layer_scale)
	n.scale = Vector2(layer_scale, layer_scale)
	n.draw.connect(func() -> void: fn.call(n))
	_iso_vp.add_child(n)
	if _rendered_once:
		# Only the new painting is drawn over what the layer holds.
		for c in _iso_vp.get_children():
			if c is CanvasItem and c != n:
				c.visible = false
		_iso_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		RenderingServer.frame_post_draw.connect(_after_bake.bind(n), CONNECT_ONE_SHOT)


func _after_bake(n: Node2D) -> void:
	if is_instance_valid(n):
		n.visible = false
	if is_instance_valid(_iso_vp):
		_iso_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _draw() -> void:
	if self_draw:
		draw_ground(self)


## ctx.drawImage(tl.canvas, tl.ox, tl.oy, tl.canvas.width / tl.scale, tl.canvas.height / tl.scale)
func draw_ground(ci: CanvasItem) -> void:
	ci.draw_texture_rect(texture, Rect2(ox, oy, width / layer_scale, height / layer_scale), false)


func make_water_node(style: String = "battle") -> Node2D:
	var n: Node2D = WaterNode.new()
	n.setup(self, style)
	return n


# ---------------------------------------------------------------- painting (iso pass)


func _diamond(x: float, y: float, lvl: float, o: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		Iso.iso(x - 0.5, y - 0.5, lvl) - o,
		Iso.iso(x + 0.5, y - 0.5, lvl) - o,
		Iso.iso(x + 0.5, y + 0.5, lvl) - o,
		Iso.iso(x - 0.5, y + 0.5, lvl) - o,
	])


## Field UVs of a tile diamond's corners (same mapping as drawField).
func _diamond_uv(x: float, y: float) -> PackedVector2Array:
	var fw := float(_gw * _r)
	var fh := float(_gh * _r)
	var u0 := (x + _b) * _r / fw
	var u1 := (x + _b + 1) * _r / fw
	var v0 := (y + _b) * _r / fh
	var v1 := (y + _b + 1) * _r / fh
	return PackedVector2Array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)])


func _draw_field(ci: CanvasItem, level: int) -> void:
	# pixel (u, v) -> grid (u/R - B - 0.5, v/R - B - 0.5) -> iso world -> layer
	var a := TW / 2.0 / _r
	var b := TH / 2.0 / _r
	var gx0 := -_b - 0.5
	var gy0 := -_b - 0.5
	ci.draw_set_transform_matrix(Transform2D(Vector2(a, b), Vector2(-a, b), Vector2(Iso.iso_x(gx0, gy0) - ox, Iso.iso_y(gx0, gy0, level) - oy)))
	ci.draw_texture(_field_tex, Vector2.ZERO)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


func _paint_layer() -> void:
	var ci := _paint
	var o := Vector2(ox, oy)
	_draw_field(ci, 0)
	for L in range(1, max_h + 1):
		# Cliff faces for this band, back to front.
		var raised: Array = []
		for t in _tiles:
			if int(t.h) >= L:
				raised.append(t)
		raised = JS.sort(raised, func(p, q): return (p.x + p.y) - (q.x + q.y))
		for t in raised:
			if h_at(int(t.x) + 1, int(t.y)) < L:
				_face(ci, int(t.x), int(t.y), L, true, o)
			if h_at(int(t.x), int(t.y) + 1) < L:
				_face(ci, int(t.x), int(t.y), L, false, o)
		# The raised field, clipped to the plateau (each diamond maps the same field pixels).
		var white := PackedColorArray([Color.WHITE])
		for t in raised:
			ci.draw_polygon(_diamond(t.x, t.y, L, o), white, _diamond_uv(t.x, t.y), _field_tex)
		# Slight brightening of higher ground (sunlit).
		var lit := PackedColorArray([Color8(255, 240, 190, 0) + Color(0, 0, 0, 0.05 * L)])
		for t in raised:
			ci.draw_polygon(_diamond(t.x, t.y, L, o), lit)
		# Rim light on back edges and grass lips on front edges.
		for t in raised:
			var x := int(t.x)
			var y := int(t.y)
			if int(t.h) != L and h_at(x, y) > L:
				continue
			var edges := [
				[h_at(x - 1, y) < L, x - 0.5, y - 0.5, x - 0.5, y + 0.5, Color(1.0, 245 / 255.0, 200 / 255.0, 0.55), true],
				[h_at(x, y - 1) < L, x - 0.5, y - 0.5, x + 0.5, y - 0.5, Color(1.0, 245 / 255.0, 200 / 255.0, 0.4), true],
				[h_at(x + 1, y) < L, x + 0.5, y - 0.5, x + 0.5, y + 0.5, Color(70 / 255.0, 110 / 255.0, 35 / 255.0, 0.95), false],
				[h_at(x, y + 1) < L, x - 0.5, y + 0.5, x + 0.5, y + 0.5, Color(90 / 255.0, 130 / 255.0, 40 / 255.0, 0.95), false],
			]
			for e in edges:
				if not e[0]:
					continue
				var s1 := Iso.iso(e[1], e[2], L) - o
				var s2 := Iso.iso(e[3], e[4], L) - o
				var light: bool = e[6]
				var wdt := 2.0 if light else 5.0
				var pts := PackedVector2Array([s1])
				for i in range(1, 7):
					var f := i / 6.0
					var wob := 0.0 if light else sin((f + x * 0.37 + y * 0.61) * 9.0) * 2.2
					pts.append(Vector2(s1.x + (s2.x - s1.x) * f, s1.y + (s2.y - s1.y) * f + wob))
				_stroke(ci, pts, e[5], wdt, true)

	# Bridges.
	for t in _tiles:
		if t.terrain != "bridge":
			continue
		var c := Iso.iso(t.x, t.y, t.h) - o
		for i in 7:
			var f := i / 6.0 - 0.5
			var col := Color8(0x8a, 0x62, 0x38) if i % 2 else Color8(0x9c, 0x72, 0x43)
			# Planks run across the river (along x).
			var ax := (f - 0.07) * TW * 0.5
			var bx := (f + 0.07) * TW * 0.5
			var poly := PackedVector2Array([
				c + Vector2(ax - TW * 0.36, ax * 0.5 + TW * 0.18 - 6),
				c + Vector2(bx - TW * 0.36, bx * 0.5 + TW * 0.18 - 6),
				c + Vector2(bx + TW * 0.36, bx * 0.5 - TW * 0.18 - 6),
				c + Vector2(ax + TW * 0.36, ax * 0.5 - TW * 0.18 - 6),
			])
			ci.draw_colored_polygon(poly, col)
			var loop := poly.duplicate()
			loop.append(poly[0])
			ci.draw_polyline(loop, Color(40 / 255.0, 25 / 255.0, 15 / 255.0, 0.7), 1.2, true)

	# Ambient occlusion along the outer forest edge.
	if _palette != "map":
		var ao := Color(20 / 255.0, 35 / 255.0, 15 / 255.0, 0.35)
		for y in range(-_b, _h + _b):
			for x in range(-_b, _w + _b):
				if x >= 0 and y >= 0 and x < _w and y < _h:
					continue
				var d := maxi(maxi(-x, -y), maxi(x - (_w - 1), y - (_h - 1)))
				if d < 2:
					continue
				ci.draw_colored_polygon(_diamond(x, y, 0, o), ao)




## 3. Decals: tufts, flowers and pebbles (after the plateaus, bridges and edge shading).
func _paint_decals() -> void:
	var ci := _decal_node
	var o := Vector2(ox, oy)
	var A = _assets()
	if A != null and not _decals.is_empty():
		for d in _decals:
			var hh := h_at(JS.rnd(d.x), JS.rnd(d.y))
			var s = A.sprite(d.k, d.v)
			if s == null:
				continue
			var p := Iso.iso(d.x, d.y, hh) - o
			A.draw_sprite(ci, s, p.x, p.y, d.v == 1, 0.9 + (d.v % 2) * 0.2)


## A wide stroke with round caps (canvas lineCap 'round').
func _stroke(ci: CanvasItem, pts: PackedVector2Array, col: Color, wdt: float, round_caps: bool) -> void:
	if round_caps and wdt >= 3.0:
		WD.stroke_round(ci, pts, col, wdt)
	else:
		ci.draw_polyline(pts, col, wdt, true)


func _face(ci: CanvasItem, x: int, y: int, L: int, se: bool, o: Vector2) -> void:
	var p1 := Vector2(x + 0.5, y - 0.5) if se else Vector2(x - 0.5, y + 0.5)
	var p2 := Vector2(x + 0.5, y + 0.5)
	var a := Iso.iso(p1.x, p1.y, L) - o
	var b := Iso.iso(p2.x, p2.y, L) - o
	var quad := PackedVector2Array([a, b, b + Vector2(0, LH), a + Vector2(0, LH)])
	var y0 := minf(a.y, b.y)
	var y1 := maxf(a.y, b.y) + LH
	var c0 := Color8(0x9a, 0x84, 0x66) if not se else Color8(0x6f, 0x5c, 0x45)
	var c1 := Color8(0x6e, 0x5a, 0x42) if not se else Color8(0x4a, 0x3c, 0x2c)
	var cols := PackedColorArray()
	for p in quad:
		cols.append(c0.lerp(c1, (p.y - y0) / (y1 - y0)))
	ci.draw_polygon(quad, cols)
	# Rock strata and stones (clipped to the face).
	var rng := Rng.new(_seed + x * 31 + y * 17 + L * 7 + (1 if se else 0))
	for i in 7:
		var f := rng.next()
		var px := a.x + (b.x - a.x) * f
		var py := a.y + (b.y - a.y) * f + rng.frange(4, LH - 4)
		var col := Color(200 / 255.0, 190 / 255.0, 170 / 255.0, 0.35) if rng.chance(0.5) else Color(40 / 255.0, 30 / 255.0, 20 / 255.0, 0.3)
		var rx := rng.frange(4, 9)
		var ry := rng.frange(2.5, 5)
		var ell := PackedVector2Array()
		for k in 24:
			var an := TAU * k / 24.0
			ell.append(Vector2(px + cos(an) * rx, py + sin(an) * ry))
		for part in Geometry2D.intersect_polygons(ell, quad):
			ci.draw_colored_polygon(part, col)
	ci.draw_line(a + Vector2(0, LH), b + Vector2(0, LH), Color(40 / 255.0, 28 / 255.0, 18 / 255.0, 0.6), 1.2, true)


func _make_decals() -> void:
	var drng := Rng.new(_seed + 99)
	var list: Array = []
	for gy in range(-_b, _h + _b):
		for gx in range(-_b, _w + _b):
			var cat := terr_at(gx, gy)
			if cat == C_WATER or cat == C_STONE:
				continue
			var n := 3 if cat == C_GRASS else (1 if cat == C_DIRT else (4 if cat == C_BRUSH else 1))
			for i in n:
				if not drng.chance(0.75):
					continue
				var k := ""
				if cat == C_DIRT:
					k = "pebble" if drng.chance(0.7) else "tuft"
				else:
					k = "flower" if drng.chance(0.18) else "tuft"
				var dx := gx + drng.frange(-0.45, 0.45)
				var dy := gy + drng.frange(-0.45, 0.45)
				list.append({"x": dx, "y": dy, "k": k, "v": drng.rint(0, 2)})
	_decals = JS.sort(list, func(p, q): return (p.x + p.y) - (q.x + q.y))
