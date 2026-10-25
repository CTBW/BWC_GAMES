## The audio engine (scripts/audio/: sfx.gd, bank.gd, placement.gd,
## loop_deck.gd, ambience.gd), the bus layout and the footsteps
## (SoldierAnim.footfalls, battle_view's per-squad treads).
## The runner works before the scene tree is live, so nothing is actually
## heard here: these tests check what the engine decides (takes, buses,
## voices, levels, fades, schedules). Most use a fresh Sfx instance with a
## test bank whose "recorded" takes are baked synth files, and a fixed clock.
extends "res://tests/test_case.gd"

const JS = preload("res://scripts/core/js.gd")
const Prefs = preload("res://scripts/core/prefs.gd")
const Bank = preload("res://scripts/audio/bank.gd")
const Placement = preload("res://scripts/audio/placement.gd")
const LoopDeck = preload("res://scripts/audio/loop_deck.gd")
const Camera = preload("res://scripts/render/camera.gd")
const SfxScript = preload("res://scripts/audio/sfx.gd")
const SoldierAnim = preload("res://scripts/render/soldier_anim.gd")
const SquadView = preload("res://scripts/render/squad_view.gd")
const BattleView = preload("res://scripts/render/battle_view.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const ViewScene = preload("res://scenes/battle/battle_view.tscn")
const WoodlandCamp = preload("res://scripts/render/woodland_camp.gd")

## Baked files standing in for recorded takes (they exist; long ones keep a voice busy).
const LONG := "res://assets/audio/hooves_0.wav" # 3.25 s
const LONG2 := "res://assets/audio/warhorn_0.wav" # 2.7 s
const SHORT := "res://assets/audio/click_0.wav"
const MISSING := "res://assets/audio/bank/not_recorded_yet.ogg"


## A view the engine can listen through: a CanvasItem with a camera.
class FakeView extends Node2D:
	var cam: RefCounted


var sfx: Node # the autoload
var _made: Array = []
var _prefs_before: Dictionary


func before_all() -> void:
	sfx = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Sfx")
	_prefs_before = Prefs.prefs()


func after_each() -> void:
	for n in _made:
		if is_instance_valid(n):
			n.free()
	_made.clear()
	if sfx != null:
		sfx.clock_ms = -1


func after_all() -> void:
	# Leave the player's sound settings as they were.
	var keep := {}
	for k in ["muted", "volMaster", "volMusic", "volAmbience", "volSfx", "volVoice"]:
		keep[k] = _prefs_before.get(k)
	Prefs.set_prefs(keep)
	if sfx != null:
		for k in SfxScript.VOLUMES:
			sfx._volumes[k] = clampf(float(keep[SfxScript.VOLUMES[k][0]]), 0.0, 1.0)
		sfx._muted = bool(keep.muted)
		sfx._apply_volumes()


## A fresh engine (not the autoload) on `bank` (with the real synth takes), clock at 10 s.
func _engine(bank: Dictionary = {}) -> Node:
	var e: Node = SfxScript.new()
	_made.append(e)
	if not bank.is_empty():
		e.bank.load_dicts(bank, _synth_meta())
	e._muted = false
	e.clock_ms = 10000
	e._rng.seed = 7
	e._ambience.rng.seed = 11
	return e


func _synth_meta() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(Bank.SYNTH_PATH))


func _listener(e: Node, at := Vector2.ZERO, zoom := 1.0) -> FakeView:
	var v := FakeView.new()
	v.cam = Camera.new(at.x, at.y, zoom)
	_made.append(v)
	e.set_listener(v)
	return v


# ---------------------------------------------------------------- bus layout

func test_bus_layout_present() -> void:
	var want := {"Master": "", "Music": "Master", "Ambience": "Master", "SFX": "Master", "Voice": "Master", "UI": "Master"}
	for n in want:
		var i := AudioServer.get_bus_index(n)
		if not assert_true(i >= 0, "bus %s" % n):
			continue
		if n != "Master":
			assert_eq(String(AudioServer.get_bus_send(i)), want[n], "%s sends to Master" % n)
	var master := AudioServer.get_bus_index("Master")
	var limiter := false
	for k in AudioServer.get_bus_effect_count(master):
		limiter = limiter or AudioServer.get_bus_effect(master, k) is AudioEffectHardLimiter
	assert_true(limiter, "a limiter on Master")
	# The beds dip under big hits and shouts: compressors keyed from SFX and from Voice.
	for n in ["Ambience", "Music"]:
		var i := AudioServer.get_bus_index(n)
		var keys: Array = []
		for k in AudioServer.get_bus_effect_count(i):
			var fx := AudioServer.get_bus_effect(i, k)
			if fx is AudioEffectCompressor:
				keys.append(String(fx.sidechain))
				# Subtle: a gentle ratio, and hits under -14 dBFS do not dip anything.
				assert_true(fx.ratio <= 2.0 and fx.threshold <= -14.0, "%s ducking is gentle" % n)
				# A key bus is mixed before the bus it ducks (a higher index).
				assert_true(AudioServer.get_bus_index(fx.sidechain) > i, "%s key %s mixed first" % [n, fx.sidechain])
		keys.sort()
		assert_eq(keys, ["SFX", "Voice"], "%s ducked by SFX and Voice" % n)
	var layout := load("res://default_bus_layout.tres") as AudioBusLayout
	assert_not_null(layout, "default_bus_layout.tres loads")


# ---------------------------------------------------------------- bank

