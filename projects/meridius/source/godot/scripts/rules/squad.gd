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
const JS = preload("res://scripts/core/js.gd")


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


# ---------------------------------------------------------------- wounds

## Soldiers who go down in a fight rise again after it, hurt, and the squad
## carries their wounds into its next fight: for the whole squad's worth of
## fallen, 30% less damage and defense and 30 less morale (2 of 6 down: 10%,
## 10). In that fight the first of them to go down again die for good.
const WOUND_PENALTY := 0.3
const WOUND_MORALE := 30
## A squad cut down to the last soldier rises Injured: 40% less damage and
## defense, 30 less morale, and every soldier of it hurt: each who goes down
## in its next fight dies, and cut down again, the squad is gone for good.
const INJURED_PENALTY := 0.4
const INJURED_MORALE := 30


## The penalty a roster squad (`wounded`, `injured`) carries into its next fight:
## {kind: "wounded" | "injured", fell, hurt, damage, defense, morale}, or null.
## `hurt` soldiers are still hurt (Squad.hurt_of).
static func wound_of(s: Dictionary) -> Variant:
	var size: int = DB.squad_size(s.typeId)
	if s.get("injured", false):
		return {"kind": "injured", "fell": size, "hurt": hurt_of(s), "damage": INJURED_PENALTY, "defense": INJURED_PENALTY, "morale": INJURED_MORALE}
	var fell: int = s.get("wounded", 0)
	if fell <= 0:
		return null
	var share := float(fell) / size
	return {"kind": "wounded", "fell": fell, "hurt": hurt_of(s), "damage": WOUND_PENALTY * share, "defense": WOUND_PENALTY * share, "morale": JS.rnd(WOUND_MORALE * share)}


## Soldiers of a roster squad still hurt from its last fight: in its next
## fight the first of them to go down die for good. Every soldier of an
## Injured squad is hurt.
static func hurt_of(s: Dictionary) -> int:
	var men: int = s.get("men", DB.squad_size(s.typeId))
	if s.get("injured", false):
		return men
	return mini(s.get("wounded", 0), men)


## Clears the penalty a squad carries from its last fight (wounded or Injured):
## a camp rest, a bandage or the Infirmary at home.
static func tend_wounds(s: Dictionary) -> void:
	s.erase("wounded")
	s.erase("injured")


## Damage multiplier of a BattleUnit carrying wounds from its last fight.
static func wound_mult(u: Dictionary) -> float:
	var w: Variant = u.get("wound")
	return 1.0 - w.damage if w != null else 1.0


## "−10% damage and defense, −10 morale".
static func wound_text(w: Dictionary) -> String:
	return "−%d%% damage and defense, −%d morale" % [JS.rnd(w.damage * 100), w.morale]


## What going down costs a squad carrying `w` (a wound_of result), without the
## full stop: "The first 2 soldiers to go down die".
static func hurt_text(w: Dictionary) -> String:
	if w.kind == "injured":
		return "Every soldier who goes down dies; cut down to the last, the squad is gone for good"
	var n: int = w.get("hurt", w.fell)
	return "The first soldier to go down dies" if n == 1 else "The first %d soldiers to go down die" % n


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
