## Self-test of a built game: `Meridius.console.exe -- --smoke`.
##
## Runs inside the real runtime (exported or editor build), so it proves the
## packed data, sprites, sounds and scripts load outside the editor: every data
## table and sprite resolves, a new company plays a full expedition with the AI,
## every encounter builds and fights to an end, and the three world views and the
## UI screens come up and draw frames. Prints "SMOKE OK" or "SMOKE FAIL: …" and
## quits with exit code 0 or 1. Results also go to user://smoke.log.
extends RefCounted

const DB = preload("res://scripts/data/db.gd")
const Rng = preload("res://scripts/core/rng.gd")
const Assets = preload("res://scripts/render/assets.gd")

static var _fails: Array[String] = []
static var _log: Array[String] = []


static func _say(s: String) -> void:
	print(s)
	_log.append(s)


static func _check(cond: bool, what: String) -> void:
	if cond:
		_say("  ok   " + what)
	else:
		_say("  FAIL " + what)
		_fails.append(what)


static func run(host: Node) -> void:
	var tree := host.get_tree()
	var t0 := Time.get_ticks_msec()
	_say("SMOKE start (Godot %s, %s)" % [Engine.get_version_info().string, OS.get_name()])

	# Data tables.
	_check(DB.UNIT_TYPES.size() >= 15 and DB.ENCOUNTERS.size() >= 10 and DB.EVENTS.size() > 10, "data tables load")

	# Every sprite key and variant resolves to real art and loads.
	var bad := 0
	var count := 0
	for key in Assets.keys():
		for v in Assets.variant_count(key):
			var spr: Dictionary = Assets.sprite(key, v)
			count += 1
			if spr.get("tex") == null:
				bad += 1
	_check(bad == 0 and count > 1000, "%d sprite variants load (%d missing)" % [count, bad])

	# Sounds.
	var sfx := host.get_node_or_null("/root/Sfx")
	_check(sfx != null and sfx.has_method("play"), "Sfx autoload present")
	if sfx != null and sfx.has_method("names"):
		var missing_sounds := 0
		for n in sfx.names():
			if sfx.stream(n, 0) == null:
				missing_sounds += 1
		_check(missing_sounds == 0, "%d sounds load" % sfx.names().size())

	# Rules: a whole expedition played by the AI, and every encounter fought out.
	var Game = load("res://scripts/meta/game.gd")
	var Auto = load("res://scripts/campaign/autoplay.gd")
	var Setup = load("res://scripts/rules/setup.gd")
	var Soldier = load("res://scripts/meta/soldier.gd")
	var Battle = load("res://scripts/rules/battle.gd")
	var g: Dictionary = Game.new_game(1234)
	_check(g.roster.size() > 0, "new game has a roster")
	var prepared: bool = Auto.auto_prepare(g, Rng.new(5))
	_check(prepared and g.get("expedition") != null, "auto-prepare launches an expedition")
	if prepared:
		var outcome = Auto.auto_expedition(g, Rng.new(5))
		_check(outcome != null and g.get("expedition") == null and g.get("lastReport") != null, "auto-expedition returns home (%s)" % str(outcome))
	var json: String = Game.to_save_json(g)
	var back = Game.from_save_json(json)
	_check(back != null and Game.to_save_json(back) == json, "save round trip")

	var fresh: Dictionary = Game.new_game(77)
	var army: Array = []
	for so in fresh.roster.slice(0, 6):
		army.append(Soldier.soldier_to_unit(so))
	var ended := 0
	for e in DB.ENCOUNTERS:
		var roll: Dictionary = Setup.roll_encounter(e.id, Rng.new(7), 2)
		var units: Array = []
		for u in army:
			units.append(u.duplicate(true))
		var b = Battle.new(Setup.build_battle(roll, units, {"survivalBonus": 0}))
		Auto.auto_battle(b)
		if b.is_over():
			ended += 1
	_check(ended == DB.ENCOUNTERS.size(), "all %d encounters fight to an end" % DB.ENCOUNTERS.size())

	# Views and screens: drive the App through its screens and draw frames.
	var app := host.get_node_or_null("/root/App")
	if app != null and app.has_method("new_game"):
		app.new_game(4321)
		for i in 10:
			await tree.process_frame
		_check(str(app.get("screen")) == "base", "new game opens the garrison")
		if app.has_method("debug_auto_prepare") and app.debug_auto_prepare(3):
			for i in 10:
				await tree.process_frame
			_check(str(app.get("screen")) == "campaign", "expedition opens the campaign map")
		if app.has_method("debug_test_battle"):
			app.debug_test_battle("raid_camp" if _has_encounter("raid_camp") else DB.ENCOUNTERS[0].id, {"seed": 7})
			for i in 30:
				await tree.process_frame
			_check(str(app.get("screen")) == "battle", "a battle opens")
			if app.has_method("debug_auto_battle"):
				app.debug_auto_battle()
				for i in 30:
					await tree.process_frame
		app.go_title()
		for i in 5:
			await tree.process_frame
	else:
		_check(false, "App autoload with new_game()")

	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	var verdict := "SMOKE OK (%.1f s)" % secs if _fails.is_empty() else "SMOKE FAIL: " + "; ".join(_fails)
	_say(verdict)
	var f := FileAccess.open("user://smoke.log", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_log) + "\n")
	tree.quit(0 if _fails.is_empty() else 1)


static func _has_encounter(id: String) -> bool:
	for e in DB.ENCOUNTERS:
		if e.id == id:
			return true
	return false
