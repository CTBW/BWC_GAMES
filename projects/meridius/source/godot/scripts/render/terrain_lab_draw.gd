## The test grid samples the same height field as the textured ground.
extends "res://scripts/render/battle_draw.gd"

const Woodland = preload("res://scripts/render/woodland_kit.gd")


func _woodland_sprite(prop: String, x: int, y: int) -> Dictionary:
	if not v.painted_woodland or v.field_index not in [1, 3]:
		return {}
	var kind := ""
	match prop:
		"tree_pine": kind = "pine"
		"tree_oak": kind = "beech" if Rng.hash2(x, y, 193) < 0.58 else "oak"
		"bush": kind = "shrub"
	if kind == "":
		return {}
	return Woodland.sprite(kind, 0.87 + Rng.hash2(x, y, 231) * 0.25)


func _prop_list() -> Array:
	if not _props.is_empty() or v.b == null:
		return _props
	super._prop_list()
	if not v.painted_woodland or v.field_index not in [1, 3]:
		return _props
	for pr in _props:
		if pr == null:
			continue
		if pr.get("under", false):
			# The production fern (battle_draw.gd), compared with the keyed painting.
			# Fallen wood and stones stay as they are.
			if pr.get("decor", "fern") == "fern":
				pr.s = Woodland.sprite("fern", 0.8 + Rng.hash2(roundi(pr.x), roundi(pr.y), 820) * 0.5)
				_update_bounds(pr)
			continue
		var tile: Dictionary = Grid.tile_at(v.b.map, pr.x, pr.y)
		var s := _woodland_sprite(tile.get("prop", ""), pr.x, pr.y)
		if not s.is_empty():
			pr.s = s
			# Paintings have authored light from the upper left: don't mirror it.
			pr.flip = false
			_update_bounds(pr)
	return _props


func _update_bounds(pr: Dictionary) -> void:
	var s: Dictionary = pr.s
	pr.k = s.scale
	pr.bx0 = pr.px - s.ax * s.scale
	pr.bx1 = pr.bx0 + s.w * s.scale
	pr.by0 = pr.py - s.ay * s.scale


func _shadow(ci: CanvasItem, s: Dictionary, p: Vector2, flip: bool, alpha: float) -> void:
	if not s.get("woodland", false):
		Assets.draw_cast_shadow(ci, s, p.x, p.y, flip, 1.0, alpha)
		return
	var skew := Transform2D(Vector2(1, 0), Vector2(-0.75, -0.32), p)
	var xf := skew * Transform2D(0.0, Vector2(s.scale, s.scale), 0.0, Vector2.ZERO)
	Assets._blit(ci, s, xf, Woodland.color(Color(0, 0, 0, alpha)))


func draw_prop_shadows(ci: CanvasItem) -> void:
	ci.material = _sorted_mat
	Assets.draw_base = Transform2D.IDENTITY
	for pr in _prop_list():
		if pr != null:
			_shadow(ci, pr.s, Vector2(pr.px, pr.py), pr.flip, 0.17 if pr.tree else 0.12)


func draw_outer(ci: CanvasItem) -> void:
	ci.material = _sorted_mat
	ci.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	Assets.draw_base = Transform2D.IDENTITY
	var props: Array = v.surroundings.props.duplicate()
	props.sort_custom(func(a, b): return a.x + a.y < b.x + b.y)
	for p in props:
		var s := Assets.sprite(_prop_sprite(p.prop), p.v)
		var painted := _woodland_sprite(p.prop, p.x, p.y)
		if not painted.is_empty():
			s = painted
		var h: float = v.terrain_surface.surface(p.x, p.y) if v.terrain_surface != null else p.h
		var at := Iso.iso(p.x, p.y, h)
		var flip := painted.is_empty() and Rng.hash2(p.x, p.y, 9) > 0.5
		_shadow(ci, s, at, flip, 0.18)
		var tint := Color(0.77, 0.87, 0.81)
		Assets.draw_sprite(ci, s, at.x, at.y, flip, 1.0, Woodland.color(tint) if not painted.is_empty() else tint)


func _draw_item(ci: CanvasItem, it: Array, time: float) -> void:
	if it[0] == K_PROP and it[1].s.get("woodland", false):
		var pr: Dictionary = it[1]
		var shade := Rng.hash2(int(pr.x), int(pr.y), 54)
		var tint := Color(0.77, 0.87, 0.88).lerp(Color(1.0, 0.99, 0.9), shade)
		tint.a = it[2]
		Assets.draw_sprite(ci, pr.s, pr.px, pr.py, false, 1.0, Woodland.color(tint), 1.0, it[3])
	elif it[0] == K_PROP and it[1].tree:
		var pr: Dictionary = it[1]
		var shade := Rng.hash2(pr.x, pr.y, 54)
		var tint := Color(0.67, 0.84, 0.83).lerp(Color(1.0, 0.98, 0.77), shade)
		tint.a = it[2]
		Assets.draw_sprite(ci, pr.s, pr.px, pr.py, pr.flip, 1.0, tint, 1.0, it[3])
	else:
		super._draw_item(ci, it, time)


func diamond(x: float, y: float, inset := 0.0) -> PackedVector2Array:
	if v.terrain_surface == null:
		return super.diamond(x, y, inset)
	var s := 0.5 - inset
	var pts := PackedVector2Array()
	for d in [Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s)]:
		pts.append(Iso.iso(x + d.x, y + d.y, v._tile_h(x + d.x, y + d.y)))
	return pts


func draw_grid(ci: CanvasItem) -> void:
	if v.terrain_surface == null:
		super.draw_grid(ci)
		return
	var segs := PackedVector2Array()
	for t in v.b.map.tiles:
		for axis in 2:
			for i in 8:
				var a := Vector2(t.x - 0.5, t.y - 0.5)
				var b := a
				a[axis] += float(i) / 8.0
				b[axis] += float(i + 1) / 8.0
				segs.append(Iso.iso(a.x, a.y, v._tile_h(a.x, a.y)))
				segs.append(Iso.iso(b.x, b.y, v._tile_h(b.x, b.y)))
	ci.draw_multiline(segs, Color(0.08, 0.12, 0.1, 0.32), 1.2, true)
