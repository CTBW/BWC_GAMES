## Performance of the battle AI on the largest battles: the last stands on the
## 24×22 grounds with every wave of the horde on the field. Times each enemy
## turn (end_turn with Ai.run_enemy_ai) and each automated company turn, and
## prints the numbers. The budget for one enemy turn is 1.5 s; the assertion
## allows twice that so a busy machine does not fail the suite.
extends "res://tests/unit/test_battle_base.gd"

const GOLDEN := ["res://tests/fixtures/golden/battle/last_stand.json", "res://tests/fixtures/golden/battle/extra.json"]
const BUDGET_MS := 1500.0


func test_enemy_turns_on_the_largest_battles() -> void:
	var setups: Array = []
	for path in GOLDEN:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			fail("missing %s" % path)
			return
		var data: Dictionary = JS.normalize(JSON.parse_string(f.get_as_text()))
		for t in data.traces:
			if t.setup.map.get("scale") == "large" and t.setup.get("encounterId") == "last_stand":
				setups.append([t.name, t.setup])
	var worst := 0.0
	var worst_at := ""
	var total := 0.0
	var turns := 0
	var player_worst := 0.0
	for entry in setups:
		var b = Battle.new(entry[1])
		b.begin(Ai.run_enemy_ai)
		var battle_worst := 0.0
		var battle_squads := 0
		while not b.is_over() and b.turn <= 30:
			var t0 := Time.get_ticks_usec()
			Ai.run_player_auto(b)
			player_worst = maxf(player_worst, (Time.get_ticks_usec() - t0) / 1000.0)
			if b.is_over():
				break
			var turn: int = b.turn
			t0 = Time.get_ticks_usec()
			b.end_turn(Ai.run_enemy_ai)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			var squads: int = b.living().size()
			total += ms
			turns += 1
			if ms > battle_worst:
				battle_worst = ms
				battle_squads = squads
			if ms > worst:
				worst = ms
				worst_at = "%s turn %d, %d squads on the field" % [entry[0], turn, squads]
		print("      %-48s worst enemy turn %6.1f ms (%d squads)" % [entry[0], battle_worst, battle_squads])
	print("      enemy turns: %d, mean %.1f ms, worst %.1f ms (%s); worst company turn %.1f ms" % [turns, total / maxi(1, turns), worst, worst_at, player_worst])
	assert_true(turns > 0)
	assert_true(worst < BUDGET_MS * 2, "worst enemy turn %.1f ms (budget %.0f ms)" % [worst, BUDGET_MS])
