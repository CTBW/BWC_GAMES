## Late-bound access to the modules the UI and the App store call into: the meta
## and campaign rules, the battle rules, the sprite registry, the world views and
## the HUDs. They are built by other agents in parallel, so the UI loads them by
## path at first use (`ResourceLoader.exists` first) instead of `preload`: a
## missing or broken module leaves the UI loading cleanly and only the features
## that need it unavailable.
##
##   const Deps = preload("res://scripts/ui/deps.gd")
##   Deps.game().level(g, "barracks")      # static funcs of scripts/meta/game.gd
##   if Deps.has("battle_view"): ...
extends RefCounted

const PATHS := {
	"game": "res://scripts/meta/game.gd",
	"soldier": "res://scripts/meta/soldier.gd",
	"expedition": "res://scripts/campaign/expedition.gd",
	"autoplay": "res://scripts/campaign/autoplay.gd",
	"setup": "res://scripts/rules/setup.gd",
	"battle": "res://scripts/rules/battle.gd",
	"ai": "res://scripts/rules/ai.gd",
	"squad": "res://scripts/rules/squad.gd",
	"rng": "res://scripts/core/rng.gd",
	"assets": "res://scripts/render/assets.gd",
	"base_view_scene": "res://scenes/base/base_view.tscn",
	"base_view": "res://scripts/render/base_view.gd",
	"campaign_view_scene": "res://scenes/campaign/campaign_view.tscn",
	"campaign_view": "res://scripts/render/campaign_view.gd",
	"battle_view_scene": "res://scenes/battle/battle_view.tscn",
	"battle_view": "res://scripts/render/battle_view.gd",
	"battle_hud": "res://scripts/ui/battle_hud.gd",
	"campaign_hud": "res://scripts/ui/campaign_hud.gd",
}

static var _cache: Dictionary = {}


static func has(key: String) -> bool:
	return mod(key) != null


## The loaded resource (GDScript or PackedScene) for a key, or null when missing.
static func mod(key: String) -> Variant:
	if _cache.has(key):
		return _cache[key]
	var p: String = PATHS.get(key, key)
	var r: Variant = null
	if ResourceLoader.exists(p):
		r = load(p)
		if r is GDScript and not (r as GDScript).can_instantiate():
			r = null
	_cache[key] = r
	return r


## Forget cached lookups (tests, or after another agent's module appeared).
static func reset() -> void:
	_cache.clear()


static func game() -> Variant:
	return mod("game")


static func soldier() -> Variant:
	return mod("soldier")


static func expedition() -> Variant:
	return mod("expedition")


static func autoplay() -> Variant:
	return mod("autoplay")


static func setup() -> Variant:
	return mod("setup")


static func battle() -> Variant:
	return mod("battle")


static func ai() -> Variant:
	return mod("ai")


static func squad() -> Variant:
	return mod("squad")


static func rng() -> Variant:
	return mod("rng")


static func assets() -> Variant:
	return mod("assets")


## Instantiates a view or HUD: the scene when there is one, else the script.
static func instance(key: String) -> Node:
	var sc: Variant = mod(key + "_scene")
	if sc is PackedScene:
		return (sc as PackedScene).instantiate()
	var s: Variant = mod(key)
	if s is GDScript:
		return (s as GDScript).new()
	return null
