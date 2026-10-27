## Who the men of a squad are, as data (unit_look.gd dresses the model). The
## squad shares its colours and kit; each man has his own face, hair, beard,
## build, helmet, clothes and dirt:
##  - The livery (the squad's colour and shield) is the same for every man,
##    but each man's dye is a little faded or fresh (`dye`: hue, saturation and
##    value offsets), as cloth from one dye lot washed and worn differently.
##  - What a man owns himself varies freely: hair, skin, beard, leather,
##    linen, and in a militia or line squad his trousers.
##  - Shuffle bags, not dice: hair, skin, beards and helmets are drawn from a
##    shuffled bag per squad, so men differ while the bag lasts (with dice, two
##    blonds turn up in about half of all squads of six).
##  - The leader (man 0) wears the squad's plume.
## Colours are display (sRGB) values. The same seed gives the same men.
extends RefCounted

## The company's colours (blue and cream, the player's squads in the concept
## art) and liveries for other companies or foes. `mark` is the squad's
## shield: [division, field2, charge]. Divisions (shield_variant.gdshader):
## 0 plain, 1 per pale, 2 per fess, 3 quarterly, 4 per bend, 5 chevron,
## 6 pale, 7 fess.
const LIVERIES := [
	{"name": "Company blue", "cloth": Color(0.234, 0.276, 0.418), "second": Color(0.85, 0.80, 0.68),
		"charge": Color(0.92, 0.90, 0.84), "division": 0},
	{"name": "Crimson", "cloth": Color(0.56, 0.13, 0.12), "second": Color(0.86, 0.70, 0.32),
		"charge": Color(0.93, 0.78, 0.36), "division": 1},
	{"name": "Forest", "cloth": Color(0.20, 0.36, 0.21), "second": Color(0.88, 0.84, 0.72),
		"charge": Color(0.94, 0.92, 0.86), "division": 5},
	{"name": "Black and gold", "cloth": Color(0.14, 0.14, 0.16), "second": Color(0.80, 0.62, 0.24),
		"charge": Color(0.92, 0.76, 0.32), "division": 3},
	{"name": "Saffron", "cloth": Color(0.80, 0.55, 0.15), "second": Color(0.36, 0.16, 0.11),
		"charge": Color(0.24, 0.13, 0.10), "division": 4},
	{"name": "Purple", "cloth": Color(0.36, 0.19, 0.42), "second": Color(0.90, 0.86, 0.76),
		"charge": Color(0.94, 0.90, 0.80), "division": 2},
	{"name": "White and red", "cloth": Color(0.84, 0.82, 0.76), "second": Color(0.62, 0.13, 0.11),
		"charge": Color(0.64, 0.13, 0.11), "division": 6},
]

## Squad marks for squads that share the company's colours: the shield's
## division and second tincture, and the leader's plume. Six squads, six marks.
const MARKS := [
	{"division": 0, "field2": Color(0.85, 0.80, 0.68), "plume": Color(0.92, 0.90, 0.84)},
	{"division": 1, "field2": Color(0.85, 0.80, 0.68), "plume": Color(0.70, 0.16, 0.13)},
	{"division": 3, "field2": Color(0.80, 0.62, 0.24), "plume": Color(0.84, 0.66, 0.26)},
	{"division": 5, "field2": Color(0.85, 0.80, 0.68), "plume": Color(0.20, 0.36, 0.21)},
	{"division": 2, "field2": Color(0.62, 0.13, 0.11), "plume": Color(0.62, 0.13, 0.11)},
	{"division": 4, "field2": Color(0.14, 0.14, 0.16), "plume": Color(0.14, 0.14, 0.16)},
]

