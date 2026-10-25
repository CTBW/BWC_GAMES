## Sound (autoload "Sfx"). Port of src/audio/sfx.ts, grown into the game's
## audio engine: buses, a sound bank, sound placed on screen, voice limits,
## ambience and music.
##
## The original synthesises each sound with Web Audio at play time from a short
## recipe. tools/bake renders those recipes with the original code
## (OfflineAudioContext) into res://assets/audio/<name>_<i>.wav: one take for
## the fixed recipes, several for the ones with randomness (noise, pitch
## jitter). The original's master gain (0.55) is rendered into the samples.
## res://assets/audio/sfx.json lists the takes and the minimum gaps.
## Recorded sound comes through the bank (scripts/audio/bank.gd,
## res://assets/audio/bank/bank.json): an event plays its recorded takes when
## the bank lists files that exist, else the baked synth takes, else its
## fallback event, so the game never goes silent while sounds are replaced.
##
##   Sfx.play("click")                    # flat (UI, banners, horns)
##   Sfx.play_at("hit_metal", world_pt)   # placed: panned by where the point is on
##                                        # screen, quieter off screen and zoomed out
##   Sfx.play_at(n, pt, {"volume_db": -3})  # opts: volume_db (added to the bank's)
##   Sfx.first_event(["step_troll", "step_large", "step"])  # the first that can sound
##   Sfx.set_listener(view) / clear_listener(view)   # the view whose `cam` places sounds
##   Sfx.set_ambience("camp") / release_ambience("camp")  # crossfades; "" = silence
##   Sfx.set_anchor("campfire", world_pt) / clear_anchor("campfire")
##   Sfx.set_music("camp")                # crossfade on the Music bus; no tracks yet = no-op
##   Sfx.set_muted(true)                  # remembered in user://prefs.json
##   Sfx.set_volume("music", 0.6)         # master | music | ambience | sfx | voice, 0..1, remembered
##
## Buses (res://default_bus_layout.tres): Master (hard limiter) ← Music,
## Ambience, UI, SFX, Voice. Music and Ambience carry compressors keyed from
## SFX and from Voice, so a big hit or a shout dips the bed a few dB.
##
## Voices: a pool of flat players (AudioStreamPlayer) and a pool of placed
## ones (AudioStreamPlayer2D, see placement.gd for why and how). Each event has
## `max_voices`: a new sound over the limit takes the place of the event's
## oldest; a full pool gives up its oldest voice. Voice bookkeeping runs on the
## take's length, not on the player's state, so it also works (and is tested)
## outside the scene tree, where nothing is actually played.
##
## Pause (the tree paused behind the menu): world sounds hold and resume with
## the game, UI sounds play on, the ambience dips and its one-shots stop, the
## music dips. Mute: the Master bus is muted and nothing new starts.
extends Node

const Prefs = preload("res://scripts/core/prefs.gd")
const Bank = preload("res://scripts/audio/bank.gd")
const Placement = preload("res://scripts/audio/placement.gd")
const LoopDeck = preload("res://scripts/audio/loop_deck.gd")
const Ambience = preload("res://scripts/audio/ambience.gd")
const Camera = preload("res://scripts/render/camera.gd")

const LAYOUT := "res://default_bus_layout.tres"
const META := Bank.SYNTH_PATH
## Flat voices (a battle volley stacks a few; the UI needs one or two).
const FLAT_VOICES := 16
## Placed voices: a whole enemy turn of blows, steps and volleys.
const WORLD_VOICES := 24
## Volume sliders: key -> [prefs key, bus].
const VOLUMES := {
	"master": ["volMaster", "Master"], "music": ["volMusic", "Music"], "ambience": ["volAmbience", "Ambience"],
	"sfx": ["volSfx", "SFX"], "voice": ["volVoice", "Voice"],
}
## Volumes changed from a slider are written to prefs this long after the last change.
const SAVE_DELAY_MS := 400


class Voice extends RefCounted:
	var player: Node
	var positional := false
	var event := ""
	var bus := ""
	## ms: when it started and when its take is over.
	var started := 0
	var ends := 0
	## ms left when held by the pause (-1: not held).
	var held := -1


