## Port of tests/campaign.test.ts, plus the new game -> expedition -> return
## home flow and a timing of auto_expedition.
extends "res://tests/test_case.gd"

const Rng = preload("res://scripts/core/rng.gd")
const Game = preload("res://scripts/meta/game.gd")
const Expedition = preload("res://scripts/campaign/expedition.gd")
const Autoplay = preload("res://scripts/campaign/autoplay.gd")


# describe('campaign generation')
func test_every_node_is_reachable_and_leads_to_the_objective() -> void:
	for seed in range(1, 40):
		var g := Game.new_game(seed)
		var army: Array = g.roster.slice(0, 5).map(func(s: Dictionary) -> String: return s.id)
		var ex := Expedition.generate_expedition(g, "hillsvain_raids", army, {"rations": 10, "bandages": 2, "bolts": 2, "torches": 1, "tools": 1})
		var obj: Dictionary = ex.nodes.filter(func(n: Dictionary) -> bool: return n.type == "objective")[0]
		for n in ex.nodes:
			if n.type != "start":
				assert_true(ex.edges.any(func(e: Array) -> bool: return e[1] == n.id), "seed %d: %s has a way in" % [seed, n.id])
			if n.type != "objective":
				assert_true(ex.edges.any(func(e: Array) -> bool: return e[0] == n.id), "seed %d: %s has a way out" % [seed, n.id])
		# BFS from start reaches the objective.
		var seen := {"n0": true}
		var q: Array = ["n0"]
		while not q.is_empty():
			var c: String = q.pop_front()
			for e in ex.edges:
				if e[0] == c and not seen.has(e[1]):
					seen[e[1]] = true
					q.append(e[1])
		assert_true(seen.has(obj.id), "seed %d: objective reachable" % seed)
		assert_true(ex.nodes.any(func(n: Dictionary) -> bool: return n.type == "camp"), "seed %d: has a camp" % seed)
		ex.current = "n0"
		assert_true(Expedition.next_nodes(ex).size() > 0, "seed %d: roads out of the muster point" % seed)


# describe('full loop')
func test_plays_several_expeditions_end_to_end_without_breaking_state() -> void:
	if slow():
		return
	var outcomes: Array = []
	var t0 := Time.get_ticks_usec()
	var expeditions := 0
	for seed in range(1, 7):
		var g := Game.new_game(seed * 77)
		var rng := Rng.new(seed)
		for cycle in 4:
			if not Autoplay.auto_prepare(g, rng):
				break
			var out := Autoplay.auto_expedition(g, rng)
			expeditions += 1
			outcomes.append(out)
			assert_eq(g.expedition, null, "home again")
			for s in g.roster:
				assert_true(s.hp > 0, "hp > 0")
				assert_false(is_nan(float(s.morale)) or is_inf(float(s.morale)), "finite morale")
			assert_true(g.resources.silver >= 0, "silver >= 0")
	assert_true(outcomes.size() > 10, "outcomes: %d" % outcomes.size())
	assert_true(outcomes.count("success") > 0, "some success")
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("      auto loop: %d expeditions in %.0f ms (%.0f ms each, incl. auto_prepare)" % [expeditions, ms, ms / maxi(1, expeditions)])


func test_new_game_to_expedition_to_return_home() -> void:
	var g := Game.new_game(4242)
	var silver0: int = g.resources.silver
	var army: Array = g.roster.slice(0, 5).map(func(s: Dictionary) -> String: return s.id)
	var sup := Game.recommended_supplies(5, 1, Game.wagon_capacity(g), 6)
	var cost := Game.supply_cost_total(g, sup)
	Expedition.start_expedition(g, "hillsvain_raids", army, sup, cost)
	assert_eq(g.cycle, 1, "cycle")
	assert_eq(g.resources.silver, silver0 - cost, "supplies paid")
	assert_not_null(g.expedition, "on the road")
	assert_eq(g.expedition.startMen, 30, "five full squads marched")
	assert_eq(g.chronicle[0].text, "Expedition 1: 5 squads (30 soldiers) march on The Hillsvain Host.")
	# March to the first stage and resolve whatever is there without a battle.
	var next := Expedition.next_nodes(g.expedition)
	assert_true(next.size() >= 2, "a choice of roads")
	var target: Dictionary = next[0]
	for n in next:
		if n.type != "battle" and n.type != "ambush":
			target = n
			break
	var rations: int = g.expedition.supplies.rations
	assert_true(Expedition.march(g, target.id), "march")
	assert_eq(g.expedition.supplies.rations, rations - 3, "five squads eat three rations")
	assert_eq(g.expedition.current, target.id)
	assert_true(target.visited, "visited")
	assert_false(Expedition.march(g, target.id), "cannot march with something pending or to the same node")
	var outcome := ""
	if g.expedition.pending != null and g.expedition.pending.kind == "battle":
		outcome = "battle"
	else:
		# Leave the node and go home.
		if g.expedition.pending != null and g.expedition.pending.kind == "event":
			Expedition.choose_event(g, 0)
		Expedition.dismiss_pending(g)
		while g.expedition != null and g.expedition.pending != null and g.expedition.pending.kind != "battle":
			Expedition.dismiss_pending(g)
		if g.expedition != null:
			var report := Expedition.return_home(g, "retreat")
			outcome = report.outcome
			assert_eq(report.survivors.size(), 5, "everyone came back")
			assert_eq(report.marches, 1, "one march")
	assert_eq(outcome, "retreat", "seed 4242 takes a road without a battle and turns home")
	if outcome == "retreat":
		assert_eq(g.expedition, null, "home")
		assert_eq(g.lastReport.outcome, "retreat")
		assert_eq(g.chronicle[0].text, "The company retreats from The Hillsvain Host, the objective unmet.")
		for id in army:
			for s in g.roster:
				if s.id == id:
					assert_eq(s.expeditions, 1, "expedition counted")
					assert_eq(s.fatigue, 0, "rested")
		assert_true(g.recruits.size() >= 3, "new recruits rolled")


func test_auto_expedition_timing() -> void:
	if slow():
		return
	# Wall time of complete automated expeditions (AI battles on both sides).
	var g := Game.new_game(1000)
	var rng := Rng.new(0)
	var times: Array = []
	for cycle in 3:
		if not Autoplay.auto_prepare(g, rng):
			break
		var t0 := Time.get_ticks_usec()
		var out := Autoplay.auto_expedition(g, rng)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		times.append(ms)
		print("      auto_expedition %d: %s, %d battles, %.0f ms" % [cycle + 1, out, g.lastReport.battles, ms])
		assert_eq(g.expedition, null)
	assert_true(times.size() == 3, "three expeditions")