## How alike a squad's men are. `dye`: spread of the livery's dye; `trousers`
## and `helmets`: the bags (`livery` = trousers in the squad's colour);
## `linen_second`: the tunic in the livery's second colour; `grime`: the
## squad's dirt and wear, each man +- 0.25 of it.
const KITS := {
	"militia": {"dye": 1.6, "grime": 0.55,
		"trousers": ["brown", "grey", "russet", "livery", "green", "undyed"],
		"helmets": ["cap", "none", "skullcap", "cap", "kettle", "none"]},
	"line": {"dye": 1.0, "grime": 0.35,
		"trousers": ["livery", "livery", "livery", "brown", "livery", "grey"],
		"helmets": ["kettle", "nasal", "kettle", "skullcap", "nasal", "none"]},
	"guard": {"dye": 0.45, "grime": 0.12, "linen_second": true,
		"trousers": ["livery", "livery", "livery", "livery", "livery", "livery"],
		"helmets": ["nasal", "nasal", "nasal", "nasal", "nasal", "nasal"]},
}

const HAIR := {
	"black": Color(0.11, 0.09, 0.08), "dark brown": Color(0.22, 0.14, 0.09),
	"brown": Color(0.344, 0.238, 0.18), "chestnut": Color(0.45, 0.25, 0.13),
	"auburn": Color(0.48, 0.25, 0.14), "dark blond": Color(0.58, 0.45, 0.27),
	"blond": Color(0.78, 0.65, 0.40), "grey": Color(0.56, 0.54, 0.51),
	"white": Color(0.80, 0.78, 0.74),
}
## Weighted by repetition in the bag.
const HAIR_BAG := ["black", "dark brown", "dark brown", "brown", "brown", "chestnut",
	"auburn", "dark blond", "blond", "grey", "white"]
const SKIN := {
	"fair": Color(0.93, 0.77, 0.65), "light": Color(0.88, 0.68, 0.53),
	"medium": Color(0.80, 0.59, 0.43), "olive": Color(0.71, 0.53, 0.37),
	"tan": Color(0.62, 0.43, 0.29), "brown": Color(0.47, 0.31, 0.21),
	"dark": Color(0.33, 0.22, 0.15),
}
const SKIN_BAG := ["fair", "light", "light", "medium", "medium", "olive", "tan", "brown", "dark"]
## Beard strength over the lower face: none, stubble, full.
const BEARDS := {"clean": 0.0, "stubble": 0.45, "full": 0.95}
const BEARD_BAG := ["clean", "clean", "stubble", "stubble", "full", "full"]
const LEATHER := [Color(0.22, 0.15, 0.10), Color(0.344, 0.238, 0.18), Color(0.50, 0.35, 0.22),
	Color(0.15, 0.13, 0.12), Color(0.40, 0.22, 0.14)]
const LINEN := [Color(0.80, 0.713, 0.618), Color(0.87, 0.84, 0.77), Color(0.66, 0.63, 0.58),
	Color(0.73, 0.63, 0.49), Color(0.60, 0.50, 0.38)]
const TROUSERS := {
	"brown": Color(0.33, 0.25, 0.18), "grey": Color(0.37, 0.37, 0.38),
	"russet": Color(0.42, 0.22, 0.15), "green": Color(0.23, 0.29, 0.20),
	"undyed": Color(0.58, 0.53, 0.45), "black": Color(0.14, 0.14, 0.16),
}
## Helmet finishes: [tint, metal]. A painted helmet takes the livery.
const FINISH := {
	"steel": [Color(0.56, 0.58, 0.61), 1.0], "iron": [Color(0.38, 0.39, 0.41), 1.0],
	"black": [Color(0.17, 0.17, 0.19), 0.8], "painted": [Color(), 0.35],
}
const FINISH_BAG := ["steel", "steel", "iron", "iron", "black", "painted"]
## Padded caps: linen or felt.
const CAPS := [Color(0.70, 0.64, 0.53), Color(0.42, 0.31, 0.21), Color(0.36, 0.34, 0.32)]


