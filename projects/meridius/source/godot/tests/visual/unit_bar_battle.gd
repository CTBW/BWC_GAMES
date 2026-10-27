## The unit bar (scripts/ui/unit_bar) in the real game, in a window: a new
## company marches out (App.debug_auto_prepare) and deploys with its first
## squad in the bar; Begin Battle; then each kind of squad in the company is
## selected in turn (a click on its card in the company column); the pointer
## over a command and over a stat plaque (their tooltips); an ability armed; a
## click on the bar's stone (it must not reach the field); a click on one of the
## company's squads in the minimap (it selects it); a foe shown in the bar by a
## right click on it (the squad staying selected), Esc going back, a right drag
## from a foe panning the camera; Esc disarming the ability, a right click on
## the field dropping the selection (the views' own keys: the bar sinks); with
## nothing selected, a left click on a foe showing it. Clicks and keys are
## synthesized (Input.parse_input_event). Checks along the way.
##
##   tools/godot.sh --path . --resolution 1920x1080 -s res://tests/visual/unit_bar_battle.gd
## Exit code 0 when every check passed and no error was logged. Shots and the
## log: tests/visual/out/unit_bar/<width>x<height>_<step>.png and .txt. Uses
## its own save file.
extends SceneTree

const DB = preload("res://scripts/data/db.gd")
const OUT := "res://tests/visual/out/unit_bar/"
const SAVE := "user://unit_bar_battle_save.json"


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
var view: Node
var bar: Control
var catcher := Catcher.new()
var failed: Array = []
var log_lines: Array = []
var tag := ""


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
	img.save_png(ProjectSettings.globalize_path(OUT + "%s_%s.png" % [tag, name]))
	_say("shot %s_%s %s" % [tag, name, img.get_size()])


## The pointer to `p` (the screen's canvas coordinates; the window's pixels
## differ when the window is not 1920×1080, the canvas being stretched).
func _point(p: Vector2) -> void:
	var w := root.get_final_transform() * p
	var m := InputEventMouseMotion.new()
	m.position = w
	m.global_position = w
	Input.parse_input_event(m)
	await _frames(2)


