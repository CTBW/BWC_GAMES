## The sound bank: what a sound event plays and how (Godot addition; the
## original synthesised every sound from a recipe, see sfx.gd).
##
## res://assets/audio/bank/bank.json is the hand-edited source. It maps event
## names (the original's `sfx(name)` names plus new ones such as `step_large`)
## to recorded takes and playback options, and holds the ambience presets and
## the music tracks. res://assets/audio/sfx.json lists the synthesised takes
## tools/bake renders from the original (never edit those; see
## tools/bake/README.md). An event plays, in this order:
##   1. its own recorded takes in bank.json (files that exist),
##   2. else the baked synth takes of the same name,
##   3. else its `fallback` event, resolved the same way (step_troll → step_large → step).
## So the game keeps its synth sounds until recorded takes are listed, and a
## listed file that is missing (not yet added, or a typo) falls through
## instead of going silent.
##
## Options (bank `defaults`, overridden per event; an event without a value
## takes its fallback event's, then the default):
##   bus               "SFX" | "UI" | "Voice" | "Ambience" | "Music"
##   volume_db         level of the event
##   pitch             base pitch shift in semitones (a large creature's steps from the small ones' takes)
##   pitch_jitter      ± semitones, random per play
##   volume_jitter_db  ± dB, random per play
##   max_voices        voices of this event at once; a new one takes over the oldest
##   min_gap_ms        a repeat sooner than this is dropped
##   positional        play_at() pans and attenuates it by where it is on screen
## A take is a res:// path or {"file": path, "volume_db": trim, "weight": w};
## an event's take with a weight comes up w times as often as one without
## (weight 1), so 0.25 is a take heard now and then.
##
##   var bank = Bank.load_default()
##   bank.resolve("step_troll")   # {event, takes: [{file, volume_db}], source: "bank"|"synth"|"", via}
##   bank.options("step_troll")   # merged options
##   bank.pick("step", 4, rng)    # take index, never the one played last when there is a choice
##   bank.pick_take("page", takes, rng)   # the same, by the takes' weights
## Pure data: no nodes, no playback (sfx.gd plays what this resolves).
extends RefCounted

const BANK_PATH := "res://assets/audio/bank/bank.json"
const SYNTH_PATH := "res://assets/audio/sfx.json"
const BUSES := ["SFX", "UI", "Voice", "Ambience", "Music"]
const DEFAULTS := {
	"bus": "SFX", "volume_db": 0.0, "pitch": 0.0, "pitch_jitter": 0.0, "volume_jitter_db": 0.0,
	"max_voices": 4, "min_gap_ms": 25, "positional": false,
}
## Longest fallback chain followed (a cycle in bank.json ends here).
const MAX_CHAIN := 8

## event name -> entry (as in bank.json; `takes` normalised to [{file, volume_db}]).
var events: Dictionary = {}
var defaults: Dictionary = DEFAULTS.duplicate()
## {fade, pause_db, presets: {id: {beds, loops, oneshots}}}
var ambience: Dictionary = {}
## {fade, pause_db, tracks: {id: {takes, volume_db}}}
var music: Dictionary = {}
## Baked synth takes: name -> [res path], and the original's master gain (in the samples).
var synth: Dictionary = {}
var synth_master := 0.55
## Index of the take each event played last (pick() avoids repeating it).
var _last: Dictionary = {}
var _exists: Dictionary = {}
## resolve() and options() per event (every step and blow asks; cleared by load_dicts).
var _resolved: Dictionary = {}
var _options: Dictionary = {}


static func load_default():
	var b = load("res://scripts/audio/bank.gd").new()
	b.load_dicts(_read(BANK_PATH), _read(SYNTH_PATH))
	return b


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Bank: cannot find %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("Bank: cannot read %s" % path)
		return {}
	return parsed


## Fill from parsed bank.json and sfx.json dictionaries (tests pass their own).
func load_dicts(bank: Dictionary, synth_meta: Dictionary) -> void:
	events = {}
	defaults = DEFAULTS.duplicate()
	defaults.merge(bank.get("defaults", {}), true)
	var evs: Dictionary = bank.get("events", {})
	for n in evs:
		var e: Dictionary = (evs[n] as Dictionary).duplicate()
		e.takes = _takes(e.get("takes", []))
		events[n] = e
	ambience = bank.get("ambience", {})
	music = bank.get("music", {})
	synth = {}
	var sounds: Dictionary = synth_meta.get("sounds", {})
	for n in sounds:
		synth[n] = Array(sounds[n])
	synth_master = float(synth_meta.get("master", 0.55))
	# The original's per-name gaps hold for its names unless bank.json sets one.
	var gaps: Dictionary = synth_meta.get("minGapMs", {})
	for n in gaps:
		if not events.has(n):
			events[n] = {"takes": []}
		if not (events[n] as Dictionary).has("min_gap_ms"):
			events[n].min_gap_ms = int(gaps[n])
	_last.clear()
	_exists.clear()
	_resolved.clear()
	_options.clear()


## Takes as [{file, volume_db}] (and `weight` when one is given) from strings or dictionaries.
static func _takes(list: Variant) -> Array:
	var out: Array = []
	if not list is Array:
		return out
	for t in list:
		if t is String:
			out.append({"file": t, "volume_db": 0.0})
		elif t is Dictionary and t.has("file"):
			var take := {"file": String(t.file), "volume_db": float(t.get("volume_db", 0.0))}
			if t.has("weight"):
				take.weight = maxf(0.0, float(t.weight))
			out.append(take)
	return out


