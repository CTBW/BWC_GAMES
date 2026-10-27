## The unit bar (scripts/ui/unit_bar): what bar_data.gd reads of a squad in a
## real battle view (its stats and where they come from, its conditions, its
## men, the soldier's gear, the 4×3 command card), a foe's bar, the bar's own
## pieces as it shows and drops a squad, its tips, and no click reaching the
## field through it. The view is advanced by hand (the runner has no frames).
extends "res://tests/test_case.gd"

const ThemeBuilder = preload("res://scripts/ui/theme_builder.gd")
const H = preload("res://scripts/ui/hud_common.gd")
const DB = preload("res://scripts/data/db.gd")
const Rng = preload("res://scripts/core/rng.gd")
const Soldier = preload("res://scripts/meta/soldier.gd")
const Setup = preload("res://scripts/rules/setup.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const Squad = preload("res://scripts/rules/squad.gd")
const Panels = preload("res://scripts/ui/hud_battle_panels.gd")
const BarData = preload("res://scripts/ui/unit_bar/bar_data.gd")
const BarTips = preload("res://scripts/ui/unit_bar/bar_tips.gd")
const UnitBar = preload("res://scripts/ui/unit_bar/unit_info_bar.gd")


## The company's records, as the store holds them (bar_data reads `game.roster`).
class FakeStore extends Node:
	var game := {"roster": []}


var host: Control
var store: FakeStore
var view: Node


func after_each() -> void:
	if host != null and is_instance_valid(host):
		host.get_parent().remove_child(host)
		host.free()
	host = null


## A battle view over fresh squads of `types`; the soldiers go on the store's roster.
func _open(types: Array, seed := 11) -> void:
	host = Control.new()
	host.theme = ThemeBuilder.theme()
	host.size = Vector2(1920, 1080)
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	store = FakeStore.new()
	host.add_child(store)
	var army: Array = []
	var n := [0]
	var next_id := func() -> String:
		n[0] += 1
		return "t%d" % (n[0] - 1)
	for i in types.size():
		var so := Soldier.new_soldier(Rng.new(seed * 31 + i), types[i], 2, next_id, 0)
		store.game.roster.append(so)
		army.append(Soldier.soldier_to_unit(so))
	var roll: Dictionary = Setup.roll_encounter("goblin_scouts", Rng.new(seed), 2)
	view = load("res://scenes/battle/battle_view.tscn").instantiate()
	view.threaded_rules = false
	view.setup(Battle.new(Setup.build_battle(roll, army, {"title": "Bar test"})))
	host.add_child(view)


func _begin() -> void:
	view.begin()
	for i in 4000:
		if not view.busy():
			break
		view.advance(0.05)


func _of_type(t: String) -> Dictionary:
	for u in view.b.active("player"):
		if u.typeId == t:
			return u
	return {}


func _stat(d: Dictionary, id: String) -> Dictionary:
	for s in d.stats:
		if s.id == id:
			return s
	return {}


func _lines(x: Dictionary) -> String:
	return "\n".join(x.get("lines", []).map(func(l): return str(l.text) if l is Dictionary else str(l)))


func _tip_text(c: Control) -> String:
	var s := BarTips.text_of(c)
	if c != null:
		c.free()
	return s


func test_squad_data() -> void:
	_open(["footman", "crossbowman", "battle_mage"])
	_begin()
	var f := _of_type("footman")
	var d := BarData.squad(view, f, store)
	assert_eq(d.uid, f.uid)
	assert_eq(d.name, str(f.name))
	assert_eq(d.faction, "player")
	assert_eq(d.members, "Soldiers")
	assert_eq(int(d.size), int(f.size))
	assert_eq(d.men.size(), int(f.size), "a place per man")
	assert_eq(d.men.filter(func(m): return m.alive).size(), int(d.alive), "the men standing")
	assert_almost(d.men.reduce(func(a, m): return a + float(m.hp), 0.0), float(d.hp), 1e-6, "the men's HP add up to the squad's")
	assert_true(d.turn.mine and not d.turn.moved and not d.turn.acted, "its turn: %s" % [d.turn])
	# Plaques: damage, move, skill, defense, armour; a melee squad's damage says so.
	assert_eq(d.stats.map(func(s): return s.id), ["melee", "move", "skill", "defense", "armor"])
	assert_eq(d.stats[0].label, "Damage", "no missile: its damage is its melee")
	assert_true(_lines(d.stats[0]).contains("Melee %s–%s × %d" % [str(f.melee[0]), str(f.melee[1]), int(f.alive)]), _lines(d.stats[0]))
	# The command card: its abilities on 1.., Redo, Next and Done in their places.
	var list := Panels.abilities(f)
	assert_eq(d.commands.size(), 12)
	for i in list.size():
		assert_eq(d.commands[i].id, "Ability_" + list[i])
		assert_eq(d.commands[i].key, str(i + 1))
	assert_eq(d.commands[BarData.SLOT_REDO].id, "Redo")
	assert_eq(d.commands[BarData.SLOT_NEXT].id, "Next")
	assert_eq(d.commands[BarData.SLOT_DONE].id, "Done")
	assert_true(d.commands[BarData.SLOT_DONE].enabled, "Done on its turn")
	assert_false(d.commands[BarData.SLOT_REDO].enabled, "nothing to redo before moving")
	# The crossbowmen: their bolts, their skill both ways, the bolts in their gear.
	var x := _of_type("crossbowman")
	var dx := BarData.squad(view, x, store)
	assert_eq(dx.stats[0].label, "Melee")
	assert_eq(dx.stats[1].id, "shot")
	assert_true(_lines(dx.stats[1]).contains("Bolts %d" % int(x.ammo)), _lines(dx.stats[1]))
	var skill := _stat(dx, "skill")
	assert_eq(skill.value, "%s / %s" % [str(x.stats.melee), str(x.stats.ranged)], "melee / ranged skill")
	assert_true(dx.items.any(func(it): return it.get("id") == "bolts" and int(it.count) == int(x.ammo)), "bolts in the gear")
	# The mages: casters.
	assert_eq(BarData.squad(view, _of_type("battle_mage"), store).members, "Casters")
	# A squad wounded in its last fight: the rules' own words in its status row.
	f.wound = {"kind": "wounded", "damage": 0.1, "morale": 5, "fell": 2, "hurt": 2}
	var w: Array = BarData.squad(view, f, store).effects.filter(func(e): return e.id == "wound")
	if assert_eq(w.size(), 1, "the wound in the status row"):
		assert_eq(w[0].name, "Wounded")
		assert_eq(w[0].desc, Squad.wound_text(f.wound) + ".")
		assert_eq(w[0].source, "Wounded in its last fight. The first 2 soldiers to go down die.")
	# Dressed down to one still hurt, then Injured: what going down costs follows.
	f.wound.hurt = 1
	w = BarData.squad(view, f, store).effects.filter(func(e): return e.id == "wound")
	assert_eq(w[0].source, "Wounded in its last fight. The first soldier to go down dies.")
	f.wound = {"kind": "injured", "damage": 0.25, "morale": 15, "fell": 8, "hurt": 8}
	w = BarData.squad(view, f, store).effects.filter(func(e): return e.id == "wound")
	assert_eq(w[0].name, "Injured")
	assert_eq(w[0].source, "Injured in its last fight. %s." % Squad.hurt_text(f.wound))
	f.erase("wound")


func test_soldier_gear_and_wear() -> void:
	_open(["footman"])
	var f := _of_type("footman")
	var so: Dictionary = store.game.roster[0]
	so.weaponTier = 2
	so.fatigue = 70
	so.armorCondition = 0.5
	var inj: String = DB.INJURIES.keys()[0]
	so.injuries = [inj]
	var d := BarData.squad(view, f, store)
	var w: Dictionary = d.items[0]
	assert_eq(w.id, "weapon")
	assert_eq(w.rarity, "uncommon", "tier 2")
	assert_eq(str(w.name), str(DB.EQUIPMENT[DB.UNIT_TYPES.footman.weaponLine].tiers[1].name))
	var a: Dictionary = d.items[1]
	assert_eq(a.id, "armour")
	assert_true(_lines(a).contains("Condition 50%"), _lines(a))
	assert_eq(d.items.size(), 6, "six slots")
	assert_true(d.items[5].is_empty(), "the rest empty")
	var ids: Array = d.effects.map(func(e): return e.id)
	assert_true(ids.has("fatigue") and ids.has("injury_" + inj), "tired and injured: %s" % [ids])
	assert_true(_lines(_stat(d, "armor")).contains("Armour worn to 50%"), _lines(_stat(d, "armor")))
	assert_true(_lines(_stat(d, "skill")).contains("Tired"), "fatigue in the skill: " + _lines(_stat(d, "skill")))
	# Without the company's records: no gear, no wear, still the squad.
	var bare := BarData.squad(view, f, null)
	assert_true(bare.items.all(func(it): return it.is_empty()), "no gear known")
	assert_false(bare.effects.any(func(e): return e.id == "fatigue"))


func test_foe_data() -> void:
	_open(["footman"])
	_begin()
	var foe: Dictionary = view.b.active("enemy")[0]
	var d := BarData.squad(view, foe, store)
	assert_ne(d.faction, "player")
	assert_false(d.turn.mine, "not its turn to show")
	assert_true(d.items[0].hidden and d.items[1].hidden, "what it carries unknown")
	for c in d.commands:
		assert_false(c.get("enabled", false), "a foe's commands are never usable: %s" % c.get("id", ""))
	assert_true(d.commands[BarData.SLOT_DONE].is_empty(), "no Done for a foe")


func test_bar_shows_and_drops() -> void:
	_open(["footman", "battle_mage"])
	_begin()
	var bar = UnitBar.new()
	host.add_child(bar)
	bar.view = view
	assert_false(bar.shown(), "down at first")
	assert_false(bar.visible)
	var f := _of_type("footman")
	f.statuses = [{"id": "bleeding", "turns": 2, "power": 5}]
	bar.show_squad(BarData.squad(view, f, store))
	assert_true(bar.shown() and bar.visible, "risen")
	var t := H.button_text(bar.find_child("Done", true, false))
	assert_eq(t, "Done")
	assert_eq(bar.find_child("Men", true, false).get_children().filter(func(c): return c.visible).size(), int(f.size), "a slot per man")
	var chip: Node = bar.find_child("Status_bleeding", true, false)
	if assert_not_null(chip, "bleeding icon"):
		assert_true(_tip_text(BarTips.status(chip.effect)).contains("(−5 a turn)"))
		var pics := chip.find_children("*", "TextureRect", false, false)
		assert_true(not pics.is_empty() and pics[0].texture != null and pics[0].texture.resource_path.ends_with("/blood.png"),
			"its own painted icon, not the placeholder")
	# The same squad again: updated in place; its condition gone, its icon goes.
	f.statuses = []
	bar.show_squad(BarData.squad(view, f, store))
	assert_true(bar.find_child("Status_bleeding", true, false) == null, "the icon goes with the condition")
	# Another squad selected: swapped.
	var m := _of_type("battle_mage")
	view.select(m.uid)
	bar.show_squad(BarData.squad(view, m, store))
	assert_eq(bar.data.uid, m.uid)
	assert_eq(bar.find_child("MenLabel", true, false).text, "Casters %d / %d" % [int(m.alive), int(m.size)])
	# A command calls the view's own method.
	bar.find_child("Ability_" + Panels.abilities(m)[0], true, false).pressed.emit()
	assert_eq(view.ui.ability, Panels.abilities(m)[0], "the spell chosen through the view")
	bar.hide_bar()
	assert_false(bar.shown(), "dropped")


func test_no_click_through() -> void:
	var bar = UnitBar.new()
	assert_eq(bar.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the full-rect root lets the field have the clicks")
	assert_eq(bar.console.mouse_filter, Control.MOUSE_FILTER_STOP, "the console takes the clicks over it")
	for b in H.buttons(bar):
		assert_true(b.get_signal_connection_list("pressed").size() > 0, "'%s' wired" % b.name)
	bar.free()


func test_tips() -> void:
	var c := {"name": "Chain Lightning", "hotkey": "1", "every": 2, "desc": "Leaps.", "reason": "Too shaken.", "aim": "Choose it, then click an enemy squad."}
	var t := _tip_text(BarTips.command(c))
	for part in ["Chain Lightning", "[1] · every other turn", "Leaps.", "Too shaken.", "Choose it"]:
		assert_true(t.contains(part), "%s in %s" % [part, t])
	assert_true(_tip_text(BarTips.command({"name": "Frost", "every": 3})).contains("every 3 turns"))
	var s := _tip_text(BarTips.stat({"name": "Armour", "value": "4.0", "desc": "Taken off every blow.", "lines": [{"text": "Base 4", "tone": "muted"}]}))
	assert_true(s.contains("Armour  4.0") and s.contains("Base 4"), s)
	assert_true(_tip_text(BarTips.man({"name": "Footman 2", "alive": false})).contains("Fallen"), "a fallen man")
	assert_true(_tip_text(BarTips.item({"hidden": true})).contains("Unknown"), "a foe's gear")
	assert_eq(BarTips.command({}), null, "an empty socket has no tip")
