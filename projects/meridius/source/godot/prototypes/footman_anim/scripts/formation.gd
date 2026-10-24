## Spacing and formation for the prototype squad, separate from animation.
##
## Everything here is on the ground plane in grid units (one tile = 1x1; screen
## px = (gx - gy) * 64, (gx + gy) * 32). A soldier is a body circle of radius
## BODY_R; his weapon is the blade of his current clip frame (the bake's
## Mixamo samples: hand to tip, metres, in his own fwd/right/up frame) turned
## to his facing. A blade sample below BODY_HEIGHT inside a neighbour's circle
## is an overlap; so is a pair of bodies closer than 2 * BODY_R.
##
## Resolution, in order: (1) slot spacing inside the tile is widened, up to
## what the tile allows, until the front rank's attack swept over its whole
## clip clears its neighbours; (2) lane rules: a rear-rank soldier attacks only
## through an open lane (a gap in the front rank wide enough for his body and
## blade), otherwise he holds guard; when a front-rank soldier falls, the man
## behind steps into the lane. The animation is never relied on to avoid
## anyone: the checks run on what is actually played.
extends RefCounted

const GRID_DIRS := [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]
## Ground scale for weapon samples (Mixamo metres per tile): chosen so the
## blade's measured reach (1.9 m) carries from the front rank to the next tile's centre.
const METERS_PER_TILE := 2.4
const BODY_R := 0.105
const BODY_HEIGHT := 1.85
## Slots: rank distance from the tile centre and the spacing between files.
const RANK := 0.25
const FILE := 0.41
## Feet stay inside the tile: |gx|, |gy| < TILE_LIMIT about the tile centre (the diamond on screen).
const TILE_LIMIT := 0.46


static func iso(g: Vector2) -> Vector2:
	return Vector2((g.x - g.y) * 64.0, (g.x + g.y) * 32.0)


static func from_iso(s: Vector2) -> Vector2:
	var a := s.x / 64.0
	var b := s.y / 32.0
	return Vector2((a + b) * 0.5, (b - a) * 0.5)


static func fwd(f: int) -> Vector2:
	return GRID_DIRS[posmod(f, 4)]


static func right(f: int) -> Vector2:
	var d: Vector2 = GRID_DIRS[posmod(f, 4)]
	return Vector2(-d.y, d.x)


## Slots for n soldiers facing f, two ranks (front first), files centred.
## Each slot: {g: grid offset from the tile centre, rank: 0 front / 1 rear, file}.
static func slots(n: int, f: int, file_gap: float = FILE) -> Array:
	var out := []
	var front := mini(n, 3) if n > 3 else n
	var rear := n - front
	for r in [0, 1]:
		var count := front if r == 0 else rear
		for i in count:
			var lat := (i - (count - 1) * 0.5) * file_gap
			var along := RANK if r == 0 else -RANK
			if n <= 3:
				along = 0.0
			var g := fwd(f) * along + right(f) * lat
			out.append({"g": g, "rank": r, "file": i, "lat": lat, "along": along})
	return out


static func inside_tile(g: Vector2) -> bool:
	return absf(g.x) < TILE_LIMIT and absf(g.y) < TILE_LIMIT


## Blade samples of a soldier now, as [ground point (grid), height (m)].
static func blade_now(soldier: Node2D) -> Array:
	var out := []
	var m: Dictionary = soldier.clip_meta(soldier.state)
	var blade: Array = m.get("blade_m", [])
	if blade.is_empty():
		return out
	var fi := clampi(int(soldier.rig.player.current_animation_position * 30.0), 0, blade.size() - 1)
	var g0: Vector2 = from_iso(soldier.position - soldier.get_meta("tile_origin", Vector2.ZERO))
	var F := fwd(soldier.facing)
	var R := right(soldier.facing)
	for s in blade[fi]:
		var off := (F * float(s[0]) + R * float(s[1])) / METERS_PER_TILE
		out.append([g0 + off, float(s[2])])
	return out


## Every overlap between squadmates now: [{a, b, kind, depth}].
static func overlaps(soldiers: Array, others: Array = []) -> Array:
	var res := []
	var all := soldiers.filter(func(s): return not s.dead)
	for i in all.size():
		var a: Node2D = all[i]
		var ga := from_iso(a.position - a.get_meta("tile_origin", Vector2.ZERO))
		for j in range(i + 1, all.size()):
			var b: Node2D = all[j]
			var gb := from_iso(b.position - b.get_meta("tile_origin", Vector2.ZERO))
			var dd := ga.distance_to(gb)
			if dd < BODY_R * 2.0 - 0.002:
				res.append({"a": a, "b": b, "kind": "body", "depth": BODY_R * 2.0 - dd})
		for j in all.size():
			if j == i:
				continue
			var b: Node2D = all[j]
			var gb := from_iso(b.position - b.get_meta("tile_origin", Vector2.ZERO))
			for s in blade_now(a):
				if s[1] < BODY_HEIGHT and (s[0] as Vector2).distance_to(gb) < BODY_R:
					res.append({"a": a, "b": b, "kind": "weapon", "depth": BODY_R - (s[0] as Vector2).distance_to(gb)})
					break
	return res


## Worst blade intrusion of a clip into a neighbour standing at grid offset
## `n` (in the attacker's fwd/right frame, grid units), over every frame.
static func clip_intrusion(blade: Array, n_fwd: float, n_right: float) -> float:
	var worst := 0.0
	for frame in blade:
		for s in frame:
			if float(s[2]) >= BODY_HEIGHT:
				continue
			var p := Vector2(float(s[0]), float(s[1])) / METERS_PER_TILE
			var d := p.distance_to(Vector2(n_fwd, n_right))
			worst = maxf(worst, BODY_R - d)
	return worst


## Resolve (1): the smallest file spacing at which the attack clears both
## neighbours in the rank, within the tile; returns {gap, clear}.
static func file_gap_for(blade: Array) -> Dictionary:
	var gap := FILE
	while gap <= 0.44:
		var worst := maxf(clip_intrusion(blade, 0.0, gap), clip_intrusion(blade, 0.0, -gap))
		if worst <= 0.0:
			return {"gap": gap, "clear": true}
		gap += 0.01
	return {"gap": 0.44, "clear": false}


## Resolve (2): lanes. A rear soldier may strike through the gap in front of
## him if the front slot of his file is empty, or if the two front men beside
## the gap stand far enough apart for his body and blade.
static func lane_open(front_alive: Array, file: int, gap: float, blade: Array) -> bool:
	if file < front_alive.size() and not front_alive[file]:
		return true
	return false
