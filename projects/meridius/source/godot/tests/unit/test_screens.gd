## Every UI screen built from a fixture GameState: each visible Button (and
## clickable card) is connected or deliberately disabled, and pressing each
## enabled one on a fresh state runs without errors and does what it says.
## World views are off; the suite runs before the scene tree is live, so screens
## are mounted under a themed host and their _ready() is called directly.
extends "res://tests/test_case.gd"

const ThemeBuilder = preload("res://scripts/ui/theme_builder.gd")
const Game = preload("res://scripts/meta/game.gd")
const DB = preload("res://scripts/data/db.gd")
const Prefs = preload("res://scripts/core/prefs.gd")
const Card = preload("res://scripts/ui/widgets/card.gd")

const SAVE := "user://test_screens_save.json"
const SCREENS := {
	"title": "res://scripts/ui/screens/title_screen.gd",
	"loading": "res://scripts/ui/screens/loading_screen.gd",
	"base": "res://scripts/ui/screens/base_screen.gd",
	"prep": "res://scripts/ui/screens/prep_screen.gd",
	"report": "res://scripts/ui/screens/report_screen.gd",
}
const PANELS := ["barracks", "command", "training", "armoury", "infirmary", "quartermaster", "roster", "memorial"]

var host: Control
var _manual_seen: Variant


func before_all() -> void:
	_manual_seen = Prefs.prefs().get("manualSeen", true)
	host = Control.new()
	host.theme = ThemeBuilder.theme()
	host.size = Vector2(1920, 1080)
	(Engine.get_main_loop() as SceneTree).root.add_child(host)


func after_all() -> void:
	_clear()
	host.free()
	App.use_views = true
	App.save_path = App.SAVE_PATH
	App.game = null
	App.panel = null
	App.soldier = null
	App.manual = null
	App.menu_open = false
	App.report = null
	Prefs.set_pref("manualSeen", _manual_seen)


func _clear() -> void:
	for c in host.get_children():
		c.free()


## A company with something to do in every building.
func fixture() -> Dictionary:
	App.use_views = false
	App.save_path = SAVE
	App.panel = null
	App.soldier = null
	App.manual = null
	App.menu_open = false
	var g := Game.new_game(1234)
	g.flags = {"welcome": true}
	g.resources = {"silver": 3000, "timber": 30, "iron": 30, "trophies": 6}
	var r: Array = g.roster
	r[0].men = 3
	r[0].hp = 40
	r[0].injuries = ["gashed_arm", "cracked_ribs"]
	r[1].morale = 12
	r[1].men = 5
	r[2].xp = 200
	r[2].level = 3
	r[3].armorCondition = 0.5
	r[4].recovering = true
	g.fallen.append({"name": "Ulf Ulfsson", "typeId": "spearman", "level": 2, "kills": 3, "battles": 4, "cause": "Cut down at Elk Hollow", "cycle": 1})
	g.chronicle.push_front({"cycle": 1, "text": "Ulf Ulfsson's spearmen fell at Elk Hollow.", "tone": "bad"})
	g.chronicle.push_front({"cycle": 1, "text": "The company returns.", "tone": "good"})
	g.lastReport = {"campaignId": DB.CAMPAIGNS[0].id, "outcome": "success", "loot": {"silver": 40, "iron": 1}, "reward": {"silver": 120},
		"buyback": 10, "stipend": 50, "fallen": ["Ulf's spearmen"], "survivors": [], "menLost": 4, "marches": 6, "battles": 3,
		"strength": [{"name": r[0].name, "typeId": "footman", "men": 3, "size": 6}]}
	App.game = g
	App.report = g.lastReport
	App.save()
	return g


func _mount(key: String, setup := Callable()) -> Control:
	_clear()
	var s: Control = load(SCREENS[key]).new()
	App.screen = key
	if setup.is_valid():
		setup.call()
	host.add_child(s)
	s._ready()
	return s


## Shown unless it or an ancestor (up to the host) is hidden; the suite runs
## outside the live tree, where is_visible_in_tree() is always false.
func _shown(n: Node) -> bool:
	while n != null and n != host:
		if n is CanvasItem and not (n as CanvasItem).visible:
			return false
		n = n.get_parent()
	return true


func _buttons(root: Node) -> Array:
	var out: Array = []
	for b in root.find_children("*", "BaseButton", true, false):
		if _shown(b) and not b.is_queued_for_deletion():
			out.append(b)
	return out


func _cards(root: Node) -> Array:
	var out: Array = []
	for c in root.find_children("*", "PanelContainer", true, false):
		if c.get_script() == Card and c.clickable and _shown(c) and not c.is_queued_for_deletion():
			out.append(c)
	return out


