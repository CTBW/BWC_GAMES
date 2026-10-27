## The unit bar (Godot only): Warcraft III's console in the bottom centre of
## the battle screen, showing the selected squad. From the left: the minimap; the
## squad's man in his frame, live (head_portrait.gd: his own 3D figure in his
## idle, flinching when the squad is struck; the type's baked portrait where
## there is no figure, as in the 2D battle), its health and morale under him;
## its name on a banner with its level, its rank and type, whether it can still
## move and act; six stat plaques and its status row; the squad's
## men, each with his own headshot and health (a click shows him in the
## portrait); its gear; the 4×3 command card (its abilities on keys 1–4, Redo,
## Next, Done). Every tooltip says what a thing does and where its numbers come
## from (bar_tips.gd).
##
## A view: it shows what bar_data.gd reads of the battle and the company; its
## commands call the battle view's own methods (as the old squad card's
## buttons, hud_battle_panels.gd), and the view's keys stay the view's. It
## rises when a squad is selected and sinks when the selection is dropped (a
## right click, the view's). The HUD can show a foe in it instead (a right click
## on one, battle_hud.gd `inspect`): its bar is tinted, its portrait framed
## grim, its abilities shown but never usable, and its card's Back goes back.
## The console takes the clicks over it, so none reach the field.
##
##   var bar = preload("res://scripts/ui/unit_bar/unit_info_bar.gd").new()
##   hud.add_child(bar)                 # full rect; the console at its bottom centre
##   bar.view = battle_view             # the minimap's
##   bar.show_squad(BarData.squad(view, u, store))
##   bar.hide_bar()
##   bar.shown() -> bool                # risen or rising
## HEIGHT: how much of the screen's bottom the console covers; its width is
## console.natural_width() (its windows and the stone round them).
extends Control

const Style = preload("res://scripts/ui/unit_bar/bar_style.gd")
const Console = preload("res://scripts/ui/unit_bar/console_frame.gd")
const PortraitFrame = preload("res://scripts/ui/unit_bar/portrait_frame.gd")
const ValueBar = preload("res://scripts/ui/unit_bar/value_bar.gd")
const StatPlaque = preload("res://scripts/ui/unit_bar/stat_plaque.gd")
const StatusIcon = preload("res://scripts/ui/unit_bar/status_icon.gd")
const MemberSlot = preload("res://scripts/ui/unit_bar/member_slot.gd")
const ItemSlot = preload("res://scripts/ui/unit_bar/item_slot.gd")
const CommandButton = preload("res://scripts/ui/unit_bar/command_button.gd")
const Minimap = preload("res://scripts/ui/unit_bar/bar_minimap.gd")
const Tip = preload("res://scripts/ui/widgets/tip.gd")

const HEIGHT := Console.HEIGHT
## The portrait's opening, and how far its frame stands above its window (its
## crest up to the rail).
const OPENING := Vector2(152, 116)
const FRAME_UP := 9.0
## The middle: the plaques (three across), the men (MEN_W), a margin each side.
const WINDOWS := {"minimap": 206.0, "portrait": 186.0, "middle": 638.0, "inventory": 132.0, "command": 264.0}
const PLAQUES := 6
const CARD_GAP := 6.0
const RISE_TIME := 0.32
## The middle window's pieces: the banner's height, the plaques' rows, the men.
const BANNER_H := 30.0
const PLAQUE_GAP := Vector2(8, 4)
const MAN_FACE := 42.0
const MEN_COLUMNS := 4
## The men's room: four across at MAN_FACE (a bigger squad's faces shrink to fit).
const MEN_W := 218.0

signal command_used(id: String)

var view: Object = null:
	set(v):
		view = v
		if _minimap != null:
			_minimap.view = v
## What is shown (bar_data.gd's squad), {} when nothing.
var data: Dictionary = {}

