## A 3D unit in the sandbox, driven by its roster profile (roster.gd) and its
## clips' sidecar: any rigged model the art pipeline exports (FBX or GLB, with
## its clips named as in the sidecar, maybe behind an "Armature|" prefix).
##   order_move(points, then)   walk a route (world points on the ground)
##   strike(target, i)          turn to a target and play attack i of the profile
##   strike_at(target)          a squad's man's blow: an attack that reaches it
##   attack_target(target)      walk up to a target and strike it
##   take_hit(from, lethal)     the hit reaction, or the death
##   play_clip(name)            any clip once (a loop until the next order)
##   die() revive() stop() is_dead() actions() clip_names()
##   set_look(mode, outline) set_outline_width(m) playback height_m()
## A profile's `face` picks the sidecar's face variants (`faces`) the unit
## wears; the other faces' meshes go. Its `kit` picks the sidecar's gear
## variants (`kit`), whose `hide` meshes go.
##
## Moves the export's clips make possible, found by their names or under the
## names the profile's `moves` maps them to (the footman's export has them all;
## see "Moves" below):
##   start, stop        the march: he sets off and slows to a halt on the spot
##                      he was sent to, each step moved by its own travel
##                      (root_path); the walk between them is planned in whole
##                      strides. `pace` "game" walks at the game's speed instead.
##                      Without a start (the crossbowman's) he sets off straight
##                      into the walk.
##   turn_90, turn_90_r, turn_180   turns in place (root_yaw, about `pivot`),
##                      for a change of heading of STEP_TURN_MIN or more
##   run, charge_hit, charge_thrust, charge_stab   the charge (charge(target)):
##                      a run that brakes into a strike
##   block, block_hit   the raised shield (set_block), blows taken on it
##   lane               a step sideways into the next file (step_lane(dist))
## The profile's `plant_feet` turns him on the move about his planted foot and
## measures each foot's slide (`slides`); the charge needs it. `counter` offers
## the counter (a blow taken, then struck back). `blend` sets the cross-fade
## into a clip (seconds, by clip name).
## Every model faces +Z: a direction d on the ground is the yaw atan2(d.x, d.z).
## The sandbox sets the height of the ground under the unit after it moves.
## A view of motion only: the sandbox decides who is hit and who falls.
extends Node3D

signal impact(target: Node3D, landed: bool, reach: float)
## A ranged attack lets go (the sandbox flies its missile).
signal release(target: Node3D, kind: String)
signal clip_event(name: String)

const OUTLINE := preload("res://prototypes/footman_anim/shaders/outline3d.gdshader")
const WhipFX = preload("res://prototypes/footman_anim/scripts/whip_fx.gd")
const LocalClips = preload("res://prototypes/sandbox3d/scripts/local_clips.gd")
const BLEND := 0.2
## Turning on the spot and on the march (radians a second).
const TURN_RATE := deg_to_rad(420.0)
const STEER_RATE := deg_to_rad(300.0)
## A blow lands within its reach and this far off the striker's facing (the
## profile's `hit_arc` if it gives one).
const HIT_ARC := 80.0
## A blow lands this far past its reach; an attack is used for a foe up to
## this far past it (an attack's `over`, pick_attack).
const OVER := 0.45
## Events that mark a blow or a shot leaving, whatever a sidecar calls them.
const HIT_EVENTS := ["contact", "strike", "strikes", "strike_left", "strike_right", "shot", "release", "fire", "impact"]
## A profile's `ready` clip (the spearman's guard) is his idle while he
## fights: he holds it after a blow or a hit, and this long after the last
## eases back into his idle. An attack started from the idle blends in over
## READY_BLEND (the clip starts in the ready stance).
const READY_HOLD := 6.0
const READY_BLEND := 0.3
## A turn in place ends in the idle's first pose and hands over in 0.05 s; a
## cape (the sidecar's `cape_bones`) still swinging from the turn settles into
## the idle's over CAPE_SETTLE instead.
const CAPE_SETTLE := 0.35
## An attack whose clip gives its blade's reach (`tip_reach_m`) and whose
## profile entry gives none stands with the tip SLASH_INTO past the target's
## centre for a slash, THRUST_INTO for a thrust (strike_dist); its blow lands
## within the tip's reach and TIP_SLACK.
const SLASH_INTO := 0.57
const THRUST_INTO := 0.25
const TIP_SLACK := 0.25
## The march. Turning on the move with planted feet: only while one foot is
## down, and about that foot, so a planted foot pivots instead of sliding.
const FOOT_STEER_RATE := deg_to_rad(220.0)
## Landing on the target: the start's travel, the walk's pace and the stop's
## travel all stretch by one factor, at most SLACK (a few centimetres a step),
## and he may come to rest up to ARRIVE_TOLERANCE (m) short of or past it
## (a squad's men stand off the tile's centre anyway). STRETCH_TYPICAL is a
## normal stretch (_plan).
const SLACK := 0.06
const ARRIVE_TOLERANCE := 0.3
const STRETCH_TYPICAL := 0.04
## The game's march (battle_view.gd _play_move: a player squad, seconds per
## tile) and walk cycle (soldier_anim.gd STRIDE: seconds per two steps): the
## march at `pace` "game".
const GAME_TILE_TIME := 0.26
const GAME_STRIDE := 0.44
## A change of heading (degrees) from which he turns in place with a turn clip.
const STEP_TURN_MIN := 30.0
## The charge (the game's shield_charge: a run of at least CHARGE_MIN_TILES,
## then the strike). He sets off from his guard into the run at CHARGE_LAUNCH_T
## (his left foot just landed: his front foot, it stays where it stands while
## the rear one pushes off), the run at CHARGE_RATE0 of its pace and cadence
## together, so planted feet hold, reaching its own over CHARGE_RAMP seconds.
## To land the strike his run may stretch by up to CHARGE_SLACK; he may come
## to rest up to CHARGE_LONG (m) farther from the target than the strike's
## distance (the blade still reaches) but only CHARGE_SHORT nearer (the blade
## would pass through it).
const CHARGE_MIN_TILES := 2
## The strikes the run can brake into, each taking over at its own point of the
## stride (enter_run_t; those the export has), and how far each may come to
## rest from its spot: [nearer, farther] (m). The slash reaches far but cuts
## through a target it is too close to; a thrust must reach and still reads
## from close in.
const CHARGE_STRIKES := ["charge_hit", "charge_thrust", "charge_stab"]
const CHARGE_LEEWAY := {"charge_hit": [0.12, 0.3], "charge_thrust": [0.15, 0.25], "charge_stab": [0.35, 0.15]}
const CHARGE_LAUNCH_T := 16.0 / 30.0
const CHARGE_RATE0 := 0.4
const CHARGE_RAMP := 0.5
const CHARGE_SLACK := 0.08
const CHARGE_LONG := 0.3
const CHARGE_SHORT := 0.12
## At the blow his body's front (a toe or the hips: the clip's lead_m ahead of
## where it stands; the lunge's front foot lands 1.7 m on) never nearer the
## target's centre than this (the dummy's sack is 0.24 m across, its base 0.3).
const CHARGE_NEAREST := 0.35

var profile: Dictionary
var meta: Dictionary
## Clip name -> {anim, length, loop, speed, events: [[t, name], ...]}.
var clips := {}
var model: Node3D
var player: AnimationPlayer
var skeleton: Skeleton3D
var fx: Node3D
var faction := "player"
var state := "idle"
var path: Array = []
var stance := ""
var speed_now := 0.0
var last_impact := ""
var playback := 1.0:
	set(v):
		playback = v
		if player:
			player.speed_scale = v
