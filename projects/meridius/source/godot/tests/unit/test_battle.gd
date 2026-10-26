## Battle rules: combat, redo, auto battles (port of tests/battle.test.ts; its
## map-generation test belongs to mapgen) plus explicit checks of occupancy,
## movement, attack legality, damage, turns, victory/defeat and retreat.
extends "res://tests/unit/test_battle_base.gd"

const Setup = preload("res://scripts/rules/setup.gd")
const Game = preload("res://scripts/meta/game.gd")
const Soldier = preload("res://scripts/meta/soldier.gd")


# ------------------------------------------------------------------ battle.test.ts: combat rules

func test_arcs_front_flank_and_rear_relative_to_facing() -> void:
	var map := open_field(7)
	var f: Dictionary = army(1, ["footman"])[0]
	f.x = 5
	f.y = 5
	f.facing = 3 # facing -y
	var b = new_battle([f], 1, map)
	assert_eq(b.arc_of(f, {"x": 5, "y": 4}), "front")
	assert_eq(b.arc_of(f, {"x": 6, "y": 5}), "flank")
	assert_eq(b.arc_of(f, {"x": 4, "y": 5}), "flank")
	assert_eq(b.arc_of(f, {"x": 5, "y": 6}), "rear")


func test_rear_attacks_hit_more_often_than_frontal_ones_against_a_shield() -> void:
	var map := open_field(9)
	var f: Dictionary = army(4, ["footman"])[0]
	var g := make_enemy("goblin_spear", 1, "g", 1)
	f.x = 5; f.y = 5; f.facing = 3
	g.x = 5; g.y = 4
	var b = new_battle([f, g], 1, map)
	var front: Dictionary = b.preview(g, f, {"from": {"x": 5, "y": 4}})
	var rear: Dictionary = b.preview(g, f, {"from": {"x": 5, "y": 6}})
	assert_true(rear.chance > front.chance + 20, "rear %d vs front %d" % [rear.chance, front.chance])
	assert_true(rear.max >= front.max)


func test_spearwall_halts_an_advancing_enemy_on_a_hit() -> void:
	var map := open_field(11)
	var s: Dictionary = army(5, ["spearman"])[0]
	s.stats.melee = 200 # always hit
	s.x = 5; s.y = 8; s.facing = 3
	s["stance"] = "spearwall"
	var g := make_enemy("orc_warrior", 1, "g", 2)
	g.x = 5; g.y = 4; g.facing = 1
	var b = new_battle([s, g], 2, map)
	b.phase = "enemy"
	b.move("g", 5, 7)
	assert_true(has_event(b.drain(), func(e): return e.t == "halt"))


# ------------------------------------------------------------------ battle.test.ts: redo move

func test_redo_walks_a_soldier_back_and_lets_him_move_again_until_he_attacks() -> void:
	var map := open_field(21)
	var f: Dictionary = army(30, ["footman"])[0]
	f.x = 5; f.y = 9; f.facing = 3
	var g := make_enemy("goblin_spear", 1, "g", 3)
	g.x = 5; g.y = 4; g.facing = 1
	var b = new_battle([f, g], 3, map)
	b.phase = "player"
	assert_true(b.move(f.uid, 5, 7))
	assert_true(b.can_redo(f.uid).ok)
	assert_true(b.redo_move(f.uid))
	assert_eq([f.x, f.y, f.hasMoved, f.facing], [5, 9, false, 3])
	# Move again, this time next to the goblin, then attack: the move is committed.
	assert_true(b.move(f.uid, 5, 5))
	assert_true(b.can_redo(f.uid).ok)
	assert_true(b.attack(f.uid, g.uid))
	assert_false(b.can_redo(f.uid).ok)
	assert_false(b.redo_move(f.uid))


func test_cannot_take_back_a_move_the_enemy_reacted_to() -> void:
	var map := open_field(22)
	var f: Dictionary = army(31, ["footman"])[0]
	f.x = 5; f.y = 6; f.facing = 3
	var g := make_enemy("goblin_spear", 1, "g", 4)
	g.x = 5; g.y = 5; g.facing = 1
	var b = new_battle([f, g], 4, map)
	b.phase = "player"
	# Stepping away from an adjacent enemy provokes a free attack.
	assert_true(b.move(f.uid, 5, 8))
	var r: Dictionary = b.can_redo(f.uid)
	assert_false(r.ok)
	assert_true(String(r.reason).contains("reacted"), r.reason)


