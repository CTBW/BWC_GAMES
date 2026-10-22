## Port of src/meta/game.ts: the GameState (a Dictionary with the original
## keys), the garrison buildings and the roster economy.
##
## GameState keys: version, seed, rng, nextId, cycle (expeditions launched),
## resources {silver, timber, iron, trophies}, buildings {id: level}, roster,
## recruits (Soldier dictionaries), fallen (FallenRecord), expedition
## (Expedition or null), completed {campaignId: count}, chronicle
## [{cycle, text, tone}], lastReport (ExpeditionReport or null), flags (optional).
## Use through `const Game = preload("res://scripts/meta/game.gd")`.
extends RefCounted

const JS = preload("res://scripts/core/js.gd")
const Rng = preload("res://scripts/core/rng.gd")
const DB = preload("res://scripts/data/db.gd")
const Squad = preload("res://scripts/rules/squad.gd")
const Soldier = preload("res://scripts/meta/soldier.gd")

const SAVE_VERSION := 1

## Chance that a recruit squad is the elite Border Collie Royal Guard (Barracks level 2+).
const ELITE_RECRUIT_CHANCE := 0.22

## Squads that answer the muster one at a time: a circle of battle mages or a war machine and its crew.
const SPECIALIST_TYPES := ["battle_mage", "battle_mage", "ballista", "mangonel"]


## Runs fn(rng) with the game's RNG and stores its state back. Returns fn's result.
static func use_rng(g: Dictionary, fn: Callable) -> Variant:
	var rng := Rng.new(g.rng)
	var out: Variant = fn.call(rng)
	g.rng = rng.state
	return out


## A Callable handing out the game's next soldier id ("u1", "u2", ...).
static func next_id(g: Dictionary) -> Callable:
	return func() -> String:
		var id := "u%d" % g.nextId
		g.nextId += 1
		return id


## A fresh game. The default seed is the clock in milliseconds, as in the original.
static func new_game(seed: Variant = null) -> Dictionary:
	if seed == null:
		seed = int(Time.get_unix_time_from_system() * 1000) % 2147483647
	var buildings := {}
	for b in DB.BUILDINGS:
		buildings[b.id] = 1
	var g := {
		"version": SAVE_VERSION,
		"seed": seed,
		"rng": Rng.new(seed).state,
		"nextId": 1,
		"cycle": 0,
		"resources": {"silver": 220, "timber": 2, "iron": 1, "trophies": 0},
		"buildings": buildings,
		"roster": [],
		"recruits": [],
		"fallen": [],
		"expedition": null,
		"completed": {},
		"chronicle": [],
		"lastReport": null,
	}
	use_rng(g, func(rng: RefCounted) -> void:
		for t in ["footman", "footman", "spearman", "spearman", "crossbowman", "crossbowman"]:
			g.roster.append(Soldier.new_soldier(rng, t, 1, next_id(g), 0))
	)
	roll_recruits(g)
	chronicle(g, "The Amberfeld Company makes camp at the edge of the Hillsvain Woods. Six squads answer the muster.")
	return g


static func _is_num(v: Variant) -> bool:
	return (v is int or v is float) and not is_nan(float(v)) and not is_inf(float(v))


## Bring a loaded save up to the squad rules. Saves from before squads stored one
## soldier's HP and no `men`: each entry becomes a full squad with the same share
## of health. Every save is also clamped so `men` and `hp` stay consistent.
static func migrate_save(g: Dictionary) -> Dictionary:
	var keep := func(s: Variant) -> bool:
		return s is Dictionary and s.get("typeId") is String and DB.UNIT_TYPES.has(s.typeId)
	var roster: Variant = g.get("roster")
	var recruits: Variant = g.get("recruits")
	g.roster = (roster if roster is Array else []).filter(keep)
	g.recruits = (recruits if recruits is Array else []).filter(keep)
	for s in g.roster:
		_fix_soldier(s)
	for s in g.recruits:
		_fix_soldier(s)
	# The marching army is a list of roster ids; drop any that no longer exist.
	var ex: Variant = g.get("expedition")
	if ex is Dictionary:
		var ids := {}
		for s in g.roster:
			ids[s.id] = true
		ex.army = ex.army.filter(func(id: Variant) -> bool: return ids.has(id))
	return g