## The march's pace: "walk" (his walk at its own speed) or "game" (the walk
## sped to the game's GAME_TILE_TIME a tile: feet skate). See set_pace.
var pace := "walk"
## On the march, a large change of heading from a standstill: a turn in place
## first (true) or straight off, turning as he goes (false).
var step_turns := false
## Metres a tile (the sandbox's): the game pace and the charge's shortest run.
var tile_m := 2.72
## The shield is to be up whenever he stands (set_block).
var block_held := false
## With planted feet: the last few stances of a foot on the move,
## [side, slide (m), state].
var slides: Array = []
var _clip := ""
var _target: Node3D
var _attack: Dictionary
var _hits: Array = []
var _then := Callable()
var _yaw_goal := NAN
var _after_turn := Callable()
var _prev_t := 0.0
var _ev_i := 0
var _variant_in := 0.0
var _variant_left := 0.0
var _ready_left := 0.0
var _idle_t_prev := 0.0
var _rng := RandomNumberGenerator.new()
var _outline: ShaderMaterial
var _outline_thin: ShaderMaterial
var _surfaces: Array = []
## The moves (see the header) his export has: "march" (the stop), "start",
## "turns", "charge", "block", "lane".
var _moves := {}
## A turn in place: its clip, root_yaw curve, scale, the heading and place it
## started from and the point he turns about.
var _turn := {}
## The travel of the clip moving him (start, stop, lane, a charge's strike)
## applied so far; the lane step's stretched to the distance asked for.
var _root_prev := Vector2.ZERO
var _lane_scale := 1.0
## The march: whether it uses the stop (and the start), the stop's cue (committed,
## and the slight change of pace that lands it), the walk's time last frame and
## the march so far, at its own pace and as stretched.
var _full_march := false
var _stop_cue := {}
var _stretch := 1.0
var _walk_t_prev := 0.0
var _march_run := Vector2.ZERO
## The charge: seconds into it, the run's time last frame, and the strike's cue
## (as the stop's, from the run); the run so far, at its own pace and as
## stretched; the strike he goes for when two land about as well.
var _charge_t := 0.0
var _charge_run := Vector2.ZERO
var _run_t_prev := 0.0
var _charge_cue := {}
var _charge_pref := "charge_hit"
## Setting off on the charge: the cross-fade's weight so far, and his front
## foot in his own space: where the guard has it, and where the run has it at
## CHARGE_LAUNCH_T.
var _launch_w := 1.0
var _launch_from := Vector3.ZERO
var _launch_run_foot := Vector3.ZERO
## Planted feet: side -> {bone, down, at, max, prev}; the ankle's height at rest.
var _feet := {}
var _ankle_rest := 0.0
## A counter waiting for the blow he takes first: whom to strike back at.
var _counter_target: Node3D


func setup(p: Dictionary) -> void:
	profile = p
	faction = p.get("faction", "player")


func _ready() -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string(profile.meta))
	model = (load(profile.model) as PackedScene).instantiate()
	if profile.has("scale"):
		model.scale = Vector3.ONE * float(profile.scale)
	add_child(model)
	player = model.find_children("*", "AnimationPlayer", true, false)[0]
	var sks := model.find_children("*", "Skeleton3D", true, false)
	skeleton = sks[0] if not sks.is_empty() else null
	# Clips kept out of Git (the succubus's kiss), where they are on disk.
	if profile.has("local_clips") and skeleton:
		meta.clips.merge(LocalClips.add(player, skeleton, String(profile.local_clips)))
	_read_clips()
	# Roles the sidecar names (the spearman's and crossbowman's exports) fill
	# what the profile leaves open.
	var roles: Dictionary = meta.get("roles", {})
	for k in ["idle", "ready", "walk", "hit"]:
		if not profile.has(k) and roles.has(k):
			profile[k] = roles[k]
	if not profile.has("death") and roles.has("death"):
		profile["death"] = roles.death[0] if roles.death is Array else roles.death
		if roles.death is Array:
			profile["deaths"] = roles.death
	if not profile.has("attacks") and roles.has("attack"):
		var list := []
		for c in (roles.attack if roles.attack is Array else [roles.attack]):
			var atk: Dictionary = profile.get("attack_defaults", {}).duplicate()
			atk["clip"] = c
			# The defaults' label names the first attack only; the profile's labels any.
			var label: String = atk.get("label", "") if list.is_empty() else ""
			atk["label"] = profile.get("labels", {}).get(c, label if label != "" else String(c).capitalize())
			list.append(atk)
		profile["attacks"] = list
	if not profile.has("extras") and roles.has("extra"):
		profile["extras"] = roles.extra
	player.animation_finished.connect(_on_finished)
	player.speed_scale = playback
	_outline = ShaderMaterial.new()
	_outline.shader = OUTLINE
	_outline_thin = ShaderMaterial.new()
	_outline_thin.shader = OUTLINE
	_dress(profile.get("face", []) + profile.get("kit", []))
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if _named(mi, profile.get("full_detail", [])):
			mi.lod_bias = 128.0
		for i in mi.mesh.get_surface_count():
			_surfaces.append([mi, i, mi.get_active_material(i)])
	if profile.get("fx", "") == "whip" and skeleton:
		fx = WhipFX.new()
		fx.name = "WhipFX"
		add_child(fx)
		var atk: Dictionary = clips.get("attack", {})
		fx.setup(self, skeleton, player, atk.get("anim", "attack"), meta.clips.get("attack", {}).get("events", {}), float(meta.get("fps", 30.0)))
	set_look("toon", true)
	_rng.randomize()
	_find_moves()
	_play(idle_clip(), 0.0, true)
	# His own breath: a squad's men don't stand in step.
	player.seek(_rng.randf() * float(clips.get(idle_clip(), {}).get("length", 1.0)), true)


## Wears the sidecar's faces and kit named in `chosen`: the meshes the other
## faces show go, and so do the meshes a chosen variant's `hide` names (the
## brute's pauldrons); a chosen face's `albedo` swaps a mesh's base colour for
## that file next to the sidecar (the brute's scar is painted into his body's).
func _dress(chosen: Array) -> void:
	var variants: Dictionary = meta.get("faces", {}).merged(meta.get("kit", {}))
	if variants.is_empty():
		return
	var shown := {}
	var hidden := {}
	var albedo := {}
	for f in chosen:
		var v: Dictionary = variants.get(f, {})
		for m in v.get("show", []):
			shown[m] = true
		for m in v.get("hide", []):
			hidden[m] = true
		albedo.merge(v.get("albedo", {}), true)
	for f in variants:
		for m in variants[f].get("show", []):
			if not shown.has(m):
				hidden[m] = true
	for m in hidden:
		var mi := model.find_child(m, true, false) as MeshInstance3D
		if mi:
			mi.get_parent().remove_child(mi)
			mi.free()
	for m in albedo:
		var mi := model.find_child(m, true, false) as MeshInstance3D
		var tex: Texture2D = load(String(profile.meta).get_base_dir().path_join(albedo[m]))
		if mi == null or tex == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i) as StandardMaterial3D
			if src:
				var mat: StandardMaterial3D = src.duplicate()
				mat.albedo_texture = tex
				mi.set_surface_override_material(i, mat)


## The sidecar's clips matched to the model's animations, with the sidecar's
## lengths and loops put back (the importer adds a held last frame and drops
## the loop flags).
func _read_clips() -> void:
	var names := player.get_animation_list()
	for c in meta.clips:
		var info: Dictionary = meta.clips[c]
		var anim := ""
		for n in names:
			if String(n) == c or String(n).ends_with("|" + c) or String(n).ends_with("/" + c):
				anim = n
				break
		if anim == "":
			for n in names:
				if String(n).to_lower() == String(c).to_lower() or String(n).to_lower().ends_with("|" + String(c).to_lower()):
					anim = n
					break
		if anim == "":
			continue
		var a := player.get_animation(anim)
		var length := float(info.get("length", info.get("duration_seconds", a.length)))
		var loop := bool(info.get("loop", false))
		# (Not by a sidecar length rounded a hair under the clip's own.)
		if length > 0.05 and length < a.length - 0.5 / float(meta.get("fps", 30.0)):
			a.length = length
		a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		var speed := float(info.get("speed_mps", info.get("walk_speed_m_s", 0.0)))
		if speed <= 0.0 and info.get("root_vel") is Array:
			var v: Array = info.root_vel
			speed = Vector3(v[0], v[1], v[2]).length()
		clips[c] = {"anim": anim, "length": a.length, "loop": loop, "speed": speed, "events": _events(info.get("events", []))}
	# A move whose clip the export names otherwise (the profile's `moves`) has it under the move's name.
	for m in profile.get("moves", {}):
		var c: String = profile.moves[m]
		if clips.has(c) and not clips.has(m):
			clips[m] = clips[c]
			meta.clips[m] = meta.clips[c]
			clips.erase(c)
			meta.clips.erase(c)


## Events as [[seconds, name], ...] in time order, from any of the sidecar
## forms: {name: t}, {name: [t, t]}, {name: [[t, label], ...]}, or
## [{name, time | seconds}, ...].
static func _events(src: Variant) -> Array:
	var out := []
	if src is Dictionary:
		for k in src:
			var v: Variant = src[k]
			if v is float or v is int:
				out.append([float(v), k])
			elif v is Array:
				for e in v:
					if e is Array and e.size() >= 2:
						out.append([float(e[0]), "%s:%s" % [k, e[1]]])
					elif e is float or e is int:
						out.append([float(e), k])
	elif src is Array:
		for e in src:
			if e is Dictionary:
				out.append([float(e.get("time", e.get("seconds", 0.0))), String(e.get("name", ""))])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out


func _named(mi: Node, parts: Array) -> bool:
	for p in parts:
		if String(mi.name).contains(p):
			return true
	return false


# --- Look ---------------------------------------------------------------------------

