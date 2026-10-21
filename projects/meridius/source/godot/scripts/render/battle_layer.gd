## One drawing pass of the battle view (a layer of BattleScene.render): a
## Node2D whose _draw() calls `draw_fn(self)`. Static layers draw once (the
## renderer keeps their commands; the camera is the parent's transform).
## Set `BattleLayer.profile = {}` to collect the milliseconds each pass takes.
extends Node2D

static var profile = null

var draw_fn: Callable
var static_draw := false


func _draw() -> void:
	if not draw_fn.is_valid():
		return
	if profile == null:
		draw_fn.call(self)
		return
	var t0 := Time.get_ticks_usec()
	draw_fn.call(self)
	profile[name] = profile.get(name, 0.0) + (Time.get_ticks_usec() - t0) / 1000.0
