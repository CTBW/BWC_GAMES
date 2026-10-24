## Drive the sandbox through its scenarios in a real window and save shots.
##   tools/godot.sh --path . --resolution 1600x900 --audio-driver Dummy -s res://prototypes/footman_anim/qa/sandbox_shots.gd -- plan=quick
## Writes tests/visual/out/footman_proto/shots/<name>.png
extends SceneTree

var sandbox: Node2D
var out := ""


func _initialize() -> void:
	_run.call_deferred()


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await process_frame
		t += 1.0 / 60.0


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out + "/" + name + ".png")
	print("SHOT ", name)


func _run() -> void:
	var args := {"plan": "quick"}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	out = ProjectSettings.globalize_path("res://tests/visual/out/footman_proto/shots")
	DirAccess.make_dir_recursive_absolute(out)
	sandbox = load("res://prototypes/footman_anim/scenes/footman_sandbox.tscn").instantiate()
	root.add_child(sandbox)
	await _wait(0.5)
	var plan: String = args.plan
	if plan == "quick" or plan == "all":
		await _shot("single_idle")
		sandbox._single("attack")
		await _wait(0.62)
		await _shot("single_attack_contact")
		sandbox.set_scenario("formation")
		await _wait(1.0)
		await _shot("formation_se")
		sandbox.set_scenario("attack")
		await _wait(0.66)
		await _shot("attack_se")
		await _wait(0.5)
		await _shot("attack_se_b")
		sandbox.set_scenario("march")
		await _wait(1.6)
		await _shot("march_mid")
		await _wait(3.0)
		await _shot("march_end")
	quit()
