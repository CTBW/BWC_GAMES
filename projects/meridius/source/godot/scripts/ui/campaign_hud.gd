## The campaign screen's HUD over the campaign map: port of `Campaign` in
## src/ui/screens/Campaign.tsx (top bar with the march, supplies and spoils;
## the army panel; the hovered node's card; the march prompt; the log; Find
## army / Retreat home and its confirmation; the pending-event dialogs of
## hud_campaign_dialogs.gd; the soldier detail overlay).
##
## Hosting (scripts/app/main.gd on the campaign screen):
##   var hud = preload("res://scripts/ui/campaign_hud.gd").new()
##   hud.setup(campaign_view)      # the CampaignView node (or null): hover, marching, focus_current()
##   ui_layer.add_child(hud)       # full rect; empty areas let clicks through to the map
## It reads `App.game` (GameState with `expedition`) and redraws on `App.changed`
## and on the view's `ui_changed`; buttons call the store like the original
## (`App.dismiss()`, `App.start_battle()`, `App.go_home(outcome)`,
## `App.open_manual("campaign")`, `App.open_soldier(id)`, `App.commit()`) and the
## expedition rules (scripts/campaign/expedition.gd) for event choices, camp
## actions, village searches and bandages.
##
##   hud.app = some_store          # optional: a stand-in for the App autoload (tests)
##   hud.refresh()                 # rebuild now (normally automatic)
extends Control

const UI = preload("res://scripts/ui/ui.gd")
const H = preload("res://scripts/ui/hud_common.gd")
const DB = preload("res://scripts/data/db.gd")
const Deps = preload("res://scripts/ui/deps.gd")
const Squad = preload("res://scripts/rules/squad.gd")
const Icon = preload("res://scripts/ui/widgets/icon.gd")
const Bar = preload("res://scripts/ui/widgets/bar.gd")
const SquadBar = preload("res://scripts/ui/widgets/squad_bar.gd")
const MenPips = preload("res://scripts/ui/widgets/men_pips.gd")
const Portrait = preload("res://scripts/ui/widgets/portrait.gd")
const ResList = preload("res://scripts/ui/widgets/res_list.gd")
const Tip = preload("res://scripts/ui/widgets/tip.gd")
const Tag = preload("res://scripts/ui/widgets/tag.gd")
const Modal = preload("res://scripts/ui/widgets/modal.gd")
const ScrollBox = preload("res://scripts/ui/widgets/scroll_box.gd")
const Dialogs = preload("res://scripts/ui/hud_campaign_dialogs.gd")

const TOP_MUTED := Color("#cdb88a")
const ZERO := Color("#ff9a86")
const LOG_COLOURS := {"bad": Color("#ffb0a0"), "good": Color("#c8eab0")}
const LOG_DEFAULT := Color("#efe2c2")

## The campaign view (scripts/render/campaign_view.gd) or null.
var view: Node = null
## The store; null means the App autoload.
var app: Object = null

var _top: Control
var _army: Control
var _card: Control
var _prompt: Control
var _log: Control
var _buttons: Control
var _retreat: Button
var _confirm: Control = null
var _modal: Control = null
var _dialog: PanelContainer = null
var _soldier: Control = null
var _soldier_key := ""
var _sigs := {}
var _dirty := true
var _view_sig := ""
var _view_set := false


func setup(campaign_view: Node = null) -> void:
	if view != null and is_instance_valid(view):
		for sig in ["changed", "ui_changed"]:
			if view.has_signal(sig) and view.is_connected(sig, _on_changed):
				view.disconnect(sig, _on_changed)
	view = campaign_view
	_view_set = true
	if view != null:
		for sig in ["changed", "ui_changed"]:
			if view.has_signal(sig):
				view.connect(sig, _on_changed)
	_dirty = true


## Follows the store's campaign view unless setup() was given one.
func _sync_view() -> void:
	if _view_set and view != null and is_instance_valid(view):
		return
	var v: Variant = _app_get("campaign_view")
	if v is Node and v != view:
		setup(v)
		_view_set = false


func _init() -> void:
	name = "CampaignHud"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var a := _app()
	if a != null and a.has_signal("changed") and not a.is_connected("changed", _on_changed):
		a.connect("changed", _on_changed)
	refresh()


