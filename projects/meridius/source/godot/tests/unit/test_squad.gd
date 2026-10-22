## Squads: size, the shared HP pool, soldiers falling at thresholds, damage
## scaling with the soldiers still standing. Port of the rule tests in
## tests/squad.test.ts (formation and squad-view tests belong to the battle view;
## "a squad starts with the soldiers its HP can carry" tests soldierToUnit, meta).
extends "res://tests/unit/test_battle_base.gd"


func test_squads_have_six_soldiers_unless_the_type_says_otherwise() -> void:
	var special := {
		"troll": 3, "wolf_rider": 4, "goblin_horn": 4, "goblin_rabble": 9,
		"battle_mage": 3, "goblin_shaman": 3, "ballista": 3, "mangonel": 3, "rock_lobber": 3, "war_wagon": 3,
	}
	for id in DB.UNIT_TYPES:
		assert_eq(DB.squad_size(id), special.get(id, DB.DEFAULT_SQUAD_SIZE), id)
	assert_eq(DB.DEFAULT_SQUAD_SIZE, 6)


func test_squad_hp_is_soldiers_times_hp_per_soldier() -> void:
	var f := footmen()
	assert_eq(f.size, 6)
	assert_eq(f.alive, 6)
	assert_eq(f.maxHp, f.hpPer * 6)
	assert_eq(f.hp, f.maxHp)
	var t := make_enemy("troll", 1, "t", 1)
	assert_eq(t.size, 3)
	assert_eq(t.alive, 3)
	assert_eq(t.maxHp, DB.UNIT_TYPES.troll.base.hp * 3)


func test_soldiers_fall_at_each_threshold() -> void:
	var table := [[60, 6], [51, 6], [50, 5], [41, 5], [40, 4], [31, 4], [30, 3], [21, 3], [20, 2], [11, 2], [10, 1], [1, 1], [0, 0]]
	for row in table:
		assert_eq(Squad.alive_for(row[0], 10, 6), row[1], "hp %d" % row[0])
	# Fractional pools (worn squads) and the cap: the dead stay dead.
	assert_eq(Squad.alive_for(10.5, 10, 6), 2)
	assert_eq(Squad.alive_for(60, 10, 4), 4)
	assert_eq(Squad.alive_for(-5, 10, 6), 0)


func test_one_heavy_blow_can_kill_several_soldiers() -> void:
	var s := {"hp": 60, "hpPer": 10, "alive": 6}
	assert_eq(Squad.kills_from(s, 35), 3)
	assert_eq(Squad.damage_squad(s, 35), 3)
	assert_eq(s, {"hp": 25, "hpPer": 10, "alive": 3})
	assert_eq(Squad.damage_squad(s, 100), 3)
	assert_eq(s.alive, 0)
	assert_eq(s.hp, 0)


func test_healing_restores_the_survivors_but_never_raises_the_dead() -> void:
	var s := {"hp": 25, "hpPer": 10, "alive": 3}
	assert_eq(Squad.heal_squad(s, 100), 5)
	assert_eq(s, {"hp": 30, "hpPer": 10, "alive": 3})
	# Negative healing does nothing; a wiped-out squad cannot be healed.
	assert_eq(Squad.heal_squad(s, -7), 0)
	var gone := {"hp": 0, "hpPer": 10, "alive": 0}
	assert_eq(Squad.heal_squad(gone, 50), 0)
	assert_eq(gone.alive, 0)


func test_member_nouns_and_squad_names() -> void:
	assert_eq(Squad.member_noun("troll", 1), "moss troll")
	assert_eq(Squad.member_noun("troll", 2), "moss trolls")
	assert_eq(Squad.member_noun("nobody", 1), "soldier")
	assert_eq(Squad.member_noun("nobody", 3), "soldiers")
	assert_eq(Squad.squad_name({"name": "Aldric Vane", "typeId": "footman"}), "Aldric's footmen")
	assert_eq(Squad.squad_name({"name": "Grukk, goblin spearman", "typeId": "goblin_spear"}), "Grukk's goblin spearmen")
	assert_eq(Squad.squad_name({"name": "Warlord Uzgash, the Red", "typeId": "orc_warlord", "leader": true}), "Warlord Uzgash")


func test_damage_scales_with_surviving_soldiers() -> void:
	var map := open_field(3)
	var a := footmen(1)
	var g := make_enemy("goblin_spear", 1, "g", 2)
	a.x = 5; a.y = 5; a.facing = 3
	g.x = 5; g.y = 4; g.facing = 1
	var b = new_battle([a, g], 1, map)
	var per := func(d: int) -> int: return maxi(1, JS.rnd(d - g.stats.armor))
	var full: Dictionary = b.preview(a, g)
	assert_eq(full.strikers, 6)
	assert_eq(full.min, per.call(a.melee[0]) * 6)
	assert_eq(full.max, per.call(a.melee[1]) * 6)
	for alive in [5, 4, 3, 2, 1]:
		a.alive = alive
		a.hp = alive * a.hpPer
		var pv: Dictionary = b.preview(a, g)
		assert_eq(pv.strikers, alive)
		assert_eq(pv.min, per.call(a.melee[0]) * alive)
		assert_eq(pv.max, per.call(a.melee[1]) * alive)