func test_redo_is_refused_once_another_soldier_takes_the_starting_tile() -> void:
	var map := open_field(23)
	var units := army(32, ["footman", "spearman"])
	var a: Dictionary = units[0]
	var c: Dictionary = units[1]
	a.x = 5; a.y = 10
	c.x = 7; c.y = 10
	var far := make_enemy("goblin_archer", 1, "g", 5)
	far.x = 12; far.y = 1
	var b = new_battle([a, c, far], 5, map)
	b.phase = "player"
	assert_true(b.move(a.uid, 5, 8))
	assert_true(b.move(c.uid, 5, 10))
	assert_false(b.can_redo(a.uid).ok)
	assert_true(b.can_redo(c.uid).ok)


# ------------------------------------------------------------------ battle.test.ts: auto battles

func test_battles_finish_and_the_starting_army_usually_beats_goblin_scouts() -> void:
	var wins := 0
	var n := 40
	for i in n:
		var b = auto_battle(Battle.new(setup_fixture("scouts:%d" % i)))
		assert_true(b.is_over(), "battle %d finished" % i)
		if b.result == "victory":
			wins += 1
	assert_true(float(wins) / n > 0.7, "won %d of %d" % [wins, n])


func test_the_warband_camp_is_a_real_fight_for_a_fresh_army() -> void:
	var wins := 0
	var n := 30
	for i in n:
		var b = auto_battle(Battle.new(setup_fixture("camp:%d" % i)))
		if b.result == "victory":
			wins += 1
	assert_true(float(wins) / n < 0.95, "won %d of %d" % [wins, n])


# ------------------------------------------------------------------ occupancy and movement

## A small duel on the open field: footmen f at (5, 9) facing -y, a goblin archer far off.
func _duel(extra_units: Array = []) -> Variant:
	var f := soldier("footman", 1, "f")
	f.x = 5; f.y = 9; f.facing = 3
	var g := enemy_f("goblin_archer", "g", 12, 1, 1)
	var units: Array = [f, g]
	units.append_array(extra_units)
	var b = new_battle(units, 1, open_field(41))
	b.phase = "player"
	return b


func test_one_squad_per_tile() -> void:
	var s := soldier("spearman", 5, "s")
	s.x = 5; s.y = 7; s.facing = 3
	var b = _duel([s])
	var f: Dictionary = b.unit("f")
	assert_eq(Grid.unit_at(b.units, 5, 7), s)
	# The ally's tile can be walked through but not ended on.
	assert_false(b.reachable(f).has(Grid.key(5, 7)), "occupied tile is not a destination")
	assert_true(b.reachable_full(f).has(Grid.key(5, 7)), "but it can be passed")
	assert_eq(b.facing_options(f, 5, 7), [])
	assert_eq(b.path_to(f, 5, 7), null)
	assert_false(b.move("f", 5, 7))
	assert_eq([f.x, f.y, f.hasMoved], [5, 9, false])
	# Through the ally to the tile beyond.
	assert_true(b.move("f", 5, 6))
	assert_eq([f.x, f.y], [5, 6])
	# Dead and fled squads free their tile; reserves are not on the field.
	s.status = "dead"
	assert_eq(Grid.unit_at(b.units, 5, 7), null)
	s.status = "routing"
	assert_eq(Grid.unit_at(b.units, 5, 7), s)
	s.status = "reserve"
	assert_eq(Grid.unit_at(b.units, 5, 7), null)


## Living squads sharing a tile, as "a and b on x,y" ("" when none do).
static func _shared_tile(b) -> String:
	var seen := {}
	for u in b.units:
		if u.status != "active" and u.status != "routing":
			continue
		var k := Grid.key(u.x, u.y)
		if seen.has(k):
			return "%s and %s on %d,%d" % [seen[k], u.uid, u.x, u.y]
		seen[k] = u.uid
	return ""