func _exit_tree() -> void:
	var a := _app()
	if a != null and a.has_signal("changed") and a.is_connected("changed", _on_changed):
		a.disconnect("changed", _on_changed)


func _on_changed() -> void:
	_dirty = true


func _process(_dt: float) -> void:
	if not is_visible_in_tree():
		return
	var vs := str([_view_ui().get("hover"), _view_ui().get("marching"), _app_get("soldier")])
	if _dirty or vs != _view_sig:
		refresh()


func _input(e: InputEvent) -> void:
	# The retreat confirmation is a dialog: keys do not reach the map behind it.
	if _confirm != null and e is InputEventKey and not e.is_action("toggle_fullscreen"):
		if e.pressed and e.is_action("cancel"):
			_close_confirm()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- store access

func _app() -> Object:
	return app if app != null else H.app(self)


func _app_get(k: String) -> Variant:
	var a := _app()
	return a.get(k) if a != null else null


func _call(method: String, args: Array = []) -> Variant:
	var a := _app()
	if a == null or not a.has_method(method):
		push_warning("CampaignHud: the store has no %s()" % method)
		return null
	return a.callv(method, args)


func _game() -> Variant:
	return _app_get("game")


func _view_ui() -> Dictionary:
	if view != null and is_instance_valid(view):
		var u: Variant = view.get("ui")
		if u is Dictionary:
			return u
	return {}


func _marching() -> bool:
	return bool(_view_ui().get("marching", false))


static func _E() -> Variant:
	return Deps.expedition()


# ---------------------------------------------------------------- actions (buttons and dialogs)

func do_dismiss() -> void:
	_call("dismiss")


func do_start_battle() -> void:
	_call("start_battle")


func do_go_home(outcome: String) -> void:
	_close_confirm()
	_call("go_home", [outcome])


func do_choose(i: int) -> void:
	var g: Variant = _game()
	if g == null or _E() == null:
		return
	_E().choose_event(g, i)
	Sfx.play("page")
	_call("commit")


func do_camp(kind: String) -> void:
	var g: Variant = _game()
	if g == null or _E() == null:
		return
	match kind:
		"watch":
			_E().camp_watch(g)
			Sfx.play("page")
		"repair":
			_E().camp_repair(g)
			Sfx.play("build")
		"rest":
			_E().camp_rest(g)
			Sfx.play("page")
	_call("commit")


func do_search(i: int) -> void:
	var g: Variant = _game()
	if g == null or _E() == null:
		return
	_E().search_spot(g, i)
	Sfx.play("page")
	_call("commit")


func do_bandage(id: String) -> void:
	var g: Variant = _game()
	if g == null or _E() == null:
		return
	if _E().use_bandage(g, id):
		Sfx.play("page")
		_call("commit")


func do_find_army() -> void:
	if view != null and is_instance_valid(view) and view.has_method("focus_current"):
		view.focus_current()


func do_open_retreat() -> void:
	if _confirm != null:
		return
	var d := _dialog_panel(520)
	var press_on := UI.button("Press on", "Button", _close_confirm)
	press_on.name = "PressOn"
	var go := UI.button("Retreat", "RedButton", func(): do_go_home("retreat"))
	go.name = "Retreat"
	d.add_child(H.stack([
		[H.title("Sound the retreat?"), 0, 10],
		[H.para("The company turns for Amberfeld with the spoils gathered so far. The objective will not be met and the campaign's reward is forfeit."), 8, 8],
		[H.center_row([press_on, go]), 0, 0],
	]))
	_confirm = Modal.make(d)
	_confirm.name = "Confirm"
	_confirm.set_meta("on_cancel", _close_confirm)
	add_child(_confirm)


func _close_confirm() -> void:
	if _confirm != null and is_instance_valid(_confirm):
		_drop(_confirm)
	_confirm = null


# ---------------------------------------------------------------- build

