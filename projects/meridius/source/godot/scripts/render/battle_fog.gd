## Soft battlefield shroud driven only by the positions currently being played back.
extends Node2D

const Visibility = preload("res://scripts/rules/visibility.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const Iso = preload("res://scripts/render/iso.gd")
const FogShader = preload("res://assets/shaders/battle_fog.gdshader")
var v
var side := "player"
var explored := {}
var seen := {}
var visible_units := {}
var _key := ""
var _image: Image
var _texture: ImageTexture
var _heights: ImageTexture
var _cover: ColorRect
var _blend := 1.0
var _old_texture: ImageTexture
var revealed := {}


func reveal(uid: String) -> void:
	revealed[uid] = true
	_key = ""
	refresh(0)


func reset_side(faction: String) -> void:
	for uid in revealed.keys():
		if v._u(uid).faction == faction:
			revealed.erase(uid)
	_key = ""
	refresh(0)


func setup(view) -> void:
	v = view
	name = "FogOfWar"
	_image = Image.create(v.b.map.w, v.b.map.h, false, Image.FORMAT_RGBA8)
	_image.fill(Color(0, 0, 0, 1))
	_texture = ImageTexture.create_from_image(_image)
	_old_texture = ImageTexture.create_from_image(_image)
	var heights := Image.create(v.b.map.w, v.b.map.h, false, Image.FORMAT_RF)
	for t in v.b.map.tiles:
		heights.set_pixel(t.x, t.y, Color(v._tile_h(t.x, t.y), 0, 0, 1))
	_heights = ImageTexture.create_from_image(heights)
	_cover = ColorRect.new()
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = FogShader
	mat.set_shader_parameter("sight_map", _texture)
	mat.set_shader_parameter("old_sight_map", _old_texture)
	mat.set_shader_parameter("height_map", _heights)
	mat.set_shader_parameter("fog_grain", load("res://assets/terrain/fog_grain.png"))
	mat.set_shader_parameter("map_size", Vector2(v.b.map.w, v.b.map.h))
	_cover.material = mat
	add_child(_cover)
	refresh(1.0, true)


func enabled() -> bool:
	return v != null and v.b.fog_enabled()


func set_side(value: String) -> void:
	side = value
	explored.clear()
	_key = ""
	refresh(1.0, true)


func refresh(dt: float, force := false) -> void:
	visible = enabled()
	if not visible:
		return
	var units: Array = []
	for uv in v.views.values():
		var u: Dictionary = v._u(uv.uid)
		units.append({"uid": uv.uid, "x": roundi(uv.x), "y": roundi(uv.y),
			"faction": u.faction, "status": "reserve" if uv.reserve or not uv.visible else uv.status,
			"alive": uv.alive, "vision": u.get("vision", Visibility.SIGHT)})
	var key := side + Visibility.stamp(units)
	if key != _key or force:
		var first := _key == "" or force
		_key = key
		var eyes := Visibility.observers(units, side)
		seen = Visibility.field(v.b.map, eyes)
		for u in units:
			if revealed.has(u.uid):
				seen[Grid.key(u.x, u.y)] = true
		explored.merge(seen)
		visible_units.clear()
		for u in units:
			if u.faction == side or (u.status != "reserve" and (revealed.has(u.uid) or Visibility.unit_seen(v.b.map, eyes, seen, u))):
				visible_units[u.uid] = true
		_old_texture.update(_image)
		for t in v.b.map.tiles:
			var k := Grid.key(t.x, t.y)
			_image.set_pixel(t.x, t.y, Color(1.0 if seen.has(k) else 0.0, 1.0 if explored.has(k) else 0.0, 0, 1))
		_texture.update(_image)
		_blend = 1.0 if first else 0.0
		v._danger_cache = null
		v._minimap_key = ""
		v.notify()
	_blend = minf(1.0, _blend + dt * 4.5)
	_cover.size = Vector2(v._w, v._h)
	var mat: ShaderMaterial = _cover.material
	mat.set_shader_parameter("camera", Vector2(v.cam.x, v.cam.y))
	mat.set_shader_parameter("view_size", _cover.size)
	mat.set_shader_parameter("zoom", v.cam.zoom)
	mat.set_shader_parameter("clock", v.time)
	mat.set_shader_parameter("blend", smoothstep(0.0, 1.0, _blend))


func sees(uid: String) -> bool:
	return not enabled() or visible_units.has(uid)


func tile_state(x: int, y: int) -> int:
	if not enabled() or seen.has(Grid.key(x, y)):
		return 2
	return 1 if explored.has(Grid.key(x, y)) else 0
