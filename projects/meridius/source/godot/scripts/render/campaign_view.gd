## The expedition map: painted land with roads and a river, forests, the
## nodes as landmarks, the routes, fog of war, the host coming down from the
## far corner, the company's banner and its march, and labels.
## Port of src/render/campaignScene.ts (class CampaignScene).
##
## Hosting (UI agent):
##   var view = preload("res://scenes/campaign/campaign_view.tscn").instantiate()
##   view.setup(App.game.expedition, func(): return App.game.get("expedition"))
##   view.node_clicked.connect(App.click_node)   # onNodeClick
##   view.changed.connect(...)                   # subscribe/notify (ui.version)
##   view.focus_current()                        # "Find army"
##   view.marching                               # a march is being animated
## Public state mirrors the class: cam, atmo, fx, terrain, props, roads, fog,
## ui {hover?, marching, version}. Plays Sfx "march" when a march starts.
extends Node2D

const Iso = preload("res://scripts/render/iso.gd")
const Rng = preload("res://scripts/core/rng.gd")
const JS = preload("res://scripts/core/js.gd")
const Camera = preload("res://scripts/render/camera.gd")
const Terrain = preload("res://scripts/render/terrain.gd")
const Atmosphere = preload("res://scripts/render/atmosphere.gd")
const Fx = preload("res://scripts/render/fx.gd")
const Assets = preload("res://scripts/render/assets.gd")
const WD = preload("res://scripts/render/world_draw.gd")
const WorldCanvas = preload("res://scripts/render/world_canvas.gd")
const ClipShader = preload("res://assets/shaders/terrain_clip.gdshader")
const GlowShader = preload("res://assets/shaders/terrain_glow.gdshader")
const FogShader = preload("res://assets/shaders/atmo_fog.gdshader")

const SIZE := 38
const TW := Iso.TW
const TH := Iso.TH
## The land the host's scorched wash, glows and warbands are clipped to.
const LAND_E := 8

signal node_clicked(id: String)
signal changed

var get_ex: Callable = func() -> Variant: return null
var terrain: Node2D
var cam: RefCounted
var atmo: RefCounted
var fx: RefCounted = Fx.new()
var props: Array = []
## "a>b" -> [{x, y}] (Map in the original; insertion-ordered here too).
var roads := {}
var fog: Array = []
## CampaignUi: {hover?: String, marching: bool, version: int}
var ui := {"marching": false, "version": 0}
var time := 0.0
var marching: bool:
	get:
		return march != null

var shown_node := ""
var march: Variant = null # {path, t, dur}
var token := {"x": 0.0, "y": 0.0}
## The host's march across the map (see build_horde).
var horde: Variant = null
var horde_fx: RefCounted = Fx.new()
## First look at a new expedition: the camera starts on the host, holds, then sweeps back.
var intro: Variant = null
var _w := 1920.0
var _h := 1080.0
var _terrain_input: Dictionary
var _ready_done := false
var _world: Node2D
var _nodes: Dictionary = {}
var _items: Array = []
var _prop_items: Array = []
var _items_root: Node2D
## Static prop runs between the dynamic items, drawn once (see _layout_items).
var _seg_key := ""
var _dyn_nodes: Array = []
var _items_key := ""
var _fog_key := ""
var _fog_still := false
static var _puff: Texture2D
var _fog_buf := PackedFloat32Array()


# ---------------------------------------------------------------- world