var console: Control
var frame: Control
var portrait: Control
var hp: Control
var morale: Control
var _minimap: Control
var _banner: Control
var _name: Label
var _type: Label
var _level: Label
var _turn: HBoxContainer
var _plaques: Array = []
var _status: HBoxContainer
var _men_label: Label
var _men: GridContainer
var _items: Array = []
var _commands: Array = []
var _focus := 0
var _risen := false
var _tween: Tween
## How far the console stands up from the screen's bottom edge: 0 sunk below
## it, 1 risen (its offsets from the bottom anchor, so a resize keeps it there).
var _lift := 0.0:
	set(v):
		_lift = v
		if console != null:
			console.offset_top = -HEIGHT * v
			console.offset_bottom = HEIGHT * (1.0 - v)


func _init() -> void:
	name = "UnitBar"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	console = Console.new()
	console.name = "Console"
	console.windows = WINDOWS.duplicate()
	console.open_stone = []
	console.unframed = ["portrait"]
	# Centred on the screen's bottom edge, as wide as its windows.
	console.anchor_left = 0.5
	console.anchor_right = 0.5
	console.anchor_top = 1.0
	console.anchor_bottom = 1.0
	console.offset_left = -console.natural_width() * 0.5
	console.offset_right = console.natural_width() * 0.5
	_lift = 0.0
	# The console takes every click over it: none reach the field behind.
	console.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(console)
	visible = false
	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	_minimap.view = view
	console.add_child(_minimap)
	frame = PortraitFrame.new()
	frame.name = "PortraitFrame"
	console.add_child(frame)
	frame.set_opening(OPENING)
	portrait = frame.portrait
	hp = _readout("hp", 18, 8.0)
	hp.name = "Health"
	morale = _readout("morale", 14, 6.0)
	morale.name = "Morale"
	Tip.attach(hp, "", true)
	Tip.attach(morale, "", true)
	_build_middle()
	for i in 6:
		var s = ItemSlot.new()
		s.name = "Item%d" % i
		console.add_child(s)
		_items.append(s)
	for i in 12:
		var c = CommandButton.new()
		c.name = "Slot%d" % i
		c.used.connect(_on_command.bind(c))
		console.add_child(c)
		_commands.append(c)
	console.laid_out.connect(_layout)
	_layout()


func _readout(kind: String, number_size: int, bar_height: float) -> Control:
	var b = ValueBar.new()
	b.kind = kind
	b.number_size = number_size
	b.bar_height = bar_height
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	console.add_child(b)
	return b


func _build_middle() -> void:
	_banner = Control.new()
	_banner.name = "NameBanner"
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.draw.connect(_draw_banner)
	console.add_child(_banner)
	_name = Style.text("", 19, Style.TEXT, "cinzel", 700)
	Style.outline(_name, 5)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_banner.add_child(_name)
	_level = Style.number("", 17, Style.TEXT)
	_level.name = "Level"
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_child(_level)
	_type = Style.text("", 14, Style.MUTED, "alegreya", 700)
	_type.name = "Type"
	Style.outline(_type, 4)
	console.add_child(_type)
	_turn = HBoxContainer.new()
	_turn.name = "Turn"
	_turn.add_theme_constant_override("separation", 6)
	_turn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	console.add_child(_turn)
	for i in PLAQUES:
		var p = StatPlaque.new()
		p.name = "Stat%d" % i
		console.add_child(p)
		_plaques.append(p)
	_status = HBoxContainer.new()
	_status.name = "Status"
	_status.add_theme_constant_override("separation", 6)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	console.add_child(_status)
	_men_label = Style.text("", 13, Style.MUTED, "cinzel", 700)
	_men_label.name = "MenLabel"
	Style.outline(_men_label, 4)
	console.add_child(_men_label)
	_men = GridContainer.new()
	_men.name = "Men"
	_men.columns = MEN_COLUMNS
	_men.add_theme_constant_override("h_separation", 6)
	_men.add_theme_constant_override("v_separation", 4)
	_men.mouse_filter = Control.MOUSE_FILTER_IGNORE
	console.add_child(_men)


