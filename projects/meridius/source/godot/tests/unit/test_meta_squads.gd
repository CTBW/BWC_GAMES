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
	var b := Battle.new(Setup.build_battle(roll, Expedition.battle_army(g), {"survivalBonus": 0}))
	Autoplay.auto_battle(b)
	var before := {}
	for s in g.roster:
		before[s.id] = s.men
	var report := Expedition.apply_battle(g, b, "Test", false)
	for u in b.units.filter(func(x: Dictionary) -> bool: return x.faction == "player"):
		var s: Variant = null
		for r in g.roster:
			if r.id == u.get("soldierId"):
				s = r
		if u.status == "dead":
			assert_eq(s, null, "the dead leave the roster")
			continue
		assert_not_null(s, "survivor on the roster")
		# Field triage may carry some of the fallen back; nobody else returns.
		var saved := 0
		for l in report.losses:
			if l.name == s.name:
				saved = JS.get_or(l, "saved", 0)
		if u.status == "downed":
			assert_eq(s.men, 1 + saved, "downed: the sergeant and the saved")
		else:
			assert_eq(s.men, maxi(1, u.alive) + saved, "standing and saved")
		assert_true(s.hp <= Soldier.squad_hp_cap(s), "hp capped")
		assert_true(s.men <= before[s.id], "never more men")
	var lost := 0
	for l in report.losses:
		lost += l.lost
	assert_eq(lost, g.expedition.menLost, "menLost")


func test_field_triage_returns_only_soldiers_who_fell_in_this_battle() -> void:
	for seed in range(1, 25):
		var g := _on_expedition(seed)
		var roll := Setup.roll_encounter("orc_overseer", Rng.new(seed), 2)
		var b := Battle.new(Setup.build_battle(roll, Expedition.battle_army(g), {"survivalBonus": 0.1}))
		Autoplay.auto_battle(b)
		var report := Expedition.apply_battle(g, b, "Test", false)
		for l in report.losses:
			var u: Dictionary = b.units.filter(func(x: Dictionary) -> bool: return x.faction == "player" and x.name == l.name)[0]
			# Squads march out at full strength here, so the fallen are size minus the standing.
			var fell: int = u.size - 1 if u.status == "downed" else u.size - u.alive
			var saved: int = JS.get_or(l, "saved", 0)
			assert_true(saved >= 0, "saved >= 0")
			assert_eq(saved + l.lost, fell, "seed %d: saved + lost = fell" % seed)
			if l.fate == "dead":
				assert_eq(saved, 0, "the dead are not saved")


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
