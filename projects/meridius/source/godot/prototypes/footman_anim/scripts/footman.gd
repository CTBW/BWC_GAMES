## One prototype footman: four facing rigs, its own animation clock, a small
## state machine (idle, walk, attack, block, hit, death, step_lane) and the
## presentation that hangs off its own animation events: hit-stop, smear,
## footstep dust. Nothing here decides combat; a squad or the sandbox asks.
##
## Clock: the AnimationPlayers run in manual mode. Smooth playback advances
## them by the frame's delta; "on twos" accumulates and advances in 1/12 s
## steps (pose, root motion and cloth springs together, like hand-drawn twos).
extends Node2D

const Rig = preload("res://prototypes/footman_anim/scripts/footman_rig.gd")

signal impact_landed(soldier: Node2D, at: Vector2)
signal stepped(soldier: Node2D, side: String, at: Vector2)
signal finished(soldier: Node2D, clip: String)

## Game facings (Formation.GRID_DIRS order): 0 SE, 1 SW, 2 NW, 3 NE.
const FACING_KEYS := ["se", "sw", "nw", "ne"]
const GRID_DIRS := [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]
## World px per view px: the painted master (~450 px) becomes an ~80 px soldier.
const FIGURE_SCALE := 0.178
const TWOS := 1.0 / 12.0
## Hit-stop on the soldier's own contact frame: 3 animation frames at 30 fps.
const HITSTOP := 0.1
const BLEND := {
	"idle>walk": 0.24, "walk>idle": 0.28, "idle>attack": 0.08, "attack>idle": 0.28, "block>attack": 0.1,
	"idle>block": 0.18, "block>idle": 0.22, "walk>block": 0.2, "any>hit": 0.12, "hit>idle": 0.22, "hit>block": 0.2,
	"any>death": 0.14, "idle>step_lane": 0.1, "step_lane>idle": 0.2, "walk>attack": 0.14,
}

var facing := 0
var rigs := {}
var rig: Node2D
var state := "idle"
var base_state := "idle"
var dead := false
## Playback rate (sandbox: 0.25x or 1x) and this soldier's own tempo.
var playback := 1.0
var tempo := 1.0
var on_twos := false
var hitstop := 0.0
var walk_to: Variant = null
var travel := Vector2.ZERO
var impacts := 0
var steps := 0
var fx: Node2D
var shake: Callable
var debug_bones := false
var debug_contacts := false
var smear_enabled := true
var label := ""
var _accum := 0.0
var _hit_jitter := Vector2.ZERO
var _smear: Array = []
var _smear_window := Vector2(-1, -1)
var _queued := ""
var _time := 0.0


func setup(available: Array, p_facing: int = 0) -> void:
	for key in available:
		var r := Rig.new()
		r.name = "Rig_" + key
		add_child(r)
		r.setup(key, FIGURE_SCALE)
		r.visible = false
		r.impact.connect(_on_impact)
		r.step.connect(_on_step)
		rigs[key] = r
	facing = p_facing if rigs.has(FACING_KEYS[p_facing]) else FACING_KEYS.find(available[0])
	rig = rigs[FACING_KEYS[facing]]
	rig.visible = true
	_play("idle", 0.0)


## The rig of a facing, or the nearest baked one while a facing is not built.
func rig_for(f: int) -> Node2D:
	return rigs.get(FACING_KEYS[f], rig)


func set_facing(f: int) -> void:
	f = posmod(f, 4)
	if not rigs.has(FACING_KEYS[f]):
		return
	var old := rig
	var anim: String = old.player.current_animation
	var pos: float = old.player.current_animation_position if anim != "" else 0.0
	facing = f
	rig = rigs[FACING_KEYS[f]]
	old.visible = false
	rig.visible = true
	if anim != "":
		rig.player.play(anim, 0.0)
		rig.player.seek(pos, true)
	rig.reset_springs()
	rig.update_parts(0.0)
	_smear.clear()
	queue_redraw()


## Ground-plane direction of the facing in world px per grid unit.
static func screen_dir(f: int) -> Vector2:
	var d: Vector2 = GRID_DIRS[f]
	return Vector2((d.x - d.y) * 64.0, (d.x + d.y) * 32.0)


