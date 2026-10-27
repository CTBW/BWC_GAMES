## The 3D battle (Godot only): a battle of the turn-based rules
## (scripts/rules/battle.gd: the company's turn, then the enemy's) on one of
## the 3D battlefields, played back with the 3D sandbox's figures and squads
## (prototypes/sandbox3d: unit3d.gd, squad3d.gd, roster.gd; the footmen
## dressed by prototypes/squad_looks when it is on disk) on the battlefield
## prototype's ground (battle3d_field.gd), seen through the game's camera
## (orthographic, 30 degrees down, a soldier 49 px tall at zoom 1). The rules'
## map is the field's own (scripts/rules/battlefields.gd): a squad stands on a
## tile, its men in ranks round the tile's centre facing the squad's facing.
##
##   var view = preload("res://scripts/render/battle3d.gd").new()
##   view.setup(battle)          # a Battle on a field's map (Setup.build_battle, opts.map)
##   host.add_child(view)        # App's world host
##   view.ended.connect(...)     # "victory" | "defeat" | "retreat", once the end has played
##
## The view has the 2D battle view's interface (scripts/render/battle_view.gd),
## so the battle HUD (scripts/ui/battle_hud.gd) and the automation drive it the
## same way: members b, ui, views (uid -> View3D: x, y, facing, hp, alive,
## morale, status, stance, routing, visible, reserve, statuses; `sq` its squad
## on the field), speed, fog (sees, tile_state); signals ui_changed, ended;
## select, set_ability, cycle_facing, redo, end_unit, select_next, begin,
## end_turn, retreat, selected_unit, run_rules, rules_running, pump, busy,
## notify, staged, next_wave_info, squad_visible, unit_visible, key_action,
## pointer_move, pointer_down(screen point, button 0 left | 2 right).
##
## Rules run ahead of the animation (the enemy's turn on a worker thread, as
## in the 2D view); the view plays back their events (Battle.drain) and never
## changes an outcome: a march walks the rules' path; a melee attack is the
## attacking squad's fight (squad3d.gd attack) in which as many of the
## target's men fall as the rules say (the rest when it ends); a volley is
## each shooter's shot, a spell its casters' with its hits where it lands; then
## both squads re-form on their tiles. Squads never answer blows by themselves
## (`fight_back` false): a strike back is the rules' own attack event.
## `ui.busy`: nothing can be ordered now (the enemy's turn, a banner, the
## rules running); the company's own marches and fights do not hold up its
## next order. busy(): anything still playing.
##
## Shadows: the paintings' own, for now (the owner's choice). With
## `sun_shadows` (set it before the view enters the tree) the sun casts them
## all instead, the men's, the trees', the houses' and the farm things' (the
## field's own: no painted shadows), on the ground and over the men.
##
## Input (events the HUD did not take): left click selects a squad of the
## company, marches it to a blue tile (pointing at a tile's edge picks the way
## it faces there; Q / E another), sets it on a foe (melee from the side
## nearest the cursor), deploys it during the deployment; right click cancels
## the ability, else the selection; a right or middle drag, or WASD, pans; the
## wheel zooms; the 2D view's battle keys (facing_prev/next, select_next,
## end_unit, end_turn, redo_move, cancel, toggle_grid, show_danger, ability_1..4).
extends Node3D

signal ui_changed
signal ended(result: String)

const JS = preload("res://scripts/core/js.gd")
const Prefs = preload("res://scripts/core/prefs.gd")
const DB = preload("res://scripts/data/db.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const Squad = preload("res://scripts/rules/squad.gd")
const Ai = preload("res://scripts/rules/ai.gd")
const Field = preload("res://scripts/render/battle3d_field.gd")
const Fog = preload("res://prototypes/battlefields3d/scripts/bf_fog.gd")
const Weather = preload("res://prototypes/battlefields3d/scripts/bf_weather.gd")
const Unit3D = preload("res://prototypes/sandbox3d/scripts/unit3d.gd")
const Fx3D = preload("res://prototypes/sandbox3d/scripts/fx3d.gd")
const Squad3D = preload("res://prototypes/sandbox3d/scripts/squad3d.gd")
const Roster = preload("res://prototypes/sandbox3d/scripts/roster.gd")

## Game scale (the sandbox's soldiers and levels): a soldier SOLDIER_PX tall at
## zoom 1, a tile TILE_PX wide (the field's: its fewer, bigger tiles) and a
## level LEVEL_PX high; the footman's height sets the metres.
const SOLDIER_PX := 49.0
const TILE_PX := Field.TILE_PX
const LEVEL_PX := 26.0
const ELEVATION := 30.0
const FOOTMAN_META := "res://prototypes/footman_anim/art3d/footman.json"
const OUTLINE_PX := 2.0
const ZOOM_MIN := 0.5
const ZOOM_MAX := 3.0
const START_ZOOM := 0.8
## The camera's distance from the point it looks at (metres).
const CAM_DIST := 80.0
const FADE_COLUMN := 64.0
## The field when the battle's map names none.
const FIELD_ID := "ashby"
## The squad looks lab dresses the footmen when it is on disk (as in the sandbox).
const LOOKS := "res://prototypes/squad_looks/scripts/"
const SQUAD_LIVERY := 0
const SQUAD_KIT := "line"
## A man's half width: he stands this far clear of a tile he cannot stand on.
const BODY_R := 0.3
## The ground under a fallen body (the sandbox's _lie).
const LIE_R := 0.9
const LIE_IN := 0.8

## Each rules unit type's squad of the sandbox (Roster.SQUADS). A type without
## one, or whose men are not on disk, takes the field as the footmen (the
## company's) or the goblin rabble.
const SQUAD_OF := {"footman": "footman", "spearman": "spearman", "crossbowman": "crossbowman",
	"battle_mage": "mage", "goblin_rabble": "goblin_rabble", "goblin_spear": "goblin_spearman",
	"goblin_archer": "goblin_archer", "orc_brute": "orc_brute", "wolf_rider": "wolf_scout_3"}
## Each spell's look (its `fx`): the casters' clip and their missile.
const SPELL_CAST := {"fire": "FireballCast", "lightning": "ChainLightningCast", "frost": "FrostNovaCast",
	"stone": "EarthFistCast", "rock": "EarthFistCast"}
## Seconds (battle time) a fight, a volley or a spell may take before it is settled at once.
const FIGHT_LIMIT := 6.0
## An attack's blows (the front rank's, the rear's) at most: a turn's attack is a short exchange.
const ATTACK_BLOWS := Vector2i(2, 1)
## Seconds an attack goes on after the last of its deaths has fallen.
const ATTACK_LINGER := 1.0
## A marching squad's men step this much quicker than their own walk.
const MARCH_PACE := 1.5
## Turn banners, waves and the end: nothing plays alongside them.
const BARRIERS := {"turn": true, "end": true, "warn": true, "wave": true, "horn": true, "overrun": true, "broken": true, "relief": true}
## Squads' events played side by side at most.
const MAX_ANIMS := 14
## Morale changes told by banners, not over the squads.
const QUIET_MORALE := {"Steadied": true, "Surrounded": true, "The battle is turning": true, "Another wave": true, "The warchief's host": true, "The war horn": true, "The horn is silenced": true, "Relief is near": true, "The warchief is slain": true}
const STANCE_NAME := {"shieldwall": "Shield Wall", "spearwall": "Spearwall", "overwatch": "Overwatch", "defend": "Defend", "square": "Square"}
const STATUS_NAME := {"chilled": "Chilled", "bloodlust": "Bloodlust!", "bleeding": "Bleeding", "cowed": "Cowed"}
const EDGE_NAME := {"n": "northern", "e": "eastern", "s": "southern", "w": "western"}
const MORALE_RANK := ["confident", "steady", "shaken", "wavering", "broken"]
## The floating words' colours.
const C_HIT := Color("#ffffff")
const C_FLANK := Color("#ffb347")
const C_MISS := Color("#c8c8c8")
const C_HEAL := Color("#9ff08a")
const C_BAD := Color("#ff8a7a")
const C_NEWS := Color("#e9d58f")
const C_MORALE := Color("#c9a7ff")
## The ground overlay (battle_draw.gd's): where the selected squad can go (or
## deploy), each tile a square with a light edge, the way it will face.
const REACH_COLOR := Color(0.41, 0.65, 1.0, 0.26)
const REACH_EDGE := Color(0.78, 0.88, 1.0, 0.6)
const DEPLOY_COLOR := Color(0.31, 0.55, 1.0, 0.18)
const DEPLOY_EDGE := Color(0.55, 0.75, 1.0, 0.4)
const DANGER_COLOR := Color(0.86, 0.24, 0.16, 0.2)
## A tile square's inset from the tile's edge, and its edge's width (tiles).
const TILE_INSET := 0.06
const TILE_EDGE := 0.035
const ARROW_COLOR := Color(1.0, 0.86, 0.45, 0.95)
const _ACTIONS := ["facing_prev", "facing_next", "select_next", "end_unit", "end_turn", "redo_move", "cancel", "toggle_grid", "show_danger", "ability_1", "ability_2", "ability_3", "ability_4"]


## What the screen shows of a rules squad (follows playback, not the rules,
## which run ahead): its tile and facing, its numbers, and its squad of figures.
class View3D extends RefCounted:
	var uid := ""
	var faction := "player"
	var x := 0
	var y := 0
	var facing := 0
	var hp = 0
	var alive := 0
	var morale = 0
	var status := "active"
	var stance = null
	var routing := false
	var visible := true
	var reserve := false
	var statuses: Array = []
	## Its figures on the field (squad3d.gd), null when none could be made.
	var sq = null


class Anim extends RefCounted:
	var t := 0.0
	var dur := 0.0
	var step: Callable
	var done: Callable
	var start: Callable
	var started := false
	## Holds the animation past `dur` until it returns true (a march, a
	## fight), `limit` seconds at most.
	var until: Callable
	var limit := FIGHT_LIMIT
	## Squads this animation shows; later events about them wait for it.
	var uids: Array = []
	var barrier := false
	var delay := 0.0


## What the company sees, as the HUD asks it (battle_fog.gd's sees and tile_state).
class FogView extends RefCounted:
	var view
	var visible_units := {}

	func enabled() -> bool:
		return view.b != null and view.b.fog_enabled()

	func sees(uid: String) -> bool:
		return not enabled() or visible_units.has(uid)

	## 2 seen now, 1 explored, 0 never seen.
	func tile_state(x: int, y: int) -> int:
		return view._tile_state(x, y)


var b
var ui: Dictionary = {"selected": null, "hover": {"tile": null, "unit": null, "preview": null, "spell": null, "path": null, "zoc": null, "dest": null, "facing": null, "facings": null, "turn": null},
	"ability": null, "busy": false, "banner": null, "log": [], "showGrid": false, "danger": false, "version": 0, "turn": 0, "side": "player"}
var views: Dictionary = {}
var speed: float = float(Prefs.prefs().get("battleSpeed", 1.0))
## Enemy turns and run_rules on a WorkerThreadPool task (false: inline, e.g. tests).
var threaded_rules := true
var fog := FogView.new()
var title := ""
var last_rules_ms := 0.0
## Squads answer blows by themselves (squad3d.gd reads it): never here.
var fight_back := false

var ppu := 33.0
var tile_m := 2.72
var level_m := 0.9
var zoom := START_ZOOM
var sun_shadows := false
var _zoom_goal := START_ZOOM
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var field
var shroud
var weather
var fx
var world: Node3D
var focus := Vector3.ZERO
## Every man on the field (squad3d.gd reads `units` and `dummies`).
var units: Array = []
var dummies: Array = []
var squads: Array = []

var _uid_of := {}
var _queue: Array = []
var _anim: Anim = null
var _anims: Array = []
var _cause: Array = []
var _strikes := {}
var _spells := {}
var _timers: Array = []
var _texts: Array = []
var _in_flight := 0
var _revealed := {}
var _ended := false
var _horde_broken := false
var _pointer := Vector2(-1, -1)
var _reach_cache = null
var _states_cache = null
var _danger_cache = null
var _facing_pick = null
var _ucache := {}
var _ucache_b = null
var _live_b = null
var _task_id := -1
var _task_t0 := 0
var _task_fn: Callable
var _applied_speed := -1.0
var _rng := RandomNumberGenerator.new()
var _sfx_node: Node = null
var _held := {}
var _focus_hold := 0.0
var _focus_goal := Vector3.INF
var _dragging := false
var _drag_moved := 0.0
var _rings: MeshInstance3D
var _ring_mesh: ImmediateMesh
var _ring_pts := {}
var _overlay: MeshInstance3D
var _overlay_mesh: ImmediateMesh
var _overlay_key := ""
var _mark_key := ""
var _tree_cards: Array = []
var _fade_t := 0.0
var _grounded := {}
var _grounded_y := {}
var _lying := {}
var _viewport_was := {}


# ---------------------------------------------------------------- construction

func setup(battle) -> void:
	b = battle
	fog.view = self
	title = String(b.setup.get("title", b.map.get("name", "")))
	_rng.seed = int(b.map.get("seed", 1)) * 7919 + 17
	views.clear()
	for u in b.units:
		var v := View3D.new()
		v.uid = u.uid
		v.faction = u.faction
		v.x = u.x
		v.y = u.y
		v.facing = u.facing
		v.hp = u.hp
		v.alive = u.alive
		v.morale = u.morale
		v.status = u.status
		v.stance = u.get("stance")
		v.routing = u.status == "routing"
		v.visible = u.status != "reserve"
		v.reserve = u.status == "reserve"
		for s in u.get("statuses", []):
			v.statuses.append(s.id)
		views[u.uid] = v
	if b.phase == "deploy":
		_banner("Deploy your company", "Click a squad, then a blue tile, to change the formation", "neutral")
		var first = _first(b.active("player"))
		if first != null:
			ui.selected = first.uid
	if field != null:
		_spawn_all()


func _ready() -> void:
	fog.view = self
	process_priority = 10   # after the units have moved: their feet go on the ground
	# Smooth edges as in the sandbox: the 3D drawn at twice the size (the
	# Compatibility renderer drops the ink line under MSAA). Put back on exit.
	var vp := get_viewport()
	_viewport_was = {"msaa": vp.msaa_3d, "mode": vp.scaling_3d_mode, "scale": vp.scaling_3d_scale}
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 2.0
	var fm_meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(FOOTMAN_META))
	var h: float = fm_meta.get("height_m", 1.7) if fm_meta is Dictionary else 1.7
	ppu = SOLDIER_PX / (h * cos(deg_to_rad(ELEVATION)))
	tile_m = TILE_PX / (sqrt(2.0) * ppu)
	level_m = LEVEL_PX / (ppu * cos(deg_to_rad(ELEVATION)))
	_build_world()
	field = Field.new()
	field.name = "Field"
	field.sun_shadows = sun_shadows
	add_child(field)
	var id: String = String(b.map.get("id", FIELD_ID)) if b != null else FIELD_ID
	field.build(id, tile_m, level_m, ELEVATION, ppu)
	if title == "":
		title = String(field.data.name)
	shroud = Fog.new(field.map)
	var fog_on: bool = b != null and b.fog_enabled()
	field.set_shared("fog_tex", shroud.tex)
	field.set_shared("sun_opacity", sun.shadow_opacity)
	field.set_shared("fog_on", fog_on)
	weather = Weather.new()
	weather.name = "Weather"
	add_child(weather)
	weather.build(field.data.weather, field.smoke, Vector2(Field.W, Field.H), tile_m)
	weather.set_shared("fog_tex", shroud.tex)
	weather.set_shared("fog_on", fog_on)
	weather.set_falling(true)
	world = Node3D.new()
	world.name = "Units"
	add_child(world)
	fx = Fx3D.new()
	fx.name = "Fx"
	fx.ground = field.ground_y
	fx.friends = func(who: Node3D) -> Array: return units.filter(func(n): return n != who and n.faction == who.faction and _alive(n))
	add_child(fx)
	_build_meshes()
	_apply_light()
	if b != null:
		_spawn_all()
	_apply_look()
	_place_camera()


