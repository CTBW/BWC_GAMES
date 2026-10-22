## Squad bookkeeping shared by the battle rules, the roster and the renderer,
## a port of src/battle/squad.ts.
##
## A squad has one HP pool. Soldiers fall as that pool crosses each soldier's
## share (`hpPer`); healing refills the survivors but never raises the dead.
## The functions take any Dictionary with `hp`, `hpPer` and `alive` (a
## BattleUnit or a SquadHealth). Use through
## `const Squad = preload("res://scripts/rules/squad.gd")`.
extends RefCounted

const DB = preload("res://scripts/data/db.gd")


## Soldiers still standing with `hp` left, never more than `cap` (the dead stay dead).
static func alive_for(hp: float, hp_per: float, cap: int) -> int:
	if hp <= 0:
		return 0
	return maxi(0, mini(cap, ceili(hp / hp_per - 1e-9)))


## Most HP the squad can hold: one full share per surviving soldier.
static func hp_cap(s: Dictionary) -> Variant:
	return s.alive * s.hpPer


## Take damage from the shared pool. Returns the soldiers lost (several if the blow crosses several shares).
static func damage_squad(s: Dictionary, damage: Variant) -> int:
	var before: int = s.alive
	s.hp = max(0, s.hp - damage)
	s.alive = alive_for(s.hp, s.hpPer, s.alive)
	return before - s.alive


## Heal the survivors, capped at their shares. Returns the HP actually restored.
static func heal_squad(s: Dictionary, amount: Variant) -> Variant:
	var before: Variant = s.hp
	s.hp = min(hp_cap(s), s.hp + max(0, amount))
	return s.hp - before


## Soldiers a hit of `damage` would kill.
static func kills_from(s: Dictionary, damage: Variant) -> int:
	return s.alive - alive_for(s.hp - damage, s.hpPer, s.alive)


## "soldier" or "soldiers" in the unit's own words: "goblin spearman", "moss trolls", "crewman" of a war machine.
static func member_noun(type_id: String, n: int) -> String:
	var def: Variant = DB.UNIT_TYPES.get(type_id)
	if def == null:
		return "soldier" if n == 1 else "soldiers"
	if def.has("crew"):
		return "crewman" if n == 1 else "crewmen"
	return (def.name if n == 1 else def.plural).to_lower()


## How the battle log names a squad: "Aldric's footmen", "Grukk's goblin spearmen", "Warlord Uzgash", "Hild's ballista crew".
static func squad_name(u: Dictionary) -> String:
	var name: String = u.name
	if u.get("leader", false):
		return name.split(",")[0]
	# JS: u.name.split(/[ ,]/)[0]
	var cut := name.length()
	var sp := name.find(" ")
	var cm := name.find(",")
	if sp >= 0:
		cut = mini(cut, sp)
	if cm >= 0:
		cut = mini(cut, cm)
	var first := name.substr(0, cut)
	var def: Variant = DB.UNIT_TYPES.get(u.typeId)
	if def != null and def.has("crew"):
		return "%s's %s crew" % [first, String(def.name).to_lower()]
	return "%s's %s" % [first, member_noun(u.typeId, 2)]


# ---------------------------------------------------------------- conditions

## The squad's condition of this kind (chilled, bloodlust, bleeding), or null.
static func status_of(u: Dictionary, id: String) -> Variant:
	for s in u.get("statuses", []):
		if s.id == id:
			return s
	return null


static func has_status(u: Dictionary, id: String) -> bool:
	return status_of(u, id) != null


## Squads that fight from the back: missile troops, casters and war machines that lob stones.
static func is_backline(u: Dictionary) -> bool:
	return u.get("shot") != null or u.tags.has("artillery") or u.tags.has("caster")


## Tiles the squad can march this turn: a chilled squad drags itself half as far.
static func move_of(u: Dictionary) -> int:
	if has_status(u, "chilled"):
		return maxi(1, ceili(float(u.stats.move) / 2.0))
	return u.stats.move
