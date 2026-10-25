## The forest ring's near side in the battle (scripts/render/battle_draw.gd
## draw_outer, _ring_fades): its trees stand in front of the field's edge rows
## and fade over the squads behind them. Real frames are drawn before each
## shot, so the props' fades have settled (they ease in over about 0.3 s).
##   tools/godot.sh --path . --resolution 1920x1080 --audio-driver Dummy
##     -s res://tests/visual/capture_forest_edge.gd -- forest_edge
## Output: tests/visual/out/battle_forest_edge_<fixture>.png
extends "res://tests/visual/battle_shots.gd"


func _sc_forest_edge() -> void:
	for name in ["scouts_clearing", "river", "camp", "last_stand"]:
		await _start(_fixture(name).setup)
		await _step(1.5)
		for i in 40:
			view.step_frame(DT)
			await process_frame
			RenderingServer.force_draw(false)
		await _shot("forest_edge_" + name)