## "toon" (hard light and shadow bands), "flat" (texture only) or "pbr" (the
## import as it is); the ink outline on or off.
func set_look(mode: String, outline: bool) -> void:
	for s in _surfaces:
		var src: Material = s[2]
		var m: StandardMaterial3D = src.duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		if _named(s[0], profile.get("two_sided", [])):
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if profile.get("opaque", true):
			m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		match mode:
			"toon":
				m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				m.metallic = 0.0
				m.roughness = 1.0
			"flat":
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var line: ShaderMaterial = null
		if outline and not _named(s[0], profile.get("no_outline", [])):
			line = _outline_thin if _named(s[0], profile.get("thin_outline", [])) else _outline
		m.next_pass = line
		s[0].set_surface_override_material(s[1], m)


func set_outline_width(metres: float) -> void:
	_outline.set_shader_parameter("width", metres)
	_outline_thin.set_shader_parameter("width", metres * 0.35)


func height_m() -> float:
	return float(meta.get("height_m", profile.get("height", 1.8))) * _k()


func title() -> String:
	return profile.get("title", name)


## The model's scale (the profile's `scale`): his strides, reach and travel grow with it.
func _k() -> float:
	return float(profile.get("scale", 1.0))


func yaw_of(d: Vector3) -> float:
	return atan2(d.x, d.z)


func forward() -> Vector3:
	return Vector3(sin(rotation.y), 0, cos(rotation.y))


# --- Clips ----------------------------------------------------------------------------

func idle_clip() -> String:
	if stance != "":
		return stance
	if _ready_left > 0.0 and clips.has(profile.get("ready", "")):
		return profile.ready
	return profile.get("idle", "idle")


## The idle's variants from the sidecar: `clips`, `every_s` (the pause
## between them), `hold_s` (how long a looping one plays) and `blend_s`.
func _variants() -> Dictionary:
	return meta.get("variants", {}).get("idle", {})


## Holds the ready clip for READY_HOLD (after a blow or a hit).
func _keep_ready() -> void:
	if clips.has(profile.get("ready", "")):
		_ready_left = READY_HOLD
		_variant_left = 0.0


## Metres a second on the walk clip (a model scaled up strides farther), or
## the game's speed at its pace.
func walk_speed() -> float:
	if pace == "game":
		return tile_m / GAME_TILE_TIME
	return maxf(float(clips.get(profile.get("walk", "walk"), {}).get("speed", 1.0)), 0.3) * _k()


func run_speed() -> float:
	return clip_speed("run")


## A clip's ground speed (metres a second), as he is scaled.
func clip_speed(c: String) -> float:
	return float(clips.get(c, {}).get("speed", 0.0)) * _k()


func clip_names() -> Array:
	var out := clips.keys()
	out.sort()
	return out


func has_clip(c: String) -> bool:
	return clips.has(c)


## The cross-fade into clip c: the profile's `blend` for it, else `fallback`.
func _blend_of(c: String, fallback: float) -> float:
	return float(profile.get("blend", {}).get(c, fallback))


## Play clip c, faded in over `blend` (the profile's `blend` for c instead
## unless `exact`), at `speed` on top of his playback.
func _play(c: String, blend := BLEND, exact := false, speed := 1.0) -> void:
	if not clips.has(c):
		return
	_clip = c
	_ev_i = 0
	_prev_t = 0.0
	player.speed_scale = playback
	player.play(clips[c].anim, blend if exact else _blend_of(c, blend), speed)
	if fx:
		fx.on_play(clips[c].anim)
	if c == idle_clip() and stance == "":
		_idle_t_prev = 0.0
		var every: Array = _variants().get("every_s", profile.get("variant_every", [9.0, 22.0]))
		_variant_in = _rng.randf_range(every[0], every[1])


## Play clip c from its start, also if it is playing now (a second blow): a
## clip started anew fades in as `_play` would.
func _replay(c: String, blend: float) -> void:
	var again := _clip == c and player.is_playing()
	_play(c, blend)
	if again:
		player.seek(0.0, true)


## Seconds into clip c of its event `ev`, or -1.
func _event_at(c: String, ev: String) -> float:
	for e in clips.get(c, {}).get("events", []):
		if e[1] == ev:
			return e[0]
	return -1.0


## What the panel offers: the profile's attacks, stances and its other clips,
## and the moves he has.
func actions() -> Array:
	var out := []
	var atks: Array = profile.get("attacks", [])
	for i in atks.size():
		if clips.has(atks[i].clip):
			out.append({"id": "attack:%d" % i, "label": atks[i].get("label", atks[i].clip), "target": true})
	for s in profile.get("stances", []):
		if clips.has(s):
			out.append({"id": "stance:" + s, "label": String(s).capitalize(), "toggle": true})
	if can_charge():
		out.append({"id": "charge", "label": profile.get("labels", {}).get("charge", "Charge"), "target": true})
	if profile.get("counter", false):
		out.append({"id": "counter", "label": "Counter", "target": true})
	if has_block():
		out.append({"id": "stance:block", "label": "Block", "toggle": true})
	if can_step_lane():
		out.append({"id": "lane", "label": "Step lane"})
	return out


func attack_info(i: int) -> Dictionary:
	var atks: Array = profile.get("attacks", [])
	return atks[i] if i >= 0 and i < atks.size() else {}


## The profile's attack that plays clip c, or -1.
func _attack_of(c: String) -> int:
	var atks: Array = profile.get("attacks", [])
	for i in atks.size():
		if atks[i].clip == c:
			return i
	return -1


## Where to stand to strike with attack i (centre to centre, metres): its
## `reach`, else where its blade reaches from (strike_dist), else the
## profile's; and whether it is shot from afar.
func reach(i: int) -> float:
	var a := attack_info(i)
	if a.has("reach"):
		return float(a.reach)
	if meta.clips.get(a.get("clip", ""), {}).has("tip_reach_m"):
		return strike_dist(a.clip)
	return float(profile.get("reach", 1.5))


func is_ranged(i: int) -> bool:
	return attack_info(i).has("missile")


## Where he stands to strike with clip c (an attack or a charge's strike),
## centre to centre, from its blade's reach (tip_reach_m): the tip a little
## past the target's centre. The profile's reach if the clip gives none.
func strike_dist(c: String) -> float:
	var tip := float(meta.clips.get(c, {}).get("tip_reach_m", 0.0))
	if tip <= 0.0:
		return float(profile.get("reach", 1.5))
	return tip * _k() - (THRUST_INTO if is_thrust(c) else SLASH_INTO)


## A thrust (the stab, the lunge) rather than a slash.
func is_thrust(c: String) -> bool:
	return "stab" in c or "thrust" in c


## How far (centre to centre) a blow of attack `a` lands: its blade's tip
## reach and TIP_SLACK where the clip gives it and the attack names no reach,
## else its reach and OVER.
func _land_dist(a: Dictionary) -> float:
	var tip := float(meta.clips.get(a.get("clip", ""), {}).get("tip_reach_m", 0.0))
	if tip > 0.0 and not a.has("reach"):
		return tip * _k() + TIP_SLACK
	return float(a.get("reach", profile.get("reach", 1.5))) + OVER


## The attacks a squad's man uses (indices): those whose clips are in `names`
## (all of his, if it is empty) and that he has.
func squad_attacks(names: Array = []) -> Array:
	var out := []
	var atks: Array = profile.get("attacks", [])
	for i in atks.size():
		if clips.has(atks[i].clip) and (names.is_empty() or atks[i].clip in names):
			out.append(i)
	return out


## Whether attack i suits a foe `d` away: from its `near` nearer than its
## reach (any nearer if it gives none) to its `over` farther (OVER, or none for a shot).
func _fits(i: int, d: float) -> bool:
	var a := attack_info(i)
	var r := reach(i)
	return d <= r + float(a.get("over", 0.0 if is_ranged(i) else OVER)) and d >= r - float(a.get("near", INF))


## One of his squad's attacks (`names`, see squad_attacks) that suits
## `target` from where he stands (_fits), at random by their `weight` (1 if
## not given; an attack of weight 0 is used only when asked for by name); the
## first of them if none does. Without a target, any of them by weight.
func pick_attack(target: Node3D, names: Array = []) -> int:
	var all := squad_attacks(names)
	if all.is_empty():
		return 0
	var fit := all.filter(func(i): return float(attack_info(i).get("weight", 1.0)) > 0.0)
	if target != null:
		var d := Vector2(target.position.x - position.x, target.position.z - position.z).length()
		fit = fit.filter(func(i): return _fits(i, d))
	if fit.is_empty():
		return all[0]
	var total := 0.0
	for i in fit:
		total += float(attack_info(i).get("weight", 1.0))
	var r := _rng.randf() * total
	for i in fit:
		r -= float(attack_info(i).get("weight", 1.0))
		if r < 0.0:
			return i
	return fit[fit.size() - 1]


