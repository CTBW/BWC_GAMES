## Port of tests/meta-squads.test.ts: squads in the meta game.
extends "res://tests/test_case.gd"

const JS = preload("res://scripts/core/js.gd")
const Rng = preload("res://scripts/core/rng.gd")
const DB = preload("res://scripts/data/db.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const Setup = preload("res://scripts/rules/setup.gd")
const Game = preload("res://scripts/meta/game.gd")
const Soldier = preload("res://scripts/meta/soldier.gd")
const Expedition = preload("res://scripts/campaign/expedition.gd")
const Autoplay = preload("res://scripts/campaign/autoplay.gd")
const Squad = preload("res://scripts/rules/squad.gd")


func _on_expedition(seed := 5) -> Dictionary:
	var g := Game.new_game(seed)
	var army: Array = g.roster.slice(0, 5).map(func(s: Dictionary) -> String: return s.id)
	Expedition.start_expedition(g, "hillsvain_raids", army, {"rations": 30, "bandages": 3, "bolts": 2, "torches": 2, "tools": 1}, 0)
	return g


func test_new_squads_start_at_full_strength() -> void:
	var g := Game.new_game(3)
	for s in g.roster:
		assert_eq(s.men, DB.squad_size(s.typeId), "men")
		assert_eq(s.hp, Soldier.squad_max_hp(s), "hp")


func test_healing_never_raises_the_dead() -> void:
	var g := _on_expedition()
	var s: Dictionary = g.roster[0]
	var per: int = Soldier.soldier_stats(s).hp
	s.men = 4
	s.hp = per * 3 + 2
	for i in 5:
		Expedition.use_bandage(g, s.id)
	assert_true(s.hp <= per * 4, "hp capped at the survivors' shares")
	assert_eq(s.men, 4, "men")
	assert_eq(Expedition.bandage_heal(s), 40, "bandageHeal")


func test_damage_outside_battle_kills_soldiers_at_each_share_never_the_last_one() -> void:
	var g := _on_expedition()
	var s: Dictionary = g.roster[0]
	var per: int = Soldier.soldier_stats(s).hp
	var lost := Expedition.hurt_squad(g, s, per * 2 + 1, func(who: String, verb: String) -> String: return "Fever: %s %s." % [who, verb])
	assert_eq(lost, 2, "lost")
	assert_eq(s.men, DB.squad_size(s.typeId) - 2, "men")
	var line: String = g.expedition.log[0].text
	assert_true(line.begins_with("Fever: two of ") and line.ends_with(" die."), "log line: " + line)
	Expedition.hurt_squad(g, s, 10000, func(_w: String, _v: String) -> String: return "x")
	assert_eq(s.men, 1, "never the last one")
	assert_eq(s.hp, 1, "hp")


func test_camp_rest_heals_only_the_survivors() -> void:
	var g := _on_expedition()
	var ex: Dictionary = g.expedition
	ex.pending = {"kind": "camp", "nodeId": ex.current, "done": ["watch"], "messages": []}
	var s: Dictionary = g.roster[0]
	var per: int = Soldier.soldier_stats(s).hp
	s.men = 3
	s.hp = JS.rnd(per * 2.5)
	Expedition.camp_rest(g)
	assert_true(s.hp <= Soldier.squad_hp_cap(s), "capped")
	assert_eq(s.men, 3, "men")


func test_battle_results_copy_squad_strength_back_to_the_roster() -> void:
	var g := _on_expedition(11)
	var roll := Setup.roll_encounter("raiding_party", Rng.new(4), 1)
	var b := Battle.new(Setup.build_battle(roll, Expedition.battle_army(g), {}))
	Autoplay.auto_battle(b)
	var before := {}
	for s in g.roster:
		before[s.id] = s.men
	var report := Expedition.apply_battle(g, b, "Test", false)
	for u in b.units.filter(func(x: Dictionary) -> bool: return x.faction == "player"):
		var s: Variant = _squad(g, u.get("soldierId"))
		if u.status == "dead":
			assert_eq(s, null, "the dead leave the roster")
			continue
		assert_not_null(s, "survivor on the roster")
		# The fallen get back up; the squad carries their wounds instead.
		assert_eq(s.men, before[s.id], "the fallen get back up")
		if u.status == "downed":
			assert_true(s.get("injured", false), "cut down to the last: injured")
		else:
			assert_eq(s.get("wounded", 0), before[s.id] - u.alive, "wounded: those who went down")
		assert_true(s.hp <= Soldier.squad_hp_cap(s), "hp capped")
	var lost := 0
	for l in report.losses:
		lost += l.lost
	assert_eq(lost, g.expedition.menLost, "menLost")


func _squad(g: Dictionary, id: Variant) -> Variant:
	for r in g.roster:
		if r.id == id:
			return r
	return null


## A battle for the expedition's army, settled by hand: `fate(u, b)` sets what happened to each squad.
func _settle(g: Dictionary, result: String, fate: Callable, opts := {}) -> Dictionary:
	var roll := Setup.roll_encounter("raiding_party", Rng.new(4), 1)
	var b := Battle.new(Setup.build_battle(roll, Expedition.battle_army(g), opts))
	for u in b.units.filter(func(x: Dictionary) -> bool: return x.faction == "player"):
		fate.call(u, b)
	b.phase = "over"
	b.result = result
	return Expedition.apply_battle(g, b, "Test", false)


func test_the_fallen_rise_wounded_and_weaken_the_squads_next_fight() -> void:
	var g := _on_expedition(11)
	var s: Dictionary = g.roster[0]
	var size: int = DB.squad_size(s.typeId)
	var per: int = Soldier.soldier_stats(s).hp
	_settle(g, "victory", func(u: Dictionary, _b) -> void:
		if u.soldierId == s.id:
			# Two go down; the four standing share a scratch of 3 HP.
			u.hp = per * (size - 2) - 3
			u.alive = size - 2
	)
	assert_eq(s.men, size, "the fallen get back up")
	assert_eq(s.wounded, 2, "two wounded")
	assert_eq(s.hp, per * size - 3, "the survivors keep their scratches")
	var clean_s: Dictionary = s.duplicate(true)
	clean_s.erase("wounded")
	var clean := Soldier.soldier_to_unit(clean_s)
	var u := Soldier.soldier_to_unit(s)
	assert_eq(u.alive, size, "every soldier marches")
	var w: Dictionary = u.wound
	assert_eq(w.kind, "wounded")
	assert_almost(float(w.damage), Squad.WOUND_PENALTY * 2 / size, 1e-9, "damage share")
	assert_eq(w.morale, JS.rnd(Squad.WOUND_MORALE * 2.0 / size), "morale")
	assert_eq(u.stats.defense, JS.rnd(clean.stats.defense * (1 - w.defense)), "defense")
	assert_eq(u.stats.rangedDefense, JS.rnd(clean.stats.rangedDefense * (1 - w.defense)), "ranged defense")
	assert_eq(u.morale, maxi(1, clean.morale - w.morale), "starts with less morale")
	assert_eq(clean.get("wound"), null, "no wound, no penalty")
	for o in g.roster.slice(1, 5):
		assert_eq(Squad.wound_of(o), null, "nobody else went down")


func test_a_wound_is_spent_by_the_next_fight() -> void:
	var g := _on_expedition(11)
	var a: Dictionary = g.roster[0]
	var c: Dictionary = g.roster[1]
	a.wounded = 3
	c.injured = true
	var report := _settle(g, "victory", func(_u, _b) -> void: pass)
	assert_eq(Squad.wound_of(a), null, "wounded: spent")
	assert_eq(Squad.wound_of(c), null, "injured: spent")
	assert_true(report.losses.is_empty(), "nobody went down")


func test_a_squad_cut_down_rises_injured_and_is_gone_if_cut_down_again() -> void:
	var g := _on_expedition(12)
	var s: Dictionary = g.roster[0]
	var size: int = DB.squad_size(s.typeId)
	var st := Soldier.soldier_stats(s)
	var report := _settle(g, "retreat", func(u: Dictionary, b) -> void:
		if u.soldierId == s.id:
			b._fall(u)
			assert_eq(u.status, "downed", "cut down, not dead")
	)
	assert_eq(_squad(g, s.id), s, "still on the roster")
	assert_true(s.injured, "injured")
	assert_eq(s.men, size, "rises whole")
	assert_eq(s.hp, Soldier.squad_hp_cap(s), "full pool")
	assert_eq(report.injured, [s.name], "reported")
	assert_eq(g.expedition.menLost, 0, "nobody lost for good")
	var u := Soldier.soldier_to_unit(s)
	assert_eq(u.wound.kind, "injured")
	assert_almost(float(u.wound.damage), Squad.INJURED_PENALTY, 1e-9, "damage")
	assert_eq(u.morale, st.morale - Squad.INJURED_MORALE, "morale")
	report = _settle(g, "retreat", func(x: Dictionary, b) -> void:
		if x.soldierId == s.id:
			b._fall(x)
			assert_eq(x.status, "dead", "cut down again while injured: gone")
	)
	assert_eq(_squad(g, s.id), null, "gone from the roster")
	assert_false(g.expedition.army.has(s.id), "gone from the army")
	assert_eq(g.fallen[0].name, s.name, "remembered among the fallen")
	assert_eq(report.losses[0].fate, "gone")
	assert_eq(g.expedition.menLost, size, "the whole squad lost")


func _loss(report: Dictionary, s: Dictionary) -> Dictionary:
	return report.losses.filter(func(l: Dictionary) -> bool: return l.name == s.name)[0]


func test_the_hurt_are_the_first_to_die_when_they_go_down_again() -> void:
	var g := _on_expedition(11)
	var a: Dictionary = g.roster[0]
	var c: Dictionary = g.roster[1]
	var size_a: int = DB.squad_size(a.typeId)
	var size_c: int = DB.squad_size(c.typeId)
	var per_a: int = Soldier.soldier_stats(a).hp
	var per_c: int = Soldier.soldier_stats(c).hp
	a.wounded = 2
	c.wounded = 2
	var report := _settle(g, "victory", func(u: Dictionary, _b) -> void:
		if u.soldierId == a.id:
			# Three go down: the two hurt die, the third rises wounded.
			u.alive = size_a - 3
			u.hp = per_a * u.alive
		elif u.soldierId == c.id:
			# One goes down, hurt, and dies; the fight spends the other's wound.
			u.alive = size_c - 1
			u.hp = per_c * u.alive
	)
	assert_eq(a.men, size_a - 2, "the two hurt die")
	assert_eq(a.wounded, 1, "the third rises wounded")
	assert_eq(a.hp, per_a * (size_a - 2), "he gets up with his full share")
	assert_eq(c.men, size_c - 1, "the hurt one who went down dies")
	assert_eq(Squad.wound_of(c), null, "nobody rises wounded")
	assert_eq(g.expedition.menLost, 3, "three lost for good")
	var la := _loss(report, a)
	assert_eq([la.fell, la.lost, la.men, la.fate], [3, 2, size_a - 2, "wounded"], "reported")
	var lc := _loss(report, c)
	assert_eq([lc.fell, lc.lost, lc.men, lc.fate], [1, 1, size_c - 1, "died"], "reported")
	assert_true(g.chronicle.any(func(e: Dictionary) -> bool: return e.text.begins_with("Two of %s's " % a.name) and e.text.contains("fell for good")), "chronicled")
	# Untouched, a squad without wounds loses nobody for good.
	for o in g.roster.slice(2, 5):
		assert_eq(o.men, DB.squad_size(o.typeId), "the rest rise whole")


func test_an_injured_squad_loses_every_soldier_who_goes_down() -> void:
	var g := _on_expedition(11)
	var c: Dictionary = g.roster[1]
	var size: int = DB.squad_size(c.typeId)
	var per: int = Soldier.soldier_stats(c).hp
	c.injured = true
	var report := _settle(g, "victory", func(u: Dictionary, _b) -> void:
		if u.soldierId == c.id:
			u.alive = size - 2
			u.hp = per * u.alive
	)
	assert_eq(_squad(g, c.id), c, "still on the roster")
	assert_eq(c.men, size - 2, "both who went down die")
	assert_eq(Squad.wound_of(c), null, "the survivors are spent of the injury, nobody rises wounded")
	assert_eq(g.expedition.menLost, 2, "two lost for good")
	assert_eq(_loss(report, c).fate, "died")


func test_a_wounded_squad_cut_down_loses_its_hurt_and_rises_injured() -> void:
	var g := _on_expedition(12)
	var s: Dictionary = g.roster[0]
	var size: int = DB.squad_size(s.typeId)
	s.wounded = 2
	var said := [false]
	var report := _settle(g, "retreat", func(u: Dictionary, b) -> void:
		if u.soldierId == s.id:
			b._fall(u)
			assert_eq(u.status, "downed", "cut down, not dead: the unhurt are dragged clear")
			said[0] = b.events.any(func(e: Dictionary) -> bool: return e.t == "log" and String(e.text).contains("those still hurt from the last fight die"))
	)
	assert_true(said[0], "the battle log says so")
	assert_eq(_squad(g, s.id), s, "still on the roster")
	assert_eq(s.men, size - 2, "the two hurt die")
	assert_true(s.injured, "the rest rise Injured")
	assert_eq(s.hp, Soldier.squad_hp_cap(s), "full pool")
	assert_eq(report.injured, [s.name], "reported")
	assert_eq(g.expedition.menLost, 2, "two lost for good")
	var l := _loss(report, s)
	assert_eq([l.lost, l.men, l.fate], [2, size - 2, "injured"])


func test_a_squad_cut_down_with_every_soldier_hurt_is_gone() -> void:
	var g := _on_expedition(12)
	var s: Dictionary = g.roster[0]
	var per: int = Soldier.soldier_stats(s).hp
	# Fever thinned the squad after its last fight; the two left are both hurt.
	s.men = 2
	s.hp = per * 2
	s.wounded = 2
	var report := _settle(g, "retreat", func(u: Dictionary, b) -> void:
		if u.soldierId == s.id:
			b._fall(u)
			assert_eq(u.status, "dead", "nobody whole to drag clear")
	)
	assert_eq(_squad(g, s.id), null, "gone from the roster")
	assert_eq(_loss(report, s).fate, "gone")
	assert_eq(g.expedition.menLost, 2, "both lost")


func test_enemies_cut_down_are_dead_and_carry_no_wounds() -> void:
	var g := _on_expedition(12)
	var roll := Setup.roll_encounter("raiding_party", Rng.new(4), 1)
	var b := Battle.new(Setup.build_battle(roll, Expedition.battle_army(g), {}))
	var e: Dictionary = b.units.filter(func(x: Dictionary) -> bool: return x.faction == "enemy" and x.status == "active")[0]
	assert_eq(e.get("wound"), null, "no wounds")
	b._fall(e)
	assert_eq(e.status, "dead")


func test_wounds_cut_the_damage_a_squad_deals() -> void:
	var g := _on_expedition(11)
	var roll := Setup.roll_encounter("raiding_party", Rng.new(4), 1)
	var b := Battle.new(Setup.build_battle(roll, Expedition.battle_army(g), {"fogOfWar": false}))
	var a: Dictionary = b.units.filter(func(x: Dictionary) -> bool: return x.faction == "player" and x.typeId == "footman")[0]
	var t: Dictionary = b.units.filter(func(x: Dictionary) -> bool: return x.faction == "enemy" and x.status == "active")[0]
	var full: Dictionary = b.preview(a, t)
	a.wound = Squad.wound_of({"typeId": a.typeId, "wounded": 3})
	var hurt: Dictionary = b.preview(a, t)
	var mult: float = 1.0 - Squad.WOUND_PENALTY * 3 / a.size
	assert_true(hurt.max < full.max, "less damage: %d < %d" % [hurt.max, full.max])
	assert_eq(hurt.chance, full.chance, "the hit chance is untouched")
	if full.arc == "front" and not a.tags.has("flanker"):
		var armor: float = t.stats.armor * (1 - a.meleePierce)
		assert_eq(hurt.max, maxi(1, JS.rnd(a.melee[1] * mult - armor)) * a.alive, "max per soldier times soldiers")


func test_a_nights_rest_or_a_bandage_dresses_the_wounds() -> void:
	var g := _on_expedition(11)
	var ex: Dictionary = g.expedition
	var a: Dictionary = g.roster[0]
	var c: Dictionary = g.roster[1]
	a.wounded = 2
	c.injured = true
	# A watch is kept, so no raider comes.
	ex.pending = {"kind": "camp", "nodeId": ex.current, "done": ["watch"], "messages": []}
	Expedition.camp_rest(g)
	assert_eq(Squad.wound_of(a), null, "wounded: dressed")
	assert_eq(Squad.wound_of(c), null, "injured: dressed")
	assert_true(ex.pending.messages.any(func(m: String) -> bool: return m.begins_with("The wounds of the last fight are dressed: two squads")), "said so")
	# Hungry, the army sleeps but the wounds stay.
	a.wounded = 2
	ex.supplies.rations = 0
	ex.pending = {"kind": "camp", "nodeId": ex.current, "done": ["watch"], "messages": []}
	Expedition.camp_rest(g)
	assert_eq(a.wounded, 2, "no food, no dressing")
	# A bandage dresses one squad's wounds, even at full HP.
	a.hp = Soldier.squad_hp_cap(a)
	var bandages: int = ex.supplies.bandages
	assert_true(Expedition.use_bandage(g, a.id), "bandaged")
	assert_eq(Squad.wound_of(a), null, "dressed")
	assert_eq(ex.supplies.bandages, bandages - 1, "one bandage")
	assert_false(Expedition.use_bandage(g, a.id), "nothing left to dress")


func test_the_infirmary_dresses_wounds_at_home() -> void:
	var g := Game.new_game(11)
	var a: Dictionary = g.roster[0]
	var c: Dictionary = g.roster[1]
	a.wounded = 2
	c.injured = true
	# A share of a new soldier's price for each soldier still hurt; Injured, all of them.
	var share: float = Game.effect(g, "infirmary", "dressCost")
	var cost_a := ceili(Game.reinforce_cost(g, a) * 2 * share)
	assert_eq(Game.dress_cost(g, a), cost_a, "wounded: the two still hurt")
	assert_eq(Game.dress_cost(g, c), ceili(Game.reinforce_cost(g, c) * c.men * share), "injured: every soldier")
	assert_eq(Game.dress_cost(g, g.roster[2]), 0, "nothing to dress")
	g.resources.silver = Game.dress_cost(g, c) - 1
	assert_false(Game.dress_wounds(g, c.id), "too poor")
	assert_true(c.injured, "still injured")
	g.resources.silver = 500
	assert_true(Game.dress_wounds(g, a.id), "dressed")
	assert_eq(Squad.wound_of(a), null, "wounded: dressed")
	assert_eq(g.resources.silver, 500 - cost_a, "paid")
	assert_false(a.get("recovering", false), "fit for the next expedition")
	assert_true(Game.dress_wounds(g, c.id), "injured: dressed")
	assert_eq(Squad.wound_of(c), null, "no longer injured")
	assert_false(Game.dress_wounds(g, a.id), "nothing left to dress")
	# A better Infirmary dresses them for less.
	a.wounded = 2
	var before := Game.dress_cost(g, a)
	g.buildings.infirmary = 3
	assert_true(Game.dress_cost(g, a) < before, "House of Healing: cheaper")
	# Spent before the next fight, the penalty never reaches the field.
	Game.dress_wounds(g, a.id)
	assert_false(Soldier.soldier_to_unit(a).has("wound"), "marches whole")


func test_dressing_costs_less_than_refilling_the_ranks() -> void:
	var g := Game.new_game(11)
	for lv in [1, 2, 3]:
		g.buildings.infirmary = lv
		for type_id in DB.UNIT_TYPES:
			if JS.get_or(DB.UNIT_TYPES[type_id], "recruitCost", 0) <= 0:
				continue
			var size := DB.squad_size(type_id)
			for level in [1, 5]:
				var s := {"typeId": type_id, "level": level, "men": size}
				var new: int = Game.reinforce_cost(g, s)
				for n in range(1, size):
					s.wounded = n
					var c := Game.dress_cost(g, s)
					assert_true(c > 0 and c < new * n, "%s L%d, Infirmary %d: %d hurt dress for %d, not %d" % [type_id, level, lv, n, c, new * n])
				s.erase("wounded")
				s.injured = true
				var ci := Game.dress_cost(g, s)
				assert_true(ci > 0 and ci < new * size, "%s L%d, Infirmary %d: Injured dress for %d, not %d" % [type_id, level, lv, ci, new * size])


func test_the_company_automation_dresses_wounds_at_home() -> void:
	var g := Game.new_game(11)
	g.resources.silver = 1000
	g.roster[0].wounded = 3
	g.roster[1].injured = true
	Autoplay.auto_prepare(g, Rng.new(4))
	assert_eq(Squad.wound_of(g.roster[0]), null, "wounded: dressed")
	assert_eq(Squad.wound_of(g.roster[1]), null, "injured: dressed")


func test_only_the_barracks_raises_men_at_a_price_and_not_on_campaign() -> void:
	var g := Game.new_game(9)
	var s: Dictionary = g.roster[0]
	var per: int = Soldier.soldier_stats(s).hp
	s.men = 3
	s.hp = per * 3
	g.resources.silver = 100
	var cost := Game.reinforce_cost(g, s)
	assert_true(Game.reinforce(g, s.id), "reinforce")
	assert_eq(s.men, 4, "men")
	assert_eq(s.hp, per * 4, "hp")
	assert_eq(g.resources.silver, 100 - cost, "paid")
	assert_true(Game.reinforce(g, s.id, 9), "fill up")
	assert_eq(s.men, DB.squad_size(s.typeId), "full")
	assert_false(Game.can_reinforce(g, s).ok, "nothing to fill")
	s.men = 5
	g.expedition = Expedition.generate_expedition(g, "hillsvain_raids", [s.id], {"rations": 1, "bandages": 0, "bolts": 0, "torches": 0, "tools": 0})
	assert_false(Game.reinforce(g, s.id), "not on campaign")


func test_migrates_saves_from_before_squads() -> void:
	var g := Game.new_game(21)
	var old: Dictionary = JS.normalize(JSON.parse_string(Game.to_save_json(g)))
	var per: int = Soldier.soldier_stats(g.roster[0]).hp
	for s in old.roster + old.recruits:
		s.erase("men")
		s.hp = Soldier.soldier_stats(s).hp
	old.roster[0].hp = per - 7
	old.roster[1].erase("hp")
	var m := Game.migrate_save(old)
	assert_eq(m.roster[0].men, DB.squad_size(m.roster[0].typeId), "men restored")
	assert_eq(m.roster[0].hp, (per - 7) * m.roster[0].men, "same share of health")
	assert_eq(m.roster[1].hp, Soldier.squad_hp_cap(m.roster[1]), "missing hp: full")
	for s in m.roster + m.recruits:
		assert_eq(s.men, DB.squad_size(s.typeId), "full squads")
		assert_true(s.hp > 0, "hp > 0")
		assert_true(s.hp <= Soldier.squad_hp_cap(s), "hp capped")
	# A current save passes through unchanged.
	var again := Game.migrate_save(JS.normalize(JSON.parse_string(Game.to_save_json(m))))
	assert_eq(again.roster, m.roster, "unchanged")


func test_the_royal_guard_answers_only_a_proper_barracks() -> void:
	var g := Game.new_game(31)
	var seen := 0
	for i in 40:
		Game.roll_recruits(g)
		seen += g.recruits.filter(func(r: Dictionary) -> bool: return r.typeId == "collie_guard").size()
	assert_eq(seen, 0, "none at the tent lines")
	g.buildings.barracks = 2
	for i in 40:
		Game.roll_recruits(g)
		seen += g.recruits.filter(func(r: Dictionary) -> bool: return r.typeId == "collie_guard").size()
	assert_true(seen > 10, "guards at the barracks: %d" % seen)
