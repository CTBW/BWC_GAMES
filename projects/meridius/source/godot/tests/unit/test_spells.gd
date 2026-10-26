## Spells, conditions and war machines: port of the rule tests in
## tests/spells.test.ts. Squads are built with the meta port (parity-tested
## against the original); battle parity for whole battles with mages, machines,
## shamans, rock lobbers and war wagons is in tests/parity (group "magic").
extends "res://tests/unit/test_battle_base.gd"

const Soldier = preload("res://scripts/meta/soldier.gd")
const Game = preload("res://scripts/meta/game.gd")
const Setup = preload("res://scripts/rules/setup.gd")
const Autoplay = preload("res://scripts/campaign/autoplay.gd")

var _ids := 0


func squad(type_id: String, x: int, y: int, facing := 3) -> Dictionary:
	var u: Dictionary
	if DB.UNIT_TYPES[type_id].faction == "player":
		var n := _ids
		u = Soldier.soldier_to_unit(Soldier.new_soldier(Rng.new(_ids + 7), type_id, 1, func() -> String: return "s%d" % n, 0))
	else:
		u = Soldier.make_enemy(type_id, 1, "e%d" % _ids, Rng.new(_ids + 1))
	_ids += 1
	u.x = x
	u.y = y
	u.facing = facing
	return u


func battle(units: Array, seed := 1, phase := "player") -> Variant:
	var b = new_battle(units, seed, open_field(7))
	b.phase = phase
	return b


static func spells_of(evs: Array) -> Array:
	return evs.filter(func(e): return e.t == "spell")


# ---------------------------------------------------------------- the new squads

func test_casters_and_engine_crews_come_three_to_a_squad() -> void:
	for id in ["battle_mage", "goblin_shaman", "ballista", "mangonel", "rock_lobber", "war_wagon"]:
		assert_eq(DB.squad_size(id), 3, id)
		var u := squad(id, 1, 1)
		assert_eq(u.size, 3, id)
		assert_eq(u.maxHp, u.hpPer * 3, id)
	assert_true(DB.is_engine("ballista") and DB.is_engine("war_wagon") and not DB.is_engine("battle_mage"), "engines")
	assert_true(DB.is_active_ability("chain_lightning") and DB.is_active_ability("shieldwall") and not DB.is_active_ability("charge"), "active abilities")


func test_engine_crews_are_named_as_a_crew() -> void:
	var u := squad("ballista", 1, 1)
	assert_true(Squad.squad_name(u).ends_with("'s ballista crew"), Squad.squad_name(u))
	assert_eq(Squad.member_noun("mangonel", 1), "crewman")
	assert_eq(Squad.member_noun("mangonel", 2), "crewmen")


func test_arcane_and_ballista_bolts_never_run_out() -> void:
	assert_eq(squad("battle_mage", 1, 1).ammo, -1)
	assert_eq(squad("ballista", 1, 1).ammo, -1)
	assert_true(squad("crossbowman", 1, 1).ammo > 0, "crossbows carry bolts")


func test_every_muster_offers_a_specialist() -> void:
	var g := Game.new_game(5)
	for i in 6:
		Game.roll_recruits(g)
		var found := false
		for r in g.recruits:
			if Game.SPECIALIST_TYPES.has(r.typeId):
				found = true
		assert_true(found, "muster %d" % i)


# ---------------------------------------------------------------- spells

