## Ferns under the trees, fallen wood at their feet and small stones on open
## ground (scripts/render/battle_draw.gd, MIGRATION.md "Terrain kit 2"): drawn
## for show, never part of the map.
extends "res://tests/test_case.gd"

const JS = preload("res://scripts/core/js.gd")
const Rng = preload("res://scripts/core/rng.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const ViewScene = preload("res://scenes/battle/battle_view.tscn")


func _fixture(name: String) -> Dictionary:
	var f := FileAccess.open("res://tests/fixtures/battle_view/setups/%s.json" % name, FileAccess.READ)
	return JS.normalize(JSON.parse_string(f.get_as_text()))


func _view(b):
	var v = ViewScene.instantiate()
	v.threaded_rules = false
	v.setup(b)
	(Engine.get_main_loop() as SceneTree).root.add_child(v)
	return v


func _decor(v, key: String) -> Array:
	return v._draw._prop_list().filter(func(pr): return pr != null and pr.get("decor") == key)


func test_ferns_stand_on_forest_tiles_and_leave_the_map_alone() -> void:
	var total := 0
	for name in ["trolls", "night_torch", "last_stand"]:
		var b = Battle.new(_fixture(name).setup)
		var v = _view(b)
		var before := JSON.stringify(b.map)
		var want := 0
		for t in b.map.tiles:
			if t.terrain == "forest" and Rng.hash2(t.x, t.y, 817) <= 0.65:
				want += 1
		var ferns: Array = _decor(v, "fern")
		assert_eq(ferns.size(), want, "%s: one fern on each chosen forest tile" % name)
		for pr in ferns:
			var t = Grid.tile_at(b.map, roundi(pr.x), roundi(pr.y))
			assert_true(t != null and t.terrain == "forest", "%s: fern at %.2f,%.2f stands on a forest tile" % [name, pr.x, pr.y])
			assert_true(absf(pr.x - roundi(pr.x)) <= 0.33 and absf(pr.y - roundi(pr.y)) <= 0.33, "%s: fern within its tile" % name)
			assert_false(pr.tree or pr.flip, "%s: a fern neither sways nor mirrors" % name)
			assert_true(String(pr.s.file).ends_with("woodland_fern.webp"), "%s: painted fern" % name)
		assert_eq(JSON.stringify(b.map), before, "%s: the map is unchanged" % name)
		total += ferns.size()
		v.get_parent().remove_child(v)
		v.free()
	assert_true(total > 10, "the forests have ferns (%d)" % total)


func test_fallen_wood_and_stones_are_scenery_only() -> void:
	var wood := 0
	var stones := 0
	for name in ["trolls", "night_torch", "last_stand"]:
		var b = Battle.new(_fixture(name).setup)
		var v = _view(b)
		var before := JSON.stringify(b.map)
		var trees := 0
		for pr in _decor(v, "deadwood"):
			# Toward the camera from the trunk, inside the tree's own tile.
			var t = Grid.tile_at(b.map, roundi(pr.x), roundi(pr.y))
			assert_true(t != null and String(t.get("prop", "")).begins_with("tree"), "%s: fallen wood at %.2f,%.2f lies under a tree" % [name, pr.x, pr.y])
			var dx: float = pr.x - roundi(pr.x)
			var dy: float = pr.y - roundi(pr.y)
			assert_true(dx > 0.0 and dy > 0.0 and dx < 0.37 and dy < 0.37, "%s: fallen wood on the near side of its trunk" % name)
			assert_true(String(pr.s.file).contains("/painted/woodland_"), "%s: painted fallen wood" % name)
			assert_false(pr.tree or pr.flip, "%s: fallen wood neither sways nor mirrors" % name)
			wood += 1
		for t in b.map.tiles:
			if t.get("prop") != null and String(t.prop).begins_with("tree"):
				trees += 1
		assert_true(_decor(v, "deadwood").size() < trees, "%s: only some trees have fallen wood" % name)
		for pr in _decor(v, "stones"):
			var t = Grid.tile_at(b.map, roundi(pr.x), roundi(pr.y))
			assert_true(t != null and t.get("prop") == null and t.terrain in ["grass", "dirt"], "%s: stones at %.2f,%.2f lie on open ground" % [name, pr.x, pr.y])
			assert_true(absf(pr.x - roundi(pr.x)) <= 0.3 and absf(pr.y - roundi(pr.y)) <= 0.3, "%s: stones within their tile" % name)
			assert_true(String(pr.s.file).contains("/painted/stones_"), "%s: painted stones" % name)
			stones += 1
		assert_eq(JSON.stringify(b.map), before, "%s: the map is unchanged" % name)
		v.get_parent().remove_child(v)
		v.free()
	assert_true(wood > 3, "the forests have fallen wood (%d)" % wood)
	assert_true(stones > 3, "the open ground has stones (%d)" % stones)
