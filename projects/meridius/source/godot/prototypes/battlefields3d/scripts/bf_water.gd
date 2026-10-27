## The open water's sheet over a 3D battlefield's river or lake: one flat mesh
## at the water level wherever the relief ground lies below it, drawn by
## shaders/bf_water.gdshader over the bed and banks the relief shader painted.
## Vertex colour R is the depth (0 at the bank, 1 at DEEP levels down), G and B
## the current's direction (grid x and y, -1..1 as 0..1) from the river tiles'
## "flow" (bf_fields.gd); lakes are still. Only the water and shallows tiles
## hold water: a hollow elsewhere below the level stays dry, and the sheet
## thins out over the bank. None where nothing lies below the level (or when
## the water is frozen: bf_field.gd does not ask).
extends RefCounted

const WaterShader = preload("res://prototypes/battlefields3d/shaders/bf_water.gdshader")
const Fields = preload("res://prototypes/battlefields3d/scripts/bf_fields.gd")
## Vertices per tile side.
const SUB := 3
## The depth (levels) at which the water counts as deep.
const DEEP := 0.6


static func build(relief, tiles: Array, level: float, tile_m: float, level_m: float) -> MeshInstance3D:
	if level < -50.0:
		return null
	var b: int = relief.b
	var gw: int = relief.gw
	var gh: int = relief.gh
	var flow := {}
	var wet := {}
	for t in tiles:
		if t.has("flow"):
			flow[Vector2i(t.x, t.y)] = Vector2(t.flow[0], t.flow[1])
		if t.terrain in ["water", "shallows"]:
			wet[Vector2i(t.x, t.y)] = true
	var x0 := -b - 0.5
	var y0 := -b - 0.5
	var nx := gw * SUB + 1
	var ny := gh * SUB + 1
	var depth := PackedFloat32Array()
	depth.resize(nx * ny)
	for j in ny:
		for k in nx:
			var gx := x0 + float(k) / SUB
			var gy := y0 + float(j) / SUB
			var d: float = level - relief.surface(gx, gy)
			depth[j * nx + k] = d if wet.has(Vector2i(roundi(gx), roundi(gy))) else minf(d, 0.0)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var index := {}
	var y := level * level_m + 0.01
	var vert := func(k: int, j: int) -> int:
		var i := j * nx + k
		if index.has(i):
			return index[i]
		var gx := x0 + float(k) / SUB
		var gy := y0 + float(j) / SUB
		var f: Vector2 = flow.get(Vector2i(roundi(gx), roundi(gy)), Vector2.ZERO)
		index[i] = verts.size()
		verts.append(Vector3(gx * tile_m, y, gy * tile_m))
		cols.append(Color(clampf(depth[i] / DEEP, 0.0, 1.0), f.x * 0.5 + 0.5, f.y * 0.5 + 0.5, 1.0))
		return index[i]
	for j in ny - 1:
		for k in nx - 1:
			var a := j * nx + k
			if depth[a] <= 0.0 and depth[a + 1] <= 0.0 and depth[a + nx] <= 0.0 and depth[a + nx + 1] <= 0.0:
				continue
			var v00: int = vert.call(k, j)
			var v10: int = vert.call(k + 1, j)
			var v01: int = vert.call(k, j + 1)
			var v11: int = vert.call(k + 1, j + 1)
			idx.append_array([v00, v10, v01, v10, v11, v01])
	if idx.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = WaterShader
	m.set_shader_parameter("tile_m", tile_m)
	m.set_shader_parameter("tile_px", Fields.TILE_PX)
	m.set_shader_parameter("level_m", level_m)
	mi.material_override = m
	return mi
