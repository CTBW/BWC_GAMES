## Port of src/battle/mapgen.ts: battle maps from templates and seeds.
##
## Small fields are generated from scatter rules; the large grounds of a last
## stand are drawn by hand (`layout` in data/maps.json) and only their details
## vary. A BattleMap is a Dictionary with the original keys (id, name, w, h,
## tiles, playerDeploy, enemyDeploy, biome, seed, border, outer, scale, entries,
## approaches, zone, zoneName, transposed, outerGround). Tiles are
## {x, y, h, terrain, v, prop?}; a tile without a prop has no "prop" key.
## Use through `const MapGen = preload("res://scripts/rules/mapgen.gd")`.
extends RefCounted

const JS = preload("res://scripts/core/js.gd")
const Rng = preload("res://scripts/core/rng.gd")
const DB = preload("res://scripts/data/db.gd")
const Grid = preload("res://scripts/rules/grid.gd")

## What each character of a hand-drawn layout stands for.
const LEGEND := {
	".": {"terrain": "grass"},
	",": {"terrain": "dirt"},
	":": {"terrain": "mud"},
	"~": {"terrain": "water"},
	"=": {"terrain": "bridge"},
	"_": {"terrain": "shallows"},
	"T": {"terrain": "forest", "prop": "tree"},
	"B": {"prop": "bush"},
	"R": {"prop": "rock_large"},
	"r": {"prop": "rock_small"},
	"S": {"prop": "stump"},
	"#": {"terrain": "dirt", "prop": "palisade"},
	"G": {"terrain": "stone", "prop": "gate"},
	"|": {"prop": "stakes"},
	"W": {"terrain": "stone", "prop": "wall_ruin"},
	"X": {"terrain": "stone", "prop": "wall_high"},
	"F": {"prop": "fence"},
	"c": {"prop": "crates"},
	"k": {"prop": "cart"},
	"h": {"prop": "haystack"},
	"o": {"terrain": "stone", "prop": "well"},
	"u": {"terrain": "rubble"},
	"s": {"terrain": "stone"},
	"t": {"terrain": "brush"},
}

## Props drawn along one axis: [running along x, running along y].
const AXIS := {
	"palisade": ["palisade", "palisade_y"],
	"fence": ["fence", "fence_y"],
	"wall_ruin": ["wall_ruin", "wall_ruin_y"],
	"gate": ["gate", "gate_y"],
	"stakes": ["stakes", "stakes_y"],
}

## Transposing a layout (x <-> y) swaps these edges.
const TRANSPOSED := {"n": "w", "w": "n", "e": "s", "s": "e"}

## Outward step beyond each edge.
const OUTWARD := {"n": {"x": 0, "y": -1}, "w": {"x": -1, "y": 0}, "e": {"x": 1, "y": 0}, "s": {"x": 0, "y": 1}}

const _STEPS := [{"x": 1, "y": 0}, {"x": 0, "y": 1}, {"x": -1, "y": 0}, {"x": 0, "y": -1}]


static func _no_prop(t: Dictionary) -> bool:
	var p: Variant = t.get("prop")
	return p == null or p == ""


## Tiles along an edge, from `a` to `b` along it.
static func _edge_tiles(w: int, h: int, edge: String, a: int, b: int) -> Array:
	var out: Array = []
	for i in range(a, b + 1):
		if edge == "n":
			out.append({"x": i, "y": 0})
		elif edge == "s":
			out.append({"x": i, "y": h - 1})
		elif edge == "w":
			out.append({"x": 0, "y": i})
		else:
			out.append({"x": w - 1, "y": i})
	return out


