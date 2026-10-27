## Native audio-only review. Run with --headless --audio-driver Dummy
## -s res://tools/audio/review_camp.gd -- <ignored-output>/camp-mix.wav <trace.json>.
## Records two minutes of the Ambience bus without speaker output or save edits.
extends SceneTree

var elapsed := 0.0
var engine: Node
var levels: Array = []
var _last_second := -1
var recording := AudioEffectRecord.new()
var ambience_bus := -1
var record_slot := -1


func _initialize() -> void:
	root.size = Vector2i(64, 64)
	call_deferred("_start")


func _start() -> void:
	engine = root.get_node("Sfx")
	engine.set_process(false)
	# Review process only: never save or change the owner's volume preferences.
	for bus in ["Master", "Ambience"]:
		var index := AudioServer.get_bus_index(bus)
		AudioServer.set_bus_volume_db(index, 0.0)
		AudioServer.set_bus_mute(index, false)
	engine._muted = false
	engine.ambience().set_muted(false)
	engine.ambience().rng.seed = 11
	ambience_bus = AudioServer.get_bus_index("Ambience")
	record_slot = AudioServer.get_bus_effect_count(ambience_bus)
	AudioServer.add_bus_effect(ambience_bus, recording)
	recording.set_recording_active(true)
	engine.set_ambience("camp")


func _process(delta: float) -> bool:
	if engine == null:
		return false
	elapsed += delta
	engine.advance(delta)
	if int(elapsed) != _last_second:
		_last_second = int(elapsed)
		var murmur_db: Variant = null
		for bed in engine.ambience().beds.loops:
			if str(bed.key).begins_with("murmur|"):
				murmur_db = bed.player.volume_db
		levels.append({"second": _last_second, "murmur_db": murmur_db,
			"ambient_calls": engine.ambience().shots_played})
	if elapsed >= 120.0:
		var args := OS.get_cmdline_user_args()
		recording.set_recording_active(false)
		if args.size() >= 2:
			var wav := recording.get_recording()
			wav.save_to_wav(args[0])
			var out := FileAccess.open(args[1], FileAccess.WRITE)
			out.store_string(JSON.stringify({"duration_s": elapsed, "captured_audio_s": wav.get_length(), "levels": levels}, "  "))
		AudioServer.remove_bus_effect(ambience_bus, record_slot)
		engine.set_ambience("", 0.0)
		engine.advance(0.1)
		quit()
	return false
