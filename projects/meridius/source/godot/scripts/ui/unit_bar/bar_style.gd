## The unit bar's materials and drawing helpers (scripts/ui/unit_bar): the
## console's stone, the brass of its sockets, the near-black windows and the
## outlined numbers every piece shares, so the bar reads as one carved console.
## Colours keep the theme's meanings (UI.GOLD brass, UI.HP health, UI.MORALE
## morale, blue company and red warband).
##
##   const Style = preload("res://scripts/ui/unit_bar/bar_style.gd")
##   Style.number("184 / 192", 22, Style.HP_HIGH)   outlined Cinzel numbers
##   Style.socket(ci, rect, lit)                     a gold-framed recessed socket
##   Style.chip("Can move", Style.MORALE)            a small enamelled tag (null colour: spent)
## The draw helpers take the CanvasItem whose _draw (or draw signal) is running.
extends RefCounted

const UI = preload("res://scripts/ui/ui.gd")

# Stone: warm lit faces, cool shadows, as the battlefield's farmhouses.
const STONE_LIGHT := Color("#d6c9ab")
const STONE := Color("#a69a84")
const STONE_DARK := Color("#5f5d68")
const MORTAR := Color("#352f2b")
const MOSS := Color("#78953a")
const MOSS_DARK := Color("#3f5a1f")
## The ink round every carved shape (the cel outline).
const INK := Color("#140e0a")

const BRASS := Color("#c99a3c")
const BRASS_LIGHT := Color("#ffd76a")
const BRASS_DARK := Color("#6f5020")
const LAPIS := Color("#2f58b8")
const LAPIS_LIGHT := Color("#8fb6ff")

## The recessed windows' floor and the sockets in it.
const WELL := Color("#0a0d11")
const WELL_2 := Color("#141a21")
const SOCKET := Color("#1b2129")

const TEXT := Color("#f6e7c2")
const MUTED := Color("#b8a27c")
const HP_HIGH := Color("#62d64f")
const HP_MID := Color("#f0c63a")
const HP_LOW := Color("#ee4a38")
const MORALE := Color("#6fb3ff")
const BUFF := Color("#62cf4c")
const DEBUFF := Color("#e8553f")
const STATE := Color("#e2b85a")
const PLAYER := Color("#2f58b8")
const ENEMY := Color("#b02a1e")

const RARITY := {"common": Color("#b9b2a2"), "uncommon": Color("#62cf4c"), "rare": Color("#5a9cff"),
	"epic": Color("#b26cff"), "legendary": Color("#ff9a2e")}

const SOUNDS := {
	"open": ["ui_bar_open", "page"], "close": ["ui_bar_close", "page"], "swap": ["ui_unit_swap", "click"],
	"hover": ["ui_hover"], "ability_hover": ["ui_ability_hover"], "low_hp": ["ui_low_hp"],
	"command": ["ui_command", "click"], "deny": ["deny"],
}


## Green over half, yellow over a quarter, red below (Warcraft's health numbers).
static func hp_color(f: float) -> Color:
	if f > 0.5:
		return HP_MID.lerp(HP_HIGH, clampf((f - 0.5) / 0.2, 0.0, 1.0))
	return HP_LOW.lerp(HP_MID, clampf((f - 0.25) / 0.15, 0.0, 1.0))


