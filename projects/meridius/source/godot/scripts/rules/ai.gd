## The battle AI (enemy horde and the company's automation), a port of src/battle/ai.ts.
##
##   const Ai = preload("res://scripts/rules/ai.gd")
##   b.end_turn(Ai.run_enemy_ai)      # run_enemy_ai(b), run_player_auto(b)
##
## Pure rules: works on a Battle (scripts/rules/battle.gd) and never touches
## nodes or autoloads, so an enemy turn can run on a worker thread. The per-turn
## field cache of the original (a WeakMap keyed by battle) lives in
## `b.ai_cache`.
extends RefCounted

const JS = preload("res://scripts/core/js.gd")
const DB = preload("res://scripts/data/db.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const Squad = preload("res://scripts/rules/squad.gd")

const PLAYER_PROFILES := {
	"footman": {"aggression": 0.55, "caution": 0.45, "swarm": 0.5},
	"spearman": {"aggression": 0.45, "caution": 0.5, "swarm": 0.5},
	"crossbowman": {"aggression": 0.2, "caution": 0.8, "preferRange": 5, "swarm": 0.2},
	"collie_guard": {"aggression": 0.6, "caution": 0.4, "swarm": 0.5},
	"battle_mage": {"aggression": 0.2, "caution": 0.95, "preferRange": 5, "swarm": 0.25, "role": "caster"},
	"ballista": {"aggression": 0.1, "caution": 0.85, "preferRange": 6, "swarm": 0.2, "role": "artillery"},
	"mangonel": {"aggression": 0.1, "caution": 0.85, "preferRange": 6, "swarm": 0.2, "role": "artillery"},
}

const DEFAULT_PROFILE := {"aggression": 0.5, "caution": 0.5}

## Who acts first in the horde: archers loose, the heavy orcs crash into the
## front, riders slip round it, the swarm floods the gaps they opened, and the
## leaders and the horn-bearer come last.
const ROLE_ORDER := {"missile": 0, "caster": 0, "artillery": 0, "shock": 1, "line": 2, "flanker": 3, "swarm": 4, "leader": 5, "herald": 6}


## What a squad can hurl at range, per soldier: its missiles, or a war
## machine's stones. `{avg, range, min}` or null.
static func _missile_of(f: Dictionary) -> Variant:
	var shot: Variant = f.get("shot")
	if shot != null and f.ammo != 0:
		return {"avg": (shot.damage[0] + shot.damage[1]) / 2.0, "range": shot.range, "min": shot.minRange}
	var def: Variant = DB.UNIT_TYPES.get(f.typeId)
	var primary: Variant = def.get("primary") if def != null else null
	var ab: Variant = DB.ABILITIES.get(primary) if primary != null else null
	if ab != null and ab.has("power"):
		return {"avg": (ab.power[0] + ab.power[1]) / 2.0, "range": JS.get_or(ab, "range", 1), "min": JS.get_or(ab, "minRange", 1)}
	return null


static func profile_of(u: Dictionary) -> Dictionary:
	var def: Variant = DB.UNIT_TYPES.get(u.typeId)
	if def != null and def.get("ai") != null:
		return def.ai
	var p: Variant = PLAYER_PROFILES.get(u.typeId)
	if p != null:
		return p
	return DEFAULT_PROFILE


## Expected damage a faction could inflict on each tile next turn: tile key -> value.
static func _danger_map(b, from: String) -> Dictionary:
	var out := {}
	var foes: Array = b.active(from)
	var fdata: Array = []
	for f in foes:
		var miss: Variant = _missile_of(f)
		fdata.append([
			f.x, f.y,
			# Weapon damage is per soldier; a depleted squad threatens less.
			float(f.alive) / f.size,
			Squad.move_of(f) + 1,
			(f.melee[0] + f.melee[1]) / 2.0,
			miss != null,
			miss.min if miss != null else 0,
			miss.range if miss != null else 0,
			miss.avg if miss != null else 0.0,
		])
	for t in b.map.tiles:
		var tx: int = t.x
		var ty: int = t.y
		var d := 0.0
		for fd in fdata:
			var strength: float = fd[2]
			var m: int = absi(fd[0] - tx) + absi(fd[1] - ty)
			if m <= fd[3]:
				d += fd[4] * 0.6 * (1.2 if m <= 1 else 1.0) * strength
			if fd[5]:
				var r := Grid.hypot(float(fd[0] - tx), float(fd[1] - ty))
				if r >= fd[6] and r <= fd[7]:
					d += fd[8] * 0.45 * strength
		out[ty * 1000 + tx] = d
	return out


## Movement-cost distance from every tile to the nearest tile adjacent to a
## foe. `flanks` makes the tiles at a foe's sides and back nearer than those
## at its front, so swarms and riders flow round a line rather than into it.
## `zone` adds the ground the enemy wants to take (last stands).
##
## The original keeps an open list that it stable-sorts by cost before taking
## the first entry; that is the entry with the least cost, the earliest pushed
## among equals. A binary heap on (cost, push order) takes the same entries in
## the same order.
static func _approach_field(b, foes: Array, flanks := false, zone: Variant = null) -> Dictionary:
	var out := {}
	var heap := _Heap.new()
	var map: Dictionary = b.map
	var seeds: Array = []
	for f in foes:
		for n in Grid.neighbors(map, f):
			var arc: String = b.arc_of(f, n) if flanks else "rear"
			seeds.append([n, 0.0 if arc == "rear" else 0.6 if arc == "flank" else 2.0])
	if zone != null:
		for p in zone:
			seeds.append([p, 1.0])
	for sd in seeds:
		var p: Dictionary = sd[0]
		var c: float = sd[1]
		if not Grid.tile_passable(map, p.x, p.y):
			continue
		var k := Grid.key(p.x, p.y)
		if out.get(k, INF) <= c:
			continue
		out[k] = c
		heap.push(c, p.x, p.y)
	var w: int = map.w
	var h: int = map.h
	var tiles: Array = map.tiles
	while heap.size() > 0:
		var cur: Array = heap.pop()
		var cc: float = cur[0]
		var cx: int = cur[2]
		var cy: int = cur[3]
		if cc > out.get(cy * 1000 + cx, INF):
			continue
		var ct: Dictionary = tiles[cy * w + cx]
		var step_cost: float = DB.TERRAIN[ct.terrain].moveCost
		for d in 4:
			var nx: int = cx + Grid.DX[d]
			var ny: int = cy + Grid.DY[d]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			if not Grid.tile_passable(map, nx, ny):
				continue
			if absi(ct.h - tiles[ny * w + nx].h) > 1:
				continue
			var c: float = cc + step_cost
			var k := ny * 1000 + nx
			if c < out.get(k, INF):
				out[k] = c
				heap.push(c, nx, ny)
	return out


## Min-heap on (cost, push order) of [cost, seq, x, y] entries.
class _Heap:
	var items: Array = []
	var seq := 0

	func size() -> int:
		return items.size()

	static func _less(a: Array, b: Array) -> bool:
		return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])

	func push(c: float, x: int, y: int) -> void:
		var e := [c, seq, x, y]
		seq += 1
		items.append(e)
		var i := items.size() - 1
		while i > 0:
			var parent := (i - 1) >> 1
			if _less(e, items[parent]):
				items[i] = items[parent]
				i = parent
			else:
				break
		items[i] = e

	func pop() -> Array:
		var top: Array = items[0]
		var last: Array = items.pop_back()
		var n := items.size()
		if n > 0:
			var i := 0
			while true:
				var l := 2 * i + 1
				if l >= n:
					break
				var r := l + 1
				var m := l
				if r < n and _less(items[r], items[l]):
					m = r
				if _less(items[m], last):
					items[i] = items[m]
					i = m
				else:
					break
			items[i] = last
		return top


