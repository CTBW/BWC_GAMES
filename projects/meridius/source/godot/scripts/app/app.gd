## Game flow and state (autoload "App"). Port of src/ui/store.ts (AppStore).
##
## STATE (read freely; change only through the methods)
##   game: Dictionary|null      GameState (scripts/meta/game.gd), the save
##   screen: String             "loading" | "title" | "base" | "prep" | "campaign" | "battle" | "report"
##   panel: String|null         open base panel: building id | "roster" | "memorial"
##   soldier: String|null       roster id shown in the soldier detail overlay
##   manual: String|null        open Field Manual page id
##   menu_open: bool            the pause/menu overlay (Godot addition; Esc / menu)
##   report: Dictionary|null    ExpeditionReport shown by the report screen
##   battle_info: Dictionary|null  {title, objective} of the expedition battle being fought
##   battle                     the Battle (scripts/rules/battle.gd) of the current battle
##   base_view / campaign_view / battle_view: Node|null   the active world views
##   load_progress: float       0..1 while loading
##   version: int               bumped by every change
## SIGNAL
##   changed                    after every change (screens re-render on it)
## FLOW (store.ts names in snake_case)
##   new_game(seed = null), continue_game(), go_title(), go_base(), open_panel(id|null),
##   open_manual(page|null), open_soldier(id|null), go_prep(),
##   launch(campaign_id, army: Array, supplies: Dictionary, cost: int), go_campaign(),
##   click_node(id), dismiss(), go_home("success"|"retreat"), start_battle(), finish_battle(),
##   open_menu(bool), toggle_mute(), toggle_fullscreen(), quit_to_title() (save, then title)
##   commit() = save() + emit_changed(); emit_changed(); sfx(name)
## SAVES  user://meridius_save.json (`save_path`): the GameState as JSON, the shape
##   of the original's localStorage save, written by Game.to_save_json and read by
##   Game.from_save_json (version must equal Game.SAVE_VERSION; then migrate_save).
##   has_save(), save(), load_save() -> bool
##   use_views := true   false: no world views are created (store-only tests).
##   manual_seen() / mark_manual_seen() (prefs key "manualSeen").
## AUTOMATION (store.debug.*): debug_test_battle(encounter_id, opts := {seed, night, darkness, mapId}),
##   debug_player_turn(), debug_auto_battle(), debug_auto_expedition(seed := 1),
##   debug_auto_prepare(seed := 1) -> bool
## VIEWS  main.gd sets `world_host` (a Node2D); views are created here and shown
##   there (without main, under an internal host so tests still run them).
extends Node

signal changed

const SAVE_PATH := "user://meridius_save.json"

const JS = preload("res://scripts/core/js.gd")
const Prefs = preload("res://scripts/core/prefs.gd")
const Rng = preload("res://scripts/core/rng.gd")
const Deps = preload("res://scripts/ui/deps.gd")

var game: Variant = null
var screen := "loading"
var panel: Variant = null
var soldier: Variant = null
var manual: Variant = null
var menu_open := false
var report: Variant = null
var battle_info: Variant = null
var battle: Variant = null
var base_view: Node = null
var campaign_view: Node = null
var battle_view: Node = null
var load_progress := 0.0
var version := 0

## Where the save lives (tests point it elsewhere).
var save_path := SAVE_PATH
## The node the active view is shown under (set by main.gd).
var world_host: Node = null
## Create the world views (headless flow tests turn this off to test the store alone).
var use_views := true
var _fallback_host: Node2D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func emit_changed() -> void:
	version += 1
	changed.emit()


## Persist and refresh after any change to the game state.
func commit() -> void:
	save()
	emit_changed()


## Plays a sound through the Sfx autoload (when present).
func sfx(name: String) -> void:
	var s := _sfx_node()
	if s != null:
		s.play(name)


func _sfx_node() -> Node:
	var ml := Engine.get_main_loop()
	return (ml as SceneTree).root.get_node_or_null("Sfx") if ml is SceneTree else null


