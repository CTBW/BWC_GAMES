## The shared widgets (ports of src/ui/common.tsx): build, values, text.
extends "res://tests/test_case.gd"

const ThemeBuilder = preload("res://scripts/ui/theme_builder.gd")
const UI = preload("res://scripts/ui/ui.gd")
const DB = preload("res://scripts/data/db.gd")
const Game = preload("res://scripts/meta/game.gd")
const Icon = preload("res://scripts/ui/widgets/icon.gd")
const ResList = preload("res://scripts/ui/widgets/res_list.gd")
const Bar = preload("res://scripts/ui/widgets/bar.gd")
const SquadBar = preload("res://scripts/ui/widgets/squad_bar.gd")
const MenPips = preload("res://scripts/ui/widgets/men_pips.gd")
const Tip = preload("res://scripts/ui/widgets/tip.gd")
const Portrait = preload("res://scripts/ui/widgets/portrait.gd")
const Tag = preload("res://scripts/ui/widgets/tag.gd")
const Card = preload("res://scripts/ui/widgets/card.gd")
const RichButton = preload("res://scripts/ui/widgets/rich_button.gd")
const Confirm = preload("res://scripts/ui/widgets/confirm.gd")
const Modal = preload("res://scripts/ui/widgets/modal.gd")
const SoldierCard = preload("res://scripts/ui/widgets/soldier_card.gd")

var host: Control


func before_all() -> void:
	host = Control.new()
	host.theme = ThemeBuilder.theme()
	host.size = Vector2(1920, 1080)
	(Engine.get_main_loop() as SceneTree).root.add_child(host)


func after_all() -> void:
	host.free()


func after_each() -> void:
	for c in host.get_children():
		c.free()


func test_res_list() -> void:
	var r := ResList.make({"silver": 120, "timber": 0, "iron": 3})
	host.add_child(r)
	var labels := r.find_children("*", "Label", true, false)
	assert_eq(labels.size(), 2, "zero amounts are left out")
	assert_eq((labels[0] as Label).text, "120")
	assert_eq((labels[1] as Label).text, "3")
	var none := ResList.make({"silver": 0})
	assert_true(none is Label and (none as Label).text == "Nothing", "empty shows Nothing")
	none.free()


func test_bar() -> void:
	var b := Bar.make(20, 100, "hp")
	assert_eq(b.theme_type_variation, &"HpLowBar", "low hp below 35%")
	assert_almost(b.value, 0.2)
	Bar.update(b, 80, 100, "hp")
	assert_eq(b.theme_type_variation, &"HpBar")
	assert_eq(Bar.variation("cp over", 1.0), "OverBar")
	assert_eq(Bar.variation("morale", 1.0), "MoraleBar")
	var z := Bar.make(5, 0, "xp")
	assert_almost(z.value, 0.0, 1e-9, "max 0 is empty")
	b.free()
	z.free()


## A decorated control often receives its padding before entering the scene.
## Reading the style for a later decoration must retain that local override.
func test_unparented_panel_preserves_explicit_padding() -> void:
	var panel := UI.panel("DarkPanel", [28, 40])
	var style: StyleBox = UI.theme_stylebox(panel).duplicate()
	assert_eq(style.content_margin_top, 28.0)
	assert_eq(style.content_margin_left, 40.0)
	panel.add_theme_stylebox_override("panel", style)
	assert_eq(UI.theme_stylebox(panel).content_margin_bottom, 28.0)
	panel.free()


func test_squad_bar() -> void:
	var b := SquadBar.make(100, 32, 6, 4, 9)
	host.add_child(b)
	assert_eq(b.squad_size, 6)
	assert_eq(b.alive, 4)
	assert_eq(b.tooltip_text, "100/192 HP · 4/6 standing")
	b.set_values(10, 32, 6, 1)
	assert_eq(b.tooltip_text, "10/192 HP · 1/6 standing")
	var g := Game.new_game(5)
	var so: Dictionary = g.roster[0]
	var r := SquadBar.roster(so, 7)
	host.add_child(r)
	assert_true(r.tooltip_text.begins_with("HP %d/" % so.hp), "roster bar label: " + r.tooltip_text)