func test_chain_lightning_scales_with_casters_and_arcs_to_the_nearest_foes() -> void:
	var m := squad("battle_mage", 5, 9)
	var a := squad("goblin_spear", 5, 4)
	var b2 := squad("goblin_spear", 6, 4)
	var c := squad("goblin_spear", 7, 4)
	var far := squad("goblin_spear", 1, 1)
	m.stats.ranged = 400
	var b = battle([m, a, b2, c, far])
	var pv: Dictionary = b.spell_preview(m, "chain_lightning", a)
	assert_true(pv.legal, str(pv.get("reason")))
	assert_eq(pv.hits.map(func(h): return h.role), ["main", "chain", "chain"])
	assert_false(pv.hits.any(func(h): return h.uid == far.uid), "no arc to a far squad")
	var power: Array = DB.ABILITIES.chain_lightning.power
	assert_eq(pv.hits[0].min, power[0] * 3)
	assert_eq(pv.hits[0].max, power[1] * 3)
	assert_true(pv.hits[1].max < pv.hits[0].max, "the arc is weaker")
	var hp_before := [a.hp, b2.hp, c.hp]
	assert_true(b.cast(m.uid, "chain_lightning", a), "cast")
	var sp := spells_of(b.drain())
	assert_eq(sp.size(), 1, "one spell event")
	assert_eq(sp[0].hits.size(), 3)
	for i in 3:
		var h: Dictionary = sp[0].hits[i]
		assert_between(h.damage, mini(pv.hits[i].min, hp_before[i]), pv.hits[i].max, "hit %d" % i)
	assert_eq(a.hp, hp_before[0] - sp[0].hits[0].damage)
	m.alive = 1
	m.hasActed = false
	m.cooldowns = {}
	assert_eq(b.spell_preview(m, "chain_lightning", b2).hits[0].max, power[1], "one mage: a third")


func test_a_spell_on_cooldown_cannot_be_cast() -> void:
	var m := squad("battle_mage", 5, 9)
	var g := squad("goblin_spear", 5, 5)
	m.stats.ranged = 400
	var b = battle([m, g])
	assert_true(b.cast(m.uid, "chain_lightning", g))
	m.hasActed = false
	m.done = false
	assert_false(b.can_cast(m, "chain_lightning").ok)
	assert_false(b.cast(m.uid, "chain_lightning", g))


func test_frost_blast_chills_foes_struck_not_friends_until_their_turn_ends() -> void:
	var m := squad("battle_mage", 5, 9)
	var f := squad("footman", 6, 5)
	var g := squad("goblin_spear", 5, 5)
	var h := squad("goblin_spear", 4, 5)
	m.stats.ranged = 400
	var b = battle([m, f, g, h])
	var pv: Dictionary = b.spell_preview(m, "frost_blast", g)
	var uids: Array = pv.hits.map(func(x): return x.uid)
	uids.sort()
	var want := [g.uid, h.uid]
	want.sort()
	assert_eq(uids, want)
	var move := Squad.move_of(g)
	assert_true(b.cast(m.uid, "frost_blast", g))
	assert_true(Squad.has_status(g, "chilled"), "struck squad chilled")
	assert_true(Squad.has_status(h, "chilled"), "squad beside chilled")
	assert_false(Squad.has_status(f, "chilled"), "friends spared")
	assert_eq(Squad.move_of(g), ceili(move / 2.0))
	assert_true(b.preview(f, g).mods.any(func(md): return md[0] == "Target chilled"), "easier to hit")
	assert_true(b.preview(g, f, {"from": {"x": 6, "y": 4}}).mods.any(func(md): return md[0] == "Chilled"), "hits worse")
	var during := [false]
	b.end_turn(func(bb): during[0] = Squad.has_status(bb.unit(g.uid), "chilled"))
	assert_true(during[0], "chilled through the enemy turn")
	assert_false(Squad.has_status(g, "chilled"), "gone after it")


func test_healing_closes_wounds_but_never_raises_the_dead() -> void:
	var m := squad("battle_mage", 5, 9)
	var f := squad("footman", 5, 7)
	var b = battle([m, f])
	f.alive = 4
	f.hp = f.hpPer * 3 + 2
	assert_true(b.cast(m.uid, "healing_light", f))
	assert_eq(f.alive, 4)
	assert_true(f.hp <= f.hpPer * 4, "capped at the survivors' shares")
	assert_true(f.hp > f.hpPer * 3 + 2, "healed")
	assert_eq(spells_of(b.drain())[0].hits[0].heal, f.hp - (f.hpPer * 3 + 2))


func test_mending_circle_heals_friends_within_two_tiles() -> void:
	var m := squad("battle_mage", 5, 9)
	m.abilities.append("mending_circle")
	var near := squad("footman", 5, 8)
	var away := squad("footman", 1, 1)
	var b = battle([m, near, away])
	for u in [m, near, away]:
		u.hp -= 10
	assert_true(b.cast(m.uid, "mending_circle", m))
	assert_true(near.hp > near.maxHp - 10)
	assert_true(m.hp > m.maxHp - 10)
	assert_eq(away.hp, away.maxHp - 10)


