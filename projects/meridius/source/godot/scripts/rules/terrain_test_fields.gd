## Deterministic terrain experiments, not campaign maps or historical replicas.
extends RefCounted

const Rng = preload("res://scripts/core/rng.gd")
const Soldier = preload("res://scripts/meta/soldier.gd")
const SIZE := 24
const BORDER := 16
const NAMES := ["Rolling meadow", "Northern forest ford", "Opposing ridges", "Woodland scouting", "Bluff and hollow"]
const NOTES := [
	"Open hills, woodland pockets and a winding track. Inspect grass / soil blends and a broad crest.",
	"Mixed northern woodland frames a shallow ford. Inspect banks, bushes, fallen wood and tree grounding.",
	"Two long ridges around a worn valley. Inspect long slopes, the crest and the descent behind it.",
	"Fog of war: move north into the trees to find a concealed enemy. Return south to leave explored ground in shadow. Patrols refill; the sentry holds position.",
	"A raised bluff with crumbling earth banks toward the camera and a long ramp behind; a track along its foot. Inspect the banks, the grass lip and the climb.",
]


static func hill(x: float, y: float, cx: float, cy: float, rx: float, ry: float) -> float:
	return exp(-pow((x - cx) / rx, 2.0) - pow((y - cy) / ry, 2.0))


## A flat-topped rise `top` levels high: steep toward the camera (+x, +y),
## a long gentle ramp on the far side, its outline bent so it is not an ellipse.
static func bluff(x: float, y: float, cx: float, cy: float, rx: float, ry: float, top: float) -> float:
	var u := (x - cx) / rx
	var v := (y - cy) / ry
	var a := atan2(v, u)
	var r := sqrt(u * u + v * v) + 0.08 * sin(a * 3.0 + 1.3) + 0.05 * sin(a * 5.0 + 0.4)
	var toward := clampf((u + v) / maxf(0.001, absf(u) + absf(v)), -1.0, 1.0) * 0.5 + 0.5
	return top * (1.0 - smoothstep(lerpf(0.3, 0.74, toward), lerpf(1.5, 1.0, toward), r))


static func height_at(which: int, x: float, y: float) -> float:
	match which:
		0:
			return 0.25 + 3.9 * hill(x, y, 9, 8, 6.5, 5.5) + 2.5 * hill(x, y, 18, 19, 7, 6)
		1:
			var river := 13.0 + sin(y * 0.24) * 1.2
			var bank := smoothstep(1.7, 5.5, absf(x - river))
			return bank * (0.5 + 3.2 * hill(x, y, 7, 4, 7, 5) + 3.8 * hill(x, y, 19, 21, 8, 6))
		4:
			return 0.15 + bluff(x, y, 10, 8, 6.5, 5.0, 2.7) + bluff(x, y, 19.5, 5.5, 3.2, 2.6, 1.3) \
				+ 0.6 * hill(x, y, 5, 19, 5, 4) + 0.3 * hill(x, y, 10, 8, 3, 3)
		_:
			return 0.2 + 4.2 * hill(x, y, 10, 5.5, 22, 3.8) + 3.6 * hill(x, y, 13, 18, 24, 4.2)


