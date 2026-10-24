## Port of common.tsx `Icon` and `TypeIcon`: the original's inline SVG icons,
## exported to assets/icons/<name>.svg by tools/ui_export_icons.ts.
##
##   const Icon = preload("res://scripts/ui/widgets/icon.gd")
##   Icon.make(name: String, size := 18, title := "", tint := Color(0,0,0,0)) -> TextureRect
##       A square icon, vertically centred in rows. `title` becomes the hover tooltip.
##       Icons drawn in currentColor (rotl, rotr, sound, mute, grid, danger) are
##       white SVGs tinted with `tint`, or with the theme colour Icon/tint (ink on
##       parchment, light on dark panels) when no tint is given.
##   Icon.tex(name) -> Texture2D          the texture (missing.svg for unknown names)
##   Icon.type_icon_name(type_id) -> String   engine / staff / shield / spear / crossbow / sword
##   Icon.type_icon(type_id, size := 16) -> TextureRect   port of TypeIcon (title = unit name)
##   Icon.NAMES                           every exported icon name
extends TextureRect

const DB = preload("res://scripts/data/db.gd")

const NAMES := ["silver", "timber", "iron", "trophies", "rations", "bandages", "bolts", "torches", "tools",
	"hp", "morale", "fatigue", "xp", "cp", "slot", "weight", "skull", "injury", "sword", "shield", "spear",
	"crossbow", "march", "eye", "bash", "spearwall", "thrust", "bolt", "horn", "charge", "rotl", "rotr",
	"sound", "mute", "grid", "danger",
	# Spells and war machines.
	"lightning", "frost", "heal", "circle", "fire", "blood", "gut", "stone", "staff", "engine",
	# Squad skills (Godot only).
	"shield_charge", "defend", "square", "growl", "hound_charge", "lick_wounds", "aimed_shot", "howl"]
const TINTED := ["rotl", "rotr", "sound", "mute", "grid", "danger"]

static var _cache: Dictionary = {}

var icon_name := ""
var explicit_tint := Color(0, 0, 0, 0)


static func tex(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var p := "res://assets/icons/%s.svg" % name
	if not NAMES.has(name) or not ResourceLoader.exists(p):
		p = "res://assets/icons/missing.svg"
	var t: Texture2D = load(p)
	_cache[name] = t
	return t


static func make(name: String, size := 18, title := "", tint := Color(0, 0, 0, 0)) -> TextureRect:
	var r: TextureRect = load("res://scripts/ui/widgets/icon.gd").new()
	r.icon_name = name
	r.explicit_tint = tint
	r.texture = tex(name)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if title != "":
		r.tooltip_text = title
		r.mouse_filter = Control.MOUSE_FILTER_PASS
	else:
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tint.a > 0.0:
		r.self_modulate = tint
	return r


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and TINTED.has(icon_name) and explicit_tint.a <= 0.0:
		self_modulate = get_theme_color("tint", "Icon")


## Changes the icon (e.g. sound ↔ mute).
func set_icon(name: String) -> void:
	icon_name = name
	texture = tex(name)
	if TINTED.has(name) and explicit_tint.a <= 0.0 and is_inside_tree():
		self_modulate = get_theme_color("tint", "Icon")


static func type_icon_name(type_id: String) -> String:
	var def: Dictionary = DB.UNIT_TYPES.get(type_id, {})
	if def.has("crew"):
		return "engine"
	if (def.get("tags", []) as Array).has("caster"):
		return "staff"
	if type_id == "footman" or type_id == "collie_guard":
		return "shield"
	if type_id == "spearman":
		return "spear"
	if type_id == "crossbowman" or type_id.contains("archer"):
		return "crossbow"
	return "sword"


static func type_icon(type_id: String, size := 16) -> TextureRect:
	var t: Dictionary = DB.UNIT_TYPES.get(type_id, {})
	return make(type_icon_name(type_id), size, t.get("name", ""))
