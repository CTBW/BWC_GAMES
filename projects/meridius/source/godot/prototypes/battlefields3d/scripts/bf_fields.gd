## The 3D battlefields' fields: four places of the Meridius frontier in four
## seasons, each a map in the rules' format ({x, y, h, surface_h, terrain,
## prop}) so scripts/rules/visibility.gd works out the fog of war over it
## unchanged, plus what is drawn on it:
##   - "pieces": houses, mills, ruins and the bridge, each over a footprint of
##     tiles that carry a rules prop (a house blocks sight as a high wall);
##   - "decor": single props (stalls, carts, harvest, yard and waterside
##     things, reeds, bank flowers) on their tiles;
##   - tile "art": a card other than the prop's own (a winter spruce for a pine).
## Every field is closed by woods: a band of trees and thickets along its edge,
## a tile to a few deep, deeper in tongues that make nooks and narrows, every
## tile of it a tree or a bush ("wild"), so no squad crosses it (the battle's
## maps are solidWoods). It stands back from what is placed (the pieces, the
## decor, fences, yards, fields, squares and roads, whose lanes run out
## through it) and from a field's "open" boxes. The woods go on outside. On
## the camera's side (south and east) the woods' first NEAR_RIM tiles are
## thickets, so no tree there hides the field behind it.
## The fields are laid out in design tiles, DESIGN to a side at 128 px a
## tile; make() fits them to W x H tiles of TILE_PX, so a field keeps its
## ground with fewer, bigger tiles (more room between two squads standing a
## tile apart) and its houses, trees and soldiers keep their size.
## Rules props are DB.PROPS ids, so the map is one the battle could load.
## Pure data: no nodes. bf_field.gd builds the scene from it.
extends RefCounted

const Fields = preload("res://scripts/rules/terrain_test_fields.gd")
const Rng = preload("res://scripts/core/rng.gd")

## A side of the fields as laid out below (design tiles of 128 px).
const DESIGN := 28.0
const W := 20
const H := 20
## Design tiles to tiles.
const K := W / DESIGN
## A tile's width on screen at zoom 1 (px): the design's 28 x 128 px over W.
const TILE_PX := 128.0 * DESIGN / W
## A tile's ground in design tiles: what is drawn so many to a tile (trees in
## the woods, ferns, grass) is drawn this many times over.
const AREA := 1.0 / (K * K)
## The tiles laid outside the field (the design's 12).
const BORDER := 9
const IDS := ["millford", "ashby", "frosthollow", "willowford"]
## How far into the woods on the camera's side they are thickets (tiles): a
## tree hides about this much of the ground behind it.
const NEAR_RIM := 3.5 * K

## Footprints (tiles across x, y) and rules props of the pieces. A piece's card
## stands on the near corner of its painted base: its width in world px (as
## cut by tools/cut_art.py) over a tile's TILE_PX gives the base's side, 1.3
## to 1.9 tiles, so a house, a barn or a ruin stands on 2 x 2 tiles and the
## bridge's deck spans 3.
const PIECE := {
	"house_townhouse": {"fp": Vector2i(2, 2), "rules": "wall_high", "w": 250},
	"house_inn": {"fp": Vector2i(2, 2), "rules": "wall_high", "w": 270},
	"house_cottage_stone": {"fp": Vector2i(2, 2), "rules": "wall_high", "w": 225},
	"house_chapel": {"fp": Vector2i(2, 2), "rules": "wall_high", "w": 250},
	"house_barn": {"fp": Vector2i(2, 2), "rules": "wall_high", "w": 330},
	"house_longhouse": {"fp": Vector2i(2, 2), "rules": "wall_high", "w": 330},
	"house_windmill": {"fp": Vector2i(2, 2), "rules": "wall_high", "w": 260},
	"watermill": {"fp": Vector2i(2, 2), "rules": "wall_high", "w": 290},
	"ruin_farmhouse": {"fp": Vector2i(2, 2), "rules": "wall_high", "w": 230},
	"ruin_barn_burnt": {"fp": Vector2i(2, 2), "rules": "wall_high", "w": 320},
	"ruin_chapel": {"fp": Vector2i(2, 2), "rules": "wall_high", "w": 290},
	"ruin_colonnade": {"fp": Vector2i(2, 2), "rules": "wall_ruin", "w": 300},
	"ruin_stones": {"fp": Vector2i(2, 2), "rules": "rock_large", "w": 270},
	"ruin_wall_corner": {"fp": Vector2i(2, 2), "rules": "wall_ruin", "w": 220},
	"w_house_longhouse": {"fp": Vector2i(2, 2), "rules": "wall_high", "w": 330},
	"w_house_cottage_stone": {"fp": Vector2i(2, 2), "rules": "wall_high", "w": 225},
	"w_house_chapel": {"fp": Vector2i(2, 2), "rules": "wall_high", "w": 250},
	"w_ruin_stones": {"fp": Vector2i(2, 2), "rules": "rock_large", "w": 270},
	"bridge_stone": {"fp": Vector2i(1, 3), "rules": "", "w": 480},
}


static func make(id: String) -> Dictionary:
	match id:
		"millford":
			return _generate(_scaled(_millford()))
		"ashby":
			return _generate(_scaled(_ashby()))
		"frosthollow":
			return _generate(_scaled(_frosthollow()))
		"willowford":
			return _generate(_scaled(_willowford()))
	return {}


# --- The four fields (in design tiles) ---------------------------------------------