func _exit_tree() -> void:
	# A rules task must finish before the battle it works on goes away.
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		if _live_b != null:
			b = _live_b
			_live_b = null
	if _viewport_was.is_empty():
		return
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = _viewport_was.msaa
		vp.scaling_3d_mode = _viewport_was.mode
		vp.scaling_3d_scale = _viewport_was.scale


func _build_world() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	# From the screen's upper left, 50 degrees up (the sandbox's).
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-90), 0)
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.55
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 60.0
	if sun_shadows:
		# Four maps along the view's depth (_place_camera fits the camera's
		# depth to the ground in view): a single map blurs a tree's shadow
		# to a smudge.
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_split_1 = 0.25
		sun.directional_shadow_split_2 = 0.5
		sun.directional_shadow_split_3 = 0.75
		sun.directional_shadow_fade_start = 0.95
	add_child(sun)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 0.1
	cam.far = 400.0
	add_child(cam)
	cam.make_current()


## The rings under the men and the tiles drawn on the ground (unshaded, vertex colours).
func _build_meshes() -> void:
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.vertex_color_use_as_albedo = true
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_mesh = ImmediateMesh.new()
	_rings = MeshInstance3D.new()
	_rings.name = "Rings"
	_rings.mesh = _ring_mesh
	_rings.material_override = rm
	_rings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rings)
	_overlay_mesh = ImmediateMesh.new()
	_overlay = MeshInstance3D.new()
	_overlay.name = "Tiles"
	_overlay.mesh = _overlay_mesh
	_overlay.material_override = rm
	_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_overlay)


## The day's light over the field's season (the sandbox's DAY).
func _apply_light() -> void:
	sun.light_energy = 0.5
	sun.light_color = Color(1.0, 0.96, 0.88)
	env.ambient_light_energy = 0.6
	env.ambient_light_color = Color(0.86, 0.9, 1.0)
	var bg := Color(0.07, 0.09, 0.07)
	env.background_color = bg
	field.set_shared("night", Vector3.ONE)
	field.mat.set_shader_parameter("deep", Vector3(bg.r, bg.g, bg.b))
	weather.set_shared("night", Vector3.ONE)


# ---------------------------------------------------------------- the squads' figures

## Every rules squad's figures on its tile, then the camera over the company.
func _spawn_all() -> void:
	if not squads.is_empty():
		return
	var defs := {}
	for s in Roster.squads():
		defs[s.id] = s
	for u in b.units:
		var id := squad_for(u, defs)
		if id != "":
			_spawn(views[u.uid], u, defs[id])
	var deploy: Array = b.map.get("playerDeploy", [])
	var foes: Array = b.map.get("enemyDeploy", [])
	var mine := _centre(deploy) if not deploy.is_empty() else Vector2(b.map.w * 0.5, b.map.h * 0.75)
	var theirs := _centre(foes) if not foes.is_empty() else Vector2(b.map.w * 0.5, b.map.h * 0.25)
	focus = field.on_ground(mine.lerp(theirs, 0.2)) + Vector3(0, 0.85, 0)
	_update_fog(1.0)


## The sandbox squad (an id of `defs`, the squads on disk) a rules unit takes
## the field as: its type's, else the footmen or the goblin rabble; "" when
## none of them is on disk (a fresh checkout has no models) and it has no figures.
static func squad_for(u: Dictionary, defs: Dictionary) -> String:
	var id: String = SQUAD_OF.get(u.typeId, "")
	if not defs.has(id):
		id = "footman" if u.faction == "player" else "goblin_rabble"
	return id if defs.has(id) else ""


static func _centre(tiles: Array) -> Vector2:
	var c := Vector2.ZERO
	for t in tiles:
		c += Vector2(t.x, t.y)
	return c / tiles.size()


## One rules squad's men (the sandbox's _spawn_squad): each at his own pace,
## face and kit, the footmen dressed by the squad looks lab when it is on disk.
func _spawn(v: View3D, u: Dictionary, s: Dictionary) -> void:
	var n: int = int(u.alive)
	if n <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng.randi()
	var d: Dictionary = Squad3D.drill_for(String(s.get("drill", s.id)))
	var sq = Squad3D.new()
	var dressed: Script = null
	var looks := []
	if s.id == "footman" and ResourceLoader.exists(LOOKS + "dressed_footman.gd"):
		dressed = load(LOOKS + "dressed_footman.gd")
		var squad_look: Script = load(LOOKS + "squad_look.gd")
		var livery: Dictionary = squad_look.get_script_constant_map().LIVERIES[SQUAD_LIVERY]
		looks = squad_look.squad(n, rng.randi(), livery, SQUAD_KIT)
	var kinds := []
	for i in n:
		kinds.append(s.profiles[i % s.profiles.size()])
	_shuffle(kinds, rng)
	var faces: Array = s.get("faces", []).duplicate()
	_shuffle(faces, rng)
	var kit: Array = s.get("kit", []).duplicate()
	_shuffle(kit, rng)
	var men := []
	for i in n:
		var p: Dictionary = kinds[i].duplicate()
		p["faction"] = u.faction
		var size := rng.randf_range(d.size.x, d.size.y)
		if not is_equal_approx(size, 1.0):
			p["scale"] = float(p.get("scale", 1.0)) * size
		if not faces.is_empty():
			p["face"] = faces[i % faces.size()]
		if not kit.is_empty():
			p["kit"] = kit[i % kit.size()]
		var m: Node3D = dressed.new() if dressed else Unit3D.new()
		m.setup(p)
		m.tile_m = tile_m
		m.name = "%s%d" % [String(u.uid).to_pascal_case(), i + 1]
		if dressed:
			m.look_spec = looks[i]
		world.add_child(m)
		var r := rng.randf_range(d.rate.x, d.rate.y)
		m.set_meta("rate", r)
		m.playback = _playback(m)
		m.set_meta("squad", sq)
		m.impact.connect(_on_impact.bind(m))
		m.release.connect(_on_release.bind(m))
		units.append(m)
		men.append(m)
	if dressed:
		load(LOOKS + "unit_look.gd").link(men)
	var at := _tile_pos(v.x, v.y)
	sq.setup(men, field, self, at, _yaw(v.facing), d)
	sq.id = s.id
	sq.title = Squad.squad_name(u)
	sq.faction = u.faction
	_place(sq, at, _yaw(v.facing))
	squads.append(sq)
	_uid_of[sq] = v.uid
	v.sq = sq
	if v.reserve:
		for m in men:
			m.visible = false


## Shuffles through the view's own generator (Array.shuffle takes the global one).
func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t


## A tile's centre on the ground.
func _tile_pos(x: float, y: float) -> Vector3:
	return field.on_ground(Vector2(x, y))


## The yaw of a rules facing (Grid.DIRS: +x, +y, -x, -y; a tile's +y is the world's +z).
static func _yaw(facing: int) -> float:
	var d: Dictionary = Grid.DIRS[facing]
	return atan2(float(d.x), float(d.y))


## The squad's men walk to its tile and stand in its ranks facing its facing.
func _reform(v: View3D, lag := Squad3D.REFORM_DELAY) -> void:
	var sq = v.sq
	if sq == null or sq.standing() == 0 or v.status == "fled":
		return
	sq._stop_fight()
	sq.mode = "reform"
	sq._form(_tile_pos(v.x, v.y), _yaw(v.facing), [], lag)
	_keep_off(sq)


## The squad marches the rules' path (tiles) to its last tile, at MARCH_PACE.
func _march(v: View3D, path: Array) -> void:
	var sq = v.sq
	if sq == null or sq.standing() == 0:
		return
	var route := []
	for i in range(1, path.size() - 1):
		route.append(_tile_pos(path[i].x, path[i].y))
	sq._stop_fight()
	_pace(sq, MARCH_PACE)
	sq.mode = "march"
	sq._form(_tile_pos(v.x, v.y), _yaw(v.facing), route, sq.drill.delay)
	_keep_off(sq)


## The squad stands at once on its places round `at`, none on what blocks a move.
func _place(sq, at: Vector3, yaw: float) -> void:
	sq.place(at, yaw)
	for m in sq.alive():
		if not _clear_of_things(m.position):
			m.position = _clear_spot(m.position, at)


