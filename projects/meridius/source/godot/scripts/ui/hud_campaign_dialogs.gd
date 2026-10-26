## The pending-event dialogs of the campaign screen: port of `PendingDialog`
## in src/ui/screens/Campaign.tsx (one builder per `pending.kind` of
## src/campaign/expedition.ts: arrive, scout, event, battle, battleResult, camp,
## village, complete).
##
##   const Dialogs = preload("res://scripts/ui/hud_campaign_dialogs.gd")
##   Dialogs.build(hud, g, ex, p) -> Dictionary {width: int, content: Control} or {} for none
## The buttons call back into the campaign HUD: hud.do_dismiss(), do_start_battle(),
## do_choose(i), do_camp("watch"|"repair"|"rest"), do_search(i), do_go_home(outcome).
extends RefCounted

const UI = preload("res://scripts/ui/ui.gd")
const H = preload("res://scripts/ui/hud_common.gd")
const DB = preload("res://scripts/data/db.gd")
const Deps = preload("res://scripts/ui/deps.gd")
const Squad = preload("res://scripts/rules/squad.gd")
const Icon = preload("res://scripts/ui/widgets/icon.gd")
const Tag = preload("res://scripts/ui/widgets/tag.gd")
const Card = preload("res://scripts/ui/widgets/card.gd")
const MenPips = preload("res://scripts/ui/widgets/men_pips.gd")
const ResList = preload("res://scripts/ui/widgets/res_list.gd")
const Choice = preload("res://scripts/ui/hud_choice.gd")

const SCOUT_TEXT := "From the high ground the scouts can see for miles: the roads ahead, the bands of the host moving along them, and far to the west the smoke of the host itself. The next stretch of the march is revealed in detail."
const LOSS := Color("#8a1f15")
const WIN := Color("#2d5a1a")


static func build(hud: Object, g: Dictionary, ex: Dictionary, p: Dictionary) -> Dictionary:
	match str(p.get("kind", "")):
		"arrive", "scout":
			return {"width": 560, "content": _arrive(hud, ex, p)}
		"event":
			return {"width": 720, "content": _event(hud, g, ex, p)}
		"battle":
			return {"width": 620, "content": _battle(hud, ex, p)}
		"battleResult":
			return {"width": 640, "content": _result(hud, p)}
		"camp":
			return {"width": 640, "content": _camp(hud, g, ex, p)}
		"village":
			return {"width": 620, "content": _village(hud, ex, p)}
		"complete":
			return {"width": 560, "content": _complete(hud, ex)}
	return {}


static func _node(ex: Dictionary, id: Variant) -> Dictionary:
	for n in ex.nodes:
		if n.id == id:
			return n
	return {"id": id, "name": str(id)}


static func _army(g: Dictionary) -> Array:
	var E = Deps.expedition()
	if E != null:
		return E.army_soldiers(g)
	var out: Array = []
	for id in g.expedition.army:
		for s in g.roster:
			if s.id == id:
				out.append(s)
	return out


static func _primary(text: String, on_press: Callable, big := false) -> Button:
	var b := UI.button(text, "RedBigButton" if big else "RedButton", on_press)
	b.name = text
	return b


static func _p(bbcode: String, italic := false, center := false, cinzel := false) -> Array:
	return [H.para(bbcode, italic, center, cinzel), 8, 8]


# ---------------------------------------------------------------- arrive / scout

static func _arrive(hud: Object, ex: Dictionary, p: Dictionary) -> Control:
	var n := _node(ex, p.get("nodeId"))
	return H.stack([
		[H.title(str(n.name)), 0, 10],
		_p(SCOUT_TEXT if p.kind == "scout" else "The company arrives."),
		[H.center_row([_primary("Continue", hud.do_dismiss)]), 0, 0],
	])


# ---------------------------------------------------------------- event

static func _event(hud: Object, g: Dictionary, ex: Dictionary, p: Dictionary) -> Control:
	var ev: Dictionary = {}
	for e in DB.EVENTS:
		if e.id == p.get("eventId"):
			ev = e
			break
	if ev.is_empty():
		return H.stack([[H.title("?"), 0, 10], [H.center_row([_primary("Continue", hud.do_dismiss)]), 0, 0]])
	var army := _army(g)
	var subject := "A soldier"
	if not army.is_empty():
		subject = str(army[0].name)
	for so in army:
		if so.id == p.get("subject"):
			subject = str(so.name)
	var items: Array = [
		[H.title(str(ev.title)), 0, 10],
		_p(UI.esc(str(ev.text).replace("{name}", subject)), true),
		[H.flourish(), 8, 8],
	]
	var result: Variant = p.get("result")
	if result == null:
		var E = Deps.expedition()
		for i in ev.choices.size():
			var ch: Dictionary = ev.choices[i]
			var ok: Dictionary = E.choice_available(g, ch) if E != null else {"ok": true}
			var hints: Array = []
			if ch.get("hint") != null:
				hints.append(["(%s)" % ch.hint, null])
			if not ok.get("ok", true):
				hints.append(["— %s" % str(ok.get("reason", "")), UI.RED])
			var idx: int = i
			var b := Choice.make(str(ch.label), hints, func(): hud.do_choose(idx), not ok.get("ok", true))
			b.name = "Choice%d" % i
			items.append([b, 6, 6])
	else:
		items.append(_p(UI.esc(str(result.text))))
		var tags := H.flow(6, true)
		for c in result.get("changes", []):
			var cs := str(c)
			tags.add_child(Tag.make(cs, "red" if cs.begins_with("-") else ("green" if cs.begins_with("+") else "gold")))
		items.append([tags, 0, 0])
		items.append([H.center_row([_primary("To arms!" if p.get("followBattle") != null else "Continue", hud.do_dismiss)]), 12, 0])
	return H.stack(items)


