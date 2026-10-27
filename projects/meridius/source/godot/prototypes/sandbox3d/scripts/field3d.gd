## The 3D sandbox's field: a training ground on rolling hills, built from the
## battle map's own pieces so 3D units can be judged on ground that looks like
## the game's battlefield.
##   - the map: tiles in the rules' format ({x, y, h, surface_h, terrain, prop}),
##     so scripts/rules/visibility.gd and grid.gd read it unchanged (fog of war);
##   - the ground: one mesh over the relief surface (scripts/render/relief.gd,
##     the Catmull-Rom surface the battle's relief terrain draws), painted by
##     shaders/terrain3d.gdshader with the battle map's terrain textures;
##   - the woodland: the painted woodland, rock and stump cut-outs of
##     assets/sprites.json as upright cards turned to the camera, each with its
##     painted shadow draped over the ground (shaders/painted_card.gdshader).
## World axes: x = grid x, z = grid y; a tile is `tile_m` metres, a level of
## height `level_m` (26 px on screen at zoom 1, as in the battle).
extends Node3D

const Relief = preload("res://scripts/render/relief.gd")
const Fields = preload("res://scripts/rules/terrain_test_fields.gd")
const Rng = preload("res://scripts/core/rng.gd")
const ReliefShader = preload("res://assets/shaders/terrain_relief.gdshader")
const TerrainShader = preload("res://prototypes/sandbox3d/shaders/terrain3d.gdshader")
const CardShader = preload("res://prototypes/sandbox3d/shaders/painted_card.gdshader")
const FOG_GRAIN := "res://assets/terrain/fog_grain.png"

const W := 28
const H := 28
const BORDER := 12
## Ground mesh cells per tile side.
const SUB := 4
## The ground pictures: the field and NEAR_PAD tiles round it at BAKE_NEAR
## pixels square (about 90 a tile, the battle's own detail at zoom 1), the
## whole padded grid at BAKE_FAR.
const NEAR_PAD := 8
const BAKE_NEAR := 4096
const BAKE_FAR := 2048
## Screen pixels per level of height at zoom 1 (the relief shader's LH).
const LEVEL_PX := 26.0
const SEED := 4711
## Terrain categories as the battle's relief shader numbers them (7: forest floor
## outside the field).
const CATS := {"grass": 0, "dirt": 1, "road": 1, "brush": 2, "forest": 3, "stone": 4,
	"water": 5, "shallows": 6, "mud": 8}
const FLOOR_CAT := 7
## Where the squads start and the straw dummies stand.
const YARD := Vector2(14.0, 16.5)
## A painted card's upright part is drawn this far toward the camera (metres):
## in the orthographic view that moves nothing on screen, it only keeps a slope
## in front of the trunk from cutting off its foot.
const CARD_PULL := 0.7
## The painted shadows' alpha correction (painted_card.gdshader shadow_gamma).
const SHADOW_GAMMA := 1.0
## A tree crown's opacity while a figure stands behind it.
const CROWN_FADE := 0.42

var tile_m := 2.72
var level_m := 0.9
var elevation := 30.0
var ppu := 33.0
var map: Dictionary
var relief
var ground: MeshInstance3D
var mat: ShaderMaterial
## Every card: {"node", "mat", "grid" (Vector2 foot), "kind", "radius" (m), "top" (m above the foot)}.
var cards: Array = []
var _card_mats := {}
var _shared := {}
var _blades: MeshInstance3D
var _sprites: Dictionary
## Tiles a figure cannot stand on (trees, rocks, deep water, steep banks).
var _blocked := {}
var _outer: Array = []
var _mark_img: Image
var _mark_tex: ImageTexture


func build(tile: float, level: float, elev: float, px_per_m: float) -> void:
	tile_m = tile
	level_m = level
	elevation = elev
	ppu = px_per_m
	_sprites = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites.json"))
	_make_map()
	relief = Relief.new(W, H, BORDER, map.tiles + _outer, SEED)
	_build_ground()
	_build_woodland()
	_build_blades()