static func make(which: int, smooth := true) -> Dictionary:
	if which == 3:
		var field := make(1, smooth)
		field["fogOfWar"] = true
		field.map.name = NAMES[3]
		field.map.id = "woodland_scouting"
		field.units[0].x = 5
		field.units[0].y = 10
		field.units[1].x = 3
		field.units[1].y = 12
		var sentry := Soldier.make_enemy("goblin_spear", 1, "woodland-sentry", Rng.new(713))
		sentry.x = 7
		sentry.y = 6
		field.units.append(sentry)
		for pos in [Vector2i(5, 8), Vector2i(7, 6)]:
			var t: Dictionary = field.map.tiles[pos.y * SIZE + pos.x]
			t.terrain = "forest"
			t["prop"] = "tree_oak"
		for u in field.units.slice(0, 2):
			field.map.tiles[u.y * SIZE + u.x].erase("prop")
		return field
	var seed := 7341 + which * 187
	var tiles: Array = []
	var outer: Array = []
	var outer_props: Array = []
	for y in range(-BORDER, SIZE + BORDER):
		for x in range(-BORDER, SIZE + BORDER):
			var elevation := height_at(which, x, y)
			var noise := Rng.hash2(x, y, seed)
			var road := 14.8 + sin(x * 0.31 + 0.6) * 1.3 if which == 4 else 12.0 + sin(x * 0.23) * 1.6
			var terrain := "grass"
			var prop := ""
			var woods := false
			match which:
				0:
					woods = hill(x, y, 3, 5, 4, 4) > 0.45 or hill(x, y, 21, 3, 5, 5) > 0.48 or hill(x, y, 3, 22, 5, 4) > 0.5
				1:
					woods = y < 8 + sin(x * 0.4) or y > 18 + sin(x * 0.3)
				4:
					woods = y < 1.5 + sin(x * 0.5) * 0.8 or (x < 1.0 and y < 12) \
						or hill(x, y, 23, 22, 5, 4) > 0.45 or hill(x, y, 23, 12, 2.5, 2) > 0.6
				_:
					woods = (x < 3 or x > 21) and noise < 0.7
			if woods:
				terrain = "forest"
				if noise < 0.48:
					prop = "tree_pine" if noise < (0.27 if which == 1 else 0.2) else "tree_oak"
				elif noise < 0.67:
					prop = "bush"
				elif noise < 0.71:
					prop = "stump" if noise < 0.69 else "log"
			elif noise < 0.09:
				terrain = "brush"
			if absf(y - road) < 0.85:
				terrain = "dirt"
				prop = ""
			if which == 2 and absf(y - 11.8) < 1.4:
				terrain = "mud" if noise < 0.7 else "dirt"
			if which == 1:
				var river := 13.0 + sin(y * 0.24) * 1.2
				if absf(x - river) < 1.5:
					terrain = "shallows" if absf(y - road) < 1.8 else "water"
					prop = ""
				elif absf(x - river) < 2.4:
					terrain = "mud"
					prop = ""
			if terrain == "grass" and noise > 0.975 and absf(y - road) > 2.0:
				prop = "rock_small"
			# Stones fallen from the bluff's banks.
			if which == 4 and terrain == "grass" and noise > 0.9 and elevation > 0.5 and elevation < 2.2:
				prop = "rock_small"
			var t := {"x": x, "y": y, "h": roundi(elevation), "surface_h": elevation,
				"terrain": terrain, "v": floori(noise * 10000)}
			var inside := x >= 0 and y >= 0 and x < SIZE and y < SIZE
			if inside and prop != "":
				t.prop = prop
			if inside:
				tiles.append(t)
			else:
				outer.append(t)
				if woods and prop != "" and noise < 0.15:
					var p: Dictionary = t.duplicate()
					p.prop = "tree_pine" if Rng.hash2(x, y, seed + 1) < 0.55 else "tree_oak"
					outer_props.append(p)
	var starts := [Vector2i(6, 15), Vector2i(8, 17)]
	if which == 1:
		starts = [Vector2i(5, 13), Vector2i(7, 15)]
	elif which == 2:
		starts = [Vector2i(8, 18), Vector2i(12, 17)]
	elif which == 4:
		starts = [Vector2i(5, 17), Vector2i(8, 19)]
	var units: Array = []
	for i in starts.size():
		var u := Soldier.make_enemy("footman" if i == 0 else "spearman", 1, "terrain-%d" % i, Rng.new(seed + i))
		u.faction = "player"
		u.name = "Terrain patrol" if i == 0 else "Slope patrol"
		u.x = starts[i].x
		u.y = starts[i].y
		u.facing = 3
		units.append(u)
		tiles[u.y * SIZE + u.x].erase("prop")
	return {"seed": seed, "units": units, "map": {
		"id": "terrain_test_%d" % which, "name": NAMES[which], "w": SIZE, "h": SIZE,
		"seed": seed, "border": BORDER, "biome": "summer", "scale": "small",
		"tiles": tiles, "outerGround": outer, "outer": outer_props, "entries": {}, "approaches": [],
		"playerDeploy": [], "enemyDeploy": [], "terrainLab": true, "smoothTerrain": smooth,
	}}
