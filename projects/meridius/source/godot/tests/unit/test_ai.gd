## The battle AI (scripts/rules/ai.gd): turns complete, attacks are taken,
## facings chosen, profiles read, results deterministic, and an enemy turn
## runs on a worker thread. Exact behaviour is proven by the parity traces.
extends "res://tests/unit/test_battle_base.gd"


func test_profiles() -> void:
	assert_eq(Ai.profile_of({"typeId": "goblin_rabble"}), DB.UNIT_TYPES.goblin_rabble.ai)
	assert_eq(Ai.profile_of({"typeId": "crossbowman"}).preferRange, 5)
	assert_eq(Ai.profile_of({"typeId": "militia"}), {"aggression": 0.5, "caution": 0.5})


func test_enemy_turns_complete_and_battles_end_without_deadlock() -> void:
	for key in ["laststand:0", "laststand:1", "scouts:0", "camp:0", "marching:2"]:
		var b = Battle.new(setup_fixture(key))
		b.begin(Ai.run_enemy_ai)
		var turns := 0
		while not b.is_over() and turns < 40:
			turns += 1
			Ai.run_player_auto(b)
			if b.is_over():
				break
			var turn_before: int = b.turn
			b.end_turn(Ai.run_enemy_ai)
			if not b.is_over():
				assert_eq([b.phase, b.turn], ["player", turn_before + 1], key)
		assert_true(b.is_over(), "%s ended (turn %d)" % [key, b.turn])
		assert_true(b.result in ["victory", "defeat", "retreat"])


func test_an_adjacent_enemy_attacks() -> void:
	var f := soldier("footman", 6, "f")
	f.x = 5; f.y = 5; f.facing = 3
	var g := enemy_f("goblin_spear", "g", 6, 5, 1)
	var b = new_battle([f, g], 1, open_field(46))
	b.phase = "player"
	b.end_turn(Ai.run_enemy_ai)
	var ev: Array = b.drain()
	assert_true(has_event(ev, func(e): return e.t == "attack" and e.uid == "g" and e.target == "f" and not e.has("reaction")), "the goblin strikes")


func test_the_company_automation_uses_stances_when_threatened() -> void:
	# Spearmen out of reach of the orc but inside its charge: they set their spears.
	var s := soldier("spearman", 5, "s")
	s.x = 5; s.y = 11; s.facing = 3
	var o := enemy_f("orc_warrior", "o", 5, 9, 3)
	o.x = 5; o.y = 4
	var b = new_battle([s, o], 3, open_field(46))
	b.phase = "player"
	Ai.run_player_auto(b)
	assert_true(Grid.dist(o, s) <= o.stats.move + 2, "ends inside the orc's reach (at %d,%d)" % [s.x, s.y])
	assert_true(s.hasActed)
	assert_eq(s.get("stance"), "spearwall")
	assert_true(has_event(b.drain(), func(e): return e.t == "stance" and e.stance == "spearwall"))


func test_choose_facing_never_shows_the_back_to_a_foe() -> void:
	var f := soldier("footman", 1, "f")
	f.x = 5; f.y = 9; f.facing = 3
	var g := enemy_f("goblin_spear", "g", 9, 5, 2)
	g.x = 5; g.y = 3
	var b = new_battle([f, g], 1, open_field(41))
	b.phase = "player"
	var facing: Variant = Ai.choose_facing(b, f, {"x": 5, "y": 7})
	assert_eq(facing, 3, "faces the goblin to the north")
	# The exposure of each facing on that tile: back to the foe is worst.
	var foes: Array = b.enemies_of(f)
	var at := {"x": 5, "y": 7}
	assert_true(Ai.exposure(at, 1, foes) > Ai.exposure(at, 0, foes))
	assert_true(Ai.exposure(at, 0, foes) > Ai.exposure(at, 3, foes))
	assert_eq(Ai.exposure(at, 3, foes), 0.0)


func test_ai_results_are_deterministic() -> void:
	var a = auto_battle(Battle.new(setup_fixture("marching:5")))
	var b = auto_battle(Battle.new(setup_fixture("marching:5")))
	assert_eq(a.result, b.result)
	assert_eq(a.turn, b.turn)
	assert_eq(a.rng.state, b.rng.state)
	assert_eq(a.units, b.units)


func test_an_enemy_turn_runs_on_a_worker_thread() -> void:
	var b = Battle.new(setup_fixture("laststand:2"))
	b.begin(Ai.run_enemy_ai)
	Ai.run_player_auto(b)
	var copy = Battle.new(setup_fixture("laststand:2"))
	copy.begin(Ai.run_enemy_ai)
	Ai.run_player_auto(copy)
	var thread := Thread.new()
	thread.start(func(): b.end_turn(Ai.run_enemy_ai))
	thread.wait_to_finish()
	copy.end_turn(Ai.run_enemy_ai)
	assert_eq(b.drain(), copy.drain(), "the same events on a worker as on the main thread")
	assert_eq(b.units, copy.units)
