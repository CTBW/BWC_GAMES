## Soldiers, new games, the roster economy and save migration must match the
## original exactly: state after every step of scripted economy runs.
## Golden: tools/parity/meta_golden.ts -> tests/fixtures/golden/meta_golden.json
## (no recorder; its ability lists are read in today's kits, H.current_kits).
extends "res://tests/test_case.gd"

const H = preload("res://tests/parity/test_meta_support.gd")
const Rng = preload("res://scripts/core/rng.gd")
const DB = preload("res://scripts/data/db.gd")
const Soldier = preload("res://scripts/meta/soldier.gd")
const Game = preload("res://scripts/meta/game.gd")

var golden: Dictionary


func before_all() -> void:
	# Recorded before the squad skills: ability lists in today's kits (H.OLD_KITS).
	golden = H.current_kits(H.load_golden("meta_golden.json"))
	_retire_infirmary_survival()


# The Infirmary lost its survival bonus with the wound rule (MIGRATION.md
# 2026-10-26): queries carry no survival effect, and its levels describe
# treatment only. Every other field is compared as recorded.
func _retire_infirmary_survival() -> void:
	var levels: Array = DB.building_by_id("infirmary").levels
	for sc in golden.scripts:
		for st in sc.steps:
			if st.op != "query":
				continue
			st.ret.effects.erase("infirmary.survival")
			for nl in st.ret.nextLevels:
				if nl.id == "infirmary" and nl.next != null:
					nl.next.effects.erase("survival")
					nl.next.description = levels[nl.next.level - 1].description


func _match(actual: Variant, expected: Variant, msg: String) -> bool:
	return assert_eq(H.diff(actual, expected), "", msg)


func test_constants() -> void:
	assert_eq(Game.SAVE_VERSION, golden.SAVE_VERSION)
	assert_eq(Game.ELITE_RECRUIT_CHANCE, golden.ELITE_RECRUIT_CHANCE)


func test_new_soldier_matches() -> void:
	for c in golden.newSoldiers:
		var rng := Rng.new(c.seed)
		var id: String = c.id
		var s := Soldier.new_soldier(rng, c.typeId, c.level, func() -> String: return id, c.cycle)
		_match(s, c.soldier, "newSoldier %s L%d" % [c.typeId, c.level])
		assert_eq(rng.state, c.rngAfter, "rng after newSoldier %s" % c.typeId)


func test_soldier_functions_match() -> void:
	var i := 0
	for c in golden.soldierFns:
		var s: Dictionary = c.soldier.duplicate(true)
		var label := "soldier %d (%s L%d)" % [i, s.typeId, s.level]
		_match(Soldier.soldier_stats(s), c.stats, label + " stats")
		_match(Soldier.weapon_bonus(s), c.weaponBonus, label + " weaponBonus")
		_match(Soldier.soldier_damage(s), c.damage, label + " damage")
		_match(Soldier.command_cost(s), c.commandCost, label + " commandCost")
		_match(Soldier.abilities_of(s), H.current_kit(c.abilities, s.typeId), label + " abilities")
		_match(Soldier.can_promote(s), c.canPromote, label + " canPromote")
		_match(Soldier.xp_to_next(s), c.xpToNext, label + " xpToNext")
		_match(Soldier.squad_max_hp(s), c.maxHp, label + " maxHp")
		_match(Soldier.squad_hp_cap(s), c.hpCap, label + " hpCap")
		_match(Soldier.soldier_to_unit(s), c.unit, label + " unit")
		_match(s, c.soldier, label + " input untouched")
		var healed: Dictionary = c.soldier.duplicate(true)
		_match(Soldier.heal_soldier(healed, c.healAmt), c.healRet, label + " heal return")
		_match(healed, c.healed, label + " healed")
		var settled: Dictionary = c.settledIn.duplicate(true)
		Soldier.settle_men(settled)
		_match(settled, c.settled, label + " settleMen")
		i += 1


func test_make_enemy_matches() -> void:
	for c in golden.enemies:
		var rng := Rng.new(c.seed)
		_match(Soldier.make_enemy(c.typeId, c.level, c.uid, rng), c.unit, "makeEnemy %s L%d" % [c.typeId, c.level])
		assert_eq(rng.state, c.rngAfter, "rng after makeEnemy %s" % c.typeId)


