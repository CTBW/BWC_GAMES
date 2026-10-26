## How long the first battle takes to open in the real game, and the second
## (the first pays for loading and compiling the battle view's scripts and
## shaders unless the boot warmed them). Windowed, 1920×1080:
##   tools/godot.sh --path . -s res://tests/visual/battle_open_time.gd
## Prints the time from App.debug_test_battle to the end of the first drawn
## frames, for two battles in a row.
extends SceneTree

var app: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	app = root.get_node("App")
	app.save_path = "user://battle_open_time_save.json"
	var t_boot := Time.get_ticks_usec()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	while app.screen != "title":
		await process_frame
	print("boot to title: %.0f ms" % ((Time.get_ticks_usec() - t_boot) / 1000.0))
	for i in 10:
		await process_frame
	app.new_game(5)
	for i in 10:
		await process_frame
	for n in 2:
		var t0 := Time.get_ticks_usec()
		app.debug_test_battle({"seed": 3 + n})
		var t1 := Time.get_ticks_usec()
		var fr: Array = []
		var last := t1
		for i in 4:
			await process_frame
			var now := Time.get_ticks_usec()
			fr.append(snappedf((now - last) / 1000.0, 0.1))
			last = now
		print("battle %d: debug_test_battle %.0f ms, first frames %s ms, total %.0f ms" % [n + 1, (t1 - t0) / 1000.0, fr, (last - t0) / 1000.0])
		app.go_base()
		for i in 10:
			await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(app.save_path))
	quit()
