## The cases of tests/horde.test.ts that need the map generator and battle
## setup: the last-stand grounds, and a whole last stand fought by the AI.
## (The pure-rules horde cases are ported by the rules tests.)
extends "res://tests/test_case.gd"

const Rng = preload("res://scripts/core/rng.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const Ai = preload("res://scripts/rules/ai.gd")
const MapGen = preload("res://scripts/rules/mapgen.gd")
const Setup = preload("res://scripts/rules/setup.gd")
const Soldier = preload("res://scripts/meta/soldier.gd")


func _soldier(type: String, seed: int, uid: String) -> Dictionary:
	var u := Soldier.soldier_to_unit(Soldier.new_soldier(Rng.new(seed), type, 1, func() -> String: return uid, 0))
	u.uid = uid
	return u


# describe('last-stand grounds')
func _ground_is_sound(id: String) -> void:
	var seen := {}
	for seed in range(1, 24):
		var m := MapGen.generate_map(id, seed)
		seen[bool(m.get("transposed", false))] = true
		var zone: Array = m.get("zone", [])
		assert_true(zone.size() > 5, "%s seed %d: ground to hold" % [id, seed])
		assert_true(m.playerDeploy.size() >= 12, "%s seed %d: deployment" % [id, seed])
		var start: Dictionary = zone[0]
		var reach := {Grid.key(start.x, start.y): true}
		var q: Array = [start]
		var qi := 0
		while qi < q.size():
			var c: Dictionary = q[qi]
			qi += 1
			for nb in Grid.neighbors(m, c):
				var k := Grid.key(nb.x, nb.y)
				if reach.has(k) or not Grid.tile_passable(m, nb.x, nb.y) or not Grid.can_step(m, c, nb):
					continue
				reach[k] = true
				q.append(nb)
		var zone_keys := {}
		for p in zone:
			zone_keys[Grid.key(p.x, p.y)] = true
		for e in m.entries:
			var list: Array = m.entries[e]
			assert_true(list.size() > 3, "%s seed %d: entries on %s" % [id, seed, e])
			for p in list:
				assert_true(reach.has(Grid.key(p.x, p.y)), "%s seed %d: entry reaches the ground" % [id, seed])
				# No entry stands on the ground to hold.
				assert_false(zone_keys.has(Grid.key(p.x, p.y)), "%s seed %d: entry off the ground" % [id, seed])
	assert_eq(seen.size(), 2, "%s: both layouts (plain and transposed)" % id)


func test_steading_every_entry_reaches_the_ground_to_hold_and_both_layouts_are_sound() -> void:
	_ground_is_sound("steading")


func test_ford_every_entry_reaches_the_ground_to_hold_and_both_layouts_are_sound() -> void:
	_ground_is_sound("ford")


func test_a_whole_last_stand_plays_to_an_end_with_the_ai_on_both_sides() -> void:
	var enemy_ai := Callable(Ai, "run_enemy_ai")
	for i in 4:
		var roll := Setup.roll_encounter("last_stand", Rng.new(70 + i), 4)
		var army: Array = []
		var types := ["footman", "footman", "spearman", "spearman", "crossbowman", "crossbowman"]
		for k in types.size():
			army.append(_soldier(types[k], 300 + i * 10 + k, "p%d" % k))
		var b := Battle.new(Setup.build_battle(roll, army, {"survivalBonus": 0}))
		b.begin(enemy_ai)
		while not b.is_over() and b.turn <= 12:
			Ai.run_player_auto(b)
			if b.is_over():
				break
			b.end_turn(enemy_ai)
		assert_true(b.is_over(), "stand %d is over" % i)
		assert_true(b.turn <= 8, "stand %d ends by turn 8 (turn %d)" % [i, b.turn])
