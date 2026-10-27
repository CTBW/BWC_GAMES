## The App store (port of src/ui/store.ts) driven through the game's flow:
## new game → base → prep → launch → the battle → home → report → base,
## plus panels, manual, soldier, menu and the automation API. The expedition is
## one battle for now (the campaign map is set aside while the game is
## redesigned): the turn-based rules on Ashby farm, one of the 3D battlefields.
## World views are off (App.use_views = false): this tests the store alone;
## battles are settled with App.debug_settle_battle or fought by the AI.
extends "res://tests/test_case.gd"

const Game = preload("res://scripts/meta/game.gd")
const Prefs = preload("res://scripts/core/prefs.gd")

const SAVE := "user://test_app_flow_save.json"

var _manual_seen: Variant


func before_all() -> void:
	_manual_seen = Prefs.prefs().get("manualSeen", false)


func before_each() -> void:
	App.use_views = false
	App.save_path = SAVE
	App.game = null
	App.screen = "title"
	App.panel = null
	App.soldier = null
	App.manual = null
	App.menu_open = false
	App.report = null
	App.battle_info = null
	App.battle = null
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))


func after_all() -> void:
	before_each()
	App.use_views = true
	App.save_path = App.SAVE_PATH
	Prefs.set_pref("manualSeen", _manual_seen)


func _launch_default() -> Dictionary:
	var g: Dictionary = App.game
	var c: Dictionary = Game.available_campaigns(g)[0]
	var army: Array = []
	for so in g.roster.slice(0, 5):
		army.append(so.id)
	var sup: Dictionary = Game.recommended_supplies(army.size(), 1, Game.wagon_capacity(g), c.stages + 1)
	var cost: int = Game.supply_cost_total(g, sup)
	App.launch(c.id, army, sup, cost)
	return c


func test_new_game_to_base() -> void:
	var count := [0]
	var f := func(): count[0] += 1
	App.changed.connect(f)
	App.new_game(1234)
	App.changed.disconnect(f)
	assert_eq(App.screen, "base")
	assert_not_null(App.game)
	assert_eq(App.game.seed, 1234)
	assert_eq(App.game.roster.size(), 6)
	assert_true(count[0] >= 1, "changed emitted")
	assert_true(App.has_save(), "new game is saved")


func test_panels_manual_soldier_menu() -> void:
	App.new_game(7)
	App.open_panel("barracks")
	assert_eq(App.panel, "barracks")
	App.open_panel(null)
	assert_eq(App.panel, null)
	App.open_panel("")
	assert_eq(App.panel, null, "empty id closes")
	App.open_soldier(App.game.roster[0].id)
	assert_eq(App.soldier, App.game.roster[0].id)
	App.open_soldier(null)
	assert_eq(App.soldier, null)
	App.open_manual("squads")
	assert_eq(App.manual, "squads")
	App.open_manual(null)
	assert_eq(App.manual, null)
	assert_true(App.manual_seen(), "closing the manual marks it seen")
	App.open_menu(true)
	assert_true(App.menu_open)
	App.open_menu(false)
	assert_false(App.menu_open)
	App.go_title()
	assert_eq(App.screen, "title")


func test_launch_takes_the_field_and_a_victory_goes_home() -> void:
	App.new_game(1234)
	App.go_prep()
	assert_eq(App.screen, "prep")
	var c := _launch_default()
	assert_eq(App.screen, "battle", "the army marches straight onto the field")
	assert_not_null(App.game.expedition, "expedition started")
	assert_eq(App.game.cycle, 1)
	assert_eq(App.battle_info.title, "Ashby farm")
	Prefs.set_pref("manualSeen", false)
	assert_eq(App.manual, null, "the manual of the old battles does not open")
	App.debug_settle_battle("victory")
	assert_eq(App.screen, "report")
	assert_eq(App.battle_info, null, "battle settled")
	assert_null_expedition()
	assert_eq(App.report.campaignId, c.id)
	assert_eq(App.report.outcome, "success", "a victory is the expedition's success")
	assert_eq(App.game.roster.size(), 6, "nobody fell")
	App.go_base()
	assert_eq(App.screen, "base")
	assert_eq(App.game.lastReport.campaignId, c.id)