## Tile keys of the path to `k`, start first (prev links; a pruned tile cuts the path short).
static func _path_tiles(reach: Dictionary, k: int) -> Array:
	var out: Array = []
	var cur := k
	while cur != -1:
		out.append(cur)
		var info: Variant = reach.get(cur)
		cur = info.prev if info != null else -1
	out.reverse()
	return out


static func _guard_penalty(b, u: Dictionary, tiles: Array, careless: bool, foes: Array) -> float:
	if careless:
		return 0.0
	var pen := 0.0
	# Only foes in a stance can make a path costly.
	var guards: Array = []
	for s in foes:
		var st: Variant = s.get("stance")
		if st == "spearwall" or (st == "overwatch" and s.get("shot") != null):
			guards.append(s)
	if guards.is_empty():
		return 0.0
	for i in range(1, tiles.size()):
		var p := {"x": tiles[i] % 1000, "y": floori(tiles[i] / 1000.0)}
		for s in guards:
			if s.stance == "spearwall" and Grid.manhattan(s, p) == 1 and b.arc_of(s, p) != "rear":
				pen += 14
			if s.stance == "overwatch" and s.get("shot") != null and Grid.dist(s, p) <= s.shot.range and Grid.dist(s, p) >= s.shot.minRange:
				if not Grid.line_of_sight(b.map, s, p).blocked:
					pen += 6
	return pen


