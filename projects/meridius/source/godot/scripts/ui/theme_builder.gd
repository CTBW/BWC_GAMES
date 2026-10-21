## Builds the Meridius UI theme from the original stylesheet (src/ui/styles.css).
##
## `ThemeBuilder.theme()` returns the shared Theme (built once, cached).
## main.tscn's UI root applies it; any other UI root can do the same:
##     const ThemeBuilder = preload("res://scripts/ui/theme_builder.gd")
##     root_control.theme = ThemeBuilder.theme()
## `ThemeBuilder.dark_theme()` is the sub-theme a dark panel carries (UI.dark(panel)
## or UI.panel("DarkPanel")): inside it every Label/RichTextLabel/Tag/Ghost button
## variation below takes the light `.panel.dark` colours, like the CSS descendant
## rules. `ThemeBuilder.save()` writes assets/ui/theme.tres (run
## `tools/godot.sh --headless --path . -s res://scripts/ui/theme_build_cli.gd`).
##
## Fonts: Cinzel 400/700/900, Alegreya 400/500/700/400-italic, Alegreya Sans 400
## (assets/fonts, from @fontsource). Default font Alegreya 16 px, ink #2b1d10.
##
## TYPE VARIATIONS (set `control.theme_type_variation = "<Name>"`)
##
## PanelContainer
##   ParchmentPanel          `.panel` cream parchment, 2 px wood border, gold inset ring,
##                           brown inner glow, drop shadow. Padding 22/26 (`.dialog`).
##   ParchmentCard           `.card` light inset card inside parchment, padding 8.
##   ParchmentCardHover      `.card.clickable:hover`.
##   ParchmentCardSelected   `.card.sel` gold border + ring.  ParchmentCardSelectedHover.
##   DarkPanel               `.panel.dark` leather panel, gold ring; padding 10/14.
##                           Give it the light-text sub-theme with UI.dark(panel).
##   TopBar                  `.topbar` full-width dark bar, padding 0/18 (height 54 by the widget).
##   TooltipPanel            dark tooltip panel (also the native tooltip), padding 8/10.
##   ModalBack               `.modal-back` radial dimming behind dialogs (full rect).
##   Tag, TagRed, TagBlue, TagGold, TagGreen   `.tag` chips (use with TagLabel*; see widgets/tag.gd).
##   AbilitySlot             the `.ability` box look as a panel (no button behaviour).
## Label
##   TitleLabel              `.panel .title` Cinzel 700 22, centred.
##   LogoLabel / LogoSubLabel  title screen MERIDIUS (Cinzel 900 104) / THE FRONTIER COMPANY.
##   BrandLabel              top bar MERIDIUS (Cinzel 900 20, spaced).
##   BannerLabel / BannerSubLabel  battle turn banner (Cinzel 900 54) / its sub line (Cinzel 18).
##   H2Label (Cinzel 700 26) HeadingLabel (h3, Cinzel 700 17) H4Label (Cinzel 700 14)
##   CinzelLabel             `.cinzel` bold 16 (names, card titles).
##   ResLabel                `.res` numbers (Cinzel 700 16); ResNameLabel `.res .lbl` (Alegreya 12, 70%).
##   BodyLabel (16)  SmallLabel (13)  TinyLabel (12)
##   MutedLabel (16) SmallMutedLabel (13) TinyMutedLabel (12)   ink-faint / #b8a27c on dark
##   GoodLabel / BadLabel (16 bold)  SmallGoodLabel / SmallBadLabel (13 bold)   `.pos` / `.neg`
##   WarnLabel (13, #8a4a10)  LossLabel (13, #8a1f15)
##   TagLabel, TagRedLabel, TagBlueLabel, TagGoldLabel, TagGreenLabel   Cinzel 700 12
##   LoadingLabel            Cinzel 22 light.   KbdLabel  Alegreya Sans 10 (`kbd`).
##   PipsLabel               building level ◆◇ pips (#a37a2a, spaced 3).
## RichTextLabel (bold [b] = Alegreya 700, [i] = italic)
##   BodyText (16)  DialogText (17, `.dialog p`)  ManualText (16)  SmallText (13)  TinyText (12)
##   MutedText (16) SmallMutedText (13) TinyMutedText (12)  TooltipText (13.5→14, light)
##   TitleText (Cinzel 700 22; [b] = Cinzel 900) for titles mixing sizes
## Button  (name = colour + size + "Button"; sizes: "" 14 px pad 8/14, Small 12 px pad 4/9,
##          Big 19 px pad 12/26 — `.btn`, `.btn.sm`, `.btn.big`)
##   Button / SmallButton / BigButton                 brown `.btn` (default)
##   DarkButton / DarkSmallButton / DarkBigButton     = brown, the HUD button (Retreat, End Turn, Menu)
##   RedButton / RedSmallButton / RedBigButton        `.btn.primary` (Plan Expedition, March Out, Retreat Home)
##   BlueButton / BlueSmallButton / BlueBigButton     `.btn.blue` (Continue)
##   GoldButton / GoldSmallButton / GoldBigButton     `.btn.gold` (Hire, Build, Refill, Promote)
##   GhostButton / GhostSmallButton / GhostBigButton  `.btn.ghost` (light text inside a dark panel)
##   ButtonActive / SmallButtonActive / IconButtonActive   `.btn.active` gold ring + glow
##   IconButton              `.btn.sm.icon` square icon button (icon max 18 px, tinted #f0e2c0)
##   ChoiceButton            `.choice` full-width left-aligned event choice
##   AbilityButton / AbilityButtonActive   `.ability` 62×62 battle ability (Cinzel 10)
##   For toggles, swap the variation (e.g. SmallButton ↔ SmallButtonActive) — see UI.set_active().
## ProgressBar  (height 9 unless the widget sets it; use widgets/bar.gd)
##   HpBar, HpLowBar, MoraleBar, FatigueBar, XpBar, CpBar, OverBar
## LineEdit
##   NameEdit                soldier name field (Cinzel 700 24, dashed underline)
## HSeparator
##   TitleRule               the 1 px rule under a `.title`;  Rule  plain parchment rule
## Custom theme types read by widgets (get_theme_color(...)):
##   MenPips/font_color      pips colour (ink; #e9d8ae on dark)
##   Icon/tint               tint for the white (currentColor) icons (ink; light on dark)
extends RefCounted

