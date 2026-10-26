## One 3D battlefield, built from its field (bf_fields.gd) the way the 3D
## sandbox builds its training ground (prototypes/sandbox3d field3d.gd):
##   - the ground: one mesh over the relief surface (scripts/render/relief.gd),
##     painted once by the battle's relief shader in the field's season
##     (assets/shaders/terrain_relief.gdshader: summer, autumn, winter, spring,
##     frozen water) into two top-down pictures the mesh looks up
##     (shaders/bf_ground.gdshader);
##   - the cards: the painted trees, rocks, houses, ruins, the bridge and the
##     farm's things as upright cut-outs turned to the camera, each with its
##     painted shadow draped over the ground (shaders/bf_card.gdshader). The
##     woods are northern (NORTH): dark spruce and fir with Scots pine, silver
##     birch, now and then an oak or a beech, small firs in the thickets.
##     Summer paintings turn gold in autumn; in winter the woods are the
##     winter kit's snowy spruce, pines and bare trees, and what has no winter
##     painting takes snow along its top edges. With `sun_shadows` (set before
##     build; the scene's DirectionalLight3D shines along `sun_way`) the sun
##     casts the shadows instead of the paintings: no painted shadow is laid,
##     each card has an unseen copy turned to the sun that only casts
##     (shaders/bf_card_caster.gdshader; the copies of one picture are one
##     mesh, `_build_casters`), and the ground takes the shadows
##     (shaders/bf_sun_shade.gdshader, the ground's overlay);
##   - grass strokes in the season's colours, and the open water's sheet
##     (bf_water.gd), unless the water is frozen;
##   - the points the chimney smoke and the burnt barn's smoke rise from
##     (`smoke`, for bf_weather.gd).
## World axes: x = grid x, z = grid y; a tile is `tile_m` metres, a level of
## height `level_m`.
extends Node3D

const Relief = preload("res://scripts/render/relief.gd")
const Rng = preload("res://scripts/core/rng.gd")
const Fields = preload("res://prototypes/battlefields3d/scripts/bf_fields.gd")
const Water = preload("res://prototypes/battlefields3d/scripts/bf_water.gd")
const ReliefShader = preload("res://assets/shaders/terrain_relief.gdshader")
const GroundShader = preload("res://prototypes/battlefields3d/shaders/bf_ground.gdshader")
const CardShader = preload("res://prototypes/battlefields3d/shaders/bf_card.gdshader")
const CasterShader = preload("res://prototypes/battlefields3d/shaders/bf_card_caster.gdshader")
const ShadeShader = preload("res://prototypes/battlefields3d/shaders/bf_sun_shade.gdshader")
const FOG_GRAIN := "res://assets/terrain/fog_grain.png"
const ART := "res://prototypes/battlefields3d/art/art.json"
const GROUND_ART := "res://prototypes/battlefields3d/art/ground/"

const W := Fields.W
const H := Fields.H
const BORDER := Fields.BORDER
## Ground mesh cells per tile side.
const SUB := 4
## The ground pictures: the field and NEAR_PAD tiles round it at BAKE_NEAR
## pixels square, the whole padded grid at BAKE_FAR.
const NEAR_PAD := 8
const BAKE_NEAR := 4096
const BAKE_FAR := 2048
## Screen pixels per level of height at zoom 1 (the relief shader's LH).
const LEVEL_PX := 26.0
const SEASONS := {"summer": 0, "autumn": 1, "winter": 2, "spring": 3}
## Terrain categories as the battle's relief shader numbers them
## (terrain.gd cat_of; 7: forest floor outside the field).
const CATS := {"grass": 0, "dirt": 1, "road": 1, "brush": 2, "forest": 3, "stone": 4,
	"water": 5, "bridge": 5, "shallows": 6, "mud": 8}
const FLOOR_CAT := 7
## A card's upright part is drawn this far toward the camera (metres): in the
## orthographic view that moves nothing on screen, it only keeps a slope in
## front of the foot from cutting it off.
const CARD_PULL := 0.7
## Cards are built this many tiles round the field; beyond, the far woods are
## the ground picture's forest floor.
const CARD_PAD := 7
## Decor that bends in the wind and grows in varying sizes.
const SOFT := ["reeds", "reeds_small", "iris", "marigolds", "horsetail"]
## The northern woods (docs/terrain-direction-2026-10-23.md: tall spruce and
## Scots pine, silver birch, the odd broadleaf, dark natural greens): each
## kind's woodland paintings (assets/sprites.json) by name, repeated by share.
const NORTH := {
	"n_evergreen": ["woodland_spruce", "woodland_spruce", "woodland_spruce", "woodland_fir_young",
		"woodland_scots_pine", "woodland_scots_pine", "woodland_pine"],
	"n_birch": ["woodland_birch"],
	"n_aspen": ["woodland_aspen_gold"],
	"n_fir_young": ["woodland_fir_young"],
}
## Of a tile's broadleaf tree (tree_oak), the share that is a birch.
const BIRCH := 0.7