func test_a_fireball_burns_friend_and_foe_and_a_miss_lands_astray() -> void:
	var missed := 0
	for seed in range(1, 41):
		var s := squad("goblin_shaman", 5, 1)
		var f := squad("footman", 5, 6)
		var g := squad("goblin_spear", 5, 5)
		var b = battle([s, f, g], seed, "enemy")
		var pv: Dictionary = b.spell_preview(s, "fireball", f)
		var gh: Array = pv.hits.filter(func(x): return x.uid == g.uid)
		assert_true(gh.size() == 1 and gh[0].ally, "the goblins beside are caught")
		s.stats.ranged = -400
		assert_true(b.cast(s.uid, "fireball", f))
		var sp: Dictionary = spells_of(b.drain())[0]
		if sp.hit:
			continue
		missed += 1
		assert_eq(maxi(absi(sp.impact.x - f.x), absi(sp.impact.y - f.y)), 1, "a tile astray")
		for h in sp.hits:
			var u: Dictionary = b.unit(h.uid)
			assert_true(absi(u.x - sp.impact.x) + absi(u.y - sp.impact.y) <= 1, "struck where it lands")
	assert_true(missed > 30, "nearly always astray at 5%%: %d" % missed)


func test_bloodlust_frenzies_a_squad_until_the_end_of_its_next_turn() -> void:
	var s := squad("goblin_shaman", 5, 1)
	var g := squad("goblin_spear", 5, 5)
	var f := squad("footman", 5, 6, 3)
	var b = battle([s, g, f], 1, "enemy")
	var before: Dictionary = b.preview(g, f)
	assert_true(b.cast(s.uid, "bloodlust", g))
	var after: Dictionary = b.preview(g, f)
	assert_eq(after.chance, mini(95, before.chance + 10))
	assert_eq(after.min, before.min + 3 * g.alive)
	assert_true(b.preview(f, g).mods.any(func(md): return md[0] == "Target in a frenzy"))
	var m0: int = g.morale
	b.change_morale(g, -20, "test")
	assert_eq(g.morale, m0 - 10, "morale losses halved")
	b._end_of_turn("enemy")
	assert_true(Squad.has_status(g, "bloodlust"), "lasts through the next turn")
	b._end_of_turn("enemy")
	assert_false(Squad.has_status(g, "bloodlust"), "then gone")


func test_gutripper_bleeds_for_two_turns_and_kills_soldiers() -> void:
	var s := squad("goblin_shaman", 5, 1)
	var f := squad("footman", 5, 5)
	s.stats.ranged = 400
	var b = battle([s, f], 1, "enemy")
	assert_eq(b.spell_preview(s, "gutripper", f).hits[0].min, DB.ABILITIES.gutripper.power[0] * 3, "ignores armour")
	assert_true(b.cast(s.uid, "gutripper", f))
	assert_true(Squad.has_status(f, "bleeding"))
	b.drain()
	var hp: int = f.hp
	b._start_turn("player")
	var first := events_of(b.drain(), "dot")
	assert_eq(first.size(), 1)
	assert_true(first[0].damage > 0)
	assert_eq(f.hp, hp - first[0].damage)
	b._start_turn("player")
	assert_eq(events_of(b.drain(), "dot").size(), 1)
	assert_false(Squad.has_status(f, "bleeding"))
	b._start_turn("player")
	assert_eq(events_of(b.drain(), "dot").size(), 0)
	assert_eq(f.alive, ceili(float(f.hp) / f.hpPer))


# ---------------------------------------------------------------- war machines

func test_a_ballista_cannot_loose_in_a_turn_it_has_moved() -> void:
	var bl := squad("ballista", 5, 10)
	var g := squad("goblin_spear", 5, 4)
	var b = battle([bl, g])
	assert_true(b.preview(bl, g).legal)
	assert_false(b.preview(bl, g, {"movedTiles": 1}).legal)
	assert_true(b.move(bl.uid, 5, 9))
	assert_false(b.attack(bl.uid, g.uid))


