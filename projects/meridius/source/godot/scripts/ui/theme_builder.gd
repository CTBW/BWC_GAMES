## Builds the Nordmark interface: vellum, blue cloth, iron and brass fittings.
## Retains the original stylesheet's semantic variation names for game screens.
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
##   ParchmentPanel          warm vellum, 11 px iron/brass binding, corner fittings.
##                           Dark ink, inward shading, drop shadow. Padding 25/28.
##   ParchmentCard           light inset card inside parchment, padding 9/10.
##   ParchmentCardHover      `.card.clickable:hover`.
##   ParchmentCardSelected   `.card.sel` gold border + ring.  ParchmentCardSelectedHover.
##   DarkPanel               charcoal-blue textured surface, 6 px metal rim; padding 14/18.
##                           Give it the light-text sub-theme with UI.dark(panel).
##   BannerPanel             blue heading band with a 5 px metal rim and light text.
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
## HSlider                 the pause menu's volumes: the bars' sunk track, a gold fill
##                          (the XP bar's) up to a round brass knob (Godot addition)
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
const ForgedStyle = preload("res://scripts/ui/styles/forged_style.gd")

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

## Warm vellum held in an iron binding, with brass inlay at fixed pixel sizes.
static func parchment_style() -> StyleBox:
	var s := ForgedStyle.new()
	s.artwork = 1
	s.bg_color = Color("#cfc2a0")
	s.gradient = _grad([[0.0, Color("#e2d7b9")], [0.5, Color("#d7caa8")], [1.0, Color("#bca981")]])
	s.gradient_angle = 160.0
	s.layers = [paper_texture(), blotch_texture()]
	s.corner_radius = 2.0
	s.metal_width = 11.0
	s.metal_color = Color("#b49c68")
	s.ornament = 2
	s.glow_size = 42.0
	s.glow_color = Color(0.18, 0.12, 0.06, 0.65)
	s.shadow_color = Color(0, 0, 0, 0.7)
	s.shadow_offset = Vector2(0, 9)
	s.shadow_blur = 20.0
	return _margins(s, 25, 28)


## Charcoal leather and blue-black steel: the common command surface.
static func dark_style() -> StyleBox:
	var s := ForgedStyle.new()
	s.artwork = 2
	s.bg_color = Color("#111a20")
	s.gradient = _grad([[0.0, Color("#293238")], [0.48, Color("#172127")], [1.0, Color("#0c141b")]])
	s.layers = [paper_texture()]
	s.corner_radius = 2.0
	s.metal_width = 6.0
	s.metal_color = Color("#9d8c65")
	s.ornament = 1
	s.glow_size = 26.0
	s.glow_color = Color(0, 0, 0, 0.7)
	s.shadow_color = Color(0, 0, 0, 0.6)
	s.shadow_offset = Vector2(0, 5)
	s.shadow_blur = 12.0
	return _margins(s, 14, 18)


static func banner_style() -> StyleBox:
	var s: ForgedStyle = dark_style()
	s.artwork = 3
	s.gradient = _grad([[0.0, Color("#344a5a")], [0.4, Color("#253b4c")], [1.0, Color("#152635")]])
	s.metal_width = 5
	s.ornament = 1
	s.shadow_blur = 4
	return _margins(s, 14, 66)


static func card_style(hover := false, sel := false) -> StyleBox:
	var s := PaperStyle.new()
	s.bg_color = Color("#ede1c2") if hover else Color(0.94, 0.89, 0.75, 0.48)
	s.corner_radius = 1.0
	_border(s, 1.0)
	s.border_color = Color("#91784b") if sel else UI.C("#55452f", 0.55)
	s.top_line = Color(1.0, 0.97, 0.81, 0.5)
	s.bottom_line = UI.C("#423826", 0.16)
	s.glow_size = 16.0
	s.glow_color = UI.C("#695536", 0.22)
	if sel:
		s.outer_ring_width = 2.0
		s.outer_ring_color = UI.C("#a88039", 0.85)
		s.bg_color = Color("#e8d6a7")
	return _margins(s, 9, 10)


static func topbar_style() -> StyleBox:
	var s: ForgedStyle = dark_style()
	s.gradient = _grad([[0.0, Color("#333a3d")], [0.15, Color("#202c33")], [1.0, Color("#10191f")]])
	s.metal_width = 5.0
	s.ornament = 0
	s.shadow_blur = 8.0
	return _margins(s, 4, 18)


static func tooltip_style() -> StyleBox:
	var s: ForgedStyle = dark_style()
	s.metal_width = 4.0
	s.ornament = 0
	return _margins(s, 10, 12)


