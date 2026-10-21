## Renders the sprite contact sheets of tests/fixtures/assets/sheets.json through
## scripts/render/assets.gd (draw_sprite, draw_cast_shadow, draw_flash,
## draw_silhouette, draw_sprite_rect) into tests/visual/out/assets_<name>_godot.png.
## tools/bake/bake.mjs renders the same layouts with the original's drawSprite /
## drawCastShadow in the browser (assets_<name>_browser.png);
## tools/bake/compare.mjs diffs them. Needs a window (not --headless):
##   tools/godot.sh --path . -s res://tests/visual/capture_assets.gd [-- name… | nomat]
## Afterwards it plays every sound through the Sfx autoload and reports voices.
extends SceneTree

const Assets = preload("res://scripts/render/assets.gd")
const SHEETS := "res://tests/fixtures/assets/sheets.json"
const OUT := "res://tests/visual/out"

var sheets: Array = []
var current := -1
var frames := 0
var vp: SubViewport
var sfx_frames := -1
## `-- nomat`: draw without Assets.sprite_material() (checks the flash fallback).
var nomat := false


func _initialize() -> void:
	var all: Array = JSON.parse_string(FileAccess.get_file_as_string(SHEETS))
	var only := Array(OS.get_cmdline_user_args())
	nomat = only.has("nomat")
	only.erase("nomat")
	for s in all:
		if only.is_empty() or only.has(s.name):
			sheets.append(s)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_next_sheet()


func _next_sheet() -> void:
	if vp != null:
		vp.queue_free()
		vp = null
	current += 1
	frames = 0
	if current >= sheets.size():
		return
	var s: Dictionary = sheets[current]
	vp = SubViewport.new()
	vp.size = Vector2i(int(s.w), int(s.h))
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# The game's root viewport filters canvas textures with mipmaps
	# (project setting); a SubViewport must ask for it.
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	root.add_child(vp)
	var main := Node2D.new()
	if not nomat:
		main.material = Assets.sprite_material()
	vp.add_child(main)
	main.draw.connect(_draw_sheet.bind(main, s, false))
	# 'lighter' items (additive flash) on a child drawn after its parent.
	var add := Node2D.new()
	add.material = Assets.additive_material()
	main.add_child(add)
	add.draw.connect(_draw_sheet.bind(add, s, true))


func _draw_sheet(ci: Node2D, s: Dictionary, additive: bool) -> void:
	if not additive:
		ci.draw_rect(Rect2(0, 0, s.w, s.h), Color.html(s.bg))
	for it in s.items:
		var mode: String = it.get("mode", "normal")
		if (mode == "lighter") != additive:
			continue
		var spr := Assets.sprite(it.key, int(it.v))
		if it.has("box"):
			Assets.draw_sprite_rect(ci, spr, Rect2(it.x, it.y, it.box, it.box))
			continue
		var flip: bool = it.get("flip", false)
		var sc := _num(it, "scale", 1.0)
		var alpha := _num(it, "alpha", 1.0)
		var rot := _num(it, "rot", 0.0)
		var sy := _num(it, "sy", 1.0)
		var shadow := _num(it, "shadow", 0.0)
		if shadow > 0.0:
			Assets.draw_cast_shadow(ci, spr, it.x, it.y, flip, sc, shadow)
		match mode:
			"flash", "lighter":
				Assets.draw_flash(ci, spr, it.x, it.y, flip, sc, alpha, sy, rot)
			"silhouette":
				Assets.draw_silhouette(ci, spr, it.x, it.y, flip, sc, alpha, sy, rot)
			_:
				Assets.draw_sprite(ci, spr, it.x, it.y, flip, sc, Color(1, 1, 1, alpha), sy, rot)


func _num(d: Dictionary, k: String, def: float) -> float:
	var v: Variant = d.get(k)
	return def if v == null else float(v)


func _process(_delta: float) -> bool:
	if current < sheets.size():
		frames += 1
		if frames == 4:
			var img := vp.get_texture().get_image()
			var path := "%s/assets_%s_godot%s.png" % [OUT, sheets[current].name, "_nomat" if nomat else ""]
			img.save_png(ProjectSettings.globalize_path(path))
			print("saved ", path, " ", img.get_size())
			_next_sheet()
		return false
	# Sounds: play every name through the autoload with the tree running.
	var sfx := root.get_node_or_null("Sfx")
	if sfx_frames < 0:
		sfx_frames = 0
		var names: PackedStringArray = sfx.names()
		var was: bool = sfx.is_muted()
		sfx.set_muted(false)
		for n in names:
			sfx.play(n)
		var voices := 0
		for p in sfx.get_children():
			if p is AudioStreamPlayer and p.playing:
				voices += 1
		print("sfx: played %d names, %d voices playing (pool %d)" % [names.size(), voices, sfx.get_child_count()])
		sfx.set_muted(was)
		return false
	sfx_frames += 1
	return sfx_frames > 2
