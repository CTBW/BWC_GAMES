## Shared UI helpers: the stylesheet's colours, the fonts, and small factories
## for the Controls the screens are built from. Port of the CSS variables and
## utility classes of src/ui/styles.css plus `Sign` / `squadTypeLabel` of
## src/ui/common.tsx.
##
## Use through `const UI = preload("res://scripts/ui/ui.gd")`.
##
## API (all static):
##   Colours            UI.INK, INK_SOFT, INK_FAINT, PARCH, PARCH_2, PARCH_DARK, WOOD, WOOD_2,
##                      GOLD, GOLD_BRIGHT, BLUE, BLUE_BRIGHT, RED, RED_BRIGHT, GREEN, HP, MORALE,
##                      LIGHT (#f0e2c0, text on dark), LIGHT_TITLE (#f6e7c2), DARK_MUTED (#b8a27c),
##                      POS (#2d6a1a), NEG (#a3261c), WARN (#8a4a10), LOSS (#8a1f15), C(hex, alpha)
##   font(family, weight := 400, italic := false, spacing := 0) -> Font
##                      family "cinzel" (400/700/900), "alegreya" (400/500/700, italic 400),
##                      "sans" (Alegreya Sans 400). spacing = extra px per glyph (CSS letter-spacing).
##   label(text, variation := "", size := 0, color := Color(0,0,0,0)) -> Label
##   cinzel(text, size := 16, weight := 700, color := Color(0,0,0,0)) -> Label   (the `.cinzel` bold lines)
##   rich(bbcode, variation := "BodyText", min_width := 0) -> RichTextLabel   (fit_content, autowrap)
##                      variations: BodyText (16) SmallText (13) TinyText (12) DialogText (17) ManualText (16, 1.45)
##   hbox(sep := 8, children := []) / vbox(sep := 6, children := []) -> BoxContainer
##   grid(columns, hsep := 8, vsep := 8) -> GridContainer
##   button(text, variation := "Button", on_press := Callable()) -> Button
##   panel(variation := "ParchmentPanel", padding := [] ) -> PanelContainer
##                      padding: [all] | [v, h] | [top, right, bottom, left] (CSS order)
##   dark(panel) -> panel    gives a DarkPanel its light-text sub-theme (ThemeBuilder.dark_theme())
##   pad(control, padding) -> control   sets the content margins of a PanelContainer (duplicates its stylebox)
##   spacer(horizontal := true) -> Control (expands)
##   gap(w, h) -> Control (fixed empty space)
##   clear(node)             frees all children now
##   sign_label(n, size := 0) -> Label   ("+3" green / "-2" red / "0"), port of Sign
##   rank_name(level) -> String, squad_type_label(type_id, level := 0, short := false) -> String
##   ellipsize(label)        single line with "…" (CSS text-overflow: ellipsis)
##   stop_mouse(control) / ignore_mouse(control)
extends RefCounted

const DB = preload("res://scripts/data/db.gd")

const INK := Color("#2b1d10")
const INK_SOFT := Color("#5b4630")
const INK_FAINT := Color("#6c5940")
const PARCH := Color("#efe2c2")
const PARCH_2 := Color("#e4d3ab")
const PARCH_DARK := Color("#cdb88a")
const WOOD := Color("#3a2414")
const WOOD_2 := Color("#5b3a20")
const GOLD := Color("#c99a3c")
const GOLD_BRIGHT := Color("#ffd76a")
const BLUE := Color("#2f58b8")
const BLUE_BRIGHT := Color("#6fa0ff")
const RED := Color("#a3261c")
const RED_BRIGHT := Color("#e0553f")
const GREEN := Color("#4f8a34")
const HP := Color("#58b84a")
const MORALE := Color("#6fb3ff")
const LIGHT := Color("#f0e2c0")
const LIGHT_TITLE := Color("#f6e7c2")
const DARK_MUTED := Color("#b8a27c")
const POS := Color("#2d6a1a")
const NEG := Color("#a3261c")
const WARN := Color("#8a4a10")
const LOSS := Color("#8a1f15")

const FONT_FILES := {
	"cinzel400": "cinzel-%s-400-normal",
	"cinzel700": "cinzel-%s-700-normal",
	"cinzel900": "cinzel-%s-900-normal",
	"alegreya400": "alegreya-%s-400-normal",
	"alegreya500": "alegreya-%s-500-normal",
	"alegreya700": "alegreya-%s-700-normal",
	"alegreya400i": "alegreya-%s-400-italic",
	"sans400": "alegreya-sans-%s-400-normal",
}