# ---------------------------------------------------------------- saves

func has_save() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	return FileAccess.get_file_as_string(save_path).length() > 0


func save() -> void:
	if game == null:
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return # storage unavailable
	f.store_string(Deps.game().to_save_json(game))
	f.close()


func load_save() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var raw := FileAccess.get_file_as_string(save_path)
	if raw == "":
		return false
	# Game.from_save_json: null on bad JSON or another SAVE_VERSION; migrates the
	# save (saves from before squads keep their soldiers: each becomes a full
	# squad) and corrects Godot's float parsing to the values the original wrote.
	var g: Variant = Deps.game().from_save_json(raw)
	if not (g is Dictionary):
		return false
	game = g
	return true


func manual_seen() -> bool:
	return Prefs.prefs().get("manualSeen", false) == true


func mark_manual_seen() -> void:
	Prefs.set_pref("manualSeen", true)


# ---------------------------------------------------------------- views

func _host() -> Node:
	if world_host != null and is_instance_valid(world_host):
		return world_host
	if _fallback_host == null:
		_fallback_host = Node2D.new()
		_fallback_host.name = "WorldHost"
		add_child(_fallback_host)
	return _fallback_host


## Shows one view in the world host and frees the others.
func _show_view(v: Node) -> void:
	var host := _host()
	for c in host.get_children():
		if c != v:
			host.remove_child(c)
			c.queue_free()
	if v != null and v.get_parent() != host:
		if v.get_parent() != null:
			v.get_parent().remove_child(v)
		host.add_child(v)


func _get_game() -> Variant:
	return game


func _get_expedition() -> Variant:
	return game.get("expedition") if game is Dictionary else null


func _drop_view(v: Node) -> void:
	if v != null and is_instance_valid(v):
		if v.get_parent() != null:
			v.get_parent().remove_child(v)
		v.queue_free()


func _set_base_view(dim := false) -> void:
	if base_view == null or not is_instance_valid(base_view):
		base_view = _new_view("base_view")
		if base_view != null:
			# BaseScene(getGame, onBuilding) + subscribe: setup(getter), building_clicked, changed.
			if base_view.has_method("setup"):
				base_view.setup(Callable(self, "_get_game"))
			if base_view.has_signal("building_clicked"):
				base_view.connect("building_clicked", Callable(self, "open_panel"))
			_subscribe(base_view)
	elif game != null and base_view.has_method("spawn_walkers"):
		base_view.spawn_walkers(game)
	if base_view != null and "dim" in base_view:
		base_view.dim = dim
	# Showing the base frees the campaign and battle views.
	_show_view(base_view)
	campaign_view = null
	battle_view = null


## A view's subscribe(): its change signal (`changed` or `ui_changed`) re-renders the UI.
func _subscribe(v: Node) -> void:
	for sig in ["changed", "ui_changed"]:
		if v.has_signal(sig) and not v.is_connected(sig, Callable(self, "emit_changed")):
			v.connect(sig, Callable(self, "emit_changed"))


func _set_dim(d: bool) -> void:
	if base_view != null and is_instance_valid(base_view) and "dim" in base_view:
		base_view.dim = d


func _new_view(key: String) -> Node:
	return Deps.instance(key) if use_views else null


func _make_battle_view(b: Variant) -> Node:
	var v := _new_view("battle_view")
	if v != null and v.has_method("setup"):
		v.setup(b)
	return v


# ---------------------------------------------------------------- flow

func new_game(seed: Variant = null) -> void:
	game = Deps.game().new_game(seed)
	save()
	go_base()


func continue_game() -> void:
	if not load_save():
		return
	if game.get("expedition") != null:
		go_campaign()
	else:
		go_base()


func go_title() -> void:
	screen = "title"
	panel = null
	menu_open = false
	_set_base_view(true)
	emit_changed()


func go_base() -> void:
	screen = "base"
	panel = null
	_set_base_view(false)
	emit_changed()