func test_a_routing_enemy_blocks_the_way_like_any_other() -> void:
	# A path may cross an ally's tile but no enemy's, fleeing or not: the walk
	# stops in front of any enemy. (The archived original planned through
	# routing foes, so the walk could end short on the ally's tile.)
	var s := soldier("spearman", 5, "s")
	s.x = 5; s.y = 8; s.facing = 3
	var g := enemy_f("goblin_spear", "g", 6, 5, 1)
	g.uid = "g2"
	g.x = 5; g.y = 7
	g.status = "routing"
	var b = _duel([s, g])
	var f: Dictionary = b.unit("f")
	assert_false(b.reachable_full(f).has(Grid.key(5, 7)), "the routing goblins' tile is not crossed")
	var reach: Dictionary = b.reachable(f)
	if reach.has(Grid.key(5, 6)):
		assert_false(b.path_from(reach, 5, 6).has({"x": 5, "y": 7}), "the way round, not through")
	if b.move("f", 5, 6):
		assert_eq([f.x, f.y], [5, 6])
	else:
		assert_eq([f.x, f.y], [5, 9])
	assert_eq(_shared_tile(b), "")


func test_a_walk_stopped_on_an_allys_tile_falls_back_to_the_last_free_one() -> void:
	# A foe in the way (put there by hand: planning never paths through one)
	# stops the walk on the ally's tile; the squad backs off to its own,
	# still facing its way.
	var s := soldier("spearman", 5, "s")
	s.x = 5; s.y = 8; s.facing = 3
	var g := enemy_f("goblin_spear", "g", 6, 5, 3)
	g.uid = "g2"
	g.x = 5; g.y = 7 # facing -y: the ally's tile is behind it, so no free attack
	var b = _duel([s, g])
	var f: Dictionary = b.unit("f")
	b.drain()
	var moved: int = b.walk(f, [{"x": 5, "y": 9}, {"x": 5, "y": 8}, {"x": 5, "y": 7}, {"x": 5, "y": 6}])
	assert_eq(moved, 0)
	assert_eq([f.x, f.y, f.facing, f.movedTiles], [5, 9, 3, 0])
	var moves: Array = events_of(b.drain(), "move")
	assert_eq(moves.size(), 2)
	assert_eq(moves[0].path, [{"x": 5, "y": 9}, {"x": 5, "y": 8}])
	assert_eq(moves[1].path, [{"x": 5, "y": 8}, {"x": 5, "y": 9}])
	assert_true(moves[1].get("backward", false), "marked as backing off")
	assert_eq(_shared_tile(b), "")


func test_a_squad_broken_on_an_allys_tile_falls_back_too() -> void:
	# Leaving the ally's tile costs a free attack that breaks the footmen.
	var s := soldier("spearman", 5, "s")
	s.x = 5; s.y = 8; s.facing = 3
	var g := enemy_f("goblin_spear", "g", 6, 5, 2)
	g.uid = "g2"
	g.x = 6; g.y = 8 # facing -x: the ally's tile is its front
	g.stats.melee = 300 # always hit
	var b = _duel([s, g])
	var f: Dictionary = b.unit("f")
	f.morale = 1
	b.walk(f, [{"x": 5, "y": 9}, {"x": 5, "y": 8}, {"x": 4, "y": 8}])
	assert_eq(f.status, "routing", "the free attack broke them")
	assert_eq([f.x, f.y], [5, 9])
	assert_eq(_shared_tile(b), "")


func test_no_two_squads_ever_share_a_tile() -> void:
	# Every encounter, both sides on automation: after each squad's action and
	# each enemy turn, every living squad has its tile to itself.
	if slow():
		return
	for seed in [1, 2]:
		var g := Game.new_game(seed)
		var army: Array = []
		for s in g.roster:
			army.append(Soldier.soldier_to_unit(s))
		for enc in DB.ENCOUNTERS:
			var roll := Setup.roll_encounter(enc.id, Rng.new(seed * 131 + 7), 1)
			var b = Battle.new(Setup.build_battle(roll, army.duplicate(true), {"title": enc.id, "darkness": false}))
			b.begin(Ai.run_enemy_ai)
			var where := ""
			while not b.is_over() and b.turn <= 30 and where == "":
				for u in b.active("player"):
					if b.is_over() or u.status != "active":
						continue
					Ai.act_unit(b, u, {"useStances": true})
					where = _shared_tile(b)
					if where != "":
						where = "after %s acted: %s" % [u.uid, where]
						break
				if where != "" or b.is_over():
					break
				b.end_turn(Ai.run_enemy_ai)
				where = _shared_tile(b)
				if where != "":
					where = "after the enemy turn: " + where
			assert_eq(where, "", "%s seed %d turn %d" % [enc.id, seed, b.turn])