func _click(p: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	await _point(p)
	var w := root.get_final_transform() * p
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.position = w
		e.global_position = w
		Input.parse_input_event(e)
		await _frames(2)


func _key(k: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = pressed
		Input.parse_input_event(e)
		await _frames(2)


## A drag with `button` held from `a` to `z` (canvas coordinates), in steps.
func _drag(a: Vector2, z: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	await _point(a)
	var xf := root.get_final_transform()
	var mask := MOUSE_BUTTON_MASK_RIGHT if button == MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_LEFT
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.button_mask = mask
	e.pressed = true
	e.position = xf * a
	e.global_position = e.position
	Input.parse_input_event(e)
	await _frames(2)
	var last: Vector2 = e.position
	for i in range(1, 7):
		var w := xf * a.lerp(z, i / 6.0)
		var m := InputEventMouseMotion.new()
		m.position = w
		m.global_position = w
		m.relative = w - last
		m.button_mask = mask
		last = w
		Input.parse_input_event(m)
		await _frames(2)
	var up := InputEventMouseButton.new()
	up.button_index = button
	up.pressed = false
	up.position = last
	up.global_position = last
	Input.parse_input_event(up)
	await _frames(2)


## What the view picks at `p` (canvas coordinates): {tile, unit}.
func _pick(p: Vector2) -> Dictionary:
	if view is Node3D:
		return view.resolve_pointer(p)
	var l: Vector2 = view.get_global_transform_with_canvas().affine_inverse() * p
	return view.resolve_pointer(l.x, l.y)


## A point over a foe in sight, clear of the HUD's panels (the hit nearest the
## middle of the first foe found), and its uid; empty when none is in sight.
func _foe_spot(con: Rect2) -> Dictionary:
	var size := root.get_viewport().get_visible_rect().size
	var hits := {}
	for y in range(120, int(con.position.y) - 20, 14):
		for x in range(280, int(size.x) - 380, 14):
			var u: Variant = _pick(Vector2(x, y)).get("unit")
			if u != null and u.faction != "player" and view.unit_visible(u):
				if not hits.has(u.uid):
					hits[u.uid] = []
				hits[u.uid].append(Vector2(x, y))
	for uid in hits:
		var pts: Array = hits[uid]
		var mid := Vector2.ZERO
		for q in pts:
			mid += q
		mid /= pts.size()
		var best: Vector2 = pts[0]
		for q in pts:
			if q.distance_to(mid) < best.distance_to(mid):
				best = q
		return {"at": best, "uid": uid}
	return {}


## A point on the field with no squad on it, clear of the HUD's panels.
func _ground_spot() -> Vector2:
	var size := root.get_viewport().get_visible_rect().size
	for f in [Vector2(0.5, 0.3), Vector2(0.5, 0.2), Vector2(0.4, 0.25), Vector2(0.6, 0.25), Vector2(0.45, 0.4), Vector2(0.55, 0.15)]:
		var q: Vector2 = size * f
		if _pick(q).get("unit") == null:
			return q
	return size * Vector2(0.5, 0.12)


func _cam() -> Variant:
	return view.get("focus") if view is Node3D else Vector2(view.cam.tx, view.cam.ty)


func _centre(n: Node) -> Vector2:
	return (n as Control).get_global_rect().get_center()


## Waits until the view has played everything back and is the company's to command.
func _settle(limit := 20.0) -> void:
	var t0 := Time.get_ticks_msec()
	while (view.ui.busy or view.busy()) and Time.get_ticks_msec() - t0 < limit * 1000.0:
		await process_frame


func _run() -> void:
	var size := root.get_viewport().get_visible_rect().size
	tag = "%dx%d" % [root.size.x, root.size.y]
	_say("window %s (canvas %s), screen %s" % [tag, size, DisplayServer.screen_get_size()])
	app = root.get_node("App")
	app.save_path = SAVE
	var Prefs = load("res://scripts/core/prefs.gd")
	Prefs.set_pref("manualSeen", true)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var t0 := Time.get_ticks_msec()
	while app.screen == "loading" and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	app.new_game(1234)
	await _frames(4)
	_check(app.debug_auto_prepare(1), "the company marches out")
	view = app.battle_view
	_check(app.screen == "battle" and view != null, "the expedition opens on the battle")
	if view == null:
		return _end()
	await _seconds(1.5)
	bar = main.find_child("UnitBar", true, false)
	_check(bar != null, "the battle HUD has the unit bar")
	if bar == null:
		return _end()
	var b = view.b
	_check(b.phase == "deploy" and view.ui.selected != null, "the company deploys with a squad selected")
	_check(bar.shown() and bar.data.get("uid") == view.ui.selected, "the bar shows the selected squad")
	await _seconds(0.5)
	var con: Rect2 = bar.console.get_global_rect()
	_check(absf(con.end.y - size.y) < 1.0 and absf(con.get_center().x - size.x * 0.5) < 1.0 and con.size.x < size.x,
		"the console stands in the middle of the screen's bottom (%s)" % con)
	_layout_checks(con)
	await _shot("01_deploy")

	var begin: Array = main.find_children("Begin", "BaseButton", true, false)
	_check(begin.size() == 1, "the HUD offers Begin Battle")
	if begin.size() == 1:
		await _click(_centre(begin[0]))
	t0 = Time.get_ticks_msec()
	while not (b.phase == "player" and not view.ui.busy and not view.busy()) and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	_check(b.phase == "player", "the company's first turn")
	await _seconds(0.4)
	await _shot("02_turn1")

	# Each kind of squad, selected by its card in the company column.
	var seen := {}
	var n := 3
	for u in b.active("player"):
		if seen.has(u.typeId) or seen.size() >= 4:
			continue
		seen[u.typeId] = true
		var card: Node = main.find_child("Mini_" + str(u.uid), true, false)
		if card == null:
			_check(false, "a card for %s" % u.name)
			continue
		await _click(_centre(card))
		await _seconds(0.45)
		_check(view.ui.selected == u.uid and bar.data.get("uid") == u.uid, "%s selected and in the bar" % u.typeId)
		_say("      portrait: %s (figure %s)" % ["live" if bar.portrait.get("_figure") != null else "baked", bar.data.get("figure")])
		await _shot("%02d_%s" % [n, u.typeId])
		n += 1

	# The tooltips: a command's (the first ability), a plaque's.
	var first: Node = null
	for c in bar.find_children("Ability_*", "BaseButton", true, false):
		if c.visible and not c.disabled:
			first = c
			break
	if first != null:
		await _point(_centre(first))
		await _seconds(0.8)
		await _shot("%02d_tip_command" % n)
		n += 1
	var plaque: Node = bar.find_child("Stat0", true, false)
	await _point(_centre(plaque))
	await _seconds(0.8)
	await _shot("%02d_tip_stat" % n)
	n += 1

	# No click through the bar: a click on its stone neither moves nor reselects.
	var sel: Variant = view.ui.selected
	var at := {"x": b.unit(sel).x, "y": b.unit(sel).y}
	await _click(con.position + Vector2(con.size.x * 0.5, 6.0))
	await _seconds(0.3)
	_check(view.ui.selected == sel and b.unit(sel).x == at.x and b.unit(sel).y == at.y and not b.unit(sel).hasMoved,
		"a click on the bar's stone does not reach the field")

	# The minimap: a click on another of the company's squads selects it.
	var mm: Control = bar.find_child("Minimap", true, false)
	var other: Variant = null
	for u in b.active("player"):
		if u.uid != sel:
			other = u
			break
	if other != null and mm != null:
		var p: Vector2 = mm.get_global_rect().position + mm._xform() * Vector2(other.x + 0.5, other.y + 0.5)
		await _click(p)
		await _seconds(0.45)
		_check(view.ui.selected == other.uid, "a click on the minimap selects %s (%s)" % [other.uid, view.ui.selected])

	# An ability armed, then Esc: disarmed, then the selection dropped.
	first = null
	for c in bar.find_children("Ability_*", "BaseButton", true, false):
		if c.visible and not c.disabled and DB.ABILITIES.get(c.command.get("ability"), {}).get("kind") in ["attack", "spell"]:
			first = c
			break
	if first != null:
		var used := []
		bar.command_used.connect(func(id): used.append(id))
		# A real pointer crossing the window moves Godot's; then the click is tried again.
		for attempt in 3:
			await _point(_centre(first))
			var hovered: Variant = root.gui_get_hovered_control()
			await _click(_centre(first))
			await _seconds(0.5)
			_say("pressed %s: used %s, hovered %s, selected %s" % [first.name, used, hovered, view.ui.selected])
			if view.ui.ability == first.command.ability:
				break
		_check(view.ui.ability == first.command.ability, "the command arms %s" % first.command.ability)
		await _shot("%02d_armed" % n)
		n += 1
		await _key(KEY_ESCAPE)
		await _frames(4)
		_check(view.ui.ability == null, "Esc disarms it")
	for attempt in 3:
		await _click(_ground_spot(), MOUSE_BUTTON_RIGHT)
		await _seconds(0.6)
		if view.ui.selected == null:
			break
	_check(view.ui.selected == null and not bar.shown(), "a right click drops the selection and the bar sinks")
	_check(not bar.visible, "the bar is gone")
	await _shot("%02d_closed" % n)
	n += 1

	# Foes: the turn ended until one is in sight (the company starts with none).
	var spot := _foe_spot(con)
	for turn in 6:
		if not spot.is_empty() or b.phase == "over":
			break
		view.end_turn()
		t0 = Time.get_ticks_msec()
		await _frames(4)
		while not (b.phase in ["player", "over"] and not view.ui.busy and not view.busy()) and Time.get_ticks_msec() - t0 < 60000:
			await process_frame
		await _seconds(0.5)
		spot = _foe_spot(con)
	_check(not spot.is_empty(), "a foe in sight (turn %d)" % int(b.get("turn") if b.get("turn") != null else 0))
	if spot.is_empty():
		return _end()
	if view.ui.selected == null:
		view.select_next()
		await _seconds(0.5)
	sel = view.ui.selected
	_check(sel != null and bar.data.get("uid") == sel, "a squad selected, in the bar")
	# A right click on the foe shows it, the squad staying selected; Esc goes
	# back (no pause menu); a right drag from it pans the camera.
	for attempt in 3:
		# The pointer rests on it first (the view's hover names what a click is on).
		await _point(spot.at)
		await _click(spot.at, MOUSE_BUTTON_RIGHT)
		await _seconds(0.5)
		if bar.data.get("uid") == spot.uid:
			break
	_check(bar.data.get("uid") == spot.uid and view.ui.selected == sel,
		"a right click on %s shows it in the bar, %s still selected (bar %s, selected %s)" % [spot.uid, sel, bar.data.get("uid"), view.ui.selected])
	_check(bar.find_child("Back", true, false) != null, "the foe's card has the way back")
	await _shot("%02d_foe" % n)
	n += 1
	await _key(KEY_ESCAPE)
	await _frames(4)
	_check(bar.data.get("uid") == sel and view.ui.selected == sel and not app.menu_open, "Esc: back to %s, no menu" % sel)
	if app.menu_open:
		app.open_menu(false)
	var cam0: Variant = _cam()
	await _drag(spot.at, spot.at + Vector2(-160, -50), MOUSE_BUTTON_RIGHT)
	await _seconds(0.4)
	_check(bar.data.get("uid") != spot.uid and _cam() != cam0, "a right drag from a foe pans the camera (%s to %s)" % [cam0, _cam()])
	# Nothing selected: a left click on a foe shows it, a right click on the field puts it away.
	for attempt in 3:
		if view.ui.selected == null:
			break
		await _click(_ground_spot(), MOUSE_BUTTON_RIGHT)
		await _seconds(0.5)
	spot = _foe_spot(con)
	_check(view.ui.selected == null and not spot.is_empty(), "nothing selected, a foe in sight")
	if not spot.is_empty():
		for attempt in 3:
			await _click(spot.at)
			await _seconds(0.5)
			if bar.data.get("uid") == spot.uid:
				break
		_check(bar.shown() and bar.data.get("uid") == spot.uid and view.ui.selected == null,
			"with nothing selected, a left click on %s shows it (%s)" % [spot.uid, bar.data.get("uid")])
		await _shot("%02d_foe_alone" % n)
		await _click(_ground_spot(), MOUSE_BUTTON_RIGHT)
		await _seconds(0.6)
		_check(not bar.shown(), "a right click on the field puts it away")
	_end()


## The HUD's other panels against the console: the log stands above it, the
## company column and the hover panels clear it.
func _layout_checks(con: Rect2) -> void:
	var hud: Node = bar.get_parent()
	var lg: Control = hud.find_child("Log", true, false)
	_check(lg != null and lg.get_global_rect().end.y <= con.position.y + 1.0, "the log stands above the bar (%s)" % (lg.get_global_rect() if lg != null else null))
	var co: Control = hud.find_child("Company", true, false)
	_check(co != null and co.get_global_rect().end.y <= con.position.y + 1.0, "the company column clears the bar (%s)" % (co.get_global_rect() if co != null else null))


func _end() -> void:
	await _frames(2)
	for e in catcher.errors:
		_say("ERROR " + e)
	_say("%d failed, %d errors" % [failed.size(), catcher.errors.size()])
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT + tag + ".txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(log_lines) + "\n")
	quit(0 if failed.is_empty() and catcher.errors.is_empty() else 1)
