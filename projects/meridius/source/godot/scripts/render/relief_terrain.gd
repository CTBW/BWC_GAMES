## Opt-in textured terrain for the terrain test fields. Keeps Terrain's cached
## layer, water and bake API so the normal battle passes render above it.
extends "res://scripts/render/terrain.gd"

const Relief = preload("res://scripts/render/relief.gd")
const ReliefShader = preload("res://assets/shaders/terrain_relief.gdshader")
var surface


static func create(inp: Dictionary) -> Node2D:
	var layer = load("res://scripts/render/relief_terrain.gd").new()
	layer.surface = Relief.new(inp.w, inp.h, inp.border, inp.tiles, inp.seed)
	layer._build(inp)
	return layer


func _make_field() -> void:
	pass # The material samples the tile textures directly on the mesh.


func _make_iso() -> void:
	_iso_vp = SubViewport.new()
	_iso_vp.name = "ReliefLayer"
	_iso_vp.size = Vector2i(width, height)
	_iso_vp.transparent_bg = true
	_iso_vp.disable_3d = true
	_iso_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_iso_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	var mat := ShaderMaterial.new()
	mat.shader = ReliefShader
	mat.set_shader_parameter("h_tex", ImageTexture.create_from_image(surface.height_image()))
	mat.set_shader_parameter("cat_tex", ImageTexture.create_from_image(Image.create_from_data(_gw, _gh, false, Image.FORMAT_R8, _cats)))
	# Shade under the canopy: full under trees, lighter beside bushes and rocks.
	var occ := Image.create(_gw, _gh, false, Image.FORMAT_R8)
	for t in _tiles:
		var prop := String(t.get("prop", ""))
		if prop.begins_with("tree"):
			occ.set_pixel(t.x + _b, t.y + _b, Color.WHITE)
		elif prop == "bush" or prop.begins_with("rock"):
			occ.set_pixel(t.x + _b, t.y + _b, Color(0.55, 0.55, 0.55))
	mat.set_shader_parameter("occ_tex", ImageTexture.create_from_image(occ))
	mat.set_shader_parameter("gw", _gw)
	mat.set_shader_parameter("gh", _gh)
	mat.set_shader_parameter("border", _b)
	mat.set_shader_parameter("phase", Vector4(surface.phase[0], surface.phase[1], surface.phase[2], surface.phase[3]))
	mat.set_shader_parameter("seed", _seed)
	mat.set_shader_parameter("camp", false)
	mat.set_shader_parameter("hmax", surface.max_h)
	for pair in [["grass", "grass"], ["dry", "dry_grass"], ["dirt", "dirt"], ["forest", "forest_floor"], ["rock", "rock"], ["mud", "mud"], ["stone", "flagstone"]]:
		mat.set_shader_parameter("tex_" + pair[0], load("res://assets/terrain/%s.webp" % pair[1]))
	var ground := MeshInstance2D.new()
	ground.name = "Surface"
	ground.mesh = surface.mesh(4, Vector2(ox, oy))
	ground.material = mat
	ground.scale = Vector2.ONE * layer_scale
	_iso_vp.add_child(ground)
	_paint = ground
	_decal_node = Node2D.new()
	_decal_node.scale = Vector2.ONE * layer_scale
	_decal_node.draw.connect(_paint_meadow)
	_iso_vp.add_child(_decal_node)
	add_child(_iso_vp)
	texture = _iso_vp.get_texture()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func show_height_contours(on: bool) -> void:
	_paint.material.set_shader_parameter("height_view", on)
	_paint.visible = true
	_decal_node.visible = not on
	_iso_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_iso_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if not RenderingServer.frame_post_draw.is_connected(_on_drawn):
		RenderingServer.frame_post_draw.connect(_on_drawn, CONNECT_ONE_SHOT)


## Sparse upright brush strokes give the ground a soft grassy silhouette.
## Cached with the ground; no per-frame grass geometry or independent height.
func _paint_meadow() -> void:
	var rng := Rng.new(_seed + 451)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for tile in _tiles:
		if tile.x < -3 or tile.y < -3 or tile.x > _w + 3 or tile.y > _h + 3:
			continue
		if tile.terrain not in ["grass", "brush", "forest"]:
			continue
		if not rng.chance(0.65):
			continue
		var n := 12 if tile.terrain == "brush" else (3 if tile.terrain == "forest" else 7)
		for i in n:
			var x: float = tile.x + rng.frange(-0.48, 0.48)
			var y: float = tile.y + rng.frange(-0.48, 0.48)
			var p := Iso.iso(x, y, surface.surface(x, y)) - Vector2(ox, oy)
			var green := Color(0.47, 0.53, 0.24)
			var gold := Color(0.77, 0.66, 0.32)
			var tip := green.lerp(gold, rng.frange(0.0, 1.0))
			var base := Color(0.28, 0.34, 0.16, 0.65)
			for blade in 3:
				var offset := rng.frange(-4.0, 4.0)
				var height := rng.frange(5.0, 13.0)
				var k := pts.size()
				pts.append_array([p + Vector2(offset - 1.3, 1), p + Vector2(offset + 1.3, 1), p + Vector2(offset + rng.frange(-4.0, 1.0), -height)])
				cols.append_array([base, base, tip])
				idx.append_array([k, k + 1, k + 2])
	if not idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(_decal_node.get_canvas_item(), idx, pts, cols)
