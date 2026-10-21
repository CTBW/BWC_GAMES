## Sprite registry. Port of src/render/assets.ts.
##
## The original loads Blender-rendered WebP sprites from public/assets/manifest.json
## and falls back to procedural Canvas art (procedural.ts / figures.ts) for every
## other key. Here both are baked ahead of time by tools/bake (which runs the
## original code in the browser) and listed in res://assets/sprites.json:
##   key -> [{file, region:[x,y,w,h] (atlas sprites), ax, ay, scale, w, h, noShadow, art}]
## with the same keys, variant lists, anchors and scales the original's
## sprite(key, variant) returns. Static functions, no autoload:
##   const Assets = preload("res://scripts/render/assets.gd")
##
## A sprite is a Dictionary: `tex` (Texture2D), `region` (Rect2 of `tex`),
## `ax`, `ay` (anchor in source px, usually the feet), `scale` (world px per
## source px), `w`, `h` (source size), `noShadow`, plus `key`, `v`, `file`, `art`.
## Treat it as read-only; it is shared and cached.
##
## Drawing (from a CanvasItem's _draw()) mirrors drawSprite / drawCastShadow:
##   Assets.draw_sprite(self, s, x, y, flip, scale, Color(1, 1, 1, alpha), sy, rot)
##   Assets.draw_cast_shadow(self, s, x, y, flip, scale, alpha)
##   drawSprite(..., {img: shadowOf(s), alpha}) -> Assets.draw_silhouette(self, s, x, y, flip, scale, alpha, sy, rot)
##   drawSprite(..., {img: flashOf(s), alpha})  -> Assets.draw_flash(self, s, x, y, flip, scale, alpha, sy, rot)
## draw_flash needs `material = Assets.sprite_material()` on the drawing
## CanvasItem for an exact white silhouette (without it, an over-bright modulate
## gives nearly the same white, except on pure-black pixels). The garrison's
## hover highlight ('lighter' + flashOf) is draw_flash on a CanvasItem whose
## material is Assets.additive_material().
## Each draw sets the CanvasItem's draw transform and restores it to
## Assets.draw_base (identity unless you set it for your own draw_set_transform).
extends RefCounted

const MANIFEST := "res://assets/sprites.json"
const MISSING := "missing"
## Red channel of the vertex colour that marks a flash draw (sprite_flash.gdshader).
const FLASH := 64.0
const SHADER_FLASH := "res://assets/shaders/sprite_flash.gdshader"
const SHADER_FLASH_ADD := "res://assets/shaders/sprite_flash_add.gdshader"

## The draw transform restored after each draw (see the header).
static var draw_base := Transform2D.IDENTITY

static var _manifest: Dictionary = {}
static var _loaded := false
static var _sprites: Dictionary = {} # key -> Array[Dictionary]
static var _textures: Dictionary = {} # file -> Texture2D
static var _pixels: Dictionary = {} # file -> {w, h, data: PackedByteArray (RGBA8 level 0), img: Image}
static var _warned: Dictionary = {}
static var _material: ShaderMaterial
static var _material_add: ShaderMaterial


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var text := FileAccess.get_file_as_string(MANIFEST)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_manifest = parsed
	else:
		push_error("Assets: cannot read %s" % MANIFEST)
		_manifest = {}


static func _tex(file: String) -> Texture2D:
	var t: Texture2D = _textures.get(file)
	if t == null:
		var st := ResourceLoader.load_threaded_get_status(file)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS or st == ResourceLoader.THREAD_LOAD_LOADED:
			t = ResourceLoader.load_threaded_get(file) as Texture2D # waits for warm_async's load
		else:
			t = load(file) as Texture2D
		if t == null:
			push_error("Assets: cannot load %s" % file)
			t = PlaceholderTexture2D.new()
		_textures[file] = t
	return t


static func _resolve(key: String, list: Array) -> Array:
	var out: Array = []
	for i in list.size():
		var e: Dictionary = list[i]
		var w := int(e.w)
		var h := int(e.h)
		var r: Variant = e.get("region")
		var region := Rect2(0, 0, w, h) if r == null else Rect2(r[0], r[1], r[2], r[3])
		out.append({
			"key": key,
			"v": i,
			"file": String(e.file),
			"tex": _tex(String(e.file)),
			"region": region,
			"ax": float(e.ax),
			"ay": float(e.ay),
			"scale": float(e.get("scale", 1.0)),
			"w": w,
			"h": h,
			"noShadow": bool(e.get("noShadow", false)),
			"art": bool(e.get("art", false)),
		})
	return out