const UI = preload("res://scripts/ui/ui.gd")
const PaperStyle = preload("res://scripts/ui/styles/paper_style.gd")

const SAVE_PATH := "res://assets/ui/theme.tres"

static var _theme: Theme
static var _dark: Theme
static var _paper_tex: Texture2D
static var _blotch_tex: Texture2D

const LABELS := {
	# name: [family, weight, size, colour, dark colour]
	"BodyLabel": ["alegreya", 400, 16, "ink", "light"],
	"SmallLabel": ["alegreya", 400, 13, "ink", "light"],
	"TinyLabel": ["alegreya", 400, 12, "ink", "light"],
	"MutedLabel": ["alegreya", 400, 16, "faint", "dmuted"],
	"SmallMutedLabel": ["alegreya", 400, 13, "faint", "dmuted"],
	"TinyMutedLabel": ["alegreya", 400, 12, "faint", "dmuted"],
	"GoodLabel": ["alegreya", 700, 16, "pos", "dgood"],
	"BadLabel": ["alegreya", 700, 16, "neg", "dbad"],
	"SmallGoodLabel": ["alegreya", 700, 13, "pos", "dgood"],
	"SmallBadLabel": ["alegreya", 700, 13, "neg", "dbad"],
	"WarnLabel": ["alegreya", 400, 13, "warn", "dbad"],
	"LossLabel": ["alegreya", 400, 13, "loss", "dbad"],
	"TitleLabel": ["cinzel", 700, 22, "ink", "title"],
	"H2Label": ["cinzel", 700, 26, "ink", "title"],
	"HeadingLabel": ["cinzel", 700, 17, "ink", "title"],
	"H4Label": ["cinzel", 700, 14, "ink", "title"],
	"CinzelLabel": ["cinzel", 700, 16, "ink", "light"],
	"ResLabel": ["cinzel", 700, 16, "ink", "light"],
	"ResNameLabel": ["alegreya", 400, 12, "ink70", "light70"],
	"TagLabel": ["cinzel", 700, 12, "ink", "light"],
	"TagRedLabel": ["cinzel", 700, 12, "tagred", "light"],
	"TagBlueLabel": ["cinzel", 700, 12, "tagblue", "light"],
	"TagGoldLabel": ["cinzel", 700, 12, "taggold", "light"],
	"TagGreenLabel": ["cinzel", 700, 12, "taggreen", "light"],
	"LoadingLabel": ["cinzel", 400, 22, "light", "light"],
	"KbdLabel": ["sans", 400, 10, "ink", "light"],
	"PipsLabel": ["alegreya", 400, 16, "pips", "pips"],
}

const RICH := {
	"BodyText": [16, "ink", "light"],
	"DialogText": [17, "ink", "light"],
	"ManualText": [16, "ink", "light"],
	"SmallText": [13, "ink", "light"],
	"TinyText": [12, "ink", "light"],
	"MutedText": [16, "faint", "dmuted"],
	"SmallMutedText": [13, "faint", "dmuted"],
	"TinyMutedText": [12, "faint", "dmuted"],
	"TooltipText": [14, "light", "light"],
}