## Seconds from the start of attack i to its first blow or shot, at his playback.
func hit_lead(i: int) -> float:
	var a := attack_info(i)
	if a.is_empty() or not clips.has(a.clip):
		return 0.0
	var c: Dictionary = clips[a.clip]
	var names: Array = a.get("hits", HIT_EVENTS)
	var t: float = float(c.length) * float(a.get("hit_at", 0.45))
	for e in c.events:
		if String(e[1]) in names or String(e[1]).get_slice(":", 0) in names:
			t = e[0]
			break
	return t / maxf(playback, 0.05)


## A blow or a shot at `target`, as a squad's man strikes: attack i, or one
## of his that reaches it (pick_attack).
func strike_at(target: Node3D, i := -1) -> void:
	if is_dead() or target == null:
		return
	strike(target, i if i >= 0 else pick_attack(target))


## Where attack i's missile leaves (the current attack's when i < 0), in the
## world: the sidecar's `shot_from` for its clip (the middle of the archer's
## arrow as he looses, in the model's axes), or Vector3.INF where it has none.
func missile_from(i := -1) -> Vector3:
	var a: Dictionary = attack_info(i) if i >= 0 else _attack
	var p: Variant = meta.get("clips", {}).get(a.get("clip", ""), {}).get("shot_from")
	if not (p is Array and p.size() == 3):
		return Vector3.INF
	var local: Vector3 = model.transform * Vector3(p[0], p[1], p[2])
	return global_transform * local if is_inside_tree() else transform * local


# --- Orders ---------------------------------------------------------------------------

func is_dead() -> bool:
	return state == "dead"


func stop() -> void:
	if is_dead():
		return
	path.clear()
	_then = Callable()
	_yaw_goal = NAN
	_after_turn = Callable()
	_counter_target = null
	state = "idle"
	_play(idle_clip())


## Walk the route (points on the ground), then `then`. With the march (the
## stop) he halts on its end, with turns he turns in place first (_march); the
## shield comes down first.
func order_move(points: Array, then := Callable()) -> void:
	if is_dead():
		return
	if block_held:
		set_block(false)
	path = points.duplicate()
	_then = then
	stance = ""
	_yaw_goal = NAN
	_after_turn = Callable()
	if path.is_empty():
		_arrive()
		return
	if can_march() or can_step_turn():
		_march()
		return
	if state != "walk":
		state = "walk"
		_play(profile.get("walk", "walk"), 0.18)


## `blend`: the idle's cross-fade, exactly (a clip that ends in its first pose), or its own.
func _arrive(blend := -1.0) -> void:
	path.clear()
	speed_now = 0.0
	state = "idle"
	_play(idle_clip(), blend if blend >= 0.0 else 0.25, blend >= 0.0)
	_raise_block()
	var t := _then
	_then = Callable()
	if t.is_valid():
		t.call()


## Turn to face a point, then `then`: a turn in place (a turn clip) for a
## change of heading of STEP_TURN_MIN or more where he has them, else on the spot.
func turn_to(at: Vector3, then := Callable()) -> void:
	var d := at - position
	if Vector2(d.x, d.z).length() < 1e-3:
		if then.is_valid():
			then.call()
		return
	var yaw := atan2(d.x, d.z)
	var delta := rad_to_deg(angle_difference(rotation.y, yaw))
	if can_step_turn() and absf(delta) >= STEP_TURN_MIN and not is_dead():
		_start_turn(delta, then)
		return
	_yaw_goal = yaw
	_after_turn = then
	if absf(angle_difference(rotation.y, _yaw_goal)) < deg_to_rad(4.0):
		rotation.y = _yaw_goal
		_yaw_goal = NAN
		_after_turn = Callable()
		if then.is_valid():
			then.call()


## Turn to face a heading (radians), then `then` (turn_to).
func face(yaw: float, then := Callable()) -> void:
	turn_to(position + Vector3(sin(yaw), 0, cos(yaw)), then)


## Face the target and play attack i; its blows land at the clip's events.
func strike(target: Node3D, i: int) -> void:
	if is_dead():
		return
	var a := attack_info(i)
	if a.is_empty() or not clips.has(a.clip):
		return
	path.clear()
	_then = Callable()
	stance = ""
	_target = target
	if target:
		turn_to(target.global_position, _swing.bind(i))
	else:
		_swing(i)


## Strike now where he faces: attack `clip`, or one that suits the target's
## distance (pick_attack).
func attack(target: Node3D = null, clip := "") -> void:
	if is_dead():
		return
	var i := _attack_of(clip) if clip != "" else pick_attack(target)
	if attack_info(i).is_empty() or not clips.has(attack_info(i).clip):
		return
	path.clear()
	_then = Callable()
	stance = ""
	_target = target
	_swing(i)


## Walk up to `target` and strike it: the attack is picked first (by weight)
## and he halts where it reaches; if it no longer suits where he came to rest
## (the march halts in whole strides), one that does.
func attack_target(target: Node3D) -> void:
	if is_dead() or target == null:
		return
	var i := pick_attack(null)
	var from := position - target.position
	from.y = 0
	if from.length() < 0.01:
		from = -forward()
	var spot := target.position + from.normalized() * reach(i)
	var go := func():
		if not is_instance_valid(target):
			return
		var d := Vector2(target.position.x - position.x, target.position.z - position.z).length()
		strike(target, i if _fits(i, d) else pick_attack(target))
	if position.distance_to(spot) < 0.15:
		go.call()
	else:
		order_move([spot], go)
	_target = target


func _swing(i: int) -> void:
	if is_dead():
		return
	var a := attack_info(i)
	_attack = a
	_hits = []
	var c: Dictionary = clips[a.clip]
	var names: Array = a.get("hits", HIT_EVENTS)
	for e in c.events:
		if String(e[1]) in names or String(e[1]).get_slice(":", 0) in names:
			_hits.append(e[0])
	if _hits.is_empty():
		_hits.append(c.length * float(a.get("hit_at", 0.45)))
	var from_idle: bool = _clip == profile.get("idle", "idle") and profile.has("ready")
	_keep_ready()
	state = "attack"
	_play(a.clip, READY_BLEND if from_idle else 0.12)


func _strike_now() -> void:
	var a := _attack
	if a.has("missile"):
		last_impact = "%s loosed" % a.get("label", a.clip)
		release.emit(_target, String(a.missile))
		return
	if _target == null or not is_instance_valid(_target):
		last_impact = "%s at the air" % a.get("label", a.clip)
		impact.emit(null, false, 0.0)
		return
	var to := _target.global_position - global_position
	to.y = 0
	var ang := rad_to_deg(absf(angle_difference(rotation.y, atan2(to.x, to.z))))
	var landed := to.length() <= _land_dist(a) and ang <= float(profile.get("hit_arc", HIT_ARC))
	last_impact = "%s %s at %.2f m, %d° off the facing" % [a.get("label", a.clip), "lands" if landed else "misses", to.length(), int(ang)]
	impact.emit(_target, landed, to.length())


## A blow from `from` (a ground point): the hit reaction, or the death. He
## turns to the blow (unless the profile's `face_blow` is false; a lethal one always).
func take_hit(from: Vector3, lethal := false) -> void:
	if is_dead():
		return
	var d := from - global_position
	if Vector2(d.x, d.z).length() > 0.05 and (profile.get("face_blow", true) or lethal):
		rotation.y = atan2(d.x, d.z)
	if lethal:
		die()
		return
	hit()


## The hit reaction where he faces: on the shield if it is up (it stays up).
func hit() -> void:
	if is_dead():
		return
	path.clear()
	_then = Callable()
	stance = ""
	_counter_target = null
	if state == "turn":
		# A blow cuts a turn in place short, and what was to follow it.
		_turn = {}
		_after_turn = Callable()
	if has_block() and state in ["block", "block_hit"]:
		state = "block_hit"
		_replay("block_hit", 0.08)
		return
	_keep_ready()
	state = "hit"
	var c: String = profile.get("hit", "hit")
	if clips.has(c):
		_replay(c, 0.08)
		return
	# No hit clip (the wolf scout): the body rocks back from the blow and steadies.
	var p := maxf(playback, 0.1)
	var tw := create_tween()
	tw.tween_property(model, "rotation:x", -0.2, 0.08 / p).set_ease(Tween.EASE_OUT)
	tw.tween_property(model, "rotation:x", 0.0, 0.4 / p).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		if state == "hit":
			state = "idle")


