## Port of src/meta/soldier.ts.
##
## A squad in the company roster, known by its sergeant's name. Persists between
## expeditions. `hp` is the squad's shared pool; `men` are the soldiers still
## serving. Healing refills their shares but never brings the dead back; only
## reinforcements raise `men`.
##
## A Soldier is a Dictionary with the original keys: id, name, typeId, level, xp,
## hp, men, morale, fatigue, injuries, weaponTier, armorTier, armorCondition
## (0..1 multiplier on armour), promoted, ammo, portrait, variant, kills, battles,
## expeditions, recruitedOn, and the optional recovering / drilled / volunteer.
## Use through `const Soldier = preload("res://scripts/meta/soldier.gd")`.
extends RefCounted

const JS = preload("res://scripts/core/js.gd")
const DB = preload("res://scripts/data/db.gd")
const Squad = preload("res://scripts/rules/squad.gd")


static func rank_name(level: int) -> String:
	return DB.RANKS[maxi(0, mini(DB.RANKS.size() - 1, level - 1))]


static func level_for_xp(xp: Variant) -> int:
	var lvl := 1
	for i in DB.XP_LEVELS.size():
		if xp >= DB.XP_LEVELS[i]:
			lvl = i + 1
	return mini(DB.MAX_LEVEL, lvl)


## {have, need} toward the next rank, or null at the top rank.
static func xp_to_next(s: Dictionary) -> Variant:
	if s.level >= DB.MAX_LEVEL:
		return null
	var base: int = DB.XP_LEVELS[s.level - 1]
	return {"have": s.xp - base, "need": DB.XP_LEVELS[s.level] - base}


static func can_promote(s: Dictionary) -> bool:
	return not s.promoted and s.level >= DB.PROMOTION_LEVEL and JS.get_or(DB.UNIT_TYPES[s.typeId], "promotion", "") != ""


## Adds b's stats to a copy of a. (The original also added b's non-stat keys,
## such as a weapon's `damage` bonus, producing an unused NaN `stats.damage`;
## such keys are skipped here.)
static func _add_stats(a: Dictionary, b: Dictionary, mult: Variant = 1) -> Dictionary:
	var out := a.duplicate()
	for k in b:
		if not out.has(k):
			continue
		out[k] += JS.get_or(b, k, 0) * mult
	return out


static func _tier(line_id: Variant, tier: Variant) -> Variant:
	if line_id == null or not DB.EQUIPMENT.has(line_id):
		return null
	var tiers: Array = DB.EQUIPMENT[line_id].tiers
	var i: int = int(tier) - 1
	if i < 0 or i >= tiers.size():
		return null
	return tiers[i]


## Full-health stats including level, equipment and lasting injuries.
static func soldier_stats(s: Dictionary) -> Dictionary:
	var def: Dictionary = DB.UNIT_TYPES[s.typeId]
	var st := _add_stats(def.base, def.perLevel, s.level - 1)
	var weapon: Variant = _tier(def.get("weaponLine"), s.weaponTier)
	var armor: Variant = _tier(def.get("armorLine"), s.armorTier)
	if weapon != null:
		st = _add_stats(st, weapon.bonus)
	if armor != null:
		st = _add_stats(st, armor.bonus)
	for id in s.injuries:
		st = _add_stats(st, DB.INJURIES[id].effect)
	st.move = max(2, st.move)
	st.hp = max(8, st.hp)
	st.morale = max(20, st.morale)
	return st


static func weapon_bonus(s: Dictionary) -> int:
	var def: Dictionary = DB.UNIT_TYPES[s.typeId]
	var weapon: Variant = _tier(def.get("weaponLine"), s.weaponTier)
	if weapon == null:
		return 0
	return JS.get_or(weapon.bonus, "damage", 0)


