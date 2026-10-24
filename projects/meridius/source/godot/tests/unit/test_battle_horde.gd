## The horde: waves, the war horn, held ground, relief, the warchief, and the
## enemies that break lines and slip round them. Port of tests/horde.test.ts
## (its last-stand-grounds test checks mapgen and belongs to that port).
extends "res://tests/unit/test_battle_base.gd"


## A battle with waves held as reserves beyond their edge, as buildBattle makes them.
## `waves`: [{turn, edge, types, label, horn?}].
func _with_waves(units: Array, waves: Array, objective: Dictionary, seed := 3) -> Variant:
	var map := open_field(seed)
	var n: Array = []
	for t in map.tiles:
		if t.y == 0:
			n.append({"x": t.x, "y": 0})
	map["entries"] = {"n": n}
	var reserve: Array = []
	var setup_waves: Array = []
	for wi in waves.size():
		var w: Dictionary = waves[wi]
		var uids: Array = []
		for i in w.types.size():
			var t: String = w.types[i]
			var u := enemy_h(t, "w%d-%d" % [wi, i], 5 + i, -3)
			u.status = "reserve"
			if t == "orc_warlord":
				u.tags.append("warchief")
			reserve.append(u)
			uids.append(u.uid)
		var sw := w.duplicate(true)
		sw.erase("types")
		sw["units"] = []
		sw["uids"] = uids
		setup_waves.append(sw)
	var all := units.duplicate()
	all.append_array(reserve)
	var b = Battle.new({"seed": seed, "map": map, "units": all, "survivalBonus": 0, "title": "t", "objective": objective, "waves": setup_waves})
	b.phase = "player"
	return b


func _rout(title := "Rout") -> Dictionary:
	return {"kind": "rout", "title": title, "brief": ""}


# ------------------------------------------------------------------ waves

func test_a_wave_marches_in_from_its_edge_on_its_turn_facing_onto_the_field() -> void:
	var f := soldier("footman", 1, "f")
	f.x = 6; f.y = 10
	var g := enemy_h("goblin_spear", "g", 2, 2)
	var b = _with_waves([f, g], [{"turn": 2, "edge": "n", "types": ["goblin_rabble", "goblin_spear"], "label": "Second wave"}], _rout())
	b.end_turn(no_ai)
	assert_eq(b.units.filter(func(u): return u.status == "reserve").size(), 2)
	b.end_turn(no_ai)
	var arrived: Array = b.units.filter(func(u): return String(u.uid).begins_with("w0"))
	assert_true(arrived.all(func(u): return u.status == "active" and u.y == 0 and u.facing == 1), "arrived on the north edge facing south")
	var ev: Array = b.drain()
	assert_true(has_event(ev, func(e): return e.t == "wave"))
	assert_eq(events_of(ev, "spawn").size(), 2)
	assert_true(has_event(ev, func(e): return e.t == "warn"))
	assert_eq(b.wave_state[0], "arrived")


func test_a_rout_battle_is_not_won_while_waves_are_still_to_come() -> void:
	var f := soldier("footman", 2, "f")
	f.x = 6; f.y = 10
	var g := enemy_h("goblin_rabble", "g", 6, 9)
	g.hp = 1
	g.alive = 1
	var b = _with_waves([f, g], [{"turn": 9, "edge": "n", "types": ["goblin_spear"], "label": "Late"}], _rout())
	f.stats.melee = 200
	b.attack("f", "g")
	assert_true(g.status == "dead" or g.status == "downed")
	assert_false(b.is_over())
	# With the field empty they come at once.
	b.end_turn(no_ai)
	assert_eq(b.unit("w0-0").status, "active")


# ------------------------------------------------------------------ the war horn

