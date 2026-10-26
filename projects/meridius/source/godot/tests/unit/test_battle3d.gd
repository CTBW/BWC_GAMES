extends "res://tests/test_case.gd"

## The expedition's battle: the turn-based rules on Ashby farm, one of the 3D
## battlefields (scripts/rules/battlefields.gd), shown by scripts/render/battle3d.gd.
## Its map and deployment zones, its things solid, the battle built on it,
## and the figures each rules squad takes the field as.

const Battlefields = preload("res://scripts/rules/battlefields.gd")
const Setup = preload("res://scripts/rules/setup.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const Autoplay = preload("res://scripts/campaign/autoplay.gd")
const Soldier = preload("res://scripts/meta/soldier.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const Rng = preload("res://scripts/core/rng.gd")
const DB = preload("res://scripts/data/db.gd")
const Roster = preload("res://prototypes/sandbox3d/scripts/roster.gd")
const Battle3D = preload("res://scripts/render/battle3d.gd")
const Field3D = preload("res://scripts/render/battle3d_field.gd")
const Fields = preload("res://prototypes/battlefields3d/scripts/bf_fields.gd")


func _army() -> Array:
	var n := [0]
	var next_id := func() -> String:
		n[0] += 1
		return "s%d" % n[0]
	var out := []
	for t in ["footman", "spearman", "crossbowman", "footman", "battle_mage", "spearman"]:
		out.append(Soldier.soldier_to_unit(Soldier.new_soldier(Rng.new(40 + out.size()), t, 1, next_id, 0)))
	return out


func _battle(seed := 3) -> RefCounted:
	var roll: Dictionary = Setup.roll_encounter("brute_vanguard", Rng.new(seed), 1)
	roll.waves = []
	return Battle.new(Setup.build_battle(roll, _army(), {"title": "Ashby farm", "map": Battlefields.battle_map("ashby")}))


func test_ashby_has_open_ground_for_each_side() -> void:
	var m: Dictionary = Battlefields.battle_map("ashby")
	assert_eq(m.id, "ashby")
	assert_true(m.playerDeploy.size() >= 12, "room for the company (%d tiles)" % m.playerDeploy.size())
	assert_true(m.enemyDeploy.size() >= 12, "room for a warband (%d tiles)" % m.enemyDeploy.size())
	var mine := {}
	for p in m.playerDeploy:
		mine[Grid.key(p.x, p.y)] = true
		var t: Dictionary = Grid.tile_at(m, p.x, p.y)
		assert_true(t.get("prop") == null and not (t.terrain in ["water", "shallows"]), "open ground at %d,%d" % [p.x, p.y])
	for p in m.enemyDeploy:
		assert_false(mine.has(Grid.key(p.x, p.y)), "the zones do not overlap")
	var gap := INF
	for a in m.playerDeploy:
		for c in m.enemyDeploy:
			gap = minf(gap, absi(a.x - c.x) + absi(a.y - c.y))
	assert_true(gap >= 8, "the sides draw up apart (%d tiles)" % gap)


## Every thing drawn on the field (the farm things too, and the bushes) is
## solid: the rules' map has a prop there that blocks a move, the 3D men cannot
## stand there, and no squad's march goes onto it.
func test_every_thing_on_the_field_blocks_a_move() -> void:
	var data: Dictionary = Fields.make("ashby")
	var m: Dictionary = Battlefields.battle_map("ashby")
	var field = Field3D.new()
	field.lay_out("ashby", 2.72, 0.9)
	var things := 0
	for d in data.decor:
		var x := roundi(d.at.x)
		var y := roundi(d.at.y)
		var t: Variant = Grid.tile_at(m, x, y)
		if t == null or not t.get("covered", false):
			continue
		things += 1
		var prop: Variant = t.get("prop")
		assert_true(prop != null and DB.PROPS[prop].blocksMove, "%s at %d,%d blocks a move (%s)" % [d.key, x, y, prop])
		assert_false(field.walkable(Vector2i(x, y)), "no man stands on the %s at %d,%d" % [d.key, x, y])
	assert_true(things >= 12, "the farm's things (%d)" % things)
	for t in m.tiles:
		if t.get("prop") == "bush":
			assert_false(field.walkable(Vector2i(t.x, t.y)), "a bush at %d,%d is solid" % [t.x, t.y])
	var b := _battle()
	for u in b.units:
		for k in b.reachable_full(u):
			var t: Dictionary = Grid.tile_at(b.map, k % 1000, floori(k / 1000.0))
			assert_true(t.get("prop") == null or not DB.PROPS[t.prop].blocksMove, "%s cannot march onto a %s" % [u.uid, t.get("prop")])
	field.free()


func test_the_battle_is_built_on_the_field() -> void:
	var b := _battle()
	assert_eq(b.phase, "deploy")
	assert_eq(b.map.id, "ashby", "the field's own map")
	var zone := {}
	for p in b.map.playerDeploy:
		zone[Grid.key(p.x, p.y)] = true
	for u in b.units:
		if u.faction == "player":
			assert_true(zone.has(Grid.key(u.x, u.y)), "%s draws up in the company's zone" % u.uid)
	assert_eq(b.units.filter(func(u): return u.faction == "player").size(), 6)
	assert_true(b.units.filter(func(u): return u.faction == "enemy").size() >= 4, "the warband")
	assert_true(b.fog_enabled(), "fog of war")


func test_the_ai_fights_it_to_an_end() -> void:
	var b := _battle(5)
	Autoplay.auto_battle(b)
	assert_eq(b.phase, "over")
	assert_true(b.result in ["victory", "defeat", "retreat"], "a result (%s)" % b.result)


func test_every_squad_takes_the_field_as_a_sandbox_squad() -> void:
	var ids := {}
	for s in Roster.SQUADS:
		ids[s.id] = true
	for t in Battle3D.SQUAD_OF:
		assert_true(DB.UNIT_TYPES.has(t), "%s is a rules type" % t)
		assert_true(ids.has(Battle3D.SQUAD_OF[t]), "%s's squad %s is in the roster" % [t, Battle3D.SQUAD_OF[t]])
	var b := _battle()
	for u in b.units:
		assert_true(Battle3D.SQUAD_OF.has(u.typeId), "%s has figures of its own" % u.typeId)


func test_a_squad_whose_men_are_not_on_disk_takes_another_squads() -> void:
	# The rigged models are not in Git: a fresh checkout has none of them.
	var wolves := {"typeId": "wolf_rider", "faction": "enemy"}
	var men := {"typeId": "spearman", "faction": "player"}
	var all := {"wolf_scout_3": {}, "spearman": {}, "footman": {}, "goblin_rabble": {}}
	assert_eq(Battle3D.squad_for(wolves, all), "wolf_scout_3")
	assert_eq(Battle3D.squad_for(men, all), "spearman")
	var some := {"footman": {}, "goblin_rabble": {}}
	assert_eq(Battle3D.squad_for(wolves, some), "goblin_rabble")
	assert_eq(Battle3D.squad_for(men, some), "footman")
	assert_eq(Battle3D.squad_for(wolves, {}), "", "no figures")


func test_a_spell_of_the_battle_mage_has_its_casters_clip() -> void:
	for a in DB.UNIT_TYPES.battle_mage.abilities:
		var ab: Dictionary = DB.ABILITIES[a]
		if ab.kind == "spell" and ab.get("target") != "self" and ab.get("fx") in ["fire", "lightning", "frost", "stone", "rock"]:
			assert_true(Battle3D.SPELL_CAST.has(ab.fx), "%s is cast" % a)


func test_a_rules_facing_is_the_squads_yaw() -> void:
	# Grid.DIRS: +x, +y, -x, -y; a tile's +y is the world's +z (yaw 0 faces +z).
	assert_almost(Battle3D._yaw(1), 0.0, 1e-5)
	assert_almost(Battle3D._yaw(0), PI / 2, 1e-5)
	assert_almost(absf(Battle3D._yaw(3)), PI, 1e-5)