func refresh() -> void:
	_dirty = false
	_sync_view()
	_view_sig = str([_view_ui().get("hover"), _view_ui().get("marching"), _app_get("soldier")])
	var g: Variant = _game()
	var ex: Variant = g.get("expedition") if g is Dictionary else null
	if not (ex is Dictionary) or _E() == null:
		# No expedition (any more): drop the sections; they are rebuilt with the next one.
		for c in [_top, _army, _card, _prompt, _log, _buttons, _modal, _soldier, _confirm]:
			_drop(c)
		_top = null
		_army = null
		_card = null
		_prompt = null
		_log = null
		_buttons = null
		_modal = null
		_dialog = null
		_soldier = null
		_soldier_key = ""
		_confirm = null
		_sigs.clear()
		return
	_section("top", [ex.marches, ex.current, ex.supplies, ex.loot, _E().ration_cost(g), ex.campaignId], _build_top.bind(g, ex))
	_section("army", _army_sig(g, ex), _build_army.bind(g, ex))
	var hover_id: Variant = _view_ui().get("hover")
	var pending: Variant = ex.get("pending")
	var marching := _marching()
	var show_card := hover_id != null and pending == null
	_section("card", [hover_id, pending == null, _node_sig(ex, hover_id), ex.current], _build_card.bind(ex, hover_id) if show_card else _clear_card)
	_section("prompt", [pending == null and not marching and hover_id == null, _E().ration_cost(g)], _build_prompt.bind(g, pending == null and not marching and hover_id == null))
	_section("log", ex.log.slice(0, 12), _build_log.bind(ex))
	_section("buttons", [pending != null or marching], _build_buttons.bind(pending != null or marching))
	_section("dialog", [pending, marching], _build_dialog.bind(g, ex, pending if not marching else null))
	_section("soldier", [_app_get("soldier"), _army_sig(g, ex)], _build_soldier)
	# Overlays stay above the panels.
	for c in [_modal, _confirm, _soldier]:
		if c != null and is_instance_valid(c) and c.get_parent() == self:
			move_child(c, -1)


## Rebuilds a part of the HUD when what it shows changed.
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


func _node(ex: Dictionary, id: Variant) -> Variant:
	for n in ex.nodes:
		if n.id == id:
			return n
	return null


func _node_sig(ex: Dictionary, id: Variant) -> String:
	var n: Variant = _node(ex, id)
	return str(n) if n != null else ""


# ---------------------------------------------------------------- top bar

func _build_top(g: Dictionary, ex: Dictionary) -> void:
	var c: Dictionary = DB.campaign_by_id(ex.campaignId)
	var bar := UI.panel("TopBar")
	UI.dark(bar)
	bar.name = "TopBar"
	bar.custom_minimum_size.y = 54
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 54
	var row := UI.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	var brand := UI.label(str(c.get("name", "")).to_upper(), "BrandLabel")
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(brand)
	var cur: Variant = _node(ex, ex.current)
	var where := UI.label("March %d · %s" % [int(ex.marches), cur.name if cur != null else ""], "", 13, TOP_MUTED)
	where.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(where)
	row.add_child(UI.spacer())
	for k in DB.SUPPLY_ORDER:
		var sup: Dictionary = DB.SUPPLIES[k]
		var n := int(ex.supplies.get(k, 0))
		var item := UI.hbox(6)
		item.name = "Supply_" + k
		item.add_child(Icon.make(k, 22))
		var num := UI.label(str(n), "ResLabel", 0, ZERO if n == 0 else H.NONE)
		num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(num)
		var tip := "[b]%s[/b]\n%s" % [UI.esc(sup.name), UI.esc(sup.description)]
		if k == "rations":
			tip += "\n[font_size=4] [/font_size]\nEach march costs %d." % _E().ration_cost(g)
		Tip.attach(item, tip, true)
		row.add_child(item)
	row.add_child(UI.spacer())
	var help := UI.button("?", "SmallButton", func(): _call("open_manual", ["campaign"]))
	help.name = "Help"
	help.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(help)
	var sp := UI.label("Spoils", "", 13, TOP_MUTED)
	sp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sp)
	var loot := ResList.make(ex.loot, 18)
	if loot is Label:
		(loot as Label).add_theme_color_override("font_color", UI.INK_FAINT)
	loot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(loot)
	bar.add_child(row)
	_top = _swap(_top, bar)


# ---------------------------------------------------------------- army