func test_shipped_bank_routes_the_original_names() -> void:
	var b = Bank.load_default()
	var fx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/assets/sfx_names.json"))
	for n in fx.names:
		assert_true(b.events.has(n), "%s in bank.json" % n)
		var r: Dictionary = b.resolve(n)
		# Recorded takes where the bank has them, else the baked synth ones: every name sounds.
		assert_true(r.source in ["bank", "synth"], "%s sounds (%s)" % [n, r.source])
		assert_eq(r.via, n)
	# (Events with takes in Git; the others may fall back to synth in a clone.)
	for n in ["block", "step", "horn", "warhorn"]:
		assert_eq(b.resolve(n).source, "bank", "%s plays recorded takes" % n)
	for n in ["stance_shieldwall", "warcry_orc_warlord"]:
		_assert_recorded(b, n)
	for n in ["click", "select", "deny", "page", "coin", "build", "turn"]:
		var o: Dictionary = b.options(n)
		assert_eq(o.bus, "UI", "%s on the UI bus" % n)
		assert_false(o.positional, "%s is flat" % n)
	for n in ["step", "swing", "hit_metal", "hit_flesh", "block", "miss", "death", "explosion", "fireball", "cast", "ballista"]:
		var o: Dictionary = b.options(n)
		assert_eq(o.bus, "SFX", "%s on the SFX bus" % n)
		assert_true(o.positional, "%s is placed" % n)
	assert_eq(b.options("warcry_orc_warlord").bus, "Voice", "the warlord's war cry is a voice")
	assert_true(b.options("warcry_orc_warlord").positional)
	for n in ["horn", "warhorn", "drum", "victory", "defeat"]:
		assert_false(b.options(n).positional, "%s is heard over the whole field" % n)
	# A unit's own kind (battle_view._kind_sfx_at): aliases reach recorded takes.
	assert_true(b.first_of(["death_goblin_rabble", "death_enemy", "death"]) in ["death_goblin_rabble", "death"])
	assert_eq(b.first_of(["death_wolf_rider", "death_enemy", "death"]), "death_wolf_rider")
	assert_eq(b.first_of(["step_orc_brute", "step_medium", "step"]), "step_orc_brute")
	assert_eq(b.options("step_orc_brute").pitch, 1.5, "an alias keeps its own options")
	# Knox's orders (Higgsfield + CC0 layers, kept local) for the player's men; footmen and
	# collie guards share the Defend stance, so the hounds have their own growl and yelp.
	for n in ["stance_spearwall", "stance_square", "stance_footman", "stance_overwatch", "rout_player", "victory"]:
		_assert_recorded(b, n)
		assert_eq(b.options(n).bus, "Voice", "%s is a voice" % n)
	# (Without the local voices, in a clone, the kind chain goes on to the synth sound.)
	assert_eq(b.first_of(["stance_defend", "stance_footman", "stance_player", "stance"]), _voice_or(b, "stance_footman", "stance"))
	assert_eq(b.first_of(["stance_defend", "stance_collie_guard", "stance_player", "stance"]), "stance_collie_guard")
	assert_eq(b.resolve("stance_collie_guard").via, "roar_collie_guard", "a hound braces with a growl")
	assert_eq(b.first_of(["rout_footman", "rout_player", "rout"]), _voice_or(b, "rout_player", "rout"))
	assert_eq(b.first_of(["rout_collie_guard", "rout_player", "rout"]), "rout_collie_guard")
	assert_eq(b.resolve("rout_collie_guard").via, "death_collie_guard", "a hound breaks with a yelp")
	# His answers to the player's orders (battle_view._say), heard wherever the squad is.
	for n in ["order_select", "order_move", "order_attack", "order_shield_charge", "order_aimed_shot"]:
		_assert_recorded(b, n)
		assert_eq(b.options(n).bus, "Voice", "%s is a voice" % n)
		assert_false(b.options(n).positional, "%s is flat" % n)
		assert_eq(b.options(n).max_voices, 1, "%s: one at a time" % n)
	# (No synth answers: in a clone the squads obey without a word.)
	assert_eq(b.first_of(["order_shield_charge", "order_attack_footman", "order_attack"]), _voice_or(b, "order_shield_charge", ""))
	assert_eq(b.first_of(["order_shieldbash", "order_attack_footman", "order_attack"]), _voice_or(b, "order_attack", ""))
	# Only the gitignored takes may be missing (Sonniss sources and the Higgsfield
	# voices, rendered from the local audio library by tools/audio/build_bank.py);
	# a clone plays the fallbacks.
	var missing: PackedStringArray = b.missing_files()
	print("      bank.json: %d files missing" % missing.size())
	for f in missing:
		assert_true(f.begins_with("res://assets/audio/bank/local/"), "%s is missing" % f)
	# Every recorded take says where it came from.
	var prov: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/bank/provenance.json"))
	assert_true(prov is Dictionary, "provenance.json")
	for ev in b.events:
		for t in b.events[ev].takes:
			assert_true((prov as Dictionary).has(t.file), "%s: %s in provenance.json" % [ev, t.file])
	# The public repository gets no Sonniss or Higgsfield sound: those stay in local/.
	for f in prov:
		if String(f).begins_with("res://assets/audio/bank/local/"):
			continue
		for s in prov[f].get("sources", []):
			var lic := str(s.get("license", ""))
			assert_false("Sonniss" in lic or "Higgsfield" in lic, "%s (%s) is outside local/" % [f, lic])


## `n` plays recorded takes, unless every take it lists is a gitignored local
## one this checkout does not have (a clone without the audio library).
func _assert_recorded(b, n: String) -> void:
	if b.resolve(n).source == "bank":
		return
	var takes: Array = b.events.get(n, {}).get("takes", [])
	if not assert_false(takes.is_empty(), "%s lists recorded takes" % n):
		return
	for t in takes:
		assert_true(t.file.begins_with("res://assets/audio/bank/local/") and not b.exists(t.file), "%s plays recorded takes (%s)" % [n, t.file])


## `n` when it plays recorded takes here, else `other` (its local takes are missing).
func _voice_or(b, n: String, other: String) -> String:
	return n if b.resolve(n).source == "bank" else other


func test_resolution_and_fallback_chain() -> void:
	var b = Bank.new()
	b.load_dicts({
		"defaults": {"max_voices": 3},
		"events": {
			"recorded": {"takes": [LONG, {"file": LONG2, "volume_db": -3}], "bus": "Voice"},
			"half": {"takes": [MISSING, SHORT]},
			"not_yet": {"takes": [MISSING]},
			"step": {"positional": true, "min_gap_ms": 70, "max_voices": 6},
			"step_large": {"fallback": "step", "pitch": -4.0},
			"step_troll": {"fallback": "step_large", "volume_db": 2.0},
			"loop_a": {"fallback": "loop_b"},
			"loop_b": {"fallback": "loop_a"},
			"orphan": {"fallback": "nothing_here"},
		},
	}, _synth_meta())
	var r: Dictionary = b.resolve("recorded")
	assert_eq(r.source, "bank")
	assert_eq(r.takes.size(), 2)
	assert_eq(r.takes[1], {"file": LONG2, "volume_db": -3.0}, "a take with its own trim")
	# A listed file that is missing is skipped; the rest still play.
	assert_eq(b.resolve("half").takes, [{"file": SHORT, "volume_db": 0.0}])
	# Recorded takes not added yet: nothing of its own and no synth, so silent.
	assert_eq(b.resolve("not_yet").source, "")
	assert_false(b.has_event("not_yet"))
	# The original's name with no recorded takes: the baked synth.
	r = b.resolve("hit_metal")
	assert_eq([r.source, r.via, r.takes.size()], ["synth", "hit_metal", 4])
	# Steps by kind: step_troll → step_large → step's synth takes.
	r = b.resolve("step_troll")
	assert_eq([r.event, r.source, r.via], ["step_troll", "synth", "step"])
	var o: Dictionary = b.options("step_troll")
	assert_eq(o.volume_db, 2.0, "its own level")
	assert_eq(o.pitch, -4.0, "the large feet's pitch")
	assert_eq([o.positional, o.min_gap_ms, o.max_voices], [true, 70, 6], "step's limits")
	assert_eq(b.options("anything").max_voices, 3, "bank defaults")
	assert_eq(b.first_of(["step_wolf", "step_large", "step"]), "step_large")
	assert_eq(b.first_of(["nope", "not_yet"]), "")
	# A fallback cycle or a dead end ends quietly.
	assert_eq(b.resolve("loop_a").takes, [])
	assert_eq(b.resolve("orphan").takes, [])
	assert_eq(b.resolve("no_such_event").takes, [])
	assert_true(b.missing_files().has(MISSING))


