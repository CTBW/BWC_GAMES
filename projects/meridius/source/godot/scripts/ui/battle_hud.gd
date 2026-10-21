## The battle screen's HUD over the battle view: port of `BattleHud` in
## src/ui/screens/Battle.tsx (top bar with title, turn line, enemy count,
## grid / danger / speed / manual toggles, Retreat and Begin Battle / End Turn;
## the objective panel; the company column; turn banners; the attack preview,
## hovered squad and hovered tile panels; the selected squad's card; the battle
## log; the retreat confirmation). The panels are built by hud_battle_panels.gd.
##
## Hosting (scripts/app/main.gd on the battle screen):
##   var hud = preload("res://scripts/ui/battle_hud.gd").new()
##   hud.setup(battle_view)        # the BattleView node (scripts/render/battle_view.gd)
##   ui_layer.add_child(hud)       # full rect; empty areas let clicks through to the field
## The HUD reads `view.b`, `view.ui`, `view.views`, `view.speed` and redraws when
## they change (signal `ui_changed`, and per frame for the playback values). Its
## buttons call the view (`select`, `set_ability`, `redo`, `end_unit`, `begin`,
## `end_turn`, `retreat`, `notify`) and the store (`App.open_manual("battle")`;
## the title comes from `App.battle_info.title` when set, else `b.setup.title`).
## Keyboard shortcuts are the view's input actions; while the retreat
## confirmation is open the HUD keeps keys from the field (Esc closes it).
##
##   hud.app = some_store          # optional stand-in for the App autoload (tests)
##   hud.refresh()                 # rebuild now (normally automatic)
extends Control

const UI = preload("res://scripts/ui/ui.gd")
const H = preload("res://scripts/ui/hud_common.gd")
const JS = preload("res://scripts/core/js.gd")
const DB = preload("res://scripts/data/db.gd")
const Prefs = preload("res://scripts/core/prefs.gd")
const Squad = preload("res://scripts/rules/squad.gd")
const Icon = preload("res://scripts/ui/widgets/icon.gd")
const Bar = preload("res://scripts/ui/widgets/bar.gd")
const SquadBar = preload("res://scripts/ui/widgets/squad_bar.gd")
const MenPips = preload("res://scripts/ui/widgets/men_pips.gd")
const Portrait = preload("res://scripts/ui/widgets/portrait.gd")
const Tip = preload("res://scripts/ui/widgets/tip.gd")
const Modal = preload("res://scripts/ui/widgets/modal.gd")
const ScrollBox = preload("res://scripts/ui/widgets/scroll_box.gd")
const RichButton = preload("res://scripts/ui/widgets/rich_button.gd")
const Panels = preload("res://scripts/ui/hud_battle_panels.gd")

const TOP_MUTED := Color("#cdb88a")
const BANNER_COLOURS := {"player": Color("#cfe0ff"), "enemy": Color("#ffb8a8"), "neutral": Color("#f6e7c2")}
const LOG_COLOURS := {"good": Color("#9fe08a"), "bad": Color("#ff9a86")}
const OBJECTIVE_TONES := {"bad": Color("#ffb0a0"), "good": Color("#a8e89a"), "warn": Color("#ffd76a")}

## The battle view (scripts/render/battle_view.gd).
var view: Node = null
## The store; null means the App autoload.
var app: Object = null

var _top: Control
var _objective: Control
var _company: VBoxContainer
var _cards := {}
var _banner: Control
var _banner_tween: Tween
var _info: Control
var _unit: Control
var _log: Control
var _confirm: Control = null
var _end_turn: Button = null
var _pulse := false
var _pulse_t := 0.0
var _sigs := {}
var _view_set := false


func setup(battle_view: Node) -> void:
	if view != null and is_instance_valid(view) and view.has_signal("ui_changed") and view.is_connected("ui_changed", refresh):
		view.disconnect("ui_changed", refresh)
	view = battle_view
	_view_set = true
	_sigs.clear()
	_cards.clear()
	if _company != null:
		UI.clear(_company)
	if view != null and view.has_signal("ui_changed"):
		view.connect("ui_changed", refresh)
	refresh()