var bank
var _muted := false
var _paused := false
var _flat: Array = []
var _world: Array = []
var _space: Node2D
var _ear: AudioListener2D
var _ambience: Node2D
var _music: Node
var _music_id := ""
var _listener: WeakRef = null
var _last_played: Dictionary = {} # event -> ms
var _streams: Dictionary = {} # path -> AudioStream
var _rng := RandomNumberGenerator.new()
var _volumes: Dictionary = {} # key -> 0..1
var _save_at := -1
## Sounds started per event since the game began (tests and the play-through read it).
var counts: Dictionary = {}
## Tests: a fixed clock in ms instead of Time.get_ticks_msec() (-1: real time).
var clock_ms := -1


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var prefs := Prefs.prefs()
	_muted = bool(prefs.get("muted", false))
	_rng.randomize()
	bank = Bank.load_default()
	ensure_buses()
	for i in FLAT_VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		add_child(p)
		_flat.append(_voice(p, false))
	# The placed voices, the ambience and a listener live in a 2D space of their own.
	_space = Node2D.new()
	_space.name = "Space"
	add_child(_space)
	_ear = AudioListener2D.new()
	_ear.name = "Listener"
	_space.add_child(_ear)
	for i in WORLD_VOICES:
		var p := AudioStreamPlayer2D.new()
		p.name = "World%d" % i
		p.attenuation = 0.0
		p.max_distance = 1e7
		_space.add_child(p)
		_world.append(_voice(p, true))
	_ambience = Ambience.new()
	_ambience.sfx = self
	_space.add_child(_ambience)
	_music = LoopDeck.new()
	_music.name = "Music"
	add_child(_music)
	for k in VOLUMES:
		_volumes[k] = clampf(float(prefs.get(VOLUMES[k][0], 1.0)), 0.0, 1.0)
	_apply_volumes()
	_ambience.set_muted(_muted)


func _voice(p: Node, positional: bool) -> Voice:
	var v := Voice.new()
	v.player = p
	v.positional = positional
	return v


func _ready() -> void:
	_ear.make_current()


func _process(delta: float) -> void:
	var p := get_tree().paused
	if p != _paused:
		set_paused(p)
	advance(minf(delta, 0.1))
	if _save_at >= 0 and _now() >= _save_at:
		_save_volumes()


func _exit_tree() -> void:
	if _save_at >= 0:
		_save_volumes()
	# A stream still playing at quit keeps its playback (and an Ogg's packet
	# data) in the AudioServer: "ObjectDB instances leaked" / "resources still
	# in use at exit" for every bed and loop. Stop everything first.
	_music.clear()
	_ambience.beds.clear()
	_ambience.loops.clear()
	_ambience._stop_shots()
	for v: Voice in _flat + _world:
		_halt(v)


## Fades and schedules: one step (real seconds). _process calls it; tests call it directly.
func advance(dt: float) -> void:
	_ambience.advance(dt)
	_music.advance(dt)


func _now() -> int:
	return clock_ms if clock_ms >= 0 else Time.get_ticks_msec()


# ---------------------------------------------------------------- buses

## Loads res://default_bus_layout.tres when the buses are not there (the
## engine loads it at start; a test or tool may have changed the layout).
func ensure_buses() -> void:
	if AudioServer.get_bus_index("SFX") >= 0 and AudioServer.get_bus_index("Ambience") >= 0:
		return
	var layout := load(LAYOUT) as AudioBusLayout
	if layout == null:
		push_error("Sfx: cannot load %s" % LAYOUT)
		return
	AudioServer.set_bus_layout(layout)


## Slider value 0..1 → bus dB (squared, so half way is -12 dB, as loudness is heard).
static func volume_db(v: float) -> float:
	return -80.0 if v <= 0.0 else maxf(-80.0, 40.0 * log(v) / log(10.0))


func set_volume(key: String, v: float, save := true) -> void:
	if not VOLUMES.has(key):
		push_error("Sfx: no volume '%s'" % key)
		return
	_volumes[key] = clampf(v, 0.0, 1.0)
	_apply_volumes()
	if save:
		_save_volumes()
	else:
		_save_at = _now() + SAVE_DELAY_MS


func volume(key: String) -> float:
	return float(_volumes.get(key, 1.0))


func _save_volumes() -> void:
	_save_at = -1
	var p := Prefs.prefs()
	for k in VOLUMES:
		p[VOLUMES[k][0]] = _volumes[k]
	Prefs.set_prefs(p)


func _apply_volumes() -> void:
	for k in VOLUMES:
		var i := AudioServer.get_bus_index(VOLUMES[k][1])
		if i < 0:
			continue
		var v: float = _volumes[k]
		AudioServer.set_bus_volume_db(i, volume_db(v))
		AudioServer.set_bus_mute(i, v <= 0.0 or (k == "master" and _muted))


# ---------------------------------------------------------------- one-shots

## Every name that can sound: the original's and the bank's events.
func names() -> PackedStringArray:
	var out := PackedStringArray(bank.synth.keys())
	for n in bank.event_names():
		if not out.has(n) and bank.has_event(n):
			out.append(n)
	return out


