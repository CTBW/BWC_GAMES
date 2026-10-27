## The unit bar's console: one carved slab of masonry at the bottom of the
## screen (the Warcraft III console's build, in the battlefield's own stone): a
## riveted brass rail along its top edge, and dark recessed windows cut into
## the wall for the bar's sections. It casts a shadow on the field round it.
## Placeholder art: the stone is a shader (bricks in screen pixels, so the wall
## tiles to any width without stretching), the windows use the painted command
## panel (assets/ui/epic/command-panel.png). The art to replace it is listed in
## references/ui/unit_bar_asset_list.md.
##
##   var c = preload("res://scripts/ui/unit_bar/console_frame.gd").new()
##   c.windows = {"minimap": 232, "portrait": 188, "middle": -1, ...}   widths in order, -1 flexible
##   c.window_rect("portrait") -> Rect2    in the console's own coordinates
##   c.natural_width() -> float            its windows and the stone round them
##   c.tint = Color(...)                    the stone's cast (biome or faction later)
##   c.laid_out                             signal: the windows have moved (after a resize;
##                                          `resized` comes before them)
## Coordinates: y = 0 is the top of the rail. The console's height is HEIGHT.
extends Control

const Style = preload("res://scripts/ui/unit_bar/bar_style.gd")
const Painted = preload("res://scripts/ui/styles/painted_frames.gd")

signal laid_out

const HEIGHT := 216.0
const RAIL_H := 9.0
## Where the windows start and stop, from the top of the rail and the bottom.
const WINDOW_TOP := RAIL_H + 12.0
const WINDOW_BOTTOM := 12.0
## Stone between the slab's ends and the windows, and between windows.
const EDGE := 14.0
const GAP := 14.0
## The recess cut round a window (the carved chamfer).
const CHAMFER := 9.0

const STONE_SHADER := """
shader_type canvas_item;
// The wall: bricks in running bond, in the console's own pixels.
uniform vec4 light : source_color = vec4(0.84, 0.79, 0.67, 1.0);
uniform vec4 mid : source_color = vec4(0.65, 0.6, 0.52, 1.0);
uniform vec4 dark : source_color = vec4(0.37, 0.36, 0.41, 1.0);
uniform vec4 mortar : source_color = vec4(0.21, 0.18, 0.17, 1.0);
uniform vec4 moss : source_color = vec4(0.47, 0.58, 0.23, 1.0);
uniform vec4 tint : source_color = vec4(1.0);
uniform float height = 270.0;
varying vec2 p;

float h21(vec2 q) { return fract(sin(dot(q, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 x) {
	vec2 i = floor(x); vec2 f = fract(x);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y);
}

void vertex() { p = VERTEX; }

void fragment() {
	vec2 bs = vec2(54.0, 25.0);
	float row = floor(p.y / bs.y);
	// The courses' joints wander a little.
	float u = p.x / bs.x + mod(row, 2.0) * 0.5 + h21(vec2(row, 3.0)) * 0.18;
	vec2 cell = vec2(floor(u), row);
	vec2 px = vec2(fract(u), fract(p.y / bs.y)) * bs;
	float r = h21(cell);
	float m = 1.6;
	float dx = min(px.x, bs.x - px.x) - m;
	float dy = min(px.y, bs.y - px.y) - m;
	// Chipped corners: some bricks lose a bite of a corner.
	vec2 cd = vec2(min(px.x, bs.x - px.x), min(px.y, bs.y - px.y));
	float chip = step(0.55, h21(cell + 9.1)) * (3.0 + 6.0 * h21(cell + 4.4));
	float corner = cd.x + cd.y - chip;
	float edge = min(min(dx, dy), corner * 0.7);
	float mor = 1.0 - smoothstep(0.0, 1.2, edge);
	// The brick's face: its own shade, grain, and a bevel lit from the top left.
	vec3 base = mix(mid.rgb, light.rgb, 0.25 + r * 0.45);
	base = mix(base, dark.rgb, step(0.86, h21(cell + 2.3)) * 0.35);
	float n = vnoise(p * 0.11) * 0.5 + vnoise(p * 0.37 + r * 9.0) * 0.32 + vnoise(p * 1.3) * 0.18;
	base *= 0.86 + 0.26 * n;
	float top = 1.0 - smoothstep(0.0, 4.5, min(px.y - m, corner));
	float left = 1.0 - smoothstep(0.0, 3.5, px.x - m);
	float bottom = 1.0 - smoothstep(0.0, 5.0, bs.y - px.y - m);
	float right = 1.0 - smoothstep(0.0, 4.0, bs.x - px.x - m);
	base = mix(base, light.rgb * 1.12, max(top, left * 0.6) * 0.55);
	base = mix(base, dark.rgb * 0.8, max(bottom, right * 0.7) * 0.6);
	// A hairline crack across a few bricks.
	float crack = step(0.9, h21(cell + 6.6)) * (1.0 - smoothstep(0.0, 0.9,
		abs(px.y - bs.y * (0.3 + 0.4 * h21(cell + 1.7)) - (px.x - bs.x * 0.5) * (h21(cell + 8.2) - 0.5) - sin(px.x * 0.6) * 1.2)));
	crack *= step(bs.x * 0.2, px.x) * step(px.x, bs.x * 0.8);
	base = mix(base, mortar.rgb, crack * 0.85);
	// Moss in the joints and on the tops of a few bricks.
	float mo = step(0.8, h21(cell + 7.7)) * smoothstep(0.45, 0.8, vnoise(p * 0.2)) * (1.0 - smoothstep(0.0, bs.y * 0.55, px.y));
	base = mix(base, moss.rgb * (0.85 + 0.3 * vnoise(p * 0.9)), mo * 0.85);
	vec3 col = mix(base, mortar.rgb * (0.8 + 0.4 * vnoise(p * 0.5)), mor);
	float mm = (1.0 - smoothstep(0.0, 2.5, abs(edge))) * smoothstep(0.55, 0.75, vnoise(p * 0.15 + 3.0));
	col = mix(col, moss.rgb * 0.7, mm * 0.6);
	// The sun from above: the wall darkens toward the screen's edge.
	col *= mix(1.04, 0.72, clamp(p.y / height, 0.0, 1.0));
	COLOR = vec4(col * tint.rgb, 1.0);
}
"""

