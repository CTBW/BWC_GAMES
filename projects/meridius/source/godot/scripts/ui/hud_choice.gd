## The `.choice` button of the campaign dialogs (src/ui/styles.css): a full-width,
## left-aligned Alegreya 500 16 px line on a pale card that slides 3 px right on
## hover, with optional `.hint` spans (13 px, ink-faint, 8 px left margin) and a
## red reason when the choice is unavailable. Disabled: 50 % opacity.
##
##   const Choice = preload("res://scripts/ui/hud_choice.gd")
##   Choice.make(label: String, hints: Array, on_press: Callable, disabled := false) -> Button
##       hints: [[text, colour (Color or null)], …] shown after the label.
## The Button text stays empty; the visible text is in the meta "label".
extends Button

const UI = preload("res://scripts/ui/ui.gd")

const HINT_COLOUR := Color("#8a7356")

var _rt: RichTextLabel
var _gap: ImageTexture
var _laying := false


static func make(label: String, hints: Array, on_press: Callable, disabled_ := false) -> Button:
	var b: Button = load("res://scripts/ui/hud_choice.gd").new()
	b.set_content(label, hints)
	b.disabled = disabled_
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


func _init() -> void:
	theme_type_variation = "ChoiceButton"
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip_text = false
	_rt = RichTextLabel.new()
	_rt.bbcode_enabled = false
	_rt.fit_content = true
	_rt.scroll_active = false
	_rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rt.add_theme_font_override("normal_font", UI.font("alegreya", 500))
	_rt.add_theme_font_size_override("normal_font_size", 16)
	_rt.add_theme_color_override("default_color", UI.INK)
	_rt.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	add_child(_rt)
	var img := Image.create(8, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_gap = ImageTexture.create_from_image(img)
	resized.connect(_layout)
	_rt.finished.connect(_layout)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func set_content(label: String, hints: Array) -> void:
	set_meta("label", label + "".join(hints.map(func(h): return " " + str(h[0]))))
	_rt.clear()
	_rt.add_text(label)
	for h in hints:
		_rt.add_image(_gap, 8, 1)
		_rt.push_font_size(13)
		_rt.push_color(h[1] if h.size() > 1 and h[1] is Color else HINT_COLOUR)
		_rt.add_text(str(h[0]))
		_rt.pop()
		_rt.pop()
	_layout()


func _margins() -> Rect2:
	var sb: StyleBox = get_theme_stylebox("normal") if is_inside_tree() else null
	if sb == null:
		return Rect2(14, 10, 14, 10)
	return Rect2(sb.get_margin(SIDE_LEFT), sb.get_margin(SIDE_TOP), sb.get_margin(SIDE_RIGHT), sb.get_margin(SIDE_BOTTOM))


func _layout() -> void:
	if _laying:
		return
	_laying = true
	var m := _margins()
	var hover := is_hovered() and not disabled
	var w := maxf(10.0, size.x - m.position.x - m.size.x)
	_rt.position = Vector2(m.position.x + (3.0 if hover else 0.0), m.position.y)
	_rt.size = Vector2(w, _rt.size.y)
	var h := float(_rt.get_content_height())
	_rt.size = Vector2(w, h)
	_rt.modulate.a = 0.5 if disabled else 1.0
	var need := h + m.position.y + m.size.y
	if absf(custom_minimum_size.y - need) > 0.5:
		custom_minimum_size.y = need
	_laying = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE:
		_layout()


func _draw() -> void:
	_layout()