## Entry tiles of a stretch of edge, those nearest its middle first.
static func _entry_list(map: Dictionary, edge: String, a: int, b: int) -> Array:
	var mid := (a + b) / 2.0
	var along_x := edge == "n" or edge == "s"
	var list: Array = _edge_tiles(map.w, map.h, edge, a, b).filter(func(p: Dictionary) -> bool: return Grid.tile_passable(map, p.x, p.y))
	return JS.sort(list, func(p: Dictionary, q: Dictionary) -> float:
		var ip: int = p.x if along_x else p.y
		var iq: int = q.x if along_x else q.y
		return absf(ip - mid) - absf(iq - mid)
	)


## Options: {ambush?: bool, approaches?: Array of edges ("n"|"e"|"s"|"w")}.
static func generate_map(template_id: String, seed: int, opts: Dictionary = {}) -> Dictionary:
	var tpl: Dictionary = DB.BATTLE_MAPS[template_id]
	if tpl.get("layout") != null:
		return _generate_authored(tpl, seed, opts)
	var rng := Rng.new(seed)
	var w: int = tpl.w
	var h: int = tpl.h
	var tiles: Array = []
	for y in h:
		for x in w:
			tiles.append({"x": x, "y": y, "h": 0, "terrain": "grass", "v": rng.rint(0, 9999)})
	var map := {
		"id": tpl.id,
		"name": tpl.name,
		"w": w,
		"h": h,
		"tiles": tiles,
		"playerDeploy": [],
		"enemyDeploy": [],
		"biome": tpl.biome,
		"seed": seed,
		"border": 7,
		"outer": [],
	}

	# Deployment zones first so features can avoid them.
	var mid: int = floori(h / 2.0)
	if opts.get("ambush"):
		for y in range(mid - 1, mid + 2):
			for x in range(4, w - 4):
				map.playerDeploy.append({"x": x, "y": y})
		for x in range(2, w - 2):
			map.enemyDeploy.append_array([{"x": x, "y": 0}, {"x": x, "y": 1}, {"x": x, "y": h - 1}, {"x": x, "y": h - 2}])
	else:
		for y in range(h - 3, h):
			for x in range(3, w - 3):
				map.playerDeploy.append({"x": x, "y": y})
		for y in 3:
			for x in range(2, w - 2):
				map.enemyDeploy.append({"x": x, "y": y})
	var reserved := {}
	for p in map.playerDeploy + map.enemyDeploy:
		reserved[Grid.key(p.x, p.y)] = true
	var g := _Gen.new(map, rng, reserved)

	# River with a bridge and a ford, crossing the field between the armies.
	if tpl.get("river"):
		var ry: int = mid + rng.rint(-1, 0)
		var bridge_x := rng.rint(3, 5)
		var ford_x := rng.rint(w - 6, w - 4)
		for x in w:
			if x > 0 and rng.chance(0.3):
				ry = maxi(mid - 2, mini(mid + 1, ry + int(rng.pick([-1, 1]))))
			for yy in [ry, ry + 1]:
				var t: Variant = g.T(x, yy)
				if t == null:
					continue
				reserved.erase(Grid.key(x, yy))
				if absi(x - bridge_x) <= 0:
					t.terrain = "bridge"
				elif absi(x - ford_x) <= 1:
					t.terrain = "shallows"
				else:
					t.terrain = "water"
				t.erase("prop")

	# Hills: raised plateaus away from the deployment rows.
	var hills := rng.rint(tpl.hills[0], tpl.hills[1])
	for i in hills:
		var cx := rng.rint(2, w - 3)
		var cy := rng.rint(3, h - 4)
		var rx := rng.frange(1.6, 3.2)
		var ry2 := rng.frange(1.4, 2.6)
		var peak := 2 if rng.chance(0.35) else 1
		for t in tiles:
			if t.terrain == "water" or t.terrain == "bridge" or t.terrain == "shallows":
				continue
			var ax: float = (t.x - cx) / rx
			var ay: float = (t.y - cy) / ry2
			var d := ax * ax + ay * ay
			if d < 1:
				t.h = maxi(t.h, peak if d < 0.35 else 1)
	# Smooth cliffs so most of the field stays walkable (allow a few 2-steps).
	for _pass in 2:
		for t in tiles:
			for n in Grid.neighbors(map, t):
				var nt: Dictionary = g.T(n.x, n.y)
				if t.h - nt.h > 1 and rng.chance(0.6):
					t.h = nt.h + 1

	# Dirt patches (visual) and thickets.
	g.scatter(rng.rint(tpl.dirt[0], tpl.dirt[1]), g.place_dirt, 0)
	g.scatter(rng.rint(tpl.brush[0], tpl.brush[1]), g.place_brush)
	# Tree clumps with undergrowth.
	g.scatter(rng.rint(tpl.treeClumps[0], tpl.treeClumps[1]), g.place_trees)
	# Rock outcrops.
	g.scatter(rng.rint(tpl.rockClumps[0], tpl.rockClumps[1]), g.place_rocks)
	g.scatter(rng.rint(tpl.bushes[0], tpl.bushes[1]), g.place_bush)
	# Fences: short straight runs.
	g.scatter(rng.rint(tpl.fences[0], tpl.fences[1]), g.place_fence, 2)
	# Ruined walls with a gap, and a broken tower.
	for r in int(tpl.ruins):
		g.scatter(1, g.place_ruin, 2)

	# The warband's camp on the enemy side.
	if tpl.get("camp"):
		var cy := rng.rint(2, 3)
		var tent_xs: Array = [3, 6, 9, 12].filter(func(x: int) -> bool: return x < w - 1)
		for tx in tent_xs:
			var y: int = cy + rng.rint(-1, 1)
			var tt: Variant = g.T(tx, y)
			if tt != null and _no_prop(tt):
				tt.prop = "tent" if rng.chance(0.75) else "crates"
				reserved.erase(Grid.key(tx, y))
				map.enemyDeploy = map.enemyDeploy.filter(func(p: Dictionary) -> bool: return not (p.x == tx and p.y == y))
		var ft: Dictionary = g.T(floori(w / 2.0), cy + 2)
		ft.prop = "campfire"
		ft.terrain = "dirt"
		for t in tiles:
			if t.y <= cy + 3 and _no_prop(t) and rng.chance(0.55) and t.terrain == "grass":
				t.terrain = "dirt"
		for tx in [1, w - 2]:
			var t: Variant = g.T(tx, cy + 3)
			if t != null and _no_prop(t):
				t.prop = "totem"
		map.enemyDeploy = map.enemyDeploy.filter(func(p: Dictionary) -> bool: return _no_prop(g.T(p.x, p.y)))

	var usable := func(p: Dictionary) -> bool: return Grid.tile_passable(map, p.x, p.y)
	map.playerDeploy = map.playerDeploy.filter(usable)
	map.enemyDeploy = map.enemyDeploy.filter(usable)
	_ensure_connected(map, rng)
	# Reinforcements enter along the far edge and down the flanks, away from the company.
	map.scale = "small"
	map.entries = {
		"n": _entry_list(map, "n", 1, w - 2),
		"w": _entry_list(map, "w", 1, floori(h * 0.55)),
		"e": _entry_list(map, "e", 1, floori(h * 0.55)),
	}
	if opts.get("ambush"):
		map.entries.s = _entry_list(map, "s", 2, w - 3)
	var appr: Variant = opts.get("approaches")
	map.approaches = appr.duplicate() if appr != null else ["n"]
	_build_outer_ring(map, rng)
	return map


