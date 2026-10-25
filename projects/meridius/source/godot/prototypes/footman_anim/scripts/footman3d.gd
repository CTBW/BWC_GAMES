## One 3D footman for the sandbox: the rig from art/footman_3d/footman_rig.blend
## (exported by art/footman_3d/tools/export_godot.py), his clips cross-faded by
## the AnimationPlayer and moved by each clip's own ground speed. The model
## faces +Z: a direction d on the ground is the yaw atan2(d.x, d.z).
##
## States: idle, start (setting off), walk (along `path`), stop (slowing into
## his guard), turn (a turn clip in place; the clip's root_yaw turns this node),
## attack (the slash, or now and then the stab), block, hit, block_hit (a blow
## taken behind the raised shield; either may be answered by a counter), lane
## (step into the lane on his right), charge (the run at a target), charge_hit
## (the run braking into a strike: `charge_hit`, the slash, off the left foot,
## `charge_thrust`, a long lunge, off the right, half a stride later, or
## `charge_stab`, the thrust, now and then), dead. The start, stop, lane step and
## charge_hit carry their own travel (`root_path`); the stop is cued from the
## walk at the stride it joins, so that it ends on the target, and the
## charge_hit likewise from the run. Measures the slide of each planted foot.
extends Node3D

signal impact(target: Node3D, landed: bool, reach: float)

const GLB := "res://prototypes/footman_anim/art3d/footman.glb"
const META := "res://prototypes/footman_anim/art3d/footman.json"
const OUTLINE := preload("res://prototypes/footman_anim/shaders/outline3d.gdshader")
const FPS := 30.0
## Seconds of cross-fade into each clip. The start, turns and lane step begin
## on idle's first frame, which idle's hands leave by up to half a metre within
## its first second: a quarter second keeps that from a swoop.
const BLEND := {"idle": 0.25, "walk": 0.2, "attack": 0.1, "block": 0.18, "hit": 0.1, "death": 0.12, "lane": 0.25, "turn": 0.25, "turn_180": 0.25,
	"start": 0.25, "stop": 0.12, "block_hit": 0.08, "run": 0.2, "charge_hit": 0.0}
const LOOPS := ["idle", "walk", "block", "run"]
## The charge (the game's shield_charge: a run of at least CHARGE_MIN_TILES,
## then the strike). He sets off from his guard into the run at CHARGE_LAUNCH_T
## (his left foot just landed: his front foot, it stays where it stands while
## the rear one pushes off), the run at CHARGE_RATE0 of its pace and cadence
## together, so planted feet hold, reaching its own over CHARGE_RAMP seconds.
## To land the strike his run may stretch by up to CHARGE_SLACK; he may come
## to rest up to CHARGE_LONG (m) farther from the target than the strike's distance (the
## blade still reaches) but only CHARGE_SHORT nearer (the blade would pass
## through it).
const CHARGE_MIN_TILES := 2
## The strikes the run can brake into, each taking over at its own point of the
## stride (those the export has), and how far each may come to rest from its
## spot: [nearer, farther] (m). The slash reaches far but cuts through a target
## it is too close to; a thrust must reach and still reads from close in.
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
## The game's march (battle_view.gd _play_move: a player squad, seconds per
## tile) and walk cycle (soldier_anim.gd STRIDE: seconds per two steps).
const GAME_TILE_TIME := 0.26
const GAME_STRIDE := 0.44
## Turning while he walks, radians per second; smaller turns than this in place are eased, not stepped.
const WALK_TURN_RATE := deg_to_rad(360.0)
## Turning on the move (start, walk, stop): only while one foot is down, and
## about that foot, so a planted foot pivots instead of sliding.
const STEER_RATE := deg_to_rad(220.0)
## Landing on the target: the start's travel, the walk's pace and the stop's
## travel all stretch by one factor, at most SLACK (a few centimetres a step),
## and he may come to rest up to ARRIVE_TOLERANCE (m) short of or past it
## (a squad's men stand off the tile's centre anyway).
const SLACK := 0.06
const ARRIVE_TOLERANCE := 0.3
const STEP_TURN_MIN := 30.0
## Where he stops in front of a dummy for the slash (metres, centre to centre)
## and how far off his facing a blow still lands.
const STRIKE_DIST := 1.45
const HIT_ARC := 70.0
## The attacks: the slash, and now and then (ATTACK_STAB_CHANCE) the stab, when
## it reaches. Where he stands for each: its blade's tip reaching SLASH_INTO
## past the target's centre for a slash (the slash's reach gives STRIKE_DIST),
## THRUST_INTO for a thrust.
const ATTACK_STAB_CHANCE := 0.35
const SLASH_INTO := 0.57
const THRUST_INTO := 0.25