func test_small_functions_match() -> void:
	var m: Dictionary = golden.misc
	for p in m.rankName:
		assert_eq(Soldier.rank_name(p[0]), p[1], "rankName(%d)" % p[0])
	for p in m.levelForXp:
		assert_eq(Soldier.level_for_xp(p[0]), p[1], "levelForXp(%d)" % p[0])
	for p in m.fatigueLabel:
		assert_eq(Soldier.fatigue_label(p[0]), p[1], "fatigueLabel(%d)" % p[0])
	for p in m.numberWord:
		assert_eq(Game.number_word(p[0]), p[1], "numberWord(%d)" % p[0])
	for p in m.recommendedSupplies:
		var a: Array = p[0]
		_match(Game.recommended_supplies(a[0], a[1], a[2], a[3]), p[1], "recommendedSupplies%s" % str(a))
	for p in m.recommendedDefault:
		_match(Game.recommended_supplies(p[0][0], p[0][1]), p[1], "recommendedSupplies default %s" % str(p[0]))
	for p in m.supplyWeight:
		assert_eq(Game.supply_weight(p[0]), p[1], "supplyWeight")


func test_new_game_matches() -> void:
	for c in golden.newGames:
		_match(Game.new_game(c.seed), c.state, "newGame(%d)" % c.seed)


func test_economy_scripts_match() -> void:
	for sc in golden.scripts:
		var g := Game.new_game(sc.seed)
		if not _match(g, sc.start, "script %d start" % sc.seed):
			return
		var n := 0
		for st in sc.steps:
			var ret: Variant = _run(g, st.op, st.args)
			var label := "seed %d step %d %s%s" % [sc.seed, n, st.op, JSON.stringify(st.args)]
			if not _match(ret, st.ret, label + " return"):
				return
			if not _match(g, st.state, label + " state"):
				return
			n += 1
		assert_true(n > 100, "steps replayed")


func test_migrations_match() -> void:
	for c in golden.migrations:
		_match(Game.migrate_save(c.input.duplicate(true)), c.output, "migrateSave old %d" % c.seed)
		_match(Game.migrate_save(c.currentIn.duplicate(true)), c.currentOut, "migrateSave clamp %d" % c.seed)
		_match(Game.migrate_save(c.plain.duplicate(true)), c.plainOut, "migrateSave current %d" % c.seed)


# ---------------------------------------------------------------- replay

func _find(g: Dictionary, id: Variant) -> Variant:
	for s in g.roster:
		if s.id == id:
			return s
	return null


func _run(g: Dictionary, op: String, a: Array) -> Variant:
	match op:
		"setRes":
			g.resources[a[0]] = a[1]
			return null
		"setBuilding":
			g.buildings[a[0]] = a[1]
			return null
		"setSoldier":
			var v: Variant = a[2]
			_find(g, a[0])[a[1]] = v.duplicate(true) if (v is Array or v is Dictionary) else v
			return null
		"hire":
			return Game.hire(g, a[0])
		"dismiss":
			return Game.dismiss(g, a[0])
		"reinforce":
			return Game.reinforce(g, a[0], a[1]) if a.size() > 1 else Game.reinforce(g, a[0])
		"drill":
			return Game.drill(g, a[0])
		"promote":
			return Game.promote(g, a[0])
		"buyEquip":
			return Game.buy_equip(g, a[0], a[1])
		"repair":
			return Game.repair(g, a[0])
		"treat":
			return Game.treat(g, a[0], a[1])
		"grantLeave":
			return Game.grant_leave(g, a[0])
		"upgradeBuilding":
			return Game.upgrade_building(g, a[0])
		"rollRecruits":
			Game.roll_recruits(g)
			return null
		"gainXp":
			return Game.gain_xp(g, _find(g, a[0]), a[1])
		"chronicle":
			Game.chronicle(g, a[0], a[1])
			return null
		"query":
			return _queries(g)
	fail("unknown op " + op)
	return null