## The scatter rules of a generated field, sharing its map, RNG and reserved set.
class _Gen:
	var map: Dictionary
	var rng: RefCounted
	var reserved: Dictionary
	var tiles: Array
	var w: int
	var h: int

	func _init(m: Dictionary, r: RefCounted, res: Dictionary) -> void:
		map = m
		rng = r
		reserved = res
		tiles = m.tiles
		w = m.w
		h = m.h

	func T(x: int, y: int) -> Variant:
		if x < 0 or y < 0 or x >= w or y >= h:
			return null
		return tiles[y * w + x]

	func is_reserved(x: int, y: int) -> bool:
		return reserved.has(y * 1000 + x)

	func is_free(x: int, y: int) -> bool:
		var t: Variant = T(x, y)
		if t == null:
			return false
		var p: Variant = t.get("prop")
		return (p == null or p == "") and not is_reserved(x, y) and t.terrain != "water" and t.terrain != "bridge" and t.terrain != "shallows"

	func scatter(count: int, place: Callable, margin: int = 1) -> void:
		for i in count:
			for tries in 30:
				var x: int = rng.rint(margin, w - 1 - margin)
				var y: int = rng.rint(margin, h - 1 - margin)
				if is_free(x, y):
					place.call(x, y)
					break

	func place_dirt(x: int, y: int) -> void:
		var r: float = rng.frange(1, 2.4)
		for t in tiles:
			if Grid.hypot(t.x - x, t.y - y) < r and t.terrain == "grass" and rng.chance(0.8):
				t.terrain = "dirt"

	func place_brush(x: int, y: int) -> void:
		for t in tiles:
			if Grid.hypot(t.x - x, t.y - y) < 1.3 and t.terrain == "grass" and not is_reserved(t.x, t.y):
				t.terrain = "brush"

	func place_trees(x: int, y: int) -> void:
		var n: int = rng.rint(2, 4)
		var px := x
		var py := y
		for i in n:
			if is_free(px, py):
				var t: Dictionary = T(px, py)
				t.prop = "tree_pine" if rng.chance(0.55) else "tree_oak"
				t.terrain = "forest"
			var d: Dictionary = rng.pick(_STEPS)
			px += d.x
			py += d.y
		for t in tiles:
			var p: Variant = t.get("prop")
			if Grid.hypot(t.x - x, t.y - y) < 1.8 and (p == null or p == "") and t.terrain == "grass" and not is_reserved(t.x, t.y) and rng.chance(0.5):
				t.terrain = "brush"

	func place_rocks(x: int, y: int) -> void:
		T(x, y).prop = "rock_large"
		for n in Grid.neighbors(map, {"x": x, "y": y}):
			if is_free(n.x, n.y) and rng.chance(0.35):
				T(n.x, n.y).prop = "rock_small"

	func place_bush(x: int, y: int) -> void:
		T(x, y).prop = "bush" if rng.chance(0.8) else "stump"

	func place_fence(x: int, y: int) -> void:
		var horiz: bool = rng.chance(0.5)
		var len: int = rng.rint(2, 3)
		for i in len:
			var fx := x + (i if horiz else 0)
			var fy := y + (0 if horiz else i)
			if is_free(fx, fy):
				T(fx, fy).prop = "fence" if horiz else "fence_y"

	func place_ruin(x: int, y: int) -> void:
		var horiz: bool = rng.chance(0.5)
		var len: int = rng.rint(3, 4)
		var gap: int = rng.rint(1, len - 2)
		for i in len:
			if i == gap:
				continue
			var fx := x + (i if horiz else 0)
			var fy := y + (0 if horiz else i)
			if is_free(fx, fy):
				var t: Dictionary = T(fx, fy)
				if i == 0 and rng.chance(0.5):
					t.prop = "wall_high"
				else:
					t.prop = "wall_ruin" if horiz else "wall_ruin_y"
				t.terrain = "stone"
		for t in tiles:
			var p: Variant = t.get("prop")
			if Grid.hypot(t.x - x, t.y - y) < 2.2 and (p == null or p == "") and t.terrain == "grass" and rng.chance(0.4):
				t.terrain = "stone"