## The squad's men whose places (squad3d.gd's slots, wider than a tile) are on
## a thing or over the water go to the nearest clear place towards the squad's
## middle (its own tile, which the rules keep clear) instead.
func _keep_off(sq) -> void:
	for m in sq.alive():
		var bl: Dictionary = sq._men[m]
		var goal: Vector3 = bl.goal
		if _clear_of_things(goal):
			continue
		var to := _clear_spot(goal, sq.center)
		var pts: Array = [to] if sq._clear_path(m.position, [to]) else sq._detour(m.position, to)
		sq._walk(m, pts, sq.yaw, float(bl.delay))


## A man standing at `p` is on walkable ground, BODY_R from anything else.
func _clear_of_things(p: Vector3) -> bool:
	for o in [Vector3.ZERO, Vector3(BODY_R, 0, 0), Vector3(-BODY_R, 0, 0), Vector3(0, 0, BODY_R), Vector3(0, 0, -BODY_R)]:
		if not field.walkable(field.tile_of(p + o)):
			return false
	return true


## The first clear place on the line from `p` to `at`.
func _clear_spot(p: Vector3, at: Vector3) -> Vector3:
	for k in range(1, 11):
		var q := p.lerp(at, k / 10.0)
		if _clear_of_things(q):
			return Vector3(q.x, field.ground_y(q.x, q.z), q.z)
	return at


## A man's playback: the battle's speed, his own rate and his squad's pace.
func _playback(m: Node3D) -> float:
	return speed * float(m.get_meta("rate", 1.0)) * float(m.get_meta("pace", 1.0))


func _pace(sq, k: float) -> void:
	for m in sq.members:
		m.set_meta("pace", k)
		m.playback = _playback(m)


func _settled(v: View3D) -> bool:
	return v.sq == null or v.sq.mode == "idle"


