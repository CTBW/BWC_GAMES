## Every rigged 3D character ready for the sandbox, in the panel's order. A
## profile names the model and its clips' sidecar and says what the sidecar
## does not: which clips are the attacks, how far each reaches (metres, centre
## to centre, where the striker stands) or what it looses, the stances, and
## the parts drawn without an outline or from both sides. Roles a sidecar
## names itself (`roles`, the spearman's, crossbowman's, goblins' and orc's exports)
## fill the rest. A model whose file is missing is left out of the roster
## (the rigged models carry Mixamo-derived clips and are not in Git; their
## sidecars are, except the wolf scout's).
extends RefCounted

const ART := "res://prototypes/sandbox3d/art3d/"
const FOOTMAN := "res://prototypes/footman_anim/art3d/"
const WOLF := "res://prototypes/wolf_scout_anim/art3d/"
## One goblin export per loadout (each weapon has its own grip), from
## references/characters/blender/goblin_rabble/tools/export_godot.py.
const GOBLIN := "res://prototypes/goblin_rabble_anim/art3d/"
## references/characters/blender/goblin_archer/tools/export_godot.py.
const ARCHER := "res://prototypes/goblin_archer_anim/art3d/"
## references/characters/blender/goblin_spear/tools/export_godot.py.
const GSPEAR := "res://prototypes/goblin_spear_anim/art3d/"
## references/characters/blender/orc_brute/tools/export_godot.py.
const ORC := "res://prototypes/orc_brute_anim/art3d/"