## A hand-drawn last-stand field. Half of the seeds transpose the layout
## (x <-> y), which mirrors it across the screen's vertical axis; the details
## (tree kinds, bushes, prop looks) vary with every seed.
static func _generate_authored(tpl: Dictionary, seed: int, opts: Dictionary) -> Dictionary:
	var L: Dictionary = tpl.layout
	var rng := Rng.new(seed)
	var flip := rng.chance(0.5)
	var rows: Array = L.rows
	var heights: Array = L.heights
	var H0: int = rows.size()
	var W0: int = String(rows[0]).length()
	var w: int = H0 if flip else W0
	var h: int = W0 if flip else H0
	var tiles: Array = []
	for y in h:
		for x in w:
			var lx: int = y if flip else x
			var ly: int = x if flip else y
			var ch: String = String(rows[ly])[lx]
			var lg: Dictionary = LEGEND.get(ch, LEGEND["."])
			var hh := 0
			if ly < heights.size() and lx < String(heights[ly]).length():
				var hc: String = String(heights[ly])[lx]
				hh = int(hc) if hc.is_valid_int() else 0
			var t := {"x": x, "y": y, "h": hh, "terrain": lg.get("terrain", "grass"), "v": rng.rint(0, 9999)}
			var lp: Variant = lg.get("prop")
			if lp == "tree":
				t.prop = "tree_pine" if rng.chance(0.55) else "tree_oak"
			elif lp != null:
				t.prop = lp
			tiles.append(t)
	var map := {
		"id": tpl.id,
		"name": tpl.name,
		"w": w,
		"h": h,
		"tiles": tiles,
		"playerDeploy": [],
		"enemyDeploy": [],
		"biome": tpl.biome,
		"seed": seed,
		"border": 8,
		"outer": [],
		"scale": "large",
	}
	var T := func(x: int, y: int) -> Variant: return Grid.tile_at(map, x, y)
	# Walls, fences and gates run along whichever axis their neighbours do.
	for t in tiles:
		var tp: Variant = t.get("prop")
		if tp == null or not AXIS.has(tp):
			continue
		var grp: String = tp
		var along_x := _runs(map, t.x - 1, t.y, grp) or _runs(map, t.x + 1, t.y, grp) or _terrain_is(map, t.x - 1, t.y, "rubble") or _terrain_is(map, t.x + 1, t.y, "rubble")
		var along_y := _runs(map, t.x, t.y - 1, grp) or _runs(map, t.x, t.y + 1, grp) or _terrain_is(map, t.x, t.y - 1, "rubble") or _terrain_is(map, t.x, t.y + 1, "rubble")
		t.prop = AXIS[grp][0] if along_x or not along_y else AXIS[grp][1]
	var rect := func(r: Array) -> Array:
		var out: Array = []
		for ly in range(r[1], r[3] + 1):
			for lx in range(r[0], r[2] + 1):
				out.append({"x": ly, "y": lx} if flip else {"x": lx, "y": ly})
		return out
	var open := func(p: Dictionary) -> bool: return Grid.tile_passable(map, p.x, p.y) and _no_prop(T.call(p.x, p.y))
	var pd: Array = []
	for r in L.deploy:
		pd.append_array(rect.call(r))
	map.playerDeploy = pd.filter(open)
	var ed: Array = []
	for r in L.enemy:
		ed.append_array(rect.call(r))
	map.enemyDeploy = ed.filter(open)
	if L.get("zone") != null:
		map.zone = rect.call(L.zone).filter(func(p: Dictionary) -> bool: return Grid.tile_passable(map, p.x, p.y))
		if L.get("zoneName") != null:
			map.zoneName = L.zoneName
	# A few bushes and stumps in the open fields, never on the marked ground.
	var marked := {}
	for p in map.playerDeploy + map.enemyDeploy + JS.get_or(map, "zone", []):
		marked[Grid.key(p.x, p.y)] = true
	var extras := rng.rint(tpl.bushes[0], tpl.bushes[1])
	var i := 0
	var tries := 0
	while i < extras and tries < 200:
		var tx := rng.rint(1, w - 2)
		var ty := rng.rint(1, h - 2)
		var t: Dictionary = T.call(tx, ty)
		tries += 1
		if not _no_prop(t) or t.terrain != "grass" or marked.has(Grid.key(t.x, t.y)):
			continue
		var crowded := false
		for n in Grid.neighbors(map, t):
			if not _no_prop(T.call(n.x, n.y)):
				crowded = true
				break
		if crowded:
			continue
		t.prop = "bush" if rng.chance(0.75) else "stump"
		i += 1
	map.entries = {}
	for e in L.entries:
		var span: Array = L.entries[e]
		var ge: String = TRANSPOSED[e] if flip else e
		map.entries[ge] = _entry_list(map, ge, span[0], span[1])
	map.transposed = flip
	var appr: Variant = opts.get("approaches")
	if appr == null:
		var edges: Variant = tpl.get("edges")
		appr = [edges.main if edges != null else "n"]
	map.approaches = appr.map(func(e: String) -> String: return TRANSPOSED[e] if flip else e)
	_build_outer_ring(map, rng)
	return map


