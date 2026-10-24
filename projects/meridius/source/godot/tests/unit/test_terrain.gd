## Terrain layer (src/render/terrain.ts buildTerrain): builds on every battle
## map template and palette, with the original's layer geometry, water and
## CPU noise. The pixels are compared in the windowed capture
## (tests/visual/capture_terrain.gd) against the original's layers.
extends "res://tests/test_case.gd"

const Terrain = preload("res://scripts/render/terrain.gd")
const Rng = preload("res://scripts/core/rng.gd")
const DB = preload("res://scripts/data/db.gd")

var maps: Dictionary
var values: Dictionary


func before_all() -> void:
	maps = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/render/battle_maps.json"))
	values = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/render/render_values.json"))


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func test_fbm_matches_original() -> void:
	for r in values.fbm:
		assert_almost(Terrain.fbm(r[0], r[1], r[2]), r[3], 1e-12, "fbm(%s, %s, %s)" % [r[0], r[1], r[2]])


func test_layer_geometry_matches_original() -> void:
	for name in maps:
		var m: Dictionary = maps[name]
		var layer: Node2D = Terrain.build_terrain(m.terrainInput)
		assert_eq(layer.ox, int(m.layer.ox), name + " ox")
		assert_eq(layer.oy, int(m.layer.oy), name + " oy")
		assert_eq(layer.width, int(m.layer.w), name + " width")
		assert_eq(layer.height, int(m.layer.h), name + " height")
		assert_almost(layer.layer_scale, float(m.layer.scale), 1e-9, name + " scale")
		assert_eq(layer.water_tiles.size(), m.layer.waterTiles.size(), name + " water tiles")
		for i in layer.water_tiles.size():
			assert_eq(layer.water_tiles[i], m.layer.waterTiles[i], name + " water tile %d" % i)
		assert_eq(layer.water.size(), layer.water_tiles.size(), name + " water path")
		_root().add_child(layer)
		var water: Node2D = layer.make_water_node("battle")
		layer.add_child(water)
		layer.free()


func _synthetic(template: String, seed: int, palette: String) -> Dictionary:
	var tpl: Dictionary = DB.BATTLE_MAPS[template]
	var w: int = tpl.w
	var h: int = tpl.h
	var rng := Rng.new(seed)
	var kinds := ["grass", "grass", "dirt", "road", "brush", "forest", "stone", "water", "shallows", "bridge", "floor", "mud", "rubble"]
	var tiles: Array = []
	for y in h:
		for x in w:
			var hh := 0
			if x > 3 and y > 3 and x < w - 3 and y < h - 3:
				hh = rng.rint(0, 2)
			tiles.append({"x": x, "y": y, "h": hh, "terrain": rng.pick(kinds)})
	return {"w": w, "h": h, "border": 8 if tpl.get("scale", "") == "large" else 7, "tiles": tiles, "seed": seed, "palette": palette}


func test_every_template_and_palette_builds() -> void:
	var n := 0
	for template in DB.BATTLE_MAPS:
		for palette in ["summer", "camp", "base", "map"]:
			var inp := _synthetic(template, 1000 + n, palette)
			if palette == "map":
				inp["roads"] = [[{"x": 0, "y": 0}, {"x": 3.5, "y": 2.25}, {"x": 7, "y": 6}], [{"x": 2, "y": 9}, {"x": 9, "y": 1}]]
				inp["decals"] = false
				inp["res"] = 14
				inp["scale"] = 0.5
			var layer: Node2D = Terrain.build_terrain(inp)
			assert_true(layer.width > 0 and layer.height > 0, "%s/%s has a size" % [template, palette])
			assert_true(layer.max_h <= 2)
			_root().add_child(layer)
			layer.free()
			n += 1
	assert_eq(n, DB.BATTLE_MAPS.size() * 4)


func test_largest_map_builds_fast() -> void:
	var m: Dictionary = maps.steading
	var layer: Node2D = Terrain.build_terrain(m.terrainInput)
	assert_true(layer.build_ms < 500.0, "CPU part of the steading build took %.0f ms" % layer.build_ms)
	layer.free()


func test_terr_at_outside_tiles() -> void:
	var inp := {"w": 2, "h": 2, "border": 2, "tiles": [{"x": 0, "y": 0, "h": 0, "terrain": "road"}, {"x": 1, "y": 0, "h": 1, "terrain": "bridge"}], "seed": 5, "palette": "summer"}
	var layer: Node2D = Terrain.build_terrain(inp)
	assert_eq(layer.terr_at(0, 0), Terrain.C_DIRT, "road paints as dirt")
	assert_eq(layer.terr_at(1, 0), Terrain.C_WATER, "bridge paints as water")
	assert_eq(layer.terr_at(-1, -1), Terrain.C_FLOOR, "outside the tiles: forest floor")
	assert_eq(layer.h_at(1, 0), 1)
	assert_eq(layer.h_at(5, 5), 0)
	layer.free()
	inp.palette = "map"
	layer = Terrain.build_terrain(inp)
	assert_eq(layer.terr_at(-1, -1), Terrain.C_GRASS, "outside the tiles on the map: grass")
	layer.free()