## Summer: a market town where the road crosses the river on a stone bridge;
## the windmill on the hill to the north, the watermill below the town.
static func _millford() -> Dictionary:
	var river := func(x: float) -> float: return 10.0 + 1.2 * sin(x * 0.25)
	var road := func(y: float) -> float: return 15.0 + 0.6 * sin(y * 0.3 + 0.5)
	var by: float = river.call(road.call(10.0))
	return {
		"id": "millford", "name": "Millford", "season": "summer", "seed": 3301,
		"blurb": "Summer. A market town where the road crosses the river on an old stone bridge: the market square with its stalls and well, the chapel on its knoll, the watermill below the houses and the windmill on the hill across the water.",
		"height": func(x: float, y: float) -> float:
			var h := 1.7
			h += 2.6 * Fields.hill(x, y, 6.5, 4.5, 4.0, 3.6)
			h += 1.3 * Fields.hill(x, y, 14.0, -5.0, 18.0, 8.0)
			h += 0.9 * Fields.hill(x, y, 22.0, 23.0, 3.6, 3.2)
			h += 1.6 * Fields.hill(x, y, 27.0, 2.0, 5.0, 4.0)
			h += 2.0 * Fields.hill(x, y, -8.0, 22.0, 9.0, 12.0) + 1.5 * Fields.hill(x, y, 36.0, 32.0, 8.0, 8.0)
			return h,
		"river": {"pts": _line(func(t: float) -> Vector2: return Vector2(t, river.call(t)), -14.0, 42.0, 1.0),
			"half": 1.2, "shallow": 0.6, "level": 1.2, "bed": 0.55},
		"roads": [
			{"pts": _line(func(t: float) -> Vector2: return Vector2(road.call(t), t), -14.0, 42.0, 1.0), "w": 0.7},
			{"pts": PackedVector2Array([Vector2(12.6, 17.8), Vector2(6.0, 18.8), Vector2(-2.0, 21.0), Vector2(-14.0, 22.0)]), "w": 0.6},
			{"pts": PackedVector2Array([Vector2(17.4, 17.0), Vector2(22.0, 15.2), Vector2(24.0, 14.4)]), "w": 0.5},
			{"pts": PackedVector2Array([Vector2(road.call(5.0), 5.0), Vector2(9.0, 5.6), Vector2(7.6, 5.0)]), "w": 0.5},
		],
		"squares": [{"c": Vector2(15.0, 17.6), "r": 2.7}],
		"woods": func(x: float, y: float, n: float) -> bool:
			if y < 1.6 + 1.2 * sin(x * 0.4 + 0.7) + (n - 0.5) * 1.4 and (x < 3.0 or x > 11.0):
				return true
			if x > 25.8 + 0.8 * sin(y * 0.5) + (n - 0.5) and y > 13.0:
				return true
			if x < 1.8 + 0.9 * sin(y * 0.6) + (n - 0.5) and y > 12.5:
				return true
			return Fields.hill(x, y, 4.0, 26.0, 3.2, 2.4) > 0.5,
		"pieces": [
			{"key": "bridge_stone", "c": Vector2(road.call(by), by)},
			{"key": "house_townhouse", "c": Vector2(11.5, 15.5)},
			{"key": "house_inn", "c": Vector2(18.5, 15.5)},
			{"key": "house_townhouse", "c": Vector2(18.5, 20.5)},
			{"key": "house_cottage_stone", "c": Vector2(11.5, 20.5)},
			{"key": "house_cottage_stone", "c": Vector2(7.5, 15.5)},
			{"key": "house_longhouse", "c": Vector2(14.5, 22.5)},
			{"key": "house_chapel", "c": Vector2(22.5, 23.5)},
			{"key": "watermill", "c": Vector2(24.5, 12.5)},
			{"key": "house_windmill", "c": Vector2(6.5, 4.5)},
			{"key": "house_barn", "c": Vector2(21.0, 4.5)},
		],
		"decor": [
			{"key": "market_stall", "at": Vector2(13.4, 16.6), "rules": "crates"},
			{"key": "market_stall", "at": Vector2(16.6, 16.4), "rules": "crates"},
			{"key": "market_stall", "at": Vector2(13.8, 19.0), "rules": "crates"},
			{"key": "p_well", "at": Vector2(16.0, 18.8), "rules": "well"},
			{"key": "p_crates", "at": Vector2(20.4, 19.0), "rules": "crates"},
			{"key": "p_cart", "at": Vector2(9.6, 21.8), "rules": "cart"},
			{"key": "p_rick", "at": Vector2(18.0, 2.4), "rules": "haystack"},
			{"key": "p_rick", "at": Vector2(23.6, 2.0), "rules": "haystack"},
			{"key": "harvest_firewood", "at": Vector2(9.2, 14.2), "rules": ""},
			{"key": "harvest_bale", "at": Vector2(21.4, 2.4), "rules": ""},
			# The town's yards and street.
			{"key": "barrels", "at": Vector2(19.2, 17.1), "rules": ""},
			{"key": "milk_churns", "at": Vector2(18.0, 17.3), "rules": ""},
			{"key": "trough", "at": Vector2(20.8, 17.8), "rules": ""},
			{"key": "sacks", "at": Vector2(12.8, 19.3), "rules": ""},
			{"key": "chopping_block", "at": Vector2(10.0, 14.7), "rules": ""},
			{"key": "beehives", "at": Vector2(9.4, 21.2), "rules": ""},
			{"key": "lantern_post", "at": Vector2(19.6, 22.4), "rules": ""},
			{"key": "lantern_post", "at": Vector2(13.9, 13.4), "rules": ""},
			{"key": "signpost", "at": Vector2(14.3, 6.0), "rules": ""},
			{"key": "wheelbarrow", "at": Vector2(21.95, 6.45), "rules": ""},
			{"key": "shrine", "at": Vector2(16.3, 2.8), "rules": ""},
		],
		# The paddock round the barn, its gate at the corner by the river.
		"fences": [[Vector2(16.5, 1.0), Vector2(16.5, 6.5)], [Vector2(19.0, 7.5), Vector2(24.5, 7.5)]],
		"reeds": 0.35,
		"bank": {"horsetail": 0.08, "iris": 0.06},
		"scatter": {"oak": 0.012, "rock": 0.04, "bush": 0.03},
		"focus": Vector2(15.0, 14.5), "close": Vector2(15.0, 16.0),
		"scouts": [Vector2i(15, 23), Vector2i(10, 12), Vector2i(21, 8)],
	}