# --- The map --------------------------------------------------------------------

func _height(x: float, y: float) -> float:
	var h := 0.55
	h += 3.4 * Fields.hill(x, y, 21.5, 5.5, 6.5, 4.6)       # the north-east hill
	h += 2.5 * Fields.hill(x, y, 3.0, 11.0, 4.2, 8.5)       # the western ridge
	h += 1.5 * Fields.hill(x, y, 23.5, 22.5, 4.5, 3.4)      # the south-east knoll
	h += Fields.bluff(x, y, 11.0, 3.5, 4.4, 3.0, 2.1)       # the bluff, its banks toward the camera
	# Beyond the field: high wooded ground behind it, lower land toward the camera.
	h += 2.6 * Fields.hill(x, y, -9.0, 6.0, 8.0, 14.0) + 2.2 * Fields.hill(x, y, 12.0, -10.0, 16.0, 7.0)
	h += 1.2 * Fields.hill(x, y, 34.0, 30.0, 8.0, 8.0)
	# The training yard is level ground.
	var yard := clampf(Fields.hill(x, y, YARD.x, YARD.y, 5.2, 4.2) * 1.7, 0.0, 1.0)
	h = lerpf(h, 0.55, yard)
	# A pond in the south-west hollow.
	h -= 0.6 * Fields.hill(x, y, 6.5, 21.5, 2.6, 2.2)
	return maxf(h, 0.0)


func _road(x: float) -> float:
	return 22.5 - x * 0.52 + 1.5 * sin(x * 0.33 + 0.4)


func _pond(x: float, y: float) -> float:
	return Vector2((x - 6.5) / 1.25, (y - 21.5) / 1.0).length()


func _woods(x: float, y: float, n: float) -> bool:
	if y < 2.4 + 1.3 * sin(x * 0.45 + 0.7) + (n - 0.5) * 1.5:
		return true
	if x < 1.6 + 0.9 * sin(y * 0.5) + (n - 0.5) * 1.2 and y < 19.0:
		return true
	if Fields.hill(x, y, 25.5, 15.0, 2.4, 3.2) > 0.42:
		return true
	if Fields.hill(x, y, 2.5, 25.5, 3.4, 2.6) > 0.5:
		return true
	return Fields.hill(x, y, 18.5, 26.5, 2.6, 1.8) > 0.55


func _make_map() -> void:
	var tiles: Array = []
	_outer.clear()
	for y in range(-BORDER, H + BORDER):
		for x in range(-BORDER, W + BORDER):
			var inside := x >= 0 and y >= 0 and x < W and y < H
			var e := _height(x, y)
			var n := Rng.hash2(x, y, SEED)
			var terrain := "grass"
			var prop := ""
			var woods := _woods(x, y, n)
			if not inside:
				# The forest ring: dense near the field, thinning to floor beyond.
				var out := maxf(maxf(-x, x - W + 1), maxf(-y, y - H + 1))
				woods = woods or n < 0.62 - out * 0.02
			if woods:
				terrain = "forest"
				if n < 0.44:
					prop = "tree_pine" if n < 0.21 else "tree_oak"
				elif n < 0.6:
					prop = "bush"
				elif n < 0.635:
					prop = "stump" if n < 0.62 else "log"
			elif n > 0.88 and n < 0.94:
				terrain = "brush"
			elif n > 0.992:
				prop = "tree_oak"
			var yard := Fields.hill(x, y, YARD.x, YARD.y, 5.2, 4.2)
			if yard > 0.72 and Rng.hash2(x, y, SEED + 3) < 0.55:
				terrain = "dirt"
			if yard > 0.3:
				prop = "" if not woods else prop
			if absf(y - _road(x)) < 0.8:
				terrain = "dirt"
				prop = ""
			var pd := _pond(x, y)
			if pd < 1.25:
				terrain = "water"
				prop = ""
			elif pd < 1.9:
				terrain = "shallows"
				prop = ""
			elif pd < 2.5:
				terrain = "mud"
				prop = ""
			if terrain == "grass" and prop == "":
				if e > 1.3 and n > 0.955:
					prop = "rock_small"
				elif e > 2.0 and n < 0.03:
					prop = "rock_large"
			if yard > 0.3 and prop.begins_with("rock"):
				prop = ""
			var t := {"x": x, "y": y, "h": roundi(e), "surface_h": e, "terrain": terrain,
				"v": floori(n * 10000)}
			if prop != "":
				t["prop"] = prop
			if inside:
				tiles.append(t)
			else:
				t["outer"] = true
				_outer.append(t)
	map = {"id": "sandbox3d", "name": "Proving grounds", "w": W, "h": H, "seed": SEED,
		"border": BORDER, "tiles": tiles}
	_blocked.clear()
	for t in tiles:
		if t.terrain == "water" or (String(t.get("prop", "")) not in ["", "bush"]):
			_blocked[Vector2i(t.x, t.y)] = true