## Large outlined numbers or words: Cinzel with a thick ink outline and a drop shadow.
static func number(text: String, size := 20, color := TEXT, weight := 700) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UI.font("cinzel", weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	outline(l, maxi(4, size / 4))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Body text in the game's Alegreya with the bar's outline.
static func text(t: String, size := 14, color := TEXT, family := "alegreya", weight := 400) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", UI.font(family, weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	outline(l, 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A small enamelled tag on the dark stone: the colour's enamel, edged in it,
## the words light; spent (no colour) it is grey and dim.
static func chip(t: String, col: Variant = null) -> PanelContainer:
	var lit: bool = col is Color
	var c: Color = col if lit else MUTED.darkened(0.35)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(c.darkened(0.62), 0.92) if lit else Color(SOCKET, 0.85)
	sb.border_color = c.darkened(0.1) if lit else c.darkened(0.3)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(text(t, 11, c.lightened(0.55) if lit else c, "cinzel", 700))
	return p


static func outline(l: Label, w: int) -> void:
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", w)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)


# --- Shapes --------------------------------------------------------------------------------

## A recessed socket: ink seam, a brass rim lit from the top left, a dark well
## inside. `lit` (0..1) warms the rim (hover, selection). `rim` is the brass width.
static func socket(ci: CanvasItem, r: Rect2, lit := 0.0, rim := 3.0, fill := SOCKET, tint := BRASS) -> void:
	ci.draw_rect(r.grow(1.0), INK)
	var brass := tint.lerp(BRASS_LIGHT, lit * 0.7)
	bevel(ci, r, rim, brass.lightened(0.25), brass.darkened(0.45), brass)
	var inner := r.grow(-rim)
	ci.draw_rect(inner, INK)
	ci.draw_rect(inner.grow(-1.0), fill)
	# The well's own shadow under its top edge.
	ci.draw_rect(Rect2(inner.position + Vector2(1, 1), Vector2(inner.size.x - 2, minf(5.0, inner.size.y * 0.2))), Color(0, 0, 0, 0.35))


## A bevelled band `w` wide inside `r`: `light` on the top and left, `dark` on
## the bottom and right, `mid` along the middle (a raised rim).
static func bevel(ci: CanvasItem, r: Rect2, w: float, light: Color, dark: Color, mid: Color) -> void:
	var a := r.position
	var b := r.end
	var ia := a + Vector2(w, w)
	var ib := b - Vector2(w, w)
	ci.draw_colored_polygon(PackedVector2Array([a, Vector2(b.x, a.y), Vector2(ib.x, ia.y), ia]), light)
	ci.draw_colored_polygon(PackedVector2Array([a, ia, Vector2(ia.x, ib.y), Vector2(a.x, b.y)]), light.lerp(mid, 0.4))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(a.x, b.y), Vector2(ia.x, ib.y), ib, b]), dark)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(b.x, a.y), b, ib, Vector2(ib.x, ia.y)]), dark.lerp(mid, 0.3))
	if w >= 3.0:
		var m := w * 0.5
		ci.draw_rect(Rect2(a + Vector2(m, m), r.size - Vector2(w, w)), Color(mid, 0.55), false, 1.0)


## A cut gem with a brass bezel and a glint (`glint` 0..1 brightens it).
static func gem(ci: CanvasItem, c: Vector2, rad: float, col := LAPIS, glint := 0.0) -> void:
	ci.draw_circle(c, rad + 2.5, INK)
	ci.draw_circle(c, rad + 1.5, BRASS_DARK)
	ci.draw_circle(c - Vector2(0.4, 0.4), rad + 0.6, BRASS)
	ci.draw_circle(c, rad - 0.4, col.darkened(0.35))
	ci.draw_circle(c - Vector2(rad * 0.15, rad * 0.15), rad * 0.72, col.lerp(Color.WHITE, 0.1 + glint * 0.5))
	ci.draw_circle(c - Vector2(rad * 0.35, rad * 0.38), rad * 0.26, Color(1, 1, 1, 0.75 + glint * 0.25))
	if glint > 0.05:
		var s := rad * (1.2 + glint * 1.8)
		var w := Color(1, 1, 0.9, glint)
		ci.draw_line(c - Vector2(s, 0), c + Vector2(s, 0), w, 1.5, true)
		ci.draw_line(c - Vector2(0, s), c + Vector2(0, s), w, 1.5, true)


static func rivet(ci: CanvasItem, c: Vector2, rad := 2.6) -> void:
	ci.draw_circle(c + Vector2(0, 1), rad + 1.0, INK)
	ci.draw_circle(c, rad, BRASS_DARK)
	ci.draw_circle(c - Vector2(0.5, 0.6), rad * 0.7, BRASS)
	ci.draw_circle(c - Vector2(0.9, 1.0), rad * 0.3, Color("#fff2c4"))


