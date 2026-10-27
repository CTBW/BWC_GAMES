## Windowed capture of terrain layers built from the original's inputs
## (tests/fixtures/render/*.json), for comparison with the original's layers
## (tests/visual/out/ref/terrain_<name>_layer.png, from
## tools/parity/render_fixtures_browser.ts).
##
##   tools/godot.sh --path . --resolution 1920x1080 -s res://tests/visual/capture_terrain.gd -- [names...]
##
## Names: forest river camp night_torch steading ford base (default: all).
## Writes tests/visual/out/terrain_<name>_layer.png (and _field.png) and prints
## the build time of each.
extends SceneTree

const Terrain = preload("res://scripts/render/terrain.gd")
const OUT := "res://tests/visual/out/"


static func load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


static func inputs() -> Dictionary:
	var out := {}
	var maps: Dictionary = load_json("res://tests/fixtures/render/battle_maps.json")
	for k in maps:
		out[k] = maps[k].terrainInput
	out["base"] = base_input()
	return out


## The garrison's ground as baseScene builds it.
static func base_input() -> Dictionary:
	if not ResourceLoader.exists("res://scripts/render/base_view.gd"):
		return {}
	var BaseView = load("res://scripts/render/base_view.gd")
	if BaseView != null and BaseView.has_method("terrain_input"):
		return BaseView.terrain_input()
	return {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var names: PackedStringArray = OS.get_cmdline_user_args()
	var all := inputs()
	if names.is_empty():
		names = PackedStringArray(all.keys())
	_run(all, names)


func _run(all: Dictionary, names: PackedStringArray) -> void:
	for name in names:
		var inp: Dictionary = all.get(name, {})
		if inp.is_empty():
			print("skip ", name)
			continue
		var t0 := Time.get_ticks_usec()
		var layer: Node2D = Terrain.build_terrain(inp)
		layer.set_meta("keep_field", true)
		root.add_child(layer)
		await layer.built
		var total := (Time.get_ticks_usec() - t0) / 1000.0
		await process_frame
		var img: Image = layer.texture.get_image()
		img.save_png(ProjectSettings.globalize_path(OUT + "terrain_%s_layer.png" % name))
		if layer.has_method("field_image"):
			var fi: Image = layer.field_image()
			if fi != null:
				fi.save_png(ProjectSettings.globalize_path(OUT + "terrain_%s_field.png" % name))
		print("%s: %dx%d cpu %.0f ms, ready after %.0f ms" % [name, layer.width, layer.height, layer.build_ms, total])
		if name == "forest":
			# late_bake: paint into a layer that has already rendered (bake after build).
			layer.bake(func(ci: CanvasItem) -> void:
				ci.draw_circle(Vector2(0, 300), 60.0, Color(1, 0, 0, 0.8)))
			await RenderingServer.frame_post_draw
			await process_frame
			layer.texture.get_image().save_png(ProjectSettings.globalize_path(OUT + "terrain_forest_late_bake.png"))
		layer.queue_free()
		await process_frame
	quit(0)
