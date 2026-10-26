## Small builders of the battle HUD (battle_hud.gd; the campaign HUD that
## shared them is set aside): the inline CSS bits of src/ui/screens/Campaign.tsx
## and Battle.tsx that are not shared widgets (`.dialog` titles and paragraphs,
## `kbd`, wrapped tag rows, absolute placement like CSS `position: absolute`).
##
##   const H = preload("res://scripts/ui/hud_common.gd")
##   H.place(c, ax, ay, x, y, grow_h, grow_v)   anchor point + offset, sized by content
##   H.text(text, size, color := none, family := "alegreya", weight := 400) -> Label
##   H.rich(bbcode, size, color := none, center := false) -> RichTextLabel
##   H.title(text, size := 22, color := none) -> Control       the `.panel .title` with its rule
##   H.para(bbcode, italic := false, center := false, cinzel := false) -> Control   `.dialog p`
##   H.kbd(text) -> Control                                     `<kbd>` (border in the text colour)
##   H.flow(gap, center := false) -> HFlowContainer             `.row` with flex-wrap
##   H.center_row(children, gap := 12, top := 0) -> Control     a centred button row
##   H.margin(c, top, right, bottom, left) -> MarginContainer
##   H.hex(c) -> String                                         "#rrggbb" for bbcode
##   H.app(node) -> Object                                      the App store (dynamic)
extends RefCounted

const UI = preload("res://scripts/ui/ui.gd")
const Flourish = preload("res://scripts/ui/widgets/flourish.gd")

const NONE := Color(0, 0, 0, 0)


## The App store autoload, untyped so calls resolve at run time.
static func app(n: Node) -> Object:
	if n != null and n.is_inside_tree():
		var a := n.get_tree().root.get_node_or_null("App")
		if a != null:
			return a
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("App")
	return null


## Positions `c` like CSS `position: absolute`: the anchor point (ax, ay) of the
## parent plus the offset (x, y); its size follows its minimum size, growing
## away from the anchor (grow: -1 begin, 0 both, 1 end).
static func place(c: Control, ax: float, ay: float, x: float, y: float, grow_h := 1, grow_v := 1) -> Control:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = x
	c.offset_right = x
	c.offset_top = y
	c.offset_bottom = y
	c.grow_horizontal = _grow(grow_h)
	c.grow_vertical = _grow(grow_v)
	return c


static func _grow(g: int) -> int:
	if g < 0:
		return Control.GROW_DIRECTION_BEGIN
	if g == 0:
		return Control.GROW_DIRECTION_BOTH
	return Control.GROW_DIRECTION_END


## A one-line label in a given family, weight, size and colour.
static func text(t: String, size: int, color := NONE, family := "alegreya", weight := 400) -> Label:
	var l := UI.label(t, "", size, color)
	l.add_theme_font_override("font", UI.font(family, weight))
	return l


## Extra space between wrapped lines (Label `line_spacing`, RichTextLabel
## `line_separation`) that brings Godot's line pitch for Alegreya at a size to
## the browser's `line-height: normal` (about 1.33 em): Godot rounds the font
## height up (12 px → 18, 13 → 19, 16 → 23).
const LINE_GAP := {11: -2, 12: -3, 13: -2, 14: -2, 15: -2, 16: -2}


static func line_gap(size: int) -> int:
	return LINE_GAP.get(size, 0)


## Wrapped rich text (Alegreya) with an explicit size and colour.
static func rich(bbcode: String, size: int, color := NONE, center := false) -> RichTextLabel:
	var r := UI.rich("[center]%s[/center]" % bbcode if center else bbcode, "BodyText")
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
		r.add_theme_font_size_override(k, size)
	r.add_theme_constant_override("line_separation", line_gap(size))
	if color.a > 0.0:
		r.add_theme_color_override("default_color", color)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func hex(c: Color) -> String:
	return "#" + c.to_html(c.a < 1.0)


