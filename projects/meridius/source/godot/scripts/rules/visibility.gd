## Shared battlefield sight. Pure data; used by rules and animation playback.
extends RefCounted

const Grid = preload("res://scripts/rules/grid.gd")
const SIGHT := 7
const WOODLAND_SIGHT := 2.1


static func woodland(map: Dictionary, at: Dictionary) -> bool:
	var t = Grid.tile_at(map, at.x, at.y)
	return t != null and (t.terrain == "forest" or String(t.get("prop", "")).begins_with("tree_") or t.get("prop") == "bush")


static func observers(units: Array, side: String) -> Array:
	return units.filter(func(u): return u.faction == side and u.status in ["active", "routing"] and u.get("alive", 1) > 0)


static func stamp(units: Array, side := "") -> String:
	var parts := PackedStringArray()
	for u in units:
		if side == "" or u.faction == side:
			parts.append("%s:%d:%d:%s:%d:%d" % [u.uid, u.x, u.y, u.status, u.get("alive", 1), radius(u)])
	return "|".join(parts)


static func radius(u: Dictionary) -> int:
	return int(u.get("vision", SIGHT))


static func tile_seen(map: Dictionary, eye: Dictionary, at: Dictionary) -> bool:
	if not Grid.in_bounds(map, eye.x, eye.y) or not Grid.in_bounds(map, at.x, at.y):
		return false
	var d := Grid.dist(eye, at)
	if d > radius(eye) + 0.01:
		return false
	if d <= 1.5:
		return true
	return not Grid.line_of_sight(map, eye, at).blocked


static func field(map: Dictionary, eyes: Array) -> Dictionary:
	var seen := {}
	for eye in eyes:
		var r := radius(eye)
		for y in range(maxi(0, eye.y - r), mini(map.h, eye.y + r + 1)):
			for x in range(maxi(0, eye.x - r), mini(map.w, eye.x + r + 1)):
				var k := Grid.key(x, y)
				if not seen.has(k) and tile_seen(map, eye, {"x": x, "y": y}):
					seen[k] = true
	return seen


static func unit_seen(map: Dictionary, eyes: Array, seen: Dictionary, target: Dictionary) -> bool:
	if not seen.has(Grid.key(target.x, target.y)):
		return false
	if not woodland(map, target):
		return true
	# The ground at a woodland edge may be known while its occupants remain concealed.
	for eye in eyes:
		if Grid.dist(eye, target) <= WOODLAND_SIGHT and tile_seen(map, eye, target):
			return true
	return false