static func modal_back_style() -> StyleBox:
	var g := _grad([[0.0, Color(0.025, 0.04, 0.055, 0.5)], [1.0, Color(0.015, 0.025, 0.04, 0.82)]])
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
		match kind:
			"Blue":
				bg = UI.C("#4c7fa6", 0.28)
				bd = UI.C("#87b8d4", 0.62)
			"Red":
				bg = UI.C("#a04a40", 0.26)
				bd = UI.C("#d49279", 0.62)
			"Gold":
				bg = UI.C("#c6a05b", 0.22)
				bd = UI.C("#ddbd79", 0.62)
			"Green":
				bg = UI.C("#527a4a", 0.25)
				bd = UI.C("#9fbd82", 0.62)
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
	s.set_corner_radius_all(1)
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
	if s is ForgedStyle:
		(o as ForgedStyle).metal_color = f.call((s as ForgedStyle).metal_color)
		(o as ForgedStyle).accent = f.call((s as ForgedStyle).accent)
		(o as ForgedStyle).art_tint = f.call((s as ForgedStyle).art_tint)
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
	# Ghost and event choices remain quiet; command buttons are inset enamel.
	if kind in ["Ghost", "GhostDark", "Choice"]:
		var quiet := PaperStyle.new()
		quiet.corner_radius = 1
		_border(quiet, 1)
		quiet.bg_color = UI.C("#101c26", 0.25) if kind == "GhostDark" else UI.C("#68583c", 0.08)
		quiet.border_color = UI.C("#b7a478", 0.45) if kind == "GhostDark" else UI.C("#625033", 0.48)
		return quiet
	var s := ForgedStyle.new()
	s.artwork = 4
	s.corner_radius = 2.0
	s.metal_width = 4.0
	s.metal_color = Color("#9a8b6c")
	s.ornament = 0
	s.shadow_color = Color(0, 0, 0, 0.6)
	s.shadow_offset = Vector2(0, 3)
	s.shadow_blur = 3.0
	s.glow_size = 12
	s.glow_color = Color(0, 0, 0, 0.45)
	s.layers = [paper_texture()]
	match kind:
		"Red":
			s.gradient = _grad([[0.0, Color("#873e37")], [0.35, Color("#682b28")], [1.0, Color("#34181c")]])
			s.metal_color = Color("#b79a6b")
		"Blue":
			s.gradient = _grad([[0.0, Color("#4a667b")], [0.38, Color("#304e65")], [1.0, Color("#152a3b")]])
		"Gold":
			s.gradient = _grad([[0.0, Color("#dfc48a")], [0.4, Color("#bfa16a")], [1.0, Color("#8b7045")]])
			s.metal_color = Color("#b3a076")
		"Ability":
			s.gradient = _grad([[0.0, Color("#36424a")], [1.0, Color("#111c24")]])
			s.metal_color = Color("#8d9291")
		_:
			s.gradient = _grad([[0.0, Color("#4b4f4c")], [0.4, Color("#2c363a")], [1.0, Color("#17232b")]])
	return s


static func _active(s: PaperStyle) -> PaperStyle:
	# `.btn.active`: inset 0 0 0 2px gold-bright, 0 0 12px rgba(255,215,106,.5) (replaces the base shadows).
	var o: PaperStyle = s.duplicate()
	o.rings = [[2.0, UI.GOLD_BRIGHT]]
	if o is ForgedStyle:
		(o as ForgedStyle).metal_color = UI.GOLD_BRIGHT
	o.top_line = Color(0, 0, 0, 0)
	o.shadow_color = Color(0, 0, 0, 0)
	o.outer_glow_size = 12.0
	o.outer_glow_color = Color(1.0, 215 / 255.0, 106 / 255.0, 0.5)
	return o


static func _set_button(t: Theme, name: String, kind: String, font_size: int, pad_h: float, pad_v: float, active := false) -> void:
	var base := _btn_base(kind)
	if base is ForgedStyle and font_size < 19:
		(base as ForgedStyle).artwork = 0
	if base is ForgedStyle and font_size >= 19:
		(base as ForgedStyle).ornament = 1
		(base as ForgedStyle).metal_width = 5
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
	f.set_corner_radius_all(1)
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


## The slider knob: a 16 px brass disc with a dark wood rim, lighter on hover.
static func knob_texture(hover: bool) -> Texture2D:
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var top := Color("#fff0b0") if hover else Color("#ffd76a")
	var bottom := Color("#d9aa4c") if hover else Color("#a37a2a")
	var rim := Color("#3a2414")
	var c := (n - 1) / 2.0
	for y in n:
		for x in n:
			var d := Vector2(x - c, y - c).length()
			# Anti-aliased edge of a 7 px disc with a 1.4 px rim.
			var a := clampf(7.5 - d, 0.0, 1.0)
			if a <= 0.0:
				continue
			var body := top.lerp(bottom, float(y) / (n - 1))
			var col := rim.lerp(body, clampf(6.1 - d, 0.0, 1.0))
			col.a = a
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


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
	_panel(t, "BannerPanel", banner_style())
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

	# Sliders (Godot addition: the sound volumes): the bars' sunk track and gold fill, a brass knob.
	var track := _bar_bg()
	_margins(track, 3, 0)
	t.set_stylebox("slider", "HSlider", track)
	var fill := _bar_fill("#ffe08a", "#c99a3c")
	_margins(fill, 3, 0)
	t.set_stylebox("grabber_area", "HSlider", fill)
	var fill_hi := _bar_fill("#fff0b0", "#d9aa4c")
	_margins(fill_hi, 3, 0)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)
	t.set_icon("grabber", "HSlider", knob_texture(false))
	t.set_icon("grabber_highlight", "HSlider", knob_texture(true))
	t.set_icon("grabber_disabled", "HSlider", knob_texture(false))
	t.set_constant("center_grabber", "HSlider", 0)

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
