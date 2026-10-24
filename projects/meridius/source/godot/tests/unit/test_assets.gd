## The sprite registry (scripts/render/assets.gd, port of src/render/assets.ts)
## against the original: tests/fixtures/assets/variant_counts.json is dumped by
## tools/bake from the original's sprite()/variantCount()/hasArt() in the browser.
extends "res://tests/test_case.gd"

const Assets = preload("res://scripts/render/assets.gd")
const DB = preload("res://scripts/data/db.gd")
const FIXTURE := "res://tests/fixtures/assets/variant_counts.json"
# Art repainted after the port, with more variants than the original drew
# (MIGRATION.md, "Painted rocks"); the original's counts no longer apply.
const REPAINTED := {"rock_small": 4, "rock_large": 4}

var fx: Dictionary
var manifest: Dictionary


func before_all() -> void:
	fx = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	manifest = JSON.parse_string(FileAccess.get_file_as_string(Assets.MANIFEST))


func test_every_entry_loads_and_regions_fit() -> void:
	var files := {}
	var entries := 0
	for key in manifest:
		for e in manifest[key]:
			entries += 1
			var tex := load(e.file) as Texture2D
			if not assert_true(tex != null, "%s: %s loads as Texture2D" % [key, e.file]):
				continue
			files[e.file] = true
			var size := tex.get_size()
			var r: Array = e.get("region", [0, 0, e.w, e.h])
			assert_eq([int(r[2]), int(r[3])], [int(e.w), int(e.h)], "%s region size = w×h" % key)
			assert_true(r[0] >= 0 and r[1] >= 0 and r[0] + r[2] <= size.x and r[1] + r[3] <= size.y, "%s region %s inside %s" % [key, r, size])
			if not e.has("region"):
				assert_eq(size, Vector2(e.w, e.h), "%s whole-file sprite size" % key)
			assert_true(float(e.scale) > 0.0, "%s scale" % key)
	assert_true(entries >= 1200, "all variants listed (%d)" % entries)
	assert_true(files.size() >= 90, "sprite files (%d)" % files.size())


func test_keys_and_variant_counts_match_original() -> void:
	var counts: Dictionary = fx.counts
	assert_eq(manifest.size(), counts.size(), "same number of keys as the original enumerates")
	for key in counts:
		assert_true(manifest.has(key), "%s in sprites.json" % key)
		assert_eq(Assets.variant_count(key), int(REPAINTED.get(key, counts[key])), "variantCount(%s)" % key)


func test_has_art_matches_original() -> void:
	var art: Array = fx.hasArt
	for key in fx.counts:
		assert_eq(Assets.has_art(key), art.has(key), "hasArt(%s)" % key)
	assert_true(Assets.has_art("palisade_x") and Assets.has_art("gate_tower"), "garrison walls have art")


func test_every_scene_key_resolves_to_real_art() -> void:
	var keys := {}
	for g in fx.groups:
		for k in fx.groups[g]:
			keys[k] = true
	# Templates the scenes build from the data tables (port-side view of the same sets).
	var poses := ["idle_f", "atk_f", "idle_b", "atk_b", "dead", "flee_b", "idle_fs", "atk_fs", "idle_bs", "atk_bs", "run_f", "run_b"]
	for t in DB.UNIT_TYPES:
		var spr: String = DB.UNIT_TYPES[t].sprite
		for p in poses:
			keys["%s_%s" % [spr, p]] = true
		keys["portrait_%s" % t] = true
	for p in poses:
		keys["margrave_rider_%s" % p] = true
	for id in DB.PROPS:
		keys[DB.PROPS[id].sprite] = true
	for b in DB.BUILDINGS:
		for lvl in range(1, b.levels.size() + 1):
			keys["b_%s_%d" % [b.id, lvl]] = true
	for n in DB.NODE_INFO:
		keys["node_%s" % n] = true
	for k in ["node_unknown", "war_banner", "palisade_x", "palisade_y", "gate_tower", "tuft", "flower", "pebble", "missing"]:
		keys[k] = true
	for k in keys:
		var n := Assets.variant_count(k)
		for v in n:
			var s := Assets.sprite(k, v)
			assert_eq(s.get("key"), k, "sprite(%s, %d) is its own art, not 'missing'" % [k, v])
			assert_true(s.tex is Texture2D, "%s texture" % k)
	assert_true(keys.size() >= 254, "scene keys (%d)" % keys.size())


