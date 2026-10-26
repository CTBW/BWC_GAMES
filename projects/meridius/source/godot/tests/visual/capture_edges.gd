## Native border review using the production battle view.
## tools/godot.sh --path . --resolution 1920x1080 --audio-driver Dummy
##   -s res://tests/visual/capture_edges.gd -- edges
## Fixed fixture seeds; no save files or physical input.
extends "res://tests/visual/battle_shots.gd"


func _sc_edges() -> void:
	for name in ["scouts_clearing", "river", "camp", "last_stand"]:
		await _start(_fixture(name).setup)
		await _step(1.5)
		await _shot("edges_" + name)
	# The normal wave/relief playback is also exercised by test_battle_view.