## Everything the constructor derives from the expedition, in the original's
## Rng order: roads, river, tiles and forest props, the forest ring, the
## terrain input and the fog lattice.
static func world_for(ex: Dictionary) -> Dictionary:
	var rng := Rng.new(ex.seed)
	var by_id := {}
	for n in ex.nodes:
		by_id[n.id] = n
	var road_map := {}
	# Roads along every edge, gently curved.
	for e in ex.edges:
		var na: Dictionary = by_id[e[0]]
		var nb: Dictionary = by_id[e[1]]
		var mx: float = (na.tx + nb.tx) / 2.0 + rng.frange(-1.6, 1.6)
		var my: float = (na.ty + nb.ty) / 2.0 + rng.frange(-1.6, 1.6)
		var pts: Array = []
		for i in 17:
			var t := i / 16.0
			pts.append({
				"x": (1 - t) * (1 - t) * na.tx + 2 * (1 - t) * t * mx + t * t * nb.tx,
				"y": (1 - t) * (1 - t) * na.ty + 2 * (1 - t) * t * my + t * t * nb.ty,
			})
		road_map["%s>%s" % [e[0], e[1]]] = pts
	var road_pts: Array = []
	for k in road_map:
		road_pts.append_array(road_map[k])
	# Road points bucketed per tile (the predicate is the same as a scan of
	# all points: a point within r lies in a cell between floor(v - r) and
	# floor(v + r) on each axis).
	var G0 := -16
	var GN := SIZE + 32
	var cells: Array = []
	cells.resize(GN * GN)
	for p in road_pts:
		var cx := floori(p.x) - G0
		var cy := floori(p.y) - G0
		if cx < 0 or cy < 0 or cx >= GN or cy >= GN:
			continue
		var k := cy * GN + cx
		if cells[k] == null:
			cells[k] = []
		cells[k].append(p)
	var far_pts := PackedFloat64Array()
	for p in road_pts:
		var cx := floori(p.x) - G0
		var cy := floori(p.y) - G0
		if cx < 0 or cy < 0 or cx >= GN or cy >= GN:
			far_pts.append(p.x)
			far_pts.append(p.y)
	var near_road := func(x: float, y: float, r: float) -> bool:
		var r2 := r * r
		for by in range(maxi(0, floori(y - r) - G0), mini(GN - 1, floori(y + r) - G0) + 1):
			for bx in range(maxi(0, floori(x - r) - G0), mini(GN - 1, floori(x + r) - G0) + 1):
				var list: Variant = cells[by * GN + bx]
				if list == null:
					continue
				for q in list:
					# The original's test, in doubles: (p.x - x) ** 2 + (p.y - y) ** 2 < r * r.
					if (q.x - x) * (q.x - x) + (q.y - y) * (q.y - y) < r2:
						return true
		for i in range(0, far_pts.size(), 2):
			if (far_pts[i] - x) * (far_pts[i] - x) + (far_pts[i + 1] - y) * (far_pts[i + 1] - y) < r2:
				return true
		return false
	var near_node := func(x: float, y: float, r: float) -> bool:
		for n in ex.nodes:
			if (n.tx - x) * (n.tx - x) + (n.ty - y) * (n.ty - y) < r * r:
				return true
		return false

	var tiles: Array = []
	var props_out: Array = []
	# River crossing the line of march.
	var river := {}
	var rx := rng.rint(4, 8)
	for y in range(SIZE - 1, -1, -1):
		var cx := JS.rnd(rx + (SIZE - 1 - y) * 0.95)
		if cx >= SIZE:
			break
		river[y * 100 + cx] = true
		river[y * 100 + cx + 1] = true
		if rng.chance(0.35):
			rx += rng.pick([-1, 1])
	for y in SIZE:
		for x in SIZE:
			var terrain := "grass"
			var h := 0
			var is_river: bool = river.has(y * 100 + x) and not near_node.call(x, y, 2)
			if is_river:
				terrain = "shallows" if near_road.call(x, y, 1.1) else "water"
			else:
				var f := Terrain.fbm(x * 0.13, y * 0.13, ex.seed)
				var clear: bool = near_node.call(x, y, 3.3) or near_road.call(x, y, 1.5)
				if f > 0.5 and not clear:
					terrain = "forest"
					if rng.chance(0.8):
						var px := x + rng.frange(-0.25, 0.25)
						var py := y + rng.frange(-0.25, 0.25)
						var pr := "tree_pine" if rng.chance(0.6) else "tree_oak"
						var pv := rng.rint(0, 9)
						props_out.append({"x": px, "y": py, "prop": pr, "v": pv, "s": rng.frange(0.85, 1.15)})
					if rng.chance(0.35):
						var px := x + rng.frange(-0.45, 0.45)
						var py := y + rng.frange(-0.45, 0.45)
						var pr := "tree_pine" if rng.chance(0.7) else "bush"
						var pv := rng.rint(0, 9)
						props_out.append({"x": px, "y": py, "prop": pr, "v": pv, "s": rng.frange(0.7, 1)})
				elif not clear and rng.chance(0.05):
					var pr: String = rng.pick(["rock_small", "bush", "bush", "rock_large"])
					props_out.append({"x": x, "y": y, "prop": pr, "v": rng.rint(0, 9), "s": 0.9})
				elif not clear and f > 0.42 and rng.chance(0.25) and not near_node.call(x, y, 3.8):
					var px := x + rng.frange(-0.3, 0.3)
					var py := y + rng.frange(-0.3, 0.3)
					var pr := "tree_oak" if rng.chance(0.5) else "tree_pine"
					var pv := rng.rint(0, 9)
					props_out.append({"x": px, "y": py, "prop": pr, "v": pv, "s": rng.frange(0.8, 1.05)})
				if f < 0.32 and not near_road.call(x, y, 2.6) and not near_node.call(x, y, 3.2) and Terrain.fbm(x * 0.2, y * 0.2, ex.seed + 9) > 0.55:
					h = 1
				if Terrain.fbm(x * 0.3, y * 0.3, ex.seed + 3) > 0.66 and terrain == "grass":
					terrain = "dirt"
			tiles.append({"x": x, "y": y, "h": h, "terrain": terrain})
	# Decorative ring of forest beyond the map.
	var B := 9
	for y in range(-B, SIZE + B):
		for x in range(-B, SIZE + B):
			if x >= 0 and y >= 0 and x < SIZE and y < SIZE:
				continue
			var d := maxi(maxi(-x, -y), maxi(x - (SIZE - 1), y - (SIZE - 1)))
			if d > 6:
				continue
			if rng.chance(0.8):
				var px := x + rng.frange(-0.3, 0.3)
				var py := y + rng.frange(-0.3, 0.3)
				var pr := "tree_pine" if rng.chance(0.6) else "tree_oak"
				var pv := rng.rint(0, 9)
				props_out.append({"x": px, "y": py, "prop": pr, "v": pv, "s": rng.frange(0.85, 1.2)})
	var road_list: Array = []
	for k in road_map:
		road_list.append(road_map[k])
	var terrain_in := {"w": SIZE, "h": SIZE, "border": B, "tiles": tiles, "seed": ex.seed, "palette": "map", "roads": road_list, "decals": false, "res": 14, "scale": 0.5}
	props_out = JS.sort(props_out, func(a, b): return (a.x + a.y) - (b.x + b.y))
	# Fog puffs on a jittered lattice.
	var fog_out: Array = []
	var fy := -6.0
	while fy < SIZE + 6:
		var fx := -6.0
		while fx < SIZE + 6:
			fog_out.append({"x": fx + Rng.hash2(fx * 10, fy * 10) * 1.2, "y": fy + Rng.hash2(fy * 10, fx * 10) * 1.2, "a": 1.0, "r": 1 + Rng.hash2(fx, fy, 4) * 0.8})
			# Constant parts of updateFog's target (edge haze and the per-puff variation).
			var f: Dictionary = fog_out[fog_out.size() - 1]
			f["edge"] = maxf(0.0, maxf(maxf(-f.x, -f.y), maxf(f.x - (SIZE - 1), f.y - (SIZE - 1))) + 2) / 3.0
			f["hk"] = 0.55 + 0.35 * Rng.hash2(f.x * 3, f.y * 3, 11)
			fx += 1.7
		fy += 1.7
	return {"roads": road_map, "props": props_out, "terrain": terrain_in, "fog": fog_out}


## nodeView: what the player can see of a node (type and title; the map
## needs no detail text).
static func node_view(n: Dictionary) -> Dictionary:
	if not n.get("revealed", false):
		return {"type": "unknown", "title": "Unexplored"}
	if n.type == "ambush" and not n.get("scouted", false):
		return {"type": "event", "title": n.name}
	return {"type": n.type, "title": n.name}


static func next_nodes(ex: Dictionary) -> Array:
	var out: Array = []
	for e in ex.edges:
		if e[0] == ex.current:
			for n in ex.nodes:
				if n.id == e[1]:
					out.append(n)
	return out


static func _node(ex: Dictionary, id: String) -> Dictionary:
	for n in ex.nodes:
		if n.id == id:
			return n
	return {}


static func _node_of_type(ex: Dictionary, type: String) -> Variant:
	for n in ex.nodes:
		if n.type == type:
			return n
	return null