const BUTTON_COLOURS := ["", "Dark", "Red", "Blue", "Gold", "Ghost"]
const BUTTON_SIZES := {"": [14, 14.0, 8.0], "Small": [12, 9.0, 4.0], "Big": [19, 26.0, 12.0]}


static func theme() -> Theme:
	if _theme == null:
		_theme = build()
	return _theme


static func dark_theme() -> Theme:
	if _dark == null:
		_dark = build_dark()
	return _dark


static func _col(key: String) -> Color:
	match key:
		"ink":
			return UI.INK
		"faint":
			return UI.INK_FAINT
		"light":
			return UI.LIGHT
		"title":
			return UI.LIGHT_TITLE
		"dmuted":
			return UI.DARK_MUTED
		"pos":
			return UI.POS
		"neg":
			return UI.NEG
		"dgood":
			return Color("#9fe08a")
		"dbad":
			return Color("#ff9a86")
		"warn":
			return UI.WARN
		"loss":
			return UI.LOSS
		"ink70":
			return UI.C("#2b1d10", 0.7)
		"light70":
			return UI.C("#f0e2c0", 0.7)
		"tagred":
			return Color("#8a1f15")
		"tagblue":
			return Color("#1f3f8c")
		"taggold":
			return Color("#6b4a10")
		"taggreen":
			return Color("#2d5a1a")
		"pips":
			return Color("#a37a2a")
	return UI.INK


static func paper_texture() -> Texture2D:
	if _paper_tex == null:
		_paper_tex = load("res://assets/ui/paper.png")
	return _paper_tex


static func blotch_texture() -> Texture2D:
	if _blotch_tex == null:
		_blotch_tex = load("res://assets/ui/blotch.png")
	return _blotch_tex


static func _grad(stops: Array) -> Gradient:
	# stops: [[offset, Color], ...]
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(s[0])
		cols.append(s[1])
	g.offsets = offs
	g.colors = cols
	return g


static func _margins(sb: StyleBox, v: float, h: float) -> StyleBox:
	sb.content_margin_top = v
	sb.content_margin_bottom = v
	sb.content_margin_left = h
	sb.content_margin_right = h
	return sb


# ------------------------------------------------------------------ panels

static func parchment_style() -> StyleBox:
	var s := PaperStyle.new()
	s.bg_color = UI.PARCH
	s.gradient = _grad([[0.0, Color("#f3e8cc")], [0.6, Color("#e8d6ac")], [1.0, Color("#dcc595")]])
	s.gradient_angle = 170.0
	s.layers = [paper_texture(), blotch_texture()]
	s.corner_radius = 7.0
	s.border_color = UI.WOOD
	_border(s, 2.0)
	s.rings = [[3.0, UI.C("#c99a3c", 0.35)], [4.0, UI.C("#3a2414", 0.35)]]
	s.glow_size = 50.0
	s.glow_color = Color(120 / 255.0, 80 / 255.0, 30 / 255.0, 0.35)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_offset = Vector2(0, 10)
	s.shadow_blur = 30.0
	return _margins(s, 22, 26)


static func dark_style() -> StyleBox:
	var s := PaperStyle.new()
	s.bg_color = Color("#2c1f14")
	s.gradient = _grad([[0.0, Color("#3b2918")], [1.0, Color("#24170d")]])
	s.gradient_angle = 170.0
	s.layers = [paper_texture()]
	s.corner_radius = 7.0
	s.border_color = Color("#1a0f07")
	_border(s, 2.0)
	s.rings = [[2.0, UI.C("#c99a3c", 0.45)]]
	s.glow_size = 40.0
	s.glow_color = Color(0, 0, 0, 0.5)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_offset = Vector2(0, 10)
	s.shadow_blur = 30.0
	return _margins(s, 10, 14)


static func card_style(hover := false, sel := false) -> StyleBox:
	var s := PaperStyle.new()
	s.bg_color = Color(1.0, 250 / 255.0, 235 / 255.0, 0.8) if hover else Color(1.0, 248 / 255.0, 228 / 255.0, 0.55)
	s.corner_radius = 6.0
	_border(s, 1.0)
	if sel:
		s.border_color = UI.GOLD
		s.outer_ring_width = 2.0
		s.outer_ring_color = UI.C("#c99a3c", 0.6)
		s.glow_size = 12.0
		s.glow_color = UI.C("#c99a3c", 0.25)
	else:
		s.border_color = UI.C("#5b4630", 0.35)
		s.glow_size = 12.0
		s.glow_color = Color(150 / 255.0, 110 / 255.0, 50 / 255.0, 0.15)
	return _margins(s, 8, 8)