func die() -> void:
	if is_dead():
		return
	path.clear()
	_then = Callable()
	_yaw_goal = NAN
	_after_turn = Callable()
	_counter_target = null
	_turn = {}
	state = "dead"
	# One of its deaths, at random (the spearman falls three ways).
	var deaths: Array = profile.get("deaths", []).filter(func(c): return clips.has(c))
	_play(deaths[_rng.randi_range(0, deaths.size() - 1)] if not deaths.is_empty() else profile.get("death", "death"), 0.12)


func revive() -> void:
	state = "idle"
	path.clear()
	stance = ""
	block_held = false
	_ready_left = 0.0
	_play(idle_clip(), 0.5, true)


## Any clip, once (a looping clip until the next order).
func play_clip(c: String) -> void:
	if not clips.has(c):
		return
	path.clear()
	_then = Callable()
	_yaw_goal = NAN
	if c == profile.get("death", "death") or c in profile.get("deaths", []):
		path.clear()
		state = "dead"
		_play(c, 0.12, true)
		player.seek(0.0, true)
		return
	state = "clip"
	_play(c, 0.15, true)
	player.seek(0.0, true)


func toggle_stance(s: String) -> void:
	if is_dead():
		return
	if s == "block" and has_block():
		set_block(not block_held)
		return
	if not clips.has(s):
		return
	stance = "" if stance == s else s
	path.clear()
	state = "idle"
	_play(idle_clip(), 0.3)


## One frame of a clip, held (for review captures).
func pose_at(c: String, seconds: float) -> void:
	if not clips.has(c):
		return
	state = "pose"
	_clip = c
	player.play(clips[c].anim, 0.0)
	player.seek(seconds, true)
	player.pause()
	if fx:
		fx.preview(clips[c].anim, seconds)


func set_fx(on: bool) -> void:
	if fx:
		fx.enabled = on
		if not on:
			fx.clear()


func _on_finished(_anim: StringName) -> void:
	match state:
		"attack":
			# A shot is followed by its reload (the crossbowman's bolt comes back).
			var then := String(_attack.get("then", ""))
			if then != "" and clips.has(then):
				state = "clip"
				_play(then, 0.15)
			else:
				state = "idle"
				_play(idle_clip(), 0.25)
				_raise_block()
		"hit":
			state = "idle"
			_play(idle_clip(), _blend_of(profile.get("hit", "hit"), 0.25), true)
			_raise_block()
			if _counter_target != null:
				_answer_counter()
		"clip":
			state = "idle"
			_play(idle_clip(), 0.25)
		"start":
			# The start ends on the walk's stride (within a centimetre): carry
			# straight on from it, posed now and with no cross-fade. A fade's first
			# frame holds the start's last pose and the next jumps two frames on.
			state = "walk"
			_play(profile.get("walk", "walk"), 0.0, true)
			player.seek(float(meta.clips.start.exit_walk_t), true)
			_walk_t_prev = player.current_animation_position
		"stop":
			# The stop ends in idle's first pose.
			_arrive(0.05)
		"charge_hit", "lane":
			# Both end in idle's first pose (the lane step one file over).
			state = "idle"
			_play(idle_clip(), 0.05, true)
			_raise_block()
		"block_hit":
			# It ends in the block's first pose.
			if block_held:
				state = "block"
				_play("block", 0.05, true)
			else:
				state = "idle"
				_play(idle_clip(), 0.25)
			if _counter_target != null:
				_answer_counter()
		"turn":
			_turn_by(_turn.want)
			_turn = {}
			# Every turn ends in idle's first pose, turned (and the cape settles).
			state = "idle"
			_play(idle_clip(), CAPE_SETTLE if not meta.get("cape_bones", []).is_empty() else 0.05, true)
			var t := _after_turn
			_after_turn = Callable()
			if t.is_valid():
				t.call()
		"idle":
			# An idle variant played out: back to the idle.
			if _clip != idle_clip():
				_play(idle_clip(), float(_variants().get("blend_s", 0.3)))


# --- Moves ------------------------------------------------------------------------------

## The moves his clips make possible (see the header), and with `plant_feet`
## his feet: the ankle's height at rest and, for the charge, where the run has
## his front foot as he sets off.
func _find_moves() -> void:
	if profile.get("plant_feet", false) and skeleton:
		for side in ["Left", "Right"]:
			var b := _bone(side + "Foot")
			if b >= 0:
				_feet[side] = {"bone": b, "down": false, "at": Vector3.ZERO, "max": 0.0, "prev": Vector3.ZERO}
		if _feet.size() < 2:
			_feet = {}
	_moves = {
		"march": _clip_has("stop", ["root_path", "enter_walk_t"]) and clips.has(profile.get("walk", "walk")),
		"start": _clip_has("start", ["root_path", "exit_walk_t"]),
		"turns": ["turn_90", "turn_90_r", "turn_180"].all(func(c): return _clip_has(c, ["root_yaw"])),
		"block": clips.has("block") and clips.has("block_hit"),
		"lane": _clip_has("lane", ["root_path"]),
		"charge": not _feet.is_empty() and clips.has("run") and not strikes().is_empty(),
	}
	if _feet.is_empty():
		return
	if _moves.charge:
		_play("run", 0.0, true)
		player.seek(CHARGE_LAUNCH_T, true)
		_launch_run_foot = _local_foot("Left")
	_play(idle_clip(), 0.0, true)
	player.advance(0.0)
	_ankle_rest = _foot_pos("Left").y - position.y


## Whether he has clip c with all of `keys` in its sidecar entry.
func _clip_has(c: String, keys: Array) -> bool:
	if not clips.has(c):
		return false
	var info: Dictionary = meta.clips.get(c, {})
	return keys.all(func(k): return info.has(k))


func can_march() -> bool:
	return _moves.get("march", false)


func can_step_turn() -> bool:
	return _moves.get("turns", false)


func can_charge() -> bool:
	return _moves.get("charge", false)


func has_block() -> bool:
	return _moves.get("block", false)


func can_step_lane() -> bool:
	return _moves.get("lane", false)


## The charge's strikes his export has: each with its travel, the point of the
## run it takes over at and its blow.
func strikes() -> Array:
	return CHARGE_STRIKES.filter(func(c): return _clip_has(c, ["root_path", "enter_run_t"]) and _event_at(c, "contact") >= 0.0)


## The march's pace (see `pace`); a walk under way takes it up at once.
func set_pace(p: String) -> void:
	pace = p
	if state == "walk" and can_march():
		_start_walk()


func _bone(suffix: String) -> int:
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_name(i).ends_with(suffix):
			return i
	return -1


## The skeleton's place in his own space (through the model and any node between).
func _skeleton_xf() -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = skeleton
	while n != null and n != self:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## A foot's ankle in his parent's space (as `position`), in the tree or not.
func _foot_pos(side: String) -> Vector3:
	return transform * _skeleton_xf() * skeleton.get_bone_global_pose(_feet[side].bone).origin


## A foot in his own space (on the ground plane), whatever his place and facing.
func _local_foot(side: String) -> Vector3:
	var p := _skeleton_xf() * skeleton.get_bone_global_pose(_feet[side].bone).origin
	return Vector3(p.x, 0, p.z)


## A clip's travel at time t (his x = his left, y = forward), from its first frame.
func root_at(c: String, t: float) -> Vector2:
	var rp: Array = meta.clips[c].root_path
	var f := clampf(t * float(meta.get("fps", 30.0)), 0.0, rp.size() - 1.0)
	var i := int(f)
	var j := mini(i + 1, rp.size() - 1)
	return Vector2(rp[i][0], rp[i][1]).lerp(Vector2(rp[j][0], rp[j][1]), f - i) * _k()


## How far forward a clip's travel takes him.
func travel_of(c: String) -> float:
	var rp: Array = meta.clips[c].root_path
	return float(rp[rp.size() - 1][1]) * _k()


## What is left of the march, along its corners.
func path_length() -> float:
	var total := 0.0
	var at := position
	for q in path:
		total += Vector2(q.x - at.x, q.z - at.z).length()
		at = q
	return total


## The point `dist` along the march from where he stands (its end, if shorter).
func _ahead(dist: float) -> Vector3:
	var at := Vector3(position.x, 0, position.z)
	var left := dist
	for q in path:
		var leg := Vector3(q.x - at.x, 0, q.z - at.z)
		if leg.length() >= left:
			return at + leg.normalized() * left
		left -= leg.length()
		at = Vector3(q.x, 0, q.z)
	return at


