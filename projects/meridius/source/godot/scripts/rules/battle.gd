## The battle rules, a port of src/battle/battle.ts (class Battle).
##
##   const Battle = preload("res://scripts/rules/battle.gd")
##   var b = Battle.new(setup)            # setup: BattleSetup dictionary
##   b.begin(Ai.run_enemy_ai)             # AI passed as a Callable(battle)
##   b.move(uid, x, y)                    # or b.move(uid, x, y, facing)
##   b.attack(uid, target_uid)            # or with an ability id
##   b.end_turn(Ai.run_enemy_ai)
##   for e in b.drain(): ...              # BattleEvent dictionaries {"t": "move", ...}
##
## State objects are the original's dictionaries with camelCase keys (see
## src/battle/types.ts): BattleUnit, BattleMap, BattleSetup, BattleEvent,
## AttackPreview `{chance, min, max, arc, mods, kill, moraleHit, legal, reason,
## soldiers, strikers}`, ReachInfo `{cost, prev, zoc}`, FacingOption
## `{facing, cost, zoc, path}`. Optional TS fields that are undefined are absent
## keys (a unit without a stance has no "stance" key). TS `Map<number, …>` and
## `Set<number>` are Dictionaries keyed by tile or state keys.
##
## Public members (snake_case of the TS fields):
##   map: Dictionary          the BattleMap (setup.map)
##   units: Array             BattleUnit dictionaries (setup.units, same array)
##   rng                      scripts/core/rng.gd instance seeded with setup.seed
##   turn: int                current turn (1-based)
##   phase: String            "deploy" | "player" | "enemy" | "over"
##   result: Variant          null or "victory" | "defeat" | "retreat"
##   events: Array            pending events (take them with drain())
##   setup: Dictionary        the BattleSetup
##   hits_taken: Dictionary   uid -> hits taken (armour wear)
##   move_records: Dictionary uid -> {x, y, facing, movedTiles, path, clean}
##   wave_state: Array        per wave: "pending" | "arrived" | "cancelled"
##   horn: String             "waiting" | "sounded" | "silent"
##   overrun: int             consecutive enemy turns ending with the held ground taken
##   objective: Dictionary    (read-only property) setup.objective or the default rout
##   waves: Array             (read-only property) setup.waves or []
##   ai_cache: Variant        per-turn field cache owned by scripts/rules/ai.gd
##
## Methods (TS name -> here): pendingWaves pending_waves, nextWave next_wave,
## company, unit, living, active, enemiesOf enemies_of, alliesOf allies_of,
## tile, moraleState morale_state, arcOf arc_of, isAdjacentEnemy
## is_adjacent_enemy, reachable, pathFrom path_from, pathTo path_to, zocTiles
## zoc_tiles, reachStates reach_states, reachableFull reachable_full,
## facingOptions facing_options, defaultFacing default_facing, moveOption
## move_option, facingTowardFoes facing_toward_foes, canMelee can_melee,
## shotRange shot_range, canShoot can_shoot, wouldShoot would_shoot, preview,
## targets, drain, log, changeMorale change_morale, deploySwap deploy_swap,
## strength, isOver is_over, begin, canAct can_act, move, canRedo can_redo,
## redoMove redo_move, walk, attack, useStance use_stance, shout, endUnit
## end_unit, endTurn end_turn, checkEnd check_end, retreat.
## Optional TS arguments are `null` when omitted (a facing of -1 also means none).
## Additions (no change in results): `preview_legal(a, t, opts)` = preview(...).legal
## without the rest; `reachable`/`reachable_full(u, budget, states)`,
## `move_option(u, x, y, facing, states)` and `move(uid, x, y, facing, states)`
## accept the squad's current `reach_states(u)` to skip a repeated search (the AI
## uses this; pass nothing otherwise). `log(text, tone)` is Battle.log; inside
## this class the rules call `_log` (GDScript's built-in log() shadows a bare call).
## The setup must hold ints for integral values (JS.normalize a parsed JSON setup).
## Rules never touch nodes or autoloads: a battle may run on a worker thread.
extends RefCounted

