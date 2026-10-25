## Port of src/battle/setup.ts: encounter rolls and battle setups.
##
## An EncounterRoll is a Dictionary {encounterId, mapId, seed, enemies:
## [{typeId, level}], ambush, waves: [Wave], allies: [{typeId, level}]}; waves
## keep edges in the map template's own terms. A BattleSetup is the Dictionary
## Battle.new() takes: {seed, map, units, survivalBonus, ambush, enemyFirst,
## darkness?, title, encounterId, kind, objective, waves}. Every wave's squads
## are in `units` from the start, as reserves staged off the field.
## Use through `const Setup = preload("res://scripts/rules/setup.gd")`.
extends RefCounted

const JS = preload("res://scripts/core/js.gd")
const Rng = preload("res://scripts/core/rng.gd")
const DB = preload("res://scripts/data/db.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const MapGen = preload("res://scripts/rules/mapgen.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const Soldier = preload("res://scripts/meta/soldier.gd")
const Squad = preload("res://scripts/rules/squad.gd")


static func roll_encounter(encounter_id: String, rng: RefCounted, depth: int) -> Dictionary:
	var e := DB.encounter_by_id(encounter_id)
	var level := func() -> int:
		return mini(e.level[1], e.level[0] + (1 if rng.chance(0.15 + depth * 0.1) else 0))
	var roll_units := func(list: Array) -> Array:
		var out: Array = []
		for entry in list:
			var n: int = rng.rint(entry[1], entry[2])
			for i in n:
				out.append({"typeId": entry[0], "level": level.call()})
		return out
	var enemies: Array = roll_units.call(e.units)
	var maps: Array = e.maps
	if e.get("ambush"):
		maps = maps.filter(func(m: String) -> bool: return not DB.BATTLE_MAPS[m].get("river", false))
	var map_id: String = rng.pick(maps)
	var tpl: Dictionary = DB.BATTLE_MAPS[map_id]
	var edges: Variant = tpl.get("edges")
	var main: String = edges.main if edges != null else "n"
	var flanks: Array = edges.flank if edges != null else ["w", "e"]
	var waves: Array = []
	for w in JS.get_or(e, "waves", []):
		var units: Array = roll_units.call(w.units)
		if w.get("warchief") != null:
			for u in units:
				if u.typeId == w.warchief:
					u.warchief = true
					break
		var edge: String
		if w.edge == "main":
			edge = main
		elif w.edge == "flank":
			edge = rng.pick(flanks)
		else:
			edge = w.edge
		var wave := {"turn": w.turn, "edge": edge, "units": units}
		if w.get("horn") != null:
			wave.horn = w.horn
		if w.get("final") != null:
			wave.final = w.final
		wave.label = w.label
		waves.append(wave)
	var allies: Array = []
	for a in JS.get_or(e, "allies", []):
		for i in int(a[1]):
			allies.append({"typeId": a[0], "level": 1})
	var seed: int = rng.rint(1, 2147483647)
	return {
		"encounterId": encounter_id,
		"mapId": map_id,
		"seed": seed,
		"enemies": enemies,
		"ambush": bool(e.get("ambush", false)),
		"waves": waves,
		"allies": allies,
	}


## Deployment order: shields in front, then spears and levies, missiles at the back.
static func _rank(u: Dictionary) -> int:
	if Squad.is_backline(u):
		return 3
	if u.typeId == "footman" or u.typeId == "collie_guard":
		return 0
	if u.typeId == "spearman":
		return 1
	return 2


static func _centre(ps: Array) -> Dictionary:
	var sx := 0.0
	var sy := 0.0
	for p in ps:
		sx += p.x
		sy += p.y
	return {"x": sx / ps.size(), "y": sy / ps.size()}


static func _pk(p: Dictionary) -> String:
	return "%d,%d" % [p.x, p.y]


## Place the player's army in a formation: shields toward the enemy, crossbows behind.
static func deploy_player(map: Dictionary, units: Array, ambush: bool) -> void:
	var zone: Array = map.playerDeploy.duplicate()
	var sorted: Array = JS.sort(units.duplicate(), func(a: Dictionary, b: Dictionary) -> int: return _rank(a) - _rank(b))
	if ambush:
		var mid := {"x": map.w / 2.0 - 0.5, "y": map.h / 2.0 - 0.5}
		JS.sort(zone, func(a: Dictionary, b: Dictionary) -> float: return Grid.dist(a, mid) - Grid.dist(b, mid))
		# Ranged in the middle, melee around them.
		var order: Array = sorted.filter(func(u: Dictionary) -> bool: return Squad.is_backline(u))
		order.append_array(sorted.filter(func(u: Dictionary) -> bool: return not Squad.is_backline(u)))
		var i := 0
		for u in order:
			if i >= zone.size():
				push_error("deployPlayer: more squads than deployment tiles")
				return
			var p: Dictionary = zone[i]
			i += 1
			u.x = p.x
			u.y = p.y
		return
	# Behind walls: hold the ways in. Each gateway, breach or gap into the
	# deployment ground gets a shield or spear squad, nearest the enemy first;
	# missiles and levies stand behind them.
	if map.get("scale") == "large":
		var inside := {}
		for p in zone:
			inside[_pk(p)] = true
		var foe_c := _centre(map.enemyDeploy if not map.enemyDeploy.is_empty() else [{"x": map.w / 2.0, "y": 0}])
		# A way in is a gap at most two tiles wide in a wall or fence: count the
		# open tiles across the gap, two either side.
		var narrow := func(q: Dictionary, dx: int, dy: int) -> bool:
			var open := 0
			for s in range(-2, 3):
				if MapGen._clear_ground(map, q.x + dy * s, q.y + dx * s):
					open += 1
			return open <= 2
		var ways: Array = zone.filter(func(p: Dictionary) -> bool:
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var q := {"x": p.x + d[0], "y": p.y + d[1]}
				if not inside.has(_pk(q)) and MapGen._clear_ground(map, q.x, q.y) and narrow.call(q, d[0], d[1]):
					return true
			return false
		)
		JS.sort(ways, func(a: Dictionary, b: Dictionary) -> float: return Grid.dist(a, foe_c) - Grid.dist(b, foe_c))
		# Only the narrow ways in: a long open edge is not a gate.
		if ways.size() > 0 and ways.size() <= 8:
			var used := {}
			var holders: Array = sorted.filter(func(u: Dictionary) -> bool: return not Squad.is_backline(u) and not u.tags.has("militia"))
			var rest: Array = sorted.filter(func(u: Dictionary) -> bool: return not holders.has(u))
			for i in ways.size():
				if i < holders.size():
					_take(used, ways[i], holders[i])
			var spare: Array = holders.slice(ways.size()) + rest
			var mid := _centre(ways if not ways.is_empty() else zone)
			var way_keys := {}
			for w in ways:
				way_keys[_pk(w)] = true
			for u in spare:
				# Behind the ways in: close to them, but not on them.
				var free: Array = zone.filter(func(p: Dictionary) -> bool: return not used.has(_pk(p)))
				JS.sort(free, func(a: Dictionary, b: Dictionary) -> float: return Grid.dist(a, mid) - Grid.dist(b, mid))
				var p: Variant = null
				for q in free:
					if not way_keys.has(_pk(q)):
						p = q
						break
				if p == null and not free.is_empty():
					p = free[0]
				if p != null:
					_take(used, p, u)
			return
	# Forward is toward the enemy's ground; ranks stand across that line.
	var foe := _centre(map.enemyDeploy if not map.enemyDeploy.is_empty() else [{"x": map.w / 2.0, "y": 0}])
	var mid2 := _centre(zone)
	var len := Grid.dist(mid2, foe)
	if len == 0:
		len = 1
	var fx: float = (foe.x - mid2.x) / len
	var fy: float = (foe.y - mid2.y) / len
	var depths: Array = []
	var laterals: Array = []
	var front := INF
	for p in zone:
		var dp: float = -((p.x - mid2.x) * fx + (p.y - mid2.y) * fy)
		depths.append(dp)
		laterals.append(absf((p.x - mid2.x) * fy - (p.y - mid2.y) * fx))
		front = minf(front, dp)
	var used2 := {}
	var offsets := [0, 1, 1.6, 2.4]
	for u in sorted:
		var want: float = front + offsets[_rank(u)]
		var best := -1
		var best_cost := INF
		for i in zone.size():
			if used2.has(_pk(zone[i])):
				continue
			var c: float = absf(depths[i] - want) * 2 + laterals[i] * 0.7
			if c < best_cost:
				best_cost = c
				best = i
		var p: Dictionary = zone[best] if best >= 0 else zone[0]
		used2[_pk(p)] = true
		u.x = p.x
		u.y = p.y


static func _take(used: Dictionary, p: Dictionary, u: Dictionary) -> void:
	used[_pk(p)] = true
	u.x = p.x
	u.y = p.y


static func deploy_enemies(map: Dictionary, units: Array, rng: RefCounted, ambush: bool) -> void:
	var zone: Array = rng.shuffle(map.enemyDeploy.duplicate())
	var melee: Array = units.filter(func(u: Dictionary) -> bool: return not Squad.is_backline(u))
	var ranged: Array = units.filter(func(u: Dictionary) -> bool: return Squad.is_backline(u))
	var mid_y: float = map.h / 2.0
	# Ranged prefer rows far from the player; melee the near rows.
	var far := func(p: Dictionary) -> float: return -absf(p.y - mid_y) if ambush else float(p.y)
	var by_far: Array = JS.sort(zone.duplicate(), func(a: Dictionary, b: Dictionary) -> float: return far.call(a) - far.call(b))
	var used := {}
	for u in ranged:
		_place(used, u, by_far)
	var near: Array = by_far.duplicate()
	near.reverse()
	for u in melee:
		_place(used, u, by_far if u.leader else near)


static func _place(used: Dictionary, u: Dictionary, list: Array) -> void:
	for q in list:
		if not used.has(_pk(q)):
			used[_pk(q)] = true
			u.x = q.x
			u.y = q.y
			return


## Every squad takes the field facing the nearest enemies (the centre of the three closest).
static func face_each_other(units: Array) -> void:
	for u in units:
		if u.status == "reserve":
			continue
		var foes: Array = units.filter(func(f: Dictionary) -> bool: return f.faction != u.faction and f.status != "reserve")
		JS.sort(foes, func(a: Dictionary, b: Dictionary) -> float: return Grid.dist(a, u) - Grid.dist(b, u))
		foes = foes.slice(0, 3)
		if foes.is_empty():
			continue
		u.facing = Grid.dir_to(u, _centre(foes))


## A local levy fighting beside the company: player-controlled, not on the roster.
static func _make_ally(type_id: String, level: int, uid: String, rng: RefCounted, leader: String) -> Dictionary:
	var u := Soldier.make_enemy(type_id, level, uid, rng)
	u.faction = "player"
	u.name = "%s, militia" % leader
	return u


## Where the squads of coming waves wait beyond their edge, in view: lined up
## behind the entry tiles, later waves further back.
static func _stage(map: Dictionary, waves: Array, by_uid: Dictionary) -> void:
	var rank_at := {}
	var ordered: Array = JS.sort(waves.duplicate(), func(a: Dictionary, b: Dictionary) -> int: return a.turn - b.turn)
	var entries: Dictionary = JS.get_or(map, "entries", {})
	for w in ordered:
		var lanes: Array = JS.get_or(entries, w.edge, [])
		var out: Dictionary = MapGen.OUTWARD[w.edge]
		var r: int = rank_at.get(w.edge, 0)
		rank_at[w.edge] = r + ceili(float(w.uids.size()) / maxi(1, mini(lanes.size(), 4))) + 1
		if lanes.is_empty():
			continue
		var width := mini(lanes.size(), 4)
		for i in w.uids.size():
			var u: Dictionary = by_uid[w.uids[i]]
			var lane: Dictionary = lanes[i % width]
			var d: int = 2 + r + floori(float(i) / width)
			u.x = lane.x + out.x * d
			u.y = lane.y + out.y * d


## The battle for an encounter roll and the company's squads (BattleUnit
## dictionaries; they are deployed in place). opts: {survivalBonus, darkness?, title?}.
static func build_battle(roll: Dictionary, army: Array, opts: Dictionary) -> Dictionary:
	var enc := DB.encounter_by_id(roll.encounterId)
	var rng := Rng.new(JS.to_i32(roll.seed) ^ 0x5bd1e995)
	var waves: Array = []
	for w in JS.get_or(roll, "waves", []):
		var c: Dictionary = w.duplicate()
		c.units = w.units.duplicate()
		waves.append(c)
	var tpl: Dictionary = DB.BATTLE_MAPS[roll.mapId]
	var edges: Variant = tpl.get("edges")
	var approaches: Array = [edges.main if edges != null else "n"]
	for w in waves:
		if not approaches.has(w.edge):
			approaches.append(w.edge)
	var map := MapGen.generate_map(roll.mapId, roll.seed, {"ambush": roll.ambush, "approaches": approaches})
	var to_grid := func(e: String) -> String: return MapGen.TRANSPOSED[e] if map.get("transposed", false) else e
	var enemies: Array = []
	for i in roll.enemies.size():
		var e: Dictionary = roll.enemies[i]
		enemies.append(Soldier.make_enemy(e.typeId, e.level, "e%d" % i, rng))
	var leaders: Array = rng.shuffle(DB.MILITIA_LEADERS.duplicate())
	var allies: Array = []
	var roll_allies: Array = JS.get_or(roll, "allies", [])
	for i in roll_allies.size():
		var a: Dictionary = roll_allies[i]
		allies.append(_make_ally(a.typeId, a.level, "m%d" % i, rng, leaders[i % leaders.size()]))
	if enc.get("kind") == "stand":
		# Before a stand the company rallies: the people it defends come out to stand beside it.
		for u in army:
			u.morale = u.maxMorale
	# A badly depleted company meets a slightly thinner host: the rabble and
	# spears at the back of the waves stay behind. The warchief and his
	# monsters always come.
	var men := 0
	for u in army:
		men += u.alive
	var strength := minf(1.0, men / 34.0)
	var spareable: Array = []
	for wi in waves.size():
		var w: Dictionary = waves[wi]
		for i in w.units.size():
			var wu: Dictionary = w.units[i]
			if not wu.get("warchief", false) and (wu.typeId == "goblin_rabble" or wu.typeId == "goblin_spear"):
				spareable.append([wi, i])
	var drop := JS.rnd(spareable.size() * (1 - strength) * 1.2)
	var dropped: Array = rng.shuffle(spareable.duplicate()).slice(0, drop)
	var drop_set := {}
	for d in dropped:
		drop_set["%d:%d" % [d[0], d[1]]] = true
	for wi in waves.size():
		var w: Dictionary = waves[wi]
		var kept: Array = []
		for i in w.units.size():
			if not drop_set.has("%d:%d" % [wi, i]):
				kept.append(w.units[i])
		w.units = kept
	deploy_player(map, army + allies, roll.ambush)
	deploy_enemies(map, enemies, rng, roll.ambush)
	var reserve: Array = []
	var setup_waves: Array = []
	for wi in waves.size():
		var w: Dictionary = waves[wi]
		var edge: String = to_grid.call(w.edge)
		var uids: Array = []
		for i in w.units.size():
			var wu: Dictionary = w.units[i]
			var u := Soldier.make_enemy(wu.typeId, wu.level, "w%d-%d" % [wi, i], rng)
			if wu.get("warchief", false):
				u.tags.append("warchief")
				u.name = rng.pick(DB.WARCHIEF_NAMES)
			u.status = "reserve"
			u.facing = Battle.INWARD[edge]
			reserve.append(u)
			uids.append(u.uid)
		var sw: Dictionary = w.duplicate()
		sw.edge = edge
		sw.units = w.units.map(func(x: Dictionary) -> Dictionary: return x.duplicate())
		sw.uids = uids
		setup_waves.append(sw)
	var by_uid := {}
	for u in reserve:
		by_uid[u.uid] = u
	_stage(map, setup_waves, by_uid)
	face_each_other(army + allies + enemies)
	var objective: Dictionary
	if enc.get("goal") != null:
		objective = enc.goal.duplicate(true)
	else:
		objective = {"kind": "rout", "title": "Rout the enemy", "brief": "Destroy or drive off every enemy squad."}
	var setup := {
		"seed": roll.seed,
		"fogOfWar": opts.get("fogOfWar", true),
		"map": map,
		"units": army + allies + enemies + reserve,
		"survivalBonus": opts.survivalBonus,
		"ambush": roll.ambush,
		"enemyFirst": roll.ambush,
	}
	if opts.get("darkness") != null:
		setup.darkness = opts.darkness
	setup.title = opts.title if opts.get("title") != null else enc.name
	setup.encounterId = roll.encounterId
	setup.kind = JS.get_or(enc, "kind", "skirmish")
	setup.objective = objective
	setup.waves = setup_waves
	return setup
