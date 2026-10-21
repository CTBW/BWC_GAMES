## Facing comes only from movement: a squad faces the way it took its last step.
## Port of tests/facing.test.ts.
extends "res://tests/unit/test_battle_base.gd"


## facing.test.ts battle(units, seed, phase): openField(seed + 40).
func _battle(units: Array, seed := 1, phase := "player") -> Variant:
	var b = new_battle(units, seed, open_field(seed + 40))
	b.phase = phase
	return b


# ------------------------------------------------------------------ facing from movement

func test_a_squad_ends_facing_the_direction_of_its_last_step() -> void:
	var f := soldier("footman", 1, "f")
	f.x = 5; f.y = 9; f.facing = 3
	var far := enemy_f("goblin_archer", "g", 12, 1, 1)
	var b = _battle([f, far])
	# Default path to (7, 9): two steps along +x.
	assert_true(b.move("f", 7, 9, 0))
	assert_eq(f.facing, 0)
	var path: Array = []
	for e in events_of(b.drain(), "move"):
		path.append_array(e.path)
	assert_eq(Grid.dir_to(path[path.size() - 2], path[path.size() - 1]), 0)


func test_every_reachable_facing_has_a_path_whose_last_step_points_that_way() -> void:
	var f := soldier("footman", 2, "f")
	f.x = 6; f.y = 6; f.facing = 3
	var b = _battle([f, enemy_f("goblin_archer", "g", 13, 0, 1)])
	var opts: Array = b.facing_options(f, 6, 4)
	var facings: Array = opts.map(func(o): return o.facing)
	facings.sort()
	assert_eq(facings, [0, 1, 2, 3])
	for o in opts:
		var p: Array = o.path
		assert_eq(p[0], {"x": 6, "y": 6})
		assert_eq(p[p.size() - 1], {"x": 6, "y": 4})
		assert_eq(Grid.dir_to(p[p.size() - 2], p[p.size() - 1]), o.facing)
		assert_true(o.cost <= f.stats.move)
	# Arriving straight ahead is cheapest; arriving from the far side costs a detour.
	var straight: Dictionary = opts.filter(func(o): return o.facing == 3)[0]
	var back: Dictionary = opts.filter(func(o): return o.facing == 1)[0]
	assert_eq(straight.cost, 2)
	assert_eq(back.cost, 4)


func test_a_long_march_leaves_no_choice() -> void:
	var f := soldier("footman", 3, "f")
	f.x = 6; f.y = 10; f.facing = 3
	var b = _battle([f, enemy_f("goblin_archer", "g", 13, 0, 1)])
	assert_eq(b.facing_options(f, 6, 6).map(func(o): return o.facing), [3])


func test_turning_on_the_spot_means_stepping_out_and_back() -> void:
	var f := soldier("footman", 4, "f")
	f.x = 6; f.y = 6; f.facing = 3
	var b = _battle([f, enemy_f("goblin_archer", "g", 13, 0, 1)])
	var home: Array = b.facing_options(f, 6, 6)
	var stay: Dictionary = home.filter(func(o): return o.facing == 3)[0]
	assert_eq(stay.path.size(), 1)
	var about: Dictionary = home.filter(func(o): return o.facing == 1)[0]
	assert_eq(about.cost, 2)
	assert_true(b.move("f", 6, 6, 1))
	assert_eq([f.x, f.y, f.facing, f.hasMoved], [6, 6, 1, true])
	# Moving onto the start tile with the facing it already has is no move at all.
	var g := soldier("spearman", 5, "s")
	g.x = 9; g.y = 9; g.facing = 3
	var b2 = _battle([g, enemy_f("goblin_archer", "e", 13, 0, 1)])
	assert_false(b2.move("s", 9, 9, 3))
	assert_false(b2.move("s", 9, 9))


func test_attacking_does_not_turn_the_attacker_or_the_target() -> void:
	var f := soldier("footman", 6, "f")
	f.x = 5; f.y = 5; f.facing = 3 # facing -y
	var g := enemy_f("goblin_spear", "g", 6, 5, 1) # on f's +x flank
	var b = _battle([f, g])
	assert_true(b.attack("f", "g"))
	assert_eq(f.facing, 3)
	assert_eq(g.facing, 1)
	assert_false(has_event(b.drain(), func(e): return e.t == "face"))


func test_flank_and_rear_follow_the_targets_last_step() -> void:
	var f := soldier("footman", 7, "f")
	f.x = 5; f.y = 9; f.facing = 3
	var g := enemy_f("goblin_spear", "g", 9, 5, 2)
	var b = _battle([f, g])
	# March straight up: the squad faces -y, so the goblin at +x is on its flank.
	assert_true(b.move("f", 5, 6, 3))
	assert_eq(b.arc_of(f, {"x": 6, "y": 6}), "flank")
	assert_eq(b.arc_of(f, {"x": 5, "y": 7}), "rear")
	assert_eq(b.arc_of(f, {"x": 5, "y": 5}), "front")
	var rear: Dictionary = b.preview(g, f, {"from": {"x": 5, "y": 7}})
	var front: Dictionary = b.preview(g, f, {"from": {"x": 5, "y": 5}})
	assert_eq(rear.arc, "rear")
	assert_true(rear.chance > front.chance)


