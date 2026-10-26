## Port of Base.tsx `BuildingPanel`, `BuildingBody` and `Pips`: a building's
## dialog — name, role, level pips, the body for that building, and the upgrade
## row (cost, Build) with Close.
##   command        campaigns with slots / command points, Plan an expedition
##   barracks       recruits (hire / take on volunteer), reinforcements (+1, Refill,
##                  Refill all), leave and recovery (Grant leave)
##   training       Drill and Promote per squad
##   armoury        Repair, weapon and armour upgrades per squad
##   infirmary      Treat each lasting injury
##   quartermaster  supply prices and weights (bought when planning)
##
##   const BuildingPanel = preload("res://scripts/ui/screens/building_panel.gd")
##   BuildingPanel.make(id: String, viewport_h := 1080.0) -> PanelContainer
extends RefCounted

const UI = preload("res://scripts/ui/ui.gd")
const DB = preload("res://scripts/data/db.gd")
const JS = preload("res://scripts/core/js.gd")
const Deps = preload("res://scripts/ui/deps.gd")
const Modal = preload("res://scripts/ui/widgets/modal.gd")
const ScrollBox = preload("res://scripts/ui/widgets/scroll_box.gd")
const Flourish = preload("res://scripts/ui/widgets/flourish.gd")
const ResList = preload("res://scripts/ui/widgets/res_list.gd")
const Icon = preload("res://scripts/ui/widgets/icon.gd")
const Tag = preload("res://scripts/ui/widgets/tag.gd")
const Tip = preload("res://scripts/ui/widgets/tip.gd")
const Portrait = preload("res://scripts/ui/widgets/portrait.gd")
const MenPips = preload("res://scripts/ui/widgets/men_pips.gd")
const RichButton = preload("res://scripts/ui/widgets/rich_button.gd")
const SoldierCard = preload("res://scripts/ui/widgets/soldier_card.gd")


## act(): a successful action plays its sound and saves; a refused one says no.
static func act(ok: bool, sound := "coin") -> void:
	if ok:
		App.sfx(sound)
		App.commit()
	else:
		App.sfx("deny")