static var _shader: Shader

## Window widths in order from the left; -1 takes what is left (one only).
var windows := {"minimap": 232.0, "buttons": 44.0, "portrait": 188.0, "middle": -1.0, "inventory": 160.0, "command": 296.0}:
	set(v):
		windows = v
		_layout()
## Windows drawn as plain stone (the minimap's button column).
var open_stone := ["buttons"]
## Windows without the painted frame drawn in them (their piece draws its own).
var unframed := ["portrait"]
var tint := Color.WHITE:
	set(v):
		tint = v
		if _stone and _stone.material:
			(_stone.material as ShaderMaterial).set_shader_parameter("tint", v)
## The enemy's cast on the brass and the window frames (red for a foe).
var accent := Color.WHITE:
	set(v):
		accent = v
		if _carve:
			_carve.queue_redraw()

var _rects := {}
var _stone: Control
var _carve: Control


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = HEIGHT
	_build()


## Its pieces, made with it (it works before it is in the tree, as in the headless tests).
func _build() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = STONE_SHADER
	_stone = Control.new()
	_stone.name = "Stone"
	_stone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stone.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("height", HEIGHT)
	mat.set_shader_parameter("light", Style.STONE_LIGHT)
	mat.set_shader_parameter("mid", Style.STONE)
	mat.set_shader_parameter("dark", Style.STONE_DARK)
	mat.set_shader_parameter("mortar", Style.MORTAR)
	mat.set_shader_parameter("moss", Style.MOSS)
	mat.set_shader_parameter("tint", tint)
	_stone.material = mat
	_stone.draw.connect(_draw_stone)
	add_child(_stone)
	_carve = Control.new()
	_carve.name = "Carving"
	_carve.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_carve.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_carve.draw.connect(_draw_carving)
	add_child(_carve)
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func window_rect(id: String) -> Rect2:
	return _rects.get(id, Rect2())


## The slab's width for its windows (a flexible one at its least).
func natural_width() -> float:
	var w := 2.0 * EDGE + GAP * (windows.size() - 1)
	for k in windows:
		w += windows[k] if windows[k] >= 0.0 else 120.0
	return w


