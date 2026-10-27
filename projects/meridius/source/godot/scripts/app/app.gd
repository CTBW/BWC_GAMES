## Game flow and state (autoload "App"). Port of src/ui/store.ts (AppStore).
##
## STATE (read freely; change only through the methods)
##   game: Dictionary|null      GameState (scripts/meta/game.gd), the save
##   screen: String             "loading" | "title" | "base" | "prep" | "battle" | "report"
##   panel: String|null         open base panel: building id | "roster" | "memorial"
##   soldier: String|null       roster id shown in the soldier detail overlay
##   manual: String|null        open Field Manual page id
##   menu_open: bool            the pause/menu overlay (Godot addition; Esc / menu)
##   report: Dictionary|null    ExpeditionReport shown by the report screen
##   battle_info: Dictionary|null  {title, objective} of the expedition battle being fought
##   battle                     the Battle (scripts/rules/battle.gd) of the current battle
##   base_view / battle_view: Node|null   the active world views (battle_view: the
##                              3D battle, scripts/render/battle3d.gd)
##   load_progress: float       0..1 while loading
##   version: int               bumped by every change
## SIGNAL
##   changed                    after every change (screens re-render on it)
## FLOW (store.ts names in snake_case)
##   new_game(seed = null), continue_game(), go_title(), go_base(), open_panel(id|null),
##   open_manual(page|null), open_soldier(id|null), go_prep(),
##   launch(campaign_id, army: Array, supplies: Dictionary, cost: int), start_battle(),
##   finish_battle(), go_home("success"|"retreat"|"defeat"),
##   open_menu(bool), toggle_mute(), toggle_fullscreen(), quit_to_title() (save, then title)
##   set_volume(key, v), volume(key): the sound sliders (master|music|ambience|sfx|voice, 0..1)
##   commit() = save() + emit_changed(); emit_changed(); sfx(name)
## MUSIC  every change asks Sfx for the track of the screen (SCREEN_MUSIC);
##   a track without recorded files plays nothing.
## SAVES  user://meridius_save.json (`save_path`): the GameState as JSON, the shape
##   of the original's localStorage save, written by Game.to_save_json and read by
##   Game.from_save_json (version must equal Game.SAVE_VERSION; then migrate_save).
##   has_save(), save(), load_save() -> bool
##   use_views := true   false: no world views are created (store-only tests).
##   manual_seen() / mark_manual_seen() (prefs key "manualSeen").
## THE EXPEDITION is one battle for now (the game is being redesigned around the
##   3D units: the campaign map is set aside): launch() takes the army straight
##   into the battle, a fixed warband (FIELD_ENCOUNTER, no waves) on Ashby farm
##   (FIELD), fought by the turn-based rules (Setup.build_battle with the field's
##   map, Battlefields.battle_map) and shown by the 3D battle. When its end has
##   played, finish_battle() applies it (Expedition.apply_battle: losses,
##   experience, loot) and the company goes home (Expedition.return_home:
##   success on a victory, retreat, defeat).
## AUTOMATION (store.debug.*): debug_test_battle(opts := {seed, army: [typeId…], level, encounter})
##   a battle on the field outside any expedition; debug_player_turn() the AI
##   plays the company's turn; debug_auto_battle() the AI fights the whole
##   battle; debug_settle_battle(result) ends the expedition's battle as
##   "victory" | "defeat" | "retreat" without fighting it;
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

## Music track (bank.json `music.tracks`) for each screen.
const SCREEN_MUSIC := {"title": "menu", "base": "camp", "prep": "camp", "report": "camp", "battle": "battle"}
## The expedition's battle: the warband (data/encounters) and the 3D battlefield it is fought on.
const FIELD_ENCOUNTER := "brute_vanguard"
const FIELD := "ashby"
const FIELD_TITLE := "Ashby farm"

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


func _exit_tree() -> void:
	# Sprite textures still loading in the background are taken from the loader
	# before it shuts down (an untaken threaded load leaks its token at exit).
	var A: Variant = Deps.assets()
	if A != null and A.has_method("collect_loaded"):
		A.collect_loaded(true)


