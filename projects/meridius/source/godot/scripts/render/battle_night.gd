## Night and dawn over the battlefield: battleScene.drawNight (torch-lit
## darkness, warm glows, the horde's torch flames, dawn breaking) and
## drawSunrise (the sun behind the relief), in screen space between the world
## and the overlays.
##
## The darkness mask is painted, as in the original, at a quarter of the
## resolution: a flat fill with the soft hole stamps multiplied out of its
## alpha ('destination-out'), in a SubViewport, then blended over the world in
## the night's colour. The glows are painted the same way into a second one and
## blended 'soft-light' (the one pass that reads the screen). The flames are
## additive ('lighter'); dawn and the sunrise are 'screen' gradients, drawn as a
## multiply and an add pass (battle_dawn.gdshaderinc). No BackBufferCopy: in
## the Compatibility renderer one cut the drawing after it out of the frame.
extends Node2D

const Iso = preload("res://scripts/render/iso.gd")
const Rng = preload("res://scripts/core/rng.gd")
const SquadView = preload("res://scripts/render/squad_view.gd")
const BattleLayer = preload("res://scripts/render/battle_layer.gd")
const NightShader = preload("res://scenes/battle/battle_night.gdshader")
const GlowShader = preload("res://scenes/battle/battle_glow.gdshader")
const DawnMulShader = preload("res://scenes/battle/battle_dawn_mul.gdshader")
const DawnAddShader = preload("res://scenes/battle/battle_dawn_add.gdshader")

## The mask is soft light and dark only: a quarter of the resolution is plenty.
const Q := 4

var v # the BattleView
var _mask_vp: SubViewport
var _glow_vp: SubViewport
var _dark: Node2D
var _holes: Node2D
var _glows: Node2D
var _composite: Node2D
var _glow_pass: Node2D
var _flames: Node2D
var _dawn_mul: Node2D
var _dawn_add: Node2D
var _night_mat: ShaderMaterial
var _dawn_mats: Array = []
var _white: Texture2D
var _lights: Array = []
var _level := 1.0
var _campfires: Array = []
var _active := false

static var _stamps := {}


func setup(view) -> void:
	v = view
	_white = ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	(_white as ImageTexture).update(_solid(Color.WHITE))
	_mask_vp = _viewport("NightMask")
	_dark = _layer(_mask_vp, "Dark", _draw_dark)
	_holes = _layer(_mask_vp, "Holes", _draw_holes)
	var mul := CanvasItemMaterial.new()
	mul.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_holes.material = mul
	_glow_vp = _viewport("NightGlow")
	_glows = _layer(_glow_vp, "Glows", _draw_glows)
	_night_mat = ShaderMaterial.new()
	_night_mat.shader = NightShader
	_composite = _layer(self, "Darkness", _draw_composite)
	_composite.material = _night_mat
	var gm := ShaderMaterial.new()
	gm.shader = GlowShader
	_glow_pass = _layer(self, "Glow", _draw_glow_pass)
	_glow_pass.material = gm
	_flames = _layer(self, "Flames", _draw_flames)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flames.material = add
	_dawn_mul = _layer(self, "DawnMul", _draw_dawn)
	_dawn_add = _layer(self, "DawnAdd", _draw_dawn)
	for pair in [[_dawn_mul, DawnMulShader], [_dawn_add, DawnAddShader]]:
		var m := ShaderMaterial.new()
		m.shader = pair[1]
		pair[0].material = m
		_dawn_mats.append(m)
	for t in v.b.map.tiles:
		if t.get("prop") == "campfire":
			_campfires.append(Vector2(Iso.iso_x(t.x, t.y), Iso.iso_y(t.x, t.y, t.h) - 20))
	refresh()


static func _solid(c: Color) -> Image:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img


func _viewport(n: String) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = n
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.size = Vector2i(480, 270)
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(vp)
	return vp


func _layer(parent: Node, n: String, fn: Callable) -> Node2D:
	var l := BattleLayer.new()
	l.name = n
	l.draw_fn = fn
	parent.add_child(l)
	return l