func _init() -> void:
	name = "BattleHud"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_company = UI.vbox(6)
	_company.name = "Company"
	_company.custom_minimum_size.x = 230
	H.place(_company, 0, 0, 12, 70)
	add_child(_company)


func _ready() -> void:
	refresh()


func _process(dt: float) -> void:
	if not is_visible_in_tree():
		return
	refresh()
	if _pulse and _end_turn != null and is_instance_valid(_end_turn):
		_pulse_t += dt
		var k := 1.0 + 0.3 * (0.5 - 0.5 * cos(TAU * _pulse_t / 1.6))
		_end_turn.modulate = Color(k, k, k)


func _input(e: InputEvent) -> void:
	# The retreat confirmation is a dialog: keys do not reach the field behind it.
	if _confirm != null and e is InputEventKey and not e.is_action("toggle_fullscreen"):
		if e.pressed and not e.is_echo() and e.is_action("cancel"):
			_close_confirm()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- state

func _app() -> Object:
	return app if app != null else H.app(self)


func _ok() -> bool:
	return view != null and is_instance_valid(view) and view.get("b") != null


func _v(uid: Variant) -> Variant:
	var vs: Variant = view.get("views")
	return vs.get(uid) if vs is Dictionary else null


func my_turn() -> bool:
	return view.b.phase == "player" and not view.ui.busy


func _title() -> String:
	var info: Variant = _app().get("battle_info") if _app() != null else null
	if info is Dictionary and info.get("title") != null:
		return str(info.title)
	return str(view.b.setup.get("title", ""))


## Enemy squads on the field as played back so far, and squads still to come in waves.
func enemy_counts() -> Vector2i:
	var b = view.b
	var left := 0
	for u in b.units:
		if u.faction != "enemy":
			continue
		var v = _v(u.uid)
		if v != null:
			if not v.reserve and v.status == "active" and not v.routing:
				left += 1
		elif u.status == "active":
			left += 1
	var coming := 0
	var waves: Array = b.waves
	for i in waves.size():
		var w: Dictionary = waves[i]
		var st: Variant = b.wave_state[i] if i < b.wave_state.size() else "pending"
		if st == "cancelled" or (w.get("horn") and b.horn == "silent"):
			continue
		for id in w.get("uids", []):
			var v = _v(id)
			if v != null and v.reserve:
				coming += 1
	return Vector2i(left, coming)


func ready_count() -> int:
	var n := 0
	for u in view.b.active("player"):
		if not u.done and (not u.hasMoved or not u.hasActed):
			n += 1
	return n


# ---------------------------------------------------------------- refresh

## Follows the store's battle view unless setup() was given one.
func _sync_view() -> void:
	if _view_set and view != null and is_instance_valid(view):
		return
	var a := _app()
	var v: Variant = a.get("battle_view") if a != null else null
	if v is Node and v != view:
		setup(v)
		_view_set = false


func refresh() -> void:
	_sync_view()
	if not _ok():
		# Nothing to show: drop the sections (they are rebuilt with the next battle).
		for c in [_top, _objective, _banner, _info, _unit, _log]:
			_drop(c)
		_top = null
		_objective = null
		_banner = null
		_info = null
		_unit = null
		_log = null
		UI.clear(_company)
		_cards.clear()
		_sigs.clear()
		return
	var b = view.b
	var ui: Dictionary = view.ui
	var counts := enemy_counts()
	var mt := my_turn()
	var fast := float(view.get("speed") if view.get("speed") != null else 1.0) > 1.0
	_section("top", [_title(), b.phase, ui.turn, ui.side, ui.busy, b.map.get("name"), b.setup.get("darkness"), counts, ui.showGrid, ui.danger, fast, mt, ready_count()], _build_top.bind(counts, mt, fast))
	var lines := objective_lines()
	_section("objective", [b.objective.get("title"), b.phase == "deploy", lines], _build_objective.bind(lines))
	_refresh_company()
	_section("banner", [ui.banner.id if ui.banner is Dictionary else null], _build_banner)
	_refresh_info()
	_refresh_unit()
	_section("log", ui.log.slice(0, 14), _build_log)
	if _confirm != null and is_instance_valid(_confirm):
		move_child(_confirm, -1)


