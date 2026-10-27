## What the unit bar shows of a squad in battle (Godot only): the rules unit
## (`view.b`), what the screen shows of it so far (`view.views`, playback runs
## behind the rules) and the company's records (the store's `game`: the
## soldier's gear, fatigue and injuries), read into the plain dictionaries the
## bar's pieces take. It only reads. Its commands call the battle view's own
## methods (set_ability, redo, select_next, end_unit), enabled exactly as the
## old squad card's buttons were (hud_battle_panels.gd `_ability_button`).
##
##   const BarData = preload("res://scripts/ui/unit_bar/bar_data.gd")
##   var d := BarData.squad(view, u, store)   # u: a rules unit; store: App or a stand-in (may be null)
##   d.stats / d.effects / d.men / d.items / d.commands     the pieces' data
## Keys: uid, faction, type_id, variant, name, type_label, level, rank, hp,
## hp_max, morale, morale_max, morale_state, morale_label, alive, size,
## members ("Soldiers" | "Casters" | "Crew"), turn {mine, moved, acted},
## figure (the man the portrait shows, or null), plus the five lists.
extends RefCounted

const UI = preload("res://scripts/ui/ui.gd")
const JS = preload("res://scripts/core/js.gd")
const DB = preload("res://scripts/data/db.gd")
const Icon = preload("res://scripts/ui/widgets/icon.gd")
const Panels = preload("res://scripts/ui/hud_battle_panels.gd")
const Squad = preload("res://scripts/rules/squad.gd")

const MORALE_LABEL := Panels.MORALE_LABEL
const COMMANDS := 12
## The command card's fixed places (4×3; the abilities fill the top row).
const SLOT_REDO := 8
const SLOT_NEXT := 10
const SLOT_DONE := 11
const TIER_RARITY := ["common", "uncommon", "rare", "epic"]
const STAT_NAME := {"hp": "HP", "morale": "morale", "melee": "melee skill", "ranged": "ranged skill", "defense": "defense",
	"rangedDefense": "defense against missiles", "armor": "armour", "move": "move", "damage": "damage"}


static func squad(view: Object, u: Dictionary, store: Object = null) -> Dictionary:
	var b = view.b
	var v = _view_of(view, u.uid)
	var def: Dictionary = DB.UNIT_TYPES.get(u.typeId, {})
	var caster: bool = (u.get("tags", []) as Array).has("caster")
	var n: int = maxi(0, int(v.alive if v != null else u.alive))
	var hp: float = maxf(0.0, float(v.hp if v != null else u.hp))
	var morale: float = maxf(0.0, float(v.morale if v != null else u.morale))
	var ms: String = b.morale_state(u)
	var mine: bool = u.faction == "player"
	var d := {
		"uid": u.uid,
		"faction": u.faction,
		"type_id": u.typeId,
		"variant": int(u.get("variant", 0)),
		"name": str(u.name),
		"type_label": UI.squad_type_label(u.typeId, int(u.get("level", 0)), true),
		"level": int(u.get("level", 0)),
		"rank": UI.rank_name(int(u.get("level", 1))) if u.get("level") else "",
		"hp": hp,
		"hp_max": float(u.maxHp),
		"morale": morale,
		"morale_max": float(u.maxMorale),
		"morale_state": ms,
		"morale_label": MORALE_LABEL.get(ms, ms),
		"alive": n,
		"size": int(u.size),
		"members": "Crew" if def.has("crew") else ("Casters" if caster else "Soldiers"),
		"turn": {"mine": mine and b.phase in ["player", "deploy"], "moved": bool(u.hasMoved), "acted": bool(u.hasActed)},
		"hidden": not view.squad_visible(v) if v != null and view.has_method("squad_visible") else false,
	}
	var s: Variant = soldier_of(u, store)
	d.stats = stats(u, s, n)
	d.effects = effects(u, v, s, ms)
	d.men = men(u, v, n, hp, d.hidden)
	d.figure = null
	for m in d.men:
		if m.alive and m.get("figure") != null:
			d.figure = m.figure
			break
	d.items = items(u, s)
	d.commands = commands(view, u, ms)
	return d


static func _view_of(view: Object, uid: Variant) -> Variant:
	var vs: Variant = view.get("views")
	return vs.get(uid) if vs is Dictionary else null


