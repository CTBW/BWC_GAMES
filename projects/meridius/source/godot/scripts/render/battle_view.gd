## The battlefield view. Port of src/render/battleScene.ts (class BattleScene).
##
## A Node2D that shows a Battle (scripts/rules/battle.gd), plays back its rule
## events and turns pointer/keyboard input on the world into battle commands.
## Rules run ahead of the animation: the view only plays back events, it never
## changes outcomes. Drawing lives in battle_draw.gd (render passes), the night
## and dawn light in battle_night.gd.
##
## ---------------------------------------------------------------- public API
## Create:   var view = preload("res://scenes/battle/battle_view.tscn").instantiate()
##           view.setup(battle)       # BattleScene constructor; before or after add_child
##           add_child(view)          # the view draws in its own local pixels at the
##                                    # viewport origin (1920×1080 or wider)
## Members (read; the HUD may also set ui.showGrid / ui.danger, then call notify()):
##   b: Battle                 the battle shown. While an enemy turn is being
##                             resolved on a worker thread, `b` is a frozen
##                             snapshot of the battle as it stood (safe to read;
##                             commands are refused while `busy`).
##   ui: Dictionary            BattleUiState. Keys are always present (null when unset):
##       selected: String|null       uid of the selected player squad
##       hover: Dictionary           HoverInfo, keys always present, null when unset:
##           tile {x,y}|null, unit uid|null, preview Dictionary|null (AttackPreview +
##           target, from {x,y}|null, ability|null, moveFirst), path Array|null,
##           zoc int|null, dest {x,y}|null, facing int|null, facings Array|null, turn bool|null,
##           spell Dictionary|null (SpellPreview: what the chosen spell, or a war
##           machine's stone, would do cast at the hovered tile; Battle.spell_preview)
##       ability: String|null        ability armed for the next click (a spell: aimed
##                                   by hovering, cast by clicking; self-target spells
##                                   cast at once from set_ability)
##       busy: bool                  playback (or the rules) still running
##       banner: Dictionary|null     {text, sub (String|null), tone "player"|"enemy"|"neutral", id}
##       log: Array                  [{text, tone|null}], newest first, ≤ 60
##       showGrid: bool, danger: bool, version: int (bumped by every notify())
##       turn: int, side: "player"|"enemy"   turn and side as played back so far
##   views: Dictionary         uid -> UnitView (fields hp, alive, morale, facing,
##                             status, stance, routing, visible, reserve, x, y,
##                             statuses (condition ids as played back), …):
##                             what the screen shows of each squad (follows playback).
##   atmo                      Atmosphere (set atmo.night = true for a night battle)
##   cam                       Camera (scripts/render/camera.gd)
##   speed: float              playback speed (prefs battleSpeed; the HUD toggles 1/2
##                             and stores it with Prefs.set_pref("battleSpeed", speed))
##   time_scale: float         extra multiplier for automation (engine.timeScale)
##   min_zoom: float, night_level: float, relief (Dictionary|null), corpses: Array
##   threaded_rules: bool      enemy turns / run_rules on a WorkerThreadPool task
##                             (default true; false runs them inline, e.g. tests)
##   auto_step: bool           _process steps the view (false: call step_frame yourself)
##   last_rules_ms, last_snapshot_ms: float   timings of the last rules task
## Signals:
##   ui_changed               every notify() (BattleScene.subscribe listeners)
##   ended(result: String)    the end has played ("victory" | "defeat" | "retreat")
## Methods (BattleScene in snake_case):
##   setup(battle) -> void, notify() -> void, busy() -> bool (getter `busy` in TS),
##   select(uid = null, say = true), set_ability(id = null), cycle_facing(dir: int ±1),
##   redo(uid = null), end_unit(), select_next(say = true), begin(), end_turn(), retreat(),
##   selected_unit() -> Dictionary|null, pump(), staged() -> Dictionary uid->dueIn,
##   next_wave_info() -> Dictionary|null {label, count, edge, dueIn, index, total},
##   minimap_rect() -> Dictionary {x, y, w, h, k, ox, oy},
##   run_rules(fn: Callable) -> void   run fn(b) (e.g. Ai.run_player_auto) like the
##                             AI turns: on a worker thread when threaded, then pump(),
##   rules_running() -> bool, advance(dt) -> void (one update, no drawing: tests),
##   step_frame(dt) -> void (update + camera + redraw; set auto_step = false first),
##   resolve_pointer(sx, sy), pointer_move(p: Vector2), pointer_down(p: Vector2, button),
##   wheel(delta), key_action(action: String, pressed: bool),
##   map_changed() (tiles edited by a tool: repaint the static layers),
##   relief_possible() -> bool.
## The HUD reads `b` for rules state (b.phase, b.active(), b.waves, b.wave_state,
## b.can_redo(uid), b.morale_state(u)…) and `views[uid]` for what is shown.
## Pointer coordinates are the view's local pixels (Camera.view_local(view, pos)).
## The minimap (large maps) sits bottom left at minimap_rect(): HUD controls
## there should let clicks through (mouse_filter IGNORE) so it can move the camera.
## Input (only events the UI did not consume, via _unhandled_input): left click
## select / move (pointing at a tile edge picks the arrival facing) / attack;
## right click cancels the ability, else the selection; right/middle drag pans;
## wheel zooms; actions facing_prev/next, select_next, end_unit, end_turn,
## redo_move, cancel, toggle_grid, show_danger (held), ability_1..4, cam_*.
extends Node2D

signal ui_changed
signal ended(result: String)