func emit_changed() -> void:
	version += 1
	_sync_music()
	changed.emit()


func _sync_music() -> void:
	var s := _sfx_node()
	if s != null and s.has_method("set_music"):
		s.set_music(SCREEN_MUSIC.get(screen, ""))


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
	# Showing the base frees the battle view.
	_show_view(base_view)
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


## The 3D battle showing Battle `b`.
func _make_battle_view(b: Variant) -> Node:
	var v := _new_view("battle3d")
	if v != null and v.has_method("setup"):
		v.setup(b)
	return v


## The rules' setup of a battle against encounter `roll` on the field.
func _field_setup(roll: Dictionary, army: Array, opts: Dictionary) -> Dictionary:
	var o := opts.duplicate()
	o.map = Deps.battlefields().battle_map(FIELD)
	return Deps.setup().build_battle(roll, army, o)


# ---------------------------------------------------------------- flow

func new_game(seed: Variant = null) -> void:
	game = Deps.game().new_game(seed)
	save()
	go_base()


func continue_game() -> void:
	if not load_save():
		return
	if game.get("expedition") != null:
		start_battle()
	else:
		go_base()


func go_title() -> void:
	screen = "title"
	panel = null
	menu_open = false
	_set_base_view(true)
	emit_changed()


## A fresh inspection field, available without creating or replacing a save.
func open_terrain_lab() -> void:
	if screen != "title":
		return
	screen = "terrain_lab"
	panel = null
	menu_open = false
	emit_changed()


func open_playground() -> void:
	if screen != "title":
		return
	screen = "playground"
	panel = null
	menu_open = false
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
	start_battle()


func go_home(outcome: String) -> void:
	if game == null or game.get("expedition") == null:
		return
	report = Deps.expedition().return_home(game, outcome)
	screen = "report"
	_set_base_view(true)
	sfx("victory" if outcome == "success" else "page")
	commit()


## The expedition's army takes the field: the battle pending, else the
## warband on Ashby farm (made the pending battle and saved, so Continue comes
## back to the same one).
func start_battle() -> void:
	var g: Variant = game
	if g == null or g.get("expedition") == null:
		return
	var Ex = Deps.expedition()
	var ex: Dictionary = g.expedition
	var p: Variant = ex.get("pending")
	if not (p is Dictionary) or p.get("kind") != "battle":
		var roll: Dictionary = Ex.ex_rng(ex, func(r: RefCounted) -> Dictionary: return Deps.setup().roll_encounter(FIELD_ENCOUNTER, r, 1))
		roll.waves = []
		p = {"kind": "battle", "nodeId": ex.current, "roll": roll, "title": FIELD_TITLE, "objective": true, "surprise": false}
		ex.pending = p
		save()
	battle = Deps.battle().new(_field_setup(p.roll, Ex.battle_army(g), {"title": p.title}))
	battle_info = {"title": p.title, "objective": p.objective}
	_drop_view(base_view)
	base_view = null
	_drop_view(battle_view)
	battle_view = _make_battle_view(battle)
	if battle_view != null:
		if battle_view.has_signal("ended"):
			battle_view.connect("ended", func(_r: String): finish_battle())
		_subscribe(battle_view)
	_show_view(battle_view)
	screen = "battle"
	emit_changed()


## The battle's end has played: it is applied to the roster and the expedition
## (Expedition.apply_battle) and the company goes home. A battle not yet over
## counts as a withdrawal. Outside an expedition (debug_test_battle) it only
## goes back to the base.
func finish_battle() -> void:
	var g: Variant = game
	if g == null:
		return
	var view: Node = battle_view if battle_view != null and is_instance_valid(battle_view) else null
	var b: Variant = view.b if view != null and view.get("b") != null else battle
	if g.get("expedition") == null or battle_info == null or b == null:
		battle_info = null
		battle = null
		_drop_view(view)
		battle_view = null
		go_base()
		return
	if b.result == null:
		b.phase = "over"
		b.result = "retreat"
	var rep: Dictionary = Deps.expedition().apply_battle(g, b, battle_info.title, battle_info.objective)
	battle_info = null
	battle = null
	_drop_view(view)
	battle_view = null
	go_home({"victory": "success", "retreat": "retreat"}.get(String(rep.result), "defeat"))


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


