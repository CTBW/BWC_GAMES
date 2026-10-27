## Port of Roster.tsx `SoldierDetail`: one squad in full — portrait, the
## sergeant's name (editable; saved on close), rank/type/strength/CP, blurb,
## experience / squad HP / morale bars, the stat grid, equipment, abilities,
## lasting injuries, wounds from the last fight, reinforcement of empty places (at home), Discharge
## (asks first, at home) and Close. Used by the base screen and the campaign HUD.
##
##   const SoldierDetail = preload("res://scripts/ui/screens/soldier_detail.gd")
##   var overlay: Control = SoldierDetail.make(id)   # full-rect modal; closes through App.open_soldier(null)
##   overlay.close()                                 # saves a changed name, then closes
extends Control

const UI = preload("res://scripts/ui/ui.gd")
const DB = preload("res://scripts/data/db.gd")
const JS = preload("res://scripts/core/js.gd")
const Deps = preload("res://scripts/ui/deps.gd")
const Modal = preload("res://scripts/ui/widgets/modal.gd")
const Portrait = preload("res://scripts/ui/widgets/portrait.gd")
const Icon = preload("res://scripts/ui/widgets/icon.gd")
const Tag = preload("res://scripts/ui/widgets/tag.gd")
const Bar = preload("res://scripts/ui/widgets/bar.gd")
const SquadBar = preload("res://scripts/ui/widgets/squad_bar.gd")
const MenPips = preload("res://scripts/ui/widgets/men_pips.gd")
const Tip = preload("res://scripts/ui/widgets/tip.gd")
const RichButton = preload("res://scripts/ui/widgets/rich_button.gd")
const Confirm = preload("res://scripts/ui/widgets/confirm.gd")
const Flourish = preload("res://scripts/ui/widgets/flourish.gd")
const PaperStyle = preload("res://scripts/ui/styles/paper_style.gd")

var soldier_id := ""
var name_edit: LineEdit
var _modal: Control


static func make(id: String) -> Control:
	var d: Control = load("res://scripts/ui/screens/soldier_detail.gd").new()
	d.soldier_id = id
	d.name = "SoldierDetail"
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	d.refresh()
	return d


func _find() -> Variant:
	if App.game == null:
		return null
	for x in App.game.roster:
		if x.id == soldier_id:
			return x
	return null


