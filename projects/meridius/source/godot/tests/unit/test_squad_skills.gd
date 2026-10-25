## Squad skills (Godot only, 22 Oct 2026; ../../docs/squad-skills.md): the footmen's
## Charge and Defend, the spearmen's Square, the Border Collie Royal Guard's
## Growl, Charge, Defend and Lick Wounds, and the crossbowmen's Aimed Shot.
## Squads come from the meta port, so they carry the kits of data/units.json.
extends "res://tests/unit/test_battle_base.gd"

const Soldier = preload("res://scripts/meta/soldier.gd")
const Game = preload("res://scripts/meta/game.gd")
const Setup = preload("res://scripts/rules/setup.gd")
const Icon = preload("res://scripts/ui/widgets/icon.gd")

const NEW_SKILLS := ["shield_charge", "defend", "square", "growl", "hound_charge", "lick_wounds", "aimed_shot", "howl"]

var _ids := 0


func squad(type_id: String, x: int, y: int, facing := 3) -> Dictionary:
	var u: Dictionary
	if DB.UNIT_TYPES[type_id].faction == "player":
		var n := _ids
		u = Soldier.soldier_to_unit(Soldier.new_soldier(Rng.new(_ids + 7), type_id, 1, func() -> String: return "s%d" % n, 0))
	else:
		u = Soldier.make_enemy(type_id, 1, "e%d" % _ids, Rng.new(_ids + 1))
	_ids += 1
	u.x = x
	u.y = y
	u.facing = facing
	return u


## A flat, open 14 × 12 field.
func battle(units: Array, seed := 1, phase := "player") -> Variant:
	var b = new_battle(units, seed, open_field(7))
	b.phase = phase
	return b


static func mod_names(pv: Dictionary) -> Array:
	return pv.mods.map(func(m): return m[0])


# ---------------------------------------------------------------- kits and icons

func test_every_squad_carries_its_new_kit() -> void:
	assert_eq(DB.UNIT_TYPES.footman.abilities, ["shieldwall", "shield_charge", "defend"])
	assert_eq(DB.UNIT_TYPES.footman.promotion, "shieldbash")
	assert_eq(DB.UNIT_TYPES.spearman.abilities, ["spearwall", "square"])
	assert_eq(DB.UNIT_TYPES.crossbowman.abilities, ["overwatch", "aimed_shot"])
	assert_eq(DB.UNIT_TYPES.collie_guard.abilities, ["growl", "hound_charge", "defend", "lick_wounds"])
	assert_eq(DB.UNIT_TYPES.collie_guard.promotion, "howl")
	var promoted := Soldier.new_soldier(Rng.new(3), "footman", 3, func() -> String: return "p", 0)
	promoted.promoted = true
	assert_eq(Soldier.abilities_of(promoted), ["shieldwall", "shield_charge", "defend", "shieldbash"])
	var hound := Soldier.new_soldier(Rng.new(3), "collie_guard", 3, func() -> String: return "h", 0)
	assert_true(Soldier.can_promote(hound), "a veteran guard can be promoted")
	hound.promoted = true
	assert_eq(Soldier.abilities_of(hound), ["howl", "hound_charge", "defend", "lick_wounds"], "Howl takes Growl's place on the bar")


func test_every_skill_has_a_button_and_an_icon() -> void:
	for id in NEW_SKILLS:
		var ab: Dictionary = DB.ABILITIES[id]
		assert_true(DB.is_active_ability(id), id + " gets a button")
		assert_true(Icon.NAMES.has(ab.icon), id + " icon listed")
		assert_true(ResourceLoader.exists("res://assets/icons/%s.svg" % ab.icon), id + " icon file")
		assert_true(str(ab.description).length() > 40, id + " description")
	for t in ["footman", "spearman", "crossbowman", "collie_guard"]:
		assert_true(Soldier.kit(t, true).size() <= 4, t + " fits keys 1–4")