static func _fix_soldier(s: Dictionary) -> void:
	var size: int = DB.squad_size(s.typeId)
	if not (s.get("injuries") is Array):
		s.injuries = []
	var per: int = Soldier.soldier_stats(s).hp
	if not _is_num(s.get("men")):
		s.men = size
		var hp0: Variant = s.get("hp")
		var old: float = float(hp0) if _is_num(hp0) and hp0 > 0 else float(per)
		s.hp = JS.rnd(minf(old * s.men, float(per * s.men)))
	s.men = maxi(1, mini(size, JS.rnd(float(s.men))))
	if not _is_num(s.get("hp")) or s.hp <= 0:
		s.hp = per * s.men
	s.hp = maxi(1, mini(JS.rnd(float(s.hp)), Soldier.squad_hp_cap(s)))


static func chronicle(g: Dictionary, text: String, tone: String = "neutral") -> void:
	g.chronicle.push_front({"cycle": g.cycle, "text": text, "tone": tone})
	if g.chronicle.size() > 60:
		g.chronicle.resize(60)


# ---------------------------------------------------------------- saves (Godot side)

## The save text: the GameState as JSON, like the original's localStorage save.
## Keys keep their order, floats keep full precision and integral values are
## written as integers (as JavaScript writes them).
static func to_save_json(g: Dictionary) -> String:
	return JSON.stringify(JS.normalize(g), "", false, true)


## Parses a save written by to_save_json (or the original game). Returns the
## migrated GameState, or null when the text is not a save of this version.
static func from_save_json(text: String) -> Variant:
	var parsed: Variant = parse_json_exact(text)
	if not (parsed is Dictionary):
		return null
	var g: Dictionary = JS.normalize(parsed)
	if g.get("version") != SAVE_VERSION:
		return null
	return migrate_save(g)


