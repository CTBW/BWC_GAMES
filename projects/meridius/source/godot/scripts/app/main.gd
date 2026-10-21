## Root of the running game (scenes/main.tscn). Port of src/ui/App.tsx and
## src/main.tsx: boots (loading screen), hosts the active world view, shows the
## screen for `App.screen` and the overlays (Field Manual, pause menu), applies
## the UI theme, F11 fullscreen, Esc.
##
## Tree:
##   Main (Control, theme)                 this script
##     World (Node2D)                      App.world_host: the base / campaign / battle view
##     UI (CanvasLayer 10, always processes)
##       Root (Control, theme)             full rect, ignores the mouse
##         Screen                          the current screen (or HUD)
##         Overlays                        manual, pause menu
##
## Screens: title, base, prep, report (scripts/ui/screens/*), loading. For
## "campaign" and "battle" the HUD scripts of the second UI agent are used when
## they exist: scripts/ui/campaign_hud.gd and scripts/ui/battle_hud.gd. Contract
## for a HUD: `extends Control`; created with `.new()`, then `setup(view)` (the
## App.campaign_view / App.battle_view node, may be null) when it has that
## method, full-rect anchors, added under Screen (inherits the theme). It reads
## App and subscribes to App.changed / the view itself. A new HUD is made when
## the screen or the view instance changes.
##
## Command line (after `--`): `--newgame [--seed=N]` starts a new company at once
## (the original's `?newgame&seed=`); `--smoke` runs scripts/qa/smoke.gd `run(main)`
## (deferred, when that file exists).
## Esc closes the topmost overlay (confirm, manual, menu, soldier, panel); when
## nothing is open it opens the pause menu (in battle only while no ability is armed,
## which Esc cancels first).
extends Control

const ThemeBuilder = preload("res://scripts/ui/theme_builder.gd")
const Deps = preload("res://scripts/ui/deps.gd")
const UI = preload("res://scripts/ui/ui.gd")

const SCREENS := {
	"loading": "res://scripts/ui/screens/loading_screen.gd",
	"title": "res://scripts/ui/screens/title_screen.gd",
	"base": "res://scripts/ui/screens/base_screen.gd",
	"prep": "res://scripts/ui/screens/prep_screen.gd",
	"report": "res://scripts/ui/screens/report_screen.gd",
}
const MANUAL := "res://scripts/ui/screens/manual.gd"
const MENU := "res://scripts/ui/screens/pause_menu.gd"
const SMOKE := "res://scripts/qa/smoke.gd"
## Loaded (and kept) behind the loading screen, so the first expedition and the
## first battle do not stop to load and compile their scripts: the battle view,
## its HUD and the battle rules alone cost ~0.75 s on the first battle.
## Deps keys first, then the screens main.gd loads by path.
const WARM_DEPS := ["setup", "battle", "ai", "expedition", "battle_view_scene", "battle_hud", "campaign_view_scene", "campaign_hud"]

var world: Node2D
var ui_root: Control
var screen_host: Control
var overlay_host: Control
var _screen_key := ""
var _screen: Control = null
var _screen_view: Node = null
var _manual: Control = null
var _menu: Control = null
## Scripts warmed at boot (held so they stay loaded).
var _warm: Array = []


func _ready() -> void:
	get_window().title = "Meridius"
	theme = ThemeBuilder.theme()
	# Native tooltip popups and subwindows take their theme from the window.
	get_window().theme = theme
	world = $World
	ui_root = $UI/Root
	ui_root.theme = theme
	screen_host = $UI/Root/Screen
	overlay_host = $UI/Root/Overlays
	App.world_host = world
	App.changed.connect(_refresh)
	_refresh()
	_boot.call_deferred()
	# Automated self-test of an exported build (the lead's scripts/qa/smoke.gd).
	if OS.get_cmdline_user_args().has("--smoke") and ResourceLoader.exists(SMOKE):
		_smoke.call_deferred()


func _smoke() -> void:
	load(SMOKE).run(self)


func _boot() -> void:
	App.screen = "loading"
	App.load_progress = 0.0
	App.emit_changed()
	await get_tree().process_frame
	# Warm the views, HUDs, rules and screens the game opens later (one per frame,
	# so the loading screen counts up).
	var steps := warm_steps()
	for i in steps.size():
		var k: String = steps[i]
		if Deps.PATHS.has(k):
			Deps.mod(k)
		elif ResourceLoader.exists(k):
			_warm.append(load(k))
		App.load_progress = float(i + 1) / (steps.size() + 2)
		App.emit_changed()
		await get_tree().process_frame
	await _warm_battle()
	App.load_progress = 1.0
	var args := OS.get_cmdline_user_args()
	if args.has("--newgame"):
		var seed := 1234
		for a in args:
			if a.begins_with("--seed="):
				seed = int(a.substr(7))
		App.new_game(seed)
	else:
		App.go_title()