## The constructor: `ex` is the expedition to build the map from, `getter`
## returns the live expedition (or null) every frame.
func setup(ex: Dictionary, getter: Callable) -> void:
	get_ex = getter
	var world := world_for(ex)
	roads = world.roads
	props = world.props
	fog = world.fog
	_terrain_input = world.terrain
	shown_node = ex.current
	var cur := _node(ex, ex.current)
	token = {"x": float(cur.tx), "y": float(cur.ty)}
	# Look up the road toward the objective rather than at the map corner.
	var obj: Dictionary = _node_of_type(ex, "objective")
	var fx0: float = cur.tx + (obj.tx - cur.tx) * 0.22
	var fy0: float = cur.ty + (obj.ty - cur.ty) * 0.22
	cam = Camera.new(Iso.iso_x(fx0, fy0), Iso.iso_y(fx0, fy0) - 60, 0.6)
	atmo = Atmosphere.new(ex.seed)
	build_horde(ex)
	if int(ex.get("marches", 0)) == 0 and horde != null:
		var p := horde_at(horde.front - 0.1, 0)
		intro = {"t": 0.0, "from": {"x": Iso.iso_x(p.x, p.y), "y": Iso.iso_y(p.x, p.y) - 40, "z": 0.5}, "to": {"x": cam.x, "y": cam.y, "z": cam.zoom}}
		cam.x = intro.from.x
		cam.tx = cam.x
		cam.y = intro.from.y
		cam.ty = cam.y
		cam.zoom = intro.from.z
		cam.tzoom = cam.zoom
	_update_fog(1.0)
	Assets.warm_async(["tree_pine", "tree_oak", "bush", "rock_small", "rock_large", "war_banner", "footman_idle_b", "spearman_idle_b", "crossbowman_idle_b",
		"node_start", "node_battle", "node_event", "node_scout", "node_village", "node_camp", "node_ambush", "node_objective",
		"goblin_rabble_idle_f", "goblin_spear_idle_f", "goblin_archer_idle_f", "orc_warrior_idle_f", "orc_brute_idle_f", "wolf_rider_idle_f"])
	_prop_items = []
	for p in props:
		var s := Assets.sprite(p.prop, p.v)
		var flip: bool = not s.get("noShadow", false) and Rng.hash2(p.x * 7, p.y * 7) > 0.5
		var x := Iso.iso_x(p.x, p.y)
		var y := Iso.iso_y(p.x, p.y)
		var it := {"d": p.x + p.y, "k": 0, "s": s, "x": x, "y": y, "flip": flip, "sc": float(p.s), "r": _bounds(s, x, y, float(p.s))}
		_quads(it)
		_prop_items.append(it)
	if is_inside_tree():
		_build_nodes()


## Precomputed quads of a static sprite (drawSprite and drawCastShadow with
## the same transforms as Assets.draw_sprite / draw_cast_shadow), so a prop is
## one draw_primitive per frame.
static func _quads(it: Dictionary) -> void:
	var s: Dictionary = it.s
	if s.is_empty():
		return
	var sc: float = s.scale * it.sc
	var sx: float = -sc if it.flip else sc
	var reg: Rect2 = s.region
	var ts: Vector2 = s.tex.get_size()
	var pts := PackedVector2Array()
	var spts := PackedVector2Array()
	var uv := PackedVector2Array()
	for c in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		var u: float = c.x * s.w - s.ax
		var v: float = c.y * s.h - s.ay
		var X := sx * u
		var Y := sc * v
		pts.append(Vector2(it.x + X, it.y + Y))
		# ctx.transform(1, 0, -0.75, -0.32, 0, 0): shadows fall down and to the right.
		spts.append(Vector2(it.x + X - 0.75 * Y, it.y - 0.32 * Y))
		uv.append((reg.position + Vector2(c.x * s.w, c.y * s.h)) / ts)
	it["tex"] = s.tex
	it["pts"] = pts
	it["spts"] = spts
	it["uv"] = uv
	it["shadow"] = not s.get("noShadow", false)


## World rectangle a sprite (and its cast shadow) can cover, for culling.
static func _bounds(s: Dictionary, x: float, y: float, sc: float) -> Rect2:
	if s.is_empty():
		return Rect2(x, y, 0, 0)
	var k: float = s.scale * sc
	var w: float = s.w * k
	var h: float = s.h * k
	var top: float = y - s.ay * k
	var left: float = x - maxf(s.ax, s.w - s.ax) * k
	return Rect2(left, top, w * 2.0 + h * 0.8, h * 1.4).grow(4.0)


func _view_rect(margin: float = 0.0) -> Rect2:
	var hw: float = _w / 2.0 / cam.zoom
	var hh: float = _h / 2.0 / cam.zoom
	return Rect2(cam.x - hw, cam.y - hh, hw * 2, hh * 2).grow(margin)


## The host coming down on Brannsted from beyond the far corner. Positions
## are given along the line from the objective (t = 0) toward the start
## (t = 1); the host lives at negative t and edges closer with every march.
func build_horde(ex: Dictionary) -> void:
	var obj: Variant = _node_of_type(ex, "objective")
	var start: Variant = _node_of_type(ex, "start")
	if obj == null or start == null:
		return
	var dx: float = start.tx - obj.tx
	var dy: float = start.ty - obj.ty
	var len := JS.hypot(dx, dy)
	if len == 0:
		len = 1.0
	var rng := Rng.new((int(ex.seed) ^ 0x6a09) & 0xFFFFFFFF)
	var kinds := ["goblin_rabble", "goblin_rabble", "goblin_spear", "goblin_spear", "goblin_archer", "orc_warrior", "orc_brute", "wolf_rider"]
	var bands: Array = []
	for i in 20:
		# Depth behind the host's front: the whole mass follows the front forward.
		var t := rng.frange(0.025, 0.24)
		var s := rng.frange(-11, 11)
		var figs: Array = []
		var n := rng.rint(9, 15)
		var kind: String = rng.pick(kinds)
		for k in n:
			# Facing down the road toward Brannsted: front views, some mirrored.
			var flip := rng.chance(0.5)
			var a := rng.frange(-0.03, 0.03)
			var b := rng.frange(-1.3, 1.3)
			var key := "%s_idle_f" % ("goblin_rabble" if kind == "wolf_rider" and k % 3 != 0 else kind)
			figs.append({"a": a, "b": b, "key": key, "v": rng.rint(0, 5), "flip": flip, "banner": k == 0})
		# Draw order inside a band: by depth (x + y); the drift moves every
		# figure of the band alike, so the order never changes.
		var ux: float = dx / len
		var uy: float = dy / len
		figs = JS.sort(figs, func(p, q): return ((ux + uy) * len * p.a + (ux - uy) * p.b) - ((ux + uy) * len * q.a + (ux - uy) * q.b))
		bands.append({"t": t, "s": s, "figs": figs})
	var fires: Array = []
	for i in 8:
		var ft := rng.frange(0.0, 0.3)
		var fs := rng.frange(-11, 11)
		fires.append({"t": ft, "s": fs, "k": rng.frange(0, 1)})
	horde = {"ox": float(obj.tx), "oy": float(obj.ty), "ux": dx / len, "uy": dy / len, "len": len, "bands": bands, "fires": fires, "front": front_for(ex)}