## The company's record of the squad (its soldier, by `soldierId`), or null.
static func soldier_of(u: Dictionary, store: Object) -> Variant:
	if u.get("soldierId") == null or store == null:
		return null
	var g: Variant = store.get("game")
	if not g is Dictionary:
		return null
	for s in g.get("roster", []):
		if s.get("id") == u.soldierId:
			return s
	return null


static func _num(x: Variant) -> String:
	return JS.num_str(x)


## A modifier's size without a needless ".0" ("4", "0.5").
static func _short(x: float) -> String:
	return JS.to_fixed(x, 1).trim_suffix(".0")


## "3–5 × 3 = 9–15": per man, the men standing, the squad's.
static func _times(r: Array, n: int) -> String:
	return "%s–%s × %d = %s–%s" % [_num(r[0]), _num(r[1]), n, _num(r[0] * n), _num(r[1] * n)]


static func _range(r: Array, n: int) -> String:
	return "%s–%s" % [_num(r[0] * n), _num(r[1] * n)]


# ---------------------------------------------------------------- stats

## The plaques: the squad's melee and its missile (or engine) damage, its move,
## its skill, defense and armour. A value above the rank's own shows green
## (gear), below it red (wear, fatigue, wounds); the tip says where it comes from.
static func stats(u: Dictionary, s: Variant, n: int) -> Array:
	var def: Dictionary = DB.UNIT_TYPES.get(u.typeId, {})
	var st: Dictionary = u.stats
	var caster: bool = (u.get("tags", []) as Array).has("caster")
	var crew: bool = def.has("crew")
	var shot: Variant = u.get("shot")
	var primary: Dictionary = DB.ABILITIES.get(def.primary, {}) if def.get("primary") != null else {}
	var ranged: bool = shot != null or primary.get("power") != null
	var base := _base(u)
	var out: Array = []
	var wb := _weapon_bonus(u, s)
	var per := "Per %s × %s standing = the squad's damage, before armour." % ["crewman" if crew else ("caster" if caster else "soldier"), "crew" if crew else "men"]
	out.append({"id": "melee", "label": "Melee" if ranged else "Damage", "icon": "sword", "value": _range(u.melee, n),
		"lines": [{"text": "Melee " + _times(u.melee, n)}] + ([wb] if not wb.is_empty() and shot == null else []) + [{"text": per, "tone": "muted"}]})
	if shot != null:
		var lines: Array = [{"text": Panels.shot_name(u) + " " + _times(shot.damage, n)},
			{"text": "Range %s–%s tiles" % [_num(shot.get("minRange", 2)), _num(shot.range)], "tone": "muted"}] + ([wb] if not wb.is_empty() else [])
		if primary.get("power") != null:
			lines.append({"text": "%s %s" % [primary.name, _times(primary.power, n)]})
		if int(u.get("ammo", -1)) >= 0:
			lines.append({"text": "Bolts %d" % int(u.ammo), "tone": "bad" if int(u.ammo) == 0 else ""})
		out.append({"id": "shot", "label": Panels.shot_name(u), "icon": "bolt" if not caster else "lightning", "value": _range(shot.damage, n), "lines": lines})
	elif primary.get("power") != null:
		out.append({"id": "primary", "label": str(primary.name), "icon": str(primary.get("icon", "stone")), "value": _range(primary.power, n),
			"lines": [{"text": "%s %s" % [primary.name, _times(primary.power, n)]}, {"text": str(primary.get("description", "")), "tone": "muted"}]})
	out.append(_stat("move", "Move", "march", st.move, base, s, "Tiles a turn on open ground."))
	var skill := _stat("melee", "Melee skill" if not ranged else "Skill", "eye", st.melee, base, s, "Against the foe's defense: the chance to hit.")
	skill.id = "skill"
	if ranged:
		var word := "Spell" if caster else ("Crew" if crew else "Ranged")
		skill.value = "%s / %s" % [_num(st.melee), _num(st.ranged)]
		skill.name = "Skill"
		skill.lines = [{"text": "Melee %s" % _num(st.melee)}] + _sources("melee", st.melee, base, s) \
			+ [{"text": "%s %s" % [word, _num(st.ranged)]}] + _sources("ranged", st.ranged, base, s)
		skill.delta = signi(int(st.melee - base.get("melee", st.melee)) + int(st.ranged - base.get("ranged", st.ranged)))
	out.append(skill)
	var dfn := _stat("defense", "Defense", "shield", st.defense, base, s, "Against the foe's skill: the chance to be missed.")
	if u.get("shieldFront"):
		dfn.value = "%s+%s" % [_num(st.defense), _num(u.shieldFront)]
		dfn.lines.append({"text": "+%s from the front (shields)" % _num(u.shieldFront), "tone": "good"})
	if st.get("rangedDefense") != null:
		dfn.lines.append({"text": "Against missiles %s" % _num(st.rangedDefense), "tone": "muted"})
	out.append(dfn)
	var arm := _stat("armor", "Armour", "shield", st.armor, base, s, "Taken off every blow that lands.")
	arm.value = JS.to_fixed(float(st.armor), 1)
	out.append(arm)
	return out


