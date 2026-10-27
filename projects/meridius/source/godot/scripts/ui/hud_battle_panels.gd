## The squad and hover panels of the battle HUD: port of `UnitPanel`,
## `RedoButton`, `FacingRose`, `Forecast`, `SpellForecast`, `ArrivalNote`,
## `UnitInfo`, `TileInfo`, `StatusChips`, `shotName`, `STATUS_INFO` and
## `squadTitle` of src/ui/screens/Battle.tsx. Builders return Controls; the
## battle HUD (battle_hud.gd) places them and rebuilds them when what they show
## changes. Buttons call the battle view (scripts/render/battle_view.gd).
##
##   const Panels = preload("res://scripts/ui/hud_battle_panels.gd")
##   Panels.unit_panel(view, u) -> Control        the selected squad's card
##   Panels.forecast(view) -> Control             attack preview (ui.hover.preview)
##   Panels.spell_forecast(view) -> Control       what a spell or a machine's stone would do (ui.hover.spell)
##   Panels.unit_info(view, u) -> Control         a hovered squad
##   Panels.tile_info(view) -> Control            a hovered tile
##   Panels.status_chips(u) -> Control            chips for a squad's conditions (null when none)
##   Panels.status_ids(list) -> Array             condition ids of a unit's or a view's `statuses`
##   Panels.shot_name(u) -> String                "Arcane bolt", "Hex bolt", "Bolt" or "Shot"
##   Panels.abilities(u) -> Array                 the squad's ability buttons' ids (keys 1–4)
extends RefCounted

