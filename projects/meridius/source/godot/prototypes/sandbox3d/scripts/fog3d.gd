## Fog of war for the 3D sandbox: the battle's sight rules
## (scripts/rules/visibility.gd: sight 7, hills, trees and thickets in the
## way) over the field's map, eased as battle_fog.gd eases its shroud, into a
## texture of one texel a tile (R seen now, G explored) that the ground and
## the woodland cards shade with the battle's grain.
extends RefCounted

const Visibility = preload("res://scripts/rules/visibility.gd")
const Grid = preload("res://scripts/rules/grid.gd")
## How fast the shroud follows the eyes (battle_fog.gd blends at 4.5 a second).
const EASE := 4.5

var map: Dictionary
var tex: ImageTexture
var seen := {}
var explored := {}
var _img: Image
var _cur: PackedFloat32Array
var _key := ""
var _eyes: Array = []
## What each eye tile sees (Visibility.field of that eye alone): the field is
## their union, so a unit stepping back onto a tile costs nothing.
var _sight := {}
## The shroud has caught up with the eyes: nothing to ease until they move.
var _settled := false


func _init(m: Dictionary) -> void:
	map = m
	_img = Image.create(m.w, m.h, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, 1))
	tex = ImageTexture.create_from_image(_img)
	_cur.resize(m.w * m.h * 2)


## The eyes: [{"x", "y"} (tiles), ...]. Sight is worked out again only when one moves.
func update(eyes: Array, dt: float) -> void:
	var parts := PackedStringArray()
	for e in eyes:
		parts.append("%d,%d" % [e.x, e.y])
	var key := "|".join(parts)
	if key != _key:
		_key = key
		_eyes = eyes
		seen = {}
		for e in eyes:
			var at := Vector2i(e.x, e.y)
			if not _sight.has(at):
				_sight[at] = Visibility.field(map, [e])
			seen.merge(_sight[at])
		for k in seen:
			explored[k] = true
		_settled = false
	if _settled:
		return
	var a := 1.0 - exp(-EASE * 2.0 * dt) if dt > 0.0 else 1.0
	var changed := false
	for y in map.h:
		for x in map.w:
			var i: int = y * map.w + x
			var k := Grid.key(x, y)
			var s := 1.0 if seen.has(k) else 0.0
			var g := 1.0 if explored.has(k) else 0.0
			var r0 := _cur[i * 2]
			var g0 := _cur[i * 2 + 1]
			if absf(s - r0) > 0.002 or absf(g - g0) > 0.002:
				_cur[i * 2] = lerpf(r0, s, a)
				_cur[i * 2 + 1] = lerpf(g0, g, a)
				_img.set_pixel(x, y, Color(_cur[i * 2], _cur[i * 2 + 1], 0, 1))
				changed = true
	if changed:
		tex.update(_img)
	else:
		_settled = true


## Forget what was explored: only what the eyes see now stays clear.
func forget() -> void:
	explored.clear()
	for k in seen:
		explored[k] = true
	_settled = false


## Whether a figure on tile t shows: on seen ground, and in the woods only
## close up (Visibility.unit_seen).
func shows(t: Vector2i) -> bool:
	return Visibility.unit_seen(map, _eyes, seen, {"x": t.x, "y": t.y})
