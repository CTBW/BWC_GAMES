## The expedition's battle in the real game, in a window (1920×1080): the
## turn-based rules on Ashby farm, shown in 3D. A new company plans and marches
## out (the company's own automation picks the army); the deployment shows; the
## battle begins (the HUD's Begin Battle); in the first turn a squad is selected
## by a click on one of its men and marched by a click on a tile toward the
## warband (synthesized clicks: Input.parse_input_event at the men's and the
## ground's screen positions); End Turn hands over and the enemy's turn plays;
## then the AI fights the rest (App.debug_auto_battle) and the view plays it
## back turn by turn until the end has played and the company is home on the
## report. Screenshots along the way. Without the rigged models (they are not
## in Git) the squads have no figures: the clicks on men are left out.
##
##   tools/godot.sh --path . --resolution 1920x1080 -s res://tests/visual/battle3d_flow.gd
## Exit code 0 when every check passed and no error was logged. Shots and the
## log: tests/visual/out/battle3d_flow/. Uses its own save file.
extends SceneTree

const OUT := "res://tests/visual/out/battle3d_flow/"
const SAVE := "user://battle3d_flow_save.json"
## Seconds the fight may take before the run gives up on its end.
const FIGHT_LIMIT := 240.0


class Catcher extends Logger:
	var mutex := Mutex.new()
	var errors: Array = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var where := "%s:%d" % [file, line]
		for bt in script_backtrace:
			if bt.get_frame_count() > 0:
				where = "%s:%d" % [bt.get_frame_file(0), bt.get_frame_line(0)]
				break
		mutex.lock()
		errors.append("%s %s" % [where, rationale if rationale != "" else code])
		mutex.unlock()


var app: Node
var main: Node
var catcher := Catcher.new()
var failed: Array = []
var log_lines: Array = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	OS.add_logger(catcher)
	_run.call_deferred()


func _say(t: String) -> void:
	print(t)
	log_lines.append(t)