## Places the pieces in their windows (console coordinates).
func _layout() -> void:
	if _minimap == null:
		return
	var mm: Rect2 = console.window_rect("minimap")
	_minimap.position = mm.position
	_minimap.size = mm.size
	var pw: Rect2 = console.window_rect("portrait")
	frame.position = Vector2(pw.position.x + (pw.size.x - frame.size.x) * 0.5, pw.position.y - FRAME_UP)
	var below := frame.position.y + frame.size.y + 3.0
	hp.position = Vector2(pw.position.x + 4.0, below)
	hp.size = Vector2(pw.size.x - 8.0, 22.0)
	morale.position = Vector2(pw.position.x + 4.0, below + 23.0)
	morale.size = Vector2(pw.size.x - 8.0, 16.0)
	# The middle: banner across the top, then the type line; plaques and status
	# at the left, the men at the right under their turn tags.
	var md: Rect2 = console.window_rect("middle")
	var left := md.position.x + 12.0
	var plaque_w := StatPlaque.SIZE.x * 3.0 + PLAQUE_GAP.x * 2.0
	_banner.position = Vector2(left, md.position.y + 4.0)
	_banner.size = Vector2(plaque_w, BANNER_H)
	_name.position = Vector2(14, 0)
	_name.size = Vector2(_banner.size.x - 28.0 - 46.0, BANNER_H)
	_level.position = Vector2(_banner.size.x - 46.0, -4)
	_level.size = Vector2(42, BANNER_H + 8)
	_type.position = Vector2(left + 4.0, md.position.y + BANNER_H + 5.0)
	var top := md.position.y + BANNER_H + 28.0
	var step := StatPlaque.SIZE + PLAQUE_GAP
	for i in _plaques.size():
		_plaques[i].position = Vector2(left + (i % 3) * step.x, top + (i / 3) * step.y)
	_status.position = Vector2(left, top + 2.0 * step.y + 1.0)
	_place_men()
	var inv: Rect2 = console.window_rect("inventory")
	var isz: Vector2 = ItemSlot.SIZE
	var ix := inv.position.x + (inv.size.x - (isz.x * 2.0 + 6.0)) * 0.5
	var iy := inv.position.y + (inv.size.y - (isz.y * 3.0 + 12.0)) * 0.5
	for i in _items.size():
		_items[i].position = Vector2(ix + (i % 2) * (isz.x + 6.0), iy + (i / 2) * (isz.y + 6.0))
	var cmd: Rect2 = console.window_rect("command")
	var cs := CommandButton.SIZE
	var cx := cmd.position.x + (cmd.size.x - (cs * 4.0 + CARD_GAP * 3.0)) * 0.5
	var cy := cmd.position.y + (cmd.size.y - (cs * 3.0 + CARD_GAP * 2.0)) * 0.5
	for i in _commands.size():
		_commands[i].position = Vector2(cx + (i % 4) * (cs + CARD_GAP), cy + (i / 4) * (cs + CARD_GAP))
	_banner.queue_redraw()


## The men under their turn tags, centred in their room at the middle's right.
func _place_men() -> void:
	var md: Rect2 = console.window_rect("middle")
	var face: float = _men.get_child(0).face if _men.get_child_count() > 0 else MAN_FACE
	var grid_w := _men.columns * (face + 8.0) + (_men.columns - 1) * 6.0
	var x := md.end.x - 12.0 - MEN_W + maxf(0.0, (MEN_W - grid_w) * 0.5)
	_turn.position = Vector2(x, md.position.y + 6.0)
	_men_label.position = Vector2(x, md.position.y + 34.0)
	_men.position = Vector2(x, md.position.y + 54.0)


# ---------------------------------------------------------------- showing

func shown() -> bool:
	return _risen


## Shows a squad: rises if the bar was down, swaps to it if another was shown,
## updates in place if it is the same (its health ghosts down, its man flinches).
func show_squad(d: Dictionary) -> void:
	var was: Dictionary = data
	data = d
	var swap: bool = was.get("uid") != d.get("uid")
	if swap:
		_focus = 0
	_fill(d, swap)
	if not _risen:
		_rise()
	elif swap:
		frame.sheen()
		Style.sound(self, "swap", {"volume_db": -6.0})
		for p in _plaques:
			p.tick()