func open_panel(id: Variant) -> void:
	if id is String and id == "":
		id = null
	panel = id
	sfx("page" if id != null else "click")
	_set_dim(id != null and screen == "base")
	emit_changed()


func open_manual(page: Variant) -> void:
	if page is String and page == "":
		page = null
	manual = page
	if page != null:
		sfx("page")
	else:
		mark_manual_seen()
	emit_changed()


func open_soldier(id: Variant) -> void:
	if id is String and id == "":
		id = null
	soldier = id
	if id != null:
		sfx("page")
	emit_changed()


func go_prep() -> void:
	screen = "prep"
	panel = null
	_set_dim(true)
	sfx("page")
	emit_changed()


func launch(campaign_id: String, army: Array, supplies: Dictionary, cost: int) -> void:
	if game == null:
		return
	Deps.expedition().start_expedition(game, campaign_id, army, supplies, cost)
	save()
	sfx("horn")
	go_campaign()


func go_campaign() -> void:
	var ex: Variant = _get_expedition()
	screen = "campaign"
	_drop_view(base_view)
	base_view = null
	_drop_view(battle_view)
	battle_view = null
	battle = null
	campaign_view = _new_view("campaign_view")
	if campaign_view != null:
		if campaign_view.has_method("setup"):
			# CampaignScene(ex, getExpedition, onNodeClick): setup(ex, getter) + node_clicked.
			campaign_view.setup(ex, Callable(self, "_get_expedition"))
		if campaign_view.has_signal("node_clicked"):
			campaign_view.connect("node_clicked", Callable(self, "click_node"))
		_subscribe(campaign_view)
	_show_view(campaign_view)
	emit_changed()


func click_node(id: String) -> void:
	var Ex = Deps.expedition()
	if game == null or not Ex.can_march(game, id):
		sfx("deny")
		return
	Ex.march(game, id)
	commit()


func dismiss() -> void:
	if game == null:
		return
	var ex: Variant = game.get("expedition")
	var p: Variant = ex.get("pending") if ex is Dictionary else null
	var was_defeat: bool = p is Dictionary and p.get("kind") == "battleResult" and p.report.get("result") == "defeat"
	Deps.expedition().dismiss_pending(game)
	if was_defeat or game.get("expedition") == null:
		report = game.lastReport
		screen = "report"
		_set_base_view(true)
	commit()


func go_home(outcome: String) -> void:
	if game == null or game.get("expedition") == null:
		return
	report = Deps.expedition().return_home(game, outcome)
	screen = "report"
	_set_base_view(true)
	sfx("victory" if outcome == "success" else "page")
	commit()


func start_battle() -> void:
	var g: Variant = game
	if g == null or g.get("expedition") == null:
		return
	var p: Variant = g.expedition.get("pending")
	if not (p is Dictionary) or p.get("kind") != "battle":
		return
	var Ex = Deps.expedition()
	var night: Dictionary = Ex.prepare_night(g)
	var setup: Dictionary = Deps.setup().build_battle(p.roll, Ex.battle_army(g), {"survivalBonus": Ex.survival_bonus(g), "title": p.title, "darkness": night.darkness})
	battle = Deps.battle().new(setup)
	battle_info = {"title": p.title, "objective": p.objective}
	battle_view = _make_battle_view(battle)
	if battle_view != null:
		if night.night and battle_view.get("atmo") != null:
			battle_view.atmo.night = true
		if battle_view.has_signal("ended"):
			battle_view.connect("ended", func(_r: String): finish_battle())
		_subscribe(battle_view)
	_drop_view(campaign_view)
	campaign_view = null
	_show_view(battle_view)
	screen = "battle"
	if not manual_seen():
		manual = "battle"
	emit_changed()


func finish_battle() -> void:
	var g: Variant = game
	var b: Variant = battle_view.b if battle_view != null and is_instance_valid(battle_view) and battle_view.get("b") != null else battle
	if g == null or b == null or battle_info == null:
		return
	Deps.expedition().apply_battle(g, b, battle_info.title, battle_info.objective)
	battle_info = null
	save()
	go_campaign()