# ---------------------------------------------------------------- battle briefing

static func _battle(hud: Object, ex: Dictionary, p: Dictionary) -> Control:
	var roll: Dictionary = p.roll
	var enc: Dictionary = DB.encounter_by_id(roll.encounterId)
	var n := _node(ex, p.get("nodeId"))
	var counts := {}
	for e in roll.enemies:
		counts[e.typeId] = int(counts.get(e.typeId, 0)) + 1
	var title := "Battle"
	if p.get("surprise"):
		title = "Ambush!"
	elif p.get("objective"):
		title = "The Last Stand"
	elif enc.get("kind") == "stand":
		title = "A Stand"
	var text := ""
	if p.get("night"):
		if int(ex.supplies.get("torches", 0)) > 0:
			text = "Goblins rush the camp in the dark! The sentries light torches so the crossbows can see."
		else:
			text = "Goblins rush the camp in the dark, and there are no torches left. Crossbows will be nearly blind."
	elif p.get("surprise"):
		text = "They strike first, from more than one side. Form up where you stand!"
	elif p.get("objective"):
		text = "Night falls over Brannsted. Torches beyond counting are coming down the western road: the whole host, and its warchief. The steading has a palisade, two gates and a breach by the old tower. Hold it until dawn."
	else:
		text = "%s hold %s. There is no going around." % [enc.get("name", ""), n.name]

	# The enemy card.
	var card := Card.make(Callable(), false, false, [9, 9])
	var col := UI.vbox(0)
	col.add_child(H.rich("[b]Enemy[/b]", 13))
	col.add_child(UI.gap(0, 4))
	var tags := H.flow(6)
	for t in counts:
		var k: int = counts[t]
		var def: Dictionary = DB.UNIT_TYPES.get(t, {})
		tags.add_child(Tag.make("%d × %s" % [k, def.get("name", t) if k == 1 else def.get("plural", t)], "red", Icon.type_icon(t, 13)))
	col.add_child(tags)
	var waves: Array = roll.get("waves", []) if roll.get("waves") != null else []
	if waves.size() > 0:
		var horn := false
		var chief := false
		var more := 0
		for w in waves:
			if w.get("horn"):
				horn = true
			more += w.units.size()
			for u in w.units:
				if u.get("warchief"):
					chief = true
		col.add_child(UI.gap(0, 6))
		col.add_child(H.rich("[b]%s[/b] %d more squads%s." % ["If the horn sounds:" if horn else "Then, in waves:", more, ", and the warchief himself" if chief else ""], 13))
	var goal: Variant = enc.get("goal")
	if goal != null:
		col.add_child(UI.gap(0, 6))
		col.add_child(H.rich("[b]%s.[/b] %s" % [UI.esc(str(goal.title)), UI.esc(str(goal.brief))], 13))
	var m: Dictionary = DB.BATTLE_MAPS.get(roll.mapId, {})
	col.add_child(UI.gap(0, 6))
	col.add_child(H.rich("[b]Ground:[/b] %s. %s" % [UI.esc(str(m.get("name", roll.mapId))), UI.esc(str(m.get("description", "")))], 13))
	card.add_child(col)

	return H.stack([
		[H.title(title), 0, 10],
		[H.para(UI.esc(str(p.get("title", ""))), false, true, true), -4, 8],
		_p(UI.esc(text)),
		[card, 0, 0],
		[H.center_row([_primary("To Battle", hud.do_start_battle, true)]), 14, 0],
	])


# ---------------------------------------------------------------- battle result

static func _small(bbcode: String, color := H.NONE) -> RichTextLabel:
	return H.rich(bbcode, 13, color)


