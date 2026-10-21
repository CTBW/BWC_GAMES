## Saves: round trip through user:// JSON, version check, migration of a save
## from before squads, has_save / continue.
extends "res://tests/test_case.gd"

const Game = preload("res://scripts/meta/game.gd")
const DB = preload("res://scripts/data/db.gd")

const SAVE := "user://test_save_flow.json"


func before_each() -> void:
	App.use_views = false
	App.save_path = SAVE
	App.game = null
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))


func after_all() -> void:
	before_each()
	App.use_views = true
	App.save_path = App.SAVE_PATH


func _write(text: String) -> void:
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_round_trip() -> void:
	assert_false(App.has_save(), "no save yet")
	App.game = Game.new_game(2024)
	App.game.resources.silver = 333
	App.game.roster[0].name = "Åke Ölund"
	App.game.roster[1].armorCondition = 0.625
	var before := JSON.stringify(App.game)
	App.save()
	assert_true(App.has_save())
	App.game = null
	assert_true(App.load_save(), "loads")
	assert_eq(App.game.resources.silver, 333)
	assert_eq(App.game.roster[0].name, "Åke Ölund", "unicode names survive")
	assert_almost(App.game.roster[1].armorCondition, 0.625)
	assert_true(App.game.roster[0].hp is int, "integral numbers load as ints")
	assert_eq(JSON.stringify(App.game), before, "identical after the round trip")


func test_round_trip_with_expedition() -> void:
	App.game = Game.new_game(77)
	App.debug_auto_prepare(3)
	var ex_before := JSON.stringify(App.game.expedition)
	App.save()
	App.game = null
	assert_true(App.load_save())
	assert_eq(JSON.stringify(App.game.expedition), ex_before, "expedition kept")


func test_wrong_version_or_garbage_is_refused() -> void:
	var g := Game.new_game(1)
	g.version = Game.SAVE_VERSION + 1
	_write(JSON.stringify(g))
	assert_false(App.load_save(), "other version")
	assert_eq(App.game, null)
	_write("not json {")
	assert_false(App.load_save(), "garbage")
	_write("")
	assert_false(App.has_save(), "an empty file is no save")
	App.continue_game()
	assert_eq(App.game, null, "continue does nothing without a save")


func test_migrates_pre_squad_save() -> void:
	var g := Game.new_game(3)
	# A save from before squads: one soldier's HP, no `men`.
	for so in g.roster:
		so.erase("men")
		so.hp = 20
	_write(JSON.stringify(g))
	assert_true(App.load_save())
	for so in App.game.roster:
		assert_eq(so.men, DB.squad_size(so.typeId), "each becomes a full squad")
		assert_true(so.hp > 20, "with a squad's HP")


func test_continue_game() -> void:
	App.new_game(55)
	App.game.flags = {"welcome": true}
	App.commit()
	App.game = null
	App.screen = "title"
	App.continue_game()
	assert_eq(App.screen, "base")
	assert_eq(App.game.seed, 55)
	assert_true(App.game.flags.welcome, "flags kept")