static func topbar_style() -> StyleBox:
	var s := PaperStyle.new()
	s.gradient = _grad([[0.0, Color(28 / 255.0, 18 / 255.0, 10 / 255.0, 0.95)], [1.0, Color(28 / 255.0, 18 / 255.0, 10 / 255.0, 0.72)]])
	s.gradient_angle = 180.0
	s.border_color = Color("#120a04")
	s.border_bottom = 2.0
	s.bottom_line = UI.C("#c99a3c", 0.45)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_offset = Vector2(0, 4)
	s.shadow_blur = 16.0
	return _margins(s, 0, 18)


static func tooltip_style() -> StyleBox:
	var s: StyleBox = dark_style()
	return _margins(s, 8, 10)


static func modal_back_style() -> StyleBox:
	var g := _grad([[0.0, Color(10 / 255.0, 6 / 255.0, 3 / 255.0, 0.35)], [1.0, Color(10 / 255.0, 6 / 255.0, 3 / 255.0, 0.7)]])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 1.0)
	t.width = 128
	t.height = 128
	var s := StyleBoxTexture.new()
	s.texture = t
	return s


static func tag_style(kind: String, dark := false) -> StyleBox:
	var bg := Color(58 / 255.0, 36 / 255.0, 20 / 255.0, 0.12)
	var bd := Color(58 / 255.0, 36 / 255.0, 20 / 255.0, 0.3)
	if dark:
		bg = UI.C("#f0e2c0", 0.08)
		bd = UI.C("#f0e2c0", 0.3)
	else:
		match kind:
			"Red":
				bg = UI.C("#a3261c", 0.15)
				bd = UI.C("#a3261c", 0.5)
			"Blue":
				bg = UI.C("#2f58b8", 0.13)
				bd = UI.C("#2f58b8", 0.45)
			"Gold":
				bg = UI.C("#c99a3c", 0.2)
				bd = UI.C("#c99a3c", 0.7)
			"Green":
				bg = UI.C("#4f8a34", 0.15)
				bd = UI.C("#4f8a34", 0.5)
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = bd
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.anti_aliasing = true
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	return s


static func _border(s: PaperStyle, w: float) -> void:
	s.border_left = w
	s.border_top = w
	s.border_right = w
	s.border_bottom = w


# ------------------------------------------------------------------ colour filters

## CSS filter: brightness(k).
static func bright(c: Color, k: float) -> Color:
	return Color(minf(c.r * k, 1.0), minf(c.g * k, 1.0), minf(c.b * k, 1.0), c.a)


## CSS filter: grayscale(g) brightness(b) opacity(o).
static func dimmed(c: Color, g := 0.7, b := 0.75, o := 0.7) -> Color:
	var k := 1.0 - g
	var r := (0.2126 + 0.7874 * k) * c.r + (0.7152 - 0.7152 * k) * c.g + (0.0722 - 0.0722 * k) * c.b
	var gg := (0.2126 - 0.2126 * k) * c.r + (0.7152 + 0.2848 * k) * c.g + (0.0722 - 0.0722 * k) * c.b
	var bb := (0.2126 - 0.2126 * k) * c.r + (0.7152 - 0.7152 * k) * c.g + (0.0722 + 0.9278 * k) * c.b
	return Color(clampf(r * b, 0, 1), clampf(gg * b, 0, 1), clampf(bb * b, 0, 1), c.a * o)


static func _map_grad(g: Gradient, f: Callable) -> Gradient:
	if g == null:
		return null
	var out := Gradient.new()
	out.offsets = g.offsets
	var cols := PackedColorArray()
	for c in g.colors:
		cols.append(f.call(c))
	out.colors = cols
	return out


## A copy of a PaperStyle with every colour passed through f (shadows kept unless `all`).
static func _map_style(s: PaperStyle, f: Callable, all := false) -> PaperStyle:
	var o: PaperStyle = s.duplicate()
	o.bg_color = f.call(s.bg_color)
	o.gradient = _map_grad(s.gradient, f)
	o.border_color = f.call(s.border_color)
	var rings := []
	for r in s.rings:
		rings.append([r[0], f.call(r[1])])
	o.rings = rings
	o.glow_color = f.call(s.glow_color)
	o.top_line = f.call(s.top_line)
	o.bottom_line = f.call(s.bottom_line)
	o.outer_ring_color = f.call(s.outer_ring_color)
	o.outer_glow_color = f.call(s.outer_glow_color)
	if all:
		o.shadow_color = f.call(s.shadow_color)
	return o


# ------------------------------------------------------------------ buttons