func _army_sig(g: Dictionary, ex: Dictionary) -> Array:
	var out: Array = [ex.supplies.get("bandages", 0), ex.get("pending") == null, ex.army]
	for so in _E().army_soldiers(g):
		out.append([so.id, so.name, so.hp, so.men, so.morale, so.fatigue, so.injuries, so.get("ammo"), so.level, so.portrait])
	var lim: Dictionary = Deps.game().army_limits(g, DB.campaign_by_id(ex.campaignId)) if Deps.game() != null else {}
	out.append(lim)
	return out


func _build_army(g: Dictionary, ex: Dictionary) -> void:
	var E = _E()
	var Game = Deps.game()
	var Soldier = Deps.soldier()
	var army: Array = E.army_soldiers(g)
	var c: Dictionary = DB.campaign_by_id(ex.campaignId)
	var lim: Dictionary = Game.army_limits(g, c)
	var p := UI.panel("DarkPanel", [12, 12])
	p.name = "Army"
	p.custom_minimum_size.x = 290
	H.place(p, 0, 0, 12, 66)
	var col := UI.vbox(0)
	var head := UI.hbox(8)
	head.add_child(UI.cinzel("The Army", 16, 700))
	head.add_child(UI.spacer())
	var men := 0
	for so in army:
		men += int(so.men)
	var info := UI.label("%d soldiers · %d/%d slots · %d/%d CP" % [men, army.size(), int(lim.slots), int(Game.army_command(g, ex.army)), int(lim.command)], "TinyMutedLabel", 11)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(info)
	col.add_child(head)
	col.add_child(UI.gap(0, 6))
	var list := UI.vbox(6)
	var can_bandage: bool = int(ex.supplies.get("bandages", 0)) > 0 and ex.get("pending") == null
	for so in army:
		list.add_child(_army_row(so, can_bandage, E, Soldier))
	var vh := get_viewport_rect().size.y if is_inside_tree() else 1080.0
	col.add_child(ScrollBox.make(list, maxf(80.0, vh - 260.0 - 24.0 - 28.0)))
	p.add_child(col)
	_army = _swap(_army, p)


func _army_row(so: Dictionary, can_bandage: bool, E, Soldier) -> Control:
	var def: Dictionary = DB.UNIT_TYPES.get(so.typeId, {})
	var st: Dictionary = Soldier.soldier_stats(so)
	var cap: int = Soldier.squad_hp_cap(so)
	var hurt: bool = so.hp < cap
	var row := UI.hbox(7)
	row.name = "Soldier_" + str(so.id)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var id := str(so.id)
	row.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			row.accept_event()
			_call("open_soldier", [id]))
	var por := Portrait.make(so.typeId, int(so.get("portrait", 0)), 40)
	por.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(por)
	var body := UI.vbox(0)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var line := UI.hbox(4)
	var nm := UI.ellipsize(UI.cinzel(str(so.name), 13, 700))
	nm.tooltip_text = "%s's %s" % [so.name, str(def.get("plural", so.typeId)).to_lower()]
	nm.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_child(H.trim(nm, 0, -1))
	var fat := UI.label(Soldier.fatigue_label(so.fatigue), "TinyLabel", 0, Color("#ffb070") if so.fatigue >= 60 else UI.DARK_MUTED)
	line.add_child(H.trim(fat, -1, -1))
	body.add_child(line)
	body.add_child(SquadBar.roster(so, 7))
	body.add_child(UI.gap(0, 2))
	var mb := Bar.make(so.morale, st.morale, "morale", 5, "Morale %d/%d" % [int(so.morale), int(st.morale)])
	mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(mb)
	var tags := H.flow(4)
	tags.add_child(H.trim(MenPips.make(int(so.men), DB.squad_size(so.typeId)), -1, -1))
	for i in so.injuries:
		var t := Tag.make(str(DB.INJURIES.get(i, {}).get("name", i)), "", "", 9)
		for l in t.find_children("*", "Label", true, false):
			(l as Label).add_theme_color_override("font_color", Color("#ffb0a0"))
		tags.add_child(t)
	if def.get("shot") != null:
		tags.add_child(H.trim(UI.label("%d bolts" % int(so.get("ammo", 0)), "TinyMutedLabel"), -1, -1))
	body.add_child(H.margin(tags, 3, 0, 0, 0))
	row.add_child(body)
	if hurt and can_bandage:
		var b := Button.new()
		b.name = "Bandage"
		b.theme_type_variation = "IconButton"
		b.icon = Icon.tex("bandages")
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 16)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.add_theme_color_override("icon_normal_color", Color.WHITE)
		b.add_theme_color_override("icon_hover_color", Color(1.15, 1.15, 1.15))
		b.add_theme_color_override("icon_pressed_color", Color(1.15, 1.15, 1.15))
		b.pressed.connect(func(): do_bandage(id))
		var heal: int = mini(E.bandage_heal(so), cap - int(so.hp))
		Tip.attach(b, "Use a bandage on %s: +10 HP per soldier (up to +%d HP). Bandages heal the living; they cannot bring back the dead." % [UI.esc(Squad.squad_name(so)), heal], true)
		row.add_child(b)
	return row


