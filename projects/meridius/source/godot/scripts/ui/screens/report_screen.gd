## Port of src/ui/screens/Report.tsx: the expedition report over the dimmed
## camp — outcome title, spoils and reward, losses and the squads that came
## back, advice, and "Back to Amberfeld".
extends Control

const UI = preload("res://scripts/ui/ui.gd")
const DB = preload("res://scripts/data/db.gd")
const Deps = preload("res://scripts/ui/deps.gd")
const Modal = preload("res://scripts/ui/widgets/modal.gd")
const ResList = preload("res://scripts/ui/widgets/res_list.gd")
const MenPips = preload("res://scripts/ui/widgets/men_pips.gd")
const SoldierCard = preload("res://scripts/ui/widgets/soldier_card.gd")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	refresh()


var _sig := ""


func refresh() -> void:
	var sig := str(JSON.stringify([App.report, App.game]).hash())
	if sig == _sig and get_child_count() > 0:
		return
	_sig = sig
	UI.clear(self)
	var r: Variant = App.report if App.report != null else (App.game.get("lastReport") if App.game != null else null)
	if r == null:
		var b := UI.button("Continue", "Button", func(): App.go_base())
		b.name = "Continue"
		add_child(b)
		return
	var g: Variant = App.game
	var Game = Deps.game()
	var Soldier = Deps.soldier()
	var c := DB.campaign_by_id(r.campaignId)
	var roster: Array = g.roster if g != null else []
	var wounded := 0
	var worn := 0
	var thin := 0
	for so in roster:
		if so.injuries.size() > 0:
			wounded += 1
		if so.morale < Soldier.soldier_stats(so).morale * 0.5:
			worn += 1
		if Game.missing_men(so) > 0:
			thin += 1
	var advice_parts: Array = ["New recruits wait at the barracks."]
	if thin:
		advice_parts.append("%s below strength; the Barracks can refill the ranks." % ("One squad is" if thin == 1 else "%d squads are" % thin))
	if wounded:
		advice_parts.append("%s the surgeon." % ("One sergeant needs" if wounded == 1 else "%d sergeants need" % wounded))
	if worn:
		advice_parts.append("%s worn down and may want leave." % ("One is" if worn == 1 else "%d are" % worn))
	var advice := " ".join(advice_parts)
	var title := "Triumph" if r.outcome == "success" else ("The Long Road Home" if r.outcome == "retreat" else "A Broken Company")
	var line := ""
	if r.outcome == "success":
		line = "The company returns from %s: Brannsted held until dawn, and the host was turned." % c.name
	elif r.outcome == "retreat":
		line = "The company turns back from %s before the objective was met." % c.name
	else:
		line = "What is left of the company limps back from %s. Half the spoils were lost in the rout." % c.name

	var d := Modal.dialog(660)
	var col := UI.vbox(0)
	d.add_child(col)
	col.add_child(UI.title_block(title, 32, Color("#2d5a1a") if r.outcome == "success" else Color("#8a1f15")))
	col.add_child(UI.rich("[center]%s[/center]" % UI.esc(line), "DialogText"))
	col.add_child(UI.gap(0, 8))

	var grid := UI.grid(2, 8, 8)
	col.add_child(grid)
	# Spoils card.
	var left := UI.panel("ParchmentCard")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lc := UI.vbox(0)
	left.add_child(lc)
	var spoils := UI.hbox(6)
	spoils.add_child(UI.rich("[b]Spoils:[/b]", "SmallText"))
	spoils.get_child(0).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	spoils.get_child(0).autowrap_mode = TextServer.AUTOWRAP_OFF
	spoils.add_child(ResList.make(r.loot, 16, "SmallMutedLabel"))
	lc.add_child(spoils)
	if (r.reward as Dictionary).size() > 0:
		var rw := UI.hbox(6)
		var rl := UI.rich("[b]Reward:[/b]", "SmallText")
		rl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		rl.autowrap_mode = TextServer.AUTOWRAP_OFF
		rw.add_child(rl)
		rw.add_child(ResList.make(r.reward, 16, "SmallMutedLabel"))
		lc.add_child(rw)
	lc.add_child(UI.label("Leftover supplies sold: %d silver" % r.buyback, "SmallLabel"))
	if r.stipend > 0:
		lc.add_child(UI.label("Council stipend: %d silver" % r.stipend, "SmallLabel"))
	lc.add_child(UI.label("%d marches · %d battles" % [r.marches, r.battles], "SmallMutedLabel"))
	grid.add_child(left)
	# Losses card.
	var right := UI.panel("ParchmentCard")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rc := UI.vbox(0)
	right.add_child(rc)
	if (r.fallen as Array).size() > 0:
		rc.add_child(UI.rich("[color=#8a1f15][b]Squads lost:[/b] %s[/color]" % UI.esc(", ".join(r.fallen)), "SmallText"))
	else:
		rc.add_child(UI.label("Every squad came home.", "SmallLabel"))
	var men_lost: Variant = r.get("menLost")
	if men_lost != null:
		var txt := ("%d %s died on the expedition." % [men_lost, "soldier" if men_lost == 1 else "soldiers"]) if men_lost else "Not a soldier was lost."
		rc.add_child(UI.label(txt, "LossLabel" if men_lost else "SmallLabel"))
	var strength: Variant = r.get("strength")
	if strength is Array:
		var losses := UI.vbox(2)
		rc.add_child(UI.gap(0, 4))
		rc.add_child(losses)
		var head := UI.rich("[b]Returned:[/b]%s" % (" no one" if (strength as Array).is_empty() else ""), "SmallText")
		losses.add_child(head)
		var Squad = Deps.squad()
		for q in strength:
			var row := UI.hbox(8)
			var nm: String = Squad.squad_name(q) if Squad != null and Squad.has_method("squad_name") else str(q.name)
			var nl := UI.label(nm, "SmallLabel")
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(nl)
			if q.get("wound") != null:
				row.add_child(SoldierCard.wound_chip(q.wound, 10))
			row.add_child(MenPips.make(q.men, q.size))
			losses.add_child(row)
	else:
		rc.add_child(UI.gap(0, 4))
		var who := ", ".join(r.survivors) if (r.survivors as Array).size() > 0 else "no one"
		rc.add_child(UI.rich("[b]Returned:[/b] %s" % UI.esc(who), "SmallText"))
	grid.add_child(right)

	col.add_child(UI.gap(0, 8))
	var adv := UI.rich("[center]%s[/center]" % UI.esc(advice), "SmallMutedText")
	col.add_child(adv)
	col.add_child(UI.gap(0, 8))
	var row := UI.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var back := UI.button("Back to Amberfeld", "RedBigButton", func(): App.go_base())
	back.name = "BackToAmberfeld"
	row.add_child(back)
	col.add_child(row)
	add_child(Modal.make(d, Callable(), false))