func test_movement_validation() -> void:
	var b = _duel()
	var f: Dictionary = b.unit("f")
	var move: int = f.stats.move
	# Beyond the move budget.
	assert_false(b.reachable(f).has(Grid.key(5, 9 - move - 1)))
	assert_false(b.move("f", 5, 9 - move - 1))
	# An impassable tile (boulders) and deep water.
	b.map.tiles[8 * b.map.w + 5]["prop"] = "rock_large"
	b.map.tiles[9 * b.map.w + 6].terrain = "water"
	assert_false(Grid.tile_passable(b.map, 5, 8))
	assert_false(Grid.tile_passable(b.map, 6, 9))
	assert_false(b.move("f", 5, 8))
	assert_false(b.move("f", 6, 9))
	# A cliff: more than one level up cannot be climbed.
	b.map.tiles[9 * b.map.w + 4].h = 2
	assert_false(Grid.can_step(b.map, {"x": 5, "y": 9}, {"x": 4, "y": 9}))
	assert_false(b.move("f", 4, 9))
	b.map.tiles[9 * b.map.w + 4].h = 1
	assert_true(Grid.can_step(b.map, {"x": 5, "y": 9}, {"x": 4, "y": 9}))
	# Off the map.
	assert_false(b.move("f", -1, 9))
	assert_false(b.move("f", 5, 40))
	# Staying put with the same facing is no move; a valid one goes through.
	assert_false(b.move("f", 5, 9))
	assert_eq(f.hasMoved, false)
	assert_true(b.move("f", 4, 9))
	# Only once per turn, and not in the other side's phase.
	assert_false(b.move("f", 4, 8))
	assert_false(b.move("g", 11, 1))


func test_move_cost_follows_terrain() -> void:
	var b = _duel()
	var f: Dictionary = b.unit("f")
	for y in range(5, 9):
		b.map.tiles[y * b.map.w + 5].terrain = "forest" # cost 2
	var reach: Dictionary = b.reachable(f)
	assert_eq(reach[Grid.key(5, 8)].cost, 2)
	assert_eq(reach[Grid.key(5, 7)].cost, 4)
	assert_false(reach.has(Grid.key(5, 6)) and reach[Grid.key(5, 6)].prev == Grid.key(5, 7))


func test_movement_execution() -> void:
	var b = _duel()
	var f: Dictionary = b.unit("f")
	assert_true(b.move("f", 7, 9, 0))
	assert_eq([f.x, f.y, f.facing, f.hasMoved, f.movedTiles, f.done], [7, 9, 0, true, 2, false])
	var moves: Array = events_of(b.drain(), "move")
	assert_eq(moves.size(), 1)
	assert_eq(moves[0].path, [{"x": 5, "y": 9}, {"x": 6, "y": 9}, {"x": 7, "y": 9}])
	assert_true(b.move_records.has("f"))
	assert_true(b.move_records.f.clean)


func test_zones_of_control() -> void:
	# A goblin facing the footmen: its front and flank tiles are its zone.
	var g := enemy_f("goblin_spear", "g2", 5, 5, 1)
	var f := soldier("footman", 9, "f2")
	f.x = 5; f.y = 6; f.facing = 3
	var b = new_battle([f, g], 9, open_field(49))
	b.phase = "player"
	var zoc: Dictionary = b.zoc_tiles(f)
	assert_true(zoc.has(Grid.key(5, 6)), "front")
	assert_true(zoc.has(Grid.key(4, 5)) and zoc.has(Grid.key(6, 5)), "flanks")
	assert_false(zoc.has(Grid.key(5, 4)), "its rear is blind")
	# The path cost counts the free attacks: stepping out of the zone costs one.
	var reach: Dictionary = b.reachable(f)
	assert_eq(reach[Grid.key(5, 8)].zoc, 1)
	assert_true(b.move("f2", 5, 8))
	var attacks: Array = events_of(b.drain(), "attack")
	assert_eq(attacks.size(), 1)
	assert_eq(attacks[0].reaction, "zoc")
	assert_eq(attacks[0].uid, "g2")
	# Wolf riders slip away: no zone of control for them.
	var w := enemy_h("wolf_rider", "w", 6, 5, 1)
	assert_eq(b.zoc_tiles(w), {})


# ------------------------------------------------------------------ attacks