## True when the resource exists (an imported sound, or a plain file). Cached.
func exists(path: String) -> bool:
	var e: Variant = _exists.get(path)
	if e == null:
		e = path != "" and ResourceLoader.exists(path)
		_exists[path] = e
	return e


## The takes of the first link of `name`'s chain that has any (shared, read only):
## {event (as asked), takes, source "bank" | "synth" | "", via (the event whose takes they are)}.
func resolve(name: String) -> Dictionary:
	var hit: Variant = _resolved.get(name)
	if hit != null:
		return hit
	var r := _resolve(name)
	_resolved[name] = r
	return r


func _resolve(name: String) -> Dictionary:
	var at := name
	for i in MAX_CHAIN:
		var e: Dictionary = events.get(at, {})
		var own: Array = []
		for t in e.get("takes", []):
			if exists(t.file):
				own.append(t)
		if not own.is_empty():
			return {"event": name, "takes": own, "source": "bank", "via": at}
		var baked: Array = synth.get(at, [])
		if not baked.is_empty():
			var out: Array = []
			for f in baked:
				out.append({"file": f, "volume_db": 0.0})
			return {"event": name, "takes": out, "source": "synth", "via": at}
		var fb: Variant = e.get("fallback")
		if not fb is String or fb == "" or fb == at:
			break
		at = fb
	return {"event": name, "takes": [], "source": "", "via": ""}


## Can `name` make a sound (own takes, synth takes or a fallback that can)?
func has_event(name: String) -> bool:
	return not (resolve(name).takes as Array).is_empty()


## The first of `names` that can make a sound, or "".
func first_of(names: Array) -> String:
	for n in names:
		if has_event(n):
			return n
	return ""


## Options of `name`: its own values, then its fallback chain's, then the
## defaults. The dictionary is shared: read it, do not change it.
func options(name: String) -> Dictionary:
	var hit: Variant = _options.get(name)
	if hit != null:
		return hit
	var o := _options_of(name)
	_options[name] = o
	return o


func _options_of(name: String) -> Dictionary:
	var out: Dictionary = {}
	var at := name
	for i in MAX_CHAIN:
		var e: Dictionary = events.get(at, {})
		for k in DEFAULTS:
			if not out.has(k) and e.has(k):
				out[k] = e[k]
		var fb: Variant = e.get("fallback")
		if not fb is String or fb == "" or fb == at:
			break
		at = fb
	for k in DEFAULTS:
		if not out.has(k):
			out[k] = defaults.get(k, DEFAULTS[k])
	out.volume_db = float(out.volume_db)
	out.pitch = float(out.pitch)
	out.pitch_jitter = float(out.pitch_jitter)
	out.volume_jitter_db = float(out.volume_jitter_db)
	out.max_voices = maxi(1, int(out.max_voices))
	out.min_gap_ms = maxi(0, int(out.min_gap_ms))
	out.positional = bool(out.positional)
	if not BUSES.has(String(out.bus)):
		out.bus = "SFX"
	return out


## A take index in 0..count-1 for the takes of `key`, never the one `key`
## played last when there are two or more.
func pick(key: String, count: int, rng: RandomNumberGenerator) -> int:
	if count <= 1:
		_last[key] = 0
		return 0
	var last: int = _last.get(key, -1)
	var i: int
	if last >= 0 and last < count:
		i = rng.randi_range(0, count - 2)
		if i >= last:
			i += 1
	else:
		i = rng.randi_range(0, count - 1)
	_last[key] = i
	return i


## pick() for `takes` (as resolve() gives them), each as often as its weight:
## an index, never the one `key` played last when there are two or more.
## Without weights it is pick() itself (the same draws from `rng`).
func pick_take(key: String, takes: Array, rng: RandomNumberGenerator) -> int:
	var count := takes.size()
	var weighted := false
	for t in takes:
		if (t as Dictionary).has("weight"):
			weighted = true
			break
	if not weighted or count <= 1:
		return pick(key, count, rng)
	var last: int = _last.get(key, -1)
	var total := 0.0
	for j in count:
		if j != last:
			total += float(takes[j].get("weight", 1.0))
	var r := rng.randf() * total
	var i := -1
	for j in count:
		if j == last:
			continue
		i = j
		r -= float(takes[j].get("weight", 1.0))
		if r < 0.0:
			break
	_last[key] = i
	return i


## Every event bank.json names.
func event_names() -> PackedStringArray:
	return PackedStringArray(events.keys())


## The ambience preset `id` ({beds, loops, oneshots}), or {}.
func ambience_preset(id: String) -> Dictionary:
	return (ambience.get("presets", {}) as Dictionary).get(id, {})


## The music track `id` ({takes, volume_db}), or {}.
func music_track(id: String) -> Dictionary:
	return (music.get("tracks", {}) as Dictionary).get(id, {})


## Files bank.json lists that do not exist (yet): recorded takes not added,
## planned ambience and music, typos. Silent at play time; tests report them.
func missing_files() -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	var add := func(list: Variant) -> void:
		for t in _takes(list):
			if not seen.has(t.file) and not exists(t.file):
				seen[t.file] = true
				out.append(t.file)
	for n in events:
		add.call(events[n].get("takes", []))
	var presets: Dictionary = ambience.get("presets", {})
	for id in presets:
		for part in ["beds", "loops", "oneshots"]:
			for spec in presets[id].get(part, []):
				add.call(spec.get("takes", []))
	var tracks: Dictionary = music.get("tracks", {})
	for id in tracks:
		add.call(tracks[id].get("takes", []))
	return out
