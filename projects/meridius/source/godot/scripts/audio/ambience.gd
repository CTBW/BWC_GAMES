## The world's background sound for Sfx (child of its 2D space). Godot addition.
##
## A preset of bank.json `ambience.presets` (camp, battle_day, battle_night) is:
##   beds      looping layers on the Ambience bus, crossfaded when the preset changes
##             [{id, takes, volume_db}]
##             Optional cycle: {hold: [min,max], quiet: [min,max], fade: seconds}.
##             These beds wait in silence, fade in, hold, then fade fully out.
##   loops     looping sounds at a place in the world, heard only once a view
##             sets their anchor (the camp's fire) [{id, takes, volume_db}]
##   oneshots  calls and noises on a random schedule: every `every` = [min, max]
##             seconds, at a random pan in `pan` = [a, b] (-1..1) and level in
##             `volume_db` = [lo, hi], ± `pitch_jitter` semitones, takes never
##             repeated back to back [{id, takes, every, pan, volume_db, pitch_jitter}]
## A change of preset crossfades all three: beds and loops both presets share
## (same id and file) play on, the others fade (a bed still fading out when its
## preset comes back turns and comes back in); the last preset's calls keep
## coming, ever quieter, until the fade ends, while the new ones rise from
## silence (day birds give way to owls as the light goes).
## Takes that do not exist are skipped, so a preset whose files are not added
## yet plays nothing (and logs nothing). While the game is paused the beds and
## loops dip by `ambience.pause_db` and no one-shot sounds; while muted no
## one-shot starts (the Master bus is muted, the beds run on silently).
##
## Driven by sfx.gd: set_preset(id, fade), set_anchor(id, world), set_paused(),
## set_muted(), advance(dt) every frame (real time).
extends Node2D

const LoopDeck = preload("res://scripts/audio/loop_deck.gd")
const Placement = preload("res://scripts/audio/placement.gd")

## Simultaneous one-shots (a bird over a bird; more are skipped, not stolen).
const SHOT_VOICES := 3

## The Sfx node: bank, place(world) and space_width().
var sfx: Node
var preset_id := ""
var beds: Node
var loops: Node
var paused := false
var muted := false
var rng := RandomNumberGenerator.new()
## One-shots played (tests and the play-through read it).
var shots_played := 0

var _preset: Dictionary = {}
## [{spec, takes, next (s), key, level, target, rate}]: the preset's calls
## (target 1) and, while a crossfade lasts, the last preset's (target 0).
## `level` 0..1 is heard on the beds' equal-power curve.
var _schedule: Array = []
## Intermittent beds: their timers include the fade before each hold / quiet gap.
var _bed_schedule: Array = []
var _anchors: Dictionary = {} # loop id -> world Vector2
var _shot_players: Array = []
var _shot_ends: Array = [] # seconds on `_clock` when each shot voice is free
var _clock := 0.0


func _init() -> void:
	name = "Ambience"
	rng.randomize()
	beds = LoopDeck.new()
	beds.name = "Beds"
	add_child(beds)
	loops = LoopDeck.new()
	loops.name = "Loops"
	add_child(loops)
	for i in SHOT_VOICES:
		var p := AudioStreamPlayer2D.new()
		p.name = "Shot%d" % i
		p.bus = "Ambience"
		p.attenuation = 0.0
		p.max_distance = 1e7
		add_child(p)
		_shot_players.append(p)
		_shot_ends.append(0.0)


func _fade(fade: float) -> float:
	return fade if fade >= 0.0 else float(sfx.bank.ambience.get("fade", 2.5)) if sfx != null else 2.5