## {melee: [min, max], shot?: [min, max]}.
static func soldier_damage(s: Dictionary) -> Dictionary:
	var def: Dictionary = DB.UNIT_TYPES[s.typeId]
	var wb := weapon_bonus(s)
	if def.get("shot") != null:
		return {"melee": def.melee.duplicate(), "shot": [def.shot.damage[0] + wb, def.shot.damage[1] + wb]}
	return {"melee": [def.melee[0] + wb, def.melee[1] + wb]}


static func command_cost(s: Dictionary) -> int:
	return DB.UNIT_TYPES[s.typeId].commandCost + DB.LEVEL_COMMAND_SURCHARGE[s.level]


static func abilities_of(s: Dictionary) -> Array:
	var def: Dictionary = DB.UNIT_TYPES[s.typeId]
	var out: Array = def.abilities.duplicate()
	if s.promoted and def.get("promotion") != null:
		out.append(def.promotion)
	return out


static func fatigue_label(f: Variant) -> String:
	if f >= 85:
		return "Exhausted"
	if f >= 60:
		return "Tired"
	if f >= 30:
		return "Weary"
	return "Fresh"


## A new full-strength squad. `next_id` is a Callable returning the next id
## (Game.next_id(g) in the meta game).
static func new_soldier(rng: RefCounted, type_id: String, level: int, next_id: Callable, cycle: int) -> Dictionary:
	var def: Dictionary = DB.UNIT_TYPES[type_id]
	var s := {}
	s.id = next_id.call()
	var first: String = rng.pick(DB.FIRST_NAMES)
	var sur: String = rng.pick(DB.SURNAMES)
	s.name = "%s %s" % [first, sur]
	s.typeId = type_id
	s.level = level
	s.xp = DB.XP_LEVELS[level - 1]
	s.hp = 0
	s.men = DB.squad_size(type_id)
	s.morale = 0
	s.fatigue = 0
	s.injuries = []
	s.weaponTier = 1
	s.armorTier = 1
	s.armorCondition = 1
	s.promoted = false
	var shot: Variant = def.get("shot")
	s.ammo = JS.get_or(shot, "ammo", 0) if shot != null else 0
	s.portrait = rng.rint(0, 5)
	s.variant = rng.rint(0, 2)
	s.kills = 0
	s.battles = 0
	s.expeditions = 0
	s.recruitedOn = cycle
	var st := soldier_stats(s)
	s.men = DB.squad_size(type_id)
	s.hp = st.hp * s.men
	s.morale = st.morale
	return s


## Full-strength HP of the squad (every soldier present and unhurt).
static func squad_max_hp(s: Dictionary) -> int:
	return soldier_stats(s).hp * DB.squad_size(s.typeId)


## Most HP the squad can heal to: one full share per soldier still serving.
static func squad_hp_cap(s: Dictionary) -> int:
	return soldier_stats(s).hp * s.men


## Heal a squad's survivors (never raises the dead). Returns HP restored.
static func heal_soldier(s: Dictionary, amount: float) -> int:
	var before: int = s.hp
	s.hp = maxi(s.hp, mini(squad_hp_cap(s), s.hp + JS.rnd(amount)))
	return s.hp - before


## Keep `men` consistent with the HP pool after damage outside battle.
static func settle_men(s: Dictionary) -> void:
	s.men = maxi(1, Squad.alive_for(s.hp, soldier_stats(s).hp, s.men))
	s.hp = maxi(1, mini(s.hp, squad_hp_cap(s)))


