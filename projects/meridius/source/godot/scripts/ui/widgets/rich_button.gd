## A Button whose label mixes text and icons, like the original's
## `<button>Hire <Icon name="silver"/> 30</button>` or `Refill all <Icon/> 40`.
## Text uses the button variation's font, size and colour; hover brightens and
## disabled greys the whole content (the CSS `filter` on `.btn`), pressed moves it
## down 1 px.
##
##   const RichButton = preload("res://scripts/ui/widgets/rich_button.gd")
##   RichButton.make(parts: Array, variation := "SmallButton", on_press := Callable()) -> Button
##       parts: Strings (text), {"icon": name, "size": px} dictionaries, or Controls.
##       e.g. RichButton.make(["Hire", {"icon": "silver", "size": 14}, "30"], "GoldSmallButton", f)
##   button.set_parts(parts)   rebuild the content
extends Button

const UI = preload("res://scripts/ui/ui.gd")
const Icon = preload("res://scripts/ui/widgets/icon.gd")

const SHADER := """
shader_type canvas_item;
uniform int mode = 0;
void fragment() {
	vec4 c = COLOR;
	if (mode == 1) {
		c.rgb = min(c.rgb * 1.15, vec3(1.0));
	} else if (mode == 2) {
		float g = 0.7;
		float k = 1.0 - g;
		vec3 o;
		o.r = (0.2126 + 0.7874 * k) * c.r + (0.7152 - 0.7152 * k) * c.g + (0.0722 - 0.0722 * k) * c.b;
		o.g = (0.2126 - 0.2126 * k) * c.r + (0.7152 + 0.2848 * k) * c.g + (0.0722 - 0.0722 * k) * c.b;
		o.b = (0.2126 - 0.2126 * k) * c.r + (0.7152 - 0.7152 * k) * c.g + (0.0722 + 0.9278 * k) * c.b;
		c.rgb = o * 0.75;
		c.a *= 0.7;
	}
	COLOR = c;
}
"""

static var _shader: Shader

var parts: Array = []
var _row: HBoxContainer
var _mode := -1


static func make(parts_: Array, variation := "SmallButton", on_press := Callable()) -> Button:
	var b: Button = load("res://scripts/ui/widgets/rich_button.gd").new()
	b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if on_press.is_valid():
		b.pressed.connect(on_press)
	b.set_parts(parts_)
	return b


func _init() -> void:
	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 4)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	_row.material = m
	add_child(_row)
	_row.minimum_size_changed.connect(_fit)
	resized.connect(_layout)


func set_parts(parts_: Array) -> void:
	parts = parts_
	UI.clear(_row)
	for p in parts:
		var c: Control
		if p is String:
			c = Label.new()
			(c as Label).text = p
		elif p is Dictionary:
			c = Icon.make(p.get("icon", ""), p.get("size", 14))
		elif p is Control:
			c = p
		else:
			continue
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.use_parent_material = true
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_row.add_child(c)
	_apply_fonts()
	_fit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_apply_fonts()
		_fit()


func _apply_fonts() -> void:
	if not is_inside_tree():
		return
	var f := get_theme_font("font")
	var fs := get_theme_font_size("font_size")
	var fc := get_theme_color("font_color")
	for c in _row.get_children():
		if c is Label:
			c.add_theme_font_override("font", f)
			c.add_theme_font_size_override("font_size", fs)
			c.add_theme_color_override("font_color", fc)


func _fit() -> void:
	var sb: StyleBox = get_theme_stylebox("normal") if is_inside_tree() else UI.theme_stylebox(self, "normal")
	var m := Vector2.ZERO
	if sb != null:
		m = sb.get_minimum_size()
	custom_minimum_size = _row.get_combined_minimum_size() + m
	_layout()


func _layout() -> void:
	var sb: StyleBox = get_theme_stylebox("normal") if is_inside_tree() else UI.theme_stylebox(self, "normal")
	var off := Vector2.ZERO
	var ms := Vector2.ZERO
	if sb != null:
		off = Vector2(sb.get_margin(SIDE_LEFT), sb.get_margin(SIDE_TOP))
		ms = sb.get_minimum_size()
	var down := 1.0 if (get_draw_mode() == DRAW_PRESSED or get_draw_mode() == DRAW_HOVER_PRESSED) and not toggle_mode else 0.0
	_row.position = off + Vector2(0, down)
	_row.size = size - ms


func _draw() -> void:
	var mode := 0
	match get_draw_mode():
		DRAW_DISABLED:
			mode = 2
		DRAW_HOVER, DRAW_PRESSED, DRAW_HOVER_PRESSED:
			mode = 1
	if mode != _mode:
		_mode = mode
		(_row.material as ShaderMaterial).set_shader_parameter("mode", mode)
	_layout()