## Takes a node out of the HUD now and frees it at the end of the frame.
static func _drop(n: Node) -> void:
	if n != null and is_instance_valid(n):
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		n.queue_free()


func _section(key: String, sig: Variant, build: Callable) -> void:
	var s := str(sig)
	if _sigs.get(key) == s:
		return
	_sigs[key] = s
	build.call()


func _swap(old: Control, c: Control) -> Control:
	_drop(old)
	if c != null:
		add_child(c)
	return c


# ---------------------------------------------------------------- top bar

func _build_top(counts: Vector2i, mt: bool, fast: bool) -> void:
	var b = view.b
	var ui: Dictionary = view.ui
	var bar := UI.panel("TopBar")
	UI.dark(bar)
	bar.name = "TopBar"
	bar.custom_minimum_size.y = 50
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 50
	var row := UI.hbox(18)
	var brand := UI.label(_title(), "BrandLabel", 17)
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(brand)
	var phase := ""
	if b.phase == "deploy":
		phase = "Deployment"
	elif b.phase == "over" and not ui.busy:
		phase = "Turn %d · Battle over" % int(ui.turn)
	else:
		phase = "Turn %d · %s" % [int(ui.turn), "Your move" if ui.side == "player" else "Enemy move"]
	var line := UI.label("%s · %s%s" % [phase, b.map.get("name", ""), " · Night" if b.setup.get("darkness") else ""], "", 13, TOP_MUTED)
	line.name = "TurnLine"
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line)
	row.add_child(UI.spacer())
	var en := UI.label("Enemy squads: %d on the field%s" % [counts.x, " · %d coming" % counts.y if counts.y > 0 else ""], "", 13, Color("#ffb0a0"))
	en.name = "EnemyCount"
	en.tooltip_text = "Enemy squads on the field, and squads still coming in waves"
	en.mouse_filter = Control.MOUSE_FILTER_PASS
	en.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(en)
	var grid := _icon_toggle("grid", bool(ui.showGrid), func(): _toggle("showGrid"))
	grid.name = "Grid"
	Tip.attach(grid, "Toggle grid (G)")
	row.add_child(grid)
	var danger := _icon_toggle("danger", bool(ui.danger), func(): _toggle("danger"))
	danger.name = "Danger"
	Tip.attach(danger, "Show where enemies can strike next turn (hold Alt)")
	row.add_child(danger)
	var speed := UI.button("2×" if fast else "1×", "SmallButtonActive" if fast else "SmallButton", _toggle_speed)
	speed.name = "Speed"
	speed.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Tip.attach(speed, "Battle speed")
	row.add_child(speed)
	var help := UI.button("?", "SmallButton", func(): _call_app("open_manual", ["battle"]))
	help.name = "Help"
	help.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Tip.attach(help, "Field manual")
	row.add_child(help)
	if b.phase != "deploy":
		var ret := UI.button("Retreat", "SmallButton", open_retreat)
		ret.name = "Retreat"
		ret.disabled = not mt
		ret.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ret)
	_end_turn = null
	_pulse = false
	if b.phase == "deploy":
		var beg := UI.button("Begin Battle", "RedButton", func(): view.begin())
		beg.name = "Begin"
		beg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(beg)
	else:
		var rdy := ready_count()
		var label := "End Turn" + (" (%d ready)" % rdy if rdy > 0 and mt else "")
		var et := RichButton.make([label, H.kbd("Enter")], "RedButton", func(): view.end_turn())
		et.name = "EndTurn"
		et.set_meta("label", label + " Enter")
		et.disabled = not mt
		et.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(et)
		_end_turn = et
		_pulse = mt and rdy == 0
		_pulse_t = 0.0
	bar.add_child(row)
	_top = _swap(_top, bar)


func _icon_toggle(icon: String, active: bool, on_press: Callable) -> Button:
	var btn := UI.button("", "IconButtonActive" if active else "IconButton", on_press)
	btn.icon = Icon.tex(icon)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.add_theme_color_override("icon_normal_color", UI.LIGHT)
	return btn