static func _list(key: String) -> Array:
	var list: Variant = _sprites.get(key)
	if list != null:
		return list
	_ensure()
	var entries: Variant = _manifest.get(key)
	if entries is Array and not (entries as Array).is_empty():
		list = _resolve(key, entries)
	else:
		# The original falls back to its 'missing' placeholder (one variant).
		if not _warned.has(key):
			_warned[key] = true
			push_warning("Assets: no sprite '%s'; drawing the 'missing' placeholder" % key)
		var missing: Array = _list(MISSING) if key != MISSING else []
		list = [missing[0]] if not missing.is_empty() else []
	_sprites[key] = list
	return list


## True when the key has Blender-rendered art (manifest art, not a procedural bake).
static func has_art(key: String) -> bool:
	_ensure()
	var entries: Variant = _manifest.get(key)
	return entries is Array and not (entries as Array).is_empty() and bool((entries as Array)[0].get("art", false))


## Get a sprite variant (variant is taken modulo the variant count).
static func sprite(key: String, variant: int = 0) -> Dictionary:
	var list := _list(key)
	if list.is_empty():
		return {}
	return list[absi(variant) % list.size()]


static func variant_count(key: String) -> int:
	return _list(key).size()


## Every key in the registry.
static func keys() -> PackedStringArray:
	_ensure()
	return PackedStringArray(_manifest.keys())


## Named ground textures of the original's manifest (`textures`; empty there).
static func texture(_key: String) -> Texture2D:
	return null


## Load the textures behind these keys now (they otherwise load on first use;
## a figure atlas takes 50–110 ms).
static func warm(key_list: Array) -> void:
	for k in key_list:
		_list(String(k))


## Start loading the textures behind these keys on worker threads; the first
## sprite() of a key then picks its texture up (waiting if still loading).
static func warm_async(key_list: Array) -> void:
	_ensure()
	for k in key_list:
		var entries: Variant = _manifest.get(String(k))
		if not entries is Array:
			continue
		for e in entries:
			var f := String(e.file)
			if not _textures.has(f) and ResourceLoader.load_threaded_get_status(f) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				ResourceLoader.load_threaded_request(f, "Texture2D")


# ---------------------------------------------------------------- hit tests

static func _pixels_of(file: String) -> Dictionary:
	var p: Variant = _pixels.get(file)
	if p != null:
		return p
	var img := _tex(file).get_image()
	var out := {"w": 0, "h": 0, "data": PackedByteArray(), "img": null}
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		if img.has_mipmaps():
			img.clear_mipmaps()
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		out = {"w": img.get_width(), "h": img.get_height(), "data": img.get_data(), "img": img}
	_pixels[file] = out
	return out


## A quarter-resolution alpha mask of a sprite's pixels, as the original builds
## it (drawImage scaled to ceil(w/4)×ceil(h/4): bilinear samples of the region).
static func _build_mask(s: Dictionary) -> Dictionary:
	var k := 4
	var sw: int = s.w
	var sh: int = s.h
	var w := maxi(1, ceili(float(sw) / k))
	var h := maxi(1, ceili(float(sh) / k))
	var a := PackedByteArray()
	a.resize(w * h)
	var px := _pixels_of(s.file)
	var data: PackedByteArray = px.data
	var tw: int = px.w
	if data.is_empty():
		return {"w": w, "h": h, "k": k, "a": a}
	var r: Rect2 = s.region
	var x0 := int(r.position.x)
	var y0 := int(r.position.y)
	var fx := float(sw) / w
	var fy := float(sh) / h
	for j in h:
		var v := (j + 0.5) * fy - 0.5
		var j0 := floori(v)
		var ty := v - j0
		var ya := clampi(j0, 0, sh - 1) + y0
		var yb := clampi(j0 + 1, 0, sh - 1) + y0
		for i in w:
			var u := (i + 0.5) * fx - 0.5
			var i0 := floori(u)
			var tx := u - i0
			var xa := clampi(i0, 0, sw - 1) + x0
			var xb := clampi(i0 + 1, 0, sw - 1) + x0
			var top := lerpf(data[(ya * tw + xa) * 4 + 3], data[(ya * tw + xb) * 4 + 3], tx)
			var bot := lerpf(data[(yb * tw + xa) * 4 + 3], data[(yb * tw + xb) * 4 + 3], tx)
			a[j * w + i] = roundi(lerpf(top, bot, ty))
	return {"w": w, "h": h, "k": k, "a": a}


## True if the sprite is opaque at a point given in its own pixel space.
static func opaque_at(s: Dictionary, px: float, py: float) -> bool:
	var m: Variant = s.get("_mask")
	if m == null:
		m = _build_mask(s)
		s["_mask"] = m
	var ix := floori(px / m.k)
	var iy := floori(py / m.k)
	if ix < 0 or iy < 0 or ix >= m.w or iy >= m.h:
		return false
	return m.a[iy * m.w + ix] > 150