func test_men_pips() -> void:
	var p := MenPips.make(5, 6)
	host.add_child(p)
	assert_eq(p.tooltip_text, "5 of 6 soldiers are still serving")
	assert_true(p.get_combined_minimum_size().x > 6 * 6, "pips and count")
	p.set_men(1, 3)
	assert_eq(p.tooltip_text, "1 of 3 soldiers is still serving")
	var bare := MenPips.make(2, 6, false)
	host.add_child(bare)
	assert_eq(bare.get_combined_minimum_size().x, 6.0 * 6 + 2 * 5, "pips only")


func test_labels_and_tags() -> void:
	assert_eq(UI.squad_type_label("footman"), "Footmen")
	assert_eq(UI.squad_type_label("footman", 3), "%s Footmen" % DB.RANKS[2])
	assert_eq(UI.squad_type_label("collie_guard", 1, true), "%s Royal Guards" % DB.RANKS[0])
	var s := UI.sign_label(3)
	assert_eq(s.text, "+3")
	assert_eq(s.theme_type_variation, &"GoodLabel")
	var neg := UI.sign_label(-2)
	assert_eq(neg.theme_type_variation, &"BadLabel")
	var zero := UI.sign_label(0)
	assert_eq(zero.text, "0")
	var t := Tag.make("2 short", "red", "cp", 10)
	host.add_child(t)
	assert_eq(t.theme_type_variation, &"TagRed")
	assert_eq(t.find_children("*", "Label", true, false)[0].theme_type_variation, &"TagRedLabel")
	for l in [s, neg, zero]:
		l.free()


## War machines are named for their crew; casters and machines have their own type icons.
func test_specialist_labels_and_icons() -> void:
	assert_eq(UI.squad_type_label("ballista", 2), "%s Ballista Crew" % DB.RANKS[1])
	assert_eq(UI.squad_type_label("mangonel"), "Mangonel Crew")
	assert_eq(UI.squad_type_label("war_wagon"), "Spiked War Wagon Crew")
	assert_eq(UI.squad_type_label("war_wagon", 0, true), "War Wagon Crew", "short name, singular")
	assert_eq(UI.squad_type_label("battle_mage", 1, true), "%s Battle Mages" % DB.RANKS[0])
	assert_eq(UI.squad_type_label("goblin_shaman"), "Goblin Shamans")
	assert_eq(Icon.type_icon_name("battle_mage"), "staff")
	assert_eq(Icon.type_icon_name("goblin_shaman"), "staff")
	for t in ["ballista", "mangonel", "rock_lobber", "war_wagon"]:
		assert_eq(Icon.type_icon_name(t), "engine", t)
	assert_eq(Icon.type_icon_name("crossbowman"), "crossbow")
	assert_eq(Icon.type_icon_name("footman"), "shield")
	for n in ["lightning", "frost", "heal", "circle", "fire", "blood", "gut", "stone", "staff", "engine"]:
		assert_true(Icon.tex(n) != Icon.tex("missing"), "icon %s exported" % n)
	# Every spell's icon exists.
	for id in DB.ABILITIES:
		var ab: Dictionary = DB.ABILITIES[id]
		if ab.get("kind") == "spell":
			assert_true(Icon.NAMES.has(ab.icon), "%s: icon %s" % [id, ab.icon])


