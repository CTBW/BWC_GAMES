## Every rigged 3D character ready for the sandbox, in the panel's order. A
## profile names the model and its clips' sidecar and says what the sidecar
## does not: which clips are the attacks, how far each reaches (metres, centre
## to centre, where the striker stands) or what it looses, the stances, and
## the parts drawn without an outline or from both sides. Roles a sidecar
## names itself (`roles`, the spearman's, crossbowman's and goblins' exports)
## fill the rest. A model whose file is missing is left out of the roster
## (the footman's GLB, the wolf scout's export and the goblins' GLBs are not
## in Git).
extends RefCounted

const ART := "res://prototypes/sandbox3d/art3d/"
const FOOTMAN := "res://prototypes/footman_anim/art3d/"
const WOLF := "res://prototypes/wolf_scout_anim/art3d/"
## One goblin export per loadout (each weapon has its own grip), from
## references/characters/blender/goblin_rabble/tools/export_godot.py.
const GOBLIN := "res://prototypes/goblin_rabble_anim/art3d/"

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
	{"id": "succubus", "title": "Succubus", "faction": "enemy",
		"model": FOOTMAN + "succubus.fbx", "meta": FOOTMAN + "succubus.json", "reach": 2.3,
		"blurb": "Whip lash with its slash effects, and an idle flourish now and then.",
		"attacks": [{"clip": "attack", "label": "Whip lash", "reach": 2.3, "hits": ["strikes"]}],
		"fx": "whip", "full_detail": ["Lash"], "thin_outline": ["Lash"]},
	{"id": "goblin_rabble_knife", "title": "Goblin Rabble · knife", "faction": "enemy",
		"model": GOBLIN + "goblin_rabble_knife.glb", "meta": GOBLIN + "goblin_rabble_knife.json", "reach": 1.0,
		"home_tile": Vector2i(20, 15), "attack_defaults": {"reach": 1.0, "label": "Knife chop"},
		"blurb": "Horde fodder: a notched knife and a barrel-bottom shield strapped to his forearm."},
	{"id": "goblin_rabble_hatchet", "title": "Goblin Rabble · hatchet", "faction": "enemy",
		"model": GOBLIN + "goblin_rabble_hatchet.glb", "meta": GOBLIN + "goblin_rabble_hatchet.json", "reach": 1.0,
		"home_tile": Vector2i(21, 16), "attack_defaults": {"reach": 1.0, "label": "Hatchet chop"},
		"blurb": "Horde fodder: a cord-lashed hatchet and a shield of scrap planks."},
	{"id": "goblin_rabble_cleaver", "title": "Goblin Rabble · cleaver", "faction": "enemy",
		"model": GOBLIN + "goblin_rabble_cleaver.glb", "meta": GOBLIN + "goblin_rabble_cleaver.json", "reach": 1.0,
		"home_tile": Vector2i(20, 17), "attack_defaults": {"reach": 1.0, "label": "Cleaver chop"},
		"blurb": "Horde fodder: a pitted cleaver and a barrel-bottom shield."},
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


static func _missing_files(p: Dictionary) -> Array:
	var out := []
	if not ResourceLoader.exists(p.model):
		out.append(p.model)
	if not FileAccess.file_exists(p.meta):
		out.append(p.meta)
	return out