func test_attack_target_legality() -> void:
	var c := soldier("crossbowman", 12, "c")
	c.x = 6; c.y = 10; c.facing = 3
	var b = _duel([c])
	var f: Dictionary = b.unit("f")
	var g: Dictionary = b.unit("g")
	# Melee needs an adjacent target on a step it can reach.
	var pv: Dictionary = b.preview(f, g)
	assert_false(pv.legal)
	assert_eq(pv.reason, "Not adjacent")
	assert_false(b.attack("f", "g"))
	assert_eq(b.targets(f), [])
	# A shot needs range, sight and light.
	g.x = 6; g.y = 4 # 6 tiles from the crossbowmen
	assert_true(b.can_shoot(c, g).ok)
	assert_eq(b.targets(c), [g])
	g.x = 6; g.y = 2 # 8 tiles: beyond range 7
	assert_eq(b.can_shoot(c, g).reason, "Out of range")
	g.x = 6; g.y = 9 # adjacent: melee instead, and too close to shoot
	assert_eq(b.can_shoot(c, g).reason, "Too close to shoot")
	assert_false(b.would_shoot(c, g))
	g.x = 6; g.y = 5
	b.map.tiles[7 * b.map.w + 6]["prop"] = "tree_oak"
	assert_eq(b.can_shoot(c, g).reason, "No line of sight")
	b.map.tiles[7 * b.map.w + 6].erase("prop")
	b.setup["darkness"] = true
	# In the dark a shot reaches two tiles less: five tiles is fine, six is not.
	assert_true(b.can_shoot(c, g).ok)
	g.y = 4
	assert_eq(b.can_shoot(c, g).reason, "Too dark to see")
	g.y = 5
	b.setup.erase("darkness")
	c.ammo = 0
	assert_eq(b.can_shoot(c, g).reason, "Out of bolts")
	c.ammo = 6
	# Pike thrust: two tiles in a straight line only.
	var s := soldier("spearman", 14, "s")
	s.x = 6; s.y = 7; s.facing = 3
	b.units.append(s)
	assert_true(b.preview(s, g, {"ability": "pikethrust"}).legal)
	g.x = 7; g.y = 5
	var pt: Dictionary = b.preview(s, g, {"ability": "pikethrust"})
	assert_false(pt.legal)
	assert_eq(pt.reason, "Needs a straight line two tiles away")
	# Dead squads cannot act; an attack is refused out of phase and once acted.
	g.x = 6; g.y = 6
	assert_true(b.attack("s", "g"))
	assert_false(b.attack("s", "g"))
	b.phase = "enemy"
	assert_false(b.attack("f", "g"))


func test_damage_calculation() -> void:
	var f := soldier("footman", 6, "f")
	f.x = 5; f.y = 5; f.facing = 3
	var g := enemy_f("goblin_spear", "g", 6, 5, 1) # on f's +x flank, facing +y
	var b = new_battle([f, g], 1, open_field(46))
	b.phase = "player"
	var armor: float = g.stats.armor
	var per := func(d: float) -> int: return maxi(1, JS.rnd(d - armor))
	# The goblin faces +y; the footmen strike from its -x side: a flank attack.
	var pv: Dictionary = b.preview(f, g)
	assert_eq(pv.arc, "flank")
	assert_eq(pv.min, per.call(f.melee[0]) * 6)
	assert_eq(pv.max, per.call(f.melee[1]) * 6)
	# From behind: ×1.25.
	g.facing = 0
	pv = b.preview(f, g)
	assert_eq(pv.arc, "rear")
	assert_eq(pv.min, per.call(f.melee[0] * 1.25) * 6)
	assert_eq(pv.max, per.call(f.melee[1] * 1.25) * 6)
	# A spearwall reaction: ×1.5 and +15 to hit.
	g.facing = 2
	var plain: Dictionary = b.preview(f, g)
	var wall: Dictionary = b.preview(f, g, {"reaction": "spearwall", "forceMelee": true})
	assert_eq(wall.max, per.call(f.melee[1] * 1.5) * 6)
	assert_eq(wall.chance, mini(95, plain.chance + 15))
	# Shield bash: ×0.55, +10 to hit, +12 morale damage.
	var bash: Dictionary = b.preview(f, g, {"ability": "shieldbash"})
	assert_eq(bash.max, per.call(f.melee[1] * 0.55) * 6)
	assert_eq(bash.chance, mini(95, plain.chance + 10))
	assert_eq(bash.moraleHit, plain.moraleHit - JS.rnd(float(plain.min + plain.max) / 2 / g.maxHp * 28) + JS.rnd(float(bash.min + bash.max) / 2 / g.maxHp * 28) + 12)
	# The chance is clamped to 5..95.
	f.stats.melee = 500
	assert_eq(b.preview(f, g).chance, 95)
	f.stats.melee = -500
	assert_eq(b.preview(f, g).chance, 5)
	# Charging orcs: +3 per soldier after moving two tiles.
	var o := enemy_f("orc_warrior", "o", 5, 9, 3)
	o.x = 5; o.y = 6
	var still: Dictionary = b.preview(o, f, {"movedTiles": 0})
	var charge: Dictionary = b.preview(o, f, {"movedTiles": 2})
	assert_eq(charge.min - still.min, 3 * 6)
	assert_eq(charge.moraleHit - still.moraleHit, 8 + JS.rnd(float(charge.min + charge.max) / 2 / f.maxHp * 28) - JS.rnd(float(still.min + still.max) / 2 / f.maxHp * 28))