## Move `dist` along the march (straight on once it runs out, or back along
## his facing for a step backwards), turning toward the way ahead.
func _move_along(dist: float, sdt: float) -> void:
	if dist < 0.0:
		position += forward() * dist
	var left := maxf(dist, 0.0)
	while left > 1e-6:
		if path.is_empty():
			position += forward() * left
			break
		var to: Vector3 = path[0] - position
		to.y = 0
		var dl := to.length()
		# A last point just passed, or beside him, is reached: he walks on as he faces.
		if dl < 1e-4 or (path.size() == 1 and dl < 0.5 and to.dot(forward()) < 0.0):
			path.pop_front()
			continue
		if left >= dl:
			position = Vector3(path[0].x, position.y, path[0].z)
			path.pop_front()
			left -= dl
		else:
			position += to / dl * left
			left = 0.0
	if not path.is_empty():
		var ahead: Vector3 = path[0] - position
		ahead.y = 0
		# Close to the last point the way to it swings about: he keeps his heading.
		if ahead.length() > (0.8 if path.size() == 1 else 0.05):
			_steer(yaw_of(ahead), sdt)


## The foot he can turn on: the one on the ground while the other swings (or
## his centre with both in the air, or without planted feet); none while both are down.
func _pivot() -> Variant:
	if _feet.is_empty():
		return position
	var l := _foot_pos("Left")
	var r := _foot_pos("Right")
	var dl := l.y - position.y < _ankle_rest + 0.035 * _k()
	var dr := r.y - position.y < _ankle_rest + 0.035 * _k()
	if dl and dr:
		return null
	if dl:
		return Vector3(l.x, 0, l.z)
	if dr:
		return Vector3(r.x, 0, r.z)
	return position


## Turn toward a heading on the move, about the planted foot.
func _steer(yaw: float, sdt: float) -> void:
	var dy := clampf(angle_difference(rotation.y, yaw), -FOOT_STEER_RATE * sdt, FOOT_STEER_RATE * sdt)
	if absf(dy) < 1e-5:
		return
	var pv = _pivot()
	if pv == null:
		return
	rotation.y += dy
	var off: Vector3 = position - pv
	off.y = 0
	position = Vector3(pv.x, position.y, pv.z) + off.rotated(Vector3.UP, dy)


## The march along `path`: on from where he is if he is already under way,
## else from a standstill (a turn in place first with `step_turns`).
func _march() -> void:
	_target = null
	_stop_cue = {}
	if state in ["walk", "start"]:
		return
	if state in ["stop", "charge"]:
		# Off again before he has settled (or off the charge): straight into the stride.
		_full_march = path_length() >= travel_of("stop") + 0.3
		_march_run = Vector2.ZERO
		_start_walk()
		return
	# A first corner within half a metre is the centre of the tile he already
	# stands on (a squad's men stand off it): it would put a sharp corner in
	# the middle of his first step, so he heads straight for the next one.
	while path.size() > 1 and Vector2(path[0].x - position.x, path[0].z - position.z).length() < 0.5:
		path.pop_front()
	var d: Vector3 = path[0] - position
	d.y = 0
	if d.length() < 0.01:
		path.pop_front()
		if path.is_empty():
			_arrive()
			return
	# From a standstill a large change of heading is a turn in place first,
	# toward where the march leads over his first steps.
	d = _ahead(1.2) - position
	d.y = 0
	var delta := rad_to_deg(angle_difference(rotation.y, yaw_of(d)))
	if step_turns and can_step_turn() and absf(delta) >= STEP_TURN_MIN and state in ["idle", "block"]:
		_start_turn(delta, _set_off)
	else:
		_set_off()


## From a standstill: the start step and the stop when the march is long
## enough for both at their shortest stretch, with the walk between them up to
## the stride the stop joins at (without a start, the walk under way to it:
## _march_walk); otherwise straight into the walk to the spot.
func _set_off() -> void:
	if not can_march():
		_start_walk()
		return
	var walk: String = profile.get("walk", "walk")
	var L := float(clips[walk].length)
	var enter := float(meta.clips.stop.enter_walk_t)
	var start := walk_speed() * fposmod(enter - float(meta.clips[walk].get("start_from_idle", 0.0)), L)
	if start < 0.5 * walk_speed() * L:
		start += walk_speed() * L
	if _moves.start:
		start = travel_of("start") + walk_speed() * fposmod(enter - float(meta.clips.start.exit_walk_t), L)
	_full_march = pace != "game" and path_length() >= (start + travel_of("stop")) * (1.0 - SLACK)
	_march_run = Vector2.ZERO
	if _full_march and _moves.start:
		state = "start"
		_root_prev = Vector2.ZERO
		# The whole march planned at once: the start, whole strides, the stop.
		_stretch = _plan(path_length(), start + travel_of("stop"), walk_speed() * L).stretch
		_play("start")
	else:
		_start_walk()


func _start_walk() -> void:
	var walk: String = profile.get("walk", "walk")
	var from_still := state not in ["walk", "start", "stop"]
	state = "walk"
	_stop_cue = {}
	var spd := 1.0
	if pace == "game":
		spd = float(clips[walk].length) / GAME_STRIDE
	_play(walk, BLEND, false, spd)
	# From a standstill the cycle starts where its feet are nearest his stance.
	if from_still:
		player.seek(float(meta.clips[walk].get("start_from_idle", 0.0)))
	_walk_t_prev = player.current_animation_position


## The plan for a distance R covered by `fixed` metres plus whole strides of C:
## how many strides, and the one stretch (within `slack`) that best balances
## coming to rest off the target (`tolerance` is a normal miss) against
## stretching his steps (STRETCH_TYPICAL is a normal stretch). `over`: the
## tolerance for coming to rest past the target, if not `tolerance`;
## `max_over`: how far past it he may come at all (beyond, a plan only if no other).
func _plan(R: float, fixed: float, C: float, slack: float = SLACK, tolerance: float = ARRIVE_TOLERANCE, over: float = -1.0, max_over: float = INF) -> Dictionary:
	var a_short := 1.0 / (tolerance * tolerance)
	var a_over := a_short if over <= 0.0 else 1.0 / (over * over)
	var b := 1.0 / (STRETCH_TYPICAL * STRETCH_TYPICAL)
	var best := {}
	for k in range(0, 64):
		var X := fixed + k * C
		if k > 0 and X > R + C:
			break
		# The best stretch for each side of the target; the better of the two.
		var cand := []
		for a in [a_short, a_over]:
			var st := clampf((a * X * R + b) / (a * X * X + b), 1.0 - slack, 1.0 + slack)
			var off := R - st * X
			var w: float = a_short if off >= 0.0 else a_over
			cand.append([w * off * off + b * (st - 1.0) * (st - 1.0), st])
		var pick: Array = cand[0] if cand[0][0] <= cand[1][0] else cand[1]
		var st: float = pick[1]
		var score: float = pick[0]
		if R - st * X < -max_over:
			score += 1000.0
		if best.is_empty() or score < best.score:
			best = {"k": k, "stretch": st, "score": score}
	return best


## `at`: how far the walk has gone past enter_walk_t this frame. The stop starts
## that far in (and its first frame is posed now: a seek otherwise holds the
## pose a frame), so the walk carries straight on into it.
func _begin_stop(at := 0.0) -> void:
	state = "stop"
	_stop_cue = {}
	_root_prev = Vector2.ZERO
	_play("stop")
	player.seek(at, true)


func _start_turn(delta_deg: float, then: Callable) -> void:
	var clip := "turn_90" if delta_deg > 0.0 else "turn_90_r"
	if absf(delta_deg) > 135.0:
		clip = "turn_180"
	var curve: Array = meta.clips[clip].root_yaw
	var total := float(curve[curve.size() - 1])
	var want := delta_deg
	# The 180 turn steps round one way only; a turn the other way goes the long way round to match it.
	if clip == "turn_180" and signf(want) != signf(total):
		want -= 360.0 * signf(want)
	var p: Array = meta.clips[clip].get("pivot", [0.0, 0.0])
	_turn = {"clip": clip, "curve": curve, "scale": want / total, "start": rotation.y, "want": deg_to_rad(want),
		"at": position, "pivot": Vector3(p[0], 0.0, p[1]) * _k()}
	_after_turn = then
	_yaw_goal = NAN
	# From the idle into a turn that starts on the ready stance (the spearman's
	# guard): blended as an attack is, and he ends it on guard.
	var from_idle: bool = _clip == profile.get("idle", "idle") and profile.has("ready")
	_keep_ready()
	state = "turn"
	_play(clip, READY_BLEND if from_idle else BLEND)


## The turn in place `yaw` (radians) on from its start, about its pivot (the
## sidecar's `pivot`, in his own space: the spearman's hips over his guard, off
## his origin; else the origin), so the body stays where the clip has it.
func _turn_by(yaw: float) -> void:
	rotation.y = _turn.start + yaw
	var pv: Vector3 = _turn.pivot
	var p: Vector3 = _turn.at + pv.rotated(Vector3.UP, _turn.start) - pv.rotated(Vector3.UP, rotation.y)
	position = Vector3(p.x, position.y, p.z)