const UNITS := [
	{"id": "footman", "title": "Footman", "faction": "player", "controller": "footman",
		"model": FOOTMAN + "footman.glb", "meta": FOOTMAN + "footman.json",
		"blurb": "Line holder. His own controller: the start and stop, turns on the planted foot, the block, the lane step and the shield charge.",
		"attacks": [{"clip": "attack", "label": "Slash"}, {"clip": "attack_stab", "label": "Stab"}, {"clip": "attack_thrust", "label": "Lunge"}]},
	{"id": "spearman", "title": "Spearman", "faction": "player",
		"model": ART + "spearman.glb", "meta": ART + "spearman.json", "reach": 2.7,
		"attack_defaults": {"reach": 2.7, "label": "Spear thrust"},
		"blurb": "Anti-charge: the long spear keeps a foe at two metres."},
	{"id": "crossbowman", "title": "Crossbowman", "faction": "player",
		"model": ART + "crossbowman.glb", "meta": ART + "crossbowman.json", "reach": 12.0,
		"attack_defaults": {"missile": "bolt", "reach": 12.0, "then": "reload"},
		"labels": {"shoot": "Snap shot", "shoot_2": "Shot", "steady_shot": "Steady shot"},
		"blurb": "Ranged: walks into range and a clear line, shoots a bolt, then reloads."},
	{"id": "mage", "title": "Battle Mage", "faction": "player",
		"model": ART + "mage.glb", "meta": ART + "mage.json",
		"idle": "Idle", "walk": "Walk", "hit": "Hit", "death": "Death", "reach": 9.0,
		"blurb": "Spellcaster: four quick casts and their full, slower versions.",
		"attacks": [
			{"clip": "FireballCast", "label": "Fireball", "missile": "fireball", "reach": 10.0, "hits": ["release"]},
			{"clip": "ChainLightningCast", "label": "Chain lightning", "missile": "lightning", "reach": 9.0, "hits": ["release"]},
			{"clip": "FrostNovaCast", "label": "Frost nova", "missile": "frost", "reach": 2.6, "hits": ["release"]},
			{"clip": "EarthFistCast", "label": "Earth fist", "missile": "earth", "reach": 8.0, "hits": ["release"]},
			{"clip": "Fireball", "label": "Fireball, full", "missile": "fireball", "reach": 10.0, "hits": ["release"]},
			{"clip": "ChainLightning", "label": "Lightning, full", "missile": "lightning", "reach": 9.0, "hits": ["release"]},
			{"clip": "FrostNova", "label": "Frost nova, full", "missile": "frost", "reach": 2.6, "hits": ["release"]},
			{"clip": "EarthFist", "label": "Earth fist, full", "missile": "earth", "reach": 8.0, "hits": ["release"]}]},
	{"id": "wolf_scout", "title": "Wolf Scout", "faction": "enemy",
		"model": WOLF + "wolf_scout.fbx", "meta": WOLF + "wolf_scout.json", "reach": 1.3,
		"blurb": "Raider: twin daggers, and a crouched stealth stance.",
		"attacks": [{"clip": "attack", "label": "Twin daggers", "reach": 1.3, "hits": ["strike_left", "strike_right"]}],
		"stances": ["stealth"], "two_sided": ["Cloak"], "no_outline": ["Cloak"]},
	{"id": "wolf_scout_2", "title": "Wolf Scout 2", "faction": "enemy",
		"model": WOLF + "wolf_scout_2.glb", "meta": WOLF + "wolf_scout_2.json", "reach": 1.3,
		"walk": "sneak",
		"blurb": "Revised shoulders and cape, with the new sneak walk. Shares Wolf Scout's idle, twin-dagger attack and death motion.",
		"attacks": [{"clip": "attack", "label": "Twin daggers", "reach": 1.3, "hits": ["strike_left", "strike_right"]}],
		"two_sided": ["Cloak", "Hood"], "no_outline": ["Cloak", "Hood"]},
	# The Sovereign Kiss is made from a Mixamo clip: it stays in local/ and is
	# offered where it is on disk (local_clips.gd). Its fog heart is fx3d.gd's "kiss".
	{"id": "succubus", "title": "Succubus", "faction": "enemy",
		"model": FOOTMAN + "succubus.fbx", "meta": FOOTMAN + "succubus.json", "reach": 2.3,
		"local_clips": "local/succubus_3d/godot/succubus_kiss",
		"blurb": "Whip lash with its slash effects, an idle flourish now and then, and the Sovereign Kiss's fog heart where its clip is on disk.",
		"attacks": [{"clip": "attack", "label": "Whip lash", "reach": 2.3, "hits": ["strikes"]},
			{"clip": "sovereign_kiss", "label": "Sovereign Kiss", "missile": "kiss", "reach": 6.0, "hits": ["kiss_breath"]}],
		"fx": "whip", "full_detail": ["Lash"], "thin_outline": ["Lash"]},
	{"id": "goblin_rabble_knife", "title": "Goblin Rabble · knife", "faction": "enemy",
		"model": GOBLIN + "goblin_rabble_knife.glb", "meta": GOBLIN + "goblin_rabble_knife.json", "reach": 1.0,
		"attack_defaults": {"reach": 1.0, "label": "Knife chop"},
		"blurb": "Horde fodder: a notched knife and a barrel-bottom shield strapped to his forearm."},
	{"id": "goblin_rabble_hatchet", "title": "Goblin Rabble · hatchet", "faction": "enemy",
		"model": GOBLIN + "goblin_rabble_hatchet.glb", "meta": GOBLIN + "goblin_rabble_hatchet.json", "reach": 1.0,
		"attack_defaults": {"reach": 1.0, "label": "Hatchet chop"},
		"blurb": "Horde fodder: a cord-lashed hatchet and a shield of scrap planks."},
	{"id": "goblin_rabble_cleaver", "title": "Goblin Rabble · cleaver", "faction": "enemy",
		"model": GOBLIN + "goblin_rabble_cleaver.glb", "meta": GOBLIN + "goblin_rabble_cleaver.json", "reach": 1.0,
		"attack_defaults": {"reach": 1.0, "label": "Cleaver chop"},
		"blurb": "Horde fodder: a pitted cleaver and a barrel-bottom shield."},
	{"id": "goblin_archer", "title": "Goblin Archer", "faction": "enemy",
		"model": ARCHER + "goblin_archer.glb", "meta": ARCHER + "goblin_archer.json", "reach": 10.0,
		"attack_defaults": {"missile": "arrow", "reach": 10.0, "label": "Shot", "hits": ["shot"]},
		"blurb": "Skirmisher: a horn bow and a quiver of red-fletched arrows. Walks into range and a clear line, draws an arrow over his shoulder and looses. Struck, he raises the bow to block."},
	{"id": "goblin_spearman", "title": "Goblin Spearman", "faction": "enemy",
		"model": GSPEAR + "goblin_spearman.glb", "meta": GSPEAR + "goblin_spearman.json", "reach": 2.0,
		"attack_defaults": {"reach": 2.0, "label": "Spear thrust"},
		"blurb": "Line goblin: a red-ragged spear held level in both hands. Draws back and drives a two-handed thrust from two metres; dying, he drops the spear."},
	{"id": "orc_brute", "title": "Orc Brute", "faction": "enemy",
		"model": ORC + "orc_brute.glb", "meta": ORC + "orc_brute.json", "reach": 1.6,
		"attack_defaults": {"reach": 1.6, "label": "Club swing"},
		"blurb": "Shock infantry: a spiked war club in his right fist, his left hand empty. Draws the club back low and swings it up through the foe; dying, he drops it."},
	{"id": "orc_brute_dual", "title": "Orc Brute · two clubs", "faction": "enemy",
		"model": ORC + "orc_brute_dual.glb", "meta": ORC + "orc_brute_dual.json", "reach": 1.6,
		"attack_defaults": {"reach": 1.6, "label": "Club swing"},
		"blurb": "Shock infantry with a spiked war club in each fist. Swings the right one up through the foe, the left held ready; dying, he drops both."},
]