static func _terrain_is(map: Dictionary, x: int, y: int, terrain: String) -> bool:
	var t: Variant = Grid.tile_at(map, x, y)
	return t != null and t.terrain == terrain


static func _axis_base(p: String) -> Variant:
	for k in AXIS:
		if AXIS[k].has(p):
			return k
	return null


static func _runs(map: Dictionary, x: int, y: int, group: String) -> bool:
	var t: Variant = Grid.tile_at(map, x, y)
	if t == null:
		return false
	var p: Variant = t.get("prop")
	if p == null or p == "":
		return false
	var base: Variant = _axis_base(p)
	return base == group or (group == "palisade" and (p == "wall_high" or p == "gate" or p == "gate_y")) or (group == "gate" and (base == "palisade" or p == "wall_high"))


## Remove props until every enemy deploy tile is reachable from the player zone.
static func _ensure_connected(map: Dictionary, rng: RefCounted) -> void:
	for guard in 40:
		var start: Variant = null
		for p in map.playerDeploy:
			if Grid.tile_passable(map, p.x, p.y):
				start = p
				break
		if start == null:
			push_error("ensureConnected: no passable player deploy tile")
			return
		var seen := {Grid.key(start.x, start.y): true}
		var q: Array = [start]
		var qi := 0
		while qi < q.size():
			var c: Dictionary = q[qi]
			qi += 1
			for n in Grid.neighbors(map, c):
				var k: int = Grid.key(n.x, n.y)
				if seen.has(k) or not Grid.tile_passable(map, n.x, n.y) or not Grid.can_step(map, c, n):
					continue
				seen[k] = true
				q.append(n)
		var target: Variant = null
		for p in map.enemyDeploy:
			if Grid.tile_passable(map, p.x, p.y) and not seen.has(Grid.key(p.x, p.y)):
				target = p
				break
		if target == null:
			for p in map.playerDeploy:
				if Grid.tile_passable(map, p.x, p.y) and not seen.has(Grid.key(p.x, p.y)):
					target = p
					break
		if target == null:
			return
		# Carve a straight-ish corridor from the target toward the start.
		var c := {"x": target.x, "y": target.y}
		while not seen.has(Grid.key(c.x, c.y)):
			var t: Dictionary = Grid.tile_at(map, c.x, c.y)
			if t.has("prop"):
				t.erase("prop")
			if t.terrain == "water":
				t.terrain = "shallows"
			var dx := signi(start.x - c.x)
			var dy := signi(start.y - c.y)
			var n: Dictionary
			if rng.chance(0.5) and dx != 0:
				n = {"x": c.x + dx, "y": c.y}
			elif dy != 0:
				n = {"x": c.x, "y": c.y + dy}
			else:
				n = {"x": c.x + dx, "y": c.y}
			var nt: Dictionary = Grid.tile_at(map, n.x, n.y)
			if absi(nt.h - t.h) > 1:
				nt.h = t.h + signi(nt.h - t.h)
			c = n