## `.panel .title`: Cinzel 700 22 centred, 6 px padding and a 1 px rule below
## (its 10 px bottom margin is the caller's: H.stack([[title, 0, 10], …])).
static func title(t: String, size := 22, color := NONE) -> Control:
	var box := UI.vbox(0)
	var l := UI.label(t, "TitleLabel", size if size != 22 else 0, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	box.add_child(UI.gap(0, 6))
	var rule := HSeparator.new()
	rule.theme_type_variation = "TitleRule"
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	return box


## `.dialog p` (17 px, line height 1.45, 8 px above and below).
static func para(bbcode: String, italic := false, center := false, cinzel := false) -> Control:
	var body := bbcode
	if italic:
		body = "[i]%s[/i]" % body
	if center:
		body = "[center]%s[/center]" % body
	var r := UI.rich(body, "DialogText")
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 17 px at line-height 1.45 = 24.65 px per line (Godot: 24 + separation).
	r.add_theme_constant_override("line_separation", 1)
	if cinzel:
		r.add_theme_font_override("normal_font", UI.font("cinzel", 400))
		r.add_theme_font_override("bold_font", UI.font("cinzel", 700))
	return r


## `kbd`: Alegreya Sans 10, padding 0 4, 1 px border in the text colour, 75 % opacity, 6 px left margin.
static func kbd(t: String, color := Color("#f6e7c2")) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = color
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.anti_aliasing = true
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.modulate.a = 0.75
	p.use_parent_material = true
	var l := UI.label(t, "KbdLabel", 10, color)
	# The browser's line box for Alegreya Sans 10 px is 12 px (Godot's is 10).
	l.custom_minimum_size.y = 12
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.use_parent_material = true
	p.add_child(l)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 2)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.use_parent_material = true
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	m.add_child(p)
	return m


## A wrapping row (`.row` with flex-wrap).
static func flow(gap: int, center := false) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", gap)
	f.add_theme_constant_override("v_separation", gap)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if center:
		f.alignment = FlowContainer.ALIGNMENT_CENTER
	return f


## A centred row of buttons with `top` px above it.
static func center_row(children: Array, gap := 12, top := 0) -> Control:
	var row := UI.hbox(gap, children)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if top > 0:
		return margin(row, top, 0, 0, 0)
	return row


static func margin(c: Control, top: int, right: int, bottom: int, left: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_bottom", bottom)
	m.add_theme_constant_override("margin_left", left)
	m.add_child(c)
	return m


## Trims the line box of a control to the browser's: Godot's font heights are
## rounded up and run 1–2 px taller than CSS `line-height: normal`, which adds
## up in the dense HUD rows. Negative margins shrink the box around the same
## baseline (the content may draw a pixel outside it).
static func trim(c: Control, top: int, bottom: int) -> MarginContainer:
	var m := margin(c, top, 0, bottom, 0)
	m.size_flags_horizontal = c.size_flags_horizontal
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return m


static func flourish() -> Control:
	return Flourish.make(0)


## A block-layout column: items are [control, margin_top, margin_bottom]; the
## vertical margins of neighbours collapse as in CSS (the larger positive one
## plus the most negative one). The first item's top margin and the last
## item's bottom margin are kept (the dialog padding stops the collapse).
static func stack(items: Array) -> VBoxContainer:
	var box := UI.vbox(0)
	var prev_mb: Variant = null
	for it in items:
		if it == null:
			continue
		var c: Control = it[0]
		var mt: float = it[1] if it.size() > 1 else 0.0
		var mb: float = it[2] if it.size() > 2 else 0.0
		var g := mt
		if prev_mb != null:
			g = maxf(0.0, maxf(prev_mb, mt)) + minf(0.0, minf(prev_mb, mt))
		if g != 0.0:
			box.add_child(UI.gap(0, maxf(0.0, g)))
		box.add_child(c)
		prev_mb = mb
	if prev_mb != null and prev_mb > 0.0:
		box.add_child(UI.gap(0, prev_mb))
	return box


## Every Button under `n` (tests and automation).
static func buttons(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is BaseButton:
			out.append(c)
		out.append_array(buttons(c))
	return out


## The first Button under `n` whose visible text (or name) contains `t`.
static func find_button(n: Node, t: String) -> BaseButton:
	for b in buttons(n):
		if button_text(b).contains(t) or str(b.name) == t:
			return b
	return null


## Text of a Button, including rich content (RichButton parts, choice rows).
static func button_text(b: BaseButton) -> String:
	if b is Button and (b as Button).text != "":
		return (b as Button).text
	if b.has_meta("label"):
		return str(b.get_meta("label"))
	var s := ""
	for c in _labels(b):
		s += c
	return s


static func _labels(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Label:
			out.append((c as Label).text)
		elif c is RichTextLabel:
			out.append((c as RichTextLabel).get_parsed_text())
		out.append_array(_labels(c))
	return out