func tile(x: int, y: int) -> Variant:
	if x < 0 or y < 0 or x >= W or y >= H:
		return null
	return map.tiles[y * W + x]


# --- Ground queries -------------------------------------------------------------

## Ground height (metres) under a world point.
func ground_y(wx: float, wz: float) -> float:
	return relief.surface(wx / tile_m, wz / tile_m) * level_m


## The ground's normal under a world point.
func ground_normal(wx: float, wz: float) -> Vector3:
	var e := 0.25
	var hx := ground_y(wx + e, wz) - ground_y(wx - e, wz)
	var hz := ground_y(wx, wz + e) - ground_y(wx, wz - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


func on_ground(grid: Vector2) -> Vector3:
	var p := Vector3(grid.x * tile_m, 0, grid.y * tile_m)
	p.y = ground_y(p.x, p.z)
	return p


func tile_of(world: Vector3) -> Vector2i:
	return Vector2i(roundi(world.x / tile_m), roundi(world.z / tile_m))


func in_field(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < W and t.y < H


func walkable(t: Vector2i) -> bool:
	return in_field(t) and not _blocked.has(t)


## The ground point under a screen ray, marched along the ray over the relief.
func pick(origin: Vector3, dir: Vector3) -> Variant:
	if absf(dir.y) < 1e-4:
		return null
	# Start where the ray is above the highest ground, step until it is below.
	var top: float = (float(relief.max_h) + 1.0) * level_m
	var t := (top - origin.y) / dir.y
	var step := 0.25
	var prev := origin + dir * t
	for i in 1200:
		var p := origin + dir * (t + step * i)
		if p.y <= ground_y(p.x, p.z):
			# Refine between prev and p.
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


## A walking route from a world point to a tile, round trees, rocks and water
## and over no bank steeper than a figure climbs: A* over the tiles (eight ways,
## no corner cutting), then pulled straight wherever the ground between allows.
func path_to(from: Vector3, goal: Vector2i) -> Array:
	var start := tile_of(from)
	if not in_field(goal):
		return []
	if not walkable(goal):
		goal = _nearest_walkable(goal)
	if start == goal:
		return [on_ground(Vector2(goal))]
	var open := {start: 0.0}
	var came := {}
	var cost := {start: 0.0}
	var guard := 0
	while not open.is_empty() and guard < 6000:
		guard += 1
		var cur: Vector2i = open.keys()[0]
		var best := INF
		for k in open:
			var f: float = open[k] + Vector2(k - goal).length()
			if f < best:
				best = f
				cur = k
		if cur == goal:
			break
		open.erase(cur)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var nb: Vector2i = cur + d
			if not walkable(nb) or not _can_step(cur, nb):
				continue
			if d.x != 0 and d.y != 0 and (not walkable(cur + Vector2i(d.x, 0)) or not walkable(cur + Vector2i(0, d.y))):
				continue
			var t: Dictionary = tile(nb.x, nb.y)
			var c: float = cost[cur] + Vector2(d).length() * (1.6 if t.terrain in ["forest", "brush", "mud", "shallows"] else 1.0)
			if not cost.has(nb) or c < cost[nb]:
				cost[nb] = c
				came[nb] = cur
				open[nb] = c
	if not came.has(goal):
		return []
	var tiles := [goal]
	while tiles[0] != start:
		tiles.push_front(came[tiles[0]])
	# String pulling: skip a tile while the straight line to the next still clears.
	var pts := [Vector2(start)]
	var i := 0
	while i < tiles.size() - 1:
		var j := tiles.size() - 1
		while j > i + 1 and not _clear(Vector2(tiles[i]), Vector2(tiles[j])):
			j -= 1
		pts.append(Vector2(tiles[j]))
		i = j
	var out := []
	for k in range(1, pts.size()):
		out.append(on_ground(pts[k]))
	return out


func _nearest_walkable(t: Vector2i) -> Vector2i:
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := t + Vector2i(dx, dy)
				if walkable(c):
					return c
	return t


func _can_step(a: Vector2i, b: Vector2i) -> bool:
	return absf(float(tile(a.x, a.y).surface_h) - float(tile(b.x, b.y).surface_h)) < 1.25


## The straight line between two tile centres crosses only walkable ground.
func _clear(a: Vector2, b: Vector2) -> bool:
	var n := ceili(a.distance_to(b) * 4.0)
	var prev := Vector2i(roundi(a.x), roundi(a.y))
	for k in range(1, n + 1):
		var p := a.lerp(b, float(k) / n)
		# Keep a figure's width off the obstacles: test both sides of the line.
		var side := (b - a).normalized().orthogonal() * 0.32
		for q in [p, p + side, p - side]:
			var c := Vector2i(roundi(q.x), roundi(q.y))
			if not walkable(c) or (c != prev and not _can_step(prev, c)):
				return false
		prev = Vector2i(roundi(p.x), roundi(p.y))
	return true


# --- The ground ----------------------------------------------------------------------

## The ground is painted once, by the battle's own relief shader
## (assets/shaders/terrain_relief.gdshader), into two top-down pictures of the
## grid: the field and its near woods sharp, the whole padded grid softer. The
## 3D ground then only looks them up, so it costs no more to draw than a
## texture, and it is the battle's ground to the brush stroke.
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
	mat.shader = TerrainShader
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
	add_child(ground)


## One picture of the ground over `rect` (grid units), `size` pixels square,
## drawn once. The relief shader lifts each vertex by the surface (its iso
## view); the quad's corners are lowered by as much beforehand, so the picture
## comes out top-down and the mapping stays exact across the quad.
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
	# Shade under the canopy: full under trees, lighter beside bushes and rocks.
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
		elif prop == "bush" or prop.begins_with("rock"):
			occ.set_pixel(gx, gy, Color(0.55, 0.55, 0.55))
	rm.set_shader_parameter("cat_tex", ImageTexture.create_from_image(Image.create_from_data(gw, gh, false, Image.FORMAT_R8, cats)))
	rm.set_shader_parameter("occ_tex", ImageTexture.create_from_image(occ))
	rm.set_shader_parameter("gw", gw)
	rm.set_shader_parameter("gh", gh)
	rm.set_shader_parameter("border", BORDER)
	rm.set_shader_parameter("phase", Vector4(relief.phase[0], relief.phase[1], relief.phase[2], relief.phase[3]))
	rm.set_shader_parameter("seed", SEED)
	rm.set_shader_parameter("camp", false)
	rm.set_shader_parameter("hmax", relief.max_h)
	for pair in [["grass", "grass"], ["dry", "dry_grass"], ["dirt", "dirt"], ["forest", "forest_floor"], ["rock", "rock"], ["mud", "mud"], ["stone", "flagstone"]]:
		rm.set_shader_parameter("tex_" + pair[0], load("res://assets/terrain/%s.webp" % pair[1]))
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
	return vp


## Highlight tiles on the ground (a route, a destination): 0 none, 1 route, 2 goal.
func mark(tiles: Dictionary) -> void:
	_mark_img.fill(Color.BLACK)
	for t in tiles:
		if in_field(t):
			_mark_img.set_pixel(t.x, t.y, Color(tiles[t] / 2.0, 0, 0))
	_mark_tex.update(_mark_img)


# --- The woodland -------------------------------------------------------------------

func _build_woodland() -> void:
	var holder := Node3D.new()
	holder.name = "Woodland"
	add_child(holder)
	var rng := Rng.new(SEED + 17)
	var near := func(t: Dictionary) -> bool:
		return t.x > -7 and t.y > -7 and t.x < W + 7 and t.y < H + 7
	for t in map.tiles + _outer:
		if not near.call(t):
			continue
		var prop := String(t.get("prop", ""))
		var at := Vector2(t.x, t.y)
		if prop != "":
			var key := "bush" if prop == "bush" else prop
			var variants: Array = _sprites.get(key, [])
			if variants.is_empty():
				continue
			var e: Dictionary = variants[int(Rng.hash2(t.x, t.y, SEED + 5) * variants.size()) % variants.size()]
			var j := Vector2(Rng.hash2(t.x, t.y, SEED + 7) - 0.5, Rng.hash2(t.x, t.y, SEED + 9) - 0.5)
			var spread := 0.32 if prop.begins_with("tree") else 0.2
			var size := 1.0
			if prop.begins_with("tree"):
				size = lerpf(0.9, 1.12, Rng.hash2(t.x, t.y, SEED + 11))
			_card(holder, e, at + j * spread * 2.0, size, prop)
		# Ferns and low shrubs on the woodland floor and in the thickets: decoration only.
		if t.terrain in ["forest", "brush"] and (prop == "" or prop == "bush" or rng.chance(0.4)):
			var ferns: Array = _sprites.get("fern", [])
			var count := 2 if t.terrain == "brush" else 1
			for i in count:
				if ferns.is_empty() or not rng.chance(0.7):
					continue
				var e: Dictionary = rng.pick(ferns)
				var off := Vector2(rng.frange(-0.45, 0.45), rng.frange(-0.45, 0.45))
				if prop.begins_with("tree") and off.length() < 0.3:
					off = off.normalized() * 0.38 if off.length() > 0.01 else Vector2(0.38, 0.1)
				_card(holder, e, at + off, rng.frange(0.75, 1.15), "fern")


## One painted cut-out standing at grid point `at`: its upright part (above the
## foot point ay) turned to the camera and stretched by 1 / cos(elevation) so it
## keeps its painted shape on screen; its painted ground shadow (below ay) laid
## on the ground through the battle's iso projection (64 px across and 32 px
## down per tile) and draped over the relief.
func _card(parent: Node3D, e: Dictionary, at: Vector2, size: float, kind: String) -> void:
	var tex: Texture2D = load(e.file)
	if tex == null:
		return
	var region := Rect2(0, 0, float(e.get("w", tex.get_width())), float(e.get("h", tex.get_height())))
	if e.has("region"):
		var r: Array = e.region
		region = Rect2(r[0], r[1], r[2], r[3])
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	# The foot point, in image pixels (an atlas entry gives it inside its region).
	var ax := float(e.ax) + (region.position.x if e.has("region") else 0.0)
	var ay := float(e.ay) + (region.position.y if e.has("region") else 0.0)
	var spx: float = float(e.scale) * size          # world px (zoom 1) per image px
	var m_px := spx / ppu                              # metres on screen per image px
	var el := deg_to_rad(elevation)
	var right := Vector3(1, 0, -1).normalized()
	var to_cam := Vector3(cos(el) * sin(PI / 4), sin(el), cos(el) * cos(PI / 4))
	var foot := on_ground(at)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	# Upright: 2 x 6 cells (rows bend in the wind).
	var cu := 2
	var cv := 6
	var top_m := (ay - region.position.y) * m_px / cos(el)
	for j in cv + 1:
		var v := region.position.y + (ay - region.position.y) * float(j) / cv
		for i in cu + 1:
			var u := region.position.x + region.size.x * float(i) / cu
			var p := right * (u - ax) * m_px + Vector3.UP * (ay - v) * m_px / cos(el)
			verts.append(p + to_cam * CARD_PULL)
			uvs.append(Vector2(u / tw, v / th))
			cols.append(Color(1.0, clampf((ay - v) * m_px / cos(el) / maxf(top_m, 0.01), 0.0, 1.0), 0, 1))
	for j in cv:
		for i in cu:
			var a := j * (cu + 1) + i
			idx.append_array([a, a + 1, a + cu + 2, a, a + cu + 2, a + cu + 1])
	# The painted shadow below the foot point, draped: 8 x 4 cells.
	var below := region.position.y + region.size.y - ay
	if below > 2.0:
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
	mi.material_override = _card_material(e.file, kind, 1.0)
	parent.add_child(mi)
	cards.append({"node": mi, "file": e.file, "grid": at, "kind": kind, "foot": foot,
		"half_w": region.size.x * 0.5 * m_px, "top": top_m * cos(el), "faded": false})


## One material per picture and fade, shared by its cards: the fog and the
## wind come from each card's own position in the shader.
func _card_material(file: String, kind: String, fade: float) -> ShaderMaterial:
	var key := "%s|%.2f" % [file, fade]
	if _card_mats.has(key):
		return _card_mats[key]
	var m := ShaderMaterial.new()
	m.shader = CardShader
	m.set_shader_parameter("tex", load(file))
	m.set_shader_parameter("sway", 0.012 if kind.begins_with("tree") else (0.035 if kind in ["bush", "fern"] else 0.0))
	m.set_shader_parameter("fade", fade)
	m.set_shader_parameter("map_size", Vector2(W, H))
	m.set_shader_parameter("tile_m", tile_m)
	m.set_shader_parameter("level_m", level_m)
	m.set_shader_parameter("fog_grain", load(FOG_GRAIN))
	m.set_shader_parameter("shadow_gamma", SHADOW_GAMMA)
	for k in _shared:
		m.set_shader_parameter(k, _shared[k])
	_card_mats[key] = m
	return m


## A shader input every ground and card material takes (fog, night).
func set_shared(param: String, value: Variant) -> void:
	_shared[param] = value
	mat.set_shader_parameter(param, value)
	for m in _card_mats.values():
		m.set_shader_parameter(param, value)
	if _blades:
		_blades.material_override.set_shader_parameter(param, value)


## Fades a tree's crown while a figure stands behind it, as the battle does.
func set_card_faded(card: Dictionary, on: bool) -> void:
	if card.faded == on:
		return
	card.faded = on
	card.node.material_override = _card_material(card.file, card.kind, CROWN_FADE if on else 1.0)


## The battle's grass strokes (relief_terrain.gd _paint_meadow): sparse upright
## blades, green to straw at the tip, that give the meadow a soft edge. One mesh.
func _build_blades() -> void:
	var rng := Rng.new(SEED + 451)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var el := deg_to_rad(elevation)
	var right := Vector3(1, 0, -1).normalized()
	var up_m := 1.0 / ppu / cos(el)
	for t in map.tiles + _outer:
		if t.x < -3 or t.y < -3 or t.x > W + 2 or t.y > H + 2:
			continue
		if t.terrain not in ["grass", "brush", "forest"]:
			continue
		if not rng.chance(0.65):
			continue
		var n := 12 if t.terrain == "brush" else (3 if t.terrain == "forest" else 7)
		for i in n:
			var p := on_ground(Vector2(t.x + rng.frange(-0.48, 0.48), t.y + rng.frange(-0.48, 0.48)))
			var tip := Color(0.47, 0.53, 0.24).lerp(Color(0.77, 0.66, 0.32), rng.frange(0.0, 1.0))
			var base := Color(0.28, 0.34, 0.16, 1.0)
			for blade in 3:
				var offset := rng.frange(-4.0, 4.0) / ppu
				var height := rng.frange(5.0, 13.0) * up_m
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
