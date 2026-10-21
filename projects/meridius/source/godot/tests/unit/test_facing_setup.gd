## The case of tests/facing.test.ts that needs battle setup: the enemy turns
## only by marching. (The pure-rules facing cases are ported by the rules tests.)
extends "res://tests/test_case.gd"

const Rng = preload("res://scripts/core/rng.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const Ai = preload("res://scripts/rules/ai.gd")
const Setup = preload("res://scripts/rules/setup.gd")
const Soldier = preload("res://scripts/meta/soldier.gd")


func _soldier(type: String, seed: int, uid: String) -> Dictionary:
	var u := Soldier.soldier_to_unit(Soldier.new_soldier(Rng.new(seed), type, 1, func() -> String: return uid, 0))
	u.uid = uid
	return u


func test_after_an_enemy_turn_every_squad_faces_its_last_step_and_nothing_turned_on_the_spot() -> void:
	var enemy_ai := Callable(Ai, "run_enemy_ai")
	for seed in range(1, 13):
		var roll := Setup.roll_encounter("raiding_party" if seed % 2 else "orc_overseer", Rng.new(seed), 2)
		var army: Array = []
		var types := ["footman", "footman", "spearman", "spearman", "crossbowman"]
		for i in types.size():
			army.append(_soldier(types[i], seed * 10 + i, "p%d" % i))
		var b := Battle.new(Setup.build_battle(roll, army, {"survivalBonus": 0}))
		b.begin(enemy_ai)
		var turn := 0
		while turn < 4 and not b.is_over():
			turn += 1
			b.drain()
			var before := {}
			for u in b.units:
				before[u.uid] = u.facing
			b.end_turn(enemy_ai)
			var ev: Array = b.drain()
			assert_false(ev.any(func(e: Dictionary) -> bool: return e.t == "face"), "seed %d: no face events" % seed)
			var last_step := {}
			var pushed := {}
			for e in ev:
				if e.t == "move" and e.path.size() > 1:
					last_step[e.uid] = Grid.dir_to(e.path[e.path.size() - 2], e.path[e.path.size() - 1])
				if e.t == "push":
					pushed[e.uid] = true
			for u in b.units:
				if u.status == "dead" or u.status == "fled":
					continue
				if last_step.has(u.uid):
					assert_eq(u.facing, last_step[u.uid], "seed %d turn %d: %s faces its last step" % [seed, turn, u.uid])
				elif not pushed.has(u.uid):
					assert_eq(u.facing, before[u.uid], "seed %d turn %d: %s kept its facing" % [seed, turn, u.uid])
