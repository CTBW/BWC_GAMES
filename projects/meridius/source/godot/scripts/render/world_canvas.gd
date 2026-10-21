## A Node2D that draws through a callback: `draw_fn.call(self)` from _draw.
## The views use several of these to split one drawing pass where the
## original switched composite modes mid-frame (each needs its own material).
extends Node2D

## Set to a Dictionary to accumulate draw time (usec) per node name (profiling).
static var profile: Variant = null

var draw_fn: Callable


func _init(fn: Callable = Callable(), node_name: String = "") -> void:
	draw_fn = fn
	if node_name != "":
		name = node_name


func _draw() -> void:
	if not draw_fn.is_valid():
		return
	if profile == null:
		draw_fn.call(self)
		return
	var t0 := Time.get_ticks_usec()
	draw_fn.call(self)
	profile[name] = profile.get(name, 0) + Time.get_ticks_usec() - t0