## How far the host has come: closer to Brannsted with every march, at its walls by the end.
func front_for(ex: Dictionary) -> float:
	return minf(-0.03, -0.27 + int(ex.get("marches", 0)) * 0.048)


## Grid point at `t` along the host's line and `s` tiles across it.
func horde_at(t: float, s: float) -> Vector2:
	var h: Dictionary = horde
	return Vector2(h.ox + h.ux * h.len * t - h.uy * s, h.oy + h.uy * h.len * t + h.ux * s)


func _ready() -> void:
	if cam == null:
		cam = Camera.new()
		atmo = Atmosphere.new(1)
	if not _terrain_input.is_empty():
		_build_nodes()


func _build_nodes() -> void:
	if _ready_done:
		return
	_ready_done = true
	var bg := WorldCanvas.new(func(ci: CanvasItem) -> void: ci.draw_rect(Rect2(Vector2.ZERO, Vector2(_w, _h)), Color8(0x1b, 0x28, 0x12)), "Background")
	add_child(bg)
	_nodes.bg = bg
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	terrain = Terrain.build_terrain(_terrain_input)
	_world.add_child(terrain)
	var water: Node2D = terrain.make_water_node("campaign")
	_world.add_child(water)
	_nodes.water = water
	_world.add_child(atmo.make_clouds_node(Iso.iso_x(SIZE / 2.0, SIZE / 2.0), Iso.iso_y(SIZE / 2.0, SIZE / 2.0)))
	_nodes.routes = _canvas("Routes", _draw_routes)
	_items_root = Node2D.new()
	_items_root.name = "Items"
	_world.add_child(_items_root)
	_nodes.air = _canvas("Air", func(ci: CanvasItem) -> void: fx.draw_air(ci))
	_nodes.fog = _make_fog_node()
	_nodes.wash = _canvas("HordeLand", _draw_horde_land)
	_nodes.wash.material = _clip_material(ClipShader)
	_nodes.glow = _canvas("HordeGlow", _draw_horde_glow)
	_nodes.glow.material = _clip_material(GlowShader)
	_nodes.bands = _canvas("HordeBands", _draw_horde_bands)
	_nodes.bands.material = _clip_material(ClipShader)
	_nodes.horde_air = _canvas("HordeAir", func(ci: CanvasItem) -> void: horde_fx.draw_air(ci))
	_nodes.labels = _canvas("Labels", _draw_labels)
	var screen := Node2D.new()
	screen.name = "Screen"
	add_child(screen)
	screen.add_child(atmo.make_grade_node())
	_refresh_view()


func _canvas(node_name: String, fn: Callable) -> Node2D:
	var n := WorldCanvas.new(fn, node_name)
	_world.add_child(n)
	return n