func _queries(g: Dictionary) -> Dictionary:
	var c := DB.campaign_by_id("hillsvain_raids")
	var per: Array = []
	for s in g.roster:
		per.append({
			"id": s.id,
			"canReinforce1": Game.can_reinforce(g, s),
			"canReinforce3": Game.can_reinforce(g, s, 3),
			"reinforceCost": Game.reinforce_cost(g, s),
			"missingMen": Game.missing_men(s),
			"drillCost": Game.drill_cost(g, s),
			"canDrill": Game.can_drill(g, s),
			"canPromoteHere": Game.can_promote_here(g, s),
			"canBuyWeapon": Game.can_buy_equip(g, s, "weapon"),
			"canBuyArmor": Game.can_buy_equip(g, s, "armor"),
			"nextWeapon": Game.next_equip(g, s, "weapon"),
			"nextArmor": Game.next_equip(g, s, "armor"),
			"weaponLine": _line_id(Game.equip_line(s, "weapon")),
			"armorLine": _line_id(Game.equip_line(s, "armor")),
			"repairCost": Game.repair_cost(g, s),
			"eligibility": Game.eligibility(g, s, c),
			"commandCost": Soldier.command_cost(s),
			"stats": Soldier.soldier_stats(s),
			"unit": Soldier.soldier_to_unit(s),
		})
	var effects := {}
	for b in DB.BUILDINGS:
		for k in b.levels[0].effects:
			effects["%s.%s" % [b.id, k]] = Game.effect(g, b.id, k)
	var next_levels: Array = []
	for b in DB.BUILDINGS:
		var nl: Variant = Game.next_level(g, b.id)
		next_levels.append({"id": b.id, "level": Game.level(g, b.id), "next": nl, "canAfford": Game.can_afford(g, nl.cost) if nl != null else null})
	var xb := 0
	for s in g.roster:
		if s.typeId == "crossbowman":
			xb += 1
	var rec := Game.recommended_supplies(mini(6, g.roster.size()), xb, Game.wagon_capacity(g), c.stages + 1)
	var recruit_costs: Array = []
	for r in g.recruits:
		recruit_costs.append([r.id, Game.recruit_cost(r)])
	var treat_costs: Array = []
	for k in DB.INJURIES:
		treat_costs.append([k, Game.treat_cost(g, k)])
	var ids: Array = g.roster.map(func(s: Dictionary) -> String: return s.id)
	ids.append("nobody")
	var prices: Array = []
	for k in DB.SUPPLY_ORDER:
		prices.append([k, Game.supply_price(g, k)])
	return {
		"per": per,
		"recruitCosts": recruit_costs,
		"leaveCost": Game.leave_cost(g),
		"promoteCost": Game.promote_cost(g),
		"treatCosts": treat_costs,
		"armyLimits": Game.army_limits(g, c),
		"armyCommand": Game.army_command(g, ids),
		"supplyPrices": prices,
		"wagonCapacity": Game.wagon_capacity(g),
		"rosterCap": Game.roster_cap(g),
		"campaigns": Game.available_campaigns(g).map(func(x: Dictionary) -> String: return x.id),
		"effects": effects,
		"nextLevels": next_levels,
		"recommended": rec,
		"recWeight": Game.supply_weight(rec),
		"recCost": Game.supply_cost_total(g, rec),
	}


func _line_id(line: Variant) -> Variant:
	return line.id if line != null else null


func test_diff_helper_detects_differences() -> void:
	assert_ne(H.diff({"a": 1}, {"a": 2}), "", "value")
	assert_ne(H.diff({"a": 1}, {"a": 1, "b": 0}), "", "missing key")
	assert_eq(H.diff({"a": 1}, {"a": 1, "b": null}), "", "absent == null")
	assert_ne(H.diff([1, 2], [1, 2, 3]), "", "array size")
	assert_eq(H.diff(0.1 + 0.2, 0.30000000000000004), "", "float")
	assert_ne(H.diff(0.1, 0.1000001), "", "float tolerance")
	assert_ne(H.diff("a", "b"), "", "string")
	assert_ne(H.diff(true, 1), "", "bool vs number")