## What the loading screen loads: Deps keys and script paths.
static func warm_steps() -> Array:
	var steps: Array = WARM_DEPS.duplicate()
	steps.append_array(SCREENS.values())
	steps.append_array([MANUAL, MENU])
	return steps


## Draws a small battle once in a hidden viewport: the battle's shaders compile
## and its figure atlases load now instead of on the first battle's first frame
## (~190 ms). Its own game and battle; nothing of the App's state is touched.
func _warm_battle() -> void:
	var Game = Deps.game()
	var Setup = Deps.setup()
	var Battle = Deps.battle()
	var Soldier = Deps.soldier()
	if Game == null or Setup == null or Battle == null or Soldier == null or not Deps.has("battle_view"):
		return
	var g: Dictionary = Game.new_game(1)
	var army: Array = []
	for so in g.roster:
		army.append(Soldier.soldier_to_unit(so))
	var roll: Dictionary = Setup.roll_encounter("raiding_party", Deps.rng().new(1), 2)
	var b = Battle.new(Setup.build_battle(roll, army, {"survivalBonus": 0}))
	var vp := SubViewport.new()
	vp.name = "WarmBattle"
	vp.size = Vector2i(480, 270)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var v := Deps.instance("battle_view")
	v.setup(b)
	vp.add_child(v)
	for i in 2:
		await get_tree().process_frame
	remove_child(vp)
	vp.queue_free()


func _make_screen(key: String) -> Control:
	var c: Control = null
	if SCREENS.has(key):
		c = load(SCREENS[key]).new()
	elif key == "battle" or key == "campaign":
		var hud := Deps.instance(key + "_hud")
		if hud is Control:
			c = hud
			if c.has_method("setup"):
				c.setup(_view_for(key))
	if c == null:
		c = Control.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.name = "Screen_" + key
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


func _view_for(key: String) -> Node:
	var v: Node = App.battle_view if key == "battle" else (App.campaign_view if key == "campaign" else null)
	return v if v != null and is_instance_valid(v) else null


func _refresh() -> void:
	if not is_inside_tree():
		return
	var key := App.screen
	var view := _view_for(key)
	if key != _screen_key or _screen == null or not is_instance_valid(_screen) or view != _screen_view:
		if _screen != null and is_instance_valid(_screen):
			screen_host.remove_child(_screen)
			_screen.queue_free()
		_screen = _make_screen(key)
		_screen_key = key
		_screen_view = view
		screen_host.add_child(_screen)
	elif _screen.has_method("refresh") and not (key == "battle" or key == "campaign"):
		# The HUDs subscribe to App.changed and their view themselves.
		_screen.refresh()
	_sync_manual()
	_sync_menu()


func _sync_manual() -> void:
	if App.manual != null and (_manual == null or not is_instance_valid(_manual)):
		_manual = load(MANUAL).make(str(App.manual), func(): App.open_manual(null))
		overlay_host.add_child(_manual)
		overlay_host.move_child(_manual, 0)
	elif App.manual == null and _manual != null:
		if is_instance_valid(_manual):
			_manual.queue_free()
		_manual = null


func _sync_menu() -> void:
	if App.menu_open and (_menu == null or not is_instance_valid(_menu)):
		_menu = load(MENU).new()
		overlay_host.add_child(_menu)
	elif not App.menu_open and _menu != null:
		if is_instance_valid(_menu):
			_menu.queue_free()
		_menu = null
	elif _menu != null and is_instance_valid(_menu) and _menu.has_method("refresh"):
		_menu.refresh()
	get_tree().paused = App.menu_open


func _input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.is_echo():
		return
	if e.is_action("toggle_fullscreen", true):
		App.toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	if e.is_action("cancel", true) and InputMap.event_is_action(e, "cancel", true):
		if _escape():
			get_viewport().set_input_as_handled()


## Closes the topmost overlay or opens the menu. Returns whether Esc was used.
func _escape() -> bool:
	var confirms := ui_root.find_children("Confirm", "", true, false)
	for c in confirms:
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			var cancel: Variant = c.get_meta("on_cancel", null)
			if cancel is Callable:
				(cancel as Callable).call()
			else:
				c.queue_free()
			return true
	if App.manual != null:
		App.open_manual(null)
		return true
	if App.menu_open:
		App.open_menu(false)
		return true
	if App.screen == "loading" or App.screen == "title":
		return false
	if App.soldier != null:
		if _screen != null and _screen.has_method("close_soldier"):
			_screen.close_soldier()
		else:
			App.open_soldier(null)
		return true
	if App.panel != null:
		App.open_panel(null)
		return true
	if App.screen == "battle" and App.battle_view != null and is_instance_valid(App.battle_view):
		var ui: Variant = App.battle_view.get("ui")
		if ui is Dictionary and ui.get("ability") != null:
			return false # the battle view cancels the armed ability
	App.open_menu(true)
	return true