## Every visible button is connected or deliberately disabled.
func _audit(root: Node, what: String) -> int:
	var n := 0
	for b in _buttons(root):
		n += 1
		var wired: bool = b.get_signal_connection_list("pressed").size() > 0 or (b as BaseButton).toggle_mode
		assert_true(wired or (b as BaseButton).disabled, "%s: button '%s' (%s) does nothing" % [what, b.name, b.get("text")])
	for c in _cards(root):
		assert_true(c.get_signal_connection_list("pressed").size() > 0, "%s: card %s does nothing" % [what, c.name])
	return n


func _targets(root: Node) -> Array:
	var out: Array = []
	for b in _buttons(root):
		if not (b as BaseButton).disabled:
			out.append(b)
	out.append_array(_cards(root))
	return out


## Presses enabled button / card i of a freshly built screen, for every i
## (the same build gives the same order).
func _press_all(build: Callable, what: String) -> int:
	var count := _targets(build.call()).size()
	for i in count:
		var targets := _targets(build.call())
		if i >= targets.size():
			fail("%s: target %d vanished on rebuild" % [what, i])
			continue
		targets[i].emit_signal("pressed")
		# Confirmations: accept them too.
		for ok in host.find_children("OK", "Button", true, false):
			if not ok.is_queued_for_deletion():
				ok.emit_signal("pressed")
	return count


func test_title() -> void:
	fixture()
	var s := _mount("title")
	assert_not_null(s.continue_button, "Continue with a save")
	assert_eq(s.new_button.theme_type_variation, &"BigButton", "plain New Company when a save exists")
	assert_true(_audit(s, "title") >= 2)
	s.continue_button.pressed.emit()
	assert_eq(App.screen, "base", "Continue loads the save")
	s = _mount("title")
	s.new_button.pressed.emit()
	var ok: Button = s.find_child("OK", true, false)
	assert_not_null(ok, "New Company asks first")
	var old_seed: int = App.game.seed
	ok.pressed.emit()
	assert_eq(App.screen, "base")
	assert_ne(App.game.seed, old_seed, "a new company")


func test_loading() -> void:
	fixture()
	App.load_progress = 0.5
	var s := _mount("loading")
	assert_eq(s.find_children("*", "Label", true, false)[0].text, "Loading… 50%")


func test_base_and_panels() -> void:
	fixture()
	var s := _mount("base")
	assert_true(_audit(s, "base") >= 6, "top bar, chronicle toggle, roster, plan")
	assert_eq(s.roster_button.text, "Roster (6)")
	for id in PANELS:
		fixture()
		App.panel = id
		s.refresh()
		assert_not_null(s.panel_overlay, "panel " + id)
		var n := _audit(s.panel_overlay, id)
		assert_true(n >= 1, "%s has buttons" % id)


func test_base_buttons_work() -> void:
	var n := _press_all(func():
		fixture()
		App.screen = "base"
		return _mount("base"), "base")
	assert_true(n >= 6, "pressed %d" % n)


func test_panel_buttons_work() -> void:
	for id in PANELS:
		var n := _press_all(func():
			fixture()
			var s := _mount("base")
			App.panel = id
			s.refresh()
			return s.panel_overlay, id)
		assert_true(n >= 1, "%s: pressed %d" % [id, n])


func test_barracks_actions() -> void:
	var g := fixture()
	var s := _mount("base")
	App.panel = "barracks"
	s.refresh()
	var silver: int = g.resources.silver
	var roster: int = g.roster.size()
	var hire: Button = s.panel_overlay.find_child("Hire", true, false)
	hire.pressed.emit()
	assert_eq(App.game.roster.size(), roster + 1, "hired")
	assert_true(App.game.resources.silver < silver, "paid")
	s.refresh()
	var refill: Button = s.panel_overlay.find_child("RefillAll", true, false)
	assert_not_null(refill, "refill all with two thin squads")
	refill.pressed.emit()
	for so in App.game.roster:
		assert_eq(so.men, DB.squad_size(so.typeId), "every squad refilled")


