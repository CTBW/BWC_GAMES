## The 3D battlefields as the rules' battle maps (Godot only). A field of the
## battlefield prototype (prototypes/battlefields3d/scripts/bf_fields.gd) is a
## map in the rules' format already ({x, y, h, terrain, prop} tiles, DB.PROPS
## ids). This makes every thing drawn on it solid, so no squad moves onto one:
## the farm things with no rules prop take one (`solid`), and the map is
## `solidWoods` (a tree or a bush is one thing on its tile here, not a stand of
## woodland). It adds where each side draws up: the open ground (passable, no
## prop, no water) in each side's box. Setup.build_battle takes it as opts.map.
## Pure data: no nodes.
extends RefCounted

const Fields = preload("res://prototypes/battlefields3d/scripts/bf_fields.gd")
const MapGen = preload("res://scripts/rules/mapgen.gd")

## Each field's deployment boxes (tiles): the company's and the enemy's. On
## Ashby farm the company draws up on the open ground south of the farm, the
## enemy north of the burnt barn by the pond, the ruined farm between them.
const DEPLOY := {
	"ashby": {"player": Rect2i(9, 18, 8, 4), "enemy": Rect2i(16, 4, 5, 5)},
}
## The rules prop of each thing the fields draw without one: what it is to a
## squad (it blocks a move; the hay and crates give cover, the posts a little).
const THINGS := {"harvest_bale": "haystack", "harvest_sheaves": "haystack", "harvest_stook": "haystack",
	"harvest_pumpkins": "crates", "harvest_firewood": "crates", "sacks": "crates", "wheelbarrow": "crates",
	"scarecrow": "fence", "signpost": "fence"}


## The rules' map of field `id`: its tiles with playerDeploy and enemyDeploy.
static func battle_map(id: String) -> Dictionary:
	var data: Dictionary = Fields.make(id)
	solid(data)
	var m: Dictionary = data.map
	m.solidWoods = true
	m.playerDeploy = _zone(m, DEPLOY[id].player)
	m.enemyDeploy = _zone(m, DEPLOY[id].enemy)
	return m


## Every thing placed on field `data` (Fields.make) blocks a move: a tile a
## thing stands on (bf_fields.gd marks it covered) without a rules prop takes
## THINGS' (crates for one not named there). Reeds and flowers are not things.
static func solid(data: Dictionary) -> void:
	var m: Dictionary = data.map
	for d in data.decor:
		var x := roundi(d.at.x)
		var y := roundi(d.at.y)
		if x < 0 or y < 0 or x >= m.w or y >= m.h:
			continue
		var t: Dictionary = m.tiles[y * m.w + x]
		if t.get("covered", false) and not t.has("prop") and t.terrain != "bridge":
			t["prop"] = THINGS.get(d.key, "crates")


static func _zone(m: Dictionary, r: Rect2i) -> Array:
	var out := []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var t: Dictionary = m.tiles[y * m.w + x]
			if MapGen._clear_ground(m, x, y) and MapGen._no_prop(t) and not (t.terrain in ["water", "shallows"]):
				out.append({"x": x, "y": y})
	return out