func test_variant_wraps_like_the_original() -> void:
	var n := Assets.variant_count("footman_idle_f")
	assert_eq(n, 6)
	assert_eq(Assets.sprite("footman_idle_f", 7), Assets.sprite("footman_idle_f", 1))
	assert_eq(Assets.sprite("footman_idle_f", -2), Assets.sprite("footman_idle_f", 2))
	assert_eq(Assets.sprite("tree_pine", 9).v, 0)


func test_unknown_key_draws_missing_once() -> void:
	var s := Assets.sprite("no_such_sprite_key")
	assert_eq(s.key, "missing")
	assert_eq(Assets.variant_count("no_such_sprite_key"), 1, "the original lists one 'missing' variant")
	assert_false(Assets.has_art("no_such_sprite_key"))
	assert_eq(int(s.w), 40)
	assert_eq([s.ax, s.ay], [20.0, 40.0])


func test_figure_anchor_and_scale() -> void:
	# figureSprite: canvas 340×380 anchored at (170, 354) before trimming,
	# scale 0.76 / 1.4 × 1.4 × 0.62.
	var s := Assets.sprite("footman_idle_f", 0)
	assert_almost(s.scale, 0.76 / 1.4 * 1.4 * 0.62, 1e-9, "figure scale")
	assert_false(s.noShadow)
	assert_true(s.ax > 0 and s.ax < s.w and s.ay > 0 and s.ay <= s.h, "anchor inside the trimmed figure")
	var tree := Assets.sprite("tree_pine", 0)
	assert_true(tree.noShadow and tree.art, "Blender tree carries its own shadow")
	assert_almost(tree.scale, 0.3201, 1e-9)
	assert_almost(tree.ax, 226.9, 1e-9)


func test_opaque_at_hit_mask() -> void:
	var s := Assets.sprite("footman_idle_f", 0)
	# Middle of the body, above the feet: opaque. Corners and outside: not.
	assert_true(Assets.opaque_at(s, s.ax, s.ay - 60), "body is opaque")
	assert_false(Assets.opaque_at(s, 0, 0), "trim margin is clear")
	assert_false(Assets.opaque_at(s, -5, 10), "outside left")
	assert_false(Assets.opaque_at(s, s.w + 4, 10), "outside right")
	var b := Assets.sprite("b_barracks_2")
	assert_true(Assets.opaque_at(b, b.ax, b.ay - 100), "building wall is opaque")
	assert_false(Assets.opaque_at(b, 2, 2), "building corner is clear")


func test_opaque_at_matches_original_masks() -> void:
	# tests/fixtures/assets/hit_masks.json: the original's opaqueAt() on a grid.
	var cases: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/assets/hit_masks.json"))
	assert_true(cases.size() >= 5, "mask cases")
	for c in cases:
		var s := Assets.sprite(c.key, int(c.v))
		assert_eq([s.w, s.h], [int(c.w), int(c.h)], "%s size" % c.key)
		var step := float(c.step)
		var bits: String = c.bits
		var i := 0
		var off := 0
		var opaque := 0
		var y := step / 2
		while y < s.h:
			var x := step / 2
			while x < s.w:
				var want := bits[i] == "1"
				if want:
					opaque += 1
				if Assets.opaque_at(s, x, y) != want:
					off += 1
				i += 1
				x += step
			y += step
		assert_eq(i, bits.length(), "%s grid size" % c.key)
		# Canvas-drawn (procedural) sprites match the browser's bilinear 4× mask
		# exactly; for decoded WebP images the browser's downscale differs a little
		# along the edges (measured ≤ 0.7% of opaque points).
		var limit := maxi(2, opaque / 100) if s.art else 2
		assert_true(off <= limit, "%s: %d of %d points disagree with the original (%d opaque)" % [c.key, off, i, opaque])