var meta: Dictionary
var model: Node3D
var player: AnimationPlayer
var skeleton: Skeleton3D
var state := "idle"
var path: Array = []
## "walk" (his walk at its own speed) or "game" (the walk sped to the game's
## 0.26 s a tile: feet skate).
var pace := "walk"
## A large change of heading from a standstill: a turn clip in place first
## (true) or straight off, turning as he goes (false).
var step_turns := false
var tile_m := 2.72
var block_held := false
var playback := 1.0:
	set(v):
		playback = v
		if player:
			player.speed_scale = v
## Diagnostics read by the sandbox.
var speed_now := 0.0
var slides: Array = []
var last_impact := ""
var _yaw_goal := NAN
var _turn := {}
var _on_arrive := Callable()
var _after_turn := Callable()
var _impact_done := false
var _target: Node3D
var _attack_clip := "attack"
## A counter waiting for the blow he takes first: whom to strike back at.
var _counter_target: Node3D
## The charge's strike he goes for when two land about as well.
var _charge_pref := "charge_hit"
var rng := RandomNumberGenerator.new()
## The lane step's travel stretched to the distance asked for.
var _lane_scale := 1.0
## Start and stop: the travel already applied, whether this march uses them,
## the stop's cue (committed, and the slight change of pace that lands it).
var _root_prev := Vector2.ZERO
var _full_march := false
var _stop_cue := {}
var _stretch := 1.0
var _walk_t_prev := 0.0
## The charge: seconds into it, the run's time last frame, and the strike's cue
## (as the stop's, from the run); the run so far, at its own pace and as stretched.
var _charge_t := 0.0
var _charge_run := Vector2.ZERO
var _run_t_prev := 0.0
var _charge_cue := {}
var _strike_clip := "charge_hit"
## Setting off: the cross-fade's weight so far, and his front foot in his own
## space: where the guard has it, and where the run has it at CHARGE_LAUNCH_T.
var _launch_w := 1.0
var _launch_from := Vector3.ZERO
var _launch_run_foot := Vector3.ZERO
var _feet := {}
var _ankle_rest := 0.0
var _outline: ShaderMaterial
var _surfaces: Array = []


func _ready() -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string(META))
	model = load(GLB).instantiate()
	add_child(model)
	player = model.find_children("*", "AnimationPlayer", true, false)[0]
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	for n in LOOPS:
		if player.has_animation(n):
			player.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	for n in ["attack", "attack_stab", "hit", "death", "turn_90", "turn_90_r", "turn_180", "start", "stop", "block_hit", "lane"] + CHARGE_STRIKES:
		if player.has_animation(n):
			player.get_animation(n).loop_mode = Animation.LOOP_NONE
	player.animation_finished.connect(_on_finished)
	rng.randomize()
	player.speed_scale = playback
	for side in ["Left", "Right"]:
		_feet[side] = {"bone": _bone(side + "Foot"), "down": false, "at": Vector3.ZERO, "max": 0.0, "prev": Vector3.ZERO}
	_outline = ShaderMaterial.new()
	_outline.shader = OUTLINE
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			_surfaces.append([mi, i, mi.mesh.surface_get_material(i)])
	set_look("toon", true)
	if player.has_animation("run"):
		player.play("run")
		player.seek(CHARGE_LAUNCH_T, true)
		_launch_run_foot = _local_foot("Left")
	player.play("idle")
	player.advance(0.0)
	_ankle_rest = _foot_pos("Left").y


func _bone(suffix: String) -> int:
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_name(i).ends_with(suffix):
			return i
	return -1


func _foot_pos(side: String) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(_feet[side].bone).origin


## A foot in his own space (on the ground plane), whatever his place and facing.
func _local_foot(side: String) -> Vector3:
	var p := global_transform.affine_inverse() * _foot_pos(side)
	return Vector3(p.x, 0, p.z)


