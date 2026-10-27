## Native review of Wolf Scout 3 in the actual sandbox scene, controller and materials.
## tools/godot.sh --path . -s res://prototypes/wolf_scout_anim/qa/wolf_scout_3_sandbox.gd
extends SceneTree

const OUT := "res://../../review/wolf-scout/wolf-scout-3/native"
var lab: Node3D
var rows: Array = []
var errors: Array = []
var events: Array = []
## Wolf Scout 2's clip lengths (s): these clips keep its timing.
const WS2_LENGTH := {"sneak": 32.0 / 30, "attack": 61.0 / 30, "death": 68.0 / 30}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	rows.append({"check": label, "passed": ok})
	if not ok:
		errors.append(label)
		push_error(label)

func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func shot(name: String, focus: Vector3, zoom: float) -> void:
	lab.focus = focus
	lab.zoom = zoom
	lab._zoom_goal = zoom
	lab._apply_look()
	await wait(0.12)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name + ".png"))
	print("WOLF3_CAPTURE ", name)

func pose(u: Node3D, clip: String, time: float) -> void:
	u.state = "pose"
	u.player.play(u.clips[clip].anim, 0.0)
	u.player.seek(time, true)
	u.player.pause()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1600, 900)
	lab = load("res://prototypes/sandbox3d/scenes/sandbox3d.tscn").instantiate()
	root.add_child(lab)
	await wait(1.0)
	lab._capturing = true
	lab.fight_back = false
	var unit: Node3D = lab._unit("wolf_scout_3")
	check(unit != null, "Wolf Scout 3 is in the sandbox")
	if not unit:
		quit(1)
		return
	check(unit.clips.size() == 4, "Exactly four clips")
	for c in ["idle", "sneak", "attack", "death"]:
		check(unit.has_clip(c), "Imported clip: " + c)
	check(is_equal_approx(unit.walk_speed(), 1.830148), "Sneak playback uses the authored travel speed")
	check(unit.faction == "player", "She is on the Amberfeld side")
	for c in ["sneak", "attack", "death"]:
		check(absf(unit.clips[c].length - WS2_LENGTH[c]) < 0.001, c + " keeps Wolf Scout 2's duration")
	check(is_equal_approx(unit.clips.idle.length, 4.0) and unit.clips.idle.loop, "Crouch idle loops over 4 s")
	unit.clip_event.connect(func(e): events.append(e))
	lab._select([unit])
	var start: Vector3 = unit.position
	pose(unit, "idle", 0.0)
	await shot("pack", start + Vector3(0, 0.9, 0), 6.0)
	lab.ui.visible = false
	lab._rings.visible = false
	unit.rotation.y = PI / 4
	pose(unit, "idle", 0.0)
	await shot("game-camera", start + Vector3(0, 0.6, 0), 2.0)
	for c in ["idle", "sneak", "attack", "death"]:
		var times: Array = {"idle": [0.0, 1.0, 2.2], "sneak": [0.27, 0.53, 0.8], "attack": [0.4333, 0.8, 1.3667], "death": [0.8, 1.4667, 2.266]}[c]
		for t in times:
			pose(unit, c, t)
			await shot("%s-%03d" % [c, roundi(t * 30) + 1], start + Vector3(0, 0.6, 0), 9.0)
	# Her head and the ear openings, from the game camera and turned.
	for turn in [PI / 4, -PI / 4, 3 * PI / 4]:
		unit.rotation.y = turn
		pose(unit, "idle", 0.97)   # an ear flick
		await shot("head-%d" % roundi(rad_to_deg(turn)), start + Vector3(0, 0.95, 0), 20.0)
	unit.rotation.y = PI / 4
	lab.ui.visible = true
	# Real playback and interruption, not only seeks.
	unit.revive()
	await wait(0.65)
	unit.order_move([start + Vector3(0, 0, 3.0)])
	await wait(0.45)
	check(unit.state == "walk" and unit._clip == "sneak", "Move enters sneak")
	check(unit.position.distance_to(start) > 0.25, "Controller moves while sneak plays")
	unit.stop()
	await wait(0.3)
	check(unit.state == "idle" and unit._clip == "idle", "Stop returns to idle")
	unit.strike(null, 0)
	await wait(1.1)
	check(events.count("strike_left") == 1 and events.count("strike_right") == 1, "Both hit events dispatch once")
	await wait(1.2)
	check(unit.state == "idle", "Attack finishes into idle")
	unit.die()
	await wait(2.6)
	check(unit.is_dead() and unit._clip == "death", "Death plays and holds its last pose")
	unit.revive()
	await wait(0.6)
	check(unit.state == "idle", "Revive returns to idle")
	FileAccess.open(OUT.path_join("checks.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": rows, "errors": errors}, "\t"))
	print("WOLF3_NATIVE_RESULT ", rows.size(), " checks; errors: ", errors)
	quit(0 if errors.is_empty() else 1)