## The weapon's damage per man, as a line (empty when it adds none or the soldier is not known).
static func _weapon_bonus(u: Dictionary, s: Variant) -> Dictionary:
	if s == null:
		return {}
	var w: Variant = _tier(DB.UNIT_TYPES.get(u.typeId, {}).get("weaponLine"), int(s.get("weaponTier", 1)))
	if w == null or float(w.bonus.get("damage", 0)) == 0.0:
		return {}
	return _signed(float(w.bonus.damage), "damage a man (%s)" % w.name)


## The rank's own stats (type and level, before gear and wear).
static func _base(u: Dictionary) -> Dictionary:
	var def: Dictionary = DB.UNIT_TYPES.get(u.typeId, {})
	var out := {}
	var lv := maxi(0, int(u.get("level", 1)) - 1)
	for k in def.get("base", {}):
		out[k] = float(def.base[k]) + float(def.get("perLevel", {}).get(k, 0)) * lv
	return out


static func _stat(id: String, label: String, icon: String, value: Variant, base: Dictionary, s: Variant, desc: String) -> Dictionary:
	var d := 0
	if base.has(id):
		d = signi(int(round((float(value) - float(base[id])) * 10.0)))
	return {"id": id, "label": label, "name": label, "icon": icon, "value": _num(value), "delta": d, "desc": desc,
		"lines": _sources(id, value, base, s)}


## Where a stat comes from: the rank's, the gear's, the soldier's injuries, fatigue and the armour's wear.
static func _sources(id: String, value: Variant, base: Dictionary, s: Variant) -> Array:
	var out: Array = []
	if not base.has(id):
		return out
	out.append({"text": "Base %s" % _short(float(base[id])), "tone": "muted"})
	if s == null:
		return out
	var def: Dictionary = DB.UNIT_TYPES.get(s.typeId, {})
	for part in [["weaponLine", "weaponTier"], ["armorLine", "armorTier"]]:
		var tier: Variant = _tier(def.get(part[0]), int(s.get(part[1], 1)))
		if tier != null and tier.bonus.has(id) and float(tier.bonus[id]) != 0.0:
			out.append(_signed(float(tier.bonus[id]), str(tier.name)))
	for inj in s.get("injuries", []):
		var e: Dictionary = DB.INJURIES.get(inj, {}).get("effect", {})
		if e.has(id):
			out.append(_signed(float(e[id]), str(DB.INJURIES[inj].name)))
	var fat := int(s.get("fatigue", 0))
	if id in ["melee", "ranged"] and fat >= 60:
		out.append(_signed(-10.0 if fat >= 85 else -5.0, "Exhausted" if fat >= 85 else "Tired"))
	if id == "move" and fat >= 85:
		out.append(_signed(-1.0, "Exhausted"))
	if id == "armor" and float(s.get("armorCondition", 1.0)) < 1.0:
		out.append({"text": "Armour worn to %d%%" % JS.rnd(float(s.armorCondition) * 100.0), "tone": "bad"})
	return out


static func _signed(x: float, what: String) -> Dictionary:
	return {"text": "%s%s %s" % ["+" if x > 0 else "−", _short(absf(x)), what], "tone": "good" if x > 0 else "bad"}