const JS = preload("res://scripts/core/js.gd")
const Rng = preload("res://scripts/core/rng.gd")
const Prefs = preload("res://scripts/core/prefs.gd")
const DB = preload("res://scripts/data/db.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const Squad = preload("res://scripts/rules/squad.gd")
const Mapgen = preload("res://scripts/rules/mapgen.gd")
const Iso = preload("res://scripts/render/iso.gd")
const Camera = preload("res://scripts/render/camera.gd")
const Formation = preload("res://scripts/render/formation.gd")
const SquadView = preload("res://scripts/render/squad_view.gd")
const SoldierAnim = preload("res://scripts/render/soldier_anim.gd")
const BattleDraw = preload("res://scripts/render/battle_draw.gd")
const BattleDeps = preload("res://scripts/render/battle_deps.gd")
const BattleLayer = preload("res://scripts/render/battle_layer.gd")
const BattleFog = preload("res://scripts/render/battle_fog.gd")
const BattleNight = preload("res://scripts/render/battle_night.gd")
const FxShader = preload("res://scenes/battle/battle_fx.gdshader")

const TW := 128
const TH := 64
const LH := 26

## Events that play alone: everything before them finishes first, nothing starts beside them.
const BARRIERS := {"turn": true, "end": true, "warn": true, "wave": true, "horn": true, "overrun": true, "broken": true, "relief": true}

## Morale changes that every squad gets at once: shown by banners and the log, not as floating numbers.
const QUIET_MORALE := {"Steadied": true, "Surrounded": true, "The battle is turning": true, "Another wave": true, "The warchief's host": true, "The war horn": true, "The horn is silenced": true, "Relief is near": true, "The warchief is slain": true}

## Most animations running at once (an enemy turn plays its squads side by side).
const MAX_ANIMS := 14

## A squad's steps are heard at most this often (s of battle time): about one
## man's step (SoldierAnim.STRIDE / 2), so a full squad is one tread, not twelve.
const STEP_BEAT := 0.19

## Labels and tints of lasting conditions.
const STATUS_COLOR := {"chilled": Color(0xbf / 255.0, 0xe6 / 255.0, 1.0), "bloodlust": Color(1.0, 0x6a / 255.0, 0x50 / 255.0), "bleeding": Color(1.0, 0x8a / 255.0, 0x7a / 255.0), "cowed": Color(0xd9 / 255.0, 0xb8 / 255.0, 1.0)}
const STATUS_LABEL := {"chilled": "CHILLED", "bloodlust": "FRENZY", "bleeding": "BLEEDING", "cowed": "COWED"}
const STANCE_NAME := {"shieldwall": "Shield Wall", "spearwall": "Spearwall", "overwatch": "Overwatch", "defend": "Defend", "square": "Square"}

## Colour of the damage numbers a spell throws up.
const SPELL_TEXT := {"lightning": "#d8ecff", "frost": "#cfeeff", "fire": "#ffc060", "gut": "#ff8a7a", "stone": "#ffffff", "rock": "#ffffff"}

## Where a spell's power gathers, by its look.
const SPELL_GLOW := {"lightning": "#8fc8ff", "frost": "#cfeeff", "heal": "#ffe48a", "circle": "#ffe48a", "fire": "#ff9a30", "blood": "#ff4030", "gut": "#c0ff60", "stone": "#c9b79a", "rock": "#c9b79a"}

const MORALE_COLORS := {
	"confident": Color8(0x9f, 0xe0, 0xff),
	"steady": Color8(0x6f, 0xb3, 0xff),
	"shaken": Color8(0xe5, 0xc3, 0x5a),
	"wavering": Color8(0xf0, 0x8a, 0x3c),
	"broken": Color8(0xe0, 0x55, 0x55),
}

## Grid facing of the step onto the field from beyond each edge.
const INWARD_DIR := {"n": 1, "w": 0, "e": 2, "s": 3}
const EDGE_NAME := {"n": "northern", "e": "eastern", "s": "southern", "w": "western"}

## Figures whose mirrored poses lead with the shield (figures.ts hasShieldPoses:
## a kite or round shield). Checked against the sprite registry when it has the key.
const SHIELD_TYPES := {"footman": true, "collie_guard": true, "orc_warrior": true}
## Squads that take the player's orders without a word (_say): the hounds.
const QUIET_TYPES := {"collie_guard": true}


## What the screen shows of a squad: one anchor on the grid (moved, turned and
## targeted as a single unit) and the soldiers standing around it.
class UnitView extends RefCounted:
	var uid := ""
	## Squad anchor on the grid (fractional while marching).
	var x := 0.0
	var y := 0.0
	var h := 0.0
	var facing := 0
	## Squad-wide jump (war cries).
	var hop := 0.0
	var shake := 0.0
	var alpha := 1.0
	## The soldiers; their offsets are relative to the anchor.
	var members: Array = []
	## Formation spacing: 1 normal, tighter behind a shield wall, ragged when fleeing.
	var tight := 1.0
	## Marching: time along the march and how strongly the stride shows (0..1).
	var walk_t := 0.0
	var walking := 0.0
	var marching := false
	var hp = 0
	## Soldiers shown standing; follows playback, not the rules (which run ahead).
	var alive := 0
	var morale = 0
	var status := "active"
	var stance = null
	var routing := false
	var visible := true
	## Still beyond the edge with a coming wave (drawn when the wave is near).
	var reserve := false
	## Conditions as played back (chilled, frenzied, bleeding).
	var statuses: Array = []
	## A war machine shows its loosing pose for this many seconds.
	var engine_atk := 0.0
	## Frame-animated soldiers: where the anchor was last frame (world px), so
	## the men can trail it (SoldierAnim.step_drift).
	var anchor_prev := Vector2.INF
	## The anchor's screen velocity last frame and the march's screen direction.
	var anchor_vel := Vector2.ZERO
	var heading := Vector2(1, 0.5).normalized()
	## Seconds since the squad's last step was heard (footfalls).
	var step_t := 0.0


## A fallen soldier left on the field.
class Corpse extends RefCounted:
	var wx := 0.0
	var wy := 0.0
	## Depth: under the living on the same tile.
	var d := 0.0
	var type := ""
	var variant := 0
	var flip := false
	var scale := 1.0


class Anim extends RefCounted:
	var t := 0.0
	var dur := 0.0
	var step: Callable
	var done: Callable
	var started := false
	var start: Callable
	## Squads this animation shows; later events about them wait for it.
	var uids: Array = []
	## Turn banners, waves and the end: nothing else plays alongside.
	var barrier := false
	## Seconds to wait before starting (a host's march sets off ragged, not in lockstep).
	var delay := 0.0


var b # Battle
var terrain # TerrainLayer (terrain.gd)
var cam: Camera
var views: Dictionary = {}
## Every soldier who has fallen this battle, where he fell.
var corpses: Array = []
var fx
var atmo
var ui: Dictionary = {
	"selected": null, "hover": {}, "ability": null, "busy": false, "banner": null, "log": [],
	"showGrid": true, "danger": false, "version": 0, "turn": 1, "side": "player",
}
## Battle playback speed, remembered between battles.
var speed: float = float(Prefs.prefs().battleSpeed)
## Simulation speed multiplier (play-test automation; engine.timeScale).
var time_scale := 1.0
var time := 0.0
var min_zoom := 0.45
## How dark it is in a battle fought through the night: 1 at midnight, 0 at sunrise.
var night_level := 0.0
## Cast shadows for every soldier even on large fields.
var rich_shadows := false
## Resolve enemy turns (and run_rules) on a WorkerThreadPool task while the view animates.
var threaded_rules := true
## Step from _process every frame (false: automation calls step_frame itself).
var auto_step := true
## Milliseconds the last rules task took (end_turn with the enemy AI, …), and
## the frozen copy made for the view on the main thread before it.
var last_rules_ms := 0.0
var last_snapshot_ms := 0.0
## The relief of a last stand: riders charging in with the sunrise (drawn only, no rules).
var relief = null
## A flash over the whole field (lightning, a fireball bursting): strength and colour.
var flash := {"a": 0.0, "color": Color.WHITE}

var _queue: Array = [] # [{e, uids}]
## The animation `_play` just created (moved into `_anims` by the scheduler).
var _anim: Anim = null
var _anims: Array = []
## Squads of the action whose consequences are being queued (morale, falls, logs follow it).
var _cause: Array = []
## Seconds before the camera may follow another action on its own.
var _focus_hold := 0.0
var _pointer := Vector2.ZERO
var _reach_cache = null
var _states_cache = null
## Facing picked with Q / E for one destination tile; pointing at another edge replaces it.
var _facing_pick = null
var _danger_cache = null
var _target_cache = null
## Targets of the chosen spell, cached per squad and spell.
var _spell_target_cache = null
var _w := 1920.0
var _h := 1080.0
var _banner_id := 0
## World rectangle the camera centre may roam, and the painted ground (the view never shows past it).
var _bounds := {"x0": 0.0, "y0": 0.0, "x1": 0.0, "y1": 0.0}
## Presentation-only border terrain and props; the battle map stays unchanged.
var surroundings := {}
var _ground := {"x0": 0.0, "y0": 0.0, "x1": 0.0, "y1": 0.0}
## The held ground is being overrun (shown until the company retakes it).
var _overrun_warn := false
var _ended := false
## The whole host is breaking (relief or warchief slain): one banner says it, not a float per squad.
var _horde_broken := false
## Squads staged this frame (staged() is asked by several passes).
var _staged_cache = null
## Pending "select the next squad once the playback is done" (afterPlayerAction).
var _select_after_idle := 0
## Rules running on a worker: the live battle and the task.
var _live_b = null
var _task_id := -1
var _task_t0 := 0
var _task_fn: Callable
var _is_setup := false
var _ucache := {}
var _ucache_b = null
var _sfx_node: Node = null
## Step event per unit type (step_<type> → step_<size> → step, the first the bank can play).
var _step_events := {}
## Sound per list of candidate names (_first_sound), "" when none can play.
var _sound_names := {}
## The last order answered (_say): no new answer while it still speaks.
var _said := ""
## Ambience preset this view asked for ("" until it is on screen).
var _ambience := ""
var _held := {}

# Layers (children), built in setup().
var _world: Node2D
var _layers := {}
var _draw: RefCounted
var fog: Node2D
var _night: Node2D
var _water: Node2D
var _minimap_key := ""
var _zone_red := false
## Opt-in test-field surface; production maps retain their original renderer.
var terrain_surface = null


# ---------------------------------------------------------------- construction

func setup(battle) -> void:
	b = battle
	var m: Dictionary = b.map
	_draw = BattleDraw.new(self)
	_w = _view_size().x
	_h = _view_size().y
	surroundings = BattleDeps.Surroundings.build(m)
	terrain = BattleDeps.build_ground(self, m)
	# Open a little closer than the whole map, leaning toward the company,
	# so the squads read as soldiers rather than specks. A last stand opens
	# wider, with the company's walls below and the enemy's ground above.
	var deploy: Array = m.playerDeploy if m.playerDeploy.size() > 0 else [{"x": (m.w - 1) / 2.0, "y": (m.h - 1) / 2.0}]
	var px := 0.0
	var py := 0.0
	for p in deploy:
		px += p.x
		py += p.y
	px /= deploy.size()
	py /= deploy.size()
	var large: bool = m.get("scale") == "large"
	var fxp := Iso.lerp((m.w - 1) / 2.0, px, 0.35 if large else 0.4)
	var fyp := Iso.lerp((m.h - 1) / 2.0, py, 0.35 if large else 0.4)
	cam = Camera.new(Iso.iso_x(fxp, fyp), Iso.iso_y(fxp, fyp) + 20, 0.72 if large else 1.0)
	_compute_bounds()
	if large:
		_frame_stand()
	fx = BattleDeps.make_fx()
	atmo = BattleDeps.make_atmosphere(m.seed)
	atmo.night = b.setup.get("darkness") == true
	if _objective().get("dawn"):
		night_level = 1.0
		atmo.night = true
	for u in b.units:
		views[u.uid] = _make_view(u)
	_warm_sprites()
	_is_setup = true
	_build_layers()
	if b.phase == "deploy":
		_banner("Deploy your company", "Click a squad, then a blue tile, to change the formation", "neutral")
		var first = _first(b.active("player"))
		if first != null:
			ui.selected = first.uid


func _ready() -> void:
	if _is_setup and _world == null:
		_build_layers()


func _enter_tree() -> void:
	# The battle's camera places its sounds (Sfx.play_at).
	var s := _audio()
	if s != null and s.has_method("set_listener"):
		s.set_listener(self)


func _exit_tree() -> void:
	var s := _audio()
	if s != null and s.has_method("clear_listener"):
		s.clear_listener(self)
		s.release_ambience(_ambience)
	_ambience = ""
	# A rules task must finish before the battle it works on goes away.
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		if _live_b != null:
			b = _live_b
			_live_b = null


## The map's tiles changed (props or heights; debug and review tools): paint
## the static layers again.
func map_changed() -> void:
	_draw._props.clear()
	for n in ["PropShadows", "Grid", "Zone", "ZoneDash"]:
		if _layers.has(n):
			_layers[n].queue_redraw()


## Start loading the figure atlases and prop sprites this battle draws (a
## figure atlas otherwise costs a 50–110 ms hitch on first use).
func _warm_sprites() -> void:
	var keys := {}
	var types := {}
	for u in b.units:
		types[u.typeId] = true
		var esc = DB.UNIT_TYPES.get(u.typeId, {}).get("escort")
		if esc != null:
			types[esc] = true
		var crew = DB.UNIT_TYPES.get(u.typeId, {}).get("crew")
		if crew != null:
			types[crew] = true
	if relief_possible():
		types["margrave_rider"] = true
	for t in types:
		SoldierAnim.warm(t)
		for pose in ["idle_f", "idle_b", "atk_f", "atk_b", "idle_fs", "idle_bs", "atk_fs", "atk_bs", "dead", "flee_b", "run_f", "run_b"]:
			keys["%s_%s" % [t, pose]] = true
	for t in b.map.tiles:
		if t.get("prop") != null:
			keys[BattleDraw._prop_sprite(t.prop)] = true
	for o in surroundings.props:
		keys[BattleDraw._prop_sprite(o.prop)] = true
	BattleDeps.warm(keys.keys())


## A dawn battle whose relief rides in (its riders are warmed up front).
func relief_possible() -> bool:
	return _objective().get("dawn") == true


## The layer stack, back to front (BattleScene.render's passes).
func _build_layers() -> void:
	if _world != null:
		return
	var bg := BattleLayer.new()
	bg.name = "Background"
	bg.draw_fn = _draw.draw_background
	add_child(bg)
	_layers["Background"] = bg
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	# The ground, with the forest ring painted into it once (bakeOuter).
	BattleDeps.attach_ground(self, _world, terrain)
	terrain.bake(_draw.draw_outer)
	_water = terrain.make_water_node("battle")
	_world.add_child(_water)
	BattleDeps.attach_clouds(self, _world, atmo)
	_add_layer(_world, "Grid", _draw.draw_grid, true)
	_add_layer(_world, "Zone", _draw.draw_zone_fill, true)
	_add_layer(_world, "ZoneDash", _draw.draw_zone_dashes, true)
	_add_layer(_world, "Under", _draw.draw_under)
	_add_layer(_world, "FxGround", _draw.draw_fx_ground)
	_add_layer(_world, "PropShadows", _draw.draw_prop_shadows, true)
	_add_layer(_world, "Sorted", _draw.draw_sorted)
	_add_layer(_world, "FxAir", _draw.draw_fx_air)
	# Glow, lightning and magic are light ('lighter'), drawn in order with the
	# rest of the air FX: the layer's material adds the draws flagged for it.
	var fx_mat := ShaderMaterial.new()
	fx_mat.shader = FxShader
	_layers.FxAir.material = fx_mat
	fx.additive = true
	# Lightning lights up the whole field for an instant; a fireball's burst warms it.
	_add_layer(self, "Flash", _draw.draw_screen_flash).material = fx_mat
	_night = BattleNight.new()
	_night.name = "Night"
	add_child(_night)
	_night.setup(self)
	fog = BattleFog.new()
	add_child(fog)
	fog.setup(self)
	_add_layer(self, "Overlays", _draw.draw_overlays)
	_add_layer(self, "MinimapBase", _draw.draw_minimap_base, true)
	_add_layer(self, "Minimap", _draw.draw_minimap)
	var texts := Node2D.new()
	texts.name = "TextWorld"
	add_child(texts)
	_layers["TextWorld"] = texts
	_add_layer(texts, "Texts", _draw.draw_texts)
	BattleDeps.attach_grade(self, atmo)
	_apply_camera()


func _add_layer(parent: Node, n: String, fn: Callable, static_draw := false) -> Node2D:
	var l := BattleLayer.new()
	l.name = n
	l.draw_fn = fn
	l.static_draw = static_draw
	parent.add_child(l)
	_layers[n] = l
	return l


## The field's corners (and the approaches beyond them) in world pixels, and the painted ground around it.
func _compute_bounds() -> void:
	var m: Dictionary = b.map
	var apps: Array = m.get("approaches", [])
	var pw := 4.0 if apps.has("w") else 0.5
	var pn := 4.0 if apps.has("n") else 0.5
	var pe := 4.0 if apps.has("e") else 0.5
	var ps := 4.0 if apps.has("s") else 0.5
	var f := _box([[-pw, -pn], [m.w - 1 + pe, -pn], [-pw, m.h - 1 + ps], [m.w - 1 + pe, m.h - 1 + ps]])
	_bounds = {"x0": f.x0, "y0": f.y0 - 120, "x1": f.x1, "y1": f.y1}
	var B: float = m.border - 0.5
	_ground = _box([[-B, -B], [m.w - 1 + B, -B], [-B, m.h - 1 + B], [m.w - 1 + B, m.h - 1 + B]])


func _box(pts: Array) -> Dictionary:
	var x0 := INF
	var y0 := INF
	var x1 := -INF
	var y1 := -INF
	for p in pts:
		var sx := Iso.iso_x(p[0], p[1])
		var sy := Iso.iso_y(p[0], p[1])
		x0 = minf(x0, sx)
		x1 = maxf(x1, sx)
		y0 = minf(y0, sy)
		y1 = maxf(y1, sy)
	return {"x0": x0, "y0": y0, "x1": x1, "y1": y1}


## Open a last stand on the whole confrontation: the company's ground and
## the horde's, centred between them and zoomed to fit both with room for
## the HUD (a wide view of the walls and what is coming at them).
func _frame_stand() -> void:
	var m: Dictionary = b.map
	var pts: Array = []
	pts.append_array(m.playerDeploy)
	pts.append_array(m.enemyDeploy)
	pts.append_array(m.get("zone", []))
	if pts.is_empty():
		return
	var x0 := INF
	var x1 := -INF
	var y0 := INF
	var y1 := -INF
	for p in pts:
		x0 = minf(x0, Iso.iso_x(p.x, p.y))
		x1 = maxf(x1, Iso.iso_x(p.x, p.y))
		y0 = minf(y0, Iso.iso_y(p.x, p.y))
		y1 = maxf(y1, Iso.iso_y(p.x, p.y))
	x0 -= 90
	x1 += 90
	y0 -= 140
	y1 += 50
	var vw := maxf(800, _w - 560)
	var vh := maxf(500, _h - 260)
	var z := Iso.clamp(minf(vw / (x1 - x0), vh / (y1 - y0)), 0.4, 0.8)
	cam.x = (x0 + x1) / 2
	cam.tx = cam.x
	cam.y = (y0 + y1) / 2 + 30 / z
	cam.ty = cam.y
	cam.zoom = z
	cam.tzoom = z


## Keep the camera over the field: its centre stays over the field and its
## view inside the painted ground. Zooming out stops when the field fits.
func _clamp_camera() -> void:
	var bd := _bounds
	var g := _ground
	var fit := minf(_w / (bd.x1 - bd.x0 + 160), _h / (bd.y1 - bd.y0 + 160))
	min_zoom = maxf(0.22, minf(0.45, fit))
	cam.tzoom = Iso.clamp(cam.tzoom, min_zoom, 1.6)
	var hw := _w / 2 / cam.tzoom
	var hh := _h / 2 / cam.tzoom
	cam.tx = _lim(cam.tx, bd.x0, bd.x1, g.x0, g.x1, hw)
	cam.ty = _lim(cam.ty, bd.y0, bd.y1, g.y0 - 200, g.y1, hh)


static func _lim(v: float, lo: float, hi: float, glo: float, ghi: float, half: float) -> float:
	var a := maxf(lo, glo + half)
	var z := minf(hi, ghi - half)
	return Iso.clamp(v, a, z) if a <= z else Iso.clamp(v, minf(lo, hi), maxf(lo, hi))


## Reserve squads of waves close enough to be seen massing beyond their edge, with turns until they march in.
func staged() -> Dictionary:
	if _staged_cache != null:
		return _staged_cache
	var out := {}
	var lead := 2 if b.map.get("scale") == "large" else 1
	var waves := _waves()
	for i in waves.size():
		var w: Dictionary = waves[i]
		if b.wave_state[i] == "cancelled":
			continue
		if w.get("horn") and b.horn != "sounded":
			continue
		var due_in: int = w.turn - ui.turn
		if due_in > lead:
			continue
		for uid in w.uids:
			var v: UnitView = views.get(uid)
			if v != null and v.reserve:
				out[uid] = maxi(0, due_in)
	_staged_cache = out
	return out


## The next wave as the HUD shows it: label, size, edge and turns until it marches in.
func next_wave_info() -> Variant:
	var n = b.next_wave()
	if n == null:
		return null
	var visible := []
	for w in _waves():
		if not w.get("horn") or b.horn == "sounded":
			visible.append(w)
	return {
		"label": n.wave.label,
		"count": n.wave.uids.size(),
		"edge": EDGE_NAME[n.wave.edge],
		"dueIn": maxi(0, n.turn - ui.turn),
		"index": visible.find(n.wave) + 1,
		"total": visible.size(),
	}


func _make_view(u: Dictionary) -> UnitView:
	var v := UnitView.new()
	v.uid = u.uid
	v.x = u.x
	v.y = u.y
	v.h = _tile_h(u.x, u.y)
	v.facing = u.facing
	v.members = SquadView.make_members(u)
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
	return v


## Re-form the squad's standing soldiers for its current number, facing and order.
func _reform_view(v: UnitView, opts: Dictionary = {}) -> void:
	var u: Dictionary = _u(v.uid)
	var o := {
		"typeId": u.typeId,
		"dur": JS.get_or(opts, "dur", 0.38),
		"stagger": JS.get_or(opts, "stagger", 0.035),
		"tight": v.tight,
		"champion": SquadView.champion_of(u),
		"spread": 0.35 if v.routing else 0.0,
	}
	if opts.has("delay"):
		o.delay = opts.delay
	if opts.get("instant"):
		o.instant = true
	SquadView.reform(v.members, u.size, v.facing, o)


## World position of one soldier (anchor + slot + lunge).
func _member_pos(v: UnitView, m) -> Vector2:
	var p := _view_pos(v)
	var q := Vector2(p.x + m.x + m.lunge.x + m.drift.x, p.y + m.y + m.lunge.y + m.drift.y)
	if m.alive and SoldierAnim.animated(m.type):
		var gp := SoldierAnim.pose(v, m, time)
		q += Vector2(gp.dx, gp.dy)
	q.y += member_ground_offset(v, q.x - p.x, q.y - p.y)
	return q


## A soldier's body comes to rest: it stays on the field where he fell.
func _add_corpse(v: UnitView, m) -> void:
	var u: Dictionary = _u(v.uid)
	var p := _member_pos(v, m)
	var c := Corpse.new()
	c.wx = p.x
	c.wy = p.y
	c.d = JS.rnd(v.x) + JS.rnd(v.y) - 0.3
	c.type = m.type
	c.variant = m.variant
	# A frame-animated man lies the way he fell, toward his squad's facing.
	c.flip = SoldierAnim.corpse_flip(SoldierAnim.facing_of(v, m)) if SoldierAnim.animated(m.type) else m.fall_flip
	c.scale = SquadView.member_scale(u)
	corpses.append(c)
	if corpses.size() > 160:
		corpses.pop_front()
	fx.burst(p.x, p.y, 1, 4, {"shape": "puff", "color": "rgba(170,150,110,1)", "speed": 40, "vz": 18, "gravity": 20, "size": 5, "max": 0.7})


## BattleScene.notify: bumps ui.version and tells every listener (signal ui_changed).
func notify() -> void:
	ui.version += 1
	ui_changed.emit()


func _banner(text: String, sub, tone: String) -> void:
	_banner_id += 1
	ui.banner = {"text": text, "sub": sub, "tone": tone, "id": _banner_id}
	notify()


# ---------------------------------------------------------------- commands (from UI)

## TS getter `busy`: animations, queued events, missiles in the air, or the rules still running.
func busy() -> bool:
	return _anims.size() > 0 or _queue.size() > 0 or BattleDeps.fx_busy(fx) or _task_id >= 0


## `say`: a squad that can still act answers ("Orders?"); not when the
## selection moves on by itself after an action.
func select(uid = null, say := true) -> void:
	var picked: bool = uid != null and uid != ui.selected
	if uid != null:
		var u: Dictionary = _u(uid)
		if u.faction != "player" or u.status != "active":
			return
		var v: UnitView = views[uid]
		_focus_on(v.x, v.y, false)
	ui.selected = uid
	ui.ability = null
	_reach_cache = null
	_states_cache = null
	_facing_pick = null
	_sfx("select")
	if picked and say and b.phase == "player" and not _u(uid).done:
		_say("select", uid)
	notify()


func set_ability(id = null) -> void:
	var u = selected_unit()
	if u == null or busy():
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
			# Cast where the casters stand: no aiming needed.
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


## Q / E: arrive on the previewed tile from another side. A squad faces the
## way it last stepped, so this picks another path to the same tile.
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


## Take back a soldier's move this turn (only before that soldier attacks).
func redo(uid = null) -> void:
	if uid == null:
		uid = ui.selected
	if busy() or uid == null:
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
	if u == null or busy():
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
	_run_battle(func(bb): bb.begin(BattleDeps.enemy_ai()))
	_sfx("horn")


func end_turn() -> void:
	if busy() or b.phase != "player":
		return
	ui.selected = null
	ui.ability = null
	_run_battle(func(bb): bb.end_turn(BattleDeps.enemy_ai()))


func retreat() -> void:
	if busy() or b.phase != "player":
		return
	b.retreat()
	pump()


func selected_unit() -> Variant:
	if ui.selected == null:
		return null
	var u: Dictionary = _u(ui.selected)
	return u if u.status == "active" else null


## Run `fn(b)` against the battle the way the enemy turns run (automation:
## Ai.run_player_auto), then play back what it did.
func run_rules(fn: Callable) -> void:
	if _task_id >= 0:
		return
	_run_battle(fn)


func rules_running() -> bool:
	return _task_id >= 0


## Run a rules step that may take long (the enemy AI) on a worker thread while
## the view keeps animating. Until it is done the view and the HUD see a
## frozen copy of the battle in `b`; the live battle is touched by the worker
## only. Then its events are pumped into the playback queue.
func _run_battle(fn: Callable) -> void:
	if not threaded_rules:
		var t0 := Time.get_ticks_usec()
		fn.call(b)
		last_rules_ms = (Time.get_ticks_usec() - t0) / 1000.0
		pump()
		return
	_live_b = b
	var t0 := Time.get_ticks_usec()
	b = _snapshot(_live_b)
	last_snapshot_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_task_fn = fn
	_task_t0 = Time.get_ticks_usec()
	_task_id = WorkerThreadPool.add_task(_task_body, false, "battle rules")
	ui.busy = true
	_reach_cache = null
	_states_cache = null
	_danger_cache = null
	_target_cache = null
	ui.hover = _empty_hover()
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


## A read-only copy of the battle as it stands: same script, its state
## deep-copied (the map and setup are never changed by the rules and are shared).
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


# ---------------------------------------------------------------- event playback

func pump() -> void:
	for e in b.drain():
		var involved := _involved(e)
		e["witnesses"] = involved
		_queue.append({"e": e, "uids": involved})
	_reach_cache = null
	_states_cache = null
	_danger_cache = null
	_target_cache = null
	_spell_target_cache = null
	ui.busy = busy()
	notify()


## The squads an event shows. Consequences (morale, falls, routs, log lines)
## also wait for the action that caused them, so a comrade's fall never
## shakes anyone before it is seen.
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


## Start queued events in order. Events about different squads may run side
## by side, so a host of thirty marches as one surge instead of one by one;
## events about the same squads, and barriers (turns, waves, the end), keep
## their order.
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
			if i > 0 or _anims.size() > 0:
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
			a.delay = a.delay + minf(0.6, started * 0.08)
			_anims.append(a)
			started += 1
			for u in uids:
				busy_u[u] = true


func _view_pos(v: UnitView) -> Vector2:
	return Vector2(Iso.iso_x(v.x, v.y), Iso.iso_y(v.x, v.y, v.h))


## Just above the heads of the squad's rear rank: bars and combat text sit here.
func _head_pos(v: UnitView) -> Vector2:
	var p := _view_pos(v)
	var top := INF
	for m in v.members:
		if m.alive:
			top = minf(top, m.y)
	if top == INF:
		top = 0.0
	return Vector2(p.x, p.y + minf(0.0, top) - SquadView.member_height(_type_of(v.uid)) - 24 - v.hop)


## Bring a point into view. `force` always pans (selecting a squad); other
## calls pan only when the point is near the screen edge, and at most about
## once a second, so a turn of many squads does not throw the camera around.
func _focus_on(x: float, y: float, force: bool) -> void:
	var wx := Iso.iso_x(x, y)
	var wy := Iso.iso_y(x, y)
	var s := cam.world_to_screen(wx, wy, _w, _h)
	var margin := 0.22
	var off := s.x < _w * margin or s.x > _w * (1 - margin) or s.y < _h * margin or s.y > _h * (1 - margin)
	if force or (off and _focus_hold <= 0):
		cam.tx = wx
		cam.ty = wy
		_clamp_camera()
		if not force:
			_focus_hold = 1.1


func _new_anim(dur: float, step: Callable = Callable(), done: Callable = Callable(), start: Callable = Callable()) -> Anim:
	var a := Anim.new()
	a.dur = dur
	a.step = step
	a.done = done
	a.start = start
	return a


func _play(e: Dictionary) -> void:
	if fog != null and fog.enabled():
		fog.refresh(0)
		if e.t == "log" and not e.get("witnesses", []).is_empty() and not e.witnesses.any(func(id): return squad_visible(views.get(id))):
			return
		if e.has("uid") and not squad_visible(views.get(e.uid)) and e.t not in ["move", "face", "spawn", "reveal", "horn", "broken"]:
			_play_unseen(e)
			return
	match e.t:
		"reveal":
			fog.reveal(e.uid)
		"sight_reset":
			fog.reset_side(e.faction)
		"log":
			ui.log.push_front({"text": e.text, "tone": e.get("tone")})
			if ui.log.size() > 60:
				ui.log.pop_back()
			notify()
		"turn":
			var is_player: bool = e.faction == "player"
			ui.turn = e.turn
			ui.side = e.faction
			_banner("Your Turn" if is_player else "Enemy Turn", "Turn %d" % e.turn, "player" if is_player else "enemy")
			_sfx("turn" if is_player else "drum")
			_anim = _new_anim(0.9)
			if is_player:
				var first = _first(b.active("player").filter(func(u): return not u.done))
				if first != null:
					ui.selected = first.uid
		"face":
			# The whole squad turns; the ranks shift their lean toward the new front.
			var v: UnitView = views[e.uid]
			if v.facing != e.facing:
				v.facing = e.facing
				_reform_view(v, {"dur": 0.28, "stagger": 0.025})
		"move":
			_play_move(e)
		"heal":
			var v: UnitView = views[e.uid]
			v.hp = e.hp
			var hp := _head_pos(v)
			var p := _view_pos(v)
			fx.text(hp.x, hp.y - 4, "+%s" % JS.num_str(e.amount), "#9ff08a", {"size": 22})
			fx.text(hp.x, hp.y - 30, e.reason, "#c8f0b0", {"size": 14, "bold": false, "delay": 0.1})
			fx.ring(p.x, p.y, 60, "rgba(150,240,120,0.8)", 0.6)
			# A troll's wounds closing, a hound licking its own (none for the others).
			_kind_sfx_at("mend", e.uid, p)
			for m in SquadView.standing(v.members):
				var q := _member_pos(v, m)
				fx.burst(q.x, q.y - 30, 0, 3, {"shape": "puff", "color": "rgba(150,230,110,1)", "speed": 20, "vz": 40, "gravity": -20, "size": 4, "max": 0.9})
			_anim = _new_anim(0.5)
		"attack":
			_play_attack(e)
		"spell":
			_play_spell(e)
		"status":
			var v: UnitView = views[e.uid]
			if e.on:
				if not v.statuses.has(e.status):
					v.statuses.append(e.status)
				var hp := _head_pos(v)
				var label: String = {"chilled": "Chilled", "bloodlust": "Bloodlust!", "bleeding": "Bleeding", "cowed": "Cowed"}.get(e.status, String(e.status).capitalize())
				fx.text(hp.x, hp.y - 36, label, STATUS_COLOR.get(e.status, Color.WHITE), {"size": 16, "delay": 0.05})
			else:
				v.statuses.erase(e.status)
		"dot":
			# The hex's wound opens again: blood, and soldiers may die of it.
			var v: UnitView = views[e.uid]
			v.hp = e.hp
			var hp := _head_pos(v)
			fx.text(hp.x, hp.y - 4, JS.num_str(e.damage), "#ff6a5a", {"size": 22})
			for m in SquadView.standing(v.members):
				var q := _member_pos(v, m)
				m.flash = maxf(m.flash, 0.3)
				m.shake = 0.6
				fx.burst(q.x, q.y - 24, 0, 5, {"shape": "spark", "colors": ["#b8291c", "#7d1a12", "#e05040"], "speed": 60, "vz": 30, "gravity": 240, "size": 2.6, "max": 0.5})
			_sfx_at("hit_flesh", _view_pos(v))
			_show_casualties(v, e.aliveBefore - e.aliveAfter, {"x": 0.0, "y": 1.0})
			_anim = _new_anim(0.55)
		"push":
			_play_push(e)
		"morale":
			var v: UnitView = views[e.uid]
			v.morale = e.value
			# Morale numbers only for the company, and only from the fighting: the
			# turn's upkeep and army-wide news (waves, horns) are told by banners.
			var quiet := QUIET_MORALE.has(e.reason)
			if absf(e.delta) >= 5 and not quiet and _u(e.uid).faction == "player":
				var hp := _head_pos(v)
				fx.text(hp.x, hp.y + 24, "%s%s morale" % ["+" if e.delta > 0 else "", JS.num_str(e.delta)], "#9fd8ff" if e.delta > 0 else "#c9a7ff", {"size": 13, "bold": false, "delay": 0.15, "life": 1.4})
		"mstate":
			var v: UnitView = views[e.uid]
			var worse := _rank(e.to) > _rank(e.from)
			var mine: bool = _u(e.uid).faction == "player"
			# Only bad news floats: a squad of the company shaken or wavering, or a band of the horde about to break.
			if e.to != "broken" and (worse if mine else e.to == "wavering"):
				var hp := _head_pos(v)
				fx.text(hp.x, hp.y - 50, _cap(e.to), "#" + MORALE_COLORS[e.to].to_html(false), {"size": 16, "delay": 0.35})
		"down":
			# The squad is destroyed: whoever is still standing falls now.
			var v: UnitView = views[e.uid]
			var u: Dictionary = _u(e.uid)
			var hp := _head_pos(v)
			v.status = "dead" if e.dead else "downed"
			v.stance = null
			v.statuses = []
			v.hp = 0
			var n := SquadView.standing(v.members).size()
			if n > 0:
				_show_casualties(v, n, {"x": 0.0, "y": -1.0})
			v.alive = 0
			if DB.is_engine(u.typeId):
				# With its crew dead the engine is wrecked where it stood.
				var ep := _view_pos(v)
				var o := Formation.engine_offset(v.facing)
				var c := Corpse.new()
				c.wx = ep.x + o.x
				c.wy = ep.y + o.y
				c.d = JS.rnd(v.x) + JS.rnd(v.y) - 0.2
				c.type = u.typeId
				c.variant = int(u.variant)
				c.flip = v.facing == 0 or v.facing == 2
				c.scale = SquadView.member_scale(u)
				corpses.append(c)
				fx.burst(ep.x, ep.y - 10, 4, 14, {"shape": "spark", "colors": ["#7a5532", "#5a3a22", "#c9ced4"], "speed": 130, "vz": 90, "gravity": 260, "size": 3, "max": 0.8})
				fx.burst(ep.x, ep.y, 6, 8, {"shape": "puff", "color": "rgba(170,150,110,1)", "speed": 50, "vz": 30, "gravity": 10, "size": 9, "max": 1.1})
				_sfx_at("crash", ep)
			var label := "Slain" if u.leader else ("Wiped out" if e.dead else "Broken")
			fx.text(hp.x, hp.y - 14, label, "#ff8a7a" if e.dead else "#ffd27a", {"size": 22})
			_kind_sfx_at("death", e.uid, _view_pos(v))
			var p := _view_pos(v)
			fx.ring(p.x, p.y, 70, "rgba(120,170,255,0.7)" if u.faction == "player" else "rgba(235,80,60,0.7)", 0.6)
			_anim = _new_anim(0.55)
			if u.faction == "player":
				cam.shake = 0.4
		"rout":
			# Order breaks: the ranks scatter and the soldiers turn to run.
			var v: UnitView = views[e.uid]
			v.routing = true
			v.stance = null
			v.tight = 1.0
			_reform_view(v, {"dur": 0.3, "stagger": 0.02})
			var hp := _head_pos(v)
			if not _horde_broken:
				fx.text(hp.x, hp.y - 18, "Routed!", "#f2efe4", {"size": 22})
				_kind_sfx_at("rout", e.uid, _view_pos(v))
			_anim = _new_anim(0.45, func(f): v.shake = (1 - f) * 0.6)
		"rally":
			var v: UnitView = views[e.uid]
			v.routing = false
			_reform_view(v, {"dur": 0.5, "stagger": 0.05})
			var hp := _head_pos(v)
			fx.text(hp.x, hp.y - 18, "Rallied!", "#9fe0ff", {"size": 20})
		"fled":
			var v: UnitView = views[e.uid]
			v.status = "fled"
			_anim = _new_anim(0.4, func(f): v.alpha = 1 - f, func(): v.visible = false)
		"stance":
			# A shield wall closes the ranks; set spears draw them in a little.
			var v: UnitView = views[e.uid]
			var st = e.get("stance")
			v.stance = st
			# A square packs its men tighter still, spears out on every side.
			var tight := 0.84 if st == "shieldwall" else (0.92 if st == "spearwall" else (0.8 if st == "square" else 1.0))
			if tight != v.tight:
				v.tight = tight
				_reform_view(v, {"dur": 0.3, "stagger": 0.03})
			if st != null:
				var hp := _head_pos(v)
				var nm: String = STANCE_NAME.get(st, String(st).capitalize())
				fx.text(hp.x, hp.y - 10, nm, "#e9d58f", {"size": 18})
				_kind_sfx_at("stance", e.uid, _view_pos(v), ["stance_" + str(st)])
				var p := _view_pos(v)
				fx.ring(p.x, p.y, 70, "rgba(240,220,150,0.9)", 0.5)
				_anim = _new_anim(0.35)
		"shout":
			var v: UnitView = views[e.uid]
			var p := _view_pos(v)
			var ab: Dictionary = DB.ABILITIES[e.ability]
			if e.ability == "lick_wounds":
				# Quiet: the hounds tend their wounds (the heal event that follows shows the healing).
				fx.text(p.x, p.y - 110, ab.name, "#c8f0b0", {"size": 20})
				_kind_sfx_at("lick", e.uid, p)
				_anim = _new_anim(0.5)
			elif e.ability == "growl" or e.ability == "howl":
				# Two tiles of menace, not four: a low purple shock wave and a roar.
				# Growl's rings are sized for its 2 tiles; Howl reaches 3.
				var k: float = float(ab.get("radius", 2)) / 2.0
				fx.ring(p.x, p.y, 150 * k, "rgba(170,110,230,0.9)", 0.8)
				fx.ring(p.x, p.y, 105 * k, "rgba(60,30,80,0.8)", 0.6)
				fx.text(p.x, p.y - 140, "%s!" % ab.name, "#d9b8ff", {"size": 26})
				cam.shake = 0.3
				_kind_sfx_at("roar", e.uid, p)
				_focus_on(v.x, v.y, true)
				_anim = _new_anim(0.8, func(f): v.hop = sin(f * PI) * 4)
			else:
				fx.ring(p.x, p.y, 260, "rgba(230,70,50,0.9)", 0.9)
				fx.ring(p.x, p.y, 180, "rgba(255,190,120,0.8)", 0.7)
				fx.text(p.x, p.y - 160, "%s!" % ab.name, "#ff9a7a", {"size": 26})
				cam.shake = 0.5
				_kind_sfx_at("warcry", e.uid, p)
				_focus_on(v.x, v.y, true)
				_anim = _new_anim(0.9, func(f): v.hop = sin(f * PI) * 10)
		"halt":
			var v: UnitView = views[e.uid]
			var hp := _head_pos(v)
			fx.text(hp.x, hp.y - 20, "Halted!", "#e9d58f", {"size": 18, "delay": 0.1})
		"warn":
			_banner("War horns!", "%s: %d squads reach the field from the %s edge at the end of this turn" % [e.label, e.count, EDGE_NAME[e.edge]], "enemy")
			_sfx("warhorn")
			_anim = _new_anim(1.1)
		"wave":
			_banner("The warchief comes!" if e.final else e.label, "%d more squads march onto the field from the %s edge" % [e.count, EDGE_NAME[e.edge]], "enemy")
			_sfx("warhorn")
			# The horde's roar, not a hound's growl (roar_<type> is the shout of one squad).
			_sfx(_first_sound(["roar_wave", "roar"]))
			cam.shake = maxf(cam.shake, 0.6 if e.final else 0.3)
			var ent = b.map.get("entries", {}).get(e.edge)
			if ent != null and ent.size() > 0:
				var c: Dictionary = ent[ent.size() / 2]
				_focus_hold = 0
				_focus_on(c.x, c.y, false)
			_anim = _new_anim(1.3)
		"spawn":
			# March in from the staging ground beyond the edge, straight onto the field.
			var v: UnitView = views[e.uid]
			v.reserve = false
			v.visible = true
			v.status = "active"
			v.alpha = 1.0
			v.x = e.from.x
			v.y = e.from.y
			v.h = 0.0
			var dx := signi(e.to.x - e.from.x)
			var dy := signi(e.to.y - e.from.y)
			var path: Array = [{"x": e.from.x, "y": e.from.y}]
			var cur := {"x": e.from.x, "y": e.from.y}
			var guard := 0
			while guard < 20 and (cur.x != e.to.x or cur.y != e.to.y):
				cur = {"x": cur.x + dx, "y": cur.y} if cur.x != e.to.x else {"x": cur.x, "y": cur.y + dy}
				path.append(cur)
				guard += 1
			if path.size() < 2:
				path.append({"x": e.to.x, "y": e.to.y})
			_play({"t": "move", "uid": e.uid, "path": path})
		"horn":
			var v: UnitView = views.get(e.uid)
			var p = _view_pos(v) if v != null else null
			if e.sounded:
				_banner("The war horn sounds!", "More of the horde will answer it next turn", "enemy")
				_sfx("warhorn")
				if p != null and squad_visible(v):
					fx.ring(p.x, p.y - 30, 200, "rgba(230,70,50,0.8)", 1.0)
					fx.ring(p.x, p.y - 30, 120, "rgba(255,190,120,0.7)", 0.8)
			else:
				_banner("The horn is silenced", "No help will come for them", "player")
				_sfx("horn")
			_anim = _new_anim(1.1)
		"overrun":
			_overrun_warn = true
			var zn = b.map.get("zoneName")
			_banner("The line is breaking!", "%s is overrun. Drive them out before their next turn ends." % (zn if zn != null else "The held ground"), "enemy")
			_sfx("drum")
			_anim = _new_anim(1.1)
		"broken":
			var v: UnitView = views.get(e.uid)
			var u: Dictionary = _u(e.uid)
			_horde_broken = true
			_banner("The horde breaks!", "%s is slain" % Squad.squad_name(u), "player")
			_sfx("relief")
			cam.shake = 0.7
			if squad_visible(v):
				var p := _view_pos(v)
				fx.ring(p.x, p.y, 320, "rgba(255,215,106,0.9)", 1.2)
				fx.ring(p.x, p.y, 200, "rgba(255,255,255,0.8)", 0.9)
			_anim = _new_anim(1.6)
		"relief":
			_horde_broken = true
			var dawn = _objective().get("dawn")
			_banner("Dawn!" if dawn else "Held!", e.text, "player")
			_sfx("relief")
			if dawn:
				# The riders crest the rise and charge before the horde breaks.
				_start_relief()
				_anim = _new_anim(3.4)
			else:
				_anim = _new_anim(1.8)
		"end":
			var result: String = e.result
			_anim = _new_anim(1.2, Callable(), func():
				_ended = true
				ended.emit(result))
			_banner("Victory" if result == "victory" else ("Withdrawal" if result == "retreat" else "Defeat"), null, "player" if result == "victory" else "enemy")
			_sfx("victory" if result == "victory" else "defeat")


## One path for the squad: the anchor walks it and every soldier keeps
## his place in the ranks, turning with the squad at each corner.
func _play_unseen(e: Dictionary) -> void:
	var uv = views.get(e.get("uid", ""))
	if uv == null:
		return
	match e.t:
		"heal", "dot":
			uv.hp = e.hp
			if e.has("aliveAfter"):
				_quiet_casualties(uv, e.aliveAfter)
		"status":
			if e.on and not uv.statuses.has(e.status):
				uv.statuses.append(e.status)
			elif not e.on:
				uv.statuses.erase(e.status)
		"morale":
			uv.morale = e.value
		"down":
			uv.status = "dead" if e.dead else "downed"
			uv.hp = 0
			uv.stance = null
			uv.statuses = []
			_quiet_casualties(uv, 0)
		"rout", "rally":
			uv.routing = e.t == "rout"
			uv.status = "routing" if uv.routing else "active"
			uv.stance = null
		"fled":
			uv.status = "fled"
			uv.visible = false
		"stance":
			uv.stance = e.get("stance")
		"push":
			_play_push(e)


func _quiet_casualties(uv, remaining: int) -> void:
	var count := 0
	for member in uv.members:
		if member.alive:
			count += 1
			if count > remaining:
				member.alive = false
	uv.alive = remaining


func _play_move(e: Dictionary) -> void:
	var v: UnitView = views[e.uid]
	var path: Array = e.path
	var steps := path.size() - 1
	var u: Dictionary = _u(e.uid)
	# Each kind keeps its own pace (soldier_anim.gd gait: heavy armour slower, goblins quicker).
	var ga := SoldierAnim.gait(_type_of(e.uid))
	var per: float = (0.15 if v.routing else (0.24 if u.faction == "enemy" else 0.26)) * ga.pace * ga.march
	var total: float = per * steps
	var st := {"last": -1}
	var last_pt: Dictionary = path[path.size() - 1]
	# A squad falling back off an ally's tile backs away, still facing its way.
	var backward: bool = e.get("backward", false)
	# Framed figures are heard by their planted feet (_footfalls); the rest by the tile.
	var tile_steps: bool = v.members.is_empty() or not SoldierAnim.animated(v.members[0].type)
	# The anchor sets off and halts over a moment (the men's spring does the rest:
	# they lag at the start and skid a little past the stop), and rounds its corners.
	var ease_in := minf(0.16, total * 0.25)
	var ease_out := minf(0.22, total * 0.3)
	var cruise: float = steps / maxf(0.001, total - 0.5 * ease_in - 0.5 * ease_out)
	var along := func(t: float) -> float:
		if t <= ease_in:
			return 0.5 * cruise * t * t / maxf(ease_in, 1e-6)
		if t >= total - ease_out:
			var r := total - t
			return steps - 0.5 * cruise * r * r / maxf(ease_out, 1e-6)
		return cruise * (t - 0.5 * ease_in)
	_anim = _new_anim(total,
		func(f):
			var pos: float = clampf(along.call(f * total), 0.0, steps)
			var i := mini(steps - 1, floori(pos))
			var k := pos - i
			var a: Dictionary = path[i]
			var bb: Dictionary = path[i + 1]
			var ha := _tile_h(a.x, a.y)
			var hb := _tile_h(bb.x, bb.y)
			var at := _path_point(path, pos)
			v.x = at.x
			v.y = at.y
			v.h = Iso.lerp(ha, hb, Iso.ease_in_out_quad(k)) + maxf(0.0, hb - ha) * sin(k * PI) * 0.4
			var dir := dir_of(a, bb)
			if dir != v.facing and not backward:
				_turn_ranks(v, dir, per)
				v.facing = dir
				_reform_view(v, {"dur": per * 0.8, "stagger": 0.02})
			if i != st.last:
				st.last = i
				if tile_steps and squad_visible(v):
					# Dust under every pair of boots, not one cloud for the squad.
					for m in SquadView.standing(v.members):
						if randf() < 0.5:
							continue
						var p := _member_pos(v, m)
						fx.burst(p.x, p.y, 1, 1, {"shape": "puff", "color": "rgba(190,165,120,1)", "speed": 18, "vz": 14, "gravity": 10, "size": 4, "max": 0.5})
					_sfx_at(_step_event(v.uid), _view_pos(v)),
		func():
			v.x = last_pt.x
			v.y = last_pt.y
			v.h = _tile_h(last_pt.x, last_pt.y)
			v.marching = false
			# Halt and dress the ranks.
			_reform_view(v, {"dur": 0.3, "stagger": 0.03}),
		func():
			v.marching = true
			for m in v.members:
				m.face = -1
				m.face_wait = 0.0
				m.face_t = 0.0
			if u.faction == "player":
				_focus_on(last_pt.x, last_pt.y, false))


## A point `pos` tiles along a path, its corners rounded (a quarter tile either
## side of each turn), so a squad wheels round a corner instead of snapping.
static func _path_point(path: Array, pos: float) -> Vector2:
	var steps := path.size() - 1
	var lin := func(q: float) -> Vector2:
		var j := clampi(floori(q), 0, steps - 1)
		var t := q - j
		var a: Dictionary = path[j]
		var b: Dictionary = path[j + 1]
		return Vector2(lerpf(a.x, b.x, t), lerpf(a.y, b.y, t))
	var c := roundi(pos)
	const R := 0.28
	if c > 0 and c < steps and absf(pos - c) < R:
		var p0: Dictionary = path[c - 1]
		var p1: Dictionary = path[c]
		var p2: Dictionary = path[c + 1]
		if (p1.x - p0.x) != (p2.x - p1.x) or (p1.y - p0.y) != (p2.y - p1.y):
			var s0: Vector2 = lin.call(c - R)
			var s1 := Vector2(p1.x, p1.y)
			var s2: Vector2 = lin.call(c + R)
			var t := (pos - (c - R)) / (2.0 * R)
			return s0.lerp(s1, t).lerp(s1.lerp(s2, t), t)
	return lin.call(pos)


## At a corner the men turn one by one, those nearest the new heading first,
## each on his own beat, instead of the whole squad flipping at once.
func _turn_ranks(v: UnitView, dir: int, per: float) -> void:
	var d: Dictionary = Grid.DIRS[dir]
	var hx := float(d.x - d.y) * 64.0
	var hy := float(d.x + d.y) * 32.0
	var order := SquadView.standing(v.members)
	JS.sort(order, func(p, q): return (q.x * hx + q.y * hy) - (p.x * hx + p.y * hy))
	for i in order.size():
		var m = order[i]
		if m.pose == "atk":
			continue
		m.face = v.facing
		m.face_wait = 0.0
		m.face_t = per * (0.08 + 0.09 * i) + fposmod(m.phase * 0.41, per * 0.12)


func _play_push(e: Dictionary) -> void:
	var v: UnitView = views[e.uid]
	var from := {"x": e.from.x, "y": e.from.y}
	var blocked: bool = e.blocked
	_anim = _new_anim(0.18 if blocked else 0.25,
		func(f):
			if blocked:
				v.shake = 1 - f
				return
			v.x = Iso.lerp(from.x, e.to.x, Iso.ease_out_cubic(f))
			v.y = Iso.lerp(from.y, e.to.y, Iso.ease_out_cubic(f)),
		func():
			v.x = e.to.x
			v.y = e.to.y
			v.h = _tile_h(e.to.x, e.to.y)
			var p := _view_pos(v)
			fx.burst(p.x, p.y, 4, 6, {"shape": "puff", "color": "rgba(190,165,120,1)", "speed": 60, "vz": 30, "gravity": 20, "size": 7, "max": 0.7})
			if blocked:
				fx.text(p.x, _head_pos(v).y, "Slammed!", "#ffd27a", {"size": 18})
				v.hp = e.hp
				_show_casualties(v, v.alive - e.alive, {"x": 0.0, "y": -1.0}))


## Soldiers of a squad fall to a blow coming from direction `from` (screen
## space, pointing from the squad toward the attacker). The nearest go down,
## then the survivors close up the ranks.
func _show_casualties(v: UnitView, count: int, from: Dictionary, opts: Dictionary = {}) -> Array:
	if count <= 0:
		return []
	var u: Dictionary = _u(v.uid)
	var fallen := SquadView.kill_members(v.members, count, from, SquadView.champion_of(u))
	for m in fallen:
		_fall_member(v, m)
	v.alive = SquadView.standing(v.members).size()
	if not opts.get("quiet", false) and fallen.size() > 0:
		var hp := _head_pos(v)
		fx.text(hp.x + 52, hp.y - 6, "%d slain" % fallen.size(), "#ff9a86", {"size": 16, "delay": 0.12})
	if v.alive > 0:
		_reform_view(v, {"delay": JS.get_or(opts, "reformDelay", 0.42 + fallen.size() * 0.07), "dur": 0.45, "stagger": 0.05})
	return fallen


## Blood and a grunt as one soldier goes down.
func _fall_member(v: UnitView, m) -> void:
	var p := _member_pos(v, m)
	fx.burst(p.x, p.y - 22, 0, 6, {"shape": "spark", "colors": ["#b8291c", "#7d1a12", "#e0a080"], "speed": 90, "vz": 50, "gravity": 220, "size": 2.4, "max": 0.4})


## Points between two squads on screen, for aiming lunges and missiles.
func _dir_between(a: UnitView, bv: UnitView) -> Dictionary:
	var ap := _view_pos(a)
	var bp := _view_pos(bv)
	var dx := bp.x - ap.x
	var dy := bp.y - ap.y
	var len := JS.hypot(dx, dy)
	if len == 0.0:
		len = 1.0
	return {"nx": dx / len, "ny": dy / len, "len": len}


## A ballista bolt carrying on through the squad it struck into the one behind.
func _play_through(e: Dictionary) -> void:
	var vv: UnitView = views[e.via]
	var tv: UnitView = views[e.target]
	var a := _view_pos(vv)
	var bp := _view_pos(tv)
	var nx := signf(bp.x - a.x)
	if nx == 0.0:
		nx = 1.0
	var ny := signf(bp.y - a.y)
	var from := {"x": -nx, "y": -ny}
	var victims := _pick_victims(tv, maxi(0, e.aliveBefore - e.aliveAfter), from)
	var dur := Iso.clamp(a.distance_to(bp) / 1400, 0.08, 0.22)
	fx.shoot({
		"x0": a.x,
		"y0": a.y - 22,
		"x1": bp.x,
		"y1": bp.y - 22,
		"t": 0.0,
		"dur": dur,
		"arc": 0.0,
		"kind": "bolt",
		"scale": 1.5,
		"onHit": func():
			tv.hp = e.targetHp
			var head := _head_pos(tv)
			fx.text(head.x, head.y - 4, JS.num_str(e.damage), "#ffffff", {"size": 26})
			fx.text(head.x, head.y - 34, "Run through!", "#ffd27a", {"size": 15, "delay": 0.05})
			for m in SquadView.standing(tv.members):
				m.flash = maxf(m.flash, 0.42)
				m.shake = 1.0
			_sfx_at("bolt_hit", bp)
			for m in victims:
				_drop_victim(tv, m, from)
			_after_casualties(tv, victims.size()),
	})
	_anim = _new_anim(dur + 0.35)


func _play_attack(e: Dictionary) -> void:
	if e.get("via") != null:
		_play_through(e)
		return
	var av: UnitView = views[e.uid]
	var tv: UnitView = views[e.target]
	var attacker: Dictionary = _u(e.uid)
	var target: Dictionary = _u(e.target)
	if target.faction == "player" or attacker.faction == "player":
		_focus_on((av.x + tv.x) / 2, (av.y + tv.y) / 2, false)
	var reaction = e.get("reaction")
	if reaction != null:
		var label := "Free attack" if reaction == "zoc" else ("Spearwall!" if reaction == "spearwall" else ("Overwatch!" if reaction == "overwatch" else "First strike!"))
		var hp := _head_pos(av)
		fx.text(hp.x, hp.y - 6, label, "#e9d58f", {"size": 16})
	# A guard (Defend) steps in and takes the blow meant for its ward.
	var ward = e.get("ward")
	if ward != null and views.has(ward):
		var wp := _view_pos(views[ward])
		var gh := _head_pos(tv)
		fx.text(gh.x, gh.y - 20, "Guarded!", "#e9d58f", {"size": 18})
		fx.ring(wp.x, wp.y, 60, "rgba(240,220,150,0.9)", 0.5)
		_sfx_at("block", wp)
	var dbt := _dir_between(av, tv)
	var nx: float = dbt.nx
	var ny: float = dbt.ny
	var len: float = dbt.len
	var killed := maxi(0, e.aliveBefore - e.aliveAfter)
	# The damage was rolled once by the rules; the animation only shows it.
	var shown := {"v": false}
	var armored: bool = target.stats.armor >= 2
	var show_hit := func():
		if shown.v:
			return
		shown.v = true
		tv.hp = e.targetHp
		var head := _head_pos(tv)
		var tp := _view_pos(tv)
		if e.hit:
			fx.text(head.x, head.y - 4, JS.num_str(e.damage), "#ffb347" if e.arc == "rear" else "#ffffff", {"size": 26 if e.arc == "front" else 30})
			if e.arc != "front":
				fx.text(head.x, head.y - 34, "Rear!" if e.arc == "rear" else "Flank!", "#ffb347", {"size": 15, "delay": 0.05})
			cam.shake = maxf(cam.shake, 0.4 if killed >= 2 else (0.28 if e.damage >= 30 else 0.16))
			_sfx_at("bolt_hit" if e.ranged else ("hit_metal" if armored else "hit_flesh"), tp)
			# The whole squad flinches.
			for m in SquadView.standing(tv.members):
				m.flash = maxf(m.flash, 0.42)
				m.shake = 1.0
				m.lunge = Vector2(nx * 4, ny * 2.5)
		else:
			var blocked: bool = not e.ranged and e.arc == "front" and target.shieldFront > 0
			fx.text(head.x, head.y - 4, "Blocked" if blocked else "Miss", "#c8c8c8", {"size": 20})
			if blocked:
				fx.burst(tp.x - nx * 30, tp.y - 26 - ny * 16, 0, 10, {"shape": "spark", "colors": ["#ffffff", "#ffe9a8"], "speed": 150, "vz": 40, "size": 2.5, "max": 0.35})
				_sfx_at("block", tp)
			else:
				_sfx_at("miss", tp)
			# Sidestep.
			for m in SquadView.standing(tv.members):
				m.lunge = Vector2(-ny * 6 * (1 if m.id % 2 else -1), nx * 3)
	var strikers := SquadView.standing(av.members)
	# Front rank first: the soldiers nearest the enemy act first and reach furthest.
	var order := strikers.duplicate()
	JS.sort(order, func(p, q): return q.x * nx + q.y * ny - (p.x * nx + p.y * ny))
	# The rules keep the squad's facing (its flanks and rear stay where they were),
	# but the men turn to face the enemy they strike or shoot at, and turn back after.
	if not DB.is_engine(attacker.typeId):
		SoldierAnim.turn_to(av, order, dir_of({"x": av.x, "y": av.y}, {"x": tv.x, "y": tv.y}))
	if e.ranged:
		_play_volley(e, av, tv, order, killed, show_hit, nx, ny, len)
		return
	if not order.is_empty() and SoldierAnim.animated(order[0].type):
		_play_drilled_melee(e, av, tv, order, killed, show_hit, nx, ny, armored)
		return
	# Melee: a ripple of blows from front to back. Each soldier winds up,
	# lunges and recovers on his own beat; the squad's damage lands once.
	var beat := 0.05
	var wind := 0.14
	var strike := 0.1
	var recover := 0.34
	var total := (order.size() - 1) * beat + wind + strike + recover
	var impact_at := wind + strike
	var reach: Array = []
	for i in order.size():
		reach.append(30.0 if i < ceili(order.size() / 2.0) else 17.0)
	# Casualties fall one by one as the blows land along the line.
	var from := {"x": -nx, "y": -ny}
	var victims := _pick_victims(tv, killed, from) if killed > 0 else []
	var st := {"next": 0, "swung2": false}
	_kind_sfx_at("swing", e.uid, _view_pos(av))
	# A war wagon lurches into its ram as the crew shove.
	if DB.is_engine(attacker.typeId):
		av.engine_atk = total
		_kind_sfx_at("smash", e.uid, _view_pos(av))
	_anim = _new_anim(total,
		func(f):
			var t: float = f * total
			for i in order.size():
				var m = order[i]
				var lt: float = t - i * beat
				var L: float = reach[i]
				if lt < 0:
					continue
				if lt < wind:
					m.pose = "atk"
					var k: float = lt / wind
					m.lunge = Vector2(-nx * 7 * k, -ny * 4 * k)
				elif lt < wind + strike:
					var k: float = (lt - wind) / strike
					m.lunge = Vector2(Iso.lerp(-nx * 7, nx * L, Iso.ease_out_cubic(k)), Iso.lerp(-ny * 4, ny * L * 0.55, Iso.ease_out_cubic(k)))
				else:
					var k: float = minf(1.0, (lt - wind - strike) / recover)
					m.lunge = Vector2(nx * L * (1 - Iso.ease_out_cubic(k)), ny * L * 0.55 * (1 - Iso.ease_out_cubic(k)))
					if k >= 1:
						m.pose = "idle"
			if t >= impact_at:
				if not shown.v:
					show_hit.call()
					if e.hit:
						var tp := _view_pos(tv)
						if armored:
							fx.burst(tp.x - nx * 24, tp.y - 26 - ny * 12, 0, 16, {"shape": "spark", "colors": ["#fff6c8", "#ffd27a", "#ffffff"], "speed": 180, "vz": 60, "gravity": 200, "size": 3, "max": 0.45})
						else:
							fx.burst(tp.x - nx * 24, tp.y - 26 - ny * 12, 0, 10, {"shape": "spark", "colors": ["#d64a3a", "#a3261c", "#f2c0a0"], "speed": 180, "vz": 60, "gravity": 200, "size": 3, "max": 0.45})
				# One victim per landing blow, front rank first.
				while st.next < victims.size() and t >= impact_at + st.next * beat * 1.4:
					_drop_victim(tv, victims[st.next], from)
					st.next += 1
			if not st.swung2 and order.size() > 3 and t >= impact_at + beat * 2:
				st.swung2 = true
				_kind_sfx_at("swing", e.uid, _view_pos(av))
			for m in SquadView.standing(tv.members):
				m.lunge *= 0.88,
		func():
			show_hit.call()
			while st.next < victims.size():
				_drop_victim(tv, victims[st.next], from)
				st.next += 1
			_after_casualties(tv, victims.size())
			for m in order:
				m.pose = "idle"
				m.lunge = Vector2.ZERO
			SoldierAnim.turn_back(order)
			for m in SquadView.standing(tv.members):
				m.lunge = Vector2.ZERO)


## Frame-animated swordsmen (SoldierAnim: the footmen). Every man winds up,
## cuts, holds the blow and recovers on his own beat, the front rank first and
## a little ragged; he steps back into the wind-up and forward into the cut.
## The squad's damage still lands once, with the first blow, and the fallen
## drop one by one as later blows land.
func _play_drilled_melee(e: Dictionary, av: UnitView, tv: UnitView, order: Array, killed: int, show_hit: Callable, nx: float, ny: float, armored: bool) -> void:
	var front := ceili(order.size() / 2.0)
	var beats: Array = []
	var lands: Array = []
	var total := 0.0
	# Bigger figures step further into the blow.
	var size_k := SquadView.member_height(order[0].type) / 49.0
	for i in order.size():
		var bt := SoldierAnim.melee_beat(i, front, order[i])
		bt.reach = (22.0 if i < front else 13.0) * size_k
		beats.append(bt)
		lands.append(bt.start + bt.wind + bt.cut)
		total = maxf(total, bt.start + bt.wind + bt.cut + bt.hold + bt.back)
	lands.sort()
	var impact_at: float = lands[0]
	var from := {"x": -nx, "y": -ny}
	var victims := _pick_victims(tv, killed, from) if killed > 0 else []
	var st := {"next": 0, "swung": 0, "hit": false}
	_anim = _new_anim(total,
		func(f):
			var t: float = f * total
			for i in order.size():
				var m = order[i]
				var bt: Dictionary = beats[i]
				var lt: float = t - bt.start
				if lt < 0:
					continue
				var L: float = bt.reach
				var back := Vector2(-nx * 6, -ny * 3.5)
				var fwd := Vector2(nx * L, ny * L * 0.55)
				if lt < bt.wind:
					m.pose = "atk"
					m.key = "wind"
					m.lunge = back * Iso.ease_in_out_quad(lt / bt.wind)
				elif lt < bt.wind + bt.cut:
					if m.key != "hit":
						m.key = "hit"
						# The first cut and one in the second rank are heard.
						if st.swung == 0 or (st.swung == 1 and i >= front):
							st.swung += 1
							_kind_sfx_at("swing", e.uid, _view_pos(av))
					m.lunge = back.lerp(fwd, Iso.ease_out_cubic((lt - bt.wind) / bt.cut))
				elif lt < bt.wind + bt.cut + bt.hold:
					m.key = "hit"
					m.lunge = fwd * (1.0 - 0.12 * (lt - bt.wind - bt.cut) / bt.hold)
				else:
					var k := minf(1.0, (lt - bt.wind - bt.cut - bt.hold) / bt.back)
					m.lunge = fwd * 0.88 * (1.0 - Iso.ease_out_cubic(k))
					if k > 0.3:
						m.pose = "idle"
						m.key = ""
			if t >= impact_at:
				if not st.hit:
					st.hit = true
					show_hit.call()
					if e.hit:
						var tp := _view_pos(tv)
						if armored:
							fx.burst(tp.x - nx * 24, tp.y - 26 - ny * 12, 0, 16, {"shape": "spark", "colors": ["#fff6c8", "#ffd27a", "#ffffff"], "speed": 180, "vz": 60, "gravity": 200, "size": 3, "max": 0.45})
						else:
							fx.burst(tp.x - nx * 24, tp.y - 26 - ny * 12, 0, 10, {"shape": "spark", "colors": ["#d64a3a", "#a3261c", "#f2c0a0"], "speed": 180, "vz": 60, "gravity": 200, "size": 3, "max": 0.45})
				# One victim per landing blow; more than there are blows fall
				# just after the last.
				while st.next < victims.size() and t >= (lands[st.next] if st.next < lands.size() else lands[lands.size() - 1] + (st.next - lands.size() + 1) * 0.06):
					_drop_victim(tv, victims[st.next], from)
					st.next += 1
			for m in SquadView.standing(tv.members):
				m.lunge *= 0.88,
		func():
			show_hit.call()
			while st.next < victims.size():
				_drop_victim(tv, victims[st.next], from)
				st.next += 1
			_after_casualties(tv, victims.size())
			for m in order:
				m.pose = "idle"
				m.key = ""
				m.lunge = Vector2.ZERO
			SoldierAnim.turn_back(order)
			for m in SquadView.standing(tv.members):
				m.lunge = Vector2.ZERO)


## The soldiers a blow from `from` will kill, chosen now and dropped as the blows land.
func _pick_victims(v: UnitView, count: int, from: Dictionary) -> Array:
	var u: Dictionary = _u(v.uid)
	var live := SquadView.standing(v.members)
	var champ := SquadView.champion_of(u)
	var order := live.duplicate()
	JS.sort(order, func(a, q):
		var pa: float = -1e6 if a.id == champ else a.to_x * from.x + a.to_y * from.y * 2
		var pb: float = -1e6 if q.id == champ else q.to_x * from.x + q.to_y * from.y * 2
		return pb - pa)
	return order.slice(0, mini(count, live.size()))


func _drop_victim(v: UnitView, m, from: Dictionary) -> void:
	if not m.alive:
		return
	var len := JS.hypot(from.x, from.y)
	if len == 0.0:
		len = 1.0
	m.alive = false
	m.dying = true
	m.death_t = 0.0
	m.death_delay = 0.0
	m.flash = 1.0
	m.pose = "idle"
	m.lunge = Vector2((-from.x / len) * 6, (-from.y / len) * 3.5)
	m.fall_flip = from.x > 0
	v.alive = SquadView.standing(v.members).size()
	_fall_member(v, m)


## After the last body drops: a casualty count, then the ranks close up.
func _after_casualties(v: UnitView, count: int) -> void:
	if count <= 0:
		return
	var hp := _head_pos(v)
	if v.alive > 0:
		fx.text(hp.x + 52, hp.y - 6, "%d slain" % count, "#ff9a86", {"size": 16, "delay": 0.05})
		_reform_view(v, {"delay": 0.45, "dur": 0.45, "stagger": 0.05})


## Missile troops loose together: each surviving archer or crossbowman fires
## his own shot, a beat apart, at a soldier of the target squad. Shots that
## miss stick in the ground around them. Casualties drop as their shots land.
func _play_volley(e: Dictionary, av: UnitView, tv: UnitView, order: Array, killed: int, show_hit: Callable, nx: float, ny: float, len: float) -> void:
	var attacker: Dictionary = _u(e.uid)
	if DB.is_engine(attacker.typeId):
		_play_engine_shot(e, av, tv, order, killed, show_hit, nx, ny, len)
		return
	# Mages and shamans loose bolts of their own power between spells.
	var caster: bool = attacker.get("tags", []).has("caster")
	var glow := "#8fc8ff" if attacker.faction == "player" else "#a6ff5a"
	var bolt: bool = attacker.typeId == "crossbowman"
	var flight := Iso.clamp(len / 1000, 0.2, 0.55)
	var aim := 0.34 if caster else 0.24
	var beat := 0.07 if bolt else (0.09 if caster else 0.05)
	var shooters: Array = []
	for i in order.size():
		shooters.append({"m": order[i], "at": aim + i * beat + randf() * 0.02, "fired": false})
	var from := {"x": -nx, "y": -ny}
	var victims := _pick_victims(tv, killed, from) if killed > 0 else []
	var targets := SquadView.standing(tv.members)
	var total := aim + (shooters.size() - 1) * beat + flight + 0.3
	_sfx_at("cast" if caster else ("crossbow" if bolt else "bow"), _view_pos(av))
	var st := {"volley_sound": false}
	_anim = _new_anim(total,
		func(f):
			var t: float = f * total
			for i in shooters.size():
				var s: Dictionary = shooters[i]
				var m = s.m
				if t < s.at:
					# Raise and draw.
					m.pose = "atk"
					m.key = "wind"
					var k := minf(1.0, t / aim)
					m.lunge = Vector2(-nx * 3 * k, -ny * 2 * k)
					continue
				if not s.fired:
					s.fired = true
					# Frame-animated archers show the loose, then lower the bow.
					m.key = "hit"
					m.lunge = Vector2(-nx * 5, -ny * 3)
					var fp := _member_pos(av, m)
					# Hits fly at the soldiers who will fall first, then at the rest.
					var to: Vector2
					var victim = victims[i] if (e.hit and i < victims.size()) else null
					if e.hit:
						var tm = victim if victim != null else (targets[(i * 3 + 1) % maxi(1, targets.size())] if targets.size() > 0 else null)
						var q := _member_pos(tv, tm) if tm != null else _view_pos(tv)
						to = Vector2(q.x + (randf() - 0.5) * 6, q.y - 18 - randf() * 10)
					else:
						var q := _view_pos(tv)
						to = Vector2(q.x + (randf() - 0.5) * 90, q.y + (randf() - 0.5) * 34)
					var shot := {
						"x0": fp.x + nx * 8,
						"y0": fp.y - (40 if caster else 28),
						"x1": to.x,
						"y1": to.y,
						"t": 0.0,
						"dur": flight * (0.92 + randf() * 0.16),
						"arc": len * 0.05 if (bolt or caster) else len * 0.16,
						"kind": "orb" if caster else ("bolt" if bolt else "arrow"),
						"scale": 0.8 if caster else 0.62,
						"stick": not e.hit and not caster,
						"onHit": func():
							show_hit.call()
							if caster:
								fx.burst(to.x, to.y, 0, 6, {"shape": "glow", "color": glow, "speed": 70, "vz": 0, "gravity": 0, "size": 3, "max": 0.35})
							if victim != null:
								_drop_victim(tv, victim, from),
					}
					if caster:
						shot.color = glow
					fx.shoot(shot)
					if caster:
						fx.burst(fp.x + nx * 8, fp.y - 40, 0, 5, {"shape": "glow", "color": glow, "speed": 40, "vz": 0, "gravity": 0, "size": 3, "max": 0.3})
					if not st.volley_sound and i == shooters.size() / 2 and shooters.size() > 2:
						st.volley_sound = true
						_sfx_at("crossbow" if bolt else "bow", _view_pos(av))
				else:
					m.lunge *= 0.86
					if t > s.at + 0.3 and SoldierAnim.animated(m.type):
						m.pose = "idle"
						m.key = ""
			for m in SquadView.standing(tv.members):
				m.lunge *= 0.9,
		func():
			show_hit.call()
			# Any casualty whose shot was not assigned (more dead than shooters) drops now.
			for vm in victims:
				_drop_victim(tv, vm, from)
			_after_casualties(tv, victims.size())
			for s in shooters:
				s.m.pose = "idle"
				s.m.key = ""
				s.m.lunge = Vector2.ZERO
			SoldierAnim.turn_back(order)
			for m in SquadView.standing(tv.members):
				m.lunge = Vector2.ZERO)


## A ballista looses: the crew heave on the windlass, the arms snap forward
## and one great bolt flies. Everyone it kills drops as it lands.
func _play_engine_shot(e: Dictionary, av: UnitView, tv: UnitView, crew: Array, killed: int, show_hit: Callable, nx: float, ny: float, len: float) -> void:
	var aim := 0.34
	var flight := Iso.clamp(len / 1500, 0.16, 0.42)
	var from := {"x": -nx, "y": -ny}
	var victims := _pick_victims(tv, killed, from) if killed > 0 else []
	var total := aim + flight + 0.4
	var st := {"fired": false}
	_anim = _new_anim(total,
		func(f):
			var t: float = f * total
			for m in crew:
				m.pose = "atk" if t < aim + 0.12 else "idle"
				m.key = "wind" if t < aim else ("hit" if t < aim + 0.12 else "")
			if st.fired or t < aim:
				return
			st.fired = true
			av.engine_atk = 0.6
			var p := _view_pos(av)
			var o := Formation.engine_offset(av.facing)
			var x0: float = p.x + o.x + nx * 20
			var y0: float = p.y + o.y - 24 + ny * 10
			var tp := _view_pos(tv)
			var to := Vector2(tp.x, tp.y - 22) if e.hit else Vector2(tp.x + (randf() - 0.5) * 120, tp.y + (randf() - 0.5) * 44)
			_sfx_at("ballista", p)
			cam.shake = maxf(cam.shake, 0.12)
			fx.burst(p.x + o.x, p.y + o.y, 0, 6, {"shape": "puff", "color": "rgba(190,165,120,1)", "speed": 40, "vz": 20, "gravity": 10, "size": 6, "max": 0.6})
			fx.shoot({
				"x0": x0,
				"y0": y0,
				"x1": to.x,
				"y1": to.y,
				"t": 0.0,
				"dur": flight,
				"arc": len * 0.03,
				"kind": "bolt",
				"scale": 1.5,
				"stick": not e.hit,
				"onHit": func():
					show_hit.call()
					if not e.hit:
						return
					fx.burst(to.x, to.y, 0, 10, {"shape": "spark", "colors": ["#d64a3a", "#a3261c", "#c9a27a"], "speed": 170, "vz": 60, "gravity": 220, "size": 3, "max": 0.5})
					for m in victims:
						_drop_victim(tv, m, from),
			}),
		func():
			show_hit.call()
			for m in victims:
				_drop_victim(tv, m, from)
			_after_casualties(tv, victims.size())
			for m in crew:
				m.pose = "idle")


## Where a caster's power gathers: the head of his staff.
func _staff_tip(v: UnitView, m) -> Vector2:
	var q := _member_pos(v, m)
	var side := -1.0 if (v.facing == 1 or v.facing == 2) else 1.0
	return Vector2(q.x + side * 7, q.y - SquadView.member_height(_type_of(v.uid)) - 6)


## The ground point of a tile (world px).
func _ground_pt(p: Dictionary) -> Vector2:
	return Vector2(Iso.iso_x(p.x, p.y), Iso.iso_y(p.x, p.y, _tile_h(p.x, p.y)))


## The view of the squad standing on a tile (as the rules have it now), else `fallback`.
func _view_at(p: Dictionary, fallback: UnitView) -> UnitView:
	var u = Grid.unit_at(b.units, p.x, p.y)
	if u != null and views.has(u.uid):
		return views[u.uid]
	return fallback


## A spell or a war machine's stone, from the casters' wind-up to every
## squad it reaches. The rules rolled each squad's damage once; this only
## shows it, at the moment the effect arrives there.
func _play_spell(e: Dictionary) -> void:
	var ab: Dictionary = DB.ABILITIES[e.ability]
	var av: UnitView = views[e.uid]
	var caster: Dictionary = _u(e.uid)
	var kind: String = ab.get("fx", "lightning")
	var engine := DB.is_engine(caster.typeId)
	var casters := SquadView.standing(av.members)
	var ap := _view_pos(av)
	var aim_pt := _ground_pt(e.at)
	# Casters (or a crew's men) turn toward where the spell goes; an engine keeps its line.
	if not DB.is_engine(caster.typeId) and (e.at.x != av.x or e.at.y != av.y):
		SoldierAnim.turn_to(av, casters, dir_of({"x": av.x, "y": av.y}, e.at))
	var imp_pt := _ground_pt(e.get("impact", e.at))
	var hits: Array = e.hits
	var hviews: Array = []
	var any_player: bool = caster.faction == "player"
	for h in hits:
		hviews.append(views[h.uid])
		if _u(h.uid).faction == "player":
			any_player = true
	var body := func(v: UnitView) -> Vector2:
		var p := _view_pos(v)
		return Vector2(p.x, p.y - 24)
	if any_player:
		_focus_on((av.x + e.at.x) / 2.0, (av.y + e.at.y) / 2.0, false)
	var glow: String = SPELL_GLOW.get(kind, "#ffffff")
	# State the steps share (lambdas capture locals by value).
	var st := {"applied": {}, "done": 0, "fired": false, "landed": false, "started": false, "lashed": false, "struck": false}
	var apply := func(i: int) -> void:
		if st.applied.has(i) or i >= hits.size():
			return
		st.applied[i] = true
		var h: Dictionary = hits[i]
		var tp := _view_pos(hviews[i])
		var src: Vector2 = ap if (h.role == "main" or h.role == "aura") else imp_pt
		var l := src.distance_to(tp)
		if l == 0.0:
			l = 1.0
		_apply_spell_hit(e, h, {"x": (src.x - tp.x) / l, "y": (src.y - tp.y) / l})
	var apply_all := func() -> void:
		for i in hits.size():
			apply.call(i)
	# Frame-animated casters gather power, then cast at the release.
	var pose := func(on: bool, cast := false) -> void:
		for m in casters:
			m.pose = "atk" if on else "idle"
			m.key = ("hit" if cast else "wind") if on else ""
	var gather := func(amount: float) -> void:
		if engine:
			return
		for m in casters:
			if randf() > amount:
				continue
			var s := _staff_tip(av, m)
			fx.burst(s.x + (randf() - 0.5) * 6, s.y + (randf() - 0.5) * 6, 0, 1, {"shape": "glow", "color": glow, "speed": 18, "vz": 0, "gravity": -30, "size": 2.6, "max": 0.45})
	var total := 1.0
	var step := func(_t: float) -> void:
		pass
	if not engine:
		_sfx_at("cast", ap)

	if kind == "lightning":
		var at := 0.5
		var gap := 0.16
		total = at + gap * maxi(1, hits.size()) + 0.45
		step = func(t: float) -> void:
			pose.call(t < at + 0.35, t >= at)
			if t < at:
				gather.call(0.7)
				return
			if not e.hit and st.done == 0:
				st.done = 1
				var miss := Vector2(aim_pt.x + (randf() - 0.5) * 70, aim_pt.y + (randf() - 0.5) * 26)
				for m in casters:
					var s := _staff_tip(av, m)
					fx.lightning(s.x, s.y, miss.x, miss.y, {"width": 2.4})
				fx.mark(miss.x, miss.y, "scorch", 0.5)
				flash = {"a": 0.6, "color": Color8(170, 200, 255)}
				_sfx_at("lightning", miss)
				var head := _head_pos(_view_at(e.at, av))
				fx.text(head.x, head.y - 4, "Miss", "#c8c8c8", {"size": 20})
				return
			while e.hit and st.done < hits.size() and t >= at + gap * st.done:
				var to: Vector2 = body.call(hviews[st.done])
				if st.done == 0:
					for m in casters:
						var s := _staff_tip(av, m)
						fx.lightning(s.x, s.y, to.x, to.y, {"width": 2.8, "branches": 2})
					flash = {"a": 1.0, "color": Color8(170, 200, 255)}
					cam.shake = maxf(cam.shake, 0.3)
				else:
					var fr: Vector2 = body.call(hviews[st.done - 1])
					fx.lightning(fr.x, fr.y, to.x, to.y, {"width": 2.2, "branches": 1})
					flash = {"a": maxf(flash.a, 0.5), "color": Color8(170, 200, 255)}
				fx.burst(to.x, to.y, 0, 14, {"shape": "glow", "color": "#bcd8ff", "speed": 150, "vz": 0, "gravity": 0, "size": 3, "max": 0.35})
				fx.mark(to.x, to.y + 24, "scorch", 0.55)
				_sfx_at("lightning", to)
				apply.call(st.done)
				st.done += 1
	elif kind == "frost":
		var at := 0.4
		var flight := 0.32
		total = at + flight + 0.55
		step = func(t: float) -> void:
			pose.call(t < at + 0.3, t >= at)
			if t < at:
				gather.call(0.7)
				return
			if not st.fired:
				st.fired = true
				for m in casters:
					for k in 2:
						var s := _staff_tip(av, m)
						var spread := 26.0 if e.hit else 90.0
						fx.shoot({"x0": s.x, "y0": s.y, "x1": aim_pt.x + (randf() - 0.5) * spread, "y1": aim_pt.y - 16 + (randf() - 0.5) * spread * 0.4, "t": 0.0, "dur": flight * (0.85 + randf() * 0.3), "arc": 18.0, "kind": "shard", "scale": 1.0})
			if not st.landed and t >= at + flight:
				st.landed = true
				_sfx_at("frost", aim_pt)
				if not e.hit:
					var head := _head_pos(_view_at(e.at, av))
					fx.text(head.x, head.y - 4, "Miss", "#c8c8c8", {"size": 20})
					return
				fx.ring(aim_pt.x, aim_pt.y, 110, "rgba(200,235,255,0.95)", 0.7)
				fx.burst(aim_pt.x, aim_pt.y - 20, 0, 26, {"shape": "glow", "colors": ["#e8f6ff", "#9fd8ff", "#ffffff"], "speed": 170, "vz": 0, "gravity": 30, "size": 3, "max": 0.6})
				fx.burst(aim_pt.x, aim_pt.y - 10, 0, 14, {"shape": "spark", "colors": ["#ffffff", "#cfeeff"], "speed": 200, "vz": 80, "gravity": 260, "size": 2.4, "max": 0.5})
				for hv in hviews:
					var p := _view_pos(hv)
					fx.mark(p.x, p.y, "frost", 1.1, 20)
				flash = {"a": 0.45, "color": Color8(210, 240, 255)}
				apply_all.call()
	elif kind == "heal" or kind == "circle":
		var at := 0.3 if kind == "circle" else 0.38
		total = at + 0.12 * hits.size() + 0.6
		step = func(t: float) -> void:
			pose.call(t < at + 0.4, t >= at)
			if t < at:
				gather.call(0.6)
				return
			if not st.started:
				st.started = true
				_sfx_at("heal", ap)
				if kind == "circle":
					fx.ring(ap.x, ap.y, TW * 2.2, "rgba(255,225,140,0.9)", 0.9)
					fx.ring(ap.x, ap.y, TW * 1.4, "rgba(255,245,200,0.7)", 0.7)
			while st.done < hits.size() and t >= at + 0.12 * st.done:
				var hv: UnitView = hviews[st.done]
				var p := _view_pos(hv)
				fx.ring(p.x, p.y, 70, "rgba(255,230,150,0.85)", 0.6)
				# Light falls on every soldier of the squad.
				for m in SquadView.standing(hv.members):
					var q := _member_pos(hv, m)
					fx.burst(q.x, q.y - 50, 0, 4, {"shape": "glow", "colors": ["#fff2b0", "#c8ff9a"], "speed": 12, "vz": 0, "gravity": -40, "size": 3, "max": 0.9})
				apply.call(st.done)
				st.done += 1
	elif kind == "fire":
		var at := 0.42
		var l := imp_pt.distance_to(ap)
		var flight := Iso.clamp(l / 700, 0.35, 0.8)
		total = at + flight + 0.65
		var explode := func() -> void:
			flash = {"a": 0.9, "color": Color8(255, 170, 80)}
			cam.shake = maxf(cam.shake, 0.5)
			fx.ring(imp_pt.x, imp_pt.y, 130, "rgba(255,150,60,0.9)", 0.6)
			fx.burst(imp_pt.x, imp_pt.y - 16, 0, 36, {"shape": "glow", "colors": ["#ffe080", "#ff9a30", "#ff5a20"], "speed": 190, "vz": 0, "gravity": -40, "size": 4.5, "max": 0.6})
			fx.burst(imp_pt.x, imp_pt.y - 10, 0, 16, {"shape": "spark", "colors": ["#ffd27a", "#ff7a2a"], "speed": 230, "vz": 120, "gravity": 300, "size": 2.6, "max": 0.6})
			fx.burst(imp_pt.x, imp_pt.y - 20, 10, 10, {"shape": "puff", "colors": ["rgba(60,48,40,1)", "rgba(90,80,70,1)"], "speed": 50, "vz": 40, "gravity": -20, "size": 14, "max": 1.6})
			fx.mark(imp_pt.x, imp_pt.y, "scorch", 1.6, 40)
			_sfx_at("explosion", imp_pt)
			apply_all.call()
		step = func(t: float) -> void:
			pose.call(t < at + 0.25, t >= at)
			if t < at:
				gather.call(0.8)
				return
			if st.fired:
				return
			st.fired = true
			_sfx_at("fireball", ap)
			var s: Vector2 = _staff_tip(av, casters[floori(casters.size() / 2.0)]) if casters.size() > 0 else Vector2(ap.x, ap.y - 40)
			fx.shoot({"x0": s.x, "y0": s.y, "x1": imp_pt.x, "y1": imp_pt.y - 14, "t": 0.0, "dur": flight, "arc": l * 0.22 + 20, "kind": "fireball", "scale": 1.1, "onHit": explode})
	elif kind == "blood" or kind == "gut":
		var at := 0.4
		var strike := 0.62
		total = 1.15
		var tv: UnitView = hviews[0] if hviews.size() > 0 else _view_at(e.at, av)
		step = func(t: float) -> void:
			pose.call(t < strike + 0.2, t >= strike)
			if t < at:
				gather.call(0.8)
				return
			if not st.lashed:
				st.lashed = true
				_sfx_at("bloodlust" if kind == "blood" else "hex", _view_pos(tv))
				var to: Vector2 = body.call(tv)
				for m in casters:
					var s := _staff_tip(av, m)
					var end := Vector2(to.x + (randf() - 0.5) * 18, to.y + (randf() - 0.5) * 10)
					if kind == "blood":
						fx.tendril(s.x, s.y, end.x, end.y, {"color": "#d8261a", "core": "#ffb08a", "dark": "#4a0606", "width": 2.2, "amp": 10, "life": 0.6})
					else:
						fx.tendril(s.x, s.y, end.x, end.y, {"color": "#7a1424", "core": "#c8ff70", "dark": "#1e0408", "width": 2.8, "amp": 16, "life": 0.65})
			if st.struck or t < strike:
				return
			st.struck = true
			if not e.hit:
				var head := _head_pos(tv)
				fx.text(head.x, head.y - 4, "Resisted", "#c8c8c8", {"size": 20})
				return
			var p := _view_pos(tv)
			if kind == "blood":
				fx.ring(p.x, p.y, 80, "rgba(255,60,40,0.9)", 0.7)
				for m in SquadView.standing(tv.members):
					var q := _member_pos(tv, m)
					fx.burst(q.x, q.y - 30, 0, 5, {"shape": "glow", "colors": ["#ff4030", "#ff9a60"], "speed": 30, "vz": 0, "gravity": -50, "size": 3, "max": 0.8})
			else:
				for m in SquadView.standing(tv.members):
					var q := _member_pos(tv, m)
					fx.burst(q.x, q.y - 28, 0, 9, {"shape": "spark", "colors": ["#b8291c", "#7d1a12", "#e05040"], "speed": 120, "vz": 70, "gravity": 260, "size": 3, "max": 0.55})
				fx.burst(p.x, p.y - 26, 0, 12, {"shape": "glow", "colors": ["#c0ff60", "#ff5040"], "speed": 80, "vz": 0, "gravity": 0, "size": 3, "max": 0.45})
			apply_all.call()
	else:
		# A war machine's stone: the arm swings, the stone tumbles high and smashes down.
		var at := 0.32
		var l := imp_pt.distance_to(ap)
		var flight := Iso.clamp(l / 600, 0.7, 1.3)
		total = at + flight + 0.7
		var crash := func() -> void:
			cam.shake = maxf(cam.shake, 0.5)
			flash = {"a": maxf(flash.a, 0.25), "color": Color8(255, 235, 200)}
			fx.ring(imp_pt.x, imp_pt.y, 150, "rgba(160,130,90,0.9)", 0.7)
			fx.ring(imp_pt.x, imp_pt.y, 90, "rgba(240,225,190,0.8)", 0.5)
			fx.burst(imp_pt.x, imp_pt.y, 8, 22, {"shape": "puff", "colors": ["rgba(170,150,110,1)", "rgba(130,110,80,1)", "rgba(200,185,150,1)"], "speed": 150, "vz": 60, "gravity": 15, "size": 17, "max": 1.5})
			fx.burst(imp_pt.x, imp_pt.y - 6, 0, 26, {"shape": "spark", "colors": ["#8a8378", "#5a4a38", "#c9b79a", "#3a2c1e"], "speed": 280, "vz": 170, "gravity": 400, "size": 4.2, "max": 0.8})
			# Chunks of the stone bounce away.
			fx.burst(imp_pt.x, imp_pt.y - 4, 4, 6, {"shape": "dot", "colors": ["#7d7568", "#9a9184"], "speed": 170, "vz": 150, "gravity": 420, "size": 5, "max": 0.9})
			fx.mark(imp_pt.x, imp_pt.y, "crater", 1.6, 60)
			_sfx_at("crash", imp_pt)
			apply_all.call()
		step = func(t: float) -> void:
			for m in casters:
				m.pose = "atk" if t < at + 0.1 else "idle"
				m.key = "wind" if t < at else ("hit" if t < at + 0.1 else "")
			if st.fired or t < at:
				return
			st.fired = true
			av.engine_atk = 0.8
			_sfx_at("catapult", ap)
			var o := Formation.engine_offset(av.facing)
			var d: Dictionary = Grid.DIRS[av.facing]
			fx.shoot({
				"x0": ap.x + o.x - Iso.iso_x(d.x, d.y) * 0.25,
				"y0": ap.y + o.y - 46,
				"x1": imp_pt.x,
				"y1": imp_pt.y - 10,
				"t": 0.0,
				"dur": flight,
				"arc": l * 0.45 + 90,
				"kind": "stone",
				"scale": 2.1 if kind == "rock" else 1.8,
				"color": "#7d6e5a" if kind == "rock" else "#8a8378",
				"onHit": crash,
			})
	var run := step
	_anim = _new_anim(total,
		func(f): run.call(f * total),
		func():
			apply_all.call()
			pose.call(false)
			SoldierAnim.turn_back(casters))


## One squad takes what the spell brought it: a wound and its dead, healing, or a frenzy.
func _apply_spell_hit(e: Dictionary, h: Dictionary, from: Dictionary) -> void:
	var ab: Dictionary = DB.ABILITIES[e.ability]
	var v: UnitView = views[h.uid]
	var t: Dictionary = _u(h.uid)
	var caster: Dictionary = _u(e.uid)
	v.hp = h.hp
	var head := _head_pos(v)
	var damage: float = float(h.get("damage", 0))
	var heal: float = float(h.get("heal", 0))
	if damage > 0:
		var col: String = SPELL_TEXT.get(ab.get("fx", "stone"), "#ffffff")
		fx.text(head.x, head.y - 4, JS.num_str(h.damage), col, {"size": 28 if h.role == "main" else 22})
		if t.faction == caster.faction:
			fx.text(head.x, head.y - 34, "Friendly fire!", "#ffb070", {"size": 14, "delay": 0.05})
		for m in SquadView.standing(v.members):
			m.flash = maxf(m.flash, 0.55)
			m.shake = 1.0
		_sfx_at("hit_metal" if (t.stats.armor >= 2 and ab.get("fx") != "gut") else "hit_flesh", _view_pos(v))
		_show_casualties(v, h.aliveBefore - h.aliveAfter, from, {"reformDelay": 0.55})
	elif ab.get("power") != null and damage == 0:
		fx.text(head.x, head.y - 4, "Unhurt", "#c8c8c8", {"size": 18})
	if heal > 0:
		fx.text(head.x, head.y - 4, "+%s" % JS.num_str(h.heal), "#9ff08a", {"size": 24})
	elif ab.get("heal") != null:
		fx.text(head.x, head.y - 4, "Unhurt", "#d8ecc8", {"size": 16})


# ---------------------------------------------------------------- update

func _process(delta: float) -> void:
	if not _is_setup or not auto_step:
		return
	var real := minf(0.05, delta)
	step_frame(real * time_scale * speed)


## One frame: update by `dt` seconds of battle time (already scaled), camera
## keys, camera transform and redraw. `_process` calls it with the engine's
## clamped, scaled delta; automation may call it with a fixed step after
## setting `auto_step = false`.
func step_frame(dt: float) -> void:
	var vs := _view_size()
	_w = vs.x
	_h = vs.y
	time += dt
	cam.pan_keys(dt, 700.0, self)
	update(dt)
	_apply_camera()
	_redraw()
	_sync_ambience()


## Day or night ambience; at dawn the night's sounds give way slowly.
func _sync_ambience() -> void:
	if not is_inside_tree():
		return
	var want := "battle_night" if atmo.night else "battle_day"
	if want == _ambience:
		return
	var first := _ambience == ""
	_ambience = want
	var s := _audio()
	if s != null and s.has_method("set_ambience"):
		s.set_ambience(want, -1.0 if first else 6.0)


## One frame of the scene's update for tests and automation (no drawing).
func advance(dt: float) -> void:
	time += dt
	update(dt)


## BattleScene.update(dt).
func update(dt: float) -> void:
	_staged_cache = null
	_poll_task()
	_clamp_camera()
	cam.update(dt)
	fx.update(dt)
	atmo.update(dt, _w, _h)
	flash.a = maxf(0.0, flash.a - dt * 3.2)
	for v: UnitView in views.values():
		v.shake = maxf(0.0, v.shake - dt * 3)
		v.engine_atk = maxf(0.0, v.engine_atk - dt)
		SquadView.step_members(v.members, dt, func(m): _add_corpse(v, m))
		if not v.members.is_empty() and SoldierAnim.animated(v.members[0].type):
			# The men follow the anchor over the ground: climbing a ledge lifts them with it.
			SoldierAnim.step_drift(v, dt, Vector2(Iso.iso_x(v.x, v.y), Iso.iso_y(v.x, v.y, 0.0)))
		v.walking = Iso.clamp(v.walking + (dt * 6 if v.marching else -dt * 4), 0, 1)
		v.step_t += dt
		if v.walking > 0:
			v.walk_t += dt
			_footfalls(v, dt)
			_step_dust(v, dt)
		if v.statuses.size() > 0 and squad_visible(v) and v.alive > 0:
			_status_motes(v, dt)
	_focus_hold = maxf(0.0, _focus_hold - dt)
	var rush := Iso.clamp(1 + _queue.size() / 45.0, 1, 1.9) if ui.side == "enemy" else 1.0
	var adt := dt * rush
	var o := _objective()
	if o.get("dawn") and o.get("turns"):
		# Night gives way to dawn turn by turn; the sun is up when the relief comes.
		var won: bool = relief != null or _ended or (b.phase == "over" and b.get("result") == "victory" and not busy())
		var want := 0.0 if won else Iso.clamp(1 - (float(ui.turn - 1) / o.turns) * 0.85, 0.15, 1)
		night_level += (want - night_level) * minf(1.0, dt * (1.6 if relief != null else 0.6))
		atmo.night = night_level > 0.05
	if relief != null:
		_step_relief(dt)
	for a: Anim in _anims.duplicate():
		if a.delay > 0:
			a.delay -= adt
			continue
		if not a.started:
			a.started = true
			if a.start.is_valid():
				a.start.call()
		a.t += adt
		if a.step.is_valid():
			a.step.call(minf(1.0, a.t / a.dur) if a.dur > 0 else 1.0)
		# Banners and the end wait for missiles still in the air.
		if a.t >= a.dur and (not a.barrier or not BattleDeps.fx_busy(fx)):
			if a.done.is_valid():
				a.done.call()
			_anims.erase(a)
	if fog != null:
		fog.refresh(dt)
	_next()
	if terrain_surface != null:
		for unit_view in views.values():
			unit_view.h = terrain_surface.surface(unit_view.x, unit_view.y)
	var bz := busy()
	if bz != ui.busy:
		ui.busy = bz
		if not bz:
			_refresh_hover()
		notify()
	if _select_after_idle > 0 and not bz:
		_select_after_idle = 0
		if b.phase == "player":
			select_next(false)


## Lasting conditions show on the soldiers: frost glitter, the red haze of a frenzy, dripping blood.
func _status_motes(v: UnitView, dt: float) -> void:
	var live := SquadView.standing(v.members)
	if live.is_empty():
		return
	for s in v.statuses:
		if randf() > (4.0 if s == "bleeding" else 6.0) * dt:
			continue
		var m = live[randi() % live.size()]
		var q := _member_pos(v, m)
		var x := q.x + (randf() - 0.5) * 14
		if s == "chilled":
			fx.burst(x, q.y - 8 - randf() * 34, 0, 1, {"shape": "glow", "color": "#e6f6ff", "speed": 6, "vz": 0, "gravity": -6, "size": 2, "max": 1})
		elif s == "bloodlust":
			fx.burst(x, q.y - 16 - randf() * 26, 0, 1, {"shape": "glow", "color": "#ff3a20", "speed": 10, "vz": 0, "gravity": -34, "size": 2.6, "max": 0.75})
		elif s == "bleeding":
			fx.burst(x, q.y - 4, 14 + randf() * 10, 1, {"shape": "dot", "color": "#9a1a12", "speed": 4, "vz": 0, "gravity": 220, "size": 2.2, "max": 0.6})


func _apply_camera() -> void:
	if _world == null:
		return
	var shake: float = cam.shake
	var sx := (randf() - 0.5) * shake * 10 if shake else 0.0
	var sy := (randf() - 0.5) * shake * 10 if shake else 0.0
	var tr := cam.transform(Vector2(_w, _h), sx, sy)
	_world.transform = tr
	_layers.TextWorld.transform = tr


func _redraw() -> void:
	for n in ["Background", "Under", "FxGround", "Sorted", "FxAir", "Flash", "Overlays", "Minimap", "Texts"]:
		var l = _layers.get(n)
		if l != null:
			l.queue_redraw()
	var g = _layers.get("Grid")
	if g != null:
		g.visible = ui.showGrid
	# The held ground: the overrun warning lasts until it is retaken (drawZone).
	if _overrun_warn and b.overrun == 0:
		_overrun_warn = false
	if _layers.has("Zone"):
		if _overrun_warn or _zone_red:
			_layers.Zone.queue_redraw()
		_zone_red = _overrun_warn
		_draw.zone_dash_uniforms(_layers.ZoneDash)
	var mk: String = _draw.minimap_key()
	if mk != _minimap_key and _layers.has("MinimapBase"):
		_minimap_key = mk
		_layers.MinimapBase.queue_redraw()
	if _water != null:
		_water.cam = cam
		_water.view_size = Vector2(_w, _h)
		_water.time = time
	if _night != null:
		_night.refresh()
	BattleDeps.refresh_atmosphere(self, atmo)


# ---------------------------------------------------------------- input

func _tile_at_screen(sx: float, sy: float) -> Variant:
	var wpt := cam.screen_to_world(sx, sy, _w, _h)
	if terrain_surface != null:
		var g: Vector2 = terrain_surface.unproject(wpt)
		var gx := roundi(g.x)
		var gy := roundi(g.y)
		return {"x": gx, "y": gy} if Grid.in_bounds(b.map, gx, gy) else null
	# Test from the highest level down so raised tiles win.
	var lvl: int = terrain.max_h if b.map.get("terrainLab", false) else 3
	while lvl >= 0:
		var gx := (wpt.x / (TW / 2.0) + (wpt.y + lvl * LH) / (TH / 2.0)) / 2
		var gy := ((wpt.y + lvl * LH) / (TH / 2.0) - wpt.x / (TW / 2.0)) / 2
		var x := JS.rnd(gx)
		var y := JS.rnd(gy)
		var t = Grid.tile_at(b.map, x, y)
		if t != null and t.h == lvl:
			return {"x": x, "y": y}
		lvl -= 1
	return null


func pointer_move(p: Vector2) -> void:
	_pointer = p
	_refresh_hover()


## Front-most living unit whose figure (opaque pixels) is under the cursor.
func squad_visible(uv) -> bool:
	return uv != null and uv.visible and (fog == null or fog.sees(uv.uid))


func unit_visible(u: Dictionary) -> bool:
	return squad_visible(views.get(u.uid))


func _unit_at_screen(sx: float, sy: float) -> Variant:
	var wp := cam.screen_to_world(sx, sy, _w, _h)
	var best = null
	var best_d := -INF
	for v: UnitView in views.values():
		if not squad_visible(v) or v.status == "dead" or v.status == "downed" or v.status == "fled":
			continue
		var u: Dictionary = _u(v.uid)
		if not _draw.body_covers(v, u, wp.x, wp.y):
			continue
		var d := v.x + v.y
		if d > best_d:
			best_d = d
			best = u
	return best


## Whether the selected soldier could be moved (or deployed) onto this tile now.
func _is_move_target(t: Dictionary) -> bool:
	var sel = selected_unit()
	if sel == null or b.known_unit_at(sel.faction, t.x, t.y) != null:
		return false
	if b.phase == "deploy":
		for p in b.map.playerDeploy:
			if p.x == t.x and p.y == t.y:
				return true
		return false
	if b.phase != "player" or sel.hasMoved or busy():
		return false
	return _reach(sel).has(Grid.key(t.x, t.y))


## What the cursor points at. A unit's figure wins over the ground behind it,
## except that an empty tile the selected soldier can move to beats a friendly
## figure that merely overlaps it on screen. Enemy figures always mean the enemy.
func resolve_pointer(sx: float, sy: float) -> Dictionary:
	var ground = _tile_at_screen(sx, sy)
	var standing_u = Grid.unit_at(b.units, ground.x, ground.y) if ground != null else null
	if standing_u != null and not unit_visible(standing_u):
		standing_u = null
	var body = _unit_at_screen(sx, sy)
	if body != null and (standing_u == null or body.uid != standing_u.uid):
		if ground != null and standing_u == null and body.faction == "player" and _is_move_target(ground):
			return {"tile": ground, "unit": null}
		return {"tile": {"x": body.x, "y": body.y}, "unit": body}
	if standing_u != null:
		return {"tile": ground, "unit": standing_u}
	return {"tile": ground, "unit": null}


static func _empty_hover() -> Dictionary:
	return {"tile": null, "unit": null, "preview": null, "spell": null, "path": null, "zoc": null, "dest": null, "facing": null, "facings": null, "turn": null}


## The spell the cursor aims: the one chosen from the squad's panel, or, with
## nothing chosen, a war machine's stone when the cursor is on an enemy.
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


## Where a spell would be cast with the cursor on tile `t` (over unit `u`), if it can be aimed there at all.
func _spell_aim(spell_id: String, t: Dictionary, u = null) -> Variant:
	var ab: Dictionary = DB.ABILITIES[spell_id]
	var target = ab.get("target")
	if target == "tile":
		return {"x": u.x, "y": u.y} if u != null else {"x": t.x, "y": t.y}
	if target == "enemy" and u != null and u.faction == "enemy":
		return {"x": u.x, "y": u.y}
	if target == "ally" and u != null and u.faction == "player":
		return {"x": u.x, "y": u.y}
	return null


func _refresh_hover() -> void:
	if _task_id >= 0:
		return
	var rp := resolve_pointer(_pointer.x, _pointer.y)
	var t = rp.tile
	var picked = rp.unit
	var hover := _empty_hover()
	hover.tile = t
	var sel = selected_unit()
	if t != null:
		var u = picked
		if u != null:
			hover.unit = u.uid
		var spell_id = _aimed_spell(sel, u) if (sel != null and not busy() and b.phase == "player") else null
		if sel != null and spell_id != null:
			var at = _spell_aim(spell_id, t, u)
			if at != null and not sel.hasActed:
				hover.spell = b.spell_preview(sel, spell_id, at)
			# A war machine's stone that cannot fly here (too close, just moved): its crew's own attack instead.
			if ui.ability == null and u != null and hover.spell != null and not hover.spell.legal:
				hover.spell = null
				hover.preview = _preview_against(sel, u)
		elif sel != null and not busy() and b.phase == "player":
			if u != null and u.faction == "enemy":
				hover.preview = _preview_against(sel, u)
				var from = hover.preview.get("from") if (hover.preview != null and hover.preview.moveFirst) else null
				if from != null:
					# Arrive facing the enemy you strike, unless that way in costs extra free attacks.
					var arr = _arrival(sel, from, Grid.dir_to(from, u), true)
					if arr != null:
						_show_arrival(hover, from, arr)
			elif u == null and not sel.hasMoved and sel.status == "active":
				if _reach(sel).has(Grid.key(t.x, t.y)):
					var pt = _pointing(t)
					# Q / E hold until the cursor points at a different edge.
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


## How the selected squad would arrive on `at`. A squad faces the way it last
## stepped, so each facing is its own path: the one picked with Q / E, else
## the one asked for (`soft`: only if it provokes no extra free attacks),
## else the default (facing the nearest enemy where possible).
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


## The facing the cursor points at inside a tile: toward the edge it is
## nearest, or none near the centre. `inside` ignores points off the tile
## (the cursor on a squad's bodies rather than its ground).
func _pointing(at: Dictionary, dead := 0.16, inside := false) -> Variant:
	var th := _tile_h(at.x, at.y)
	var wp := cam.screen_to_world(_pointer.x, _pointer.y, _w, _h)
	var dx := wp.x - Iso.iso_x(at.x, at.y)
	var dy := wp.y - Iso.iso_y(at.x, at.y, th)
	var gx := (dx / (TW / 2.0) + dy / (TH / 2.0)) / 2
	var gy := (dy / (TH / 2.0) - dx / (TW / 2.0)) / 2
	if JS.hypot(gx, gy) < dead:
		return null
	if inside and absf(gx) + absf(gy) > 0.62:
		return null
	return Grid.dir_to({"x": 0, "y": 0}, {"x": gx, "y": gy})


## Preview an attack, including move-then-strike for melee from the side under the cursor.
func _preview_against(sel: Dictionary, target: Dictionary) -> Variant:
	if sel.hasActed:
		return null
	var ability = ui.ability
	var here: Dictionary = b.preview(sel, target, {"ability": ability} if ability != null else {})
	if here.legal:
		return _pv(here, target.uid, ability, false)
	if sel.hasMoved:
		return _pv(here, target.uid, ability, false)
	var ab = DB.ABILITIES[ability] if ability != null else null
	if sel.get("shot") != null and ab == null:
		# Ranged units: suggest the reachable tile that keeps the best shot.
		var reach := _reach(sel)
		var best = null
		for k in reach:
			var from := {"x": k % 1000, "y": floori(k / 1000.0)}
			var pv: Dictionary = b.preview(sel, target, {"from": from, "movedTiles": 1})
			if pv.legal and (best == null or pv.chance > best.pv.chance):
				best = {"pv": pv, "from": from}
		if best != null:
			var out := _pv(best.pv, target.uid, null, true)
			out.from = best.from
			return out
		return _pv(here, target.uid, null, false)
	# Melee: choose the adjacent tile closest to the cursor. A charge takes the
	# closest side that gives it its run, and the closest side only when none does.
	var reach := _reach(sel)
	var wpt := cam.screen_to_world(_pointer.x, _pointer.y, _w, _h)
	var reach_opts: Array = []
	for d in Grid.DIRS:
		if ab != null and ab.get("reach") == 2:
			reach_opts.append({"x": target.x - d.x * 2, "y": target.y - d.y * 2})
		else:
			reach_opts.append({"x": target.x + d.x, "y": target.y + d.y})
	var strike := func(from: Dictionary) -> Dictionary:
		var path = b.path_to(sel, from.x, from.y)
		var opts := {"from": from, "movedTiles": path.size() - 1 if path != null else 1}
		if ability != null:
			opts.ability = ability
		return b.preview(sel, target, opts)
	var run: bool = ab != null and ab.get("minRun") != null
	var best = null
	var best_run = null
	for from in reach_opts:
		if not reach.has(Grid.key(from.x, from.y)):
			continue
		var fxw := Iso.iso_x(from.x, from.y)
		var fyw := Iso.iso_y(from.x, from.y, _tile_h(from.x, from.y))
		var d := JS.hypot(fxw - wpt.x, fyw - wpt.y)
		var side := {"from": from, "d": d, "pv": null}
		if run and (best_run == null or d < best_run.d):
			side.pv = strike.call(from)
			if side.pv.legal:
				best_run = side
		if best == null or d < best.d:
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


func pointer_down(p: Vector2, button: int) -> void:
	if button == 2:
		if ui.ability != null:
			ui.ability = null
		else:
			ui.selected = null
		_refresh_hover()
		notify()
		return
	if button == 0 and b.map.get("scale") == "large":
		# Clicking the minimap moves the camera there.
		var r := minimap_rect()
		if p.x >= r.x - 4 and p.x <= r.x + r.w + 4 and p.y >= r.y - 4 and p.y <= r.y + r.h + 4:
			cam.tx = r.ox + (p.x - r.x) / r.k
			cam.ty = r.oy + (p.y - r.y) / r.k
			return
	if button != 0 or busy() or _ended:
		return
	_pointer = p
	if b.phase == "player":
		_refresh_hover()
	var hv: Dictionary = ui.hover
	var rp := resolve_pointer(p.x, p.y)
	var t = rp.tile
	var u = rp.unit
	if t == null:
		return
	if b.phase == "deploy":
		if u != null and u.faction == "player":
			if ui.selected != null and ui.selected != u.uid:
				b.deploy_swap(ui.selected, t.x, t.y)
				_sync_views()
				_sfx_at("step", _ground_pt(t))
				ui.selected = null
			else:
				ui.selected = u.uid
			notify()
		elif ui.selected != null and b.deploy_swap(ui.selected, t.x, t.y):
			_sync_views()
			_sfx_at("step", _ground_pt(t))
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
		# A chosen spell that cannot be cast here stops the click; a machine's stone gives way to its crew's attack.
		if at != null and ui.ability != null:
			_sfx("deny")
			return
		if at == null and ui.ability != null:
			# With a spell chosen, a click on another of the company's squads picks that squad instead.
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
		_say("attack", sel.uid, ["order_" + str(pv.ability)] if pv.get("ability") != null else [])
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
		_say("move", sel.uid)
		b.move(sel.uid, t.x, t.y, hv.facing if same else null)
		pump()
		_after_player_action(sel)


func _after_player_action(u: Dictionary) -> void:
	if u.done or u.status != "active":
		# Wait for animations; then the selection moves on (requestAnimationFrame poll in the original).
		_select_after_idle += 1


func _sync_views() -> void:
	for u in b.units:
		var v: UnitView = views[u.uid]
		v.x = u.x
		v.y = u.y
		v.h = _tile_h(u.x, u.y)
		if v.facing != u.facing:
			v.facing = u.facing
			_reform_view(v, {"instant": true})


func wheel(delta: float) -> void:
	cam.tzoom = Iso.clamp(cam.tzoom * (0.9 if delta > 0 else 1.1), min_zoom, 1.6)


## The keyboard commands of BattleScene.key / keyUp, by input action.
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


const _ACTIONS := ["facing_prev", "facing_next", "select_next", "end_unit", "end_turn", "redo_move", "cancel", "toggle_grid", "show_danger", "ability_1", "ability_2", "ability_3", "ability_4"]


func _unhandled_input(e: InputEvent) -> void:
	if not _is_setup:
		return
	if e is InputEventMouseMotion:
		pointer_move(Camera.view_local(self, e.position))
		return
	if e is InputEventMouseButton:
		var p := Camera.view_local(self, e.position)
		if e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			wheel(1.0 if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0)
			get_viewport().set_input_as_handled()
			return
		if e.pressed:
			cam.drag_input(e, self)
			var button := 0 if e.button_index == MOUSE_BUTTON_LEFT else (2 if e.button_index == MOUSE_BUTTON_RIGHT else (1 if e.button_index == MOUSE_BUTTON_MIDDLE else -1))
			if button >= 0:
				pointer_down(p, button)
				get_viewport().set_input_as_handled()
		return
	if e is InputEventKey:
		if e.is_echo():
			return
		for a in _ACTIONS:
			# Only the exact chord (Ctrl+Z for redo, plain keys otherwise).
			if not InputMap.event_is_action(e, a, true):
				continue
			if e.pressed:
				_held[a] = true
				key_action(a, true)
			elif _held.has(a):
				_held.erase(a)
				key_action(a, false)
			get_viewport().set_input_as_handled()
			return


func _input(e: InputEvent) -> void:
	if not _is_setup:
		return
	# The drag follows the pointer over HUD panels and ends on release anywhere.
	cam.drag_motion(e, self)
	# Alt released anywhere ends the danger view (keyUp on the window).
	if e is InputEventKey and not e.pressed and _held.has("show_danger") and e.is_action("show_danger"):
		_held.erase("show_danger")
		key_action("show_danger", false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _held.has("show_danger"):
		_held.erase("show_danger")
		key_action("show_danger", false)


# ---------------------------------------------------------------- relief

## The relief of a last stand: the Margrave's riders come down the road the
## horde came by and fall on its rear, a column of lances three ranks deep,
## reining in where the field is blocked or the enemy stands.
func _start_relief() -> void:
	var used := {}
	for w in _waves():
		used[w.edge] = used.get(w.edge, 0) + 1
	var entries: Dictionary = b.map.get("entries", {})
	var roads: Array = ["w", "n", "e", "s"].filter(func(e): return entries.get(e) != null and entries.get(e).size() > 0)
	JS.sort(roads, func(p, q): return used.get(q, 0) - used.get(p, 0))
	var edge: String = roads[0] if roads.size() > 0 else "s"
	var facing: int = BattleDeps.inward(edge)
	var d: Dictionary = Grid.DIRS[facing]
	var W: int = b.map.w
	var H: int = b.map.h
	var ns := edge == "n" or edge == "s"
	var edge_tile := func(a: int) -> Dictionary:
		if edge == "n":
			return {"x": a, "y": 0}
		if edge == "s":
			return {"x": a, "y": H - 1}
		if edge == "w":
			return {"x": 0, "y": a}
		return {"x": W - 1, "y": a}
	var road: Array = entries.get(edge) if entries.get(edge) != null else [edge_tile.call(floori((W if ns else H) / 2.0))]
	var lo := INF
	var hi := -INF
	for p in road:
		var a: float = p.x if ns else p.y
		lo = minf(lo, a)
		hi = maxf(hi, a)
	var cols := maxi(3, JS.rnd((hi - lo + 1) / 0.75))
	var rng := Rng.new(b.turn * 31 + W)
	var riders: Array = []
	for rank in 3:
		for c in cols - (rank % 2):
			var a := lo - 0.2 + ((hi - lo + 0.4) * (c + (rank % 2) * 0.5)) / (cols - 1)
			var e0: Dictionary = edge_tile.call(JS.rnd(a))
			# Ride in until the ground is blocked or the enemy stands in the way.
			var depth := -1
			while depth < 4 - rank:
				var nx: int = e0.x + d.x * (depth + 1)
				var ny: int = e0.y + d.y * (depth + 1)
				if not Grid.tile_passable(b.map, nx, ny) or Grid.unit_at(b.units, nx, ny) != null:
					break
				depth += 1
			var end := maxf(depth, -0.6) - rank * 0.9 + rng.frange(-0.15, 0.15)
			var out := 2.6 + rank * 1.15
			var side := a - JS.rnd(a)
			var base := {"x": e0.x + (side if ns else 0.0), "y": e0.y + (0.0 if ns else side)}
			riders.append({
				"x0": base.x - d.x * out, "y0": base.y - d.y * out,
				"x1": base.x + d.x * end, "y1": base.y + d.y * end,
				"delay": rank * 0.32 + rng.frange(0, 0.2), "speed": rng.frange(3.4, 4),
				"facing": facing, "variant": (c * 2 + rank) % 6, "dust": 0.0,
			})
	relief = {"t": 0.0, "glow": 0.0, "edge": edge, "riders": riders}
	# Look toward them as they come.
	var ex := 0.0
	var ey := 0.0
	for q in riders:
		ex += Iso.iso_x(q.x1, q.y1)
		ey += Iso.iso_y(q.x1, q.y1, 0)
	ex /= riders.size()
	ey /= riders.size()
	cam.tx = Iso.lerp(cam.x, ex, 0.65)
	cam.ty = Iso.lerp(cam.y, ey - 40, 0.65)
	_sfx_at("hooves", Vector2(ex, ey))


## Where a relief rider is at time `t`, his stride and how far he has come into view.
func _rider_at(q: Dictionary, t: float) -> Dictionary:
	var len := JS.hypot(q.x1 - q.x0, q.y1 - q.y0)
	var run := maxf(0.0, t - q.delay)
	var dur: float = len / q.speed + 0.4
	var k := Iso.clamp(run / dur, 0, 1)
	# Full gallop most of the way, reining in over the last stretch.
	var f := (k / 0.75) * 0.88 if k < 0.75 else 0.88 + 0.12 * Iso.ease_out_cubic((k - 0.75) / 0.25)
	var moving := run > 0 and k < 1
	var phase := run * 9
	var pose := ("idle" if run > 0 else "atk") if not moving else ("atk" if sin(phase) > 0 else "run")
	return {
		"x": Iso.lerp(q.x0, q.x1, f),
		"y": Iso.lerp(q.y0, q.y1, f),
		"pose": pose,
		"bob": absf(sin(phase)) * 4 if moving else 0.0,
		"alpha": Iso.clamp((f * len) / 1.1, 0, 1) if run > 0 else 0.0,
		"moving": moving,
	}


func _step_relief(dt: float) -> void:
	var r: Dictionary = relief
	r.t += dt
	r.glow = r.t / 1.2 if r.t < 1.2 else maxf(0.3, 1 - (r.t - 1.2) * 0.2)
	for q in r.riders:
		var p := _rider_at(q, r.t)
		if not p.moving:
			continue
		q.dust += dt
		if q.dust > 0.09:
			q.dust = 0.0
			var th := _tile_h(JS.rnd(p.x), JS.rnd(p.y))
			fx.burst(Iso.iso_x(p.x, p.y) + (randf() - 0.5) * 30, Iso.iso_y(p.x, p.y, th) + 2, 2, 1, {"shape": "puff", "color": "rgba(196,172,128,1)", "speed": 16, "vz": 22, "gravity": 6, "size": 9, "max": 1.1, "drag": 0.8})


# ---------------------------------------------------------------- minimap rect

## Screen rectangle of the minimap (bottom left) and its scale from world pixels.
func minimap_rect() -> Dictionary:
	var bd := _bounds
	var ww: float = bd.x1 - bd.x0 + 200
	var wh: float = bd.y1 - bd.y0 + 200
	var W := mini(250, JS.rnd(_w * 0.17))
	var k := W / ww
	var H := JS.rnd(wh * k)
	return {"x": 14, "y": _h - H - 14, "w": W, "h": H, "k": k, "ox": bd.x0 - 100, "oy": bd.y0 - 100}


# ---------------------------------------------------------------- helpers

func _view_size() -> Vector2:
	if is_inside_tree():
		return Camera.view_size(self)
	return Vector2(ProjectSettings.get_setting("display/window/size/viewport_width", 1920), ProjectSettings.get_setting("display/window/size/viewport_height", 1080))


func _tile_h(x, y) -> float:
	if terrain_surface != null:
		return terrain_surface.surface(float(x), float(y))
	var t = Grid.tile_at(b.map, int(x), int(y))
	return float(t.h) if t != null else 0.0


## Each figure's foot and shadow sample the same surface as the terrain.
func member_ground_offset(uv, ox: float, oy: float) -> float:
	if terrain_surface == null:
		return 0.0
	var d := Iso.from_iso(ox, oy)
	return (uv.h - terrain_surface.surface(uv.x + d.x, uv.y + d.y)) * LH


## _u(uid) through a uid index (b.unit searches the list; the passes ask
## for every squad every frame). Rebuilt when `b` is swapped for a snapshot.
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


func _objective() -> Dictionary:
	return BattleDeps.objective(b)


func _waves() -> Array:
	return BattleDeps.waves(b)


func _type_of(uid: String) -> String:
	return _u(uid).typeId


## The Sfx autoload found at run time, or null (the view also runs in tools
## and tests that load it before the autoloads exist).
func _audio() -> Node:
	if _sfx_node == null or not is_instance_valid(_sfx_node):
		var ml := Engine.get_main_loop() as SceneTree
		_sfx_node = ml.root.get_node_or_null("Sfx") if ml != null else null
	return _sfx_node


## A flat sound: the UI, turn banners, horns and drums of the whole field.
func _sfx(n: String) -> void:
	var s := _audio()
	if s != null:
		s.play(n)


## A sound of a squad or a point of impact (world px): Sfx pans it by where
## it is on screen and lowers it off screen and zoomed out.
func _sfx_at(n: String, at: Vector2, opts: Dictionary = {}) -> void:
	var s := _audio()
	if s == null:
		return
	if s.has_method("play_at"):
		s.play_at(n, at, opts)
	else:
		s.play(n)


## A unit's sound in its own kind: `first` names (e.g. stance_shieldwall), then
## <base>_<typeId> → <base>_<faction> → <base>, the first the bank can play;
## silent when none can (a hound's growl, a troll's death, an orc's war cry).
func _kind_sfx_at(base: String, uid: String, at: Vector2, first: Array = []) -> void:
	var u: Dictionary = _u(uid)
	var names: Array = first + [base + "_" + str(u.get("typeId", "")), base + "_" + str(u.get("faction", "")), base]
	var n := _first_sound(names)
	if n != "":
		_sfx_at(n, at)


## A squad answering the player's order ("Orders?", "Moving!", "At them!"):
## `first` names (e.g. order_shield_charge), then order_<line>_<typeId> →
## order_<line>. One voice answers at a time: none starts while the last
## still speaks. The hounds (QUIET_TYPES) obey without a word.
func _say(line: String, uid: String, first: Array = []) -> void:
	var type := str(_u(uid).get("typeId", ""))
	if QUIET_TYPES.has(type) or not views.has(uid):
		return
	var s := _audio()
	if s == null or (_said != "" and s.has_method("playing") and s.playing(_said) > 0):
		return
	var n := _first_sound(first + ["order_%s_%s" % [line, type], "order_" + line])
	if n != "":
		_said = n
		_sfx_at(n, _view_pos(views[uid]))


## The first of `names` the bank can play, or "" (cached per list).
func _first_sound(names: Array) -> String:
	var key := "|".join(names)
	var n: Variant = _sound_names.get(key)
	if n == null:
		var s := _audio()
		n = s.first_event(names) if s != null and s.has_method("first_event") else str(names[-1])
		_sound_names[key] = n
	return n


## Steps follow the men's planted feet (SoldierAnim.footfalls), gathered per
## squad: one tread per beat at most, from the squad's place, a little louder
## for a full squad and softer for a few survivors, in the figure's own kind.
func _footfalls(v: UnitView, dt: float) -> void:
	if not squad_visible(v) or v.reserve or v.alive <= 0:
		return
	var men := 0
	var down := 0
	for m in v.members:
		if not m.alive or m.dying:
			continue
		men += 1
		if SoldierAnim.animated(m.type):
			down += SoldierAnim.footfalls(v, m, dt)
	if down == 0 or v.step_t < STEP_BEAT:
		return
	v.step_t = 0.0
	_sfx_at(_step_event(v.uid), _view_pos(v), {"volume_db": clampf(3.0 * log(men / 6.0) / log(2.0), -6.0, 2.0)})


## Footstep dust: a puff under each man's foot as it lands, of the ground he
## walks on (dust on earth and roads, grit on stone, a splash in shallows, mud
## clods, bits of leaf in the woods), bigger and more for heavy feet; a troll's
## stamp shakes the camera. Only for squads in view, and thinned out when the
## camera is far away.
const STEP_DUST := {
	"grass": ["rgba(150,152,96,0.5)", 0.0], "dirt": ["rgba(190,165,120,0.55)", 1.0], "road": ["rgba(196,176,136,0.55)", 1.0],
	"brush": ["rgba(120,130,70,0.5)", 0.12], "forest": ["rgba(96,112,56,0.5)", 0.12], "mud": ["rgba(92,70,46,0.6)", 1.0],
	"shallows": ["rgba(205,225,240,0.8)", 1.0], "water": ["rgba(205,225,240,0.8)", 1.0], "stone": ["rgba(160,156,146,0.5)", 0.5],
	"bridge": ["rgba(150,128,96,0.5)", 0.4], "rubble": ["rgba(150,146,136,0.55)", 0.8],
}


func _step_dust(v: UnitView, dt: float) -> void:
	if not squad_visible(v) or v.reserve or v.alive <= 0 or cam.zoom < 0.42:
		return
	var p := _view_pos(v)
	if absf(p.x - cam.x) > _w / cam.zoom * 0.6 + 120 or absf(p.y - cam.y) > _h / cam.zoom * 0.6 + 160:
		return
	var tile = Grid.tile_at(b.map, roundi(v.x), roundi(v.y))
	var terrain: String = str(tile.terrain) if tile != null else "grass"
	var look: Array = STEP_DUST.get(terrain, STEP_DUST.grass)
	var wet := terrain == "shallows" or terrain == "water"
	for m in v.members:
		if not m.alive or m.dying or not SoldierAnim.animated(m.type):
			continue
		var n := SoldierAnim.footfalls(v, m, dt)
		if n <= 0:
			continue
		var ga := SoldierAnim.gait(m.type)
		var heavy: float = ga.stomp
		if look[1] <= 0.0 or randf() > look[1] * (0.35 + 0.65 * minf(1.0, heavy)):
			continue
		var q := _member_pos(v, m)
		# Low and faint: the puffs are drawn over the men, so they must not climb their legs.
		if wet:
			fx.burst(q.x, q.y, 1, 2 + int(heavy * 2), {"shape": "dot", "color": look[0], "speed": 26 + 18 * heavy, "vz": 30, "gravity": 160, "size": 1.2 * ga.dust, "max": 0.3})
		else:
			fx.burst(q.x, q.y + 1, 0.5, 1 + int(heavy), {"shape": "puff", "color": look[0], "speed": 8 + 10 * heavy, "vz": 3 + 3 * heavy, "gravity": 6, "size": 1.7 * ga.dust, "max": 0.35 + 0.2 * heavy})
		if heavy >= 1.0:
			cam.shake = maxf(cam.shake, 0.06 * (heavy - 0.6))


## The step sound of a squad's kind: step_<type>, else step_<size>, else step.
func _step_event(uid: String) -> String:
	var t := _type_of(uid)
	var ev: Variant = _step_events.get(t)
	if ev == null:
		var size := str(DB.UNIT_TYPES.get(t, {}).get("size", "medium"))
		var s := _audio()
		ev = s.first_event(["step_" + t, "step_" + size, "step"]) if s != null and s.has_method("first_event") else "step"
		if ev == "":
			ev = "step"
		_step_events[t] = ev
	return ev


static func _first(arr: Array) -> Variant:
	return arr[0] if arr.size() > 0 else null


## Sprite key and mirroring for a soldier's pose at a facing. +x and +y show
## the front, -x and -y the back; +x and -x are mirrored. Troops with shields
## use their shield-leading poses when mirrored, so the shield stays on the
## soldier's left arm in every direction.
static func pose_key(type: String, pose: String, facing: int) -> Dictionary:
	var lead := BattleDeps.has_shield_poses(type)
	var flip := facing == 0 or facing == 2
	return {"key": "%s_%s_%s%s" % [type, pose, "f" if Formation.faces_camera(facing) else "b", "s" if (flip and lead) else ""], "flip": flip}


static func dir_of(a: Dictionary, bb: Dictionary) -> int:
	var dx: float = bb.x - a.x
	var dy: float = bb.y - a.y
	if absf(dx) >= absf(dy):
		return 0 if dx >= 0 else 2
	return 1 if dy >= 0 else 3


static func morale_of(m: float, mx: float) -> String:
	if m <= 0:
		return "broken"
	var r := m / mx
	if r >= 0.9:
		return "confident"
	if r >= 0.5:
		return "steady"
	if r >= 0.25:
		return "shaken"
	return "wavering"


static func _rank(s: String) -> int:
	return ["confident", "steady", "shaken", "wavering", "broken"].find(s)


static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1)