static func _btn_base(kind: String) -> PaperStyle:
	var s := PaperStyle.new()
	s.corner_radius = 5.0
	_border(s, 1.0)
	s.border_color = Color("#22130a")
	s.top_line = Color(1.0, 230 / 255.0, 180 / 255.0, 0.25)
	s.rings = [[1.0, UI.C("#c99a3c", 0.25)]]
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_offset = Vector2(0, 2)
	s.shadow_blur = 4.0
	match kind:
		"Red":
			s.gradient = _grad([[0.0, Color("#c4412f")], [0.55, Color("#93261a")], [1.0, Color("#761b12")]])
		"Blue":
			s.gradient = _grad([[0.0, Color("#4a74d4")], [0.55, Color("#2f58b8")], [1.0, Color("#22418c")]])
		"Gold":
			s.gradient = _grad([[0.0, Color("#e3b956")], [0.6, Color("#b98a2e")], [1.0, Color("#8e6620")]])
		"Ghost", "GhostDark":
			s.bg_color = Color(58 / 255.0, 36 / 255.0, 20 / 255.0, 0.08)
			s.border_color = UI.C("#3a2414", 0.45) if kind == "Ghost" else UI.C("#f0e2c0", 0.35)
			s.top_line = Color(0, 0, 0, 0)
			s.rings = []
			s.shadow_color = Color(0, 0, 0, 0)
		"Ability":
			s.corner_radius = 6.0
			s.gradient = _grad([[0.0, Color("#5b3a20")], [1.0, Color("#2c1a0c")]])
			s.border_color = Color("#120a04")
			s.top_line = Color(0, 0, 0, 0)
			s.rings = [[1.0, UI.C("#c99a3c", 0.35)]]
			s.shadow_color = Color(0, 0, 0, 0.4)
		"Choice":
			s.bg_color = Color(1.0, 248 / 255.0, 228 / 255.0, 0.6)
			s.border_color = UI.C("#5b4630", 0.4)
			s.top_line = Color(0, 0, 0, 0)
			s.rings = []
			s.shadow_color = Color(0, 0, 0, 0)
		_:
			s.gradient = _grad([[0.0, Color("#7b4c28")], [0.55, Color("#57331a")], [1.0, Color("#452812")]])
	return s


static func _active(s: PaperStyle) -> PaperStyle:
	# `.btn.active`: inset 0 0 0 2px gold-bright, 0 0 12px rgba(255,215,106,.5) (replaces the base shadows).
	var o: PaperStyle = s.duplicate()
	o.rings = [[2.0, UI.GOLD_BRIGHT]]
	o.top_line = Color(0, 0, 0, 0)
	o.shadow_color = Color(0, 0, 0, 0)
	o.outer_glow_size = 12.0
	o.outer_glow_color = Color(1.0, 215 / 255.0, 106 / 255.0, 0.5)
	return o