## Autumn: a farm the war has passed through, the farmhouse roofless and the
## barn still smouldering, the harvest left standing in the field.
static func _ashby() -> Dictionary:
	return {
		"id": "ashby", "name": "Ashby farm", "season": "autumn", "seed": 5107, "weather": "leaves",
		"blurb": "Autumn. A farm the war has passed through: the farmhouse roofless, the barn still smouldering, a wagon wrecked in the lane and the harvest left standing in the stubble. Russet woods, falling leaves.",
		"height": func(x: float, y: float) -> float:
			var h := 0.7
			h += 2.3 * Fields.hill(x, y, 7.0, 5.0, 5.5, 4.5)
			h += 1.7 * Fields.hill(x, y, 22.0, 21.0, 6.0, 5.0)
			h += 0.9 * Fields.hill(x, y, 14.0, 12.5, 5.0, 4.0)
			h += Fields.bluff(x, y, 5.0, 19.0, 3.8, 3.0, 1.8)
			h += 2.4 * Fields.hill(x, y, -8.0, 8.0, 8.0, 14.0) + 2.0 * Fields.hill(x, y, 14.0, -10.0, 16.0, 7.0)
			return h,
		"ponds": [{"c": Vector2(22.0, 6.0), "rx": 1.7, "ry": 1.3, "level": 0.95}],
		"roads": [
			{"pts": PackedVector2Array([Vector2(-14.0, 25.0), Vector2(0.0, 23.5), Vector2(8.0, 19.8), Vector2(11.5, 16.0), Vector2(13.0, 14.6)]), "w": 0.65},
			{"pts": PackedVector2Array([Vector2(13.0, 14.6), Vector2(15.5, 9.0), Vector2(15.0, 2.0), Vector2(16.0, -14.0)]), "w": 0.6},
		],
		"yards": [{"c": Vector2(14.5, 12.5), "r": 3.4}],
		"fields": [{"rect": Rect2(18.5, 13.5, 7.0, 8.0)}],
		"woods": func(x: float, y: float, n: float) -> bool:
			if y < 2.2 + 1.3 * sin(x * 0.45 + 0.7) + (n - 0.5) * 1.5:
				return true
			if x < 1.6 + 0.9 * sin(y * 0.5) + (n - 0.5) * 1.2 and y < 17.0:
				return true
			if Fields.hill(x, y, 26.0, 9.0, 2.4, 3.6) > 0.42:
				return true
			return Fields.hill(x, y, 10.0, 26.5, 4.0, 1.8) > 0.55,
		"pieces": [
			{"key": "ruin_farmhouse", "c": Vector2(12.5, 11.5)},
			{"key": "ruin_barn_burnt", "c": Vector2(17.0, 9.5), "smoke": "ash"},
			{"key": "ruin_wall_corner", "c": Vector2(9.5, 14.5)},
		],
		"decor": [
			{"key": "wagon_wreck", "at": Vector2(11.4, 17.0), "rules": "cart"},
			{"key": "harvest_pumpkins", "at": Vector2(15.4, 14.2), "rules": ""},
			{"key": "harvest_pumpkins", "at": Vector2(16.2, 14.8), "rules": ""},
			{"key": "harvest_firewood", "at": Vector2(14.4, 10.2), "rules": ""},
			{"key": "harvest_bale", "at": Vector2(10.6, 9.8), "rules": ""},
			{"key": "harvest_bale", "at": Vector2(11.4, 9.2), "rules": ""},
			{"key": "harvest_sheaves", "at": Vector2(18.4, 12.8), "rules": ""},
			{"key": "p_rick", "at": Vector2(20.0, 11.8), "rules": "haystack"},
			{"key": "p_crates", "at": Vector2(15.8, 12.6), "rules": "crates"},
			{"key": "scarecrow", "at": Vector2(22.0, 17.4), "rules": ""},
			{"key": "wheelbarrow", "at": Vector2(16.8, 13.6), "rules": ""},
			{"key": "sacks", "at": Vector2(14.0, 13.0), "rules": ""},
			{"key": "signpost", "at": Vector2(10.8, 15.4), "rules": ""},
		],
		"reeds": 0.45,
		"stooks": {"rect": Rect2(19.0, 14.0, 6.0, 7.0), "step": 1.6},
		"fences": [[Vector2(18.0, 13.0), Vector2(26.0, 13.0)], [Vector2(18.0, 13.0), Vector2(18.0, 22.0)], [Vector2(8.0, 7.5), Vector2(8.0, 12.0)]],
		"scatter": {"oak": 0.02, "rock": 0.02, "bush": 0.03},
		"focus": Vector2(14.0, 13.0), "close": Vector2(14.0, 12.0),
		"scouts": [Vector2i(6, 23), Vector2i(14, 19), Vector2i(23, 23)],
	}