func test_a_squad_wiped_out_is_down_and_counts_as_a_kill() -> void:
	var f := soldier("footman", 6, "f")
	f.x = 5; f.y = 5; f.facing = 3
	f.stats.melee = 500
	var g := enemy_f("goblin_spear", "g", 6, 5, 1)
	g.hp = 3
	g.alive = 1
	var far := enemy_f("goblin_archer", "e", 13, 0, 1)
	var b = new_battle([f, g, far], 1, open_field(46))
	b.phase = "player"
	assert_true(b.attack("f", "g"))
	assert_eq([g.status, g.hp, g.alive], ["dead", 0, 0])
	assert_eq(f.kills, 1)
	assert_eq(f.xp, DB.UNIT_TYPES.goblin_spear.value)
	var evs: Array = b.drain()
	assert_true(has_event(evs, func(e): return e.t == "down" and e.uid == "g" and e.dead))
	assert_eq(Grid.unit_at(b.units, 6, 5), null)
	assert_false(b.is_over())


# ------------------------------------------------------------------ turns, victory, defeat, retreat

func test_turn_progression() -> void:
	var b = _duel()
	var f: Dictionary = b.unit("f")
	var g: Dictionary = b.unit("g")
	b.phase = "deploy"
	b.begin(no_ai)
	assert_eq([b.phase, b.turn], ["player", 1])
	var evs: Array = b.drain()
	assert_eq(evs[0], {"t": "turn", "faction": "player", "turn": 1})
	assert_true(b.move("f", 5, 8))
	assert_true(b.use_stance("f", "shieldwall"))
	assert_eq([f.hasMoved, f.hasActed, f.done, f.get("stance")], [true, true, true, "shieldwall"])
	var phases: Array = []
	b.end_turn(func(bb): phases.append([bb.phase, bb.turn]))
	assert_eq(phases, [["enemy", 1]])
	assert_eq([b.phase, b.turn], ["player", 2])
	evs = b.drain()
	assert_eq(events_of(evs, "turn"), [{"t": "turn", "faction": "enemy", "turn": 1}, {"t": "turn", "faction": "player", "turn": 2}])
	# A new turn clears the squad's flags and its stance.
	assert_eq([f.hasMoved, f.hasActed, f.done, f.movedTiles, f.get("stance")], [false, false, false, 0, null])
	assert_true(has_event(evs, func(e): return e.t == "stance" and e.uid == "f" and e.stance == null))
	# Cooldowns count down at the start of the squad's turn.
	f.cooldowns["shieldbash"] = 2
	b.end_turn(no_ai)
	assert_eq(f.cooldowns.shieldbash, 1)
	b.end_turn(no_ai)
	assert_eq(f.cooldowns.shieldbash, 0)
	# end_turn only works in the player's phase.
	b.phase = "enemy"
	b.end_turn(no_ai)
	assert_eq(b.turn, 4)
	assert_eq(g.status, "active")


func test_enemy_first_battles_open_with_the_enemy_turn() -> void:
	var b = _duel()
	b.phase = "deploy"
	b.setup["enemyFirst"] = true
	var seen: Array = []
	b.begin(func(bb): seen.append(bb.phase))
	assert_eq(seen, ["enemy"])
	assert_eq([b.phase, b.turn], ["player", 1])
	var turns: Array = events_of(b.drain(), "turn")
	assert_eq(turns.map(func(e): return e.faction), ["enemy", "player"])