## (The test runner works before the scene tree is live, so theme lookups through
## ancestors are checked in the windowed captures instead.)
func test_icon_tint() -> void:
	var i := Icon.make("sound", 18, "Sound on", Color.RED)
	host.add_child(i)
	assert_eq(i.self_modulate, Color.RED, "explicit tint")
	assert_eq(i.tooltip_text, "Sound on")
	assert_eq(i.mouse_filter, Control.MOUSE_FILTER_PASS, "titled icons take the mouse for their tooltip")
	var k := Icon.make("silver", 18)
	host.add_child(k)
	assert_eq(k.self_modulate, Color.WHITE, "coloured icons are not tinted")
	assert_eq(k.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(Icon.tex("no_such_icon"), Icon.tex("missing"), "unknown names fall back")


func test_card_and_rich_button() -> void:
	var clicks := [0]
	var c := Card.make(func(): clicks[0] += 1, true)
	host.add_child(c)
	assert_eq(c.theme_type_variation, &"ParchmentCardSelected")
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	c._gui_input(e)
	assert_eq(clicks[0], 1, "card click")
	c.set_disabled_look(true)
	assert_almost(c.modulate.a, 0.55, 1e-6)
	var b := RichButton.make(["Hire", {"icon": "silver", "size": 14}, "30"], "GoldSmallButton", func(): clicks[0] += 10)
	host.add_child(b)
	assert_true(b.custom_minimum_size.x > 60.0, "sized to its parts")
	b.pressed.emit()
	assert_eq(clicks[0], 11)
	var labels := b.find_children("*", "Label", true, false)
	assert_eq(labels.size(), 2)
	assert_eq((labels[0] as Label).text, "Hire")


func test_portrait() -> void:
	var p := Portrait.make("footman", 2, 56)
	host.add_child(p)
	assert_eq(p.custom_minimum_size, Vector2(56, 56))
	p.set_unit("goblin_spearman", 0, true)
	assert_eq(p.type_id, "goblin_spearman")
	var p2 := Portrait.make("troll", 0, 44, true)
	host.add_child(p2)
	assert_true(p2.dead)


func test_tip_and_confirm_and_modal() -> void:
	var b := UI.button("X", "Button")
	host.add_child(b)
	Tip.attach(b, "[b]Hello[/b] there")
	var tip := b.get_node_or_null("Tip")
	assert_not_null(tip)
	assert_eq(tip.content, "[b]Hello[/b] there")
	Tip.set_content(b, "Other")
	assert_eq(tip.content, "Other")
	assert_true(b.mouse_entered.is_connected(tip._show), "shows on hover")
	var ok := [false]
	var m := Confirm.ask(host, "Sure?", func(): ok[0] = true)
	var okb: Button = m.find_child("OK", true, false)
	assert_not_null(okb)
	okb.pressed.emit()
	assert_true(ok[0], "OK runs the action")
	var closed := [false]
	var d := Modal.dialog(400)
	var md := Modal.make(d, func(): closed[0] = true)
	host.add_child(md)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	md._gui_input(e)
	assert_true(closed[0], "a click on the dimmed back closes")


func test_soldier_card() -> void:
	var g := Game.new_game(9)
	g.roster[0].injuries = ["gashed_arm"]
	g.roster[0].men = 4
	var c := SoldierCard.make(g.roster[0], func(): pass, false, true)
	host.add_child(c)
	var texts: Array = []
	for l in c.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	assert_true(texts.has(g.roster[0].name), "name")
	assert_true(texts.has("2 short"), "short tag: %s" % [texts])
	assert_true(texts.has(DB.INJURIES.gashed_arm.name), "injury tag")
	var sorted := SoldierCard.sort_roster(g.roster)
	assert_eq(sorted[0].typeId, "footman", "line first")
	assert_eq(sorted[sorted.size() - 1].typeId, "crossbowman", "missiles last")


## Play-through finding: a soldier card without tags (no injuries, full
## strength, sound armour) built its tag row and left it unparented, so every
## such card leaked a node (39 HFlowContainer orphans after one play-through,
## "CanvasItem RIDs leaked" at exit). Building and freeing cards leaves nothing.
func test_soldier_card_leaves_no_orphans() -> void:
	var g: Dictionary = Game.new_game(5)
	var so: Dictionary = g.roster[0]
	assert_true(so.injuries.is_empty() and not so.get("recovering", false), "a soldier without tags")
	var before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for i in 5:
		var card: Control = SoldierCard.make(so, Callable(), false, false, [])
		card.free()
	assert_eq(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), before, "no orphan nodes left by cards")