var tile_m := 2.72
var level_m := 0.9
var elevation := 30.0
var ppu := 33.0
## The sun casts the shadows, not the paintings (see the top).
var sun_shadows := false
## The sun's light across the ground (horizontal): from the screen's upper
## left, as the battle's and the sandbox's sun.
var sun_way := Vector3(1, 0, 0)
var data: Dictionary
var map: Dictionary
var season := "summer"
var relief
var ground: MeshInstance3D
var mat: ShaderMaterial
var water: MeshInstance3D
## Every card: {"node", "grid" (Vector2 foot), "kind", "key"}.
var cards: Array = []
## Where smoke rises: {"at": Vector3, "kind": "chimney" | "ash"}.
var smoke: Array = []
var _card_mats := {}
## The casters by material (sun_shadows), merged once the field is built:
## {key: {"mat", "parts": [[verts, uvs, uv2s, idx], ...]}}.
var _casters := {}
## The ground's overlay that takes the sun's shadows (sun_shadows).
var _shade_mat: ShaderMaterial
var _glow_mats: Array = []
var _shared := {}
var _blades: MeshInstance3D
var _sprites: Dictionary
var _art: Dictionary
var _north := {}
var _outer: Array = []
var _mark_img: Image
var _mark_tex: ImageTexture
## The ground mesh's heights (levels) as a texture, for the fog behind cards.
var _h_tex: ImageTexture
var _h_origin: Vector2
var _bakes: Array = []


func build(field_id: String, tile: float, level: float, elev: float, px_per_m: float) -> void:
	tile_m = tile
	level_m = level
	elevation = elev
	ppu = px_per_m
	data = Fields.make(field_id)
	map = data.map
	_outer = data.outer
	season = data.season
	_sprites = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites.json"))
	_art = JSON.parse_string(FileAccess.get_file_as_string(ART))
	relief = Relief.new(W, H, BORDER, map.tiles + _outer, data.seed)
	_build_ground()
	_build_woodland()
	_build_pieces()
	if sun_shadows:
		_build_casters()
	_build_blades()
	if not data.frozen:
		water = Water.build(relief, map.tiles + _outer, float(data.water_level), tile_m, level_m)
		if water:
			add_child(water)
			water.material_override.set_shader_parameter("map_size", Vector2(W, H))
			water.material_override.set_shader_parameter("fog_grain", load(FOG_GRAIN))


## Waits until the ground pictures have been drawn (on the next frame drawn).
func wait_baked() -> void:
	for i in 3:
		await RenderingServer.frame_post_draw


func tile(x: int, y: int) -> Variant:
	if x < 0 or y < 0 or x >= W or y >= H:
		return null
	return map.tiles[y * W + x]


# --- Ground queries -------------------------------------------------------------

## Ground height (metres) under a world point.
func ground_y(wx: float, wz: float) -> float:
	return relief.surface(wx / tile_m, wz / tile_m) * level_m


func on_ground(grid: Vector2) -> Vector3:
	var p := Vector3(grid.x * tile_m, 0, grid.y * tile_m)
	p.y = ground_y(p.x, p.z)
	return p


func tile_of(world: Vector3) -> Vector2i:
	return Vector2i(roundi(world.x / tile_m), roundi(world.z / tile_m))


