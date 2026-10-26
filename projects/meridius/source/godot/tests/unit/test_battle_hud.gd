## The battle HUD (scripts/ui/battle_hud.gd + hud_battle_panels.gd, port of
## `BattleHud` in src/ui/screens/Battle.tsx) over a real battle view showing a
## Battle from Setup.build_battle: deployment, the selected squad's card, the
## attack preview, hovered squad / tile panels, the enemy turn, the retreat
## confirmation and the end of the battle; every button wired or deliberately
## disabled. Mages and war machines: spell buttons with their reasons, the
## spell forecast, crews and casters on the squad's card, conditions. The view runs its rules synchronously (threaded_rules = false) and
## is advanced by hand (the runner has no frames).
extends "res://tests/test_case.gd"

const ThemeBuilder = preload("res://scripts/ui/theme_builder.gd")
const H = preload("res://scripts/ui/hud_common.gd")
const DB = preload("res://scripts/data/db.gd")
const Rng = preload("res://scripts/core/rng.gd")
const Game = preload("res://scripts/meta/game.gd")
const Soldier = preload("res://scripts/meta/soldier.gd")
const Setup = preload("res://scripts/rules/setup.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const Ai = preload("res://scripts/rules/ai.gd")
const BattleHud = preload("res://scripts/ui/battle_hud.gd")
const Panels = preload("res://scripts/ui/hud_battle_panels.gd")
const Squad = preload("res://scripts/rules/squad.gd")
const Grid = preload("res://scripts/rules/grid.gd")


class FakeStore extends Node:
	signal changed
	var battle_info: Variant = null
	var calls: Array = []

	func open_manual(page: Variant) -> void:
		calls.append(["open_manual", page])


var host: Control
var store: FakeStore
var view: Node
var hud: Control


func _battle(encounter := "goblin_scouts", seed := 7, promoted := false) -> Variant:
	var g := Game.new_game(seed)
	if promoted:
		for so in g.roster:
			so.promoted = true
	var army: Array = []
	for so in g.roster.slice(0, 6):
		army.append(Soldier.soldier_to_unit(so))
	var roll: Dictionary = Setup.roll_encounter(encounter, Rng.new(seed), 2)
	return Battle.new(Setup.build_battle(roll, army, {"title": "Test battle"}))


## A battle with a chosen army of fresh squads (the store's debug_test_battle with `army`).
func _battle_with(types: Array, encounter := "shaman_fire", seed := 11, level := 2) -> Variant:
	var army: Array = []
	var n := [0]
	var next_id := func() -> String:
		n[0] += 1
		return "t%d" % (n[0] - 1)
	for i in types.size():
		army.append(Soldier.soldier_to_unit(Soldier.new_soldier(Rng.new(seed * 31 + i), types[i], level, next_id, 0)))
	var roll: Dictionary = Setup.roll_encounter(encounter, Rng.new(seed), 2)
	return Battle.new(Setup.build_battle(roll, army, {"title": "Test battle"}))


func _open(encounter := "goblin_scouts", promoted := false, battle: Variant = null) -> void:
	host = Control.new()
	host.theme = ThemeBuilder.theme()
	host.size = Vector2(1920, 1080)
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	store = FakeStore.new()
	host.add_child(store)
	view = load("res://scenes/battle/battle_view.tscn").instantiate()
	view.threaded_rules = false
	view.setup(battle if battle != null else _battle(encounter, 7, promoted))
	host.add_child(view)
	hud = BattleHud.new()
	hud.app = store
	host.add_child(hud)
	hud.setup(view)


func after_each() -> void:
	if host != null and is_instance_valid(host):
		host.get_parent().remove_child(host)
		host.free()
	host = null


## Plays back the view's queued events (the runner has no frames).
func _settle(max_steps := 4000) -> void:
	for i in max_steps:
		if not view.busy():
			break
		view.advance(0.05)
	view.advance(0.05)
	hud.refresh()


func _live(n: Node) -> bool:
	return is_instance_valid(n) and not n.is_queued_for_deletion() and hud.is_ancestor_of(n)


func _button(text: String) -> BaseButton:
	var live: Array = H.buttons(hud).filter(func(b): return _live(b))
	for b in live:
		if str(b.name) == text:
			return b
	for b in live:
		if H.button_text(b).contains(text):
			return b
	return null


func _node(name: String) -> Node:
	var n := hud.find_child(name, true, false)
	return n if n != null and _live(n) else null


func _text_of(n: Node) -> String:
	if n == null:
		return ""
	var s := ""
	for c in [n] + n.find_children("*", "", true, false):
		if c is Label:
			s += (c as Label).text + "\n"
		elif c is RichTextLabel:
			s += (c as RichTextLabel).get_parsed_text() + "\n"
	return s


func _check_buttons(where: String) -> int:
	var n := 0
	for b in H.buttons(hud):
		if not _live(b):
			continue
		n += 1
		assert_true(b.get_signal_connection_list("pressed").size() > 0, "%s: '%s' (%s) is connected" % [where, H.button_text(b), b.name])
	return n


func assert_null(v: Variant, msg := "expected nothing") -> bool:
	return assert_true(v == null, msg)


func _click(c: Control) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	c.gui_input.emit(e)


func _begin() -> void:
	_button("Begin").pressed.emit()
	_settle()


func test_deployment() -> void:
	_open()
	hud.refresh()
	var b = view.b
	assert_eq(b.phase, "deploy")
	var top := _node("TopBar")
	var t := _text_of(top)
	assert_true(t.contains("Test battle"), "battle title")
	assert_true(t.contains("Deployment · %s" % b.map.name), "deployment line: " + t)
	assert_true(t.contains("Enemies in sight: %d" % hud.enemy_counts().x), "enemy count: " + t)
	assert_not_null(_button("Begin"), "Begin Battle")
	assert_null(_button("Retreat"), "no Retreat while deploying")
	assert_null(_button("EndTurn"), "no End Turn while deploying")
	# The company column: one card per squad.
	var players: Array = b.units.filter(func(u): return u.faction == "player")
	for u in players:
		assert_not_null(_node("Mini_" + str(u.uid)), "card for " + str(u.name))
	# Objective with its brief, the deploy banner, the first squad selected.
	var obj := _text_of(_node("Objective"))
	assert_true(obj.contains(str(b.objective.title)), "objective title")
	assert_true(obj.contains(str(b.objective.brief)), "objective brief while deploying")
	assert_true(_text_of(_node("Banner")).contains("Deploy your company"), "deploy banner")
	var panel := _node("UnitPanel")
	if assert_not_null(panel, "selected squad's card"):
		var sel: Dictionary = b.unit(view.ui.selected)
		var pt := _text_of(panel)
		assert_true(pt.contains(str(sel.name)), "name")
		assert_true(pt.contains("Can move") and pt.contains("Can act"), "status tags")
		assert_true(pt.contains("Soldiers"), "soldiers line")
		assert_true(pt.contains("Facing"), "facing rose")
		assert_true(pt.contains("Melee %s" % str(sel.stats.melee)), "stats line: " + pt)
	assert_true(_text_of(_node("Log")).contains("Hold the line. Mind the flanks.") or view.ui.log.size() > 0, "log")
	_check_buttons("deploy")


func test_toggles_and_manual() -> void:
	_open()
	hud.refresh()
	var grid0: bool = view.ui.showGrid
	_button("Grid").pressed.emit()
	hud.refresh()
	assert_eq(view.ui.showGrid, not grid0, "grid toggled")
	assert_eq(str(_button("Grid").theme_type_variation), "IconButtonActive" if not grid0 else "IconButton", "grid button look")
	_button("Danger").pressed.emit()
	hud.refresh()
	assert_true(view.ui.danger, "danger on")
	assert_eq(str(_button("Danger").theme_type_variation), "IconButtonActive")
	var s0: float = view.speed
	_button("Speed").pressed.emit()
	hud.refresh()
	assert_eq(view.speed, 1.0 if s0 > 1.0 else 2.0, "speed toggled")
	assert_eq(_button("Speed").text, "2×" if view.speed > 1.0 else "1×")
	_button("Speed").pressed.emit()
	assert_eq(view.speed, s0, "speed back")
	_button("Help").pressed.emit()
	assert_eq(store.calls.back(), ["open_manual", "battle"])


func test_begin_and_select() -> void:
	_open()
	hud.refresh()
	_begin()
	var b = view.b
	assert_eq(b.phase, "player", "battle begun")
	var t := _text_of(_node("TopBar"))
	assert_true(t.contains("Turn 1 · Your move"), "turn line: " + t)
	var et := _button("EndTurn")
	if assert_not_null(et, "End Turn"):
		assert_false(et.disabled, "End Turn enabled on my turn")
		assert_true(H.button_text(et).contains("ready)"), "ready count: " + H.button_text(et))
	assert_not_null(_button("Retreat"), "Retreat")
	assert_false(_button("Retreat").disabled)
	# Select another squad from the company column.
	var players: Array = b.active("player")
	var other: Dictionary = players[1]
	_click(_node("Mini_" + str(other.uid)))
	hud.refresh()
	assert_eq(view.ui.selected, other.uid, "card click selects")
	assert_true(_text_of(_node("UnitPanel")).contains(str(other.name)), "card shows it")
	# Abilities: one button per ability, keys 1..n.
	var list := Panels.abilities(other)
	for i in list.size():
		var btn := _button("Ability_" + list[i])
		if assert_not_null(btn, "ability " + list[i]):
			assert_true(H.button_text(btn).begins_with(str(i + 1)), "key number")
	_check_buttons("player turn")
	# Done ends the squad and selects the next.
	_button("Done").pressed.emit()
	_settle()
	assert_true(b.unit(other.uid).done, "squad done")
	assert_ne(view.ui.selected, other.uid, "next squad selected")
	hud.refresh()
	var card := _node("Mini_" + str(other.uid))
	assert_true(_text_of(card).contains("Done"), "card says Done")
	assert_almost(card.modulate.a, 0.6, 1e-6, "done card dimmed")


func test_ability_arms_and_stance() -> void:
	_open("goblin_scouts", true)
	_begin()
	var b = view.b
	var u: Dictionary = b.unit(view.ui.selected)
	var list := Panels.abilities(u)
	assert_true(list.size() >= 2, "a stance and the promotion's attack: %s" % [list])
	# An attack ability is armed for the next click (and disarmed by a second press).
	var attack := ""
	var stance := ""
	for a in list:
		if DB.ABILITIES[a].kind == "attack":
			attack = a
		elif DB.ABILITIES[a].kind == "stance":
			stance = a
	if attack != "":
		var btn := _button("Ability_" + attack)
		assert_false(btn.disabled, "attack ability usable")
		btn.pressed.emit()
		hud.refresh()
		assert_eq(view.ui.ability, attack, "attack ability armed")
		assert_eq(str(_button("Ability_" + attack).theme_type_variation), "AbilityButtonActive", "armed look")
		_button("Ability_" + attack).pressed.emit()
		hud.refresh()
		assert_eq(view.ui.ability, null, "pressed again: disarmed")
	# A stance is taken at once: the squad has acted, its card shows the stance.
	if stance != "":
		_button("Ability_" + stance).pressed.emit()
		_settle()
		u = b.unit(u.uid)
		assert_eq(u.get("stance"), stance, "stance taken")
		assert_true(u.hasActed, "acted")
		assert_true(_text_of(_node("UnitPanel")).contains("Acted"), "Acted tag")
		for a in list:
			assert_true(_button("Ability_" + a).disabled, "abilities spent after acting: " + a)
		assert_true(_text_of(_node("Mini_" + str(u.uid))).contains(str(DB.ABILITIES[stance].name)), "card shows the stance")


func test_attack_preview_and_hover_panels() -> void:
	_open()
	_begin()
	var b = view.b
	var sel: Dictionary = b.unit(view.ui.selected)
	var target: Dictionary = b.active("enemy")[0]
	# Not adjacent: the forecast says why.
	var pv: Dictionary = b.preview(sel, target, {})
	pv.target = target.uid
	pv.from = null
	pv.ability = null
	pv.moveFirst = false
	view.ui.hover.preview = pv
	view.ui.hover.unit = target.uid
	hud.refresh()
	var fc := _node("Forecast")
	if assert_not_null(fc, "forecast"):
		var t := _text_of(fc)
		assert_true(t.contains(Panels.squad_title(target)), "target title")
		if not pv.legal:
			assert_true(t.contains(str(pv.reason)), "reason: " + t)
	# A legal attack from the tile beside the target.
	var from: Variant = null
	for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
		var p := {"x": int(target.x) + d[0], "y": int(target.y) + d[1]}
		if b.preview_legal(sel, target, {"from": p}):
			from = p
			break
	if from != null:
		pv = b.preview(sel, target, {"from": from, "movedTiles": 1})
		pv.target = target.uid
		pv.from = from
		pv.ability = null
		pv.moveFirst = true
		view.ui.hover.preview = pv
		view.ui.hover.dest = from
		view.ui.hover.facing = 0
		hud.refresh()
		var t := _text_of(_node("Forecast"))
		assert_true(t.contains("%d%%" % int(pv.chance)), "chance")
		assert_true(t.contains("Move & attack"), "move first")
		assert_true(t.contains("Squad damage"), "damage")
		assert_true(t.contains("Destroy squad:"), "kill chance")
		assert_true(t.contains("Morale shock:"), "morale shock")
		assert_true(t.contains("Melee skill"), "modifiers")
		assert_true(t.contains("Arrives"), "arrival note")
		assert_true(t.contains("Move the cursor around the target"), "hint")
	# Hovering a squad without a preview: its info card.
	view.ui.hover.preview = null
	view.ui.hover.unit = target.uid
	hud.refresh()
	var ui_t := _text_of(_node("UnitInfo"))
	assert_true(ui_t.contains(Panels.squad_title(target)), "unit info title")
	assert_true(ui_t.contains("HP each"), "hp each")
	# Hovering a tile.
	view.ui.hover.unit = null
	view.ui.hover.tile = {"x": int(sel.x), "y": int(sel.y)}
	view.ui.hover.dest = {"x": int(sel.x), "y": int(sel.y)}
	view.ui.hover.facing = 1
	view.ui.hover.facings = [1, 2]
	view.ui.hover.zoc = 1
	hud.refresh()
	var tt := _text_of(_node("TileInfo"))
	assert_true(tt.contains("Move cost") or tt.contains("Passable") or tt.contains("Impassable"), "tile line: " + tt)
	assert_true(tt.contains("Q / E or point at an edge: other sides (2)"), "facings")
	assert_true(tt.contains("This path leaves enemy reach: 1 free attack(s)."), "zoc")
	view.ui.hover = {"tile": null, "unit": null, "preview": null, "path": null, "zoc": null, "dest": null, "facing": null, "facings": null, "turn": null}
	hud.refresh()
	assert_null(_node("TileInfo"), "nothing hovered: no panel")
	assert_null(_node("Forecast"))


func test_enemy_turn() -> void:
	_open()
	_begin()
	var b0 = view.b
	_button("EndTurn").pressed.emit()
	# Mid-playback: the enemy's move, End Turn and Retreat disabled.
	var saw_enemy := false
	for i in 4000:
		if not view.busy():
			break
		view.advance(0.05)
		hud.refresh()
		if view.ui.side == "enemy":
			var t := _text_of(_node("TopBar"))
			if t.contains("Enemy move"):
				saw_enemy = true
				var et := _button("EndTurn")
				if et != null:
					assert_true(et.disabled, "End Turn disabled during the enemy turn")
				var r := _button("Retreat")
				if r != null:
					assert_true(r.disabled, "Retreat disabled during the enemy turn")
				break
	assert_true(saw_enemy, "the enemy turn is shown")
	_settle()
	if view.b.phase == "player":
		assert_true(_text_of(_node("TopBar")).contains("Turn 2 · Your move"), "turn 2")


func test_retreat_confirmation_and_end() -> void:
	_open()
	_begin()
	_button("Retreat").pressed.emit()
	hud.refresh()
	assert_true(hud.confirm_open(), "confirmation open")
	var c := _node("Confirm")
	assert_true(_text_of(c).contains("Withdraw from the field?"))
	_check_buttons("confirm")
	_button("FightOn").pressed.emit()
	assert_false(hud.confirm_open(), "Fight on closes it")
	_button("Retreat").pressed.emit()
	_button("Withdraw").pressed.emit()
	_settle()
	assert_eq(view.b.phase, "over", "battle over")
	assert_eq(view.b.result, "retreat")
	hud.refresh()
	var t := _text_of(_node("TopBar"))
	assert_true(t.contains("Battle over"), "over line: " + t)
	assert_null(_node("UnitPanel"), "no squad card after the battle")
	assert_true(_button("EndTurn").disabled, "End Turn disabled")
	assert_true(_text_of(_node("Banner")).contains("Withdrawal"), "end banner")


func test_objective_lines_last_stand() -> void:
	_open("last_stand")
	hud.refresh()
	var lines: Array = hud.objective_lines()
	var t := _text_of(_node("Objective"))
	assert_true(t.contains(str(view.b.objective.title)), "objective title")
	for l in lines:
		assert_true(t.contains(str(l.text)), "line " + str(l.text))
	if view.b.objective.get("turns"):
		assert_true(t.contains("Turn 1 of %d" % int(view.b.objective.turns)), "turns line")


# ---------------------------------------------------------------- mages and war machines

const SPECIALISTS := ["footman", "spearman", "battle_mage", "ballista", "mangonel", "crossbowman"]


func _open_specialists() -> void:
	_open("shaman_fire", false, _battle_with(SPECIALISTS))
	_begin()


func _of_type(t: String) -> Dictionary:
	for u in view.b.active("player"):
		if u.typeId == t:
			return u
	return {}


func _tip(n: Node) -> String:
	var t: Node = n.find_child("Tip", false, false) if n != null else null
	return str(t.content) if t != null else ""


func _clear_hover() -> void:
	view.ui.hover = {"tile": null, "unit": null, "preview": null, "spell": null, "path": null, "zoc": null, "dest": null, "facing": null, "facings": null, "turn": null}


func test_spell_buttons_and_unit_panel() -> void:
	_open_specialists()
	var b = view.b
	var mage := _of_type("battle_mage")
	if not assert_false(mage.is_empty(), "the mages are on the field"):
		return
	view.select(mage.uid)
	hud.refresh()
	var pt := _text_of(_node("UnitPanel"))
	assert_true(pt.contains("Casters"), "casters, not soldiers: " + pt)
	assert_true(pt.contains("Battle Mages"), "type label")
	assert_true(pt.contains("Arcane bolt 5–7 × 3 = 15–21"), "the mages' bolt: " + pt)
	assert_true(pt.contains("Melee 3–5 × 3 = 9–15"), "melee line")
	assert_true(pt.contains("Spell %s" % str(mage.stats.ranged)), "spell skill")
	assert_false(pt.contains("Bolts"), "no ammunition")
	# A button per spell, usable now, with its cadence and how to aim it.
	var list := Panels.abilities(mage)
	assert_eq(list, ["chain_lightning", "frost_blast", "healing_light"], "spells are active abilities")
	for i in list.size():
		var btn := _button("Ability_" + list[i])
		if assert_not_null(btn, list[i]):
			assert_true(H.button_text(btn).begins_with(str(i + 1)), "key number")
			assert_eq(btn.disabled, not b.can_cast(mage, list[i]).ok, list[i] + " enabled when it can be cast")
	var tl := _tip(_button("Ability_chain_lightning"))
	assert_true(tl.contains("every other turn"), "cooldown 2: " + tl)
	assert_true(tl.contains("Choose it, then click an enemy squad."), "aim hint")
	assert_true(_tip(_button("Ability_frost_blast")).contains("every 3 turns"), "cooldown 3")
	assert_true(_tip(_button("Ability_healing_light")).contains("Choose it, then click a friendly squad."), "heal aims at a friend")
	# Choosing a spell arms it.
	_button("Ability_chain_lightning").pressed.emit()
	hud.refresh()
	assert_eq(view.ui.ability, "chain_lightning", "spell chosen")
	assert_eq(str(_button("Ability_chain_lightning").theme_type_variation), "AbilityButtonActive")
	view.set_ability(null)
	# On cooldown: disabled, the turns on the button, no reason line.
	mage.cooldowns["chain_lightning"] = 2
	hud.refresh()
	var cl := _button("Ability_chain_lightning")
	assert_true(cl.disabled, "on cooldown")
	assert_true(_text_of(cl).contains("2"), "turns left shown")
	assert_false(_tip(cl).contains("Ready in"), "no reason line for a cooldown")
	mage.cooldowns.erase("chain_lightning")
	# Too shaken to cast.
	var keep: int = mage.morale
	mage.morale = maxi(1, int(mage.maxMorale * 0.1))
	hud.refresh()
	assert_eq(b.morale_state(mage), "wavering")
	for a in list:
		assert_true(_button("Ability_" + a).disabled, a + " disabled when wavering")
	assert_true(_tip(_button("Ability_frost_blast")).contains("Too shaken"), "reason: " + _tip(_button("Ability_frost_blast")))
	mage.morale = keep
	_check_buttons("mages")

	# The ballista: its crew, its bolt, no ability buttons.
	var bal := _of_type("ballista")
	view.select(bal.uid)
	hud.refresh()
	pt = _text_of(_node("UnitPanel"))
	assert_true(pt.contains("Crew"), "crew line")
	assert_true(pt.contains("Ballista Crew"), "crew label: " + pt)
	assert_true(pt.contains("Bolt 20–26 × 3 = 60–78"), "the bolt: " + pt)
	assert_true(pt.contains("Crew %s" % str(bal.stats.ranged)), "crew skill")

	# The mangonel: its stone and the rule about moving.
	var mg := _of_type("mangonel")
	view.select(mg.uid)
	hud.refresh()
	pt = _text_of(_node("UnitPanel"))
	assert_true(pt.contains("Hurl Stone 10–14 × 3 = 30–42"), "the stone: " + pt)
	assert_true(pt.contains("Melee 2–4 × 3 = 6–12"), "melee after the stone")
	assert_true(pt.contains("Crew %s" % str(mg.stats.ranged)), "crew skill")
	var hs := _button("Ability_hurl_stone")
	if assert_not_null(hs, "stone button"):
		assert_false(hs.disabled, "can loose before moving")
		assert_false(_tip(hs).contains(" · every"), "no cooldown")
		assert_true(_tip(hs).contains("Choose it, then click a squad or a tile."), "aims at a tile")
	mg.movedTiles = 1
	hud.refresh()
	hs = _button("Ability_hurl_stone")
	assert_true(hs.disabled, "moved: cannot loose")
	assert_true(_tip(hs).contains("Cannot loose in a turn it has moved"), "reason: " + _tip(hs))
	mg.movedTiles = 0


## A real preview from the rules, whatever it says.
func test_spell_forecast_from_rules() -> void:
	_open_specialists()
	var b = view.b
	var mage := _of_type("battle_mage")
	view.select(mage.uid)
	view.set_ability("chain_lightning")
	var target: Dictionary = b.active("enemy")[0]
	var best := 1e9
	for e in b.active("enemy"):
		var d: float = absf(e.x - mage.x) + absf(e.y - mage.y)
		if d < best:
			best = d
			target = e
	var pv: Dictionary = b.spell_preview(mage, "chain_lightning", {"x": int(target.x), "y": int(target.y)})
	_clear_hover()
	view.ui.hover.spell = pv
	view.ui.hover.unit = target.uid
	hud.refresh()
	var sf := _node("SpellForecast")
	if assert_not_null(sf, "spell forecast"):
		var t := _text_of(sf)
		assert_true(t.contains("Chain Lightning"), "spell name")
		assert_true(t.contains("%d battle mages cast · 9–12 each" % int(pv.casters)), "casters and power: " + t)
		if pv.legal:
			assert_true(t.contains("Strikes home") and t.contains("%d%%" % int(pv.chance)), "chance")
			for h in pv.hits:
				assert_true(t.contains(Squad.squad_name(b.unit(h.uid))), "row for " + str(h.uid))
			assert_true(t.contains("Spell skill"), "modifiers")
		else:
			assert_true(t.contains(str(pv.reason)), "why not: " + t)
	assert_null(_node("UnitInfo"), "the spell forecast takes the hover panel")


## The forecast's rows from a preview: damage, arcs, splash on friends, healing, conditions.
func test_spell_forecast_rows() -> void:
	_open_specialists()
	var b = view.b
	var mage := _of_type("battle_mage")
	var foes: Array = b.active("enemy")
	var friend := _of_type("footman")
	view.select(mage.uid)
	_clear_hover()
	view.ui.hover.spell = {"legal": true, "ability": "chain_lightning", "at": {"x": int(foes[0].x), "y": int(foes[0].y)}, "chance": 86,
		"mods": [["Spell skill", 74], ["Target defense", -8], ["The spell seeks its mark", 15], ["Confident", 5]], "casters": 3,
		"hits": [{"uid": foes[0].uid, "role": "main", "min": 27, "max": 36, "heal": false, "ally": false, "soldiers": [1, 2], "kill": 0},
			{"uid": foes[1].uid, "role": "chain", "min": 15, "max": 21, "heal": false, "ally": false, "soldiers": [1, 1], "kill": 0},
			{"uid": friend.uid, "role": "splash", "min": 9, "max": 12, "heal": false, "ally": true, "soldiers": [0, 1], "kill": 0}],
		"scatter": false, "moraleHit": 12}
	# The spell forecast comes before an attack preview.
	view.ui.hover.preview = {"legal": false, "reason": "Out of reach", "target": foes[0].uid}
	hud.refresh()
	assert_null(_node("Forecast"), "no attack forecast under a spell")
	var sf := _node("SpellForecast")
	if not assert_not_null(sf, "spell forecast"):
		return
	var t := _text_of(sf)
	assert_true(t.contains("3 battle mages cast · 9–12 each"), "head: " + t)
	assert_true(t.contains("Strikes home") and t.contains("86%"), "chance")
	assert_true(t.contains(Squad.squad_name(foes[0])) and t.contains("27–36 · slays 1–2"), "main row: " + t)
	assert_true(t.contains("arc: ") and t.contains("15–21 · slays 1"), "arc row")
	assert_true(t.contains("beside: ") and t.contains("9–12 · slays 0–1"), "friendly row")
	assert_true(t.contains("Your own squad stands in the blast!"), "friendly fire warning")
	assert_false(t.contains("A miss lands"), "lightning does not scatter")
	var own: Node = sf.find_child("Hit_" + str(friend.uid), true, false)
	if assert_not_null(own, "friendly row"):
		var name_label: Label = null
		for l in own.find_children("*", "Label", true, false):
			if (l as Label).text == Squad.squad_name(friend):
				name_label = l
		assert_true(name_label != null and name_label.get_theme_color("font_color") == Panels.OWN_HIT, "friends caught in orange")
		assert_true(own.tooltip_text.contains("standing"), "row tooltip")
	var mt := _text_of(sf.find_child("Mods", true, false))
	assert_true(mt.contains("Spell skill") and mt.contains("74") and not mt.contains("+74"), "skill plain: " + mt)
	assert_true(mt.contains("+15") and mt.contains("-8"), "bonus and penalty")

	# Healing: certain, the wounds it closes.
	view.ui.hover.spell = {"legal": true, "ability": "healing_light", "at": {"x": int(friend.x), "y": int(friend.y)}, "chance": 100, "mods": [], "casters": 2,
		"hits": [{"uid": friend.uid, "role": "main", "min": 16, "max": 22, "heal": true, "ally": true, "soldiers": [0, 0], "kill": 0}], "scatter": false, "moraleHit": 0}
	hud.refresh()
	t = _text_of(_node("SpellForecast"))
	assert_true(t.contains("2 battle mages cast · heals 8–11 each"), "heal head: " + t)
	assert_true(t.contains("Certain") and t.contains("100%"), "certain")
	assert_true(t.contains("+16–22"), "healing")
	assert_false(t.contains("in the blast"), "healing is no friendly fire")

	# Frost: the chill note. Gutripper: the bleeding note. Bloodlust: the condition in the row.
	view.ui.hover.spell = {"legal": true, "ability": "frost_blast", "at": {"x": 0, "y": 0}, "chance": 70, "mods": [], "casters": 3,
		"hits": [{"uid": foes[0].uid, "role": "main", "min": 15, "max": 21, "heal": false, "ally": false, "soldiers": [0, 1], "kill": 0}], "scatter": false, "moraleHit": 4}
	hud.refresh()
	assert_true(_text_of(_node("SpellForecast")).contains("Everyone struck is chilled: Half movement"), "chill note")
	var gut: Dictionary = view.ui.hover.spell.duplicate(true)
	gut.ability = "gutripper"
	view.ui.hover.spell = gut
	hud.refresh()
	assert_true(_text_of(_node("SpellForecast")).contains("The wound bleeds for 40% of the damage at the start of its next two turns."), "bleed note")
	view.ui.hover.spell = {"legal": true, "ability": "bloodlust", "at": {"x": 0, "y": 0}, "chance": 100, "mods": [], "casters": 3,
		"hits": [{"uid": friend.uid, "role": "main", "min": 0, "max": 0, "heal": false, "ally": true, "soldiers": [0, 0], "kill": 0}], "scatter": false, "moraleHit": 0}
	hud.refresh()
	t = _text_of(_node("SpellForecast"))
	assert_true(t.contains("Bloodlust") and t.contains("Certain"), "a blessing: " + t)
	# Nobody there; an illegal aim says why.
	view.ui.hover.spell = {"legal": true, "ability": "chain_lightning", "at": {"x": 0, "y": 0}, "chance": 50, "mods": [], "casters": 3, "hits": [], "scatter": false, "moraleHit": 0}
	hud.refresh()
	assert_true(_text_of(_node("SpellForecast")).contains("Nobody stands where it would land."), "empty")
	view.ui.hover.spell = {"legal": false, "reason": "No line of sight", "ability": "chain_lightning", "at": {"x": 0, "y": 0}, "chance": 100, "mods": [], "casters": 3, "hits": [], "scatter": false, "moraleHit": 0}
	hud.refresh()
	t = _text_of(_node("SpellForecast"))
	assert_true(t.contains("No line of sight") and not t.contains("Strikes home"), "reason only")

	# A mangonel's stone: its crew at the engine, the scatter note.
	var mg := _of_type("mangonel")
	view.select(mg.uid)
	view.ui.hover.spell = {"legal": true, "ability": "hurl_stone", "at": {"x": int(foes[0].x), "y": int(foes[0].y)}, "chance": 53,
		"mods": [["Crew skill", 62], ["Target defense", -2], ["Long range", -12]], "casters": 3,
		"hits": [{"uid": foes[0].uid, "role": "main", "min": 30, "max": 42, "heal": false, "ally": false, "soldiers": [4, 5], "kill": 0.1}], "scatter": true, "moraleHit": 10}
	hud.refresh()
	t = _text_of(_node("SpellForecast"))
	assert_true(t.contains("3 crewmen at the engine · 10–14 each"), "crew head: " + t)
	assert_true(t.contains("A miss lands one tile astray, and still strikes whoever stands there."), "scatter")
	assert_true(t.contains("53%") and t.contains("30–42 · slays 4–5"), "stone row")
	_clear_hover()
	hud.refresh()
	assert_null(_node("SpellForecast"), "gone with the hover")


func test_conditions_and_hover_card() -> void:
	_open_specialists()
	var b = view.b
	var mage := _of_type("battle_mage")
	var foe: Dictionary = b.active("enemy")[0]
	view.select(mage.uid)
	mage.statuses = [{"id": "bleeding", "turns": 2, "power": 5, "by": foe.uid}]
	var mv = view.views.get(mage.uid)
	if mv != null and "statuses" in mv:
		mv.statuses = ["bleeding"]
	hud.refresh()
	var chip := _node("Status_bleeding")
	if assert_not_null(chip, "bleeding chip on the squad's card"):
		assert_true(_text_of(chip).contains("Bleeding"))
		var tip := _tip(chip)
		assert_true(tip.contains("(−5 a turn, 2 more)") and tip.contains("Loses HP"), "tip: " + tip)
	assert_true(_text_of(_node("Mini_" + str(mage.uid))).contains("Bleeding"), "the company card shows it")
	# A hovered enemy: chilled, its abilities and cooldowns.
	foe.statuses = [{"id": "chilled", "turns": 1}]
	_clear_hover()
	view.ui.hover.unit = foe.uid
	hud.refresh()
	var info := _node("UnitInfo")
	if assert_not_null(info, "unit info"):
		assert_true(_text_of(info).contains("Chilled"), "condition chip")
		var c2: Node = info.find_child("Status_chilled", true, false)
		assert_true(c2 != null and _tip(c2).contains("Half movement"), "what it does")
	# The mages hovered: spells with their cooldowns, "Spells" skill and range.
	mage.cooldowns["frost_blast"] = 2
	view.ui.hover.unit = mage.uid
	hud.refresh()
	var it := _text_of(_node("UnitInfo"))
	assert_true(it.contains("Chain Lightning, Frost Blast (ready in 2), Healing Light"), "spells and cooldowns: " + it)
	assert_true(it.contains("Arcane bolt 5–7 × 3 = 15–21 · Melee"), "shot name")
	assert_true(it.contains("Spells %s, range 5" % str(mage.stats.ranged)), "spells skill: " + it)
	assert_true(it.contains("Bleeding"), "own condition")
	# A mangonel hovered: its stone.
	view.ui.hover.unit = _of_type("mangonel").uid
	hud.refresh()
	assert_true(_text_of(_node("UnitInfo")).contains("Hurl Stone 10–14 × 3 = 30–42 · Melee"), "stone line")
	mage.statuses = []
	foe.statuses = []
	if mv != null and "statuses" in mv:
		mv.statuses = []
	hud.refresh()
	assert_null(_node("Status_bleeding"), "chips go with the condition")


func test_squad_skill_buttons() -> void:
	# The squad skills on the bar (../../docs/squad-skills.md): one word per
	# button and no two alike, Lick Wounds held back while an enemy stands
	# beside the hounds, an Aimed Shot only before the squad moves; each says why.
	_open("goblin_scouts", false, _battle_with(["footman", "spearman", "crossbowman", "collie_guard"], "goblin_scouts", 11, 3))
	_begin()
	var b = view.b
	var f := _of_type("footman")
	f.abilities.append("shieldbash")
	view.select(f.uid)
	hud.refresh()
	var words: Array = []
	for a in Panels.abilities(f):
		var w := _text_of(_button("Ability_" + a)).strip_edges()
		assert_false(words.has(w), "a word of its own: " + w)
		words.append(w)
	assert_eq(words.size(), 4, "four keys: %s" % [words])
	var c := _of_type("collie_guard")
	assert_eq(Panels.abilities(c), ["growl", "hound_charge", "defend", "lick_wounds"])
	view.select(c.uid)
	hud.refresh()
	for a in Panels.abilities(c):
		assert_false(_button("Ability_" + a).disabled, a + " usable")
	# An enemy beside the hounds: no licking wounds, and the reason.
	# The panel stays selected: the enemy's step alone must refresh the button.
	var foe: Dictionary = b.active("enemy")[0]
	var home := {"x": foe.x, "y": foe.y}
	for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
		var x: int = c.x + d[0]
		var y: int = c.y + d[1]
		if Grid.tile_passable(b.map, x, y) and Grid.unit_at(b.units, x, y) == null:
			foe.x = x
			foe.y = y
			break
	hud.refresh()
	var lick := _button("Ability_lick_wounds")
	assert_true(lick.disabled, "an enemy beside them")
	assert_true(_tip(lick).contains("Not with an enemy beside them."), _tip(lick))
	foe.x = home.x
	foe.y = home.y
	hud.refresh()
	assert_false(_button("Ability_lick_wounds").disabled, "the enemy stepped away")
	# An aimed shot waits for a squad that has not moved.
	var xb := _of_type("crossbowman")
	view.select(xb.uid)
	hud.refresh()
	assert_false(_button("Ability_aimed_shot").disabled, "before moving")
	for k in b.reachable(xb):
		var p := {"x": int(k) % 1000, "y": int(k) / 1000}
		if (p.x != xb.x or p.y != xb.y) and b.move(xb.uid, p.x, p.y):
			break
	_settle()
	view.select(xb.uid)
	hud.refresh()
	var aim := _button("Ability_aimed_shot")
	assert_true(aim.disabled, "after moving")
	assert_true(_tip(aim).contains("Only in a turn the squad has not moved."), _tip(aim))
