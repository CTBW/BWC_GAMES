## Shared helpers for the battle rule tests (no tests of its own).
##
## The squads, open fields and battle setups the original tests build with
## soldier.ts / mapgen.ts / setup.ts come from tests/fixtures/golden/battle/fixtures.json
## (tools/parity/battle_fixtures.ts), so these tests exercise only the rules port.
extends "res://tests/test_case.gd"

const JS = preload("res://scripts/core/js.gd")
const Rng = preload("res://scripts/core/rng.gd")
const DB = preload("res://scripts/data/db.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const Squad = preload("res://scripts/rules/squad.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const Ai = preload("res://scripts/rules/ai.gd")

const FIXTURES := "res://tests/fixtures/golden/battle/fixtures.json"
const DEFAULT_ARMY := ["footman", "footman", "spearman", "spearman", "crossbowman"]

static var _fixtures: Variant = null


static func fixtures() -> Dictionary:
	if _fixtures == null:
		var f := FileAccess.open(FIXTURES, FileAccess.READ)
		if f == null:
			push_error("missing %s (run tools/parity/battle_fixtures.ts)" % FIXTURES)
			_fixtures = {"units": {}, "setups": {}, "fields": {}}
		else:
			_fixtures = JS.normalize(JSON.parse_string(f.get_as_text()))
	return _fixtures


func _unit(key: String) -> Variant:
	var u: Variant = fixtures().units.get(key)
	if u == null:
		fail("fixture %s missing: add it to tools/parity/battle_fixtures.ts" % key)
		return null
	return u.duplicate(true)


## tests/battle.test.ts army(seed, types).
func army(seed: int, types: Array = DEFAULT_ARMY) -> Array:
	var v: Variant = _unit("army:%d:%s" % [seed, ",".join(PackedStringArray(types))])
	return v if v != null else []


## makeEnemy(type, level, uid, new Rng(seed)).
func make_enemy(type: String, level: int, uid: String, seed: int) -> Dictionary:
	var v: Variant = _unit("enemy:%s:%d:%s:%d" % [type, level, uid, seed])
	return v if v != null else {}


## tests/squad.test.ts footmen(seed).
func footmen(seed := 1) -> Dictionary:
	var v: Variant = _unit("footmen:%d" % seed)
	return v if v != null else {}


## tests/facing.test.ts and horde.test.ts soldier(type, seed, uid).
func soldier(type: String, seed: int, uid: String) -> Dictionary:
	var v: Variant = _unit("soldier:%s:%d:%s" % [type, seed, uid])
	return v if v != null else {}


## tests/facing.test.ts enemy(): makeEnemy with new Rng(uid.length + x * 7 + y), placed.
func enemy_f(type: String, uid: String, x: int, y: int, facing: int) -> Dictionary:
	var g := make_enemy(type, 1, uid, uid.length() + x * 7 + y)
	g.x = x
	g.y = y
	g.facing = facing
	return g


## tests/horde.test.ts enemy(): makeEnemy with new Rng(uid.length * 13 + x), placed.
func enemy_h(type: String, uid: String, x: int, y: int, facing := 1) -> Dictionary:
	var g := make_enemy(type, 1, uid, uid.length() * 13 + x)
	g.x = x
	g.y = y
	g.facing = facing
	return g


func setup_fixture(key: String) -> Dictionary:
	var s: Variant = fixtures().setups.get(key)
	if s == null:
		fail("setup fixture %s missing" % key)
		return {}
	return s.duplicate(true)


## The original tests' openField(seed): generateMap('forest_clearing', seed), all flat grass.
func open_field(seed: int) -> Dictionary:
	var m: Variant = fixtures().fields.get(str(seed))
	if m == null:
		fail("field fixture %d missing" % seed)
		return {}
	return m.duplicate(true)


func new_battle(units: Array, seed: int, map: Dictionary, extra := {}) -> Variant:
	var setup := {"seed": seed, "map": map, "units": units, "title": "t"}
	setup.merge(extra, true)
	return Battle.new(setup)


## The autoBattle loop of tests/battle.test.ts (AI on both sides, no captain's retreat).
static func auto_battle(b, max_turns := 30) -> Variant:
	b.begin(Ai.run_enemy_ai)
	while not b.is_over() and b.turn <= max_turns:
		Ai.run_player_auto(b)
		if b.is_over():
			break
		b.end_turn(Ai.run_enemy_ai)
	return b


static func no_ai(_b) -> void:
	pass


static func events_of(evs: Array, t: String) -> Array:
	return evs.filter(func(e): return e.t == t)


static func has_event(evs: Array, pred: Callable) -> bool:
	for e in evs:
		if pred.call(e):
			return true
	return false