static func make(id: String, viewport_h := 1080.0) -> PanelContainer:
	var g: Dictionary = App.game
	var Game = Deps.game()
	var b := DB.building_by_id(id)
	var lvl: int = Game.level(g, id)
	var cur: Dictionary = b.levels[lvl - 1]
	var nl: Variant = Game.next_level(g, id)
	var d := Modal.dialog(760)
	d.name = "BuildingPanel_" + id
	var col := UI.vbox(0)
	d.add_child(col)
	# Header.
	var head := UI.hbox(8)
	var left := UI.vbox(0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(UI.label(cur.name, "H2Label"))
	left.add_child(UI.label(b.role, "MutedLabel"))
	head.add_child(left)
	var right := UI.vbox(0)
	var pips := ""
	for i in b.levels.size():
		pips += "◆" if i < lvl else "◇"
	var pl := UI.label(pips, "PipsLabel")
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(pl)
	var ll := UI.label("Level %d" % lvl, "SmallMutedLabel")
	ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(ll)
	head.add_child(right)
	var head_band := UI.panel("BannerPanel", [12, 18])
	head_band.add_child(head)
	col.add_child(head_band)
	col.add_child(Flourish.make())
	var body := body_for(id, g, viewport_h)
	var scroll := ScrollBox.make(body, viewport_h * 0.54, 4)
	scroll.name = "Body"
	col.add_child(scroll)
	col.add_child(Flourish.make())
	# Upgrade row.
	var foot := UI.hbox(8)
	if nl != null:
		var up := UI.hbox(12)
		up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t := UI.vbox(0)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.add_child(UI.cinzel("Upgrade to %s" % nl.name))
		t.add_child(UI.rich(UI.esc(nl.description), "SmallText"))
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		up.add_child(t)
		var cost := ResList.make(nl.cost)
		up.add_child(cost)
		var build := UI.button("Build", "GoldButton", func():
			if Game.upgrade_building(App.game, id):
				App.sfx("build")
				App.commit())
		build.name = "Build"
		build.disabled = not Game.can_afford(g, nl.cost)
		build.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		up.add_child(build)
		foot.add_child(up)
	else:
		var fu := UI.label("Fully upgraded.", "MutedLabel")
		fu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(fu)
	var close := UI.button("Close", "Button", func(): App.open_panel(null))
	close.name = "Close"
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(close)
	col.add_child(foot)
	return d


static func body_for(id: String, g: Dictionary, viewport_h := 1080.0) -> Control:
	match id:
		"command":
			return _command(g)
		"barracks":
			return _barracks(g)
		"training":
			return _training(g)
		"armoury":
			return _armoury(g)
		"infirmary":
			return _infirmary(g)
		"quartermaster":
			return _quartermaster(g)
	return UI.vbox()


static func _h3(text: String) -> Label:
	return UI.label(text, "HeadingLabel")


static func _tip_text(bb: String, reason: Variant) -> String:
	if reason != null and str(reason) != "":
		return "%s\n[color=#ffb0a0]%s[/color]" % [bb, UI.esc(str(reason))]
	return bb


# ---------------------------------------------------------------- command

static func _command(g: Dictionary) -> Control:
	var Game = Deps.game()
	var col := UI.vbox(6)
	col.add_child(UI.rich("The map table shows the frontier from Karstenburg to the Vattern. From here the company plans its expeditions. A larger staff lets you field more soldiers.", "BodyText"))
	for c in Game.available_campaigns(g):
		var lim: Dictionary = Game.army_limits(g, c)
		var card := UI.panel("ParchmentCard")
		var cc := UI.vbox(0)
		card.add_child(cc)
		var top := UI.hbox(8)
		var nm := UI.cinzel(c.name)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(nm)
		top.add_child(Tag.make("Tier %s · %s" % [JS.num_str(c.tier), c.tierName], "gold"))
		cc.add_child(top)
		cc.add_child(UI.rich(UI.esc(c.blurb), "SmallText"))
		cc.add_child(UI.gap(0, 6))
		var stats := UI.hbox(14)
		var s1 := UI.hbox(4, [Icon.make("slot"), UI.label("%d unit slots" % lim.slots, "SmallLabel")])
		var s2 := UI.hbox(4, [Icon.make("cp"), UI.label("%d command points" % lim.command, "SmallLabel")])
		stats.add_child(s1)
		stats.add_child(s2)
		stats.add_child(UI.label("Completed %d×" % JS.get_or(g.completed, c.id, 0), "SmallMutedLabel"))
		cc.add_child(stats)
		col.add_child(card)
	col.add_child(UI.label("Harder campaign tiers open in later builds as the company grows.", "SmallMutedLabel"))
	var row := UI.hbox()
	var plan := UI.button("Plan an expedition", "RedButton", func(): App.go_prep())
	plan.name = "PlanExpedition"
	row.add_child(plan)
	col.add_child(row)
	return col


# ---------------------------------------------------------------- barracks

static func _barracks(g: Dictionary) -> Control:
	var Game = Deps.game()
	var Soldier = Deps.soldier()
	var col := UI.vbox(6)
	var cap: int = Game.roster_cap(g)
	var low: Array = g.roster.filter(func(so): return so.morale < Soldier.soldier_stats(so).morale)
	var thin: Array = g.roster.filter(func(so): return Game.missing_men(so) > 0)
	JS.sort(thin, func(a, b): return (Game.missing_men(b) - Game.missing_men(a)) if Game.missing_men(b) != Game.missing_men(a) else (b.level - a.level))
	var refill_all := 0
	for so in thin:
		refill_all += Game.missing_men(so) * Game.reinforce_cost(g, so)
	# Recruits.
	var head := UI.hbox(8)
	var h := _h3("Recruits at the gate")
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(h)
	head.add_child(UI.label("Roster %d/%d squads · New squads arrive after each expedition" % [g.roster.size(), cap], "SmallLabel"))
	col.add_child(head)
	if g.recruits.is_empty():
		col.add_child(UI.label("No one else answers the muster this time.", "MutedLabel"))
	var cards: Array = []
	for r in g.recruits:
		var cost: int = Game.recruit_cost(r)
		var def: Dictionary = DB.UNIT_TYPES[r.typeId]
		var card := UI.panel("ParchmentCard")
		card.name = "Recruit_" + str(r.id)
		var row := UI.hbox(8)
		card.add_child(row)
		row.add_child(Portrait.make(r.typeId, r.portrait, 54))
		var info := UI.vbox(0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.ellipsize(UI.cinzel(r.name, 14)))
		info.add_child(UI.rich("%s [color=#8a7356]· %s[/color]" % [UI.squad_type_label(r.typeId, r.level), def.role], "SmallText"))
		var meta := UI.hbox(8)
		meta.add_child(MenPips.make(r.men, DB.squad_size(r.typeId), true, "", UI.INK_FAINT))
		meta.add_child(UI.hbox(3, [Icon.make("cp", 14), UI.label("%d CP" % Soldier.command_cost(r), "SmallMutedLabel")]))
		if r.typeId == "collie_guard":
			meta.add_child(Tag.make("Elite", "gold", "", 10))
		# The muster's specialist: battle mages or a war machine, with what it does.
		var specialist: bool = def.has("crew") or (def.get("tags", []) as Array).has("caster")
		if specialist:
			var spec := Tag.make("War machine" if def.has("crew") else "Mages", "blue", "", 10)
			spec.name = "Specialist"
			meta.add_child(spec)
		info.add_child(meta)
		if specialist:
			var blurb := UI.rich(UI.esc(str(def.blurb)), "TinyMutedText")
			blurb.name = "SpecialistBlurb"
			info.add_child(UI.gap(0, 2))
			info.add_child(blurb)
		row.add_child(info)
		var hire: Button
		if cost == 0:
			hire = UI.button("Take on volunteer", "GoldSmallButton")
		else:
			hire = RichButton.make(["Hire", {"icon": "silver", "size": 14}, str(cost)], "GoldSmallButton")
		hire.name = "Hire"
		hire.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		hire.disabled = g.resources.silver < cost or g.roster.size() >= cap
		var rid: String = r.id
		hire.pressed.connect(func(): act(Game.hire(App.game, rid)))
		row.add_child(hire)
		cards.append(card)
	if not cards.is_empty():
		col.add_child(UI.equal_grid(cards, 2, 8, 8))
	if Game.level(g, "barracks") < 2:
		col.add_child(UI.rich("A proper Barracks (level 2) draws the Border Collie Royal Guard to the gate now and then.", "SmallMutedText"))
	col.add_child(UI.rich("Each muster one specialist squad also offers its service: three battle mages, or a ballista or mangonel with its crew.", "SmallMutedText"))
	col.add_child(Flourish.make())
	# Reinforcements.
	var rh := UI.hbox(8)
	var rt := _h3("Reinforcements")
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rh.add_child(rt)
	if thin.size() > 1:
		var all_b := RichButton.make(["Refill all", {"icon": "silver", "size": 14}, str(refill_all)], "GoldSmallButton", func():
			var ok := false
			for so in thin.duplicate():
				var s2: Variant = _find_soldier(App.game, so.id)
				if s2 != null:
					ok = Game.reinforce(App.game, so.id, Game.missing_men(s2)) or ok
			act(ok))
		all_b.name = "RefillAll"
		all_b.disabled = g.resources.silver < refill_all
		Tip.attach(all_b, ("Fill every empty place in the company for %d silver." % refill_all) if g.resources.silver >= refill_all else "Needs %d silver." % refill_all)
		rh.add_child(all_b)
	col.add_child(rh)
	col.add_child(UI.rich("The dead stay dead: rest and surgeons heal the survivors, and only new soldiers from the Barracks fill a squad's empty places. Each arrives fit and drilled to the squad's rank.", "SmallMutedText"))
	for so in thin:
		var miss: int = Game.missing_men(so)
		var rc: int = Game.reinforce_cost(g, so)
		var one: Dictionary = Game.can_reinforce(g, so, 1)
		var all: Dictionary = Game.can_reinforce(g, so, miss)
		var short := UI.vbox(0)
		short.custom_minimum_size.x = 92
		var s1 := UI.label("%d short" % miss, "SmallLabel")
		s1.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		short.add_child(s1)
		var s2 := UI.label("%d silver each" % rc, "TinyMutedLabel")
		s2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		short.add_child(s2)
		var sid: String = so.id
		var plus := RichButton.make(["+1", {"icon": "silver", "size": 14}, str(rc)], "GoldSmallButton", func(): act(Game.reinforce(App.game, sid)))
		plus.name = "PlusOne"
		plus.disabled = not one.ok
		Tip.attach(plus, ("One new %s joins %s's squad (%d silver)." % [DB.UNIT_TYPES[so.typeId].name.to_lower(), so.name, rc]) if one.ok else str(one.get("reason", "")))
		var trailing: Array = [short, plus]
		if miss > 1:
			var refill := RichButton.make(["Refill", {"icon": "silver", "size": 14}, str(rc * miss)], "GoldSmallButton", func(): act(Game.reinforce(App.game, sid, miss)))
			refill.name = "Refill"
			refill.disabled = not all.ok
			Tip.attach(refill, ("Bring the squad to full strength: %d soldiers for %d silver." % [miss, rc * miss]) if all.ok else str(all.get("reason", "")))
			trailing.append(refill)
		col.add_child(SoldierCard.row(so, trailing))
	if thin.is_empty():
		col.add_child(UI.label("Every squad stands at full strength.", "SmallMutedLabel"))
	col.add_child(Flourish.make())
	# Leave.
	col.add_child(_h3("Leave and recovery"))
	col.add_child(UI.rich("Squads who stay home recover 20 morale per expedition. Leave restores morale fully, but the squad sits out the next expedition. Cost %d silver." % Game.leave_cost(g), "SmallMutedText"))
	for so in low:
		var sid: String = so.id
		var leave := UI.button("Grant leave", "SmallButton", func(): act(Game.grant_leave(App.game, sid)))
		leave.name = "GrantLeave"
		leave.disabled = so.get("recovering", false) == true or g.resources.silver < Game.leave_cost(g)
		col.add_child(SoldierCard.row(so, [leave]))
	if low.is_empty():
		col.add_child(UI.label("Everyone's spirits are high.", "SmallMutedLabel"))
	return col


static func _find_soldier(g: Dictionary, id: String) -> Variant:
	for so in g.roster:
		if so.id == id:
			return so
	return null


# ---------------------------------------------------------------- training

static func _training(g: Dictionary) -> Control:
	var Game = Deps.game()
	var col := UI.vbox(6)
	var promo: Variant = Game.effect(g, "training", "promote")
	var pc: Dictionary = Game.promote_cost(g)
	var intro := "Drill grants 10 XP (once per squad per expedition) up to %s rank. %s" % [UI.rank_name(int(Game.effect(g, "training", "drillMaxLevel"))),
		("Veterans can be promoted to learn a second ability (%d silver, %d iron)." % [pc.silver, pc.iron]) if promo else "Upgrade the yard to promote veterans."]
	col.add_child(UI.rich(intro, "SmallMutedText"))
	for so in g.roster:
		var d: Dictionary = Game.can_drill(g, so)
		var p: Dictionary = Game.can_promote_here(g, so)
		var promo_ab: Variant = DB.UNIT_TYPES[so.typeId].get("promotion")
		var xp := UI.vbox(0)
		xp.custom_minimum_size.x = 110
		xp.add_child(UI.label("XP %d%s" % [so.xp, " · Promoted" if so.get("promoted") else ""], "TinyMutedLabel"))
		var sid: String = so.id
		var drill := UI.button("Drill %d" % Game.drill_cost(g, so), "SmallButton", func(): act(Game.drill(App.game, sid)))
		drill.name = "Drill"
		drill.disabled = not d.ok
		Tip.attach(drill, ("Costs %d silver." % Game.drill_cost(g, so)) if d.ok else str(d.get("reason", "")))
		var trailing: Array = [xp, drill]
		if promo_ab and not so.get("promoted"):
			var A: Dictionary = DB.ABILITIES[promo_ab]
			var pb := UI.button("Promote", "GoldSmallButton", func(): act(Game.promote(App.game, sid), "build"))
			pb.name = "Promote"
			pb.disabled = not p.ok
			Tip.attach(pb, _tip_text("[b]%s[/b]: %s" % [A.name, UI.esc(A.description)], null if p.ok else p.get("reason", "")), true)
			trailing.append(pb)
		col.add_child(SoldierCard.row(so, trailing))
	return col


# ---------------------------------------------------------------- armoury

static func _bonus_text(bonus: Dictionary) -> String:
	var parts: Array = []
	for k in bonus:
		parts.append("+%s %s" % [JS.num_str(bonus[k]), k])
	return ", ".join(parts)


static func _armoury(g: Dictionary) -> Control:
	var Game = Deps.game()
	var col := UI.vbox(6)
	col.add_child(UI.rich("Armour wears down with every blow taken. Worn armour protects less. The smith forges tier %s gear." % JS.num_str(Game.effect(g, "armoury", "tier")), "SmallMutedText"))
	for so in g.roster:
		var wn: Variant = Game.next_equip(g, so, "weapon")
		var an: Variant = Game.next_equip(g, so, "armor")
		var wc: Dictionary = Game.can_buy_equip(g, so, "weapon")
		var ac: Dictionary = Game.can_buy_equip(g, so, "armor")
		var rc: int = Game.repair_cost(g, so)
		var sid: String = so.id
		var rep_col := UI.vbox(3)
		rep_col.add_child(UI.label("Armour %d%%" % JS.rnd(so.armorCondition * 100.0), "TinyLabel"))
		var rep := UI.button("Repair %s" % (str(rc) if rc > 0 else ""), "SmallButton", func(): act(Game.repair(App.game, sid), "build"))
		rep.name = "Repair"
		rep.disabled = rc <= 0 or g.resources.silver < rc
		rep_col.add_child(rep)
		var trailing: Array = [rep_col]
		if wn != null:
			var wb := RichButton.make([{"icon": "sword", "size": 14}, "T%s" % JS.num_str(wn.tier), ResList.make(wn.cost, 12)], "GoldSmallButton", func(): act(Game.buy_equip(App.game, sid, "weapon"), "build"))
			wb.name = "BuyWeapon"
			wb.disabled = not wc.ok
			Tip.attach(wb, _tip_text("%s: %s" % [UI.esc(wn.name), _bonus_text(wn.bonus)], null if wc.ok else wc.get("reason", "")))
			trailing.append(wb)
		if an != null:
			var ab := RichButton.make([{"icon": "shield", "size": 14}, "T%s" % JS.num_str(an.tier), ResList.make(an.cost, 12)], "GoldSmallButton", func(): act(Game.buy_equip(App.game, sid, "armor"), "build"))
			ab.name = "BuyArmour"
			ab.disabled = not ac.ok
			Tip.attach(ab, _tip_text("%s: %s" % [UI.esc(an.name), _bonus_text(an.bonus)], null if ac.ok else ac.get("reason", "")))
			trailing.append(ab)
		# The gear buttons are wide: the name and bar columns give way (CSS flex-shrink).
		col.add_child(SoldierCard.row(so, trailing, Callable(), 150, 92))
	return col


# ---------------------------------------------------------------- infirmary

static func _infirmary(g: Dictionary) -> Control:
	var Game = Deps.game()
	var col := UI.vbox(6)
	var hurt: Array = g.roster.filter(func(so): return so.injuries.size() > 0)
	var intro := "A sergeant's lasting injury weakens the whole squad until treated. Treatment benches the squad for the next expedition."
	col.add_child(UI.rich(intro, "SmallMutedText"))
	if hurt.is_empty():
		col.add_child(UI.rich("The cots are empty. Long may it last.", "BodyText"))
	for so in hurt:
		var bcol := UI.vbox(6)
		var sid: String = so.id
		for inj in so.injuries:
			var I: Dictionary = DB.INJURIES[inj]
			var cost: int = Game.treat_cost(g, inj)
			var iid: String = inj
			var tb := UI.button("Treat %s · %d" % [I.name, cost], "SmallButton", func(): act(Game.treat(App.game, sid, iid)))
			tb.name = "Treat_" + iid
			tb.disabled = g.resources.silver < cost
			var effs: Array = []
			for k in I.effect:
				effs.append("%s %s" % [JS.num_str(I.effect[k]), k])
			Tip.attach(tb, UI.esc("%s %s" % [I.description, ", ".join(effs)]))
			bcol.add_child(tb)
		col.add_child(SoldierCard.row(so, [bcol]))
	return col


# ---------------------------------------------------------------- quartermaster

static func _quartermaster(g: Dictionary) -> Control:
	var Game = Deps.game()
	var col := UI.vbox(6)
	col.add_child(UI.rich("Wagon capacity [b]%d[/b]. Leftover supplies are bought back at %d%% when the company returns." % [Game.wagon_capacity(g), JS.rnd(float(Game.effect(g, "quartermaster", "buyback")) * 100.0)], "SmallText"))
	for k in DB.SUPPLY_ORDER:
		var S: Dictionary = DB.SUPPLIES[k]
		var card := UI.panel("ParchmentCard")
		var row := UI.hbox(8)
		card.add_child(row)
		row.add_child(Icon.make(k, 28))
		var info := UI.vbox(0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.cinzel(S.name))
		info.add_child(UI.rich(UI.esc(S.description), "SmallText"))
		row.add_child(info)
		var price := UI.vbox(0)
		price.custom_minimum_size.x = 90
		var pr := UI.hbox(4, [Icon.make("silver", 14), UI.label(str(Game.supply_price(g, k)), "SmallLabel")])
		pr.alignment = BoxContainer.ALIGNMENT_END
		price.add_child(pr)
		var w := UI.label("weight %s" % JS.num_str(S.weight), "SmallMutedLabel")
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price.add_child(w)
		price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(price)
		col.add_child(card)
	col.add_child(UI.label("Supplies are bought when planning an expedition.", "SmallMutedLabel"))
	return col