const UI = preload("res://scripts/ui/ui.gd")
const H = preload("res://scripts/ui/hud_common.gd")
const JS = preload("res://scripts/core/js.gd")
const DB = preload("res://scripts/data/db.gd")
const Squad = preload("res://scripts/rules/squad.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const Icon = preload("res://scripts/ui/widgets/icon.gd")
const Bar = preload("res://scripts/ui/widgets/bar.gd")
const SquadBar = preload("res://scripts/ui/widgets/squad_bar.gd")
const MenPips = preload("res://scripts/ui/widgets/men_pips.gd")
const Portrait = preload("res://scripts/ui/widgets/portrait.gd")
const Tip = preload("res://scripts/ui/widgets/tip.gd")
const Tag = preload("res://scripts/ui/widgets/tag.gd")
const RichButton = preload("res://scripts/ui/widgets/rich_button.gd")

const MORALE_LABEL := {"confident": "Confident", "steady": "Steady", "shaken": "Shaken", "wavering": "Wavering", "broken": "Broken"}
## Screen arrows for the four grid facings: +x down-right, +y down-left, -x up-left, -y up-right.
const FACING_ARROW := {0: "↘", 1: "↙", 2: "↖", 3: "↗"}
const NEG := Color("#a3261c")
const POS := Color("#2d6a1a")

## Lasting conditions: name, chip colour and what it does.
const STATUS_INFO := {
	"chilled": {"name": "Chilled", "color": "#bfe6ff", "text": "Half movement, −10 to hit and −10 defense until the end of its turn."},
	"bloodlust": {"name": "Bloodlust", "color": "#ff8a6a", "text": "+10 to hit and +3 damage per soldier in melee, morale losses halved, −8 defense."},
	"bleeding": {"name": "Bleeding", "color": "#ff9a8a", "text": "Loses HP (and soldiers) at the start of each of its turns."},
	"cowed": {"name": "Cowed", "color": "#d9b8ff", "text": "−10 to hit until the end of its turn."},
}
## How the spell forecast names a squad's part in it ("arc: Skab's goblin rabble").
const ROLE_NAME := {"main": "", "splash": "beside", "chain": "arc", "aura": ""}
## Friendly squads caught in a blast.
const OWN_HIT := Color("#b4520e")

const FACING_TIP := "A squad faces the way it last stepped. Choose the side it arrives from: point at an edge of the destination tile, or press [b]Q[/b] / [b]E[/b]. To turn on the spot, point at an edge of its own tile (it steps out and back)."


static func _view_of(view: Object, uid: Variant) -> Variant:
	var vs: Variant = view.get("views")
	if vs is Dictionary:
		return vs.get(uid)
	return null


static func _num(x: Variant) -> String:
	return JS.num_str(x)


## The squad's abilities with buttons: stances, shouts, spells, and attack
## abilities only when they deal damage (DB.is_active_ability).
static func abilities(u: Dictionary) -> Array:
	var out: Array = []
	for a in u.get("abilities", []):
		if DB.is_active_ability(a):
			out.append(a)
	return out


## What the squad's missile weapon is called: crossbow bolts, arcane bolts, hexes, a ballista's bolt.
static func shot_name(u: Dictionary) -> String:
	match str(u.get("typeId", "")):
		"battle_mage":
			return "Arcane bolt"
		"goblin_shaman":
			return "Hex bolt"
		"ballista":
			return "Bolt"
	return "Shot"


## Condition ids of a rules unit's `statuses` ([{id, turns, …}]) or a view's (ids).
static func status_ids(list: Variant) -> Array:
	var out: Array = []
	if list is Array:
		for s in list:
			out.append(str(s.get("id")) if s is Dictionary else str(s))
	return out


static func status_name(id: String) -> String:
	return str(STATUS_INFO.get(id, {}).get("name", id.capitalize()))


## Chips for a squad's lasting conditions (chilled, frenzied, bleeding), with what each does.
static func status_chips(u: Dictionary) -> Control:
	var list: Array = u.get("statuses") if u.get("statuses") is Array else []
	if list.is_empty():
		return null
	var row := H.flow(4)
	row.name = "Statuses"
	for s in list:
		var id: String = str(s.get("id")) if s is Dictionary else str(s)
		var info: Dictionary = STATUS_INFO.get(id, {"name": status_name(id), "color": "#f0e2c0", "text": ""})
		var tip := "[b]%s[/b]" % info.name
		if id == "bleeding" and s is Dictionary and s.get("power"):
			tip += " (−%s a turn, %s more)" % [_num(s.power), _num(s.get("turns", 0))]
		tip += "\n" + str(info.text)
		var chip := Tag.make(str(info.name), "", "", 10)
		chip.name = "Status_" + id
		var sb: StyleBoxFlat = load("res://scripts/ui/theme_builder.gd").tag_style("")
		sb.bg_color = Color(15 / 255.0, 10 / 255.0, 6 / 255.0, 0.75)
		chip.add_theme_stylebox_override("panel", sb)
		for l in chip.find_children("*", "Label", true, false):
			(l as Label).add_theme_color_override("font_color", Color(str(info.color)))
		Tip.attach(chip, tip)
		row.add_child(chip)
	return row


## "Grukk's Goblin Spearmen", "Aldric Holm's Footmen", or a leader's own name.
static func squad_title(u: Dictionary) -> String:
	var name := str(u.name)
	if u.get("leader"):
		return name.split(",")[0]
	var who := name
	if u.faction != "player":
		who = _first_word(name)
	return "%s's %s" % [who, DB.UNIT_TYPES.get(u.typeId, {}).get("plural", u.typeId)]


## JS name.split(/[ ,]/)[0]
static func _first_word(name: String) -> String:
	var cut := name.length()
	for ch in [" ", ","]:
		var i := name.find(ch)
		if i >= 0:
			cut = mini(cut, i)
	return name.substr(0, cut)


static func _row_between(a: Control, b: Control, sep := 8) -> HBoxContainer:
	var r := UI.hbox(sep)
	r.add_child(a)
	r.add_child(UI.spacer())
	r.add_child(b)
	return r


## A `.tiny` line (11.5 px; Godot's 12 px line box trimmed to the browser's).
static func _tiny(t: String, color := H.NONE, bb := false) -> Control:
	if bb:
		return H.trim(H.rich(t, 12, color), -1, -1)
	var l := UI.label(t, "TinyLabel", 0, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_constant_override("line_spacing", H.line_gap(12))
	return H.trim(l, -1, -1)


## A `.small` line (13 px).
static func _small(t: String, color := H.NONE, bb := false) -> Control:
	if bb:
		return H.trim(H.rich(t, 13, color), 0, -1)
	var l := UI.label(t, "SmallLabel", 0, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_constant_override("line_spacing", H.line_gap(13))
	return H.trim(l, 0, -1)


# ---------------------------------------------------------------- selected squad

static func unit_panel(view: Object, u: Dictionary) -> Control:
	var b = view.b
	var v = _view_of(view, u.uid)
	var ms: String = b.morale_state(u)
	var my_turn: bool = b.phase == "player" and not view.ui.busy
	var n: int = maxi(0, int(v.alive if v != null else u.alive))
	var hp: float = float(v.hp if v != null else u.hp)
	var morale: float = float(v.morale if v != null else u.morale)
	var facing: int = int(v.facing if v != null else u.facing)

	var def: Dictionary = DB.UNIT_TYPES.get(u.typeId, {})
	var caster: bool = (u.get("tags", []) as Array).has("caster")
	var primary: Dictionary = DB.ABILITIES.get(def.primary, {}) if def.get("primary") != null else {}

	var p := UI.panel("DarkPanel", [17, 22])
	p.name = "UnitPanel"
	p.custom_minimum_size.x = 660
	var row := UI.hbox(14)
	p.add_child(row)

	var por := Portrait.make(u.typeId, int(u.get("variant", 0)), 92)
	row.add_child(por)

	# Name, type, soldiers, bars, damage and stats.
	var mid := UI.vbox(0)
	mid.custom_minimum_size.x = 252
	mid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var name := UI.ellipsize(UI.cinzel(str(u.name), 16, 700))
	name.custom_minimum_size.x = 252
	mid.add_child(name)
	var type_row := UI.hbox(4)
	type_row.add_child(Icon.type_icon(u.typeId, 14))
	type_row.add_child(UI.label(UI.squad_type_label(u.typeId, int(u.get("level", 0)), true), "SmallLabel"))
	var mor_row := UI.hbox(3)
	mor_row.add_child(Icon.make("morale", 14))
	mor_row.add_child(UI.label(MORALE_LABEL.get(ms, ms), "SmallLabel"))
	mid.add_child(H.trim(_row_between(type_row, mor_row, 4), 0, -1))
	var sol_row := UI.hbox(5)
	sol_row.add_child(UI.label("Crew" if def.has("crew") else ("Casters" if caster else "Soldiers"), "SmallLabel"))
	sol_row.add_child(MenPips.make(n, int(u.size)))
	var hp_row := UI.hbox(3)
	hp_row.add_child(Icon.make("hp", 14))
	hp_row.add_child(UI.label("%d/%s" % [maxi(0, JS.rnd(hp)), _num(u.maxHp)], "SmallLabel"))
	hp_row.tooltip_text = "%s HP per soldier" % _num(u.hpPer)
	hp_row.mouse_filter = Control.MOUSE_FILTER_PASS
	mid.add_child(H.margin(_row_between(sol_row, hp_row), 3, 0, -1, 0))
	mid.add_child(SquadBar.make(hp, float(u.hpPer), int(u.size), n))
	mid.add_child(UI.gap(0, 3))
	var mb := Bar.make(morale, float(u.maxMorale), "morale", 6)
	mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(mb)
	var dmg := func(r: Array) -> String:
		return "%s–%s × %d = [b]%s–%s[/b]" % [_num(r[0]), _num(r[1]), n, _num(r[0] * n), _num(r[1] * n)]
	var dmg_box := UI.vbox(0)
	dmg_box.tooltip_text = "Per soldier × soldiers standing = squad damage, before armour"
	dmg_box.mouse_filter = Control.MOUSE_FILTER_PASS
	var shot: Variant = u.get("shot")
	if shot != null:
		var s: String = shot_name(u) + " " + dmg.call(shot.damage)
		if int(u.get("ammo", -1)) >= 0:
			s += " · Bolts %d" % int(u.ammo)
		dmg_box.add_child(_tiny(s, H.NONE, true))
	if primary.get("power") != null:
		dmg_box.add_child(_tiny("%s %s" % [UI.esc(str(primary.name)), dmg.call(primary.power)], H.NONE, true))
	dmg_box.add_child(_tiny(("Melee " if shot != null or not primary.is_empty() else "Damage ") + dmg.call(u.melee), H.NONE, true))
	mid.add_child(H.margin(dmg_box, 5, 0, 0, 0))
	var st: Dictionary = u.stats
	var stats := "Melee %s" % _num(st.melee)
	if shot != null or not primary.is_empty():
		stats += " · %s %s" % ["Spell" if caster else ("Crew" if def.has("crew") else "Ranged"), _num(st.ranged)]
	stats += " · Def %s" % _num(st.defense)
	if u.get("shieldFront"):
		stats += " (+%s shield)" % _num(u.shieldFront)
	stats += " · Armour %s · Move %s" % [JS.to_fixed(float(st.armor), 1), _num(st.move)]
	mid.add_child(_tiny(stats))
	var chips := status_chips(u)
	if chips != null:
		mid.add_child(H.margin(chips, 2, 0, 0, 0))
	var wound: Variant = u.get("wound")
	if wound != null:
		var wt := _tiny("%s: %s" % ["Injured" if wound.kind == "injured" else "Wounded", Squad.wound_text(wound)], Color("#8a1f15"))
		wt.name = "Wound"
		mid.add_child(H.margin(wt, 2, 0, 0, 0))
	row.add_child(mid)

	# Status tags, Redo, abilities.
	var acts := UI.vbox(6)
	acts.alignment = BoxContainer.ALIGNMENT_CENTER
	acts.custom_minimum_size.x = 0
	var tags := H.flow(6)
	tags.add_child(Tag.make("Moved" if u.hasMoved else "Can move", "" if u.hasMoved else "blue"))
	tags.add_child(Tag.make("Acted" if u.hasActed else "Can act", "" if u.hasActed else "red"))
	if u.hasMoved and b.phase == "player":
		tags.add_child(_redo_button(view, u))
	acts.add_child(tags)
	var ab_row := UI.hbox(6)
	var list := abilities(u)
	for i in list.size():
		ab_row.add_child(_ability_button(view, u, list[i], i, ms, my_turn))
	acts.add_child(ab_row)
	acts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(acts)

	# Facing and Done.
	var right := UI.vbox(6)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	var rose_box := UI.vbox(2)
	rose_box.mouse_filter = Control.MOUSE_FILTER_PASS
	var fl := UI.label("Facing", "TinyMutedLabel")
	fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rose_box.add_child(fl)
	var rose := facing_rose(facing)
	rose.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rose_box.add_child(rose)
	rose_box.name = "Facing"
	Tip.attach(rose_box, FACING_TIP, true)
	right.add_child(rose_box)
	var done := RichButton.make(["Done", H.kbd("Space")], "SmallButton", func(): view.end_unit())
	done.name = "Done"
	done.set_meta("label", "Done Space")
	done.disabled = not my_turn
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	right.add_child(done)
	row.add_child(right)
	return p


static func _redo_button(view: Object, u: Dictionary) -> Control:
	var can: Dictionary = view.b.can_redo(u.uid)
	var ok: bool = can.get("ok", false) and not view.ui.busy
	var uid: String = u.uid
	var btn := UI.button("↶ Redo move", "GoldSmallButton", func(): view.redo(uid))
	btn.name = "Redo"
	btn.disabled = not ok
	Tip.attach(btn, "Walk this squad back to where it started the turn and move again. Only before attacking. (Backspace)" if can.get("ok", false) else UI.esc(str(can.get("reason", ""))), true)
	return btn


static func _ability_button(view: Object, u: Dictionary, a: String, i: int, ms: String, my_turn: bool) -> Control:
	var ab: Dictionary = DB.ABILITIES.get(a, {})
	var cd := int(u.get("cooldowns", {}).get(a, 0))
	var ammo := int(u.get("ammo", -1))
	var spell: bool = ab.get("kind") == "spell"
	var cast: Dictionary = view.b.can_cast(u, a) if spell else {}
	# Lick Wounds needs no enemy beside the squad; an aimed shot, a squad that has not moved.
	var shout_ok: Dictionary = view.b.can_shout(u, a) if ab.get("kind") == "shout" else {"ok": true}
	var still_ok: bool = not ab.get("still", false) or not u.hasMoved
	var disabled: bool = not my_turn or u.hasActed or cd > 0 or (not cast.get("ok", false) if spell else ms == "wavering") \
		or (ab.get("ammoCost") != null and ammo >= 0 and ammo < int(ab.ammoCost)) \
		or (a == "overwatch" and ammo == 0) or not shout_ok.get("ok", false) or not still_ok
	# Why it cannot be used now (a cooldown shows on the button itself).
	var why := ""
	if spell and not cast.get("ok", false) and my_turn and not u.hasActed and cd == 0:
		why = str(cast.get("reason", ""))
	elif ms == "wavering" and not spell:
		why = "Too shaken to use abilities."
	elif my_turn and not u.hasActed and cd == 0 and not shout_ok.get("ok", false):
		why = str(shout_ok.get("reason", "")) + "."
	elif my_turn and not u.hasActed and not still_ok:
		why = "Only in a turn the squad has not moved."
	var active: bool = view.ui.ability == a
	var btn := Button.new()
	btn.name = "Ability_" + a
	btn.set_meta("label", "%d %s" % [i + 1, ab.get("name", a)])
	btn.theme_type_variation = "AbilityButtonActive" if active else "AbilityButton"
	btn.custom_minimum_size = Vector2(62, 62)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.disabled = disabled
	var aid := a
	btn.pressed.connect(func(): view.set_ability(aid))
	var content := UI.vbox(2)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ic := Icon.make(str(ab.get("icon", "sword")), 26)
	content.add_child(ic)
	# The button's word: `short` where two names would begin alike (Shield Wall, Shield Bash).
	var nm := UI.label(str(ab.get("short", str(ab.get("name", a)).split(" ")[0])), "", 10, UI.LIGHT_TITLE)
	nm.add_theme_font_override("font", UI.font("cinzel", 700))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(nm)
	btn.add_child(content)
	var key := UI.label(str(i + 1), "", 9, Color(UI.LIGHT_TITLE, 0.7))
	key.add_theme_font_override("font", UI.font("cinzel", 700))
	key.position = Vector2(4, 1)
	btn.add_child(key)
	if cd > 0:
		var ov := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.55)
		sb.set_corner_radius_all(1)
		ov.add_theme_stylebox_override("panel", sb)
		ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var cl := UI.label(str(cd), "", 22, UI.LIGHT_TITLE)
		cl.add_theme_font_override("font", UI.font("cinzel", 700))
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ov.add_child(cl)
		btn.add_child(ov)
	# `.ability:disabled` greys and darkens the whole button; hover brightens it.
	var dim := Color(0.55, 0.53, 0.5) if disabled else Color.WHITE
	content.modulate = dim
	key.modulate = dim
	btn.mouse_entered.connect(func():
		if not btn.disabled:
			content.modulate = Color(1.2, 1.2, 1.2))
	btn.mouse_exited.connect(func(): content.modulate = dim)
	var muted := H.hex(UI.DARK_MUTED)
	var tip := "[b]%s[/b] [color=%s][%d][/color]" % [UI.esc(str(ab.get("name", a))), muted, i + 1]
	var every := int(ab.get("cooldown", 0))
	if every > 1:
		tip += "[color=%s] · every %s[/color]" % [muted, "other turn" if every == 2 else "%d turns" % every]
	tip += "\n" + UI.esc(str(ab.get("description", "")))
	if why != "":
		tip += "\n[color=#ffb0a0]%s[/color]" % UI.esc(why)
	if spell and ab.get("target") != "self":
		var what := "an enemy squad"
		if ab.get("target") == "ally":
			what = "a friendly squad"
		elif ab.get("target") == "tile":
			what = "a squad or a tile"
		tip += "\n[color=%s]Choose it, then click %s.[/color]" % [muted, what]
	Tip.attach(btn, tip, true)
	return btn


## Read-only compass: the squad's facing, set only by its last step.
static func facing_rose(facing: int) -> Control:
	var g := UI.grid(2, 2, 2)
	g.name = "FacingRose"
	for d in [2, 3, 1, 0]:
		var cell := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(1)
		sb.bg_color = Color("#cfb878") if d == facing else Color(0, 0, 0, 0.18)
		sb.set_border_width_all(1)
		sb.border_color = Color("#f0d797") if d == facing else Color("#4c5351")
		sb.anti_aliasing = true
		cell.add_theme_stylebox_override("panel", sb)
		cell.custom_minimum_size = Vector2(22, 20)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := UI.label(FACING_ARROW[d], "", 15, Color("#2a1a08") if d == facing else Color(240 / 255.0, 226 / 255.0, 192 / 255.0, 0.28))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.add_child(l)
		cell.name = "Dir%d" % d
		g.add_child(cell)
	return g


# ---------------------------------------------------------------- attack preview

static func _header(title: String, sub: Control, u: Dictionary) -> Control:
	var row := UI.hbox(8)
	var left := UI.vbox(0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := UI.cinzel(title, 16, 700)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(t)
	left.add_child(sub)
	row.add_child(left)
	var por := Portrait.make(u.typeId, int(u.get("variant", 0)), 44)
	por.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(por)
	return row


static func forecast(view: Object) -> Control:
	var b = view.b
	var pv: Dictionary = view.ui.hover.preview
	# A squad standing guard (Defend) takes the blow: the forecast is about it.
	var ward: Variant = b.unit(pv.target) if pv.get("guard") != null else null
	var target: Dictionary = b.unit(pv.guard) if ward != null else b.unit(pv.target)
	var attacker: Variant = b.unit(view.ui.selected) if view.ui.selected != null else null
	var tv = _view_of(view, target.uid)
	var thp := maxi(0, JS.rnd(float(tv.hp if tv != null else target.hp)))
	var talive := int(tv.alive if tv != null else target.alive)
	var arc := "Frontal" if pv.get("arc") == "front" else ("Flank" if pv.get("arc") == "flank" else "Rear")

	var p := UI.panel("ParchmentPanel", [16, 16])
	p.name = "Forecast"
	p.custom_minimum_size.x = 300
	var col := UI.vbox(0)
	var sub := UI.hbox(6)
	# `.tiny.muted` row: the pips take its colour.
	sub.add_child(MenPips.make(talive, int(target.size), true, "", UI.INK_FAINT))
	sub.add_child(UI.label("· %d/%s HP · %s" % [thp, _num(target.maxHp), MORALE_LABEL.get(b.morale_state(target), "")], "TinyMutedLabel"))
	col.add_child(_header(squad_title(target), sub, target))
	col.add_child(UI.gap(0, 8))
	col.add_child(H.flourish())
	col.add_child(UI.gap(0, 8))
	if not pv.get("legal", false):
		var l := UI.label(str(pv.get("reason", "")), "BadLabel")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(l)
		p.add_child(col)
		return p
	var chance := int(pv.chance)
	var top := UI.hbox(8)
	var lcol := UI.vbox(0)
	var what := "Attack"
	if pv.get("ability") != null:
		what = str(DB.ABILITIES.get(pv.ability, {}).get("name", pv.ability))
	elif pv.get("moveFirst"):
		what = "Move & attack"
	lcol.add_child(UI.label("%s · %s" % [what, arc], "TinyMutedLabel"))
	var big := UI.label("%d%%" % chance, "", 40, Color("#2d5a1a") if chance >= 70 else (Color("#6b4a10") if chance >= 45 else Color("#8a1f15")))
	big.add_theme_font_override("font", UI.font("cinzel", 900))
	# `.forecast .big`: line-height 1 (Godot's box for Cinzel 40 is 55 px).
	lcol.add_child(H.trim(big, -6, -9))
	lcol.size_flags_vertical = Control.SIZE_SHRINK_END
	top.add_child(lcol)
	top.add_child(UI.spacer())
	var rcol := UI.vbox(0)
	rcol.size_flags_vertical = Control.SIZE_SHRINK_END
	var sd := UI.label("Squad damage", "TinyMutedLabel")
	sd.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rcol.add_child(sd)
	var dm := UI.label("%s–%s" % [_num(pv.min), _num(pv.max)], "", 26)
	dm.add_theme_font_override("font", UI.font("cinzel", 900))
	dm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rcol.add_child(dm)
	top.add_child(rcol)
	col.add_child(top)

	var strikers := int(pv.get("strikers", 0))
	var strikes := "%d strike" % strikers
	if attacker != null:
		strikes = "%d %s %s" % [strikers, Squad.member_noun(attacker.typeId, strikers), "strikes" if strikers == 1 else "strike"]
	var s0 := int(pv.soldiers[0])
	var s1 := int(pv.soldiers[1])
	var slays := "Slays none" if s1 <= 0 else "Slays %s %s" % [str(s1) if s0 == s1 else "%d–%d" % [s0, s1], Squad.member_noun(target.typeId, s1)]
	var sl := UI.label(slays, "SmallGoodLabel" if s1 > 0 else "SmallMutedLabel")
	col.add_child(H.margin(_row_between(UI.label(strikes, "SmallLabel"), sl), 4, 0, 0, 0))
	var destroy := H.rich("Destroy squad: [b]%d%%[/b]" % JS.rnd(float(pv.kill) * 100.0), 13)
	destroy.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	destroy.autowrap_mode = TextServer.AUTOWRAP_OFF
	destroy.tooltip_text = "Chance this attack destroys the whole squad"
	destroy.mouse_filter = Control.MOUSE_FILTER_PASS
	var shock := H.rich("Morale shock: [b]−%s[/b]" % _num(pv.moraleHit), 13)
	shock.size_flags_horizontal = Control.SIZE_SHRINK_END
	shock.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(H.margin(_row_between(destroy, shock), 2, 0, 0, 0))
	col.add_child(H.margin(_mods(pv.get("mods", [])), 6, 0, 0, 0))
	if pv.get("moveFirst"):
		var note := arrival_note(view)
		if note != null:
			col.add_child(H.margin(note, 6, 0, 0, 0))
		col.add_child(H.margin(_tiny("Move the cursor around the target to choose the side you attack from; Q / E change the way you arrive.", UI.INK_FAINT), 4, 0, 0, 0))
	if ward != null:
		var gl := UI.label("%s stand guard: they take the blow aimed at %s, on their shields." % [squad_title(target), squad_title(ward)], "", 12, NEG)
		gl.add_theme_font_override("font", UI.font("alegreya", 700))
		gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gl.add_theme_constant_override("line_spacing", H.line_gap(12))
		col.add_child(H.margin(H.trim(gl, -1, -1), 4, 0, 0, 0))
	if target.get("tags", []).has("firstStrike") and pv.get("arc") == "front" and pv.get("moveFirst"):
		var fs := UI.label("Spearmen strike first at anyone charging their front.", "", 12, NEG)
		fs.add_theme_font_override("font", UI.font("alegreya", 700))
		fs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fs.add_theme_constant_override("line_spacing", H.line_gap(12))
		col.add_child(H.margin(H.trim(fs, -1, -1), 4, 0, 0, 0))
	p.add_child(col)
	return p


## The `.mods` list of a forecast: each modifier with its value (the skill it
## starts from plain, bonuses green, penalties red), a dotted rule under each row.
## `any_skill`: every "… skill" counts as the base (the spell forecast's
## "Spell skill", "Crew skill"); otherwise only Melee and Ranged skill do.
static func _mods(list: Array, any_skill := false) -> Control:
	var mods := UI.vbox(0)
	mods.name = "Mods"
	for m in list:
		var k := str(m[0])
		var val: float = float(m[1])
		var skill := k.ends_with("skill") if any_skill else (k == "Melee skill" or k == "Ranged skill")
		var vs := ("+" + _num(m[1])) if val > 0 and not skill else _num(m[1])
		var vl := UI.label(vs, "", 12, POS if val > 0 and not skill else (NEG if val < 0 else H.NONE))
		if (val > 0 and not skill) or val < 0:
			vl.add_theme_font_override("font", UI.font("alegreya", 700))
		mods.add_child(_dotted_row(UI.label(k, "", 12), vl))
	return mods


# ---------------------------------------------------------------- spell forecast

## What a spell (or a war machine's stone) would do: its chance, and every
## squad it would touch with the damage, the dead and the healing, friends
## caught in a blast called out in orange.
static func spell_forecast(view: Object) -> Control:
	var b = view.b
	var pv: Dictionary = view.ui.hover.spell
	var ab: Dictionary = DB.ABILITIES.get(pv.ability, {})
	var caster: Variant = b.unit(view.ui.selected) if view.ui.selected != null else null
	var hostile: bool = ab.get("power") != null
	var hits: Array = pv.get("hits", [])
	var friendly: Array = hits.filter(func(h): return h.get("ally") and not h.get("heal") and float(h.get("max", 0)) > 0)

	var p := UI.panel("ParchmentPanel", [16, 16])
	p.name = "SpellForecast"
	p.custom_minimum_size.x = 300
	var col := UI.vbox(0)
	# Head: the spell, who casts it and how hard, its icon.
	var head := UI.hbox(8)
	var left := UI.vbox(0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := UI.cinzel(str(ab.get("name", pv.ability)), 16, 700)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(t)
	var sub := ""
	if caster != null:
		var n := int(pv.get("casters", 0))
		sub = "%d %s %s" % [n, Squad.member_noun(caster.typeId, n), "at the engine" if ab.get("engine") else ("casts" if n == 1 else "cast")]
	if hostile:
		sub += " · %s–%s each" % [_num(ab.power[0]), _num(ab.power[1])]
	elif ab.get("heal") != null:
		sub += " · heals %s–%s each" % [_num(ab.heal[0]), _num(ab.heal[1])]
	var sl := UI.label(sub, "TinyMutedLabel")
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(H.trim(sl, -1, -1))
	head.add_child(left)
	var ic := Icon.make(str(ab.get("icon", "missing")), 34)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	col.add_child(head)
	col.add_child(UI.gap(0, 8))
	col.add_child(H.flourish())
	col.add_child(UI.gap(0, 8))
	if not pv.get("legal", false):
		var l := UI.label(str(pv.get("reason", "")), "BadLabel")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(l)
		p.add_child(col)
		return p

	# The chance, and where a miss lands.
	var chance := int(pv.chance)
	var top := UI.hbox(8)
	var lcol := UI.vbox(0)
	lcol.add_child(UI.label("Strikes home" if hostile else "Certain", "TinyMutedLabel"))
	var big := UI.label("%d%%" % chance, "", 40, Color("#2d5a1a") if chance >= 70 else (Color("#6b4a10") if chance >= 45 else Color("#8a1f15")))
	big.name = "Chance"
	big.add_theme_font_override("font", UI.font("cinzel", 900))
	lcol.add_child(H.trim(big, -6, -9))
	lcol.size_flags_vertical = Control.SIZE_SHRINK_END
	top.add_child(lcol)
	top.add_child(UI.spacer())
	if pv.get("scatter"):
		var sc := UI.label("A miss lands one tile astray, and still strikes whoever stands there.", "TinyMutedLabel")
		sc.name = "Scatter"
		sc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		sc.custom_minimum_size.x = 150
		sc.add_theme_constant_override("line_spacing", H.line_gap(12))
		var scm := H.trim(sc, -1, -1)
		scm.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		top.add_child(scm)
	col.add_child(top)
	if hits.is_empty():
		col.add_child(H.margin(_small("Nobody stands where it would land.", UI.INK_FAINT), 4, 0, 0, 0))

	# One row for every squad it touches.
	var rows := UI.vbox(0)
	rows.name = "Hits"
	for h in hits:
		var tu: Dictionary = b.unit(h.uid)
		var tv = _view_of(view, tu.uid)
		var own: bool = h.get("ally") and not h.get("heal") and float(h.get("max", 0)) > 0
		var alive := int(tv.alive if tv != null else tu.alive)
		var r := UI.hbox(8)
		r.name = "Hit_" + str(h.uid)
		r.tooltip_text = "%s: %d/%d standing" % [Squad.squad_name(tu), alive, int(tu.size)]
		r.mouse_filter = Control.MOUSE_FILTER_PASS
		var who := UI.hbox(0)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var role: String = ROLE_NAME.get(str(h.get("role", "")), "")
		if role != "":
			who.add_child(UI.label(role + ": ", "SmallMutedLabel"))
		who.add_child(UI.ellipsize(UI.label(Squad.squad_name(tu), "SmallLabel", 0, OWN_HIT if own else H.NONE)))
		r.add_child(who)
		var what := ""
		if h.get("heal"):
			what = "[b][color=%s]+%s–%s[/color][/b]" % [H.hex(POS), _num(h.min), _num(h.max)]
		elif float(h.get("max", 0)) > 0:
			what = "[b]%s–%s[/b]" % [_num(h.min), _num(h.max)]
			var s0 := int(h.soldiers[0])
			var s1 := int(h.soldiers[1])
			if s1 > 0:
				var slays := " · slays %s" % (str(s1) if s0 == s1 else "%d–%d" % [s0, s1])
				what += slays if own else "[b][color=%s]%s[/color][/b]" % [H.hex(POS), slays]
		else:
			var st: Variant = ab.get("status")
			what = "[color=%s]%s[/color]" % [H.hex(UI.INK_FAINT), status_name(str(st.id)) if st is Dictionary else "—"]
		var val := H.rich(what, 13, OWN_HIT if own else H.NONE)
		val.autowrap_mode = TextServer.AUTOWRAP_OFF
		val.size_flags_horizontal = Control.SIZE_SHRINK_END
		r.add_child(val)
		rows.add_child(H.trim(r, 0, -1))
	col.add_child(H.margin(rows, 4, 0, 0, 0))
	if not friendly.is_empty():
		col.add_child(H.margin(_tiny("Your own %s in the blast!" % ("squad stands" if friendly.size() == 1 else "squads stand"), OWN_HIT), 4, 0, 0, 0))
	var status: Variant = ab.get("status")
	if status is Dictionary and hostile:
		var info: Dictionary = STATUS_INFO.get(str(status.id), {"name": status_name(str(status.id)), "text": ""})
		col.add_child(H.margin(_tiny("Everyone struck is %s: %s" % [str(info.name).to_lower(), info.text]), 4, 0, 0, 0))
	if ab.get("bleed"):
		col.add_child(H.margin(_tiny("The wound bleeds for %d%% of the damage at the start of its next two turns." % JS.rnd(float(ab.bleed) * 100.0)), 4, 0, 0, 0))
	var ml: Array = pv.get("mods", [])
	if not ml.is_empty():
		col.add_child(H.margin(_mods(ml, true), 6, 0, 0, 0))
	p.add_child(col)
	return p


## `.mods div`: label and value apart, a dotted rule under the row.
static func _dotted_row(a: Control, b: Control) -> Control:
	# 12.5 px text, padding 1 px 0 and a 1 px rule: 20 px a row.
	var r := _row_between(H.trim(a, -1, -1), H.trim(b, -1, -1))
	var m := H.margin(r, 1, 0, 3, 0)
	m.draw.connect(func():
		var y := m.size.y - 0.5
		var c := Color(91 / 255.0, 70 / 255.0, 48 / 255.0, 0.25)
		var x := 0.0
		while x < m.size.x:
			m.draw_rect(Rect2(x, y - 0.5, 1, 1), c)
			x += 2.0)
	return m


## Which way the squad will face after its move-and-strike, relative to its target.
static func arrival_note(view: Object) -> Control:
	var h: Dictionary = view.ui.hover
	var pv: Variant = h.get("preview")
	if pv == null or h.get("facing") == null or h.get("dest") == null:
		return null
	var t: Dictionary = view.b.unit(pv.target)
	var me: Dictionary = t.duplicate()
	me.x = h.dest.x
	me.y = h.dest.y
	me.facing = h.facing
	var arc: String = view.b.arc_of(me, t)
	var text := "facing the enemy" if arc == "front" else ("side-on to the enemy: its next blows land in your flank" if arc == "flank" else "with your back to the enemy")
	var l := UI.label("Arrives %s %s." % [FACING_ARROW.get(int(h.facing), ""), text], "", 12, H.NONE if arc == "front" else NEG)
	if arc != "front":
		l.add_theme_font_override("font", UI.font("alegreya", 700))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_constant_override("line_spacing", H.line_gap(12))
	return H.trim(l, -1, -1)


# ---------------------------------------------------------------- hovered squad

static func unit_info(view: Object, u: Dictionary) -> Control:
	var b = view.b
	var def: Dictionary = DB.UNIT_TYPES.get(u.typeId, {})
	var v = _view_of(view, u.uid)
	var hp := maxi(0, JS.rnd(float(v.hp if v != null else u.hp)))
	var alive := int(v.alive if v != null else u.alive)
	var morale: Variant = v.morale if v != null else u.morale
	var per := func(r: Array) -> String:
		return "%s–%s × %d = %s–%s" % [_num(r[0]), _num(r[1]), alive, _num(r[0] * alive), _num(r[1] * alive)]

	var p := UI.panel("ParchmentPanel", [16, 16])
	p.name = "UnitInfo"
	p.custom_minimum_size.x = 300
	var col := UI.vbox(0)
	var kind := ""
	if u.get("leader"):
		kind = "%s %s" % [UI.rank_name(int(u.get("level", 1))), def.get("name", u.typeId)]
	else:
		kind = UI.squad_type_label(u.typeId, int(u.get("level", 0)) if u.faction == "player" else 0)
	var sub := UI.label("%s · %s" % [kind, def.get("role", "")], "TinyMutedLabel")
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_header(squad_title(u), sub, u))
	col.add_child(UI.gap(0, 8))
	col.add_child(H.flourish())
	col.add_child(UI.gap(0, 8))
	col.add_child(_small(str(def.get("blurb", ""))))
	var sol := UI.hbox(5)
	sol.add_child(UI.label("Alone" if int(u.size) == 1 else "Soldiers", "SmallLabel"))
	sol.add_child(MenPips.make(alive, int(u.size)))
	col.add_child(H.margin(_row_between(sol, UI.label("%s HP each" % _num(u.hpPer), "TinyMutedLabel")), 6, 0, 0, 0))
	col.add_child(SquadBar.make(hp, float(u.hpPer), int(u.size), alive, 7))
	col.add_child(H.margin(_small("HP %d/%s · Morale %s (%s)" % [hp, _num(u.maxHp), MORALE_LABEL.get(b.morale_state(u), ""), _num(morale)]), 4, 0, 0, 0))
	var shot: Variant = u.get("shot")
	var primary: Dictionary = DB.ABILITIES.get(def.primary, {}) if def.get("primary") != null else {}
	var dmg_line := ""
	if shot != null:
		dmg_line += "%s %s · " % [shot_name(u), per.call(shot.damage)]
	if primary.get("power") != null:
		dmg_line += "%s %s · " % [primary.name, per.call(primary.power)]
	var dl := _tiny(dmg_line + "Melee %s" % per.call(u.melee))
	dl.tooltip_text = "Per soldier × soldiers standing, before armour"
	dl.mouse_filter = Control.MOUSE_FILTER_STOP
	col.add_child(H.margin(dl, 3, 0, 0, 0))
	var st: Dictionary = u.stats
	var s := "Melee %s · Def %s" % [_num(st.melee), _num(st.defense)]
	if u.get("shieldFront"):
		s += " (+%s)" % _num(u.shieldFront)
	s += " · Armour %s · Move %s" % [JS.to_fixed(float(st.armor), 1), _num(st.move)]
	if shot != null:
		s += " · %s %s, range %s" % ["Spells" if (u.get("tags", []) as Array).has("caster") else "Bow", _num(st.ranged), _num(shot.range)]
	col.add_child(H.margin(_tiny(s), 4, 0, 0, 0))
	var abl: Array = u.get("abilities", [])
	if abl.size() > 0:
		var cds: Dictionary = u.get("cooldowns", {}) if u.get("cooldowns") is Dictionary else {}
		var names := abl.map(func(a):
			var cd := int(cds.get(a, 0))
			return str(DB.ABILITIES.get(a, {}).get("name", a)) + (" (ready in %d)" % cd if cd > 0 else ""))
		var al := _tiny(", ".join(names))
		al.name = "Abilities"
		col.add_child(H.margin(al, 4, 0, 0, 0))
	var chips := status_chips(u)
	if chips != null:
		col.add_child(H.margin(chips, 4, 0, 0, 0))
	var wound: Variant = u.get("wound")
	if wound != null:
		var wl: String
		if wound.kind == "injured":
			wl = "Injured in its last fight: %s. %s." % [Squad.wound_text(wound), Squad.hurt_text(wound)]
		else:
			wl = "Wounded in its last fight (%d still hurt): %s. %s." % [wound.get("hurt", wound.fell), Squad.wound_text(wound), Squad.hurt_text(wound)]
		var wlc := _small(wl, Color("#8a1f15"))
		wlc.name = "Wound"
		col.add_child(H.margin(wlc, 4, 0, 0, 0))
	if u.get("leader"):
		col.add_child(H.margin(_small("Warband leader: if he falls, his followers lose heart.", Color("#8a1f15")), 4, 0, 0, 0))
	p.add_child(col)
	return p


# ---------------------------------------------------------------- hovered tile

static func tile_info(view: Object) -> Control:
	var h: Dictionary = view.ui.hover
	var t: Dictionary = h.tile
	var tile: Variant = Grid.tile_at(view.b.map, int(t.x), int(t.y))
	if tile == null:
		return null
	var ter: Dictionary = DB.TERRAIN.get(tile.terrain, {})
	var prop: Variant = DB.PROPS.get(tile.prop) if tile.get("prop") != null else null
	var p := UI.panel("DarkPanel", [10, 14])
	p.name = "TileInfo"
	p.custom_minimum_size.x = 240
	var col := UI.vbox(0)
	if view.fog != null and view.fog.tile_state(t.x, t.y) == 0:
		col.add_child(UI.cinzel("Unexplored terrain", 16, 700))
		p.add_child(col)
		return p
	col.add_child(UI.cinzel(str(prop.name if prop != null else ter.get("name", tile.terrain)), 16, 700))
	var s := ""
	if prop != null:
		s = "Passable · Move cost %s" % _num(Grid.move_cost(view.b.map, t.x, t.y)) if Grid.tile_passable(view.b.map, t.x, t.y) else "Impassable"
	else:
		var mc: Variant = ter.get("moveCost", 1)
		s = "Move cost %s" % ("–" if float(mc) >= 99 else _num(mc))
	if int(tile.get("h", 0)) > 0:
		s += " · High ground (+%s)" % _num(tile.h)
	if ter.get("rangedCover"):
		s += " · -%s%% to missiles" % _num(ter.rangedCover)
	if prop != null and prop.get("cover"):
		s += " · Cover %s%%" % _num(prop.cover)
	if prop != null and prop.get("los") == 2:
		s += " · Blocks sight"
	col.add_child(_tiny(s))
	if h.get("facing") != null and h.get("dest") != null:
		var facings: Variant = h.get("facings")
		var nf: int = facings.size() if facings is Array else 0
		var line := "%s facing %s" % ["Turn on the spot" if h.get("turn") else "Arrives", FACING_ARROW.get(int(h.facing), "")]
		var more := " · Q / E or point at an edge: other sides (%d)" % nf if nf > 1 else " · the only way in"
		col.add_child(H.margin(H.rich("%s[color=%s]%s[/color]" % [line, H.hex(UI.DARK_MUTED), more], 12, UI.GOLD_BRIGHT), 3, 0, 0, 0))
	if h.get("zoc"):
		col.add_child(H.margin(_tiny("This path leaves enemy reach: %s free attack(s)." % _num(h.zoc), Color("#ffb070")), 3, 0, 0, 0))
	p.add_child(col)
	return p