## Rebuilds from the game state (keeps a name being typed).
func refresh() -> void:
	var typed := name_edit.text if name_edit != null else ""
	UI.clear(self)
	var so: Variant = _find()
	if so == null:
		return
	var g: Dictionary = App.game
	var Game = Deps.game()
	var Soldier = Deps.soldier()
	var def: Dictionary = DB.UNIT_TYPES[so.typeId]
	var st: Dictionary = Soldier.soldier_stats(so)
	var dmg: Dictionary = Soldier.soldier_damage(so)
	var nx: Variant = Soldier.xp_to_next(so)
	var weapon: Variant = DB.EQUIPMENT[def.weaponLine].tiers[so.weaponTier - 1] if def.get("weaponLine") else null
	var armor: Variant = DB.EQUIPMENT[def.armorLine].tiers[so.armorTier - 1] if def.get("armorLine") else null
	var abil: Array = Soldier.abilities_of(so)
	var size := DB.squad_size(so.typeId)
	var missing: int = Game.missing_men(so)
	var rc: int = Game.reinforce_cost(g, so)
	var one: Dictionary = Game.can_reinforce(g, so, 1)
	var all: Dictionary = Game.can_reinforce(g, so, missing)
	var times := func(r: Array) -> String:
		return "%d–%d × %d = %d–%d" % [r[0], r[1], so.men, r[0] * so.men, r[1] * so.men]
	var caster: bool = (def.get("tags", []) as Array).has("caster")
	var crew: bool = def.has("crew")
	var who := "crewmen" if crew else ("mages" if caster else "soldiers")
	var lob: Dictionary = DB.ABILITIES.get(def.primary, {}) if def.get("primary") != null else {}

	var d := Modal.dialog(760)
	var col := UI.vbox(0)
	d.add_child(col)
	# Head: portrait and identity.
	var head := UI.hbox(16)
	col.add_child(head)
	head.add_child(Portrait.make(so.typeId, so.portrait, 128))
	var id_col := UI.vbox(0)
	id_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(id_col)
	name_edit = LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.theme_type_variation = "NameEdit"
	name_edit.text = typed if typed != "" else so.name
	name_edit.tooltip_text = "Rename the squad's sergeant"
	name_edit.max_length = 64
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(func(_t): close())
	id_col.add_child(name_edit)
	id_col.add_child(UI.gap(0, 4))
	var who_row := UI.hbox(6)
	who_row.add_child(Icon.type_icon(so.typeId, 18))
	who_row.add_child(UI.rich("[b]%s[/b] %s [color=#8a7356]· %s[/color]" % [UI.rank_name(so.level), def.plural, def.role], "BodyText"))
	(who_row.get_child(1) as RichTextLabel).autowrap_mode = TextServer.AUTOWRAP_OFF
	(who_row.get_child(1) as RichTextLabel).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	who_row.add_child(MenPips.make(so.men, size))
	if so.get("promoted"):
		who_row.add_child(Tag.make("Promoted", "gold"))
	who_row.add_child(Tag.make("%d CP" % Soldier.command_cost(so), "blue", "cp"))
	id_col.add_child(who_row)
	id_col.add_child(UI.gap(0, 6))
	id_col.add_child(UI.rich(UI.esc(def.blurb), "SmallText"))
	id_col.add_child(UI.gap(0, 8))
	var bars := UI.hbox(10)
	id_col.add_child(bars)
	var xp_col := UI.vbox(0)
	xp_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_col.add_child(UI.label("Experience %s" % ("%d/%d" % [nx.have, nx.need] if nx != null else "(max rank)"), "TinyLabel"))
	var xb := Bar.make(nx.have if nx != null else 1, nx.need if nx != null else 1, "xp")
	xb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_col.add_child(xb)
	bars.add_child(xp_col)
	var hp_col := UI.vbox(0)
	hp_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_col.size_flags_stretch_ratio = 1.3
	hp_col.add_child(UI.rich("Squad HP %d/%d [color=#8a7356]· %d per soldier[/color]" % [so.hp, Soldier.squad_hp_cap(so), st.hp], "TinyText"))
	hp_col.add_child(SquadBar.roster(so))
	bars.add_child(hp_col)
	var mo_col := UI.vbox(0)
	mo_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mo_col.add_child(UI.label("Morale %d/%d" % [so.morale, st.morale], "TinyLabel"))
	var mb := Bar.make(so.morale, st.morale, "morale")
	mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mo_col.add_child(mb)
	bars.add_child(mo_col)

	col.add_child(Flourish.make())
	# Stat grid (4 columns; the damage lines span two).
	var stats := UI.vbox(4)
	col.add_child(stats)
	var ranged: Variant = st.get("ranged", 0)
	# A mangonel's stone in place of a shot; mages loose arcane bolts, a ballista its bolt.
	var missile: Array
	if lob.get("power") != null:
		missile = ["Stone", times.call(lob.power), "%s: %d–%d per crewman at the engine, half to everyone beside the squad struck." % [lob.name, lob.power[0], lob.power[1]]]
	else:
		missile = ["Arcane bolt" if caster else ("Bolt" if crew else "Shot damage"), times.call(dmg.shot) if dmg.get("shot") != null else "–",
			("Each of the %d %s looses for %d–%d before armour." % [so.men, who, dmg.shot[0], dmg.shot[1]]) if dmg.get("shot") != null else "No missile weapon."]
	var cells := [
		[["Melee", str(st.melee)], ["Spell skill" if caster else ("Crew skill" if crew else "Ranged"), str(ranged) if ranged else "–"], ["Defense", str(st.defense)], ["vs. missiles", str(st.rangedDefense)]],
		[["Armour", JS.to_fixed(st.armor * so.armorCondition, 1)], ["Move", str(st.move)], ["Shield", ("+%d" % def.shieldFront) if def.get("shieldFront") else "–"], ["Crew" if crew else ("Mages" if caster else "Soldiers"), "%d/%d" % [so.men, size]]],
		[["Melee damage", times.call(dmg.melee), "Each of the %d %s strikes for %d–%d before armour." % [so.men, who, dmg.melee[0], dmg.melee[1]]], missile],
		[["Fatigue", Soldier.fatigue_label(so.fatigue)], ["Battles", str(so.battles)], ["Squads slain", str(so.kills), "Enemy squads destroyed"], null],
	]
	for row_cells in cells:
		var row := UI.hbox(10)
		for c in row_cells:
			if c == null:
				row.add_child(UI.spacer())
				continue
			row.add_child(_stat(c[0], c[1], c[2] if c.size() > 2 else ""))
		stats.add_child(row)

	# Equipment and abilities.
	col.add_child(UI.gap(0, 10))
	var eq := UI.panel("ParchmentCard")
	var eqc := UI.vbox(0)
	eq.add_child(eqc)
	eqc.add_child(UI.label("Equipment", "H4Label"))
	if weapon != null:
		eqc.add_child(_icon_line("sword", "%s [color=#8a7356](tier %d)[/color]" % [weapon.name, so.weaponTier]))
	else:
		# Squads with no weapon line: the engine and its tackle, staves and spellbooks.
		var gear := "–"
		if crew:
			gear = "The %s and its tackle" % str(def.name).to_lower()
		elif caster:
			gear = "Staves and spellbooks"
		eqc.add_child(_icon_line("engine" if crew else ("staff" if caster else "sword"), "%s [color=#8a7356](not forged at the armoury)[/color]" % gear))
	if armor != null:
		eqc.add_child(_icon_line("shield", "%s [color=#8a7356](tier %d, %d%%)[/color]" % [armor.name, so.armorTier, JS.rnd(so.armorCondition * 100.0)]))
	else:
		eqc.add_child(_icon_line("shield", "Robes, no armour" if caster else "Leather aprons"))
	if def.get("shot") != null and def.shot.get("ammo") != null:
		eqc.add_child(_icon_line("bolts", "%d bolts in the quiver" % so.ammo))
	var ab := UI.panel("ParchmentCard")
	var abc := UI.vbox(0)
	ab.add_child(abc)
	abc.add_child(UI.label("Abilities", "H4Label"))
	for a in abil:
		var A: Dictionary = DB.ABILITIES[a]
		var line := _icon_line(A.icon, "[b]%s[/b]" % A.name)
		line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		Tip.attach(line, UI.esc(A.description), true)
		abc.add_child(line)
	if def.get("promotion") and not so.get("promoted"):
		var promo: Dictionary = DB.ABILITIES[def.promotion]
		var up: Variant = promo.get("upgrades")
		abc.add_child(UI.label(("Promotion: %s becomes %s" % [DB.ABILITIES[up].name, promo.name]) if up else "Promotion unlocks: %s" % promo.name, "SmallMutedLabel"))
	if (def.get("tags", []) as Array).has("firstStrike"):
		abc.add_child(UI.rich("Passive: strikes first at enemies that close in from the front.", "SmallMutedText"))
	if (def.get("tags", []) as Array).has("impale"):
		abc.add_child(UI.rich("Passive: a bolt that strikes home goes on into the next foe behind, at half force.", "SmallMutedText"))
	if crew:
		abc.add_child(UI.rich("A war machine: it cannot loose in a turn it has moved.", "SmallMutedText"))
	col.add_child(UI.equal_grid([eq, ab], 2, 8, 8))

	# Lasting injuries.
	if so.injuries.size() > 0:
		col.add_child(UI.gap(0, 8))
		var inj := UI.panel("ParchmentCard")
		var ic := UI.vbox(0)
		inj.add_child(ic)
		ic.add_child(UI.label("Lasting injuries", "H4Label"))
		for i in so.injuries:
			var I: Dictionary = DB.INJURIES[i]
			var effs: Array = []
			for k in I.effect:
				effs.append("%s %s" % [JS.num_str(I.effect[k]), k])
			ic.add_child(UI.rich("[b]%s[/b]: %s (%s)" % [I.name, UI.esc(I.description), ", ".join(effs)], "SmallText"))
		col.add_child(inj)

	# Wounds carried from the last fight.
	var wound: Variant = Deps.squad().wound_of(so)
	if wound != null:
		col.add_child(UI.gap(0, 8))
		var wc := UI.panel("ParchmentCard")
		wc.name = "Wound"
		var wcol := UI.vbox(0)
		wc.add_child(wcol)
		var injured: bool = wound.kind == "injured"
		wcol.add_child(UI.label("Injured" if injured else "Wounded", "H4Label"))
		var why := "Cut down to the last in its last fight." if injured else ("%s still hurt from its last fight." % ("One soldier is" if wound.hurt == 1 else "%d soldiers are" % wound.hurt))
		var wr := UI.hbox(8)
		wcol.add_child(wr)
		var wt := UI.rich("%s In its next fight: %s. %s." % [why, Deps.squad().wound_text(wound), Deps.squad().hurt_text(wound)], "SmallText")
		wt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		wr.add_child(wt)
		if g.get("expedition") == null:
			var dc: int = Game.dress_cost(g, so)
			var db := RichButton.make(["Dress wounds", {"icon": "silver", "size": 13}, str(dc)], "GoldSmallButton", _dress_wounds)
			db.name = "DressWounds"
			db.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			db.disabled = g.resources.silver < dc
			Tip.attach(db, "The Infirmary dresses the wounds: the squad marches with the next expedition at full strength, and its soldiers who go down rise again (%d silver; new soldiers for the hurt would cost %d)." % [dc, Game.reinforce_cost(g, so) * wound.hurt])
			wr.add_child(db)
		col.add_child(wc)

	# Empty places in the ranks.
	if missing > 0:
		col.add_child(UI.gap(0, 8))
		var mc := UI.panel("ParchmentCard")
		var mr := UI.hbox(8)
		mc.add_child(mr)
		var txt := "[b]%d %s empty in the ranks.[/b] %s" % [missing, "place" if missing == 1 else "places",
			"The Barracks can send replacements once the company is home." if g.get("expedition") != null else "The Barracks can fill them for %d silver per soldier." % rc]
		var mt := UI.rich(txt, "SmallText")
		mt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mr.add_child(mt)
		if g.get("expedition") == null:
			var btns := UI.hbox(6)
			btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var b1 := RichButton.make(["+1", {"icon": "silver", "size": 13}, str(rc)], "GoldSmallButton", _reinforce.bind(1))
			b1.name = "ReinforceOne"
			b1.disabled = not one.ok
			Tip.attach(b1, ("One new %s joins, fit and ready (%d silver)." % [def.name.to_lower(), rc]) if one.ok else str(one.get("reason", "")))
			btns.add_child(b1)
			if missing > 1:
				var b2 := RichButton.make(["Refill %d" % missing, {"icon": "silver", "size": 13}, str(rc * missing)], "GoldSmallButton", _reinforce.bind(missing))
				b2.name = "ReinforceAll"
				b2.disabled = not all.ok
				Tip.attach(b2, ("Bring the squad to full strength: %d soldiers for %d silver." % [missing, rc * missing]) if all.ok else str(all.get("reason", "")))
				btns.add_child(b2)
			mr.add_child(btns)
		col.add_child(mc)

	# Footer.
	col.add_child(UI.gap(0, 12))
	var foot := UI.hbox(8)
	var served := UI.label("Served on %d expedition%s." % [so.expeditions, "" if so.expeditions == 1 else "s"], "SmallMutedLabel")
	served.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	served.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(served)
	if g.get("expedition") == null:
		var dis := UI.button("Discharge", "GhostSmallButton", _discharge)
		dis.name = "Discharge"
		dis.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		foot.add_child(dis)
	var close_b := UI.button("Close", "Button", close)
	close_b.name = "Close"
	foot.add_child(close_b)
	col.add_child(foot)

	_modal = Modal.make(d, close, false)
	add_child(_modal)