## [edge, lo, hi] of each approach with entries: the stretch beyond the edge
## where a coming wave masses (the entries' span plus a margin).
static func _approach_spans(map: Dictionary) -> Array:
	var out: Array = []
	var entries: Dictionary = JS.get_or(map, "entries", {})
	for e in JS.get_or(map, "approaches", []):
		var list: Variant = entries.get(e)
		if list == null or list.is_empty():
			continue
		var lo := 1 << 30
		var hi := -(1 << 30)
		for p in list:
			var v: int = p.x if e == "n" or e == "s" else p.y
			lo = mini(lo, v)
			hi = maxi(hi, v)
		out.append([e, lo - 1, hi + 1])
	return out


static func _in_spans(map: Dictionary, spans: Array, x: int, y: int) -> Variant:
	for s in spans:
		var e: String = s[0]
		var along := x if e == "n" or e == "s" else y
		if along < s[1] or along > s[2]:
			continue
		if e == "n" and y < 0:
			return e
		if e == "s" and y >= map.h:
			return e
		if e == "w" and x < 0:
			return e
		if e == "e" and x >= map.w:
			return e
	return null


## The stretch beyond an approach edge where a coming wave masses in view: as
## wide as the edge's entries (plus a margin) and as deep as the border.
## Returns the edge, or null.
static func in_approach(map: Dictionary, x: int, y: int) -> Variant:
	return _in_spans(map, _approach_spans(map), x, y)