# ------------------------------------------------------------------ systems that read facing

func test_slipping_away_behind_an_enemys_back_provokes_no_free_attack() -> void:
	# The goblin faces -y; the footman stands right behind it at +y.
	var f := soldier("footman", 8, "f")
	f.x = 5; f.y = 6; f.facing = 3
	var g := enemy_f("goblin_spear", "g", 5, 5, 3)
	var b = _battle([f, g], 8)
	assert_false(b.zoc_tiles(f).has(6 * 1000 + 5))
	assert_true(b.move("f", 5, 8))
	assert_false(has_event(b.drain(), func(e): return e.t == "attack"))
	# Now the goblin faces the footman: stepping away invites a blow.
	var f2 := soldier("footman", 9, "f2")
	f2.x = 5; f2.y = 6; f2.facing = 3
	var g2 := enemy_f("goblin_spear", "g2", 5, 5, 1)
	var b2 = _battle([f2, g2], 9)
	assert_true(b2.move("f2", 5, 8))
	assert_true(has_event(b2.drain(), func(e): return e.t == "attack" and e.get("reaction") == "zoc"))


func test_a_spearwall_strikes_front_and_flanks_never_behind_and_does_not_turn() -> void:
	var s := soldier("spearman", 10, "s")
	s.stats.melee = 200
	s.x = 5; s.y = 5; s.facing = 3
	s["stance"] = "spearwall"
	# An orc walks up behind the spearmen.
	var o := enemy_f("orc_warrior", "o", 5, 9, 3)
	var b = _battle([s, o], 10, "enemy")
	assert_true(b.move("o", 5, 6))
	assert_false(has_event(b.drain(), func(e): return e.t == "attack"))
	assert_eq(s.facing, 3)
	# Another walks into the front.
	var s2 := soldier("spearman", 11, "s2")
	s2.stats.melee = 200
	s2.x = 5; s2.y = 7; s2.facing = 3
	s2["stance"] = "spearwall"
	var o2 := enemy_f("orc_warrior", "o2", 5, 3, 1)
	var b2 = _battle([s2, o2], 11, "enemy")
	b2.move("o2", 5, 6)
	assert_true(has_event(b2.drain(), func(e): return e.t == "attack" and e.get("reaction") == "spearwall"))
	assert_eq(s2.facing, 3)


func test_overwatch_watches_the_front_and_flanks_only() -> void:
	var c := soldier("crossbowman", 12, "c")
	c.stats.ranged = 200
	c.x = 6; c.y = 8; c.facing = 3
	c["stance"] = "overwatch"
	# A goblin moves about behind the crossbowmen, in range.
	var g := enemy_f("goblin_spear", "g", 2, 12, 0)
	var b = _battle([c, g], 12, "enemy")
	b.move("g", 6, 11)
	assert_false(has_event(b.drain(), func(e): return e.t == "attack"))
	# In front, the bolts fly.
	var c2 := soldier("crossbowman", 13, "c2")
	c2.stats.ranged = 200
	c2.x = 6; c2.y = 9; c2.facing = 3
	c2["stance"] = "overwatch"
	var g2 := enemy_f("goblin_spear", "g2", 6, 1, 1)
	var b2 = _battle([c2, g2], 13, "enemy")
	b2.move("g2", 6, 5)
	assert_true(has_event(b2.drain(), func(e): return e.t == "attack" and e.get("reaction") == "overwatch"))
	assert_eq(c2.facing, 3)


func test_first_strike_needs_the_attacker_in_the_spearmens_front() -> void:
	var s := soldier("spearman", 14, "s")
	s.x = 5; s.y = 5; s.facing = 3
	var g := enemy_f("goblin_spear", "g", 5, 8, 3)
	var b = _battle([s, g], 14, "enemy")
	# From behind: no first strike.
	b.move("g", 5, 6)
	b.attack("g", "s")
	assert_false(has_event(b.drain(), func(e): return e.t == "attack" and e.get("reaction") == "firstStrike"))


# ------------------------------------------------------------------ the enemy turns only by marching

func test_after_an_enemy_turn_every_squad_faces_its_last_step() -> void:
	for seed in range(1, 13):
		var b = Battle.new(setup_fixture("marching:%d" % seed))
		b.begin(Ai.run_enemy_ai)
		var turn := 0
		while turn < 4 and not b.is_over():
			turn += 1
			b.drain()
			var before := {}
			for u in b.units:
				before[u.uid] = u.facing
			b.end_turn(Ai.run_enemy_ai)
			var ev: Array = b.drain()
			assert_false(has_event(ev, func(e): return e.t == "face"), "seed %d: no turning on the spot" % seed)
			var last_step := {}
			for e in ev:
				if e.t == "move" and e.path.size() > 1:
					last_step[e.uid] = Grid.dir_to(e.path[e.path.size() - 2], e.path[e.path.size() - 1])
			for u in b.units:
				if u.status == "dead" or u.status == "fled":
					continue
				if last_step.has(u.uid):
					assert_eq(u.facing, last_step[u.uid], "seed %d %s faces its last step" % [seed, u.uid])
				elif not has_event(ev, func(e): return e.t == "push" and e.uid == u.uid):
					assert_eq(u.facing, before[u.uid], "seed %d %s kept its facing" % [seed, u.uid])