func _clip_material(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("lo", -LAND_E)
	m.set_shader_parameter("hi", SIZE + LAND_E)
	return m


func _ex() -> Variant:
	return get_ex.call() if get_ex.is_valid() else null


func _notify() -> void:
	ui.version += 1
	changed.emit()


func _update_fog(rate: float) -> void:
	var ex: Variant = _ex()
	if ex == null:
		return
	var known: Array = []
	var key := ""
	for n in ex.nodes:
		if n.get("revealed", false):
			known.append(n)
			key += "%s%s," % [n.id, "v" if n.get("visited", false) else ""]
	# Once every puff has settled on its target (and the knowledge is the
	# same), the update no longer changes anything visible.
	if key == _fog_key and _fog_still:
		return
	if key != _fog_key:
		_fog_key = key
		_fog_still = false
	var moved := 0.0
	var kx := PackedFloat64Array()
	var ky := PackedFloat64Array()
	var kv := PackedFloat64Array()
	for n in known:
		kx.append(n.tx)
		ky.append(n.ty)
		kv.append(1.5 if n.get("visited", false) else 0.0)
	var nk := kx.size()
	for f in fog:
		var fxp: float = f.x
		var fyp: float = f.y
		var d := INF
		for i in nk:
			var ddx := kx[i] - fxp
			var ddy := ky[i] - fyp
			d = minf(d, sqrt(ddx * ddx + ddy * ddy) - kv[i])
		var unknown := clampf((d - 5) / 5.0, 0.0, 1.0)
		var target: float = clampf(maxf(unknown * 0.4, f.edge), 0.0, 1.0) * f.hk
		moved = maxf(moved, absf(target - f.a))
		f.a += (target - f.a) * rate
	_fog_still = moved < 0.0005


# ---------------------------------------------------------------- update


func _process(delta: float) -> void:
	if not _ready_done:
		return
	var dt := minf(0.05, delta)
	time += dt
	update(dt)
	_refresh_view()


func update(dt: float) -> void:
	var ex: Variant = _ex()
	cam.pan_keys(dt, 700.0, self)
	# Keep the view over the map.
	var cx := Iso.iso_x(SIZE / 2.0, SIZE / 2.0)
	var cy := Iso.iso_y(SIZE / 2.0, SIZE / 2.0)
	var rx: float = (SIZE * TW) / 2.0 - _w / (2 * cam.zoom) + 200
	var ry: float = (SIZE * TH) / 2.0 - _h / (2 * cam.zoom) + 150
	cam.tx = clampf(cam.tx, cx - maxf(0, rx), cx + maxf(0, rx))
	cam.ty = clampf(cam.ty, cy - maxf(0, ry), cy + maxf(0, ry))
	if intro != null:
		# Hold on the host for a moment, then sweep back to the company.
		var it: Dictionary = intro
		it.t += dt
		var k := clampf((it.t - 2.2) / 2.6, 0.0, 1.0)
		var e := 2 * k * k if k < 0.5 else 1 - pow(-2 * k + 2, 2) / 2
		cam.x = it.from.x + (it.to.x - it.from.x) * e
		cam.tx = cam.x
		cam.y = it.from.y + (it.to.y - it.from.y) * e
		cam.ty = cam.y
		cam.zoom = it.from.z + (it.to.z - it.from.z) * e
		cam.tzoom = cam.zoom
		if k >= 1 or march != null:
			intro = null
	else:
		cam.update(dt)
	atmo.update(dt, _w, _h)
	fx.update(dt)
	# The host creeps forward as the company marches.
	if horde != null and ex != null:
		var want := front_for(ex)
		horde.front += (want - horde.front) * minf(1.0, dt * 0.8)
		for f in horde.fires:
			f.k += dt
			if f.k > 0.32:
				f.k = 0.0
				var p := horde_at(horde.front - f.t, f.s)
				horde_fx.burst(Iso.iso_x(p.x, p.y) + (randf() - 0.5) * 24, Iso.iso_y(p.x, p.y), 30, 1, {"shape": "puff", "color": "rgba(60,50,46,1)" if randf() < 0.4 else "rgba(96,86,80,1)", "speed": 8, "vz": 40, "gravity": -6, "size": 26, "max": 6, "drag": 0.15})
	horde_fx.update(dt)
	_update_fog(minf(1.0, dt * 1.5))
	if ex != null and ex.current != shown_node and march == null:
		var road: Variant = roads.get("%s>%s" % [shown_node, ex.current])
		var target := _node(ex, ex.current)
		march = {"path": road if road != null else [token, {"x": target.tx, "y": target.ty}], "t": 0.0, "dur": 1.8}
		ui.marching = true
		_sfx("march")
		_notify()
	if march != null:
		var m: Dictionary = march
		m.t += dt
		var f := minf(1.0, m.t / m.dur)
		var e := 2 * f * f if f < 0.5 else 1 - pow(-2 * f + 2, 2) / 2
		var path: Array = m.path
		var idx := e * (path.size() - 1)
		var i := mini(path.size() - 2, floori(idx))
		var k := idx - i
		token = {"x": path[i].x + (path[i + 1].x - path[i].x) * k, "y": path[i].y + (path[i + 1].y - path[i].y) * k}
		cam.tx = Iso.iso_x(token.x, token.y)
		cam.ty = Iso.iso_y(token.x, token.y) - 60
		if randf() < dt * 14:
			fx.burst(Iso.iso_x(token.x, token.y), Iso.iso_y(token.x, token.y), 2, 2, {"shape": "puff", "color": "rgba(190,165,120,1)", "speed": 20, "vz": 20, "gravity": 5, "size": 7, "max": 0.8})
		if f >= 1:
			march = null
			shown_node = ex.current if ex != null else shown_node
			ui.marching = false
			_notify()
	# Smoke from the fires of the objective and of visited camps (drawNode
	# spawned it once per rendered frame at 15%; here per 1/60 s).
	if ex != null:
		for n in ex.nodes:
			if node_view(n).type == "unknown":
				continue
			if n.type == "objective" or (n.type == "camp" and n.get("visited", false)):
				if randf() < 0.15 * dt * 60.0:
					fx.burst(Iso.iso_x(n.tx, n.ty) + 10, Iso.iso_y(n.tx, n.ty) - 60, 30, 1, {"shape": "puff", "color": "rgba(200,200,200,1)", "speed": 6, "vz": 30, "gravity": -6, "size": 12, "max": 2.5, "drag": 0.2})


func _sfx(sound: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var s: Node = tree.root.get_node_or_null("Sfx") if tree != null else null
	if s != null:
		s.play(sound)


func focus_current() -> void:
	var ex: Variant = _ex()
	if ex == null:
		return
	var n := _node(ex, ex.current)
	var obj: Dictionary = _node_of_type(ex, "objective")
	var fx0: float = n.tx + (obj.tx - n.tx) * 0.18
	var fy0: float = n.ty + (obj.ty - n.ty) * 0.18
	cam.tx = Iso.iso_x(fx0, fy0)
	cam.ty = Iso.iso_y(fx0, fy0) - 60


# ---------------------------------------------------------------- input


func node_at(sx: float, sy: float) -> Variant:
	var ex: Variant = _ex()
	if ex == null:
		return null
	var wpt: Vector2 = cam.screen_to_world(sx, sy, _w, _h)
	var best: Variant = null
	var bd := 70.0
	for n in ex.nodes:
		var d := JS.hypot(Iso.iso_x(n.tx, n.ty) - wpt.x, Iso.iso_y(n.tx, n.ty) - 30 - wpt.y)
		if d < bd:
			bd = d
			best = n
	return best


func pointer_move(sx: float, sy: float) -> void:
	var n: Variant = node_at(sx, sy)
	var id: Variant = n.id if n != null else null
	if id != ui.get("hover"):
		if id == null:
			ui.erase("hover")
		else:
			ui["hover"] = id
		_notify()


func pointer_down(sx: float, sy: float, button: int) -> void:
	if button != MOUSE_BUTTON_LEFT or march != null:
		return
	var n: Variant = node_at(sx, sy)
	if n != null:
		node_clicked.emit(n.id)


func wheel(delta: float) -> void:
	cam.wheel(delta, 0.25, 1.2)


func _unhandled_input(e: InputEvent) -> void:
	if not _ready_done:
		return
	if e is InputEventMouseMotion:
		var p := Camera.view_local(self, e.position)
		pointer_move(p.x, p.y)
	elif e is InputEventMouseButton and e.pressed:
		var p := Camera.view_local(self, e.position)
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			wheel(-1)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			wheel(1)
		else:
			cam.drag_input(e, self)
			pointer_down(p.x, p.y, e.button_index)


func _input(e: InputEvent) -> void:
	if cam != null:
		cam.drag_motion(e, self)


# ---------------------------------------------------------------- render


func _refresh_view() -> void:
	var view := Camera.view_size(self)
	_w = view.x
	_h = view.y
	_world.transform = cam.transform(view)
	var inv: Transform2D = _world.get_global_transform().affine_inverse()
	for key in ["wash", "glow", "bands"]:
		var m: ShaderMaterial = _nodes[key].material
		m.set_shader_parameter("to_world_x", inv.x)
		m.set_shader_parameter("to_world_y", inv.y)
		m.set_shader_parameter("to_world_o", inv.origin)
	_nodes.water.time = time
	(_nodes.fog.material as ShaderMaterial).set_shader_parameter("time", time)
	_upload_fog()
	_build_items()
	atmo.redraw(view, time)
	for k in _nodes:
		if k != "water" and k != "fog":
			_nodes[k].queue_redraw()


## Depth-sorted props, landmarks and the army (props are sorted once).
func _build_items() -> void:
	var ex: Variant = _ex()
	var key := "%s,%s,%d" % [token.x, token.y, ex.nodes.size() if ex != null else -1]
	if key == _items_key and not _items.is_empty():
		_layout_items()
		return
	_items_key = key
	var dyn: Array = []
	if ex != null:
		for n in ex.nodes:
			dyn.append({"d": n.tx + n.ty + 0.2, "k": 1, "n": n})
		dyn.append({"d": token.x + token.y + 0.4, "k": 2})
	dyn = JS.sort(dyn, func(a, b): return a.d - b.d)
	var all: Array = []
	var i := 0
	var j := 0
	while i < _prop_items.size() or j < dyn.size():
		if j >= dyn.size() or (i < _prop_items.size() and _prop_items[i].d <= dyn[j].d):
			all.append(_prop_items[i])
			i += 1
		else:
			all.append(dyn[j])
			j += 1
	_items = all
	_layout_items()


## The props never move: each run of props between two dynamic items
## (landmarks, the army) is a canvas item recorded once and kept until the
## order or the shadow detail changes; only the dynamic items redraw per frame.
## Same draw order as drawing the whole sorted list every frame.
func _layout_items() -> void:
	var zoom_skip: bool = cam.zoom < 0.32
	var sig := PackedStringArray([str(zoom_skip)])
	for i in _items.size():
		if _items[i].k != 0:
			sig.append(str(i))
	var key := ",".join(sig)
	if key != _seg_key:
		_seg_key = key
		for c in _items_root.get_children():
			c.queue_free()
			_items_root.remove_child(c)
		_dyn_nodes = []
		var run: Array = []
		for it in _items:
			if it.k == 0:
				run.append(it)
				continue
			if not run.is_empty():
				_add_run(run, zoom_skip)
				run = []
			var item: Dictionary = it
			var n := WorldCanvas.new(func(ci: CanvasItem) -> void: _draw_dynamic(ci, item), "Dyn")
			_items_root.add_child(n)
			_dyn_nodes.append(n)
		if not run.is_empty():
			_add_run(run, zoom_skip)
	for n in _dyn_nodes:
		n.queue_redraw()


func _add_run(run: Array, zoom_skip: bool) -> void:
	var items := run.duplicate()
	var n := WorldCanvas.new(func(ci: CanvasItem) -> void: _draw_props(ci, items, zoom_skip), "Props")
	_items_root.add_child(n)


func _draw_props(ci: CanvasItem, items: Array, zoom_skip: bool) -> void:
	var white := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	var shade := Color(0, 0, 0, 0.16)
	var dark := PackedColorArray([shade, shade, shade, shade])
	for it in items:
		if not it.has("pts"):
			continue
		if not zoom_skip and it.shadow:
			ci.draw_primitive(it.spts, dark, it.uv, it.tex)
		ci.draw_primitive(it.pts, white, it.uv, it.tex)


func _draw_dynamic(ci: CanvasItem, it: Dictionary) -> void:
	var ex: Variant = _ex()
	if it.k == 2:
		_draw_army(ci)
		return
	if ex == null:
		return
	var reachable := false
	if march == null:
		for n in next_nodes(ex):
			if n.id == it.n.id:
				reachable = true
	_draw_node(ci, ex, it.n, reachable)


func _draw_routes(ci: CanvasItem) -> void:
	var ex: Variant = _ex()
	if ex == null:
		return
	var nxt := {}
	if march == null:
		for n in next_nodes(ex):
			nxt[n.id] = true
	var path: Array = ex.path
	var segs := PackedVector2Array()
	var caps := PackedVector2Array()
	for key in roads:
		var ab: PackedStringArray = key.split(">")
		var a := ab[0]
		var b := ab[1]
		var travelled := path.has(a) and path.has(b) and path.find(b) == path.find(a) + 1
		var open: bool = a == ex.current and nxt.has(b)
		if not travelled and not open:
			continue
		var pts := PackedVector2Array()
		for p in roads[key]:
			pts.append(Iso.iso(p.x, p.y))
		if travelled:
			var col := Color(60 / 255.0, 90 / 255.0, 200 / 255.0, 0.7)
			WD.stroke_round(ci, pts, col, 6.0)
		else:
			_dashed(segs, caps, pts, [10.0, 12.0], -time * 40.0)
	if segs.size() > 0:
		var col := Color(1.0, 225 / 255.0, 130 / 255.0, 0.95)
		ci.draw_multiline(segs, col, 5.0, true)
		for c in caps:
			WD.fill_circle(ci, c, 2.5, col)


## A dashed polyline with round caps (setLineDash + lineDashOffset): the dash
## segments go to `segs` (one batched multiline), the cap centres to `caps`.
func _dashed(segs: PackedVector2Array, caps: PackedVector2Array, pts: PackedVector2Array, pattern: Array, offset: float) -> void:
	var period: float = pattern[0] + pattern[1]
	# Position along the dash pattern at the start of the path.
	var phase := fposmod(offset, period)
	var on: bool = phase < float(pattern[0])
	var left: float = (float(pattern[0]) - phase) if on else (period - phase)
	if on:
		caps.append(pts[0])
	for s in range(1, pts.size()):
		var a := pts[s - 1]
		var b := pts[s]
		var seg := a.distance_to(b)
		var pos := 0.0
		var from := a
		while seg - pos > left:
			pos += left
			var p := a.lerp(b, pos / seg)
			if on:
				segs.append(from)
				segs.append(p)
				caps.append(p)
			else:
				caps.append(p)
			from = p
			on = not on
			left = float(pattern[0]) if on else float(pattern[1])
		left -= seg - pos
		if on:
			segs.append(from)
			segs.append(b)
	if on:
		caps.append(pts[pts.size() - 1])


func _draw_node(ci: CanvasItem, ex: Dictionary, n: Dictionary, reachable: bool) -> void:
	var x := Iso.iso_x(n.tx, n.ty)
	var y := Iso.iso_y(n.tx, n.ty)
	var view := node_view(n)
	var hover: bool = ui.get("hover") == n.id
	# Clearing under the landmark.
	ci.draw_colored_polygon(WD.ellipse(x, y, 90, 45, 0.0, 48), Color(40 / 255.0, 30 / 255.0, 15 / 255.0, 0.18))
	if reachable or hover:
		var a := 0.55 + 0.35 * sin(time * 3)
		var ring := WD.ellipse(x, y, 80, 40, 0.0, 64)
		ring.append(ring[0])
		ci.draw_polyline(ring, WD.with_alpha(Color8(0xff, 0xf3, 0xc4) if hover else Color8(0xff, 0xd7, 0x6a), a), 4.0, true)
	if view.type == "unknown":
		WD.draw_text(ci, x, y - 20, "?", 64.0, Color(60 / 255.0, 50 / 255.0, 40 / 255.0, 0.7), cam.zoom)
		return
	var s := Assets.sprite("node_%s" % view.type)
	var base := 0.92 if s.get("noShadow", false) else 1.4
	var alpha := 0.7 if n.get("visited", false) and n.id != ex.current else 1.0
	Assets.draw_cast_shadow(ci, s, x, y, false, base, 0.2 * alpha)
	Assets.draw_sprite(ci, s, x, y, false, base + (0.06 if hover else 0.0), Color(1, 1, 1, alpha))


func _draw_army(ci: CanvasItem) -> void:
	var x := Iso.iso_x(token.x, token.y)
	var y := Iso.iso_y(token.x, token.y)
	var bob := absf(sin(time * 9)) * 4 if march != null else 0.0
	# Banner bearer and a few soldiers.
	var types := ["footman", "spearman", "crossbowman"]
	var offs := [[-26, 8], [22, 12], [0, -10]]
	for i in 3:
		var s := Assets.sprite("%s_idle_b" % types[i])
		var ox: float = offs[i][0]
		var oy: float = offs[i][1]
		Assets.draw_cast_shadow(ci, s, x + ox, y + oy, false, 0.85, 0.2)
		Assets.draw_sprite(ci, s, x + ox, y + oy - bob * (1.0 if i % 2 else 0.6), false, 0.85)
	# Standard.
	ci.draw_line(Vector2(x + 6, y - 6), Vector2(x + 6, y - 150), Color8(0x4a, 0x2f, 0x1c), 4.0, true)
	var wave := sin(time * 4) * 6
	var flag := PackedVector2Array([Vector2(x + 8, y - 148)])
	_quad(flag, Vector2(x + 8, y - 148), Vector2(x + 40, y - 150 + wave), Vector2(x + 70, y - 140))
	flag.append(Vector2(x + 66, y - 108))
	_quad(flag, Vector2(x + 66, y - 108), Vector2(x + 38, y - 116 - wave), Vector2(x + 8, y - 110))
	ci.draw_colored_polygon(flag, Color8(0x2f, 0x58, 0xb8))
	var loop := flag.duplicate()
	loop.append(flag[0])
	ci.draw_polyline(loop, Color8(0x1a, 0x12, 0x08), 2.0, true)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(x + 38, y - 138), Vector2(x + 46, y - 128), Vector2(x + 38, y - 118), Vector2(x + 30, y - 128)]), Color8(0xf2, 0xef, 0xe4))