func hide_bar() -> void:
	if not _risen:
		return
	_risen = false
	data = {}
	if _tween != null:
		_tween.kill()
	if not is_inside_tree():
		_lift = 0.0
		visible = false
		return
	Style.sound(self, "close", {"volume_db": -8.0})
	_tween = create_tween()
	_tween.tween_property(self, "_lift", 0.0, RISE_TIME * 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func():
		visible = false
		portrait.live = false)


func _rise() -> void:
	_risen = true
	visible = true
	portrait.live = true
	if _tween != null:
		_tween.kill()
	if not is_inside_tree():
		_lift = 1.0
	else:
		_lift = 0.0
		_tween = create_tween()
		_tween.tween_property(self, "_lift", 1.0, RISE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	frame.sheen()
	hp.count_up()
	morale.count_up()
	for p in _plaques:
		p.tick()
	Style.sound(self, "open", {"volume_db": -6.0})


func _fill(d: Dictionary, swap: bool) -> void:
	var foe: bool = d.get("faction") != "player"
	console.accent = Color(1.0, 0.55, 0.5) if foe else Color.WHITE
	console.tint = Color(0.86, 0.8, 0.8) if foe else Color.WHITE
	frame.faction = String(d.get("faction", "player"))
	# The portrait: the focused man (the first standing unless one was clicked).
	var men: Array = d.get("men", [])
	if _focus >= men.size() or not men[_focus].alive:
		_focus = 0
	var fig: Variant = men[_focus].get("figure") if _focus < men.size() else d.get("figure")
	var struck: bool = not swap and float(d.get("hp", 0)) < hp.value - 0.01
	portrait.show_figure(fig, String(d.get("type_id", "")), int(d.get("variant", 0)))
	if struck:
		portrait.flinch()
	hp.set_value(float(d.get("hp", 0)), float(d.get("hp_max", 1)), not swap)
	morale.set_value(float(d.get("morale", 0)), float(d.get("morale_max", 1)), not swap)
	Tip.set_content(morale, "[b]Morale: %s[/b]\n%d of %d. A squad that loses heart wavers, then breaks and runs." % [d.get("morale_label", ""), int(d.get("morale", 0)), int(d.get("morale_max", 0))])
	Tip.set_content(hp, "[b]Health[/b]\n%d of %d HP: %d HP a man, the squad's men standing as long as their share holds." % [int(d.get("hp", 0)), int(d.get("hp_max", 0)), int(float(d.get("hp_max", 0)) / maxf(1.0, float(d.get("size", 1))))])
	_name.text = String(d.get("name", ""))
	_level.text = str(int(d.get("level", 0))) if int(d.get("level", 0)) > 0 else ""
	_type.text = "%s · %s" % [d.get("type_label", ""), d.get("morale_label", "")]
	_banner.queue_redraw()
	_fill_turn(d)
	var stats: Array = d.get("stats", [])
	for i in _plaques.size():
		_plaques[i].visible = i < stats.size()
		if i < stats.size():
			_plaques[i].set_stat(stats[i])
	_fill_status(d.get("effects", []))
	_fill_men(d, men)
	var items: Array = d.get("items", [])
	for i in _items.size():
		_items[i].set_item(items[i] if i < items.size() else {})
	var cmds: Array = d.get("commands", [])
	# Each button is named after its command: the old names go first, so a command
	# that moves to another place keeps its name (no "Ability_x2").
	for i in _commands.size():
		_commands[i].name = "Slot%d" % i
	for i in _commands.size():
		_commands[i].set_command(cmds[i] if i < cmds.size() else {})


func _fill_turn(d: Dictionary) -> void:
	for c in _turn.get_children():
		_turn.remove_child(c)
		c.queue_free()
	var t: Dictionary = d.get("turn", {})
	if not t.get("mine", false):
		return
	_turn.add_child(Style.chip("Moved" if t.moved else "Can move", null if t.moved else Style.MORALE))
	_turn.add_child(Style.chip("Acted" if t.acted else "Can act", null if t.acted else Style.HP_LOW))


## The status row: icons kept by id, new ones popping in, ended ones fading out.
func _fill_status(list: Array) -> void:
	var have := {}
	for c in _status.get_children():
		if c.has_method("is_expiring") and not c.is_expiring():
			have[String(c.effect.get("id", ""))] = c
	var want := {}
	var n := 0
	for e in list:
		want[e.id] = true
		if have.has(e.id):
			have[e.id].set_effect(e)
		else:
			var s = StatusIcon.new()
			s.name = "Status_" + String(e.id)
			s.set_effect(e)
			_status.add_child(s)
			s.pop_in(0.05 * n)
		n += 1
	for id in have:
		if not want.has(id):
			have[id].expire()


func _fill_men(d: Dictionary, men: Array) -> void:
	var foe: bool = d.get("faction") != "player"
	_men_label.text = "%s %d / %d" % [d.get("members", "Soldiers"), int(d.get("alive", 0)), int(d.get("size", 0))]
	# Two rows: six men three by three, eight four by four; more, smaller to fit.
	_men.columns = maxi(3, ceili(men.size() / 2.0)) if men.size() > 3 else maxi(1, men.size())
	var face := minf(MAN_FACE, floorf((MEN_W + 6.0) / _men.columns - 6.0 - 8.0))
	var slots := _men.get_children()
	for i in maxi(slots.size(), men.size()):
		if i >= men.size():
			slots[i].visible = false
			continue
		var s: Control
		if i < slots.size():
			s = slots[i]
		else:
			s = MemberSlot.new()
			s.name = "Man%d" % i
			s.picked.connect(_on_man.bind(i))
			_men.add_child(s)
		s.visible = true
		s.face = face
		s.faction = "enemy" if foe else "player"
		s.set_man(men[i], i == _focus)
	_place_men()


func _on_man(i: int) -> void:
	var men: Array = data.get("men", [])
	if i >= men.size() or not men[i].alive or bool(men[i].get("hidden", false)):
		Style.sound(self, "deny")
		return
	_focus = i
	Style.sound(self, "swap", {"volume_db": -8.0})
	portrait.show_figure(men[i].get("figure"), String(data.get("type_id", "")), int(data.get("variant", 0)))
	frame.sheen()
	_fill_men(data, men)


func _on_command(id: String, b: Control) -> void:
	var c: Dictionary = b.command
	var f: Variant = c.get("call")
	if b.usable() and f is Callable and (f as Callable).is_valid():
		(f as Callable).call()
	command_used.emit(id)


# ---------------------------------------------------------------- drawing

## The name's banner (a ribbon in the side's colour, brass-edged) and the level
## in its brass medallion at the banner's right end.
func _draw_banner() -> void:
	var c := _banner
	var r := Rect2(Vector2.ZERO, c.size)
	var foe: bool = data.get("faction", "player") != "player"
	var col: Color = Color("#6e1a14") if foe else Color("#1d3577")
	c.draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.35))
	Style.ribbon(c, r, col, 12.0)
	if _level != null and _level.text != "":
		var m := Vector2(r.size.x - 25.0, r.size.y * 0.5)
		c.draw_circle(m + Vector2(1.5, 2.5), 19.0, Color(0, 0, 0, 0.35))
		c.draw_circle(m, 19.0, Style.INK)
		c.draw_circle(m, 17.0, Style.BRASS_DARK)
		c.draw_circle(m, 15.0, Style.BRASS)
		c.draw_circle(m + Vector2(-2, -2), 12.5, Style.BRASS.lightened(0.15))
		c.draw_circle(m, 11.5, col.darkened(0.25))
		c.draw_arc(m, 11.5, PI * 1.1, PI * 1.9, 12, Color(1, 1, 1, 0.25), 1.5, true)