## Look: "toon" (lit, hard light and shadow bands), "flat" (texture only, like
## the Mixar previews) or "pbr" (the import as it is); outline on or off.
func set_look(mode: String, outline: bool) -> void:
	for s in _surfaces:
		var src: Material = s[2]
		var m: StandardMaterial3D = src.duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
		# Sharp texture at the camera's slant.
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		match mode:
			"toon":
				m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				m.metallic = 0.0
				m.roughness = 1.0
			"flat":
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.next_pass = _outline if outline else null
		s[0].set_surface_override_material(s[1], m)


func set_outline_width(metres: float) -> void:
	_outline.set_shader_parameter("width", metres)


func yaw_of(d: Vector3) -> float:
	return atan2(d.x, d.z)


func forward() -> Vector3:
	return Vector3(sin(rotation.y), 0, cos(rotation.y))


func walk_speed() -> float:
	if pace == "game":
		return tile_m / GAME_TILE_TIME
	return clip_speed("walk")


func run_speed() -> float:
	return clip_speed("run")


func clip_speed(clip: String) -> float:
	var v: Array = meta.clips[clip].root_vel
	return Vector3(v[0], v[1], v[2]).length()


func can_charge() -> bool:
	return not strikes().is_empty()


func strikes() -> Array:
	return CHARGE_STRIKES.filter(func(c): return meta.clips.has(c))


## Where he stands to strike with a clip (an attack or a charge strike), centre to centre.
func strike_dist(clip: String) -> float:
	var into := THRUST_INTO if is_thrust(clip) else SLASH_INTO
	return float(meta.clips[clip].get("tip_reach_m", STRIKE_DIST + into)) - into


## A thrust (the stab, the lunge) rather than the slash.
func is_thrust(clip: String) -> bool:
	return "stab" in clip or "thrust" in clip


## The attack for a blow: now and then the stab, if he has it and, with a target
## `dist` away (centre to centre), it reaches.
func pick_attack(dist: float = -1.0) -> String:
	if not meta.clips.has("attack_stab") or rng.randf() >= ATTACK_STAB_CHANCE:
		return "attack"
	if dist >= 0.0 and dist > float(meta.clips.attack_stab.tip_reach_m) + 0.1:
		return "attack"
	return "attack_stab"


func _play(clip: String, blend_key: String = "", speed: float = 1.0) -> void:
	player.play(clip, BLEND.get(blend_key if blend_key != "" else clip, 0.2), speed)


## A clip's travel at time t (Godot local x = his left, y = forward), from its first frame.
func root_at(clip: String, t: float) -> Vector2:
	var rp: Array = meta.clips[clip].root_path
	var f := clampf(t * FPS, 0.0, rp.size() - 1.0)
	var i := int(f)
	var j := mini(i + 1, rp.size() - 1)
	return Vector2(rp[i][0], rp[i][1]).lerp(Vector2(rp[j][0], rp[j][1]), f - i)


func travel_of(clip: String) -> float:
	var rp: Array = meta.clips[clip].root_path
	return float(rp[rp.size() - 1][1])


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
			position = Vector3(path[0].x, 0, path[0].z)
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
## his centre with both in the air); none while both are down.
func _pivot() -> Variant:
	var l := _foot_pos("Left")
	var r := _foot_pos("Right")
	var dl := l.y < _ankle_rest + 0.035
	var dr := r.y < _ankle_rest + 0.035
	if dl and dr:
		return null
	if dl:
		return Vector3(l.x, 0, l.z)
	if dr:
		return Vector3(r.x, 0, r.z)
	return position


## Turn toward a heading on the move, about the planted foot.
func _steer(yaw: float, sdt: float) -> void:
	var dy := clampf(angle_difference(rotation.y, yaw), -STEER_RATE * sdt, STEER_RATE * sdt)
	if absf(dy) < 1e-5:
		return
	var pv = _pivot()
	if pv == null:
		return
	rotation.y += dy
	var off: Vector3 = position - pv
	position = pv + off.rotated(Vector3.UP, dy)


# --- Orders -------------------------------------------------------------------

