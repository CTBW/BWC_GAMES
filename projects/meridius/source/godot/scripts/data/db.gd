## Game data tables, loaded from res://data/*.json.
##
## The JSON is exported once from the original TypeScript tables
## (tools/export_data.ts) and is now the editable source of content. Keys keep
## their original camelCase names. Integral numbers load as ints, fractions as
## floats (JS.normalize). Use through `const DB = preload("res://scripts/data/db.gd")`.
extends RefCounted

const JS = preload("res://scripts/core/js.gd")

# abilities.json
static var ABILITIES: Dictionary
# buildings.json
static var BUILDINGS: Array
# campaigns.json
static var NODE_INFO: Dictionary
static var CAMPAIGNS: Array
# encounters.json
static var ENCOUNTERS: Array
# events.json
static var EVENTS: Array
static var NIGHT_RAID: Dictionary
# items.json
static var EQUIPMENT: Dictionary
static var SUPPLIES: Dictionary
static var SUPPLY_ORDER: Array
static var INJURIES: Dictionary
# maps.json
static var BATTLE_MAPS: Dictionary
# names.json
static var FIRST_NAMES: Array
static var SURNAMES: Array
static var GOBLIN_NAMES: Array
static var ORC_NAMES: Array
static var WARLORD_NAMES: Array
static var WARCHIEF_NAMES: Array
static var MILITIA_LEADERS: Array
static var EPITHETS: Array
# terrain.json
static var TERRAIN: Dictionary
static var PROPS: Dictionary
# units.json
static var DEFAULT_SQUAD_SIZE: int
static var UNIT_TYPES: Dictionary
static var PLAYER_TYPES: Array
static var RANKS: Array
static var XP_LEVELS: Array
static var MAX_LEVEL: int
static var PROMOTION_LEVEL: int
static var LEVEL_COMMAND_SURCHARGE: Array


static func _static_init() -> void:
	ABILITIES = _load("abilities").ABILITIES
	BUILDINGS = _load("buildings").BUILDINGS
	var c := _load("campaigns")
	NODE_INFO = c.NODE_INFO
	CAMPAIGNS = c.CAMPAIGNS
	ENCOUNTERS = _load("encounters").ENCOUNTERS
	var e := _load("events")
	EVENTS = e.EVENTS
	NIGHT_RAID = e.NIGHT_RAID
	var it := _load("items")
	EQUIPMENT = it.EQUIPMENT
	SUPPLIES = it.SUPPLIES
	SUPPLY_ORDER = it.SUPPLY_ORDER
	INJURIES = it.INJURIES
	BATTLE_MAPS = _load("maps").BATTLE_MAPS
	var n := _load("names")
	FIRST_NAMES = n.FIRST_NAMES
	SURNAMES = n.SURNAMES
	GOBLIN_NAMES = n.GOBLIN_NAMES
	ORC_NAMES = n.ORC_NAMES
	WARLORD_NAMES = n.WARLORD_NAMES
	WARCHIEF_NAMES = n.WARCHIEF_NAMES
	MILITIA_LEADERS = n.MILITIA_LEADERS
	EPITHETS = n.EPITHETS
	var t := _load("terrain")
	TERRAIN = t.TERRAIN
	PROPS = t.PROPS
	var u := _load("units")
	DEFAULT_SQUAD_SIZE = u.DEFAULT_SQUAD_SIZE
	UNIT_TYPES = u.UNIT_TYPES
	PLAYER_TYPES = u.PLAYER_TYPES
	RANKS = u.RANKS
	XP_LEVELS = u.XP_LEVELS
	MAX_LEVEL = u.MAX_LEVEL
	PROMOTION_LEVEL = u.PROMOTION_LEVEL
	LEVEL_COMMAND_SURCHARGE = u.LEVEL_COMMAND_SURCHARGE


static func _load(name: String) -> Dictionary:
	var path := "res://data/%s.json" % name
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DB: cannot open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		push_error("DB: %s is not a JSON object" % path)
		return {}
	return JS.normalize(parsed)


## Soldiers in one squad of this type (src/data/units.ts squadSize).
static func squad_size(type_id: String) -> int:
	var t: Dictionary = UNIT_TYPES.get(type_id, {})
	return t.get("squad", DEFAULT_SQUAD_SIZE)


static func building_by_id(id: String) -> Dictionary:
	for b in BUILDINGS:
		if b.id == id:
			return b
	push_error("Unknown building " + id)
	return {}


static func campaign_by_id(id: String) -> Dictionary:
	for c in CAMPAIGNS:
		if c.id == id:
			return c
	push_error("Unknown campaign " + id)
	return {}


static func encounter_by_id(id: String) -> Dictionary:
	for e in ENCOUNTERS:
		if e.id == id:
			return e
	push_error("Unknown encounter " + id)
	return {}