func _stat(label: String, value: String, title := "") -> Control:
	var cell := PanelContainer.new()
	var st := PaperStyle.new()
	st.dash_bottom = UI.C("#5b4630", 0.3)
	st.dash_len = 1.0
	st.dash_gap = 1.0
	st.content_margin_bottom = 1
	cell.add_theme_stylebox_override("panel", st)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.mouse_filter = Control.MOUSE_FILTER_PASS if title != "" else Control.MOUSE_FILTER_IGNORE
	cell.tooltip_text = title
	var r := UI.hbox(4)
	var l := UI.label(label, "SmallLabel")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(l)
	var v := UI.label(value, "SmallLabel")
	v.add_theme_font_override("font", UI.font("cinzel", 700))
	r.add_child(v)
	cell.add_child(r)
	return cell


func _icon_line(icon: String, bbcode: String) -> HBoxContainer:
	var r := UI.hbox(6)
	r.add_child(Icon.make(icon, 15))
	var t := UI.rich(bbcode, "SmallText")
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	t.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	r.add_child(t)
	return r


func _reinforce(count: int) -> void:
	var Game = Deps.game()
	if Game.reinforce(App.game, soldier_id, count):
		App.sfx("coin")
		App.commit()
	else:
		App.sfx("deny")


func _dress_wounds() -> void:
	var Game = Deps.game()
	if Game.dress_wounds(App.game, soldier_id):
		App.sfx("coin")
		App.commit()
	else:
		App.sfx("deny")


func _discharge() -> void:
	var so: Variant = _find()
	if so == null:
		return
	Confirm.ask(self, "Discharge %s and the squad from the company?" % so.name, func():
		Deps.game().dismiss(App.game, soldier_id)
		App.open_soldier(null)
		App.commit())


## Saves a changed name (trimmed, at most 32 characters), then closes.
func close() -> void:
	var so: Variant = _find()
	if so != null and name_edit != null:
		var n := name_edit.text.strip_edges()
		if n != "" and name_edit.text != so.name:
			so.name = n.substr(0, 32)
			App.commit()
	App.open_soldier(null)