## The man of squad `sq` standing nearest `at`.
func _nearest_man(sq, at: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := INF
	if sq == null:
		return null
	for m in sq.alive():
		var d := Squad3D.flat(m.position - at).length()
		if d < bd:
			bd = d
			best = m
	return best


## Above the heads of a squad's men: where its words float.
func _head(v: View3D) -> Vector3:
	if v.sq == null:
		return _tile_pos(v.x, v.y) + Vector3(0, 2.3, 0)
	var men: Array = v.sq.alive()
	var c: Vector3 = v.sq.centroid() if not men.is_empty() else _tile_pos(v.x, v.y)
	var h := 1.8
	for m in men:
		h = maxf(h, m.height_m())
	return Vector3(c.x, maxf(c.y, field.ground_y(c.x, c.z)) + h + 0.5, c.z)


## n of the squad's standing men fall, those nearest `from` first.
func _kill(v: View3D, n: int, from: Vector3) -> void:
	if v.sq == null or n <= 0:
		return
	var men: Array = v.sq.alive()
	men.sort_custom(func(p, q): return p.position.distance_squared_to(from) < q.position.distance_squared_to(from))
	for i in mini(n, men.size()):
		men[i].take_hit(from, true)


## The squad's men down to `n` standing, at once and quietly (unseen).
func _quiet_casualties(v: View3D, n: int) -> void:
	v.alive = n
	if v.sq == null:
		return
	var men: Array = v.sq.alive()
	for i in range(n, men.size()):
		men[i].die()


# ---------------------------------------------------------------- what squad3d.gd asks of its host

func _squad_of(u: Node3D):
	return u.get_meta("squad") if u != null and u.has_meta("squad") else null


func _is_unit(n: Node3D) -> bool:
	return n != null and n.has_method("take_hit")


func _alive(n: Node3D) -> bool:
	return n != null and is_instance_valid(n) and (not _is_unit(n) or not n.is_dead())


func _hostile(u: Node3D, n: Node3D) -> bool:
	return n != null and n != u and _is_unit(n) and n.faction != u.faction


## The squads' own route marks are not shown: the view marks the ground itself.
func show_route(_marks: Dictionary) -> void:
	pass


func clear_route(_marks: Dictionary) -> void:
	pass


## A clear line of sight between two ground points (the battle's rule).
func _line_clear(a: Vector3, c: Vector3) -> bool:
	var ta: Vector2i = field.tile_of(a)
	var tb: Vector2i = field.tile_of(c)
	if not field.in_field(ta) or not field.in_field(tb):
		return true
	return not Grid.line_of_sight(field.map, {"x": ta.x, "y": ta.y}, {"x": tb.x, "y": tb.y}).blocked


# ---------------------------------------------------------------- blows (playback of the rules' hits)

## A blow lands or misses. In an attack being played back, as many of the
## target squad's men fall as the rules said, spread over the blows.
func _on_impact(target: Node3D, landed: bool, _reach: float, who: Node3D) -> void:
	var mine = _squad_of(who)
	if mine:
		mine.swung(who)
	if _spells.has(mine):
		_apply_spell(_spells[mine])
		return
	var st: Variant = _strikes.get(mine)
	if st != null and st.volley:
		st.left -= 1
	if target == null or not is_instance_valid(target) or not _is_unit(target):
		return
	var h: float = target.height_m()
	fx.spark(target.position + Vector3(0, h * 0.6, 0) - _dir(who, target) * 0.25, landed)
	if landed:
		_struck(st, who, target)


func _on_release(target: Node3D, kind: String, who: Node3D) -> void:
	var mine = _squad_of(who)
	if mine:
		mine.swung(who)
	_in_flight += 1
	fx.launch(kind, who, target, _missile_land.bind(who))


func _missile_land(target: Node3D, who: Node3D) -> void:
	_in_flight = maxi(0, _in_flight - 1)
	var mine = _squad_of(who)
	if _spells.has(mine):
		_apply_spell(_spells[mine])
		return
	var st: Variant = _strikes.get(mine)
	if st == null:
		return
	if st.volley:
		st.left -= 1
	# A man already fallen: the shot finds another of his squad.
	if (target == null or not _alive(target)) and st.v.sq != null:
		target = _nearest_man(st.v.sq, target.position if target != null and is_instance_valid(target) else st.v.sq.centroid())
	if target != null and _alive(target):
		_struck(st, who, target)


## Man `target` is struck by `who`: he falls if the attack being played back
## (`st`) still owes his squad a death and the blows left to come say so, else he flinches.
func _struck(st: Variant, who: Node3D, target: Node3D) -> void:
	if target.is_dead():
		return
	var dies := false
	if st != null:
		_show_hit(st)
		if _squad_of(target) == st.v.sq and st.budget > 0:
			var left := maxi(1, _blows_left(st, who))
			dies = st.budget >= left or _rng.randf() < float(st.budget) / left
	if dies:
		st.budget -= 1
		st.v.alive = maxi(0, st.v.alive - 1)
	var theirs = _squad_of(target)
	if theirs:
		theirs.struck(target)
	target.take_hit(who.position, dies)


## Blows still to come in the attack `st` (this one counted): shots not yet
## landed, or the fighting men's blows.
func _blows_left(st: Dictionary, who: Node3D) -> int:
	if st.volley:
		return int(st.left) + 1
	var sq = _squad_of(who)
	var n := 1
	if sq != null:
		for m in sq.alive():
			n += maxi(0, int(sq._men[m].blows))
	return n


func _dir(a: Node3D, c: Node3D) -> Vector3:
	var d := c.position - a.position
	d.y = 0
	return d.normalized() if d.length() > 1e-3 else Vector3.ZERO


# ---------------------------------------------------------------- state for the HUD

## BattleScene.notify: bumps ui.version and tells every listener (signal ui_changed).
func notify() -> void:
	ui.version += 1
	ui_changed.emit()


func _banner(text: String, sub, tone: String) -> void:
	ui.banner = {"text": text, "sub": sub, "tone": tone, "id": ui.version + 1}
	notify()


## Anything still playing (animations, queued events, missiles) or the rules running.
func busy() -> bool:
	return _anims.size() > 0 or _queue.size() > 0 or _in_flight > 0 or _task_id >= 0


## Nothing can be ordered now: the rules are running, it is not the company's
## turn as played back, or a banner (a turn, a wave, the end) is still to come.
func locked() -> bool:
	if _task_id >= 0 or _ended or ui.side != "player":
		return true
	for a in _anims:
		if a.barrier:
			return true
	for q in _queue:
		if BARRIERS.has(q.e.t):
			return true
	return false


func squad_visible(v) -> bool:
	return v != null and v.visible and (v.faction == "player" or fog.sees(v.uid))


func unit_visible(u: Dictionary) -> bool:
	return squad_visible(views.get(u.uid))


func selected_unit() -> Variant:
	if ui.selected == null:
		return null
	var u: Dictionary = _u(ui.selected)
	return u if u.status == "active" else null


func staged() -> Dictionary:
	var out := {}
	var waves := _waves()
	for i in waves.size():
		var w: Dictionary = waves[i]
		if b.wave_state[i] == "cancelled" or (w.get("horn") and b.horn != "sounded"):
			continue
		var due_in: int = w.turn - ui.turn
		if due_in > 1:
			continue
		for uid in w.uids:
			var v: View3D = views.get(uid)
			if v != null and v.reserve:
				out[uid] = maxi(0, due_in)
	return out


## The next wave as the HUD shows it: label, size, edge and turns until it marches in.
func next_wave_info() -> Variant:
	var n = b.next_wave()
	if n == null:
		return null
	var shown := []
	for w in _waves():
		if not w.get("horn") or b.horn == "sounded":
			shown.append(w)
	return {"label": n.wave.label, "count": n.wave.uids.size(), "edge": EDGE_NAME[n.wave.edge],
		"dueIn": maxi(0, n.turn - ui.turn), "index": shown.find(n.wave) + 1, "total": shown.size()}


func _waves() -> Array:
	var w: Variant = b.get("waves")
	return w if w is Array else []


func _tile_state(x: int, y: int) -> int:
	if b == null or not b.fog_enabled() or shroud == null or shroud.seen.has(Grid.key(x, y)):
		return 2
	return 1 if shroud.explored.has(Grid.key(x, y)) else 0


# ---------------------------------------------------------------- commands (from the HUD and the keys)

func select(uid = null, say := true) -> void:
	if uid != null:
		var u: Dictionary = _u(uid)
		if u.faction != "player" or u.status != "active":
			return
		_focus_on(views[uid].x, views[uid].y, false)
	ui.selected = uid
	ui.ability = null
	_reach_cache = null
	_states_cache = null
	_facing_pick = null
	_sfx("select")
	_refresh_hover()
	notify()


func set_ability(id = null) -> void:
	var u = selected_unit()
	if u == null or locked():
		return
	if id == null:
		ui.ability = null
		notify()
		return
	var ab: Dictionary = DB.ABILITIES[id]
	if ab.kind == "stance":
		if b.use_stance(u.uid, id):
			pump()
	elif ab.kind == "shout":
		if b.shout(u.uid, id):
			pump()
	elif ab.kind == "spell":
		if not b.can_cast(u, id).ok:
			_sfx("deny")
		elif ab.get("target") == "self":
			if b.cast(u.uid, id, {"x": u.x, "y": u.y}):
				ui.ability = null
				pump()
				_after_player_action(u)
		else:
			ui.ability = null if ui.ability == id else id
			_sfx("click")
			_refresh_hover()
	else:
		ui.ability = null if ui.ability == id else id
		_sfx("click")
	notify()


## Q / E: arrive on the previewed tile from another side (another path to it).
func cycle_facing(dir: int) -> void:
	var h: Dictionary = ui.hover
	if h.get("dest") == null or h.get("facing") == null or h.get("facings") == null or h.facings.size() < 2:
		_sfx("deny")
		return
	var i: int = h.facings.find(h.facing)
	var f: int = h.facings[(i + dir + h.facings.size()) % h.facings.size()]
	var pointed = null
	if h.get("tile") != null and h.dest.x == h.tile.x and h.dest.y == h.tile.y:
		pointed = _pointing(h.dest)
	_facing_pick = {"at": Grid.key(h.dest.x, h.dest.y), "facing": f, "pointed": pointed}
	_refresh_hover()
	_sfx("click")


## Take back a squad's move this turn (only before it attacks).
func redo(uid = null) -> void:
	if uid == null:
		uid = ui.selected
	if locked() or uid == null:
		return
	if b.redo_move(uid):
		pump()
		ui.selected = uid
		ui.ability = null
		_sfx("click")
		notify()
	else:
		_sfx("deny")


func end_unit() -> void:
	var u = selected_unit()
	if u == null or locked():
		return
	b.end_unit(u.uid)
	select_next()


func select_next(say := true) -> void:
	var list: Array = b.active("player").filter(func(x): return not x.done)
	if list.is_empty():
		select(null)
		return
	var cur := -1
	for i in list.size():
		if list[i].uid == ui.selected:
			cur = i
			break
	select(list[(cur + 1) % list.size()].uid, say)


func begin() -> void:
	if b.phase != "deploy" or _task_id >= 0:
		return
	_run_battle(func(bb): bb.begin(Callable(Ai, "run_enemy_ai")))
	_sfx("horn")


func end_turn() -> void:
	if locked() or b.phase != "player":
		return
	ui.selected = null
	ui.ability = null
	_run_battle(func(bb): bb.end_turn(Callable(Ai, "run_enemy_ai")))


func retreat() -> void:
	if locked() or b.phase != "player":
		return
	b.retreat()
	pump()


## Run `fn(b)` the way the enemy turns run (automation: Ai.run_player_auto), then play back what it did.
func run_rules(fn: Callable) -> void:
	if _task_id >= 0:
		return
	_run_battle(fn)


func rules_running() -> bool:
	return _task_id >= 0


## A rules step that may take long (the enemy AI) runs on a worker thread
## while the view keeps playing; until it is done `b` is a frozen copy of the
## battle (safe to read). Then its events are pumped into the playback queue.
func _run_battle(fn: Callable) -> void:
	if not threaded_rules:
		var t0 := Time.get_ticks_usec()
		fn.call(b)
		last_rules_ms = (Time.get_ticks_usec() - t0) / 1000.0
		pump()
		return
	_live_b = b
	b = _snapshot(_live_b)
	_task_fn = fn
	_task_t0 = Time.get_ticks_usec()
	_task_id = WorkerThreadPool.add_task(_task_body, false, "battle rules")
	_reach_cache = null
	_states_cache = null
	_danger_cache = null
	ui.hover = _empty_hover()
	_sync_busy()
	notify()


func _task_body() -> void:
	_task_fn.call(_live_b)


func _poll_task() -> void:
	if _task_id < 0 or not WorkerThreadPool.is_task_completed(_task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	last_rules_ms = (Time.get_ticks_usec() - _task_t0) / 1000.0
	b = _live_b
	_live_b = null
	_task_fn = Callable()
	pump()


## A read-only copy of the battle as it stands (battle_view.gd's _snapshot).
static func _snapshot(live) -> Variant:
	var snap = live.get_script().new(live.setup)
	for p in live.get_property_list():
		if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n: String = p.name
		if n == "objective" or n == "waves" or n == "ai_cache":
			continue
		var v = live.get(n)
		if n == "map" or n == "setup" or n == "rng":
			snap.set(n, v)
		elif v is Array or v is Dictionary:
			snap.set(n, v.duplicate(true))
		else:
			snap.set(n, v)
	return snap


func _after_player_action(u: Dictionary) -> void:
	_reach_cache = null
	_states_cache = null
	if u.done or u.status != "active":
		select_next(false)
	else:
		_refresh_hover()


## After a deployment swap: the squads walk to their new tiles.
func _sync_views() -> void:
	for u in b.units:
		var v: View3D = views[u.uid]
		if v.x != u.x or v.y != u.y or v.facing != u.facing:
			v.x = u.x
			v.y = u.y
			v.facing = u.facing
			_reform(v, Vector2(0.0, 0.2))


# ---------------------------------------------------------------- event playback

func pump() -> void:
	for e in b.drain():
		var involved := _involved(e)
		e["witnesses"] = involved
		_queue.append({"e": e, "uids": involved})
	_reach_cache = null
	_states_cache = null
	_danger_cache = null
	_sync_busy()
	notify()


## The squads an event shows. Consequences (morale, falls, routs, log lines)
## wait for the action that caused them (battle_view.gd's _involved).
func _involved(e: Dictionary) -> Array:
	match e.t:
		"move", "face", "stance", "halt", "spawn", "shout", "horn", "broken":
			_cause = [e.uid]
			return [e.uid]
		"attack":
			_cause = [e.uid, e.target]
			if e.get("via") != null:
				_cause.append(e.via)
			return _cause.duplicate()
		"spell":
			_cause = [e.uid]
			for h in e.hits:
				if not _cause.has(h.uid):
					_cause.append(h.uid)
			return _cause.duplicate()
		"status", "dot", "push", "heal", "morale", "mstate", "down", "rout", "rally", "fled":
			var out := [e.uid]
			for c in _cause:
				if not out.has(c):
					out.append(c)
			return out
		"log":
			return _cause.duplicate()
		_:
			_cause = []
			return []


## Start queued events in order; events about different squads run side by
## side, those about the same squads and the barriers keep their order.
func _next() -> void:
	for a in _anims:
		if a.barrier:
			return
	var busy_u := {}
	for a in _anims:
		for u in a.uids:
			busy_u[u] = true
	var started := 0
	var i := 0
	while i < _queue.size():
		var q: Dictionary = _queue[i]
		var e: Dictionary = q.e
		var uids: Array = q.uids
		if BARRIERS.has(e.t):
			if i > 0 or _anims.size() > 0 or _in_flight > 0:
				return
			_queue.remove_at(i)
			_anim = null
			_play(e)
			if _anim != null:
				var a: Anim = _anim
				_anim = null
				a.barrier = true
				a.uids = uids
				_anims.append(a)
				return
			continue
		if _anims.size() >= MAX_ANIMS:
			return
		var blocked := false
		for u in uids:
			if busy_u.has(u):
				blocked = true
				break
		if blocked:
			for u in uids:
				busy_u[u] = true
			i += 1
			continue
		_queue.remove_at(i)
		_anim = null
		_play(e)
		if _anim != null:
			var a: Anim = _anim
			_anim = null
			a.uids = uids
			a.delay += minf(0.6, started * 0.08)
			_anims.append(a)
			started += 1
			for u in uids:
				busy_u[u] = true


func _new_anim(dur: float, step: Callable = Callable(), done: Callable = Callable()) -> Anim:
	var a := Anim.new()
	a.dur = dur
	a.step = step
	a.done = done
	return a


func _step_anims(dt: float) -> void:
	for a: Anim in _anims.duplicate():
		if a.delay > 0:
			a.delay -= dt
			continue
		if not a.started:
			a.started = true
			if a.start.is_valid():
				a.start.call()
		a.t += dt
		if a.step.is_valid():
			a.step.call(minf(1.0, a.t / a.dur) if a.dur > 0 else 1.0)
		var held: bool = a.until.is_valid() and a.t < a.limit and not a.until.call()
		if a.t >= a.dur and not held:
			if a.done.is_valid():
				a.done.call()
			_anims.erase(a)


func _play(e: Dictionary) -> void:
	if fog.enabled():
		if e.t == "log" and not e.get("witnesses", []).is_empty() and not e.witnesses.any(func(id): return squad_visible(views.get(id))):
			return
		if e.has("uid") and not squad_visible(views.get(e.uid)) and e.t not in ["move", "face", "spawn", "reveal", "horn", "broken", "attack", "spell"]:
			_play_unseen(e)
			return
	match e.t:
		"reveal":
			_revealed[e.uid] = true
			_update_fog(0.0)
		"sight_reset":
			for uid in _revealed.keys():
				if views.has(uid) and views[uid].faction == e.faction:
					_revealed.erase(uid)
			_update_fog(0.0)
		"log":
			ui.log.push_front({"text": e.text, "tone": e.get("tone")})
			if ui.log.size() > 60:
				ui.log.pop_back()
			notify()
		"turn":
			var mine: bool = e.faction == "player"
			ui.turn = e.turn
			ui.side = e.faction
			_banner("Your Turn" if mine else "Enemy Turn", "Turn %d" % e.turn, "player" if mine else "enemy")
			_sfx("turn" if mine else "drum")
			_anim = _new_anim(0.9)
			if mine:
				var first = _first(b.active("player").filter(func(u): return not u.done))
				if first != null:
					ui.selected = first.uid
					_focus_on(views[first.uid].x, views[first.uid].y, false)
		"face":
			var v: View3D = views[e.uid]
			if v.facing != e.facing:
				v.facing = e.facing
				_reform(v, Vector2(0.0, 0.2))
				_anim = _new_anim(0.2)
				_anim.until = _settled.bind(v)
				_anim.limit = 2.5
		"move":
			_play_move(e)
		"heal":
			var v: View3D = views[e.uid]
			v.hp = e.hp
			_text(_head(v), "+%s" % JS.num_str(e.amount), C_HEAL)
			_text(_head(v) + Vector3(0, -0.5, 0), str(e.reason), C_HEAL, 0.6, 0.1)
			_anim = _new_anim(0.5)
		"attack":
			_play_attack(e)
		"spell":
			_play_spell(e)
		"status":
			var v: View3D = views[e.uid]
			if e.on:
				if not v.statuses.has(e.status):
					v.statuses.append(e.status)
				_text(_head(v) + Vector3(0, 0.6, 0), STATUS_NAME.get(e.status, String(e.status).capitalize()), C_NEWS, 0.7, 0.05)
			else:
				v.statuses.erase(e.status)
		"dot":
			var v: View3D = views[e.uid]
			v.hp = e.hp
			_text(_head(v), JS.num_str(e.damage), C_BAD)
			_kill(v, int(e.aliveBefore) - int(e.aliveAfter), _tile_pos(v.x, v.y) + Vector3(0, 0, 1))
			v.alive = int(e.aliveAfter)
			_anim = _new_anim(0.55)
		"push":
			_play_push(e)
		"morale":
			var v: View3D = views[e.uid]
			v.morale = e.value
			if absf(e.delta) >= 5 and not QUIET_MORALE.has(e.reason) and v.faction == "player":
				_text(_head(v) + Vector3(0, -0.4, 0), "%s%s morale" % ["+" if e.delta > 0 else "", JS.num_str(e.delta)], Color("#9fd8ff") if e.delta > 0 else C_MORALE, 0.55, 0.15)
		"mstate":
			var v: View3D = views[e.uid]
			var worse: bool = MORALE_RANK.find(e.to) > MORALE_RANK.find(e.from)
			if e.to != "broken" and (worse if v.faction == "player" else e.to == "wavering"):
				_text(_head(v) + Vector3(0, 0.8, 0), String(e.to).capitalize(), C_MORALE, 0.7, 0.35)
		"down":
			var v: View3D = views[e.uid]
			var u: Dictionary = _u(e.uid)
			v.status = "dead" if e.dead else "downed"
			v.stance = null
			v.statuses = []
			v.hp = 0
			_text(_head(v), "Slain" if u.get("leader") else ("Wiped out" if e.dead else "Broken"), C_BAD if e.dead else Color("#ffd27a"))
			if v.sq != null:
				_kill(v, v.sq.standing(), _tile_pos(v.x, v.y))
			v.alive = 0
			_sfx("death")
			_anim = _new_anim(0.6)
		"rout":
			var v: View3D = views[e.uid]
			v.routing = true
			v.stance = null
			if not _horde_broken:
				_text(_head(v), "Routed!", Color("#f2efe4"))
			_anim = _new_anim(0.45)
		"rally":
			var v: View3D = views[e.uid]
			v.routing = false
			_text(_head(v), "Rallied!", Color("#9fe0ff"), 0.8)
		"fled":
			var v: View3D = views[e.uid]
			v.status = "fled"
			_anim = _new_anim(0.4, Callable(), func():
				v.visible = false
				if v.sq != null:
					for m in v.sq.members:
						m.visible = false)
		"stance":
			var v: View3D = views[e.uid]
			v.stance = e.get("stance")
			if v.stance != null:
				_text(_head(v), STANCE_NAME.get(v.stance, String(v.stance).capitalize()), C_NEWS, 0.8)
				_anim = _new_anim(0.35)
		"shout":
			var v: View3D = views[e.uid]
			_text(_head(v) + Vector3(0, 0.4, 0), "%s!" % DB.ABILITIES[e.ability].name, Color("#ff9a7a"))
			_focus_on(v.x, v.y, false)
			_anim = _new_anim(0.8)
		"halt":
			_text(_head(views[e.uid]), "Halted!", C_NEWS, 0.8, 0.1)
		"warn":
			_banner("War horns!", "%s: %d squads reach the field from the %s edge at the end of this turn" % [e.label, e.count, EDGE_NAME[e.edge]], "enemy")
			_sfx("warhorn")
			_anim = _new_anim(1.1)
		"wave":
			_banner("The warchief comes!" if e.final else e.label, "%d more squads march onto the field from the %s edge" % [e.count, EDGE_NAME[e.edge]], "enemy")
			_sfx("warhorn")
			_anim = _new_anim(1.3)
		"spawn":
			var v: View3D = views[e.uid]
			v.reserve = false
			v.visible = true
			v.status = "active"
			v.x = e.to.x
			v.y = e.to.y
			if v.sq != null:
				var from := Vector2(clampf(e.from.x, 0, b.map.w - 1), clampf(e.from.y, 0, b.map.h - 1))
				v.sq.place(field.on_ground(from), _yaw(v.facing))
				for m in v.sq.alive():
					m.visible = true
				_march(v, [e.from, e.to])
				_anim = _new_anim(0.3)
				_anim.until = _settled.bind(v)
				_anim.limit = 8.0
		"horn":
			if e.sounded:
				_banner("The war horn sounds!", "More of the horde will answer it next turn", "enemy")
				_sfx("warhorn")
			else:
				_banner("The horn is silenced", "No help will come for them", "player")
				_sfx("horn")
			_anim = _new_anim(1.1)
		"overrun":
			var zn = b.map.get("zoneName")
			_banner("The line is breaking!", "%s is overrun. Drive them out before their next turn ends." % (zn if zn != null else "The held ground"), "enemy")
			_sfx("drum")
			_anim = _new_anim(1.1)
		"broken":
			_horde_broken = true
			_banner("The horde breaks!", "%s is slain" % Squad.squad_name(_u(e.uid)), "player")
			_sfx("relief")
			_anim = _new_anim(1.6)
		"relief":
			_horde_broken = true
			_banner("Held!", e.text, "player")
			_sfx("relief")
			_anim = _new_anim(1.8)
		"end":
			var result: String = e.result
			_banner("Victory" if result == "victory" else ("Withdrawal" if result == "retreat" else "Defeat"), null, "player" if result == "victory" else "enemy")
			_sfx("victory" if result == "victory" else "defeat")
			_anim = _new_anim(1.4, Callable(), func():
				_ended = true
				_sync_busy()
				notify()
				# After this frame: whoever hears it takes the view off the screen.
				ended.emit.call_deferred(result))


## An event about a squad the company does not see: its state only (battle_view.gd's _play_unseen).
func _play_unseen(e: Dictionary) -> void:
	var v: View3D = views.get(e.get("uid", ""))
	if v == null:
		return
	match e.t:
		"heal", "dot":
			v.hp = e.hp
			if e.has("aliveAfter"):
				_quiet_casualties(v, int(e.aliveAfter))
		"status":
			if e.on and not v.statuses.has(e.status):
				v.statuses.append(e.status)
			elif not e.on:
				v.statuses.erase(e.status)
		"morale":
			v.morale = e.value
		"down":
			v.status = "dead" if e.dead else "downed"
			v.hp = 0
			v.stance = null
			v.statuses = []
			_quiet_casualties(v, 0)
		"rout", "rally":
			v.routing = e.t == "rout"
			v.status = "routing" if v.routing else "active"
			v.stance = null
		"fled":
			v.status = "fled"
			v.visible = false
			if v.sq != null:
				for m in v.sq.members:
					m.visible = false
		"stance":
			v.stance = e.get("stance")
		"push":
			_play_push(e)


## A march along the rules' path; the squad faces the way of its last step (a
## squad falling back off an ally's tile backs away, still facing its way).
## A squad the company sees neither set off nor arrive is moved at once.
func _play_move(e: Dictionary) -> void:
	var v: View3D = views[e.uid]
	var path: Array = e.path
	var last: Dictionary = path[path.size() - 1]
	var seen_from := squad_visible(v)
	if path.size() > 1 and not e.get("backward", false):
		v.facing = Grid.dir_to(path[path.size() - 2], last)
	v.x = last.x
	v.y = last.y
	if v.sq == null:
		return
	var shown: bool = v.faction == "player" or seen_from or not fog.enabled() or shroud.shows(Vector2i(last.x, last.y))
	if not shown:
		_place(v.sq, _tile_pos(v.x, v.y), _yaw(v.facing))
		return
	if v.faction == "player" or _near_company(last):
		_focus_on(last.x, last.y, false)
	_march(v, path)
	_anim = _new_anim(0.3, Callable(), _pace.bind(v.sq, 1.0))
	_anim.until = _settled.bind(v)
	_anim.limit = 4.0 + 2.5 * path.size()


func _play_push(e: Dictionary) -> void:
	var v: View3D = views[e.uid]
	v.hp = e.get("hp", v.hp)
	if not e.get("blocked", false):
		v.x = e.to.x
		v.y = e.to.y
	_text(_head(v), "Pushed back!" if not e.get("blocked", false) else "Crushed!", C_FLANK, 0.8)
	var left: Variant = e.get("alive")
	if left is int and left < v.alive:
		_kill(v, v.alive - left, _tile_pos(e.from.x, e.from.y))
		v.alive = left
	_reform(v, Vector2(0.0, 0.15))
	_anim = _new_anim(0.3)
	_anim.until = _settled.bind(v)
	_anim.limit = 3.0


## Whether tile t is within a few tiles of one of the company's squads (the
## camera follows the enemy only there).
func _near_company(t: Dictionary) -> bool:
	for v in views.values():
		if v.faction == "player" and v.alive > 0 and absi(v.x - int(t.x)) + absi(v.y - int(t.y)) <= 6:
			return true
	return false


## An attack: a melee attack is the attacker's fight (its men march up and
## strike in their own time), a ranged one each shooter's shot from where he
## stands. As many of the target's men fall as the rules say: on the blows
## that land, the rest when it is over; then both squads re-form on their tiles.
func _play_attack(e: Dictionary) -> void:
	var av: View3D = views[e.uid]
	var tv: View3D = views[e.target]
	if av.faction == "player" or tv.faction == "player":
		_focus_on((av.x + tv.x) / 2.0, (av.y + tv.y) / 2.0, false)
	var reaction = e.get("reaction")
	if reaction != null:
		var label := "Free attack" if reaction == "zoc" else ("Spearwall!" if reaction == "spearwall" else ("Overwatch!" if reaction == "overwatch" else "First strike!"))
		_text(_head(av), label, C_NEWS, 0.7)
	if e.get("ward") != null and views.has(e.ward):
		_text(_head(tv) + Vector3(0, 0.5, 0), "Guarded!", C_NEWS, 0.8)
	var st := {"v": tv, "e": e, "budget": maxi(0, int(e.aliveBefore) - int(e.aliveAfter)), "volley": bool(e.ranged), "left": 0, "shown": false, "spent": -1.0}
	var fights: bool = av.sq != null and tv.sq != null and av.sq.standing() > 0 and tv.sq.standing() > 0 and (squad_visible(av) or squad_visible(tv))
	if not fights:
		_anim = _new_anim(0.35, Callable(), _end_attack.bind(av, st))
		return
	_strikes[av.sq] = st
	if e.ranged:
		var men: Array = av.sq.alive()
		var foes: Array = tv.sq.alive()
		st.left = men.size()
		for i in men.size():
			var m: Node3D = men[i]
			var t: Node3D = foes[i % foes.size()]
			_later(i * 0.08 + _rng.randf() * 0.12, func():
				if m.is_dead() or not _alive(t):
					st.left -= 1
				else:
					m.strike_at(t))
		_anim = _new_anim(0.4, Callable(), _end_attack.bind(av, st))
		_anim.until = func(): return st.left <= 0
	else:
		av.sq.attack(_nearest_man(tv.sq, av.sq.centroid()))
		_keep_off(av.sq)
		for m in av.sq.alive():
			var bl: Dictionary = av.sq._men[m]
			bl.blows = mini(int(bl.blows), ATTACK_BLOWS.x if bl.role == "front" else ATTACK_BLOWS.y)
		var a := _new_anim(0.4, Callable(), _end_attack.bind(av, st))
		# Over when the squad is done, or a little after the last death owed has fallen.
		a.until = func():
			if st.budget <= 0 and st.spent < 0.0 and st.shown:
				st.spent = a.t
			return av.sq.mode != "fight" or (st.spent >= 0.0 and a.t - st.spent >= ATTACK_LINGER)
		_anim = a
	_anim.limit = FIGHT_LIMIT


## The attack's numbers over the target (once): its damage, or the miss.
func _show_hit(st: Dictionary) -> void:
	if st.shown:
		return
	st.shown = true
	var e: Dictionary = st.e
	var tv: View3D = st.v
	tv.hp = e.targetHp
	if e.hit:
		_text(_head(tv), JS.num_str(e.damage), C_FLANK if e.arc == "rear" else C_HIT, 1.15 if e.arc == "front" else 1.3)
		if e.arc != "front":
			_text(_head(tv) + Vector3(0, 0.55, 0), "Rear!" if e.arc == "rear" else "Flank!", C_FLANK, 0.7, 0.05)
		var armored: bool = _u(tv.uid).stats.armor >= 2
		_sfx("bolt_hit" if e.ranged else ("hit_metal" if armored else "hit_flesh"))
	else:
		var blocked: bool = not e.ranged and e.arc == "front" and _u(tv.uid).get("shieldFront", 0) > 0
		_text(_head(tv), "Blocked" if blocked else "Miss", C_MISS, 0.9)
		_sfx("block" if blocked else "miss")
	notify()


## The attack is over: the deaths still owed fall, both squads re-form on their tiles.
func _end_attack(av: View3D, st: Dictionary) -> void:
	if av.sq != null:
		_strikes.erase(av.sq)
	_show_hit(st)
	var tv: View3D = st.v
	var after := int(st.e.aliveAfter)
	if tv.sq != null and tv.sq.standing() > after:
		_kill(tv, tv.sq.standing() - after, av.sq.centroid() if av.sq != null else _tile_pos(av.x, av.y))
	tv.alive = after
	_reform(av)
	_reform(tv)


## A spell: its casters cast at where it goes (the mage's clips and missiles,
## when they have them), and where it lands its hits show and their men fall.
func _play_spell(e: Dictionary) -> void:
	var ab: Dictionary = DB.ABILITIES[e.ability]
	var av: View3D = views[e.uid]
	var at := _tile_pos(e.at.x, e.at.y)
	_text(_head(av) + Vector3(0, 0.4, 0), String(ab.name), Color("#cfe6ff"), 0.8)
	if av.faction == "player" or e.hits.any(func(h): return views[h.uid].faction == "player"):
		_focus_on((av.x + e.at.x) / 2.0, (av.y + e.at.y) / 2.0, false)
	var st := {"e": e, "at": at, "applied": false}
	var clip: String = SPELL_CAST.get(ab.get("fx", ""), "")
	var mark: Node3D = null
	for h in e.hits:
		var hv: View3D = views[h.uid]
		if hv.sq != null and hv.sq.standing() > 0:
			mark = _nearest_man(hv.sq, at)
			break
	if av.sq != null and av.sq.standing() > 0 and clip != "" and mark != null and squad_visible(av):
		_spells[av.sq] = st
		var men: Array = av.sq.alive()
		for i in men.size():
			var m: Node3D = men[i]
			var k: int = m.pick_attack(mark, [clip])
			_later(i * 0.15, func():
				if not m.is_dead() and _alive(mark):
					m.strike(mark, k))
	else:
		_later(0.45, func():
			fx.spark(at + Vector3(0, 0.8, 0), true)
			_apply_spell(st))
	_anim = _new_anim(0.6, Callable(), func():
		_apply_spell(st)
		if av.sq != null:
			_spells.erase(av.sq)
			_reform(av))
	_anim.until = func(): return st.applied
	_anim.limit = 5.0


## The spell's hits show where it lands (once).
func _apply_spell(st: Dictionary) -> void:
	if st.applied:
		return
	st.applied = true
	for h in st.e.hits:
		var hv: View3D = views[h.uid]
		hv.hp = h.hp
		if float(h.get("heal", 0)) > 0:
			_text(_head(hv), "+%s" % JS.num_str(h.heal), C_HEAL)
		elif float(h.get("damage", 0)) > 0:
			_text(_head(hv), JS.num_str(h.damage), C_BAD)
		var after := int(h.get("aliveAfter", hv.alive))
		if hv.sq != null and hv.sq.standing() > after:
			_kill(hv, hv.sq.standing() - after, st.at)
		hv.alive = after
		if h.get("status") != null and not hv.statuses.has(h.status):
			hv.statuses.append(h.status)
	notify()


## Calls fn after `delay` seconds of battle time.
func _later(delay: float, fn: Callable) -> void:
	_timers.append([delay, fn])


# ---------------------------------------------------------------- floating words

## Words rising over the field (Label3D, always in front), `size` 1 a squad's
## damage, after `delay` seconds.
func _text(at: Vector3, s: String, col: Color, size := 1.0, delay := 0.0) -> void:
	var l := Label3D.new()
	l.text = s
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 64
	l.pixel_size = 0.017 * size
	l.outline_size = 16
	l.modulate = col
	l.outline_modulate = Color(0.06, 0.04, 0.03, 0.85)
	l.render_priority = 10
	l.outline_render_priority = 9
	l.position = at
	l.visible = false
	add_child(l)
	_texts.append({"node": l, "t": -delay, "y": at.y})


func _step_texts(dt: float) -> void:
	for x in _texts.duplicate():
		x.t += dt
		var l: Label3D = x.node
		if x.t < 0.0:
			continue
		var life := 1.5
		l.visible = true
		l.position.y = x.y + 0.9 * (1.0 - pow(1.0 - minf(1.0, x.t / life), 2.0))
		l.modulate.a = clampf((life - x.t) / (life * 0.35), 0.0, 1.0)
		l.outline_modulate.a = l.modulate.a * 0.85
		if x.t >= life:
			l.queue_free()
			_texts.erase(x)


# ---------------------------------------------------------------- pointer: what it points at and previews

func _ground_at(screen: Vector2) -> Variant:
	if cam == null or screen.x < 0:
		return null
	return field.pick(cam.project_ray_origin(screen), cam.project_ray_normal(screen))


func _tile_at_screen(screen: Vector2) -> Variant:
	var g = _ground_at(screen)
	if g == null:
		return null
	var t: Vector2i = field.tile_of(g)
	return {"x": t.x, "y": t.y} if Grid.in_bounds(b.map, t.x, t.y) else null


## The man under a screen point (near his body from feet to head); the nearest the camera wins.
func _pick_body(screen: Vector2) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for n in units:
		if not n.visible or n.is_dead():
			continue
		var h: float = n.height_m()
		for f in [0.1, 0.35, 0.6, 0.85]:
			var p := cam.unproject_position(n.position + Vector3(0, h * f, 0))
			if p.distance_to(screen) < 0.34 * ppu * zoom:
				var depth := cam.global_position.distance_to(n.position)
				if depth < bd:
					bd = depth
					best = n
	return best


## The rules squad whose figure is under a screen point (seen, still on the field).
func _unit_at_screen(screen: Vector2) -> Variant:
	var man := _pick_body(screen)
	var sq = _squad_of(man)
	if sq == null or not _uid_of.has(sq):
		return null
	var v: View3D = views[_uid_of[sq]]
	if not squad_visible(v) or v.status in ["dead", "downed", "fled"]:
		return null
	return _u(v.uid)


## What the pointer points at: a man is his squad (the men stand over the
## edges of their tile), else the squad on the tile under the pointer.
func resolve_pointer(screen: Vector2) -> Dictionary:
	var ground = _tile_at_screen(screen)
	var standing_u = Grid.unit_at(b.units, ground.x, ground.y) if ground != null else null
	if standing_u != null and not unit_visible(standing_u):
		standing_u = null
	var body = _unit_at_screen(screen)
	if body != null and (standing_u == null or body.uid != standing_u.uid):
		return {"tile": {"x": body.x, "y": body.y}, "unit": body}
	return {"tile": ground, "unit": standing_u}


static func _empty_hover() -> Dictionary:
	return {"tile": null, "unit": null, "preview": null, "spell": null, "path": null, "zoc": null, "dest": null, "facing": null, "facings": null, "turn": null}


## The spell the cursor aims: the one chosen, or with none chosen a war
## machine's stone when the cursor is on an enemy.
func _aimed_spell(sel, under = null) -> Variant:
	if sel == null:
		return null
	var id = ui.ability
	if id != null:
		return id if DB.ABILITIES.get(id, {}).get("kind") == "spell" else null
	var primary = DB.UNIT_TYPES.get(sel.typeId, {}).get("primary")
	if primary != null and under != null and under.faction == "enemy" and b.can_cast(sel, primary).ok:
		return primary
	return null


func _spell_aim(spell_id: String, t: Dictionary, u = null) -> Variant:
	var target = DB.ABILITIES[spell_id].get("target")
	if target == "tile":
		return {"x": u.x, "y": u.y} if u != null else {"x": t.x, "y": t.y}
	if target == "enemy" and u != null and u.faction == "enemy":
		return {"x": u.x, "y": u.y}
	if target == "ally" and u != null and u.faction == "player":
		return {"x": u.x, "y": u.y}
	return null


func pointer_move(p: Vector2) -> void:
	_pointer = p
	_refresh_hover()


## The hover of battle_view.gd: the tile and squad pointed at, an attack's
## preview, the march (path, arrival tile and facing) or a spell's.
func _refresh_hover() -> void:
	if _task_id >= 0 or b == null or field == null:
		return
	var rp := resolve_pointer(_pointer)
	var t = rp.tile
	var hover := _empty_hover()
	hover.tile = t
	var sel = selected_unit()
	var can: bool = sel != null and not locked() and b.phase == "player"
	if t != null:
		var u = rp.unit
		if u != null:
			hover.unit = u.uid
		var spell_id = _aimed_spell(sel, u) if can else null
		if can and spell_id != null:
			var at = _spell_aim(spell_id, t, u)
			if at != null and not sel.hasActed:
				hover.spell = b.spell_preview(sel, spell_id, at)
			if ui.ability == null and u != null and hover.spell != null and not hover.spell.legal:
				hover.spell = null
				hover.preview = _preview_against(sel, u)
		elif can:
			if u != null and u.faction == "enemy":
				hover.preview = _preview_against(sel, u)
				var from = hover.preview.get("from") if (hover.preview != null and hover.preview.moveFirst) else null
				if from != null:
					var arr = _arrival(sel, from, Grid.dir_to(from, u), true)
					if arr != null:
						_show_arrival(hover, from, arr)
			elif u == null and not sel.hasMoved and sel.status == "active":
				if _reach(sel).has(Grid.key(t.x, t.y)):
					var pt = _pointing(t)
					if _facing_pick != null and pt != _facing_pick.pointed:
						_facing_pick = null
					var arr = _arrival(sel, t, pt)
					if arr != null:
						_show_arrival(hover, t, arr)
			elif u != null and u.uid == sel.uid and not sel.hasMoved and sel.status == "active":
				# Pointing at an edge of the squad's own tile: step out and back to face that way.
				var want = _pointing(t, 0.2, true)
				if want != null and want != sel.facing:
					var arr = _arrival(sel, t, want, false, true)
					if arr != null and arr.opt.facing == want:
						_show_arrival(hover, t, arr)
						hover.turn = true
	var changed: bool = hover != ui.hover
	ui.hover = hover
	if changed:
		notify()


func _show_arrival(hover: Dictionary, at: Dictionary, arr: Dictionary) -> void:
	hover.dest = {"x": at.x, "y": at.y}
	hover.path = arr.opt.path if arr.opt.path.size() > 1 else null
	hover.zoc = arr.opt.zoc
	hover.facing = arr.opt.facing
	hover.facings = arr.all.map(func(o): return o.facing)


func _states(u: Dictionary) -> Dictionary:
	if _states_cache == null or _states_cache.uid != u.uid:
		_states_cache = {"uid": u.uid, "states": b.reach_states(u)}
	return _states_cache.states


## How the selected squad would arrive on `at` (battle_view.gd's _arrival):
## the facing picked with Q / E, else the one asked for (`soft`: only if it
## provokes no extra free attacks), else the default.
func _arrival(sel: Dictionary, at: Dictionary, want = null, soft := false, turn_only := false) -> Variant:
	var all: Array = b.facing_options(sel, at.x, at.y, _states(sel))
	if turn_only:
		all = all.filter(func(o): return o.path.size() > 1)
	if all.is_empty():
		return null
	var k := Grid.key(at.x, at.y)
	if _facing_pick != null and _facing_pick.at != k:
		_facing_pick = null
	var opt = null
	if _facing_pick != null:
		for o in all:
			if o.facing == _facing_pick.facing:
				opt = o
				break
	if opt == null and want != null:
		var o = null
		var min_zoc := INF
		for q in all:
			min_zoc = minf(min_zoc, q.zoc)
			if o == null and q.facing == want:
				o = q
		if o != null and (not soft or o.zoc <= min_zoc):
			opt = o
	if opt == null:
		opt = b.default_facing(sel, at.x, at.y, all)
	return {"opt": opt, "all": all} if opt != null else null


## The facing the pointer points at inside tile `at`: toward the edge it is
## nearest, none near the centre (`inside`: none off the tile).
func _pointing(at: Dictionary, dead := 0.16, inside := false) -> Variant:
	var g = _ground_at(_pointer)
	if g == null:
		return null
	var gx: float = g.x / tile_m - at.x
	var gy: float = g.z / tile_m - at.y
	if Vector2(gx, gy).length() < dead:
		return null
	if inside and absf(gx) + absf(gy) > 0.62:
		return null
	return Grid.dir_to({"x": 0, "y": 0}, {"x": gx, "y": gy})


## An attack's preview, with move-then-strike for melee from the side nearest the pointer.
func _preview_against(sel: Dictionary, target: Dictionary) -> Variant:
	if sel.hasActed:
		return null
	var ability = ui.ability
	var here: Dictionary = b.preview(sel, target, {"ability": ability} if ability != null else {})
	if here.legal or sel.hasMoved:
		return _pv(here, target.uid, ability, false)
	var ab = DB.ABILITIES[ability] if ability != null else null
	var reach := _reach(sel)
	if sel.get("shot") != null and ab == null:
		# Ranged units: the reachable tile that keeps the best shot.
		var best = null
		for k in reach:
			var from := {"x": k % 1000, "y": floori(k / 1000.0)}
			var pv: Dictionary = b.preview(sel, target, {"from": from, "movedTiles": 1})
			if pv.legal and (best == null or pv.chance > best.pv.chance):
				best = {"pv": pv, "from": from}
		if best == null:
			return _pv(here, target.uid, null, false)
		var out := _pv(best.pv, target.uid, null, true)
		out.from = best.from
		return out
	# Melee: the side nearest the pointer (a charge: the nearest that gives it its run).
	var g = _ground_at(_pointer)
	var pt := Vector2(g.x / tile_m, g.z / tile_m) if g != null else Vector2(target.x, target.y)
	var opts: Array = []
	for d in Grid.DIRS:
		if ab != null and ab.get("reach") == 2:
			opts.append({"x": target.x - d.x * 2, "y": target.y - d.y * 2})
		else:
			opts.append({"x": target.x + d.x, "y": target.y + d.y})
	var strike := func(from: Dictionary) -> Dictionary:
		var path = b.path_to(sel, from.x, from.y)
		var o := {"from": from, "movedTiles": path.size() - 1 if path != null else 1}
		if ability != null:
			o.ability = ability
		return b.preview(sel, target, o)
	var run: bool = ab != null and ab.get("minRun") != null
	var best = null
	var best_run = null
	for from in opts:
		if not reach.has(Grid.key(from.x, from.y)):
			continue
		var side := {"from": from, "d": pt.distance_to(Vector2(from.x, from.y)), "pv": null}
		if run and (best_run == null or side.d < best_run.d):
			side.pv = strike.call(from)
			if side.pv.legal:
				best_run = side
		if best == null or side.d < best.d:
			best = side
	if best == null:
		return _pv(here, target.uid, ability, false)
	if best_run != null:
		best = best_run
	var pv: Dictionary = best.pv if best.pv != null else strike.call(best.from)
	var out := _pv(pv, target.uid, ability, true)
	out.from = best.from
	return out


static func _pv(p: Dictionary, target: String, ability, move_first: bool) -> Dictionary:
	var out := p.duplicate()
	out.target = target
	out.from = null
	out.ability = ability
	out.moveFirst = move_first
	return out


func _reach(u: Dictionary) -> Dictionary:
	if _reach_cache == null or _reach_cache.uid != u.uid:
		_reach_cache = {"uid": u.uid, "reach": b.reachable(u)}
	return _reach_cache.reach


## A click (battle_view.gd's pointer_down): deploy swaps, spells, attacks
## (moving first to the side previewed), marches; right click cancels.
func pointer_down(p: Vector2, button: int) -> void:
	if b == null or field == null:
		return
	if button == 2:
		if ui.ability != null:
			ui.ability = null
		else:
			ui.selected = null
		_refresh_hover()
		notify()
		return
	if button != 0 or locked():
		return
	_pointer = p
	if b.phase == "player":
		_refresh_hover()
	var hv: Dictionary = ui.hover
	var rp := resolve_pointer(p)
	var t = rp.tile
	var u = rp.unit
	if t == null:
		return
	if b.phase == "deploy":
		if u != null and u.faction == "player":
			if ui.selected != null and ui.selected != u.uid:
				b.deploy_swap(ui.selected, t.x, t.y)
				_sync_views()
				ui.selected = null
			else:
				ui.selected = u.uid
			_sfx("select")
			notify()
		elif ui.selected != null and b.deploy_swap(ui.selected, t.x, t.y):
			_sync_views()
			_sfx("click")
			notify()
		return
	if b.phase != "player":
		return
	var sel = selected_unit()
	var spell_id = _aimed_spell(sel, u)
	if sel != null and spell_id != null:
		var at = _spell_aim(spell_id, t, u)
		if at != null and b.cast(sel.uid, spell_id, at):
			ui.ability = null
			pump()
			_after_player_action(sel)
			return
		if at != null and ui.ability != null:
			_sfx("deny")
			return
		if at == null and ui.ability != null:
			if u != null and u.faction == "player":
				select(u.uid)
			else:
				_sfx("deny")
			return
	if u != null and u.faction == "player":
		if sel != null and u.uid == sel.uid and hv.get("turn") and hv.get("facing") != null:
			# Step out and back to face the edge pointed at.
			b.move(sel.uid, sel.x, sel.y, hv.facing)
			pump()
			_after_player_action(sel)
			return
		select(u.uid)
		return
	if sel == null:
		return
	if u != null and u.faction == "enemy":
		var pv = hv.preview if (hv.get("preview") != null and hv.preview.target == u.uid) else _preview_against(sel, u)
		if pv == null or not pv.legal:
			_sfx("deny")
			return
		if pv.moveFirst and pv.get("from") != null:
			var same: bool = hv.get("dest") != null and hv.dest.x == pv.from.x and hv.dest.y == pv.from.y
			b.move(sel.uid, pv.from.x, pv.from.y, hv.facing if same else null)
			if sel.status == "active" and not sel.hasActed and b.preview(sel, u, {"ability": pv.ability} if pv.get("ability") != null else {}).legal:
				b.attack(sel.uid, u.uid, pv.get("ability"))
		else:
			b.attack(sel.uid, u.uid, pv.get("ability"))
		ui.ability = null
		pump()
		_after_player_action(sel)
		return
	if not sel.hasMoved and _reach(sel).has(Grid.key(t.x, t.y)) and not (t.x == sel.x and t.y == sel.y):
		var same: bool = hv.get("dest") != null and hv.dest.x == t.x and hv.dest.y == t.y
		b.move(sel.uid, t.x, t.y, hv.facing if same else null)
		pump()
		_after_player_action(sel)


## The keyboard commands of battle_view.gd, by input action.
func key_action(action: String, pressed: bool) -> void:
	if not pressed:
		if action == "show_danger":
			ui.danger = false
			notify()
		return
	match action:
		"facing_prev":
			cycle_facing(-1)
		"facing_next":
			cycle_facing(1)
		"select_next":
			select_next()
		"end_unit":
			end_unit()
		"end_turn":
			end_turn()
		"redo_move":
			redo()
		"cancel":
			ui.ability = null
			_refresh_hover()
			notify()
		"toggle_grid":
			ui.showGrid = not ui.showGrid
			notify()
		"show_danger":
			ui.danger = true
			notify()
		"ability_1", "ability_2", "ability_3", "ability_4":
			var n := int(action.substr(8))
			var u = selected_unit()
			if u != null:
				var list: Array = u.abilities.filter(func(a): return DB.is_active_ability(a))
				if n - 1 < list.size():
					set_ability(list[n - 1])


func _unhandled_input(event: InputEvent) -> void:
	if b == null or field == null:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_goal = clampf(_zoom_goal * 1.12, ZOOM_MIN, ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_goal = clampf(_zoom_goal / 1.12, ZOOM_MIN, ZOOM_MAX)
		elif event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if event.pressed:
				_dragging = true
				_drag_moved = 0.0
			else:
				_dragging = false
				if event.button_index == MOUSE_BUTTON_RIGHT and _drag_moved < 6.0:
					pointer_down(event.position, 2)
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			pointer_down(event.position, 0)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _dragging:
			_drag_moved += event.relative.length()
			if _drag_moved >= 6.0:
				_focus_goal = Vector3.INF
				_pan(event.relative)
		pointer_move(event.position)
	elif event is InputEventKey and not event.is_echo():
		for a in _ACTIONS:
			# Only the exact chord (Ctrl+Z for redo, plain keys otherwise).
			if not InputMap.event_is_action(event, a, true):
				continue
			if event.pressed:
				_held[a] = true
				key_action(a, true)
			elif _held.has(a):
				_held.erase(a)
				key_action(a, false)
			get_viewport().set_input_as_handled()
			return


func _input(event: InputEvent) -> void:
	# A drag ends on release anywhere (over the HUD too); Alt released anywhere ends the danger view.
	if event is InputEventMouseButton and not event.pressed and event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		if _dragging and _drag_moved >= 6.0:
			_dragging = false
	if event is InputEventKey and not event.pressed and _held.has("show_danger") and event.is_action("show_danger"):
		_held.erase("show_danger")
		key_action("show_danger", false)


func _pan(rel: Vector2) -> void:
	var k := 1.0 / (ppu * zoom)
	var right := Vector3(1, 0, -1).normalized()
	var down := Vector3(1, 0, 1).normalized()
	focus -= right * rel.x * k + down * rel.y * k / sin(deg_to_rad(ELEVATION))


## Bring tile (x, y) into view: when it is near the screen's edge, at most
## about once a second (a turn of many squads does not throw the camera
## about), or always when `force`.
func _focus_on(x: float, y: float, force: bool) -> void:
	if cam == null or field == null or not is_inside_tree():
		return
	var p := _tile_pos(x, y)
	var s := cam.unproject_position(p)
	var vs := get_viewport().get_visible_rect().size
	var off := not Rect2(vs * Vector2(0.2, 0.18), vs * Vector2(0.6, 0.6)).has_point(s)
	if force or (off and _focus_hold <= 0.0):
		_focus_goal = p + Vector3(0, 0.85, 0)
		if not force:
			_focus_hold = 1.1


# ---------------------------------------------------------------- frame

func _process(dt: float) -> void:
	if b == null or field == null:
		return
	dt = minf(dt, 0.05)
	var sdt := dt * speed
	if speed != _applied_speed:
		_applied_speed = speed
		for m in units:
			m.playback = _playback(m)
	for n in units:
		var at := Vector2(n.position.x, n.position.z)
		if _grounded.get(n, Vector2.INF) != at or n.position.y != _grounded_y.get(n, NAN):
			n.position.y = field.ground_y(at.x, at.y)
			_grounded[n] = at
			_grounded_y[n] = n.position.y
		_lie(n, dt)
	var keys := Vector2(Input.get_axis("cam_left", "cam_right"), Input.get_axis("cam_up", "cam_down"))
	if keys.length() > 0.0:
		_focus_goal = Vector3.INF
		_pan(-keys * 900.0 * dt)
	var old := zoom
	zoom = lerpf(zoom, _zoom_goal, minf(1.0, dt * 10.0))
	if absf(zoom - old) > 1e-4:
		_apply_look()
	for q in squads:
		q.tick(dt)
	for tm in _timers.duplicate():
		tm[0] -= sdt
		if tm[0] <= 0.0:
			_timers.erase(tm)
			tm[1].call()
	_step_texts(sdt)
	_poll_task()
	_step_anims(sdt)
	_next()
	_update_fog(dt)
	_sync_busy()
	_focus_hold = maxf(0.0, _focus_hold - dt)
	if _focus_goal != Vector3.INF:
		focus = focus.lerp(_focus_goal, minf(1.0, dt * 4.0))
		if focus.distance_to(_focus_goal) < 0.05:
			_focus_goal = Vector3.INF
	_place_camera()
	weather.follow(focus)
	_fade_t -= dt
	if _fade_t <= 0.0:
		_fade_t = 0.1
		_fade_crowns()
	_draw_rings()
	_draw_overlay()


## ui.busy follows locked(); when it clears the hover is worked out again.
func _sync_busy() -> void:
	var bz := locked()
	if bz != ui.busy:
		ui.busy = bz
		if not bz:
			_refresh_hover()
		notify()


func _place_camera() -> void:
	var lo := -3.0 * tile_m
	var hi := (Field.W + 2.0) * tile_m
	focus.x = clampf(focus.x, lo, hi)
	focus.z = clampf(focus.z, lo, hi)
	var el := deg_to_rad(ELEVATION)
	var d := Vector3(cos(el) * sin(PI / 4), sin(el), cos(el) * cos(PI / 4))
	cam.position = focus + d * CAM_DIST
	cam.look_at(focus, Vector3.UP)
	cam.size = get_viewport().get_visible_rect().size.y / (ppu * zoom)
	if not sun_shadows:
		sun.directional_shadow_max_distance = clampf(40.0 / zoom + 40.0, 40.0, 140.0)
		return
	# The sun's maps span the camera's depth (Godot takes an orthogonal camera's
	# near to far, not the light's max distance): the camera's depth is fitted
	# to the ground in view, `reach` either side of the focus along the view,
	# with room for the tallest trees and the weather over it.
	var reach := cam.size * 0.5 / tan(el)
	cam.near = maxf(CAM_DIST - reach - 30.0, 0.1)
	cam.far = CAM_DIST + reach + 15.0
	sun.directional_shadow_max_distance = cam.far


func _apply_look() -> void:
	var w := OUTLINE_PX / (ppu * zoom)
	for u in units:
		u.set_look("toon", true)
		u.set_outline_width(w)


## The ground's plane under a fallen body, so he lies on the slope (the sandbox's _lie).
func _lie(n: Node3D, dt: float) -> void:
	var w0: float = _lying.get(n, 0.0)
	var w := move_toward(w0, 1.0 if n.is_dead() else 0.0, dt / LIE_IN)
	if w == 0.0 and w0 == 0.0:
		return
	_lying[n] = w
	var p := n.global_position
	var up := Vector3(field.ground_y(p.x - LIE_R, p.z) - field.ground_y(p.x + LIE_R, p.z), 2.0 * LIE_R,
		field.ground_y(p.x, p.z - LIE_R) - field.ground_y(p.x, p.z + LIE_R)).normalized()
	up = n.global_basis.orthonormalized().transposed() * up
	n.model.quaternion = Quaternion.IDENTITY.slerp(Quaternion(Vector3.UP, up), w)


## The company's squads are the eyes (where their men stand as played back); a
## foe's squad shows when the rules revealed it or one of its men stands on
## ground they see (in the woods only close up), a fallen foe where they have looked.
func _update_fog(dt: float) -> void:
	if shroud == null:
		return
	var on: bool = b.fog_enabled()
	var eyes := []
	for v in views.values():
		if v.faction == "player" and v.sq != null and v.sq.standing() > 0 and v.status != "fled":
			var t: Vector2i = field.tile_of(v.sq.centroid())
			if field.in_field(t):
				eyes.append({"x": t.x, "y": t.y})
	shroud.update(eyes, dt)
	var seen := {}
	for v in views.values():
		if v.faction == "player":
			continue
		var shows: bool = not on or _revealed.has(v.uid) or _ended
		if v.sq != null and not shows:
			for m in v.sq.alive():
				if shroud.shows(field.tile_of(m.position)):
					shows = true
					break
		if shows and v.visible and not v.reserve:
			seen[v.uid] = true
		if v.sq == null:
			continue
		for m in v.sq.members:
			if not v.visible or v.reserve:
				m.visible = false
			elif m.is_dead():
				var t: Vector2i = field.tile_of(m.position)
				m.visible = not on or _ended or shroud.explored.has(Grid.key(t.x, t.y))
			else:
				m.visible = shows
	if seen != fog.visible_units:
		fog.visible_units = seen
		_danger_cache = null
		_refresh_hover()
		notify()


## Tree crowns fade while a figure stands behind them (the sandbox's _fade_crowns).
func _fade_crowns() -> void:
	var view_dir := Vector3(1, 0, 1).normalized()
	if _tree_cards.is_empty():
		_tree_cards = field.cards.filter(func(c): return String(c.kind).begins_with("tree") and c.has("half_w"))
	var cols := {}
	for u in units:
		if u.visible:
			var sh := cam.unproject_position(u.position + Vector3(0, u.height_m() * 0.6, 0))
			var k := floori(sh.x / FADE_COLUMN)
			if not cols.has(k):
				cols[k] = []
			cols[k].append([u.position, sh])
	for c in _tree_cards:
		var on := false
		var foot: Vector3 = c.foot
		var sf := cam.unproject_position(foot)
		var half: float = c.half_w * ppu * zoom * 0.8
		var top: float = c.top * ppu * zoom
		for k in range(floori((sf.x - half) / FADE_COLUMN), floori((sf.x + half) / FADE_COLUMN) + 1):
			for f in cols.get(k, []):
				if (f[0] - foot).dot(view_dir) > -0.3:
					continue
				var sh: Vector2 = f[1]
				if absf(sh.x - sf.x) < half and sh.y < sf.y + 4.0 and sh.y > sf.y - top:
					on = true
					break
			if on:
				break
		field.set_card_faded(c, on)


## Gold rings under the selected squad's men; under the squad pointed at, red
## for a foe the selected squad can attack (dim if it cannot), pale gold for
## another of the company's.
func _draw_rings() -> void:
	_ring_mesh.clear_surfaces()
	var rings := []
	var sel: View3D = views.get(ui.selected) if ui.selected != null else null
	if sel != null and sel.sq != null:
		for m in sel.sq.alive():
			rings.append([m.position, Color(1.0, 0.84, 0.4, 0.95), _ring_size(m)])
	var hv: View3D = views.get(ui.hover.get("unit")) if ui.hover.get("unit") != null else null
	if hv != null and hv != sel and hv.sq != null and squad_visible(hv):
		var col := Color(1.0, 0.84, 0.4, 0.45)
		if hv.faction != "player":
			var pv: Variant = ui.hover.get("preview")
			var sp: Variant = ui.hover.get("spell")
			var legal: bool = (pv != null and pv.get("legal", false)) or (sp != null and sp.get("legal", false))
			col = Color(1.0, 0.3, 0.22, 0.95) if legal else Color(0.85, 0.55, 0.5, 0.5)
		for m in hv.sq.alive():
			if m.visible:
				rings.append([m.position, col, _ring_size(m)])
	if rings.is_empty():
		return
	_ring_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rings:
		var col: Color = r[1]
		var pts := _ring_points(r[0], r[2])
		for i in range(0, pts.size() - 2, 2):
			for k in [0, 1, 3, 0, 3, 2]:
				_ring_mesh.surface_set_color(col)
				_ring_mesh.surface_add_vertex(pts[i + k])
	_ring_mesh.surface_end()


func _ring_size(u: Node3D) -> float:
	return 0.62 * clampf(u.height_m() / 1.7, 0.7, 1.5)


## A ring's points draped over the ground (sampled at eight points round it), kept while it stands still.
func _ring_points(c: Vector3, rad: float) -> PackedVector3Array:
	var key := Vector4(snappedf(c.x, 0.01), snappedf(c.y, 0.01), snappedf(c.z, 0.01), rad)
	if _ring_pts.has(key):
		return _ring_pts[key]
	if _ring_pts.size() > 160:
		_ring_pts.clear()
	var n := 40
	var m := 8
	var hs := PackedFloat32Array()
	for j in m:
		var a := TAU * j / m
		hs.append(field.ground_y(c.x + cos(a) * rad, c.z + sin(a) * rad) + 0.05)
	var pts := PackedVector3Array()
	for i in n + 1:
		var a := TAU * i / n
		var f := float(i * m) / n
		var j := int(f) % m
		var y := lerpf(hs[j], hs[(j + 1) % m], f - floorf(f))
		for rr in [rad - 0.07, rad]:
			pts.append(Vector3(c.x + cos(a) * rr, y, c.z + sin(a) * rr))
	_ring_pts[key] = pts
	return pts


## The tiles on the ground: where the selected squad can march (or deploy),
## an arrow at the tile it would arrive on, facing the way it would face; with
## Alt held where the enemies in sight can strike next turn; the march's path
## marked on the ground (dots, a ring at its end); the grid and the tile
## pointed at (the ground shader's grid_on and hover).
func _draw_overlay() -> void:
	var tiles: Array = []
	var col := REACH_COLOR
	var edge := REACH_EDGE
	var sel = selected_unit() if not locked() else null
	if sel != null and b.phase == "deploy":
		tiles = b.map.playerDeploy
		col = DEPLOY_COLOR
		edge = DEPLOY_EDGE
	elif sel != null and b.phase == "player" and not sel.hasMoved:
		for k in _reach(sel):
			tiles.append({"x": k % 1000, "y": floori(k / 1000.0)})
	var danger: Dictionary = _danger_tiles() if ui.danger and _task_id < 0 else {}
	var h: Dictionary = ui.hover
	var key := "%s|%s|%d|%s|%s|%d" % [b.phase, sel.uid if sel != null else "", tiles.size(), str(h.get("dest")), str(h.get("facing")), danger.size()]
	if key != _overlay_key:
		_overlay_key = key
		_overlay_mesh.clear_surfaces()
		if not tiles.is_empty() or not danger.is_empty() or h.get("dest") != null:
			_overlay_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			for k in danger:
				_tile_quad({"x": k % 1000, "y": floori(k / 1000.0)}, DANGER_COLOR)
			for t in tiles:
				_tile_quad(t, col)
				_tile_edge(t, edge)
			if h.get("dest") != null and h.get("facing") != null:
				_arrow(h.dest, int(h.facing))
			_overlay_mesh.surface_end()
	var marks := {}
	if h.get("path") != null:
		for p in h.path:
			marks[Vector2i(p.x, p.y)] = 1
	if h.get("dest") != null:
		marks[Vector2i(h.dest.x, h.dest.y)] = 2
	var mk := str(marks)
	if mk != _mark_key:
		_mark_key = mk
		field.mark(marks)
	field.mat.set_shader_parameter("grid_on", bool(ui.showGrid))
	var ht = h.get("tile")
	var lit: bool = ht != null and not locked() and b.phase in ["player", "deploy"]
	field.mat.set_shader_parameter("hover", Vector2(ht.x, ht.y) if lit else Vector2(-99, -99))


## Where the enemies in sight can strike next turn: next to every tile they
## can reach, within a shot's range of it, and a war machine's stones from
## where it stands (battle_draw.gd's _danger_tiles).
func _danger_tiles() -> Dictionary:
	if _danger_cache != null:
		return _danger_cache
	var out := {}
	var m: Dictionary = b.map
	for e in b.active("enemy"):
		if not unit_visible(e):
			continue
		var primary = DB.UNIT_TYPES.get(e.typeId, {}).get("primary")
		var lob = DB.ABILITIES.get(primary) if primary != null else null
		if lob != null and lob.get("range"):
			var lmin: float = lob.get("minRange", 1)
			for t in m.tiles:
				var dd := Grid.dist(t, e)
				if dd <= lob.range and dd >= lmin:
					out[Grid.key(t.x, t.y)] = true
		var reach: Dictionary = b.reachable_full(e)
		var shot = e.get("shot")
		for k in reach:
			var px: int = k % 1000
			var py: int = floori(k / 1000.0)
			for d in Grid.DIRS:
				if Grid.in_bounds(m, px + d.x, py + d.y):
					out[Grid.key(px + d.x, py + d.y)] = true
			if shot != null:
				var r: int = ceili(shot.range)
				for y in range(maxi(0, py - r), mini(m.h - 1, py + r) + 1):
					for x in range(maxi(0, px - r), mini(m.w - 1, px + r) + 1):
						var dd := Grid.hypot(float(x - px), float(y - py))
						if dd <= shot.range and dd >= shot.minRange:
							out[Grid.key(x, y)] = true
	_danger_cache = out
	return out


## A tile's square, inset a little, draped over the ground in 3 x 3 parts.
func _tile_quad(t: Dictionary, col: Color) -> void:
	var n := 3
	var s := (1.0 - 2.0 * TILE_INSET) / n
	for i in n:
		for j in n:
			var x0: float = t.x - 0.5 + TILE_INSET + i * s
			var y0: float = t.y - 0.5 + TILE_INSET + j * s
			_ground_quad([Vector2(x0, y0), Vector2(x0 + s, y0), Vector2(x0 + s, y0 + s), Vector2(x0, y0 + s)], col, 0.05)


## The light edge round a tile's square: a band along each side inside it,
## draped over the ground in three parts.
func _tile_edge(t: Dictionary, col: Color) -> void:
	var a := 0.5 - TILE_INSET
	var w := TILE_EDGE
	var c := Vector2(t.x, t.y)
	for side: Vector2 in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]:
		var along := Vector2(-side.y, side.x)
		for k in 3:
			var u0 := -a + 2.0 * a * k / 3.0
			var u1 := -a + 2.0 * a * (k + 1) / 3.0
			var o := c + side * a
			var i := c + side * (a - w)
			_ground_quad([o + along * u0, o + along * u1, i + along * u1, i + along * u0], col, 0.06)


## A quad of tile points (grid x, y) on the ground, `lift` metres above it.
func _ground_quad(c: Array, col: Color, lift: float) -> void:
	var p := []
	for q in c:
		p.append(field.on_ground(q) + Vector3(0, lift, 0))
	for k in [0, 1, 2, 0, 2, 3]:
		_overlay_mesh.surface_set_color(col)
		_overlay_mesh.surface_add_vertex(p[k])


## A chevron on tile `t` pointing the way `facing`.
func _arrow(t: Dictionary, facing: int) -> void:
	var d: Dictionary = Grid.DIRS[facing]
	var f := Vector2(d.x, d.y)
	var side := Vector2(-f.y, f.x)
	var c := Vector2(t.x, t.y)
	var tip := c + f * 0.42
	var back := c + f * 0.1
	var tri := [[tip, back + side * 0.3, back + side * 0.18 + f * 0.08], [tip, back + side * 0.18 + f * 0.08, back - side * 0.18 + f * 0.08], [tip, back - side * 0.18 + f * 0.08, back - side * 0.3]]
	for tr in tri:
		for q in tr:
			_overlay_mesh.surface_set_color(ARROW_COLOR)
			_overlay_mesh.surface_add_vertex(field.on_ground(q) + Vector3(0, 0.08, 0))


# ---------------------------------------------------------------- helpers

## _u(uid) through a uid index, rebuilt when `b` is swapped for a snapshot.
func _u(uid: String) -> Dictionary:
	if _ucache_b != b:
		_ucache.clear()
		_ucache_b = b
		for x in b.units:
			_ucache[x.uid] = x
	var u = _ucache.get(uid)
	if u == null:
		u = b.unit(uid)
		_ucache[uid] = u
	return u


## The Sfx autoload found at run time, or null (tools and tests that load the view first).
func _audio() -> Node:
	if _sfx_node == null or not is_instance_valid(_sfx_node):
		var ml := Engine.get_main_loop() as SceneTree
		_sfx_node = ml.root.get_node_or_null("Sfx") if ml != null else null
	return _sfx_node


func _sfx(n: String) -> void:
	var s := _audio()
	if s != null:
		s.play(n)


static func _first(arr: Array) -> Variant:
	return arr[0] if arr.size() > 0 else null