static func _target_weight(b, u: Dictionary, t: Dictionary) -> float:
	var role: Variant = profile_of(u).get("role")
	var w := 1.0
	# Riders hunt the crossbowmen; everyone likes a soft target.
	if t.get("shot") != null:
		w += 0.9 if role == "flanker" else 0.3
	if t.status == "routing":
		w -= 0.4
	if t.leader:
		w += 0.3
	if u.faction == "enemy":
		# The horde goes for the weak: thinned squads and shaken ones.
		w += (1 - float(t.hp) / t.maxHp) * 0.5
		var ms: String = b.morale_state(t)
		if ms == "shaken" or ms == "wavering":
			w += 0.3
		if t.tags.has("militia"):
			w += 0.2
	return w


## Per-turn caches: the foes' threat map and approach fields only change when
## the other side moves, and an enemy turn may run thirty squads over them.
static func _cache_for(b, side: String) -> Dictionary:
	var parts: PackedStringArray = []
	for u in b.active(side):
		parts.append("%s:%d,%d,%d,%d" % [u.uid, u.x, u.y, u.facing, u.alive])
	var stamp := "%d|%s|%s" % [b.turn, b.phase, ";".join(parts)]
	var c: Variant = b.ai_cache
	if c == null or c.stamp != stamp:
		c = {"stamp": stamp, "danger": {}, "fields": {}}
		b.ai_cache = c
	return c


static func _cached_danger(b, from: String) -> Dictionary:
	var c := _cache_for(b, from)
	var d: Variant = c.danger.get(from)
	if d == null:
		d = _danger_map(b, from)
		c.danger[from] = d
	return d


static func _cached_approach(b, u: Dictionary, foes: Array, flanks: bool, zone: Variant) -> Dictionary:
	var side := "enemy" if u.faction == "player" else "player"
	var c := _cache_for(b, side)
	var k := "%s|%s|%s" % [side, "true" if flanks else "false", "z" if zone != null else ""]
	var f: Variant = c.fields.get(k)
	if f == null:
		f = _approach_field(b, foes, flanks, zone)
		c.fields[k] = f
	return f


static func _cover_at(b, p: Dictionary, threat: Variant) -> Variant:
	if threat == null:
		return 0
	var c = 0
	for n in Grid.neighbors(b.map, p):
		var t: Dictionary = Grid.tile_at(b.map, n.x, n.y)
		var prop: Variant = t.get("prop")
		if prop and DB.PROPS[prop].cover and Grid.dist(n, threat) < Grid.dist(p, threat):
			c = maxi(c, DB.PROPS[prop].cover)
	return c


## How badly a squad on `at` facing `dir` would be caught by the foes that can
## reach it next turn: blows into its flank count about half, into its back in
## full; frontal blows meet its shields and spears.
static func exposure(at: Dictionary, dir: int, foes: Array) -> float:
	var fx: int = Grid.DX[dir]
	var fy: int = Grid.DY[dir]
	var pen := 0.0
	for e in foes:
		var strength: float = float(e.alive) / e.size
		var m := Grid.manhattan(e, at)
		var threat := 0.0
		if m <= Squad.move_of(e) + 1:
			threat = ((e.melee[0] + e.melee[1]) / 2.0) * strength * (1.5 if m <= 1 else 1.0)
		var miss: Variant = _missile_of(e)
		if miss != null and Grid.dist(e, at) <= miss.range:
			threat = maxf(threat, miss.avg * strength * 0.5)
		if not threat:
			continue
		var dx: float = float(e.x) - float(at.x)
		var dy: float = float(e.y) - float(at.y)
		var len := Grid.hypot(dx, dy)
		if len == 0.0:
			len = 1.0
		var cos_v: float = (fx * dx + fy * dy) / len
		pen += threat * (0.0 if cos_v >= 0.5 else 0.45 if cos_v > -0.5 else 1.0)
	return pen