## March through the points (ground positions); `then` runs on arrival.
func march(points: Array, then: Callable = Callable()) -> void:
	if state == "dead" or points.is_empty():
		return
	path = points.duplicate()
	_on_arrive = then
	_target = null
	_stop_cue = {}
	if state in ["walk", "start"]:
		return
	if state in ["stop", "charge"]:
		# Off again before he has settled (or off the charge): straight into the stride.
		_full_march = path_length() >= travel_of("stop") + 0.3
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
	if step_turns and absf(delta) >= STEP_TURN_MIN and state in ["idle", "block"]:
		_start_turn(delta, _set_off)
	else:
		_set_off()


## From a standstill: the start step when the march is long enough for it and
## the stop, otherwise straight into the walk.
func _set_off() -> void:
	_full_march = pace != "game" and path_length() >= travel_of("start") + travel_of("stop") + 0.15
	if _full_march:
		state = "start"
		_root_prev = Vector2.ZERO
		# The whole march planned at once: the start, whole strides, the stop.
		var L := player.get_animation("walk").length
		var lead := walk_speed() * fposmod(float(meta.clips.stop.enter_walk_t) - float(meta.clips.start.exit_walk_t), L)
		_stretch = _plan(path_length(), travel_of("start") + lead + travel_of("stop"), walk_speed() * L).stretch
		_play("start")
	else:
		_start_walk()


func _start_walk() -> void:
	var from_still := state not in ["walk", "start", "stop"]
	state = "walk"
	_stop_cue = {}
	var spd := 1.0
	if pace == "game":
		spd = float(meta.clips.walk.length) / GAME_STRIDE
	_play("walk", "walk", spd)
	# From a standstill the cycle starts where its feet are nearest his stance.
	if from_still:
		player.seek(float(meta.clips.walk.get("start_from_idle", 0.0)))
	_walk_t_prev = player.current_animation_position


## The plan for a distance R covered by `fixed` metres plus whole strides of C:
## how many strides, and the one stretch (within SLACK) that best balances
## coming to rest off the target (ARRIVE_TOLERANCE is a normal miss) against
## stretching his steps (STRETCH_TYPICAL is a normal stretch).
const STRETCH_TYPICAL := 0.04


func _plan(R: float, fixed: float, C: float, slack: float = SLACK, tolerance: float = ARRIVE_TOLERANCE, over: float = -1.0, max_over: float = INF) -> Dictionary:
	# `over`: the tolerance for coming to rest past the target, if not `tolerance`;
	# `max_over`: how far past it he may come at all (beyond, a plan only if no other).
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


func _begin_stop() -> void:
	state = "stop"
	_stop_cue = {}
	_root_prev = Vector2.ZERO
	_play("stop")


func _arrive() -> void:
	path.clear()
	speed_now = 0.0
	state = "idle"
	_play("idle")
	if _on_arrive.is_valid():
		var t := _on_arrive
		_on_arrive = Callable()
		t.call()


## Turn in place to face a yaw (radians), stepping round with a turn clip when
## the change is large enough; `then` runs when he faces it.
func face(yaw: float, then: Callable = Callable()) -> void:
	if state == "dead":
		return
	var delta := rad_to_deg(angle_difference(rotation.y, yaw))
	if absf(delta) < STEP_TURN_MIN:
		_yaw_goal = yaw
		if then.is_valid():
			then.call()
		return
	_start_turn(delta, then)


func _start_turn(delta_deg: float, then: Callable) -> void:
	var clip := "turn_90" if delta_deg > 0.0 else "turn_90_r"
	if absf(delta_deg) > 135.0:
		clip = "turn_180"
	var curve: Array = meta.clips[clip].root_yaw
	var total: float = curve[curve.size() - 1]
	var want := delta_deg
	# The 180 turn steps round one way only; a turn the other way goes the long way round to match it.
	if clip == "turn_180" and signf(want) != signf(total):
		want -= 360.0 * signf(want)
	_turn = {"clip": clip, "curve": curve, "scale": want / total, "start": rotation.y, "want": deg_to_rad(want)}
	_after_turn = then
	_yaw_goal = NAN
	state = "turn"
	_play(clip, "turn_180" if clip == "turn_180" else "turn")