# ---------------------------------------------------------------- menu (Godot addition)

func open_menu(open: bool) -> void:
	menu_open = open
	sfx("page" if open else "click")
	emit_changed()


func toggle_mute() -> void:
	var s := _sfx_node()
	if s != null:
		s.set_muted(not s.is_muted())
	emit_changed()


func is_muted() -> bool:
	var s := _sfx_node()
	return s != null and s.is_muted()


func toggle_fullscreen() -> void:
	if not is_inside_tree():
		return
	var w := get_window()
	if w == null:
		return
	if w.mode == Window.MODE_FULLSCREEN or w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		w.mode = Window.MODE_WINDOWED
	else:
		w.mode = Window.MODE_FULLSCREEN
	emit_changed()


func is_fullscreen() -> bool:
	if not is_inside_tree():
		return false
	var w := get_window()
	return w != null and (w.mode == Window.MODE_FULLSCREEN or w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN)


## Saves and returns to the title (the battle in progress is not saved, as in the original).
func quit_to_title() -> void:
	save()
	manual = null
	soldier = null
	menu_open = false
	if screen == "battle" or screen == "campaign":
		_drop_view(battle_view)
		battle_view = null
		battle = null
		battle_info = null
		_drop_view(campaign_view)
		campaign_view = null
	go_title()


# ---------------------------------------------------------------- automation (play-tests)

## Start a stand-alone battle for review, outside any expedition.
func debug_test_battle(encounter_id: String, opts: Dictionary = {}) -> void:
	var g: Variant = game
	if g == null:
		return
	var roll: Dictionary = Deps.setup().roll_encounter(encounter_id, Rng.new(JS.get_or(opts, "seed", 7)), 2)
	if opts.get("mapId") != null:
		roll.mapId = opts.mapId
	var Soldier = Deps.soldier()
	var army: Array = []
	for so in g.roster.slice(0, 6):
		army.append(Soldier.soldier_to_unit(so))
	var bopts := {"survivalBonus": 0}
	if opts.get("darkness") != null:
		bopts.darkness = opts.darkness
	battle = Deps.battle().new(Deps.setup().build_battle(roll, army, bopts))
	battle_info = null
	battle_view = _make_battle_view(battle)
	if battle_view != null:
		if opts.get("night") and battle_view.get("atmo") != null:
			battle_view.atmo.night = true
		if battle_view.has_signal("ended"):
			battle_view.connect("ended", func(_r: String): go_base())
		_subscribe(battle_view)
	_drop_view(base_view)
	base_view = null
	_drop_view(campaign_view)
	campaign_view = null
	_show_view(battle_view)
	screen = "battle"
	emit_changed()


## Let the AI play the company's current turn (play-test captures).
func debug_player_turn() -> void:
	var s := battle_view
	var b: Variant = s.b if s != null else battle
	if b == null or b.phase != "player":
		return
	Deps.ai().run_player_auto(b)
	if s != null:
		s.pump()


## Fight the current battle with the AI on both sides.
func debug_auto_battle() -> void:
	var s := battle_view
	var b: Variant = s.b if s != null else battle
	if b == null:
		return
	if b.phase == "deploy" and s != null:
		s.begin()
	Deps.autoplay().auto_battle(b)
	if s != null:
		s.pump()
	elif battle_info != null:
		# No view to play the end back: settle the battle at once.
		finish_battle()


func debug_auto_expedition(seed := 1) -> void:
	if game == null:
		return
	Deps.autoplay().auto_expedition(game, Rng.new(seed))
	report = game.lastReport
	screen = "report"
	_set_base_view(true)
	commit()


func debug_auto_prepare(seed := 1) -> bool:
	if game == null:
		return false
	var ok: bool = Deps.autoplay().auto_prepare(game, Rng.new(seed))
	if ok:
		save()
		go_campaign()
	return ok