## Battle-ready copy of a soldier, including fatigue penalties.
static func soldier_to_unit(s: Dictionary) -> Dictionary:
	var def: Dictionary = DB.UNIT_TYPES[s.typeId]
	var st := soldier_stats(s)
	var dmg := soldier_damage(s)
	var eff := st.duplicate()
	eff.armor = st.armor * s.armorCondition
	if s.fatigue >= 60:
		eff.melee -= 5
		eff.ranged -= 5
	if s.fatigue >= 85:
		eff.melee -= 5
		eff.ranged -= 5
		eff.move = max(2, eff.move - 1)
	# The squad marches out with the soldiers its HP can carry.
	var size: int = DB.squad_size(s.typeId)
	var men: int = maxi(1, mini(size, JS.get_or(s, "men", size)))
	var hp: int = maxi(1, mini(s.hp, st.hp * men))
	var u := {
		"uid": "p-%s" % s.id,
		"soldierId": s.id,
		"typeId": s.typeId,
		"faction": "player",
		"name": s.name,
		"level": s.level,
		"x": 0,
		"y": 0,
		"facing": 3,
		"hp": hp,
		"maxHp": st.hp * size,
		"size": size,
		"alive": Squad.alive_for(hp, st.hp, men),
		"hpPer": st.hp,
		"morale": maxi(1, mini(s.morale, st.morale)),
		"maxMorale": st.morale,
		"stats": eff,
		"melee": dmg.melee,
		"meleePierce": JS.get_or(def, "meleePierce", 0),
	}
	var shot: Variant = def.get("shot")
	if shot != null and dmg.get("shot") != null:
		u.shot = {"damage": dmg.shot, "range": shot.range, "minRange": JS.get_or(shot, "minRange", 2), "pierce": shot.pierce}
	# Only crossbows draw on the bolt supply; arcane bolts and ballista bolts never run out.
	u.ammo = s.ammo if shot != null and shot.get("ammo") != null else -1
	u.shieldFront = JS.get_or(def, "shieldFront", 0)
	u.abilities = abilities_of(s)
	u.cooldowns = {}
	u.hasMoved = false
	u.hasActed = false
	u.movedTiles = 0
	u.done = false
	u.status = "active"
	u.kills = 0
	u.damageDealt = 0
	u.xp = 0
	u.leader = false
	u.tags = JS.get_or(def, "tags", []).duplicate()
	u.variant = s.variant
	u.struck = []
	u.startMorale = s.morale
	u.statuses = []
	return u


static func make_enemy(type_id: String, level: int, uid: String, rng: RefCounted) -> Dictionary:
	var def: Dictionary = DB.UNIT_TYPES[type_id]
	var st := _add_stats(def.base, def.perLevel, level - 1)
	var leader: bool = JS.get_or(def, "leader", false)
	var name: String
	if leader:
		name = rng.pick(DB.WARLORD_NAMES)
	elif type_id.begins_with("orc"):
		name = rng.pick(DB.ORC_NAMES)
	else:
		name = rng.pick(DB.GOBLIN_NAMES)
	var size: int = DB.squad_size(type_id)
	var u := {
		"uid": uid,
		"typeId": type_id,
		"faction": "enemy",
		"name": name if leader else "%s, %s" % [name, String(def.name).to_lower()],
		"level": level,
		"x": 0,
		"y": 0,
		"facing": 1,
		"hp": st.hp * size,
		"maxHp": st.hp * size,
		"size": size,
		"alive": size,
		"hpPer": st.hp,
		"morale": st.morale,
		"maxMorale": st.morale,
		"stats": st,
		"melee": def.melee.duplicate(),
		"meleePierce": JS.get_or(def, "meleePierce", 0),
	}
	var shot: Variant = def.get("shot")
	if shot != null:
		u.shot = {"damage": shot.damage.duplicate(), "range": shot.range, "minRange": JS.get_or(shot, "minRange", 2), "pierce": shot.pierce}
	u.ammo = -1
	u.shieldFront = JS.get_or(def, "shieldFront", 0)
	u.abilities = def.abilities.duplicate()
	u.cooldowns = {}
	u.hasMoved = false
	u.hasActed = false
	u.movedTiles = 0
	u.done = false
	u.status = "active"
	u.kills = 0
	u.damageDealt = 0
	u.xp = 0
	u.leader = leader
	u.tags = JS.get_or(def, "tags", []).duplicate()
	u.variant = rng.rint(0, 2)
	u.struck = []
	u.startMorale = st.morale
	u.statuses = []
	return u
