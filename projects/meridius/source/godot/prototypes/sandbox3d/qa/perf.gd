## Frame cost of the 3D sandbox, with its parts switched off one at a time.
##   tools/godot.sh --path . --audio-driver Dummy -s res://prototypes/sandbox3d/qa/perf.gd
## Prints the mean frame time, the process time, draw calls and objects per case.
extends SceneTree

var sb: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _measure(label: String, sec := 2.0) -> void:
	for i in 10:
		await process_frame
	var t0 := Time.get_ticks_usec()
	var frames := 0
	var proc := 0.0
	var calls := 0.0
	var objs := 0.0
	while Time.get_ticks_usec() - t0 < int(sec * 1e6):
		await process_frame
		frames += 1
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / frames
	print("PERF %-28s %6.1f ms/frame  %5.1f fps  process %5.1f ms  calls %6d  objects %6d" % [label, ms, 1000.0 / ms, proc / frames * 1000.0, calls / frames, objs / frames])


func _run() -> void:
	sb = load("res://prototypes/sandbox3d/scenes/sandbox3d.tscn").instantiate()
	root.add_child(sb)
	await _measure("warm up", 1.0)
	sb._set_zoom(1.25)
	await _measure("baseline zoom 1.25")
	sb._set_zoom(0.62)
	await _measure("baseline zoom 0.62")
	sb._set_zoom(1.25)
	sb.get_viewport().scaling_3d_scale = 1.0
	await _measure("3D at 1x")
	sb.get_viewport().scaling_3d_scale = 2.0
	sb.sun.shadow_enabled = false
	await _measure("no shadows")
	sb.sun.shadow_enabled = true
	var wood: Node3D = sb.field.get_node("Woodland")
	wood.visible = false
	await _measure("no woodland")
	wood.visible = true
	sb.field._blades.visible = false
	await _measure("no grass blades")
	sb.field._blades.visible = true
	sb.set_process(false)
	await _measure("sandbox _process off")
	sb.set_process(true)
	for u in sb.units:
		u.visible = false
		u.process_mode = Node.PROCESS_MODE_DISABLED
	await _measure("no units")
	quit()