## Pick the way to arrive on `tile`: a squad faces the way it last stepped, so
## the path decides which side it shows the enemy. Never pays extra free
## attacks for a better facing, and turns in place (out and back) only when it
## clearly helps. Returns a facing or null.
static func choose_facing(b, u: Dictionary, tile: Dictionary, states: Variant = null) -> Variant:
	var options: Array = b.facing_options(u, tile.x, tile.y, states)
	if options.is_empty():
		return null
	var min_zoc = options[0].zoc
	for o in options:
		if o.zoc < min_zoc:
			min_zoc = o.zoc
	var foes: Array = b.enemies_of(u)
	var home: bool = tile.x == u.x and tile.y == u.y
	var best_facing: Variant = null
	var best_s := 0.0
	for o in options:
		if o.zoc > min_zoc:
			continue
		var s: float = exposure(tile, o.facing, foes) + o.cost * 0.05
		if home and o.path.size() > 1:
			s += 4
		if best_facing == null or s < best_s:
			best_facing = o.facing
			best_s = s
	return best_facing


## Worth of a spell in the terms attacks are weighed in (squad damage in one
## caster's share). Harm to foes counts, harm to friends counts against it half
## again; healing counts where wounds are open; a chill or a frenzy counts by
## the blows it will change.
static func _spell_value(b, u: Dictionary, ab: Dictionary, pv: Dictionary) -> float:
	var p: float = pv.chance / 100.0
	var s := 0.0
	for h in pv.hits:
		var t: Dictionary = b.unit(h.uid)
		var avg: float = (h.min + h.max) / 2.0 / u.size
		if h.heal:
			# Wounds that would cost soldiers soon are worth closing first.
			var low: float = 1.3 if float(t.hp) / maxi(1, t.alive * t.hpPer) < 0.6 else 1.0
			s += avg * 0.75 * low * (1.3 if b.is_adjacent_enemy(t) else 1.0)
			continue
		if ab.has("power"):
			var reach: float = 0.5 + p * 0.5 if h.role == "splash" and pv.scatter else p
			if h.ally:
				s -= reach * avg * 1.6 + h.kill * 30
			else:
				s += reach * avg * _target_weight(b, u, t) + h.kill * 22
			if not h.ally and ab.get("bleed"):
				s += p * avg * ab.bleed * 2
			if not h.ally and ab.has("status") and ab.status.id == "chilled":
				s += p * 3 * (float(t.alive) / t.size) * (1.5 if Grid.manhattan(t, u) <= Squad.move_of(t) + 2 else 1.0)
			continue
		if ab.has("status") and ab.status.id == "bloodlust" and h.ally and t.get("shot") == null and not Squad.has_status(t, "bloodlust"):
			# A frenzy is worth the extra blows of a squad about to fight.
			var near := false
			for f in b.enemies_of(t):
				if Grid.manhattan(f, t) <= Squad.move_of(t) + 1:
					near = true
					break
			if not near:
				continue
			var blows: float = t.alive * (3 + ((t.melee[0] + t.melee[1]) / 2.0) * 0.1)
			s += (blows / u.size) * (0.7 if t.hasActed else 1.4) - 1.5
	return s + p * pv.moraleHit * 0.35


## Tiles worth aiming a spell of this kind at: squads to strike or bless, and for blasts the ground beside foes.
static func _spell_aims(b, u: Dictionary, ab: Dictionary, from: Dictionary) -> Array:
	var rng_v: float = JS.get_or(ab, "range", 1) + 0.01
	if ab.target == "self":
		return [{"x": from.x, "y": from.y}]
	if ab.target == "ally":
		var allies: Array = []
		for a in b.active(u.faction):
			if Grid.dist(a, from) <= rng_v:
				allies.append(a)
		return allies
	var foes: Array = []
	for f in b.living():
		if f.faction != u.faction and Grid.dist(f, from) <= rng_v + 1:
			foes.append(f)
	if ab.target == "enemy":
		var out_e: Array = []
		for f in foes:
			if Grid.dist(f, from) <= rng_v:
				out_e.append(f)
		return out_e
	var out := {}
	for f in foes:
		out[Grid.key(f.x, f.y)] = {"x": f.x, "y": f.y}
		if ab.get("splash"):
			for n in Grid.neighbors(b.map, f):
				if Grid.dist(n, from) <= rng_v:
					out[Grid.key(n.x, n.y)] = n
	var aims: Array = []
	for q in out.values():
		if Grid.dist(q, from) <= rng_v:
			aims.append(q)
	return aims