## The squads, each of `size` men of the profiles in `units` (several: the
## men share them out in turn, shuffled; a profile named twice serves twice as
## many), each man with one of `faces` and one of `kit` (each dealt out
## shuffled; the variants the sidecar's `faces` and `kit` name), standing in the drill of
## squad3d.gd's DRILLS[`drill`] (its id if not given), centred on `home`
## (tiles) and facing their side's way (the player's east, the enemy's west).
## The players' squads stand west of the yard, two lines deep, and the
## enemy's east of it, a wolf pack on either flank.
const SQUADS := [
	{"id": "footman", "title": "Footmen", "units": ["footman"], "size": 6, "home": Vector2(13.0, 16.0),
		"blurb": "Six footmen in two ranks of three, each in his own time. The front rank strikes while the rear rank stands ready behind it; spread to the line, the rear rank steps up beside it, so all six strike."},
	{"id": "spearman", "title": "Spearmen", "units": ["spearman"], "size": 6, "home": Vector2(13.0, 19.0),
		"blurb": "Six spears in two chequered ranks: both ranks thrust, the rear rank's spears past the front rank's shoulders."},
	{"id": "crossbowman", "title": "Crossbowmen", "units": ["crossbowman"], "size": 6, "home": Vector2(10.4, 17.6),
		"blurb": "Six crossbows in two chequered ranks. They halt in range with a clear line and loose in volleys: each bolt timed to leave with the others', then each man reloads in his own time. Or at will."},
	{"id": "mage", "title": "Battle Mages", "units": ["mage"], "size": 3, "home": Vector2(10.6, 14.4),
		"blurb": "Three mages in a wedge, each casting his own spell when he is ready: fireball, chain lightning, earth fist, or a frost nova at a foe close by. Or in volleys."},
	{"id": "wolf_scout", "title": "Wolf Scouts", "units": ["wolf_scout"], "size": 3, "home": Vector2(18.6, 13.0),
		"blurb": "A pack of three in a wedge. They close round the foe, each to a flank, and strike with their twin daggers."},
	{"id": "wolf_scout_2", "title": "Wolf Scouts 2", "units": ["wolf_scout_2"], "size": 3, "home": Vector2(20.4, 21.6), "drill": "wolf_scout",
		"blurb": "The revised Wolf Scouts in a pack of three, on their sneak walk: they close round the foe, each to a flank."},
	{"id": "succubus", "title": "Succubi", "units": ["succubus"], "size": 3, "home": Vector2(21.0, 14.6),
		"blurb": "Three succubi in a wide wedge: they spread round the foe at the whip's length and lash it."},
	{"id": "goblin_rabble", "title": "Goblin Rabble", "units": ["goblin_rabble_knife", "goblin_rabble_hatchet", "goblin_rabble_cleaver"],
		"size": 10, "home": Vector2(18.4, 19.4),
		"blurb": "Ten goblins in two ragged ranks of five, knives, hatchets and cleavers mixed. They straggle on the march, and in a fight the rear rank swarms round the foe beside the front."},
	{"id": "goblin_archer", "title": "Goblin Archers", "units": ["goblin_archer"], "size": 8, "home": Vector2(20.8, 17.8),
		"blurb": "Eight archers in two chequered ranks of four. They halt in range with a clear line and loose in volleys, the arrows on their arc together. Or at will."},
	{"id": "goblin_spearman", "title": "Goblin Spearmen", "units": ["goblin_spearman"], "size": 8, "home": Vector2(18.4, 16.2),
		"blurb": "Eight spears in two chequered ranks of four: both ranks thrust, the rear rank's spears past the front rank."},
	{"id": "orc_brute", "title": "Orc Brutes", "units": ["orc_brute", "orc_brute", "orc_brute_dual"], "size": 6, "home": Vector2(22.6, 19.6),
		"faces": [["jaw"], ["beard"], ["scar"], ["beard", "scar"], ["jaw", "scar"], []],
		"kit": [["no_left_pauldron"], ["no_right_pauldron"], [], [], [], []],
		"blurb": "Six brutes in two loose ranks of three, each in his own time and with his own face: an iron jaw, a braided beard, a clawed eye, or bare. Two carry a club in each fist, and two have lost a pauldron. The front rank swings while the rear rank stands ready; spread to the line, the rear rank shoulders in beside it."},
]


## The profiles whose model and sidecar are on disk.
static func available() -> Array:
	var out := []
	for p in UNITS:
		if _missing_files(p).is_empty():
			out.append(p.duplicate(true))
	return out


## The units left out, each as {"title", "files"}: the files not on disk.
static func missing() -> Array:
	var out := []
	for p in UNITS:
		var files := _missing_files(p)
		if not files.is_empty():
			out.append({"title": p.title, "files": files})
	return out


## The squads whose men are all on disk, each with its `profiles` (copies) and `faction`.
static func squads() -> Array:
	var have := {}
	for p in available():
		have[p.id] = p
	var out := []
	for s in SQUADS:
		if s.units.all(func(u): return have.has(u)):
			var q: Dictionary = s.duplicate(true)
			q["profiles"] = s.units.map(func(u): return have[u])
			q["faction"] = q.profiles[0].faction
			out.append(q)
	return out


static func _missing_files(p: Dictionary) -> Array:
	var out := []
	if not ResourceLoader.exists(p.model):
		out.append(p.model)
	if not FileAccess.file_exists(p.meta):
		out.append(p.meta)
	return out
