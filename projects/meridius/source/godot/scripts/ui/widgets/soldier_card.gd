## Port of Roster.tsx `SoldierCard`, `SQUAD_ORDER` / `squadOrder`, and Base.tsx
## `SoldierRow` (the wide card row of the building panels).
##
##   const SoldierCard = preload("res://scripts/ui/widgets/soldier_card.gd")
##   SoldierCard.make(so: Dictionary, on_click := Callable(), selected := false, disabled := false, extra: Array = []) -> PanelContainer
##       Portrait 52, name + command-point tag, type line (+ ★ when promoted),
##       segmented squad HP bar with pips, morale bar, status tags (injuries,
##       Recovering, Worn armour, "N short") and `extra` tag Controls.
##   SoldierCard.row(so: Dictionary, trailing: Array = [], on_click := Callable(), name_w := 190, bars_w := 104) -> PanelContainer
##       SoldierRow: Portrait 42 | name / type (name_w px) | pips, HP, morale (bars_w px) | tags | trailing controls.
##       (CSS lets the 190/104 columns shrink when the trailing buttons are wide; pass smaller widths there.)
##   SoldierCard.squad_order(type_id) -> int      line first, then spears, missiles, mages and war machines
##   SoldierCard.sort_roster(list) -> Array       by squad_order, then level (high first); a sorted copy
extends RefCounted

const UI = preload("res://scripts/ui/ui.gd")
const DB = preload("res://scripts/data/db.gd")
const Deps = preload("res://scripts/ui/deps.gd")
const JS = preload("res://scripts/core/js.gd")
const Card = preload("res://scripts/ui/widgets/card.gd")
const Portrait = preload("res://scripts/ui/widgets/portrait.gd")
const Icon = preload("res://scripts/ui/widgets/icon.gd")
const Tag = preload("res://scripts/ui/widgets/tag.gd")
const Bar = preload("res://scripts/ui/widgets/bar.gd")
const SquadBar = preload("res://scripts/ui/widgets/squad_bar.gd")
const MenPips = preload("res://scripts/ui/widgets/men_pips.gd")

## Order squads are listed in: the line first, then spears, then missiles.
const SQUAD_ORDER := ["collie_guard", "footman", "spearman", "crossbowman", "battle_mage", "ballista", "mangonel"]


static func squad_order(type_id: String) -> int:
	var i := SQUAD_ORDER.find(type_id)
	return SQUAD_ORDER.size() if i < 0 else i


static func sort_roster(list: Array) -> Array:
	var out := list.duplicate()
	return JS.sort(out, func(a, b): return (squad_order(a.typeId) - squad_order(b.typeId)) if squad_order(a.typeId) != squad_order(b.typeId) else (b.level - a.level))


static func make(so: Dictionary, on_click := Callable(), selected := false, disabled := false, extra: Array = []) -> PanelContainer:
	var Soldier = Deps.soldier()
	var Game = Deps.game()
	var st: Dictionary = Soldier.soldier_stats(so)
	var card := Card.make(on_click, selected, disabled)
	card.name = "Card_" + str(so.id)
	var row := UI.hbox(8)
	card.add_child(row)
	var portrait := Portrait.make(so.typeId, so.portrait, 52)
	row.add_child(portrait)
	var col := UI.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	# Name and command points.
	var head := UI.hbox(8)
	var nm := UI.ellipsize(UI.cinzel(so.name, 14))
	head.add_child(nm)
	var cp := Tag.make(str(Soldier.command_cost(so)), "", "cp", 0, "Command points")
	head.add_child(cp)
	col.add_child(head)
	# Type line.
	var tl := UI.hbox(4)
	tl.add_child(Icon.type_icon(so.typeId, 13))
	var type_label := UI.label(UI.squad_type_label(so.typeId, so.level, true), "TinyLabel")
	type_label.tooltip_text = UI.squad_type_label(so.typeId, so.level)
	type_label.mouse_filter = Control.MOUSE_FILTER_PASS
	tl.add_child(type_label)
	if so.get("promoted"):
		tl.add_child(Tag.make("★", "gold", "", 0, "", 3))
	tl.add_child(UI.spacer())
	col.add_child(tl)
	# Bars.
	var bars := UI.vbox(3)
	col.add_child(UI.gap(0, 3))
	col.add_child(bars)
	var hp_row := UI.hbox(6)
	var hp_bar := SquadBar.roster(so, 7)
	hp_row.add_child(hp_bar)
	hp_row.add_child(MenPips.make(so.men, DB.squad_size(so.typeId)))
	bars.add_child(hp_row)
	var mb := Bar.make(so.morale, st.morale, "morale", 6, "Morale %d/%d" % [so.morale, st.morale])
	mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bars.add_child(mb)
	# Tags.
	var tags := HFlowContainer.new()
	tags.add_theme_constant_override("h_separation", 3)
	tags.add_theme_constant_override("v_separation", 3)
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in so.injuries:
		tags.add_child(Tag.make(DB.INJURIES[i].name, "red", "", 10))
	if so.get("recovering"):
		tags.add_child(Tag.make("Recovering", "blue", "", 10))
	if so.armorCondition < 0.7:
		tags.add_child(Tag.make("Worn armour", "", "", 10))
	var miss: int = Game.missing_men(so)
	if miss > 0:
		tags.add_child(Tag.make("%d short" % miss, "", "", 10))
	for e in extra:
		if e != null:
			tags.add_child(e)
	if tags.get_child_count() > 0:
		col.add_child(UI.gap(0, 4))
		col.add_child(tags)
	else:
		# Not shown: free it (an unparented node is never freed with the card).
		tags.free()
	return card


## Base.tsx SoldierRow.
static func row(so: Dictionary, trailing: Array = [], on_click := Callable(), name_w := 190, bars_w := 104) -> PanelContainer:
	var Soldier = Deps.soldier()
	var st: Dictionary = Soldier.soldier_stats(so)
	var card := Card.make(on_click)
	card.name = "Row_" + str(so.id)
	var r := UI.hbox(8)
	card.add_child(r)
	var p := Portrait.make(so.typeId, so.portrait, 42)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(p)
	var who := UI.vbox(0)
	who.custom_minimum_size.x = name_w
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_child(UI.ellipsize(UI.cinzel(so.name, 14)))
	var tl := UI.hbox(4)
	tl.add_child(Icon.type_icon(so.typeId, 14))
	tl.add_child(UI.label(UI.squad_type_label(so.typeId, so.level, true), "SmallMutedLabel"))
	who.add_child(tl)
	r.add_child(who)
	var bars := UI.vbox(4)
	bars.custom_minimum_size.x = bars_w
	bars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bars.add_child(MenPips.make(so.men, DB.squad_size(so.typeId)))
	bars.add_child(SquadBar.roster(so, 7))
	var mb := Bar.make(so.morale, st.morale, "morale", 6, "Morale %d/%d" % [so.morale, st.morale])
	mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bars.add_child(mb)
	r.add_child(bars)
	var tags := HFlowContainer.new()
	tags.add_theme_constant_override("h_separation", 4)
	tags.add_theme_constant_override("v_separation", 4)
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tags.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tags.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if so.get("recovering"):
		tags.add_child(Tag.make("Recovering", "blue"))
	for i in so.injuries:
		tags.add_child(Tag.make(DB.INJURIES[i].name, "red"))
	r.add_child(tags)
	for t in trailing:
		if t != null:
			if t is Control:
				(t as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
			r.add_child(t)
	return card