## The windows' rects for the console's width.
func _layout() -> void:
	var fixed := 0.0
	var n := windows.size()
	for k in windows:
		if windows[k] >= 0.0:
			fixed += windows[k]
	var flex := maxf(120.0, size.x - 2.0 * EDGE - fixed - GAP * (n - 1))
	var x := EDGE
	_rects.clear()
	for k in windows:
		var w: float = windows[k] if windows[k] >= 0.0 else flex
		_rects[k] = Rect2(x, WINDOW_TOP, w, HEIGHT - WINDOW_TOP - WINDOW_BOTTOM)
		x += w + GAP
	if _stone:
		_stone.queue_redraw()
		_carve.queue_redraw()
	laid_out.emit()


# --- The stone -----------------------------------------------------------------------------

## The wall, to the screen's bottom edge and a little past it (the rise's overshoot).
func _draw_stone() -> void:
	_stone.draw_rect(Rect2(0, 0, size.x, HEIGHT + 8), Color.WHITE)


# --- The carving over the stone: outlines, rail, recesses ---------------------------------

func _draw_carving() -> void:
	var c := _carve
	var w := size.x
	var ink := Style.INK
	var bottom := HEIGHT + 8.0
	# The slab's shadow on the field: above it, at its ends, the corners between.
	var o := Color(0, 0, 0, 0)
	var sh := Color(0, 0, 0, 0.45)
	var s := 12.0
	_fade(c, [Vector2(0, -s), Vector2(w, -s), Vector2(w, 0), Vector2(0, 0)], [o, o, sh, sh])
	_fade(c, [Vector2(-s, 0), Vector2(0, 0), Vector2(0, bottom), Vector2(-s, bottom)], [o, sh, sh, o])
	_fade(c, [Vector2(w, 0), Vector2(w + s, 0), Vector2(w + s, bottom), Vector2(w, bottom)], [sh, o, o, sh])
	_fade(c, [Vector2(-s, -s), Vector2(0, -s), Vector2(0, 0), Vector2(-s, 0)], [o, o, sh, o])
	_fade(c, [Vector2(w, -s), Vector2(w + s, -s), Vector2(w + s, 0), Vector2(w, 0)], [o, o, o, sh])
	# Its ends: lit on the left, shadowed on the right, inked.
	c.draw_rect(Rect2(1.5, RAIL_H + 1.5, 3, bottom), Color(1, 1, 1, 0.14))
	c.draw_rect(Rect2(w - 4.5, RAIL_H + 1.5, 3, bottom), Color(0, 0, 0, 0.3))
	for x in [0.0, w]:
		c.draw_line(Vector2(x, 0), Vector2(x, bottom), ink, 3.0)
	# The brass rail along the wall's top, riveted, and its shadow on the wall.
	c.draw_rect(Rect2(0, RAIL_H, w, 6), Color(0, 0, 0, 0.3))
	var rail := Rect2(0, 0, w, RAIL_H)
	var brass := Style.BRASS * accent
	c.draw_rect(rail.grow(1.5), ink)
	Style.bevel(c, rail, 3.0, brass.lightened(0.3), brass.darkened(0.5), brass)
	var rx := 40.0
	while rx < w - 30.0:
		Style.rivet(c, Vector2(rx, RAIL_H * 0.5), 2.2)
		rx += 96.0
	# The recesses and the windows set in them.
	for k in _rects:
		var r: Rect2 = _rects[k]
		if open_stone.has(k):
			continue
		_recess(c, r)
		if not unframed.has(k):
			_window(c, r)


## The chamfer cut round a window: shadowed on the top and left inner faces,
## lit on the bottom and right (light from the top left), inked.
func _recess(c: Control, r: Rect2) -> void:
	var o := r.grow(CHAMFER)
	Style.bevel(c, o, CHAMFER, Color(0.12, 0.1, 0.1, 0.78), Color(0.95, 0.88, 0.72, 0.42), Color(0.3, 0.27, 0.25, 0.6))
	c.draw_rect(o, Style.INK, false, 3.0)


## The window's dark floor in the painted command-panel frame (brass corners).
func _window(c: Control, r: Rect2) -> void:
	c.draw_rect(r, Style.WELL)
	Painted.draw_frame(c.get_canvas_item(), r.grow(2.0), 2, 0.55, accent)
	c.draw_rect(r, Style.INK, false, 2.0)


func _fade(c: Control, pts: Array, cols: Array) -> void:
	c.draw_polygon(PackedVector2Array(pts), PackedColorArray(cols))