func has_event(sound: String) -> bool:
	return bank.has_event(sound)


## The first of `candidates` that can sound, or "" (footsteps by unit type: step_troll → step_large → step).
func first_event(candidates: Array) -> String:
	return bank.first_of(candidates)


## Number of takes `play(sound)` picks from (0 for an unknown name).
func variant_count(sound: String) -> int:
	return (bank.resolve(sound).takes as Array).size()


## The AudioStream of one take (loaded on first use), or null.
func stream(sound: String, variant := 0) -> AudioStream:
	var takes: Array = bank.resolve(sound).takes
	if takes.is_empty():
		return null
	return load_stream(takes[absi(variant) % takes.size()].file)


func load_stream(path: String) -> AudioStream:
	var s: Variant = _streams.get(path)
	if s == null:
		if not bank.exists(path):
			return null
		s = load(path) as AudioStream
		if s == null:
			push_error("Sfx: cannot load %s" % path)
			return null
		_streams[path] = s
	return s


## The original's master gain (already in the synth samples).
func master_gain() -> float:
	return bank.synth_master


## Plays `sound` flat (centred, full level).
func play(sound: String, opts: Dictionary = {}) -> void:
	_start(sound, null, opts)


## Plays `sound` from world point `at` of the listening view: panned by where it
## is on screen, quieter off screen and zoomed out. Flat when the event is not
## positional or no view listens.
func play_at(sound: String, at: Vector2, opts: Dictionary = {}) -> void:
	_start(sound, at, opts)


func _start(sound: String, at: Variant, opts: Dictionary) -> Voice:
	if _muted:
		return null
	var o: Dictionary = bank.options(sound)
	var spot: Variant = null
	if at != null and o.positional:
		spot = place(at)
		# Far off screen: not worth a voice, and it does not hold back a nearer one.
		if spot != null and not Placement.audible(spot.db):
			return null
	var now := _now()
	if now - int(_last_played.get(sound, -100000)) < int(o.min_gap_ms):
		return null
	_last_played[sound] = now
	var r: Dictionary = bank.resolve(sound)
	var takes: Array = r.takes
	if takes.is_empty():
		return null # unknown names make no sound, as in the original
	var take: Dictionary = takes[bank.pick_take(r.via, takes, _rng)]
	var s := load_stream(take.file)
	if s == null:
		return null
	var v := _take_voice(sound, int(o.max_voices), spot != null, now)
	var pj: float = o.pitch_jitter
	var vj: float = o.volume_jitter_db
	var pitch := pow(2.0, (o.pitch + _rng.randf_range(-pj, pj)) / 12.0)
	var db: float = o.volume_db + take.volume_db + _rng.randf_range(-vj, vj) + float(opts.get("volume_db", 0.0))
	var p := v.player
	if spot != null:
		db += spot.db + Placement.voice_db(spot.pan)
		(p as AudioStreamPlayer2D).position = Vector2(Placement.pan_x(spot.pan, space_width()), 0.0)
	p.stream = s
	p.bus = o.bus
	p.pitch_scale = pitch
	p.volume_db = db
	v.event = sound
	v.bus = o.bus
	v.started = now
	v.ends = now + int(ceil(s.get_length() / pitch * 1000.0)) + 30
	v.held = -1
	counts[sound] = int(counts.get(sound, 0)) + 1
	if p.is_inside_tree():
		p.stream_paused = false
		p.play()
		if _paused and v.bus != "UI":
			# A world sound asked for behind the pause menu waits for the game.
			p.stream_paused = true
			v.held = v.ends - now
	return v


## A voice for a new sound of `event`: over the event's limit, its oldest
## voice; else a free one from the right pool; else that pool's oldest.
func _take_voice(event: String, max_voices: int, positional: bool, now: int) -> Voice:
	var mine: Array = []
	for v: Voice in _flat + _world:
		if v.event == event and _busy(v, now):
			mine.append(v)
	if mine.size() >= max_voices:
		var oldest: Voice = _oldest(mine)
		_halt(oldest)
		if oldest.positional == positional:
			return oldest
	var pool: Array = _world if positional else _flat
	for v: Voice in pool:
		if not _busy(v, now):
			return v
	var o: Voice = _oldest(pool)
	_halt(o)
	return o


static func _oldest(list: Array) -> Voice:
	var o: Voice = list[0]
	for v: Voice in list:
		if v.started < o.started:
			o = v
	return o


