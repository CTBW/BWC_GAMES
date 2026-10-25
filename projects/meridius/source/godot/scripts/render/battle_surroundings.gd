## Presentation-only terrain outside the tactical grid. Entry corridors stay
## clear for the existing spawn animations; no rules or deployment cells change.
extends RefCounted

const Rng = preload("res://scripts/core/rng.gd")
const Mapgen = preload("res://scripts/rules/mapgen.gd")


static func build(map: Dictionary) -> Dictionary:
	var tiles: Array = []
	var props: Array = []
	var spans: Array = Mapgen._approach_spans(map)
	# Retain the surrounding forest, but clear small props from entry corridors.
	for p in map.get("outer", []):
		if Mapgen._in_spans(map, spans, p.x, p.y) == null:
			props.append(p)
	# Continue the field's grass and soil through the approaches. A few narrow
	# worn tracks read as entrances instead of a whole brown staging rectangle.
	for g in map.get("outerGround", []):
		var edge = Mapgen._in_spans(map, spans, g.x, g.y)
		var terrain := "grass"
		if edge != null:
			var ns: bool = edge == "n" or edge == "s"
			var along: float = g.x if ns else g.y
			var lanes: Array = map.entries[edge]
			var coords: Array = lanes.map(func(p): return p.x if ns else p.y)
			coords.sort()
			var lo: float = coords[0]
			var hi: float = coords[-1]
			var count := 2 if hi - lo > 7 else 1
			for i in count:
				var centre := lerpf(lo, hi, (i + 0.5) / count)
				if absf(along - centre) < 0.85:
					terrain = "dirt"
			# Small patches use the same ground palette as the playable map.
			if terrain == "grass" and Rng.hash2(g.x, g.y, map.seed) < 0.08:
				terrain = "brush"
		else:
			terrain = g.terrain
		tiles.append({"x": g.x, "y": g.y, "h": 0, "terrain": terrain})
	return {"tiles": tiles, "props": props}