# ---------------------------------------------------------------- hovered node

func _clear_card() -> void:
	_card = _swap(_card, null)


func _build_card(ex: Dictionary, id: Variant) -> void:
	var n: Variant = _node(ex, id)
	if n == null:
		_clear_card()
		return
	var E = _E()
	var v: Dictionary = E.node_view(n)
	var reachable := false
	for q in E.next_nodes(ex):
		if q.id == n.id:
			reachable = true
	var p := UI.panel("ParchmentPanel", [14, 16])
	p.name = "NodeCard"
	p.custom_minimum_size.x = 300
	H.place(p, 1, 0, -16, 70, -1, 1)
	var col := UI.vbox(0)
	var t := UI.cinzel(str(v.title), 18, 700)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(t)
	var kind := "Unknown" if v.type == "unknown" else str(DB.NODE_INFO.get(v.type, {}).get("name", v.type))
	col.add_child(UI.label(kind + (" · visited" if n.get("visited") else ""), "SmallMutedLabel"))
	col.add_child(UI.gap(0, 8))
	col.add_child(H.flourish())
	col.add_child(UI.gap(0, 8))
	col.add_child(H.rich(UI.esc(str(v.detail)), 13))
	var roll: Variant = n.get("encounter")
	if roll != null and (n.get("scouted") or n.type == "objective"):
		col.add_child(UI.gap(0, 6))
		col.add_child(H.rich("[b]Ground:[/b] %s" % UI.esc(str(DB.BATTLE_MAPS.get(roll.mapId, {}).get("name", roll.mapId))), 13))
	if v.type == "event" and n.get("revealed") and n.type == "event" and n.get("eventId") != null and n.get("scouted"):
		var title := ""
		for e in DB.EVENTS:
			if e.id == n.eventId:
				title = str(e.title)
		col.add_child(UI.gap(0, 6))
		col.add_child(H.rich("Scouts report: %s" % UI.esc(title), 13))
	if reachable:
		col.add_child(UI.gap(0, 8))
		col.add_child(H.rich("Click to march here.", 13, Color("#6b4a10")))
	elif not n.get("visited"):
		col.add_child(UI.gap(0, 8))
		col.add_child(H.rich("Not reachable from here.", 13, UI.INK_FAINT))
	p.add_child(col)
	_card = _swap(_card, p)


# ---------------------------------------------------------------- march prompt

func _build_prompt(g: Dictionary, show: bool) -> void:
	if not show:
		_prompt = _swap(_prompt, null)
		return
	var p := UI.panel("DarkPanel", [8, 18])
	p.name = "MarchPrompt"
	H.place(p, 0.5, 0, 0, 66, 0, 1)
	var row := UI.hbox(0)
	var a := UI.cinzel("Choose the next march", 16, 400)
	a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(a)
	var b := UI.label(" · each march eats %d rations and tires the army" % _E().ration_cost(g), "SmallMutedLabel")
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(b)
	p.add_child(row)
	_prompt = _swap(_prompt, p)


# ---------------------------------------------------------------- log