func test_soldier_detail() -> void:
	var g := fixture()
	var s := _mount("base")
	var so: Dictionary = g.roster[0]
	App.soldier = so.id
	s.refresh()
	var d: Control = s.soldier_overlay
	assert_not_null(d)
	assert_true(_audit(d, "soldier") >= 4, "+1, refill, discharge, close")
	d.name_edit.text = "  Gunnar the Bold  "
	d.close()
	assert_eq(so.name, "Gunnar the Bold", "renamed on close")
	assert_eq(App.soldier, null, "closed")
	App.soldier = so.id
	s.refresh()
	s.soldier_overlay.find_child("ReinforceAll", true, false).pressed.emit()
	assert_eq(so.men, 6, "refilled from the detail")
	var count: int = g.roster.size()
	s.soldier_overlay.find_child("Discharge", true, false).pressed.emit()
	var ok: Button = s.soldier_overlay.find_child("OK", true, false)
	assert_not_null(ok, "discharge asks first")
	ok.pressed.emit()
	assert_eq(App.game.roster.size(), count - 1, "discharged")
	var n := _press_all(func():
		var g2 := fixture()
		var s2 := _mount("base")
		App.soldier = g2.roster[0].id
		s2.refresh()
		return s2.soldier_overlay, "soldier")
	assert_true(n >= 4)


func test_welcome() -> void:
	var g := fixture()
	g.flags = {}
	var s := _mount("base")
	assert_not_null(s.welcome_overlay, "welcome on the first visit")
	_audit(s.welcome_overlay, "welcome")
	s.welcome_overlay.find_child("ReadManual", true, false).pressed.emit()
	assert_true(App.game.flags.welcome, "read")
	assert_eq(App.manual, "battle", "opens the manual")


func test_prep() -> void:
	fixture()
	var s := _mount("prep")
	assert_true(_audit(s, "prep") >= 12, "back, advice, ±, march, cards")
	assert_eq(s.army.size(), 4, "suggested force (one footman wounded, one recovering)")
	var army0: Array = s.army.duplicate()
	var rations: int = s.supplies.rations
	s.find_child("Supply_rations", true, false).find_child("Plus", true, false).pressed.emit()
	assert_eq(s.supplies.rations, rations + 1)
	s.find_child("Supply_rations", true, false).find_child("Minus", true, false).pressed.emit()
	assert_eq(s.supplies.rations, rations)
	s._toggle(army0[0])
	assert_false(s.army.has(army0[0]), "toggled out")
	s._toggle(army0[0])
	assert_true(s.army.has(army0[0]), "toggled in")
	s.march_button.pressed.emit()
	assert_eq(App.screen, "campaign", "marched out")
	assert_not_null(App.game.expedition)
	var n := _press_all(func():
		fixture()
		return _mount("prep"), "prep")
	assert_true(n >= 12)


func test_prep_problems_disable_march() -> void:
	var g := fixture()
	g.resources.silver = 0
	var s := _mount("prep")
	assert_true(s.march_button.disabled, "not enough silver")
	g.resources.silver = 3000
	for id in s.army.duplicate():
		s._toggle(id)
	assert_true(s.march_button.disabled, "no squad chosen")


func test_report() -> void:
	fixture()
	var s := _mount("report")
	assert_eq(_audit(s, "report"), 1)
	var texts: Array = []
	for l in s.find_children("*", "Label", true, false):
		texts.append(l.text)
	assert_true(texts.has("Triumph"), "title")
	assert_true(texts.has("4 soldiers died on the expedition."), "losses")
	s.find_child("BackToAmberfeld", true, false).pressed.emit()
	assert_eq(App.screen, "base")


func test_manual_pages() -> void:
	fixture()
	var closed := [false]
	var m: Control = load("res://scripts/ui/screens/manual.gd").make("battle", func(): closed[0] = true)
	host.add_child(m)
	assert_eq(_audit(m, "manual"), 8, "seven tabs and To the field")
	for p in m.pages():
		m.find_child("Tab_" + p.id, true, false).pressed.emit()
		assert_eq(m.page, p.id)
		assert_eq(m._body.get_child_count(), p.body.size(), p.id)
	m.find_child("ToTheField", true, false).pressed.emit()
	assert_true(closed[0])
	m.free()


func test_pause_menu() -> void:
	fixture()
	App.screen = "base"
	var m: Control = load("res://scripts/ui/screens/pause_menu.gd").new()
	host.add_child(m)
	assert_eq(_audit(m, "menu"), 6)
	App.menu_open = true
	m.find_child("Resume", true, false).pressed.emit()
	assert_false(App.menu_open)
	App.menu_open = true
	m.find_child("SaveQuit", true, false).pressed.emit()
	assert_eq(App.screen, "title")
	m.find_child("NewCompany", true, false).pressed.emit()
	var ok: Button = m.find_child("OK", true, false)
	assert_not_null(ok)
	ok.pressed.emit()
	assert_eq(App.screen, "base", "a new company")
	m.free()