## The men of a squad of `n` (up to six; a bag refills past that).
## `livery`: an entry of LIVERIES; `kit`: a key of KITS; `mark`: an entry of
## MARKS, or {} for the livery's own shield.
static func squad(n: int, seed_: int, livery: Dictionary, kit: String = "line", mark: Dictionary = {}) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var k: Dictionary = KITS.get(kit, KITS.line)
	var bags := {}
	var men := []
	var cloth: Color = livery.cloth
	var second: Color = livery.second
	var division: int = mark.get("division", livery.division)
	var field2: Color = mark.get("field2", second)
	var plume: Color = mark.get("plume", second)
	for i in n:
		var m := {"leader": i == 0}
		m.livery = cloth
		m.dye = Vector3(rng.randfn(0.0, 0.008), rng.randfn(0.0, 0.08), rng.randfn(0.0, 0.07)) * float(k.dye)
		var tr: String = _draw(bags, "trousers", k.trousers, rng)
		m.trousers = cloth.darkened(0.12) if tr == "livery" else TROUSERS[tr]
		m.trousers_livery = tr == "livery"
		m.linen = second if k.get("linen_second", false) else LINEN[rng.randi() % LINEN.size()]
		m.leather = LEATHER[rng.randi() % LEATHER.size()]
		m.hair_name = _draw(bags, "hair", HAIR_BAG, rng)
		m.hair = HAIR[m.hair_name]
		m.skin_name = _draw(bags, "skin", SKIN_BAG, rng)
		m.skin = SKIN[m.skin_name]
		m.beard_name = _draw(bags, "beard", BEARD_BAG, rng)
		m.beard = BEARDS[m.beard_name]
		m.grime = clampf(float(k.grime) + rng.randf_range(-0.25, 0.25), 0.0, 1.0)
		m.helmet = _draw(bags, "helmet", k.helmets, rng)
		var fin: String = "steel" if kit == "guard" else _draw(bags, "finish", FINISH_BAG, rng)
		m.finish = fin
		m.helmet_tint = cloth if fin == "painted" else FINISH[fin][0]
		m.helmet_metal = FINISH[fin][1]
		if m.helmet == "cap":
			m.helmet_tint = CAPS[rng.randi() % CAPS.size()]
			m.helmet_metal = 0.0
		m.plume = plume if i == 0 else Color(0, 0, 0, 0)
		# A leader is never bareheaded or in a cap: his plume needs a helmet.
		if i == 0 and m.helmet in ["none", "cap"]:
			m.helmet = "kettle" if kit != "guard" else "nasal"
			m.helmet_tint = FINISH.steel[0]
			m.helmet_metal = 1.0
		m.head_scale = clampf(1.0 + rng.randfn(0.0, 0.03), 0.93, 1.07)
		m.chest_scale = clampf(1.0 + rng.randfn(0.0, 0.025), 0.95, 1.05) + (0.02 if i == 0 else 0.0)
		m.glance = rng.randf_range(0.3, 1.0)
		m.field = cloth
		m.field2 = field2
		m.charge = livery.charge
		m.division = division
		m.wear = clampf(m.grime + rng.randf_range(-0.2, 0.2), 0.0, 1.0)
		men.append(m)
	return men


## One draw from the named shuffle bag, refilled and reshuffled when empty.
static func _draw(bags: Dictionary, key: String, items: Array, rng: RandomNumberGenerator) -> String:
	var bag: Array = bags.get(key, [])
	if bag.is_empty():
		bag = items.duplicate()
		for i in range(bag.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = bag[i]
			bag[i] = bag[j]
			bag[j] = t
	var out: String = bag.pop_back()
	bags[key] = bag
	return out


## A line about a man for the panel.
static func describe(m: Dictionary) -> String:
	var helm := {"none": "bareheaded", "cap": "padded cap", "skullcap": "skullcap", "kettle": "kettle hat", "nasal": "nasal helm"}
	var h: String = helm.get(m.helmet, m.helmet)
	if m.helmet in ["skullcap", "kettle", "nasal"]:
		h = "%s %s" % [m.finish, h]
	var beard: String = {"clean": "", "stubble": ", stubble", "full": ", full beard"}.get(m.beard_name, "")
	return "%s%s · %s hair%s · %s skin" % ["Leader · " if m.leader else "", h, m.hair_name, beard, m.skin_name]