func test_takes_never_repeat_back_to_back() -> void:
	var b = Bank.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for count in [2, 3, 4, 7]:
		var last := -1
		var seen := {}
		for i in 400:
			var k: int = b.pick("ev%d" % count, count, rng)
			assert_true(k >= 0 and k < count)
			if k == last:
				fail("take %d twice in a row of %d" % [k, count])
				break
			last = k
			seen[k] = true
		assert_eq(seen.size(), count, "every take of %d comes up" % count)
	assert_eq(b.pick("one", 1, rng), 0, "a single take repeats")
	# Through the engine: the take a voice got is never the last one.
	var e := _engine({"events": {"zap": {"takes": [SHORT, LONG, LONG2], "min_gap_ms": 0, "max_voices": 9}}})
	var prev: Variant = null
	for i in 30:
		e.clock_ms += 10
		var v = e._start("zap", null, {})
		assert_ne(v.player.stream, prev, "play %d repeats the take" % i)
		prev = v.player.stream


func test_a_weighted_take_comes_up_now_and_then() -> void:
	var b = Bank.new()
	b.load_dicts({"events": {"page": {"takes": [SHORT, LONG, {"file": LONG2, "weight": 0.25}]}}}, _synth_meta())
	var takes: Array = b.resolve("page").takes
	assert_eq(takes[2], {"file": LONG2, "volume_db": 0.0, "weight": 0.25})
	assert_false((takes[0] as Dictionary).has("weight"), "no weight unless one is given")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var counts := [0, 0, 0]
	var last := -1
	for i in 3000:
		var k: int = b.pick_take("page", takes, rng)
		assert_ne(k, last, "never twice in a row")
		last = k
		counts[k] += 1
	# Without repeats, a take of weight w among two of weight 1 plays w / (1 + 2w) of the time: 1 in 6.
	assert_almost(counts[2] / 3000.0, 1.0 / 6.0, 0.03, "the weighted take: %s" % [counts])
	assert_almost(float(counts[0]) / counts[1], 1.0, 0.15, "the others alike")
	# Unweighted takes draw exactly as pick() does.
	var r1 := RandomNumberGenerator.new()
	var r2 := RandomNumberGenerator.new()
	r1.seed = 9
	r2.seed = 9
	var plain := [{"file": SHORT, "volume_db": 0.0}, {"file": LONG, "volume_db": 0.0}, {"file": LONG2, "volume_db": 0.0}]
	for i in 20:
		assert_eq(b.pick_take("a", plain, r1), b.pick("b", 3, r2))
	# Through the engine: the weighted take is the rare one (1 in 12 here; two takes simply alternate).
	var e := _engine({"events": {"page": {"takes": [SHORT, LONG, {"file": LONG2, "weight": 0.1}], "min_gap_ms": 0, "max_voices": 9}}})
	var rare := 0
	for i in 240:
		e.clock_ms += 10
		if e._start("page", null, {}).player.stream == e.load_stream(LONG2):
			rare += 1
	assert_true(rare > 0 and rare < 50, "the weighted take %d times of 240" % rare)


# ---------------------------------------------------------------- voices

func test_voice_limit_takes_the_oldest() -> void:
	var e := _engine({"events": {
		"zap": {"takes": [LONG], "max_voices": 2, "min_gap_ms": 0},
		"many": {"takes": [LONG], "max_voices": 99, "min_gap_ms": 0},
		"gap": {"takes": [SHORT], "min_gap_ms": 100},
	}})
	var t0: int = e.clock_ms
	for i in 3:
		e.clock_ms = t0 + i * 10
		e.play("zap")
	assert_eq(e.playing("zap"), 2, "two at most")
	var starts: Array = []
	for v in e.voices():
		if v.event == "zap":
			starts.append(v.started)
	starts.sort()
	assert_eq(starts, [t0 + 10, t0 + 20], "the oldest made way")
	# A full pool gives up its oldest voice.
	for i in 20:
		e.clock_ms = t0 + 100 + i
		e.play("many")
	assert_eq(e.playing(), SfxScript.FLAT_VOICES, "the flat pool is full")
	assert_eq(e.playing("many"), SfxScript.FLAT_VOICES)
	# A voice is free again once its take is over.
	e.clock_ms = t0 + 100 + 20 + 3300
	assert_eq(e.playing(), 0)
	# Repeats sooner than min_gap_ms are dropped.
	e.play("gap")
	e.clock_ms += 50
	e.play("gap")
	assert_eq(e.counts.get("gap", 0), 1)
	e.clock_ms += 60
	e.play("gap")
	assert_eq(e.counts.get("gap", 0), 2)


func test_placed_sounds_pan_and_fade_with_the_camera() -> void:
	var e := _engine()
	var view := _listener(e) # camera at the world origin, zoom 1, view 1920×1080
	# The event's own level in the mix (bank.json); placement adds to it.
	var lv: float = e.bank.options("hit_metal").volume_db
	# Right of centre: panned right, as loud as a flat sound (the 2D voice's 6 dB back).
	var v = e._start("hit_metal", Vector2(768, 0), {})
	assert_true(v.positional, "a placed voice")
	var p: Dictionary = Placement.place(Vector2(960 + 768, 540), Vector2(1920, 1080), 1.0)
	assert_almost(p.pan, 0.6, 1e-6)
	assert_almost(v.player.position.x, 0.6 * 1920.0, 1e-3)
	assert_almost(v.player.volume_db, lv + Placement.voice_db(0.6), 1e-4)
	assert_eq(v.player.bus, &"SFX")
	# Left and centre.
	e.clock_ms += 100
	v = e._start("hit_metal", Vector2(-960, 0), {})
	assert_almost(v.player.position.x, -0.75 * 1920.0, 1e-3, "the left edge")
	# Zoomed out: quieter.
	view.cam.zoom = 0.5
	e.clock_ms += 100
	v = e._start("hit_metal", Vector2.ZERO, {"volume_db": -2.0})
	assert_almost(v.player.volume_db, lv - 4.0 - 2.0 + Placement.CENTRE_DB, 1e-4)
	view.cam.zoom = 1.0
	# Half a screen beyond the edge: 12 dB down; far away: not played at all, and no gap used.
	e.clock_ms += 100
	v = e._start("hit_metal", Vector2(1920, 0), {})
	assert_almost(v.player.volume_db, lv - 12.0 + Placement.voice_db(1.0), 1e-4)
	e.clock_ms += 100
	var before: int = e._last_played.get("hit_metal")
	assert_true(e._start("hit_metal", Vector2(960 * 6, 0), {}) == null, "far off screen: culled")
	assert_eq(e._last_played.get("hit_metal"), before)
	# UI sounds stay flat even when given a place.
	v = e._start("click", Vector2(768, 0), {})
	assert_false(v.positional)
	assert_eq(v.player.bus, &"UI")
	# No view listening: flat.
	e.clear_listener(view)
	e.clock_ms += 100
	v = e._start("hit_metal", Vector2(768, 0), {})
	assert_false(v.positional)


