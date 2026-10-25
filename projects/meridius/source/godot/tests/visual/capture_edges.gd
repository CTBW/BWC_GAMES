## Native border review using the production battle and campaign views.
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
	view.queue_free()
	await process_frame
	view = null
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/render/campaign_start.json"))
	var ex: Dictionary = fixture.game.expedition.duplicate(true)
	var campaign: Node2D = load("res://scenes/campaign/campaign_view.tscn").instantiate()
	campaign.setup(ex, func(): return ex)
	vp.add_child(campaign)
	await _campaign_shot(campaign, "company")
	# Inspect the former horde corner with identical coordinates from the old
	# fixture, with fog intact, then after a later march.
	var h: Dictionary = fixture.horde
	for marches in [0, 5]:
		ex.marches = marches
		var gx: float = h.ox + h.ux * h.len * -0.20
		var gy: float = h.oy + h.uy * h.len * -0.20
		campaign.cam.x = Iso.iso_x(gx, gy)
		campaign.cam.tx = campaign.cam.x
		campaign.cam.y = Iso.iso_y(gx, gy)
		campaign.cam.ty = campaign.cam.y
		campaign.cam.zoom = 0.6
		campaign.cam.tzoom = 0.6
		# Avoid camera clamp moving the deliberately targeted corner capture.
		campaign.set_process(false)
		campaign._refresh_view()
		await _campaign_shot(campaign, "corner_%d" % marches)
	campaign.queue_free()
	await process_frame


func _campaign_shot(campaign: Node2D, label: String) -> void:
	for i in 8:
		await process_frame
		RenderingServer.force_draw(false)
	var img := vp.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + "campaign_edges_%s.png" % label))
	print("campaign ", label)
