## The battle HUD (scripts/ui/battle_hud.gd + hud_battle_panels.gd, port of
## `BattleHud` in src/ui/screens/Battle.tsx) over a real battle view showing a
## Battle from Setup.build_battle: deployment, the selected squad's card, the
## attack preview, hovered squad / tile panels, the enemy turn, the retreat
## confirmation and the end of the battle; every button wired or deliberately
## disabled. The view runs its rules synchronously (threaded_rules = false) and
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
	return Battle.new(Setup.build_battle(roll, army, {"survivalBonus": 0, "title": "Test battle"}))


func _open(encounter := "goblin_scouts", promoted := false) -> void:
	host = Control.new()
	host.theme = ThemeBuilder.theme()
	host.size = Vector2(1920, 1080)
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	store = FakeStore.new()
	host.add_child(store)
	view = load("res://scenes/battle/battle_view.tscn").instantiate()
	view.threaded_rules = false
	view.setup(_battle(encounter, 7, promoted))
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
	assert_true(t.contains("Enemy squads: %d on the field" % b.active("enemy").size()), "enemy count: " + t)
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
