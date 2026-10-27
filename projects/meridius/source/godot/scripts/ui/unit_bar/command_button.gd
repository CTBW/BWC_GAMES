## A button of the bar's command card (Warcraft III's 4×3 card): its icon in a
## gold-framed socket, its hotkey in the top-left corner, its cost at the
## bottom right, the cooldown's radial sweep with the time left. Unusable:
## greyed. Armed (waiting for the player to pick a tile or a foe): a pulsing
## gold frame until it is used or cancelled. Hover glows and ticks, a press sinks
## it. A BaseButton (the HUD's and the automation's buttons): `pressed` plays the
## press and says `used`; it is `disabled` while it cannot be used. Its name is
## the command's id ("Ability_shieldwall", "Done"), its label meta "1 Shield
## Wall". Empty slots are dark sockets. Commands without an icon draw their
## `mark` (check, next, undo).
##
##   var b = preload("res://scripts/ui/unit_bar/command_button.gd").new()
##   b.set_command({id, name, icon | mark, key, hotkey, enabled, active, cooldown: 0..1,
##       cooldown_text, cost, desc, lines, reason, aim, every})     {} for an empty socket
extends BaseButton

signal used(id: String)

const Style = preload("res://scripts/ui/unit_bar/bar_style.gd")
const Icon = preload("res://scripts/ui/widgets/icon.gd")
const Tip = preload("res://scripts/ui/widgets/tip.gd")
const BarTips = preload("res://scripts/ui/unit_bar/bar_tips.gd")

const SIZE := 56.0

var command: Dictionary = {}
var _icon: TextureRect
var _key: Label
var _cost: Label
var _cd: Label
var _hovered := false
var _pulse := 0.0
var _press_flash := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	pivot_offset = Vector2(SIZE, SIZE) * 0.5
	pressed.connect(trigger)
	button_down.connect(_place)
	button_up.connect(_place)
	_build()


## Its pieces, made with it (it works before it is in the tree, as in the headless tests).
func _build() -> void:
	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.material = Style.icon_material()
	add_child(_icon)
	_cd = Style.number("", 20, Style.TEXT)
	_cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_cd)
	_key = Style.number("", 12, Style.BRASS_LIGHT)
	_key.position = Vector2(6, 2)
	add_child(_key)
	_cost = Style.number("", 12, Style.MORALE)
	_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cost.position = Vector2(SIZE - 34, SIZE - 20)
	_cost.size = Vector2(28, 16)
	add_child(_cost)
	Tip.attach(self, func(): return BarTips.command(command), true)
	mouse_entered.connect(func():
		_hovered = true
		if not command.is_empty():
			Style.sound(self, "ability_hover", {"volume_db": -8.0})
		queue_redraw())
	mouse_exited.connect(func():
		_hovered = false
		_place()
		queue_redraw())
	_place()
	set_command(command)


func set_command(c: Dictionary) -> void:
	command = c if c != null else {}
	if _icon == null:
		return
	var empty := command.is_empty()
	if not empty:
		name = String(command.id)
		set_meta("label", ("%s %s" % [command.key, command.name]) if String(command.get("key", "")) != "" else String(command.get("name", "")))
	_icon.texture = Icon.painted(String(command.icon)) if command.has("icon") else null
	_key.text = String(command.get("key", ""))
	var cost: Variant = command.get("cost")
	_cost.text = str(cost) if cost != null and str(cost) != "" else ""
	var cd := float(command.get("cooldown", 0.0))
	_cd.text = String(command.get("cooldown_text", "")) if cd > 0.0 else ""
	var mat := _icon.material as ShaderMaterial
	mat.set_shader_parameter("gray", 0.0 if usable() else 0.9)
	mat.set_shader_parameter("bright", 1.0 if usable() else 0.7)
	# Unusable commands stay hoverable (their tip says why) but cannot be pressed.
	disabled = not usable()
	mouse_filter = Control.MOUSE_FILTER_IGNORE if empty else Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if usable() else Control.CURSOR_ARROW
	queue_redraw()


func usable() -> bool:
	return not command.is_empty() and bool(command.get("enabled", false)) and float(command.get("cooldown", 0.0)) <= 0.0