## Winter: a hamlet in the snow by a frozen lake, smoke from its chimneys, the
## standing stones on the hill above it.
static func _frosthollow() -> Dictionary:
	return {
		"id": "frosthollow", "name": "Frosthollow", "season": "winter", "frozen": true, "seed": 7717, "weather": "snow",
		"blurb": "Winter. A hamlet in deep snow beside a frozen lake: longhouse, cottages with lit windows and smoking chimneys, the chapel on its rise, the old standing stones on the hill above. Snow-laden spruce and pine, bare oaks and birches, falling snow.",
		"height": func(x: float, y: float) -> float:
			var h := 1.1
			h += 3.0 * Fields.hill(x, y, 21.5, 5.0, 4.6, 4.0)
			h += 2.0 * Fields.hill(x, y, 3.0, 9.0, 4.0, 7.0)
			h += 1.0 * Fields.hill(x, y, 19.5, 19.5, 3.4, 3.0)
			h += Fields.bluff(x, y, 13.0, 3.0, 4.0, 2.6, 1.6)
			h += 2.6 * Fields.hill(x, y, -9.0, 6.0, 8.0, 14.0) + 2.2 * Fields.hill(x, y, 12.0, -10.0, 16.0, 7.0)
			return h,
		"ponds": [{"c": Vector2(7.0, 20.5), "rx": 4.2, "ry": 3.0, "level": 1.05}],
		# The road to the chapel fords the stream.
		"river": {"pts": PackedVector2Array([Vector2(10.5, 19.0), Vector2(14.0, 16.4), Vector2(18.0, 15.2), Vector2(23.0, 14.6), Vector2(28.0, 12.8), Vector2(42.0, 11.0)]),
			"half": 0.6, "shallow": 0.4, "level": 1.05, "bed": 0.35, "ford": {"c": Vector2(17.5, 15.4), "r": 1.2}},
		"roads": [
			{"pts": PackedVector2Array([Vector2(-14.0, 13.0), Vector2(4.0, 13.5), Vector2(10.0, 12.0), Vector2(15.0, 12.6), Vector2(18.5, 16.5), Vector2(19.0, 18.0)]), "w": 0.65},
			{"pts": PackedVector2Array([Vector2(15.0, 12.6), Vector2(19.0, 10.0), Vector2(24.0, 9.2), Vector2(42.0, 8.0)]), "w": 0.6},
		],
		"yards": [{"c": Vector2(13.5, 11.5), "r": 3.0}],
		"woods": func(x: float, y: float, n: float) -> bool:
			if y < 2.4 + 1.3 * sin(x * 0.45 + 0.7) + (n - 0.5) * 1.5 and (x < 9.0 or x > 17.0):
				return true
			if x < 1.8 + 0.9 * sin(y * 0.5) + (n - 0.5) * 1.2 and y < 16.0:
				return true
			if Fields.hill(x, y, 26.0, 21.0, 2.6, 4.0) > 0.42:
				return true
			return Fields.hill(x, y, 14.0, 26.5, 4.0, 1.8) > 0.55,
		"pieces": [
			{"key": "w_house_longhouse", "c": Vector2(12.0, 9.5)},
			{"key": "w_house_cottage_stone", "c": Vector2(16.5, 11.5), "glow": true},
			{"key": "w_house_cottage_stone", "c": Vector2(9.5, 14.5), "glow": true},
			{"key": "w_house_chapel", "c": Vector2(19.5, 19.5), "glow": true},
			{"key": "w_ruin_stones", "c": Vector2(21.5, 5.5)},
		],
		"decor": [
			# The woodpile by the sledge, the fallen log and the stump, clear of
			# the cottage's roof.
			{"key": "harvest_firewood", "at": Vector2(16.4, 7.8), "rules": "", "v": 0},
			{"key": "p_cart", "at": Vector2(10.2, 11.6), "rules": "cart", "snow": true},
			{"key": "w_log", "at": Vector2(17.6, 8.2), "rules": "log"},
			{"key": "w_stump", "at": Vector2(18.4, 7.6), "rules": "stump"},
			{"key": "p_crates", "at": Vector2(14.2, 13.8), "rules": "crates", "snow": true},
			{"key": "chopping_block", "at": Vector2(14.8, 12.0), "rules": "", "v": 0},
			{"key": "barrels", "at": Vector2(13.0, 11.2), "rules": "", "v": 0},
			{"key": "signpost", "at": Vector2(15.8, 14.2), "rules": ""},
			# Each yard its own barrels (barrels_w's paintings, by "v").
			{"key": "barrels", "at": Vector2(17.6, 12.6), "rules": "", "v": 2},
			{"key": "barrels", "at": Vector2(10.9, 15.6), "rules": "", "v": 5},
			{"key": "barrels", "at": Vector2(12.0, 15.0), "rules": "", "v": 4},
			{"key": "barrels", "at": Vector2(14.4, 9.2), "rules": "", "v": 1},
			{"key": "barrels", "at": Vector2(21.2, 18.2), "rules": "", "v": 3},
			{"key": "chopping_block", "at": Vector2(8.0, 15.8), "rules": "", "v": 1},
			# Winter only: a sledge has no summer painting.
			{"key": "sledge", "at": Vector2(16.2, 9.0), "rules": "", "v": 0},
		],
		# Last year's reeds stand dry through the ice at the edges.
		"reeds": 0.3,
		"scatter": {"oak": 0.012, "rock": 0.045, "bush": 0.015},
		"focus": Vector2(14.0, 13.0), "close": Vector2(14.0, 11.0),
		"scouts": [Vector2i(12, 22), Vector2i(20, 14), Vector2i(6, 7)],
	}