static func _set_button(t: Theme, name: String, kind: String, font_size: int, pad_h: float, pad_v: float, active := false) -> void:
	var base := _btn_base(kind)
	if active:
		base = _active(base)
	var hover_k := 1.2 if kind == "Ability" else 1.15
	var normal := _margins(base, pad_v, pad_h) as PaperStyle
	var hover: PaperStyle = _map_style(normal, func(c): return bright(c, hover_k))
	var pressed: PaperStyle = hover.duplicate()
	pressed.offset = Vector2(0, 1)
	pressed.content_margin_top = pad_v + 1
	pressed.content_margin_bottom = pad_v - 1
	var disabled: PaperStyle
	if kind == "Ability":
		disabled = _map_style(normal, func(c): return dimmed(c, 0.8, 0.6, 1.0), true)
	elif kind == "Choice":
		disabled = _map_style(normal, func(c): return Color(c, c.a * 0.5), true)
	else:
		disabled = _map_style(normal, func(c): return dimmed(c), true)
	if kind == "Choice":
		hover.bg_color = Color(1.0, 245 / 255.0, 215 / 255.0, 0.95)
		hover.border_color = normal.border_color
		hover.offset = Vector2(3, 0)
		pressed = hover.duplicate()
	if name != "Button":
		t.set_type_variation(name, "Button")
	t.set_stylebox("normal", name, normal)
	t.set_stylebox("hover", name, hover)
	t.set_stylebox("pressed", name, pressed)
	t.set_stylebox("hover_pressed", name, pressed)
	t.set_stylebox("disabled", name, disabled)
	t.set_stylebox("focus", name, _focus_style())
	var fc := UI.LIGHT_TITLE
	if kind == "Gold" or kind == "Ghost" or kind == "Choice":
		fc = UI.INK
	elif kind == "GhostDark":
		fc = UI.LIGHT
	var fh := bright(fc, hover_k) if kind != "Choice" else fc
	var fd := dimmed(fc, 0.8, 0.6, 1.0) if kind == "Ability" else (Color(fc, 0.5) if kind == "Choice" else dimmed(fc))
	for k in ["font_color", "font_focus_color"]:
		t.set_color(k, name, fc)
	for k in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(k, name, fh)
	t.set_color("font_disabled_color", name, fd)
	var ic := UI.LIGHT if kind != "Gold" and kind != "Ghost" and kind != "Choice" else UI.INK
	for k in ["icon_normal_color", "icon_focus_color"]:
		t.set_color(k, name, ic)
	for k in ["icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		t.set_color(k, name, bright(ic, hover_k))
	t.set_color("icon_disabled_color", name, dimmed(ic))
	if kind == "Choice":
		t.set_font("font", name, UI.font("alegreya", 500))
	else:
		# `.btn { letter-spacing: 0.03em }`: FontVariation spacing is whole pixels,
		# so it rounds to 1 px for the 19 px big buttons and to none at 12 and 14 px.
		t.set_font("font", name, UI.font("cinzel", 700, false, button_spacing(font_size)))
	t.set_font_size("font_size", name, font_size)
	t.set_constant("h_separation", name, 6)
	t.set_constant("icon_max_width", name, 18)
	t.set_constant("outline_size", name, 0)


## Letter spacing (px per glyph) of a Cinzel button at this size: CSS 0.03em, rounded.
static func button_spacing(font_size: int) -> int:
	return roundi(0.03 * font_size)


static func _focus_style() -> StyleBox:
	var f := StyleBoxFlat.new()
	f.draw_center = false
	f.border_color = UI.C("#ffd76a", 0.7)
	f.set_border_width_all(1)
	f.set_corner_radius_all(6)
	f.set_expand_margin_all(2)
	f.anti_aliasing = true
	return f


# ------------------------------------------------------------------ bars

static func _bar_fill(top: String, bottom: String) -> StyleBox:
	var s := PaperStyle.new()
	s.gradient = _grad([[0.0, Color(top)], [1.0, Color(bottom)]])
	s.corner_radius = 2.0
	s.top_line = Color(1, 1, 1, 0.3)
	return s


static func _bar_bg() -> StyleBox:
	var s := PaperStyle.new()
	s.bg_color = Color(30 / 255.0, 18 / 255.0, 8 / 255.0, 0.55)
	s.corner_radius = 2.0
	s.top_line = Color(0, 0, 0, 0.35)
	return s


# ------------------------------------------------------------------ build

static func build() -> Theme:
	var t := Theme.new()
	t.default_font = UI.font("alegreya", 400)
	t.default_font_size = 16

	# Plain containers draw nothing (CSS divs).
	for type in ["PanelContainer", "Panel", "ScrollContainer"]:
		t.set_stylebox("panel", type, StyleBoxEmpty.new())

	# Text.
	t.set_color("font_color", "Label", UI.INK)
	t.set_constant("line_spacing", "Label", 1)
	t.set_font("font", "Label", UI.font("alegreya", 400))
	t.set_font_size("font_size", "Label", 16)
	_rich_base(t, "RichTextLabel", 16, UI.INK)
	for name in LABELS:
		var d: Array = LABELS[name]
		t.set_type_variation(name, "Label")
		t.set_font("font", name, UI.font(d[0], d[1]))
		t.set_font_size("font_size", name, d[2])
		t.set_color("font_color", name, _col(d[3]))
	for name in RICH:
		var d: Array = RICH[name]
		t.set_type_variation(name, "RichTextLabel")
		_rich_base(t, name, d[0], _col(d[1]))
	# Rich text in Cinzel for titles with mixed sizes.
	t.set_type_variation("TitleText", "RichTextLabel")
	_rich_base(t, "TitleText", 22, UI.INK)
	t.set_font("normal_font", "TitleText", UI.font("cinzel", 700))
	t.set_font("bold_font", "TitleText", UI.font("cinzel", 900))
	t.set_constant("line_separation", "DialogText", 2)
	t.set_constant("line_separation", "ManualText", 2)
	t.set_constant("line_spacing", "LoadingLabel", 0)
	# Large display labels.
	_display(t, "LogoLabel", UI.font("cinzel", 900, false, 17), 104, UI.LIGHT_TITLE, UI.INK, Vector2(0, 4))
	_display(t, "LogoSubLabel", UI.font("cinzel", 400, false, 8), 20, Color("#e9d58f"), Color(0, 0, 0, 0.9), Vector2(0, 2))
	_display(t, "BrandLabel", UI.font("cinzel", 900, false, 2), 20, UI.LIGHT_TITLE, Color(0, 0, 0, 0), Vector2.ZERO)
	_display(t, "BannerLabel", UI.font("cinzel", 900, false, 5), 54, UI.LIGHT_TITLE, UI.INK, Vector2(0, 3))
	_display(t, "BannerSubLabel", UI.font("cinzel", 400), 18, UI.LIGHT, Color(0, 0, 0, 1), Vector2(0, 2))
	t.set_font("font", "PipsLabel", UI.font("alegreya", 400, false, 3))
	t.set_type_variation("TitleLabel", "Label")
	t.set_constant("line_spacing", "TitleLabel", 0)

	# Panels.
	_panel(t, "ParchmentPanel", parchment_style())
	_panel(t, "ParchmentCard", card_style())
	_panel(t, "ParchmentCardHover", card_style(true))
	_panel(t, "ParchmentCardSelected", card_style(false, true))
	_panel(t, "ParchmentCardSelectedHover", card_style(true, true))
	_panel(t, "DarkPanel", dark_style())
	_panel(t, "TopBar", topbar_style())
	_panel(t, "TooltipPanel", tooltip_style())
	_panel(t, "ModalBack", modal_back_style())
	for k in ["", "Red", "Blue", "Gold", "Green"]:
		_panel(t, "Tag" + k, tag_style(k))
	var slot: PaperStyle = _btn_base("Ability")
	_panel(t, "AbilitySlot", slot)
	# Native tooltips.
	t.set_stylebox("panel", "TooltipPanel", tooltip_style())
	t.set_color("font_color", "TooltipLabel", UI.LIGHT)
	t.set_font("font", "TooltipLabel", UI.font("alegreya", 400))
	t.set_font_size("font_size", "TooltipLabel", 14)

	# Buttons.
	for colour in BUTTON_COLOURS:
		for size in BUTTON_SIZES:
			var sz: Array = BUTTON_SIZES[size]
			var name: String = colour + size + "Button"
			var kind: String = "" if colour == "Dark" else colour
			_set_button(t, name, kind, sz[0], sz[1], sz[2])
	_set_button(t, "ButtonActive", "", 14, 14, 8, true)
	_set_button(t, "SmallButtonActive", "", 12, 9, 4, true)
	_set_button(t, "IconButton", "", 12, 8, 6)
	_set_button(t, "IconButtonActive", "", 12, 8, 6, true)
	_set_button(t, "ChoiceButton", "Choice", 16, 14, 10)
	t.set_constant("align_to_largest_stylebox", "ChoiceButton", 0)
	_set_button(t, "AbilityButton", "Ability", 10, 2, 2)
	_set_button(t, "AbilityButtonActive", "Ability", 10, 2, 2, true)
	t.set_constant("icon_max_width", "AbilityButton", 26)
	t.set_constant("icon_max_width", "AbilityButtonActive", 26)

	# Bars.
	t.set_stylebox("background", "ProgressBar", _bar_bg())
	t.set_stylebox("fill", "ProgressBar", _bar_fill("#7fd36f", "#3f9a33"))
	t.set_font_size("font_size", "ProgressBar", 1)
	var bars := {
		"HpBar": ["#7fd36f", "#3f9a33"], "HpLowBar": ["#f0b450", "#c87a20"], "MoraleBar": ["#9ccfff", "#3f7fd0"],
		"FatigueBar": ["#d6b07a", "#9b7440"], "XpBar": ["#ffe08a", "#c99a3c"], "CpBar": ["#8fb0ff", "#2f58b8"],
		"OverBar": ["#ff8a70", "#b02a1e"],
	}
	for name in bars:
		t.set_type_variation(name, "ProgressBar")
		t.set_stylebox("fill", name, _bar_fill(bars[name][0], bars[name][1]))
		t.set_stylebox("background", name, _bar_bg())

	# Scrollbars (`.scroll`: thin, rgba(91,70,48,.5) on transparent).
	for type in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxEmpty.new()
		track.content_margin_left = 4
		track.content_margin_right = 4
		track.content_margin_top = 4
		track.content_margin_bottom = 4
		t.set_stylebox("scroll", type, track)
		t.set_stylebox("scroll_focus", type, track)
		for st in [["grabber", 0.5], ["grabber_highlight", 0.7], ["grabber_pressed", 0.85]]:
			var g := StyleBoxFlat.new()
			g.bg_color = UI.C("#5b4630", st[1])
			g.set_corner_radius_all(4)
			g.anti_aliasing = true
			t.set_stylebox(st[0], type, g)
		for icon in ["increment", "decrement", "increment_highlight", "decrement_highlight", "increment_pressed", "decrement_pressed"]:
			t.set_icon(icon, type, ImageTexture.new())

	# Separators.
	var rule := StyleBoxLine.new()
	rule.color = UI.C("#5b4630", 0.35)
	rule.thickness = 1
	t.set_stylebox("separator", "HSeparator", rule)
	t.set_constant("separation", "HSeparator", 1)
	t.set_type_variation("TitleRule", "HSeparator")
	t.set_stylebox("separator", "TitleRule", rule)
	t.set_type_variation("Rule", "HSeparator")
	t.set_stylebox("separator", "Rule", rule)

	# Text fields.
	var le := StyleBoxFlat.new()
	le.bg_color = Color(1, 248 / 255.0, 228 / 255.0, 0.55)
	le.border_color = UI.C("#5b4630", 0.4)
	le.set_border_width_all(1)
	le.set_corner_radius_all(4)
	_margins(le, 4, 8)
	for st in ["normal", "focus", "read_only"]:
		t.set_stylebox(st, "LineEdit", le)
	t.set_color("font_color", "LineEdit", UI.INK)
	t.set_color("caret_color", "LineEdit", UI.INK)
	t.set_color("selection_color", "LineEdit", UI.C("#c99a3c", 0.45))
	t.set_color("font_selected_color", "LineEdit", UI.INK)
	t.set_color("font_placeholder_color", "LineEdit", UI.INK_FAINT)
	var name_edit := PaperStyle.new()
	name_edit.dash_bottom = UI.C("#5b4630", 0.4)
	_margins(name_edit, 1, 1)
	t.set_type_variation("NameEdit", "LineEdit")
	for st in ["normal", "focus", "read_only"]:
		t.set_stylebox(st, "NameEdit", name_edit)
	t.set_font("font", "NameEdit", UI.font("cinzel", 700))
	t.set_font_size("font_size", "NameEdit", 24)

	# Colours the widgets read.
	t.set_color("font_color", "MenPips", UI.INK)
	t.set_color("tint", "Icon", UI.INK)
	return t


static func _rich_base(t: Theme, name: String, size: int, colour: Color) -> void:
	t.set_color("default_color", name, colour)
	t.set_font("normal_font", name, UI.font("alegreya", 400))
	t.set_font("bold_font", name, UI.font("alegreya", 700))
	t.set_font("italics_font", name, UI.font("alegreya", 400, true))
	t.set_font("bold_italics_font", name, UI.font("alegreya", 700))
	t.set_font("mono_font", name, UI.font("sans", 400))
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		t.set_font_size(k, name, size)
	t.set_constant("line_separation", name, 1)
	t.set_stylebox("normal", name, StyleBoxEmpty.new())
	t.set_stylebox("focus", name, StyleBoxEmpty.new())


static func _display(t: Theme, name: String, f: Font, size: int, colour: Color, shadow: Color, off: Vector2) -> void:
	t.set_type_variation(name, "Label")
	t.set_font("font", name, f)
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, colour)
	t.set_color("font_shadow_color", name, shadow)
	t.set_constant("shadow_offset_x", name, int(off.x))
	t.set_constant("shadow_offset_y", name, int(off.y))
	t.set_constant("line_spacing", name, 0)


