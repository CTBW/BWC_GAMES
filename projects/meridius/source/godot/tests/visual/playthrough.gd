## Input-driven play-through of the real game in a window (1920×1080).
##
## Boots scenes/main.tscn and plays it only through synthesized input events
## delivered like a player's (Input.parse_input_event: mouse motion, buttons,
## wheel, keys) at screen positions computed from the Controls' rects and from
## the world cameras (Camera.world_to_screen) for buildings, map nodes, tiles
## and squads. Game state is only read, to choose where to click and to check
## what each click did; no game method performs an action. The battle bot asks
## the rules what the company's automation would do (Ai.act_unit on a deep copy
## of the battle) and turns that into clicks: select a squad, point at a tile
## edge (and Q / E) for the facing, click the tile, click the enemy, ability
## buttons and number keys, Redo, Done / Space, End Turn / Enter.
##
## Default flow (~2.5 min): title → New Company → welcome → buildings on the
## camp map (Barracks: hire a recruit) → Roster → a soldier → Sound twice → F11
## twice → Esc menu → Plan Expedition (army, supplies, advice) → March Out → map
## nodes to a battle (dialogs through their buttons) → the battle (manual,
## deployment swap, Begin, played to its end by clicks: Redo, abilities, grid,
## danger, wheel, key pan, speed) → result → Retreat home → report → garrison →
## the last stand opened through the debug API to click its minimap → Save and
## Quit to Title. `-- --full` adds Save/Continue mid-expedition, more nodes, a
## second expedition with a battle left by Retreat, two turns of the last stand
## and New Company over the old save (~5 min).
##
##   tools/godot.sh --path . -s res://tests/visual/playthrough.gd [-- --full]
## Exit code 0 when every check passed and no error was logged. Log, frame times and screenshots: tests/visual/out/playthrough/.
## The game's own save and prefs are not touched (a separate save file; prefs
## are restored at the end). Real mouse and key events of whoever sits at the
## machine are dropped while it runs (only the synthesized ones reach the game).
extends SceneTree

const JS = preload("res://scripts/core/js.gd")
const Rng = preload("res://scripts/core/rng.gd")
const Iso = preload("res://scripts/render/iso.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const Ai = preload("res://scripts/rules/ai.gd")
const DB = preload("res://scripts/data/db.gd")
const Expedition = preload("res://scripts/campaign/expedition.gd")
const H = preload("res://scripts/ui/hud_common.gd")

## Device id of the synthesized events (everything else is dropped).
const MARK := 7357
const OUT := "res://tests/visual/out/playthrough/"
const SAVE := "user://playthrough_save.json"
const PREFS := "user://prefs.json"
## The player's prefs while a run has them replaced (restored at the end, or
## by the next run if this one was killed).
const PREFS_BACKUP := "user://prefs.playthrough-backup.json"


class Catcher extends Logger:
	var mutex := Mutex.new()
	var errors: Array = []
	var warnings: Array = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtrace: Array[ScriptBacktrace]) -> void:
		var where := "%s:%d" % [file, line]
		for bt in script_backtrace:
			if bt.get_frame_count() > 0:
				where = "%s:%d" % [bt.get_frame_file(0), bt.get_frame_line(0)]
				break
		var msg := rationale if rationale != "" else code
		mutex.lock()
		if error_type == ERROR_TYPE_WARNING:
			warnings.append("%s %s" % [where, msg])
		else:
			errors.append("%s %s" % [where, msg])
		mutex.unlock()


## Drops mouse and key events that were not synthesized here (the real mouse of
## whoever sits at the machine), except the engine's own re-sends of the last
## pointer position.
class RealInputFilter extends Node:
	var mark := 0
	var mouse := Vector2.ZERO
	var dropped := 0
	var samples: Array = []

	func _input(e: InputEvent) -> void:
		if not (e is InputEventMouse or e is InputEventKey):
			return
		if e.device == mark:
			return
		if e is InputEventMouseMotion and (e as InputEventMouseMotion).position.distance_to(mouse) < 0.5:
			return
		dropped += 1
		if samples.size() < 8:
			samples.append("%s dev %d at %s" % [e.get_class(), e.device, e.position if e is InputEventMouse else e.as_text()])
		get_viewport().set_input_as_handled()


var catcher := Catcher.new()
var filter := RealInputFilter.new()
var app: Node
var main: Node
var full := false
var failures: Array = []
var steps := 0
var lines: Array = []
var t_start := 0
var shot_n := 0
var mouse := Vector2(960, 540)
var _mask := 0
## Frame times (ms) per phase.
var phase := "boot"
var frame_ms := {}
var _last_frame := 0
var _prefs_backup: Variant = null
var _hovered_api := false
## Frames over 100 ms: [phase, ms, the last logged step].
var hitches: Array = []
## Time this script spent on its own work (planning, picking, captures) in the
## current frame: taken out of the frame times.
var _excl_us := 0
## Battle bookkeeping.
var used := {}
var battles := 0


func _initialize() -> void:
	OS.add_logger(catcher)
	full = OS.get_cmdline_user_args().has("--full")
	_run.call_deferred()


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if _last_frame > 0:
		if not frame_ms.has(phase):
			frame_ms[phase] = []
		var ms := maxf(0.0, (now - _last_frame - _excl_us) / 1000.0)
		frame_ms[phase].append(ms)
		if ms > 100.0:
			hitches.append([phase, ms, lines[-1] if lines.size() > 0 else ""])
	_last_frame = now
	_excl_us = 0
	return false


# ---------------------------------------------------------------- log

func say(s: String) -> void:
	var l := "[%6.1fs] %s" % [(Time.get_ticks_msec() - t_start) / 1000.0, s]
	lines.append(l)
	print(l)


func check(cond: bool, what: String) -> bool:
	steps += 1
	if cond:
		say("ok   " + what)
	else:
		failures.append(what)
		say("FAIL " + what)
	return cond


func shot(name: String) -> void:
	await process_frame
	var t0 := Time.get_ticks_usec()
	shot_n += 1
	var img := root.get_texture().get_image()
	var path := OUT + "%02d_%s.png" % [shot_n, name]
	img.save_png(ProjectSettings.globalize_path(path))
	say("shot " + path.get_file())
	# The capture and PNG encoding are not the game's frame time.
	_excl_us += Time.get_ticks_usec() - t0



func set_phase(p: String) -> void:
	phase = p


# ---------------------------------------------------------------- frames

func frames(n := 1) -> void:
	for i in n:
		await process_frame


func wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < sec * 1000.0:
		await process_frame


## Waits until cond() (or the timeout, which fails the check).
func until(cond: Callable, timeout: float, what: String) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > timeout * 1000.0:
			check(false, "timeout (%.0f s): %s" % [timeout, what])
			return false
		await process_frame
	return true


# ---------------------------------------------------------------- input