static func _result(hud: Object, p: Dictionary) -> Control:
	var r: Dictionary = p.report
	var res := str(r.get("result", "victory"))
	var title := "Victory" if res == "victory" else ("Withdrawal" if res == "retreat" else "Defeat")
	var losses: Variant = r.get("losses")
	var lost_men := 0
	var gone := 0
	if losses != null:
		for l in losses:
			lost_men += int(l.lost)
			if l.fate == "dead" or l.fate == "gone":
				gone += 1

	# Left card: foes, spoils, supplies used.
	var left := Card.make(Callable(), false, false, [9, 9])
	var lc := UI.vbox(0)
	var killed := int(r.get("enemiesKilled", 0))
	var foes := "[b]Foes[/b]: %d %s destroyed, %d fled" % [killed, "squad" if killed == 1 else "squads", int(r.get("enemiesFled", 0))]
	if r.get("enemySoldiersSlain") != null:
		foes += "[color=%s] · %d soldiers slain[/color]" % [H.hex(UI.INK_FAINT), int(r.enemySoldiersSlain)]
	lc.add_child(_small(foes))
	var spoils := UI.hbox(6)
	spoils.add_child(H.text("Spoils:", 13, H.NONE, "alegreya", 700))
	spoils.add_child(ResList.make(r.get("loot", {}), 15, "SmallMutedLabel"))
	lc.add_child(spoils)
	if int(r.get("bandagesUsed", 0)) > 0:
		lc.add_child(_small("%d bandage(s) used on the wounded" % int(r.bandagesUsed)))
	if int(r.get("boltsUsed", 0)) > 0:
		lc.add_child(_small("%d bolts loosed" % int(r.boltsUsed)))
	left.add_child(lc)

	# Right card: losses.
	var right := Card.make(Callable(), false, false, [9, 9])
	var rc := UI.vbox(0)
	if losses != null:
		if lost_men > 0:
			var s := "[b]%d[/b] %s lost" % [lost_men, "soldier" if lost_men == 1 else "soldiers"]
			if gone > 0:
				s += ", %d %s destroyed" % [gone, "squad" if gone == 1 else "squads"]
			rc.add_child(_small(s + ".", LOSS))
		else:
			rc.add_child(_small("Not a soldier was lost."))
	elif r.get("fallen", []).size() > 0:
		rc.add_child(_small("[b]Fallen:[/b] %s" % UI.esc(", ".join(r.fallen.map(func(f): return str(f.name)))), LOSS))
	else:
		rc.add_child(_small("No one was lost."))
	if losses == null:
		for w in r.get("wounded", []):
			rc.add_child(_small("[b]%s[/b] survived: %s" % [UI.esc(str(w.name)), UI.esc(str(w.injury))]))
	if r.get("routed", []).size() > 0:
		rc.add_child(_small("Fled the field: %s" % UI.esc(", ".join(r.routed.map(func(x): return str(x))))))
	right.add_child(rc)

	var grid := UI.grid(2, 8, 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(left)
	grid.add_child(right)

	var items: Array = [
		[H.title(title, 30, WIN if res == "victory" else LOSS), 0, 10],
		[H.para(UI.esc(str(r.get("title", ""))), false, true, true), -6, 8],
		[grid, 0, 0],
	]
	if losses != null and losses.size() > 0:
		var lcard := Card.make(Callable(), false, false, [9, 9])
		var list := UI.vbox(3)
		for l in losses:
			var injury: Variant = null
			for w in r.get("wounded", []):
				if w.name == l.name:
					injury = w.injury
			var fought: bool = l.fate == "fought" or l.fate == "wounded"
			var colour := H.NONE if fought else LOSS
			var first := str(l.name).split(" ")[0]
			var s := "[b]%s[/b]: " % UI.esc(Squad.squad_name(l))
			if l.fate == "gone":
				s += "cut down again while Injured: gone for good (%d lost)." % int(l.lost)
			elif l.fate == "injured":
				s += "cut down to the last; they rise Injured for their next fight."
			elif l.fate == "wounded":
				s += "%d went down; they rise wounded for their next fight." % int(l.fell)
			elif l.fate == "dead":
				s += "wiped out with their sergeant (%d lost)." % int(l.lost)
			elif l.fate == "downed":
				s += "cut down to the last man; %s lives%s. %d lost." % [first, " (%s)" % str(injury).to_lower() if injury != null else "", int(l.lost)]
			elif int(l.lost) > 0:
				s += "lost %d %s, %d/%d remain." % [int(l.lost), "man" if int(l.lost) == 1 else "men", int(l.men), int(l.size)]
			else:
				s += "no one lost, %d/%d remain." % [int(l.men), int(l.size)]
			var saved := int(l.get("saved", 0)) if l.get("saved") != null else 0
			if saved > 0:
				s += "[color=%s] %d of the fallen %s found alive and carried back, badly hurt.[/color]" % [H.hex(UI.INK_FAINT), saved, "was" if saved == 1 else "were"]
			var row := UI.hbox(8)
			var t := _small(s, colour)
			row.add_child(t)
			row.add_child(MenPips.make(int(l.men), int(l.size), false, "", LOSS if not fought else H.NONE))
			list.add_child(row)
		lcard.add_child(list)
		items.append([lcard, 8, 0])
	var ups: Array = r.get("levelUps", [])
	if ups.size() > 0:
		var ucard := Card.make(Callable(), false, false, [9, 9])
		var ul := UI.vbox(0)
		for l in ups:
			ul.add_child(_small("★ %s" % UI.esc(str(l)), Color("#6b4a10")))
		ucard.add_child(ul)
		items.append([ucard, 8, 0])
	var xs: Array = []
	for x in r.get("xp", []):
		xs.append("%s +%d" % [str(x.name).split(" ")[0], int(x.xp)])
	items.append([_small("Experience: %s" % UI.esc(" · ".join(xs)), UI.INK_FAINT), 6, 0])
	items.append([H.center_row([_primary("Retreat home" if res == "defeat" else "Continue", hud.do_dismiss)]), 12, 0])
	return H.stack(items)


# ---------------------------------------------------------------- camp

static func _camp(hud: Object, g: Dictionary, ex: Dictionary, p: Dictionary) -> Control:
	var done: Array = p.get("done", [])
	var army := _army(g)
	var sup: Dictionary = ex.supplies
	var col := UI.vbox(6)
	var watch := Choice.make("Light torches and set a watch ", [["(-1 torch: no night raid)", null]], func(): hud.do_camp("watch"), done.has("watch") or int(sup.get("torches", 0)) < 1)
	watch.name = "Watch"
	var repair := Choice.make("Mend armour and kit ", [["(-1 tools: +40% armour condition)", null]], func(): hud.do_camp("repair"), done.has("repair") or int(sup.get("tools", 0)) < 1)
	repair.name = "Repair"
	var rest := Choice.make("Eat a hot meal and sleep ", [["(-%d rations: heal the living, recover morale and fatigue)" % army.size(), null]], func(): hud.do_camp("rest"), done.has("rest"))
	rest.name = "Rest"
	for c in [watch, repair, rest]:
		col.add_child(H.margin(c, 6, 0, 6, 0))
	var items: Array = [
		[H.title(str(_node(ex, p.get("nodeId")).name)), 0, 10],
		_p("A sheltered hollow with water and dry wood. Night is falling. What will the company do?"),
		[col, 0, 0],
	]
	for m in p.get("messages", []):
		items.append([H.para(UI.esc(str(m))), 6, 6])
	items.append([H.center_row([_primary("Break camp", hud.do_dismiss)]), 10, 0])
	return H.stack(items)


# ---------------------------------------------------------------- village

static func _village(hud: Object, ex: Dictionary, p: Dictionary) -> Control:
	var col := UI.vbox(6)
	var spots: Array = p.get("spots", [])
	for i in spots.size():
		var sp: Dictionary = spots[i]
		var hints: Array = []
		if sp.get("locked"):
			hints.append(["(needs 1 tools)", null])
		if sp.get("searched"):
			hints.append(["(searched)", null])
		var idx: int = i
		var b := Choice.make("Search %s " % str(sp.label).to_lower(), hints, func(): hud.do_search(idx), bool(sp.get("searched")) or (bool(sp.get("locked")) and int(ex.supplies.get("tools", 0)) < 1))
		b.name = "Spot%d" % i
		col.add_child(H.margin(b, 6, 0, 6, 0))
	var items: Array = [
		[H.title(str(_node(ex, p.get("nodeId")).name)), 0, 10],
		_p("The village is empty. Doors hang open; the raiders were thorough, but not everything was found."),
		[col, 0, 0],
	]
	for m in p.get("messages", []):
		items.append([H.para(UI.esc(str(m))), 6, 6])
	items.append([H.center_row([_primary("Move on", hud.do_dismiss)]), 10, 0])
	return H.stack(items)


# ---------------------------------------------------------------- objective complete

static func _complete(hud: Object, ex: Dictionary) -> Control:
	var spoils := UI.hbox(0)
	spoils.alignment = BoxContainer.ALIGNMENT_CENTER
	var lbl := UI.label("Spoils: ", "", 17)
	spoils.add_child(lbl)
	spoils.add_child(ResList.make(ex.get("loot", {})))
	var b := _primary("Return to Amberfeld", func(): hud.do_go_home("success"), true)
	return H.stack([
		[H.title("Objective Complete", 30, WIN), 0, 10],
		_p("Brannsted held. When the sun came up the Margrave's riders came over the hill, and the host broke against them and ran for the woods. The country west of the Vattern is saved, for now, by the Amberfeld Company.", false, true),
		[spoils, 8, 8],
		[H.center_row([b]), 0, 0],
	])
