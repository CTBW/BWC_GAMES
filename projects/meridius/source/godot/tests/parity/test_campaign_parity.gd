## The campaign layer step for step: expedition generation, driven runs
## (marches, events, camps, villages, effects, bandages, battles, the return
## home) and complete autoplay campaigns, comparing the full GameState after
## every step.
## Golden: tests/fixtures/golden/campaign_golden.json, first recorded from the
## archived TypeScript game by tools/parity/campaign_golden.ts. The driven runs
## and autoplay campaigns are now re-recorded by the port after a deliberate
## rule change (`MERIDIUS_RECORD=1 tools/test.sh test_campaign_parity`, with
## the run driver ported below); the other sections stay as the original wrote them.
extends "res://tests/test_case.gd"

const H = preload("res://tests/parity/test_meta_support.gd")
const JS = preload("res://scripts/core/js.gd")
const Rng = preload("res://scripts/core/rng.gd")
const DB = preload("res://scripts/data/db.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const Setup = preload("res://scripts/rules/setup.gd")
const Game = preload("res://scripts/meta/game.gd")
const Expedition = preload("res://scripts/campaign/expedition.gd")
const Autoplay = preload("res://scripts/campaign/autoplay.gd")

const Soldier = preload("res://scripts/meta/soldier.gd")
const Squad = preload("res://scripts/rules/squad.gd")

const SUP := {"rations": 10, "bandages": 2, "bolts": 2, "torches": 1, "tools": 1}
const UPGRADE_ORDER := ["command", "infirmary", "barracks", "training", "armoury", "quartermaster"]

var golden: Dictionary
var recording := H.recording()


func before_all() -> void:
	golden = H.load_golden("campaign_golden.json")


func after_all() -> void:
	if recording:
		H.write_golden("campaign_golden.json", golden)


func _match(actual: Variant, expected: Variant, msg: String) -> bool:
	return assert_eq(H.diff(actual, expected), "", msg)


func test_constants() -> void:
	assert_eq(Autoplay.RETREAT_STRENGTH, golden.RETREAT_STRENGTH)


func test_v8_sort_order_matches() -> void:
	for c in golden.v8sort:
		var r := Rng.new(c.seed)
		var calls: Array = []
		var arr: Array = range(c.n)
		Autoplay.v8_sort(arr, func(a: int, b: int) -> float:
			calls.append([a, b])
			return r.next() - 0.5
		)
		_match(calls, c.calls, "v8 sort calls n=%d seed %d" % [c.n, c.seed])
		_match(arr, c.sorted, "v8 sort result n=%d seed %d" % [c.n, c.seed])


func test_generate_expedition_matches() -> void:
	for c in golden.generated:
		var g := Game.new_game(c.seed)
		var ex := Expedition.generate_expedition(g, "hillsvain_raids", c.army, SUP)
		if not _match(ex, c.ex, "generateExpedition seed %d" % c.seed):
			return
		assert_eq(g.rng, c.gameRng, "game rng after seed %d" % c.seed)
		_match(ex.nodes.map(func(n: Dictionary) -> Dictionary: return Expedition.node_view(n)), c.views, "nodeView seed %d" % c.seed)
		var shown: Dictionary = ex.duplicate(true)
		for n in shown.nodes:
			n.revealed = true
			n.scouted = true
		_match(shown.nodes.map(func(n: Dictionary) -> Dictionary: return Expedition.node_view(n)), c.viewsScouted, "nodeView scouted seed %d" % c.seed)
		var names: Array = []
		for t in ["start", "battle", "ambush", "scout", "village", "event", "camp", "objective"]:
			names.append(Expedition.node_type_name(t))
		_match(names, c.nodeTypeNames, "nodeTypeName")


func test_driven_runs_with_scripted_battles_match() -> void:
	_driven(false)


func test_driven_runs_with_ai_battles_match() -> void:
	if slow():
		return
	_driven(true)


func _driven(auto: bool) -> void:
	if recording:
		for i in golden.runs.size():
			var r: Dictionary = golden.runs[i]
			if r.auto != auto:
				continue
			var expeditions: int = r.steps.filter(func(s: Dictionary) -> bool: return s.op == "startExpedition").size()
			golden.runs[i] = _driven_run(r.seed, expeditions, r.auto, JS.get_or(r, "raids", false))
		return
	var count := 0
	for r in golden.runs:
		if r.auto != auto:
			continue
		var g := Game.new_game(r.seed)
		if not _match(g, r.start, "run %d start" % r.seed):
			return
		var n := 0
		for st in r.steps:
			var label := "run %d step %d %s %s" % [r.seed, n, st.op, H._short(st.args)]
			var ret: Variant = _run(g, st.op, st.args)
			if not _match(ret, st.ret, label + " return"):
				return
			if not _match(g, st.state, label + " state"):
				return
			n += 1
			count += 1
	assert_true(count > 150, "steps replayed: %d" % count)


func test_autoplay_campaigns_match() -> void:
	if slow():
		return
	if recording:
		for a in golden.autos:
			a.cycles = _autoplay_cycles(a.seed, a.rngSeed)
		return
	for a in golden.autos:
		var g := Game.new_game(a.seed)
		var rng := Rng.new(a.rngSeed)
		if not _match(g, a.start, "auto %d start" % a.seed):
			return
		var ci := 0
		for c in a.cycles:
			var label := "auto %d cycle %d" % [a.seed, ci]
			var prepared := Autoplay.auto_prepare(g, rng)
			assert_eq(prepared, c.prepared, label + " prepared")
			if not _match(g, c.afterPrepare, label + " after autoPrepare"):
				return
			if not prepared:
				break
			var outcome := Autoplay.auto_expedition(g, rng)
			assert_eq(outcome, c.outcome, label + " outcome")
			if not _match(g, c.afterExpedition, label + " after autoExpedition"):
				return
			var upgrades := _auto_upgrades(g)
			_match(upgrades, c.upgrades, label + " upgrades")
			if not _match(g, c.afterUpgrades, label + " after upgrades"):
				return
			assert_eq(rng.state, c.rngState, label + " rng")
			ci += 1


# ---------------------------------------------------------------- replay

func _soldier(g: Dictionary, id: Variant) -> Variant:
	for s in g.roster:
		if s.id == id:
			return s
	return null


func _battle_of(g: Dictionary) -> Dictionary:
	var p: Dictionary = g.expedition.pending
	var night := Expedition.prepare_night(g)
	var setup := Setup.build_battle(p.roll, Expedition.battle_army(g), {"title": p.title, "darkness": night.darkness})
	return {"p": p, "b": Battle.new(setup)}


func _queries(g: Dictionary) -> Dictionary:
	var ex: Variant = g.expedition
	if ex == null:
		return {"none": true}
	var p: Variant = ex.pending
	var choices: Variant = null
	if p != null and p.kind == "event":
		choices = Expedition._event(p.eventId).choices.map(func(ch: Dictionary) -> Dictionary: return Expedition.choice_available(g, ch))
	return {
		"next": Expedition.next_nodes(ex).map(func(n: Dictionary) -> String: return n.id),
		"canMarch": ex.nodes.map(func(n: Dictionary) -> bool: return Expedition.can_march(g, n.id)),
		"views": ex.nodes.map(func(n: Dictionary) -> Dictionary: return Expedition.node_view(n)),
		"rationCost": Expedition.ration_cost(g),
		"army": Expedition.army_soldiers(g).map(func(s: Dictionary) -> String: return s.id),
		"battleArmy": Expedition.battle_army(g),
		"bandageHeal": Expedition.army_soldiers(g).map(func(s: Dictionary) -> int: return Expedition.bandage_heal(s)),
		"choices": choices,
	}


func _run(g: Dictionary, op: String, a: Array) -> Variant:
	match op:
		"startExpedition":
			Expedition.start_expedition(g, a[0], a[1], a[2], a[3])
			return null
		"march":
			return Expedition.march(g, a[0])
		"dismissPending":
			Expedition.dismiss_pending(g)
			return null
		"chooseEvent":
			Expedition.choose_event(g, a[0])
			return null
		"campRest":
			Expedition.camp_rest(g)
			return null
		"campWatch":
			Expedition.camp_watch(g)
			return null
		"campRepair":
			Expedition.camp_repair(g)
			return null
		"useBandage":
			return Expedition.use_bandage(g, a[0])
		"searchSpot":
			Expedition.search_spot(g, a[0])
			return null
		"hurtSquad":
			return Expedition.hurt_squad(g, _soldier(g, a[0]), a[1], func(who: String, verb: String) -> String: return "Test: %s %s." % [who, verb])
		"applyEffect":
			var subject: Variant = _soldier(g, a[1]) if a[1] != null else null
			if a[2] != null:
				return Expedition.apply_effect(g, a[0], subject, a[2])
			return Expedition.apply_effect(g, a[0], subject)
		"battleAuto":
			var bo := _battle_of(g)
			var b: RefCounted = bo.b
			Autoplay.auto_battle(b)
			var report := Expedition.apply_battle(g, b, bo.p.title, bo.p.objective)
			return {"report": report, "turn": b.turn, "result": b.result}
		"battleScripted":
			var bo := _battle_of(g)
			var b: RefCounted = bo.b
			for c in a[0]:
				var u: Dictionary = b.unit(c.uid)
				for k in ["status", "hp", "alive", "kills", "xp", "morale", "ammo"]:
					if c.has(k):
						u[k] = c[k]
				b.hits_taken[c.uid] = c.hits
			b.result = a[1]
			b.phase = "over"
			return Expedition.apply_battle(g, b, bo.p.title, bo.p.objective)
		"returnHome":
			return Expedition.return_home(g, a[0])
		"reinforce":
			return Game.reinforce(g, a[0], a[1])
		"hire":
			return Game.hire(g, a[0])
		"upgradeBuilding":
			return Game.upgrade_building(g, a[0])
		"treat":
			return Game.treat(g, a[0], a[1])
		"setRes":
			g.resources[a[0]] = a[1]
			return null
		"autoPrepare":
			return Autoplay.auto_prepare(g, Rng.new(a[0]))
		"query":
			return _queries(g)
	fail("unknown op " + op)
	return null


# ---------------------------------------------------------------- re-recording
# Ports of tools/parity/campaign_golden.ts (archived with the original), used
# only when MERIDIUS_RECORD=1.

## The buildings a captain upgrades after an autoplay expedition.
func _auto_upgrades(g: Dictionary) -> Array:
	var upgrades: Array = []
	for b in UPGRADE_ORDER:
		var nl: Variant = Game.next_level(g, b)
		if nl != null and Game.can_afford(g, nl.cost) and g.resources.silver - JS.get_or(nl.cost, "silver", 0) > 150:
			Game.upgrade_building(g, b)
			upgrades.append(b)
	return upgrades


## Up to four autoplay cycles (prepare, expedition, upgrades) of a new company.
func _autoplay_cycles(seed: int, rng_seed: int) -> Array:
	var g := Game.new_game(seed)
	var rng := Rng.new(rng_seed)
	var cycles: Array = []
	for c in 4:
		var before: int = g.fallen.size()
		var prepared := Autoplay.auto_prepare(g, rng)
		var after_prepare: Variant = H.jsonable(g)
		if not prepared:
			cycles.append({"prepared": prepared, "afterPrepare": after_prepare})
			break
		var outcome := Autoplay.auto_expedition(g, rng)
		var after_expedition: Variant = H.jsonable(g)
		var deaths: int = g.fallen.size() - before
		var upgrades := _auto_upgrades(g)
		cycles.append({"prepared": prepared, "afterPrepare": after_prepare, "outcome": outcome, "deaths": deaths,
			"afterExpedition": after_expedition, "upgrades": upgrades, "afterUpgrades": H.jsonable(g), "rngState": rng.state})
	return cycles


const EFFECTS := [
	{"k": "supply", "id": "rations", "n": 3}, {"k": "supply", "id": "torches", "n": -5}, {"k": "loot", "id": "silver", "n": 12}, {"k": "loot", "id": "iron", "n": -4},
	{"k": "morale", "n": -9, "who": "all"}, {"k": "morale", "n": 6, "who": "random"}, {"k": "morale", "n": 4, "who": "strongest"}, {"k": "morale", "n": -3, "who": "type:spearman"},
	{"k": "hp", "n": -14, "who": "weakest"}, {"k": "hp", "n": -7, "who": "all"}, {"k": "hp", "n": 5, "who": "random"}, {"k": "hp", "n": -30, "who": "type:crossbowman"},
	{"k": "fatigue", "n": 25, "who": "all"}, {"k": "fatigue", "n": -10, "who": "random"}, {"k": "xp", "n": 12, "who": "strongest"}, {"k": "xp", "n": 40, "who": "random"},
	{"k": "injury", "who": "random"}, {"k": "injury", "who": "weakest"}, {"k": "recruit", "typeId": "spearman", "level": 2}, {"k": "recruit", "typeId": "crossbowman", "level": 1},
	{"k": "reveal", "stages": 2}, {"k": "battle", "encounterId": "goblin_scouts"},
]


## A driven run: `expeditions` expeditions steered by a seeded driver through
## every kind of node, with AI (`auto`) or scripted battles; `raids` rests
## without a watch and searches villages in order, to meet night raids.
func _driven_run(seed: int, expeditions: int, auto: bool, raids: bool) -> Dictionary:
	var g := Game.new_game(seed)
	var drv := Rng.new(seed * 31 + 5)
	var start: Variant = H.jsonable(g)
	var steps: Array = []
	var step := func(op: String, args: Array) -> Variant:
		var ret: Variant = _run(g, op, H.jsonable(args))
		steps.append({"op": op, "args": H.jsonable(args), "ret": H.jsonable(ret), "state": H.jsonable(g)})
		return ret
	var effects_done := false
	for e in expeditions:
		# Between expeditions: refill and hire, then march out.
		if e > 0:
			step.call("setRes", ["silver", g.resources.silver + 200])
			for s in g.roster.duplicate():
				if Game.missing_men(s) > 0:
					step.call("reinforce", [s.id, drv.rint(1, 3)])
			if g.recruits.size() > 0 and g.roster.size() < 8:
				step.call("hire", [g.recruits[0].id])
			for s in g.roster:
				if s.injuries.size() > 0:
					step.call("treat", [s.id, s.injuries[0]])
					break
			step.call("upgradeBuilding", [drv.pick(["infirmary", "quartermaster", "barracks", "armoury"])])
		var c: Dictionary = Game.available_campaigns(g)[0]
		var army: Array = g.roster.filter(func(s: Dictionary) -> bool: return Game.eligibility(g, s, c).ok).slice(0, 6).map(func(s: Dictionary) -> String: return s.id)
		var xb: int = army.filter(func(id: String) -> bool: return _soldier(g, id).typeId == "crossbowman").size()
		var sup := Game.recommended_supplies(army.size(), xb, Game.wagon_capacity(g), c.stages + 1)
		if e == 1:
			sup.rations = 4 # a hungry march
		step.call("startExpedition", [c.id, army, sup, mini(g.resources.silver, Game.supply_cost_total(g, sup))])
		step.call("query", [])
		var guard := 0
		while g.expedition != null and guard < 150:
			guard += 1
			var ex: Dictionary = g.expedition
			var p: Variant = ex.pending
			if p == null:
				var next := Expedition.next_nodes(ex)
				if not effects_done and ex.marches >= 2:
					effects_done = true
					for ef in EFFECTS:
						var army2 := Expedition.army_soldiers(g)
						var subj: Variant = null
						if drv.chance(0.5) and army2.size() > 0:
							subj = drv.pick(army2).id
						var label: Variant = "A test" if drv.chance(0.5) else null
						step.call("applyEffect", [ef, subj, label])
					step.call("hurtSquad", [Expedition.army_soldiers(g)[0].id, 9.5])
					step.call("query", [])
				var hurt: Variant = null
				for s in Expedition.army_soldiers(g):
					if s.hp < Soldier.squad_hp_cap(s):
						hurt = s
						break
				if hurt != null and drv.chance(0.5):
					step.call("useBandage", [hurt.id])
				if drv.chance(0.1):
					var first: Array = Expedition.army_soldiers(g)
					step.call("useBandage", [first[0].id if first.size() > 0 else "nobody"])
				if drv.chance(0.08):
					step.call("march", [ex.nodes[ex.nodes.size() - 1].id]) # not adjacent: refused
				if drv.chance(0.03) and ex.marches >= 2:
					step.call("returnHome", ["retreat"])
					break
				if next.is_empty():
					step.call("returnHome", ["success" if ex.objectiveDone else "retreat"])
					break
				step.call("march", [drv.pick(next).id])
				if drv.chance(0.3):
					step.call("query", [])
				continue
			match str(p.kind):
				"arrive", "scout":
					step.call("dismissPending", [])
				"event":
					if p.get("result") == null:
						var ev: Dictionary = Expedition._event(p.eventId)
						if drv.chance(0.2):
							step.call("chooseEvent", [drv.rint(0, ev.choices.size() - 1)]) # maybe unavailable
						if not _pending_has_result(g):
							var ok: Array = []
							for i in ev.choices.size():
								if Expedition.choice_available(g, ev.choices[i]).ok:
									ok.append(i)
							step.call("query", [])
							step.call("chooseEvent", [drv.pick(ok) if ok.size() > 0 else 0])
					step.call("dismissPending", [])
				"camp":
					# Raids mode: rest without a watch, so night raids come while torches remain.
					var acts: Array = ["campRest"] if raids else drv.shuffle(["campWatch", "campRepair", "campRest"])
					for a in acts:
						if _pending_kind(g) != "camp":
							break
						if drv.chance(0.85):
							step.call(a, [])
					if _pending_kind(g) == "camp":
						step.call("dismissPending", [])
				"village":
					var order: Array = [0, 1, 2, 3] if raids else drv.shuffle([0, 1, 2, 3, 4])
					for i in order:
						if _pending_kind(g) != "village":
							break
						step.call("searchSpot", [i])
					if _pending_kind(g) == "village":
						step.call("dismissPending", [])
				"battle":
					if auto:
						step.call("battleAuto", [])
					else:
						var outcome := _script_outcome(g, drv)
						step.call("battleScripted", [outcome[0], outcome[1]])
				"battleResult":
					step.call("dismissPending", [])
				"complete":
					step.call("returnHome", ["success"])
		if g.expedition != null:
			step.call("returnHome", ["retreat"])
	return {"seed": seed, "auto": auto, "raids": raids, "start": start, "steps": steps}


func _pending_kind(g: Dictionary) -> String:
	if g.expedition == null or g.expedition.pending == null:
		return ""
	return str(g.expedition.pending.kind)


func _pending_has_result(g: Dictionary) -> bool:
	return g.expedition != null and g.expedition.pending != null and g.expedition.pending.get("result") != null


## Scripted battle outcome: a fate for every squad that needs no AI.
func _script_outcome(g: Dictionary, drv) -> Array:
	var p: Dictionary = g.expedition.pending
	# Mirror _battle_of without touching the game: build on copies to read the units.
	var copy: Dictionary = H.jsonable(g)
	var night := Expedition.prepare_night(copy)
	var setup := Setup.build_battle(H.jsonable(p.roll), Expedition.battle_army(copy), {"title": p.title, "darkness": night.darkness})
	var changes: Array = []
	for u in setup.units:
		if u.status == "reserve" and drv.chance(0.6):
			continue
		var roll: float = drv.next()
		var c := {"uid": u.uid, "hits": drv.rint(0, 6)}
		if u.faction == "player":
			if roll < 0.12:
				c.merge({"status": "dead", "hp": 0, "alive": 0}, true)
			elif roll < 0.27:
				c.merge({"status": "downed", "hp": 0, "alive": 0}, true)
			else:
				var hp: int = drv.rint(1, u.hp)
				c.merge({"status": "fled" if roll < 0.37 else "active", "hp": hp, "alive": Squad.alive_for(hp, u.hpPer, u.alive)}, true)
			c.merge({"kills": drv.rint(0, 3), "xp": drv.rint(0, 16), "morale": drv.rint(1, u.maxMorale)}, true)
			if u.get("shot") != null:
				c.ammo = drv.rint(0, u.ammo)
		else:
			if roll < 0.5:
				c.merge({"status": "dead", "hp": 0, "alive": 0}, true)
			elif roll < 0.7:
				c.merge({"status": "fled", "hp": drv.rint(1, u.hp), "alive": 1}, true)
			else:
				var hp: int = drv.rint(1, u.hp)
				c.merge({"hp": hp, "alive": Squad.alive_for(hp, u.hpPer, u.alive)}, true)
		changes.append(c)
	return [changes, drv.pick(["victory", "victory", "victory", "retreat", "defeat"])]