func test_every_stance_and_condition_wears_its_icon_on_the_map() -> void:
	# Beside a squad's bar on the field: the icon of the skill behind it.
	var BattleDraw = load("res://scripts/render/battle_draw.gd")
	for id in DB.ABILITIES:
		var ab: Dictionary = DB.ABILITIES[id]
		if ab.get("kind") == "stance":
			assert_eq(BattleDraw.stance_icon(str(ab.stance)), ab.icon, id + " on the map")
	assert_eq(BattleDraw.stance_icon("square"), "square")
	assert_eq(BattleDraw.stance_icon("no_such_stance"), "", "an unknown stance stays a word")
	var badges: Array = []
	for st in load("res://scripts/render/battle_view.gd").STATUS_LABEL:
		var icon: String = BattleDraw.STATUS_ICON.get(st, "")
		assert_true(Icon.NAMES.has(icon), "%s wears %s" % [st, icon])
		badges.append(icon)
	# Every badge has its painted icon; where none is painted, the SVG.
	for id in DB.ABILITIES:
		if DB.ABILITIES[id].get("kind") == "stance":
			badges.append(str(DB.ABILITIES[id].icon))
	for icon in badges:
		assert_eq(Icon.painted(icon).resource_path, "res://assets/icons/painted/%s.png" % icon, icon + " painted")
		assert_true(Icon.painted(icon).get_width() >= 64, icon + " big enough to shrink")
	assert_eq(Icon.painted("howl"), Icon.tex("howl"), "Howl has no painting yet")


# ---------------------------------------------------------------- charge

func test_a_charge_needs_a_run_and_hits_harder() -> void:
	var f := squad("footman", 4, 8)
	var g := squad("goblin_spear", 4, 3, 1)
	var b = battle([f, g])
	var from := {"x": 4, "y": 4}
	var short: Dictionary = b.preview(f, g, {"from": from, "ability": "shield_charge", "movedTiles": 1})
	assert_false(short.legal, "one tile is no run")
	assert_eq(short.reason, "Needs a run of at least 2 tiles")
	var plain: Dictionary = b.preview(f, g, {"from": from, "movedTiles": 4})
	var pv: Dictionary = b.preview(f, g, {"from": from, "ability": "shield_charge", "movedTiles": 4})
	assert_true(pv.legal, str(pv.reason))
	assert_true(pv.max > plain.max and pv.min >= plain.min, "+30% damage")
	assert_eq(pv.chance, mini(95, plain.chance + 5), "+5 to hit")
	assert_true(mod_names(pv).has("Charge"), "named in the forecast")
	assert_true(pv.moraleHit >= plain.moraleHit + 10, "the impact shakes them")
	assert_true(b.move(f.uid, 4, 4), "run in")
	assert_true(b.attack(f.uid, g.uid, "shield_charge"), "charge")
	assert_eq(f.cooldowns.shield_charge, 3)
	var atk: Array = events_of(b.drain(), "attack")
	assert_eq(atk[atk.size() - 1].ability, "shield_charge")


func test_the_hounds_charge_is_surer_and_more_frightening() -> void:
	var c := squad("collie_guard", 4, 8)
	var g := squad("goblin_spear", 4, 3, 1)
	var b = battle([c, g])
	var from := {"x": 4, "y": 4}
	var plain: Dictionary = b.preview(c, g, {"from": from, "movedTiles": 4})
	var pv: Dictionary = b.preview(c, g, {"from": from, "ability": "hound_charge", "movedTiles": 4})
	assert_true(pv.legal)
	assert_eq(pv.chance, mini(95, plain.chance + 12))
	assert_true(pv.moraleHit >= plain.moraleHit + 14)
	assert_false(b.attack(c.uid, g.uid, "hound_charge"), "not adjacent and no run yet")


func test_a_square_breaks_a_charge_and_strikes_first_from_any_side() -> void:
	# The spearmen face +x; the footmen come at their flank, from +y.
	var s := squad("spearman", 6, 4, 0)
	s.faction = "enemy"
	var f := squad("footman", 6, 9)
	var b = battle([s, f])
	var from := {"x": 6, "y": 5}
	assert_eq(b.preview(f, s, {"from": from, "ability": "shield_charge", "movedTiles": 4}).arc, "flank", "an open flank")
	s["stance"] = "square"
	var plain: Dictionary = b.preview(f, s, {"from": from, "movedTiles": 4})
	var pv: Dictionary = b.preview(f, s, {"from": from, "ability": "shield_charge", "movedTiles": 4})
	assert_eq(pv.arc, "front", "a square has no flank")
	assert_true(mod_names(pv).has("Charge broken by the square"))
	var rows := {}
	for m in pv.mods:
		rows[m[0]] = m[1]
	assert_eq([rows.get("Charge"), rows.get("Charge broken by the square")], [5, -5], "the square takes back the charge's +5, not a 0 row")
	assert_eq([pv.chance, pv.min, pv.max, pv.moraleHit], [plain.chance, plain.min, plain.max, plain.moraleHit], "nothing left of the charge")
	assert_true(b.move(f.uid, 6, 5), "close in")
	b.drain()
	assert_true(b.attack(f.uid, s.uid, "shield_charge"))
	var atk: Array = events_of(b.drain(), "attack")
	assert_eq(atk[0].uid, s.uid, "the square strikes first")
	assert_eq(atk[0].get("reaction"), "firstStrike")


