## Capture the user's current Unit Playground as a production baseline.
## Does not replace its sprites or inject the Mixamo study into battle playback.
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1920,1080)
	root.content_scale_size = Vector2i(1920,1080)
	var screen = load("res://scripts/ui/screens/unit_playground.gd").new()
	root.add_child(screen)
	await process_frame
	screen.set_process(false)
	var lab = screen.view
	var results := {}
	for solo in [true,false]:
		lab.solo = solo
		lab.looping = false
		lab.facing = 1
		lab.choose_clip("Attack")
		lab.frame_subject(3.0 if solo else 1.6)
		(screen.find_child("Grouping",true,false) as OptionButton).select(1 if solo else 0)
		screen._refresh_info()
		var name := "sandbox_single" if solo else "sandbox_squad"
		var out := ProjectSettings.globalize_path("res://tests/visual/out/mixamo-attack/" + name)
		DirAccess.make_dir_recursive_absolute(out)
		var peak_lunge := 0.0
		for frame in 72:
			for tick in 2: lab.tick(1.0/60)
			screen.status.text = "CURRENT SPRITES / Attack / %.2fs" % lab.elapsed
			for member in lab.views[lab.SUBJECT].members:
				peak_lunge = maxf(peak_lunge,member.lunge.length())
			await process_frame
			await process_frame
			RenderingServer.force_draw(false)
			assert(root.get_texture().get_image().save_png(out+"/%04d.png" % frame) == OK)
		results[name] = {"subjects":1 if solo else lab.views[lab.SUBJECT].members.size(),
			"peak_whole_sprite_lunge_px":peak_lunge,"capture_fps":30,"frames":72,
			"route":"scripts/ui/screens/unit_playground.gd", "mixamo_installed":false}
	var delivery := ProjectSettings.globalize_path("res://../../../../workspace/2026-10-20_meridius/motion-study/mixamo/sandbox-checks.json")
	var file := FileAccess.open(delivery,FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"  "))
	print("SANDBOX_BASELINE ", JSON.stringify(results))
	screen.queue_free()
	await process_frame
	quit()