## Changes to preset `id` ("" for silence), crossfading over `fade` s (-1: the bank's).
## A bed with the same id and file in both presets keeps playing.
func set_preset(id: String, fade := -1.0) -> void:
	if id == preset_id:
		return
	var f := _fade(fade)
	var rate := 1.0 / f if f > 0.0 else 1e6
	var was_loops := {}
	for spec in _preset.get("loops", []):
		was_loops[String(spec.get("id", ""))] = _key(spec)
	preset_id = id
	_preset = sfx.bank.ambience_preset(id) if (sfx != null and id != "") else {}
	var keep := {}
	for spec in _preset.get("beds", []):
		if spec.has("cycle"):
			continue
		var key := _key(spec)
		var l = beds.live(key)
		if l != null:
			keep[key] = true
			l.base_db = float(spec.get("volume_db", 0.0))
	for key in beds.live_keys():
		if not keep.has(key):
			beds.stop(key, f)
	var keep_loops := {}
	for spec in _preset.get("loops", []):
		var lid := String(spec.get("id", ""))
		var l = loops.live(lid)
		if l != null and was_loops.get(lid) == _key(spec):
			keep_loops[lid] = true
			l.base_db = float(spec.get("volume_db", 0.0))
	for key in loops.live_keys():
		if not keep_loops.has(key):
			loops.stop(key, f)
	_bed_schedule = []
	for spec in _preset.get("beds", []):
		var key := _key(spec)
		if spec.has("cycle"):
			if not _existing(spec.get("takes", [])).is_empty():
				_bed_schedule.append({"spec": spec, "key": key, "sounding": false,
					"next": _pick_in(spec.cycle.get("quiet", [20, 40]), 20.0)})
			continue
		if keep.has(key):
			continue
		var back = beds.revive(key, f)
		if back != null:
			# Back before it had faded: the same bed turns, from where it was.
			back.base_db = float(spec.get("volume_db", 0.0))
			continue
		var s := _stream_of(spec, "bed:" + key)
		if s != null:
			beds.start(key, s, "Ambience", float(spec.get("volume_db", 0.0)), f)
	for spec in _preset.get("loops", []):
		var lid := String(spec.get("id", ""))
		if _anchors.has(lid) and not keep_loops.has(lid):
			_start_loop(spec, f)
	var leaving := {}
	for s in _schedule:
		s.target = 0.0
		s.rate = rate
		leaving[s.key] = s
	for spec in _preset.get("oneshots", []):
		var takes := _existing(spec.get("takes", []))
		if takes.is_empty():
			continue
		var key := "shot:%s:%s" % [id, spec.get("id", "")]
		var back: Variant = leaving.get(key)
		if back != null:
			# Back before they had faded: the same calls rise again.
			back.target = 1.0
			continue
		var every := _range(spec.get("every", [8, 20]), 8.0)
		# The first call comes anywhere in the first interval, not all at once.
		var initial := _range(spec.get("initial_every", [every.x * 0.3, every.y]), every.x)
		_schedule.append({"spec": spec, "takes": takes, "next": rng.randf_range(initial.x, initial.y), "key": key,
			"level": 0.0, "target": 1.0, "rate": rate})


## Keys of the beds playing (not fading out).
func bed_keys() -> Array:
	return beds.live_keys()


func loop_keys() -> Array:
	return loops.live_keys()


## A positional loop of the preset (by id) sounds from world point `at`.
func set_anchor(id: String, at: Vector2) -> void:
	var had := _anchors.has(id)
	_anchors[id] = at
	if had:
		return
	for spec in _preset.get("loops", []):
		if String(spec.get("id", "")) == id and loops.live(id) == null:
			_start_loop(spec, _fade(-1.0))


func clear_anchor(id: String, fade := -1.0) -> void:
	_anchors.erase(id)
	loops.stop(id, _fade(fade))


func _start_loop(spec: Dictionary, fade: float) -> void:
	var id := String(spec.get("id", ""))
	var s := _stream_of(spec, "loop:" + id)
	if s == null:
		return
	var l = loops.start(id, s, "Ambience", float(spec.get("volume_db", 0.0)), fade, true)
	l.anchor = _anchors.get(id)
	_place_loop(l)


func set_paused(p: bool) -> void:
	paused = p
	var dip := float(sfx.bank.ambience.get("pause_db", -8.0)) if sfx != null else -8.0
	beds.duck_db = dip if p else 0.0
	loops.duck_db = dip if p else 0.0
	if p:
		_stop_shots()


func set_muted(m: bool) -> void:
	muted = m
	if m:
		_stop_shots()


func _stop_shots() -> void:
	for i in _shot_players.size():
		_shot_players[i].stop()
		_shot_ends[i] = 0.0


func advance(dt: float) -> void:
	_clock += dt
	if not paused and not muted:
		_advance_bed_cycles(dt)
	beds.advance(dt)
	for l in loops.loops:
		l.anchor = _anchors.get(l.key, l.anchor)
		_place_loop(l)
	loops.advance(dt)
	if paused or muted:
		return
	for s in _schedule.duplicate():
		s.level = move_toward(s.level, s.target, s.rate * dt)
		if s.level <= 0.0 and s.target <= 0.0:
			_schedule.erase(s)
			continue
		s.next -= dt
		if s.next > 0.0:
			continue
		var every := _range(s.spec.get("every", [8, 20]), 8.0)
		s.next = rng.randf_range(every.x, every.y)
		_shot(s)