func _toggle(key: String) -> void:
	view.ui[key] = not bool(view.ui.get(key))
	view.notify()


func _toggle_speed() -> void:
	var fast := float(view.get("speed") if view.get("speed") != null else 1.0) > 1.0
	view.speed = 1.0 if fast else 2.0
	Prefs.set_pref("battleSpeed", view.speed)
	view.notify()


func _call_app(method: String, args: Array = []) -> void:
	var a := _app()
	if a == null or not a.has_method(method):
		push_warning("BattleHud: the store has no %s()" % method)
		return
	a.callv(method, args)


# ---------------------------------------------------------------- retreat confirmation

func open_retreat() -> void:
	if _confirm != null:
		return
	var d := Modal.dialog(520, [24, 28])
	var fight := UI.button("Fight on", "Button", _close_confirm)
	fight.name = "FightOn"
	var go := UI.button("Withdraw", "RedButton", func():
		_close_confirm()
		view.retreat())
	go.name = "Withdraw"
	d.add_child(H.stack([
		[H.title("Withdraw from the field?"), 0, 10],
		[H.para("Soldiers locked in melee take a parting blow as they pull back. The wounded are carried off. The enemy keeps the field, and you collect no spoils from it."), 8, 8],
		[H.center_row([fight, go]), 0, 0],
	]))
	_confirm = Modal.make(d)
	_confirm.name = "Confirm"
	_confirm.set_meta("on_cancel", _close_confirm)
	add_child(_confirm)


func _close_confirm() -> void:
	if _confirm != null and is_instance_valid(_confirm):
		_drop(_confirm)
	_confirm = null


func confirm_open() -> bool:
	return _confirm != null and is_instance_valid(_confirm)


# ---------------------------------------------------------------- objective

## What wins and loses this battle, how long until relief, the next wave and
## the war horn: [{text, tone}].
func objective_lines() -> Array:
	var b = view.b
	var o: Dictionary = b.objective
	var turn := int(view.ui.turn)
	var lines: Array = []
	if (o.get("kind") == "survive" or o.get("kind") == "hold") and o.get("turns"):
		var left: int = int(o.turns) - turn
		lines.append({"text": "Hold this one last turn!" if left <= 0 else "Turn %d of %d · %d more %s after this" % [turn, int(o.turns), left, "turn" if left == 1 else "turns"], "tone": "good" if left <= 1 else null})
	if o.get("kind") == "hold" and b.map.get("zoneName"):
		lines.append({"text": "Keep the enemy out of %s (gold line)" % str(b.map.zoneName).to_lower(), "tone": null})
	if o.get("warchief"):
		var chief: Variant = null
		for u in b.units:
			if u.get("tags", []).has("warchief"):
				chief = u
				break
		var v = _v(chief.uid) if chief != null else null
		if chief != null and v != null and not v.reserve and chief.status == "active":
			lines.append({"text": "The warchief is on the field: slay %s to break the horde" % str(chief.name).split(",")[0], "tone": "warn"})
		elif chief != null and chief.status == "reserve":
			lines.append({"text": "Slay the warchief when he comes to break the horde", "tone": null})
	var horn_wave := false
	for w in b.waves:
		if w.get("horn"):
			horn_wave = true
	if o.get("hornTurn") != null and b.horn == "waiting" and horn_wave:
		var left: int = int(o.hornTurn) - turn
		lines.append({"text": "The horn-bearer sounds his horn this enemy turn unless he falls!" if left <= 0 else "The horn-bearer sounds his horn in %d %s: kill him first" % [left, "turn" if left == 1 else "turns"], "tone": "bad"})
	if b.horn == "silent" and horn_wave:
		lines.append({"text": "The horn is silenced", "tone": "good"})
	var nxt: Variant = view.next_wave_info() if view.has_method("next_wave_info") else null
	if nxt is Dictionary:
		var due := int(nxt.dueIn)
		var when := "at the end of this turn" if due <= 0 else ("next turn" if due == 1 else "in %d turns" % due)
		var head := "Wave %d of %d" % [int(nxt.index), int(nxt.total)] if int(nxt.total) > 1 else "Reinforcements"
		lines.append({"text": "%s: %d squads from the %s edge %s" % [head, int(nxt.count), nxt.edge, when], "tone": "bad" if due <= 1 else null})
	return lines


