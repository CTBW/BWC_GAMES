## Saves: GameState -> JSON text -> parse -> migrate_save gives the same state,
## at every stage of the loop; saves written by the original game load too.
extends "res://tests/test_case.gd"

const H = preload("res://tests/parity/test_meta_support.gd")
const JS = preload("res://scripts/core/js.gd")
const Rng = preload("res://scripts/core/rng.gd")
const Game = preload("res://scripts/meta/game.gd")
const Expedition = preload("res://scripts/campaign/expedition.gd")
const Autoplay = preload("res://scripts/campaign/autoplay.gd")


func _round_trip(g: Dictionary, label: String) -> void:
	var text := Game.to_save_json(g)
	var back: Variant = Game.from_save_json(text)
	assert_not_null(back, label + ": loads")
	if back == null:
		return
	# Strict: same keys, same values (test_case compares ints and floats by value).
	assert_eq(back, g, label + ": same state")
	# And the reloaded game saves to the same text.
	var again := Game.to_save_json(back)
	if again != text:
		var i := 0
		while i < mini(again.length(), text.length()) and again[i] == text[i]:
			i += 1
		fail("%s: save text differs at %d: ...%s... vs ...%s..." % [label, i, text.substr(maxi(0, i - 60), 120), again.substr(maxi(0, i - 60), 120)])


func test_round_trip_through_the_whole_loop() -> void:
	var g := Game.new_game(5150)
	_round_trip(g, "new game")
	var army: Array = g.roster.map(func(s: Dictionary) -> String: return s.id)
	var sup := Game.recommended_supplies(army.size(), 2, Game.wagon_capacity(g), 6)
	Expedition.start_expedition(g, "hillsvain_raids", army, sup, Game.supply_cost_total(g, sup))
	_round_trip(g, "launched")
	var steps := 0
	while g.expedition != null and steps < 60:
		steps += 1
		var ex: Dictionary = g.expedition
		var p: Variant = ex.pending
		if p == null:
			var nxt := Expedition.next_nodes(ex)
			if nxt.is_empty():
				Expedition.return_home(g, "success" if ex.objectiveDone else "retreat")
				break
			Expedition.march(g, nxt[nxt.size() - 1].id)
		elif p.kind == "battle":
			var night := Expedition.prepare_night(g)
			var setup := preload("res://scripts/rules/setup.gd").build_battle(p.roll, Expedition.battle_army(g), {"survivalBonus": Expedition.survival_bonus(g), "title": p.title, "darkness": night.darkness})
			var b = preload("res://scripts/rules/battle.gd").new(setup)
			Autoplay.auto_battle(b)
			Expedition.apply_battle(g, b, p.title, p.objective)
		elif p.kind == "event" and p.get("result") == null:
			# The first choice the company can take (as the auto-player does): a
			# choice it cannot afford would leave the event pending for ever.
			var ev: Dictionary = Expedition._event(p.eventId)
			var idx := 0
			for i in ev.choices.size():
				if Expedition.choice_available(g, ev.choices[i]).ok:
					idx = i
					break
			Expedition.choose_event(g, idx)
		elif p.kind == "camp" and not p.done.has("rest"):
			Expedition.camp_repair(g)
			Expedition.camp_rest(g)
		elif p.kind == "village" and not p.spots[0].searched:
			Expedition.search_spot(g, 0)
		elif p.kind == "complete":
			Expedition.return_home(g, "success")
		else:
			Expedition.dismiss_pending(g)
		_round_trip(g, "step %d (%s)" % [steps, "home" if g.expedition == null else str(JS.get_or(g.expedition.pending if g.expedition.pending != null else {}, "kind", "none"))])
	assert_eq(g.expedition, null, "the expedition ended")
	assert_not_null(g.lastReport, "with a report")
	_round_trip(g, "home")


func test_saves_written_by_the_original_load() -> void:
	var golden: Dictionary = H.load_golden("campaign_golden.json", false)
	assert_eq(golden.saves.size(), 3)
	for s in golden.saves:
		var g: Variant = Game.from_save_json(s.text)
		assert_not_null(g, s.label + ": loads")
		if g == null:
			continue
		assert_eq(H.diff(g, JSON.parse_string(s.text)), "", s.label + ": same state")
		# Byte for byte: Godot writes the save text the original wrote.
		assert_true(Game.to_save_json(g) == s.text, s.label + ": same save text as the original")
		_round_trip(g, s.label + " (resaved)")
	# The loaded mid-expedition save plays on.
	var mid: Dictionary = Game.from_save_json(golden.saves[1].text)
	assert_not_null(mid.expedition, "on the march")
	var out := Autoplay.auto_expedition(mid, Rng.new(3))
	assert_true(out in ["success", "retreat", "defeat"], "plays to an end: " + out)


func test_rejects_other_versions_and_garbage() -> void:
	var g := Game.new_game(1)
	g.version = Game.SAVE_VERSION + 1
	assert_eq(Game.from_save_json(Game.to_save_json(g)), null, "other version")
	assert_eq(Game.from_save_json("not json"), null, "garbage")
	assert_eq(Game.from_save_json("[1, 2]"), null, "not an object")


func test_integral_numbers_load_as_ints() -> void:
	var g: Dictionary = Game.from_save_json(Game.to_save_json(Game.new_game(8)))
	assert_true(g.resources.silver is int, "silver is an int")
	assert_true(g.roster[0].hp is int, "hp is an int")
	assert_true(g.nextId is int, "nextId is an int")


func test_floats_load_exactly() -> void:
	# Godot's own parser reads 0.44999999999999996 as 0.45; saves must not drift.
	var v := 1.0 - 0.55
	var parsed: Dictionary = Game.parse_json_exact('{"a": 0.44999999999999996, "b": [0.1, 0.30000000000000004, 0.6499999999999999, -0.44999999999999996, 3, 1e-7], "s": "1.5, 0.44999999999999996"}')
	assert_true(parsed.a == v, "0.44999999999999996 exact")
	assert_true(parsed.b[0] == 0.1 and parsed.b[1] == 0.1 + 0.2 and parsed.b[3] == -v, "others exact")
	assert_eq(parsed.s, "1.5, 0.44999999999999996", "strings untouched")
	var g := Game.new_game(3)
	g.roster[0].armorCondition = v
	var back: Dictionary = Game.from_save_json(Game.to_save_json(g))
	assert_true(back.roster[0].armorCondition == v, "armorCondition survives a save")
	assert_eq(Game.repair_cost(back, back.roster[0]), Game.repair_cost(g, g.roster[0]), "same repair cost")