## Appends a quadratic curve from p0 (exclusive) through control c to p1.
static func _quad(out: PackedVector2Array, p0: Vector2, c: Vector2, p1: Vector2) -> void:
	for i in range(1, 13):
		var t := i / 12.0
		out.append(p0 * (1 - t) * (1 - t) + c * 2 * (1 - t) * t + p1 * t * t)


## Fog of war: every puff in one MultiMesh (atmo_fog.gdshader moves them);
## the per-puff alpha is uploaded when it has changed.
func _make_fog_node() -> Node2D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = Terrain._unit_quad()
	mm.instance_count = fog.size()
	_fog_buf = PackedFloat32Array()
	_fog_buf.resize(fog.size() * 16)
	for i in fog.size():
		var f: Dictionary = fog[i]
		var o := i * 16
		_fog_buf[o] = 1.0
		_fog_buf[o + 5] = 1.0
		_fog_buf[o + 8] = 1.0
		_fog_buf[o + 9] = 1.0
		_fog_buf[o + 10] = 1.0
		_fog_buf[o + 12] = Iso.iso_x(f.x, f.y)
		_fog_buf[o + 13] = Iso.iso_y(f.x, f.y) - 30
		_fog_buf[o + 14] = 150 * f.r
		_fog_buf[o + 15] = f.x
	# The quads are placed by the shader: give the MultiMesh the fog's real
	# extent, or its canvas item is culled as a unit quad at the origin.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in fog.size():
		var c := Vector2(_fog_buf[i * 16 + 12], _fog_buf[i * 16 + 13])
		var r: float = _fog_buf[i * 16 + 14] + 12.0
		lo = lo.min(c - Vector2(r, r))
		hi = hi.max(c + Vector2(r, r))
	mm.custom_aabb = AABB(Vector3(lo.x, lo.y, -1), Vector3(hi.x - lo.x, hi.y - lo.y, 2))
	var n := MultiMeshInstance2D.new()
	n.name = "Fog"
	n.multimesh = mm
	n.texture = puff()
	var mat := ShaderMaterial.new()
	mat.shader = FogShader
	n.material = mat
	_world.add_child(n)
	for i in fog.size():
		var f: Dictionary = fog[i]
		_fog_buf[i * 16 + 11] = 0.85 * f.a if f.a >= 0.02 else 0.0
	mm.buffer = _fog_buf
	return n