static func _panel(t: Theme, name: String, sb: StyleBox) -> void:
	t.set_type_variation(name, "PanelContainer")
	t.set_stylebox("panel", name, sb)


## The sub-theme of `.panel.dark` (and the top bar): light text colours, dark tags,
## light ghost buttons, gold title rule.
static func build_dark() -> Theme:
	var t := Theme.new()
	var root := theme()
	t.set_color("font_color", "Label", UI.LIGHT)
	t.set_color("default_color", "RichTextLabel", UI.LIGHT)
	for name in LABELS:
		var d: Array = LABELS[name]
		t.set_type_variation(name, "Label")
		t.set_color("font_color", name, _col(d[4]))
	for name in ["LogoLabel", "LogoSubLabel", "BrandLabel", "BannerLabel", "BannerSubLabel"]:
		t.set_type_variation(name, "Label")
		t.set_color("font_color", name, root.get_color("font_color", name))
	for name in RICH:
		var d: Array = RICH[name]
		t.set_type_variation(name, "RichTextLabel")
		t.set_color("default_color", name, _col(d[2]))
	t.set_type_variation("TitleText", "RichTextLabel")
	t.set_color("default_color", "TitleText", UI.LIGHT_TITLE)
	for k in ["", "Red", "Blue", "Gold", "Green"]:
		t.set_type_variation("Tag" + k, "PanelContainer")
		t.set_stylebox("panel", "Tag" + k, tag_style(k, true))
	for size in BUTTON_SIZES:
		var sz: Array = BUTTON_SIZES[size]
		_set_button(t, "Ghost" + size + "Button", "GhostDark", sz[0], sz[1], sz[2])
	var rule := StyleBoxLine.new()
	rule.color = UI.C("#c99a3c", 0.35)
	rule.thickness = 1
	t.set_type_variation("TitleRule", "HSeparator")
	t.set_stylebox("separator", "TitleRule", rule)
	t.set_color("font_color", "MenPips", Color("#e9d8ae"))
	t.set_color("tint", "Icon", UI.LIGHT)
	return t


## Writes the theme to assets/ui/theme.tres (for the project setting gui/theme/custom).
static func save() -> int:
	return ResourceSaver.save(theme(), SAVE_PATH)