## JSON.parse with every number read back as exactly the double that was
## written. (Godot's parser can land one ulp off on 17-digit values such as
## 0.44999999999999996; both JavaScript and Godot write the shortest form that
## identifies a double, so the neighbour whose shortest form is the token is the
## right one.) Returns null on a parse error, without logging one.
static func parse_json_exact(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	var data: Variant = json.data
	var tokens := _number_tokens(text)
	if _count_numbers(data) != tokens.size():
		return data
	var pos := [0]
	return _fix_numbers(data, tokens, pos)


## The number tokens of a JSON text, in order (strings skipped).
static func _number_tokens(text: String) -> Array:
	var bytes := text.to_utf8_buffer()
	var out: Array = []
	var n := bytes.size()
	var i := 0
	while i < n:
		var c := bytes[i]
		if c == 34:
			i += 1
			while i < n and bytes[i] != 34:
				i += 2 if bytes[i] == 92 else 1
			i += 1
		elif c == 45 or (c >= 48 and c <= 57):
			var j := i + 1
			while j < n:
				var d := bytes[j]
				if (d >= 48 and d <= 57) or d == 46 or d == 101 or d == 69 or d == 43 or d == 45:
					j += 1
				else:
					break
			out.append(bytes.slice(i, j).get_string_from_ascii())
			i = j
		else:
			i += 1
	return out


static func _count_numbers(v: Variant) -> int:
	if v is float or v is int:
		return 1
	var n := 0
	if v is Array:
		for x in v:
			n += _count_numbers(x)
	elif v is Dictionary:
		for k in v:
			n += _count_numbers(v[k])
	return n


static func _fix_numbers(v: Variant, tokens: Array, pos: Array) -> Variant:
	if v is float or v is int:
		var t: String = tokens[pos[0]]
		pos[0] += 1
		return _exact_double(float(v), t)
	if v is Array:
		for i in v.size():
			v[i] = _fix_numbers(v[i], tokens, pos)
	elif v is Dictionary:
		for k in v:
			v[k] = _fix_numbers(v[k], tokens, pos)
	return v


static func _exact_double(f: float, token: String) -> float:
	if not (token.contains(".") or token.contains("e") or token.contains("E")):
		return f
	if JSON.stringify(f, "", false, true) == token:
		return f
	var b := PackedByteArray()
	b.resize(8)
	for delta in [1, -1, 2, -2]:
		b.encode_double(0, f)
		b.encode_s64(0, b.decode_s64(0) + delta)
		var c := b.decode_double(0)
		if JSON.stringify(c, "", false, true) == token:
			return c
	return f


# ---------------------------------------------------------------- buildings

static func level(g: Dictionary, id: String) -> int:
	return JS.get_or(g.buildings, id, 1)


static func effect(g: Dictionary, id: String, key: String) -> Variant:
	var b := DB.building_by_id(id)
	return JS.get_or(b.levels[level(g, id) - 1].effects, key, 0)


## The building's next level (a BuildingLevel dictionary), or null at the top.
static func next_level(g: Dictionary, id: String) -> Variant:
	var b := DB.building_by_id(id)
	var i := level(g, id)
	return b.levels[i] if i < b.levels.size() else null


static func can_afford(g: Dictionary, cost: Dictionary) -> bool:
	for k in cost:
		if g.resources[k] < JS.get_or(cost, k, 0):
			return false
	return true


static func pay(g: Dictionary, cost: Dictionary) -> void:
	for k in cost:
		g.resources[k] -= JS.get_or(cost, k, 0)


static func upgrade_building(g: Dictionary, id: String) -> bool:
	var nl: Variant = next_level(g, id)
	if nl == null or not can_afford(g, nl.cost):
		return false
	pay(g, nl.cost)
	g.buildings[id] = nl.level
	chronicle(g, "The %s is rebuilt as the %s." % [String(DB.building_by_id(id).name).to_lower(), nl.name], "good")
	return true


# ---------------------------------------------------------------- recruits

static func roll_recruits(g: Dictionary) -> void:
	var pool: int = effect(g, "barracks", "pool")
	var vet: float = effect(g, "barracks", "veteranChance")
	var elite := level(g, "barracks") >= 2
	g.recruits = use_rng(g, func(rng: RefCounted) -> Array:
		var out: Array = []
		for i in pool:
			var t: String = "collie_guard" if elite and rng.chance(ELITE_RECRUIT_CHANCE) else rng.pick(DB.PLAYER_TYPES)
			var lvl := 1
			if rng.chance(vet):
				lvl = 3 if rng.chance(vet * 0.4) else 2
			out.append(Soldier.new_soldier(rng, t, lvl, next_id(g), g.cycle))
		# One specialist squad is on offer each cycle as well.
		var spec: String = rng.pick(SPECIALIST_TYPES)
		out.append(Soldier.new_soldier(rng, spec, 2 if rng.chance(vet) else 1, next_id(g), g.cycle))
		# A thin company draws volunteers from the steadings: one joins for free.
		if g.roster.size() < 6:
			var v := Soldier.new_soldier(rng, "spearman", 1, next_id(g), g.cycle)
			v.volunteer = true
			out.push_front(v)
		return out
	)


static func recruit_cost(s: Dictionary) -> int:
	if s.get("volunteer"):
		return 0
	return JS.rnd(DB.UNIT_TYPES[s.typeId].recruitCost * (1 + (s.level - 1) * 0.6))


static func roster_cap(g: Dictionary) -> int:
	return effect(g, "barracks", "rosterCap")


static func _find(list: Array, id: Variant) -> Variant:
	for s in list:
		if s.id == id:
			return s
	return null


static func hire(g: Dictionary, id: String) -> bool:
	var s: Variant = _find(g.recruits, id)
	if s == null:
		return false
	var cost := recruit_cost(s)
	if g.resources.silver < cost or g.roster.size() >= roster_cap(g):
		return false
	g.resources.silver -= cost
	g.recruits = g.recruits.filter(func(r: Dictionary) -> bool: return r.id != id)
	g.roster.append(s)
	chronicle(g, "%s signs on with %s %s." % [s.name, number_word(s.men), String(DB.UNIT_TYPES[s.typeId].plural).to_lower()])
	return true


static func dismiss(g: Dictionary, id: String) -> bool:
	var s: Variant = _find(g.roster, id)
	if s == null or g.roster.size() <= 1:
		return false
	g.roster = g.roster.filter(func(r: Dictionary) -> bool: return r.id != id)
	chronicle(g, "%s are discharged from the company." % Squad.squad_name(s))
	return true


# ---------------------------------------------------------------- reinforcements

const _NUMBER_WORDS := ["no", "one", "two", "three", "four", "five", "six", "seven", "eight"]


static func number_word(n: int) -> String:
	return _NUMBER_WORDS[n] if n >= 0 and n < _NUMBER_WORDS.size() else str(n)


## Soldiers a squad is short of full strength.
static func missing_men(s: Dictionary) -> int:
	return maxi(0, DB.squad_size(s.typeId) - s.men)


## Silver for one replacement soldier: a share of the squad's hiring price,
## a little more for seasoned squads (the newcomer is drilled up to their rank).
static func reinforce_cost(_g: Dictionary, s: Dictionary) -> int:
	var def: Dictionary = DB.UNIT_TYPES[s.typeId]
	return ceili(float(def.recruitCost) / DB.squad_size(s.typeId) * 0.8 * (1 + (s.level - 1) * 0.25))


## {ok, reason?}
static func can_reinforce(g: Dictionary, s: Dictionary, count: int = 1) -> Dictionary:
	if g.expedition != null:
		return {"ok": false, "reason": "Only at the Barracks, between expeditions"}
	var missing := missing_men(s)
	if missing <= 0:
		return {"ok": false, "reason": "The squad is at full strength"}
	var n := mini(count, missing)
	var cost := reinforce_cost(g, s) * n
	if g.resources.silver < cost:
		return {"ok": false, "reason": "Needs %d silver" % cost}
	return {"ok": true}


## Fill a squad's empty places (one soldier by default; `count` for more). New
## soldiers arrive fit, each with a full share of HP. The only way to raise `men`.
static func reinforce(g: Dictionary, id: String, count: int = 1) -> bool:
	var s: Variant = _find(g.roster, id)
	if s == null or not can_reinforce(g, s, count).ok:
		return false
	var n := mini(count, missing_men(s))
	var per: int = Soldier.soldier_stats(s).hp
	g.resources.silver -= reinforce_cost(g, s) * n
	s.men += n
	s.hp = mini(Soldier.squad_hp_cap(s), s.hp + per * n)
	var def: Dictionary = DB.UNIT_TYPES[s.typeId]
	var who: String
	if n == 1:
		who = "A new %s joins" % String(def.name).to_lower()
	else:
		var w := number_word(n)
		who = "%s%s new %s join" % [w.substr(0, 1).to_upper(), w.substr(1), String(def.plural).to_lower()]
	chronicle(g, "%s %s's squad (%d/%d)." % [who, s.name, s.men, DB.squad_size(s.typeId)])
	return true


# ---------------------------------------------------------------- training

static func drill_cost(g: Dictionary, s: Dictionary) -> int:
	return effect(g, "training", "drillCost") + (s.level - 1) * 15


static func can_drill(g: Dictionary, s: Dictionary) -> Dictionary:
	if s.get("drilled"):
		return {"ok": false, "reason": "Already drilled this cycle"}
	if s.level >= effect(g, "training", "drillMaxLevel"):
		return {"ok": false, "reason": "Yard cannot teach this rank"}
	if g.resources.silver < drill_cost(g, s):
		return {"ok": false, "reason": "Not enough silver"}
	return {"ok": true}


static func drill(g: Dictionary, id: String) -> bool:
	var s: Variant = _find(g.roster, id)
	if s == null or not can_drill(g, s).ok:
		return false
	g.resources.silver -= drill_cost(g, s)
	s.drilled = true
	gain_xp(g, s, 10)
	return true


## Adds XP; returns the level-up message, or null.
static func gain_xp(g: Dictionary, s: Dictionary, xp: int) -> Variant:
	var before: int = s.level
	s.xp += xp
	var lvl := Soldier.level_for_xp(s.xp)
	if lvl > before:
		var old := Soldier.soldier_stats(s)
		s.level = lvl
		var now := Soldier.soldier_stats(s)
		# Every soldier still serving gains the new rank's toughness.
		s.hp = mini(Soldier.squad_hp_cap(s), s.hp + (now.hp - old.hp) * s.men)
		s.morale = mini(now.morale, s.morale + (now.morale - old.morale))
		var msg := "%s rise to %s." % [Squad.squad_name(s), _rank_label(lvl)]
		chronicle(g, msg, "good")
		return msg
	return null


static func _rank_label(lvl: int) -> String:
	var labels := ["Recruit", "Soldier", "Veteran", "Sergeant", "Champion"]
	return labels[lvl - 1] if lvl >= 1 and lvl <= labels.size() else "undefined"


static func promote_cost(g: Dictionary) -> Dictionary:
	return {"silver": effect(g, "training", "promoteCost"), "iron": 1}


static func can_promote_here(g: Dictionary, s: Dictionary) -> Dictionary:
	if not Soldier.can_promote(s):
		return {"ok": false, "reason": "Already promoted" if s.promoted else "Needs Veteran rank"}
	if not effect(g, "training", "promote"):
		return {"ok": false, "reason": "Needs Training Yard level 2"}
	if not can_afford(g, promote_cost(g)):
		return {"ok": false, "reason": "Cannot afford"}
	return {"ok": true}


static func promote(g: Dictionary, id: String) -> bool:
	var s: Variant = _find(g.roster, id)
	if s == null or not can_promote_here(g, s).ok:
		return false
	pay(g, promote_cost(g))
	s.promoted = true
	chronicle(g, "%s are promoted and learn a new skill." % Squad.squad_name(s), "good")
	return true


# ---------------------------------------------------------------- armoury

## The squad's equipment line for a slot ("weapon" | "armor"), or null.
static func equip_line(s: Dictionary, slot: String) -> Variant:
	var def: Dictionary = DB.UNIT_TYPES[s.typeId]
	var line_id: Variant = def.get("weaponLine") if slot == "weapon" else def.get("armorLine")
	return DB.EQUIPMENT.get(line_id) if line_id != null else null


## The next tier the armoury could issue, or null.
static func next_equip(_g: Dictionary, s: Dictionary, slot: String) -> Variant:
	var line: Variant = equip_line(s, slot)
	var cur: int = s.weaponTier if slot == "weapon" else s.armorTier
	if line == null or cur < 0 or cur >= line.tiers.size():
		return null
	return line.tiers[cur]


static func can_buy_equip(g: Dictionary, s: Dictionary, slot: String) -> Dictionary:
	var nxt: Variant = next_equip(g, s, slot)
	if nxt == null:
		return {"ok": false, "reason": "Best available"}
	if effect(g, "armoury", "tier") < nxt.tier:
		return {"ok": false, "reason": "Needs Armoury level %s" % JS.num_str(nxt.armoryLevel)}
	if not can_afford(g, nxt.cost):
		return {"ok": false, "reason": "Cannot afford"}
	return {"ok": true}


static func buy_equip(g: Dictionary, id: String, slot: String) -> bool:
	var s: Variant = _find(g.roster, id)
	if s == null or not can_buy_equip(g, s, slot).ok:
		return false
	var nxt: Dictionary = next_equip(g, s, slot)
	pay(g, nxt.cost)
	var was_full: bool = s.hp >= Soldier.squad_hp_cap(s)
	if slot == "weapon":
		s.weaponTier += 1
	else:
		s.armorTier += 1
		s.armorCondition = 1
	# Armour that adds toughness tops up a squad resting at full health.
	if was_full:
		s.hp = Soldier.squad_hp_cap(s)
	var nm: String = nxt.name
	var many: String = ("coats" + nm.substr(4)) if nm.to_lower().begins_with("coat of ") else nm + "s"
	chronicle(g, "%s are issued %s." % [Squad.squad_name(s), many.to_lower()])
	return true


static func repair_cost(g: Dictionary, s: Dictionary) -> int:
	return ceili((1 - float(s.armorCondition)) * 60 * effect(g, "armoury", "repairCost"))


static func repair(g: Dictionary, id: String) -> bool:
	var s: Variant = _find(g.roster, id)
	if s == null:
		return false
	var c := repair_cost(g, s)
	if c <= 0 or g.resources.silver < c:
		return false
	g.resources.silver -= c
	s.armorCondition = 1
	return true


# ---------------------------------------------------------------- infirmary / leave

static func treat_cost(g: Dictionary, injury_id: String) -> int:
	return effect(g, "infirmary", "treatCost") * DB.INJURIES[injury_id].severity


static func treat(g: Dictionary, id: String, injury_id: String) -> bool:
	var s: Variant = _find(g.roster, id)
	if s == null:
		return false
	var c := treat_cost(g, injury_id)
	if not s.injuries.has(injury_id) or g.resources.silver < c:
		return false
	g.resources.silver -= c
	var was_full: bool = s.hp >= Soldier.squad_hp_cap(s)
	s.injuries = s.injuries.filter(func(x: Variant) -> bool: return x != injury_id)
	if was_full:
		s.hp = Soldier.squad_hp_cap(s)
	s.recovering = true
	chronicle(g, "The surgeons treat %s's %s." % [s.name, String(DB.INJURIES[injury_id].name).to_lower()])
	return true


static func leave_cost(g: Dictionary) -> int:
	return effect(g, "barracks", "leaveCost")


static func grant_leave(g: Dictionary, id: String) -> bool:
	var s: Variant = _find(g.roster, id)
	if s == null:
		return false
	var mx: int = Soldier.soldier_stats(s).morale
	if s.morale >= mx or g.resources.silver < leave_cost(g):
		return false
	g.resources.silver -= leave_cost(g)
	s.morale = mx
	s.recovering = true
	return true


# ---------------------------------------------------------------- expedition limits

## {slots, command} for an expedition of campaign `c` (a CampaignDef dictionary).
static func army_limits(g: Dictionary, c: Dictionary) -> Dictionary:
	return {
		"slots": c.unitSlots + effect(g, "command", "slotBonus"),
		"command": c.commandPoints + effect(g, "command", "commandBonus"),
	}


## {ok, reluctant, reason?}
static func eligibility(_g: Dictionary, s: Dictionary, c: Dictionary) -> Dictionary:
	if s.get("recovering"):
		return {"ok": false, "reluctant": false, "reason": "Recovering"}
	if s.level > c.refuseAbove:
		return {"ok": false, "reluctant": false, "reason": "Refuses: beneath a %s" % _rank_label(s.level)}
	var st := Soldier.soldier_stats(s)
	if s.morale < st.morale * 0.2:
		return {"ok": false, "reluctant": false, "reason": "Morale broken"}
	return {"ok": true, "reluctant": s.level > c.reluctantAbove}


static func army_command(g: Dictionary, ids: Array) -> int:
	var sum := 0
	for id in ids:
		var s: Variant = _find(g.roster, id)
		if s != null:
			sum += Soldier.command_cost(s)
	return sum


static func supply_price(g: Dictionary, id: String) -> int:
	return maxi(1, JS.rnd(DB.SUPPLIES[id].cost * effect(g, "quartermaster", "priceMult")))


static func wagon_capacity(g: Dictionary) -> int:
	return effect(g, "quartermaster", "capacity")


static func supply_weight(supplies: Dictionary) -> int:
	var s := 0
	for k in supplies:
		s += JS.get_or(supplies, k, 0) * DB.SUPPLIES[k].weight
	return s


static func supply_cost_total(g: Dictionary, supplies: Dictionary) -> int:
	var s := 0
	for k in supplies:
		s += JS.get_or(supplies, k, 0) * supply_price(g, k)
	return s


## CampaignDef dictionaries the command tent can plan.
static func available_campaigns(g: Dictionary) -> Array:
	var out: Array = []
	for id in ["hillsvain_raids"]:
		var c := DB.campaign_by_id(id)
		if level(g, "command") >= c.requiresCommandLevel:
			out.append(c)
	return out


## The quartermaster's advice: rations for every march plus one camp meal,
## then trimmed until it fits the wagon. Marches = campaign stages + 1.
static func recommended_supplies(army_size: int, crossbows: int, capacity: int = 30, marches: int = 6) -> Dictionary:
	var half: int = ceili(army_size / 2.0)
	var sup := {
		"rations": half * marches + army_size,
		"bandages": 3,
		"bolts": maxi(0, crossbows * 2),
		"torches": 2,
		"tools": 1,
	}
	var trim := ["torches", "bandages", "bolts", "tools", "rations"]
	var guard := 0
	while supply_weight(sup) > capacity and guard < 200:
		guard += 1
		var k: Variant = null
		for t in trim:
			var floor_v: int = half * marches if t == "rations" else (1 if t == "torches" or t == "bandages" else 0)
			if sup[t] > floor_v:
				k = t
				break
		if k == null:
			break
		sup[k] -= 1
	return sup
