## Battlefields and battle setups: every map template builds a sound field;
## every encounter deploys the right squads on the right ground; the squads of
## coming waves wait off the field beyond their edge.
extends "res://tests/test_case.gd"

const JS = preload("res://scripts/core/js.gd")
const Rng = preload("res://scripts/core/rng.gd")
const DB = preload("res://scripts/data/db.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const MapGen = preload("res://scripts/rules/mapgen.gd")
const Setup = preload("res://scripts/rules/setup.gd")
const Soldier = preload("res://scripts/meta/soldier.gd")

const OPTS := [{}, {"ambush": true}, {"ambush": false, "approaches": ["n", "w", "e"]}]


func _reach(map: Dictionary, start: Dictionary) -> Dictionary:
	var seen := {Grid.key(start.x, start.y): true}
	var q: Array = [start]
	var qi := 0
	while qi < q.size():
		var c: Dictionary = q[qi]
		qi += 1
		for n in Grid.neighbors(map, c):
			var k := Grid.key(n.x, n.y)
			if seen.has(k) or not Grid.tile_passable(map, n.x, n.y) or not Grid.can_step(map, c, n):
				continue
			seen[k] = true
			q.append(n)
	return seen


func test_every_map_template_builds_a_sound_field() -> void:
	for id in DB.BATTLE_MAPS:
		var tpl: Dictionary = DB.BATTLE_MAPS[id]
		var large: bool = tpl.get("layout") != null
		for seed in range(1, 11):
			for opts in OPTS:
				if large and opts.get("ambush", false):
					continue
				var m := MapGen.generate_map(id, seed, opts)
				var label := "%s seed %d %s" % [id, seed, JSON.stringify(opts)]
				assert_eq(m.id, id, label)
				assert_eq(m.scale, "large" if large else "small", label + " scale")
				if not large:
					assert_eq([m.w, m.h], [tpl.w, tpl.h], label + " size")
				else:
					assert_true([m.w, m.h] == [tpl.w, tpl.h] or [m.w, m.h] == [tpl.h, tpl.w], label + " size (maybe transposed)")
				assert_eq(m.tiles.size(), m.w * m.h, label + " tiles")
				var ok := true
				for i in m.tiles.size():
					var t: Dictionary = m.tiles[i]
					if t.x != i % m.w or t.y != i / m.w or not DB.TERRAIN.has(t.terrain) or (t.has("prop") and not DB.PROPS.has(t.prop)):
						ok = false
				assert_true(ok, label + " tiles laid out in order with known terrain and props")
				assert_true(m.playerDeploy.size() >= 6, label + " room to deploy the company")
				assert_true(m.enemyDeploy.size() >= 6, label + " room for the enemy")
				var seen := {}
				for p in m.playerDeploy + m.enemyDeploy:
					assert_true(Grid.tile_passable(m, p.x, p.y), label + " deploy tile passable")
					seen[Grid.key(p.x, p.y)] = seen.get(Grid.key(p.x, p.y), 0) + 1
				for k in seen:
					assert_eq(seen[k], 1, label + " deploy tiles unique")
				if not large:
					# Every enemy deploy tile is reachable from the company's ground.
					var reach := _reach(m, m.playerDeploy[0])
					for p in m.enemyDeploy:
						assert_true(reach.has(Grid.key(p.x, p.y)), label + " enemy ground reachable")
				for e in m.entries:
					for p in m.entries[e]:
						assert_true(Grid.tile_passable(m, p.x, p.y) and Grid.is_edge(m, p), label + " entry on the edge")
				for e in m.approaches:
					assert_true(m.entries.has(e), label + " approach %s has entries" % e)
				assert_true(m.outer.size() > 50, label + " decorative ring")
				for o in m.outer:
					assert_false(Grid.in_bounds(m, o.x, o.y), label + " ring outside the field")
				for o in m.outerGround:
					assert_not_null(MapGen.in_approach(m, o.x, o.y), label + " open ground lies in an approach")


func _company(kind: String, seed: int) -> Array:
	var rng := Rng.new(seed)
	var n := [0]
	var next_id := func() -> String:
		n[0] += 1
		return "c%d" % n[0]
	var types: Array = ["footman", "footman", "spearman", "spearman", "crossbowman", "crossbowman"]
	if kind == "small":
		types = ["footman", "spearman", "crossbowman"]
	var out: Array = []
	for i in types.size():
		var s := Soldier.new_soldier(rng, types[i], 1, next_id, 0)
		if kind == "depleted":
			s.men = 2
			s.hp = Soldier.soldier_stats(s).hp * 2
		out.append(Soldier.soldier_to_unit(s))
	return out


func test_every_encounter_deploys_its_squads_on_the_right_ground() -> void:
	for e in DB.ENCOUNTERS:
		for seed in range(1, 6):
			for kind in ["full", "small", "depleted"]:
				var roll := Setup.roll_encounter(e.id, Rng.new(seed * 101), 2)
				var army := _company(kind, seed)
				var setup := Setup.build_battle(roll, army, {"survivalBonus": 0})
				var label := "%s seed %d %s on %s" % [e.id, seed, kind, roll.mapId]
				var m: Dictionary = setup.map
				var reserve: Array = setup.units.filter(func(u: Dictionary) -> bool: return u.status == "reserve")
				var field: Array = setup.units.filter(func(u: Dictionary) -> bool: return u.status != "reserve")
				var wave_units := 0
				for w in setup.waves:
					wave_units += w.uids.size()
					assert_eq(w.units.size(), w.uids.size(), label + " wave units and uids")
				# Counts: the company, its allies, the enemy on the field and every wave squad.
				assert_eq(setup.units.size(), army.size() + roll.allies.size() + roll.enemies.size() + wave_units, label + " unit count")
				assert_eq(reserve.size(), wave_units, label + " reserves are the wave squads")
				assert_eq(field.size(), army.size() + roll.allies.size() + roll.enemies.size(), label + " on the field")
				var player_ground := {}
				for p in m.playerDeploy:
					player_ground[Grid.key(p.x, p.y)] = true
				var enemy_ground := {}
				for p in m.enemyDeploy:
					enemy_ground[Grid.key(p.x, p.y)] = true
				var taken := {}
				for u in field:
					var k := Grid.key(u.x, u.y)
					assert_false(taken.has(k), label + " one squad per tile (%s)" % u.uid)
					taken[k] = true
					assert_true(Grid.tile_passable(m, u.x, u.y), label + " on passable ground (%s)" % u.uid)
					assert_true(u.facing >= 0 and u.facing <= 3, label + " facing")
					if u.faction == "player":
						assert_true(player_ground.has(k), label + " %s on the company's ground" % u.uid)
					else:
						assert_true(enemy_ground.has(k), label + " %s on the enemy's ground" % u.uid)
				# The company: every squad it brought, in the order it came, deployed in place.
				for i in army.size():
					assert_true(is_same(setup.units[i], army[i]), label + " army first")
				assert_eq(setup.units.filter(func(u: Dictionary) -> bool: return u.faction == "player").size(), army.size() + roll.allies.size(), label + " player squads")
				if e.get("kind") == "stand":
					for u in army:
						assert_eq(u.morale, u.maxMorale, label + " the company rallies before a stand")


func test_reserves_wait_off_the_field_beyond_their_edge() -> void:
	var checked := 0
	for e in DB.ENCOUNTERS:
		if e.get("waves") == null:
			continue
		for seed in range(1, 6):
			var roll := Setup.roll_encounter(e.id, Rng.new(seed * 977), 3)
			var setup := Setup.build_battle(roll, _company("full", seed), {"survivalBonus": 0})
			var m: Dictionary = setup.map
			var by_uid := {}
			for u in setup.units:
				by_uid[u.uid] = u
			var spots := {}
			for w in setup.waves:
				var lanes: Array = m.entries[w.edge]
				var lo := 1 << 20
				var hi := -(1 << 20)
				for p in lanes:
					var a: int = p.x if w.edge == "n" or w.edge == "s" else p.y
					lo = mini(lo, a)
					hi = maxi(hi, a)
				for uid in w.uids:
					var u: Dictionary = by_uid[uid]
					var label := "%s seed %d %s (%s edge)" % [e.id, seed, uid, w.edge]
					assert_eq(u.status, "reserve", label + " status")
					assert_eq(u.faction, "enemy", label + " faction")
					assert_false(Grid.in_bounds(m, u.x, u.y), label + " off the field")
					assert_eq(u.facing, Battle.INWARD[w.edge], label + " faces onto the field")
					match w.edge:
						"n":
							assert_true(u.y <= -2, label + " beyond the north edge")
						"s":
							assert_true(u.y >= m.h + 1, label + " beyond the south edge")
						"w":
							assert_true(u.x <= -2, label + " beyond the west edge")
						"e":
							assert_true(u.x >= m.w + 1, label + " beyond the east edge")
					var along: int = u.x if w.edge == "n" or w.edge == "s" else u.y
					assert_true(along >= lo and along <= hi, label + " behind the entries")
					var k := "%d,%d" % [u.x, u.y]
					assert_false(spots.has(k), label + " own spot")
					spots[k] = true
					checked += 1
				# The warchief comes with the final wave.
				for i in w.units.size():
					if w.units[i].get("warchief", false):
						assert_true(by_uid[w.uids[i]].tags.has("warchief"), "warchief tagged")
	assert_true(checked > 100, "reserves checked: %d" % checked)


func test_a_depleted_company_meets_a_thinner_host() -> void:
	# The rabble and spears at the back of the waves stay behind; the warchief always comes.
	var full_count := 0
	var thin_count := 0
	for seed in range(1, 9):
		var roll := Setup.roll_encounter("last_stand", Rng.new(seed), 4)
		var full := Setup.build_battle(roll.duplicate(true), _company("full", seed), {"survivalBonus": 0})
		var thin := Setup.build_battle(roll.duplicate(true), _company("depleted", seed), {"survivalBonus": 0})
		for w in full.waves:
			full_count += w.uids.size()
		for w in thin.waves:
			thin_count += w.uids.size()
		assert_true(thin.units.any(func(u: Dictionary) -> bool: return u.tags.has("warchief")), "the warchief comes")
	assert_true(thin_count < full_count, "fewer squads against the depleted company (%d < %d)" % [thin_count, full_count])