## Charge a target (the game's shield_charge): from CHARGE_MIN_TILES or more
## away he runs straight at it, steering about the planted foot, and the run
## brakes into a strike (which takes over the run at one point of the stride,
## its enter_run_t), so that he comes to rest where the strike reaches it as
## the blade lands. Nearer, he walks up and strikes. Returns whether he charges.
func charge(target: Node3D) -> bool:
	if is_dead() or target == null or not can_charge():
		return false
	var to := target.position - position
	to.y = 0
	if to.length() < CHARGE_MIN_TILES * tile_m:
		attack_target(target)
		return false
	path.clear()
	_then = Callable()
	_yaw_goal = NAN
	stance = ""
	_target = target
	_charge_cue = {}
	_stretch = 1.0
	_charge_t = 0.0
	_charge_run = Vector2.ZERO
	_charge_pref = "charge_stab" if clips.has("charge_stab") and _rng.randf() < _share("attack_stab") else "charge_hit"
	_launch_from = _local_foot("Left")
	_launch_w = 0.0 if state in ["idle", "block"] else 1.0
	state = "charge"
	_play("run")
	player.seek(CHARGE_LAUNCH_T)
	_run_t_prev = player.current_animation_position
	return true


## The share of his attacks' weight that clip c's attack has (the stab's: how
## often the charge goes for the stab).
func _share(c: String) -> float:
	var total := 0.0
	for a in profile.get("attacks", []):
		total += float(a.get("weight", 1.0))
	var i := _attack_of(c)
	return float(attack_info(i).get("weight", 1.0)) / total if i >= 0 and total > 0.0 else 0.0


func _begin_charge_hit(c: String, at: float) -> void:
	state = "charge_hit"
	_attack = {"clip": c, "label": "%s (%s)" % [profile.get("labels", {}).get("charge", "Charge"), c]}
	_hits = [_event_at(c, "contact")]
	_play(c)
	player.seek(at, true)
	# The run has already carried him `at` into the clip.
	_root_prev = root_at(c, at)


## The strike's travel for the time the clip moves on this frame (as the run's:
## the node keeps pace with the pose, so the planted foot holds through the
## hand-off), turning to the target until the blow.
func _charge_hit_step(sdt: float) -> void:
	var c: String = _attack.clip
	var r := root_at(c, player.current_animation_position + sdt)
	var d := r - _root_prev
	_root_prev = r
	d.y *= _stretch
	position += Vector3(d.x, 0, d.y).rotated(Vector3.UP, rotation.y)
	speed_now = d.length() / maxf(sdt, 1e-4)
	if not _hits.is_empty() and _target != null and is_instance_valid(_target):
		var to := _target.position - position
		_steer(yaw_of(Vector3(to.x, 0, to.z)), sdt)


## Raise or lower the shield: up whenever he stands, from now on.
func set_block(on: bool) -> void:
	if not has_block():
		return
	block_held = on
	if on and state == "idle":
		state = "block"
		stance = ""
		_play("block")
	elif not on and state == "block":
		state = "idle"
		_play(idle_clip())


func _raise_block() -> void:
	if block_held:
		set_block(true)


## Take a blow and strike back at `target` (the game's counterattack): the hit
## (on the shield, if it is up), then an attack that suits its distance, if it
## is within his first attack's reach and roughly ahead; otherwise only the hit.
func counter(target: Node3D) -> void:
	if state not in ["idle", "block"]:
		return
	hit()
	_counter_target = target


func _answer_counter() -> void:
	var t := _counter_target
	_counter_target = null
	if t == null or not is_instance_valid(t):
		return
	var to := t.position - position
	to.y = 0
	if to.length() > _land_dist(attack_info(0)) or rad_to_deg(absf(angle_difference(rotation.y, yaw_of(to)))) > 100.0:
		last_impact = "too far to strike back"
		return
	strike(t, pick_attack(t))


## Sideways into the lane on his right (one file, about 1.1 m): short steps
## from his guard to his guard, moved by the clip's own travel (`root_path`,
## built for `lane_m`), stretched to the distance asked for.
func step_lane(dist: float) -> void:
	if not can_step_lane() or state not in ["idle", "block"]:
		return
	state = "lane"
	_lane_scale = dist / (float(meta.clips.lane.get("lane_m", dist)) * _k())
	_root_prev = Vector2.ZERO
	_play("lane")


## One of the idle's variants now, at rest only (the footman lab's button).
func idle_variant(blend := -1.0) -> void:
	var variants: Array = _variants().get("clips", profile.get("idle_variants", [])).filter(func(c): return clips.has(c))
	if state == "idle" and stance == "" and not variants.is_empty():
		_start_variant(variants[_rng.randi_range(0, variants.size() - 1)], blend if blend >= 0.0 else _blend_of(idle_clip(), BLEND), true)


func _start_variant(v: String, blend: float, exact := false) -> void:
	_play(v, blend, exact)
	var hold: Array = _variants().get("hold_s", [clips[v].length, clips[v].length])
	_variant_left = _rng.randf_range(hold[0], hold[1])


# --- Frame ------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if player == null or state == "pose":
		return
	var sdt := dt * playback
	speed_now = 0.0
	# Only the walk (its stride kept to the ground covered) and the charge's run
	# play at their own rate.
	if state not in ["walk", "charge"] and player.speed_scale != playback:
		player.speed_scale = playback
	if _ready_left > 0.0 and state != "dead":
		_ready_left -= sdt
	_events_tick()
	if not is_nan(_yaw_goal):
		rotation.y = rotate_toward(rotation.y, _yaw_goal, TURN_RATE * sdt)
		if absf(angle_difference(rotation.y, _yaw_goal)) < 1e-3:
			_yaw_goal = NAN
			var t := _after_turn
			_after_turn = Callable()
			if t.is_valid():
				t.call()
	match state:
		"walk":
			# Planned into the stop, or turning about his planted foot (without
			# planted feet, rounding sharp corners nearly on the spot as before).
			if can_march() and (_full_march or not _feet.is_empty()):
				_march_walk(sdt)
			else:
				_walk(sdt)
		"start", "stop":
			var r := root_at(state, player.current_animation_position)
			var d := r - _root_prev
			_root_prev = r
			d.y *= _stretch
			_move_along(d.y, sdt)
			_march_run += Vector2(d.y / _stretch, d.y)
			position += Vector3(d.x, 0, 0).rotated(Vector3.UP, rotation.y)
			speed_now = d.length() / maxf(sdt, 1e-4)
		"turn":
			var curve: Array = _turn.curve
			var f := clampf(player.current_animation_position * float(meta.get("fps", 30.0)), 0.0, curve.size() - 1.0)
			var i := int(f)
			var j := mini(i + 1, curve.size() - 1)
			_turn_by(deg_to_rad(lerpf(curve[i], curve[j], f - i) * _turn.scale))
		"lane":
			var r := root_at("lane", player.current_animation_position) * _lane_scale
			var d := r - _root_prev
			_root_prev = r
			position += Vector3(d.x, 0, d.y).rotated(Vector3.UP, rotation.y)
			speed_now = d.length() / maxf(sdt, 1e-4)
		"charge":
			_charge(sdt)
		"charge_hit":
			_charge_hit_step(sdt)
		"idle":
			_rest(sdt)
	if not _feet.is_empty():
		_measure_feet(sdt)


## At rest: after his own wait (the sidecar's variants.idle.every_s, counted
## from when the idle began) one of the idle's variants, once, or a looping
## one for its hold_s. With the profile's `variant_on_wrap` it starts as the
## idle comes round to its first frame, the pose both start on.
func _rest(sdt: float) -> void:
	var cfg := _variants()
	if stance == "" and _clip == idle_clip() and _ready_left <= 0.0:
		var t := player.current_animation_position
		var wrapped := t < _idle_t_prev
		_idle_t_prev = t
		_variant_in -= sdt
		var variants: Array = cfg.get("clips", profile.get("idle_variants", []))
		if _variant_in <= 0.0 and not variants.is_empty() and (wrapped or not profile.get("variant_on_wrap", false)):
			var v: String = variants[_rng.randi_range(0, variants.size() - 1)]
			if clips.has(v):
				_start_variant(v, float(cfg.get("blend_s", 0.3)))
			else:
				_variant_in = 30.0
	elif stance == "" and _clip != idle_clip() and clips.get(_clip, {}).get("loop", false):
		# A looping variant (the spearman's guard) has played its hold, or
		# the fight he held his ready stance for is over: back to the idle.
		_variant_left -= sdt
		if _variant_left <= 0.0:
			_play(idle_clip(), float(cfg.get("blend_s", 0.3)))