func _build_log(ex: Dictionary) -> void:
	var p := UI.panel("DarkPanel", [10, 14])
	p.name = "Log"
	p.custom_minimum_size.x = 420
	H.place(p, 0, 1, 12, -14, 1, -1)
	var col := UI.vbox(0)
	var lines: Array = ex.log.slice(0, 12)
	for i in lines.size():
		var l: Dictionary = lines[i]
		var c: Color = LOG_COLOURS.get(l.get("tone"), LOG_DEFAULT)
		var lab := UI.label(str(l.text), "", 13, c)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.add_theme_constant_override("line_spacing", H.line_gap(13))
		lab.modulate.a = 1.0 - i * 0.06
		col.add_child(H.trim(lab, -1, -1))
	p.add_child(ScrollBox.make(col, 150.0 - 20.0))
	_log = _swap(_log, p)


# ---------------------------------------------------------------- buttons

func _build_buttons(blocked: bool) -> void:
	var row := UI.hbox(10)
	row.name = "Buttons"
	H.place(row, 1, 1, -16, -16, -1, -1)
	var find := UI.button("Find army", "Button", do_find_army)
	find.name = "FindArmy"
	row.add_child(find)
	_retreat = UI.button("Retreat home", "RedButton", do_open_retreat)
	_retreat.name = "RetreatHome"
	_retreat.disabled = blocked
	_retreat.mouse_default_cursor_shape = Control.CURSOR_ARROW if blocked else Control.CURSOR_POINTING_HAND
	row.add_child(_retreat)
	_buttons = _swap(_buttons, row)


# ---------------------------------------------------------------- pending dialog

func _dialog_panel(width: int) -> PanelContainer:
	var d := Modal.dialog(width, [24, 28])
	d.name = "Dialog"
	return d


func _build_dialog(g: Dictionary, ex: Dictionary, p: Variant) -> void:
	var built: Dictionary = Dialogs.build(self, g, ex, p) if p is Dictionary else {}
	if built.is_empty():
		if _modal != null and is_instance_valid(_modal):
			_drop(_modal)
		_modal = null
		_dialog = null
		return
	if _modal == null or not is_instance_valid(_modal):
		# The dialog fades in and rises when it appears; later changes of the
		# pending event only replace its content (React keeps the same element).
		_dialog = _dialog_panel(built.width)
		_dialog.add_child(built.content)
		_modal = Modal.make(_dialog)
		_modal.name = "PendingDialog"
		add_child(_modal)
		return
	_dialog.custom_minimum_size.x = built.width
	UI.clear(_dialog)
	_dialog.add_child(built.content)
	_dialog.reset_size()


## The open dialog's kind ("" when none): for tests and automation.
func dialog_kind() -> String:
	var g: Variant = _game()
	if _modal == null or not is_instance_valid(_modal) or not (g is Dictionary) or g.get("expedition") == null:
		return ""
	var p: Variant = g.expedition.get("pending")
	return str(p.kind) if p is Dictionary else ""


# ---------------------------------------------------------------- soldier detail

const SOLDIER_DETAIL := "res://scripts/ui/screens/soldier_detail.gd"


## The SoldierDetail overlay of src/ui/screens/Roster.tsx (built by the UI
## shell's soldier_detail.gd) while `App.soldier` is set.
func _build_soldier() -> void:
	var id: Variant = _app_get("soldier")
	var key := str(id) if id != null else ""
	if key == "":
		if _soldier != null and is_instance_valid(_soldier):
			_drop(_soldier)
		_soldier = null
		_soldier_key = ""
		return
	if key != _soldier_key or _soldier == null or not is_instance_valid(_soldier):
		if _soldier != null and is_instance_valid(_soldier):
			_drop(_soldier)
		_soldier = null
		var s: Variant = Deps.mod(SOLDIER_DETAIL)
		if s is GDScript:
			var c: Variant = (s as GDScript).call("make", key)
			if c is Control:
				_soldier = c
				add_child(c)
		_soldier_key = key
	elif _soldier.has_method("refresh"):
		_soldier.refresh()


## Esc on the soldier detail (main.gd): saves a changed name like Close.
func close_soldier() -> void:
	if _soldier != null and is_instance_valid(_soldier) and _soldier.has_method("close"):
		_soldier.close()
	else:
		_call("open_soldier", [null])
