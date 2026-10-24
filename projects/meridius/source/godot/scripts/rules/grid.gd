## Grid helpers for the battle map, a port of src/battle/grid.ts.
##
## Points are `{"x": int, "y": int}` dictionaries; a tile key is `y * 1000 + x`.
## Use through `const Grid = preload("res://scripts/rules/grid.gd")`.
## Static functions only: safe to call from a worker thread.
extends RefCounted

const JS = preload("res://scripts/core/js.gd")
const DB = preload("res://scripts/data/db.gd")

const DIRS: Array = [
	{"x": 1, "y": 0},
	{"x": 0, "y": 1},
	{"x": -1, "y": 0},
	{"x": 0, "y": -1},
]
## DIRS as plain coordinate tables (hot loops).
const DX: Array[int] = [1, 0, -1, 0]
const DY: Array[int] = [0, 1, 0, -1]


static func tile_at(map: Dictionary, x: int, y: int) -> Variant:
	if x < 0 or y < 0 or x >= map.w or y >= map.h:
		return null
	return map.tiles[y * map.w + x]


static func in_bounds(map: Dictionary, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < map.w and y < map.h


static func key(x: int, y: int) -> int:
	return y * 1000 + x


static func unkey(k: int) -> Dictionary:
	# JS: { x: k % 1000, y: Math.floor(k / 1000) } (also right for keys of off-field points).
	return {"x": k % 1000, "y": floori(k / 1000.0)}


static func manhattan(a: Dictionary, b: Dictionary) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Math.hypot exactly as V8 computes it (normalised by the larger value, then
## sqrt * max). It can differ by one ulp from sqrt(x*x + y*y), which would
## change AI scores and break parity with the original.
static func hypot(x: float, y: float) -> float:
	var ax := absf(x)
	var ay := absf(y)
	var m := ax if ax > ay else ay
	if m == 0.0:
		return 0.0
	if is_inf(m):
		return INF
	var a := ax / m
	var b := ay / m
	return sqrt(a * a + b * b) * m


static func dist(a: Dictionary, b: Dictionary) -> float:
	return hypot(float(a.x) - float(b.x), float(a.y) - float(b.y))


## Facing (0..3) from one point toward another (points may be fractional).
static func dir_to(from: Dictionary, to: Dictionary) -> int:
	var dx: float = float(to.x) - float(from.x)
	var dy: float = float(to.y) - float(from.y)
	if absf(dx) >= absf(dy):
		return 0 if dx >= 0 else 2
	return 1 if dy >= 0 else 3


static func tile_passable(map: Dictionary, x: int, y: int) -> bool:
	var t: Variant = tile_at(map, x, y)
	if t == null:
		return false
	if not DB.TERRAIN[t.terrain].passable:
		return false
	var p: Variant = t.get("prop")
	if p and DB.PROPS[p].blocksMove:
		return false
	return true


static func move_cost(map: Dictionary, x: int, y: int) -> int:
	var t: Dictionary = tile_at(map, x, y)
	return DB.TERRAIN[t.terrain].moveCost


## Can a unit step between two adjacent tiles given heights?
static func can_step(map: Dictionary, a: Dictionary, b: Dictionary) -> bool:
	var ta: Variant = tile_at(map, a.x, a.y)
	var tb: Variant = tile_at(map, b.x, b.y)
	if ta == null or tb == null:
		return false
	return absi(ta.h - tb.h) <= 1


## The squad standing (active or routing) on (x, y), or null.
static func unit_at(units: Array, x: int, y: int) -> Variant:
	for u in units:
		if u.x == x and u.y == y and (u.status == "active" or u.status == "routing"):
			return u
	return null


static func neighbors(map: Dictionary, p: Dictionary) -> Array:
	var out: Array = []
	for d in 4:
		var nx: int = p.x + DX[d]
		var ny: int = p.y + DY[d]
		if in_bounds(map, nx, ny):
			out.append({"x": nx, "y": ny})
	return out


static func is_edge(map: Dictionary, p: Dictionary) -> bool:
	return p.x == 0 or p.y == 0 or p.x == map.w - 1 or p.y == map.h - 1


## Line of sight between tile centres. Returns `{blocked, partial, tiles}`:
## blocked, the number of partial obstructions crossed, and the tiles crossed
## (excluding endpoints).
static func line_of_sight(map: Dictionary, a: Dictionary, b: Dictionary) -> Dictionary:
	var ta: Dictionary = tile_at(map, a.x, a.y)
	var tb: Dictionary = tile_at(map, b.x, b.y)
	var ha: float = ta.h + 0.9
	var hb: float = tb.h + 0.6
	var ax: int = a.x
	var ay: int = a.y
	var bx: int = b.x
	var by: int = b.y
	var steps: int = maxi(absi(bx - ax), absi(by - ay)) * 3
	var seen := {}
	var tiles: Array = []
	var partial := 0
	var foliage := 0.0
	for i in range(1, steps):
		var f: float = float(i) / steps
		var fx: float = ax + (bx - ax) * f
		var fy: float = ay + (by - ay) * f
		var x: int = JS.rnd(fx)
		var y: int = JS.rnd(fy)
		if (x == ax and y == ay) or (x == bx and y == by):
			continue
		var k := key(x, y)
		if seen.has(k):
			continue
		seen[k] = true
		var t: Variant = tile_at(map, x, y)
		if t == null:
			continue
		tiles.append({"x": x, "y": y})
		var line_h: float = ha + (hb - ha) * f
		if t.h > line_h:
			return {"blocked": true, "partial": partial, "tiles": tiles}
		var prop: Variant = t.get("prop")
		if prop:
			var p: Dictionary = DB.PROPS[prop]
			if p.los == 2:
				return {"blocked": true, "partial": partial, "tiles": tiles}
			if p.los == 1:
				partial += 1
		var lb: float = DB.TERRAIN[t.terrain].losBlock
		foliage += lb
		if foliage >= 1:
			return {"blocked": true, "partial": partial, "tiles": tiles}
		if lb > 0:
			partial += 1
	return {"blocked": false, "partial": partial, "tiles": tiles}
