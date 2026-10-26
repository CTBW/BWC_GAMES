## The 3D battle's field (Godot only): one of the 3D battlefields
## (prototypes/battlefields3d bf_field.gd: the relief ground in its season, the
## painted woods, houses and farm things, the grass and the water) with what the
## 3D units need to cross it, as the 3D sandbox's field3d.gd gives its
## training ground:
##   - which tiles a man can stand on (`walkable`): as in the rules, not the
##     impassable terrain nor a tile with a thing on it (a tree, a bush, a
##     rock, a house, a cart, the farm things: Battlefields.solid);
##   - walking routes (`path_to`: A* over the tiles, eight ways, no corner
##     cutting, no bank steeper than a figure climbs, then pulled straight);
##   - tree crowns that fade while a figure stands behind them
##     (`set_card_faded`, each card's `half_w` and `top` in metres).
## World axes: x = grid x, z = grid y; a tile is `tile_m` metres.
extends "res://prototypes/battlefields3d/scripts/bf_field.gd"

const DB = preload("res://scripts/data/db.gd")
const Battlefields = preload("res://scripts/rules/battlefields.gd")

## How far a faded crown shows (the sandbox's CROWN_FADE).
const CROWN_FADE := 0.42
## The highest step between two tiles' surfaces a figure climbs (levels).
const STEP := 1.25

var _blocked := {}
## A faded copy of each card material, kept in step with the shared inputs.
var _faded_mats := {}


func build(field_id: String, tile: float, level: float, elev: float, px_per_m: float) -> void:
	super.build(field_id, tile, level, elev, px_per_m)
	_block()


## The field's map and relief only, without the ground, woods and bakes (tests).
func lay_out(field_id: String, tile: float, level: float) -> void:
	tile_m = tile
	level_m = level
	data = Fields.make(field_id)
	map = data.map
	_outer = data.outer
	season = data.season
	relief = Relief.new(W, H, BORDER, map.tiles + _outer, data.seed)
	_block()


func _block() -> void:
	Battlefields.solid(data)
	_blocked.clear()
	for t in map.tiles:
		var prop := String(t.get("prop", ""))
		var ter: Dictionary = DB.TERRAIN.get(t.terrain, {})
		var blocks: bool = prop != "" and DB.PROPS.get(prop, {}).get("blocksMove", true)
		if not ter.get("passable", true) or blocks:
			_blocked[Vector2i(t.x, t.y)] = true


func walkable(t: Vector2i) -> bool:
	return in_field(t) and not _blocked.has(t)


## A walking route from a world point to a tile, round trees, rocks, houses and
## water and over no bank steeper than a figure climbs: A* over the tiles (eight
## ways, no corner cutting), then pulled straight wherever the ground between
## allows. Empty when there is no way.
func path_to(from: Vector3, goal: Vector2i) -> Array:
	var start := tile_of(from)
	if not in_field(goal):
		return []
	if not walkable(goal):
		goal = _nearest_walkable(goal)
	if not walkable(start):
		start = _nearest_walkable(start)
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
			var c: float = cost[cur] + Vector2(d).length() * float(DB.TERRAIN.get(t.terrain, {}).get("moveCost", 1))
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
	return absf(float(tile(a.x, a.y).surface_h) - float(tile(b.x, b.y).surface_h)) < STEP


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


# --- Crowns that fade ---------------------------------------------------------------

## Each card also keeps its painting's half width and its height above the
## foot (metres on screen), for the crown fade.
func _card(parent: Node3D, e: Dictionary, at: Vector2, size: float, kind: String, key: String, look := {}) -> Dictionary:
	var card := super._card(parent, e, at, size, kind, key, look)
	if card.is_empty():
		return card
	var tex: Texture2D = load(e.file)
	var region := Rect2(0, 0, float(e.get("w", tex.get_width())), float(e.get("h", tex.get_height())))
	if e.has("region"):
		var r: Array = e.region
		region = Rect2(r[0], r[1], r[2], r[3])
	var ay := float(e.ay) + (region.position.y if e.has("region") else 0.0)
	var m_px: float = float(e.scale) * size / ppu
	card["half_w"] = region.size.x * 0.5 * m_px
	card["top"] = (ay - region.position.y) * m_px
	card["faded"] = false
	card["mat"] = card.node.material_override
	return card


## Fades a tree's crown while a figure stands behind it, as the battle does.
func set_card_faded(card: Dictionary, on: bool) -> void:
	if card.get("faded", false) == on:
		return
	card.faded = on
	var m: ShaderMaterial = card.mat
	if on:
		if not _faded_mats.has(m):
			var f: ShaderMaterial = m.duplicate()
			f.set_shader_parameter("fade", CROWN_FADE)
			_faded_mats[m] = f
		card.node.material_override = _faded_mats[m]
	else:
		card.node.material_override = m


func set_shared(param: String, value: Variant) -> void:
	super.set_shared(param, value)
	for f in _faded_mats.values():
		f.set_shader_parameter(param, value)