## Per frame (after the view's update): what to show and the lights to cut.
func refresh() -> void:
	var night: bool = v.atmo.night
	var sunrise: bool = v.relief != null and v.relief.glow > 0
	var dawn = v._objective().get("dawn")
	_level = v.night_level if dawn else 1.0
	_active = night
	if night:
		v.atmo.own_night_mask = true
		_collect_lights(dawn)
	var size := Vector2i(ceili(v._w / Q), ceili(v._h / Q))
	for vp in [_mask_vp, _glow_vp]:
		if vp.size != size:
			vp.size = size
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if night else SubViewport.UPDATE_DISABLED
	for l in [_dark, _holes, _glows]:
		l.scale = Vector2(1.0 / Q, 1.0 / Q)
		l.queue_redraw()
	_composite.visible = night
	_glow_pass.visible = night
	_flames.visible = night and dawn and _level > 0.2
	var late := 1.0 - _level
	var dawn_a := minf(0.45, (late - 0.25) * 0.75) if (night and dawn and late > 0.25) else 0.0
	var sun := Vector4.ZERO
	if sunrise:
		var r: Dictionary = v.relief
		var W: float = v.b.map.w
		var H: float = v.b.map.h
		var mid: Vector2 = {"n": Vector2(W / 2, -3), "s": Vector2(W / 2, H + 2), "w": Vector2(-3, H / 2), "e": Vector2(W + 2, H / 2)}[r.edge]
		var s: Vector2 = v.cam.world_to_screen(Iso.iso_x(mid.x, mid.y), Iso.iso_y(mid.x, mid.y, 0), v._w, v._h)
		sun = Vector4(s.x, s.y, maxf(v._w, v._h) * 1.1, r.glow)
	for m in _dawn_mats:
		m.set_shader_parameter("dawn_a", dawn_a)
		m.set_shader_parameter("view_size", Vector2(v._w, v._h))
		m.set_shader_parameter("sun", sun)
	_dawn_mul.visible = dawn_a > 0 or sunrise
	_dawn_add.visible = _dawn_mul.visible
	_night_mat.set_shader_parameter("night_rgb", _night_color())
	for l in [_composite, _glow_pass, _flames, _dawn_mul, _dawn_add]:
		if l.visible:
			l.queue_redraw()


## A battle through the night lightens toward dawn: the dark thins and warms.
func _night_color() -> Color:
	var late := 1.0 - _level
	return Color(roundf(12 + 40 * late) / 255.0, roundf(16 + 14 * late) / 255.0, roundf(40 + 10 * late) / 255.0)


func _collect_lights(dawn) -> void:
	_lights.clear()
	var lit: bool = not v.b.setup.get("darkness", false)
	var staged: Dictionary = v.staged()
	for uv in v.views.values():
		var waiting: bool = uv.reserve and staged.has(uv.uid)
		if not (uv.visible or waiting) or uv.status == "dead" or uv.status == "fled":
			continue
		var u: Dictionary = v._u(uv.uid)
		var p: Vector2 = v._view_pos(uv)
		# The horde comes by torchlight: every warband carries fire.
		var r := (230.0 if lit else 120.0) if u.faction == "player" else (125.0 if dawn else 70.0)
		_lights.append(Vector3(p.x, p.y - 40, r))
	if dawn and v._host_alpha > 0.05:
		for t in v._host_torches:
			_lights.append(Vector3(t.x, t.y, 70))
	for c in _campfires:
		_lights.append(Vector3(c.x, c.y, 320))


func _draw_dark(ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(0, 0, v._w, v._h), Color(1, 1, 1, 0.74 * _level))


func _draw_holes(ci: CanvasItem) -> void:
	var hole := stamp("hole_mul")
	var w: float = v._w
	var h: float = v._h
	var time: float = v.time
	for l in _lights:
		var s: Vector2 = v.cam.world_to_screen(l.x, l.y, w, h)
		var r: float = l.z * v.cam.zoom * (1 + sin(time * 9 + l.x) * 0.03)
		if s.x + r < 0 or s.y + r < 0 or s.x - r > w or s.y - r > h:
			continue
		ci.draw_texture_rect(hole, Rect2(s.x - r, s.y - r, r * 2, r * 2), false)


## Warm glow where the light falls.
func _draw_glows(ci: CanvasItem) -> void:
	var glow := stamp("glow")
	var w: float = v._w
	var h: float = v._h
	var col := Color(1, 1, 1, 0.32 * _level)
	for l in _lights:
		var s: Vector2 = v.cam.world_to_screen(l.x, l.y, w, h)
		var r: float = l.z * v.cam.zoom * 0.8
		if s.x + r < 0 or s.y + r < 0 or s.x - r > w or s.y - r > h:
			continue
		ci.draw_texture_rect(glow, Rect2(s.x - r, s.y - r, r * 2, r * 2), false, col)