func test_victory_when_the_last_enemy_falls() -> void:
	var f := soldier("footman", 6, "f")
	f.x = 5; f.y = 5; f.facing = 3
	f.stats.melee = 500
	var g := enemy_f("goblin_spear", "g", 6, 5, 1)
	g.hp = 3
	g.alive = 1
	var b = new_battle([f, g], 1, open_field(46))
	b.phase = "player"
	var xp_before: int = f.xp
	assert_true(b.attack("f", "g"))
	assert_true(b.is_over())
	assert_eq(b.result, "victory")
	var end: Array = events_of(b.drain(), "end")
	assert_eq(end, [{"t": "end", "result": "victory"}])
	# Experience: the kill, then 5 for the victory plus one soldier's share of the damage.
	assert_eq(f.xp, xp_before + DB.UNIT_TYPES.goblin_spear.value + 5 + floori(float(f.damageDealt) / (8 * f.size)))
	# Nothing acts once the battle is over.
	assert_false(b.move("f", 5, 6))


func test_defeat_when_the_company_is_gone_militia_does_not_count() -> void:
	var f := soldier("footman", 6, "f")
	f.x = 5; f.y = 5; f.facing = 3
	f.hp = 2
	f.alive = 1
	var m := soldier("spearman", 5, "s")
	m.tags.append("militia")
	m.x = 1; m.y = 1
	var o := enemy_f("orc_warrior", "o", 5, 9, 1)
	o.x = 5; o.y = 4
	o.stats.melee = 500
	var b = new_battle([f, m, o], 7, open_field(46))
	b.phase = "enemy"
	assert_eq(b.company(), [f])
	assert_true(b.attack("o", "f"))
	assert_true(f.status == "dead" or f.status == "downed")
	assert_eq(m.status, "active")
	assert_eq(b.result, "defeat")
	assert_true(has_event(b.drain(), func(e): return e.t == "end" and e.result == "defeat"))


func test_retreat_costs_free_attacks_and_ends_the_battle() -> void:
	var f := soldier("footman", 6, "f")
	f.x = 5; f.y = 5; f.facing = 3
	var c := soldier("crossbowman", 12, "c")
	c.x = 1; c.y = 10
	var g := enemy_f("goblin_spear", "g", 6, 5, 1)
	g.x = 5; g.y = 4
	var b = new_battle([f, c, g], 4, open_field(46))
	b.phase = "enemy"
	b.retreat()
	assert_false(b.is_over(), "only in the player's turn")
	b.phase = "player"
	var xp_c: int = c.xp
	b.retreat()
	assert_eq([b.phase, b.result], ["over", "retreat"])
	var evs: Array = b.drain()
	var attacks: Array = events_of(evs, "attack")
	assert_eq(attacks.size(), 1, "only the squad in contact is struck as it pulls out")
	assert_eq([attacks[0].uid, attacks[0].target, attacks[0].reaction], ["g", "f", "zoc"])
	assert_eq(c.xp, xp_c + 2)
	assert_eq(evs[evs.size() - 1], {"t": "end", "result": "retreat"})


func test_deploy_swap() -> void:
	var b = _duel()
	b.phase = "deploy"
	var f: Dictionary = b.unit("f")
	var zone: Array = b.map.playerDeploy
	var p: Dictionary = zone[0]
	var q: Dictionary = zone[1]
	assert_true(b.deploy_swap("f", p.x, p.y))
	assert_eq([f.x, f.y], [p.x, p.y])
	# Squads take the field facing the enemy.
	assert_eq(f.facing, Grid.dir_to(f, b.unit("g")))
	var s := soldier("spearman", 5, "s")
	s.x = q.x; s.y = q.y
	b.units.append(s)
	assert_true(b.deploy_swap("s", p.x, p.y))
	assert_eq([s.x, s.y, f.x, f.y], [p.x, p.y, q.x, q.y])
	# Outside the deployment ground, or after the battle began: refused.
	assert_false(b.deploy_swap("s", 0, 0) and not zone.any(func(z): return z.x == 0 and z.y == 0))
	b.phase = "player"
	assert_false(b.deploy_swap("s", q.x, q.y))
