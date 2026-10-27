## Windowed captures of the UI screens for comparison with the original's
## screenshots (projects/meridius/review). Run with a window at 1920×1080:
##   tools/godot.sh --path . --resolution 1920x1080 -s res://tests/visual/ui_capture.gd -- [shot ...]
## Shots (default: all): title base welcome barracks roster soldier memorial command
##   training armoury infirmary quartermaster manual prep report menu
## PNGs go to tests/visual/out/ui-<shot>.png. Uses its own save file.
extends SceneTree

const OUT := "res://tests/visual/out"
const ALL := ["title", "welcome", "base", "barracks", "roster", "soldier", "memorial", "command", "training",
	"armoury", "infirmary", "quartermaster", "manual", "prep", "report", "menu",
	"hover", "tooltip", "tip", "confirm", "barracks2", "soldier2", "roster2", "infirmary2", "prep2", "memorial2", "battle"]

var app: Node
var main: Node


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(6)
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := "%s/ui-%s.png" % [OUT, name]
	img.save_png(path)
	print("shot ", ProjectSettings.globalize_path(path), " ", img.get_size())


func _run() -> void:
	app = root.get_node("App")
	app.save_path = "user://capture_save.json"
	var Prefs = load("res://scripts/core/prefs.gd")
	Prefs.set_pref("manualSeen", true)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(8)
	var shots: Array = Array(OS.get_cmdline_user_args())
	if shots.is_empty():
		shots = ALL
	# A fixed company: seed 1234, welcome read, a few changes for richer panels.
	app.game = load("res://scripts/meta/game.gd").new_game(1234)
	app.save()
	for shot in shots:
		await _prepare(shot)
		await _shot(shot)
	quit(0)


## A synthetic mouse move (hover, tooltips).
func _move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = Vector2(1, 0)
	Input.parse_input_event(e)
	await _frames(3)


func _reset_overlays() -> void:
	for c in main.find_children("Confirm", "", true, false):
		c.queue_free()
	app.panel = null
	app.soldier = null
	app.manual = null
	app.menu_open = false


## A company after a hard expedition: thinned squads, injuries, wounds, low morale, the fallen.
func _roughen() -> void:
	var g: Dictionary = app.game
	if g.get("_rough"):
		return
	var r: Array = g.roster
	r[0].men = 4
	r[0].hp = mini(r[0].hp, 100)
	r[0].injuries = ["gashed_arm"]
	r[0].wounded = 2
	r[1].men = 2
	r[1].hp = mini(r[1].hp, 50)
	r[1].morale = 20
	r[2].men = 5
	r[3].armorCondition = 0.55
	r[3].promoted = true
	r[4].injured = true
	g.resources.silver = 400
	if g.fallen.is_empty():
		g.fallen.append({"name": "Ulf Ulfsson", "typeId": "spearman", "level": 2, "kills": 3, "battles": 4, "cause": "Cut down at Elk Hollow", "cycle": 1})
	g._rough = true


func _prepare(shot: String) -> void:
	_reset_overlays()
	if shot.ends_with("2"):
		_roughen()
		shot = shot.substr(0, shot.length() - 1)
	var g: Dictionary = app.game
	if g.get("flags") == null:
		g.flags = {}
	g.flags.welcome = shot != "welcome"
	match shot:
		"title":
			app.save()
			app.go_title()
		"welcome", "base":
			app.go_base()
		"barracks", "command", "training", "armoury", "infirmary", "quartermaster", "memorial", "roster":
			app.go_base()
			app.open_panel(shot)
		"soldier":
			app.go_base()
			app.open_panel("roster")
			app.open_soldier(g.roster[0].id)
		"manual":
			app.go_base()
			app.open_manual("squads")
		"prep":
			app.go_base()
			app.go_prep()
		"report":
			app.go_base()
			if app.game.get("lastReport") == null:
				app.debug_auto_prepare(1)
				app.debug_settle_battle("victory")
			else:
				app.report = app.game.lastReport
				app.screen = "report"
				app.emit_changed()
		"menu":
			app.go_base()
			app.open_menu(true)
		"hover":
			app.go_base()
			await _frames(2)
			if app.base_view != null:
				app.base_view.ui.hover = "barracks"
		"tooltip":
			app.go_base()
			await _frames(3)
			var b: Control = main.find_child("Sound", true, false)
			await _move(b.get_global_rect().get_center())
			await create_timer(1.4).timeout
		"tip":
			app.go_base()
			app.open_panel("barracks")
			await create_timer(0.6).timeout
			var b: Control = main.find_child("PlusOne", true, false)
			if b != null:
				await _move(b.get_global_rect().get_center() + Vector2(-3, 0))
				await _move(b.get_global_rect().get_center())
		"confirm":
			app.go_title()
			await _frames(3)
			main.find_child("NewCompany", true, false).emit_signal("pressed")
		"battle":
			app.go_base()
			app.debug_auto_prepare(5)
	app.emit_changed()
	await _frames(4)
