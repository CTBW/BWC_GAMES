## The campaign layer must match the original step for step: expedition
## generation, driven runs (marches, events, camps, villages, effects, bandages,
## battles, the return home) and complete autoplay campaigns, comparing the full
## GameState after every step.
## Golden: tools/parity/campaign_golden.ts -> tests/fixtures/golden/campaign_golden.json
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

const SUP := {"rations": 10, "bandages": 2, "bolts": 2, "torches": 1, "tools": 1}

var golden: Dictionary


func before_all() -> void:
	golden = H.load_golden("campaign_golden.json")


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
			var upgrades: Array = []
			for b in ["command", "infirmary", "barracks", "training", "armoury", "quartermaster"]:
				var nl: Variant = Game.next_level(g, b)
				if nl != null and Game.can_afford(g, nl.cost) and g.resources.silver - JS.get_or(nl.cost, "silver", 0) > 150:
					Game.upgrade_building(g, b)
					upgrades.append(b)
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
	var setup := Setup.build_battle(p.roll, Expedition.battle_army(g), {"survivalBonus": Expedition.survival_bonus(g), "title": p.title, "darkness": night.darkness})
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
		"survivalBonus": Expedition.survival_bonus(g),
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