static func _tier(line: Variant, tier: int) -> Variant:
	if line == null or not DB.EQUIPMENT.has(line):
		return null
	var tiers: Array = DB.EQUIPMENT[line].tiers
	return tiers[clampi(tier - 1, 0, tiers.size() - 1)]


# ---------------------------------------------------------------- effects

## The status row: its stance, its lasting conditions, its wounds and the
## soldier's injuries and fatigue, a warband leader's part, and a rout.
static func effects(u: Dictionary, v: Variant, s: Variant, ms: String) -> Array:
	var out: Array = []
	var stance: Variant = u.get("stance")
	if stance != null and DB.ABILITIES.has(stance):
		var ab: Dictionary = DB.ABILITIES[stance]
		out.append({"id": "stance", "name": str(ab.name), "icon": str(ab.get("icon", "shield")), "kind": "state",
			"desc": str(ab.get("description", "")), "source": "Stance, until the squad moves or acts."})
	for st in u.get("statuses", []):
		var info: Dictionary = Panels.STATUS_INFO.get(st.get("id"), {})
		if info.is_empty():
			continue
		out.append({"id": str(st.id), "name": str(info.name), "icon": {"chilled": "frost", "bloodlust": "blood", "bleeding": "blood", "cowed": "growl"}.get(st.id, "eye"),
			"kind": "buff" if st.id == "bloodlust" else "debuff", "turns": int(st.get("turns", -1)),
			"desc": str(info.text) + (" (−%s a turn)" % _num(st.power) if st.get("power") != null else "")})
	var wound: Variant = u.get("wound")
	if wound is Dictionary:
		var injured: bool = wound.get("kind") == "injured"
		out.append({"id": "wound", "name": "Injured" if injured else "Wounded", "icon": "injury", "kind": "debuff",
			"desc": Squad.wound_text(wound) + ".",
			"source": "%s in its last fight. %s." % ["Injured" if injured else "Wounded", Squad.hurt_text(wound)]})
	if s != null:
		for inj in s.get("injuries", []):
			var row: Dictionary = DB.INJURIES.get(inj, {})
			if row.is_empty():
				continue
			var parts: Array = []
			for k in row.get("effect", {}):
				var x := float(row.effect[k])
				parts.append("%s%s %s" % ["+" if x > 0 else "−", _short(absf(x)), STAT_NAME.get(k, k)])
			out.append({"id": "injury_" + str(inj), "name": str(row.name), "icon": "injury", "kind": "debuff",
				"desc": "%s %s." % [str(row.get("description", "")), ", ".join(parts)], "source": "A lasting injury"})
		var fat := int(s.get("fatigue", 0))
		if fat >= 60:
			out.append({"id": "fatigue", "name": "Exhausted" if fat >= 85 else "Tired", "icon": "fatigue", "kind": "debuff",
				"desc": "−10 melee and ranged skill, −1 move." if fat >= 85 else "−5 melee and ranged skill.", "source": "Fatigue %d" % fat})
	if u.get("leader"):
		out.append({"id": "leader", "name": "Warband leader", "icon": "horn", "kind": "state", "desc": "If he falls, his followers lose heart."})
	if ms == "wavering":
		out.append({"id": "wavering", "name": "Wavering", "icon": "morale", "kind": "debuff", "desc": "Too shaken to use abilities."})
	if (v != null and v.routing) or u.get("status") == "routing":
		out.append({"id": "routing", "name": "Routing", "icon": "march", "kind": "debuff", "desc": "Broken: it runs for the edge of the field."})
	return out


# ---------------------------------------------------------------- men

