## Live-tree integration check of the UI shell: runs scenes/main.tscn with real
## frames and clicks through the game by pressing the actual buttons —
## title → New Company → welcome → manual → roster → soldier → Esc menu →
## each building → prep → March Out → the 3D battle → Begin Battle → Retreat →
## Withdraw → report → base →
## a test battle. Logged errors are collected and listed by file. Works headless:
##   tools/godot.sh --headless --path . -s res://tests/visual/ui_flow_check.gd
## Exit code 0 when every step passed and no error came from the UI shell
## (scripts/ui outside the HUD files, scripts/app).
extends SceneTree

class Catcher extends Logger:
	var mutex := Mutex.new()
	var errors: Array = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var where := file
		for bt in script_backtrace:
			if bt.get_frame_count() > 0:
				where = bt.get_frame_file(0)
				line = bt.get_frame_line(0)
				break
		mutex.lock()
		errors.append({"file": where, "line": line, "msg": rationale if rationale != "" else code})
		mutex.unlock()


var catcher := Catcher.new()
var app: Node
var main: Node
var failures: Array = []
var steps := 0


func _initialize() -> void:
	OS.add_logger(catcher)
	_run.call_deferred()


func _frames(n := 3) -> void:
	for i in n:
		await process_frame


func check(cond: bool, what: String) -> void:
	steps += 1
	if not cond:
		failures.append(what)
		print("FAIL ", what)
	else:
		print("ok   ", what)


func _ui() -> Control:
	return main.get_node("UI/Root")


func _find(name: String) -> Node:
	for n in _ui().find_children(name, "", true, false):
		if not n.is_queued_for_deletion() and (not (n is CanvasItem) or (n as CanvasItem).is_visible_in_tree()):
			return n
	return null


func press(name: String) -> bool:
	var b := _find(name)
	if b == null:
		check(false, "button %s present" % name)
		return false
	if b is BaseButton and (b as BaseButton).disabled:
		check(false, "button %s enabled" % name)
		return false
	b.emit_signal("pressed")
	return true


func key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	var r := e.duplicate()
	r.pressed = false
	Input.parse_input_event(r)


func _run() -> void:
	app = root.get_node("App")
	app.save_path = "user://ui_flow_check_save.json"
	if FileAccess.file_exists(app.save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(app.save_path))
	var Prefs = load("res://scripts/core/prefs.gd")
	var seen: Variant = Prefs.prefs().get("manualSeen", false)
	Prefs.set_pref("manualSeen", true)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(8)
	check(app.screen == "title", "boots to the title")
	check(_find("Continue") == null, "no Continue without a save")
	press("NewCompany")
	await _frames()
	check(app.screen == "base", "New Company opens the garrison")
	check(app.base_view != null, "the camp view is shown")
	check(_find("WelcomeModal") != null, "the welcome letter on the first visit")
	press("ToWork")
	await _frames()
	check(_find("WelcomeModal") == null and app.game.flags.welcome, "welcome closed")
	press("FieldManual")
	await _frames()
	check(app.manual == "base" and _find("Manual") != null, "Field Manual opens")
	press("Tab_horde")
	await _frames()
	press("ToTheField")
	await _frames()
	check(app.manual == null and _find("Manual") == null, "manual closed")
	press("Roster")
	await _frames()
	check(app.panel == "roster" and _find("RosterPanel") != null, "roster panel")
	var card := _find("Card_" + app.game.roster[0].id)
	if card != null:
		card.emit_signal("pressed")
	await _frames()
	check(app.soldier == app.game.roster[0].id and _find("SoldierDetail") != null, "soldier detail")
	key(KEY_ESCAPE)
	await _frames()
	check(app.soldier == null, "Esc closes the soldier detail")
	key(KEY_ESCAPE)
	await _frames()
	check(app.panel == null, "Esc closes the panel")
	key(KEY_ESCAPE)
	await _frames()
	check(app.menu_open and _find("PauseMenu") != null and paused, "Esc opens the pause menu (world paused)")
	key(KEY_ESCAPE)
	await _frames()
	check(not app.menu_open and not paused, "Esc closes it")
	for id in ["barracks", "command", "training", "armoury", "infirmary", "quartermaster", "memorial"]:
		app.open_panel(id)
		await _frames(2)
		check(_find("Close") != null, "panel %s open" % id)
		press("Close")
		await _frames(2)
		check(app.panel == null, "panel %s closes" % id)
	app.open_panel("barracks")
	await _frames()
	var silver: int = app.game.resources.silver
	press("Hire")
	await _frames()
	check(app.game.roster.size() == 7 and app.game.resources.silver < silver, "hire a recruit")
	press("Close")
	await _frames()
	press("Sound")
	await _frames()
	var muted: bool = app.is_muted()
	press("Sound")
	check(app.is_muted() != muted, "sound toggles")
	press("PlanExpedition")
	await _frames(4)
	check(app.screen == "prep" and _find("PrepPanel") != null, "Plan the Expedition")
	press("Advice")
	await _frames()
	press("MarchOut")
	await _frames(6)
	check(app.screen == "battle" and app.game.expedition != null, "March Out takes the company onto the field")
	var hud := main.get_node("UI/Root/Screen").get_child(0)
	check(hud.name == "Screen_battle", "battle screen node")
	print("     battle view: ", app.battle_view, "  hud: ", hud.get_script().resource_path if hud.get_script() else "(none)")
	check(press("Begin"), "Begin Battle")
	var v: Node = app.battle_view
	for i in 900:
		if v.b.phase == "player" and not v.ui.busy:
			break
		await _frames(1)
	check(v.b.phase == "player" and not v.ui.busy, "the company's turn")
	check(press("Retreat"), "Retreat")
	await _frames()
	check(press("Withdraw"), "Withdraw")
	for i in 600:
		if app.screen == "report":
			break
		await _frames(1)
	check(app.screen == "report" and _find("BackToAmberfeld") != null, "report after the return")
	press("BackToAmberfeld")
	await _frames(4)
	check(app.screen == "base", "back to Amberfeld")
	press("Menu")
	await _frames(3)
	check(app.screen == "title" and _find("Continue") != null, "Menu goes to the title, Continue offered")
	press("Continue")
	await _frames(4)
	check(app.screen == "base", "Continue")
	app.debug_test_battle({"seed": 3})
	await _frames(8)
	check(app.screen == "battle", "a test battle")
	var bh := main.get_node("UI/Root/Screen").get_child(0)
	print("     battle view: ", app.battle_view, "  hud: ", bh.get_script().resource_path if bh.get_script() else "(none)")
	app.go_base()
	await _frames(4)
	Prefs.set_pref("manualSeen", seen)
	# Report.
	var mine := 0
	var by_file := {}
	for e in catcher.errors:
		var f: String = e.file
		by_file[f] = by_file.get(f, 0) + 1
		var hud_file := f.contains("/ui/hud_") or f.contains("battle_hud")
		if (f.contains("res://scripts/ui/") and not hud_file) or f.contains("res://scripts/app/"):
			mine += 1
			print("UI ERROR %s:%d %s" % [f, e.line, e.msg])
	print("")
	print("errors by file: ", by_file)
	print("==== %d steps, %d failed, %d errors from the UI shell, %d errors elsewhere ====" % [steps, failures.size(), mine, catcher.errors.size() - mine])
	quit(0 if failures.is_empty() and mine == 0 else 1)