# ---------------------------------------------------------------- drawing

static func _xf(s: Dictionary, x: float, y: float, flip: bool, scale: float, sy: float, rot: float) -> Transform2D:
	var sc: float = s.scale * scale
	return Transform2D(rot, Vector2(-sc if flip else sc, sc * sy), 0.0, Vector2(x, y))


static func _blit(ci: CanvasItem, s: Dictionary, xf: Transform2D, modulate: Color) -> void:
	ci.draw_set_transform_matrix(draw_base * xf)
	ci.draw_texture_rect_region(s.tex, Rect2(-s.ax, -s.ay, s.w, s.h), s.region, modulate)
	ci.draw_set_transform_matrix(draw_base)


## Draw a sprite anchored at world point (x, y) (drawSprite). `flip` mirrors
## horizontally about the anchor, `scale` multiplies the sprite's own scale,
## `sy` stretches vertically, `rot` rotates (radians) about the anchor;
## `modulate.a` is the original's `alpha`.
static func draw_sprite(ci: CanvasItem, s: Dictionary, x: float, y: float, flip := false, scale := 1.0, modulate := Color.WHITE, sy := 1.0, rot := 0.0) -> void:
	if s.is_empty():
		return
	_blit(ci, s, _xf(s, x, y, flip, scale, sy, rot), modulate)


## drawSprite with img: flashOf(s): a white silhouette at `alpha` (see header).
static func draw_flash(ci: CanvasItem, s: Dictionary, x: float, y: float, flip := false, scale := 1.0, alpha := 1.0, sy := 1.0, rot := 0.0) -> void:
	if s.is_empty():
		return
	_blit(ci, s, _xf(s, x, y, flip, scale, sy, rot), Color(FLASH, FLASH, FLASH, alpha))


## drawSprite with img: shadowOf(s): a black silhouette at `alpha`.
static func draw_silhouette(ci: CanvasItem, s: Dictionary, x: float, y: float, flip := false, scale := 1.0, alpha := 1.0, sy := 1.0, rot := 0.0) -> void:
	if s.is_empty():
		return
	_blit(ci, s, _xf(s, x, y, flip, scale, sy, rot), Color(0, 0, 0, alpha))


## Cast shadow: the silhouette flattened and skewed away from the upper-left
## light (drawCastShadow). Sprites with their own baked shadow draw none.
static func draw_cast_shadow(ci: CanvasItem, s: Dictionary, x: float, y: float, flip := false, scale := 1.0, alpha := 0.22) -> void:
	if s.is_empty() or s.noShadow:
		return
	var sc: float = s.scale * scale
	# ctx.transform(1, 0, -0.75, -0.32, 0, 0): shadows fall down and to the right.
	var skew := Transform2D(Vector2(1, 0), Vector2(-0.75, -0.32), Vector2(x, y))
	var xf := skew * Transform2D(0.0, Vector2(-sc if flip else sc, sc), 0.0, Vector2.ZERO)
	_blit(ci, s, xf, Color(0, 0, 0, alpha))


## Draw the whole sprite into a rectangle (the Portrait component's drawImage).
static func draw_sprite_rect(ci: CanvasItem, s: Dictionary, rect: Rect2, modulate := Color.WHITE) -> void:
	if s.is_empty():
		return
	ci.draw_texture_rect_region(s.tex, rect, s.region, modulate)


## The sprite as a Texture2D of its own (an AtlasTexture for atlas sprites),
## for Controls such as TextureRect. Cached per sprite.
static func atlas_texture(s: Dictionary) -> Texture2D:
	if s.is_empty():
		return null
	var t: Variant = s.get("_atlas")
	if t == null:
		var tex: Texture2D = s.tex
		var r: Rect2 = s.region
		if r.position == Vector2.ZERO and r.size == tex.get_size():
			t = tex
		else:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = r
			t = at
		s["_atlas"] = t
	return t


## The sprite's pixels as a new Image (straight alpha RGBA8), e.g. to paint
## decals into a terrain image on the CPU.
static func sprite_image(s: Dictionary) -> Image:
	if s.is_empty():
		return null
	var img: Image = _pixels_of(s.file).img
	return null if img == null else img.get_region(Rect2i(s.region))


## Material for CanvasItems that call draw_flash (exact white silhouettes).
static func sprite_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER_FLASH)
	return _material


## Additive variant: draw_flash on such a CanvasItem is 'lighter' + flashOf.
static func additive_material() -> ShaderMaterial:
	if _material_add == null:
		_material_add = ShaderMaterial.new()
		_material_add.shader = load(SHADER_FLASH_ADD)
	return _material_add