func test_placement_math() -> void:
	var view := Vector2(1920, 1080)
	var c: Dictionary = Placement.place(view / 2, view, 1.0)
	assert_eq([c.pan, c.db], [0.0, 0.0], "centre")
	assert_almost(Placement.place(Vector2(1920, 540), view, 1.0).pan, Placement.EDGE_PAN)
	assert_almost(Placement.place(Vector2(1920 + 960 * 3, 540), view, 1.0).pan, 1.0, 1e-9, "beyond the edge: as far as it goes")
	assert_almost(Placement.place(Vector2(960, 1080 + 540), view, 1.0).db, -12.0, 1e-9, "below the screen")
	assert_almost(Placement.zoom_db(0.5), -4.0, 1e-9)
	assert_almost(Placement.zoom_db(0.25), -8.0, 1e-9)
	assert_eq(Placement.zoom_db(1.6), 0.0, "zoomed in is not louder")
	assert_almost(Placement.voice_db(0.0), 6.0206, 1e-4)
	assert_almost(Placement.voice_db(1.0), 6.0206 - 0.9691, 1e-3)
	assert_false(Placement.audible(-40.0))


func test_pause_holds_world_sounds_not_the_ui() -> void:
	var e := _engine()
	var world = e._start("hit_metal", null, {})
	var ui = e._start("click", null, {})
	e.set_paused(true)
	assert_true(world.held >= 0, "a world sound waits for the game")
	assert_eq(ui.held, -1, "the UI plays on")
	e.clock_ms += 60000
	assert_eq(e.playing("hit_metal"), 1, "still held a minute later")
	e.set_paused(false)
	assert_eq(world.held, -1)
	assert_true(world.ends > e.clock_ms, "it finishes after the pause")
	assert_eq(e.ambience().beds.duck_db, 0.0)


func test_mute() -> void:
	var e := _engine()
	e.play("hit_metal")
	e.set_muted(true)
	var master := AudioServer.get_bus_index("Master")
	assert_true(AudioServer.is_bus_mute(master), "the Master bus is muted")
	assert_eq(e.playing(), 0, "what was playing stops")
	e.clock_ms += 100
	e.play("hit_metal")
	e.play_at("swing", Vector2.ZERO)
	assert_eq(e.playing(), 0, "nothing new starts")
	assert_true(e.ambience().muted, "no ambience calls while muted")
	e.set_muted(false)
	assert_eq(AudioServer.is_bus_mute(master), e.volume("master") <= 0.0)
	e.clock_ms += 100
	e.play("hit_metal")
	assert_eq(e.playing(), 1)


# ---------------------------------------------------------------- volumes

