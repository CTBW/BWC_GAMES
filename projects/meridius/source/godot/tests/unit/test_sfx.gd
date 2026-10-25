## The Sfx autoload (scripts/audio/sfx.gd, port of src/audio/sfx.ts) against
## the original's sound names, dumped by tools/bake to tests/fixtures/assets/sfx_names.json.
## Since the sound bank (scripts/audio/bank.gd) the baked synth takes are the
## fallback layer under the recorded ones: every original name must still
## have its baked takes and sound, and Sfx may know more names (bank events
## such as step_large). The engine itself is tested in test_audio.gd.
extends "res://tests/test_case.gd"

const Prefs = preload("res://scripts/core/prefs.gd")
const FIXTURE := "res://tests/fixtures/assets/sfx_names.json"

var fx: Dictionary
var sfx: Node


func before_all() -> void:
	fx = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	sfx = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Sfx")


func test_autoload_present() -> void:
	assert_not_null(sfx, "Sfx autoload")
	assert_true(sfx.has_method("play") and sfx.has_method("set_muted") and sfx.has_method("is_muted"))
	assert_true(sfx.has_method("play_at") and sfx.has_method("set_ambience") and sfx.has_method("set_music") and sfx.has_method("set_volume"))


func test_every_original_sound_has_baked_takes() -> void:
	assert_eq(fx.names.size(), 42, "sfx.ts names")
	var names := Array(sfx.names())
	var synth: Dictionary = sfx.bank.synth
	assert_eq(synth.size(), fx.names.size(), "baked names: no extra or missing")
	for n in fx.names:
		assert_true(names.has(n), "%s can sound" % n)
		var takes := int(fx.takes[n])
		var files: Array = synth.get(n, [])
		assert_eq(files.size(), takes, "%s baked takes" % n)
		for i in files.size():
			var s: AudioStream = sfx.load_stream(files[i])
			if assert_true(s is AudioStreamWAV, "%s take %d is a WAV stream" % [n, i]):
				assert_true(s.get_length() > 0.03, "%s take %d has sound" % [n, i])
				assert_eq((s as AudioStreamWAV).format, AudioStreamWAV.FORMAT_16_BITS, "%s PCM" % n)
		# What play() picks from: recorded takes once the bank lists them, the baked ones until then.
		var r: Dictionary = sfx.bank.resolve(n)
		assert_true(sfx.variant_count(n) >= 1, "%s resolves to takes" % n)
		if r.source == "synth":
			assert_eq(sfx.variant_count(n), takes, "%s plays its baked takes" % n)
	# Extra names are bank events that resolve (e.g. step_large → step).
	for n in names:
		if not fx.names.has(n):
			assert_true(sfx.bank.events.has(n), "%s is a bank event" % n)
	assert_eq(sfx.variant_count("no_such_sound"), 0)


func test_master_and_gaps_match_original() -> void:
	assert_almost(sfx.master_gain(), float(fx.master), 1e-12)
	assert_eq(fx.minGapMs, {"step": 70})
	assert_eq(int(fx.defaultGapMs), 25)
	# The bank keeps the original's gaps for its names.
	for n in fx.names:
		assert_eq(sfx.bank.options(n).min_gap_ms, int(fx.minGapMs.get(n, fx.defaultGapMs)), "%s gap" % n)


func test_play_every_sound() -> void:
	var was: bool = sfx.is_muted()
	sfx.set_muted(false)
	for n in fx.names:
		sfx.play(n)
	sfx.play("no_such_sound")
	# Every name went through the gap bookkeeping without an error.
	for n in fx.names:
		assert_true(sfx._last_played.has(n), "%s played" % n)
	# tests/run_tests.gd runs before the scene tree is live; voices start only in a running game.
	if sfx.is_inside_tree():
		var playing := 0
		for p in sfx.get_children():
			if p is AudioStreamPlayer and p.playing:
				playing += 1
		assert_true(playing > 0, "voices playing (%d)" % playing)
	sfx.set_muted(was)


func test_min_gap_drops_repeats() -> void:
	var was: bool = sfx.is_muted()
	sfx.set_muted(true) # stops every voice
	sfx.set_muted(false)
	# The original's per-name gaps: 70 ms for steps, 25 ms for everything else.
	for case in [["hit_flesh", 10, false], ["hit_flesh", 30, true], ["step", 60, false], ["step", 80, true]]:
		var at: int = Time.get_ticks_msec() - case[1]
		sfx._last_played[case[0]] = at
		sfx.play(case[0])
		var played: bool = sfx._last_played[case[0]] != at
		assert_eq(played, case[2], "%s %d ms after the last one plays: %s" % case)
	sfx.set_muted(was)


func test_muted_is_persisted() -> void:
	var was: bool = sfx.is_muted()
	sfx.set_muted(true)
	assert_true(sfx.is_muted())
	assert_eq(Prefs.prefs().muted, true, "pref saved")
	sfx.play("click") # silent while muted
	sfx.set_muted(false)
	assert_eq(Prefs.prefs().muted, false)
	sfx.set_muted(was)