const JS = preload("res://scripts/core/js.gd")
const Rng = preload("res://scripts/core/rng.gd")
const DB = preload("res://scripts/data/db.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const Squad = preload("res://scripts/rules/squad.gd")
const Visibility = preload("res://scripts/rules/visibility.gd")

## In a rout battle, the enemy gives up at the end of this turn if no more help is coming.
const GIVE_UP_TURN := 14

## The step that carries a squad from beyond an edge onto the field: the way it faces on arrival.
const INWARD := {"n": 1, "w": 0, "e": 2, "s": 3}

const DEFAULT_OBJECTIVE := {"kind": "rout", "title": "Rout the enemy", "brief": "Destroy or drive off every enemy squad."}

## Chance that a fallen soldier was only wounded (plus 5% per level and the infirmary/bandage bonus).
const FALL_SURVIVAL_BASE := 0.45

const EDGE_NAME := {"n": "northern", "e": "eastern", "s": "southern", "w": "western"}


static func facing_toward(from: Dictionary, to: Dictionary) -> int:
	return Grid.dir_to(from, to)


var map: Dictionary
var units: Array
var rng
var turn := 1
var phase := "deploy"
var result: Variant = null
var events: Array = []
var setup: Dictionary
## Hits taken per unit (armour wear).
var hits_taken: Dictionary = {}
## This turn's player moves that can still be redone, by unit.
var move_records: Dictionary = {}
## What became of each wave of reinforcements.
var wave_state: Array = []
## Waves whose arrival has been announced.
var _wave_seen: Dictionary = {}
## The war horn: still to be sounded, sounded (its waves are coming), or silenced with its bearer.
var horn := "waiting"
## Consecutive enemy turns that ended with the held ground taken.
var overrun := 0
## Per-turn caches of the AI (ai.gd's fieldCache, kept on the battle).
var ai_cache: Variant = null
## Old recorded setups without this field keep their original no-fog rules.
var explored := {"player": {}, "enemy": {}}
var _sight_cache := {}
var _sight_stamp := ""

var objective: Dictionary:
	get:
		var o: Variant = setup.get("objective")
		return DEFAULT_OBJECTIVE if o == null else o

var waves: Array:
	get:
		var w: Variant = setup.get("waves")
		return [] if w == null else w


func _init(battle_setup: Dictionary) -> void:
	setup = battle_setup
	map = battle_setup.map
	units = battle_setup.units
	rng = Rng.new(battle_setup.seed)
	for u in units:
		hits_taken[u.uid] = 0
	wave_state = []
	for w in waves:
		wave_state.append("pending")
	refresh_sight()


func fog_enabled() -> bool:
	return setup.get("fogOfWar", false)


func refresh_sight(force := false) -> void:
	if not fog_enabled():
		return
	var key := Visibility.stamp(units) + str(revealed.keys())
	if not force and key == _sight_stamp:
		return
	_sight_stamp = key
	_sight_cache.clear()
	for side in ["player", "enemy"]:
		var eyes := Visibility.observers(units, side)
		var seen := Visibility.field(map, eyes)
		for u in units:
			if revealed.has(u.uid) and Grid.in_bounds(map, u.x, u.y):
				seen[Grid.key(u.x, u.y)] = true
		_sight_cache[side] = {"eyes": eyes, "seen": seen}
		explored[side].merge(seen)


func visible_tiles(side: String) -> Dictionary:
	refresh_sight()
	return _sight_cache.get(side, {}).get("seen", {})


func visible_to(side: String, u: Dictionary) -> bool:
	if u.faction == side or not fog_enabled():
		return true
	if u.status == "reserve":
		return false
	if revealed.has(u.uid):
		return true
	refresh_sight()
	var sight: Dictionary = _sight_cache[side]
	return Visibility.unit_seen(map, sight.eyes, sight.seen, u)


func known_unit_at(side: String, x: int, y: int) -> Variant:
	var u = Grid.unit_at(units, x, y)
	return u if u != null and visible_to(side, u) else null


## Waves still to come. A horn wave counts while the horn may yet sound.
func pending_waves() -> int:
	var n := 0
	for s in wave_state:
		if s == "pending":
			n += 1
	return n


## The next wave due, `{index, wave, turn}` (horn waves only once sounded), or null.
func next_wave() -> Variant:
	var best: Variant = null
	var ws := waves
	for i in ws.size():
		var w: Dictionary = ws[i]
		if wave_state[i] != "pending" or (w.get("horn") and horn != "sounded"):
			continue
		if best == null or w.turn < best.turn:
			best = {"index": i, "wave": w, "turn": w.turn}
	return best


## Company squads (the militia fights beside them but cannot carry the day alone).
func company() -> Array:
	var out: Array = []
	for u in active("player"):
		if not u.tags.has("militia"):
			out.append(u)
	return out


# ---------------------------------------------------------------- queries

func unit(uid: String) -> Variant:
	for x in units:
		if x.uid == uid:
			return x
	push_error("no unit %s" % uid)
	return null


func living(faction: String = "") -> Array:
	var out: Array = []
	for u in units:
		if (u.status == "active" or u.status == "routing") and (faction == "" or u.faction == faction):
			out.append(u)
	return out


func active(faction: String = "") -> Array:
	var out: Array = []
	for u in units:
		if u.status == "active" and (faction == "" or u.faction == faction):
			out.append(u)
	return out


func enemies_of(u: Dictionary) -> Array:
	return active("enemy" if u.faction == "player" else "player").filter(func(f): return visible_to(u.faction, f))


func allies_of(u: Dictionary) -> Array:
	var out: Array = []
	for a in units:
		if a.status == "active" and a.faction == u.faction and a.uid != u.uid:
			out.append(a)
	return out


func tile(p: Dictionary) -> Dictionary:
	return Grid.tile_at(map, p.x, p.y)


func morale_state(u: Dictionary) -> String:
	if u.status == "routing" or u.morale <= 0:
		return "broken"
	var r: float = float(u.morale) / u.maxMorale
	if r >= 0.9:
		return "confident"
	if r >= 0.5:
		return "steady"
	if r >= 0.25:
		return "shaken"
	return "wavering"


## Arc from which `target` is attacked by someone standing at `from`.
func arc_of(target: Dictionary, from: Dictionary) -> String:
	# A spear square faces every way: it has no flank or rear.
	if target.get("stance") == "square":
		return "front"
	var fx: int = Grid.DX[target.facing]
	var fy: int = Grid.DY[target.facing]
	var dx: float = float(from.x) - float(target.x)
	var dy: float = float(from.y) - float(target.y)
	var len := Grid.hypot(dx, dy)
	if len == 0.0:
		len = 1.0
	var cos_v: float = (fx * dx + fy * dy) / len
	var angle: float = (acos(maxf(-1.0, minf(1.0, cos_v))) * 180.0) / PI
	if angle <= 60:
		return "front"
	if angle < 120:
		return "flank"
	return "rear"


func is_adjacent_enemy(u: Dictionary, p: Variant = null) -> bool:
	return _enemy_beside(u, u if p == null else p)


## isAdjacentEnemy without building the enemies list.
func _enemy_beside(u: Dictionary, at: Dictionary) -> bool:
	var foe: String = "enemy" if u.faction == "player" else "player"
	for e in units:
		if e.status == "active" and e.faction == foe and Grid.manhattan(e, at) == 1 and visible_to(u.faction, e):
			return true
	return false


## Destinations the unit can end its move on: tile key -> {cost, prev, zoc}.
## `states`: this squad's reach_states(u, budget) when already at hand (same result, no new search).
func reachable(u: Dictionary, budget: Variant = null, states: Variant = null) -> Dictionary:
	var out := reachable_full(u, budget, states)
	var start := Grid.key(u.x, u.y)
	for k in out.keys():
		if k == start:
			continue
		if known_unit_at(u.faction, k % 1000, floori(k / 1000.0)) != null:
			out.erase(k)
	return out


func path_from(reach: Dictionary, x: int, y: int) -> Variant:
	var k := Grid.key(x, y)
	if not reach.has(k):
		return null
	# Walk back through prev links; intermediate tiles may have been pruned
	# from the map only if occupied by allies, so rebuild via a full search.
	var path: Array = []
	var guard := {}
	while k != -1:
		if guard.has(k):
			return null
		guard[k] = true
		path.append({"x": k % 1000, "y": floori(k / 1000.0)})
		var info: Variant = reach.get(k)
		if info == null:
			return null
		k = info.prev
	path.reverse()
	return path


## Path to a tile, arriving with the default facing (see `default_facing`), or null.
func path_to(u: Dictionary, x: int, y: int) -> Variant:
	if known_unit_at(u.faction, x, y) != null and not (x == u.x and y == u.y):
		return null
	var opt: Variant = move_option(u, x, y)
	return opt.path if opt != null and opt.path.size() > 1 else null


## Tiles a foe can strike at a squad leaving them: its front and flanks.
## A squad cannot strike what it cannot see, so its rear tile is free.
## Returns a set: tile key -> true.
func zoc_tiles(u: Dictionary) -> Dictionary:
	var out := {}
	# Skirmishers (wolf riders) wheel away before a blow can land.
	if u.tags.has("skirmish"):
		return out
	for f in enemies_of(u):
		for n in Grid.neighbors(map, f):
			if arc_of(f, n) == "rear":
				continue
			if absi(tile(n).h - tile(f).h) > 1:
				continue
			out[Grid.key(n.x, n.y)] = true
	return out


## Search state: a tile plus the facing the squad arrived with.
static func skey(x: int, y: int, d: int) -> int:
	return (y * 1000 + x) * 4 + d


static func unkey_state(s: int) -> Dictionary:
	var k: int = floori(s / 4.0)
	return {"x": k % 1000, "y": floori(k / 1000.0)}


## Dijkstra over (tile, facing on arrival): the facing is always the
## direction of the last step. Allies can be passed through, not enemies
## (routing ones included: `walk` stops in front of any enemy, so a path
## through one would cut the move short, possibly on an ally's tile; the
## archived original searched through them).
## Cheapest first, then fewest free attacks provoked.
## Returns state key -> {cost, prev, zoc} (state key = tile key * 4 + facing).
func reach_states(u: Dictionary, budget: Variant = null) -> Dictionary:
	if budget == null:
		budget = Squad.move_of(u)
	var out := {}
	var s0 := skey(u.x, u.y, u.facing)
	out[s0] = {"cost": 0, "prev": -1, "zoc": 0}
	# The open list of the original, as parallel arrays: state, x, y, cost, zoc
	# (and the cost and zoc as doubles for the scan). Taken out by swapping in
	# the last entry, exactly like the original's array.
	var o_s: Array = [s0]
	var o_x := PackedInt32Array([u.x])
	var o_y := PackedInt32Array([u.y])
	var o_cost: Array = [0]
	var o_zoc: Array = [0]
	var o_c := PackedFloat64Array([0.0])
	var o_z := PackedFloat64Array([0.0])
	var foe_at := {}
	for f in units:
		if f.faction != u.faction and (f.status == "active" or f.status == "routing") and visible_to(u.faction, f):
			foe_at[Grid.key(f.x, f.y)] = true
	var zt := zoc_tiles(u)
	var w: int = map.w
	var h: int = map.h
	var tiles: Array = map.tiles
	while o_s.size() > 0:
		var n_open := o_s.size()
		var bi := 0
		var bc: float = o_c[0]
		var bz: float = o_z[0]
		for i in range(1, n_open):
			var ac: float = o_c[i]
			if ac < bc or (ac == bc and o_z[i] < bz):
				bi = i
				bc = ac
				bz = o_z[i]
		var cur_s: int = o_s[bi]
		var cx: int = o_x[bi]
		var cy: int = o_y[bi]
		var cc = o_cost[bi]
		var cz = o_zoc[bi]
		var last := n_open - 1
		o_s[bi] = o_s[last]
		o_x[bi] = o_x[last]
		o_y[bi] = o_y[last]
		o_cost[bi] = o_cost[last]
		o_zoc[bi] = o_zoc[last]
		o_c[bi] = o_c[last]
		o_z[bi] = o_z[last]
		o_s.resize(last)
		o_x.resize(last)
		o_y.resize(last)
		o_cost.resize(last)
		o_zoc.resize(last)
		o_c.resize(last)
		o_z.resize(last)
		var best: Dictionary = out[cur_s]
		if cc > best.cost or (cc == best.cost and cz > best.zoc):
			continue
		# canStep: no step leads off a tile outside the map (a squad placed off the field).
		if cx < 0 or cy < 0 or cx >= w or cy >= h:
			continue
		var leaving := 1 if zt.has(cy * 1000 + cx) else 0
		var ch: int = tiles[cy * w + cx].h
		for d in 4:
			var nx: int = cx + Grid.DX[d]
			var ny: int = cy + Grid.DY[d]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			if foe_at.has(ny * 1000 + nx):
				continue
			if not Grid.tile_passable(map, nx, ny):
				continue
			var nt: Dictionary = tiles[ny * w + nx]
			if absi(ch - nt.h) > 1:
				continue
			var c = cc + DB.TERRAIN[nt.terrain].moveCost
			if c > budget:
				continue
			var z = cz + leaving
			var ns := (ny * 1000 + nx) * 4 + d
			var prev: Variant = out.get(ns)
			if prev == null or c < prev.cost or (c == prev.cost and z < prev.zoc):
				out[ns] = {"cost": c, "prev": cur_s, "zoc": z}
				o_s.append(ns)
				o_x.append(nx)
				o_y.append(ny)
				o_cost.append(c)
				o_zoc.append(z)
				o_c.append(c)
				o_z.append(z)
	return out


## Cheapest way to each tile, whatever the facing (prev links follow tiles).
func reachable_full(u: Dictionary, budget: Variant = null, states: Variant = null) -> Dictionary:
	if states == null:
		states = reach_states(u, budget)
	var out := {}
	out[Grid.key(u.x, u.y)] = {"cost": 0, "prev": -1, "zoc": 0}
	for s in states:
		var info: Dictionary = states[s]
		var k: int = floori(s / 4.0)
		var prev: Variant = out.get(k)
		if prev == null or info.cost < prev.cost or (info.cost == prev.cost and info.zoc < prev.zoc):
			out[k] = {"cost": info.cost, "prev": -1 if info.prev < 0 else floori(info.prev / 4.0), "zoc": info.zoc}
	return out


## Every facing the squad can end its move on (x, y) with, and the path for each.
func facing_options(u: Dictionary, x: int, y: int, states: Variant = null) -> Array:
	if states == null:
		states = reach_states(u)
	var home: bool = x == u.x and y == u.y
	if not home and known_unit_at(u.faction, x, y) != null:
		return []
	var out: Array = []
	for d in 4:
		var s := skey(x, y, d)
		var info: Variant = states.get(s)
		if info == null:
			continue
		var path: Array = []
		var cur: int = s
		while cur != -1:
			path.append(unkey_state(cur))
			cur = states[cur].prev
		path.reverse()
		out.append({"facing": d, "cost": info.cost, "zoc": info.zoc, "path": path})
	return out


## The facing a squad takes when nobody chooses: never more free attacks
## than the safest way in, then facing the nearest enemy, else turned side
## on rather than showing its back, then the shortest walk.
func default_facing(u: Dictionary, x: int, y: int, options: Array) -> Variant:
	if options.is_empty():
		return null
	var min_zoc = options[0].zoc
	for o in options:
		if o.zoc < min_zoc:
			min_zoc = o.zoc
	var safe: Array = []
	for o in options:
		if o.zoc == min_zoc:
			safe.append(o)
	var foes := enemies_of(u)
	# A stable sort's first element: the earliest option with the least score.
	if foes.is_empty():
		var first: Dictionary = safe[0]
		for o in safe:
			if o.cost < first.cost:
				first = o
		return first
	var at := {"x": x, "y": y}
	var near: Dictionary = foes[0]
	for i in range(1, foes.size()):
		var f: Dictionary = foes[i]
		if Grid.dist(f, at) < Grid.dist(near, at):
			near = f
	var want := Grid.dir_to(at, near)
	var best: Dictionary = safe[0]
	var best_score = _facing_score(best, want)
	for o in safe:
		var s = _facing_score(o, want)
		if s < best_score:
			best = o
			best_score = s
	return best


static func _facing_score(o: Dictionary, want: int) -> Variant:
	var off: int = (0 if o.facing == want else 2) if absi(o.facing - want) % 2 == 0 else 1
	return off * 100 + o.cost


## The way the squad would end a move on (x, y): with `facing` if that is possible, else the default.
func move_option(u: Dictionary, x: int, y: int, facing: Variant = null, states: Variant = null) -> Variant:
	facing = _facing_arg(facing)
	var options := facing_options(u, x, y, states)
	if facing != null:
		for q in options:
			if q.facing == facing:
				return q
	return default_facing(u, x, y, options)


static func _facing_arg(facing: Variant) -> Variant:
	if facing == null or facing < 0:
		return null
	return int(facing)


## The facing toward the nearest enemies (deployment and new arrivals).
func facing_toward_foes(u: Dictionary, at: Variant = null) -> int:
	var p: Dictionary = u if at == null else at
	var foes: Array = []
	for f in units:
		if f.faction != u.faction and f.status == "active" and visible_to(u.faction, f):
			foes.append(f)
	var d := {}
	for f in foes:
		d[f.uid] = Grid.dist(f, p)
	JS.sort(foes, func(a, b): return d[a.uid] - d[b.uid])
	foes = foes.slice(0, 3)
	if foes.is_empty():
		return u.facing
	var sx := 0.0
	var sy := 0.0
	for f in foes:
		sx += f.x
		sy += f.y
	return Grid.dir_to(p, {"x": sx / foes.size(), "y": sy / foes.size()})


func can_melee(a: Dictionary, t: Dictionary, from: Variant = null, reach: int = 1) -> bool:
	if not visible_to(a.faction, t):
		return false
	var fp: Dictionary = a if from == null else from
	var ta := tile(fp)
	var tt := tile(t)
	if absi(ta.h - tt.h) > 1:
		return false
	if reach == 1:
		return Grid.manhattan(fp, t) == 1
	# Straight line, exactly two tiles, nothing solid in between.
	var dx: int = t.x - fp.x
	var dy: int = t.y - fp.y
	if not ((absi(dx) == 2 and dy == 0) or (absi(dy) == 2 and dx == 0)):
		return false
	var mid: Dictionary = Grid.tile_at(map, fp.x + dx / 2, fp.y + dy / 2)
	var mp: Variant = mid.get("prop")
	if mp and DB.PROPS[mp].los == 2:
		return false
	if mid.h > maxi(ta.h, tt.h):
		return false
	return true


func shot_range(a: Dictionary, from: Dictionary, t: Dictionary) -> Variant:
	var shot: Variant = a.get("shot")
	if shot == null:
		return 0
	var dh: int = tile(from).h - tile(t).h
	return shot.range + maxi(0, dh)


## `{ok: bool, reason?: String}`.
func can_shoot(a: Dictionary, t: Dictionary, from: Variant = null) -> Dictionary:
	return _can_shoot(a, t, a if from == null else from, [])


## The line of sight from `from` to `t`, computed once per `memo` (a preview
## asks for the same line up to three times; the map does not change meanwhile).
func _los(from: Dictionary, t: Dictionary, memo: Array) -> Dictionary:
	if memo.is_empty():
		memo.append(Grid.line_of_sight(map, from, t))
	return memo[0]


func _can_shoot(a: Dictionary, t: Dictionary, fp: Dictionary, memo: Array) -> Dictionary:
	if not visible_to(a.faction, t):
		return {"ok": false, "reason": "Target is hidden by fog of war"}
	var shot: Variant = a.get("shot")
	if shot == null:
		return {"ok": false, "reason": "No ranged weapon"}
	if a.ammo == 0:
		return {"ok": false, "reason": "Out of bolts"}
	var d := Grid.dist(fp, t)
	if d < shot.minRange:
		return {"ok": false, "reason": "Too close to shoot"}
	if d > shot_range(a, fp, t) + 0.01:
		return {"ok": false, "reason": "Out of range"}
	if setup.get("darkness") and d > shot.range - 2:
		return {"ok": false, "reason": "Too dark to see"}
	var los := _los(fp, t, memo)
	if los.blocked:
		return {"ok": false, "reason": "No line of sight"}
	return {"ok": true}


## Whether the default attack against this target would be a shot.
func would_shoot(a: Dictionary, t: Dictionary, from: Variant = null) -> bool:
	return _would_shoot(a, t, a if from == null else from, [])


func _would_shoot(a: Dictionary, t: Dictionary, fp: Dictionary, memo: Array) -> bool:
	return a.get("shot") != null and Grid.manhattan(fp, t) > 1 and _can_shoot(a, t, fp, memo).ok


## Whether `preview(a, t, opts).legal` would be true (the same checks, without the rest).
func preview_legal(a: Dictionary, t: Dictionary, opts: Dictionary = {}) -> bool:
	if not visible_to(a.faction, t):
		return false
	var from: Variant = opts.get("from")
	if from == null:
		from = {"x": a.x, "y": a.y}
	var ab_id: Variant = opts.get("ability")
	var ab: Variant = DB.ABILITIES.get(ab_id) if ab_id else null
	var memo: Array = []
	var ranged: bool = bool(ab.get("ranged", false)) if ab != null else (not opts.get("forceMelee", false) and _would_shoot(a, t, from, memo))
	if ab != null and _run_short(a, ab, opts) != "":
		return false
	if ranged:
		return _can_shoot(a, t, from, memo).ok and not _unbraced(a, opts)
	var reach: int = JS.get_or(ab, "reach", 1) if ab != null else 1
	return can_melee(a, t, from, reach)


## A war machine has to be braced and laid before it can loose: not in a turn it has moved.
func _unbraced(a: Dictionary, opts: Dictionary) -> bool:
	if not a.tags.has("engine") or opts.get("reaction"):
		return false
	var mtv: Variant = opts.get("movedTiles")
	return (a.movedTiles if mtv == null else mtv) > 0


## Why an attack ability cannot be used after this turn's move, or "": a
## charge needs a run (`minRun` tiles), an aimed shot a squad that has not moved (`still`).
func _run_short(a: Dictionary, ab: Dictionary, opts: Dictionary) -> String:
	var mtv: Variant = opts.get("movedTiles")
	var run: int = a.movedTiles if mtv == null else mtv
	if ab.get("minRun") and run < ab.minRun:
		return "Needs a run of at least %d tiles" % ab.minRun
	if ab.get("still") and ((run > 0) if mtv != null else a.hasMoved):
		return "Only in a turn the squad has not moved"
	return ""


## Defend: the squad standing guard beside `t` that takes an attack aimed at
## it, or null. Only attacks ordered against `t` are caught (not free attacks,
## spearwalls, overwatch or first strikes), and a guard is never guarded.
## Each guard catches one blow per stand (`guardSpent`). The sturdiest guard
## steps in (most HP, then uid).
func guard_of(a: Dictionary, t: Dictionary, opts: Dictionary = {}) -> Variant:
	if opts.get("reaction") or t.get("stance") == "defend" or t.faction == a.faction:
		return null
	var best: Variant = null
	for g in units:
		if g.get("stance") != "defend" or g.get("guardSpent") or g.status != "active" or g.faction != t.faction or g.uid == t.uid or Grid.manhattan(g, t) != 1:
			continue
		if best == null or g.hp > best.hp or (g.hp == best.hp and String(g.uid) < String(best.uid)):
			best = g
	return best


## A charge that meets a spear square loses everything the run gave it.
static func _charge_broken(ab: Variant, d: Dictionary) -> bool:
	return ab != null and ab.get("minRun") and d.get("stance") == "square"


## AttackOpts: {from?: Pt, ability?: String, reaction?: String, forceMelee?: bool, movedTiles?: int}.
func preview(a: Dictionary, t: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var from: Variant = opts.get("from")
	if from == null:
		from = {"x": a.x, "y": a.y}
	var ab_id: Variant = opts.get("ability")
	var ab: Variant = DB.ABILITIES.get(ab_id) if ab_id else null
	var reaction: Variant = opts.get("reaction")
	var memo: Array = []
	var ranged: bool = bool(ab.get("ranged", false)) if ab != null else (not opts.get("forceMelee", false) and _would_shoot(a, t, from, memo))
	var mods: Array = []
	var legal := true
	var reason: Variant = null
	if not visible_to(a.faction, t):
		return {"legal": false, "reason": "Target is hidden by fog of war", "chance": 0, "min": 0, "max": 0, "arc": "front", "mods": [], "kill": 0, "moraleHit": 0, "soldiers": [0, 0], "strikers": 0}

	if ranged:
		var s := _can_shoot(a, t, from, memo)
		if not s.ok:
			legal = false
			reason = s.reason
		elif _unbraced(a, opts):
			# A war machine has to be braced and laid before it can loose.
			legal = false
			reason = "Cannot loose in a turn it has moved"
	else:
		var reach: int = JS.get_or(ab, "reach", 1) if ab != null else 1
		if not can_melee(a, t, from, reach):
			legal = false
			reason = "Needs a straight line two tiles away" if reach > 1 else "Not adjacent"
	if legal and ab != null:
		var short := _run_short(a, ab, opts)
		if short != "":
			legal = false
			reason = short

	# Who takes the blow: the target, or a squad standing guard beside it
	# (Defend), on its shield. Where it lands (range, sight, cover, ground)
	# stays the target's tile.
	var guard: Variant = guard_of(a, t, opts)
	var d: Dictionary = t if guard == null else guard
	var arc := "front" if guard != null else arc_of(t, from)
	var chance = a.stats.ranged if ranged else a.stats.melee
	mods.append(["Ranged skill" if ranged else "Melee skill", chance])

	var def = d.stats.rangedDefense if ranged else d.stats.defense
	var t_tile := tile(t)
	def += DB.TERRAIN[t_tile.terrain].defenseMod
	# Holding a gateway: the posts and the narrow way shelter the defenders.
	var tprop: Variant = t_tile.get("prop")
	if tprop and DB.PROPS[tprop].get("defense"):
		def += DB.PROPS[tprop].defense
	var t_stance: Variant = d.get("stance")
	var shieldwall: bool = t_stance == "shieldwall"
	if d.shieldFront and (arc == "front" or (shieldwall and arc == "flank")):
		def += d.shieldFront
	if shieldwall:
		def += 15 if ranged else 20
	# A square bristles against blades but packs its men for the archers.
	if t_stance == "square":
		def += -10 if ranged else 6
	if not shieldwall:
		# alliesOf(t).some(shieldwall beside it)
		for x in units:
			if x.status == "active" and x.faction == d.faction and x.uid != d.uid and x.get("stance") == "shieldwall" and Grid.manhattan(x, d) == 1:
				def += 6
				break
	var tms := morale_state(d)
	if tms == "shaken":
		def -= 5
	if tms == "wavering":
		def -= 10
	chance -= def
	mods.append(["Target defense", -def])
	if Squad.has_status(d, "chilled"):
		chance += 10
		mods.append(["Target chilled", 10])
	if Squad.has_status(d, "bloodlust"):
		chance += 8
		mods.append(["Target in a frenzy", 8])

	if d.status == "routing":
		chance += 15
		mods.append(["Fleeing target", 15])
	if arc == "flank":
		chance += 10
		mods.append(["Flank attack", 10])
	elif arc == "rear":
		chance += 20
		mods.append(["Attack from behind", 20])

	var dh: int = tile(from).h - t_tile.h
	if dh != 0:
		var hm: int = maxi(-16, mini(16, dh * 8))
		chance += hm
		mods.append(["High ground" if hm > 0 else "Attacking uphill", hm])

	var ams := morale_state(a)
	var am := 5 if ams == "confident" else -8 if ams == "shaken" else -15 if ams == "wavering" else 0
	if am:
		chance += am
		mods.append(["Confident" if ams == "confident" else "Shaken" if ams == "shaken" else "Wavering", am])
	if Squad.has_status(a, "chilled"):
		chance -= 10
		mods.append(["Chilled", -10])
	if not ranged and Squad.has_status(a, "bloodlust"):
		chance += 10
		mods.append(["Bloodlust", 10])
	if Squad.has_status(a, "cowed"):
		chance -= 10
		mods.append(["Cowed", -10])

	if ranged and legal:
		# An aimed shot waits for its moment: cover, a blocked view and troops in the way do not spoil it.
		var aimed: bool = ab != null and bool(ab.get("ignoreCover", false))
		var rd := Grid.dist(from, t)
		if rd > 4:
			var m := -JS.rnd((rd - 4) * 4)
			chance += m
			mods.append(["Long range", m])
		var los := _los(from, t, memo)
		if los.partial and not aimed:
			chance -= los.partial * 10
			mods.append(["Obstructed view", -los.partial * 10])
		var between := 0
		for p in los.tiles:
			if Grid.unit_at(units, p.x, p.y) != null:
				between += 1
		if between and not aimed:
			chance -= between * 12
			mods.append(["Shooting past troops", -between * 12])
		var last: Variant = los.tiles[los.tiles.size() - 1] if los.tiles.size() > 0 else null
		if last != null and Grid.manhattan(last, t) <= 1 and not aimed:
			var lt: Dictionary = Grid.tile_at(map, last.x, last.y)
			var lp: Variant = lt.get("prop")
			if lp and DB.PROPS[lp].cover:
				chance -= DB.PROPS[lp].cover
				mods.append(["Behind %s" % String(DB.PROPS[lp].name).to_lower(), -DB.PROPS[lp].cover])
		var tc = DB.TERRAIN[t_tile.terrain].rangedCover if not aimed else 0
		if tc:
			chance -= tc
			mods.append(["In %s" % String(DB.TERRAIN[t_tile.terrain].name).to_lower(), -tc])
		if _enemy_beside(a, from):
			chance -= 15
			mods.append(["Engaged in melee", -15])
		var mt: Variant = opts.get("movedTiles")
		var moved: bool = (mt > 0) if mt != null else a.hasMoved
		if not moved and not reaction:
			chance += 8
			mods.append(["Steady aim", 8])
		if setup.get("darkness"):
			chance -= 10
			mods.append(["Darkness", -10])

	if not ranged and a.tags.has("swarm"):
		var pack := 0
		# alliesOf(a) beside the target, not counting the attacker's own tile.
		for x in units:
			if x.status == "active" and x.faction == a.faction and x.uid != a.uid and Grid.manhattan(x, t) == 1 and not (x.x == from.x and x.y == from.y):
				pack += 1
		if pack:
			var m := mini(15, pack * 5)
			chance += m
			mods.append(["Pack tactics", m])

	var broken := _charge_broken(ab, d)
	if ab != null and ab.get("hitMod"):
		chance += ab.hitMod
		mods.append([ab.name, ab.hitMod])
	if broken:
		# The square takes back what the run gave, so the rows still add up.
		var lost = -JS.get_or(ab, "hitMod", 0)
		chance += lost
		mods.append(["Charge broken by the square", lost])
	if reaction == "overwatch":
		chance -= 5
		mods.append(["Snap shot", -5])
	if reaction == "spearwall":
		chance += 15
		mods.append(["Set spears", 15])

	chance = maxi(5, mini(95, JS.rnd(chance)))

	# Damage: every surviving soldier lands one blow, each reduced by the
	# target's armour, and the squad's total is rolled once.
	var base: Array = a.shot.damage if ranged else a.melee
	var mult = JS.get_or(ab, "damageMult", 1) if ab != null and not broken else 1
	if reaction == "spearwall":
		mult *= 1.5
	if arc == "rear":
		mult *= 1.25
	# Flankers (wolf riders) tear into sides and backs.
	if not ranged and arc != "front" and a.tags.has("flanker"):
		mult *= 1.3
	var flat := 0
	var mtv: Variant = opts.get("movedTiles")
	var moved_tiles = a.movedTiles if mtv == null else mtv
	var charging: bool = not ranged and a.abilities.has("charge") and moved_tiles >= 2 and not reaction and d.get("stance") != "square"
	if charging:
		flat += 3
	# Frenzied soldiers put everything into every blow.
	if not ranged and Squad.has_status(a, "bloodlust"):
		flat += 3
	var pierce = 1 if (ab != null and ab.get("ignoreArmor")) else (a.shot.pierce if ranged else a.meleePierce)
	var armor = d.stats.armor * (1 - pierce)
	var strikers: int = maxi(1, a.alive)
	var mn: int = maxi(1, JS.rnd(base[0] * mult + flat - armor)) * strikers
	var mx: int = maxi(1, JS.rnd(base[1] * mult + flat - armor)) * strikers
	var killing := 0
	for dmg in range(mn, mx + 1):
		if dmg >= d.hp:
			killing += 1
	var kill: float = (float(killing) / (mx - mn + 1)) * (float(chance) / 100.0)
	var avg: float = (mn + mx) / 2.0
	var morale_hit: int = (JS.rnd((avg / d.maxHp) * 28)
		+ (4 if arc == "flank" else 8 if arc == "rear" else 0)
		+ (JS.get_or(ab, "moraleDamage", 0) if ab != null and not broken else 0)
		+ (8 if charging else 0))
	var soldiers := [Squad.kills_from(d, mn), Squad.kills_from(d, mx)]

	var out := {"chance": chance, "min": mn, "max": mx, "arc": arc, "mods": mods, "kill": kill, "moraleHit": morale_hit, "legal": legal, "reason": reason, "soldiers": soldiers, "strikers": strikers}
	# Numbers for the guard that steps in (Defend): `guard` is its uid.
	if guard != null:
		out["guard"] = guard.uid
	return out


## Targets the unit could attack right now from `from` with the given ability.
func targets(u: Dictionary, from: Variant = null, ability: Variant = null) -> Array:
	var fp: Dictionary = u if from == null else from
	var list := enemies_of(u)
	for x in units:
		if x.status == "routing" and x.faction != u.faction:
			list.append(x)
	var out: Array = []
	var opts := {"from": fp, "ability": ability, "movedTiles": u.movedTiles}
	for t in list:
		if preview(u, t, opts).legal:
			out.append(t)
	return out


# ---------------------------------------------------------------- events

func _emit(e: Dictionary) -> void:
	events.append(e)


## Fighting gives a squad's position away until its next turn.
var revealed := {}


func reveal_combat(u: Dictionary) -> void:
	if fog_enabled() and not revealed.has(u.uid):
		revealed[u.uid] = true
		_emit({"t": "reveal", "uid": u.uid})


func drain() -> Array:
	var out := events
	events = []
	return out


## Battle.log of the original (call it as `b.log(text)`; inside this class
## GDScript's built-in log() would shadow it, so the rules use _log).
func log(text: String, tone: String = "neutral") -> void:
	_log(text, tone)


func _log(text: String, tone: String = "neutral") -> void:
	_emit({"t": "log", "text": text, "tone": tone})


# ---------------------------------------------------------------- morale

func change_morale(u: Dictionary, delta: Variant, reason: String) -> void:
	if u.status != "active" or delta == 0:
		return
	# A frenzied squad barely notices what would shake it.
	if delta < 0 and Squad.has_status(u, "bloodlust"):
		delta = mini(-1, JS.rnd(delta / 2.0))
	var before := morale_state(u)
	u.morale = maxi(0, mini(u.maxMorale, JS.rnd(u.morale + delta)))
	_emit({"t": "morale", "uid": u.uid, "delta": JS.rnd(delta), "value": u.morale, "reason": reason})
	var after := morale_state(u)
	if after != before:
		_emit({"t": "mstate", "uid": u.uid, "from": before, "to": after})
	if u.morale <= 0:
		_rout(u)


func _rout(u: Dictionary) -> void:
	if u.status != "active":
		return
	if u.leader:
		u.morale = 1
		return
	u.status = "routing"
	u.erase("stance")
	_emit({"t": "rout", "uid": u.uid})
	_log("%s %s and %s!" % [Squad.squad_name(u), "breaks" if u.leader else "break", "flees" if u.leader else "flee"], "bad" if u.faction == "player" else "good")
	for a in active(u.faction):
		if Grid.dist(a, u) <= 4:
			change_morale(a, -6, "Ally fled")
	for e in active("enemy" if u.faction == "player" else "player"):
		if Grid.dist(e, u) <= 5:
			change_morale(e, 3, "Enemy fled")


# ---------------------------------------------------------------- damage

func _fall(u: Dictionary, killer: Variant = null) -> void:
	var dead := true
	if u.faction == "player":
		var p: float = FALL_SURVIVAL_BASE + 0.05 * (u.level - 1) + setup.survivalBonus
		dead = not rng.chance(p)
	u.status = "dead" if dead else "downed"
	u.erase("stance")
	u.hp = 0
	u.alive = 0
	u["statuses"] = []
	_emit({"t": "down", "uid": u.uid, "dead": dead})
	var name := Squad.squad_name(u)
	var text := ""
	if u.leader:
		text = "%s is slain." % name
	elif dead:
		text = "%s are wiped out to the last." % name
	else:
		text = "%s are cut down; the wounded sergeant is dragged clear." % name
	_log(text, "bad" if u.faction == "player" else "good")
	if killer != null:
		killer.kills += 1
		if killer.faction == "player":
			var def: Variant = DB.UNIT_TYPES.get(u.typeId)
			killer.xp += JS.get_or(def, "value", 4) if def != null else 4
		change_morale(killer, 8, "Felled a foe")
	if u.tags.has("herald") and horn == "waiting":
		_silence_horn()
	if u.tags.has("warchief") and u.faction == "enemy":
		_horde_breaks(u)
		return
	if u.leader:
		for a in active(u.faction):
			change_morale(a, -35, "Leader fell")
	else:
		for a in active(u.faction):
			var d := Grid.dist(a, u)
			if d <= 1.01:
				change_morale(a, -16, "Comrade fell beside them")
			elif d <= 4:
				change_morale(a, -10, "Comrade fell")
	for e in active("enemy" if u.faction == "player" else "player"):
		if not is_same(e, killer) and Grid.dist(e, u) <= 4:
			change_morale(e, 4, "Enemy fell")


func _resolve_attack(a: Dictionary, t: Dictionary, opts: Dictionary) -> bool:
	reveal_combat(a)
	reveal_combat(t)
	var ab_id: Variant = opts.get("ability")
	var ab: Variant = DB.ABILITIES.get(ab_id) if ab_id else null
	var pv := preview(a, t, opts)
	var from: Variant = opts.get("from")
	var ranged: bool = bool(ab.get("ranged", false)) if ab != null else (not opts.get("forceMelee", false) and would_shoot(a, t, a if from == null else from))
	if ranged and a.ammo > 0:
		a.ammo = maxi(0, a.ammo - (JS.get_or(ab, "ammoCost", 1) if ab != null else 1))
	# Defend: the guard beside the target steps in and takes the blow (the
	# preview's numbers are already the guard's). From here on `t` is whoever is struck.
	var ward: Variant = null
	var guard: Variant = guard_of(a, t, opts)
	if guard != null:
		ward = t
		t = guard
		t["guardSpent"] = true
		reveal_combat(t)
		_log("%s step in front of %s!" % [Squad.squad_name(t), Squad.squad_name(ward)], "good" if t.faction == "player" else "bad")
	# One roll for the whole squad, however many soldiers swing or loose.
	var hit: bool = rng.next() * 100 < pv.chance
	var damage := 0
	if hit:
		damage = mini(t.hp, rng.rint(pv.min, pv.max))
	var alive_before: int = t.alive
	if hit:
		hits_taken[t.uid] = JS.get_or(hits_taken, t.uid, 0) + 1
		Squad.damage_squad(t, damage)
		a.damageDealt += damage
	var lost: int = alive_before - t.alive
	var reaction: Variant = opts.get("reaction")
	var ev := {
		"t": "attack", "uid": a.uid, "target": t.uid, "ranged": ranged, "hit": hit, "damage": damage,
		"chance": pv.chance, "arc": pv.arc, "targetHp": t.hp, "strikers": pv.strikers,
		"aliveBefore": alive_before, "aliveAfter": t.alive,
	}
	if ab_id != null:
		ev["ability"] = ab_id
	if reaction != null:
		ev["reaction"] = reaction
	if ward != null:
		ev["ward"] = ward.uid
	_emit(ev)
	var how := ""
	match reaction:
		"spearwall":
			how = " (spearwall)"
		"overwatch":
			how = " (overwatch)"
		"zoc":
			how = " (free attack)"
		"firstStrike":
			how = " (first strike)"
	var side := "" if pv.arc == "front" else " in the flank" if pv.arc == "flank" else " from behind"
	var fallen := ""
	if lost > 0 and t.alive > 0:
		fallen = " %s %s %s." % ["One" if lost == 1 else str(lost), Squad.member_noun(t.typeId, lost), "falls" if lost == 1 else "fall"]
	var tone := ("good" if hit else "neutral") if a.faction == "player" else ("bad" if hit else "neutral")
	if hit:
		_log("%s hit %s%s for %d%s.%s" % [Squad.squad_name(a), Squad.squad_name(t), side, damage, how, fallen], tone)
	else:
		_log("%s miss %s%s (%s%%)." % [Squad.squad_name(a), Squad.squad_name(t), how, JS.num_str(pv.chance)], tone)
	if not hit:
		return false
	# A ballista bolt carries on through into the next foe behind.
	var through: Variant = impale_target(a, t) if ranged and not reaction and ward == null and a.tags.has("impale") else null
	if t.hp <= 0:
		if t.status == "routing":
			# Cut down while fleeing.
			t.status = "active"
		_fall(t, a)
		if through != null:
			_impale(a, t, through, damage, pv.strikers)
		return true
	if t.status == "active":
		var mtv: Variant = opts.get("movedTiles")
		var charging: bool = not ranged and a.abilities.has("charge") and (a.movedTiles if mtv == null else mtv) >= 2 and not reaction and t.get("stance") != "square"
		# Watching comrades fall shakes a squad more than the wounds alone.
		var loss: int = (JS.rnd((float(damage) / t.maxHp) * 28)
			+ (4 if pv.arc == "flank" else 8 if pv.arc == "rear" else 0)
			+ (JS.get_or(ab, "moraleDamage", 0) if ab != null and not _charge_broken(ab, t) else 0)
			+ (8 if charging else 0)
			+ JS.rnd(float(lost * 6) / t.size))
		var reason: String
		if pv.arc == "rear":
			reason = "Struck from behind"
		elif pv.arc == "flank":
			reason = "Flanked"
		elif lost > 0:
			reason = "Lost a soldier" if lost == 1 else "Lost %d soldiers" % lost
		else:
			reason = "Wounded"
		change_morale(t, -loss, reason)
	if ab != null and ab.get("push") and t.status != "dead" and t.status != "downed":
		_push(a, t)
	# Brutes smash a squad out of the line and shoulder into the gap.
	elif not ranged and not reaction and a.tags.has("smash") and t.status == "active":
		_push(a, t, true)
	if through != null:
		_impale(a, t, through, damage, pv.strikers)
	return true


## The next foe behind `t` on the line of a ballista's shot, within two tiles,
## or null. A wall stops the bolt, and so does one of the company's own squads.
func impale_target(a: Dictionary, t: Dictionary) -> Variant:
	var dx: int = t.x - a.x
	var dy: int = t.y - a.y
	var len: float = JS.hypot(dx, dy)
	if len == 0:
		len = 1.0
	var last := {"x": t.x, "y": t.y}
	for k in range(1, 3):
		var p := {"x": JS.rnd(t.x + (dx / len) * k), "y": JS.rnd(t.y + (dy / len) * k)}
		if p.x == last.x and p.y == last.y:
			continue
		last = p
		var tl: Variant = Grid.tile_at(map, p.x, p.y)
		if tl == null:
			return null
		var prop: Variant = tl.get("prop")
		if prop and DB.PROPS[prop].los == 2:
			return null
		var u: Variant = Grid.unit_at(units, p.x, p.y)
		if u != null:
			return u if u.faction != a.faction else null
	return null


## The bolt goes on through `via` into `t` at half force (no new roll: it is the same bolt).
func _impale(a: Dictionary, via: Dictionary, t: Dictionary, damage: int, strikers: int) -> void:
	if t.status != "active" and t.status != "routing":
		return
	var dmg: int = mini(t.hp, maxi(1, JS.rnd(damage * 0.5)))
	var alive_before: int = t.alive
	hits_taken[t.uid] = JS.get_or(hits_taken, t.uid, 0) + 1
	Squad.damage_squad(t, dmg)
	a.damageDealt += dmg
	var lost: int = alive_before - t.alive
	_emit({
		"t": "attack", "uid": a.uid, "target": t.uid, "ranged": true, "ability": "impale", "hit": true, "damage": dmg,
		"chance": 100, "arc": arc_of(t, a), "targetHp": t.hp, "strikers": strikers,
		"aliveBefore": alive_before, "aliveAfter": t.alive, "via": via.uid,
	})
	var fallen := ""
	if lost > 0 and t.alive > 0:
		fallen = " %s %s %s." % ["One" if lost == 1 else str(lost), Squad.member_noun(t.typeId, lost), "falls" if lost == 1 else "fall"]
	_log("The bolt goes on through into %s for %d.%s" % [Squad.squad_name(t), dmg, fallen], "good" if a.faction == "player" else "bad")
	_after_damage(a, t, dmg, lost, 4, "Impaled")


## What follows damage outside a plain attack (spells, a bolt carrying on,
## bleeding): the squad falls, or its morale takes the wound and the losses.
## Friendly fire earns nobody a kill.
func _after_damage(by: Variant, t: Dictionary, damage: int, lost: int, extra: int, reason: String) -> void:
	if t.hp <= 0:
		if t.status == "routing":
			t.status = "active"
		_fall(t, by if by != null and by.faction != t.faction and by.status == "active" else null)
		return
	if t.status != "active":
		return
	var loss: int = JS.rnd((float(damage) / t.maxHp) * 28) + extra + JS.rnd(float(lost * 6) / t.size)
	var why := reason
	if lost > 0:
		why = "Lost a soldier" if lost == 1 else "Lost %d soldiers" % lost
	change_morale(t, -loss, why)


func _push(a: Dictionary, t: Dictionary, follow := false) -> void:
	# A square is braced on every side: it gives no ground.
	if t.get("stance") == "square":
		_log("The square of %s holds its ground." % Squad.squad_name(t))
		return
	var dx := signi(t.x - a.x)
	var dy := signi(t.y - a.y)
	var to := {"x": t.x + dx, "y": t.y + dy}
	var from := {"x": t.x, "y": t.y}
	var ok: bool = (Grid.tile_passable(map, to.x, to.y)
		and Grid.unit_at(units, to.x, to.y) == null
		and tile(to).h <= tile(from).h + 0
		and tile(from).h - tile(to).h <= 2)
	if ok:
		t.x = to.x
		t.y = to.y
		_emit({"t": "push", "uid": t.uid, "from": from, "to": to, "blocked": false, "hp": t.hp, "alive": t.alive})
		if follow and a.status == "active" and absi(tile(from).h - tile(a).h) <= 1:
			var at := {"x": a.x, "y": a.y}
			a.x = from.x
			a.y = from.y
			a.facing = Grid.dir_to(at, from)
			_emit({"t": "move", "uid": a.uid, "path": [at, from.duplicate()]})
			_log("%s smash %s back and force their way into the gap!" % [Squad.squad_name(a), Squad.squad_name(t)], "good" if a.faction == "player" else "bad")
	else:
		# Every soldier in the squad is slammed into the obstacle.
		var slam: int = mini(t.hp, 3 * t.alive)
		Squad.damage_squad(t, slam)
		a.damageDealt += slam
		_emit({"t": "push", "uid": t.uid, "from": from, "to": from, "blocked": true, "hp": t.hp, "alive": t.alive})
		_log("%s %s slammed against the obstacle." % [Squad.squad_name(t), "is" if t.leader else "are"])
		if t.hp <= 0:
			_fall(t, a)


# ---------------------------------------------------------------- actions

func deploy_swap(uid: String, x: int, y: int) -> bool:
	if phase != "deploy":
		return false
	var u: Dictionary = unit(uid)
	var in_zone := false
	for p in map.playerDeploy:
		if p.x == x and p.y == y:
			in_zone = true
			break
	if not in_zone:
		return false
	var other: Variant = Grid.unit_at(units, x, y)
	if other != null and other.faction != "player":
		return false
	if other != null:
		other.x = u.x
		other.y = u.y
		other.facing = facing_toward_foes(other)
	u.x = x
	u.y = y
	# Squads take the field facing the enemy; after that only marching turns them.
	u.facing = facing_toward_foes(u)
	return true


## Remaining fighting strength of a faction relative to the start (by HP).
func strength(faction: String) -> float:
	var total = 0
	for u in units:
		if u.faction == faction and u.status != "reserve":
			total += u.maxHp
	var left = 0
	for u in active(faction):
		left += u.hp
	return float(left) / total if total else 0.0


func is_over() -> bool:
	return phase == "over"


func begin(run_ai: Callable) -> void:
	if phase != "deploy":
		return
	if setup.get("enemyFirst"):
		phase = "enemy"
		_start_turn("enemy")
		if is_over():
			return
		run_ai.call(self)
		if is_over():
			return
		_end_of_turn("enemy")
	phase = "player"
	_start_turn("player")


func can_act(u: Dictionary) -> bool:
	return u.status == "active" and phase == ("player" if u.faction == "player" else "enemy") and not u.done


## Walk to (x, y). The squad ends facing the way its last step went; pass
## `facing` to take the path that arrives that way (ending on the start tile
## turns the squad by stepping out and back).
## `states` (optional, used by the AI): the squad's reach_states as they stand now.
func move(uid: String, x: int, y: int, facing: Variant = null, states: Variant = null) -> bool:
	facing = _facing_arg(facing)
	var u: Dictionary = unit(uid)
	if not can_act(u) or u.hasMoved:
		return false
	if u.x == x and u.y == y and (facing == null or facing == u.facing):
		return false
	var opt: Variant = move_option(u, x, y, facing, states)
	if opt == null or (facing != null and opt.facing != facing):
		return false
	var path: Array = opt.path
	if path.size() < 2:
		return false
	var before := {"x": u.x, "y": u.y, "facing": u.facing, "movedTiles": u.movedTiles}
	var mark := events.size()
	var rng_before: int = rng.state
	refresh_sight()
	var explored_before: int = explored[u.faction].size()
	var known_before: Array = enemies_of(u).map(func(e): return e.uid)
	walk(u, path)
	u.hasMoved = true
	# A move can be redone only if nothing reacted to it: no free attack,
	# spearwall or overwatch shot, and no dice rolled along the way.
	var clean: bool = rng.state == rng_before
	if fog_enabled() and (explored[u.faction].size() > explored_before or enemies_of(u).any(func(e): return not known_before.has(e.uid))):
		clean = false # Scouting cannot be undone to keep newly learned information for free.
	if clean:
		for i in range(mark, events.size()):
			# A walk cut short and fallen back is no clean move either.
			if events[i].t != "move" or events[i].get("backward", false):
				clean = false
				break
	if u.faction == "player":
		var rec := before.duplicate()
		rec["path"] = path
		rec["scouted"] = fog_enabled() and (explored[u.faction].size() > explored_before or enemies_of(u).any(func(e): return not known_before.has(e.uid)))
		rec["clean"] = clean and u.status == "active"
		move_records[u.uid] = rec
	_after_action(u)
	return true


## Whether a soldier's move this turn can be taken back. Only before the soldier attacks or acts.
## `{ok: bool, reason?: String}`.
func can_redo(uid: String) -> Dictionary:
	var u: Dictionary = unit(uid)
	var r: Variant = move_records.get(uid)
	if phase != "player" or u.status != "active":
		return {"ok": false, "reason": "Only during your turn."}
	if not u.hasMoved or r == null:
		return {"ok": false, "reason": "This soldier has not moved yet."}
	if u.hasActed:
		return {"ok": false, "reason": "This soldier has already attacked or acted."}
	if r.get("scouted", false):
		return {"ok": false, "reason": "Scouting revealed new ground or enemy positions; this move cannot be taken back."}
	if not r.clean:
		return {"ok": false, "reason": "The enemy reacted to this move, so it cannot be taken back."}
	var blocker: Variant = Grid.unit_at(units, r.x, r.y)
	if blocker != null and not is_same(blocker, u):
		return {"ok": false, "reason": "%s now stand on the starting tile." % Squad.squad_name(blocker)}
	return {"ok": true}


## Walk the soldier back to where the turn's move started, ready to move again.
func redo_move(uid: String) -> bool:
	if not can_redo(uid).ok:
		return false
	var u: Dictionary = unit(uid)
	var r: Dictionary = move_records[uid]
	u.x = r.x
	u.y = r.y
	u.facing = r.facing
	u.movedTiles = r.movedTiles
	u.hasMoved = false
	u.done = false
	move_records.erase(uid)
	var back: Array = r.path.duplicate()
	back.reverse()
	_emit({"t": "move", "uid": uid, "path": back})
	_emit({"t": "face", "uid": uid, "facing": r.facing})
	return true


func _flush(u: Dictionary, seg: Array) -> void:
	if seg[0].size() > 1:
		_emit({"t": "move", "uid": u.uid, "path": seg[0]})
	seg[0] = [{"x": u.x, "y": u.y}]


func _stopped(u: Dictionary, fleeing: bool) -> bool:
	return u.status == "dead" or u.status == "downed" or u.status == "fled" or (not fleeing and u.status != "active")


## Whether a squad other than `u` stands on `p`.
func _held_by_other(u: Dictionary, p: Dictionary) -> bool:
	for w in units:
		if not is_same(w, u) and w.x == p.x and w.y == p.y and (w.status == "active" or w.status == "routing"):
			return true
	return false


## Walk a path step by step, resolving reactions. Returns tiles moved.
func walk(u: Dictionary, path: Array) -> int:
	var seg: Array = [[{"x": u.x, "y": u.y}]]
	var trail: Array = [{"x": u.x, "y": u.y}]
	var moved := 0
	var fleeing: bool = u.status == "routing"
	for i in range(1, path.size()):
		var a: Dictionary = path[i - 1]
		var b: Dictionary = path[i]
		# Leaving a zone of control provokes free attacks.
		# Leaving a foe's front or flank provokes a free attack; its rear is blind.
		# Skirmishers slip away untouched.
		var zoc: Array = []
		if not u.tags.has("skirmish"):
			for e in enemies_of(u):
				if Grid.manhattan(e, a) == 1 and can_melee(e, u, e) and e.status == "active" and arc_of(e, a) != "rear":
					zoc.append(e)
		if zoc.size() > 0:
			_flush(u, seg)
			for e in zoc:
				if u.status != "active" and u.status != "routing":
					break
				_resolve_attack(e, u, {"reaction": "zoc", "forceMelee": true})
			if _stopped(u, fleeing):
				break
		var blocker: Variant = Grid.unit_at(units, b.x, b.y)
		if blocker != null and not is_same(blocker, u) and blocker.faction != u.faction:
			break
		u.x = b.x
		u.y = b.y
		refresh_sight()
		u.facing = Grid.dir_to(a, b)
		seg[0].append({"x": b.x, "y": b.y})
		trail.append({"x": b.x, "y": b.y})
		moved += 1
		# Spearwall: entering a guarded tile.
		if u.status == "active":
			var halted := false
			for s in enemies_of(u):
				if s.get("stance") != "spearwall" or Grid.manhattan(s, b) != 1:
					continue
				if arc_of(s, b) == "rear" or s.struck.has(u.uid):
					continue
				if not can_melee(s, u, s):
					continue
				_flush(u, seg)
				s.struck.append(u.uid)
				var hit := _resolve_attack(s, u, {"reaction": "spearwall", "forceMelee": true})
				if hit and (u.status == "active" or u.status == "routing"):
					halted = true
					_emit({"t": "halt", "uid": u.uid, "by": s.uid})
				elif not hit:
					s.erase("stance")
					_emit({"t": "stance", "uid": s.uid, "stance": null})
					_log("%s slip past the spears of %s." % [Squad.squad_name(u), Squad.squad_name(s)])
				if u.status != "active":
					break
			if halted or u.status != "active":
				break
		# Overwatch: moving into a covered tile.
		if u.status == "active":
			for o in active("enemy" if u.faction == "player" else "player"):
				if o.get("stance") != "overwatch":
					continue
				# Crossbowmen watch their front and flanks, not the ground behind them.
				if arc_of(o, u) == "rear":
					continue
				if not can_shoot(o, u, o).ok:
					continue
				_flush(u, seg)
				o.erase("stance")
				_emit({"t": "stance", "uid": o.uid, "stance": null})
				_resolve_attack(o, u, {"reaction": "overwatch"})
				if u.status != "active":
					break
			if _stopped(u, fleeing):
				break
	_flush(u, seg)
	# Cut short while passing through allies (a free attack broke the squad, a
	# spearwall halted it, a foe stood in the way): it falls back along its
	# path, still facing its way, to the last tile it had to itself, so no two
	# squads ever share a tile. (Not in the archived original, which left both
	# squads on the one tile.)
	if u.status == "active" or u.status == "routing":
		var j := trail.size() - 1
		while j > 0 and _held_by_other(u, trail[j]):
			j -= 1
		if j < trail.size() - 1:
			var back: Array = trail.slice(j)
			back.reverse()
			u.x = trail[j].x
			u.y = trail[j].y
			moved = j
			_emit({"t": "move", "uid": u.uid, "path": back, "backward": true})
	u.movedTiles += moved
	return moved


func attack(uid: String, target_uid: String, ability: Variant = null) -> bool:
	var a: Dictionary = unit(uid)
	var t: Dictionary = unit(target_uid)
	if not can_act(a) or a.hasActed:
		return false
	var ab: Variant = DB.ABILITIES.get(ability) if ability else null
	if ab != null and JS.get_or(a.cooldowns, ab.id, 0) > 0:
		return false
	if ab != null and morale_state(a) == "wavering":
		return false
	if ab != null and ab.get("ammoCost") and a.ammo >= 0 and a.ammo < ab.ammoCost:
		return false
	var pv := preview(a, t, {"ability": ability})
	if not pv.legal:
		return false
	# Attacking commits the soldier's move. It does not turn the squad: a
	# squad faces only the way it last stepped.
	move_records.erase(uid)
	var ranged: bool = bool(ab.get("ranged", false)) if ab != null else would_shoot(a, t)
	# Spearmen strike first at anyone who closes in and attacks from the front.
	if (not ranged
		and t.status == "active"
		and t.tags.has("firstStrike")
		and a.movedTiles > 0
		and arc_of(t, a) == "front"
		and not t.struck.has(a.uid)
		and can_melee(t, a, t)):
		t.struck.append(a.uid)
		_resolve_attack(t, a, {"reaction": "firstStrike", "forceMelee": true})
		if a.status != "active":
			a.hasActed = true
			_after_action(a)
			return true
	_resolve_attack(a, t, {"ability": ability, "forceMelee": not ranged})
	if ab != null and ab.get("cooldown"):
		a.cooldowns[ab.id] = ab.cooldown
	a.hasActed = true
	_after_action(a)
	return true


func use_stance(uid: String, ability: String) -> bool:
	var u: Dictionary = unit(uid)
	var ab: Variant = DB.ABILITIES.get(ability)
	if ab == null or not ab.get("stance") or not u.abilities.has(ability):
		return false
	if not can_act(u) or u.hasActed:
		return false
	if morale_state(u) == "wavering":
		return false
	if ab.stance == "overwatch" and (u.ammo == 0 or u.get("shot") == null):
		return false
	u["stance"] = ab.stance
	u.erase("guardSpent")
	u.hasActed = true
	move_records.erase(uid)
	_emit({"t": "stance", "uid": uid, "stance": ab.stance})
	_after_action(u)
	return true


## Whether the squad may use this shout (or other instant act of its own, like
## Lick Wounds) now: `{ok, reason?}`.
func can_shout(u: Dictionary, ability: String) -> Dictionary:
	var ab: Variant = DB.ABILITIES.get(ability)
	if ab == null or ab.kind != "shout" or not u.abilities.has(ability):
		return {"ok": false, "reason": "Not known to this squad"}
	if not can_act(u) or u.hasActed:
		return {"ok": false, "reason": "Has already acted"}
	var cd: int = JS.get_or(u.cooldowns, ability, 0)
	if cd > 0:
		return {"ok": false, "reason": "Ready in %d turns" % cd}
	# Wounds are tended out of reach of the enemy's blades.
	if ab.get("calm") and _enemy_beside(u, u):
		return {"ok": false, "reason": "Not with an enemy beside them"}
	return {"ok": true}


func shout(uid: String, ability: String) -> bool:
	var u: Dictionary = unit(uid)
	if not can_shout(u, ability).ok:
		return false
	var ab: Dictionary = DB.ABILITIES[ability]
	move_records.erase(uid)
	_emit({"t": "shout", "uid": uid, "ability": ability})
	_log("%s: %s!" % [Squad.squad_name(u), ab.name], "good" if u.faction == "player" else "bad")
	var r = JS.get_or(ab, "radius", 4)
	for a in allies_of(u):
		if Grid.dist(a, u) <= r:
			change_morale(a, JS.get_or(ab, "moraleGain", 0), ab.name)
	for e in enemies_of(u):
		if Grid.dist(e, u) <= r:
			change_morale(e, -JS.get_or(ab, "moraleDamage", 0), ab.name)
			# Growl: those it reaches lose their nerve for a turn.
			if ab.has("status") and e.status == "active":
				_add_status(e, ab.status.id, ab.status.turns, u.uid)
	if ab.has("selfHeal"):
		_tend(u, ab)
	u.cooldowns[ability] = JS.get_or(ab, "cooldown", 0)
	u.hasActed = true
	_after_action(u)
	return true


## Lick Wounds: the squad heals its survivors (per soldier standing), closes
## the conditions named in `cleanse` and takes heart. The dead stay dead.
func _tend(u: Dictionary, ab: Dictionary) -> void:
	var healed = Squad.heal_squad(u, rng.rint(ab.selfHeal[0] * u.alive, ab.selfHeal[1] * u.alive))
	if healed > 0:
		_emit({"t": "heal", "uid": u.uid, "amount": healed, "hp": u.hp, "reason": ab.name})
		_log("The wounds of %s close (+%s)." % [Squad.squad_name(u), JS.num_str(healed)], "good" if u.faction == "player" else "bad")
	for id in ab.get("cleanse", []):
		var s: Variant = Squad.status_of(u, id)
		if s != null:
			u.statuses.erase(s)
			_emit({"t": "status", "uid": u.uid, "status": id, "on": false, "turns": 0})
	if ab.get("selfMorale"):
		change_morale(u, mini(ab.selfMorale, u.maxMorale - u.morale), ab.name)


# ---------------------------------------------------------------- spells and war machines

## The squads a spell aimed at `at` would touch, in the order it reaches them,
## with the share of its force each takes: `[{u, role, factor}]`. Lightning
## arcs from the squad struck to the nearest other foes; blasts and stones
## catch every squad on the tiles beside the one struck.
func spell_reach(a: Dictionary, ab: Dictionary, at: Dictionary, from: Variant = null) -> Array:
	var fp: Dictionary = a if from == null else from
	var out: Array = []
	if ab.has("aura"):
		for u in active(a.faction):
			if Grid.manhattan(u, fp) <= ab.aura:
				out.append({"u": u, "role": "aura", "factor": 1})
		return out
	var main: Variant = Grid.unit_at(units, at.x, at.y)
	if main != null and (ab.target == "tile" or ((main.faction != a.faction) if ab.target == "enemy" else (main.faction == a.faction))):
		out.append({"u": main, "role": "main", "factor": 1})
	if ab.get("splash"):
		for n in Grid.neighbors(map, at):
			var u: Variant = Grid.unit_at(units, n.x, n.y)
			if u == null or (not ab.get("friendly", false) and u.faction == a.faction):
				continue
			out.append({"u": u, "role": "splash", "factor": ab.splash})
	if ab.has("chain") and not out.is_empty() and out[0].role == "main":
		var last: Dictionary = out[0].u
		var factor = 1
		var struck := {last.uid: true}
		for j in ab.chain.jumps:
			var near: Array = []
			for u in units:
				if (u.status == "active" or u.status == "routing") and u.faction != a.faction and not struck.has(u.uid) and Grid.manhattan(u, last) <= ab.chain.reach:
					near.append(u)
			if near.is_empty():
				break
			var anchor := last
			near = JS.sort(near, func(p, q): return _chain_order(p, q, anchor))
			var nxt: Dictionary = near[0]
			factor *= ab.chain.falloff
			struck[nxt.uid] = true
			out.append({"u": nxt, "role": "chain", "factor": factor})
			last = nxt
	return out


## Lightning arcs to the nearest foe, the most hurt first, then by uid.
static func _chain_order(p: Dictionary, q: Dictionary, last: Dictionary) -> int:
	var d: int = Grid.manhattan(p, last) - Grid.manhattan(q, last)
	if d != 0:
		return d
	if p.hp != q.hp:
		return p.hp - q.hp
	return -1 if String(p.uid) < String(q.uid) else 1


## Damage range a spell's share `factor` does to `t`: each caster's blow less armour, times the casters standing.
func _spell_damage(a: Dictionary, ab: Dictionary, t: Dictionary, factor: Variant) -> Array:
	var casters: int = maxi(1, a.alive)
	var pierce = 1 if ab.get("ignoreArmor") else JS.get_or(ab, "pierce", 0)
	var armor = t.stats.armor * (1 - pierce)
	var lo: int = maxi(1, JS.rnd(ab.power[0] * factor - armor)) * casters
	var hi: int = maxi(1, JS.rnd(ab.power[1] * factor - armor)) * casters
	return [lo, hi]


## What casting `ability_id` at the tile `at` would do now (opts: from?, movedTiles?).
## SpellPreview `{legal, reason?, ability, at, chance, mods, casters, hits, scatter, moraleHit}`.
func spell_preview(a: Dictionary, ability_id: String, at: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var ab: Variant = DB.ABILITIES.get(ability_id)
	var fv: Variant = opts.get("from")
	var from: Dictionary = {"x": a.x, "y": a.y} if fv == null else fv
	var casters: int = maxi(1, a.alive)
	var mods: Array = []
	var base := {"legal": true, "ability": ability_id, "at": {"x": at.x, "y": at.y}, "chance": 100, "mods": mods, "casters": casters, "hits": [], "scatter": ab != null and bool(ab.get("scatter", false)), "moraleHit": 0}
	if ab == null or ab.kind != "spell":
		return _spell_fail(base, "Not a spell")
	if not a.abilities.has(ability_id):
		return _spell_fail(base, "Not known to this squad")
	if Grid.tile_at(map, at.x, at.y) == null:
		return _spell_fail(base, "Off the field")
	var target: Variant = Grid.unit_at(units, at.x, at.y)
	if fog_enabled() and not visible_tiles(a.faction).has(Grid.key(at.x, at.y)):
		return _spell_fail(base, "Target ground is hidden by fog of war")
	if target != null and not visible_to(a.faction, target) and (ab.target != "tile" or not opts.get("resolve", false)):
		target = null # A concealed occupant must not change a ground-target preview.
	var mtv: Variant = opts.get("movedTiles")
	var moved: bool = (a.movedTiles if mtv == null else mtv) > 0
	if ab.get("engine") and moved:
		return _spell_fail(base, "Cannot loose in a turn it has moved")
	var hostile: bool = ab.has("power")
	var range_v = JS.get_or(ab, "range", 1)
	if ab.target == "self":
		if at.x != from.x or at.y != from.y:
			return _spell_fail(base, "Cast where the casters stand")
	else:
		if ab.target == "enemy" and (target == null or target.faction == a.faction):
			return _spell_fail(base, "Choose an enemy squad")
		if ab.target == "ally" and (target == null or target.faction != a.faction or target.status != "active"):
			return _spell_fail(base, "Choose a friendly squad")
		var d0 := Grid.dist(from, at)
		if hostile and d0 < maxi(1, JS.get_or(ab, "minRange", 1)):
			return _spell_fail(base, "Too close")
		if d0 > range_v + 0.01:
			return _spell_fail(base, "Out of range")
		if ab.get("sight") and d0 > 0 and Grid.line_of_sight(map, from, at).blocked:
			return _spell_fail(base, "No line of sight")
		if hostile and setup.get("darkness") and d0 > range_v - 2:
			return _spell_fail(base, "Too dark to see")
	var chance = 100
	if hostile:
		chance = a.stats.ranged
		mods.append(["Crew skill" if ab.get("engine") else "Spell skill", chance])
		if target != null and target.faction != a.faction:
			# Squads dodge a spell; nobody dodges a falling stone, only its aim.
			var def: int = JS.rnd(float(target.stats.rangedDefense) / (2 if ab.get("engine") else 1))
			chance -= def
			mods.append(["Target defense", -def])
			if target.status == "routing":
				chance += 15
				mods.append(["Fleeing target", 15])
		if ab.get("hitBonus"):
			chance += ab.hitBonus
			mods.append(["Crude engine" if ab.get("engine") else "The spell seeks its mark", ab.hitBonus])
		var d := Grid.dist(from, at)
		if ab.get("engine") and d > 5:
			var m := -JS.rnd((d - 5) * 3)
			chance += m
			mods.append(["Long range", m])
		var ams := morale_state(a)
		var am := 5 if ams == "confident" else -8 if ams == "shaken" else -15 if ams == "wavering" else 0
		if am:
			chance += am
			mods.append(["Confident" if ams == "confident" else "Shaken" if ams == "shaken" else "Wavering", am])
		if _enemy_beside(a, from):
			chance -= 15
			mods.append(["Engaged in melee", -15])
		if Squad.has_status(a, "chilled"):
			chance -= 10
			mods.append(["Chilled", -10])
		if setup.get("darkness"):
			chance -= 10
			mods.append(["Darkness", -10])
		chance = maxi(5, mini(95, JS.rnd(chance)))
	var p: float = float(chance) / 100.0
	var hits: Array = []
	for r in spell_reach(a, ab, at, from):
		var u: Dictionary = r.u
		if not opts.get("resolve", false) and not visible_to(a.faction, u):
			continue
		var ally: bool = u.faction == a.faction
		if ab.has("heal"):
			var missing = u.alive * u.hpPer - u.hp
			var lo = min(missing, ab.heal[0] * casters)
			var hi = min(missing, ab.heal[1] * casters)
			hits.append({"uid": u.uid, "role": r.role, "min": lo, "max": hi, "heal": true, "ally": ally, "soldiers": [0, 0], "kill": 0})
			continue
		if not hostile:
			hits.append({"uid": u.uid, "role": r.role, "min": 0, "max": 0, "heal": false, "ally": ally, "soldiers": [0, 0], "kill": 0})
			continue
		var dm := _spell_damage(a, ab, u, r.factor)
		var killing := 0
		for dmg in range(dm[0], dm[1] + 1):
			if dmg >= u.hp:
				killing += 1
		# Splash from a stone that strays still lands somewhere near; the rest needs the spell to strike home.
		var reach: float = 0.5 + p * 0.5 if r.role == "splash" and ab.get("scatter") else p
		hits.append({"uid": u.uid, "role": r.role, "min": dm[0], "max": dm[1], "heal": false, "ally": ally, "soldiers": [Squad.kills_from(u, dm[0]), Squad.kills_from(u, dm[1])], "kill": (float(killing) / (dm[1] - dm[0] + 1)) * reach})
	var morale_hit := 0
	if target != null:
		for h in hits:
			if h.role == "main" and not h.heal:
				morale_hit = JS.rnd(((h.min + h.max) / 2.0 / target.maxHp) * 28) + JS.get_or(ab, "moraleDamage", 0)
				break
	base.chance = chance
	base.hits = hits
	base.moraleHit = morale_hit
	return base


static func _spell_fail(base: Dictionary, reason: String) -> Dictionary:
	base.legal = false
	base["reason"] = reason
	return base


## Squads (or the caster's own tile) a spell could be cast at right now.
func spell_targets(u: Dictionary, ability_id: String, from: Variant = null) -> Array:
	var ab: Variant = DB.ABILITIES.get(ability_id)
	if ab == null or ab.kind != "spell":
		return []
	if ab.target == "self":
		return [u]
	var fp: Dictionary = u if from == null else from
	var pool: Array = []
	if ab.target == "ally":
		pool = active(u.faction)
	else:
		for x in living():
			if x.faction != u.faction:
				pool.append(x)
	var out: Array = []
	for t in pool:
		if spell_preview(u, ability_id, t, {"from": fp}).legal:
			out.append(t)
	return out


## Whether the squad may use this spell at all now (cooldown, nerve, having acted): `{ok, reason?}`.
func can_cast(u: Dictionary, ability_id: String) -> Dictionary:
	var ab: Variant = DB.ABILITIES.get(ability_id)
	if ab == null or ab.kind != "spell" or not u.abilities.has(ability_id):
		return {"ok": false, "reason": "Not known to this squad"}
	if not can_act(u) or u.hasActed:
		return {"ok": false, "reason": "Has already acted"}
	var cd: int = JS.get_or(u.cooldowns, ability_id, 0)
	if cd > 0:
		return {"ok": false, "reason": "Ready in %d turns" % cd}
	# A war machine's shot is its plain attack; spells need a steady nerve.
	var def: Variant = DB.UNIT_TYPES.get(u.typeId)
	var primary: Variant = def.get("primary") if def != null else null
	if morale_state(u) == "wavering" and primary != ability_id:
		return {"ok": false, "reason": "Too shaken"}
	if ab.get("engine") and u.movedTiles > 0:
		return {"ok": false, "reason": "Cannot loose in a turn it has moved"}
	return {"ok": true}


## Cast a spell (or loose a war machine's stone) at the tile `at`.
func cast(uid: String, ability_id: String, at: Dictionary) -> bool:
	var a: Dictionary = unit(uid)
	if not can_cast(a, ability_id).ok:
		return false
	var pv := spell_preview(a, ability_id, at, {"resolve": true})
	if not pv.legal:
		return false
	move_records.erase(uid)
	var ab: Dictionary = DB.ABILITIES[ability_id]
	_resolve_spell(a, ab, at, pv)
	if ab.get("cooldown"):
		a.cooldowns[ability_id] = ab.cooldown
	a.hasActed = true
	_after_action(a)
	return true


## The spell takes effect. One roll decides whether it strikes home; a stone
## or fireball that misses lands a tile astray. Each squad touched then takes
## one damage roll (or one healing roll): the casters' power is rolled once
## per squad, never per caster.
func _resolve_spell(a: Dictionary, ab: Dictionary, at: Dictionary, pv: Dictionary) -> void:
	if ab.has("power"):
		reveal_combat(a)
	var hostile: bool = ab.has("power")
	var hit: bool = not hostile or rng.next() * 100 < pv.chance
	var impact := {"x": at.x, "y": at.y}
	if not hit and ab.get("scatter"):
		var astray: Array = []
		for dd in [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]]:
			var q := {"x": at.x + dd[0], "y": at.y + dd[1]}
			if Grid.tile_at(map, q.x, q.y) != null and not (q.x == a.x and q.y == a.y):
				astray.append(q)
		if not astray.is_empty():
			impact = astray[rng.rint(0, astray.size() - 1)]
	# A stray stone or fireball strikes whoever stands where it lands, in full.
	var reach: Array = spell_reach(a, ab, impact) if hit or ab.get("scatter") else []
	var casters: int = maxi(1, a.alive)
	var hits: Array = []
	var after: Array = []
	for r in reach:
		var t: Dictionary = r.u
		if t.status != "active" and t.status != "routing":
			continue
		var alive_before: int = t.alive
		var damage := 0
		var heal = 0
		if ab.has("power"):
			var dm := _spell_damage(a, ab, t, r.factor)
			damage = mini(t.hp, rng.rint(dm[0], dm[1]))
			hits_taken[t.uid] = JS.get_or(hits_taken, t.uid, 0) + 1
			Squad.damage_squad(t, damage)
			if t.faction != a.faction:
				a.damageDealt += damage
		if ab.has("heal"):
			heal = Squad.heal_squad(t, rng.rint(ab.heal[0] * casters, ab.heal[1] * casters))
			# Healers learn from the wounds they close.
			if a.faction == "player":
				a.damageDealt += JS.rnd(heal * 0.5)
		var status: Variant = null
		if ab.has("status") and t.hp > 0:
			status = ab.status.id
		elif ab.get("bleed") and damage > 0 and t.hp > 0:
			status = "bleeding"
		var h := {"uid": t.uid, "role": r.role, "damage": damage, "heal": heal, "hp": t.hp, "aliveBefore": alive_before, "aliveAfter": t.alive}
		if status != null:
			h["status"] = status
		if ab.has("power"):
			reveal_combat(t)
		hits.append(h)
		after.append({"t": t, "role": r.role, "damage": damage, "heal": heal, "lost": alive_before - t.alive})
	_emit({"t": "spell", "uid": a.uid, "ability": ab.id, "at": {"x": at.x, "y": at.y}, "impact": impact, "hit": hit, "chance": pv.chance, "casters": casters, "hits": hits})
	if hostile and not hit:
		if ab.get("scatter"):
			_log("%s: %s goes astray%s (%s%%)." % [Squad.squad_name(a), ab.name, "" if not hits.is_empty() else " and lands on empty ground", JS.num_str(pv.chance)], "neutral")
		else:
			var aimed: Variant = Grid.unit_at(units, at.x, at.y)
			_log("%s: %s misses %s (%s%%)." % [Squad.squad_name(a), ab.name, Squad.squad_name(a if aimed == null else aimed), JS.num_str(pv.chance)], "neutral")
	elif not hostile and not ab.has("heal"):
		_log("%s: %s!" % [Squad.squad_name(a), ab.name], "good" if a.faction == "player" else "bad")
	for f in after:
		_spell_aftermath(a, ab, f)


## One squad's consequences of a spell, after the spell event: the log, falls
## and morale, healing's cheer, and the conditions it lays on.
func _spell_aftermath(a: Dictionary, ab: Dictionary, f: Dictionary) -> void:
	var t: Dictionary = f.t
	var damage: int = f.damage
	var lost: int = f.lost
	if ab.has("power"):
		var fallen := ""
		if lost > 0 and t.alive > 0:
			fallen = " %s %s %s." % ["One" if lost == 1 else str(lost), Squad.member_noun(t.typeId, lost), "falls" if lost == 1 else "fall"]
		var friendly := " (their own side!)" if t.faction == a.faction else ""
		var lead := "The lightning arcs to" if f.role == "chain" else "The blast catches" if f.role == "splash" else "%s strikes" % ab.name
		_log("%s %s%s for %d.%s" % [lead, Squad.squad_name(t), friendly, damage, fallen], "bad" if t.faction == "player" else "good")
		var md: int = JS.get_or(ab, "moraleDamage", 0)
		_after_damage(a, t, damage, lost, md if f.role == "main" else JS.rnd(md / 2.0), ab.name)
	if ab.has("heal"):
		if f.heal > 0:
			_log("%s: the wounds of %s close (+%s)." % [ab.name, Squad.squad_name(t), JS.num_str(f.heal)], "good" if t.faction == "player" else "bad")
		if ab.get("moraleGain"):
			change_morale(t, ab.moraleGain, ab.name)
	if t.status != "active" and t.status != "routing":
		return
	if ab.has("status"):
		_add_status(t, ab.status.id, ab.status.turns, a.uid)
		if ab.status.id == "bloodlust":
			_log("%s %s seized by bloodlust!" % [Squad.squad_name(t), "is" if t.leader else "are"], "good" if t.faction == "player" else "bad")
		if not ab.has("heal") and ab.get("moraleGain"):
			change_morale(t, ab.moraleGain, ab.name)
	if ab.get("bleed") and damage > 0:
		_add_status(t, "bleeding", 2, a.uid, maxi(1, JS.rnd(damage * ab.bleed)))


## Lay a condition on a squad (renewing it if it is already there).
func _add_status(t: Dictionary, id: String, turns: int, by: Variant = null, power: Variant = null) -> void:
	var cur: Variant = Squad.status_of(t, id)
	if cur != null:
		cur.turns = maxi(cur.turns, turns)
		if power:
			cur["power"] = maxi(JS.get_or(cur, "power", 0), power)
		if by != null:
			cur["by"] = by
	else:
		var s := {"id": id, "turns": turns}
		if by != null:
			s["by"] = by
		if power != null:
			s["power"] = power
		if not t.has("statuses"):
			t["statuses"] = []
		t.statuses.append(s)
	_emit({"t": "status", "uid": t.uid, "status": id, "on": true, "turns": turns})


## Chill and frenzy wear off at the end of the squad's own turn once their time is up.
func _end_of_turn(faction: String) -> void:
	for u in units:
		if u.faction != faction or u.get("statuses", []).is_empty():
			continue
		for s in u.statuses.duplicate():
			if s.id == "bleeding":
				continue
			s.turns -= 1
			if s.turns > 0:
				continue
			u.statuses.erase(s)
			if u.status == "active" or u.status == "routing":
				_emit({"t": "status", "uid": u.uid, "status": s.id, "on": false, "turns": 0})


## Bleeding wounds open again at the start of the squad's turn.
func _bleed(u: Dictionary) -> void:
	var s: Variant = Squad.status_of(u, "bleeding")
	if s == null or (u.status != "active" and u.status != "routing"):
		return
	var alive_before: int = u.alive
	var damage: int = mini(u.hp, JS.get_or(s, "power", 1))
	Squad.damage_squad(u, damage)
	_emit({"t": "dot", "uid": u.uid, "status": "bleeding", "damage": damage, "hp": u.hp, "aliveBefore": alive_before, "aliveAfter": u.alive})
	var lost: int = alive_before - u.alive
	var fallen := ""
	if lost > 0 and u.alive > 0:
		fallen = " %s %s %s." % ["One" if lost == 1 else str(lost), Squad.member_noun(u.typeId, lost), "dies" if lost == 1 else "die"]
	_log("%s bleed from the gutripper hex (−%d).%s" % [Squad.squad_name(u), damage, fallen], "bad" if u.faction == "player" else "good")
	s.turns -= 1
	if s.turns <= 0:
		u.statuses.erase(s)
		if u.hp > 0:
			_emit({"t": "status", "uid": u.uid, "status": "bleeding", "on": false, "turns": 0})
	var by: Variant = null
	if s.has("by"):
		for x in units:
			if x.uid == s.by:
				by = x
				break
	_after_damage(by, u, damage, lost, 3, "Bleeding")


func end_unit(uid: String) -> void:
	var u: Dictionary = unit(uid)
	u.done = true


func _after_action(u: Dictionary) -> void:
	if u.hasMoved and u.hasActed:
		u.done = true
	check_end()


func end_turn(run_ai: Callable) -> void:
	if phase != "player":
		return
	move_records.clear()
	_end_of_turn("player")
	phase = "enemy"
	_start_turn("enemy")
	if is_over():
		return
	run_ai.call(self)
	if is_over():
		return
	_end_of_turn("enemy")
	_after_enemy_turn()
	if is_over():
		return
	turn += 1
	phase = "player"
	_start_turn("player")


# ---------------------------------------------------------------- the horde

## The horn-bearer sounds the war horn: the band he calls marches in next turn.
func _sound_horn(h: Dictionary) -> void:
	horn = "sounded"
	var ws := waves
	for i in ws.size():
		var w: Dictionary = ws[i]
		if w.get("horn") and wave_state[i] == "pending":
			w.turn = maxi(w.turn, turn + 1)
	_emit({"t": "horn", "uid": h.uid, "sounded": true})
	_log("%s sound the war horn! More of them will come." % Squad.squad_name(h), "bad")
	for e in active("enemy"):
		change_morale(e, 6, "The war horn")
	for p in active("player"):
		change_morale(p, -4, "The war horn")


## The horn-bearer fell before he could call for help.
func _silence_horn() -> void:
	if horn != "waiting":
		return
	for u in units:
		if u.faction == "enemy" and u.tags.has("herald") and (u.status == "active" or u.status == "routing"):
			return
	horn = "silent"
	var h: Variant = null
	for u in units:
		if u.tags.has("herald"):
			h = u
			break
	var ws := waves
	for i in ws.size():
		if ws[i].get("horn") and wave_state[i] == "pending":
			wave_state[i] = "cancelled"
	if h != null:
		_emit({"t": "horn", "uid": h.uid, "sounded": false})
	_log("The war horn falls silent. No help will come for them.", "good")
	for p in active("player"):
		change_morale(p, 4, "The horn is silenced")


## The warchief is slain: the horde loses heart, no more waves come and every foe runs.
func _horde_breaks(chief: Dictionary) -> void:
	_emit({"t": "broken", "uid": chief.uid})
	_log("%s is slain! The horde breaks and flees!" % Squad.squad_name(chief), "good")
	_cancel_pending_waves()
	for e in active("enemy"):
		e.status = "routing"
		e.erase("stance")
		_emit({"t": "rout", "uid": e.uid})
	for p in active("player"):
		change_morale(p, 25, "The warchief is slain")


func _cancel_pending_waves() -> void:
	var out: Array = []
	for s in wave_state:
		out.append("cancelled" if s == "pending" else s)
	wave_state = out


## Squads of due waves march in at their edge; those that find no room wait for the next turn.
func _arrive_waves() -> void:
	# With the field empty, the horde does not wait for its turn.
	var empty: bool = active("enemy").size() == 0
	var hurried := false
	var ws := waves
	for i in ws.size():
		var w: Dictionary = ws[i]
		if wave_state[i] != "pending":
			continue
		if w.get("horn") and horn != "sounded":
			continue
		if w.turn > turn:
			var nw: Variant = next_wave() if (empty and not hurried) else null
			if not (empty and not hurried and nw != null and nw.index == i):
				continue
		if w.turn > turn:
			hurried = true
		var entries: Array = []
		var all_entries: Variant = map.get("entries")
		var lane: Variant = all_entries.get(w.edge) if all_entries != null else null
		if lane != null:
			for p in lane:
				if Grid.tile_passable(map, p.x, p.y) and Grid.unit_at(units, p.x, p.y) == null:
					entries.append(p)
		var waiting: Array = []
		for id in w.uids:
			var wu: Dictionary = unit(id)
			if wu.status == "reserve":
				waiting.append(wu)
		if not _wave_seen.has(i):
			_wave_seen[i] = true
			var is_final: bool = bool(w.get("final", false))
			_emit({"t": "wave", "wave": i, "edge": w.edge, "label": w.label, "count": w.uids.size(), "final": is_final})
			_log("%s: %d more squads march onto the field!" % [w.label, w.uids.size()], "bad")
			for p in active("player"):
				change_morale(p, -7 if is_final else -3, "The warchief's host" if is_final else "Another wave")
		for u in waiting:
			if entries.is_empty():
				break
			var p: Dictionary = entries.pop_front()
			var from := {"x": u.x, "y": u.y}
			u.x = p.x
			u.y = p.y
			u.status = "active"
			u.facing = INWARD[w.edge]
			_emit({"t": "spawn", "uid": u.uid, "from": from, "to": {"x": p.x, "y": p.y}})
		var all_in := true
		for id in w.uids:
			if unit(id).status == "reserve":
				all_in = false
				break
		if all_in:
			wave_state[i] = "arrived"


## Waves due on the coming enemy turn are sighted at the start of the player's turn.
func _warn_waves() -> void:
	var ws := waves
	for i in ws.size():
		var w: Dictionary = ws[i]
		if wave_state[i] != "pending" or (w.get("horn") and horn != "sounded"):
			continue
		if w.turn != turn:
			continue
		_emit({"t": "warn", "wave": i, "edge": w.edge, "turn": w.turn, "label": w.label, "count": w.uids.size()})
		_log("War horns beyond the %s edge: %s will reach the field at the end of this turn." % [EDGE_NAME[w.edge], String(w.label).to_lower()], "bad")


## After the enemy moves: is the held ground lost, and has the relief come?
func _after_enemy_turn() -> void:
	var o := objective
	var zone: Variant = map.get("zone")
	if o.kind == "hold" and zone != null and zone.size() > 0:
		var inside := {}
		for p in zone:
			inside[Grid.key(p.x, p.y)] = true
		var foes := 0
		for u in active("enemy"):
			if inside.has(Grid.key(u.x, u.y)):
				foes += 1
		var ours := 0
		for u in active("player"):
			if inside.has(Grid.key(u.x, u.y)):
				ours += 1
		if foes >= 2 and foes >= ours + 2:
			overrun += 1
			var zone_name: Variant = map.get("zoneName")
			if overrun >= 2:
				_log("%s is overrun. The line is broken." % ("The held ground" if zone_name == null else zone_name), "bad")
				_finish("defeat")
				return
			_emit({"t": "overrun", "turnsLeft": 1})
			_log("The enemy is inside %s! Drive them out before their next turn ends." % ("the line" if zone_name == null else String(zone_name).to_lower()), "bad")
		else:
			overrun = 0
	# A band that cannot break the company in a long fight gives up and slinks off.
	if o.kind == "rout" and turn >= GIVE_UP_TURN and pending_waves() == 0 and active("enemy").size() > 0:
		_log("The enemy has had enough. They slink back into the woods.", "good")
		for e in active("enemy"):
			e.status = "routing"
			_emit({"t": "rout", "uid": e.uid})
		_finish("victory")
		return
	if (o.kind == "survive" or o.kind == "hold") and o.get("turns") != null and turn >= o.turns:
		var relief: Variant = o.get("relief")
		var text: String = "The relief column arrives" if relief == null else relief
		_emit({"t": "relief", "text": text})
		_log("%s! The horde falls back before them." % text, "good")
		_cancel_pending_waves()
		for e in active("enemy"):
			e.status = "routing"
			_emit({"t": "rout", "uid": e.uid})
		_finish("victory")


func _start_turn(faction: String) -> void:
	if fog_enabled():
		for uid in revealed.keys():
			if unit(uid).faction == faction:
				revealed.erase(uid)
		_emit({"t": "sight_reset", "faction": faction})
	_emit({"t": "turn", "faction": faction, "turn": turn})
	if faction == "enemy":
		var o := objective
		var horn_turn: Variant = o.get("hornTurn")
		if horn == "waiting" and horn_turn != null and turn >= horn_turn and _any_horn_wave():
			var herald: Variant = null
			for u in units:
				if u.faction == "enemy" and u.tags.has("herald") and (u.status == "active" or u.status == "routing"):
					herald = u
					break
			if herald != null:
				_sound_horn(herald)
			else:
				_silence_horn()
		_arrive_waves()
	else:
		_warn_waves()
		var o := objective
		if o.get("turns") != null and o.kind != "rout" and turn == o.turns:
			_log("Dawn is breaking. Hold them for one more turn!", "good")
			for p in active("player"):
				change_morale(p, 8, "Relief is near")
	for u in units:
		u.struck = []
	for u in units:
		if u.faction != faction:
			continue
		u.hasMoved = false
		u.hasActed = false
		u.done = false
		u.movedTiles = 0
		var cds: Dictionary = u.cooldowns
		for k in cds.keys():
			cds[k] = maxi(0, cds[k] - 1)
		u.erase("guardSpent")
		if u.get("stance"):
			u.erase("stance")
			_emit({"t": "stance", "uid": u.uid, "stance": null})
		if not u.get("statuses", []).is_empty():
			_bleed(u)
		# Trolls knit their wounds closed, but a fallen troll stays down.
		if u.status == "active" and u.tags.has("regenerate"):
			var healed = Squad.heal_squad(u, JS.rnd(u.hpPer * 0.12) * u.alive)
			if healed > 0:
				_emit({"t": "heal", "uid": u.uid, "amount": healed, "hp": u.hp, "reason": "Regenerates"})
				_log("The wounds of %s close (+%s)." % [Squad.squad_name(u), JS.num_str(healed)], "good" if u.faction == "player" else "bad")
	# Morale upkeep: steady when supported, shaken when surrounded or losing.
	var str_now := strength(faction)
	for u in active(faction):
		var allies := 0
		for a in allies_of(u):
			if Grid.manhattan(a, u) == 1:
				allies += 1
		var foes := 0
		for e in enemies_of(u):
			if Grid.manhattan(e, u) == 1:
				foes += 1
		var d := 0
		var reason := "Steadied"
		if foes == 0:
			d += 2
		d += mini(2, allies) * 2
		if foes >= 2:
			d -= 8
			reason = "Surrounded"
		# While more waves are coming the horde does not count its losses.
		if not u.leader and str_now < 0.5 and not (faction == "enemy" and pending_waves() > 0):
			d -= 12 if str_now < 0.3 else 6
			reason = "The battle is turning"
		var nd: int = mini(d, u.maxMorale - u.morale) if d > 0 else d
		if nd != 0:
			change_morale(u, nd, reason)
	# Routing troops either rally or keep running.
	var routing: Array = []
	for x in units:
		if x.faction == faction and x.status == "routing":
			routing.append(x)
	for u in routing:
		var near := false
		for e in enemies_of(u):
			if Grid.dist(e, u) <= 3:
				near = true
				break
		var p: float = (0.4 if u.faction == "player" else 0.22) + 0.05 * (u.level - 1)
		if not near and rng.chance(p):
			u.status = "active"
			u.morale = JS.rnd(u.maxMorale * 0.3)
			u.done = true
			_emit({"t": "rally", "uid": u.uid})
			_log("%s %s!" % [Squad.squad_name(u), "rallies" if u.leader else "rally"], "good" if u.faction == "player" else "bad")
		else:
			_flee(u)
	check_end()


func _any_horn_wave() -> bool:
	for w in waves:
		if w.get("horn"):
			return true
	return false


func _flee(u: Dictionary) -> void:
	var reach := reachable_full(u)
	var foes := enemies_of(u)
	var best: Variant = null
	var best_score := INF
	var mw: int = map.w
	var mh: int = map.h
	for k in reach:
		var p := {"x": k % 1000, "y": floori(k / 1000.0)}
		if Grid.unit_at(units, p.x, p.y) != null and not (p.x == u.x and p.y == u.y):
			continue
		var edge: int = mini(mini(p.x, p.y), mini(mw - 1 - p.x, mh - 1 - p.y))
		var foe_d := 10.0
		if foes.size() > 0:
			foe_d = INF
			for f in foes:
				foe_d = minf(foe_d, Grid.dist(f, p))
		var s: float = edge * 3 - minf(foe_d, 6.0)
		if s < best_score:
			best_score = s
			best = p
	if best != null and not (best.x == u.x and best.y == u.y):
		var path: Variant = path_from(reach, best.x, best.y)
		if path != null:
			walk(u, path)
	if u.status == "routing" and Grid.is_edge(map, u):
		u.status = "fled"
		_emit({"t": "fled", "uid": u.uid})
		# A horn-bearer who gets away raises the alarm.
		if u.tags.has("herald") and horn == "waiting":
			_sound_horn(u)


func check_end() -> void:
	if phase == "over":
		return
	if company().size() == 0:
		_finish("defeat")
	elif active("enemy").size() == 0 and pending_waves() == 0:
		_finish("victory")


func retreat() -> void:
	if phase != "player":
		return
	for u in active("player"):
		var foe: Variant = null
		for e in enemies_of(u):
			if Grid.manhattan(e, u) == 1:
				foe = e
				break
		if foe != null:
			_resolve_attack(foe, u, {"reaction": "zoc", "forceMelee": true})
	_finish("retreat")


func _finish(res: String) -> void:
	phase = "over"
	result = res
	for u in units:
		if u.status == "routing":
			u.status = "fled"
			_emit({"t": "fled", "uid": u.uid})
	if res == "defeat":
		for u in units:
			if u.faction == "player" and u.status == "downed":
				if rng.chance(0.5):
					u.status = "dead"
					_log("The survivors of %s are left behind on the field." % Squad.squad_name(u), "bad")
	# Experience.
	for u in units:
		if u.faction != "player":
			continue
		if u.status == "dead":
			continue
		# Damage is counted for the whole squad; experience follows one soldier's share.
		u.xp += (5 if res == "victory" else 2) + floori(float(u.damageDealt) / (8 * u.size))
	_emit({"t": "end", "result": res})