## The attack picked before walking up, kept if it suits where he came to rest
## (the walk stops in whole strides, up to ~40 cm off): the stab only if it
## reaches, the slash only if he isn't so close that it cuts through the target.
func _fit_attack(target: Node3D, clip: String) -> String:
	if not is_instance_valid(target) or not meta.clips.has("attack_stab"):
		return "attack"
	var d := Vector2(target.position.x - position.x, target.position.z - position.z).length()
	if clip == "attack_stab" and d > float(meta.clips.attack_stab.tip_reach_m) + 0.1:
		return "attack"
	if clip == "attack" and d < strike_dist("attack") - 0.25:
		return "attack_stab"
	return clip


## Strike: `clip` ("attack", the slash, or "attack_stab"), or one picked for
## the target's distance (pick_attack).
func attack(target: Node3D = null, clip: String = "") -> void:
	if state == "dead":
		return
	path.clear()
	_target = target
	if clip == "":
		var d := -1.0
		if target != null:
			d = Vector2(target.position.x - position.x, target.position.z - position.z).length()
		clip = pick_attack(d)
	_attack_clip = clip
	_impact_done = false
	state = "attack"
	_play(clip, "attack")


## Walk up to a target, face it and strike: the attack is picked first, and he
## stops where it reaches.
func attack_target(target: Node3D) -> void:
	if state == "dead":
		return
	var clip := pick_attack()
	var from := position - target.position
	from.y = 0
	if from.length() < 0.01:
		from = -forward()
	var spot := target.position + from.normalized() * strike_dist(clip)
	var strike := func():
		face(yaw_of(target.position - position), func(): attack(target, _fit_attack(target, clip)))
	if position.distance_to(spot) < 0.15:
		strike.call()
	else:
		march([spot], strike)
	_target = target


## Charge a target (the game's shield_charge): from CHARGE_MIN_TILES or more
## away he runs straight at it, steering about the planted foot, and the run
## brakes into the strike (`charge_hit`, which takes over the run at one point
## of the stride, enter_run_t), so that he comes to rest where the strike reaches it as
## the blade lands. Nearer, he walks up and strikes. Returns whether he charges.
func charge(target: Node3D) -> bool:
	if state == "dead" or not can_charge():
		return false
	var to := target.position - position
	to.y = 0
	if to.length() < CHARGE_MIN_TILES * tile_m:
		attack_target(target)
		return false
	path.clear()
	_target = target
	_impact_done = false
	_charge_cue = {}
	_stretch = 1.0
	_charge_t = 0.0
	_charge_run = Vector2.ZERO
	_charge_pref = "charge_stab" if meta.clips.has("charge_stab") and rng.randf() < ATTACK_STAB_CHANCE else "charge_hit"
	_launch_from = _local_foot("Left")
	_launch_w = 0.0 if state in ["idle", "block"] else 1.0
	state = "charge"
	_play("run")
	player.seek(CHARGE_LAUNCH_T)
	_run_t_prev = player.current_animation_position
	return true


func _begin_charge_hit(clip: String, at: float) -> void:
	state = "charge_hit"
	_strike_clip = clip
	player.speed_scale = playback
	player.play(clip, BLEND.charge_hit)
	player.seek(at, true)
	# The run has already carried him `at` into the clip.
	_root_prev = root_at(clip, at)
	_impact_done = false


## The strike's travel for the time the clip moves on this frame (as the run's:
## the node keeps pace with the pose, so the planted foot holds through the
## hand-off), turning to the target until the blow.
func _charge_hit_step(sdt: float) -> void:
	var r := root_at(_strike_clip, player.current_animation_position + sdt)
	var d := r - _root_prev
	_root_prev = r
	d.y *= _stretch
	position += Vector3(d.x, 0, d.y).rotated(Vector3.UP, rotation.y)
	speed_now = d.length() / maxf(sdt, 1e-4)
	if not _impact_done and _target != null and is_instance_valid(_target):
		var to := _target.position - position
		_steer(yaw_of(Vector3(to.x, 0, to.z)), sdt)
	if not _impact_done and player.current_animation_position >= float(meta.clips[_strike_clip].events.contact):
		_impact_done = true
		_strike()


func set_block(on: bool) -> void:
	block_held = on
	if on and state == "idle":
		state = "block"
		_play("block")
	elif not on and state == "block":
		state = "idle"
		_play("idle")