func _busy(v: Voice, now: int) -> bool:
	if v.held >= 0:
		return true
	if now >= v.ends:
		return false
	# Stopped from outside (or the stream ended early): free.
	if v.player.is_inside_tree() and now - v.started > 250 and not v.player.playing:
		return false
	return true


func _halt(v: Voice) -> void:
	v.player.stop()
	v.ends = 0
	v.held = -1
	v.event = ""


## Voices sounding now, per event (tests, the play-through and the asset capture read it).
func playing(event := "") -> int:
	var n := 0
	var now := _now()
	for v: Voice in _flat + _world:
		if _busy(v, now) and (event == "" or v.event == event):
			n += 1
	return n


## The voice records (tests).
func voices() -> Array:
	return _flat + _world


# ---------------------------------------------------------------- placement

## The view whose camera places play_at sounds and positional loops: a
## CanvasItem with `cam` (scripts/render/camera.gd). The last one set listens.
func set_listener(view: Node) -> void:
	_listener = weakref(view) if view != null else null


## `view` stops listening (it leaves the screen): its placed sounds stop.
func clear_listener(view: Node) -> void:
	if listener() != view:
		return
	_listener = null
	for v: Voice in _world:
		_halt(v)


func listener() -> Node:
	var n: Variant = _listener.get_ref() if _listener != null else null
	return n if n != null and is_instance_valid(n) else null


## {pan, db} of world point `at` in the listening view, or null when no view listens.
func place(at: Vector2) -> Variant:
	var view := listener()
	if view == null:
		return null
	var cam: Variant = view.get("cam")
	if cam == null:
		return null
	var size: Vector2 = Camera.view_size(view) if view.is_inside_tree() else Vector2(1920, 1080)
	return Placement.place(cam.world_to_screen(at.x, at.y, size.x, size.y), size, float(cam.zoom))


## Width of the screen the 2D voices pan across (Godot's pan law divides by it).
func space_width() -> float:
	return get_viewport().get_visible_rect().size.x if is_inside_tree() else 1920.0


# ---------------------------------------------------------------- ambience and music

## Crossfades to ambience preset `id` ("" for none) over `fade` s (-1: the bank's).
func set_ambience(id: String, fade := -1.0) -> void:
	_ambience.set_preset(id, fade)


## Fades out preset `id` if it is still the one playing (a view leaving the screen).
func release_ambience(id: String, fade := -1.0) -> void:
	if _ambience.preset_id == id:
		_ambience.set_preset("", fade)


func ambience_id() -> String:
	return _ambience.preset_id


func ambience() -> Node:
	return _ambience


func set_anchor(id: String, at: Vector2) -> void:
	_ambience.set_anchor(id, at)


func clear_anchor(id: String) -> void:
	_ambience.clear_anchor(id)


## Crossfades to music track `id` of bank.json ("" for none). A track without
## takes that exist fades the current one out and plays nothing.
func set_music(id: String, fade := -1.0) -> void:
	if id == _music_id:
		return
	_music_id = id
	var f := fade if fade >= 0.0 else float(bank.music.get("fade", 3.0))
	_music.stop_all(f)
	var track: Dictionary = bank.music_track(id)
	var takes: Array = []
	for t in bank._takes(track.get("takes", [])):
		if bank.exists(t.file):
			takes.append(t)
	if takes.is_empty():
		return
	var t: Dictionary = takes[bank.pick("music:" + id, takes.size(), _rng)]
	var s := load_stream(t.file)
	if s != null:
		_music.start(id, s, "Music", float(track.get("volume_db", 0.0)) + t.volume_db, f)


func music_id() -> String:
	return _music_id


func music_deck() -> Node:
	return _music


# ---------------------------------------------------------------- pause and mute

func set_paused(p: bool) -> void:
	if p == _paused:
		return
	_paused = p
	var now := _now()
	for v: Voice in _flat + _world:
		if v.bus == "UI":
			continue
		if p and _busy(v, now):
			v.held = maxi(0, v.ends - now)
			v.player.stream_paused = true
		elif not p and v.held >= 0:
			v.ends = now + v.held
			v.held = -1
			v.player.stream_paused = false
	_ambience.set_paused(p)
	_music.duck_db = float(bank.music.get("pause_db", -4.0)) if p else 0.0


func is_paused() -> bool:
	return _paused


func set_muted(m: bool) -> void:
	_muted = m
	Prefs.set_pref("muted", m)
	_apply_volumes()
	# The original zeroes its master gain: what is playing falls silent too.
	if m:
		for v: Voice in _flat + _world:
			_halt(v)
	_ambience.set_muted(m)


func is_muted() -> bool:
	return _muted
