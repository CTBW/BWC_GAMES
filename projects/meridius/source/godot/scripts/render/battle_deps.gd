## The battle view's bindings to the modules around it: rules (battle.gd,
## ai.gd), the world renderer (terrain.gd, fx.gd, atmosphere.gd) and the
## sprite registry. Kept in one place so battle_view.gd / battle_draw.gd read
## like the original's battleScene.ts.
extends RefCounted

const Terrain = preload("res://scripts/render/terrain.gd")
const Fx = preload("res://scripts/render/fx.gd")
const Atmosphere = preload("res://scripts/render/atmosphere.gd")

const AI_PATH := "res://scripts/rules/ai.gd"
const BATTLE_PATH := "res://scripts/rules/battle.gd"

## Figures whose mirrored poses lead with the shield (figures.ts hasShieldPoses:
## styleFor(type, 0).shield is 'kite' or 'round').
const SHIELD_TYPES := {"footman": true, "collie_guard": true, "orc_warrior": true}
## battle.ts INWARD: grid facing of the step onto the field from beyond each edge.
const INWARD := {"n": 1, "w": 0, "e": 2, "s": 3}

static var _scripts := {}


static func _script(path: String) -> Variant:
	if not _scripts.has(path):
		_scripts[path] = load(path) if ResourceLoader.exists(path) else null
	return _scripts[path]


## Assets.warm_async (texture loads on worker threads), or warm when missing.
static func warm(keys: Array) -> void:
	var A = load("res://scripts/render/assets.gd")
	if A.has_method("warm_async"):
		A.warm_async(keys)
	elif A.has_method("warm"):
		A.warm(keys)


## Every SubViewport the view paints into filters sprites like the root (the
## project's linear-with-mipmaps; only the root viewport takes the setting).
static func prepare_viewport(vp: SubViewport) -> void:
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


static func has_shield_poses(type: String) -> bool:
	return SHIELD_TYPES.has(type)


static func inward(edge: String) -> int:
	var B = _script(BATTLE_PATH)
	if B != null and "INWARD" in B:
		return B.INWARD[edge]
	return INWARD[edge]


## Battle.objective (a TS getter).
static func objective(b) -> Dictionary:
	if b.has_method("get_objective"):
		return b.get_objective()
	var o = b.get("objective")
	if o is Callable:
		return o.call()
	if o is Dictionary:
		return o
	if b.has_method("objective"):
		return b.call("objective")
	return {}


## Battle.waves (a TS getter).
static func waves(b) -> Array:
	var w = b.get("waves")
	if w is Array:
		return w
	if b.has_method("waves"):
		return b.call("waves")
	return b.setup.get("waves", [])


## Ai.run_enemy_ai as a Callable(b).
static func enemy_ai() -> Callable:
	var A = _script(AI_PATH)
	return Callable(A, "run_enemy_ai")


static func player_auto() -> Callable:
	var A = _script(AI_PATH)
	return Callable(A, "run_player_auto")


# ---------------------------------------------------------------- ground

static func build_ground(view, m: Dictionary) -> Node2D:
	var tiles: Array = m.tiles.duplicate()
	# The open approaches beyond the edges are painted as ground too.
	for g in m.get("outerGround", []):
		tiles.append({"x": g.x, "y": g.y, "h": 0, "terrain": g.terrain})
	return Terrain.build_terrain({
		"w": m.w,
		"h": m.h,
		"border": m.border,
		"tiles": tiles,
		"seed": m.seed,
		"palette": "camp" if m.get("biome") == "camp" else "summer",
	})


static func attach_ground(view, world: Node2D, layer: Node2D) -> void:
	world.add_child(layer)


# ---------------------------------------------------------------- fx / atmosphere

static func make_fx() -> Variant:
	return Fx.new()


static func make_atmosphere(seed: int) -> Variant:
	return Atmosphere.new(seed)


static func attach_clouds(view, world: Node2D, atmo) -> void:
	if not atmo.has_method("make_clouds_node"):
		return
	var m: Dictionary = view.b.map
	var n: Node2D = atmo.make_clouds_node(view.Iso.iso_x(m.w / 2.0, m.h / 2.0), view.Iso.iso_y(m.w / 2.0, m.h / 2.0))
	world.add_child(n)
	view._layers["Clouds"] = n


static func attach_grade(view, atmo) -> void:
	if not atmo.has_method("make_grade_node"):
		return
	var n: Node2D = atmo.make_grade_node()
	view.add_child(n)
	view._layers["Grade"] = n


static func refresh_atmosphere(view, atmo) -> void:
	if atmo.has_method("redraw"):
		atmo.redraw(Vector2(view._w, view._h), view.time)


## Fx.busy: missiles still in the air.
static func fx_busy(fx) -> bool:
	return fx.busy