## Spring: a ford where the road crosses the river in the shallows, reeds along
## the banks, blossom in the woods, the ruins of an older chapel on its knoll.
static func _willowford() -> Dictionary:
	var river := func(y: float) -> float: return 13.5 + 2.0 * sin(y * 0.2 + 0.4)
	return {
		"id": "willowford", "name": "Willowford", "season": "spring", "seed": 9203, "weather": "petals",
		"blurb": "Spring. The road fords the river in the shallows between reed beds; blossom in the woods and wild flowers in the meadows, the ruins of an older chapel on the knoll and a broken colonnade by the water. Petals on the wind.",
		"height": func(x: float, y: float) -> float:
			var h := 1.6
			h += 2.2 * Fields.hill(x, y, 5.5, 7.0, 4.2, 3.6)
			h += 1.6 * Fields.hill(x, y, 22.5, 5.5, 4.5, 4.0)
			h += 1.0 * Fields.hill(x, y, 22.0, 21.5, 4.0, 3.0)
			h += Fields.bluff(x, y, 4.0, 20.0, 3.4, 3.0, 1.6)
			h += 2.4 * Fields.hill(x, y, -8.0, 8.0, 8.0, 14.0) + 2.0 * Fields.hill(x, y, 14.0, -10.0, 16.0, 7.0)
			return h,
		"river": {"pts": _line(func(t: float) -> Vector2: return Vector2(river.call(t), t), -14.0, 42.0, 1.0),
			"half": 1.4, "shallow": 0.7, "level": 1.2, "bed": 0.6,
			"ford": {"c": Vector2(river.call(16.0), 16.0), "r": 2.2}},
		"roads": [
			{"pts": PackedVector2Array([Vector2(-14.0, 17.5), Vector2(4.0, 16.8), Vector2(10.0, 16.2), Vector2(18.0, 15.6), Vector2(24.0, 13.0), Vector2(42.0, 10.0)]), "w": 0.65},
			{"pts": PackedVector2Array([Vector2(7.0, 16.6), Vector2(6.0, 11.0), Vector2(5.5, 9.0)]), "w": 0.5},
		],
		"woods": func(x: float, y: float, n: float) -> bool:
			if y < 2.0 + 1.2 * sin(x * 0.45 + 0.7) + (n - 0.5) * 1.5:
				return true
			if x > 25.8 + 0.8 * sin(y * 0.5) + (n - 0.5) and y > 9.0:
				return true
			if x < 1.6 + 0.9 * sin(y * 0.5) + (n - 0.5) * 1.2 and y < 15.0:
				return true
			return Fields.hill(x, y, 8.0, 26.0, 3.6, 2.0) > 0.5,
		"pieces": [
			{"key": "ruin_chapel", "c": Vector2(5.0, 6.5)},
			{"key": "ruin_colonnade", "c": Vector2(19.0, 21.5)},
			{"key": "ruin_stones", "c": Vector2(22.0, 5.5)},
		],
		"decor": [
			{"key": "harvest_sheaves", "at": Vector2(21.0, 16.2), "rules": ""},
			{"key": "log", "at": Vector2(9.4, 21.0), "rules": "log"},
			{"key": "stump", "at": Vector2(20.4, 9.6), "rules": "stump"},
			# The ferryman's bank below the ford, and the fisher's above it.
			{"key": "rowboat", "at": Vector2(9.4, 19.6), "rules": ""},
			{"key": "mooring_post", "at": Vector2(10.3, 18.4), "rules": ""},
			{"key": "fish_trap", "at": Vector2(16.4, 11.2), "rules": ""},
			{"key": "reed_bundles", "at": Vector2(16.7, 12.5), "rules": ""},
			{"key": "driftwood", "at": Vector2(12.4, 8.4), "rules": ""},
			{"key": "river_stones", "at": Vector2(14.9, 18.4), "rules": ""},
		],
		"reeds": 0.6,
		"bank": {"marigolds": 0.12, "iris": 0.08, "horsetail": 0.06},
		"scatter": {"oak": 0.02, "rock": 0.03, "bush": 0.04, "blossom": 0.45},
		"focus": Vector2(13.5, 14.5), "close": Vector2(14.0, 16.0),
		"scouts": [Vector2i(8, 21), Vector2i(19, 12), Vector2i(17, 24)],
	}


# --- The generator ---------------------------------------------------------------------

## Field f, laid out in design tiles, in tiles: every place and size on the
## ground times K (but the stooks' spacing), its heights and water levels as
## they are. A piece keeps its
## footprint, its middle moved onto whole tiles; the bridge stays on its road.
static func _scaled(f: Dictionary) -> Dictionary:
	var g := f.duplicate()
	var hf: Callable = f.height
	var wf: Callable = f.woods
	g.height = func(x: float, y: float) -> float: return hf.call(x / K, y / K)
	g.woods = func(x: float, y: float, n: float) -> bool: return wf.call(x / K, y / K, n)
	if f.has("river"):
		var r: Dictionary = f.river.duplicate()
		r.pts = _times_k(r.pts)
		r.half *= K
		r.shallow *= K
		if r.has("ford"):
			r.ford = {"c": r.ford.c * K, "r": r.ford.r * K}
		g.river = r
	g.ponds = f.get("ponds", []).map(func(p): return {"c": p.c * K, "rx": p.rx * K, "ry": p.ry * K, "level": p.level})
	g.roads = f.get("roads", []).map(func(r): return {"pts": _times_k(r.pts), "w": r.w * K})
	for key in ["squares", "yards"]:
		g[key] = f.get(key, []).map(func(q): return {"c": q.c * K, "r": q.r * K})
	g.fields = f.get("fields", []).map(func(q): return {"rect": Rect2(q.rect.position * K, q.rect.size * K)})
	g.open = f.get("open", []).map(func(q): return Rect2(q.position * K, q.size * K))
	# The stooks stand as many tiles apart as before (each makes its tile a
	# haystack), so squads still find their way between them.
	if f.has("stooks"):
		g.stooks = {"rect": Rect2(f.stooks.rect.position * K, f.stooks.rect.size * K), "step": f.stooks.step}
	g.fences = f.get("fences", []).map(func(line): return [line[0] * K, line[1] * K])
	g.decor = f.get("decor", []).map(func(d):
		var e: Dictionary = d.duplicate()
		e.at = d.at * K
		return e)
	g.pieces = f.get("pieces", []).map(func(p):
		var e: Dictionary = p.duplicate()
		var c: Vector2 = p.c * K
		if p.key != "bridge_stone":
			var half := Vector2(PIECE[p.key].fp) * 0.5 - Vector2(0.5, 0.5)
			c = (c - half).round() + half
		e.c = c
		if p.has("foot"):
			e.foot = p.foot * K
		return e)
	g.focus = f.focus * K
	g.close = f.close * K
	g.scouts = f.scouts.map(func(s): return Vector2i((Vector2(s) * K).round()))
	return g


static func _times_k(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p * K)
	return out