func clip_meta(clip: String) -> Dictionary:
	return rig.meta.clips.get(clip, {})


## Root velocity of a clip in world px/s (march speed measured from foot contact).
func clip_velocity(clip: String) -> Vector2:
	var m := clip_meta(clip)
	var v: Array = m.get("root_velocity", [0, 0])
	var sx := -1.0 if rig.mirrored else 1.0
	return Vector2(v[0] * sx, v[1]) * FIGURE_SCALE


func idle(offset: float = -1.0) -> void:
	if dead:
		return
	base_state = "idle"
	_play("idle", _blend_for("idle"))
	if offset >= 0.0:
		var len: float = rig.player.get_animation("idle").length
		rig.player.seek(fmod(offset, len), true)


func guard() -> void:
	if dead:
		return
	base_state = "block"
	_play("block", _blend_for("block"))


## March on the spot (inspection: the clip without root motion).
func walk_in_place() -> void:
	if dead:
		return
	walk_to = null
	base_state = "walk"
	if state != "walk":
		_play("walk", _blend_for("walk"))


func walk_toward(point: Vector2) -> void:
	if dead:
		return
	walk_to = point
	base_state = "walk"
	if state != "walk":
		_play("walk", _blend_for("walk"))


func attack(delay: float = 0.0) -> void:
	if dead:
		return
	if delay > 0.0:
		_queued = "attack"
		_queue_t = delay
		return
	_play("attack", _blend_for("attack"))
	_smear_window = _swing_window()


var _queue_t := 0.0


func hit() -> void:
	if dead:
		return
	_play("hit", BLEND["any>hit"])


func die() -> void:
	if dead:
		return
	dead = true
	walk_to = null
	_play("death", BLEND["any>death"])


func step_lane(by: Vector2) -> void:
	if dead:
		return
	walk_to = null
	travel = by
	_play("step_lane", _blend_for("step_lane"))


func revive() -> void:
	dead = false
	_play("idle", 0.0)
	base_state = "idle"


func _blend_for(next: String) -> float:
	var k := state + ">" + next
	if BLEND.has(k):
		return BLEND[k]
	return BLEND.get("any>" + next, 0.18)


func _play(clip: String, blend: float) -> void:
	state = clip
	rig.player.play(clip, blend, 1.0)
	_smear.clear()


func _process(dt: float) -> void:
	var d := dt * playback
	_time += dt
	if _queued != "":
		_queue_t -= d
		if _queue_t <= 0.0:
			var q := _queued
			_queued = ""
			if q == "attack":
				attack()
	if on_twos:
		_accum += d
		while _accum >= TWOS:
			_accum -= TWOS
			_advance(TWOS)
	else:
		_accum = 0.0
		_advance(d)
	if hitstop > 0.0:
		# A held contact frame: the soldier shudders in place.
		_hit_jitter = Vector2(randf_range(-1, 1), randf_range(-0.5, 0.5)) * 0.9 * minf(1.0, hitstop / HITSTOP)
	else:
		_hit_jitter = Vector2.ZERO
	rig.position = _hit_jitter
	queue_redraw()


func _advance(d: float) -> void:
	if hitstop > 0.0:
		hitstop -= d
		if hitstop > 0.0:
			return
		d = -hitstop
		hitstop = 0.0
	var sd := d * tempo
	rig.player.advance(sd)
	# Root motion: the march speed comes from the clip (measured foot contact).
	if state == "walk" and walk_to != null:
		var v := clip_velocity("walk")
		var to: Vector2 = walk_to - position
		var step_v := v * sd
		if to.length() <= step_v.length() + 0.01 or to.dot(v) <= 0.0:
			position = walk_to
			walk_to = null
			base_state = "idle"
			_play("idle", BLEND["walk>idle"])
			finished.emit(self, "walk")
		else:
			position += step_v
	elif state == "step_lane":
		var m := clip_meta("step_lane")
		position += travel * (sd / maxf(0.01, float(m.get("length", 1.0))))
	rig.update_parts(sd)
	_track_smear()
	if state == "death":
		return
	var anim: String = rig.player.current_animation
	if anim == "" or not rig.player.is_playing():
		_on_clip_end(state)