## One entry per place in the squad: the men standing first (the last of them
## carries the squad's wounds), then the fallen; each with his figure on the
## field when the view has one (the 3D battle's).
static func men(u: Dictionary, v: Variant, n: int, hp: float, hidden: bool) -> Array:
	var per := float(u.hpPer)
	var size := maxi(int(u.size), n)
	var standing: Array = []
	var fallen: Array = []
	var sq: Variant = v.get("sq") if v is Object else null
	if sq is Object and is_instance_valid(sq) and "members" in sq:
		for m in sq.members:
			if not is_instance_valid(m):
				continue
			if m.is_dead():
				fallen.append(m)
			else:
				standing.append(m)
	var noun: String = DB.UNIT_TYPES.get(u.typeId, {}).get("name", u.typeId)
	var out: Array = []
	for i in size:
		var alive := i < n
		var m := {"index": i, "alive": alive, "hp_max": per, "hidden": hidden, "lead": i == 0,
			"type_id": u.typeId, "variant": int(u.get("variant", 0)),
			"name": ("%s" % str(u.name) if i == 0 and not u.get("leader") and u.faction == "player" else "%s %d" % [noun, i + 1])}
		if u.get("leader") and i == 0:
			m.name = Panels.squad_title(u)
		if alive:
			m.hp = per if i < n - 1 else clampf(hp - per * (n - 1), 1.0, per)
			m.wounded = i == n - 1 and m.hp < per
			m.figure = standing[i] if i < standing.size() else null
		else:
			m.hp = 0.0
			var j := i - n
			m.figure = fallen[j] if j < fallen.size() else null
		out.append(m)
	return out


# ---------------------------------------------------------------- items

## The six slots: the squad's weapon and armour (their tiers from the armoury),
## the crossbowmen's bolts; a foe's are unknown.
static func items(u: Dictionary, s: Variant) -> Array:
	var out: Array = []
	if u.faction != "player":
		out = [{"hidden": true, "desc": "What a foe carries is not known."}, {"hidden": true, "desc": "What a foe carries is not known."}]
	elif s != null:
		var def: Dictionary = DB.UNIT_TYPES.get(u.typeId, {})
		var w: Variant = _tier(def.get("weaponLine"), int(s.get("weaponTier", 1)))
		if w != null:
			out.append(_gear(w, int(s.get("weaponTier", 1)), Icon.type_icon_name(u.typeId), "Weapon"))
		var a: Variant = _tier(def.get("armorLine"), int(s.get("armorTier", 1)))
		if a != null:
			var it := _gear(a, int(s.get("armorTier", 1)), "shield", "Armour")
			var cond := float(s.get("armorCondition", 1.0))
			it.lines.append({"text": "Condition %d%%" % JS.rnd(cond * 100.0), "tone": "bad" if cond < 1.0 else "muted"})
			out.append(it)
	if u.faction == "player" and int(u.get("ammo", -1)) >= 0:
		var sup: Dictionary = DB.SUPPLIES.get("bolts", {})
		out.append({"id": "bolts", "name": str(sup.get("name", "Bolts")), "icon": "bolts", "rarity": "common", "count": int(u.ammo), "kind": "Supplies",
			"desc": "The crossbowmen's bolts for this battle; one volley uses one.", "lines": []})
	while out.size() < 6:
		out.append({})
	return out


static func _gear(t: Dictionary, tier: int, icon: String, kind: String) -> Dictionary:
	var lines: Array = []
	for k in t.get("bonus", {}):
		lines.append(_signed(float(t.bonus[k]), STAT_NAME.get(k, k)))
	if lines.is_empty():
		lines.append({"text": "The armoury's plain issue.", "tone": "muted"})
	return {"id": kind.to_lower(), "name": str(t.name), "icon": icon, "rarity": TIER_RARITY[clampi(tier - 1, 0, TIER_RARITY.size() - 1)],
		"count": -1, "kind": "%s · tier %d" % [kind, tier], "desc": "", "lines": lines}


# ---------------------------------------------------------------- commands