func test_defeat_loses_the_army() -> void:
	App.new_game(77)
	_launch_default()
	var army: Array = App.game.expedition.army.duplicate()
	App.debug_settle_battle("defeat")
	assert_eq(App.screen, "report")
	assert_eq(App.report.outcome, "defeat")
	for id in army:
		assert_true(App.game.roster.all(func(s): return s.id != id), "%s fell" % id)
	assert_true(App.game.fallen.size() >= army.size(), "remembered among the fallen")


func test_finish_battle_without_a_view_withdraws() -> void:
	App.new_game(31)
	_launch_default()
	var men := 0
	for s in App.game.roster:
		men += int(s.men)
	App.finish_battle()
	assert_eq(App.screen, "report")
	assert_eq(App.report.outcome, "retreat", "no battle fought: the company withdraws")
	var after := 0
	for s in App.game.roster:
		after += int(s.men)
	assert_eq(after, men, "nobody lost")


func test_auto_battle_is_fought_by_the_rules_and_applied() -> void:
	App.new_game(8)
	_launch_default()
	var b = App.battle
	assert_not_null(b, "a rules battle")
	assert_eq(b.map.id, "ashby", "on Ashby farm")
	assert_eq(b.phase, "deploy", "the company deploys first")
	assert_eq(b.setup.encounterId, App.FIELD_ENCOUNTER)
	assert_eq(App.game.expedition.pending.kind, "battle", "the battle is the expedition's pending one")
	var battles: int = App.game.roster.reduce(func(n, s): return n + int(s.battles), 0)
	App.debug_auto_battle()
	assert_eq(b.phase, "over", "fought to the end, turn by turn")
	assert_eq(App.screen, "report")
	assert_eq(App.report.outcome, {"victory": "success", "retreat": "retreat"}.get(b.result, "defeat"))
	var after: int = App.game.roster.reduce(func(n, s): return n + int(s.battles), 0)
	assert_true(after > battles, "the battle counted for the squads that fought it")


func assert_null_expedition() -> void:
	assert_true(App.game.expedition == null, "expedition over")


func test_auto_prepare_opens_the_battle() -> void:
	App.new_game(4321)
	assert_true(App.debug_auto_prepare(2), "auto prepare")
	assert_eq(App.screen, "battle")
	assert_not_null(App.game.expedition)
	App.debug_settle_battle("retreat")
	assert_eq(App.screen, "report")
	assert_eq(App.report.outcome, "retreat")


func test_debug_test_battle() -> void:
	App.new_game(5)
	App.debug_test_battle({"seed": 3, "army": ["footman", "spearman"], "level": 2})
	assert_eq(App.screen, "battle")
	assert_eq(App.battle_info, null, "stand-alone battle")
	App.finish_battle()
	assert_eq(App.screen, "base", "a stand-alone battle goes back to the base")
	assert_eq(App.game.roster.size(), 6, "the roster is untouched")


func test_quit_to_title_saves() -> void:
	App.new_game(11)
	App.game.resources.silver = 777
	App.quit_to_title()
	assert_eq(App.screen, "title")
	App.game = null
	App.continue_game()
	assert_eq(App.screen, "base")
	assert_eq(App.game.resources.silver, 777, "saved before leaving")


func test_continue_into_the_battle() -> void:
	App.new_game(12)
	_launch_default()
	var roll: Dictionary = App.game.expedition.pending.roll
	var units: Array = App.battle.units.map(func(u): return [u.typeId, u.x, u.y])
	App.game = null
	App.go_title()
	App.continue_game()
	assert_eq(App.screen, "battle", "a save with an expedition continues on the field")
	assert_eq(App.game.expedition.pending.roll, roll, "the same warband")
	assert_eq(App.battle.units.map(func(u): return [u.typeId, u.x, u.y]), units, "drawn up the same way")