## Plays the press and says `used` (a click, a hotkey through the bar, or
## `pressed` emitted by the automation).
func trigger() -> void:
	if command.is_empty():
		return
	_press_flash = 1.0
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(0.9, 0.9), 0.05)
	t.tween_property(self, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if usable():
		Style.sound(self, "command")
	else:
		Style.sound(self, "deny")
	used.emit(String(command.id))


func _place() -> void:
	if _icon == null:
		return
	var down := 2.0 if is_pressed_down() else 0.0
	_icon.position = Vector2(7, 7 + down)
	_icon.size = Vector2(SIZE - 14, SIZE - 14)


## Held down under the pointer (BaseButton's pressed draw state).
func is_pressed_down() -> bool:
	return get_draw_mode() == DRAW_PRESSED or get_draw_mode() == DRAW_HOVER_PRESSED


func _gui_input(e: InputEvent) -> void:
	# A click on an unusable command is refused with a sound, as Warcraft's are.
	if disabled and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not command.is_empty():
		Style.sound(self, "deny")
		accept_event()


func _process(dt: float) -> void:
	var busy := false
	if bool(command.get("active", false)):
		_pulse += dt * 5.0
		busy = true
	if _press_flash > 0.0:
		_press_flash = maxf(0.0, _press_flash - dt * 4.0)
		(_icon.material as ShaderMaterial).set_shader_parameter("flash", _press_flash * 0.5)
		busy = true
	if busy:
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if command.is_empty():
		# A dark empty socket.
		draw_rect(r.grow(1), Style.INK)
		Style.bevel(self, r, 3.0, Color("#3a3226"), Color("#0b0907"), Color("#241e17"))
		draw_rect(r.grow(-3), Color("#0d1014"))
		draw_rect(Rect2(r.position + Vector2(3, 3), Vector2(r.size.x - 6, 6)), Color(0, 0, 0, 0.4))
		return
	var active := bool(command.get("active", false))
	var lit := 1.0 if active else (0.6 if _hovered and usable() else 0.0)
	var tint := Style.BRASS if usable() or active else Color("#7d7462")
	if active:
		var p := 0.5 + 0.5 * sin(_pulse)
		draw_rect(r.grow(6), Color(Style.BRASS_LIGHT, 0.15 + 0.25 * p))
		draw_rect(r.grow(3), Color(Style.BRASS_LIGHT, 0.45 + 0.35 * p))
	Style.socket(self, r.grow(-1.0 if is_pressed_down() else 0.0), lit, 4.0, Color("#191d23"), tint)
	if not command.has("icon") and command.has("mark"):
		_mark(r.grow(-15).grow_individual(0, -1 if is_pressed_down() else 0, 0, 1 if is_pressed_down() else 0), String(command.mark), Style.BRASS_LIGHT if usable() else Color("#7d7462"))
	if _hovered and usable():
		draw_rect(r.grow(-5), Color(1, 0.95, 0.75, 0.10))
	var cd := float(command.get("cooldown", 0.0))
	if cd > 0.0:
		var c := r.get_center()
		var ir := r.grow(-5)
		draw_set_transform(Vector2.ZERO)
		Style.pie(self, c, size.x * 0.72, cd, Color(0, 0, 0, 0.62))
		# Keep the sweep inside the socket: cover what spilled past its rim.
		draw_rect(Rect2(r.position, Vector2(r.size.x, ir.position.y - r.position.y)), Color(0, 0, 0, 0))
	if String(command.get("key", "")) != "":
		draw_rect(Rect2(4, 4, 16, 16), Color(0, 0, 0, 0.55))


## A drawn mark in place of an icon: a check (Done), a double chevron (Next),
## a hooked arrow back (Redo); inked, then struck in `col`.
func _mark(r: Rect2, kind: String, col: Color) -> void:
	var lines: Array = []
	var p := func(x: float, y: float) -> Vector2: return r.position + r.size * Vector2(x, y)
	match kind:
		"check":
			lines = [PackedVector2Array([p.call(0.08, 0.55), p.call(0.38, 0.85), p.call(0.92, 0.18)])]
		"next":
			lines = [PackedVector2Array([p.call(0.12, 0.15), p.call(0.47, 0.5), p.call(0.12, 0.85)]),
				PackedVector2Array([p.call(0.53, 0.15), p.call(0.88, 0.5), p.call(0.53, 0.85)])]
		"undo":
			var arc := PackedVector2Array()
			for i in 13:
				var a := lerpf(-PI * 0.5, PI * 0.5, i / 12.0)
				arc.append(p.call(0.55 + 0.32 * cos(a), 0.55 + 0.3 * sin(a)))
			arc.append(p.call(0.12, 0.85))
			arc.insert(0, p.call(0.22, 0.25))
			lines = [arc, PackedVector2Array([p.call(0.38, 0.05), p.call(0.18, 0.25), p.call(0.38, 0.45)])]
	for l in lines:
		draw_polyline(l, Style.INK, 9.0, true)
	for l in lines:
		draw_polyline(l, col, 5.0, true)