func test_volume_prefs_round_trip() -> void:
	assert_not_null(sfx)
	sfx.set_volume("music", 0.5)
	sfx.set_volume("ambience", 0.0)
	sfx.set_volume("voice", 0.75, false) # a slider: applied now, saved a moment later
	var p := Prefs.prefs()
	assert_almost(float(p.volMusic), 0.5, 1e-9, "saved")
	assert_almost(float(p.volAmbience), 0.0, 1e-9)
	var music := AudioServer.get_bus_index("Music")
	assert_almost(AudioServer.get_bus_volume_db(music), -12.0412, 1e-3, "half way is -12 dB")
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("Ambience")), "0 silences the bus")
	assert_almost(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Voice")), SfxScript.volume_db(0.75), 1e-4)
	assert_true(sfx._save_at >= 0, "the slider's value is saved shortly")
	sfx._save_volumes()
	assert_almost(float(Prefs.prefs().volVoice), 0.75, 1e-9)
	# A new start reads them back and sets the buses.
	sfx.set_volume("music", 0.25)
	var e := _engine()
	assert_almost(e.volume("music"), 0.25, 1e-9)
	assert_almost(e.volume("ambience"), 0.0, 1e-9)
	assert_almost(AudioServer.get_bus_volume_db(music), SfxScript.volume_db(0.25), 1e-4)
	assert_eq(SfxScript.volume_db(1.0), 0.0)
	assert_eq(SfxScript.volume_db(0.0), -80.0)
	# The App wrappers the pause menu's sliders use.
	App.set_volume("sfx", 0.4)
	assert_almost(App.volume("sfx"), 0.4, 1e-9)
	for k in ["music", "ambience", "voice", "sfx"]:
		sfx.set_volume(k, float(_prefs_before.get(SfxScript.VOLUMES[k][0], 1.0)))


# ---------------------------------------------------------------- ambience and music

func _amb_bank() -> Dictionary:
	return {"ambience": {"fade": 2.0, "pause_db": -8.0, "presets": {
		"day": {
			"beds": [{"id": "wind", "takes": [LONG], "volume_db": -10.0}],
			"loops": [{"id": "fire", "takes": [LONG2], "volume_db": -6.0}],
			"oneshots": [{"id": "bird", "takes": [SHORT, LONG], "every": [1.0, 2.0], "pan": [-1.0, 1.0], "volume_db": [-20.0, -10.0], "pitch_jitter": 1.0}],
		},
		"night": {"beds": [{"id": "wind", "takes": [LONG2], "volume_db": -12.0}, {"id": "crickets", "takes": [SHORT]}]},
		"same_wind": {"beds": [{"id": "wind", "takes": [LONG], "volume_db": -4.0}]},
		"unrecorded": {
			"beds": [{"id": "x", "takes": [MISSING]}],
			"loops": [{"id": "fire", "takes": [MISSING]}],
			"oneshots": [{"id": "y", "takes": [MISSING], "every": [0.1, 0.2]}],
		},
	}}, "music": {"fade": 3.0, "pause_db": -4.0, "tracks": {"camp": {"takes": [LONG], "volume_db": -6.0}, "battle": {"takes": [LONG2]}, "silent": {"takes": [MISSING]}}}}


func test_ambience_crossfades_between_scenes() -> void:
	var e := _engine(_amb_bank())
	var amb = e.ambience()
	e.set_ambience("day")
	assert_eq(e.ambience_id(), "day")
	assert_eq(amb.bed_keys().size(), 1)
	var wind = amb.beds.loops[0]
	assert_eq(wind.level, 0.0, "fades in from silence")
	assert_eq(String(wind.player.bus), "Ambience")
	assert_true(wind.player.stream is AudioStreamWAV and wind.player.stream.loop_mode != AudioStreamWAV.LOOP_DISABLED, "the bed loops")
	var shared := load(LONG) as AudioStreamWAV
	assert_eq(shared.loop_mode, AudioStreamWAV.LOOP_DISABLED, "the take's one-shot copy does not")
	e.advance(1.0)
	assert_almost(wind.level, 0.5, 1e-6, "half way after 1 s of a 2 s fade")
	e.advance(1.5)
	assert_eq(wind.level, 1.0)
	assert_almost(wind.player.volume_db, -10.0, 1e-4)
	# The scene changes: the night's beds come in while the day's go out.
	e.set_ambience("night")
	assert_eq(amb.bed_keys().size(), 2, "night's two beds")
	assert_eq(amb.beds.loops.size(), 3, "and the day's wind fading out")
	e.advance(1.0)
	var lv := {}
	for l in amb.beds.loops:
		lv[l.key] = l.level
	assert_almost(lv["wind|" + LONG], 0.5, 1e-6)
	assert_almost(lv["wind|" + LONG2], 0.5, 1e-6)
	e.advance(1.5)
	assert_eq(amb.beds.loops.size(), 2, "the day's bed is gone")
	# Equal power: half way through a crossfade each bed is at -3 dB.
	var deck := LoopDeck.new()
	_made.append(deck)
	var l = deck.start("a", load(SHORT), "Ambience", 0.0, 2.0)
	deck.advance(1.0)
	assert_almost(l.player.volume_db, -3.0103, 1e-3)
	# A bed both presets share keeps playing.
	e.set_ambience("day")
	e.advance(3.0)
	var day_wind = amb.beds.loops[0]
	e.set_ambience("same_wind")
	assert_eq(amb.beds.loops.size(), 1)
	assert_eq(amb.beds.loops[0], day_wind, "the same wind, not restarted")
	assert_eq(day_wind.base_db, -4.0, "at the new level")
	# A view that leaves releases its preset; another view's preset is left alone.
	e.release_ambience("day")
	assert_eq(e.ambience_id(), "same_wind")
	e.release_ambience("same_wind")
	assert_eq(e.ambience_id(), "")
	e.advance(2.5)
	assert_eq(amb.beds.loops.size(), 0, "silence")


## Entries of a preset part with at least one take that exists.
func _playable(e: Node, entries: Array) -> int:
	var n := 0
	for s in entries:
		for t in s.get("takes", []):
			if e.bank.exists(t if t is String else str(t.get("file", ""))):
				n += 1
				break
	return n


func test_ambience_plays_the_files_it_has() -> void:
	# The shipped presets: whatever exists plays (the gitignored Sonniss takes may not).
	var e := _engine()
	for id in ["camp", "camp_night", "battle_day", "battle_night"]:
		var pr: Dictionary = e.bank.ambience_preset(id)
		assert_false(pr.is_empty(), "%s preset in bank.json" % id)
		e.set_ambience(id)
		e.set_anchor("campfire", Vector2(100, 50))
		e.advance(30.0)
		assert_eq(e.ambience_id(), id)
		var continuous: Array = pr.get("beds", []).filter(func(s): return not s.has("cycle"))
		assert_between(e.ambience().beds.loops.size(), _playable(e, continuous), _playable(e, pr.get("beds", [])), "%s: continuous beds plus any active swell" % id)
		assert_eq(e.ambience().loops.loops.size(), _playable(e, pr.get("loops", [])), "%s: loops" % id)
		if _playable(e, pr.get("oneshots", [])) > 0:
			assert_true(e.ambience().shots_played > 0, "%s: one-shots" % id)
	# A preset whose files nobody has added is silent.
	var t := _engine(_amb_bank())
	t.set_ambience("unrecorded")
	t.set_anchor("fire", Vector2.ZERO)
	t.advance(5.0)
	assert_eq([t.ambience().beds.loops.size(), t.ambience().loops.loops.size(), t.ambience().shots_played], [0, 0, 0])


func test_ambience_one_shots_and_pause() -> void:
	var e := _engine(_amb_bank())
	var amb = e.ambience()
	e.set_ambience("day")
	for i in 100:
		e.advance(0.1)
	# Every 1–2 s over 10 s, voices allowing: never on a fixed beat.
	assert_between(amb.shots_played, 4, 11, "calls in 10 s")
	var pans := {}
	for p in amb._shot_players:
		if p.stream != null:
			pans[snappedf(p.position.x, 1.0)] = true
			assert_eq(String(p.bus), "Ambience")
	assert_true(pans.size() >= 2, "from different places")
	# Paused: the beds dip, no calls.
	e.set_paused(true)
	var n: int = amb.shots_played
	for i in 50:
		e.advance(0.1)
	assert_eq(amb.shots_played, n, "silent while paused")
	assert_almost(amb.beds.loops[0].player.volume_db, -10.0 - 8.0, 1e-3, "the bed dips by pause_db")
	e.set_paused(false)
	for i in 20:
		e.advance(0.1)
	assert_almost(amb.beds.loops[0].player.volume_db, -10.0, 1e-3)
	# Muted: no calls either.
	e.set_muted(true)
	n = amb.shots_played
	for i in 50:
		e.advance(0.1)
	assert_eq(amb.shots_played, n, "silent while muted")
	e.set_muted(false)


func _advance_audio(e: Node, seconds: float) -> void:
	for i in int(round(seconds * 10.0)):
		e.advance(0.1)


func test_ambience_calls_ebb_away_as_the_next_scene_comes_in() -> void:
	var data := _amb_bank()
	var day: Dictionary = data.ambience.presets.day
	day.oneshots[0].merge({"takes": [SHORT], "pan": [0.0, 0.0], "volume_db": [-10.0, -10.0], "pitch_jitter": 0.0}, true)
	data.ambience.presets.night["loops"] = [{"id": "fire", "takes": [LONG2], "volume_db": -3.0}]
	data.ambience.presets.night["oneshots"] = [{"id": "owl", "takes": [SHORT], "every": [3.0, 5.0]}]
	var e := _engine(data)
	var amb = e.ambience()
	e.set_anchor("fire", Vector2.ZERO)
	e.set_ambience("day")
	_advance_audio(e, 5.0)
	var bird: Dictionary = amb._schedule[0]
	var fire = amb.loops.live("fire")
	assert_eq(bird.level, 1.0, "the day's calls at full level")
	amb._shot_ends.fill(0.0)
	amb._shot(bird)
	var full: float = amb._shot_players[0].volume_db
	# Night falls over 4 s: the birds keep calling, ever quieter, as the owl rises.
	e.set_ambience("night", 4.0)
	assert_eq(amb._schedule.size(), 2, "the day's calls and the night's")
	var owl: Dictionary = amb._schedule[1]
	assert_eq([owl.key, owl.level], ["shot:night:owl", 0.0], "the owl rises from silence")
	_advance_audio(e, 2.0)
	assert_almost(bird.level, 0.5, 1e-6)
	assert_almost(owl.level, 0.5, 1e-6)
	amb._shot_ends.fill(0.0)
	amb._shot(bird)
	assert_almost(amb._shot_players[0].volume_db, full - 3.0103, 1e-3, "half way: a call 3 dB down, not skipped")
	_advance_audio(e, 2.1)
	assert_eq(amb._schedule, [owl], "the birds are gone once the fade ends")
	# The fire both share burns on; the night only sets its level.
	assert_eq(amb.loops.loops.size(), 1)
	assert_eq(amb.loops.loops[0], fire, "the same fire, not restarted")
	assert_eq([fire.level, fire.base_db], [1.0, -3.0])
	# Back to day and to night again before the owl has faded: the same calls
	# rise, and the night's wind turns back from where it was.
	var night_wind = amb.beds.live("wind|" + LONG2)
	e.set_ambience("day", 4.0)
	_advance_audio(e, 1.0)
	e.set_ambience("night", 4.0)
	var owls: Array = amb._schedule.filter(func(s): return s.key == "shot:night:owl")
	assert_eq(owls, [owl], "one owl, picked up where it was")
	assert_almost(owl.level, 0.75, 1e-6)
	assert_eq(owl.target, 1.0)
	assert_true(amb.beds.live("wind|" + LONG2) == night_wind, "the same night wind, not restarted")
	assert_eq(amb.beds.loops.filter(func(l): return l.key == "wind|" + LONG2).size(), 1)
	assert_almost(night_wind.level, 0.75, 1e-6)
	assert_eq(night_wind.base_db, -12.0)
	# Gone to silence: every call fades.
	e.set_ambience("", 2.0)
	_advance_audio(e, 2.1)
	assert_eq(amb._schedule, [], "silence")
	assert_eq(amb.loops.loops.size(), 0)


func test_intermittent_bed_fades_to_real_silence_and_returns() -> void:
	var data := _amb_bank()
	data.ambience.presets.day.beds.append({"id": "murmur", "takes": [LONG2],
		"volume_db": -6.0, "cycle": {"hold": [3, 3], "quiet": [4, 4], "fade": 2.0}})
	var e := _engine(data)
	var amb = e.ambience()
	e.set_ambience("day")
	_advance_audio(e, 3.8)
	assert_eq(amb.beds.loops.size(), 1, "only wind during the initial quiet gap")
	_advance_audio(e, 0.3)
	var murmur = amb.beds.live("murmur|" + LONG2)
	if not assert_not_null(murmur):
		return
	assert_true(murmur.level > 0.0 and murmur.level < 0.2, "murmur eases in")
	_advance_audio(e, 2.0)
	assert_almost(murmur.player.volume_db, -6.0, 1e-4, "quieter peak level")
	_advance_audio(e, 4.0)
	assert_true(murmur.target == 0.0 and murmur.level > 0.0 and murmur.level < 1.0, "slow fade out")
	_advance_audio(e, 1.3)
	assert_eq(amb.beds.loops.size(), 1, "murmur player is gone, not a quiet continuous loop")
	_advance_audio(e, 3.2)
	assert_eq(amb.beds.loops.size(), 1, "silence lasts between swells")
	_advance_audio(e, 1.0)
	assert_eq(amb.beds.loops.size(), 2, "next swell returns")
	assert_eq(amb.beds.loops[0].key, "wind|" + LONG, "background kept playing")
	e.set_ambience("night")
	_advance_audio(e, 15.0)
	assert_eq(amb.beds.loops.size(), 2, "leaving camp cancels future swells")
	assert_true(amb.beds.live("murmur|" + LONG2) == null)


func test_intermittent_bed_waits_while_paused_or_muted() -> void:
	var data := _amb_bank()
	data.ambience.presets.day.beds = [{"id": "murmur", "takes": [LONG],
		"volume_db": -6.0, "cycle": {"hold": [3, 3], "quiet": [4, 4], "fade": 2.0}}]
	var e := _engine(data)
	var amb = e.ambience()
	e.set_ambience("day")
	e.set_paused(true)
	_advance_audio(e, 20.0)
	assert_eq(amb.beds.loops.size(), 0, "no swell starts while paused")
	e.set_paused(false)
	e.set_muted(true)
	_advance_audio(e, 20.0)
	assert_eq(amb.beds.loops.size(), 0, "no swell starts while muted")
	e.set_muted(false)
	_advance_audio(e, 6.2)
	assert_eq(amb.beds.loops.size(), 1, "schedule resumes")
	e.set_paused(true)
	_advance_audio(e, 10.0)
	assert_almost(amb.beds.loops[0].player.volume_db, -14.0, 1e-3, "active swell ducks with the other beds")
	e.set_paused(false)
	_advance_audio(e, 6.0)
	assert_eq(amb.beds.loops.size(), 0, "resumed swell finishes")
	e.release_ambience("day")
	_advance_audio(e, 20.0)
	assert_eq(amb.beds.loops.size(), 0, "released scene cannot restart its murmur")


func test_camp_uses_selected_forest_and_spaces_chaffinch_calls() -> void:
	var e := _engine()
	var camp: Dictionary = e.bank.ambience_preset("camp").duplicate(true)
	assert_eq(camp.beds[0].takes, ["res://assets/audio/bank/local/ambience/camp_forest_01.ogg"], "Baltic pine only")
	var bird: Dictionary = camp.oneshots.filter(func(s): return s.id == "songbird")[0]
	# Use the shipped schedule with a tiny portable fixture: no library required.
	bird.takes = [SHORT]
	e.bank.load_dicts({"ambience": {"presets": {"calls": {"oneshots": [bird]}}}}, _synth_meta())
	e.set_ambience("calls")
	var last_call := 0.0
	var calls := 0
	for i in 2000:
		e.advance(0.1)
		if e.ambience().shots_played > calls:
			var now := (i + 1) * 0.1
			assert_between(now - last_call, 10.0, 25.1, "first and subsequent chaffinch calls")
			last_call = now
			calls = e.ambience().shots_played
	assert_true(calls >= 7, "calls keep returning over several minutes")


func test_positional_loop_follows_the_camera() -> void:
	var e := _engine(_amb_bank())
	var view := _listener(e)
	e.set_ambience("day")
	assert_eq(e.ambience().loop_keys(), [], "no fire until a view sets it")
	e.set_anchor("fire", Vector2(480, 0))
	assert_eq(e.ambience().loop_keys(), ["fire"])
	e.advance(3.0)
	var fire = e.ambience().loops.loops[0]
	assert_true(fire.player is AudioStreamPlayer2D)
	assert_almost(fire.player.position.x, 0.375 * 1920.0, 1e-3, "right of centre")
	assert_almost(fire.player.volume_db, -6.0 + Placement.voice_db(0.375), 1e-3)
	# The camera pans past it: it moves to the left and falls off screen.
	view.cam.x = 480.0 + 1920.0
	e.advance(0.1)
	assert_true(fire.player.position.x < 0.0, "now on the left")
	assert_almost(fire.player.volume_db, -6.0 - 12.0 + Placement.voice_db(-1.0), 1e-3, "half a screen off")
	e.clear_anchor("fire")
	e.advance(2.5)
	assert_eq(e.ambience().loops.loops.size(), 0, "faded out with its view")


func test_music_crossfades_and_no_tracks_is_silent() -> void:
	var shipped := _engine()
	shipped.set_music("camp")
	assert_eq(shipped.music_id(), "camp")
	assert_eq(shipped.music_deck().loops.size(), 0, "no tracks yet: nothing plays")
	var e := _engine(_amb_bank())
	e.set_music("camp")
	var deck = e.music_deck()
	assert_eq(deck.loops.size(), 1)
	assert_eq(String(deck.loops[0].player.bus), "Music")
	e.advance(3.0)
	assert_almost(deck.loops[0].player.volume_db, -6.0, 1e-4)
	e.set_music("camp")
	assert_eq(deck.loops.size(), 1, "the same track keeps playing")
	e.set_music("battle")
	assert_eq(deck.loops.size(), 2, "crossfading")
	e.advance(3.0)
	assert_eq(deck.live_keys(), ["battle"])
	assert_eq(deck.loops.size(), 1)
	e.set_paused(true)
	e.advance(1.0)
	assert_almost(deck.loops[0].player.volume_db, -4.0, 1e-3, "dips behind the pause menu")
	e.set_paused(false)
	e.set_music("silent")
	e.advance(3.0)
	assert_eq(deck.loops.size(), 0, "a track without files fades the last one out")


func test_views_hook_the_camp() -> void:
	assert_not_null(sfx)
	var was: String = sfx.ambience_id()
	var bv: Node2D = load("res://scripts/render/base_view.gd").new()
	_made.append(bv)
	bv._enter_tree()
	assert_eq(sfx.ambience_id(), "camp", "the camp's ambience")
	assert_eq(sfx.listener(), bv, "its camera places sounds")
	assert_true(sfx.ambience()._anchors.has("campfire"), "the fire is placed")
	bv._exit_tree()
	assert_eq(sfx.ambience_id(), "", "gone with the view")
	assert_true(sfx.listener() == null, "no listener")
	assert_false(sfx.ambience()._anchors.has("campfire"))
	sfx.set_ambience(was, 0.0)


func test_the_camp_hands_day_and_night_over_slowly() -> void:
	assert_not_null(sfx)
	var was: String = sfx.ambience_id()
	var view: Node2D = WoodlandCamp.new()
	_made.append(view)
	view._enter_tree()
	assert_eq(sfx.ambience_id(), "camp", "day in camp")
	view.set_night(true)
	assert_eq(sfx.ambience_id(), "camp_night", "the night's sounds")
	var amb = sfx.ambience()
	for s in amb._schedule:
		assert_eq(s.target, 1.0 if s.key.begins_with("shot:camp_night:") else 0.0, s.key)
		assert_almost(s.rate, 1.0 / WoodlandCamp.AMBIENCE_FADE, 1e-6, "%s over %s s" % [s.key, WoodlandCamp.AMBIENCE_FADE])
	if _playable(sfx, sfx.bank.ambience_preset("camp_night").get("oneshots", [])) > 0:
		assert_true(amb._schedule.any(func(s): return s.key == "shot:camp_night:owl"), "the owl comes in")
	# The night's wind is the day's, deeper and quieter: one fades into the other.
	var day_wind := "wind|res://assets/audio/bank/local/ambience/camp_forest_01.ogg"
	var night_wind := "wind|res://assets/audio/bank/local/ambience/camp_night_wind_01.ogg"
	var night_beds: Array = sfx.bank.ambience_preset("camp_night").beds
	assert_eq(night_beds[0].takes, [night_wind.get_slice("|", 1)])
	assert_eq(night_beds[0].volume_db, -15.7, "half the day's wind as heard (its take is 0.8 dB quieter)")
	if sfx.bank.exists(night_wind.get_slice("|", 1)):
		assert_true(amb.bed_keys().has(night_wind), "the night wind comes in")
		assert_false(amb.bed_keys().has(day_wind), "the day's fades")
	var fading: Array = amb.beds.loops.filter(func(l): return l.key == day_wind)
	view.set_night(false)
	assert_eq(sfx.ambience_id(), "camp", "back to day")
	if not fading.is_empty():
		assert_true(amb.beds.live(day_wind) == fading[0], "the day's wind turns back, not restarted")
	# Another screen's ambience is left alone; the camp takes over again when it is back.
	sfx.set_ambience("battle_day", 0.0)
	view.set_night(true)
	assert_eq(sfx.ambience_id(), "battle_day", "not the camp's to change")
	view._enter_tree()
	assert_eq(sfx.ambience_id(), "camp_night", "night when it is night")
	view._exit_tree()
	assert_eq(sfx.ambience_id(), "", "the night is released with the view")
	sfx.set_ambience(was, 0.0)


# ---------------------------------------------------------------- footsteps

func test_footfalls_follow_the_stride() -> void:
	var uv = BattleView.UnitView.new()
	uv.walking = 1.0
	var m = SquadView.Member.new()
	m.id = 2
	m.phase = 1.234
	m.type = "footman"
	var dt := 1.0 / 60.0
	var feet := 0
	for i in 120:
		uv.walk_t += dt
		feet += SoldierAnim.footfalls(uv, m, dt)
	# Exactly the stride's contacts over the 2 s: two a cycle of his gait phase.
	var want := floori(SoldierAnim.gait_phase(uv, m, uv.walk_t) * 2.0 - 0.25) - floori(SoldierAnim.gait_phase(uv, m, 0.0) * 2.0 - 0.25)
	assert_eq(feet, want, "every contact once")
	assert_between(feet, 7, 11, "about 4.5 steps a second")
	# A big frame still counts each foot.
	uv.walk_t += 0.5
	assert_true(SoldierAnim.footfalls(uv, m, 0.5) >= 2)
	# Standing, striking or not yet marching: no feet.
	uv.walking = 0.1
	uv.walk_t += 0.3
	assert_eq(SoldierAnim.footfalls(uv, m, 0.3), 0)
	uv.walking = 1.0
	m.pose = "atk"
	uv.walk_t += 0.3
	assert_eq(SoldierAnim.footfalls(uv, m, 0.3), 0)


func test_a_marching_squad_is_one_tread() -> void:
	var f: Dictionary = JS.normalize(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/battle_view/setups/trolls.json")))
	var v = ViewScene.instantiate()
	v.threaded_rules = false
	v.setup(Battle.new(f.setup))
	(Engine.get_main_loop() as SceneTree).root.add_child(v)
	_made.append(v)
	var uv = null
	var troll = null
	for u in v.b.units:
		if u.typeId == "footman" and uv == null:
			uv = v.views[u.uid]
		if u.typeId == "troll":
			troll = v.views[u.uid]
	if not assert_not_null(uv, "a footman squad"):
		return
	assert_eq(v._step_event(uv.uid), "step_medium", "footmen: medium feet")
	assert_eq(v._step_event(troll.uid), "step_troll", "a troll's own (falls back to step_large, then step)")
	sfx.clock_ms = 100000
	var muted: bool = sfx.is_muted()
	sfx._muted = false
	var before: int = sfx.counts.get("step_medium", 0)
	uv.marching = true
	var men := 0
	for m in uv.members:
		if m.alive:
			men += 1
	var dt := 1.0 / 30.0
	for i in 60:
		sfx.clock_ms += 33
		v.advance(dt)
	uv.marching = false
	for i in 30:
		sfx.clock_ms += 33
		v.advance(dt)
	sfx._muted = muted
	var heard: int = sfx.counts.get("step_medium", 0) - before
	print("      a squad of %d footmen marching 2 s: %d treads heard" % [men, heard])
	# Six men set down some 50 feet in 2 s; the squad is heard as one tread.
	assert_between(heard, 4, ceili(2.4 / BattleView.STEP_BEAT) + 1, "treads heard (%d men)" % men)


# ---------------------------------------------------------------- orders

## The squads answer the player's orders (battle_view._say): one answer at a
## time, the ability's own line first, none when the selection moves on by
## itself or for a squad that has acted, and the hounds obey without a word.
func test_the_squads_answer_orders() -> void:
	# Without the local voices (a clone) the answers play a stand-in take: this
	# checks when a squad answers, not what it says.
	var lines := ["order_select", "order_move", "order_attack", "order_shield_charge", "order_aimed_shot"]
	var kept := {}
	for n in lines:
		if sfx.bank.resolve(n).source != "bank":
			kept[n] = sfx.bank.events[n].takes
			sfx.bank.events[n].takes = [{"file": SHORT, "volume_db": 0.0}]
	sfx.bank._resolved.clear()
	_answers_to_orders()
	for n in kept:
		sfx.bank.events[n].takes = kept[n]
	sfx.bank._resolved.clear()


func _answers_to_orders() -> void:
	var f: Dictionary = JS.normalize(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/battle_view/setups/trolls.json")))
	var foot: Array = f.setup.units.filter(func(u): return u.typeId == "footman")
	foot[1].typeId = "collie_guard"
	var v = ViewScene.instantiate()
	v.threaded_rules = false
	v.setup(Battle.new(f.setup))
	(Engine.get_main_loop() as SceneTree).root.add_child(v)
	_made.append(v)
	var of := {}
	for u in v.b.units:
		if u.faction == "player" and not of.has(u.typeId):
			of[u.typeId] = u.uid
	for t in ["footman", "spearman", "crossbowman", "collie_guard"]:
		if not assert_true(of.has(t), "a %s squad" % t):
			return
	sfx.clock_ms = 300000
	var muted: bool = sfx.is_muted()
	sfx._muted = false
	var before := {}
	for n in ["order_select", "order_move", "order_attack", "order_shield_charge", "order_aimed_shot"]:
		before[n] = sfx.counts.get(n, 0)
	var said := func(n: String) -> int: return sfx.counts.get(n, 0) - before[n]
	v.select(null) # the deployment starts on the first squad
	v.select(of.footman)
	assert_eq(said.call("order_select"), 0, "deploying: quiet (only squads that can act answer)")
	v.select(null)
	v.b.phase = "player"
	v.select(of.footman)
	assert_eq(said.call("order_select"), 1, "picked: \"Orders?\"")
	v.select(of.spearman)
	assert_eq(said.call("order_select"), 1, "not over the last answer")
	sfx.clock_ms += 3000
	v.select(of.spearman)
	assert_eq(said.call("order_select"), 1, "the same squad again: quiet")
	v.select(of.crossbowman, false)
	assert_eq(said.call("order_select"), 1, "the selection moving on by itself: quiet")
	v.select(of.collie_guard)
	assert_eq(said.call("order_select"), 1, "the hounds: quiet")
	v._u(of.footman).done = true
	v.select(of.footman)
	assert_eq(said.call("order_select"), 1, "a squad that has acted: quiet")
	v._u(of.footman).done = false
	v.select(of.spearman)
	assert_eq(said.call("order_select"), 2, "another squad: \"Ready.\"")
	sfx.clock_ms += 3000
	v._say("attack", of.footman, ["order_shield_charge"])
	assert_eq(said.call("order_shield_charge"), 1, "Charge: \"Forward, shields!\"")
	sfx.clock_ms += 3000
	v._say("attack", of.crossbowman, ["order_aimed_shot"])
	assert_eq(said.call("order_aimed_shot"), 1, "Aimed Shot: \"Loose!\"")
	sfx.clock_ms += 3000
	v._say("attack", of.spearman, ["order_brace"])
	assert_eq(said.call("order_attack"), 1, "an attack without a line of its own: \"At them!\"")
	sfx.clock_ms += 3000
	v._say("move", of.spearman)
	assert_eq(said.call("order_move"), 1, "\"Moving!\"")
	sfx.clock_ms += 3000
	v._say("attack", of.collie_guard, ["order_hound_charge"])
	v._say("move", of.collie_guard)
	assert_eq(said.call("order_attack") + said.call("order_move"), 2, "the hounds run and bite without a word")
	sfx._muted = muted