func _build_objective(lines: Array) -> void:
	var b = view.b
	var o: Dictionary = b.objective
	var p := UI.panel("DarkPanel", [8, 18, 10, 18])
	p.name = "Objective"
	H.place(p, 0.5, 0, 0, 58, 0, 1)
	var col := UI.vbox(0)
	var texts: Array = []
	var t := UI.label(str(o.get("title", "")), "", 15, UI.LIGHT_TITLE)
	t.add_theme_font_override("font", UI.font("cinzel", 700))
	texts.append([t, 15, UI.font("cinzel", 700)])
	if b.phase == "deploy" and o.get("brief") != null:
		var br := UI.label(str(o.brief), "", 13, Color("#e9dcc0"))
		br.add_theme_constant_override("line_spacing", H.line_gap(13))
		texts.append([br, 13, UI.font("alegreya", 400), 2])
	for l in lines:
		var ll := UI.label(str(l.text), "", 12, OBJECTIVE_TONES.get(l.get("tone"), Color("#d8c8a4")))
		ll.add_theme_constant_override("line_spacing", H.line_gap(12))
		texts.append([ll, 12, UI.font("alegreya", 400), 2])
	# max-width: min(640px, 70vw); shrink to the longest line.
	var vw := get_viewport_rect().size.x if is_inside_tree() else 1920.0
	var max_w := minf(640.0, vw * 0.7) - 40.0
	var w := 0.0
	for it in texts:
		var f: Font = it[2]
		w = maxf(w, f.get_string_size(it[0].text, HORIZONTAL_ALIGNMENT_LEFT, -1, it[1]).x + 2.0)
	w = minf(w, max_w)
	for it in texts:
		var l: Label = it[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = w
		if it.size() > 3:
			col.add_child(UI.gap(0, it[3]))
		col.add_child(l)
	p.add_child(col)
	_ignore_all(p)
	_objective = _swap(_objective, p)


static func _ignore_all(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_all(c)


# ---------------------------------------------------------------- company

func _refresh_company() -> void:
	var b = view.b
	var players: Array = b.units.filter(func(u): return u.faction == "player")
	var ids: Array = players.map(func(u): return u.uid)
	if str(ids) != str(_cards.keys()):
		UI.clear(_company)
		_cards.clear()
		for uid in ids:
			_cards[uid] = {"node": null, "sig": ""}
	for u in players:
		var v = _v(u.uid)
		var st: String = str(v.status) if v != null and v.status != null else str(u.status)
		var done: bool = b.phase == "player" and bool(u.get("done", false))
		var sig := str([view.ui.selected == u.uid, st, v.alive if v != null else u.alive, JS.rnd(float(v.hp if v != null else u.hp)), v.morale if v != null else u.morale, v.routing if v != null else false, u.get("stance"), done, u.name])
		var rec: Dictionary = _cards[u.uid]
		if rec.sig == sig and rec.node != null and is_instance_valid(rec.node):
			continue
		rec.sig = sig
		var card := _mini_card(u, v, st, done, view.ui.selected == u.uid)
		if rec.node != null and is_instance_valid(rec.node):
			var idx: int = rec.node.get_index()
			rec.node.queue_free()
			_company.remove_child(rec.node)
			_company.add_child(card)
			_company.move_child(card, idx)
		else:
			_company.add_child(card)
		rec.node = card


func _mini_card(u: Dictionary, v, st: String, done: bool, selected: bool) -> Control:
	var gone := st == "dead" or st == "downed" or st == "fled"
	var routing: bool = (v != null and v.routing) or st == "routing"
	var alive: int = int(v.alive if v != null else u.alive)
	var hp: float = float(v.hp if v != null else u.hp)
	var morale: float = float(v.morale if v != null else u.morale)
	var p := UI.panel("DarkPanel", [8, 8])
	p.name = "Mini_" + str(u.uid)
	p.tooltip_text = "%s: %d/%d standing, %d/%s HP" % [Squad.squad_name(u), alive, int(u.size), maxi(0, JS.rnd(hp)), JS.num_str(u.maxHp)]
	if gone:
		p.modulate.a = 0.5
	elif done:
		p.modulate.a = 0.6
	if not gone:
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var uid: String = u.uid
		p.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				p.accept_event()
				view.select(uid))
	if selected:
		var ring := StyleBoxFlat.new()
		ring.draw_center = false
		ring.border_color = UI.GOLD_BRIGHT
		ring.set_border_width_all(2)
		ring.set_corner_radius_all(9)
		ring.anti_aliasing = true
		p.draw.connect(func(): p.draw_style_box(ring, Rect2(Vector2(-2, -2), p.size + Vector2(4, 4))))
	var row := UI.hbox(8)
	var por := Portrait.make(u.typeId, int(u.get("variant", 0)), 36, st == "dead")
	por.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(por)
	var col := UI.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var line := UI.hbox(4)
	var nm := UI.ellipsize(UI.cinzel(Panels._first_word(str(u.name)), 12, 700, UI.LIGHT))
	line.add_child(H.trim(nm, 0, -1))
	var status := ""
	if st == "dead":
		status = "Slain"
	elif st == "downed":
		status = "Cut down"
	elif st == "fled":
		status = "Fled"
	elif routing:
		status = "Fleeing"
	elif u.get("stance") != null:
		status = str(DB.ABILITIES.get(u.stance, {}).get("name", ""))
	elif done:
		status = "Done"
	var sl := UI.label(status, "TinyLabel", 0, Color("#ff9a86") if routing else UI.DARK_MUTED)
	line.add_child(H.trim(sl, -1, -1))
	col.add_child(line)
	col.add_child(SquadBar.make(hp, float(u.hpPer), int(u.size), alive, 7))
	var bottom := UI.hbox(6)
	var mb := Bar.make(morale, float(u.maxMorale), "morale", 4)
	mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(mb)
	bottom.add_child(H.trim(MenPips.make(alive, int(u.size)), -1, -1))
	col.add_child(H.margin(bottom, 2, 0, 0, 0))
	row.add_child(col)
	p.add_child(row)
	return p


# ---------------------------------------------------------------- banner

func _build_banner() -> void:
	var bn: Variant = view.ui.banner
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	if not (bn is Dictionary):
		_banner = _swap(_banner, null)
		return
	var box := UI.vbox(0)
	box.name = "Banner"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	H.place(box, 0.5, 0.24, 0, 0, 0, 1)
	box.add_child(_banner_rule())
	var h1 := UI.label(str(bn.text), "BannerLabel", 0, BANNER_COLOURS.get(bn.get("tone"), BANNER_COLOURS.neutral))
	h1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(h1)
	box.add_child(_banner_rule())
	if bn.get("sub") != null and str(bn.sub) != "":
		var sub := UI.label(str(bn.sub), "BannerSubLabel")
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(sub)
	_ignore_all(box)
	_banner = _swap(_banner, box)
	# CSS `banner` keyframes over 1.6 s: fade in and settle from 115 %, hold, fade out.
	box.modulate.a = 0.0
	box.scale = Vector2(1.15, 1.15)
	box.resized.connect(func(): box.pivot_offset = box.size * 0.5)
	var tw := create_tween()
	_banner_tween = tw
	tw.set_parallel(true)
	tw.tween_property(box, "modulate:a", 1.0, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(box, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(0.96)
	tw.chain().tween_property(box, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _banner_rule() -> Control:
	var r := Control.new()
	r.custom_minimum_size = Vector2(360, 14)
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	r.draw.connect(func():
		var y := 6.0
		var gold := UI.GOLD
		var clear := Color(gold, 0.0)
		var w := r.size.x
		r.draw_polygon(PackedVector2Array([Vector2(0, y), Vector2(w * 0.5, y), Vector2(w * 0.5, y + 2), Vector2(0, y + 2)]), PackedColorArray([clear, gold, gold, clear]))
		r.draw_polygon(PackedVector2Array([Vector2(w * 0.5, y), Vector2(w, y), Vector2(w, y + 2), Vector2(w * 0.5, y + 2)]), PackedColorArray([gold, clear, clear, gold])))
	return r


# ---------------------------------------------------------------- hover panels

func _refresh_info() -> void:
	var b = view.b
	var h: Dictionary = view.ui.hover
	var sel: Variant = b.unit(view.ui.selected) if view.ui.selected != null else null
	var kind := ""
	var sig: Array = []
	if h.get("preview") != null and sel != null:
		kind = "forecast"
		var t: Variant = b.unit(h.preview.target)
		var tv = _v(h.preview.target)
		sig = [h.preview, view.ui.selected, h.get("facing"), h.get("dest"), t.morale if t != null else null, t.status if t != null else null,
			[tv.hp, tv.alive] if tv != null else null]
	elif h.get("unit") != null:
		kind = "unit"
		var u: Variant = b.unit(h.unit)
		var v = _v(h.unit)
		sig = [h.unit, u.morale if u != null else null, u.status if u != null else null, [v.hp, v.alive, v.morale] if v != null else null]
	elif h.get("tile") != null:
		kind = "tile"
		sig = [h.tile, h.get("facing"), h.get("dest"), h.get("facings"), h.get("turn"), h.get("zoc")]
	_section("info", [kind, sig], _build_info.bind(kind))


func _build_info(kind: String) -> void:
	var c: Control = null
	match kind:
		"forecast":
			c = Panels.forecast(view)
		"unit":
			var u: Variant = view.b.unit(view.ui.hover.unit)
			if u != null:
				c = Panels.unit_info(view, u)
		"tile":
			c = Panels.tile_info(view)
	if c != null:
		H.place(c, 1, 0, -16, 70, -1, 1)
	_info = _swap(_info, c)


# ---------------------------------------------------------------- selected squad

func _refresh_unit() -> void:
	var b = view.b
	var sel: Variant = b.unit(view.ui.selected) if view.ui.selected != null else null
	var show: bool = sel != null and sel.status == "active" and b.phase != "over"
	var sig: Array = [show]
	if show:
		var v = _v(sel.uid)
		sig = [show, sel.uid, sel.hasMoved, sel.hasActed, sel.get("cooldowns"), sel.get("ammo"), sel.get("stance"), sel.morale, sel.level,
			[v.hp, v.alive, v.morale, v.facing] if v != null else null, view.ui.ability, view.ui.busy, b.phase, b.can_redo(sel.uid)]
	_section("unit", sig, _build_unit.bind(sel if show else null))


func _build_unit(sel: Variant) -> void:
	if sel == null:
		_unit = _swap(_unit, null)
		return
	var p := Panels.unit_panel(view, sel)
	H.place(p, 0.5, 1, 0, -14, 0, -1)
	_unit = _swap(_unit, p)


# ---------------------------------------------------------------- log

func _build_log() -> void:
	var p := UI.panel("DarkPanel", [10, 14])
	p.name = "Log"
	var vw := get_viewport_rect().size.x if is_inside_tree() else 1920.0
	p.custom_minimum_size.x = 260 if vw <= 1400 else 330
	H.place(p, 1, 1, -12, -14, -1, -1)
	var col := UI.vbox(0)
	var lines: Array = view.ui.log.slice(0, 14)
	for i in lines.size():
		var l: Dictionary = lines[i]
		var lab := UI.label(str(l.text), "", 13, LOG_COLOURS.get(l.get("tone"), UI.LIGHT))
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.add_theme_constant_override("line_spacing", H.line_gap(13))
		lab.modulate.a = 1.0 - i * 0.05
		col.add_child(H.trim(lab, -1, -1))
	if lines.is_empty():
		col.add_child(UI.label("Hold the line. Mind the flanks.", "SmallMutedLabel"))
	p.add_child(ScrollBox.make(col, 170.0 - 20.0))
	_log = _swap(_log, p)