func _upload_fog(force: bool = false) -> void:
	var changed := force
	for i in fog.size():
		var f: Dictionary = fog[i]
		# Puffs below 0.02 are skipped by the original.
		var a: float = 0.85 * f.a if f.a >= 0.02 else 0.0
		if absf(_fog_buf[i * 16 + 11] - a) > 0.0005:
			_fog_buf[i * 16 + 11] = a
			changed = true
	if changed:
		var mm: MultiMesh = _nodes.fog.multimesh if _nodes.has("fog") else null
		if mm == null:
			return
		mm.buffer = _fog_buf


## The soft grey-green mist puff (128 px radial gradient from r 8 to 64).
static func puff() -> Texture2D:
	if _puff != null:
		return _puff
	var stops := [[0.0, Color8(200, 208, 200, 255)], [0.5, Color(196 / 255.0, 205 / 255.0, 198 / 255.0, 0.55)], [1.0, Color(190 / 255.0, 200 / 255.0, 194 / 255.0, 0.0)]]
	var data := PackedByteArray()
	data.resize(128 * 128 * 4)
	for py in 128:
		for px in 128:
			var d := Vector2(px + 0.5 - 64, py + 0.5 - 64).length()
			var t := clampf((d - 8.0) / 56.0, 0.0, 1.0)
			var c: Color = stops[0][1].lerp(stops[1][1], t / 0.5) if t < 0.5 else stops[1][1].lerp(stops[2][1], (t - 0.5) / 0.5)
			var o := (py * 128 + px) * 4
			data[o] = c.r8
			data[o + 1] = c.g8
			data[o + 2] = c.b8
			data[o + 3] = c.a8
	_puff = ImageTexture.create_from_image(Image.create_from_data(128, 128, false, Image.FORMAT_RGBA8, data))
	return _puff


