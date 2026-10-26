## The campaign HUD (scripts/ui/campaign_hud.gd, port of src/ui/screens/Campaign.tsx)
## over a real expedition (Game.new_game + Autoplay.auto_prepare): the panels it
## shows, every button wired (or deliberately disabled), and each pending dialog
## kind of src/campaign/expedition.ts built and answered through its buttons.
## The store is a stand-in recording the calls (the flow test uses the real App).
extends "res://tests/test_case.gd"

const ThemeBuilder = preload("res://scripts/ui/theme_builder.gd")
const H = preload("res://scripts/ui/hud_common.gd")
const DB = preload("res://scripts/data/db.gd")
const Rng = preload("res://scripts/core/rng.gd")
const Game = preload("res://scripts/meta/game.gd")
const Setup = preload("res://scripts/rules/setup.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const Expedition = preload("res://scripts/campaign/expedition.gd")
const Autoplay = preload("res://scripts/campaign/autoplay.gd")
const CampaignHud = preload("res://scripts/ui/campaign_hud.gd")


## Stand-in for the App store: records calls, applies the rules like store.ts.
class FakeStore extends Node:
	signal changed
	var game: Variant = null
	var soldier: Variant = null
	var campaign_view: Variant = null
	var calls: Array = []

	func commit() -> void:
		calls.append(["commit"])
		changed.emit()

	func dismiss() -> void:
		calls.append(["dismiss"])
		Expedition.dismiss_pending(game)
		changed.emit()

	func start_battle() -> void:
		calls.append(["start_battle"])

	func go_home(outcome: String) -> void:
		calls.append(["go_home", outcome])

	func open_manual(page: Variant) -> void:
		calls.append(["open_manual", page])

	func open_soldier(id: Variant) -> void:
		calls.append(["open_soldier", id])
		soldier = id
		changed.emit()

	func called(name: String) -> bool:
		for c in calls:
			if c[0] == name:
				return true
		return false


## Stand-in for the campaign view: the CampaignUi dict and focus_current().
class FakeView extends Node2D:
	signal changed
	var ui := {"marching": false, "version": 0}
	var focused := 0

	func focus_current() -> void:
		focused += 1


var host: Control
var store: FakeStore
var hud: Control
var g: Dictionary


func before_each() -> void:
	g = Game.new_game(4242)
	assert_true(Autoplay.auto_prepare(g), "an expedition launches")
	store = FakeStore.new()
	store.game = g
	host = Control.new()
	host.theme = ThemeBuilder.theme()
	host.size = Vector2(1920, 1080)
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	host.add_child(store)
	hud = CampaignHud.new()
	hud.app = store
	host.add_child(hud)


func after_each() -> void:
	host.get_parent().remove_child(host)
	host.free()


## Still shown by the HUD (the runner adds nodes outside the running tree, so
## there is no _ready and no frame: the tests call hud.refresh() themselves).
func _live(n: Node) -> bool:
	return is_instance_valid(n) and not n.is_queued_for_deletion() and hud.is_ancestor_of(n)


## A live button by node name, else by exact text, else by text containing `text`.
func _button(text: String) -> BaseButton:
	var live: Array = H.buttons(hud).filter(func(b): return _live(b))
	for b in live:
		if str(b.name) == text:
			return b
	for b in live:
		if H.button_text(b) == text:
			return b
	for b in live:
		if H.button_text(b).contains(text):
			return b
	return null


func _press(text: String) -> bool:
	var b := _button(text)
	if not assert_not_null(b, "button %s" % text):
		return false
	if not assert_false(b.disabled, "%s enabled" % text):
		return false
	b.pressed.emit()
	hud.refresh()
	return true


## Every visible button has a handler, unless it is disabled on purpose.
func _check_buttons(where: String) -> int:
	var n := 0
	for b in H.buttons(hud):
		if not _live(b):
			continue
		n += 1
		assert_true(b.get_signal_connection_list("pressed").size() > 0, "%s: '%s' (%s) is connected" % [where, H.button_text(b), b.name])
	return n


func _text_of(n: Node) -> String:
	var s := ""
	for c in n.find_children("*", "", true, false):
		if c is Label:
			s += (c as Label).text + "\n"
		elif c is RichTextLabel:
			s += (c as RichTextLabel).get_parsed_text() + "\n"
	return s


func _node_of_type(t: String) -> Variant:
	for n in g.expedition.nodes:
		if n.type == t:
			return n
	return null


func test_start_screen() -> void:
	hud.refresh()
	var ex: Dictionary = g.expedition
	var c: Dictionary = DB.campaign_by_id(ex.campaignId)
	var top := hud.get_node_or_null("TopBar")
	if not assert_not_null(top, "top bar"):
		return
	var t := _text_of(top)
	assert_true(t.contains(str(c.name).to_upper()), "campaign name in capitals")
	assert_true(t.contains("March 0 · Muster point"), "march line: " + t)
	assert_true(t.contains("Spoils"), "spoils label")
	assert_true(t.contains("Nothing"), "no spoils yet")
	for k in DB.SUPPLY_ORDER:
		assert_not_null(top.find_child("Supply_" + k, true, false), "supply " + k)
	var army := hud.get_node_or_null("Army")
	if assert_not_null(army, "army panel"):
		var at := _text_of(army)
		assert_true(at.contains("The Army"), "army heading")
		for so in Expedition.army_soldiers(g):
			assert_true(at.contains(str(so.name)), "squad " + str(so.name))
			assert_true(at.contains("Fresh"), "fatigue label")
	var prompt := hud.get_node_or_null("MarchPrompt")
	if assert_not_null(prompt, "march prompt"):
		assert_true(_text_of(prompt).contains("each march eats %d rations and tires the army" % Expedition.ration_cost(g)))
	assert_not_null(hud.get_node_or_null("Log"), "log")
	assert_true(_text_of(hud.get_node("Log")).contains(str(ex.log[0].text)), "newest log line")
	assert_eq(hud.dialog_kind(), "", "no dialog")
	var retreat := _button("Retreat home")
	if assert_not_null(retreat):
		assert_false(retreat.disabled, "retreat enabled without a pending event")
	assert_true(_check_buttons("start") >= 3, "help, find army, retreat")


func test_top_bar_help_and_find_army() -> void:
	var view := FakeView.new()
	host.add_child(view)
	hud.setup(view)
	hud.refresh()
	_press("Help")
	assert_eq(store.calls.back(), ["open_manual", "campaign"])
	_press("Find army")
	assert_eq(view.focused, 1, "focus_current")


func test_soldier_row_opens_detail() -> void:
	hud.refresh()
	var so: Dictionary = Expedition.army_soldiers(g)[0]
	var row: Control = hud.find_child("Soldier_" + str(so.id), true, false)
	if not assert_not_null(row, "army row"):
		return
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	row.gui_input.emit(e)
	assert_eq(store.calls.back(), ["open_soldier", so.id])
	hud.refresh()
	# The soldier detail overlay of the UI shell (when present) opens over the HUD.
	if ResourceLoader.exists("res://scripts/ui/screens/soldier_detail.gd"):
		assert_not_null(hud._soldier, "soldier overlay")


func test_bandage_button() -> void:
	var so: Dictionary = Expedition.army_soldiers(g)[0]
	so.hp = int(so.hp) - 25
	g.expedition.supplies.bandages = 2
	hud.refresh()
	var b := _button("Bandage")
	if not assert_not_null(b, "bandage button on a hurt squad"):
		return
	var hp_before: int = so.hp
	b.pressed.emit()
	assert_true(so.hp > hp_before, "bandage heals")
	assert_eq(int(g.expedition.supplies.bandages), 1, "one bandage used")
	assert_true(store.called("commit"))
	# No bandage buttons while an event is pending.
	g.expedition.pending = {"kind": "arrive", "nodeId": g.expedition.current}
	so.hp = int(so.hp) - 25
	hud.refresh()
	for x in H.buttons(hud):
		if _live(x):
			assert_ne(str(x.name), "Bandage", "no bandage during a pending event")


func test_retreat_confirmation() -> void:
	hud.refresh()
	_press("Retreat home")
	var modal := hud.get_node_or_null("Confirm")
	if not assert_not_null(modal, "confirmation"):
		return
	assert_true(_text_of(modal).contains("Sound the retreat?"))
	_check_buttons("confirm")
	_press("Press on")
	assert_false(_live(modal), "Press on closes it")
	_press("Retreat home")
	_press("PressOn")
	_press("Retreat home")
	_press("Retreat")
	assert_eq(store.calls.back(), ["go_home", "retreat"])


func test_hover_card_and_marching() -> void:
	var view := FakeView.new()
	host.add_child(view)
	hud.setup(view)
	var nxt: Array = Expedition.next_nodes(g.expedition)
	view.ui["hover"] = nxt[0].id
	hud.refresh()
	var card := hud.get_node_or_null("NodeCard")
	if assert_not_null(card, "node card"):
		var t := _text_of(card)
		assert_true(t.contains("Click to march here."), "reachable: " + t)
		assert_true(t.contains(str(Expedition.node_view(nxt[0]).title)))
	assert_null_node("MarchPrompt", "no prompt while hovering")
	# A far node.
	var far: Variant = null
	for n in g.expedition.nodes:
		if n.stage >= 3:
			far = n
			break
	view.ui["hover"] = far.id
	hud.refresh()
	card = hud.get_node_or_null("NodeCard")
	if assert_not_null(card):
		var t := _text_of(card)
		assert_true(t.contains("Unexplored") or t.contains("Not reachable from here."), t)
	view.ui.erase("hover")
	view.ui.marching = true
	hud.refresh()
	assert_null_node("NodeCard", "card gone")
	assert_null_node("MarchPrompt", "no prompt while marching")
	assert_true(_button("Retreat home").disabled, "no retreat while marching")
	view.ui.marching = false
	hud.refresh()
	assert_not_null(hud.get_node_or_null("MarchPrompt"))


func assert_null_node(path: String, msg: String) -> void:
	var n := hud.get_node_or_null(path)
	assert_true(n == null or not _live(n), msg)


func test_arrive_and_scout() -> void:
	for kind in ["arrive", "scout"]:
		g.expedition.pending = {"kind": kind, "nodeId": g.expedition.current}
		hud.refresh()
		assert_eq(hud.dialog_kind(), kind)
		var t := _text_of(hud.get_node("PendingDialog"))
		assert_true(t.contains("Muster point"), "title is the node name")
		if kind == "scout":
			assert_true(t.contains("From the high ground the scouts can see for miles"))
		else:
			assert_true(t.contains("The company arrives."))
		_check_buttons(kind)
		assert_true(_button("Retreat home").disabled, "retreat blocked by the dialog")
		_press("Continue")
		assert_eq(store.calls.back(), ["dismiss"])
		assert_eq(hud.dialog_kind(), "", "dismissed")


func test_event_choices_and_result() -> void:
	var army := Expedition.army_soldiers(g)
	var ev: Dictionary = DB.EVENTS[0]
	g.expedition.pending = {"kind": "event", "nodeId": g.expedition.current, "eventId": ev.id, "subject": army[1].id}
	hud.refresh()
	assert_eq(hud.dialog_kind(), "event")
	var t := _text_of(hud.get_node("PendingDialog"))
	assert_true(t.contains(str(ev.title)), "event title")
	assert_true(t.contains(str(ev.text).replace("{name}", army[1].name).substr(0, 30)), "event text with the subject's name")
	var choices: Array = []
	for b in H.buttons(hud):
		if _live(b) and str(b.name).begins_with("Choice"):
			choices.append(b)
	assert_eq(choices.size(), ev.choices.size(), "one button per choice")
	for i in ev.choices.size():
		var ok: Dictionary = Expedition.choice_available(g, ev.choices[i])
		assert_eq(choices[i].disabled, not ok.ok, "choice %d availability" % i)
		var label := H.button_text(choices[i])
		assert_true(label.contains(str(ev.choices[i].label)), "choice label " + label)
		if ev.choices[i].get("hint") != null:
			assert_true(label.contains("(%s)" % ev.choices[i].hint), "hint " + label)
	_check_buttons("event")
	# Take the first available choice.
	var pick := -1
	for i in choices.size():
		if not choices[i].disabled:
			pick = i
			break
	choices[pick].pressed.emit()
	hud.refresh()
	assert_true(store.called("commit"))
	var p: Dictionary = g.expedition.pending
	assert_not_null(p.get("result"), "a result")
	t = _text_of(hud.get_node("PendingDialog"))
	assert_true(t.contains(str(p.result.text).substr(0, 20)), "result text")
	for c in p.result.changes:
		assert_true(t.contains(str(c)), "change tag " + str(c))
	for b in H.buttons(hud):
		if _live(b):
			assert_false(str(b.name).begins_with("Choice"), "choices gone after the result")
	_press("To arms!" if p.get("followBattle") != null else "Continue")
	assert_true(store.called("dismiss"))


func test_unavailable_choice_shows_reason() -> void:
	# An event whose choice needs supplies the army does not have.
	var ev: Variant = null
	var idx := -1
	for e in DB.EVENTS:
		for i in e.choices.size():
			var r: Variant = e.choices[i].get("requires")
			if r is Dictionary and r.get("supply") != null:
				ev = e
				idx = i
				break
		if ev != null:
			break
	if ev == null:
		skip("no event with a supply requirement")
		return
	var need: Array = ev.choices[idx].requires.supply
	g.expedition.supplies[need[0]] = 0
	g.expedition.pending = {"kind": "event", "nodeId": g.expedition.current, "eventId": ev.id}
	hud.refresh()
	var b := _button("Choice%d" % idx)
	if assert_not_null(b):
		assert_true(b.disabled, "disabled without the supply")
		assert_true(H.button_text(b).contains("— Needs"), "reason shown: " + H.button_text(b))


func test_battle_briefing() -> void:
	var n: Variant = _node_of_type("battle")
	if n == null or n.get("encounter") == null:
		skip("no battle node")
		return
	g.expedition.pending = {"kind": "battle", "nodeId": n.id, "roll": n.encounter, "title": "%s at %s" % [DB.encounter_by_id(n.encounter.encounterId).name, n.name], "objective": false, "surprise": false}
	hud.refresh()
	assert_eq(hud.dialog_kind(), "battle")
	var t := _text_of(hud.get_node("PendingDialog"))
	assert_true(t.contains("Battle") or t.contains("A Stand"), "title")
	assert_true(t.contains("There is no going around."), "briefing text")
	assert_true(t.contains("Enemy"), "enemy card")
	assert_true(t.contains("Ground:"), "ground line")
	assert_true(t.contains(" × "), "enemy counts")
	_check_buttons("battle")
	_press("To Battle")
	assert_eq(store.calls.back(), ["start_battle"])
	# Ambush and the last stand.
	g.expedition.pending.surprise = true
	hud.refresh()
	assert_true(_text_of(hud.get_node("PendingDialog")).contains("Ambush!"))
	var obj: Variant = _node_of_type("objective")
	if obj != null:
		g.expedition.pending = {"kind": "battle", "nodeId": obj.id, "roll": obj.encounter, "title": obj.name, "objective": true, "surprise": false}
		hud.refresh()
		t = _text_of(hud.get_node("PendingDialog"))
		assert_true(t.contains("The Last Stand"), "objective title")
		assert_true(t.contains("Hold it until dawn."), "objective text")


func test_battle_result_from_a_real_battle() -> void:
	var n: Variant = _node_of_type("battle")
	if n == null:
		skip("no battle node")
		return
	var setup := Setup.build_battle(n.encounter, Expedition.battle_army(g), {"title": "Test fight", "darkness": false})
	var b = Battle.new(setup)
	Autoplay.auto_battle(b)
	Expedition.apply_battle(g, b, "Test fight", false)
	hud.refresh()
	assert_eq(hud.dialog_kind(), "battleResult")
	var r: Dictionary = g.expedition.pending.report
	var t := _text_of(hud.get_node("PendingDialog"))
	var title := "Victory" if r.result == "victory" else ("Withdrawal" if r.result == "retreat" else "Defeat")
	assert_true(t.contains(title), "result title")
	assert_true(t.contains("Test fight"), "battle title")
	assert_true(t.contains("Foes"), "foes line")
	assert_true(t.contains("Spoils:"), "spoils line")
	assert_true(t.contains("Experience:"), "experience line")
	_check_buttons("battleResult")
	_press("Retreat home" if r.result == "defeat" else "Continue")
	assert_true(store.called("dismiss"))


func test_camp_actions() -> void:
	g.expedition.pending = {"kind": "camp", "nodeId": g.expedition.current, "done": [], "messages": []}
	g.expedition.supplies.torches = 1
	g.expedition.supplies.tools = 1
	hud.refresh()
	assert_eq(hud.dialog_kind(), "camp")
	var t := _text_of(hud.get_node("PendingDialog"))
	assert_true(t.contains("A sheltered hollow with water and dry wood."))
	_check_buttons("camp")
	var army_n := Expedition.army_soldiers(g).size()
	assert_true(H.button_text(_button("Rest")).contains("(-%d rations: heal the living, recover morale and fatigue)" % army_n))
	for name in ["Watch", "Repair", "Rest"]:
		var b := _button(name)
		if assert_not_null(b, name):
			assert_false(b.disabled, name + " available")
			b.pressed.emit()
			hud.refresh()
			assert_true(_button(name).disabled, name + " done")
	assert_eq(g.expedition.pending.done.size(), 3, "three camp actions")
	t = _text_of(hud.get_node("PendingDialog"))
	for m in g.expedition.pending.messages:
		assert_true(t.contains(str(m).substr(0, 20)), "message shown")
	_press("Break camp")
	assert_true(store.called("dismiss"))


func test_camp_without_supplies() -> void:
	g.expedition.pending = {"kind": "camp", "nodeId": g.expedition.current, "done": [], "messages": []}
	g.expedition.supplies.torches = 0
	g.expedition.supplies.tools = 0
	hud.refresh()
	assert_true(_button("Watch").disabled, "no torches")
	assert_true(_button("Repair").disabled, "no tools")
	assert_false(_button("Rest").disabled, "rest always")


func test_village_search() -> void:
	g.expedition.pending = {"kind": "village", "nodeId": g.expedition.current, "messages": [], "spots": [
		{"label": "The longhouse", "searched": false, "locked": false},
		{"label": "The smithy", "searched": false, "locked": false},
		{"label": "A root cellar", "searched": false, "locked": false},
		{"label": "A locked strongbox", "searched": false, "locked": true}]}
	g.expedition.supplies.tools = 0
	hud.refresh()
	assert_eq(hud.dialog_kind(), "village")
	_check_buttons("village")
	assert_true(H.button_text(_button("Spot0")).contains("Search the longhouse"))
	assert_true(_button("Spot3").disabled, "locked without tools")
	assert_true(H.button_text(_button("Spot3")).contains("(needs 1 tools)"))
	_button("Spot0").pressed.emit()
	hud.refresh()
	if g.expedition.pending != null and g.expedition.pending.kind == "village":
		assert_true(_button("Spot0").disabled, "searched")
		assert_true(H.button_text(_button("Spot0")).contains("(searched)"))
		assert_true(g.expedition.pending.messages.size() > 0, "a find")
		_press("Move on")
		assert_true(store.called("dismiss"))
	else:
		# A search may wake raiders: the dialog becomes a battle briefing.
		assert_eq(hud.dialog_kind(), "battle")


func test_objective_complete() -> void:
	g.expedition.loot = {"silver": 40, "timber": 2, "iron": 0, "trophies": 1}
	g.expedition.pending = {"kind": "complete"}
	hud.refresh()
	assert_eq(hud.dialog_kind(), "complete")
	var t := _text_of(hud.get_node("PendingDialog"))
	assert_true(t.contains("Objective Complete"))
	assert_true(t.contains("Brannsted held."))
	_check_buttons("complete")
	_press("Return to Amberfeld")
	assert_eq(store.calls.back(), ["go_home", "success"])


func test_dialog_keeps_its_modal_while_the_kind_changes() -> void:
	g.expedition.pending = {"kind": "arrive", "nodeId": g.expedition.current}
	hud.refresh()
	var m := hud.get_node("PendingDialog")
	g.expedition.pending = {"kind": "camp", "nodeId": g.expedition.current, "done": [], "messages": []}
	hud.refresh()
	assert_true(is_same(m, hud.get_node("PendingDialog")), "same modal, new content")
	assert_eq(hud.dialog_kind(), "camp")
	g.expedition.pending = null
	hud.refresh()
	assert_false(_live(m), "closed")