## Dense decorative forest around the playable area (not part of the grid).
static func _build_outer_ring(map: Dictionary, rng: RefCounted) -> void:
	var b: int = map.border
	var w: int = map.w
	var h: int = map.h
	var spans := _approach_spans(map)
	var ground: Array = []
	var outer: Array = map.outer
	map.outerGround = ground
	for y in range(-b, h + b):
		for x in range(-b, w + b):
			if x >= 0 and y >= 0 and x < w and y < h:
				continue
			var d: int = maxi(maxi(-x, -y), maxi(x - (w - 1), y - (h - 1)))
			# Approaches: an open, trampled field where the horde masses, edged by brush.
			if _in_spans(map, spans, x, y) != null:
				ground.append({"x": x, "y": y, "terrain": "dirt" if rng.chance(0.55) else "grass"})
				if rng.chance(0.04):
					var p: String = rng.pick(["bush", "rock_small", "stump"])
					outer.append({"x": x, "y": y, "h": 0, "prop": p, "v": rng.rint(0, 9999)})
				continue
			# Keep the near-camera edges open so trees never hide the troops.
			var front := x >= w or y >= h
			if front and d <= 2:
				if rng.chance(0.18):
					var p: String = rng.pick(["bush", "rock_small", "bush"])
					outer.append({"x": x, "y": y, "h": 0, "prop": p, "v": rng.rint(0, 9999)})
				continue
			var density := 0.35 if d <= 1 else (0.6 if d <= 2 else 0.85)
			if not rng.chance(density):
				if rng.chance(0.25):
					var p: String = rng.pick(["bush", "rock_small", "bush"])
					outer.append({"x": x, "y": y, "h": 0, "prop": p, "v": rng.rint(0, 9999)})
				continue
			var prop: String
			if rng.chance(0.08):
				prop = "rock_large"
			elif rng.chance(0.6):
				prop = "tree_pine"
			else:
				prop = "tree_oak"
			outer.append({"x": x, "y": y, "h": 0, "prop": prop, "v": rng.rint(0, 9999)})


static func prop_blocks(prop: Variant = null) -> bool:
	return prop != null and prop != "" and DB.PROPS[prop].blocksMove
