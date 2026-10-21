## The App store (port of src/ui/store.ts) driven through the game's flow:
## new game → base → prep → launch → campaign → battle → campaign → home →
## report → base, plus panels, manual, soldier, menu and the automation API.
## World views are off (App.use_views = false): this tests the store alone.
extends "res://tests/test_case.gd"

const Game = preload("res://scripts/meta/game.gd")
const Ex = preload("res://scripts/campaign/expedition.gd")
const Setup = preload("res://scripts/rules/setup.gd")
const Rng = preload("res://scripts/core/rng.gd")
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


func test_full_flow_with_battle() -> void:
	App.new_game(1234)
	App.go_prep()
	assert_eq(App.screen, "prep")
	var c := _launch_default()
	assert_eq(App.screen, "campaign")
	assert_not_null(App.game.expedition, "expedition started")
	assert_eq(App.game.cycle, 1)
	# Stage a battle as the campaign would after a march.
	var ex: Dictionary = App.game.expedition
	ex.pending = {"kind": "battle", "nodeId": ex.current, "roll": Setup.roll_encounter("raiding_party", Rng.new(3), 1), "title": "Test Field", "objective": false, "surprise": false}
	Prefs.set_pref("manualSeen", false)
	App.start_battle()
	assert_eq(App.screen, "battle")
	assert_not_null(App.battle, "battle created")
	assert_eq(App.battle_info.title, "Test Field")
	assert_eq(App.manual, "battle", "the manual opens before the first battle")
	App.open_manual(null)
	var b: RefCounted = App.battle
	App.debug_auto_battle()
	assert_eq(App.screen, "campaign", "back on the map after the battle")
	assert_true(b.is_over(), "fought to the end")
	assert_eq(App.battle_info, null, "battle settled")
	var p: Variant = App.game.expedition.get("pending") if App.game.expedition != null else null
	if p != null:
		assert_eq(p.kind, "battleResult")
		App.dismiss()
	if App.screen == "campaign":
		App.go_home("retreat")
	assert_eq(App.screen, "report")
	assert_not_null(App.report)
	assert_eq(App.report.campaignId, c.id)
	assert_null_expedition()
	App.go_base()
	assert_eq(App.screen, "base")
	assert_eq(App.game.lastReport.campaignId, c.id)


func assert_null_expedition() -> void:
	assert_true(App.game.expedition == null, "expedition over")


func test_click_node_and_deny() -> void:
	App.new_game(99)
	_launch_default()
	var ex: Dictionary = App.game.expedition
	var marches: int = ex.marches
	App.click_node("no-such-node")
	assert_eq(App.game.expedition.marches, marches, "a refused march changes nothing")
	var nxt: Array = Ex.next_nodes(ex)
	assert_true(nxt.size() > 0, "a road ahead")
	App.click_node(nxt[0].id)
	assert_eq(App.game.expedition.current, nxt[0].id, "marched")
	assert_eq(App.game.expedition.marches, marches + 1)


func test_auto_prepare_and_expedition() -> void:
	App.new_game(4321)
	assert_true(App.debug_auto_prepare(2), "auto prepare")
	assert_eq(App.screen, "campaign")
	App.debug_auto_expedition(2)
	assert_eq(App.screen, "report")
	assert_not_null(App.report)
	assert_true(App.game.expedition == null)
	assert_true(["success", "retreat", "defeat"].has(App.report.outcome), "outcome")


func test_debug_test_battle() -> void:
	App.new_game(5)
	App.debug_test_battle("raiding_party", {"seed": 3})
	assert_eq(App.screen, "battle")
	assert_not_null(App.battle)
	assert_eq(App.battle_info, null, "stand-alone battle")
	App.battle.begin(func(b): load("res://scripts/rules/ai.gd").run_enemy_ai(b))
	App.debug_player_turn()
	assert_true(App.battle.turn >= 1)


func test_quit_to_title_saves() -> void:
	App.new_game(11)
	App.game.resources.silver = 777
	App.quit_to_title()
	assert_eq(App.screen, "title")
	App.game = null
	App.continue_game()
	assert_eq(App.screen, "base")
	assert_eq(App.game.resources.silver, 777, "saved before leaving")


func test_continue_into_campaign() -> void:
	App.new_game(12)
	_launch_default()
	App.game = null
	App.go_title()
	App.continue_game()
	assert_eq(App.screen, "campaign", "a save with an expedition continues on the map")