func in_field(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < W and t.y < H


## The ground point under a screen ray, marched along the ray over the relief.
func pick(origin: Vector3, dir: Vector3) -> Variant:
	if absf(dir.y) < 1e-4:
		return null
	var top: float = (float(relief.max_h) + 1.0) * level_m
	var t := (top - origin.y) / dir.y
	var step := 0.25
	var prev := origin + dir * t
	for i in 1200:
		var p := origin + dir * (t + step * i)
		if p.y <= ground_y(p.x, p.z):
			var a := prev
			var b := p
			for k in 12:
				var m := (a + b) * 0.5
				if m.y <= ground_y(m.x, m.z):
					b = m
				else:
					a = m
			return b
		prev = p
	return null


## Highlight tiles on the ground (the scouts' tiles): 0 none, 1 route, 2 goal.
func mark(tiles: Dictionary) -> void:
	_mark_img.fill(Color.BLACK)
	for t in tiles:
		if in_field(t):
			_mark_img.set_pixel(t.x, t.y, Color(tiles[t] / 2.0, 0, 0))
	_mark_tex.update(_mark_img)


# --- The ground ----------------------------------------------------------------------

func _build_ground() -> void:
	var gw: int = relief.gw
	var gh: int = relief.gh
	var nx := gw * SUB + 1
	var ny := gh * SUB + 1
	var x0 := -BORDER - 0.5
	var y0 := -BORDER - 0.5
	var step := 1.0 / SUB
	var hs := PackedFloat32Array()
	hs.resize(nx * ny)
	for j in ny:
		for k in nx:
			hs[j * nx + k] = relief.surface(x0 + k * step, y0 + j * step)
	var himg := Image.create_from_data(nx, ny, false, Image.FORMAT_RF, hs.to_byte_array())
	himg.convert(Image.FORMAT_RH)
	_h_tex = ImageTexture.create_from_image(himg)
	_h_origin = Vector2(x0, y0)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(nx * ny)
	norms.resize(nx * ny)
	uvs.resize(nx * ny)
	var d := step * tile_m
	for j in ny:
		for k in nx:
			var i := j * nx + k
			var gx := x0 + k * step
			var gy := y0 + j * step
			verts[i] = Vector3(gx * tile_m, hs[i] * level_m, gy * tile_m)
			uvs[i] = Vector2(gx, gy)
			var hl := hs[j * nx + maxi(k - 1, 0)] * level_m
			var hr := hs[j * nx + mini(k + 1, nx - 1)] * level_m
			var hu := hs[maxi(j - 1, 0) * nx + k] * level_m
			var hd := hs[mini(j + 1, ny - 1) * nx + k] * level_m
			norms[i] = Vector3(hl - hr, 2.0 * d, hu - hd).normalized()
	var idx := PackedInt32Array()
	idx.resize((nx - 1) * (ny - 1) * 6)
	var n := 0
	for j in ny - 1:
		for k in nx - 1:
			var a := j * nx + k
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
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	ground = MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = mesh
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mat = ShaderMaterial.new()
	mat.shader = GroundShader
	var near := Rect2(-NEAR_PAD - 0.5, -NEAR_PAD - 0.5, W + 2 * NEAR_PAD, H + 2 * NEAR_PAD)
	var far := Rect2(x0, y0, gw, gh)
	mat.set_shader_parameter("near_tex", _bake("BakeNear", near, BAKE_NEAR).get_texture())
	mat.set_shader_parameter("far_tex", _bake("BakeFar", far, BAKE_FAR).get_texture())
	mat.set_shader_parameter("near_rect", Vector4(near.position.x, near.position.y, near.size.x, near.size.y))
	mat.set_shader_parameter("far_rect", Vector4(far.position.x, far.position.y, far.size.x, far.size.y))
	mat.set_shader_parameter("map_size", Vector2(W, H))
	mat.set_shader_parameter("tile_m", tile_m)
	mat.set_shader_parameter("level_m", level_m)
	mat.set_shader_parameter("fog_grain", load(FOG_GRAIN))
	_mark_img = Image.create(W, H, false, Image.FORMAT_R8)
	_mark_tex = ImageTexture.create_from_image(_mark_img)
	mat.set_shader_parameter("mark_tex", _mark_tex)
	ground.material_override = mat
	if sun_shadows:
		_shade_mat = ShaderMaterial.new()
		_shade_mat.shader = ShadeShader
		_shade_mat.set_shader_parameter("map_size", Vector2(W, H))
		_shade_mat.set_shader_parameter("tile_m", tile_m)
		ground.material_overlay = _shade_mat
	add_child(ground)


## One picture of the ground over `rect` (grid units), `size` pixels square,
## drawn once by the relief shader in the field's season. The shader lifts
## each vertex by the surface (its iso view); the quad's corners are lowered by
## as much beforehand, so the picture comes out top-down.
func _bake(label: String, rect: Rect2, size: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = label
	vp.size = Vector2i(size, size)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var gw: int = relief.gw
	var gh: int = relief.gh
	var rm := ShaderMaterial.new()
	rm.shader = ReliefShader
	rm.set_shader_parameter("h_tex", ImageTexture.create_from_image(relief.height_image()))
	var cats := PackedByteArray()
	cats.resize(gw * gh)
	# Shade under the canopy and round the buildings.
	var occ := Image.create(gw, gh, false, Image.FORMAT_R8)
	for t in map.tiles + _outer:
		var gx: int = int(t.x) + BORDER
		var gy: int = int(t.y) + BORDER
		var c: int = CATS.get(t.terrain, 0)
		if t.get("outer", false) and t.terrain == "forest":
			c = FLOOR_CAT
		cats[gy * gw + gx] = c
		var prop := String(t.get("prop", ""))
		if prop.begins_with("tree"):
			occ.set_pixel(gx, gy, Color.WHITE)
		elif prop in ["wall_high", "wall_ruin"]:
			occ.set_pixel(gx, gy, Color(0.7, 0.7, 0.7))
		elif prop == "bush" or prop.begins_with("rock"):
			occ.set_pixel(gx, gy, Color(0.55, 0.55, 0.55))
	rm.set_shader_parameter("cat_tex", ImageTexture.create_from_image(Image.create_from_data(gw, gh, false, Image.FORMAT_R8, cats)))
	rm.set_shader_parameter("occ_tex", ImageTexture.create_from_image(occ))
	rm.set_shader_parameter("gw", gw)
	rm.set_shader_parameter("gh", gh)
	rm.set_shader_parameter("border", BORDER)
	rm.set_shader_parameter("phase", Vector4(relief.phase[0], relief.phase[1], relief.phase[2], relief.phase[3]))
	rm.set_shader_parameter("seed", data.seed)
	rm.set_shader_parameter("camp", false)
	rm.set_shader_parameter("hmax", relief.max_h)
	for pair in [["grass", "grass"], ["dry", "dry_grass"], ["dirt", "dirt"], ["forest", "forest_floor"], ["rock", "rock"], ["mud", "mud"], ["stone", "flagstone"]]:
		rm.set_shader_parameter("tex_" + pair[0], load("res://assets/terrain/%s.webp" % pair[1]))
	rm.set_shader_parameter("season", SEASONS.get(season, 0))
	rm.set_shader_parameter("frozen", data.frozen)
	for g in ["snow", "snow_road", "ice", "autumn"]:
		rm.set_shader_parameter("tex_" + g, load(GROUND_ART + g + ".webp"))
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for c in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var g: Vector2 = rect.position + c * rect.size
		verts.append(c * size + Vector2(0, relief.surface(g.x, g.y) * LEVEL_PX))
		uvs.append(g)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 1, 3, 2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var quad := MeshInstance2D.new()
	quad.mesh = mesh
	quad.material = rm
	vp.add_child(quad)
	add_child(vp)
	_bakes.append(vp)
	return vp


# --- The woods and the field's small things -------------------------------------------

## The painting a tile's prop is drawn with in the field's season, its size
## and its look ({"autumn", "snow"}), or [] for none.
func _seasonal(prop: String, t: Dictionary) -> Array:
	var h := Rng.hash2(t.x, t.y, data.seed + 13)
	var winter := season == "winter"
	match prop:
		"tree_pine":
			if winter:
				return ["w_spruce" if h < 0.5 else ("w_scots_pine" if h < 0.8 else "w_fir_young"), 1.0, {}]
			return ["n_evergreen", 1.0, {}]
		"tree_oak":
			var birch := Rng.hash2(t.x, t.y, data.seed + 19) < BIRCH
			if winter:
				return ["w_birch_bare" if birch else "w_oak_bare", 1.0, {}]
			if t.has("art"):
				return [t.art, 1.0, {}]
			if birch:
				if season == "autumn":
					return ["n_aspen", 1.0, {}] if h < 0.5 else ["n_birch", 1.0, {"autumn": 0.85}]
				return ["n_birch", 1.0, {}]
			return ["tree_oak", 1.0, {"autumn": 1.0} if season == "autumn" else {}]
		"bush":
			if winter:
				return ["w_fir_young", 0.5, {}] if h < 0.45 else _snowed("deadwood")
			if h < 0.4:
				return ["n_fir_young", 0.5, {}]
			return ["bush", 1.0, {"autumn": 0.85} if season == "autumn" else {}]
		"stump", "log", "rock_small", "rock_large":
			return [("w_" + prop) if winter else prop, 1.0, {}]
	return []


## A small thing's painting in snow ("_w") where it has one, else its own
## with snow along its top edges: [key, size, look] as _seasonal.
func _snowed(key: String) -> Array:
	return [key + "_w", 1.0, {}] if _art.has(key + "_w") else [key, 1.0, {"snow": 1.0}]


func _variants(key: String) -> Array:
	if _art.has(key):
		return _art[key]
	if NORTH.has(key):
		return _northern(key)
	return _sprites.get(key, [])


## A NORTH kind's paintings: each name's entry in sprites.json (the one at a
## third of the painting's size where it has several).
func _northern(key: String) -> Array:
	if _north.has(key):
		return _north[key]
	var out := []
	for stem in NORTH[key]:
		var found = null
		for k in _sprites:
			if not _sprites[k] is Array:
				continue
			for e in _sprites[k]:
				if e is Dictionary and String(e.get("file", "")).get_file().get_basename() == stem:
					if found == null or absf(float(e.scale) - 0.3333) < absf(float(found.scale) - 0.3333):
						found = e
		if found != null:
			out.append(found)
	_north[key] = out
	return out


func _build_woodland() -> void:
	var holder := Node3D.new()
	holder.name = "Woodland"
	add_child(holder)
	var rng := Rng.new(data.seed + 17)
	var seed: int = data.seed
	var winter := season == "winter"
	for t in map.tiles + _outer:
		if t.x <= -CARD_PAD or t.y <= -CARD_PAD or t.x >= W + CARD_PAD or t.y >= H + CARD_PAD:
			continue
		var at := Vector2(t.x, t.y)
		var prop := String(t.get("prop", ""))
		if prop != "" and not t.get("covered", false):
			var pick := _seasonal(prop, t)
			if not pick.is_empty():
				var variants := _variants(pick[0])
				if not variants.is_empty():
					var e: Dictionary = variants[int(Rng.hash2(t.x, t.y, seed + 5) * variants.size()) % variants.size()]
					var j := Vector2(Rng.hash2(t.x, t.y, seed + 7) - 0.5, Rng.hash2(t.x, t.y, seed + 9) - 0.5)
					var tree := prop.begins_with("tree")
					var size: float = pick[1]
					if tree:
						size *= lerpf(0.9, 1.12, Rng.hash2(t.x, t.y, seed + 11))
					_card(holder, e, at + j * (0.64 if tree else 0.4), size, prop, pick[0], pick[2])
		if t.get("covered", false) or t.terrain in ["water", "shallows", "bridge", "stone"]:
			continue
		# Ferns (bracken in autumn) on the woodland floor and in the thickets.
		if not winter and t.terrain in ["forest", "brush"] and (prop == "" or prop == "bush" or rng.chance(0.4)):
			var ferns := _variants("fern")
			for i in (2 if t.terrain == "brush" else 1):
				if ferns.is_empty() or not rng.chance(0.7):
					continue
				var off := Vector2(rng.frange(-0.45, 0.45), rng.frange(-0.45, 0.45))
				if prop.begins_with("tree") and off.length() < 0.3:
					off = off.normalized() * 0.38 if off.length() > 0.01 else Vector2(0.38, 0.1)
				_card(holder, rng.pick(ferns), at + off, rng.frange(0.75, 1.15), "fern", "fern",
					{"autumn": 1.0} if season == "autumn" else {})
		# Fallen branches under the trees; small stones in the open.
		if t.terrain == "forest" and rng.chance(0.1):
			var dk := _snowed("deadwood") if winter else ["deadwood", 1.0, {"autumn": 0.6} if season == "autumn" else {}]
			var dw := _variants(dk[0])
			if not dw.is_empty():
				_card(holder, rng.pick(dw), at + Vector2(rng.frange(-0.4, 0.4), rng.frange(-0.4, 0.4)), rng.frange(0.8, 1.05),
					"deadwood", dk[0], dk[2])
		elif t.terrain in ["grass", "dirt", "mud"] and prop == "" and rng.chance(0.045):
			var sk := _snowed("stones") if winter else ["stones", 1.0, {}]
			var st := _variants(sk[0])
			if not st.is_empty():
				_card(holder, rng.pick(st), at + Vector2(rng.frange(-0.4, 0.4), rng.frange(-0.4, 0.4)), rng.frange(0.8, 1.1),
					"stones", sk[0], sk[2])


## The houses, mills, ruins and the bridge, and the field's single things
## (stalls, carts, harvest, fences, reeds).
func _build_pieces() -> void:
	var holder := Node3D.new()
	holder.name = "Pieces"
	add_child(holder)
	var winter := season == "winter"
	for pc in data.pieces:
		var variants := _variants(pc.key)
		if variants.is_empty():
			continue
		var e: Dictionary = variants[0]
		var lived: bool = pc.glow or e.has("smoke")
		var card := _card(holder, e, pc.foot, 1.0, "piece", pc.key, {"glow": lived, "snow": 1.0 if winter and not pc.key.begins_with("w_") else 0.0,
			"stand": pc.key == "bridge_stone", "piece": pc})
		for s in e.get("smoke", []):
			smoke.append({"at": _card_point(card, e, Vector2(s[0], s[1])), "kind": "chimney"})
		if pc.smoke == "ash":
			# A burnt roof smoulders along its length.
			for f in [0.36, 0.52, 0.68]:
				var px := Vector2(float(e.w) * f, float(e.ay) * 0.55)
				smoke.append({"at": _card_point(card, e, px), "kind": "ash"})
	for d in data.decor:
		# A winter field's props stand in snow where they have a winter painting.
		var variants := _variants(d.key + "_w" if winter and _art.has(d.key + "_w") else d.key)
		if variants.is_empty():
			continue
		var h := Rng.hash2(d.at.x * 7.0, d.at.y * 7.0, data.seed + 29)
		# A painting the field names ("v"), or one by the place.
		var v: int = d.get("v", -1)
		var e: Dictionary = variants[(v if v >= 0 else int(h * variants.size())) % variants.size()]
		var look := {"sway": d.key in SOFT}
		var reed: bool = d.key in ["reeds", "reeds_small"]
		if winter and not d.key.begins_with("w_") and not e.get("snowy", false):
			look["snow"] = 1.0
			if reed:
				look["autumn"] = 0.9
		elif season == "autumn" and reed:
			look["autumn"] = 0.7
		var size := lerpf(0.88, 1.08, h) if d.key in SOFT or d.key == "harvest_stook" else 1.0
		_card(holder, e, d.at, size, "decor", d.key, look)


## A point of a card's painting (image pixels) in the world.
func _card_point(card: Dictionary, e: Dictionary, px: Vector2) -> Vector3:
	var m_px: float = float(e.scale) * card.size / ppu
	var el := deg_to_rad(elevation)
	var right := Vector3(1, 0, -1).normalized()
	var to_cam := Vector3(cos(el) * sin(PI / 4), sin(el), cos(el) * cos(PI / 4))
	return card.foot + right * (px.x - float(e.ax)) * m_px + Vector3.UP * (float(e.ay) - px.y) * m_px / cos(el) + to_cam * (CARD_PULL + 0.3)


## One painted cut-out standing at grid point `at`: its upright part (above the
## foot point ay) turned to the camera and stretched by 1 / cos(elevation) so it
## keeps its painted shape on screen; its painted ground shadow (below ay) laid
## on the ground through the battle's iso projection (64 px across and 32 px
## down per tile) and draped over the relief.
func _card(parent: Node3D, e: Dictionary, at: Vector2, size: float, kind: String, key: String, look := {}) -> Dictionary:
	var tex: Texture2D = load(e.file)
	if tex == null:
		return {}
	var region := Rect2(0, 0, float(e.get("w", tex.get_width())), float(e.get("h", tex.get_height())))
	if e.has("region"):
		var r: Array = e.region
		region = Rect2(r[0], r[1], r[2], r[3])
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var ax := float(e.ax) + (region.position.x if e.has("region") else 0.0)
	var ay := float(e.ay) + (region.position.y if e.has("region") else 0.0)
	var spx: float = float(e.scale) * size
	var m_px := spx / ppu
	var el := deg_to_rad(elevation)
	var right := Vector3(1, 0, -1).normalized()
	var to_cam := Vector3(cos(el) * sin(PI / 4), sin(el), cos(el) * cos(PI / 4))
	var foot := on_ground(at)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	# Upright: 2 x 6 cells (rows bend in the wind). A standing card (the bridge,
	# whose piers go down into the river below its foot) is upright down to its
	# bottom edge, pulled toward the camera until that edge is clear of the ground.
	var stand: bool = look.get("stand", false)
	var cu := 2
	var cv := 6
	var bottom := region.position.y + region.size.y if stand else ay
	var top_m := (ay - region.position.y) * m_px / cos(el)
	var pull := CARD_PULL + ((bottom - ay) * m_px / (cos(el) * sin(el)) if stand else 0.0)
	for j in cv + 1:
		var v := region.position.y + (bottom - region.position.y) * float(j) / cv
		for i in cu + 1:
			var u := region.position.x + region.size.x * float(i) / cu
			var p := right * (u - ax) * m_px + Vector3.UP * (ay - v) * m_px / cos(el)
			verts.append(p + to_cam * pull)
			uvs.append(Vector2(u / tw, v / th))
			cols.append(Color(1.0, clampf((ay - v) * m_px / cos(el) / maxf(top_m, 0.01), 0.0, 1.0), 0, 1))
	for j in cv:
		for i in cu:
			var a := j * (cu + 1) + i
			idx.append_array([a, a + 1, a + cu + 2, a, a + cu + 2, a + cu + 1])
	# The painted shadow below the foot point, draped: 8 x 4 cells (unless the
	# sun casts the shadows).
	var below := region.position.y + region.size.y - ay
	if below > 2.0 and not stand and not sun_shadows:
		var base := verts.size()
		var su := 8
		var sv := 4
		for j in sv + 1:
			var v := ay + below * float(j) / sv
			for i in su + 1:
				var u := region.position.x + region.size.x * float(i) / su
				var dx := (u - ax) * spx
				var dy := (v - ay) * spx
				var g := at + Vector2((dx / 64.0 + dy / 32.0) * 0.5, (dy / 32.0 - dx / 64.0) * 0.5)
				var w := on_ground(g) + Vector3(0, 0.035, 0)
				verts.append(w - foot)
				uvs.append(Vector2(u / tw, v / th))
				cols.append(Color(0, 0, 0, 1))
		for j in sv:
			for i in su:
				var a := base + j * (su + 1) + i
				idx.append_array([a, a + 1, a + su + 2, a, a + su + 2, a + su + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = foot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _card_material(e.file, kind, look)
	parent.add_child(mi)
	if sun_shadows and not stand:
		_caster(mi, tex, region, Vector2(ax, ay), m_px, look)
	var card := {"node": mi, "grid": at, "kind": kind, "key": key, "foot": foot, "size": size}
	cards.append(card)
	return card


## A card's shadow caster (sun_shadows): its upright part again, square to the
## sun's way and as tall as the card stands, swaying with it; drawn into the
## sun's shadow map only, merged with its picture's others (`_build_casters`). A piece's (a house, a mill,
## a ruin) stands over its footprint: as wide as the footprint across the
## sun's way, a quarter of the footprint down the sun's way from its middle,
## and only as tall as the building is (its painted base, the footprint's
## depth on screen, taken off the bottom, the rest stretched to the top).
func _caster(card: MeshInstance3D, tex: Texture2D, region: Rect2, anchor: Vector2, m_px: float, look: Dictionary) -> void:
	var el := deg_to_rad(elevation)
	var side := Vector3.UP.cross(sun_way).normalized()
	var top_px := anchor.y - region.position.y
	var origin := Vector3.ZERO
	var across := m_px
	var base_px := 0.0
	var pc: Dictionary = look.get("piece", {})
	if not pc.is_empty():
		var fp: Vector2i = Fields.PIECE[pc.key].fp
		var c := on_ground(pc.c)
		var reach := absf(sun_way.x) * fp.x + absf(sun_way.z) * fp.y
		origin = c + sun_way * reach * 0.25 * tile_m - card.position
		origin.y = c.y - card.position.y
		across = (absf(side.x) * fp.x + absf(side.z) * fp.y) * tile_m / region.size.x
		anchor.x = region.position.x + region.size.x * 0.5
		# The footprint's depth on screen in the painting's pixels (a tile is
		# 64 px deep at zoom 1), from the foot to the middle of the base.
		base_px = (fp.x + fp.y) * 16.0 / (m_px * ppu)
	var tall := maxf(top_px - base_px, 1.0) * m_px / cos(el)
	# UV2: the card's phase in the wind (from its foot, as bf_card.gdshader
	# takes it) and how far the point sways (its height up the card's node,
	# times its share of the height squared).
	var ph := card.position.x * 0.37 + card.position.z * 0.53
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	var cu := 2
	var cv := 6
	for j in cv + 1:
		var v := region.position.y + top_px * float(j) / cv
		var up := maxf(anchor.y - v - base_px, 0.0) * m_px / cos(el)
		var h := up / tall
		for i in cu + 1:
			var u := region.position.x + region.size.x * float(i) / cu
			verts.append(card.position + origin + side * (u - anchor.x) * across + Vector3.UP * up)
			uvs.append(Vector2(u / tex.get_width(), v / tex.get_height()))
			uv2s.append(Vector2(ph, h * h * (origin.y + up)))
	for j in cv:
		for i in cu:
			var a := j * (cu + 1) + i
			idx.append_array([a, a + 1, a + cu + 2, a, a + cu + 2, a + cu + 1])
	var sway: float = card.material_override.get_shader_parameter("sway")
	var key := "%s|%.3f" % [tex.resource_path, sway]
	if not _casters.has(key):
		var m := ShaderMaterial.new()
		m.shader = CasterShader
		m.set_shader_parameter("tex", tex)
		m.set_shader_parameter("sway", sway)
		_casters[key] = {"mat": m, "parts": []}
	_casters[key].parts.append([verts, uvs, uv2s, idx])


## The casters merged into one shadow-only mesh per picture and sway (in the
## field's space, as the cards' holders are): a draw per picture into each of
## the sun's shadow splits, not one per card.
func _build_casters() -> void:
	var holder := Node3D.new()
	holder.name = "Casters"
	add_child(holder)
	for key in _casters:
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var uv2s := PackedVector2Array()
		var idx := PackedInt32Array()
		for part in _casters[key].parts:
			var base := verts.size()
			verts.append_array(part[0])
			uvs.append_array(part[1])
			uv2s.append_array(part[2])
			for i in part[3]:
				idx.append(base + i)
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_TEX_UV2] = uv2s
		arr[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.name = "Caster"
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		mi.material_override = _casters[key].mat
		holder.add_child(mi)
	_casters.clear()


## One material per picture and look, shared by its cards: the fog and the
## wind come from each card's own position in the shader.
func _card_material(file: String, kind: String, look: Dictionary) -> ShaderMaterial:
	var autumn: float = look.get("autumn", 0.0)
	var snow: float = look.get("snow", 0.0)
	var glow: bool = look.get("glow", false)
	var key := "%s|%.2f|%.2f|%s" % [file, autumn, snow, glow]
	if _card_mats.has(key):
		return _card_mats[key]
	var m := ShaderMaterial.new()
	m.shader = CardShader
	m.set_shader_parameter("tex", load(file))
	var sway := 0.0
	if kind.begins_with("tree"):
		sway = 0.012
	elif kind in ["bush", "fern"] or look.get("sway", false) or file.contains("reeds") or file.contains("harvest_0") or file.contains("harvest_1"):
		sway = 0.035
	m.set_shader_parameter("sway", sway)
	m.set_shader_parameter("map_size", Vector2(W, H))
	m.set_shader_parameter("tile_m", tile_m)
	m.set_shader_parameter("level_m", level_m)
	m.set_shader_parameter("fog_grain", load(FOG_GRAIN))
	m.set_shader_parameter("autumn", autumn)
	m.set_shader_parameter("snow_cap", snow)
	m.set_shader_parameter("h_tex", _h_tex)
	m.set_shader_parameter("h_origin", _h_origin)
	m.set_shader_parameter("h_sub", float(SUB))
	for k in _shared:
		m.set_shader_parameter(k, _shared[k])
	if glow:
		_glow_mats.append(m)
	_card_mats[key] = m
	return m


## A shader input every ground, water and card material takes (fog, night).
func set_shared(param: String, value: Variant) -> void:
	_shared[param] = value
	mat.set_shader_parameter(param, value)
	if _shade_mat:
		_shade_mat.set_shader_parameter(param, value)
	for m in _card_mats.values():
		m.set_shader_parameter(param, value)
	if _blades:
		_blades.material_override.set_shader_parameter(param, value)
	if water:
		water.material_override.set_shader_parameter(param, value)


## Lit windows at night in the lived-in houses.
func set_glow(on: bool) -> void:
	for m in _glow_mats:
		m.set_shader_parameter("glow", 1.0 if on else 0.0)


## The battle's grass strokes in the season's colours: summer's green to
## straw, autumn's straw and russet, spring's fresh green; in winter a few dry
## stalks through the snow. One mesh.
func _build_blades() -> void:
	var rng := Rng.new(data.seed + 451)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var el := deg_to_rad(elevation)
	var right := Vector3(1, 0, -1).normalized()
	var up_m := 1.0 / ppu / cos(el)
	var look: Dictionary = {
		"summer": {"base": Color(0.28, 0.34, 0.16), "tip0": Color(0.47, 0.53, 0.24), "tip1": Color(0.77, 0.66, 0.32), "keep": 0.65, "n": 7, "tall": 1.0},
		"autumn": {"base": Color(0.36, 0.3, 0.14), "tip0": Color(0.74, 0.56, 0.26), "tip1": Color(0.7, 0.4, 0.17), "keep": 0.7, "n": 7, "tall": 1.0},
		"spring": {"base": Color(0.24, 0.36, 0.13), "tip0": Color(0.46, 0.62, 0.22), "tip1": Color(0.64, 0.72, 0.3), "keep": 0.7, "n": 8, "tall": 1.05},
		"winter": {"base": Color(0.4, 0.33, 0.22), "tip0": Color(0.6, 0.52, 0.36), "tip1": Color(0.7, 0.62, 0.46), "keep": 0.3, "n": 2, "tall": 0.75},
	}[season]
	for t in map.tiles + _outer:
		if t.x < -3 or t.y < -3 or t.x > W + 2 or t.y > H + 2:
			continue
		if t.terrain not in ["grass", "brush", "forest"] or t.get("covered", false):
			continue
		if not rng.chance(look.keep):
			continue
		var n: int = look.n * 2 if t.terrain == "brush" else (maxi(1, look.n / 2) if t.terrain == "forest" else look.n)
		for i in n:
			var p := on_ground(Vector2(t.x + rng.frange(-0.48, 0.48), t.y + rng.frange(-0.48, 0.48)))
			var tip: Color = look.tip0.lerp(look.tip1, rng.frange(0.0, 1.0))
			var base: Color = look.base
			for blade in 3:
				var offset := rng.frange(-4.0, 4.0) / ppu
				var height: float = rng.frange(5.0, 13.0) * up_m * look.tall
				var lean := rng.frange(-4.0, 1.0) / ppu
				verts.append_array([p + right * (offset - 1.3 / ppu), p + right * (offset + 1.3 / ppu),
					p + right * (offset + lean) + Vector3.UP * height])
				cols.append_array([base, base, tip])
				uvs.append_array([Vector2(0, 0), Vector2(0, 0), Vector2(0, 1)])
	if verts.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_blades = MeshInstance3D.new()
	_blades.name = "GrassStrokes"
	_blades.mesh = mesh
	_blades.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = CardShader
	m.set_shader_parameter("blades", true)
	m.set_shader_parameter("sway", 0.08)
	m.set_shader_parameter("map_size", Vector2(W, H))
	m.set_shader_parameter("tile_m", tile_m)
	m.set_shader_parameter("level_m", level_m)
	m.set_shader_parameter("fog_grain", load(FOG_GRAIN))
	for k in _shared:
		m.set_shader_parameter(k, _shared[k])
	_blades.material_override = m
	add_child(_blades)