## The 4×3 card: the squad's abilities on the top row (keys 1–4), then Redo,
## Next and Done on the bottom row. A foe's abilities show, never usable and
## without the company's keys, with when each is ready again.
## Each command's `call` is what pressing it does (the view's own methods).
static func commands(view: Object, u: Dictionary, ms: String) -> Array:
	var b = view.b
	var my_turn: bool = b.phase == "player" and not view.ui.busy
	var mine: bool = u.faction == "player"
	var out: Array = []
	out.resize(COMMANDS)
	out.fill({})
	var list := Panels.abilities(u)
	for i in mini(list.size(), 4):
		out[i] = ability(view, u, list[i], i, ms, my_turn and mine)
		if not mine:
			var cd := int(u.get("cooldowns", {}).get(list[i], 0))
			out[i].enabled = false
			out[i].reason = ""
			out[i].aim = ""
			out[i].hotkey = ""
			out[i].key = ""
			out[i].lines = [{"text": "Ready again in %d turn%s." % [cd, "" if cd == 1 else "s"] if cd > 0 else "Ready.", "tone": "muted" if cd > 0 else "bad"}]
			out[i].call = Callable()
	if not mine:
		return out
	var can: Dictionary = b.can_redo(u.uid) if b.phase == "player" else {"ok": false, "reason": "Only in your turn."}
	var uid: String = u.uid
	out[SLOT_REDO] = {"id": "Redo", "name": "Redo move", "mark": "undo", "hotkey": "Backspace",
		"enabled": bool(can.get("ok", false)) and u.hasMoved and not view.ui.busy,
		"desc": "Walk this squad back to where it started the turn and move again. Only before attacking.",
		"reason": "" if can.get("ok", false) or not u.hasMoved else str(can.get("reason", "")),
		"call": func(): view.redo(uid)}
	out[SLOT_NEXT] = {"id": "Next", "name": "Next squad", "mark": "next", "hotkey": "Tab",
		"enabled": b.phase in ["player", "deploy"] and not view.ui.busy,
		"desc": "Select the next squad of the company that has not finished its turn.",
		"call": func(): view.select_next()}
	out[SLOT_DONE] = {"id": "Done", "name": "Done", "mark": "check", "hotkey": "Space", "enabled": my_turn,
		"desc": "This squad's turn is over; the next one is selected.",
		"call": func(): view.end_unit()}
	return out


## An ability's command: usable as the old card's button was, with the same reasons.
static func ability(view: Object, u: Dictionary, a: String, i: int, ms: String, my_turn: bool) -> Dictionary:
	var ab: Dictionary = DB.ABILITIES.get(a, {})
	var cd := int(u.get("cooldowns", {}).get(a, 0))
	var ammo := int(u.get("ammo", -1))
	var spell: bool = ab.get("kind") == "spell"
	var cast: Dictionary = view.b.can_cast(u, a) if spell else {}
	# Lick Wounds needs no enemy beside the squad; an aimed shot, a squad that has not moved.
	var shout_ok: Dictionary = view.b.can_shout(u, a) if ab.get("kind") == "shout" else {"ok": true}
	var still_ok: bool = not ab.get("still", false) or not u.hasMoved
	var disabled: bool = not my_turn or u.hasActed or cd > 0 or (not cast.get("ok", false) if spell else ms == "wavering") \
		or (ab.get("ammoCost") != null and ammo >= 0 and ammo < int(ab.ammoCost)) \
		or (a == "overwatch" and ammo == 0) or not shout_ok.get("ok", false) or not still_ok
	# Why it cannot be used now (a cooldown shows on the button itself).
	var why := ""
	if spell and not cast.get("ok", false) and my_turn and not u.hasActed and cd == 0:
		why = str(cast.get("reason", ""))
	elif ms == "wavering" and not spell:
		why = "Too shaken to use abilities."
	elif my_turn and not u.hasActed and cd == 0 and not shout_ok.get("ok", false):
		why = str(shout_ok.get("reason", "")) + "."
	elif my_turn and not u.hasActed and not still_ok:
		why = "Only in a turn the squad has not moved."
	var aim := ""
	if spell and ab.get("target") != "self":
		var what := "an enemy squad"
		if ab.get("target") == "ally":
			what = "a friendly squad"
		elif ab.get("target") == "tile":
			what = "a squad or a tile"
		aim = "Choose it, then click %s." % what
	var every := int(ab.get("cooldown", 0))
	var aid := a
	return {"id": "Ability_" + a, "ability": a, "name": str(ab.get("name", a)), "icon": str(ab.get("icon", "sword")),
		"hotkey": str(i + 1), "key": str(i + 1), "enabled": not disabled, "active": view.ui.ability == a,
		"cooldown": float(cd) / maxf(1.0, float(every)) if cd > 0 else 0.0, "cooldown_text": str(cd) if cd > 0 else "",
		"cost": str(int(ab.ammoCost)) if ab.get("ammoCost") != null and ammo >= 0 else "",
		"every": every, "desc": str(ab.get("description", "")), "reason": why, "aim": aim,
		"call": func(): view.set_ability(aid)}