## Behind the front the land is scorched and smoking; the host's warbands
## mass there under their standards, and burning farms send up smoke. Drawn
## over the fog: the horde is seen from afar even where scouts have not been.
func _draw_horde_land(ci: CanvasItem) -> void:
	if horde == null:
		return
	var h: Dictionary = horde
	# Scorched land: a reddish-dark wash deepening away from the front, on the land only.
	var a := horde_at(h.front, -30)
	var b := horde_at(h.front, 30)
	var c := horde_at(h.front - 0.5, 30)
	var d := horde_at(h.front - 0.5, -30)
	var p0 := Iso.iso(horde_at(h.front, 0).x, horde_at(h.front, 0).y)
	var p1 := Iso.iso(horde_at(h.front - 0.3, 0).x, horde_at(h.front - 0.3, 0).y)
	var quad := PackedVector2Array([Iso.iso(a.x, a.y), Iso.iso(b.x, b.y), Iso.iso(c.x, c.y), Iso.iso(d.x, d.y)])
	var axis := p1 - p0
	var len2 := axis.length_squared()
	if len2 <= 0:
		return
	var stops := [[0.0, Color(60 / 255.0, 20 / 255.0, 10 / 255.0, 0.0)], [0.18, Color(70 / 255.0, 24 / 255.0, 12 / 255.0, 0.38)], [1.0, Color(36 / 255.0, 12 / 255.0, 8 / 255.0, 0.62)]]
	# Cut the quad at the gradient stops so each piece is linear in colour.
	var cuts := [-1e6, 0.0, 0.18, 1.0, 1e6]
	var n := axis / len2
	var perp := Vector2(-axis.y, axis.x).normalized() * 2e4
	for i in cuts.size() - 1:
		var lo_p := p0 + axis * maxf(cuts[i], -50.0)
		var hi_p := p0 + axis * minf(cuts[i + 1], 50.0)
		var band := PackedVector2Array([lo_p - perp, lo_p + perp, hi_p + perp, hi_p - perp])
		for part in Geometry2D.intersect_polygons(quad, band):
			var cols := PackedColorArray()
			for p in part:
				var t := clampf((p - p0).dot(n), 0.0, 1.0)
				cols.append(stops[0][1].lerp(stops[1][1], t / 0.18) if t < 0.18 else stops[1][1].lerp(stops[2][1], (t - 0.18) / 0.82))
			ci.draw_polygon(part, cols)


func _draw_horde_glow(ci: CanvasItem) -> void:
	if horde == null:
		return
	var h: Dictionary = horde
	# Fire-glow along the front ('lighter').
	for f in h.fires:
		var p := horde_at(h.front - f.t, f.s)
		var x := Iso.iso_x(p.x, p.y)
		var y := Iso.iso_y(p.x, p.y)
		var r: float = 70 + 18 * sin(time * 3 + f.k * 9)
		var pts := WD.ellipse(x, y, r, r, 0.0, 40)
		var uv := PackedVector2Array()
		for q in pts:
			uv.append((q - Vector2(x, y)) / r)
		pts.append(Vector2(x, y))
		uv.append(Vector2.ZERO)
		# Fan around the centre (last vertex) so UVs interpolate radially.
		var idx := PackedInt32Array()
		for i in 40:
			idx.append_array([40, i, (i + 1) % 40])
		var cols := PackedColorArray()
		cols.resize(41)
		cols.fill(Color(4.0 / r, 0, 0, 1))
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols, uv)


func _draw_horde_bands(ci: CanvasItem) -> void:
	if horde == null:
		return
	var h: Dictionary = horde
	# The warbands, dark against the smoke, drifting toward Brannsted.
	if not h.has("sorted"):
		h["sorted"] = JS.sort(h.bands.duplicate(), func(p, q): return q.t - p.t)
	var vr := _view_rect(260.0)
	for bd in h.sorted:
		var drift := sin(time * 0.4 + bd.s) * 0.004
		for f in bd.figs:
			var p := horde_at(h.front - bd.t + f.a + drift, bd.s + f.b)
			var x := Iso.iso_x(p.x, p.y)
			var y := Iso.iso_y(p.x, p.y) + sin(time * 6 + f.b * 5) * 0.8
			if not vr.has_point(Vector2(x, y)):
				continue
			if f.banner:
				Assets.draw_sprite(ci, Assets.sprite("war_banner", f.v), x, y, false, 0.55, Color(1, 1, 1, 0.95))
				continue
			var s := Assets.sprite(f.key, f.v)
			Assets.draw_sprite(ci, s, x, y, f.flip, 0.46, Color(1, 1, 1, 0.95))
			Assets.draw_silhouette(ci, s, x, y, f.flip, 0.46, 0.4)


func _draw_labels(ci: CanvasItem) -> void:
	var ex: Variant = _ex()
	if ex == null:
		return
	var z: float = cam.zoom
	for n in ex.nodes:
		var view := node_view(n)
		if view.type == "unknown":
			continue
		var x := Iso.iso_x(n.tx, n.ty)
		var y := Iso.iso_y(n.tx, n.ty) + 34
		var size := 15.0 / maxf(0.4, z)
		var label: String = view.title
		var wdt := WD.text_width(label, size * z) / z + 18.0 / z
		ci.draw_rect(Rect2(x - wdt / 2, y - size, wdt, size * 1.45), Color(40 / 255.0, 28 / 255.0, 16 / 255.0, 0.78))
		WD.draw_text(ci, x, y + size * 0.15, label, size, Color8(0xff, 0xd7, 0x6a) if n.id == ex.current else Color8(0xf2, 0xe8, 0xcc), z)