## A sound slider moved: applied at once, remembered shortly after (Sfx).
func set_volume(key: String, v: float) -> void:
	var s := _sfx_node()
	if s != null:
		s.set_volume(key, v, false)


func volume(key: String) -> float:
	var s := _sfx_node()
	return s.volume(key) if s != null else 1.0


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
	if screen == "battle":
		_drop_view(battle_view)
		battle_view = null
		battle_info = null
		battle = null
	go_title()


# ---------------------------------------------------------------- automation (play-tests)

## A stand-alone battle on the field for review, outside any expedition: the
## warband (`encounter`, else FIELD_ENCOUNTER) against a chosen army of fresh
## squads (`army`: type ids, at `level`), else the roster's first six.
func debug_test_battle(opts: Dictionary = {}) -> void:
	var g: Variant = game
	if g == null:
		return
	var seed: int = JS.get_or(opts, "seed", 7)
	var roll: Dictionary = Deps.setup().roll_encounter(String(JS.get_or(opts, "encounter", FIELD_ENCOUNTER)), Rng.new(seed), 1)
	roll.waves = []
	var Soldier = Deps.soldier()
	var army: Array = []
	if opts.get("army") != null:
		var n := [0]
		var next_id := func() -> String:
			n[0] += 1
			return "t%d" % (n[0] - 1)
		var types: Array = opts.army
		for i in types.size():
			army.append(Soldier.soldier_to_unit(Soldier.new_soldier(Rng.new(seed * 31 + i), str(types[i]), int(JS.get_or(opts, "level", 1)), next_id, 0)))
	else:
		for so in g.roster.slice(0, 6):
			army.append(Soldier.soldier_to_unit(so))
	battle = Deps.battle().new(_field_setup(roll, army, {"title": FIELD_TITLE}))
	battle_info = null
	_drop_view(base_view)
	base_view = null
	_drop_view(battle_view)
	battle_view = _make_battle_view(battle)
	if battle_view != null:
		if battle_view.has_signal("ended"):
			battle_view.connect("ended", func(_r: String): go_base())
		_subscribe(battle_view)
	_show_view(battle_view)
	screen = "battle"
	emit_changed()


## Let the AI play the company's current turn (play-test captures).
func debug_player_turn() -> void:
	var s := battle_view
	var b: Variant = s.b if s != null else battle
	if b == null or b.phase != "player" or (s != null and s.rules_running()):
		return
	if s != null:
		s.run_rules(func(bb): Deps.ai().run_player_auto(bb))
	else:
		Deps.ai().run_player_auto(b)


## Fight the current battle with the AI on both sides; the view plays it back.
func debug_auto_battle() -> void:
	var s := battle_view
	var b: Variant = s.b if s != null else battle
	if b == null or (s != null and s.rules_running()):
		return
	if s != null:
		s.run_rules(func(bb): Deps.autoplay().auto_battle(bb))
		return
	Deps.autoplay().auto_battle(b)
	if battle_info != null:
		# No view to play the end back: settle the battle at once.
		finish_battle()


## Ends the expedition's battle as `result` without fighting it, then goes home
## (a defeat: every squad of the company falls).
func debug_settle_battle(result: String) -> void:
	if game == null or game.get("expedition") == null:
		return
	if battle == null or battle_info == null:
		start_battle()
	var view: Node = battle_view if battle_view != null and is_instance_valid(battle_view) else null
	var b: Variant = view.b if view != null and view.get("b") != null else battle
	if b == null or (view != null and view.rules_running()):
		return
	if result == "defeat":
		for u in b.units:
			if u.faction == "player":
				u.status = "dead"
				u.alive = 0
				u.hp = 0
	b.phase = "over"
	b.result = result
	finish_battle()


func debug_auto_prepare(seed := 1) -> bool:
	if game == null:
		return false
	var ok: bool = Deps.autoplay().auto_prepare(game, Rng.new(seed))
	if ok:
		save()
		start_battle()
	return ok