func _horn(kill_herald: bool) -> Variant:
	var f := soldier("footman", 3, "f")
	f.x = 6; f.y = 10
	var h := enemy_h("goblin_horn", "h", 8, 2)
	var g := enemy_h("goblin_spear", "g", 3, 2)
	var b = _with_waves([f, h, g], [{"turn": 3, "edge": "n", "horn": true, "types": ["goblin_rabble", "goblin_rabble"], "label": "Answer"}],
		{"kind": "rout", "hornTurn": 2, "title": "Horn", "brief": ""})
	if kill_herald:
		h.hp = 1
		h.alive = 1
		f.x = 8; f.y = 3
		f.stats.melee = 200
		b.attack("f", "h")
	b.end_turn(no_ai)
	b.end_turn(no_ai)
	b.end_turn(no_ai)
	return b


func test_the_horn_sounds_if_the_bearer_lives_and_its_band_arrives_the_turn_after() -> void:
	var b = _horn(false)
	assert_eq(b.horn, "sounded")
	assert_eq(b.unit("w0-0").status, "active")


func test_the_horn_falls_silent_if_the_bearer_is_killed_first() -> void:
	var b = _horn(true)
	assert_eq(b.horn, "silent")
	assert_eq(b.wave_state[0], "cancelled")
	assert_eq(b.unit("w0-0").status, "reserve")


# ------------------------------------------------------------------ holding ground

func _hold_battle() -> Variant:
	var f := soldier("footman", 4, "f")
	f.x = 1; f.y = 11
	var map := open_field(5)
	map["zone"] = [{"x": 6, "y": 6}, {"x": 7, "y": 6}, {"x": 6, "y": 7}, {"x": 7, "y": 7}]
	map["zoneName"] = "The yard"
	var a := enemy_h("goblin_spear", "a", 6, 6)
	var c := enemy_h("goblin_spear", "c", 7, 7)
	var b = Battle.new({"seed": 5, "map": map, "units": [f, a, c], "survivalBonus": 0, "title": "t",
		"objective": {"kind": "hold", "turns": 9, "title": "Hold", "brief": ""}})
	b.phase = "player"
	return b


func test_two_enemy_turns_ending_with_the_ground_taken_lose_the_battle() -> void:
	var b = _hold_battle()
	b.end_turn(no_ai)
	assert_false(b.is_over())
	assert_eq(b.overrun, 1)
	assert_true(has_event(b.drain(), func(e): return e.t == "overrun"))
	b.end_turn(no_ai)
	assert_eq(b.result, "defeat")


func test_retaking_the_ground_resets_the_count() -> void:
	var b = _hold_battle()
	b.end_turn(no_ai)
	assert_eq(b.overrun, 1)
	# Two defenders step in: the attackers no longer outnumber them by two.
	var f2 := soldier("spearman", 6, "f2")
	f2.x = 7; f2.y = 6
	var f3 := soldier("spearman", 7, "f3")
	f3.x = 6; f3.y = 7
	b.units.append(f2)
	b.units.append(f3)
	b.end_turn(no_ai)
	assert_eq(b.overrun, 0)
	assert_false(b.is_over())


func test_the_relief_comes_when_the_last_turn_ends() -> void:
	var f := soldier("footman", 8, "f")
	f.x = 6; f.y = 10
	var g := enemy_h("goblin_spear", "g", 2, 2)
	var b = _with_waves([f, g], [{"turn": 9, "edge": "n", "types": ["goblin_rabble"], "label": "Too late"}],
		{"kind": "survive", "turns": 2, "title": "Survive", "brief": "", "relief": "Riders"})
	b.end_turn(no_ai)
	assert_false(b.is_over())
	b.end_turn(no_ai)
	assert_eq(b.result, "victory")
	var ev: Array = b.drain()
	assert_true(has_event(ev, func(e): return e.t == "relief" and e.text == "Riders"))
	assert_eq(b.wave_state[0], "cancelled")
	assert_eq(g.status, "fled")


# ------------------------------------------------------------------ the warchief