func _draw_composite(ci: CanvasItem) -> void:
	ci.draw_texture_rect(_mask_vp.get_texture(), Rect2(0, 0, v._w, v._h), false)


func _draw_glow_pass(ci: CanvasItem) -> void:
	ci.draw_texture_rect(_glow_vp.get_texture(), Rect2(0, 0, v._w, v._h), false)


## Torch flames over the horde's warbands, so the host reads as a river of fire.
func _draw_flames(ci: CanvasItem) -> void:
	var fl := stamp("flame")
	var w: float = v._w
	var h: float = v._h
	var time: float = v.time
	var col := Color(1, 1, 1, 0.9 * _level)
	var flame := func(wx: float, wy: float, k: float) -> void:
		var s: Vector2 = v.cam.world_to_screen(wx, wy, w, h)
		if s.x < -20 or s.y < -20 or s.x > w + 20 or s.y > h + 20:
			return
		var f := 1 + sin(time * 13 + k) * 0.18 + sin(time * 7.3 + k * 3) * 0.1
		var r: float = 27 * v.cam.zoom * f
		ci.draw_texture_rect(fl, Rect2(s.x - r, s.y - r, r * 2, r * 2), false, col)
	var staged: Dictionary = v.staged()
	for uv in v.views.values():
		var waiting: bool = uv.reserve and staged.has(uv.uid)
		if not (uv.visible or waiting) or uv.status == "dead" or uv.status == "fled" or uv.routing:
			continue
		var u: Dictionary = v._u(uv.uid)
		if u.faction != "enemy":
			continue
		var live := SquadView.standing(uv.members)
		var i := 0
		while i < live.size():
			var p: Vector2 = v._member_pos(uv, live[i])
			flame.call(p.x + 8, p.y - SquadView.member_height(u.typeId) - 10, Rng.hash2(i, uv.uid.length()) * 40 + i)
			i += 3
	if v._host_alpha > 0.05:
		for i in v._host_torches.size():
			var t: Vector2 = v._host_torches[i]
			flame.call(t.x, t.y - 8, i * 1.7)


func _draw_dawn(ci: CanvasItem) -> void:
	ci.draw_texture_rect(_white, Rect2(0, 0, v._w, v._h), false)


# ---------------------------------------------------------------- stamps

## Soft round light stamps, drawn once and scaled per light (the original's
## 128 px radial-gradient canvases). Gradients interpolate premultiplied on the
## canvas: the flame's colour stops are sampled that way into the gradient.
static func stamp(kind: String) -> Texture2D:
	if _stamps.has(kind):
		return _stamps[kind]
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	match kind:
		"hole_mul":
			# createRadialGradient(64, 64, 10, 64, 64, 64): 0.95 black inside r 10,
			# fading out at 64; stored as what multiplies the mask's alpha (1 - hole).
			offs = PackedFloat32Array([0.0, 10.0 / 64.0, 1.0])
			cols = PackedColorArray([Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.05), Color(1, 1, 1, 1)])
		"glow":
			offs = PackedFloat32Array([0.0, 1.0])
			cols = PackedColorArray([Color(1, 170 / 255.0, 70 / 255.0, 1), Color(1, 170 / 255.0, 70 / 255.0, 0)])
		_:
			for i in 17:
				var t := i / 16.0
				offs.append(t)
				cols.append(_flame_at(t))
	g.offsets = offs
	g.colors = cols
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_stamps[kind] = tex
	return tex


## The flame stamp at radius t (0..1): (255,220,140,1) -> 0.35 (255,140,40,0.6)
## -> (255,90,20,0), interpolated premultiplied.
static func _flame_at(t: float) -> Color:
	var c0 := Vector4(1.0, 220 / 255.0, 140 / 255.0, 1.0)
	var c1 := Vector4(1.0 * 0.6, 140 / 255.0 * 0.6, 40 / 255.0 * 0.6, 0.6)
	var p: Vector4 = c0.lerp(c1, t / 0.35) if t < 0.35 else c1.lerp(Vector4.ZERO, (t - 0.35) / 0.65)
	if p.w <= 0.0001:
		return Color(1, 140 / 255.0, 40 / 255.0, 0)
	return Color(p.x / p.w, p.y / p.w, p.z / p.w, p.w)