func _on_clip_end(clip: String) -> void:
	finished.emit(self, clip)
	if clip == "attack" or clip == "hit" or clip == "step_lane":
		if base_state == "block":
			_play("block", BLEND["hit>block"])
		else:
			base_state = "idle"
			_play("idle", BLEND["attack>idle"] if clip == "attack" else 0.2)


func _on_impact() -> void:
	impacts += 1
	hitstop = HITSTOP
	var at := to_global(rig.bone_tip("sword"))
	impact_landed.emit(self, at)


func _on_step(side: String) -> void:
	steps += 1
	var at := to_global(rig.joint("foot_" + side))
	stepped.emit(self, side, at)


## Frames of the attack where the blade is fast enough to smear.
func _swing_window() -> Vector2:
	var m := clip_meta("attack")
	var tip: Array = m.get("tip", [])
	if tip.size() < 3:
		return Vector2(-1, -1)
	var sp: Array[float] = []
	var top := 0.0
	for i in range(1, tip.size()):
		var s := Vector2(tip[i][0] - tip[i - 1][0], tip[i][1] - tip[i - 1][1]).length()
		sp.append(s)
		top = maxf(top, s)
	var a := -1
	var b := -1
	for i in sp.size():
		if sp[i] > top * 0.42:
			if a < 0:
				a = i
			b = i + 1
	return Vector2(a / 30.0, b / 30.0)


func _track_smear() -> void:
	if not smear_enabled or state != "attack":
		_smear.clear()
		return
	var t: float = rig.player.current_animation_position
	if t < _smear_window.x or t > _smear_window.y + 0.06:
		if _smear.size() > 0 and t > _smear_window.y + 0.06:
			_smear.clear()
		return
	var tip: Vector2 = rig.bone_tip("sword")
	var mid: Vector2 = rig.joint("sword") * 0.35 + tip * 0.65
	_smear.append({"t": t, "tip": tip, "mid": mid})
	while _smear.size() > 6:
		_smear.pop_front()


func _draw() -> void:
	if _smear.size() >= 2:
		_draw_smear()
	if debug_bones:
		for b in Rig.BONES:
			if b[1] == "":
				continue
			draw_line(rig.joint(b[1]) + _hit_jitter, rig.joint(b[0]) + _hit_jitter, Color(1, 0.2, 0.6, 0.9), 1.0)
			draw_circle(rig.joint(b[0]) + _hit_jitter, 1.4, Color(1, 1, 0.2, 0.9))
		draw_line(rig.joint("sword"), rig.bone_tip("sword"), Color(0.2, 1, 1, 0.9), 1.0)
	if debug_contacts:
		var m := clip_meta(state)
		var con: Dictionary = m.get("contact", {})
		var fi := int(rig.player.current_animation_position * 30.0)
		for side in ["r", "l"]:
			var arr: Array = con.get(side, [])
			var p: Vector2 = rig.joint("foot_" + side)
			if fi < arr.size() and arr[fi]:
				draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), Color(0.1, 1, 0.3), false, 1.2)
			else:
				draw_circle(p, 1.6, Color(1, 0.4, 0.1, 0.8))


func _draw_smear() -> void:
	# A cel swoosh: a crescent between the blade's outer (tip) and inner trail,
	# solid near the blade and fading at the tail, with a thin cool rim.
	var n := _smear.size()
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for s in _smear:
		outer.append(s.tip + _hit_jitter)
		inner.append(s.mid + _hit_jitter)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in n:
		pts.append(outer[i])
		cols.append(Color(1, 1, 1, 0.05 + 0.8 * float(i) / (n - 1)))
	for i in range(n - 1, -1, -1):
		pts.append(inner[i])
		cols.append(Color(0.85, 0.93, 1.0, 0.02 + 0.45 * float(i) / (n - 1)))
	if Geometry2D.triangulate_polygon(pts).size() > 0:
		draw_polygon(pts, cols)
	draw_polyline(outer, Color(0.55, 0.75, 1.0, 0.55), 1.2, true)