func test_the_warchiefs_fall_breaks_the_horde() -> void:
	var f := soldier("footman", 9, "f")
	f.stats.melee = 200
	f.x = 6; f.y = 6
	var chief := enemy_h("orc_warlord", "chief", 6, 5)
	chief.tags.append("warchief")
	chief.hp = 1
	chief.alive = 1
	var g := enemy_h("goblin_spear", "g", 2, 2)
	var b = _with_waves([f, chief, g], [{"turn": 5, "edge": "n", "types": ["goblin_rabble"], "label": "More"}],
		{"kind": "hold", "turns": 9, "warchief": true, "title": "Hold", "brief": ""})
	b.attack("f", "chief")
	assert_true(has_event(b.drain(), func(e): return e.t == "broken"))
	assert_eq(b.result, "victory")
	assert_eq(b.wave_state[0], "cancelled")


# ------------------------------------------------------------------ breaking and slipping round lines

func test_a_brute_that_hits_smashes_the_squad_back_and_steps_into_the_gap() -> void:
	var f := soldier("footman", 10, "f")
	f.x = 6; f.y = 6; f.facing = 3
	var br := enemy_h("orc_brute", "br", 6, 5, 1)
	br.stats.melee = 300
	var b = new_battle([f, br], 10, open_field(10))
	b.phase = "enemy"
	b.attack("br", "f")
	assert_eq([f.x, f.y], [6, 7])
	assert_eq([br.x, br.y], [6, 6])


func test_a_blocked_push_slams_the_squad_into_the_obstacle() -> void:
	var f := soldier("footman", 10, "f")
	f.x = 6; f.y = 6; f.facing = 3
	var br := enemy_h("orc_brute", "br", 6, 5, 1)
	br.stats.melee = 300
	var map := open_field(10)
	map.tiles[7 * map.w + 6]["prop"] = "rock_large"
	var b = new_battle([f, br], 10, map)
	b.phase = "enemy"
	var alive_before: int = f.alive
	b.attack("br", "f")
	var ev: Array = b.drain()
	var push: Array = events_of(ev, "push")
	assert_eq(push.size(), 1)
	assert_true(push[0].blocked)
	assert_eq([f.x, f.y, br.x, br.y], [6, 6, 6, 5])
	var hit: Dictionary = events_of(ev, "attack")[0]
	# Three damage per soldier left standing after the blow.
	assert_eq(f.hp, maxi(0, hit.targetHp - mini(hit.targetHp, 3 * hit.aliveAfter)))
	assert_true(f.alive <= alive_before)


func test_wolf_riders_slip_away_without_free_attacks() -> void:
	var f := soldier("footman", 11, "f")
	f.x = 6; f.y = 6; f.facing = 3
	var w := enemy_h("wolf_rider", "w", 6, 5, 1)
	var b = new_battle([f, w], 11, open_field(11))
	b.phase = "enemy"
	assert_true(b.move("w", 3, 3))
	assert_false(has_event(b.drain(), func(e): return e.t == "attack"))


# ------------------------------------------------------------------ long skirmishes end

func test_a_band_that_cannot_break_the_company_gives_up() -> void:
	var f := soldier("footman", 12, "f")
	f.x = 1; f.y = 11
	var g := enemy_h("goblin_archer", "g", 12, 0)
	var b = new_battle([f, g], 12, open_field(12))
	b.phase = "player"
	var t := 0
	while t < Battle.GIVE_UP_TURN + 1 and not b.is_over():
		b.end_turn(no_ai)
		t += 1
	assert_eq(b.result, "victory")
	assert_eq(b.turn, Battle.GIVE_UP_TURN)


func test_a_whole_last_stand_plays_to_an_end_with_the_ai_on_both_sides() -> void:
	for i in 4:
		var b = Battle.new(setup_fixture("laststand:%d" % i))
		b.begin(Ai.run_enemy_ai)
		while not b.is_over() and b.turn <= 12:
			Ai.run_player_auto(b)
			if b.is_over():
				break
			b.end_turn(Ai.run_enemy_ai)
		assert_true(b.is_over(), "last stand %d ended" % i)
		assert_true(b.turn <= 8, "last stand %d ended by turn 8 (turn %d)" % [i, b.turn])