## A filled pie from the top, clockwise over `f` (0..1) of a turn: the cooldown sweep.
static func pie(ci: CanvasItem, c: Vector2, rad: float, f: float, col: Color) -> void:
	if f <= 0.0:
		return
	var pts := PackedVector2Array([c])
	var n := maxi(3, int(48 * f))
	for i in n + 1:
		var a := -PI * 0.5 + TAU * f * float(i) / n
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	ci.draw_colored_polygon(pts, col)


## A ribbon with notched swallow-tail ends, filled `col`, edged in ink and brass.
static func ribbon(ci: CanvasItem, r: Rect2, col: Color, notch := 9.0) -> void:
	var a := r.position
	var b := r.end
	var my := r.get_center().y
	var pts := PackedVector2Array([a, Vector2(b.x, a.y), Vector2(b.x - notch, my), b, Vector2(a.x, b.y), Vector2(a.x + notch, my)])
	var outer := PackedVector2Array()
	for p in pts:
		outer.append(p)
	ci.draw_colored_polygon(pts, col)
	ci.draw_colored_polygon(PackedVector2Array([a + Vector2(2, 2), Vector2(b.x - 2, a.y + 2), Vector2(b.x - 4, a.y + 6),
		a + Vector2(4, 6)]), Color(1, 1, 1, 0.16))
	ci.draw_line(Vector2(a.x + notch * 0.6, b.y - 3), Vector2(b.x - notch * 0.6, b.y - 3), Color(0, 0, 0, 0.25), 2.0)
	outer.append(a)
	ci.draw_polyline(outer, INK, 2.5, true)
	ci.draw_line(Vector2(a.x + 6, a.y + 3.5), Vector2(b.x - 6, a.y + 3.5), Color(BRASS_LIGHT, 0.6), 1.0)
	ci.draw_line(Vector2(a.x + 6, b.y - 1.5), Vector2(b.x - 6, b.y - 1.5), Color(BRASS, 0.5), 1.0)


## Shared shaders for the bar's pieces: an icon greyed when unusable, flashed
## white when struck (`flash`), brightened along a passing band (`sweep`).
const ICON_SHADER := """
shader_type canvas_item;
uniform float gray = 0.0;
uniform float flash = 0.0;
uniform float sweep = -1.0;
uniform float bright = 1.0;
void fragment() {
	// COLOR comes in as the texture times the vertex colour (and modulate).
	vec4 c = COLOR;
	float l = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	c.rgb = mix(c.rgb, vec3(l * 0.75), gray);
	c.rgb *= bright;
	c.rgb = mix(c.rgb, vec3(1.0), flash);
	if (sweep > -0.5) {
		float d = (UV.x + UV.y * 0.6) - sweep * 2.2 + 0.3;
		c.rgb += vec3(1.0, 0.95, 0.75) * smoothstep(0.18, 0.0, abs(d)) * 0.55;
	}
	COLOR = c;
}
"""

static var _icon_shader: Shader


static func icon_material() -> ShaderMaterial:
	if _icon_shader == null:
		_icon_shader = Shader.new()
		_icon_shader.code = ICON_SHADER
	var m := ShaderMaterial.new()
	m.shader = _icon_shader
	return m


## Plays a bar sound by its role (SOUNDS): the first of its events the bank can
## play; nothing while the Sfx autoload is absent (tests) or none is recorded.
static func sound(node: Node, role: String, opts: Dictionary = {}) -> void:
	if node == null or not node.is_inside_tree():
		return
	var sfx := node.get_tree().root.get_node_or_null("Sfx")
	if sfx == null or not sfx.has_method("first_event"):
		return
	var ev: String = sfx.first_event(SOUNDS.get(role, [role]))
	if ev != "":
		sfx.play(ev, opts)