## The best spell to cast from `from`, if any is worth casting: `{id, at, s, pv}` or null.
static func _best_spell(b, u: Dictionary, spells: Array, from: Dictionary, moved: int) -> Variant:
	var best: Variant = null
	for id in spells:
		var ab: Dictionary = DB.ABILITIES[id]
		if ab.get("engine") and moved > 0:
			continue
		for at in _spell_aims(b, u, ab, from):
			var pv: Dictionary = b.spell_preview(u, id, at, {"from": from, "movedTiles": moved})
			if not pv.legal or pv.hits.is_empty():
				continue
			var s := _spell_value(b, u, ab, pv)
			if best == null or s > best.s:
				best = {"id": id, "at": {"x": at.x, "y": at.y}, "s": s, "pv": pv}
	return best


static func _nearest_foe(foes: Array, p: Dictionary) -> float:
	var m := INF
	for f in foes:
		m = minf(m, Grid.dist(f, p))
	return m


static func act_unit(b, u: Dictionary, opts: Dictionary = {}) -> void:
	if u.status != "active" or b.is_over():
		return
	var prof := profile_of(u)
	var foes: Array = b.enemies_of(u)
	var all_foes: Array = foes.duplicate()
	for x in b.units:
		if x.status == "routing" and x.faction != u.faction:
			all_foes.append(x)
	if all_foes.is_empty():
		return
	var ms: String = b.morale_state(u)

	# Leaders shout when the warband wavers or the enemy closes in.
	for ab in u.abilities:
		var def: Variant = DB.ABILITIES.get(ab)
		if def == null or def.kind != "shout" or JS.get_or(u.cooldowns, ab, 0) > 0 or u.hasActed:
			continue
		var r = JS.get_or(def, "radius", 4)
		var shaky := 0
		for a in b.allies_of(u):
			if Grid.dist(a, u) <= r and float(a.morale) / a.maxMorale < 0.6:
				shaky += 1
		var close := 0
		for f in foes:
			if Grid.dist(f, u) <= r:
				close += 1
		if shaky >= 2 or close >= 2:
			b.shout(u.uid, ab)

	var carelessness = JS.get_or(prof, "carelessness", 0)
	var careless: bool = b.rng.chance(carelessness)
	var danger := _cached_danger(b, "enemy" if u.faction == "player" else "player")
	# The horn-bearer hangs back only until his horn has sounded; then he fights like the rest.
	var role: Variant = prof.get("role")
	if role == "herald" and b.horn != "waiting":
		role = "line"
	# The company's own automation holds its ground in a last stand, and keeps
	# a reserve standing in the ground to hold so it is never simply walked into.
	var hold: Variant = opts.get("hold")
	var map_zone: Variant = b.map.get("zone")
	var zone_keys: Variant = null
	if hold != null and map_zone != null:
		zone_keys = {}
		for p in map_zone:
			zone_keys[Grid.key(p.x, p.y)] = true
	var guards := 2
	if zone_keys != null:
		guards = 0
		for a in b.allies_of(u):
			if zone_keys.has(Grid.key(a.x, a.y)):
				guards += 1
	var reach: Dictionary
	# The squad's search states: nothing changes the battle between here and its
	# move, so choose_facing and b.move reuse them instead of searching again.
	var states: Variant = null
	if u.hasMoved:
		reach = {Grid.key(u.x, u.y): {"cost": 0, "prev": -1, "zoc": 0}}
	else:
		states = b.reach_states(u)
		reach = b.reachable(u, null, states)
	var timid: bool = ms == "shaken" or ms == "wavering"
	var aggression: float = prof.aggression * 0.4 if timid else float(prof.aggression)
	var caution: float = minf(1.0, prof.caution + 0.4) if timid else float(prof.caution)
	var swarm = JS.get_or(prof, "swarm", 0)
	var prefer_range: Variant = prof.get("preferRange")
	var u_shot: Variant = u.get("shot")

	# An attack is worth making when its expected value clears this bar. Steady
	# troops take any worthwhile attack and pick the safest tile for it; shaken
	# ones only strike when the whole plan, position included, clears it.
	# The horde never stands idle beside the enemy: swarms hack at anything in reach.
	var horde: bool = u.faction == "enemy" and role != "herald" and role != "missile"
	var min_attack: float = 0.8 if horde and (role == "swarm" or role == "shock") else 2.0
	var best: Variant = null
	var attack_options: Array = [null]
	if ms != "wavering":
		for ab in u.abilities:
			var def: Variant = DB.ABILITIES.get(ab)
			if def != null and def.kind == "attack" and def.get("damageMult") and JS.get_or(u.cooldowns, ab, 0) == 0:
				attack_options.append(ab)
	# Spells ready to cast (a war machine's stone is its plain attack and needs no nerve).
	var spells: Array = []
	if not u.hasActed:
		for id in u.abilities:
			var def: Variant = DB.ABILITIES.get(id)
			if def != null and def.kind == "spell" and b.can_cast(u, id).ok:
				spells.append(id)
	var ranged: bool = Squad.is_backline(u)

	# Nothing below changes the battle until the plan is chosen, so the
	# squad's allies and the target weights are looked up once.
	var allies: Array = b.allies_of(u)
	# guardPenalty reads b.enemiesOf(u) as it stands now (a shout may have routed foes).
	var guard_foes: Array = b.enemies_of(u)
	var weights := {}
	for t in all_foes:
		weights[t.uid] = _target_weight(b, u, t)
	var t_range: int = u_shot.range + 3 if u_shot != null else 3

	for k in reach:
		var info: Dictionary = reach[k]
		var tile := {"x": k % 1000, "y": floori(k / 1000.0)}
		var tiles := _path_tiles(reach, k)
		var moved := tiles.size() - 1
		var zoc_cost = info.zoc * 6 * (1 - carelessness * 0.5)
		var guard := _guard_penalty(b, u, tiles, careless, guard_foes)
		var dng = JS.get_or(danger, k, 0) * caution * 0.6
		var adj_allies := 0
		for a in allies:
			if Grid.manhattan(a, tile) == 1:
				adj_allies += 1
		var tile_h: int = Grid.tile_at(b.map, tile.x, tile.y).h
		var outside := _outside(hold, zone_keys, guards, k)
		var pos_score = -zoc_cost - guard - dng + swarm * adj_allies * 3 + tile_h * 1.5 - outside
		# The horn-bearer keeps well out of reach.
		if role == "herald":
			pos_score -= maxf(0.0, 6 - _nearest_foe(foes, tile)) * 4
		if ranged:
			var nf := _nearest_foe(foes, tile)
			if nf <= 1.01:
				pos_score -= 12
			if prefer_range:
				pos_score -= absf(nf - prefer_range) * 1.2
			pos_score += _cover_at(b, tile, foes[0] if foes.size() > 0 else null) * 0.15

		if not spells.is_empty():
			var sp: Variant = _best_spell(b, u, spells, tile, moved)
			if sp != null:
				var sscore: float = sp.s * (0.6 + aggression) + pos_score
				if (sscore if timid else sp.s) >= min_attack and (best == null or sscore > best.score):
					best = {"score": sscore, "tile": tile, "spell": {"id": sp.id, "at": sp.at}}

		if not u.hasActed and role != "herald":
			for t in all_foes:
				if Grid.manhattan(t, tile) > t_range:
					continue
				for ab in attack_options:
					var popts := {"from": tile, "ability": ab, "movedTiles": moved}
					# Melee squads: a cheap legality check first (most targets are out of reach).
					if u_shot == null and not b.preview_legal(u, t, popts):
						continue
					var pv: Dictionary = b.preview(u, t, popts)
					if not pv.legal:
						continue
					# Squad damage in one full-strength soldier's terms, so it weighs
					# against position the way a single blow always has.
					var avg: float = (pv.min + pv.max) / 2.0 / u.size
					var p: float = pv.chance / 100.0
					# Morale only breaks on a hit, so it counts at the hit chance like damage does.
					var s: float = p * avg * weights[t.uid] + pv.kill * 22 + p * pv.moraleHit * 0.35
					if pv.arc == "rear":
						s += 3 * p
					# Swarms and riders go round the shields: sides and backs first.
					if role == "swarm" or role == "flanker":
						s += (2.5 if pv.arc == "flank" else 5.0 if pv.arc == "rear" else 0.0) * p
					if role == "flanker" and pv.arc == "front" and (t.get("stance") == "spearwall" or t.tags.has("firstStrike")):
						s -= 4
					# Piling onto a squad already beset breaks it.
					if role == "swarm":
						var beset := 0
						for a in allies:
							if Grid.manhattan(a, t) == 1 and not (a.x == tile.x and a.y == tile.y):
								beset += 1
						s += beset * 1.2
					if t.status == "routing":
						s *= 0.5
					# Spearmen strike first at chargers from the front.
					if u_shot == null and t.tags.has("firstStrike") and moved > 0 and pv.arc == "front" and not careless:
						s -= 7
					var score: float = s * (0.6 + aggression) + pos_score
					if (score if timid else s) < min_attack:
						continue
					if best == null or score > best.score:
						best = {"score": score, "tile": tile, "target": t, "ability": ab}

	# Without a worthwhile attack, advance (or hold) according to temperament.
	if best == null:
		# The horde makes for the ground it means to take as much as for the company.
		var zone: Variant = b.map.get("zone") if u.faction == "enemy" and b.objective.kind == "hold" else null
		var field := _cached_approach(b, u, foes, role == "swarm" or role == "flanker", zone)
		var move_plan: Variant = null
		for k in reach:
			var info: Dictionary = reach[k]
			var tile := {"x": k % 1000, "y": floori(k / 1000.0)}
			var tiles := _path_tiles(reach, k)
			var approach = field.get(k, 30)
			var adj_allies := 0
			for a in allies:
				if Grid.manhattan(a, tile) == 1:
					adj_allies += 1
			var s = (-approach * aggression * 2
				- JS.get_or(danger, k, 0) * caution * 0.5
				- info.zoc * 6
				- _guard_penalty(b, u, tiles, careless, guard_foes)
				+ swarm * adj_allies * 2
				+ Grid.tile_at(b.map, tile.x, tile.y).h * 1.5
				- _outside(hold, zone_keys, guards, k))
			if role == "herald":
				s -= maxf(0.0, 6 - _nearest_foe(foes, tile)) * 4
			# A war machine that moves cannot loose this turn or be laid well: it shifts only when it must.
			if u.tags.has("engine") and role != "shock" and k != Grid.key(u.x, u.y):
				s -= 4
			if ranged and prefer_range:
				var nf := _nearest_foe(foes, tile)
				s -= absf(nf - prefer_range) * 2
				var reach_of = u_shot.range if u_shot != null else (_missile_of(u).range if _missile_of(u) != null else 5)
				var lobs: bool = u.tags.has("artillery")
				var seen := false
				for f in foes:
					if (lobs or not Grid.line_of_sight(b.map, tile, f).blocked) and Grid.dist(tile, f) <= reach_of:
						seen = true
						break
				if seen:
					s += 4
				s += _cover_at(b, tile, foes[0] if foes.size() > 0 else null) * 0.15
			if move_plan == null or s > move_plan.score:
				move_plan = {"score": s, "tile": tile}
		best = move_plan
	if best == null:
		return

	if not u.hasMoved:
		var facing: Variant = choose_facing(b, u, best.tile, states)
		var home: bool = best.tile.x == u.x and best.tile.y == u.y
		if not home or (facing != null and facing != u.facing):
			b.move(u.uid, best.tile.x, best.tile.y, facing, states)
	if u.status != "active" or b.is_over():
		return

	var spell: Variant = best.get("spell")
	if spell != null and not u.hasActed:
		# Cast as planned; if the target moved or fell on the way, choose again from here.
		if not b.cast(u.uid, spell.id, spell.at):
			var again: Array = []
			for id in u.abilities:
				var def: Variant = DB.ABILITIES.get(id)
				if def != null and def.kind == "spell" and b.can_cast(u, id).ok:
					again.append(id)
			var sp: Variant = _best_spell(b, u, again, u, u.movedTiles)
			if sp != null and sp.s >= min_attack:
				b.cast(u.uid, sp.id, sp.at)
		if u.status != "active" or b.is_over():
			return

	var best_target: Variant = best.get("target")
	if best_target != null and not u.hasActed:
		var target: Variant = best_target
		var ability: Variant = best.get("ability")
		if not b.preview(u, target, {"ability": ability}).legal or (target.status != "active" and target.status != "routing"):
			# Re-pick from where we actually ended up.
			var options: Array = []
			for t in b.targets(u):
				options.append({"t": t, "pv": b.preview(u, t)})
			_sort_options(options)
			target = options[0].t if options.size() > 0 else null
			ability = null
		if target != null:
			b.attack(u.uid, target.uid, ability)
	elif not u.hasActed and ms != "wavering":
		# Attacks cost nothing, so a unit that ends its move within reach strikes
		# anyway rather than standing idle beside the enemy.
		var options: Array = []
		for t in b.targets(u):
			var pv: Dictionary = b.preview(u, t)
			if pv.legal and pv.chance >= (5 if horde else 15):
				options.append({"t": t, "pv": pv})
		_sort_options(options)
		if options.size() > 0:
			b.attack(u.uid, options[0].t.uid)

	if u.status != "active" or b.is_over():
		return

	# Player-side automation (simulation) can use stances.
	if opts.get("useStances") and not u.hasActed:
		var stance: Variant = null
		for a in u.abilities:
			var def: Variant = DB.ABILITIES.get(a)
			if def != null and def.kind == "stance":
				stance = a
				break
		if stance != null:
			var threat := false
			for f in foes:
				if Grid.dist(f, u) <= f.stats.move + 2:
					threat = true
					break
			if threat:
				b.use_stance(u.uid, stance)