func test_armour_is_taken_off_every_soldiers_blow() -> void:
	var map := open_field(5)
	var a := make_enemy("goblin_spear", 1, "a", 1)
	var f := footmen(2)
	a.x = 5; a.y = 5; f.x = 5; f.y = 4; f.facing = 1
	var b = new_battle([a, f], 1, map)
	var pv: Dictionary = b.preview(a, f, {"from": {"x": 5, "y": 5}})
	assert_eq(pv.min, maxi(1, JS.rnd(a.melee[0] - f.stats.armor * (1 - a.meleePierce))) * 6)


func test_damage_is_rolled_and_applied_once_however_many_swing() -> void:
	var map := open_field(7)
	for seed in range(1, 40):
		var a := footmen(seed)
		var g := make_enemy("goblin_spear", 1, "g", seed)
		a.x = 5; a.y = 5; a.facing = 3
		g.x = 5; g.y = 4; g.facing = 1
		a.stats.melee = 300 # always hit
		var b = new_battle([a, g], seed, map.duplicate(true))
		b.phase = "player"
		var hp_before: int = g.hp
		assert_true(b.attack(a.uid, g.uid), "attack %d" % seed)
		var attacks: Array = b.drain().filter(func(e): return e.t == "attack" and e.uid == a.uid)
		assert_eq(attacks.size(), 1)
		var e: Dictionary = attacks[0]
		assert_eq(e.strikers, 6)
		assert_eq(hp_before - g.hp, e.damage)
		assert_eq(e.aliveBefore, 6)
		assert_eq(e.aliveAfter, g.alive)
		assert_eq(g.alive, Squad.alive_for(g.hp, g.hpPer, 6))
		assert_eq(a.damageDealt, e.damage)


func test_enemy_squads_and_trolls_follow_the_same_rule() -> void:
	var map := open_field(9)
	var t := make_enemy("troll", 1, "t", 3)
	var f := footmen(3)
	t.x = 5; t.y = 5; f.x = 5; f.y = 4; f.facing = 1
	var b = new_battle([t, f], 1, map)
	var full: Dictionary = b.preview(t, f, {"from": {"x": 5, "y": 5}})
	assert_eq(full.strikers, 3)
	t.alive = 1
	t.hp = t.hpPer
	var one: Dictionary = b.preview(t, f, {"from": {"x": 5, "y": 5}})
	assert_eq(one.min * 3, full.min)
	assert_eq(one.max * 3, full.max)


func test_troll_regeneration_closes_wounds_but_a_fallen_troll_stays_down() -> void:
	var map := open_field(11)
	var t := make_enemy("troll", 1, "t", 3)
	var f := footmen(4)
	t.x = 2; t.y = 2; f.x = 9; f.y = 9
	var b = new_battle([t, f], 1, map)
	t.hp = t.hpPer + 5 # two trolls standing, the second badly hurt
	t.alive = 2
	b.phase = "player"
	b.end_turn(no_ai)
	assert_eq(t.alive, 2)
	assert_true(t.hp <= 2 * t.hpPer, "healed at most to the survivors' shares")
	assert_true(t.hp > t.hpPer + 5, "wounds closed")
	assert_true(has_event(b.drain(), func(e): return e.t == "heal"))


func test_a_heavy_hit_kills_several_soldiers_and_reports_it() -> void:
	# Soldier deaths at HP thresholds inside a real attack: one blow, several fall.
	var map := open_field(7)
	var a := footmen(5)
	var r := enemy_h("goblin_rabble", "g", 6, 4, 1)
	a.x = 5; a.y = 5; a.facing = 3
	r.x = 5; r.y = 4
	a.stats.melee = 300 # always hit
	var b = new_battle([a, r], 3, map)
	b.phase = "player"
	assert_eq(r.alive, 9)
	assert_true(b.attack(a.uid, r.uid))
	var e: Dictionary = b.drain().filter(func(x): return x.t == "attack")[0]
	assert_true(e.hit)
	assert_eq(e.aliveBefore, 9)
	assert_eq(e.aliveAfter, r.alive)
	assert_eq(r.alive, Squad.alive_for(r.hp, r.hpPer, 9))
	# Six footmen strike 7-10 each against 9 HP goblins: four to six fall at once.
	assert_between(e.aliveBefore - e.aliveAfter, 4, 6, "soldiers killed by one blow of %d" % e.damage)
