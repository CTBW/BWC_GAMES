## Encounter rolls and battle setups must match the original: enemy rolls,
## maps, deployment of the company and the enemy, allies, waves staged off the
## field as reserves, and facing.
## Golden: tools/parity/setup_golden.ts -> tests/fixtures/golden/setup_golden.json
extends "res://tests/test_case.gd"

const H = preload("res://tests/parity/test_meta_support.gd")
const Rng = preload("res://scripts/core/rng.gd")
const Setup = preload("res://scripts/rules/setup.gd")

var golden: Dictionary


func before_all() -> void:
	golden = H.load_golden("setup_golden.json")


func _summary(m: Dictionary) -> Dictionary:
	var s := m.duplicate()
	s.erase("tiles")
	s.erase("outer")
	s.erase("outerGround")
	s.tileCount = m.tiles.size()
	s.outerCount = m.outer.size()
	s.outerGroundCount = JS.get_or(m, "outerGround", []).size()
	return s


func test_rolls_match() -> void:
	for c in golden.rolls:
		var rng := Rng.new(c.seed)
		var roll := Setup.roll_encounter(c.encounterId, rng, c.depth)
		var label := "%s depth %d seed %d" % [c.encounterId, c.depth, c.seed]
		if not assert_eq(H.diff(roll, c.roll), "", label):
			return
		assert_eq(rng.state, c.rngAfter, label + " rng after")


func test_setups_match() -> void:
	var n := 0
	for c in golden.setups:
		var army: Array = c.army.duplicate(true)
		var setup := Setup.build_battle(c.roll.duplicate(true), army, c.opts)
		var expected: Dictionary = c.setup.duplicate(true)
		# Battles no longer roll whether a cut-down squad survives (the wound
		# rule, MIGRATION.md 2026-10-26): setups carry no survivalBonus.
		expected.erase("survivalBonus")
		var got := setup.duplicate(true)
		assert_true(setup.fogOfWar, "new battles enable fog of war")
		got.erase("fogOfWar")
		if not c.fullMap:
			got.map = _summary(setup.map)
		var label := "%s on %s (%s company, %s)" % [c.roll.encounterId, c.roll.mapId, c.kind, JSON.stringify(c.opts)]
		if not assert_eq(H.diff(got, expected), "", label):
			return
		# The army objects themselves are the deployed units.
		for i in army.size():
			assert_true(is_same(army[i], setup.units[i]), label + " army deployed in place")
		n += 1
	assert_true(n >= 70, "setups compared")


const JS = preload("res://scripts/core/js.gd")