static func _outside(hold: Variant, zone_keys: Variant, guards: int, k: int) -> int:
	return (12 if hold != null and not hold.has(k) else 0) - (8 if zone_keys != null and guards < 2 and zone_keys.has(k) else 0)


## Best expected damage first (stable, as the original's sort).
static func _sort_options(options: Array) -> void:
	JS.sort(options, func(a, c): return c.pv.chance * (c.pv.min + c.pv.max) - a.pv.chance * (a.pv.min + a.pv.max))


static func run_enemy_ai(b) -> void:
	var players: Array = b.active("player")
	var order: Array = b.active("enemy")
	var rank := {}
	var near := {}
	for u in order:
		var r := 0
		if u.get("shot") != null:
			r = 0
		elif u.leader:
			r = 5
		else:
			var role: Variant = profile_of(u).get("role")
			r = JS.get_or(ROLE_ORDER, "line" if role == null else role, 2)
		rank[u.uid] = r
		var d := 99.0
		var m := INF
		for p in players:
			m = minf(m, Grid.dist(p, u))
		near[u.uid] = minf(m, d)
	JS.sort(order, func(a, c):
		var ra: int = rank[a.uid]
		var rc: int = rank[c.uid]
		if ra != rc:
			return ra - rc
		return near[a.uid] - near[c.uid])
	for u in order:
		if b.is_over():
			return
		if u.status != "active":
			continue
		act_unit(b, u)


## Plays the player's side automatically (used by the simulator and tests).
## In a last stand it holds the deployment ground and the ground to keep, as a
## sensible commander would, instead of marching out to meet the horde.
static func run_player_auto(b) -> void:
	var o: Dictionary = b.objective
	var hold: Variant = null
	if o.kind == "hold" or o.kind == "survive":
		hold = {}
		for p in b.map.playerDeploy:
			hold[Grid.key(p.x, p.y)] = true
		var zone: Variant = b.map.get("zone")
		if zone != null:
			for p in zone:
				hold[Grid.key(p.x, p.y)] = true
	var order: Array = b.active("player")
	JS.sort(order, func(a, c): return (0 if Squad.is_backline(a) else 1) - (0 if Squad.is_backline(c) else 1))
	for u in order:
		if b.is_over():
			return
		if u.status != "active":
			continue
		act_unit(b, u, {"useStances": true, "hold": hold})