static func _line(f: Callable, t0: float, t1: float, step: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var t := t0
	while t <= t1 + 1e-4:
		pts.append(f.call(t))
		t += step
	return pts


## Distance from p to a polyline, and the line's direction there.
static func _near(p: Vector2, pts: PackedVector2Array) -> Array:
	var best := INF
	var dir := Vector2.RIGHT
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
			dir = ab.normalized()
	return [best, dir]


## Smooth noise in [0, 1] along a line: hashed values a unit apart, eased between.
static func _wave(s: float, seed: int) -> float:
	var i := floori(s)
	var k := s - i
	k = k * k * (3.0 - 2.0 * k)
	return lerpf(Rng.hash2(i, 0, seed), Rng.hash2(i + 1, 0, seed), k)


## Tile p's distance from edge e (0 north y = 0, 1 south, 2 west x = 0, 3 east)
## and its place along it: (distance, place).
static func _from_edge(e: int, p: Vector2i) -> Vector2i:
	match e:
		0:
			return Vector2i(p.y, p.x)
		1:
			return Vector2i(H - 1 - p.y, p.x)
		2:
			return Vector2i(p.x, p.y)
	return Vector2i(W - 1 - p.x, p.y)


## The woods along each edge: for each tile along it, how deep they stand (a
## tile is in them when its distance from that edge is less). A field may set
## "border": {"depth", "spread", "deep"}: the least depth, how much it waves
## and how deep the tongues go (design tiles). Each depth stops at the tiles in `keep`, so
## whatever is placed stays open and joined to the field.
static func _border(f: Dictionary, keep: Dictionary) -> Array:
	var b: Dictionary = f.get("border", {})
	var seed: int = f.seed
	var out := []
	for e in 4:
		var row := PackedFloat32Array()
		row.resize(W)
		for s in W:
			var u := s / K
			var d: float = b.get("depth", 1.2) + b.get("spread", 2.6) * _wave(u * 0.26, seed + 101 + e * 7)
			d += b.get("deep", 5.0) * maxf(0.0, _wave(u * 0.42 + 0.5, seed + 131 + e * 7) - 0.6) / 0.4
			row[s] = d * K
		out.append(row)
	for k in keep:
		for e in 4:
			var ds := _from_edge(e, k)
			if ds.y >= 0 and ds.y < W:
				out[e][ds.y] = minf(out[e][ds.y], float(ds.x))
	return out


## A tile of the woods on the camera's side (south or east, in the field or
## outside it) less than NEAR_RIM in from their edge.
static func _near_rim(border: Array, x: int, y: int) -> bool:
	for e in [1, 3]:
		var ds := _from_edge(e, Vector2i(x, y))
		if ds.y >= 0 and ds.y < W and ds.x < border[e][ds.y] and border[e][ds.y] - ds.x <= NEAR_RIM:
			return true
	return false


static func _in_border(border: Array, x: int, y: int) -> bool:
	for e in 4:
		var ds := _from_edge(e, Vector2i(x, y))
		if ds.x < border[e][ds.y]:
			return true
	return false


## The tiles the edge woods stand back from: what the field places (the
## ground cleared round the pieces, a tile round the decor), its fences, yards, fields, squares, roads
## and "open" boxes.
static func _kept(f: Dictionary, pieces: Array) -> Dictionary:
	var keep := {}
	for pc in pieces:
		for c in pc.tiles:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					keep[c + Vector2i(dx, dy)] = true
		# The ground cleared of trees round a piece (_generate) as well.
		for y in range(floori(pc.c.y) - 4, floori(pc.c.y) + 5):
			for x in range(floori(pc.c.x) - 4, floori(pc.c.x) + 5):
				if Vector2(x, y).distance_to(pc.c) < 3.3 * K:
					keep[Vector2i(x, y)] = true
	for d in f.get("decor", []):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				keep[Vector2i(roundi(d.at.x) + dx, roundi(d.at.y) + dy)] = true
	for line in f.get("fences", []):
		var steps := ceili(line[0].distance_to(line[1]) * 2.0)
		for i in steps + 1:
			var q: Vector2 = line[0].lerp(line[1], float(i) / steps)
			keep[Vector2i(roundi(q.x), roundi(q.y))] = true
	var st: Dictionary = f.get("stooks", {})
	var boxes: Array = f.get("open", []).duplicate()
	for fl in f.get("fields", []):
		boxes.append(fl.rect)
	if not st.is_empty():
		boxes.append(st.rect)
	for y in H:
		for x in W:
			var p := Vector2(x, y)
			var k := false
			for r in boxes:
				k = k or Rect2(r).grow(0.5).has_point(p)
			for yd in f.get("yards", []):
				k = k or p.distance_to(yd.c) < yd.r + 0.5
			for sq in f.get("squares", []):
				k = k or p.distance_to(sq.c) < sq.r + 0.5
			for rd in f.get("roads", []):
				k = k or _near(p, rd.pts)[0] < rd.w
			if k:
				keep[Vector2i(x, y)] = true
	return keep


static func _footprint(c: Vector2, fp: Vector2i) -> Array:
	var x0 := roundi(c.x - fp.x * 0.5 + 0.5)
	var y0 := roundi(c.y - fp.y * 0.5 + 0.5)
	var out := []
	for y in range(y0, y0 + fp.y):
		for x in range(x0, x0 + fp.x):
			out.append(Vector2i(x, y))
	return out


static func _generate(f: Dictionary) -> Dictionary:
	var seed: int = f.seed
	var hf: Callable = f.height
	var pieces: Array = []
	var pads: Array = []
	for p in f.get("pieces", []):
		var info: Dictionary = PIECE[p.key]
		var tiles := _footprint(p.c, info.fp)
		var piece := {"key": p.key, "c": p.c, "tiles": tiles, "rules": info.rules,
			"glow": p.get("glow", false), "smoke": p.get("smoke", "")}
		# The card's foot: the near corner of a square base as wide as the painting;
		# the bridge's is the middle of its deck's near end, on the near bank: the
		# deck spans 0.59 of the painting's width at a tile per TILE_PX / 2 px,
		# so the foot is half that from the centre.
		var s: float = float(info.w) / (2.0 * TILE_PX)
		var foot := Vector2(0.0, 0.5897 * info.w / TILE_PX) if p.key == "bridge_stone" else Vector2(s, s)
		piece["foot"] = p.c + foot + Vector2(p.get("foot", Vector2.ZERO))
		pieces.append(piece)
		if p.key != "bridge_stone":
			pads.append({"c": p.c, "fp": Vector2(info.fp), "h": hf.call(p.c.x, p.c.y)})
	var river: Dictionary = f.get("river", {})
	var ponds: Array = f.get("ponds", [])
	var border := _border(f, _kept(f, pieces))
	var tiles: Array = []
	var outer: Array = []
	var flows := {}
	for y in range(-BORDER, H + BORDER):
		for x in range(-BORDER, W + BORDER):
			var inside := x >= 0 and y >= 0 and x < W and y < H
			var p := Vector2(x, y)
			var n := Rng.hash2(x, y, seed)
			var e: float = hf.call(x, y)
			# Level pads under the buildings, eased into the ground round them.
			for pad in pads:
				var q: Vector2 = (p - pad.c).abs() - pad.fp * 0.5
				var out_d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
				var k := 1.0 - smoothstep(0.0, 1.8 * K, out_d)
				e = lerpf(e, pad.h, k)
			var terrain := "grass"
			var prop := ""
			var water_d := INF
			# The river: a channel below its level, its banks raised above it.
			if not river.is_empty():
				var nr := _near(p, river.pts)
				water_d = nr[0]
				var half: float = river.half
				var level: float = river.level
				var bank := maxf(e, level + 0.35)
				var bed: float = level - river.bed
				var ford: Dictionary = river.get("ford", {})
				var in_ford: bool = not ford.is_empty() and p.distance_to(ford.c) < ford.r
				if in_ford:
					bed = level - 0.22
				e = lerpf(bed, bank, smoothstep(half * 0.55, half + river.shallow + 1.3 * K, water_d))
				if water_d < half + river.shallow:
					terrain = "shallows" if (in_ford or water_d > half) else "water"
					flows[Vector2i(x, y)] = nr[1]
			for pd in ponds:
				var d: float = Vector2((x - pd.c.x) / pd.rx, (y - pd.c.y) / pd.ry).length()
				var bed: float = pd.level - 0.45
				if d < 1.6:
					e = lerpf(bed, maxf(e, pd.level + 0.3), smoothstep(0.55, 1.6, d))
				if d < 1.0:
					terrain = "water"
				elif d < 1.3:
					terrain = "shallows"
				elif d < 1.6 and terrain == "grass" and n < 0.5:
					terrain = "mud"
			var wet := terrain in ["water", "shallows"]
			var woods: bool = f.woods.call(x, y, n)
			var out := maxf(maxf(-x, x - W + 1), maxf(-y, y - H + 1))
			# The edge woods, and outside the field their close stand.
			var wild: bool = not wet and (_in_border(border, x, y) if inside else out <= 5.0 * K)
			if not inside:
				woods = woods or n < 0.62 - out / K * 0.02
			if wet:
				woods = false
			if woods:
				terrain = "forest"
				if n < 0.44:
					prop = "tree_pine" if n < 0.29 else "tree_oak"
				elif n < 0.6:
					prop = "bush"
				elif n < 0.635:
					prop = "stump" if n < 0.62 else "log"
			elif not wet:
				var sc: Dictionary = f.get("scatter", {})
				if n > 0.88 and n < 0.93:
					terrain = "brush"
				elif n > 1.0 - sc.get("oak", 0.01):
					prop = "tree_oak"
				elif n < sc.get("bush", 0.0):
					prop = "bush"
				elif n > 0.4 and n < 0.4 + sc.get("rock", 0.0) and e > 1.4:
					prop = "rock_small" if n < 0.4 + sc.get("rock", 0.0) * 0.85 else "rock_large"
			for sq in f.get("squares", []):
				if p.distance_to(sq.c) < sq.r + (n - 0.5) * 0.3 * K:
					terrain = "stone"
					prop = ""
			for yd in f.get("yards", []):
				var d := p.distance_to(yd.c)
				if d < yd.r:
					prop = ""
					if Rng.hash2(x, y, seed + 3) < 0.6 - d / yd.r * 0.4:
						terrain = "dirt"
			for fl in f.get("fields", []):
				if fl.rect.has_point(p):
					terrain = "grass"
					prop = ""
			if wild:
				terrain = "forest"
				var k := Rng.hash2(x, y, seed + 97)
				prop = "tree_pine" if k < 0.62 else ("tree_oak" if k < 0.88 else "bush")
				if _near_rim(border, x, y):
					prop = "bush"
			for r in f.get("roads", []):
				if not wet and _near(p, r.pts)[0] < r.w:
					terrain = "dirt"
					prop = ""
			var t := {"x": x, "y": y, "h": roundi(e), "surface_h": e, "terrain": terrain, "v": floori(n * 10000)}
			if prop != "":
				t["prop"] = prop
			if wild and inside and prop != "":
				t["wild"] = true
			if flows.has(Vector2i(x, y)):
				var fd: Vector2 = flows[Vector2i(x, y)]
				t["flow"] = [fd.x, fd.y]
			if inside:
				tiles.append(t)
			else:
				t["outer"] = true
				outer.append(t)
	var map := {"id": f.id, "name": f.name, "w": W, "h": H, "seed": seed, "border": BORDER, "tiles": tiles}
	var at := func(x: int, y: int) -> Variant:
		if x < 0 or y < 0 or x >= W or y >= H:
			return null
		return tiles[y * W + x]
	# The pieces' footprints: their rules prop, nothing else drawn there.
	for pc in pieces:
		for c in pc.tiles:
			var t = at.call(c.x, c.y)
			if t == null:
				continue
			t.erase("prop")
			t["covered"] = true
			if pc.key == "bridge_stone":
				if t.terrain in ["water", "shallows"]:
					t.terrain = "bridge"
				continue
			if pc.rules != "":
				t["prop"] = pc.rules
			if t.terrain in ["forest", "brush"]:
				t.terrain = "grass"
	# Clear the ground round each piece of trees and boulders, so nothing grows
	# through a roof or blocks a door.
	for pc in pieces:
		for y in range(roundi(pc.c.y) - 4, roundi(pc.c.y) + 4):
			for x in range(roundi(pc.c.x) - 4, roundi(pc.c.x) + 4):
				var t = at.call(x, y)
				if t == null or t.get("covered", false) or Vector2(x, y).distance_to(pc.c) >= 3.2 * K:
					continue
				var prop := String(t.get("prop", ""))
				if prop.begins_with("tree") or prop.begins_with("rock"):
					t.erase("prop")
	var decor: Array = []
	var rng := Rng.new(seed + 61)
	var built := {}
	for pc in pieces:
		for c in pc.tiles:
			built[c] = true
	for d in f.get("decor", []):
		decor.append({"key": d.key, "at": d.at, "snow": d.get("snow", false), "v": d.get("v", -1)})
		# A thing by a house, on the edge of its footprint, leaves the house's prop.
		var t = null if built.has(Vector2i(roundi(d.at.x), roundi(d.at.y))) else at.call(roundi(d.at.x), roundi(d.at.y))
		if t != null:
			t.erase("prop")
			t["covered"] = true
			if d.rules != "":
				t["prop"] = d.rules
	# Stooks in rows across the stubble.
	var st: Dictionary = f.get("stooks", {})
	if not st.is_empty():
		var yy: float = st.rect.position.y
		while yy < st.rect.end.y:
			var xx: float = st.rect.position.x
			while xx < st.rect.end.x:
				if rng.chance(0.8):
					var q := Vector2(xx + rng.frange(-0.25, 0.25), yy + rng.frange(-0.25, 0.25))
					# None where a placed prop (the scarecrow) stands.
					var t = at.call(roundi(q.x), roundi(q.y))
					if t == null or not t.get("covered", false):
						decor.append({"key": "harvest_stook", "at": q, "snow": false})
					if t != null and not t.get("covered", false):
						t["prop"] = "haystack"
						t["covered"] = true
				xx += st.step
			yy += st.step
	# Fences along their lines, a panel a tile, some fallen out.
	for line in f.get("fences", []):
		var a: Vector2 = line[0]
		var b: Vector2 = line[1]
		var along_x := absf(b.x - a.x) > absf(b.y - a.y)
		var steps := roundi(a.distance_to(b))
		for i in steps:
			if not rng.chance(0.8):
				continue
			var q := a.lerp(b, (i + 0.5) / steps)
			var t = at.call(roundi(q.x), roundi(q.y))
			if t == null or t.get("covered", false) or t.terrain in ["water", "shallows", "dirt"]:
				continue
			t.erase("prop")
			t["prop"] = "fence" if along_x else "fence_y"
			t["covered"] = true
			decor.append({"key": "p_fence_x" if along_x else "p_fence_y", "at": q, "snow": false})
	# Reed beds along the banks: clumps in the shallows, half of them with a
	# small tuft beside them, and lone tufts between the clumps; none where a
	# road fords the water.
	var reeds: float = f.get("reeds", 0.0)
	if reeds > 0.0:
		for t in tiles + outer:
			if t.terrain != "shallows" or t.get("covered", false):
				continue
			var on_road := false
			for rd in f.get("roads", []):
				on_road = on_road or _near(Vector2(t.x, t.y), rd.pts)[0] < rd.w + 0.9 * K
			if on_road:
				continue
			var r := Rng.hash2(t.x, t.y, seed + 41)
			var c := Vector2(t.x, t.y) + Vector2(Rng.hash2(t.x, t.y, seed + 43) - 0.5, Rng.hash2(t.x, t.y, seed + 47) - 0.5) * 0.6
			if r < reeds:
				decor.append({"key": "reeds", "at": c, "snow": false})
				if Rng.hash2(t.x, t.y, seed + 49) < 0.5:
					decor.append({"key": "reeds_small", "at": c + Vector2.from_angle(Rng.hash2(t.x, t.y, seed + 51) * TAU) * 0.42, "snow": false})
			elif r < reeds * 1.4:
				decor.append({"key": "reeds_small", "at": c, "snow": false})
	# The season's flowers and horsetail on the grass along the shallows'
	# edge: {key: share of those tiles}.
	var bank: Dictionary = f.get("bank", {})
	if not bank.is_empty():
		for t in tiles:
			if not t.terrain in ["grass", "mud"] or t.has("prop") or t.get("covered", false):
				continue
			var by_water := false
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb = at.call(t.x + o.x, t.y + o.y)
				by_water = by_water or (nb != null and nb.terrain == "shallows")
			if not by_water:
				continue
			var r := Rng.hash2(t.x, t.y, seed + 67)
			for key in bank:
				if r < bank[key]:
					var j := Vector2(Rng.hash2(t.x, t.y, seed + 71) - 0.5, Rng.hash2(t.x, t.y, seed + 73) - 0.5) * 0.5
					decor.append({"key": key, "at": Vector2(t.x, t.y) + j, "snow": false})
					break
				r -= bank[key]
	# Blossom: a share of the oaks in flower.
	var blossom: float = f.get("scatter", {}).get("blossom", 0.0)
	for t in tiles + outer:
		if t.get("prop", "") == "tree_oak" and Rng.hash2(t.x, t.y, seed + 53) < blossom:
			t["art"] = "tree_oak_spring"
	return {"id": f.id, "name": f.name, "blurb": f.blurb, "season": f.season, "frozen": f.get("frozen", false),
		"weather": f.get("weather", ""), "seed": seed, "map": map, "outer": outer, "pieces": pieces,
		"decor": decor, "water_level": river.get("level", ponds[0].level if not ponds.is_empty() else -99.0),
		"has_river": not river.is_empty(), "focus": f.focus, "close": f.close, "scouts": f.scouts}