## Take a blow and strike back at `target` (the game's counterattack): the hit
## (on the shield, if it is up), then an attack, the stab now and then, if the
## target is within the slash's reach and roughly ahead; otherwise only the hit.
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
	if to.length() > float(meta.clips.attack.tip_reach_m) + 0.25 or rad_to_deg(absf(angle_difference(rotation.y, yaw_of(to)))) > 100.0:
		last_impact = "too far to strike back"
		return
	face(yaw_of(to), func(): attack(t))


func hit() -> void:
	if state == "dead":
		return
	path.clear()
	_counter_target = null
	# Behind the raised shield the blow is taken on it; the shield stays up.
	if state in ["block", "block_hit"]:
		state = "block_hit"
		_play("block_hit")
		player.seek(0.0)
		return
	state = "hit"
	_play("hit")


func die() -> void:
	if state == "dead":
		return
	path.clear()
	state = "dead"
	_play("death")


func revive() -> void:
	state = "idle"
	path.clear()
	player.play("idle", 0.5)


## Sideways into the lane on his right (one file, about 1.1 m): four short
## steps from his guard to his guard, moved by the clip's own travel
## (`root_path`, built for `lane_m`), stretched to the distance asked for.
func step_lane(dist: float) -> void:
	if state not in ["idle", "block"]:
		return
	state = "lane"
	_lane_scale = dist / float(meta.clips.lane.get("lane_m", dist))
	_root_prev = Vector2.ZERO
	_play("lane")


func _on_finished(anim: StringName) -> void:
	match state:
		"start":
			# The start ends on the walk's stride: carry straight on from it.
			state = "walk"
			player.play("walk", 0.05)
			player.seek(float(meta.clips.start.exit_walk_t))
			_walk_t_prev = player.current_animation_position
		"stop":
			# The stop ends in idle's first pose.
			path.clear()
			state = "idle"
			player.play("idle", 0.05)
			if block_held:
				set_block(true)
			if _on_arrive.is_valid():
				var t := _on_arrive
				_on_arrive = Callable()
				t.call()
		"charge_hit":
			# It ends in idle's first pose (the attack's last).
			state = "idle"
			player.play("idle", 0.05)
			if block_held:
				set_block(true)
		"lane":
			# It ends in idle's first pose, one file over.
			state = "idle"
			player.play("idle", 0.05)
			if block_held:
				set_block(true)
		"block_hit":
			# It ends in the block's first pose.
			state = "block" if block_held else "idle"
			player.play(state, 0.05 if block_held else BLEND.idle)
			if _counter_target != null:
				_answer_counter()
		"attack":
			state = "idle"
			_play("idle")
			if block_held:
				set_block(true)
		"hit":
			state = "idle"
			_play("idle", "hit")
			if block_held:
				set_block(true)
			if _counter_target != null:
				_answer_counter()
		"turn":
			rotation.y = _turn.start + _turn.want
			_turn = {}
			# Every turn ends in idle's first pose, turned.
			state = "idle"
			player.play("idle", 0.05)
			if _after_turn.is_valid():
				var t := _after_turn
				_after_turn = Callable()
				t.call()


# --- Per frame ----------------------------------------------------------------