func test_atlas_texture_and_image() -> void:
	var s := Assets.sprite("portrait_troll", 1)
	var t := Assets.atlas_texture(s)
	assert_true(t is AtlasTexture, "atlas sprite gives an AtlasTexture")
	assert_eq(t.get_size(), Vector2(160, 160))
	var img := Assets.sprite_image(Assets.sprite("tuft", 0))
	assert_not_null(img)
	assert_eq(img.get_size(), Vector2i(40, 30))
	var whole := Assets.atlas_texture(Assets.sprite("well"))
	assert_false(whole is AtlasTexture, "whole-file sprite gives its texture")


func test_warm_async_then_sprite() -> void:
	Assets.warm_async(["goblin_horn_idle_f", "goblin_horn_atk_b", "portrait_goblin_horn"])
	var s := Assets.sprite("goblin_horn_atk_b", 3)
	assert_eq(s.key, "goblin_horn_atk_b")
	assert_true(s.tex is Texture2D and s.tex.get_width() > 0, "texture from the threaded load")
	Assets.warm(["portrait_goblin_horn"])
	assert_true(Assets.sprite("portrait_goblin_horn").tex is Texture2D)


## Play-through finding: textures warm_async asked for but never drew stayed
## with the threaded loader; each such request was reported as a leaked
## RefCounted ("ObjectDB instances leaked at exit"). Finished loads are taken
## into the cache by the next warm_async, and all of them at exit.
func test_warm_async_requests_are_taken_from_the_loader() -> void:
	Assets._ensure()
	# Two keys on different files, out of the cache (the earlier tests loaded everything).
	var fresh: Array = []
	var files := {}
	for k in ["goblin_horn_idle_f", "portrait_troll", "tuft", "well"]:
		var f := String(Assets._manifest[k][0].file)
		if not files.has(f) and ResourceLoader.load_threaded_get_status(f) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			files[f] = true
			fresh.append(k)
		if fresh.size() >= 2:
			break
	if not assert_eq(fresh.size(), 2, "two keys"):
		return
	var kept := {}
	for f in files:
		kept[f] = Assets._textures.get(f)
		Assets._textures.erase(f)
	var f0 := String(Assets._manifest[fresh[0]][0].file)
	var f1 := String(Assets._manifest[fresh[1]][0].file)
	Assets.warm_async([fresh[0]])
	assert_true(Assets.pending_loads() >= 1 or Assets._textures.has(f0), "requested (or, already in the resource cache, taken at once)")
	# Finished loads are taken by the next warm_async.
	var t0 := Time.get_ticks_msec()
	while ResourceLoader.load_threaded_get_status(f0) == ResourceLoader.THREAD_LOAD_IN_PROGRESS and Time.get_ticks_msec() - t0 < 5000:
		OS.delay_msec(5)
	Assets.warm_async([fresh[1]])
	assert_true(Assets._textures.has(f0), "the finished load is in the cache")
	assert_eq(ResourceLoader.load_threaded_get_status(f0), ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "and no longer held by the loader")
	# At exit everything is taken, also loads still running.
	Assets.collect_loaded(true)
	assert_eq(Assets.pending_loads(), 0, "nothing left with the loader")
	assert_true(Assets._textures.has(f1))
	assert_eq(ResourceLoader.load_threaded_get_status(f1), ResourceLoader.THREAD_LOAD_INVALID_RESOURCE)
	for f in kept:
		if kept[f] != null:
			assert_eq(Assets._textures.get(f), kept[f], "the same texture as before (from the resource cache)")


func test_materials_load() -> void:
	assert_true(Assets.sprite_material().shader is Shader)
	assert_true(Assets.additive_material().shader is Shader)
	assert_eq(Assets.texture("ground_detail"), null, "the original lists no ground textures")
