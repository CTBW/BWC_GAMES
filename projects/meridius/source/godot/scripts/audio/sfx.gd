## Sound effects (autoload "Sfx"). Port of src/audio/sfx.ts.
##
## The original synthesises each sound with Web Audio at play time from a short
## recipe. tools/bake renders those recipes with the original code
## (OfflineAudioContext) into res://assets/audio/<name>_<i>.wav: one take for
## the fixed recipes, several for the ones with randomness (noise, pitch
## jitter), one of which is picked at random on each play. The original's
## master gain (0.55) is rendered into the samples, so players run at 0 dB.
## res://assets/audio/sfx.json lists the takes and the minimum gaps.
##
##   Sfx.play("hit_metal")     # same names as the original's sfx(name)
##   Sfx.set_muted(true)       # remembered in user://prefs.json
extends Node

const Prefs = preload("res://scripts/core/prefs.gd")
const META := "res://assets/audio/sfx.json"
## Simultaneous sounds (Web Audio overlaps any number; a battle volley stacks a few).
const POOL := 24

var _muted := false
var _files: Dictionary = {} # name -> Array[String]
var _streams: Dictionary = {} # name -> Array[AudioStream]
var _gaps: Dictionary = {} # name -> ms
var _default_gap := 25
var _master := 0.55
var _last_played: Dictionary = {} # name -> ms
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_muted = bool(Prefs.prefs().get("muted", false))
	_rng.randomize()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(META))
	if not parsed is Dictionary:
		push_error("Sfx: cannot read %s" % META)
		return
	var meta: Dictionary = parsed
	_master = float(meta.get("master", 0.55))
	_default_gap = int(meta.get("defaultGapMs", 25))
	var gaps: Dictionary = meta.get("minGapMs", {})
	for n in gaps:
		_gaps[n] = int(gaps[n])
	var sounds: Dictionary = meta.get("sounds", {})
	for n in sounds:
		_files[n] = Array(sounds[n])


func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		add_child(p)
		_players.append(p)


## Every sound name of the original.
func names() -> PackedStringArray:
	return PackedStringArray(_files.keys())


## Number of baked takes of a sound (0 for an unknown name).
func variant_count(sound: String) -> int:
	return (_files.get(sound, []) as Array).size()


## The AudioStream of one take (loaded on first use), or null.
func stream(sound: String, variant := 0) -> AudioStream:
	var list: Variant = _streams.get(sound)
	if list == null:
		var files: Array = _files.get(sound, [])
		list = []
		for f in files:
			var s := load(f) as AudioStream
			if s == null:
				push_error("Sfx: cannot load %s" % f)
			list.append(s)
		_streams[sound] = list
	if (list as Array).is_empty():
		return null
	return list[absi(variant) % (list as Array).size()]


## The original's master gain (already in the samples).
func master_gain() -> float:
	return _master


func play(sound: String) -> void:
	if _muted:
		return
	var now := Time.get_ticks_msec()
	var min_gap: int = _gaps.get(sound, _default_gap)
	if now - int(_last_played.get(sound, -100000)) < min_gap:
		return
	_last_played[sound] = now
	var n := variant_count(sound)
	if n == 0 or not is_inside_tree() or _players.is_empty():
		return # unknown names make no sound, as in the original
	var s := stream(sound, _rng.randi_range(0, n - 1))
	if s == null:
		return
	var p := _free_player()
	p.stream = s
	p.volume_db = 0.0
	p.play()


func _free_player() -> AudioStreamPlayer:
	for i in _players.size():
		var p := _players[(_next + i) % _players.size()]
		if not p.playing:
			_next = (_next + i + 1) % _players.size()
			return p
	# All busy: take the one started longest ago.
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	return p


func set_muted(m: bool) -> void:
	_muted = m
	Prefs.set_pref("muted", m)
	# The original zeroes its master gain: what is playing falls silent too.
	if m:
		for p in _players:
			p.stop()


func is_muted() -> bool:
	return _muted