func _process(dt: float) -> void:
	var sdt := dt * playback
	speed_now = 0.0
	# Only the charge's run plays at its own rate.
	if state != "charge" and player.speed_scale != playback:
		player.speed_scale = playback
	match state:
		"walk":
			_walk(sdt)
		"charge":
			_charge(sdt)
		"charge_hit":
			_charge_hit_step(sdt)
		"start", "stop":
			var r := root_at(state, player.current_animation_position)
			var d := r - _root_prev
			_root_prev = r
			d.y *= _stretch
			_move_along(d.y, sdt)
			position += Vector3(d.x, 0, 0).rotated(Vector3.UP, rotation.y)
			speed_now = d.length() / maxf(sdt, 1e-4)
		"turn":
			var curve: Array = _turn.curve
			var f := clampf(player.current_animation_position * FPS, 0.0, curve.size() - 1.0)
			var i := int(f)
			var j := mini(i + 1, curve.size() - 1)
			var y: float = lerpf(curve[i], curve[j], f - i)
			rotation.y = _turn.start + deg_to_rad(y * _turn.scale)
		"attack":
			var ev: Dictionary = meta.clips[_attack_clip].events
			if not _impact_done and player.current_animation == _attack_clip and player.current_animation_position >= ev.contact:
				_impact_done = true
				_strike()
		"lane":
			var r := root_at("lane", player.current_animation_position) * _lane_scale
			var d := r - _root_prev
			_root_prev = r
			position += Vector3(d.x, 0, d.y).rotated(Vector3.UP, rotation.y)
			speed_now = d.length() / maxf(sdt, 1e-4)
	if not is_nan(_yaw_goal) and state in ["idle", "block"]:
		var dy := angle_difference(rotation.y, _yaw_goal)
		var stepy := WALK_TURN_RATE * 0.6 * sdt
		if absf(dy) <= stepy:
			rotation.y = _yaw_goal
			_yaw_goal = NAN
		else:
			rotation.y += signf(dy) * stepy
	_measure_feet(sdt)


func _walk(sdt: float) -> void:
	var spd := walk_speed()
	if _full_march:
		# The stop joins the walk at one stride (enter_walk_t) and covers a set
		# distance. Every frame the plan is remade (_plan): which coming crossing
		# of that stride to stop at (k cycles after the next), and the stretch of
		# pace and stop that lands him on the target.
		var L := player.current_animation_length
		var t := player.current_animation_position
		var enter := float(meta.clips.stop.enter_walk_t)
		var crossed := (_walk_t_prev <= enter and enter < t) or (t < _walk_t_prev and (enter >= _walk_t_prev or enter < t))
		_walk_t_prev = t
		if crossed and not _stop_cue.is_empty() and int(_stop_cue.k) == 0:
			_begin_stop()
			return
		var d_next := walk_speed() * fposmod(enter - t, L)
		_stop_cue = _plan(path_length(), d_next + travel_of("stop"), walk_speed() * L)
		_stretch = float(_stop_cue.stretch)
		spd *= _stretch
		_move_along(spd * sdt, sdt)
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
		position = Vector3(path[0].x, 0, path[0].z)
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
## at, and the stretch of run and strike that brings him to rest at its distance (strike_dist)
## from the target; the strike that does it best is cued. The stretch is planned
## for the whole run, what he has run counting as stretched: replanned for only
## what is left, it would fade as the run shortens and the miss would stay.
func _charge(sdt: float) -> void:
	if _target == null or not is_instance_valid(_target):
		state = "idle"
		_play("idle")
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
		var nearest := strike_dist(c) - float(meta.clips[c].get("lead_m", 0.5)) - CHARGE_NEAREST
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
		_launch_w = minf(1.0, _launch_w + sdt * rate / float(BLEND.run))
		var run_foot := _launch_run_foot - Vector3(0, 0, 1) * V * fposmod(t - CHARGE_LAUNCH_T, L)
		var shift := (_launch_from - run_foot) * (_launch_w - w0)
		position += basis * shift
		spd *= w0
	position += forward() * spd * sdt
	speed_now = spd
	_charge_run += Vector2(spd / _stretch, spd) * sdt


func _strike() -> void:
	var clip := _strike_clip if state == "charge_hit" else _attack_clip
	var reach: float = meta.clips[clip].get("tip_reach_m", 1.9)
	if _target == null or not is_instance_valid(_target):
		last_impact = "swing at the air"
		impact.emit(null, false, 0.0)
		return
	var to := _target.position - position
	to.y = 0
	var ang := rad_to_deg(absf(angle_difference(rotation.y, yaw_of(to))))
	var landed := to.length() <= reach + 0.25 and ang <= HIT_ARC
	var kind := "lunge" if "thrust" in clip else "stab" if "stab" in clip else "slash"
	last_impact = "%s %s at %.2f m, %d° off his facing" % [kind, "hit" if landed else "missed", to.length(), int(ang)]
	impact.emit(_target, landed, to.length())


## Slide of a planted foot on the march, in the lane step and in the turns:
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
		var down := p.y < _ankle_rest + 0.03 and state in ["walk", "lane", "start", "stop", "charge", "charge_hit", "turn"]
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