## Viewport (canvas) coordinates → window pixels (the stretch transform).
func _to_window(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func _send(e: InputEvent) -> void:
	e.device = MARK
	Input.parse_input_event(e)


func move_mouse(p: Vector2, n := 3) -> void:
	var from := mouse
	for i in range(1, n + 1):
		var q := from.lerp(p, float(i) / n)
		var e := InputEventMouseMotion.new()
		var w := _to_window(q)
		e.position = w
		e.global_position = w
		e.relative = _to_window(q) - _to_window(mouse)
		e.button_mask = _mask
		mouse = q
		filter.mouse = w
		_send(e)
		await process_frame
	await process_frame


func _button(p: Vector2, idx: int, pressed: bool, double := false) -> void:
	var e := InputEventMouseButton.new()
	var w := _to_window(p)
	e.position = w
	e.global_position = w
	e.button_index = idx
	e.pressed = pressed
	e.double_click = double
	var bit := 1 << (idx - 1)
	if pressed:
		_mask |= bit
	else:
		_mask &= ~bit
	e.button_mask = _mask
	_send(e)


func click_at(p: Vector2, idx := MOUSE_BUTTON_LEFT) -> void:
	if mouse.distance_to(p) > 0.5:
		await move_mouse(p)
	_button(p, idx, true)
	await frames(3)
	_button(p, idx, false)
	await frames(2)


func wheel_at(p: Vector2, down: bool) -> void:
	if mouse.distance_to(p) > 0.5:
		await move_mouse(p)
	var idx := MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
	_button(p, idx, true)
	await process_frame
	_button(p, idx, false)
	await frames(2)


## Middle-button drag from a to b (pans the world views).
func drag(a: Vector2, b: Vector2, idx := MOUSE_BUTTON_MIDDLE) -> void:
	await move_mouse(a)
	_button(a, idx, true)
	await frames(2)
	await move_mouse(b, 6)
	_button(b, idx, false)
	await frames(2)


func _key_event(code: Key, pressed: bool, ctrl := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	e.ctrl_pressed = ctrl
	if pressed and code >= KEY_0 and code <= KEY_Z:
		e.unicode = code
	return e


func key(code: Key, ctrl := false) -> void:
	if ctrl:
		_send(_key_event(KEY_CTRL, true, true))
		await process_frame
	_send(_key_event(code, true, ctrl))
	await frames(2)
	_send(_key_event(code, false, ctrl))
	if ctrl:
		await process_frame
		_send(_key_event(KEY_CTRL, false, false))
	await frames(2)


func key_hold(code: Key, sec: float) -> void:
	_send(_key_event(code, true))
	await wait(sec)
	_send(_key_event(code, false))
	await frames(2)


# ---------------------------------------------------------------- controls

func ui_root() -> Control:
	return main.get_node("UI/Root")


func screen_node() -> Control:
	var s: Node = main.get_node("UI/Root/Screen")
	for c in s.get_children():
		if not c.is_queued_for_deletion():
			return c
	return null


func live(n: Node) -> bool:
	return n != null and is_instance_valid(n) and not n.is_queued_for_deletion() and n.is_inside_tree() and (not (n is CanvasItem) or (n as CanvasItem).is_visible_in_tree())


## The first visible node with this name under `under` (the UI root by default).
func find(node_name: String, under: Node = null) -> Control:
	var base: Node = under if under != null else ui_root()
	if base == null:
		return null
	for n in base.find_children(node_name, "", true, false):
		if n is Control and live(n):
			var gone := false
			var p := n.get_parent()
			while p != null:
				if p.is_queued_for_deletion():
					gone = true
					break
				p = p.get_parent()
			if not gone:
				return n
	return null


## A button whose name or visible text contains `t`.
func find_button(t: String, under: Node = null) -> BaseButton:
	var base: Node = under if under != null else ui_root()
	for b in H.buttons(base):
		if live(b) and str(b.name) == t:
			return b
	for b in H.buttons(base):
		if live(b) and H.button_text(b).contains(t):
			return b
	return null


func _canvas_rect(c: Control) -> Rect2:
	var xf := c.get_global_transform_with_canvas()
	return Rect2(xf * Vector2.ZERO, xf.get_scale() * c.size)


func hovered() -> Control:
	if _hovered_api:
		return root.gui_get_hovered_control()
	return null


## Controls on the UI layers that would take a mouse event at viewport point p
## (visible, not IGNORE, rect contains p, inside any clipping parent).
func _stoppers_at(p: Vector2) -> Array:
	var out: Array = []
	for base in [ui_root(), root.get_node_or_null("TipLayer")]:
		if base == null:
			continue
		_collect(base, p, out)
	return out


func _collect(n: Node, p: Vector2, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is Control:
		var c := n as Control
		var r := _canvas_rect(c)
		if c.clip_contents and not r.has_point(p):
			return
		if c.mouse_filter == Control.MOUSE_FILTER_STOP and r.has_point(p) and not c.is_queued_for_deletion():
			out.append(c)
	for ch in n.get_children():
		_collect(ch, p, out)


func ui_blocks(p: Vector2) -> bool:
	return not _stoppers_at(p).is_empty()


func _is_in(c: Control, inner: Control) -> bool:
	return inner != null and (inner == c or c.is_ancestor_of(inner))


## Clicks a Control at a point inside it that the GUI really routes to it
## (checked through the hovered control after moving there).
func click_control(c: Control, what: String) -> bool:
	if not live(c):
		return check(false, "%s: control present" % what)
	if c is BaseButton and (c as BaseButton).disabled:
		return check(false, "%s: enabled" % what)
	# Layout settles a frame after a rebuild: take the rect fresh for every try.
	await process_frame
	var spots: Array = [Vector2(0.5, 0.5), Vector2(0.3, 0.35), Vector2(0.7, 0.65), Vector2(0.3, 0.65), Vector2(0.7, 0.35)]
	var r := Rect2()
	for f in spots:
		if not live(c):
			return check(false, "%s: still there" % what)
		r = _canvas_rect(c)
		var p: Vector2 = r.position + r.size * f
		await move_mouse(p)
		if not live(c):
			return check(false, "%s: still there after the pointer moved onto it" % what)
		var hv := hovered()
		if not _hovered_api or _is_in(c, hv):
			await click_at(p)
			return true
		say("     %s: point %s goes to %s %s, trying another" % [what, p, hv.get_path() if hv != null else "(nothing)", _canvas_rect(hv) if hv != null else ""])
	return check(false, "%s: no point of %s reaches it (blocked by %s)" % [what, r, hovered().get_path() if hovered() != null else "nothing / the world"])


func press(node_name: String, what := "", under: Node = null) -> bool:
	var b: Control = find(node_name, under)
	if b == null:
		b = find_button(node_name, under)
	if b == null:
		return check(false, "%s: button '%s' on screen %s" % [what if what != "" else node_name, node_name, app.screen])
	return await click_control(b, what if what != "" else node_name)


# ---------------------------------------------------------------- world views

func local_to_vp(view: CanvasItem, p: Vector2) -> Vector2:
	return view.get_global_transform_with_canvas() * p


func on_screen(p: Vector2, margin := 24.0) -> bool:
	var s := root.get_visible_rect().size
	return p.x > margin and p.y > margin and p.x < s.x - margin and p.y < s.y - margin


## Waits for a world camera to settle on its target.
func settle(cam: RefCounted, timeout := 2.0) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout * 1000.0:
		if absf(cam.x - cam.tx) < 0.8 and absf(cam.y - cam.ty) < 0.8 and absf(cam.zoom - cam.tzoom) < 0.002:
			return
		await process_frame


## A point of the screen free of UI (for drags).
func free_point(near := Vector2(960, 560)) -> Variant:
	for r in [0, 80, 160, 260, 360]:
		for a in 8:
			var p: Vector2 = near + Vector2(r, 0).rotated(a * TAU / 8.0)
			if on_screen(p, 60) and not ui_blocks(p):
				return p
	return null


## Pans a world view by middle-drag so world point (wx, wy) comes to `want` (view-local px).
func pan_to(view: Node2D, cam: RefCounted, wx: float, wy: float, want := Vector2(960, 560)) -> void:
	for i in 4:
		var vs: Vector2 = Vector2(view.get("_w"), view.get("_h"))
		var s: Vector2 = cam.world_to_screen(wx, wy, vs.x, vs.y)
		var d: Vector2 = want - s
		if d.length() < 40:
			return
		if d.length() > 700:
			d = d.normalized() * 700
		var start: Variant = free_point(local_to_vp(view, want - d * 0.5))
		if start == null:
			start = free_point()
		if start == null:
			say("     no free point to drag from")
			return
		await drag(start, start + d)
		await frames(2)


# ---------------------------------------------------------------- run

func _run() -> void:
	t_start = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for f in DirAccess.get_files_at(ProjectSettings.globalize_path(OUT)):
		if f.ends_with(".png"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT + f))
	_hovered_api = root.has_method("gui_get_hovered_control")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	var scr := DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_position(scr.position + Vector2i(maxi(0, (scr.size.x - 1920) / 2), maxi(0, (scr.size.y - 1080) / 2)))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	# Real pointer motion over the window must not merge into the synthesized
	# events (accumulation would give them the real position); it is dropped.
	Input.use_accumulated_input = false
	# Keep the player's prefs; start as a first-time player (manual unseen, speed 1).
	if FileAccess.file_exists(PREFS_BACKUP):
		_prefs_backup = FileAccess.get_file_as_string(PREFS_BACKUP)
	elif FileAccess.file_exists(PREFS):
		_prefs_backup = FileAccess.get_file_as_string(PREFS)
		var bf := FileAccess.open(PREFS_BACKUP, FileAccess.WRITE)
		bf.store_string(_prefs_backup)
		bf.close()
	var pf := FileAccess.open(PREFS, FileAccess.WRITE)
	pf.store_string(JSON.stringify({"muted": false, "battleSpeed": 1, "manualSeen": false}))
	pf.close()
	app = root.get_node("App")
	app.save_path = SAVE
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	filter.name = "RealInputFilter"
	filter.mark = MARK
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	root.add_child(filter)
	await frames(2)
	say("window %s, viewport %s, screen %s, hovered-control API %s" % [DisplayServer.window_get_size(), root.get_visible_rect().size, DisplayServer.screen_get_size(), _hovered_api])
	var ok := true
	ok = await _title() and ok
	if ok:
		ok = await _garrison()
	if ok:
		ok = await _prep(1)
	if ok:
		ok = await _expedition_one()
	if ok and full:
		ok = await _second_expedition()
	if ok:
		ok = await _last_stand()
	if ok and full:
		ok = await _restart()
	_finish()


func _finish() -> void:
	set_phase("end")
	# Restore the player's prefs and drop the test save.
	if _prefs_backup != null:
		var f := FileAccess.open(PREFS, FileAccess.WRITE)
		f.store_string(_prefs_backup)
		f.close()
	if FileAccess.file_exists(PREFS_BACKUP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS_BACKUP))
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	say("")
	say("frame times (1920×1080 window, vsync off):")
	for p in frame_ms:
		say("  " + _stats(p, frame_ms[p]))
	say("frames over 100 ms (phase, ms, after):")
	for h in hitches:
		say("  %-16s %7.1f ms  after: %s" % h)
	say("real input events dropped: %d %s" % [filter.dropped, filter.samples])
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	say("orphan nodes: %d" % orphans)
	if orphans > 0:
		Node.print_orphan_nodes()
	catcher.mutex.lock()
	var errs: Array = catcher.errors.duplicate()
	var warns: Array = catcher.warnings.duplicate()
	catcher.mutex.unlock()
	for e in errs:
		say("ERROR " + e)
	for w in warns:
		say("WARNING " + w)
	say("==== %d checks, %d failed, %d errors, %d warnings, %d battles, %.0f s ====" % [steps, failures.size(), errs.size(), warns.size(), battles, (Time.get_ticks_msec() - t_start) / 1000.0])
	for f in failures:
		say("  failed: " + f)
	var out := FileAccess.open(ProjectSettings.globalize_path(OUT + "playthrough.txt"), FileAccess.WRITE)
	out.store_string("\n".join(lines) + "\n")
	out.close()
	quit(0 if failures.is_empty() and errs.is_empty() else 1)


func _stats(p: String, times: Array) -> String:
	if times.is_empty():
		return "%-16s no frames" % p
	var sorted := times.duplicate()
	sorted.sort()
	var total := 0.0
	for t in times:
		total += t
	var p99: float = sorted[mini(sorted.size() - 1, int(sorted.size() * 0.99))]
	var over := 0
	for t in times:
		if t > 33.4:
			over += 1
	return "%-16s %6d frames %6.1f s  %6.1f fps  p99 %6.1f ms  worst %6.1f ms  >33 ms: %d" % [p, times.size(), total / 1000.0, times.size() / maxf(total / 1000.0, 1e-6), p99, sorted[-1], over]


# ---------------------------------------------------------------- title, garrison

func _title() -> bool:
	set_phase("title")
	if not await until(func(): return app.screen == "title" and find("NewCompany") != null, 20.0, "boot to the title"):
		return false
	check(find("Continue") == null, "title: no Continue without a save")
	await wait(0.6)
	await shot("title")
	if not await press("NewCompany", "title: New Company"):
		return false
	await until(func(): return app.screen == "base", 10.0, "New Company opens the garrison")
	set_phase("base")
	check(app.game != null and app.game.roster.size() == 6, "a new company of 6 squads")
	await until(func(): return find("WelcomeModal") != null, 5.0, "the welcome letter")
	await wait(0.5)
	await shot("welcome")
	await press("ToWork", "welcome: To work")
	await frames(3)
	return check(find("WelcomeModal") == null and app.game.flags.get("welcome") == true, "welcome closed")


## Clicks a building on the camp map (a point the view itself resolves to it).
func click_building(id: String) -> bool:
	var v: Node2D = app.base_view
	if not check(v != null and is_instance_valid(v), "base view present"):
		return false
	await settle(v.cam)
	var b := DB.building_by_id(id)
	for attempt in 2:
		var wx := Iso.iso_x(b.pos[0], b.pos[1])
		var wy := Iso.iso_y(b.pos[0], b.pos[1])
		var pick: Variant = null
		for oy in [-60, -90, -40, -120, -20]:
			for ox in [0, -30, 30]:
				var s: Vector2 = v.cam.world_to_screen(wx + ox, wy + oy, v._w, v._h)
				var p := local_to_vp(v, s)
				if on_screen(p) and not ui_blocks(p) and v.building_at(s.x, s.y) == id:
					pick = p
					break
			if pick != null:
				break
		if pick == null:
			await pan_to(v, v.cam, wx, wy - 60)
			await settle(v.cam)
			continue
		await move_mouse(pick)
		await frames(2)
		if not check(v.ui.get("hover") == id, "hover over %s highlights it (hover %s)" % [id, v.ui.get("hover")]):
			var lp: Vector2 = v.get_global_transform_with_canvas().affine_inverse() * pick
			say("     at %s: building_at %s, dim %s, panel %s, hovered control %s, cam %.0f,%.0f→%.0f,%.0f z %.3f→%.3f" % [pick, v.building_at(lp.x, lp.y), v.dim, app.panel, hovered(), v.cam.x, v.cam.y, v.cam.tx, v.cam.ty, v.cam.zoom, v.cam.tzoom])
		var tip := find("HoverTip")
		check(tip != null, "garrison: hover tip for %s" % id)
		await click_at(pick)
		return await until(func(): return app.panel == id, 3.0, "click on the %s opens its panel" % id)
	return check(false, "a clickable point on the %s" % id)


func _garrison() -> bool:
	set_phase("base")
	var g: Dictionary = app.game
	# (The Field Manual is left unread here: the first battle opens it.)
	# Keyboard pan and wheel zoom on the camp.
	var v: Node2D = app.base_view
	var tx0: float = v.cam.tx
	await key_hold(KEY_D, 0.3)
	check(v.cam.tx > tx0 + 20, "garrison: D pans the camp (tx %.0f → %.0f)" % [tx0, v.cam.tx])
	await key_hold(KEY_A, 0.3)
	var z0: float = v.cam.tzoom
	var fp: Variant = free_point()
	await wheel_at(fp, true)
	check(v.cam.tzoom < z0, "garrison: wheel down zooms out (%.2f → %.2f)" % [z0, v.cam.tzoom])
	await wheel_at(fp, false)
	await settle(v.cam)
	# Barracks on the map: hire a recruit.
	if await click_building("barracks"):
		await wait(0.4)
		await shot("barracks")
		var silver: int = g.resources.silver
		var n: int = g.roster.size()
		if await press("Hire", "barracks: Hire"):
			await frames(3)
			check(app.game.roster.size() == n + 1 and app.game.resources.silver < silver, "hire a recruit (roster %d → %d, silver %d → %d)" % [n, app.game.roster.size(), silver, app.game.resources.silver])
		await press("Close", "barracks: Close")
		await until(func(): return app.panel == null and find("PanelOverlay") == null, 3.0, "panel closes")
	# Other buildings: close with Esc, with a click on the dimmed back, with Close.
	var how := 0
	for id in ["training", "armoury", "infirmary", "quartermaster", "command"]:
		if not await click_building(id):
			continue
		await wait(0.4)
		check(find("BuildingPanel_" + id) != null, "%s panel shown" % id)
		match how % 3:
			0:
				await key(KEY_ESCAPE)
			1:
				await click_at(Vector2(40, 1040))
			2:
				await press("Close", id + ": Close")
		how += 1
		await until(func(): return app.panel == null, 3.0, "%s panel closes" % id)
		await frames(2)
	# Clicks on the map are ignored behind an open panel.
	# Roster → a soldier → Close → Close.
	await press("Roster", "Roster")
	await until(func(): return app.panel == "roster" and find("RosterPanel") != null, 3.0, "roster opens")
	await wait(0.4)
	var so: Dictionary = app.game.roster[0]
	await press("Card_" + str(so.id), "roster: a soldier card")
	await until(func(): return app.soldier == so.id and find("SoldierDetail") != null, 3.0, "soldier detail opens")
	await wait(0.4)
	await shot("soldier")
	await press("Close", "soldier detail: Close", find("SoldierDetail"))
	await until(func(): return app.soldier == null, 3.0, "soldier detail closes")
	await press("Close", "roster: Close", find("RosterPanel"))
	await until(func(): return app.panel == null, 3.0, "roster closes")
	# Sound twice.
	var muted: bool = app.is_muted()
	await press("Sound", "top bar: Sound")
	check(app.is_muted() != muted, "Sound toggles mute (now %s)" % app.is_muted())
	await press("Sound", "top bar: Sound again")
	check(app.is_muted() == muted, "Sound toggles back")
	# F11 twice.
	await key(KEY_F11)
	await wait(1.0)
	check(app.is_fullscreen(), "F11: fullscreen")
	await shot("fullscreen")
	await key(KEY_F11)
	await wait(1.0)
	check(not app.is_fullscreen(), "F11 again: windowed")
	check(DisplayServer.window_get_size() == Vector2i(1920, 1080), "the window is back at 1920×1080 (%s)" % DisplayServer.window_get_size())
	await wait(0.3)
	# Esc menu: paused, Resume.
	await key(KEY_ESCAPE)
	await until(func(): return app.menu_open and find("PauseMenu") != null, 3.0, "Esc opens the pause menu")
	check(paused, "the world is paused behind the menu")
	await wait(0.4)
	await shot("pause_menu")
	await press("Resume", "menu: Resume")
	await until(func(): return not app.menu_open and not paused, 3.0, "Resume closes the menu")
	await shot("garrison")
	return true


# ---------------------------------------------------------------- prep

func _prep(n: int) -> bool:
	set_phase("prep")
	await press("PlanExpedition", "Plan Expedition")
	if not await until(func(): return app.screen == "prep" and find("PrepPanel") != null, 4.0, "the prep screen"):
		return false
	await wait(0.5)
	var prep: Node = screen_node()
	var army: Array = prep.army.duplicate()
	check(army.size() > 0, "a suggested army (%d squads)" % army.size())
	# Take a squad out of the army and put it back.
	if army.size() > 0:
		var id: String = army[-1]
		await press("Card_" + id, "prep: a squad card (out)")
		await frames(3)
		check(not screen_node().army.has(id), "the squad leaves the army")
		await press("Card_" + id, "prep: the squad card (in)")
		await frames(3)
		check(screen_node().army.has(id), "the squad rejoins the army")
	# Supplies: one more ration, one fewer, the quartermaster's advice.
	var k: String = DB.SUPPLY_ORDER[0]
	var before: int = screen_node().supplies[k]
	await press("Plus", "prep: + " + k, find("Supply_" + k))
	await frames(2)
	check(screen_node().supplies[k] == before + 1, "+ adds a %s (%d → %d)" % [k, before, screen_node().supplies[k]])
	await press("Minus", "prep: − " + k, find("Supply_" + k))
	await frames(2)
	check(screen_node().supplies[k] == before, "− takes it back")
	await press("Advice", "prep: Quartermaster's advice")
	await frames(2)
	await shot("prep_%d" % n)
	var mb: BaseButton = find("MarchOut")
	if not check(mb != null and not mb.disabled, "March Out enabled"):
		return false
	set_phase("campaign")
	await press("MarchOut", "March Out")
	if not await until(func(): return app.screen == "campaign" and app.game.get("expedition") != null and app.campaign_view != null, 6.0, "March Out starts the expedition"):
		return false
	await wait(0.5)
	return true


# ---------------------------------------------------------------- campaign

func hud() -> Control:
	return screen_node()


func dialog_kind() -> String:
	var h := hud()
	return h.dialog_kind() if h != null and h.has_method("dialog_kind") else ""


func _node_by_id(id: String) -> Dictionary:
	for n in app.game.expedition.nodes:
		if n.id == id:
			return n
	return {}


## Clicks a node of the campaign map (where the map itself resolves it).
func click_node(n: Dictionary) -> bool:
	var v: Node2D = app.campaign_view
	await until(func(): return not v.marching and v.intro == null, 20.0, "the march ends")
	await settle(v.cam, 3.0)
	for attempt in 3:
		var wx := Iso.iso_x(n.tx, n.ty)
		var wy := Iso.iso_y(n.tx, n.ty) - 30
		var pick: Variant = null
		for o in [Vector2.ZERO, Vector2(0, -20), Vector2(0, 20), Vector2(-25, 0), Vector2(25, 0)]:
			var s: Vector2 = v.cam.world_to_screen(wx + o.x, wy + o.y, v._w, v._h)
			var p := local_to_vp(v, s)
			if on_screen(p, 40) and not ui_blocks(p):
				var at: Variant = v.node_at(s.x, s.y)
				if at != null and at.id == n.id:
					pick = p
					break
		if pick == null:
			await pan_to(v, v.cam, wx, wy)
			await settle(v.cam)
			continue
		await move_mouse(pick)
		if not check(v.ui.get("hover") == n.id, "map: hover on %s (%s)" % [n.id, n.type]):
			var lp: Vector2 = v.get_global_transform_with_canvas().affine_inverse() * pick
			var at2: Variant = v.node_at(lp.x, lp.y)
			say("     at %s: node_at %s, hover %s, hovered control %s, cam %.0f,%.0f→%.0f,%.0f" % [pick, at2.id if at2 != null else "none", v.ui.get("hover"), hovered(), v.cam.x, v.cam.y, v.cam.tx, v.cam.ty])
		var card := find("NodeCard")
		check(card != null, "map: the node card shows on hover")
		var cur: String = app.game.expedition.current
		await click_at(pick)
		var ok := await until(func(): return app.game.get("expedition") == null or app.game.expedition.current != cur or app.screen != "campaign", 4.0, "click on %s marches there" % n.id)
		if not ok:
			var lp: Vector2 = v.get_global_transform_with_canvas().affine_inverse() * pick
			var at: Variant = v.node_at(lp.x, lp.y)
			say("     click at %s: node_at %s, hover %s, marching %s, intro %s, pending %s, can_march %s, hovered control %s" % [pick, at.id if at != null else "none", v.ui.get("hover"), v.marching, v.intro != null, app.game.expedition.get("pending"), Expedition.can_march(app.game, n.id), hovered()])
		return ok
	return check(false, "map: a clickable point on node %s" % n.id)


## Picks the next node: `want` types first (in order), else anything but the objective.
func pick_next(want: Array) -> Variant:
	var nxt: Array = Expedition.next_nodes(app.game.expedition)
	for t in want:
		for n in nxt:
			if n.type == t and Expedition.can_march(app.game, n.id):
				return n
	for n in nxt:
		if n.type != "objective" and Expedition.can_march(app.game, n.id):
			return n
	return nxt[0] if nxt.size() > 0 else null


## Answers the pending dialog through its buttons until none is left (or a battle starts).
func answer_dialogs(seen: Dictionary) -> bool:
	for i in 12:
		await frames(2)
		if app.screen != "campaign":
			return true
		var kind := dialog_kind()
		if kind == "":
			return true
		await wait(0.45)
		var d := find("PendingDialog")
		if not check(d != null, "dialog '%s' shown" % kind):
			return false
		if not seen.has(kind):
			await shot("dialog_" + kind)
		seen[kind] = true
		var p: Dictionary = app.game.expedition.pending
		match kind:
			"arrive", "scout":
				await press("Continue", kind + ": Continue", d)
			"event":
				if p.get("result") == null:
					var picked := false
					for b in H.buttons(d):
						if live(b) and str(b.name).begins_with("Choice") and not b.disabled:
							await click_control(b, "event: " + H.button_text(b).substr(0, 40))
							picked = true
							break
					check(picked, "event: a choice is available")
					await frames(3)
					check(app.game.expedition.get("pending") == null or app.game.expedition.pending.get("result") != null, "event: the choice has a result")
				else:
					await press("To arms!" if p.get("followBattle") != null else "Continue", "event: close", d)
			"camp":
				for nm in ["Watch", "Repair", "Rest"]:
					var b: BaseButton = find_button(nm, find("PendingDialog"))
					if b != null and not b.disabled:
						await click_control(b, "camp: " + nm)
						await frames(3)
				await press("Break camp", "camp: Break camp", find("PendingDialog"))
			"village":
				var b: BaseButton = find_button("Spot0", d)
				if b != null and not b.disabled:
					await click_control(b, "village: search a spot")
					await frames(3)
				await press("Move on", "village: Move on", find("PendingDialog"))
			"battle":
				return true
			"battleResult":
				var res: String = p.report.result
				await press("Retreat home" if res == "defeat" else "Continue", "battle result (%s)" % res, d)
				if res == "defeat":
					return true
			"complete":
				await press("Return to Amberfeld", "complete: Return to Amberfeld", d)
				return true
			_:
				return check(false, "unknown dialog kind " + kind)
		await frames(3)
	return check(dialog_kind() == "", "dialogs answered")


func _expedition_one() -> bool:
	set_phase("campaign")
	var v: Node2D = app.campaign_view
	# The first look sweeps from the host back to the company; then the map is the player's.
	await until(func(): return v.intro == null, 15.0, "the opening sweep of the map ends")
	await wait(0.3)
	await shot("campaign")
	# Keys pan, wheel zooms, Find army.
	var tx0: float = v.cam.tx
	await key_hold(KEY_D, 0.3)
	check(v.cam.tx > tx0 + 20, "map: D pans (tx %.0f → %.0f)" % [tx0, v.cam.tx])
	var fp: Variant = free_point()
	var z0: float = v.cam.tzoom
	await wheel_at(fp, true)
	check(v.cam.tzoom < z0, "map: wheel zooms out")
	await press("FindArmy", "map: Find army")
	await settle(v.cam)
	var seen := {}
	var fought := false
	var marches := 0
	while marches < 9 and app.screen == "campaign":
		await answer_dialogs(seen)
		if app.screen != "campaign" or app.game.get("expedition") == null:
			break
		if dialog_kind() == "battle":
			await shot("briefing")
			var manual_first: bool = not app.manual_seen()
			set_phase("battle")
			await press("To Battle", "briefing: To Battle", find("PendingDialog"))
			if not await until(func(): return app.screen == "battle" and app.battle_view != null, 8.0, "To Battle opens the battle"):
				return false
			if not await play_battle(manual_first):
				return false
			fought = true
			set_phase("campaign")
			await until(func(): return app.screen == "campaign", 30.0, "back on the map after the battle")
			await answer_dialogs(seen)
			if not full:
				break
			if battles == 1:
				# Save and quit to the title, then Continue from the save.
				if not await _save_quit_continue():
					return false
				v = app.campaign_view
			continue
		# Enough seen: home.
		if fought and seen.size() >= 4:
			break
		var want: Array = ["event", "camp", "village", "scout"] if fought else (["battle", "ambush", "event", "camp", "village", "scout"] if full else ["battle", "ambush"])
		var n: Variant = pick_next(want)
		if n == null:
			break
		if n.type == "objective":
			break
		say("     march to %s (%s)" % [n.id, n.type])
		if not await click_node(n):
			return false
		marches += 1
		await until(func(): return app.campaign_view == null or not app.campaign_view.marching, 20.0, "march animation")
		await frames(4)
	check(fought, "expedition 1: fought a battle (seen %s)" % [seen.keys()])
	if app.screen == "campaign":
		if not await retreat_home():
			return false
	return await report_and_home(1)


func retreat_home() -> bool:
	await press("RetreatHome", "map: Retreat home")
	await until(func(): return find("Confirm", hud()) != null, 3.0, "retreat confirmation")
	await wait(0.4)
	await shot("retreat_confirm")
	await press("PressOn", "confirm: Press on", find("Confirm", hud()))
	await until(func(): return find("Confirm", hud()) == null, 3.0, "Press on closes it")
	await press("RetreatHome", "map: Retreat home again")
	await until(func(): return find("Confirm", hud()) != null, 3.0, "retreat confirmation")
	await wait(0.4)
	await press("Retreat", "confirm: Retreat", find("Confirm", hud()))
	return await until(func(): return app.screen == "report", 5.0, "the report after the retreat")


func report_and_home(n: int) -> bool:
	set_phase("report")
	if not await until(func(): return app.screen == "report" and find("BackToAmberfeld") != null, 5.0, "report screen"):
		return false
	check(app.game.get("expedition") == null, "the expedition is over")
	await wait(0.6)
	await shot("report_%d" % n)
	await press("BackToAmberfeld", "report: Back to Amberfeld")
	set_phase("base")
	return await until(func(): return app.screen == "base" and app.base_view != null, 5.0, "back in the garrison")


func _save_quit_continue() -> bool:
	var ex: Dictionary = app.game.expedition
	var cur: String = ex.current
	var visited: int = ex.get("visited", []).size() if ex.get("visited") is Array else -1
	await key(KEY_ESCAPE)
	if not await until(func(): return app.menu_open and find("PauseMenu") != null, 3.0, "Esc on the map opens the menu"):
		return false
	await wait(0.3)
	await press("SaveQuit", "menu: Save and Quit to Title")
	if not await until(func(): return app.screen == "title" and find("Continue") != null, 5.0, "title with Continue"):
		return false
	set_phase("title")
	await wait(0.4)
	await shot("title_continue")
	await press("Continue", "title: Continue")
	set_phase("campaign")
	if not await until(func(): return app.screen == "campaign" and app.campaign_view != null, 6.0, "Continue resumes the expedition"):
		return false
	check(app.game.expedition.current == cur, "the saved expedition is back at %s" % cur)
	await wait(1.0)
	return true


# ---------------------------------------------------------------- second expedition

func _second_expedition() -> bool:
	# Field Manual from the top bar, a tab, back to the field.
	await press("FieldManual", "top bar: Field Manual")
	await until(func(): return app.manual != null and find("Manual") != null, 3.0, "Field Manual opens")
	await wait(0.4)
	await press("Tab_horde", "manual: The Horde tab")
	await frames(3)
	check(find("Tab_horde") != null, "manual: tabs rebuilt")
	await press("ToTheField", "manual: To the field")
	await until(func(): return app.manual == null, 3.0, "manual closes")
	if not await _prep(2):
		return false
	var seen := {}
	for i in 8:
		await answer_dialogs(seen)
		if app.screen != "campaign":
			break
		if dialog_kind() == "battle":
			set_phase("battle")
			await press("To Battle", "briefing: To Battle", find("PendingDialog"))
			if not await until(func(): return app.screen == "battle" and app.battle_view != null, 8.0, "To Battle"):
				return false
			if not await battle_then_retreat():
				return false
			set_phase("campaign")
			await until(func(): return app.screen == "campaign", 30.0, "back on the map after the retreat")
			await answer_dialogs(seen)
			break
		var n: Variant = pick_next(["battle", "ambush"])
		if n == null or n.type == "objective":
			break
		say("     march to %s (%s)" % [n.id, n.type])
		if not await click_node(n):
			return false
		await until(func(): return app.campaign_view == null or not app.campaign_view.marching, 20.0, "march animation")
		await frames(4)
	if app.screen == "campaign":
		if not await retreat_home():
			return false
	return await report_and_home(2)


func _restart() -> bool:
	set_phase("base")
	var old_size: int = app.game.roster.size()
	var old_cycle: int = app.game.cycle
	await key(KEY_ESCAPE)
	await until(func(): return app.menu_open, 3.0, "menu")
	await wait(0.3)
	await press("NewCompany", "menu: New Company", find("PauseMenu"))
	await until(func(): return find("Confirm") != null, 3.0, "New Company asks first")
	await wait(0.4)
	await shot("new_company_confirm")
	await press("OK", "confirm: OK", find("Confirm"))
	if not await until(func(): return app.screen == "base" and not app.menu_open, 5.0, "a new company"):
		return false
	await frames(3)
	check(app.game.roster.size() == 6 and app.game.cycle == 0 and app.game.get("expedition") == null, "the old company is replaced (roster %d → %d, expeditions %d → %d)" % [old_size, app.game.roster.size(), old_cycle, app.game.cycle])
	check(find("WelcomeModal") != null, "the welcome letter again")
	await press("ToWork", "welcome: To work")
	await frames(3)
	await shot("restart")
	return true


# ---------------------------------------------------------------- battle

func bv() -> Node2D:
	return app.battle_view


func bhud() -> Control:
	return screen_node()


## Deep copy of the battle for planning (its own RNG at the same state).
func clone_battle(live_b) -> Variant:
	var c = live_b.get_script().new(live_b.setup)
	for p in live_b.get_property_list():
		if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n: String = p.name
		if n == "objective" or n == "waves" or n == "ai_cache":
			continue
		var val = live_b.get(n)
		if n == "map" or n == "setup":
			c.set(n, val)
		elif n == "rng":
			var r := Rng.new(0)
			r.state = val.state
			c.set(n, r)
		elif val is Array or val is Dictionary:
			c.set(n, val.duplicate(true))
		else:
			c.set(n, val)
	c.drain()
	return c


## What the company's automation would do with this squad now.
func plan_for(uid: String) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var plan := _plan_for(uid)
	_excl_us += Time.get_ticks_usec() - t0
	return plan


func _plan_for(uid: String) -> Dictionary:
	var b = bv().b
	var o: Dictionary = b.objective
	var hold: Variant = null
	if o.kind == "hold" or o.kind == "survive":
		hold = {}
		for p in b.map.playerDeploy:
			hold[Grid.key(p.x, p.y)] = true
		var zone: Variant = b.map.get("zone")
		if zone != null:
			for p in zone:
				hold[Grid.key(p.x, p.y)] = true
	var c = clone_battle(b)
	var cu: Dictionary = c.unit(uid)
	var u: Dictionary = b.unit(uid)
	Ai.act_unit(c, cu, {"useStances": true, "hold": hold})
	var plan := {"move": null, "facing": null, "attack": null, "ability": null, "stance": null, "shout": null}
	var first_move := true
	var evs: Array = c.drain().filter(func(e): return e.get("uid") == uid)
	for e in evs:
		if e.get("uid") != uid:
			continue
		match str(e.t):
			"move":
				if first_move and not u.hasMoved:
					first_move = false
					var path: Array = e.path
					plan.move = {"x": int(path[-1].x), "y": int(path[-1].y)}
			"attack":
				if plan.attack == null and e.get("reaction") == null:
					plan.attack = e.target
					plan.ability = e.get("ability")
			"stance":
				if e.get("stance") != null:
					for a in u.abilities:
						if DB.ABILITIES[a].get("stance") == e.stance:
							plan.stance = a
			"shout":
				plan.shout = e.ability
	if plan.move != null:
		# Where the squad stands at the end and how it faces (the move may be cut short).
		plan.move = {"x": int(cu.x), "y": int(cu.y)} if cu.hasMoved else plan.move
		plan.facing = int(cu.facing)
		if plan.move.x == u.x and plan.move.y == u.y and plan.facing == u.facing:
			plan.move = null
	if plan.move != null:
		var occ: Variant = Grid.unit_at(b.units, plan.move.x, plan.move.y)
		if occ != null and occ.uid != uid:
			# The copy put the squad where another one stands: report how the copy differs.
			var diff: Array = []
			for lu in b.units:
				var cu2: Variant = null
				for x in c.units:
					if x.uid == lu.uid:
						cu2 = x
				if cu2 == null:
					diff.append("%s missing" % lu.uid)
				elif cu2.uid != uid and (cu2.x != lu.x or cu2.y != lu.y or cu2.status != lu.status):
					diff.append("%s live %d,%d %s copy %d,%d %s" % [lu.uid, lu.x, lu.y, lu.status, cu2.x, cu2.y, cu2.status])
			say("     plan for %s ends on %s's tile %s; copy events %s; differences %s" % [uid, occ.uid, plan.move, evs.map(func(e): return "%s %s" % [e.t, e.get("path", e.get("target", ""))]), diff])
	return plan


func _vs() -> Vector2:
	return Vector2(bv()._w, bv()._h)


func _to_screen(wx: float, wy: float) -> Vector2:
	var s := _vs()
	return bv().cam.world_to_screen(wx, wy, s.x, s.y)


## A view-local point on the squad's figures that the view resolves to it.
func unit_point(uid: String) -> Variant:
	var t0 := Time.get_ticks_usec()
	var p: Variant = _unit_point(uid)
	_excl_us += Time.get_ticks_usec() - t0
	return p


func _unit_point(uid: String) -> Variant:
	var view := bv()
	var v = view.views.get(uid)
	if v == null:
		return null
	var z: float = view.cam.zoom
	var base := _to_screen(Iso.iso_x(v.x, v.y), Iso.iso_y(v.x, v.y, v.h))
	for oy in [-30, -44, -18, -58, -6, 6]:
		for ox in [0, -16, 16, -30, 30]:
			var p: Vector2 = base + Vector2(ox, oy) * z
			var vp := local_to_vp(view, p)
			if not on_screen(vp, 30) or ui_blocks(vp):
				continue
			var rp: Dictionary = view.resolve_pointer(p.x, p.y)
			if rp.unit != null and rp.unit.uid == uid:
				return p
	return null


## A view-local point on tile t pointing toward `facing` (or its centre) that
## the view resolves to that empty tile.
func tile_point(t: Dictionary, facing: Variant) -> Variant:
	var t0 := Time.get_ticks_usec()
	var p: Variant = _tile_point(t, facing)
	_excl_us += Time.get_ticks_usec() - t0
	return p


func _tile_point(t: Dictionary, facing: Variant) -> Variant:
	var view := bv()
	var th: float = view._tile_h(t.x, t.y)
	var c := Vector2(Iso.iso_x(t.x, t.y), Iso.iso_y(t.x, t.y, th))
	var offs: Array = []
	if facing != null:
		var d: Dictionary = Grid.DIRS[facing]
		for m in [0.34, 0.27, 0.41, 0.2]:
			for side in [0.0, 0.08, -0.08]:
				var gx: float = d.x * m + (-d.y) * side
				var gy: float = d.y * m + d.x * side
				offs.append(Vector2((gx - gy) * 64.0, (gx + gy) * 32.0))
	offs.append(Vector2.ZERO)
	# Anywhere on the diamond, the far (upper) half first: it is the part a raised
	# tile or a squad in front leaves visible.
	for gy in [-0.3, -0.15, 0.0, 0.15, 0.3]:
		for gx in [-0.3, -0.15, 0.0, 0.15, 0.3]:
			offs.append(Vector2((gx - gy) * 64.0, (gx + gy) * 32.0))
	for o in offs:
		var p := _to_screen(c.x + o.x, c.y + o.y)
		var vp := local_to_vp(view, p)
		if not on_screen(vp, 30) or ui_blocks(vp):
			continue
		var rp: Dictionary = view.resolve_pointer(p.x, p.y)
		if rp.tile != null and rp.tile.x == t.x and rp.tile.y == t.y and rp.unit == null:
			return p
	return null


## Brings grid point (x, y) into the free middle of the screen.
func bring(x: float, y: float) -> void:
	var view := bv()
	var h: float = view._tile_h(x, y)
	await pan_to(view, view.cam, Iso.iso_x(x, y), Iso.iso_y(x, y, h), Vector2(_vs().x * 0.52, _vs().y * 0.52))
	await settle(view.cam, 1.5)


func idle() -> bool:
	var view := bv()
	return view == null or not is_instance_valid(view) or (not view.busy() and not view.rules_running())


func wait_idle(timeout := 60.0, what := "playback") -> bool:
	return await until(func(): return idle(), timeout, what)


## State of the view for failure reports.
func view_state(p: Variant = null) -> String:
	var view := bv()
	var s := "phase %s, busy %s (anims %d, queue %d, fx %s, task %d), selected %s, ability %s, cam %.0f,%.0f→%.0f,%.0f z %.2f" % [view.b.phase, view.busy(), view._anims.size(), view._queue.size(), view.fx.busy, view._task_id, view.ui.selected, view.ui.ability, view.cam.x, view.cam.y, view.cam.tx, view.cam.ty, view.cam.zoom]
	if p != null:
		var rp: Dictionary = view.resolve_pointer(p.x, p.y)
		var hv := hovered()
		s += ", at %s: tile %s unit %s, hovered control %s, hover %s" % [p, rp.tile, rp.unit.uid if rp.unit != null else null, hv.get_path() if hv != null else null, view.ui.hover]
	return s


func select_squad(uid: String) -> bool:
	var view := bv()
	if view.ui.selected == uid:
		return true
	await settle(view.cam, 1.5)
	for attempt in 3:
		var p: Variant = unit_point(uid)
		if p == null:
			var u: Dictionary = view.b.unit(uid)
			await bring(u.x, u.y)
			continue
		await move_mouse(local_to_vp(view, p))
		check(view.ui.hover.get("unit") == uid, "battle: hover on squad %s" % uid)
		await click_at(local_to_vp(view, p))
		await frames(2)
		if view.ui.selected == uid:
			return true
		say("     select %s missed: %s" % [uid, view_state(p)])
		await settle(view.cam, 1.5)
	return check(false, "battle: click selects squad %s (selected %s)" % [uid, view.ui.selected])


## Points at the tile (and its edge for the facing), cycles Q / E if needed, clicks.
func move_squad(uid: String, t: Dictionary, facing: Variant, use_keys: bool) -> bool:
	var view := bv()
	await settle(view.cam, 1.5)
	var u0: Dictionary = view.b.unit(uid)
	if u0.x == t.x and u0.y == t.y:
		return await turn_squad(uid, facing)
	var p: Variant = null
	for attempt in 3:
		p = tile_point(t, facing)
		if p != null:
			break
		await bring(t.x, t.y)
	if p == null:
		var th: float = view._tile_h(t.x, t.y)
		var cp := _to_screen(Iso.iso_x(t.x, t.y), Iso.iso_y(t.x, t.y, th))
		var occ: Variant = Grid.unit_at(view.b.units, t.x, t.y)
		var rp0: Dictionary = view.resolve_pointer(cp.x, cp.y)
		var seen_u: Variant = rp0.unit
		var seen_s := ""
		if seen_u != null:
			var sv = view.views[seen_u.uid]
			seen_s = "%s rules %d,%d %s, view %.2f,%.2f %s" % [seen_u.uid, seen_u.x, seen_u.y, seen_u.status, sv.x, sv.y, sv.status]
		return check(false, "battle: a clickable point on tile %s, h %s, on screen %s, UI over the centre %s, rules unit there %s, figure seen there %s, reachable %s (%s)" % [t, th, on_screen(local_to_vp(view, cp), 30), _stoppers_at(local_to_vp(view, cp)).map(func(c): return c.name), occ.uid if occ != null else null, seen_s, view._reach(view.b.unit(view.ui.selected)).has(Grid.key(t.x, t.y)) if view.ui.selected != null else "-", view_state()])
	await move_mouse(local_to_vp(view, p))
	await frames(2)
	var hv: Dictionary = view.ui.hover
	if not check(hv.get("dest") != null and hv.dest.x == t.x and hv.dest.y == t.y, "battle: hover previews the move to %d,%d" % [t.x, t.y]):
		say("     reachable %s; %s" % [view._reach(view.b.unit(uid)).has(Grid.key(t.x, t.y)), view_state(p)])
		return false
	if facing != null and hv.get("facing") != facing and hv.get("facings") is Array and hv.facings.has(facing):
		for i in 4:
			await key(KEY_E if use_keys or i > 0 else KEY_Q)
			await frames(2)
			if view.ui.hover.get("facing") == facing:
				used["qe"] = true
				break
	var want_f: Variant = view.ui.hover.get("facing")
	await click_at(local_to_vp(view, p))
	await frames(2)
	var u: Dictionary = view.b.unit(uid)
	var moved: bool = u.hasMoved or u.status != "active"
	check(moved, "battle: click moves %s to %d,%d" % [uid, t.x, t.y])
	if moved and u.x == t.x and u.y == t.y and want_f != null:
		check(u.facing == want_f, "battle: arrives facing %s as previewed (%s)" % [want_f, u.facing])
	await wait_idle(30.0, "move playback")
	return moved


## Turns the selected squad where it stands: point at the edge of its own tile, click.
func turn_squad(uid: String, facing: Variant) -> bool:
	var view := bv()
	var u: Dictionary = view.b.unit(uid)
	if facing == null:
		return false
	var th: float = view._tile_h(u.x, u.y)
	var c := Vector2(Iso.iso_x(u.x, u.y), Iso.iso_y(u.x, u.y, th))
	var d: Dictionary = Grid.DIRS[facing]
	var pick: Variant = null
	for m in [0.32, 0.28, 0.4, 0.24]:
		for side in [0.0, 0.1, -0.1]:
			var gx: float = d.x * m + (-d.y) * side
			var gy: float = d.y * m + d.x * side
			var p := _to_screen(c.x + (gx - gy) * 64.0, c.y + (gx + gy) * 32.0)
			var vp := local_to_vp(view, p)
			if not on_screen(vp, 30) or ui_blocks(vp):
				continue
			var rp: Dictionary = view.resolve_pointer(p.x, p.y)
			if rp.unit != null and rp.unit.uid == uid:
				pick = p
				break
		if pick != null:
			break
	if pick == null:
		say("     no point on %s's own tile edge toward %s" % [uid, facing])
		return false
	await move_mouse(local_to_vp(view, pick))
	await frames(2)
	var hv: Dictionary = view.ui.hover
	if not (hv.get("turn") == true and hv.get("facing") == facing):
		say("     pointing at the edge does not offer the turn (hover %s)" % [hv])
		return false
	await click_at(local_to_vp(view, pick))
	await frames(2)
	var uu: Dictionary = view.b.unit(uid)
	var ok: bool = uu.hasMoved and (uu.facing == facing or uu.status != "active")
	check(ok, "battle: click on the tile edge turns %s to face %s (%s)" % [uid, facing, uu.facing])
	used["turn"] = true
	await wait_idle(20.0, "turn playback")
	return ok


func attack_with(uid: String, target: String, ability: Variant) -> bool:
	var view := bv()
	await settle(view.cam, 1.5)
	if ability != null:
		var ab: Dictionary = DB.ABILITIES[ability]
		var list: Array = view.b.unit(uid).abilities.filter(func(a): return DB.ABILITIES[a].kind != "attack" or DB.ABILITIES[a].get("damageMult"))
		var idx: int = list.find(ability)
		if used.has("ability_key") or idx < 0 or idx > 3:
			await press("Ability_" + ability, "battle: ability button " + ab.name)
			used["ability_button"] = true
		else:
			await key(KEY_1 + idx)
			used["ability_key"] = true
		await frames(2)
		if not check(view.ui.ability == ability, "battle: %s armed (%s)" % [ab.name, view.ui.ability]):
			ability = null
	var p: Variant = null
	for attempt in 3:
		p = unit_point(target)
		if p != null:
			break
		var t: Dictionary = view.b.unit(target)
		await bring(t.x, t.y)
	if p == null:
		return check(false, "battle: a clickable point on enemy %s" % target)
	await move_mouse(local_to_vp(view, p))
	await frames(2)
	# The forecast that opens on the hover sits top right (as in the original):
	# a target under it is brought to the middle first.
	if ui_blocks(local_to_vp(view, p)):
		var t2: Dictionary = view.b.unit(target)
		await bring(t2.x, t2.y)
		p = unit_point(target)
		if p == null:
			return check(false, "battle: a clickable point on enemy %s away from the forecast" % target)
		await move_mouse(local_to_vp(view, p))
		await frames(2)
	var pv: Variant = view.ui.hover.get("preview")
	if pv == null or pv.target != target or not pv.legal:
		say("     no legal attack on %s from here (preview %s)" % [target, "none" if pv == null else str(pv.get("legal"))])
		if view.ui.ability != null:
			await click_at(local_to_vp(view, p), MOUSE_BUTTON_RIGHT)
		return false
	check(find("Forecast") != null, "battle: the attack forecast shows")
	var u: Dictionary = view.b.unit(uid)
	await click_at(local_to_vp(view, p))
	await frames(2)
	var acted: bool = view.b.unit(uid).hasActed or view.b.unit(uid).status != "active" or view.b.phase == "over"
	check(acted, "battle: click attacks %s" % target)
	if acted and ability != null:
		used["ability"] = true
	await wait_idle(30.0, "attack playback")
	return acted


func use_hud_ability(uid: String, ab_id: String, what: String) -> bool:
	var view := bv()
	if not await press("Ability_" + ab_id, "battle: %s button" % what):
		return false
	await frames(2)
	var u: Dictionary = view.b.unit(uid)
	var ok: bool = u.hasActed or u.get("stance") != null
	check(ok, "battle: %s used" % what)
	used["ability"] = true
	await wait_idle(20.0, what)
	return ok


func play_battle(first: bool) -> bool:
	battles += 1
	var view := bv()
	await frames(4)
	say("battle %d: %s (%s, %dx%d, %d enemy squads)" % [battles, view.b.setup.get("title", ""), view.b.map.get("name"), view.b.map.w, view.b.map.h, view.b.active("enemy").size()])
	if first:
		check(app.manual == "battle" and find("Manual") != null, "first battle: the Field Manual opens")
		await wait(0.5)
		await shot("battle_manual")
		await press("ToTheField", "manual: To the field")
		await until(func(): return app.manual == null, 3.0, "manual closes")
	await wait(0.8)
	await shot("battle_%d_deploy" % battles)
	if not check(view.b.phase == "deploy", "deployment first"):
		return false
	# Deployment: swap a squad onto a free deployment tile.
	var players: Array = view.b.active("player")
	var free: Variant = null
	for p in view.b.map.playerDeploy:
		if Grid.unit_at(view.b.units, p.x, p.y) == null:
			free = p
			break
	if first and free != null and players.size() > 0:
		var uid: String = players[0].uid
		if await select_squad(uid):
			var tp: Variant = tile_point(free, null)
			if tp != null:
				await click_at(local_to_vp(view, tp))
				await frames(2)
				var u: Dictionary = view.b.unit(uid)
				check(u.x == free.x and u.y == free.y, "deployment: click moves %s to %d,%d" % [uid, free.x, free.y])
	# Speed 2 for the rest.
	if float(view.speed) < 2.0:
		await press("Speed", "battle: speed toggle")
		check(float(view.speed) == 2.0, "battle speed 2 (%s)" % view.speed)
	await press("Begin", "battle: Begin Battle")
	if not await until(func(): return view.b.phase != "deploy", 5.0, "Begin starts the battle"):
		return false
	await wait_idle(60.0, "opening")
	var turn := 0
	while is_instance_valid(view) and view.b.phase != "over" and app.screen == "battle":
		turn += 1
		set_phase("battle")
		if not await until(func(): return not is_instance_valid(view) or view.b.phase == "player" and idle() or view.b.phase == "over", 240.0, "the company's turn %d" % turn):
			return false
		if not is_instance_valid(view) or view.b.phase == "over":
			break
		if turn > 40:
			return check(false, "battle ends within 40 turns")
		await player_turn(turn)
		if not is_instance_valid(view) or view.b.phase == "over":
			break
		if turn == 1:
			await shot("battle_%d_turn1" % battles)
		# End Turn: the button, or Enter.
		set_phase("battle-enemy")
		var t0: int = view.b.turn
		if turn % 2 == 1:
			await press("EndTurn", "battle: End Turn")
		else:
			await key(KEY_ENTER)
		if not await until(func(): return not is_instance_valid(view) or view.b.phase != "player" or view.rules_running() or view.b.turn != t0, 5.0, "End Turn hands over"):
			say("     " + view_state())
			return false
	set_phase("battle")
	if not is_instance_valid(view):
		return check(app.screen == "campaign", "battle closed")
	var res: Variant = view.b.get("result")
	say("battle %d over after %d turns: %s" % [battles, turn, res])
	await shot("battle_%d_end" % battles)
	check(not used.is_empty(), "battle exercised %s" % [used.keys()])
	return await until(func(): return app.screen == "campaign", 30.0, "the end plays and returns to the map")


func player_turn(turn: int) -> void:
	var view := bv()
	if turn == 1 and battles == 1:
		# Toggle the grid, hold Alt for the danger tiles, zoom, pan with keys.
		await key(KEY_G)
		check(view.ui.showGrid == false, "G hides the grid")
		await key(KEY_G)
		check(view.ui.showGrid == true, "G shows it again")
		_send(_key_event(KEY_ALT, true))
		await frames(4)
		check(view.ui.danger, "Alt held: danger tiles")
		await shot("battle_danger")
		_send(_key_event(KEY_ALT, false))
		await frames(3)
		check(not view.ui.danger, "Alt released")
		var fp: Variant = free_point()
		var z0: float = view.cam.tzoom
		await wheel_at(fp, false)
		check(view.cam.tzoom > z0, "wheel up zooms in")
		await wheel_at(fp, true)
		var tx0: float = view.cam.tx
		await key_hold(KEY_A, 0.25)
		check(view.cam.tx < tx0 - 10, "A pans the field")
		# Tab selects a squad.
		await key(KEY_TAB)
		check(view.ui.selected != null, "Tab selects a squad")
	var order: Array = view.b.active("player")
	JS.sort(order, func(a, c): return (0 if a.get("shot") != null else 1) - (0 if c.get("shot") != null else 1))
	for u0 in order:
		if not is_instance_valid(view) or view.b.phase != "player":
			return
		var u: Dictionary = view.b.unit(u0.uid)
		if u.status != "active" or u.done:
			continue
		await wait_idle(30.0, "before %s" % u.uid)
		if not await select_squad(u.uid):
			continue
		await settle(view.cam, 1.0)
		var plan := plan_for(u.uid)
		say("     %s %s at %d,%d: %s" % [u.uid, u.typeId, u.x, u.y, plan])
		if plan.shout != null:
			await use_hud_ability(u.uid, plan.shout, "shout " + str(plan.shout))
			continue
		if plan.move != null:
			var moved := await move_squad(u.uid, plan.move, plan.facing, turn % 2 == 0)
			if moved and not used.has("redo") and view.b.can_redo(u.uid).get("ok"):
				# Redo once: take the move back, then make it again.
				var back: Dictionary = view.b.move_records.get(u.uid, {})
				await key(KEY_BACKSPACE)
				await wait_idle(10.0, "redo")
				var uu: Dictionary = view.b.unit(u.uid)
				check(not uu.hasMoved and uu.x == back.get("x") and uu.y == back.get("y"), "Backspace takes the move back (%d,%d)" % [uu.x, uu.y])
				used["redo"] = true
				if view.ui.selected != u.uid:
					await select_squad(u.uid)
				await move_squad(u.uid, plan.move, plan.facing, true)
		if not is_instance_valid(view) or view.b.phase != "player":
			return
		u = view.b.unit(u.uid)
		if u.status != "active":
			continue
		var ability: Variant = plan.ability
		if plan.attack != null and not u.hasActed:
			if view.ui.selected != u.uid:
				await select_squad(u.uid)
			await attack_with(u.uid, plan.attack, ability)
		elif plan.stance != null and not u.hasActed:
			await use_hud_ability(u.uid, plan.stance, "stance " + str(plan.stance))
		elif not used.has("ability") and not u.hasActed and turn >= 2:
			for a in u.abilities:
				if DB.ABILITIES[a].kind == "stance" and view.b.morale_state(u) != "wavering":
					await use_hud_ability(u.uid, a, "stance " + a)
					break
		if not is_instance_valid(view) or view.b.phase != "player":
			return
		u = view.b.unit(u.uid)
		if u.status == "active" and not u.done:
			if view.ui.selected != u.uid:
				await select_squad(u.uid)
			if not used.has("done_button"):
				await press("Done", "battle: Done")
				used["done_button"] = true
			else:
				await key(KEY_SPACE)
			await frames(2)
			check(view.b.unit(u.uid).done, "squad %s done" % u.uid)
		await wait_idle(30.0, "after %s" % u.uid)


func battle_then_retreat() -> bool:
	battles += 1
	var view := bv()
	await frames(4)
	say("battle %d: %s — to be left by the Retreat button" % [battles, view.b.setup.get("title", "")])
	await wait(0.6)
	await press("Begin", "battle: Begin Battle")
	await until(func(): return view.b.phase != "deploy", 5.0, "Begin")
	await until(func(): return view.b.phase == "player" and idle() or view.b.phase == "over", 120.0, "first turn")
	if view.b.phase == "over":
		return true
	await press("Retreat", "battle: Retreat")
	await until(func(): return find("Confirm", bhud()) != null, 3.0, "retreat confirmation")
	await wait(0.4)
	await shot("battle_retreat_confirm")
	# Esc closes it, then again and withdraw.
	await key(KEY_ESCAPE)
	await until(func(): return find("Confirm", bhud()) == null, 3.0, "Esc closes the confirmation")
	check(not app.menu_open, "Esc on the confirmation does not open the menu")
	await press("Retreat", "battle: Retreat again")
	await until(func(): return find("Confirm", bhud()) != null, 3.0, "retreat confirmation")
	await wait(0.4)
	await press("Withdraw", "confirm: Withdraw")
	await until(func(): return view.b.phase == "over" or not is_instance_valid(view), 5.0, "the company withdraws")
	if is_instance_valid(view):
		check(view.b.get("result") == "retreat", "battle result: retreat (%s)" % view.b.get("result"))
	return await until(func(): return app.screen == "campaign", 30.0, "back on the map")


# ---------------------------------------------------------------- last stand (debug start)

func _last_stand() -> bool:
	set_phase("laststand-load")
	# Started through the debug API (no expedition needed); played by input.
	var t0 := Time.get_ticks_usec()
	app.debug_test_battle("last_stand", {"seed": 7, "night": true, "darkness": true})
	var t1 := Time.get_ticks_usec()
	say("last stand opens in %.0f ms" % ((t1 - t0) / 1000.0))
	await until(func(): return app.screen == "battle" and app.battle_view != null, 5.0, "last stand opens")
	await frames(3)
	var view := bv()
	set_phase("laststand-deploy")
	await wait(2.0)
	check(view.b.map.get("scale") == "large", "a large map with a minimap")
	await shot("laststand_open")
	var r: Dictionary = view.minimap_rect()
	# No HUD control over any part of the minimap.
	var over := {}
	for fx in [0.05, 0.3, 0.5, 0.7, 0.95]:
		for fy in [0.05, 0.35, 0.65, 0.95]:
			for c in _stoppers_at(local_to_vp(view, Vector2(r.x + r.w * fx, r.y + r.h * fy))):
				over[str(c.get_path())] = true
	check(over.is_empty(), "no HUD control takes clicks over the minimap %s (%s)" % [r, over.keys()])
	# Zoomed in, the camera has room to move: click the minimap's far corner.
	var fp0: Variant = free_point()
	for i in 6:
		await wheel_at(fp0, false)
	await settle(view.cam, 2.0)
	var mp := local_to_vp(view, Vector2(r.x + r.w * 0.85, r.y + r.h * 0.2))
	await move_mouse(mp)
	var hv := hovered()
	check(hv == null or not ui_blocks(mp), "nothing of the HUD under the pointer on the minimap at %s (%s)" % [mp, hv.get_path() if hv != null else "none"])
	var cx: float = view.cam.tx
	var cy: float = view.cam.ty
	await click_at(mp)
	await frames(2)
	check(absf(view.cam.tx - cx) + absf(view.cam.ty - cy) > 50, "minimap click moves the camera (%.0f,%.0f → %.0f,%.0f)" % [cx, cy, view.cam.tx, view.cam.ty])
	await wait(1.0)
	await shot("laststand_minimap")
	var mp2 := local_to_vp(view, Vector2(r.x + r.w * 0.5, r.y + r.h * 0.5))
	await click_at(mp2)
	await wait(1.0)
	if not full:
		await key(KEY_ESCAPE)
		await until(func(): return app.menu_open, 3.0, "menu")
		await press("SaveQuit", "menu: Save and Quit to Title")
		set_phase("title")
		return await until(func(): return app.screen == "title", 5.0, "title")
	await press("Begin", "last stand: Begin Battle")
	set_phase("laststand-play")
	await until(func(): return view.b.phase == "player" and idle() or view.b.phase == "over", 240.0, "last stand turn 1")
	# Two turns of the company played by clicks, then the horde's turns.
	for turn in 2:
		if view.b.phase != "player":
			break
		await player_turn(turn + 1)
		if view.b.phase != "player":
			break
		await press("EndTurn", "last stand: End Turn")
		set_phase("laststand-enemy")
		await until(func(): return view.b.phase == "player" and idle() or view.b.phase == "over", 240.0, "last stand enemy turn")
		set_phase("laststand-play")
	say("last stand: %d enemy squads on the field after %d turns" % [view.b.active("enemy").size(), view.ui.turn])
	# The whole field in view.
	set_phase("laststand-zoomed-out")
	var fp: Variant = free_point()
	for i in 10:
		await wheel_at(fp, true)
	await wait(2.0)
	await shot("laststand_field")
	set_phase("laststand-play")
	await key(KEY_ESCAPE)
	await until(func(): return app.menu_open, 3.0, "menu")
	await press("SaveQuit", "menu: Save and Quit to Title")
	set_phase("title")
	await until(func(): return app.screen == "title", 5.0, "title")
	await press("Continue", "title: Continue")
	set_phase("base")
	return await until(func(): return app.screen == "base", 5.0, "Continue: the garrison")