# ---------------------------------------------------------------- square

func test_a_square_has_no_flank_or_rear_and_trades_missile_cover_for_blades() -> void:
	var s := squad("spearman", 6, 6, 0)
	var g := squad("orc_warrior", 5, 6, 0)
	var a := squad("goblin_archer", 11, 6, 2)
	g.stats.melee = 60
	a.stats.ranged = 60
	var b = battle([s, g, a])
	assert_eq(b.arc_of(s, g), "rear")
	var melee: Dictionary = b.preview(g, s, {"movedTiles": 0})
	var shot: Dictionary = b.preview(a, s, {"movedTiles": 0})
	s["stance"] = "square"
	assert_eq(b.arc_of(s, g), "front")
	var melee_sq: Dictionary = b.preview(g, s, {"movedTiles": 0})
	var shot_sq: Dictionary = b.preview(a, s, {"movedTiles": 0})
	# From behind: +20 to hit and ×1.25 damage are gone, and 6 more defense.
	assert_eq(melee_sq.chance, maxi(5, melee.chance - 20 - 6))
	assert_true(melee_sq.max < melee.max, "no rear blow")
	assert_eq(shot_sq.chance, mini(95, shot.chance + 10), "a packed target")


func test_a_square_cannot_be_pushed() -> void:
	var s := squad("spearman", 6, 6, 2)
	s.faction = "enemy"
	s["stance"] = "square"
	var f := squad("footman", 7, 6, 2)
	f.abilities.append("shieldbash")
	f.stats.melee = 400
	var b = battle([s, f])
	assert_true(b.attack(f.uid, s.uid, "shieldbash"))
	var evs: Array = b.drain()
	assert_eq(events_of(evs, "push").size(), 0, "no push")
	assert_eq([s.x, s.y], [6, 6])
	assert_true(has_event(evs, func(e): return e.t == "log" and String(e.text).contains("holds its ground")))


# ---------------------------------------------------------------- defend

func test_a_guard_takes_the_blow_meant_for_the_squad_beside_it() -> void:
	var guard := squad("footman", 4, 6)
	var ward := squad("crossbowman", 5, 6)
	var o := squad("orc_warrior", 6, 6, 2)
	o.stats.melee = 400
	var b = battle([guard, ward, o], 3, "enemy")
	assert_eq(b.preview(o, ward).get("guard"), null, "no guard yet")
	guard["stance"] = "defend"
	var pv: Dictionary = b.preview(o, ward)
	assert_eq(pv.guard, guard.uid, "the guard steps in")
	assert_eq(pv.arc, "front", "on its shield")
	assert_true(pv.legal, "the attack itself stays legal")
	var ward_hp: int = ward.hp
	var guard_hp: int = guard.hp
	assert_true(b.attack(o.uid, ward.uid))
	var evs: Array = b.drain()
	var atk: Dictionary = events_of(evs, "attack")[0]
	assert_eq(atk.target, guard.uid)
	assert_eq(atk.ward, ward.uid)
	assert_eq(ward.hp, ward_hp, "the crossbowmen are untouched")
	assert_eq(guard.hp, guard_hp - atk.damage)
	assert_true(has_event(evs, func(e): return e.t == "log" and String(e.text).contains("step in front of")))


func test_a_guard_covers_shots_but_not_free_attacks_or_other_guards() -> void:
	var guard := squad("collie_guard", 4, 6)
	var ward := squad("crossbowman", 5, 6)
	var other := squad("footman", 4, 5)
	var a := squad("goblin_archer", 5, 1, 1)
	var o := squad("orc_warrior", 6, 6, 2)
	var b = battle([guard, ward, other, a, o], 3, "enemy")
	guard["stance"] = "defend"
	other["stance"] = "defend"
	assert_eq(b.preview(a, ward).get("guard"), guard.uid, "shield raised over the archers' mark")
	assert_eq(b.guard_of(o, ward, {"reaction": "zoc"}), null, "free attacks are not caught")
	assert_eq(b.guard_of(o, other), null, "a guard is not guarded")
	ward["stance"] = "defend"
	assert_eq(b.guard_of(o, ward), null, "nor is a squad that stands guard itself")