static var _fonts: Dictionary = {}

const SHORT_PLURAL := {"collie_guard": "Royal Guards", "war_wagon": "War Wagons"}


## A colour from hex with an alpha (CSS rgba()).
static func C(hex: String, alpha := 1.0) -> Color:
	var c := Color(hex)
	c.a = alpha
	return c


## The font for a family/weight/style, with the Latin Extended subset as fallback
## and an optional letter spacing in px. Cached.
static func font(family: String, weight := 400, italic := false, spacing := 0) -> Font:
	var key := "%s%d%s" % [family, weight, "i" if italic else ""]
	var ck := "%s/%d" % [key, spacing]
	if _fonts.has(ck):
		return _fonts[ck]
	if not FONT_FILES.has(key):
		push_error("UI.font: no font " + key)
		key = "alegreya400"
	var pattern: String = FONT_FILES[key]
	var fv := FontVariation.new()
	fv.base_font = load("res://assets/fonts/%s.woff2" % (pattern % "latin"))
	var ext: Font = load("res://assets/fonts/%s.woff2" % (pattern % "latin-ext"))
	if ext != null:
		fv.fallbacks = [ext]
	if spacing != 0:
		fv.spacing_glyph = spacing
	_fonts[ck] = fv
	return fv


static func label(text: String, variation := "", size := 0, color := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A `.cinzel` line (Cinzel, bold by default).
static func cinzel(text: String, size := 16, weight := 700, color := Color(0, 0, 0, 0)) -> Label:
	var l := label(text, "CinzelLabel", size, color)
	if weight != 700:
		l.add_theme_font_override("font", font("cinzel", weight))
	return l


## Wrapped rich text sized to its content. Use [b], [i], [color=#hex] in bbcode.
static func rich(bbcode: String, variation := "BodyText", min_width := 0) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.theme_type_variation = variation
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if min_width > 0:
		r.custom_minimum_size.x = min_width
	r.text = bbcode
	return r


static func hbox(sep := 8, children: Array = []) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.alignment = BoxContainer.ALIGNMENT_BEGIN
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in children:
		if c != null:
			b.add_child(c)
	return b


static func vbox(sep := 6, children: Array = []) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in children:
		if c != null:
			b.add_child(c)
	return b


static func grid(columns: int, hsep := 8, vsep := 8) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", hsep)
	g.add_theme_constant_override("v_separation", vsep)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


static func button(text: String, variation := "Button", on_press := Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


static func panel(variation := "ParchmentPanel", padding: Array = []) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	if not padding.is_empty():
		pad(p, padding)
	if variation == "BannerPanel":
		# Keep live headings clear of the fixed-size painted clasps and folded ends.
		var banner: StyleBox = theme_stylebox(p).duplicate()
		banner.content_margin_left = maxf(66, banner.content_margin_left)
		banner.content_margin_right = maxf(66, banner.content_margin_right)
		banner.content_margin_top = maxf(20, banner.content_margin_top)
		banner.content_margin_bottom = maxf(22, banner.content_margin_bottom)
		p.add_theme_stylebox_override("panel", banner)
	if variation in ["DarkPanel", "BannerPanel"]:
		dark(p)
	return p


## Gives a dark panel its sub-theme so labels, tags and ghost buttons inside it
## take the light colours of `.panel.dark` (CSS descendant selectors).
static func dark(p: Control) -> Control:
	var TB = load("res://scripts/ui/theme_builder.gd")
	p.theme = TB.dark_theme()
	return p


## Sets the content margins (CSS padding) of a PanelContainer, [all] | [v, h] | [t, r, b, l].
static func pad(c: Control, padding: Array) -> Control:
	var t: float = padding[0]
	var r: float = t
	var b: float = t
	var l: float = t
	if padding.size() == 2:
		r = padding[1]
		l = r
	elif padding.size() >= 4:
		r = padding[1]
		b = padding[2]
		l = padding[3]
	var sb: StyleBox = theme_stylebox(c, "panel")
	sb = sb.duplicate() if sb != null else StyleBoxEmpty.new()
	sb.content_margin_top = t
	sb.content_margin_right = r
	sb.content_margin_bottom = b
	sb.content_margin_left = l
	c.add_theme_stylebox_override("panel", sb)
	return c


## A control's stylebox from its theme variation, also before it is in the tree
## (then looked up in its own theme and the UI theme; ancestors' sub-themes are not known yet).
static func theme_stylebox(c: Control, item := "panel") -> StyleBox:
	if c.has_theme_stylebox_override(item):
		return c.get_theme_stylebox(item)
	if c.is_inside_tree():
		return c.get_theme_stylebox(item)
	var TB = load("res://scripts/ui/theme_builder.gd")
	var types: Array = []
	if c.theme_type_variation != &"":
		types.append(c.theme_type_variation)
	types.append(c.get_class())
	for th in [c.theme, TB.theme()]:
		if th == null:
			continue
		for ty in types:
			if (th as Theme).has_stylebox(item, ty):
				return (th as Theme).get_stylebox(item, ty)
	return null


## The `.panel .title` block: centred Cinzel title, 6 px, a hairline rule, 10 px.
## A restrained blue cloth heading set into the panel's binding.
static func title_block(text: String, size := 0, color := Color(0, 0, 0, 0)) -> VBoxContainer:
	var col := vbox(0)
	var band := panel("BannerPanel", [7, 18])
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(text, "TitleLabel", size, color.lightened(0.55) if color.a > 0 else LIGHT_TITLE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	band.add_child(l)
	col.add_child(band)
	col.add_child(gap(0, 12))
	return col


static func title_block_rich(bbcode: String) -> VBoxContainer:
	var col := vbox(0)
	var band := panel("BannerPanel", [7, 18])
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(rich("[center]%s[/center]" % bbcode.replace("#8a7356", "#b8a27c"), "TitleText"))
	col.add_child(band)
	col.add_child(gap(0, 12))
	return col


## CSS grid with equal columns (repeat(n, minmax(0, 1fr))): rows of equal-width
## cells; a short last row is padded so its cells keep the column width.
static func equal_grid(items: Array, cols: int, hsep := 8, vsep := 8) -> VBoxContainer:
	var col := vbox(vsep)
	var row: HBoxContainer = null
	for i in items.size():
		if i % cols == 0:
			row = hbox(hsep)
			col.add_child(row)
		var it: Control = items[i]
		it.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		it.size_flags_stretch_ratio = 1.0
		row.add_child(it)
	if row != null:
		for k in cols - row.get_child_count():
			row.add_child(spacer())
	return col


static func spacer(horizontal := true) -> Control:
	var s := Control.new()
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if horizontal:
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s


static func gap(w: float, h: float) -> Control:
	var s := Control.new()
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.custom_minimum_size = Vector2(w, h)
	return s


static func clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


## Port of common.tsx Sign: "+n" in green, "-n" in red, "0" plain.
static func sign_label(n: int, size := 0) -> Label:
	var l := label("+%d" % n if n > 0 else str(n), "GoodLabel" if n > 0 else ("BadLabel" if n < 0 else ""), size)
	return l


static func rank_name(level: int) -> String:
	var ranks: Array = DB.RANKS
	return ranks[clampi(level - 1, 0, ranks.size() - 1)]


## "Footmen", with rank when given: "Veteran Footmen". `short` uses compact names for long types.
static func squad_type_label(type_id: String, level := 0, short := false) -> String:
	var def: Dictionary = DB.UNIT_TYPES.get(type_id, {})
	var plural: String = ""
	if def.has("crew"):
		# One war machine and its crew: "Veteran Ballista Crew".
		var nm := ""
		if short and SHORT_PLURAL.has(type_id):
			nm = SHORT_PLURAL[type_id]
			if nm.ends_with("s"):
				nm = nm.left(-1)
		plural = "%s Crew" % (nm if nm != "" else str(def.get("name", type_id)))
	elif short and SHORT_PLURAL.has(type_id):
		plural = SHORT_PLURAL[type_id]
	else:
		plural = def.get("plural", type_id)
	return "%s %s" % [rank_name(level), plural] if level else plural


static func ellipsize(l: Label) -> Label:
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 1
	return l


static func stop_mouse(c: Control) -> Control:
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	return c


static func ignore_mouse(c: Control) -> Control:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Escapes text for bbcode.
static func esc(s: String) -> String:
	return s.replace("[", "[lb]")