func _events_tick() -> void:
	if not clips.has(_clip) or not player.is_playing():
		return
	var t := player.current_animation_position
	var evs: Array = clips[_clip].events
	if t < _prev_t:
		_ev_i = 0
	while _ev_i < evs.size() and t >= evs[_ev_i][0]:
		clip_event.emit(evs[_ev_i][1])
		_ev_i += 1
	if state in ["attack", "charge_hit"]:
		while not _hits.is_empty() and t >= _hits[0]:
			_hits.pop_front()
			_strike_now()
	_prev_t = t


func _walk(sdt: float) -> void:
	if path.is_empty():
		_arrive()
		return
	var to: Vector3 = path[0] - position
	to.y = 0
	var dist := to.length()
	if dist < 1e-3:
		path.pop_front()
		return
	var goal := atan2(to.x, to.z)
	rotation.y = rotate_toward(rotation.y, goal, STEER_RATE * sdt)
	# Sharp corners are turned nearly on the spot: no gliding sideways.
	var off := absf(angle_difference(rotation.y, goal))
	var spd := walk_speed() * clampf(1.0 - (off - 0.35) / 1.1, 0.12, 1.0)
	var step := spd * sdt
	if step >= dist:
		position = Vector3(path[0].x, position.y, path[0].z)
		path.pop_front()
		if path.is_empty():
			_arrive()
	else:
		position += to / dist * step
	speed_now = spd
	# The stride keeps pace with the ground covered.
	player.speed_scale = playback * clampf(spd / walk_speed(), 0.35, 1.0)


## The march's walk. With the stop in it (_full_march) every frame
## the plan is remade (_plan): which coming crossing of the stride the stop
## joins at (enter_walk_t) to stop at (k cycles after the next), and the
## stretch of pace and stop that lands him on the target. As in the charge the
## stretch is planned for the whole march, what he has walked counting as
## stretched: replanned for only what is left, it would fade as the march
## shortens and he would miss by up to half a stride. The stop joins a walk
## under way: a crossing within its first half cycle (from a standstill, without
## a start) is passed by. Otherwise he walks the route, turning about his
## planted foot.
func _march_walk(sdt: float) -> void:
	var spd := walk_speed()
	if _full_march:
		var L := player.current_animation_length
		var t := player.current_animation_position
		var enter := float(meta.clips.stop.enter_walk_t)
		var crossed := (_walk_t_prev <= enter and enter < t) or (t < _walk_t_prev and (enter >= _walk_t_prev or enter < t))
		_walk_t_prev = t
		if crossed and not _stop_cue.is_empty() and int(_stop_cue.k) == 0 and not _stop_cue.skip:
			_begin_stop(fposmod(t - enter, L))
			return
		var d_next := walk_speed() * fposmod(enter - t, L)
		var skip := _march_run.x + d_next < 0.5 * walk_speed() * L
		if skip:
			d_next += walk_speed() * L
		_stop_cue = _plan(path_length() + _march_run.y, _march_run.x + d_next + travel_of("stop"), walk_speed() * L)
		_stop_cue.skip = skip
		# What is left takes the stretch that brings the whole march to the plan's.
		var rest := maxf(d_next + int(_stop_cue.k) * walk_speed() * L + travel_of("stop"), 0.5)
		_stretch = clampf((float(_stop_cue.stretch) * (_march_run.x + rest) - _march_run.y) / rest, 1.0 - SLACK, 1.0 + SLACK)
		spd *= _stretch
		_move_along(spd * sdt, sdt)
		_march_run += Vector2(walk_speed(), spd) * sdt
		speed_now = spd
		return
	if path.is_empty():
		_arrive()
		return
	var to: Vector3 = path[0] - position
	to.y = 0
	var dist := to.length()
	var stepd := spd * sdt
	if dist > 0.001:
		_steer(yaw_of(to), sdt)
	if stepd >= dist:
		position = Vector3(path[0].x, position.y, path[0].z)
		path.pop_front()
		if path.is_empty():
			_arrive()
			return
	else:
		position += to / dist * stepd
	speed_now = spd


## The charge's run: straight at the target, steering about the planted foot.
## The run's distance per second of its own time is always its clip speed (its
## pace and cadence rise together), so as with the stop every frame the plan is
## remade, for each strike: which coming crossing of its enter_run_t to brake
## at, and the stretch of run and strike that brings him to rest at its
## distance (strike_dist) from the target; the strike that does it best is
## cued. The stretch is planned for the whole run, what he has run counting as
## stretched: replanned for only what is left, it would fade as the run
## shortens and the miss would stay.
func _charge(sdt: float) -> void:
	if _target == null or not is_instance_valid(_target):
		state = "idle"
		_play(idle_clip())
		return
	_charge_t += sdt
	var rate := lerpf(CHARGE_RATE0, 1.0, smoothstep(0.0, CHARGE_RAMP, _charge_t))
	player.speed_scale = playback * rate
	var to := _target.position - position
	to.y = 0
	_steer(yaw_of(to), sdt)
	var L := player.current_animation_length
	var t := player.current_animation_position
	if not _charge_cue.is_empty() and int(_charge_cue.k) == 0:
		var enter := float(meta.clips[_charge_cue.clip].enter_run_t)
		var crossed := (_run_t_prev <= enter and enter < t) or (t < _run_t_prev and (enter >= _run_t_prev or enter < t))
		if crossed:
			_run_t_prev = t
			_begin_charge_hit(_charge_cue.clip, fposmod(t - enter, L))
			_charge_hit_step(sdt)
			return
	_run_t_prev = t
	var V := run_speed()
	_charge_cue = {}
	for c in strikes():
		var e := float(meta.clips[c].enter_run_t)
		var lw: Array = CHARGE_LEEWAY.get(c, [CHARGE_SHORT, CHARGE_LONG])
		var nearest := strike_dist(c) - float(meta.clips[c].get("lead_m", 0.5)) * _k() - CHARGE_NEAREST
		var ahead := V * fposmod(e - t, L) + travel_of(c)
		var plan := _plan(to.length() - strike_dist(c) + _charge_run.y, _charge_run.x + ahead, V * L, CHARGE_SLACK, lw[1], lw[0], nearest)
		plan.rest = ahead + int(plan.k) * V * L
		# The strike he goes for wins unless another lands clearly nearer.
		plan.score += 0.0 if c == _charge_pref else 1.0
		if _charge_cue.is_empty() or plan.score < _charge_cue.score:
			plan.clip = c
			_charge_cue = plan
	# What is left takes the stretch that brings the whole run to the plan's.
	var rest := maxf(float(_charge_cue.rest), 0.5)
	_stretch = clampf((float(_charge_cue.stretch) * (_charge_run.x + rest) - _charge_run.y) / rest, 1.0 - CHARGE_SLACK, 1.0 + CHARGE_SLACK)
	var spd := V * rate * _stretch
	if _launch_w < 1.0:
		# Setting off: the run's sweep counts only as far as the cross-fade has
		# come, and the body shifts over the front foot as its guard spot gives
		# way to the run's, so that foot stays where it stands.
		var w0 := _launch_w
		_launch_w = minf(1.0, _launch_w + sdt * rate / maxf(_blend_of("run", BLEND), 1e-3))
		var run_foot := _launch_run_foot - Vector3(0, 0, 1) * V * fposmod(t - CHARGE_LAUNCH_T, L)
		var shift := (_launch_from - run_foot) * (_launch_w - w0)
		position += basis * shift
		spd *= w0
	position += forward() * spd * sdt
	speed_now = spd
	_charge_run += Vector2(spd / _stretch, spd) * sdt


## Slide of a planted foot on the move, in the lane step and in the turns:
## how far the ankle moves across the ground while it is down (within 3 cm of
## its standing height). A turn's shuffled steps stay that low, so in a turn
## a foot is down only while it all but stands still (under 0.4 m/s). The last
## few stances are kept.
func _measure_feet(sdt: float) -> void:
	for side in _feet:
		var ft: Dictionary = _feet[side]
		var p := _foot_pos(side)
		var moved := Vector2(p.x - ft.prev.x, p.z - ft.prev.z).length()
		ft.prev = p
		var down := p.y - position.y < _ankle_rest + 0.03 * _k() and state in ["walk", "lane", "start", "stop", "charge", "charge_hit", "turn"]
		if state == "turn" and moved > 0.4 * maxf(sdt, 1e-4):
			down = false
		if down and not ft.down:
			ft.at = p
			ft.max = 0.0
		elif down:
			ft.max = maxf(ft.max, Vector2(p.x - ft.at.x, p.z - ft.at.z).length())
		elif ft.down and ft.max > 0.0:
			slides.append([side, ft.max, state])
			if slides.size() > 8:
				slides.pop_front()
		ft.down = down