func test_the_sturdiest_guard_steps_in() -> void:
	var g1 := squad("footman", 4, 6)
	var g2 := squad("footman", 5, 7)
	var ward := squad("crossbowman", 5, 6)
	var o := squad("orc_warrior", 6, 6, 2)
	var b = battle([g1, g2, ward, o], 3, "enemy")
	g1["stance"] = "defend"
	g2["stance"] = "defend"
	Squad.damage_squad(g1, 10)
	assert_eq(b.guard_of(o, ward).uid, g2.uid)


func test_a_guard_catches_only_the_first_blow_each_turn() -> void:
	var guard := squad("footman", 4, 6)
	var ward := squad("crossbowman", 5, 6)
	var o1 := squad("orc_warrior", 6, 6, 2)
	var o2 := squad("orc_warrior", 5, 5, 1)
	var b = battle([guard, ward, o1, o2], 3, "enemy")
	guard["stance"] = "defend"
	assert_true(b.attack(o1.uid, ward.uid))
	assert_eq(events_of(b.drain(), "attack")[0].target, guard.uid, "the first blow is caught")
	assert_true(guard.get("guardSpent", false))
	assert_eq(b.preview(o2, ward).get("guard"), null, "the forecast shows the ward exposed")
	assert_true(b.attack(o2.uid, ward.uid))
	var atk: Dictionary = events_of(b.drain(), "attack")[0]
	assert_eq(atk.target, ward.uid, "the second gets through")
	assert_eq(atk.get("ward"), null)
	# A new stand next turn guards again.
	b.phase = "player"
	b._start_turn("player")
	assert_false(guard.has("guardSpent"), "rested at the start of its turn")
	assert_true(b.use_stance(guard.uid, "defend"))
	assert_eq(b.guard_of(o1, ward).uid, guard.uid)


# ---------------------------------------------------------------- growl

func test_growl_cows_the_foes_close_by_until_their_turn_ends() -> void:
	var c := squad("collie_guard", 6, 6)
	var near := squad("goblin_spear", 6, 4, 1)
	var far := squad("goblin_spear", 6, 1, 1)
	var b = battle([c, near, far])
	var m_near: int = near.morale
	var m_far: int = far.morale
	var before: Dictionary = b.preview(near, c, {"from": {"x": 6, "y": 5}, "movedTiles": 1})
	assert_true(b.can_shout(c, "growl").ok)
	assert_true(b.shout(c.uid, "growl"))
	assert_eq(near.morale, m_near - 12)
	assert_eq(far.morale, m_far, "out of earshot")
	assert_true(Squad.has_status(near, "cowed"))
	assert_false(Squad.has_status(far, "cowed"))
	assert_eq(c.cooldowns.growl, 3)
	var after: Dictionary = b.preview(near, c, {"from": {"x": 6, "y": 5}, "movedTiles": 1})
	assert_false(mod_names(before).has("Cowed"))
	assert_true(after.mods.any(func(m): return m[0] == "Cowed" and m[1] == -10), "−10 to hit")
	b._end_of_turn("enemy")
	assert_false(Squad.has_status(near, "cowed"), "gone at the end of its turn")


func test_veteran_royal_guards_howl_farther_and_longer() -> void:
	var s := Soldier.new_soldier(Rng.new(5), "collie_guard", 3, func() -> String: return "v", 0)
	s.promoted = true
	var c := Soldier.soldier_to_unit(s)
	c.x = 6
	c.y = 6
	c.facing = 3
	var near := squad("goblin_spear", 6, 3, 1)
	var far := squad("goblin_spear", 6, 2, 1)
	var b = battle([c, near, far])
	assert_false(c.abilities.has("growl"), "Howl replaces Growl")
	assert_false(b.can_shout(c, "growl").ok)
	var m_near: int = near.morale
	assert_true(b.shout(c.uid, "howl"))
	assert_eq(near.morale, m_near - 16, "3 tiles away and heard")
	assert_true(Squad.has_status(near, "cowed"))
	assert_false(Squad.has_status(far, "cowed"), "4 tiles is out of earshot")
	assert_eq(c.cooldowns.howl, 3)
	b._end_of_turn("enemy")
	assert_true(Squad.has_status(near, "cowed"), "still cowed through a second turn")
	b._end_of_turn("enemy")
	assert_false(Squad.has_status(near, "cowed"))