func _check(ok: bool, what: String) -> void:
	_say(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		failed.append(what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func _shot(name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := OUT + name + ".png"
	img.save_png(path)
	_say("shot %s" % ProjectSettings.globalize_path(path))


func _click(p: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	Input.parse_input_event(m)
	await _frames(2)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.position = p
		e.global_position = p
		Input.parse_input_event(e)
		await _frames(2)


func _run() -> void:
	app = root.get_node("App")
	app.save_path = SAVE
	var Prefs = load("res://scripts/core/prefs.gd")
	Prefs.set_pref("manualSeen", true)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var t0 := Time.get_ticks_msec()
	while app.screen == "loading" and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	_say("loaded in %d ms" % (Time.get_ticks_msec() - t0))
	app.new_game(1234)
	await _frames(4)
	t0 = Time.get_ticks_msec()
	_check(app.debug_auto_prepare(1), "the company marches out")
	_say("battle opened in %d ms" % (Time.get_ticks_msec() - t0))
	var v: Node = app.battle_view
	_check(app.screen == "battle" and v != null, "the expedition opens on the 3D battle")
	if v == null:
		return _end()
	await _seconds(1.5)
	# The rigged models are not in Git: on a fresh checkout no squad has men to
	# show or click, and the battle plays without figures.
	var bare: bool = v.squads.is_empty()
	if bare:
		_say("no squad's men are on disk (the rigged models are not in Git): no figures, no clicks on them")
	else:
		var mine: Array = v.squads.filter(func(q): return q.faction == "player")
		var theirs: Array = v.squads.filter(func(q): return q.faction == "enemy")
		_check(mine.size() == app.game.expedition.army.size(), "every squad of the army is on the field (%d)" % mine.size())
		_check(theirs.size() == v.b.units.filter(func(u): return u.faction == "enemy").size(), "every squad of the warband is on the field (%d)" % theirs.size())
	_check(v.b.phase == "deploy", "the company deploys first")
	await _shot("01_deploy")
	var begin: Array = main.find_children("Begin", "BaseButton", true, false)
	_check(begin.size() == 1, "the HUD offers Begin Battle")
	if begin.size() == 1:
		await _click(begin[0].get_global_rect().get_center())
	t0 = Time.get_ticks_msec()
	while not (v.b.phase == "player" and not v.ui.busy and not v.busy()) and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	_check(v.b.phase == "player" and not v.ui.busy, "the company's first turn")
	await _shot("02_turn1")
	if not bare:
		await _march(v)
	var et: Array = main.find_children("EndTurn", "BaseButton", true, false)
	_check(et.size() == 1, "the HUD offers End Turn")
	if et.size() == 1:
		await _click(et[0].get_global_rect().get_center())
	await _seconds(0.5)
	_check(v.ui.side == "enemy" or v.rules_running() or v.b.turn > 1, "End Turn hands over to the enemy")
	await _seconds(2.5)
	await _shot("06_enemy_turn")
	t0 = Time.get_ticks_msec()
	while not (v.b.phase == "player" and not v.ui.busy and not v.busy()) and v.b.phase != "over" and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	_say("the enemy's turn played in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0 + 3.0))
	_check(v.b.phase == "player" or v.b.phase == "over", "the company's second turn")
	await _shot("07_turn2")
	# The AI fights the rest; the view plays it back, turn by turn.
	v.speed = 2.0
	app.debug_auto_battle()
	var start := Time.get_ticks_msec()
	var shots := 0
	var frames := 0
	var slow := 0
	var last := Time.get_ticks_msec()
	var fielded := {}
	for q in v.squads:
		fielded[q] = q.members.size()
	while app.screen == "battle" and Time.get_ticks_msec() - start < FIGHT_LIMIT * 1000.0:
		await process_frame
		frames += 1
		var now := Time.get_ticks_msec()
		if now - last > 50:
			slow += 1
		last = now
		if not is_instance_valid(v):
			break
		var fallen := 0
		for q in v.squads:
			fallen += int(fielded[q]) - q.standing()
		if shots == 0 and fallen > 0:
			shots = 1
			await _seconds(0.3)
			await _shot("08_first_blood")
		elif shots == 1 and now - start > 20000:
			shots = 2
			v._zoom_goal = 1.6
			await _seconds(0.8)
			await _shot("09_close")
			v._zoom_goal = 0.8
		elif shots == 2 and v.b.phase == "over" and not v.rules_running():
			shots = 3
			_say("the rules' battle: %s after %d turns" % [v.b.result, v.b.turn])
	var secs := (Time.get_ticks_msec() - start) / 1000.0
	_say("playback: %.1f s, %d frames (%.0f fps), %d frames over 50 ms" % [secs, frames, frames / maxf(secs, 0.01), slow])
	_check(app.screen == "report", "the end played and the company is home: the report (%s)" % app.screen)
	_check(app.game.expedition == null, "the expedition is over")
	await _frames(10)
	await _shot("10_report")
	_end()

## Selects a squad by a click on one of its men, then marches it toward the
## warband by a click on a tile.
func _march(v: Node) -> void:
	var u: Dictionary = v.b.active("player")[1]
	var sq = v.views[u.uid].sq
	# One of its men in plain sight: a man of the squad in front covers one behind.
	var mp := Vector2.ZERO
	for man: Node3D in sq.alive():
		mp = v.cam.unproject_position(man.position + Vector3(0, man.height_m() * 0.5, 0))
		var under = v.resolve_pointer(mp).get("unit")
		if under != null and under.uid == u.uid:
			break
	await _click(mp)
	_check(v.ui.selected == u.uid, "a click on a man selects his squad (%s)" % v.ui.selected)
	var foe: Dictionary = v.b.active("enemy")[0]
	var best = null
	var bd := INF
	for k in v._reach(u):
		var t := {"x": k % 1000, "y": floori(k / 1000.0)}
		var d: float = absf(t.x - foe.x) + absf(t.y - foe.y)
		if d < bd and v.b.known_unit_at("player", t.x, t.y) == null:
			bd = d
			best = t
	_check(best != null, "a tile to march to")
	if best != null:
		var p: Vector2 = v.cam.unproject_position(v.field.on_ground(Vector2(best.x, best.y)))
		var m := InputEventMouseMotion.new()
		m.position = p
		m.global_position = p
		Input.parse_input_event(m)
		await _frames(3)
		_check(v.ui.hover.get("dest") != null, "the hover previews the march (%s)" % v.ui.hover.get("dest"))
		await _shot("03_preview")
		await _click(p)
		await _seconds(0.4)
		var moved: Dictionary = v.b.unit(u.uid)
		_check(moved.hasMoved and moved.x == best.x and moved.y == best.y, "a click on the tile marches the squad there")
		await _seconds(1.2)
		await _shot("04_march")
		var t0 := Time.get_ticks_msec()
		while v.busy() and Time.get_ticks_msec() - t0 < 20000:
			await process_frame
		_say("march played in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0 + 1.6))
		await _shot("05_marched")


func _end() -> void:
	for e in catcher.errors:
		_say("ERROR %s" % e)
	if not catcher.errors.is_empty():
		failed.append("%d errors logged" % catcher.errors.size())
	_say("%s: %d checks failed" % ["FAILED" if not failed.is_empty() else "PASSED", failed.size()])
	var f := FileAccess.open(OUT + "log.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log_lines) + "\n")
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(0 if failed.is_empty() else 1)