func test_a_ballista_bolt_runs_through_into_the_foe_behind_never_friends() -> void:
	var bl := squad("ballista", 5, 10)
	var g := squad("goblin_spear", 5, 6)
	var h := squad("goblin_spear", 5, 5)
	bl.stats.ranged = 400
	var b = battle([bl, g, h])
	assert_true(b.attack(bl.uid, g.uid))
	var atk := events_of(b.drain(), "attack")
	assert_eq(atk.size(), 2)
	assert_eq(atk[1].target, h.uid)
	assert_eq(atk[1].via, g.uid)
	assert_eq(atk[1].damage, maxi(1, JS.rnd(atk[0].damage * 0.5)))
	var bl2 := squad("ballista", 5, 10)
	var g2 := squad("goblin_spear", 5, 6)
	var f2 := squad("footman", 5, 5)
	bl2.stats.ranged = 400
	var b2 = battle([bl2, g2, f2])
	assert_eq(b2.impale_target(bl2, g2), null, "a friendly squad stops the bolt")


func test_a_mangonel_lobs_over_obstacles_not_too_close_not_after_moving() -> void:
	var mg := squad("mangonel", 5, 10)
	var g := squad("goblin_spear", 5, 4)
	var close := squad("goblin_spear", 5, 8)
	var b = battle([mg, g, close])
	for x in b.map.w:
		b.map.tiles[7 * b.map.w + x].prop = "rock_large"
	assert_true(b.spell_preview(mg, "hurl_stone", g).legal, "over the rocks")
	assert_false(b.spell_preview(mg, "hurl_stone", close).legal, "too close")
	assert_false(b.spell_preview(mg, "hurl_stone", g, {"movedTiles": 1}).legal, "not after moving")


func test_a_war_wagon_smashes_a_squad_out_of_the_line() -> void:
	var w := squad("war_wagon", 5, 4, 1)
	var f := squad("footman", 5, 5, 3)
	w.stats.melee = 400
	var b = battle([w, f], 1, "enemy")
	assert_true(b.attack(w.uid, f.uid))
	if f.status == "active":
		assert_eq(f.y, 6, "pushed back")
		assert_eq(w.y, 5, "rolls into the gap")


# ---------------------------------------------------------------- the AI

func test_shamans_and_rock_lobbers_cast_in_the_enemy_turn() -> void:
	var s := squad("goblin_shaman", 5, 2, 1)
	var r := squad("rock_lobber", 7, 1, 1)
	var g := squad("goblin_spear", 5, 4, 1)
	var f := squad("footman", 5, 7, 3)
	var c := squad("crossbowman", 6, 9, 3)
	var b = battle([s, r, g, f, c], 4, "enemy")
	Ai.run_enemy_ai(b)
	var casts := spells_of(b.drain())
	assert_true(casts.size() >= 1, "at least one cast")
	for e in casts:
		assert_eq(DB.ABILITIES[e.ability].kind, "spell")


func test_player_mages_cast_when_the_company_is_automated() -> void:
	var m := squad("battle_mage", 5, 9)
	var f := squad("footman", 5, 7)
	var g := squad("goblin_spear", 5, 4, 1)
	var h := squad("goblin_spear", 6, 4, 1)
	var b = battle([m, f, g, h], 2)
	Ai.act_unit(b, m, {"useStances": true})
	assert_eq(spells_of(b.drain()).size(), 1)


func test_whole_battles_with_the_new_squads_end() -> void:
	for pair in [["shaman_fire", 3], ["siege_train", 5]]:
		var roll := Setup.roll_encounter(pair[0], Rng.new(pair[1]), 2)
		var army: Array = []
		var i := 0
		for t in ["footman", "spearman", "battle_mage", "ballista", "mangonel", "crossbowman"]:
			var tag := "a%d-%d" % [pair[1], i]
			army.append(Soldier.soldier_to_unit(Soldier.new_soldier(Rng.new(pair[1] + i), t, 1, func() -> String: return tag, 0)))
			i += 1
		var b = Battle.new(Setup.build_battle(roll, army, {}))
		Autoplay.auto_battle(b)
		assert_true(b.is_over(), "%s ends" % pair[0])
		assert_not_null(b.result, "%s has a result" % pair[0])
