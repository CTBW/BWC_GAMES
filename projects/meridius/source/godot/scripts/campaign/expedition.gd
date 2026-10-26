## Port of src/campaign/expedition.ts: the expedition map, marching, events,
## camps, villages, battles and the return home.
##
## State objects are Dictionaries with the original keys:
## - Expedition: {campaignId, seed, rng, nodes, edges, current, path, army,
##   supplies, loot, marches, objectiveDone, log, pending, battles, startArmy,
##   starving, menLost, startMen}
## - CNode: {id, stage, lane, type, name, revealed, scouted, visited, tx, ty,
##   encounter?, eventId?, night?}
## - Pending: {kind: "arrive"|"event"|"battle"|"battleResult"|"camp"|"village"|"scout"|"complete", ...}
## - BattleReport, SquadLoss, ExpeditionReport as in the original.
## Use through `const Expedition = preload("res://scripts/campaign/expedition.gd")`.
extends RefCounted

const JS = preload("res://scripts/core/js.gd")
const Rng = preload("res://scripts/core/rng.gd")
const DB = preload("res://scripts/data/db.gd")
const Squad = preload("res://scripts/rules/squad.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const Setup = preload("res://scripts/rules/setup.gd")
const Game = preload("res://scripts/meta/game.gd")
const Soldier = preload("res://scripts/meta/soldier.gd")

const PLACE_NAMES := {
	"battle": ["Wolfsrun Glade", "Burnt Oak Clearing", "The Long Meadow", "Elk Hollow", "Raven Copse", "Mossback Ridge", "Grey Stones"],
	"ambush": ["Tangled Road", "Bramble Pass", "The Narrows", "Darkwood Track"],
	"scout": ["Watcher's Rock", "The Old Tower", "Hawk Crag", "Signal Hill"],
	"village": ["Ostby", "Lindholm", "Kettlewick", "Brannsted", "Halla", "Mjolby"],
	"event": ["Crossroads", "Woodcutter's Track", "The Mill Road", "Fenside", "Old Shrine Path", "Charcoal Burners' Clearing"],
	"camp": ["Spring Hollow", "Fir Shelter", "The Lee of the Hill", "Stone Circle"],
}

## One line of news of the host per march: it is always closer than the last.
const HORDE_NEWS := [
	"Smoke on the western skyline: the host has crossed out of the Hillsvain Woods.",
	"Refugees pass the column at a run. Ostby is burning.",
	"War drums in the distance, all through the night.",
	"Wolf riders shadow the column from the ridges, and vanish when the crossbows turn.",
	"The host is a day from Brannsted. Its fires light the whole western sky.",
	"You can hear them now: thousands of voices, and the horns.",
]


## rng.pick that, like JS, yields null for an empty list (the draw is still made).
static func _pick(r: RefCounted, arr: Array) -> Variant:
	var i := int(floor(r.next() * arr.size()))
	return arr[i] if i < arr.size() else null


# ---------------------------------------------------------------- generation

static func generate_expedition(g: Dictionary, campaign_id: String, army: Array, supplies: Dictionary) -> Dictionary:
	var c := DB.campaign_by_id(campaign_id)
	var seed: int = Game.use_rng(g, func(r: RefCounted) -> int: return r.rint(1, 2147483647))
	var rng := Rng.new(seed)
	var nodes: Array = []
	var edges: Array = []
	var used_names := {}
	var name_for := func(t: String) -> String:
		var list: Array = PLACE_NAMES.get(t, ["Waypoint"])
		for i in 10:
			var n: String = rng.pick(list)
			if not used_names.has(n):
				used_names[n] = true
				return n
		return rng.pick(list)
	var total: int = c.stages + 1
	var place := func(stage: int, lane: int, lanes: int) -> Dictionary:
		var t := float(stage) / total
		var cx := 30 + (7 - 30) * t
		var cy := 30 + (7 - 30) * t
		var off := 0.0 if lanes == 1 else (lane - (lanes - 1) / 2.0) * 7.5
		var tx := JS.rnd(cx + off * 0.7071 + rng.frange(-1.2, 1.2))
		var ty := JS.rnd(cy - off * 0.7071 + rng.frange(-1.2, 1.2))
		return {"tx": tx, "ty": ty}
	var n0 := {"id": "n0", "stage": 0, "lane": 0, "type": "start", "name": "Muster point", "revealed": true, "scouted": true, "visited": true}
	n0.merge(place.call(0, 0, 1))
	nodes.append(n0)
	var prev: Array = [n0]
	var camp_placed := false
	var weight_keys: Array = c.weights.keys()
	for s in range(1, c.stages + 1):
		var lanes: int = rng.rint(c.lanes[0], c.lanes[1])
		var stage_nodes: Array = []
		for l in lanes:
			var type: String = rng.weighted(weight_keys, func(t: String) -> float: return JS.get_or(c.weights, t, 0))
			if s == 1 and (type == "camp" or type == "ambush"):
				type = rng.pick(["event", "village", "battle"])
			if type == "camp" and s < 2:
				type = "event"
			var nd := {
				"id": "n%d" % (nodes.size() + stage_nodes.size()),
				"stage": s,
				"lane": l,
				"type": type,
				"name": "",
				"revealed": s == 1,
				"scouted": false,
				"visited": false,
			}
			nd.merge(place.call(s, l, lanes))
			stage_nodes.append(nd)
		# Guarantee variety: a battle in every stage after the first, a camp mid-way.
		if s >= 2 and not stage_nodes.any(func(n: Dictionary) -> bool: return n.type == "battle" or n.type == "ambush"):
			rng.pick(stage_nodes).type = "battle"
		if not camp_placed and s == ceili(c.stages / 2.0) + 1 and not stage_nodes.any(func(n: Dictionary) -> bool: return n.type == "camp"):
			var cand: Array = stage_nodes.filter(func(n: Dictionary) -> bool: return n.type != "battle")
			var pick: Dictionary = rng.pick(cand) if not cand.is_empty() else stage_nodes[stage_nodes.size() - 1]
			pick.type = "camp"
		if stage_nodes.any(func(n: Dictionary) -> bool: return n.type == "camp"):
			camp_placed = true
		if s == c.stages and not stage_nodes.any(func(n: Dictionary) -> bool: return n.type == "camp") and stage_nodes.size() > 1:
			var pool: Array = stage_nodes.filter(func(n: Dictionary) -> bool: return n.type != "battle") + stage_nodes
			rng.pick(pool).type = "camp"
		for n in stage_nodes:
			n.name = name_for.call(n.type)
			if n.type == "battle" or n.type == "ambush":
				var depth: int = s - 1
				var is_ambush: bool = n.type == "ambush"
				var pool: Array = DB.ENCOUNTERS.filter(func(e: Dictionary) -> bool:
					return e.tier == c.encounterTier and not e.get("objective", false) \
						and (e.get("ambush", false) if is_ambush else not e.get("ambush", false)) \
						and JS.get_or(e, "minDepth", 0) <= depth and JS.get_or(e, "maxDepth", 99) >= depth
				)
				if pool.is_empty():
					pool = DB.ENCOUNTERS.filter(func(e: Dictionary) -> bool: return e.get("ambush", false))
				var enc: Dictionary = rng.weighted(pool, func(e: Dictionary) -> float: return e.weight)
				n.encounter = Setup.roll_encounter(enc.id, rng, s - 1)
			if n.type == "event":
				n.eventId = _pick_event(rng, s, nodes + stage_nodes).id
			if n.type == "camp":
				n.night = true
			nodes.append(n)
		_connect(prev, stage_nodes, edges, rng)
		prev = stage_nodes
	# Half way, the road crosses the Vattern where Ostby's people are fleeing:
	# one road leads to the ford, and to a stand there if the company takes it.
	var ford_stage: int = mini(c.stages - 1, 3)
	var ford_cands: Array = nodes.filter(func(n: Dictionary) -> bool: return n.stage == ford_stage and n.type != "camp" and n.type != "start")
	if ford_cands.size() > 1:
		var f: Dictionary = rng.pick(ford_cands)
		f.type = "battle"
		f.name = "The Vattern Ford"
		f.encounter = Setup.roll_encounter("refugee_stand", rng, ford_stage - 1)
		f.erase("eventId")
	var obj := {
		"id": "n%d" % nodes.size(),
		"stage": total,
		"lane": 0,
		"type": "objective",
		"name": c.objective.name,
		"revealed": true,
		"scouted": false,
		"visited": false,
	}
	obj.merge(place.call(total, 0, 1))
	obj.encounter = Setup.roll_encounter(c.objective.encounterId, rng, c.stages)
	nodes.append(obj)
	for p in prev:
		edges.append([p.id, obj.id])

	return {
		"campaignId": campaign_id,
		"seed": seed,
		"rng": rng.state,
		"nodes": nodes,
		"edges": edges,
		"current": "n0",
		"path": ["n0"],
		"army": army.duplicate(),
		"supplies": supplies.duplicate(),
		"loot": {"silver": 0, "timber": 0, "iron": 0, "trophies": 0},
		"marches": 0,
		"objectiveDone": false,
		"log": [{"text": "The company marches for %s." % c.region}],
		"pending": null,
		"battles": 0,
		"startArmy": army.size(),
		"starving": 0,
		"menLost": 0,
	}


static func _pick_event(rng: RefCounted, stage: int, existing: Array) -> Dictionary:
	var used := {}
	for n in existing:
		var id: Variant = n.get("eventId")
		if id != null and id != "":
			used[id] = true
	var pool: Array = DB.EVENTS.filter(func(e: Dictionary) -> bool:
		return JS.get_or(e, "minStage", 0) <= stage - 1 and JS.get_or(e, "maxStage", 99) >= stage - 1 and not used.has(e.id)
	)
	return rng.weighted(pool if not pool.is_empty() else DB.EVENTS, func(e: Dictionary) -> float: return e.weight)


static func _pos(n: Dictionary, arr: Array) -> float:
	return 0.5 if arr.size() == 1 else float(n.lane) / (arr.size() - 1)


static func _lane_of(id: String, arr: Array) -> int:
	for n in arr:
		if n.id == id:
			return n.lane
	return 0


## Non-crossing edges between consecutive stages; every node gets in and out.
static func _connect(a: Array, b: Array, edges: Array, rng: RefCounted) -> void:
	var has_in := {}
	for n in a:
		var p := _pos(n, a)
		var sorted: Array = JS.sort(b.duplicate(), func(x: Dictionary, y: Dictionary) -> float: return absf(_pos(x, b) - p) - absf(_pos(y, b) - p))
		edges.append([n.id, sorted[0].id])
		has_in[sorted[0].id] = true
		if sorted.size() > 1 and absf(_pos(sorted[1], b) - p) <= 0.55 and rng.chance(0.55):
			edges.append([n.id, sorted[1].id])
			has_in[sorted[1].id] = true
	for m in b:
		if has_in.has(m.id):
			continue
		var p := _pos(m, b)
		var src: Dictionary = JS.sort(a.duplicate(), func(x: Dictionary, y: Dictionary) -> float: return absf(_pos(x, a) - p) - absf(_pos(y, a) - p))[0]
		edges.append([src.id, m.id])
	# Remove crossing edges (keep the first of a crossing pair).
	var a_ids := {}
	for n in a:
		a_ids[n.id] = true
	var b_ids := {}
	for n in b:
		b_ids[n.id] = true
	var stage_edges: Array = edges.filter(func(e: Array) -> bool: return a_ids.has(e[0]) and b_ids.has(e[1]))
	for i in stage_edges.size():
		for j in range(i + 1, stage_edges.size()):
			var f1: String = stage_edges[i][0]
			var t1: String = stage_edges[i][1]
			var f2: String = stage_edges[j][0]
			var t2: String = stage_edges[j][1]
			var cross := (_lane_of(f1, a) - _lane_of(f2, a)) * (_lane_of(t1, b) - _lane_of(t2, b)) < 0
			if not cross:
				continue
			var out_f2 := 0
			var in_t2 := 0
			for e in edges:
				if e[0] == f2:
					out_f2 += 1
				if e[1] == t2:
					in_t2 += 1
			if out_f2 > 1 and in_t2 > 1:
				# edges.indexOf(stageEdges[j]): the same array object.
				for k in edges.size():
					if is_same(edges[k], stage_edges[j]):
						edges.remove_at(k)
						break


# ---------------------------------------------------------------- helpers

## Runs fn(rng) with the expedition's RNG and stores its state back.
static func ex_rng(ex: Dictionary, fn: Callable) -> Variant:
	var r := Rng.new(ex.rng)
	var out: Variant = fn.call(r)
	ex.rng = r.state
	return out


static func node(ex: Dictionary, id: String) -> Dictionary:
	for n in ex.nodes:
		if n.id == id:
			return n
	push_error("no node " + id)
	return {}


static func next_nodes(ex: Dictionary) -> Array:
	var out: Array = []
	for e in ex.edges:
		if e[0] == ex.current:
			out.append(node(ex, e[1]))
	return out


## The roster entries of the marching army, in army order.
static func army_soldiers(g: Dictionary) -> Array:
	var ex: Dictionary = g.expedition
	var out: Array = []
	for id in ex.army:
		for s in g.roster:
			if s.id == id:
				out.append(s)
				break
	return out


static func ration_cost(g: Dictionary) -> int:
	return ceili(army_soldiers(g).size() / 2.0)


static func _add_log(ex: Dictionary, text: String, tone: String = "neutral") -> void:
	ex.log.push_front({"text": text, "tone": tone})
	if ex.log.size() > 40:
		ex.log.resize(40)


## Damage a squad outside battle. The pool loses `amount`; any soldier whose
## share runs out dies (never the last one: the road does not wipe out a squad).
## Deaths go to the expedition log and the chronicle. Returns soldiers lost.
## `say(who, verb)` writes the line: "one of Aldric's footmen" / "dies".
static func hurt_squad(g: Dictionary, s: Dictionary, amount: float, say: Callable) -> int:
	var before: int = s.men
	s.hp = maxi(1, s.hp - maxi(0, JS.rnd(amount)))
	Soldier.settle_men(s)
	var lost: int = before - s.men
	if lost > 0:
		var who := "%s of %s" % [Game.number_word(lost), Squad.squad_name(s)]
		var verb := "dies" if lost == 1 else "die"
		var text: String = say.call(who, verb)
		var ex: Variant = g.expedition
		if ex != null:
			ex.menLost = JS.get_or(ex, "menLost", 0) + lost
			_add_log(ex, text, "bad")
		Game.chronicle(g, text, "bad")
	return lost


static func _reveal_ahead(ex: Dictionary, from_id: String, depth: int, scout: bool = false) -> void:
	var frontier: Array = [from_id]
	for d in depth:
		var nxt: Array = []
		for id in frontier:
			for e in ex.edges:
				if e[0] != id:
					continue
				var n := node(ex, e[1])
				n.revealed = true
				if scout:
					n.scouted = true
				nxt.append(n.id)
		frontier = nxt


static func _wave_squads(roll: Dictionary) -> int:
	var k := 0
	for w in JS.get_or(roll, "waves", []):
		k += w.units.size()
	return k


## What the player can see about a node: {type, title, detail}.
static func node_view(n: Dictionary) -> Dictionary:
	if not n.revealed:
		return {"type": "unknown", "title": "Unexplored", "detail": "Scouts have not been this way."}
	if n.type == "ambush" and not n.scouted:
		return {"type": "event", "title": n.name, "detail": "Quiet woods. Too quiet, perhaps."}
	var info: Dictionary = DB.NODE_INFO[n.type]
	var detail: String = info.blurb
	var enc: Variant = n.get("encounter")
	if enc != null and (n.scouted or n.type == "objective"):
		var counts := {}
		for e in enc.enemies:
			counts[e.typeId] = counts.get(e.typeId, 0) + 1
		var parts: Array = []
		for t in counts:
			var k: int = counts[t]
			parts.append("%d %s" % [k, DB.UNIT_TYPES[t].name if k == 1 else DB.UNIT_TYPES[t].plural])
		detail = ", ".join(parts)
		var waves: Array = JS.get_or(enc, "waves", [])
		var more := _wave_squads(enc)
		if not waves.is_empty():
			if waves.any(func(w: Dictionary) -> bool: return w.get("horn", false)):
				detail += ". A horn-bearer can call %d more squads." % more
			else:
				detail += ". Then %s: %d squads." % ["one more wave" if waves.size() == 1 else "%d more waves" % waves.size(), more]
	elif enc != null:
		var k: int = enc.enemies.size() + _wave_squads(enc)
		detail = "A band of the host." if k <= 6 else ("A large band of the host, with more behind it." if k <= 10 else "The host in force.")
		var intel: Variant = DB.encounter_by_id(enc.encounterId).get("intel")
		if intel != null and intel != "" and n.type != "ambush":
			detail += " %s" % intel
	return {"type": n.type, "title": n.name, "detail": detail}


# ---------------------------------------------------------------- start / march

static func start_expedition(g: Dictionary, campaign_id: String, army: Array, supplies: Dictionary, cost: int) -> void:
	g.resources.silver -= cost
	g.cycle += 1
	var ex := generate_expedition(g, campaign_id, army, supplies)
	g.expedition = ex
	var c := DB.campaign_by_id(campaign_id)
	for s in army_soldiers(g):
		s.fatigue = 0
		if s.level > c.reluctantAbove:
			s.morale = maxi(1, s.morale - 15)
			_add_log(ex, "%s grumbles about chasing goblins (-15 morale)." % s.name, "bad")
	var men := 0
	for s in army_soldiers(g):
		men += s.men
	ex.startMen = men
	Game.chronicle(g, "Expedition %d: %d squads (%d soldiers) march on %s." % [g.cycle, army.size(), men, c.name])


static func can_march(g: Dictionary, id: String) -> bool:
	var ex: Variant = g.expedition
	if ex == null or ex.pending != null:
		return false
	for n in next_nodes(ex):
		if n.id == id:
			return true
	return false


static func march(g: Dictionary, id: String) -> bool:
	var ex: Variant = g.expedition
	if ex == null or not can_march(g, id):
		return false
	var c := DB.campaign_by_id(ex.campaignId)
	var need := ration_cost(g)
	var soldiers := army_soldiers(g)
	ex.marches += 1
	if ex.supplies.rations >= need:
		ex.supplies.rations -= need
		ex.starving = 0
	else:
		ex.supplies.rations = 0
		ex.starving += 1
		_add_log(ex, "The rations have run out. The army marches hungry.", "bad")
		for s in soldiers:
			s.morale = maxi(1, s.morale - 8 - ex.starving * 2)
			s.fatigue = mini(100, s.fatigue + 10)
			# Hunger costs every soldier 2 HP of his share.
			hurt_squad(g, s, 2 * s.men, func(who: String, _verb: String) -> String: return "Hunger takes %s." % who)
	for s in soldiers:
		s.fatigue = mini(100, s.fatigue + c.marchFatigue)
	ex.current = id
	ex.path.append(id)
	var n := node(ex, id)
	n.visited = true
	n.revealed = true
	_reveal_ahead(ex, id, 1)
	var news: Variant = HORDE_NEWS[mini(HORDE_NEWS.size() - 1, ex.marches - 1)] if ex.marches >= 1 else null
	if news != null:
		_add_log(ex, news, "bad")
	ex.pending = {"kind": "arrive", "nodeId": id}
	_resolve_arrival(g)
	return true


static func _resolve_arrival(g: Dictionary) -> void:
	var ex: Dictionary = g.expedition
	var n := node(ex, ex.current)
	match n.type:
		"battle":
			ex.pending = {"kind": "battle", "nodeId": n.id, "roll": n.encounter, "title": "%s at %s" % [DB.encounter_by_id(n.encounter.encounterId).name, n.name], "objective": false, "surprise": false}
		"ambush":
			_add_log(ex, "Ambush at %s!" % n.name, "bad")
			ex.pending = {"kind": "battle", "nodeId": n.id, "roll": n.encounter, "title": "Ambush at %s" % n.name, "objective": false, "surprise": true}
		"objective":
			ex.pending = {"kind": "battle", "nodeId": n.id, "roll": n.encounter, "title": n.name, "objective": true, "surprise": false}
		"event":
			var p := {"kind": "event", "nodeId": n.id, "eventId": n.eventId}
			var subject: Variant = ex_rng(ex, func(r: RefCounted) -> Variant: return _pick(r, army_soldiers(g)))
			if subject != null:
				p.subject = subject.id
			ex.pending = p
		"camp":
			ex.pending = {"kind": "camp", "nodeId": n.id, "done": [], "messages": []}
		"village":
			var spots: Array = ex_rng(ex, func(r: RefCounted) -> Array:
				var labels: Array = r.shuffle(["The longhouse", "A collapsed barn", "The smithy", "The well house", "A root cellar", "The chapel"]).slice(0, 3)
				var out: Array = []
				for label in labels:
					out.append({"label": label, "searched": false, "locked": false})
				out.append({"label": "A locked strongbox", "searched": false, "locked": true})
				return out
			)
			ex.pending = {"kind": "village", "nodeId": n.id, "messages": [], "spots": spots}
		"scout":
			_reveal_ahead(ex, n.id, 3, true)
			_add_log(ex, "From %s the scouts map the road ahead." % n.name, "good")
			var host := 0
			for q in ex.nodes:
				if q.type == "objective":
					var enc: Variant = q.get("encounter")
					if enc != null:
						host = enc.enemies.size() + _wave_squads(enc)
					break
			if host:
				_add_log(ex, "Beyond the woods the host is on the move toward Brannsted: the scouts count %d warbands under the banners, and the warchief's own standard among them." % host, "bad")
			ex.pending = {"kind": "scout", "nodeId": n.id}
		_:
			ex.pending = null


static func dismiss_pending(g: Dictionary) -> void:
	var ex: Variant = g.expedition
	if ex == null or ex.pending == null:
		return
	var p: Dictionary = ex.pending
	if p.kind == "event" and p.get("followBattle") != null:
		ex.pending = {"kind": "battle", "nodeId": p.nodeId, "roll": p.followBattle, "title": "Ambushed!", "objective": false, "surprise": true}
		return
	if p.kind == "battleResult" and p.report.result == "defeat":
		return_home(g, "defeat")
		return
	if p.kind == "battleResult" and p.report.objective and p.report.result == "victory":
		ex.pending = {"kind": "complete"}
		return
	ex.pending = null


# ---------------------------------------------------------------- events

## Whether an event choice (an EventChoice dictionary) can be taken: {ok, reason?}.
static func choice_available(g: Dictionary, ch: Dictionary) -> Dictionary:
	var ex: Dictionary = g.expedition
	var r: Variant = ch.get("requires")
	if r == null:
		return {"ok": true}
	var sup: Variant = r.get("supply")
	if sup != null and JS.get_or(ex.supplies, sup[0], 0) < maxi(1, sup[1]):
		return {"ok": false, "reason": "Needs %s" % String(DB.SUPPLIES[sup[0]].name).to_lower()}
	var loot: Variant = r.get("loot")
	if loot != null and JS.get_or(ex.loot, loot[0], 0) < loot[1]:
		return {"ok": false, "reason": "Needs %s %s in the spoils" % [JS.num_str(loot[1]), loot[0]]}
	var type: Variant = r.get("type")
	if type != null and type != "" and not army_soldiers(g).any(func(s: Dictionary) -> bool: return s.typeId == type):
		return {"ok": false, "reason": "Needs a %s" % String(DB.UNIT_TYPES[type].name).to_lower()}
	if r.get("slot", false):
		var lim := Game.army_limits(g, DB.campaign_by_id(ex.campaignId))
		if ex.army.size() >= lim.slots:
			return {"ok": false, "reason": "No free unit slot"}
		if Game.army_command(g, ex.army) + 2 > lim.command:
			return {"ok": false, "reason": "Not enough command points"}
	return {"ok": true}


static func _event(id: Variant) -> Variant:
	for e in DB.EVENTS:
		if e.id == id:
			return e
	return null


static func choose_event(g: Dictionary, choice_index: int) -> void:
	var ex: Dictionary = g.expedition
	var p: Variant = ex.pending
	if p == null or p.kind != "event" or p.get("result") != null:
		return
	var ev: Dictionary = _event(p.eventId)
	if choice_index < 0 or choice_index >= ev.choices.size():
		return
	var ch: Dictionary = ev.choices[choice_index]
	if not choice_available(g, ch).ok:
		return
	var outcome: Dictionary = ex_rng(ex, func(r: RefCounted) -> Variant: return r.weighted(ch.outcomes, func(o: Dictionary) -> float: return o.weight))
	var subject: Variant = null
	for s in army_soldiers(g):
		if s.id == p.get("subject"):
			subject = s
			break
	if subject == null:
		subject = ex_rng(ex, func(r: RefCounted) -> Variant: return _pick(r, army_soldiers(g)))
	var changes: Array = []
	var battle: Variant = null
	for e in outcome.effects:
		var res := apply_effect(g, e, subject, ev.title)
		if res.get("text") != null:
			changes.append(res.text)
		if res.get("extra") != null:
			changes.append_array(res.extra)
		if res.get("battle") != null:
			battle = res.battle
	var text: String = String(outcome.text).replace("{name}", subject.name if subject != null else "A soldier")
	p.result = {"text": text, "changes": changes}
	if battle != null:
		p.followBattle = battle
	_add_log(ex, "%s: %s" % [ev.title, text])


static func _pick_who(g: Dictionary, who: String, subject: Variant) -> Array:
	var army := army_soldiers(g)
	if who == "all":
		return army
	if who == "random":
		return [subject] if subject != null else army.slice(0, 1)
	if who == "weakest":
		return JS.sort(army.duplicate(), func(a: Dictionary, b: Dictionary) -> float:
			return float(a.hp) / Soldier.squad_max_hp(a) - float(b.hp) / Soldier.squad_max_hp(b)
		).slice(0, 1)
	if who == "strongest":
		return JS.sort(army.duplicate(), func(a: Dictionary, b: Dictionary) -> int: return b.level - a.level).slice(0, 1)
	if who.begins_with("type:"):
		var t := who.substr(5)
		return army.filter(func(s: Dictionary) -> bool: return s.typeId == t)
	return []


static func _sign(n: Variant) -> String:
	return "+%s" % JS.num_str(n) if n > 0 else JS.num_str(n)


static func _first_names(who: Array) -> String:
	return ", ".join(who.map(func(s: Dictionary) -> String: return String(s.name).split(" ")[0]))


## Applies one event effect (an Effect dictionary). Returns {text?, extra?, battle?}.
static func apply_effect(g: Dictionary, e: Dictionary, subject: Variant = null, cause: String = "The road") -> Dictionary:
	var ex: Dictionary = g.expedition
	match e.k:
		"supply":
			var before: int = JS.get_or(ex.supplies, e.id, 0)
			ex.supplies[e.id] = maxi(0, before + e.n)
			var d: int = ex.supplies[e.id] - before
			return {"text": "%s %s" % [_sign(d), String(DB.SUPPLIES[e.id].name).to_lower()]} if d != 0 else {}
		"loot":
			var before: int = JS.get_or(ex.loot, e.id, 0)
			ex.loot[e.id] = maxi(0, before + e.n)
			var d: int = ex.loot[e.id] - before
			return {"text": "%s %s" % [_sign(d), e.id]} if d != 0 else {}
		"morale":
			var who := _pick_who(g, e.who, subject)
			for s in who:
				s.morale = maxi(1, mini(Soldier.soldier_stats(s).morale, s.morale + e.n))
			return {"text": "%s morale%s" % [_sign(e.n), " (army)" if e.who == "all" else " (%s)" % _first_names(who)]}
		"hp":
			# Effects are written for one soldier; every soldier in the squad takes them.
			var who := _pick_who(g, e.who, subject)
			var extra: Array = []
			for s in who:
				if e.n >= 0:
					Soldier.heal_soldier(s, e.n * s.men)
				else:
					var lost := hurt_squad(g, s, -e.n * s.men, func(w: String, verb: String) -> String: return "%s: %s %s." % [cause, w, verb])
					if lost:
						extra.append("-%d %s (%s)" % [lost, Squad.member_noun(s.typeId, lost), String(s.name).split(" ")[0]])
			return {"text": "%s HP each%s" % [_sign(e.n), " (army)" if e.who == "all" else " (%s)" % _first_names(who)], "extra": extra}
		"fatigue":
			var who := _pick_who(g, e.who, subject)
			for s in who:
				s.fatigue = maxi(0, mini(100, s.fatigue + e.n))
			return {"text": "%s fatigue%s" % [_sign(e.n), " (army)" if e.who == "all" else ""]}
		"xp":
			var who := _pick_who(g, e.who, subject)
			for s in who:
				Game.gain_xp(g, s, e.n)
			return {"text": "%s XP (%s)" % [_sign(e.n), _first_names(who)]}
		"injury":
			var who := _pick_who(g, e.who, subject)
			var out: Array = []
			for s in who:
				var inj: String = ex_rng(ex, func(r: RefCounted) -> Variant: return r.pick(DB.INJURIES.keys()))
				if not s.injuries.has(inj):
					s.injuries.append(inj)
				out.append("%s: %s" % [String(s.name).split(" ")[0], DB.INJURIES[inj].name])
			return {"text": ", ".join(out)}
		"recruit":
			var s: Dictionary = ex_rng(ex, func(r: RefCounted) -> Variant: return Soldier.new_soldier(r, e.typeId, e.level, Game.next_id(g), g.cycle))
			# A band met on the road is never a full squad: the Barracks can fill it later.
			s.men = maxi(1, ceili(DB.squad_size(e.typeId) / 2.0))
			s.hp = Soldier.squad_hp_cap(s)
			s.fatigue = 20
			g.roster.append(s)
			ex.army.append(s.id)
			var plural := String(DB.UNIT_TYPES[e.typeId].plural).to_lower()
			Game.chronicle(g, "%s and %s more %s join the company on the road." % [s.name, Game.number_word(s.men - 1), plural])
			return {"text": "%s joins with %d %s (%d/%d, %d CP)" % [s.name, s.men, plural, s.men, DB.squad_size(e.typeId), Soldier.command_cost(s)]}
		"battle":
			var stage: int = node(ex, ex.current).stage
			var roll: Dictionary = ex_rng(ex, func(r: RefCounted) -> Variant: return Setup.roll_encounter(e.encounterId, r, stage))
			return {"text": "Battle!", "battle": roll}
		"reveal":
			_reveal_ahead(ex, ex.current, e.stages, true)
			return {"text": "The road ahead is scouted (%s stages)" % JS.num_str(e.stages)}
	push_error("unknown effect " + str(e.k))
	return {}


# ---------------------------------------------------------------- camp & village

static func camp_rest(g: Dictionary) -> void:
	var ex: Dictionary = g.expedition
	var p: Variant = ex.pending
	if p == null or p.kind != "camp" or p.done.has("rest"):
		return
	var army := army_soldiers(g)
	var need := army.size()
	var fed: int = mini(need, ex.supplies.rations)
	ex.supplies.rations -= fed
	var ratio: float = float(fed) / need if need > 0 else NAN
	var tended := 0
	for s in army:
		var st := Soldier.soldier_stats(s)
		# 30% of every surviving soldier's share; the dead stay dead.
		Soldier.heal_soldier(s, Soldier.squad_hp_cap(s) * 0.3 * ratio)
		s.morale = mini(st.morale, s.morale + JS.rnd(15 * ratio))
		s.fatigue = maxi(0, s.fatigue - JS.rnd(45 * ratio))
		# A full night's rest dresses the wounds of the last fight.
		if ratio >= 1 and Squad.wound_of(s) != null:
			tend_wounds(s)
			tended += 1
	p.done.append("rest")
	if ratio >= 1:
		p.messages.append("The army eats a hot meal and sleeps (-%d rations): +30%% HP, +15 morale, -45 fatigue." % fed)
		if tended > 0:
			p.messages.append("The wounds of the last fight are dressed: %s fit to fight again." % ("one squad is" if tended == 1 else "%s squads are" % Game.number_word(tended)))
	else:
		p.messages.append("There is not enough food for everyone (-%d rations). The rest is poor." % fed)
	# Night raid unless a watch is kept with torches.
	if not p.done.has("watch"):
		var raid: bool = ex_rng(ex, func(r: RefCounted) -> bool: return r.chance(0.3))
		if raid:
			p.raid = true
			p.messages.append("In the dark, goblins rush the camp!")
			var stage: int = node(ex, ex.current).stage
			ex.pending = {
				"kind": "battle",
				"nodeId": p.nodeId,
				"roll": ex_rng(ex, func(r: RefCounted) -> Variant: return Setup.roll_encounter("road_ambush", r, stage)),
				"title": "Night raid on the camp",
				"objective": false,
				"surprise": true,
				"night": true,
			}
			_add_log(ex, "Goblins raid the camp in the night!", "bad")


static func camp_watch(g: Dictionary) -> void:
	var ex: Dictionary = g.expedition
	var p: Variant = ex.pending
	if p == null or p.kind != "camp" or p.done.has("watch") or ex.supplies.torches < 1:
		return
	ex.supplies.torches -= 1
	p.done.append("watch")
	p.messages.append("Torches are lit around the camp and a watch is set (-1 torch). No raider will catch you sleeping.")


static func camp_repair(g: Dictionary) -> void:
	var ex: Dictionary = g.expedition
	var p: Variant = ex.pending
	if p == null or p.kind != "camp" or p.done.has("repair") or ex.supplies.tools < 1:
		return
	ex.supplies.tools -= 1
	for s in army_soldiers(g):
		s.armorCondition = minf(1.0, s.armorCondition + 0.4)
	p.done.append("repair")
	p.messages.append("The army mends straps and hammers out dents (-1 tools): +40% armour condition.")


## A bandage heals a squad's survivors and dresses the wounds of its last fight.
static func use_bandage(g: Dictionary, soldier_id: String) -> bool:
	var ex: Variant = g.expedition
	if ex == null or ex.supplies.bandages < 1:
		return false
	var s: Variant = null
	for r in g.roster:
		if r.id == soldier_id:
			s = r
			break
	if s == null:
		return false
	var wound: Variant = Squad.wound_of(s)
	if s.hp >= Soldier.squad_hp_cap(s) and wound == null:
		return false
	ex.supplies.bandages -= 1
	var healed := Soldier.heal_soldier(s, bandage_heal(s))
	if wound != null:
		tend_wounds(s)
		_add_log(ex, "%s are bandaged (+%d HP); the wounds of their last fight are dressed." % [Squad.squad_name(s), healed])
	else:
		_add_log(ex, "%s are bandaged (+%d HP)." % [Squad.squad_name(s), healed])
	return true


## Clears the penalty a squad carries from its last fight (wounded or Injured).
static func tend_wounds(s: Dictionary) -> void:
	s.erase("wounded")
	s.erase("injured")


## HP one bandage restores to a squad: 10 for each soldier still serving.
static func bandage_heal(s: Dictionary) -> int:
	return 10 * s.men


static func search_spot(g: Dictionary, index: int) -> void:
	var ex: Dictionary = g.expedition
	var p: Variant = ex.pending
	if p == null or p.kind != "village":
		return
	if index < 0 or index >= p.spots.size():
		return
	var spot: Dictionary = p.spots[index]
	if spot.searched:
		return
	if spot.locked:
		if ex.supplies.tools < 1:
			return
		ex.supplies.tools -= 1
	spot.searched = true
	var msg: String = ex_rng(ex, func(r: RefCounted) -> String:
		if spot.locked:
			var silver: int = r.rint(30, 55)
			ex.loot.silver += silver
			var iron: int = r.rint(1, 2)
			ex.loot.iron += iron
			return "You pry the strongbox open (-1 tools): %d silver and %d iron." % [silver, iron]
		var roll: float = r.next()
		if roll < 0.12 and not p.spots.any(func(s: Dictionary) -> bool: return String(s.label).contains("(raiders)")):
			spot.label += " (raiders)"
			var here := node(ex, ex.current)
			ex.pending = {
				"kind": "battle",
				"nodeId": p.nodeId,
				"roll": Setup.roll_encounter("goblin_scouts", r, here.stage),
				"title": "Raiders in %s" % here.name,
				"objective": false,
				"surprise": false,
			}
			return "Goblins burst from the ruins!"
		if roll < 0.35:
			var n: int = r.rint(2, 4)
			ex.supplies.rations += n
			return "A hidden store of food: +%d rations." % n
		if roll < 0.58:
			var n: int = r.rint(2, 4)
			ex.loot.timber += n
			return "Seasoned beams worth hauling home: +%d timber." % n
		if roll < 0.7:
			ex.supplies.bandages += 2
			return "Linen and herbs: +2 bandages."
		if roll < 0.82:
			ex.supplies.bolts += 1
			ex.loot.iron += 1
			return "A hunter's cache: +1 bundle of bolts, +1 iron."
		var silver2: int = r.rint(10, 25)
		ex.loot.silver += silver2
		return "A few coins under the floorboards: +%d silver." % silver2
	)
	if ex.pending != null and ex.pending.kind == "village":
		ex.pending.messages.append("%s: %s" % [spot.label, msg])
	_add_log(ex, msg)


# ---------------------------------------------------------------- battles

## BattleUnits for the marching squads that can still fight.
static func battle_army(g: Dictionary) -> Array:
	var out: Array = []
	for s in army_soldiers(g):
		if s.hp > 0:
			out.append(Soldier.soldier_to_unit(s))
	return out


## Night battles: a carried torch lights the field (consumed); otherwise darkness
## hampers shooting. Returns {night, darkness, torchUsed}.
static func prepare_night(g: Dictionary) -> Dictionary:
	var ex: Dictionary = g.expedition
	var p: Variant = ex.pending
	if p == null or p.kind != "battle" or not p.get("night", false):
		return {"night": false, "darkness": false, "torchUsed": false}
	if ex.supplies.torches > 0:
		ex.supplies.torches -= 1
		_add_log(ex, "Torches are lit around the camp (-1 torch).")
		return {"night": true, "darkness": false, "torchUsed": true}
	return {"night": true, "darkness": true, "torchUsed": false}


## Apply a finished battle (a Battle instance) to the roster and expedition.
static func apply_battle(g: Dictionary, b: RefCounted, title: String, objective: bool) -> Dictionary:
	var ex: Dictionary = g.expedition
	ex.battles += 1
	var result: String = b.result if b.result != null else "defeat"
	var enemies_killed := 0
	var enemies_fled := 0
	var slain := 0
	for u in b.units:
		if u.faction != "enemy":
			continue
		if u.status == "dead":
			enemies_killed += 1
		elif u.status == "fled":
			enemies_fled += 1
		slain += maxi(0, JS.get_or(u, "size", 1) - JS.get_or(u, "alive", 0))
	var report := {
		"title": title,
		"result": result,
		"objective": objective,
		"loot": {},
		"fallen": [],
		"injured": [],
		"routed": [],
		"levelUps": [],
		"xp": [],
		"enemiesKilled": enemies_killed,
		"enemiesFled": enemies_fled,
		"enemySoldiersSlain": slain,
		"losses": [],
		"boltsUsed": 0,
	}
	# The soldiers who went down rise again once the fighting is over. Their
	# wounds weaken the squad in its next fight (Squad.wound_of); the penalty
	# it carried into this one is spent. A squad cut down to the last rises
	# Injured; cut down again while Injured, it is gone for good.
	for u in b.units.filter(func(x: Dictionary) -> bool: return x.faction == "player" and x.get("soldierId") != null):
		var s: Variant = null
		for r in g.roster:
			if r.id == u.soldierId:
				s = r
				break
		if s == null:
			continue
		s.battles += 1
		s.kills += u.kills
		var st := Soldier.soldier_stats(s)
		var size: int = DB.squad_size(s.typeId)
		# Soldiers who marched into the battle (as soldier_to_unit fielded them).
		var men0: int = maxi(1, mini(size, s.men))
		var marched: int = Squad.alive_for(maxi(1, mini(s.hp, st.hp * men0)), st.hp, men0)
		s.erase("wounded")
		s.erase("injured")
		if u.status == "dead":
			report.fallen.append({"name": s.name, "typeId": s.typeId, "level": s.level})
			report.losses.append({"name": s.name, "typeId": s.typeId, "fell": marched, "lost": s.men, "men": 0, "size": size, "fate": "gone"})
			ex.menLost = JS.get_or(ex, "menLost", 0) + s.men
			g.fallen.push_front({"name": s.name, "typeId": s.typeId, "level": s.level, "kills": s.kills, "battles": s.battles, "cause": "Fell at %s" % title, "cycle": g.cycle})
			var sid: String = s.id
			g.roster = g.roster.filter(func(r: Dictionary) -> bool: return r.id != sid)
			ex.army = ex.army.filter(func(id: String) -> bool: return id != sid)
			Game.chronicle(g, "%s and his %s fell at %s." % [s.name, String(DB.UNIT_TYPES[s.typeId].plural).to_lower(), title], "bad")
			continue
		if u.status == "downed":
			# Cut down to the last: the squad rises whole, Injured. The penalty,
			# not the pool or its spirit, carries the blow into the next fight.
			s.men = men0
			s.hp = Soldier.squad_hp_cap(s)
			s.morale = st.morale
			s.injured = true
			report.injured.append(s.name)
			report.losses.append({"name": s.name, "typeId": s.typeId, "fell": marched, "lost": 0, "men": s.men, "size": size, "fate": "injured"})
		else:
			# The survivors keep their scratches; the fallen get up with their
			# full share, wounded. (Men too hurt to march, which only an old save
			# can have, stay as they were.)
			var fell: int = maxi(0, marched - maxi(1, JS.get_or(u, "alive", marched)))
			s.men = men0
			s.hp = maxi(1, mini(int(u.hp) + fell * st.hp, Soldier.squad_hp_cap(s)))
			if fell > 0:
				s.wounded = fell
				report.losses.append({"name": s.name, "typeId": s.typeId, "fell": fell, "lost": 0, "men": s.men, "size": size, "fate": "wounded"})
			s.morale = maxi(1, u.morale + (12 if result == "victory" else -5))
			if u.status == "fled":
				s.morale = maxi(1, JS.rnd(st.morale * 0.25))
				report.routed.append(s.name)
		s.morale = mini(st.morale, s.morale)
		s.fatigue = mini(100, s.fatigue + 6)
		var hits: int = JS.get_or(b.hits_taken, u.uid, 0)
		s.armorCondition = maxf(0.3, s.armorCondition - hits * 0.05)
		# Only crossbows draw on the bolt supply (arcane and ballista bolts never run out).
		var sh: Variant = DB.UNIT_TYPES[s.typeId].get("shot")
		if sh != null and sh.get("ammo") != null:
			report.boltsUsed += maxi(0, s.ammo - maxi(0, u.ammo))
			s.ammo = maxi(0, u.ammo)
		report.xp.append({"name": s.name, "xp": u.xp})
		var lv: Variant = Game.gain_xp(g, s, u.xp)
		if lv != null:
			report.levelUps.append(lv)
	# Refill quivers from spare bolts.
	for s in army_soldiers(g):
		var shot: Variant = DB.UNIT_TYPES[s.typeId].get("shot")
		var full: int = JS.get_or(shot, "ammo", 0) if shot != null else 0
		if full == 0:
			continue
		while s.ammo < full and ex.supplies.bolts > 0:
			ex.supplies.bolts -= 1
			s.ammo = mini(full, s.ammo + 6)
	if result == "victory":
		var enc := DB.encounter_by_id(JS.get_or(b.setup, "encounterId", "goblin_scouts"))
		var lt: Dictionary = enc.loot
		var bonus := 0
		for u in b.units:
			if u.faction == "enemy" and u.status == "dead":
				bonus += JS.get_or(DB.UNIT_TYPES[u.typeId], "value", 0) * 2
		var loot: Dictionary = ex_rng(ex, func(r: RefCounted) -> Dictionary:
			var silver: int = r.rint(lt.silver[0], lt.silver[1]) + bonus
			var iron: int = r.rint(lt.iron[0], lt.iron[1]) if lt.get("iron") != null else 0
			var timber: int = r.rint(lt.timber[0], lt.timber[1]) if lt.get("timber") != null else 0
			return {"silver": silver, "iron": iron, "timber": timber, "trophies": JS.get_or(lt, "trophies", 0)}
		)
		for k in loot:
			ex.loot[k] += loot[k]
		report.loot = loot
		if objective:
			ex.objectiveDone = true
	var n := node(ex, ex.current)
	if result == "victory":
		_add_log(ex, "Victory: %s." % title, "good")
	elif result == "retreat":
		_add_log(ex, "The army withdrew from %s." % n.name, "bad")
	else:
		_add_log(ex, "Defeat at %s." % n.name, "bad")
	ex.pending = {"kind": "battleResult", "report": report}
	# An army with nobody able to fight goes home.
	if army_soldiers(g).is_empty():
		report.result = "defeat"
	return report


# ---------------------------------------------------------------- return

## Ends the expedition ("success" | "retreat" | "defeat"). Returns the ExpeditionReport.
static func return_home(g: Dictionary, outcome: String) -> Dictionary:
	var ex: Dictionary = g.expedition
	var c := DB.campaign_by_id(ex.campaignId)
	var loot: Dictionary = ex.loot.duplicate()
	if outcome == "defeat":
		for k in loot:
			loot[k] = floori(loot[k] / 2.0)
	var reward: Dictionary = c.reward.duplicate() if outcome == "success" else {}
	for k in loot:
		g.resources[k] += loot[k] + JS.get_or(reward, k, 0)
	var buyback := 0.0
	for k in ex.supplies:
		buyback += ex.supplies[k] * DB.SUPPLIES[k].cost * Game.effect(g, "quartermaster", "buyback")
	var bb := floori(buyback)
	g.resources.silver += bb
	var stipend: int = Game.effect(g, "command", "stipend")
	g.resources.silver += stipend
	var survivors := army_soldiers(g)
	for s in g.roster:
		var st := Soldier.soldier_stats(s)
		# Home again, the survivors heal fully. The fallen are only replaced by reinforcements.
		if ex.army.has(s.id):
			s.expeditions += 1
			s.hp = Soldier.squad_hp_cap(s)
			s.fatigue = 0
			s.morale = mini(st.morale, s.morale + (25 if outcome == "success" else 12))
		else:
			if not s.get("recovering", false):
				s.morale = mini(st.morale, s.morale + 20)
			s.recovering = false
			s.hp = Soldier.squad_hp_cap(s)
		s.drilled = false
		var shot: Variant = DB.UNIT_TYPES[s.typeId].get("shot")
		if shot != null and JS.get_or(shot, "ammo", 0):
			s.ammo = shot.ammo
	if outcome == "success":
		g.completed[c.id] = JS.get_or(g.completed, c.id, 0) + 1
	var fallen_now: Array = []
	for f in g.fallen:
		if f.cycle == g.cycle:
			fallen_now.append(f.name)
	var report := {
		"campaignId": c.id,
		"outcome": outcome,
		"loot": loot,
		"reward": reward,
		"buyback": bb,
		"stipend": stipend,
		"fallen": fallen_now,
		"survivors": survivors.map(func(s: Dictionary) -> String: return s.name),
		"strength": survivors.map(func(s: Dictionary) -> Dictionary: return {"name": s.name, "typeId": s.typeId, "men": s.men, "size": DB.squad_size(s.typeId), "wound": Squad.wound_of(s)}),
		"menLost": JS.get_or(ex, "menLost", 0),
		"marches": ex.marches,
		"battles": ex.battles,
	}
	var text: String
	if outcome == "success":
		text = "The company returns victorious from %s." % c.name
	elif outcome == "retreat":
		text = "The company retreats from %s, the objective unmet." % c.name
	else:
		text = "The company is broken in %s. Survivors straggle home." % c.name
	Game.chronicle(g, text, "good" if outcome == "success" else "bad")
	g.expedition = null
	g.lastReport = report
	Game.roll_recruits(g)
	return report


static func node_type_name(t: String) -> String:
	return DB.NODE_INFO[t].name
