## The data tables load from res://data with ints for integral values.
extends "res://tests/test_case.gd"

const DB = preload("res://scripts/data/db.gd")


func test_tables_load() -> void:
	assert_true(DB.UNIT_TYPES.has("footman"), "footman defined")
	assert_true(DB.UNIT_TYPES.has("troll"), "troll defined")
	assert_eq(DB.DEFAULT_SQUAD_SIZE, 6)
	assert_eq(DB.squad_size("footman"), 6)
	assert_eq(DB.squad_size("troll"), 3)
	assert_true(DB.ABILITIES.size() > 5, "abilities")
	assert_true(DB.TERRAIN.has("grass"), "terrain grass")
	assert_true(DB.ENCOUNTERS.size() > 5, "encounters")
	assert_true(DB.EVENTS.size() > 5, "events")
	assert_true(DB.BATTLE_MAPS.size() > 2, "maps")
	assert_eq(DB.PLAYER_TYPES, ["footman", "spearman", "crossbowman"])
	assert_true(DB.UNIT_TYPES.footman.base.hp is int, "integral numbers load as int")
	assert_eq(DB.campaign_by_id(DB.CAMPAIGNS[0].id).id, DB.CAMPAIGNS[0].id)