# ---------------------------------------------------------------- lick wounds

func test_lick_wounds_heals_the_living_and_stops_the_bleeding() -> void:
	var c := squad("collie_guard", 6, 6)
	var g := squad("goblin_spear", 6, 2, 1)
	var b = battle([c, g])
	Squad.damage_squad(c, c.hpPer + 10)
	var alive: int = c.alive
	c.statuses = [{"id": "bleeding", "turns": 2, "power": 3}]
	var hp: int = c.hp
	assert_true(b.shout(c.uid, "lick_wounds"))
	assert_between(c.hp - hp, mini(3 * alive, Squad.hp_cap(c) - hp), 5 * alive, "3–5 per hound")
	assert_true(c.hp <= alive * c.hpPer, "the fallen stay dead")
	assert_eq(c.alive, alive)
	assert_false(Squad.has_status(c, "bleeding"), "the bleeding stops")
	var evs: Array = b.drain()
	assert_true(has_event(evs, func(e): return e.t == "heal" and e.uid == c.uid and e.reason == "Lick Wounds"))
	assert_true(has_event(evs, func(e): return e.t == "status" and e.status == "bleeding" and not e.on))


func test_no_licking_wounds_with_an_enemy_beside() -> void:
	var c := squad("collie_guard", 6, 6)
	var g := squad("goblin_spear", 6, 5, 1)
	var b = battle([c, g])
	var can: Dictionary = b.can_shout(c, "lick_wounds")
	assert_false(can.ok)
	assert_eq(can.reason, "Not with an enemy beside them")
	assert_false(b.shout(c.uid, "lick_wounds"))


# ---------------------------------------------------------------- aimed shot

func test_an_aimed_shot_ignores_troops_in_the_way_but_needs_a_still_squad() -> void:
	var x := squad("crossbowman", 6, 9)
	var screen := squad("footman", 6, 7)
	var g := squad("goblin_spear", 6, 4, 1)
	var b = battle([x, screen, g])
	var plain: Dictionary = b.preview(x, g)
	var pv: Dictionary = b.preview(x, g, {"ability": "aimed_shot"})
	assert_true(plain.legal and pv.legal, str(pv.reason))
	assert_true(mod_names(plain).has("Shooting past troops"))
	assert_false(mod_names(pv).has("Shooting past troops"), "aimed past them")
	assert_eq(pv.chance, mini(95, plain.chance + 12 + 20))
	assert_eq(pv.moraleHit, plain.moraleHit + 6)
	var moved: Dictionary = b.preview(x, g, {"ability": "aimed_shot", "movedTiles": 1})
	assert_false(moved.legal)
	assert_eq(moved.reason, "Only in a turn the squad has not moved")
	assert_true(b.move(x.uid, 5, 9))
	assert_false(b.attack(x.uid, g.uid, "aimed_shot"), "not after moving")
	assert_true(b.attack(x.uid, g.uid), "a plain shot still")


# ---------------------------------------------------------------- automation

func test_the_company_automation_uses_the_new_skills() -> void:
	# Both sides on automation through every encounter: the battles end, no
	# squads share a tile, and the new skills come into play.
	if slow():
		return
	var used := {}
	for seed in [1, 2]:
		var army: Array = []
		var k := 0
		for t in ["footman", "footman", "spearman", "crossbowman", "collie_guard"]:
			army.append(Soldier.soldier_to_unit(Soldier.new_soldier(Rng.new(seed * 11 + k), t, 2, func() -> String: return "a%d%d" % [seed, k], 0)))
			k += 1
		for enc in DB.ENCOUNTERS:
			var roll := Setup.roll_encounter(enc.id, Rng.new(seed * 131 + 7), 1)
			var b = auto_battle(Battle.new(Setup.build_battle(roll, army.duplicate(true), {"survivalBonus": 0, "title": enc.id, "darkness": false})))
			for e in b.drain():
				if e.t == "attack" and e.get("ability") != null:
					used[e.ability] = true
				elif e.t == "shout":
					used[e.ability] = true
				elif e.t == "stance" and e.get("stance") != null:
					used[e.stance] = true
				elif e.t == "attack" and e.get("ward") != null:
					used["guarded"] = true
			assert_true(b.is_over() or b.turn > 30, enc.id)
	for id in ["shield_charge", "hound_charge", "aimed_shot", "growl", "defend"]:
		assert_true(used.has(id), "%s used (%s)" % [id, ", ".join(PackedStringArray(used.keys()))])
