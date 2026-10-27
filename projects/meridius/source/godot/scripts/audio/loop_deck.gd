## Looping players that fade in and out: the ambience beds and positional
## loops (ambience.gd) and the music (sfx.gd). Godot addition.
##
## A loop's level runs 0..1 toward its target at its own rate and is heard on
## an equal-power curve, so two beds crossfading keep the room's loudness. A
## loop faded out to 0 is stopped and its player freed. `duck_db` lowers the
## whole deck smoothly (the pause dip). Fades are stepped by advance(dt) (the
## owner's _process, or a test), so they never depend on Tweens or the tree.
##
##   var deck = LoopDeck.new(); add_child(deck)
##   deck.start("wind", stream, "Ambience", -10.0, 2.5)      # fades in over 2.5 s
##   deck.stop_all(2.5)                                       # fades everything out
##   deck.advance(dt)
extends Node

## Pause dip speed (dB per second).
const DUCK_RATE := 10.0
## The level a silent player is set to.
const SILENT_DB := -80.0


class Loop extends RefCounted:
	var key := ""
	## AudioStreamPlayer, or AudioStreamPlayer2D for a loop with a place in the world.
	var player: Node
	## Fade position 0..1, where it is heading and how fast (per second).
	var level := 0.0
	var target := 1.0
	var rate := 1.0
	## Its own level, and where the world puts it (positional loops).
	var base_db := 0.0
	var place_db := 0.0
	## World point of a positional loop (null: not placed yet, silent).
	var anchor: Variant = null


var loops: Array = []
## The dip the deck is heading to, and where it is.
var duck_db := 0.0
var _duck := 0.0


## Starts `stream` looping on `bus`, fading in over `fade` s (0: at once).
func start(key: String, stream: AudioStream, bus: String, base_db: float, fade: float, positional := false) -> Loop:
	var l := Loop.new()
	l.key = key
	l.base_db = base_db
	l.level = 0.0 if fade > 0.0 else 1.0
	l.target = 1.0
	l.rate = 1.0 / fade if fade > 0.0 else 1e6
	var p: Node
	if positional:
		var p2 := AudioStreamPlayer2D.new()
		p2.attenuation = 0.0
		p2.max_distance = 1e7
		p = p2
	else:
		p = AudioStreamPlayer.new()
	p.name = "Loop_%s_%d" % [key.validate_node_name(), loops.size()]
	p.stream = looped(stream)
	p.bus = bus
	l.player = p
	add_child(p)
	_apply(l)
	if p.is_inside_tree():
		p.play()
	loops.append(l)
	return l


## Fades the loops with `key` out over `fade` s.
func stop(key: String, fade: float) -> void:
	for l: Loop in loops:
		if l.key == key:
			_fade_out(l, fade)


func stop_all(fade: float) -> void:
	for l: Loop in loops:
		_fade_out(l, fade)


func _fade_out(l: Loop, fade: float) -> void:
	l.target = 0.0
	l.rate = 1.0 / fade if fade > 0.0 else 1e6


## A loop with `key` still fading out turns and fades back in over `fade` s,
## from where it is in the file and in its fade; null if there is none.
func revive(key: String, fade: float) -> Loop:
	for l: Loop in loops:
		if l.key == key and l.target <= 0.0:
			l.target = 1.0
			l.rate = 1.0 / fade if fade > 0.0 else 1e6
			return l
	return null


## The first loop with `key` still sounding or fading in, or null.
func live(key: String) -> Loop:
	for l: Loop in loops:
		if l.key == key and l.target > 0.0:
			return l
	return null


## Keys of the loops not fading out.
func live_keys() -> Array:
	var out: Array = []
	for l: Loop in loops:
		if l.target > 0.0:
			out.append(l.key)
	return out


## One step of the fades.
func advance(dt: float) -> void:
	_duck = move_toward(_duck, duck_db, DUCK_RATE * dt)
	for l: Loop in loops.duplicate():
		l.level = move_toward(l.level, l.target, l.rate * dt)
		if l.level <= 0.0 and l.target <= 0.0:
			_drop(l.player)
			loops.erase(l)
			continue
		_apply(l)


func _drop(p: Node) -> void:
	p.stop()
	remove_child(p)
	p.queue_free()


func _apply(l: Loop) -> void:
	var k := sin(clampf(l.level, 0.0, 1.0) * PI * 0.5)
	var db := SILENT_DB if k <= 0.0001 else l.base_db + l.place_db + _duck + linear_to_db(k)
	l.player.volume_db = maxf(SILENT_DB, db)


## Stops and frees everything at once.
func clear() -> void:
	for l: Loop in loops:
		_drop(l.player)
	loops.clear()


## The stream set to loop: as imported when the import loops it already, else
## a looping copy (the cached resource may also be played as a one-shot).
static func looped(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamWAV:
		if (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED:
			return stream
		var w := stream.duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
		return w
	if "loop" in stream and not bool(stream.get("loop")):
		var c := stream.duplicate()
		c.set("loop", true)
		return c
	return stream