## Actual silence between swells: fading a bed out also frees its player.
## Freeze the schedule on pause / mute, like the ambient calls.
func _advance_bed_cycles(dt: float) -> void:
	for s in _bed_schedule:
		s.next -= dt
		if s.next > 0.0:
			continue
		var cycle: Dictionary = s.spec.cycle
		var fade := maxf(0.0, float(cycle.get("fade", 8.0)))
		if s.sounding:
			beds.stop(s.key, fade)
			s.sounding = false
			s.next = fade + maxf(0.1, _pick_in(cycle.get("quiet", [20, 40]), 20.0))
		else:
			var stream := _stream_of(s.spec, "bed:" + str(s.key))
			if stream != null:
				beds.start(s.key, stream, "Ambience", float(s.spec.get("volume_db", 0.0)), fade)
				s.sounding = true
			s.next = fade + maxf(0.1, _pick_in(cycle.get("hold", [8, 16]), 8.0))


## Plays one call of a scheduled one-shot, if a voice is free.
func _shot(s: Dictionary) -> void:
	var slot := -1
	for i in _shot_players.size():
		if _clock >= _shot_ends[i]:
			slot = i
			break
	if slot < 0:
		return
	var takes: Array = s.takes
	var take: Dictionary = takes[sfx.bank.pick(s.key, takes.size(), rng)]
	var stream := _load(take.file)
	if stream == null:
		return
	var spec: Dictionary = s.spec
	var pan := clampf(_pick_in(spec.get("pan", [0, 0]), 0.0), -1.0, 1.0)
	var j := float(spec.get("pitch_jitter", 0.0))
	var pitch := pow(2.0, rng.randf_range(-j, j) / 12.0)
	var p: AudioStreamPlayer2D = _shot_players[slot]
	p.stream = stream
	p.pitch_scale = pitch
	p.position = Vector2(Placement.pan_x(pan, sfx.space_width()), 0.0)
	# A call of a preset fading in or out is quieter, never skipped.
	var fade_db := linear_to_db(maxf(0.001, sin(clampf(s.level, 0.0, 1.0) * PI * 0.5)))
	p.volume_db = _pick_in(spec.get("volume_db", [-12, -12]), -12.0) + take.volume_db + Placement.voice_db(pan) + fade_db
	_shot_ends[slot] = _clock + stream.get_length() / pitch + 0.05
	shots_played += 1
	if p.is_inside_tree():
		p.play()


## A positional loop follows the camera: pan and level from where its anchor is on screen.
func _place_loop(l) -> void:
	if l.anchor == null or sfx == null:
		return
	var at: Variant = sfx.place(l.anchor)
	if at == null:
		l.place_db = Placement.voice_db(0.0)
		l.player.position = Vector2.ZERO
		return
	l.place_db = maxf(at.db, Placement.CULL_DB) + Placement.voice_db(at.pan)
	l.player.position = Vector2(Placement.pan_x(at.pan, sfx.space_width()), 0.0)


func _key(spec: Dictionary) -> String:
	var takes: Array = sfx.bank._takes(spec.get("takes", [])) if sfx != null else []
	return "%s|%s" % [spec.get("id", ""), takes[0].file if not takes.is_empty() else ""]


## An existing take of a looping layer, or null.
func _stream_of(spec: Dictionary, pick_key: String) -> AudioStream:
	var takes := _existing(spec.get("takes", []))
	if takes.is_empty():
		return null
	return _load(takes[sfx.bank.pick(pick_key, takes.size(), rng)].file)


func _existing(list: Variant) -> Array:
	var out: Array = []
	if sfx == null:
		return out
	for t in sfx.bank._takes(list):
		if sfx.bank.exists(t.file):
			out.append(t)
	return out


func _load(path: String) -> AudioStream:
	return sfx.load_stream(path) if sfx != null else null


func _range(v: Variant, fallback: float) -> Vector2:
	if v is Array and v.size() >= 2:
		var a := float(v[0])
		var b := float(v[1])
		return Vector2(minf(a, b), maxf(a, b))
	if v is float or v is int:
		return Vector2(float(v), float(v))
	return Vector2(fallback, fallback)


func _pick_in(v: Variant, fallback: float) -> float:
	var r := _range(v, fallback)
	return rng.randf_range(r.x, r.y)
