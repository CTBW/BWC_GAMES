## The battle view's drawing passes: the render half of src/render/battleScene.ts
## (bakeOuter, drawGrid, drawHighlights, drawZone, drawEntryWarnings,
## drawFacingArrow, drawFootprints, drawSorted, moveGhost, drawSquadShadow,
## engineOf, drawTints, drawSquad, drawStandard, drawOverlays, drawWaveLabels,
## the screen flash, the minimap).
## Each pass is called from a BattleLayer's _draw() with that CanvasItem; world
## passes draw in world pixels (the camera is the parent's transform), overlay
## passes in the view's screen pixels. The night and dawn are battle_night.gd.
extends RefCounted

const JS = preload("res://scripts/core/js.gd")
const Rng = preload("res://scripts/core/rng.gd")
const DB = preload("res://scripts/data/db.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const Iso = preload("res://scripts/render/iso.gd")
const Assets = preload("res://scripts/render/assets.gd")
const Formation = preload("res://scripts/render/formation.gd")
const SquadView = preload("res://scripts/render/squad_view.gd")
const BattleDeps = preload("res://scripts/render/battle_deps.gd")
const Fx = preload("res://scripts/render/fx.gd")
const SortedShader = preload("res://scenes/battle/battle_sorted.gdshader")
const DashShader = preload("res://scenes/battle/battle_dash.gdshader")
const FONT_PATH := "res://assets/fonts/cinzel-latin-700-normal.woff2"

const TW := 128.0
const TH := 64.0

var v # the BattleView
var font: Font
var _sorted_mat: ShaderMaterial
var _props: Array = [] # static prop list (positions, sprites, boxes)
var _host_vp: SubViewport
var _minimap_key := ""


func _init(view) -> void:
	v = view
	var base: Font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = base
	# Cinzel has no ★: fall back to the system's serif (the original's Georgia).
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["Georgia", "Segoe UI Symbol", "serif"])
	fv.fallbacks = [sys]
	font = fv
	_sorted_mat = ShaderMaterial.new()
	_sorted_mat.shader = SortedShader


static func rgba(r: float, g: float, bl: float, a: float) -> Color:
	return Color(r / 255.0, g / 255.0, bl / 255.0, a)


# ---------------------------------------------------------------- primitives

## Untextured geometry gathered for one draw call: the original fills and
## strokes many small paths; drawn one by one in Godot each would be its own
## draw call. Fills (in order) go into one triangle array, strokes into one
## antialiased multiline per width, drawn after the fills.
class Geo extends RefCounted:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var lines := {} # width -> [PackedVector2Array, PackedColorArray]

	## A convex polygon (fan).
	func poly(p: PackedVector2Array, c: Color) -> void:
		var base := pts.size()
		pts.append_array(p)
		for i in p.size():
			cols.append(c)
		for i in range(1, p.size() - 1):
			idx.append(base)
			idx.append(base + i)
			idx.append(base + i + 1)

	## Any simple polygon.
	func tri_poly(p: PackedVector2Array, c: Color) -> void:
		var t := Geometry2D.triangulate_polygon(p)
		if t.is_empty():
			return
		var base := pts.size()
		pts.append_array(p)
		for i in p.size():
			cols.append(c)
		for i in t:
			idx.append(base + i)

	func line(a: Vector2, b: Vector2, c: Color, w: float) -> void:
		var l = lines.get(w)
		if l == null:
			l = [PackedVector2Array(), PackedColorArray()]
			lines[w] = l
		l[0].append(a)
		l[0].append(b)
		l[1].append(c)

	func outline(p: PackedVector2Array, c: Color, w: float) -> void:
		for i in p.size():
			line(p[i], p[(i + 1) % p.size()], c, w)

	## A small filled disc (round caps and joins).
	func disc(at: Vector2, r: float, c: Color, n := 8) -> void:
		var p := PackedVector2Array()
		for i in n:
			var a := TAU * i / n
			p.append(at + Vector2(cos(a), sin(a)) * r)
		poly(p, c)

	func flush(ci: CanvasItem) -> void:
		if not idx.is_empty():
			RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols)
		for w in lines:
			ci.draw_multiline_colors(lines[w][0], lines[w][1], w, true)
		pts = PackedVector2Array()
		cols = PackedColorArray()
		idx = PackedInt32Array()
		lines = {}


## A convex or concave simple polygon, filled once (no triangulation errors).
static func fill_poly(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 3:
		return
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		return
	var cols := PackedColorArray()
	cols.resize(pts.size())
	cols.fill(col)
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols)


static func stroke_poly(ci: CanvasItem, pts: PackedVector2Array, col: Color, width: float, closed := true) -> void:
	if pts.size() < 2:
		return
	var p := pts
	if closed:
		p = pts.duplicate()
		p.append(pts[0])
	ci.draw_polyline(p, col, width, true)


## An ellipse (ctx.ellipse) filled: a soft-edged disc texture stretched over
## its box (one textured rect, so the contact shadows batch).
static func fill_ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	ci.draw_texture_rect(_disc(), Rect2(c.x - rx, c.y - ry, rx * 2, ry * 2), false, col)


static var _disc_tex: Texture2D


## A white disc with an antialiased rim, 64 px across.
static func _disc() -> Texture2D:
	if _disc_tex != null:
		return _disc_tex
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0 - 1.0 / 32.0, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_disc_tex = tex
	return _disc_tex


static func ellipse_points(c: Vector2, rx: float, ry: float, n := 48) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		out.append(Vector2(c.x + cos(a) * rx, c.y + sin(a) * ry))
	return out


## A dashed stroke along a polyline (setLineDash + lineDashOffset), one
## subpath, into a Geo.
static func dash_geo(g: Geo, pts: PackedVector2Array, col: Color, width: float, on: float, off: float, offset: float, closed := false) -> void:
	var p := pts
	if closed and pts.size() > 1:
		p = pts.duplicate()
		p.append(pts[0])
	var period := on + off
	var s := 0.0
	for i in range(1, p.size()):
		var a := p[i - 1]
		var bb := p[i]
		var L := a.distance_to(bb)
		if L <= 0.0:
			continue
		var dirv := (bb - a) / L
		var t := 0.0
		while t < L:
			var ph := fposmod(s + t + offset, period)
			if ph >= period:
				ph = 0.0
			if ph < on:
				var e := minf(L, t + maxf(on - ph, 1e-6))
				g.line(a + dirv * t, a + dirv * e, col, width)
				t = e
			else:
				t = minf(L, t + maxf(period - ph, 1e-6))
		s += L


func diamond(x: float, y: float, inset := 0.0) -> PackedVector2Array:
	var h: float = v._tile_h(x, y)
	var s := 0.5 - inset
	return PackedVector2Array([
		Vector2(Iso.iso_x(x - s, y - s), Iso.iso_y(x - s, y - s, h)),
		Vector2(Iso.iso_x(x + s, y - s), Iso.iso_y(x + s, y - s, h)),
		Vector2(Iso.iso_x(x + s, y + s), Iso.iso_y(x + s, y + s, h)),
		Vector2(Iso.iso_x(x - s, y + s), Iso.iso_y(x - s, y + s, h)),
	])


## fillTiles into a Geo: the fills, then the strokes (flushed together).
func fill_tiles(g: Geo, tiles: Array, fill: Color, stroke = null, inset := 0.04) -> void:
	for t in tiles:
		var d := diamond(t.x, t.y, inset)
		g.poly(d, fill)
		if stroke != null:
			g.outline(d, stroke, 2.0)


# ---------------------------------------------------------------- static layers

func draw_background(ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(0, 0, v._w, v._h), Color8(0x1b, 0x28, 0x12))


## Paint the decorative forest ring beyond the field into the ground layer,
## back to front, once (bakeOuter). It never changes, so a large field does not
## redraw hundreds of trees every frame, and it is always drawn behind the
## squads, so the forest at the near edges never hides a soldier.
func draw_outer(ci: CanvasItem) -> void:
	Assets.draw_base = Transform2D.IDENTITY
	var outer: Array = v.b.map.outer.duplicate()
	JS.sort(outer, func(a, q): return a.x + a.y - (q.x + q.y))
	for o in outer:
		var s := Assets.sprite(_prop_sprite(o.prop), o.v)
		if s.is_empty():
			continue
		var px := Iso.iso_x(o.x, o.y) + (Rng.hash2(o.x, o.y, 5) - 0.5) * 40
		var py := Iso.iso_y(o.x, o.y, o.h) + (Rng.hash2(o.x, o.y, 6) - 0.5) * 20
		var flip: bool = not s.noShadow and Rng.hash2(o.x, o.y, 9) > 0.5
		var sc := 0.9 + Rng.hash2(o.x, o.y, 3) * 0.35
		Assets.draw_cast_shadow(ci, s, px, py, flip, sc, 0.2 if String(o.prop).begins_with("tree") else 0.16)
		Assets.draw_sprite(ci, s, px, py, flip, sc)


static func _prop_sprite(prop: String) -> String:
	var p = DB.PROPS.get(prop)
	if p != null and p.get("sprite") != null:
		return p.sprite
	return prop


func draw_grid(ci: CanvasItem) -> void:
	var segs := PackedVector2Array()
	for t in v.b.map.tiles:
		if DB.TERRAIN[t.terrain].get("water") and t.terrain == "water":
			continue
		var d := diamond(t.x, t.y, 0.02)
		for i in 4:
			segs.append(d[i])
			segs.append(d[(i + 1) % 4])
	if not segs.is_empty():
		ci.draw_multiline(segs, rgba(30, 40, 15, 0.16), 1.2, true)


# ---------------------------------------------------------------- highlights

## The ground to hold: a gold outline (red and pulsing while it is being
## overrun). The fill (its own layer, redrawn only while it pulses) ...
func draw_zone_fill(ci: CanvasItem) -> void:
	var zone: Array = v.b.map.get("zone", [])
	if zone.is_empty():
		return
	var danger: bool = v._overrun_warn
	var pulse := 0.5 + 0.5 * sin(v.time * 5)
	var g := Geo.new()
	fill_tiles(g, zone, rgba(220, 60, 40, 0.1 + 0.08 * pulse) if danger else rgba(255, 215, 106, 0.06), null, 0.0)
	g.flush(ci)


## ... and the dashed outer edges: static quads, the dashes marched by a shader
## (battle_dash.gdshader; `zone_dash_uniforms` sets them each frame).
func draw_zone_dashes(ci: CanvasItem) -> void:
	var zone: Array = v.b.map.get("zone", [])
	if zone.is_empty():
		return
	if ci.material == null:
		var mat := ShaderMaterial.new()
		mat.shader = DashShader
		ci.material = mat
	var in_zone := {}
	for p in zone:
		in_zone[Grid.key(p.x, p.y)] = true
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var w := 3.0
	var f := 0.7 # a feathered rim of about a pixel (the canvas antialiases strokes)
	for p in zone:
		var th: float = v._tile_h(p.x, p.y)
		var c := [
			Vector2(Iso.iso_x(p.x - 0.5, p.y - 0.5), Iso.iso_y(p.x - 0.5, p.y - 0.5, th)),
			Vector2(Iso.iso_x(p.x + 0.5, p.y - 0.5), Iso.iso_y(p.x + 0.5, p.y - 0.5, th)),
			Vector2(Iso.iso_x(p.x + 0.5, p.y + 0.5), Iso.iso_y(p.x + 0.5, p.y + 0.5, th)),
			Vector2(Iso.iso_x(p.x - 0.5, p.y + 0.5), Iso.iso_y(p.x - 0.5, p.y + 0.5, th)),
		]
		# Outer edges only: those not shared with another tile of the zone.
		for e in [[0, -1, 0, 1], [1, 0, 1, 2], [0, 1, 2, 3], [-1, 0, 3, 0]]:
			if in_zone.has(Grid.key(p.x + e[0], p.y + e[1])):
				continue
			var a: Vector2 = c[e[2]]
			var b: Vector2 = c[e[3]]
			var L := a.distance_to(b)
			var n := Vector2(-(b - a).y, (b - a).x) / L
			var hw := w / 2.0 - f / 2.0
			var ho := w / 2.0 + f / 2.0
			var base := pts.size()
			pts.append_array([a + n * ho, b + n * ho, a + n * hw, b + n * hw, a - n * hw, b - n * hw, a - n * ho, b - n * ho])
			cols.append_array([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color(1, 1, 1, 0), Color(1, 1, 1, 0)])
			uvs.append_array([Vector2(0, 0), Vector2(L, 0), Vector2(0, 0), Vector2(L, 0), Vector2(0, 0), Vector2(L, 0), Vector2(0, 0), Vector2(L, 0)])
			for q in 3:
				var o := base + q * 2
				idx.append_array([o, o + 1, o + 3, o, o + 3, o + 2])
	if not idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols, uvs)


func zone_dash_uniforms(ci: CanvasItem) -> void:
	var mat := ci.material as ShaderMaterial
	if mat == null:
		return
	var pulse := 0.5 + 0.5 * sin(v.time * 5)
	mat.set_shader_parameter("offset", -v.time * 12)
	mat.set_shader_parameter("tint", rgba(255, 90, 70, 0.6 + 0.4 * pulse) if v._overrun_warn else rgba(255, 215, 106, 0.75))


## Where the next waves will march in: red tiles with arrows pointing onto
## the field, bright and pulsing for a wave due at the end of this turn,
## faint for the one after.
func _draw_entry_warnings(g: Geo, time: float) -> void:
	var b = v.b
	var waves: Array = v._waves()
	for i in waves.size():
		var w: Dictionary = waves[i]
		if b.wave_state[i] == "cancelled" or (w.get("horn") and b.horn != "sounded"):
			continue
		var waiting := 0
		for uid in w.uids:
			var uv = v.views.get(uid)
			if uv != null and uv.reserve:
				waiting += 1
		if waiting == 0:
			continue
		var due_in: int = w.turn - v.ui.turn
		if due_in > 1:
			continue
		var ent = b.map.get("entries", {}).get(w.edge)
		var entries: Array = (ent if ent != null else []).slice(0, waiting)
		var pulse := 0.55 + 0.45 * sin(time * 6) if due_in <= 0 else 0.35
		fill_tiles(g, entries, rgba(220, 50, 35, 0.2 * pulse + (0.12 if due_in <= 0 else 0.04)), rgba(255, 90, 70, 0.5 * pulse), 0.06)
		var inward: Dictionary = Grid.DIRS[BattleDeps.INWARD[w.edge]]
		var alpha := 0.55 + 0.45 * pulse if due_in <= 0 else 0.4
		var fill := Color(1.0, 0x6a / 255.0, 0x50 / 255.0, alpha)
		var edge := rgba(40, 10, 5, 0.8 * alpha)
		for p in entries:
			var th: float = v._tile_h(p.x, p.y)
			for off in [-0.25, 0.1]:
				var pts := PackedVector2Array()
				for q in [[off + 0.3, 0.0], [off, 0.22], [off + 0.08, 0.0], [off, -0.22]]:
					var gx: float = p.x + inward.x * q[0] - inward.y * q[1]
					var gy: float = p.y + inward.y * q[0] + inward.x * q[1]
					pts.append(Vector2(Iso.iso_x(gx, gy), Iso.iso_y(gx, gy, th)))
				# Star-shaped from its tip: a fan.
				g.poly(pts, fill)
				g.outline(pts, edge, 1.5)


func _danger_tiles() -> Dictionary:
	if v._danger_cache != null:
		return v._danger_cache
	var out := {}
	var b = v.b
	var m: Dictionary = b.map
	for e in b.active("enemy"):
		# A war machine's stones fall from where it stands now: it cannot move and loose in one turn.
		var primary = DB.UNIT_TYPES.get(e.typeId, {}).get("primary")
		var lob = DB.ABILITIES.get(primary) if primary != null else null
		if lob != null and lob.get("range"):
			var lmin: float = lob.get("minRange", 1)
			for t in m.tiles:
				var dd := Grid.dist(t, e)
				if dd <= lob.range and dd >= lmin:
					out[Grid.key(t.x, t.y)] = true
		var reach: Dictionary = b.reachable_full(e)
		var shot = e.get("shot")
		for k in reach:
			var px: int = k % 1000
			var py: int = floori(k / 1000.0)
			for d in Grid.DIRS:
				out[Grid.key(px + d.x, py + d.y)] = true
			if shot != null:
				# Every tile within range: only those in the range's square can be.
				var r: int = ceili(shot.range)
				for y in range(maxi(0, py - r), mini(m.h - 1, py + r) + 1):
					for x in range(maxi(0, px - r), mini(m.w - 1, px + r) + 1):
						var dd := Grid.hypot(float(x - px), float(y - py))
						if dd <= shot.range and dd >= shot.minRange:
							out[Grid.key(x, y)] = true
	v._danger_cache = out
	return out


## drawHighlights and drawFootprints: the overlays on the ground under everyone.
func draw_under(ci: CanvasItem) -> void:
	var b = v.b
	var time: float = v.time
	var g := Geo.new()
	_draw_entry_warnings(g, time)
	g.flush(ci)
	if b.phase == "deploy":
		fill_tiles(g, b.map.playerDeploy, rgba(80, 140, 255, 0.16), rgba(140, 190, 255, 0.35))
	if v.ui.danger:
		var d: Array = []
		for k in _danger_tiles():
			var p := {"x": k % 1000, "y": floori(k / 1000.0)}
			if Grid.tile_at(b.map, p.x, p.y) != null:
				d.append(p)
		fill_tiles(g, d, rgba(220, 60, 40, 0.16))
	g.flush(ci)
	# Stance zones.
	for u in b.active("player") + b.active("enemy"):
		if u.get("stance") == "spearwall":
			var zone: Array = []
			for dd in Grid.DIRS:
				var p := {"x": u.x + dd.x, "y": u.y + dd.y}
				if Grid.tile_at(b.map, p.x, p.y) != null and b.arc_of(u, p) != "rear":
					zone.append(p)
			fill_tiles(g, zone, rgba(240, 200, 90, 0.16), rgba(240, 200, 90, 0.45), 0.1)
	g.flush(ci)
	var sel = v.selected_unit()
	if sel != null and b.phase == "player" and not v.busy():
		if not sel.hasMoved:
			var reach: Dictionary = v._reach(sel)
			var tiles: Array = []
			for k in reach:
				tiles.append({"x": k % 1000, "y": floori(k / 1000.0)})
			var pulse := 0.26 + 0.05 * sin(time * 3)
			fill_tiles(g, tiles, rgba(105, 165, 255, pulse), rgba(200, 225, 255, 0.6), 0.06)
			g.flush(ci)
		var cx := Iso.iso_x(sel.x, sel.y)
		var cy := Iso.iso_y(sel.x, sel.y, v._tile_h(sel.x, sel.y))
		var ring := func(r: float, col: Color) -> void:
			dash_geo(g, ellipse_points(Vector2(cx, cy), r * TW * 0.7071, r * TH * 0.7071, 96), col, 2.0, 6.0, 8.0, 0.0, true)
			g.flush(ci)
		# The spell being aimed, or a war machine's stone: its reach and what it can be cast at.
		var chosen = v.ui.ability if (v.ui.ability != null and DB.ABILITIES.get(v.ui.ability, {}).get("kind") == "spell") else null
		var primary = DB.UNIT_TYPES.get(sel.typeId, {}).get("primary")
		var spell_id = chosen
		if spell_id == null and primary != null and v.ui.ability == null and b.can_cast(sel, primary).ok:
			spell_id = primary
		if spell_id != null and not sel.hasActed:
			var ab: Dictionary = DB.ABILITIES[spell_id]
			var magic: bool = not ab.get("engine", false)
			if ab.get("range"):
				ring.call(float(ab.range), rgba(200, 170, 255, 0.55) if magic else rgba(255, 210, 140, 0.5))
			if ab.get("minRange"):
				ring.call(float(ab.minRange) - 0.5, rgba(255, 140, 110, 0.4))
			var skey := "%s|%s|%d,%d|%d" % [sel.uid, spell_id, sel.x, sel.y, b.turn]
			if v._spell_target_cache == null or v._spell_target_cache.key != skey:
				v._spell_target_cache = {"key": skey, "list": b.spell_targets(sel, spell_id)}
			var ally: bool = ab.get("target") == "ally"
			for t in v._spell_target_cache.list:
				fill_tiles(g, [t], rgba(120, 220, 120, 0.22) if ally else rgba(230, 70, 50, 0.24), rgba(160, 240, 150, 0.8) if ally else rgba(255, 120, 90, 0.8), 0.08)
			g.flush(ci)
		var shot = sel.get("shot")
		if chosen == null and shot != null and not sel.hasActed and sel.get("stance") != "overwatch":
			# Range ring hint: tiles within range (light).
			ring.call(float(shot.range), rgba(255, 230, 160, 0.35))
		# Attackable enemies.
		if not sel.hasActed and chosen == null:
			var ab = v.ui.ability
			var tkey := "%s|%s|%d,%d" % [sel.uid, ab if ab != null else "", sel.x, sel.y]
			if v._target_cache == null or v._target_cache.key != tkey:
				v._target_cache = {"key": tkey, "list": b.targets(sel, sel, ab)}
			for t in v._target_cache.list:
				fill_tiles(g, [t], rgba(230, 70, 50, 0.28), rgba(255, 120, 90, 0.8), 0.08)
			g.flush(ci)
		_draw_spell_area(ci, g, time)
	_draw_path_and_arrows(ci, g, time)
	_draw_footprints(ci, g, time)


## What the hovered spell would strike: the blast's ground, friends caught in
## it in orange, and lightning's arcs.
func _draw_spell_area(ci: CanvasItem, g: Geo, time: float) -> void:
	var b = v.b
	var sp = v.ui.hover.get("spell")
	if sp == null or not sp.get("legal") or v.busy():
		return
	var ab: Dictionary = DB.ABILITIES[sp.ability]
	if ab.get("splash"):
		var area: Array = [sp.at]
		area.append_array(Grid.neighbors(b.map, sp.at))
		fill_tiles(g, area, rgba(255, 170, 80, 0.12), rgba(255, 190, 110, 0.55), 0.12)
		g.flush(ci)
	for h in sp.hits:
		var u: Dictionary = v._u(h.uid)
		var good: bool = float(h.get("heal", 0)) > 0 or (h.get("ally", false) and not h.get("max"))
		var ally: bool = h.get("ally", false)
		var fill := rgba(140, 240, 130, 0.32) if good else (rgba(255, 150, 40, 0.42) if ally else rgba(255, 80, 50, 0.36))
		var edge := rgba(190, 255, 170, 0.95) if good else (rgba(255, 190, 90, 1) if ally else rgba(255, 140, 110, 1))
		fill_tiles(g, [u], fill, edge, 0.05)
	g.flush(ci)
	# Lightning: the arcs it will jump along.
	if ab.get("chain") == null:
		return
	var pts := PackedVector2Array()
	for h in sp.hits:
		if h.role != "main" and h.role != "chain":
			continue
		var u: Dictionary = v._u(h.uid)
		pts.append(Vector2(Iso.iso_x(u.x, u.y), Iso.iso_y(u.x, u.y, v._tile_h(u.x, u.y)) - 20))
	if pts.size() > 1:
		dash_geo(g, pts, rgba(190, 215, 255, 0.85), 2.5, 4.0, 6.0, -time * 40)
		g.flush(ci)


func _draw_path_and_arrows(ci: CanvasItem, g: Geo, time: float) -> void:
	var busy: bool = v.busy()
	# Path preview.
	var path = v.ui.hover.get("path")
	if path != null and path.size() > 1 and not busy:
		var pts := PackedVector2Array()
		for p in path:
			pts.append(Vector2(Iso.iso_x(p.x, p.y), Iso.iso_y(p.x, p.y, v._tile_h(p.x, p.y))))
		# The shadow under the path: one stroke with round joins and caps.
		var polys := Geometry2D.offset_polyline(pts, 4.5, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
		if polys.size() == 1:
			g.tri_poly(polys[0], rgba(20, 15, 10, 0.45))
		else:
			# A path crossing itself: the outlines, holes left out.
			var outer_cw := Geometry2D.is_polygon_clockwise(polys[0])
			for poly in polys:
				if Geometry2D.is_polygon_clockwise(poly) == outer_cw:
					g.tri_poly(poly, rgba(20, 15, 10, 0.45))
		g.flush(ci)
		var zoc = v.ui.hover.get("zoc")
		var col := Color.html("#ffb070") if (zoc != null and zoc > 0) else Color.html("#f4e6b0")
		# Round-capped dots (dash 2, gap 10, width 4).
		var dots := Geo.new()
		dash_geo(dots, pts, col, 4.0, 2.0, 10.0, -time * 30)
		for w in dots.lines:
			var segs: PackedVector2Array = dots.lines[w][0]
			for i in segs.size() / 2:
				g.disc(segs[2 * i], 2.0, col)
				g.disc(segs[2 * i + 1], 2.0, col)
				g.line(segs[2 * i], segs[2 * i + 1], col, w)
		g.flush(ci)
	# Arrival facing: a bright arrow on the destination, faint ones for the other ways in.
	var hv: Dictionary = v.ui.hover
	if hv.get("dest") != null and hv.get("facing") != null and not busy:
		for f in (hv.facings if hv.get("facings") != null else []):
			if f != hv.facing:
				facing_arrow(g, hv.dest, f, 0.62, false)
				g.flush(ci)
		facing_arrow(g, hv.dest, hv.facing, 1.0, true)
		g.flush(ci)
	# Hovered tile.
	var ht = hv.get("tile")
	if ht != null:
		g.outline(diamond(ht.x, ht.y, 0.03), rgba(255, 245, 210, 0.8), 2.5)
		g.flush(ci)


## An arrow on the ground of a tile pointing toward one of its edges: the way
## a squad will face when it arrives. `main` is the chosen facing; the small
## ones mark the other approaches the player can pick with Q / E.
func facing_arrow(g: Geo, at: Dictionary, f: int, alpha: float, main: bool, screen := false) -> void:
	var th: float = v._tile_h(at.x, at.y)
	var d: Dictionary = Grid.DIRS[f]
	# A little larger zoomed out, so it still reads on a large field.
	var k := Iso.clamp(0.85 / v.cam.zoom, 1, 1.4)
	var pts := PackedVector2Array()
	var shape := [[0.72, 0], [0.4, 0.3], [0.44, 0.12], [0.1, 0.12], [0.1, -0.12], [0.44, -0.12], [0.4, -0.3]] if main else [[0.66, 0], [0.44, 0.2], [0.5, 0], [0.44, -0.2]]
	for q in shape:
		var gx: float = at.x + (d.x * q[0] - d.y * q[1]) * k
		var gy: float = at.y + (d.y * q[0] + d.x * q[1]) * k
		if screen:
			pts.append(v.cam.world_to_screen(Iso.iso_x(gx, gy), Iso.iso_y(gx, gy, th), v._w, v._h))
		else:
			pts.append(Vector2(Iso.iso_x(gx, gy), Iso.iso_y(gx, gy, th)))
	var fill := Color.html("#ffd76a") if main else Color.html("#f4ead0")
	fill.a = alpha
	# Star-shaped from the tip: a fan.
	g.poly(pts, fill)
	var lw := (2.6 if main else 1.6) * (maxf(0.7, v.cam.zoom) if screen else 1.0)
	var ec := rgba(40, 25, 10, 0.9 * alpha)
	g.outline(pts, ec, lw)
	for q in pts:
		g.disc(q, lw / 2.0, ec, 6)


## The facing arrow drawn on its own (the ghost's and the overlay's).
func draw_facing_arrow(ci: CanvasItem, at: Dictionary, f: int, alpha: float, main: bool, screen := false) -> void:
	var g := Geo.new()
	facing_arrow(g, at, f, alpha, main, screen)
	g.flush(ci)


## Each squad's footprint on its tile, drawn on the ground under everyone:
## trodden earth, corner marks in the squad's colours and a chevron at its
## front edge. It shows at a glance which soldiers belong together.
func _draw_footprints(ci: CanvasItem, g: Geo, time: float) -> void:
	var k := 0.86
	var base := [Vector2(0, -32 * k), Vector2(64 * k, 0), Vector2(0, 32 * k), Vector2(-64 * k, 0)]
	var sel_fill := rgba(255, 215, 106, 0.13 + 0.07 * sin(time * 4))
	for uv in v.views.values():
		if not uv.visible or uv.alive <= 0 or (uv.status != "active" and uv.status != "routing"):
			continue
		var u: Dictionary = v._u(uv.uid)
		var sel: bool = v.ui.selected == uv.uid
		var p: Vector2 = v._view_pos(uv)
		var player: bool = u.faction == "player"
		var col: Color = GOLD if (player and sel) else (FOOT_PLAYER if player else FOOT_ENEMY)
		var pts := PackedVector2Array([p + base[0], p + base[1], p + base[2], p + base[3]])
		var fill: Color = sel_fill if sel else (FILL_PLAYER if player else FILL_ENEMY)
		fill.a *= uv.alpha
		g.poly(pts, fill)
		# Corner brackets (round joins).
		var bc := col
		bc.a *= uv.alpha * (1.0 if sel else 0.75)
		var lw := 3.0 if sel else 2.0
		for i in 4:
			var c := pts[i]
			g.line(c + (pts[(i + 3) % 4] - c) * 0.22, c, bc, lw)
			g.line(c, c + (pts[(i + 1) % 4] - c) * 0.22, bc, lw)
			g.disc(c, lw / 2.0, bc, 6)
		# Chevron on the front edge.
		var d: Dictionary = Grid.DIRS[uv.facing]
		var fx := Iso.iso_x(d.x, d.y) * 0.5 * k
		var fy := Iso.iso_y(d.x, d.y) * 0.5 * k
		var xf := Transform2D(atan2(fy, fx), p + Vector2(fx, fy))
		# Concave: fan from the tip.
		g.poly(PackedVector2Array([xf * Vector2(9, 0), xf * Vector2(-3, -7), xf * Vector2(0, 0), xf * Vector2(-3, 7)]), bc)
	g.flush(ci)


const GOLD := Color(1.0, 0xd7 / 255.0, 0x6a / 255.0)
const FOOT_PLAYER := Color(130 / 255.0, 185 / 255.0, 1.0, 0.95)
const FOOT_ENEMY := Color(240 / 255.0, 96 / 255.0, 74 / 255.0, 0.95)
const FILL_PLAYER := Color(40 / 255.0, 70 / 255.0, 130 / 255.0, 0.13)
const FILL_ENEMY := Color(120 / 255.0, 30 / 255.0, 20 / 255.0, 0.12)


func draw_fx_ground(ci: CanvasItem) -> void:
	if v.fx.has_method("draw_ground"):
		v.fx.draw_ground(ci)


func draw_fx_air(ci: CanvasItem) -> void:
	if v.fx.has_method("draw_air"):
		v.fx.draw_air(ci)


func draw_texts(ci: CanvasItem) -> void:
	if v.fx.has_method("draw_texts"):
		v.fx.draw_texts(ci, v.cam.zoom)


# ---------------------------------------------------------------- sorted pass

func _prop_list() -> Array:
	if not _props.is_empty() or v.b == null:
		return _props
	for t in v.b.map.tiles:
		var prop = t.get("prop")
		if prop == null:
			continue
		var s := Assets.sprite(_prop_sprite(prop), t.v)
		if s.is_empty():
			continue
		var px := Iso.iso_x(t.x, t.y)
		var py := Iso.iso_y(t.x, t.y, t.h)
		var flip: bool = not s.noShadow and Rng.hash2(t.x, t.y, 9) > 0.5
		var k: float = s.scale
		var bx0: float = px - (s.w - s.ax) * k if flip else px - s.ax * k
		_props.append({"x": t.x, "y": t.y, "px": px, "py": py, "s": s, "flip": flip, "d": float(t.x + t.y), "tree": String(prop).begins_with("tree"),
			"bx0": bx0, "bx1": bx0 + s.w * k, "by0": py - s.ay * k, "k": k})
	if _props.is_empty():
		_props.append(null) # marks the list as built
	return _props


## The props' cast shadows, drawn once (drawSorted draws them first of all,
## unaffected by a prop's fade or sway). Black at a low alpha, they composite
## the same in any order, so they go by texture (few draw calls).
func draw_prop_shadows(ci: CanvasItem) -> void:
	Assets.draw_base = Transform2D.IDENTITY
	var list: Array = _prop_list().filter(func(pr): return pr != null)
	list.sort_custom(func(a, q): return String(a.s.file) < String(q.s.file))
	for pr in list:
		Assets.draw_cast_shadow(ci, pr.s, pr.px, pr.py, pr.flip, 1.0, 0.2 if pr.tree else 0.16)


func draw_sorted(ci: CanvasItem) -> void:
	Assets.draw_base = Transform2D.IDENTITY
	if ci.material != _sorted_mat:
		ci.material = _sorted_mat
	var b = v.b
	var time: float = v.time
	var cam = v.cam
	var zoom: float = cam.zoom
	# Only what can be on screen is drawn: large fields hold hundreds of props.
	var hw: float = v._w / zoom / 2 + 240
	var hh: float = v._h / zoom / 2
	var cx: float = cam.x
	var cy: float = cam.y
	var staged: Dictionary = v.staged()
	# `marks`: world points that must stay in sight (one is enough to fade a prop).
	var boxes := {} # column -> [[x, y, d]]
	for uv in v.views.values():
		if not (uv.visible or staged.has(uv.uid)) or not _shows(uv):
			continue
		var p: Vector2 = v._view_pos(uv)
		if absf(p.x - cx) < hw and p.y - cy > -hh - 60 and p.y - cy < hh + 420:
			var col := floori(p.x / 128.0)
			if not boxes.has(col):
				boxes[col] = []
			boxes[col].append([p.x, p.y, uv.x + uv.y])
	# Where the selected squad is about to go: a ghost formation. Walls and
	# trees in front of it fade as they would over a squad, so the facing
	# arrow at a gateway stays in sight.
	var ghost = move_ghost()
	var items := {}
	var keys := PackedFloat64Array()
	var n := [0]
	var push := func(d: float, item: Array) -> void:
		var key: float = d + n[0] * 1e-9
		while items.has(key):
			key += 1e-12
		items[key] = item
		keys.append(key)
		n[0] += 1
	for pr in _prop_list():
		if pr == null:
			continue
		var px: float = pr.px
		var py: float = pr.py
		if not (absf(px - cx) < hw and py - cy > -hh - 60 and py - cy < hh + 420):
			continue
		var d: float = pr.d
		var s: Dictionary = pr.s
		var flip: bool = pr.flip
		var k: float = pr.k
		# Fade a prop only where its opaque pixels actually cover a squad standing behind it.
		var alpha := 1.0
		var bx0: float = pr.bx0
		var bx1: float = pr.bx1
		var by0: float = pr.by0
		if ghost != null and ghost.at.x + ghost.at.y < d:
			for mk in ghost.marks:
				var wx: float = mk.x
				var wy: float = mk.y
				if wx < bx0 or wx > bx1 or wy < by0 or wy > py + 4:
					continue
				if Assets.opaque_at(s, s.ax - (wx - px) / k if flip else s.ax + (wx - px) / k, s.ay + (wy - py) / k):
					alpha = 0.28
					break
		if alpha == 1.0:
			for col in range(floori((bx0 - 30) / 128.0), floori((bx1 + 30) / 128.0) + 1):
				var list = boxes.get(col)
				if list == null:
					continue
				for ub in list:
					if ub[2] >= d:
						continue
					var ux: float = ub[0]
					var uy: float = ub[1]
					if ux + 30 < bx0 or ux - 30 > bx1 or uy < by0 or uy - 70 > py:
						continue
					var covered := 0
					for o in OFFS:
						var wx: float = ux + o.x
						var wy: float = uy + o.y
						var lx: float = s.ax - (wx - px) / k if flip else s.ax + (wx - px) / k
						var ly: float = s.ay + (wy - py) / k
						if Assets.opaque_at(s, lx, ly):
							covered += 1
					if covered >= 2:
						# Squads are small figures: let them read clearly through the foliage.
						alpha = 0.28
						break
				if alpha < 1.0:
					break
		var sway := sin(time * 0.9 + pr.x * 0.7 + pr.y * 0.3) * 0.012 if pr.tree else 0.0
		push.call(d, [K_PROP, pr, alpha, sway])
	# The forest ring beyond the field is painted into the ground layer (bakeOuter).
	var host = v._host
	if host != null and v._host_alpha > 0.01:
		push.call(host.d, [K_HOST])
	# The fallen lie where they dropped, under the living.
	for c in v.corpses:
		if absf(c.wx - cx) < hw and c.wy - cy > -hh - 60 and c.wy - cy < hh + 420:
			push.call(c.d, [K_CORPSE, c])
	# The ghost formation; squads in front of it fade.
	if ghost != null:
		push.call(ghost.at.x + ghost.at.y + 0.04, [K_GHOST, ghost])
	for uv in v.views.values():
		# Coming waves mass beyond their edge, darkened, until they march in.
		var waiting: bool = uv.reserve and staged.has(uv.uid)
		if not (uv.visible or waiting) or not _shows(uv):
			continue
		var vp: Vector2 = v._view_pos(uv)
		if not (absf(vp.x - cx) < hw and vp.y - cy > -hh - 60 and vp.y - cy < hh + 420):
			continue
		var u: Dictionary = v._u(uv.uid)
		# Turning on the spot: the squad itself steps aside for its ghost.
		var self_ghost: bool = ghost != null and ghost.turn and uv.uid == v.ui.selected
		var hides: bool = self_ghost or (ghost != null and uv.x + uv.y > ghost.at.x + ghost.at.y and body_covers(uv, u, ghost.wx, ghost.wy - 24, 8))
		push.call(uv.x + uv.y + 0.05, [K_SQUAD, uv, u, 0.4 if hides else 1.0, 0.42 if waiting else 0.0])
	if v.relief != null:
		for q in v.relief.riders:
			var p: Dictionary = v._rider_at(q, v.relief.t)
			if p.alpha <= 0:
				continue
			var th: float = v._tile_h(JS.rnd(p.x), JS.rnd(p.y))
			var wx := Iso.iso_x(p.x, p.y)
			var wy := Iso.iso_y(p.x, p.y, th)
			if not (absf(wx - cx) < hw and wy - cy > -hh - 60 and wy - cy < hh + 420):
				continue
			var s := Assets.sprite("margrave_rider_%s_%s" % [p.pose, "f" if Formation.faces_camera(q.facing) else "b"], q.variant)
			push.call(p.x + p.y + 0.05, [K_RIDER, s, wx, wy, p, q])
	keys.sort()
	for key in keys:
		_draw_shadow(ci, items[key])
	for key in keys:
		_draw_item(ci, items[key], time)


const K_PROP := 0
const K_HOST := 1
const K_CORPSE := 2
const K_GHOST := 3
const K_SQUAD := 4
const K_RIDER := 5
const OFFS := [Vector2(0, -22), Vector2(0, -44), Vector2(-26, -30), Vector2(26, -30), Vector2(0, -62)]


## Something of the squad to draw: soldiers standing or falling, or a war machine's engine.
func _shows(uv) -> bool:
	return _has_bodies(uv) or (_engine_stands(uv) and DB.is_engine(v._type_of(uv.uid)))


static func _has_bodies(uv) -> bool:
	for m in uv.members:
		if m.alive or m.dying:
			return true
	return false


func _draw_shadow(ci: CanvasItem, it: Array) -> void:
	match it[0]:
		K_SQUAD:
			_draw_squad_shadow(ci, it[1], it[2])
		K_RIDER:
			var p: Dictionary = it[4]
			fill_ellipse(ci, Vector2(it[2], it[3] + 1), 30, 10, Color(20 / 255.0, 25 / 255.0, 10 / 255.0, 0.3 * p.alpha))


func _draw_item(ci: CanvasItem, it: Array, time: float) -> void:
	match it[0]:
		K_PROP:
			var pr: Dictionary = it[1]
			Assets.draw_sprite(ci, pr.s, pr.px, pr.py, pr.flip, 1.0, Color(1, 1, 1, it[2]), 1.0, it[3])
		K_HOST:
			var host: Dictionary = v._host
			var tex = host_texture()
			if tex != null:
				ci.draw_texture(tex, Vector2(host.x, host.y), Color(1, 1, 16, v._host_alpha))
		K_CORPSE:
			var c = it[1]
			Assets.draw_sprite(ci, Assets.sprite("%s_dead" % c.type, c.variant), c.wx, c.wy, c.flip, c.scale, Color(1, 1, 1, 0.9))
		K_GHOST:
			_draw_ghost(ci, it[1])
		K_SQUAD:
			_draw_squad(ci, it[1], it[2], time, it[3], it[4])
		K_RIDER:
			var p: Dictionary = it[4]
			var q: Dictionary = it[5]
			Assets.draw_sprite(ci, it[1], it[2], it[3] - p.bob, q.facing == 0 or q.facing == 2, 0.56, Color(1, 1, 1, p.alpha))


# ---------------------------------------------------------------- host

## The massed host painted once into its own texture (the original's host canvas).
func host_texture() -> Variant:
	var host = v._host
	if host == null:
		return null
	if _host_vp == null:
		_host_vp = SubViewport.new()
		_host_vp.name = "HostPaint"
		_host_vp.size = Vector2i(maxi(1, host.w), maxi(1, host.h))
		_host_vp.transparent_bg = true
		_host_vp.disable_3d = true
		_host_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		BattleDeps.prepare_viewport(_host_vp)
		var l = load("res://scripts/render/battle_layer.gd").new()
		l.position = Vector2(-host.x, -host.y)
		l.draw_fn = _paint_host
		_host_vp.add_child(l)
		v.add_child(_host_vp)
	return _host_vp.get_texture()


func _paint_host(ci: CanvasItem) -> void:
	Assets.draw_base = Transform2D.IDENTITY
	for f in v._host.figs:
		if f.banner:
			Assets.draw_sprite(ci, Assets.sprite("war_banner", f.v), f.wx, f.wy, false, 0.8)
			continue
		var s := Assets.sprite(f.key, f.v)
		var key: String = f.key
		var sc := 0.5 if key.begins_with("wolf") else (0.46 if key.begins_with("goblin_rabble") else 0.5)
		Assets.draw_sprite(ci, s, f.wx, f.wy, f.flip, sc)
		# Distance and dusk: the host reads as a dark mass, not as squads.
		Assets.draw_silhouette(ci, s, f.wx, f.wy, f.flip, sc, 0.5)


# ---------------------------------------------------------------- ghost and squads

## The selected squad's formation at the end of the previewed path, if any.
func move_ghost() -> Variant:
	var path = v.ui.hover.get("path")
	var sel = v.selected_unit()
	if path == null or path.size() < 2 or sel == null or v.busy():
		return null
	var uv = v.views[sel.uid]
	var at: Dictionary = path[path.size() - 1]
	var prev: Dictionary = path[path.size() - 2]
	var facing: int = v.dir_of(prev, at)
	var turn: bool = at.x == sel.x and at.y == sel.y
	var live := SquadView.standing(uv.members)
	var slots := Formation.formation_slots(live.size(), sel.size, facing, uv.tight, sel.typeId)
	var h: float = v._tile_h(at.x, at.y)
	var wx := Iso.iso_x(at.x, at.y)
	var wy := Iso.iso_y(at.x, at.y, h)
	# The arrow along its length and each ghost soldier's body.
	var d: Dictionary = Grid.DIRS[facing]
	var marks: Array = []
	for a in [0.3, 0.5, 0.72]:
		marks.append(Vector2(Iso.iso_x(at.x + d.x * a, at.y + d.y * a), Iso.iso_y(at.x + d.x * a, at.y + d.y * a, h)))
	for i in mini(slots.size(), live.size()):
		marks.append(Vector2(wx + slots[i].x, wy + slots[i].y - 26))
	return {"at": at, "wx": wx, "wy": wy, "marks": marks, "turn": turn, "facing": facing, "live": live, "slots": slots, "scale": SquadView.member_scale(sel)}


func _draw_ghost(ci: CanvasItem, g: Dictionary) -> void:
	var order: Array = []
	for i in g.live.size():
		order.append([g.live[i], g.slots[i]])
	JS.sort(order, func(p, q): return p[1].y - q[1].y)
	for o in order:
		var m = o[0]
		var s: Dictionary = o[1]
		var pk: Dictionary = v.pose_key(m.type, "idle", g.facing)
		Assets.draw_sprite(ci, Assets.sprite(pk.key, m.variant), g.wx + s.x, g.wy + s.y, pk.flip, g.scale, Color(1, 1, 1, 0.42))
	# The facing arrow again over the ghost so it reads through the bodies;
	# clearly when the squad turns where it stands.
	draw_facing_arrow(ci, g.at, g.facing, 0.9 if g.turn else 0.4, true)


## Sprite for one soldier given the squad's facing, his pose and the squad's order.
## Cached on the member until the pose, facing or order change.
func member_sprite(uv, m) -> Array:
	var state: int = (1000 if uv.routing else 0) + (100 if m.pose == "atk" else 0) + uv.facing
	if m.spr_state == state and m.spr_cache != null:
		return m.spr_cache
	var out: Array
	if uv.routing:
		out = [Assets.sprite("%s_flee_b" % m.type, m.variant), uv.facing == 2 or uv.facing == 0]
	else:
		var pk: Dictionary = v.pose_key(m.type, "atk" if m.pose == "atk" else "idle", uv.facing)
		out = [Assets.sprite(pk.key, m.variant), pk.flip]
	# What a blit needs, out of the sprite's dictionary: texture, rect, region, scale.
	var sd: Dictionary = out[0]
	if sd.is_empty():
		out.append_array([null, Rect2(), Rect2(), 1.0])
	else:
		out.append_array([sd.tex, Rect2(-sd.ax, -sd.ay, sd.w, sd.h), sd.region, sd.scale])
	m.spr_state = state
	m.spr_cache = out
	return out


## Whether a squad's drawn soldiers cover a world point (with a little tolerance).
func body_covers(uv, u: Dictionary, wx: float, wy: float, tol := 4.0) -> bool:
	var k0 := SquadView.member_scale(u)
	var eng = engine_of(uv, u) if _engine_stands(uv) else null
	if eng != null and not eng.s.is_empty():
		var es: Dictionary = eng.s
		var ek: float = es.scale * k0
		for o in [Vector2(0, 0), Vector2(tol, 0), Vector2(-tol, 0), Vector2(0, tol), Vector2(0, -tol)]:
			var lx: float = es.ax - (wx + o.x - eng.x) / ek if eng.flip else es.ax + (wx + o.x - eng.x) / ek
			var ly: float = es.ay + (wy + o.y - eng.y) / ek
			if Assets.opaque_at(es, lx, ly):
				return true
	for m in uv.members:
		if not m.alive:
			continue
		var ms := member_sprite(uv, m)
		var s: Dictionary = ms[0]
		if s.is_empty():
			continue
		var flip: bool = ms[1]
		var p: Vector2 = v._member_pos(uv, m)
		var k: float = s.scale * k0
		for o in [Vector2(0, 0), Vector2(tol, 0), Vector2(-tol, 0), Vector2(0, tol), Vector2(0, -tol)]:
			var lx: float = s.ax - (wx + o.x - p.x) / k if flip else s.ax + (wx + o.x - p.x) / k
			var ly: float = s.ay + (wy + o.y - (p.y - uv.hop)) / k
			if Assets.opaque_at(s, lx, ly):
				return true
	return false


## Whether a crew squad's engine still stands. The original draws it only
## while a crewman stands, so it vanished between the last one's fall and the
## squad's `down` event (which leaves the wreck); here it stays until then.
static func _engine_stands(uv) -> bool:
	return uv.alive > 0 or (uv.status != "dead" and uv.status != "downed")


## The war machine of a crew squad: its sprite, where it stands and which way it is drawn.
func engine_of(uv, u: Dictionary) -> Variant:
	if not DB.is_engine(u.typeId):
		return null
	var p: Vector2 = v._view_pos(uv)
	var o := Formation.engine_offset(uv.facing)
	# The engine moves with its crew: shoved forward when they ram or heave, rocked when they are struck.
	var lx := 0.0
	var ly := 0.0
	var n := 0
	for m in uv.members:
		if m.alive:
			lx += m.lunge.x
			ly += m.lunge.y
			n += 1
	if n > 0:
		lx /= n
		ly /= n
	var pose := "atk" if (uv.engine_atk > 0 and not uv.routing) else "idle"
	var s := Assets.sprite("%s_%s_%s" % [u.typeId, pose, "f" if Formation.faces_camera(uv.facing) else "b"], int(u.variant))
	var shake: float = sin(v.time * 55) * uv.shake * 3 if uv.shake else 0.0
	return {"s": s, "flip": uv.facing == 0 or uv.facing == 2, "x": p.x + o.x + lx + shake, "y": p.y + o.y + ly - uv.hop, "oy": o.y}


func _draw_squad_shadow(ci: CanvasItem, uv, u: Dictionary) -> void:
	var k := SquadView.member_scale(u)
	var def: Dictionary = DB.UNIT_TYPES[u.typeId]
	var big := 0.85 if def.has("crew") else (1.5 if (u.size <= 3 and def.get("size") == "large") else (0.8 if def.get("size") == "small" else 1.0))
	var eng = engine_of(uv, u) if _engine_stands(uv) else null
	var col := Color(20 / 255.0, 25 / 255.0, 10 / 255.0, 0.3 * uv.alpha)
	var bx := Iso.iso_x(uv.x, uv.y)
	var by := Iso.iso_y(uv.x, uv.y, uv.h)
	var rx := 14 * big
	var ry := 6.5 * big
	var disc := _disc()
	for m in uv.members:
		if not m.alive and not m.dying:
			continue
		var px: float = bx + m.x + m.lunge.x
		var py: float = by + m.y + m.lunge.y + 1
		ci.draw_texture_rect(disc, Rect2(px - rx, py - ry, rx * 2, ry * 2), false, col)
	if eng != null:
		ci.draw_texture_rect(disc, Rect2(eng.x - 40, eng.y + 2 - 17, 80, 34), false, col)
	# Zoomed out, or on a crowded large field, the contact shadows are enough:
	# a cast shadow per soldier doubles the drawing for little to see.
	if v.cam.zoom < 0.5 or (v.b.map.get("scale") == "large" and not v.rich_shadows):
		return
	for m in uv.members:
		if not m.alive:
			continue
		var ms := member_sprite(uv, m)
		Assets.draw_cast_shadow(ci, ms[0], bx + m.x + m.lunge.x, by + m.y + m.lunge.y, ms[1], k, 0.16 * uv.alpha)
	if eng != null:
		Assets.draw_cast_shadow(ci, eng.s, eng.x, eng.y, eng.flip, k, 0.18 * uv.alpha)


## Assets.draw_sprite without restoring the transform afterwards (the next
## sprite sets its own); call `ci.draw_set_transform_matrix(Assets.draw_base)`
## before drawing anything else.
static func _blit(ci: CanvasItem, s: Dictionary, x: float, y: float, flip: bool, scale: float, mod: Color, sy := 1.0, rot := 0.0) -> void:
	if s.is_empty():
		return
	var sc: float = s.scale * scale
	ci.draw_set_transform_matrix(Transform2D(rot, Vector2(-sc if flip else sc, sc * sy), 0.0, Vector2(x, y)))
	ci.draw_texture_rect_region(s.tex, Rect2(-s.ax, -s.ay, s.w, s.h), s.region, mod)


## _blit from a member_sprite() cache entry.
static func _blit_m(ci: CanvasItem, ms: Array, x: float, y: float, scale: float, mod: Color, sy := 1.0, rot := 0.0) -> void:
	var tex = ms[2]
	if tex == null:
		return
	var sc: float = ms[5] * scale
	ci.draw_set_transform_matrix(Transform2D(rot, Vector2(-sc if ms[1] else sc, sc * sy), 0.0, Vector2(x, y)))
	ci.draw_texture_rect_region(tex, ms[3], ms[4], mod)


## Frost on a chilled squad, the red of a frenzy: a tinted copy of the figure
## over it (tintOf; the sorted pass's material draws Assets.TINT colours).
static func _draw_tints(ci: CanvasItem, uv, s: Dictionary, x: float, y: float, flip: bool, scale: float, alpha: float, sy: float, rot: float, time: float, phase: float) -> void:
	for st in uv.statuses:
		if st == "bleeding":
			continue
		var chill: bool = st == "chilled"
		var a := 0.42 if chill else 0.22 + 0.09 * sin(time * 6 + phase)
		_blit(ci, s, x, y, flip, scale, Assets.tint_modulate(TINT_CHILL if chill else TINT_FRENZY, alpha * a), sy, rot)
		# Rime on the chilled: a faint frosty sheen over the blue.
		if chill:
			_blit(ci, s, x, y, flip, scale, Assets.tint_modulate(Color.WHITE, alpha * 0.12), sy, rot)


const TINT_CHILL := Color(0x7c / 255.0, 0xc4 / 255.0, 1.0)
const TINT_FRENZY := Color(0xc8 / 255.0, 0x1e / 255.0, 0x10 / 255.0)


## The engine among its crew (the drawEngine step of drawSquad).
func _draw_engine(ci: CanvasItem, uv, eng: Dictionary, scale: float, alpha: float, dim: float, time: float) -> void:
	var s: Dictionary = eng.s
	_blit(ci, s, eng.x, eng.y, eng.flip, scale, Color(1, 1, 1, alpha))
	if dim > 0:
		_blit(ci, s, eng.x, eng.y, eng.flip, scale, Color(0, 0, 0, alpha * dim))
	_draw_tints(ci, uv, s, eng.x, eng.y, eng.flip, scale, alpha, 1.0, 0.0, time, 0.0)
	var fl := 0.0
	for m in uv.members:
		if m.alive:
			fl = maxf(fl, m.flash)
	if fl > 0:
		_blit(ci, s, eng.x, eng.y, eng.flip, scale, Color(Assets.FLASH, Assets.FLASH, Assets.FLASH, fl * 0.6))


## `dim` darkens the squad (a wave still massing beyond the edge).
func _draw_squad(ci: CanvasItem, uv, u: Dictionary, time: float, fade := 1.0, dim := 0.0) -> void:
	var fighting: bool = uv.status == "active" or uv.status == "routing"
	var base_scale := SquadView.member_scale(u)
	# Back rank first so the front rank overlaps it.
	var bodies: Array = []
	for m in uv.members:
		if m.alive or m.dying:
			# Stable insertion by y + lunge.y (JS sort order).
			var key: float = m.y + m.lunge.y
			var j := bodies.size()
			while j > 0 and bodies[j - 1].y + bodies[j - 1].lunge.y > key:
				j -= 1
			bodies.insert(j, m)
	var bearer = _standard_bearer(uv, u)
	var champ := SquadView.champion_of(u)
	var alpha: float = uv.alpha * fade
	var white := Color(1, 1, 1, alpha)
	# memberPose, per squad: feet, bob and lean of each soldier this frame.
	var bx := Iso.iso_x(uv.x, uv.y)
	var by := Iso.iso_y(uv.x, uv.y, uv.h)
	var marching: float = uv.walking
	var idle := 1.0 - marching
	var side := -1.0 if (uv.facing == 1 or uv.facing == 2) else 1.0
	var vshake: float = sin(time * 55) * uv.shake * 3 if uv.shake else 0.0
	var hop: float = uv.hop
	var walk: float = uv.walk_t * 3.3
	# A war machine stands among its crew: those behind it are drawn first.
	var eng = engine_of(uv, u) if _engine_stands(uv) else null
	var engine_drawn: bool = eng == null
	var tinted: bool = uv.statuses.size() > 0
	for m in bodies:
		if not engine_drawn and m.y + m.lunge.y > eng.oy:
			engine_drawn = true
			_draw_engine(ci, uv, eng, base_scale, alpha, dim, time)
		var ms := member_sprite(uv, m)
		var s: Dictionary = ms[0]
		var flip: bool = ms[1]
		var phase: float = m.phase
		# Marching: one shared cadence with a little personal slack, so the
		# squad keeps step without moving like a single cut-out.
		var bob := marching * absf(sin((walk + phase * 0.05) * PI)) * 3.4
		var shake_x: float = sin(time * 60 + m.id) * m.shake * 2.5 if m.shake else 0.0
		var qx: float = bx + m.x + m.lunge.x + idle * sin(time * 0.43 + phase * 2.3) * 0.8 + shake_x + vshake
		var qy: float = by + m.y + m.lunge.y - bob - hop
		# The champion stands a head taller than his guard.
		var scale := base_scale * 1.18 if m.id == champ else base_scale
		if m.dying:
			# Falls: tips over, then settles into the body left on the field.
			var k := Iso.ease_out_cubic(m.death_t)
			var settle := Iso.clamp((m.death_t - 0.55) / 0.45, 0, 1)
			var dir := -1.0 if m.fall_flip else 1.0
			if settle < 1:
				_blit(ci, s, qx, qy + k * 3, flip, scale, Color(1, 1, 1, alpha * (1 - settle)), 1.0, dir * k * 1.35)
			if settle > 0:
				_blit(ci, Assets.sprite("%s_dead" % m.type, m.variant), qx, qy, m.fall_flip, scale, Color(1, 1, 1, alpha * settle * 0.9))
			if m.flash > 0:
				_blit(ci, s, qx, qy + k * 3, flip, scale, Color(Assets.FLASH, Assets.FLASH, Assets.FLASH, m.flash * 0.7 * (1 - settle)), 1.0, dir * k * 1.35)
			continue
		var breathe := 1 + sin(time * 2.2 + phase) * 0.016 * idle
		var rot := sin(time * 1.1 + phase) * 0.014 * idle + side * 0.05 * marching
		_blit_m(ci, ms, qx, qy, scale, white, breathe, rot)
		if dim > 0:
			_blit_m(ci, ms, qx, qy, scale, Color(0, 0, 0, alpha * dim), breathe, rot)
		if tinted:
			_draw_tints(ci, uv, s, qx, qy, flip, scale, alpha, breathe, rot, time, phase)
		if m.flash > 0:
			_blit_m(ci, ms, qx, qy, scale, Color(Assets.FLASH, Assets.FLASH, Assets.FLASH, m.flash * 0.8), breathe, rot)
		if m == bearer and (fighting or uv.reserve):
			ci.draw_set_transform_matrix(Assets.draw_base)
			_draw_standard(ci, u, qx, qy, flip, time, alpha)
	if not engine_drawn:
		_draw_engine(ci, uv, eng, base_scale, alpha, dim, time)
	ci.draw_set_transform_matrix(Assets.draw_base)


## The soldier carrying the squad's standard: the middle of the rear rank.
func _standard_bearer(uv, u: Dictionary) -> Variant:
	if u.size <= 3 or uv.routing:
		return null
	var live := SquadView.standing(uv.members)
	if live.size() < 2:
		return null
	# A champion carries his own banner (the warlord's war standard).
	if SquadView.champion_of(u) >= 0:
		return null
	var fc := Formation.faces_camera(uv.facing)
	var rear_y := INF if fc else -INF
	for m in live:
		rear_y = minf(rear_y, m.to_y) if fc else maxf(rear_y, m.to_y)
	# The most central of the rear rank (the first of equals, as a stable sort gives).
	var best = null
	for m in live:
		if absf(m.to_y - rear_y) < 3 and (best == null or absf(m.to_x) < absf(best.to_x)):
			best = m
	return best


## A small standard on a pole, waving: the squad's colours.
func _draw_standard(ci: CanvasItem, u: Dictionary, x: float, y: float, flip: bool, time: float, alpha: float) -> void:
	var H := SquadView.member_height(u.typeId)
	var px := x + (-9.0 if flip else 9.0)
	var top := y - H - 13
	var goblin: bool = String(u.typeId).begins_with("goblin")
	var player: bool = u.faction == "player"
	var collie: bool = u.typeId == "collie_guard"
	var cloth := (Color.html("#1e1c1a") if collie else Color.html("#2f58b8")) if player else (Color.html("#a3261c") if goblin else Color.html("#7a2418"))
	var trim := (Color.html("#d6a840") if collie else Color.html("#ece2c6")) if player else Color.html("#1c1612")
	var dir := -1.0 if flip else 1.0
	var pole := Color.html("#3a2614")
	pole.a = alpha
	ci.draw_line(Vector2(px, y - H * 0.35), Vector2(px, top), pole, 2.0, true)
	# Cloth: a short pennant whose free edge ripples.
	var w := 17.0
	var hgt := 11.0
	var pts := PackedVector2Array()
	pts.resize(10)
	pts[0] = Vector2(px, top + 1)
	for i in range(1, 6):
		var f := i / 5.0
		pts[i] = Vector2(px + dir * w * f, top + 1 + sin(time * 5 - f * 4) * 2.2 * f)
	var tail := 0.55 if goblin else 0.75
	pts[6] = Vector2(px + dir * w * tail, top + hgt * 0.55 + sin(time * 5 - 3) * 2)
	pts[7] = Vector2(px + dir * w, top + hgt + sin(time * 5 - 4) * 2.2)
	pts[8] = Vector2(px, top + hgt)
	pts[9] = pts[0]
	cloth.a = alpha
	# Star-shaped from the pole's top: a fan.
	var cols := PackedColorArray()
	cols.resize(9)
	cols.fill(cloth)
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), FAN9, pts.slice(0, 9), cols)
	ci.draw_polyline(pts, Color(30 / 255.0, 18 / 255.0, 10 / 255.0, 0.85 * alpha), 1.2, true)
	# Device: a pale eagle dot for the company, a skull for the raiders.
	trim.a = alpha
	var dc := Vector2(px + dir * w * 0.38, top + hgt * 0.5 + sin(time * 5 - 1.5) * 0.8)
	ci.draw_texture_rect(_disc(), Rect2(dc.x - 2.6, dc.y - 2.6, 5.2, 5.2), false, trim)


const FAN9 := [0, 1, 2, 0, 2, 3, 0, 3, 4, 0, 4, 5, 0, 5, 6, 0, 6, 7, 0, 7, 8]


# ---------------------------------------------------------------- overlays (screen)

func draw_overlays(ci: CanvasItem) -> void:
	var b = v.b
	var w: float = v._w
	var h: float = v._h
	var time: float = v.time
	# One shared health bar per squad, cut into one segment per soldier, with
	# morale beneath; drawn in screen space for crispness. Status labels go on
	# after every bar, so a crowded line never hides one under its neighbour's bar.
	var labels: Array = []
	for uv in v.views.values():
		if not uv.visible or uv.reserve or uv.status == "dead" or uv.status == "downed" or uv.status == "fled" or uv.alive <= 0:
			continue
		var u: Dictionary = v._u(uv.uid)
		var head: Vector2 = v._head_pos(uv)
		var s: Vector2 = v.cam.world_to_screen(head.x, head.y, w, h)
		var n: int = u.size
		var gap := 2
		var seg := 17 if n <= 3 else 8
		var bw := n * seg + (n - 1) * gap
		var x := JS.rnd(s.x - bw / 2.0)
		var y := JS.rnd(s.y - 8)
		if x + bw + 200 < 0 or x - 20 > w or y + 20 < 0 or y - 20 > h:
			continue
		ci.draw_rect(Rect2(x - 2, y - 2, bw + 4, 12), rgba(15, 10, 6, 0.78))
		var player: bool = u.faction == "player"
		var color := (Color.html("#e0a03a") if float(uv.alive) / n <= 0.34 else Color.html("#58b84a")) if player else Color.html("#d9473a")
		for i in n:
			var sx := x + i * (seg + gap)
			if i >= uv.alive:
				# A fallen soldier's share: dark, with a small cross.
				ci.draw_rect(Rect2(sx, y, seg, 5), rgba(70, 40, 30, 0.9))
				var cc := rgba(220, 120, 100, 0.65)
				ci.draw_line(Vector2(sx + seg / 2.0 - 2, y + 0.5), Vector2(sx + seg / 2.0 + 2, y + 4.5), cc, 1.0, true)
				ci.draw_line(Vector2(sx + seg / 2.0 + 2, y + 0.5), Vector2(sx + seg / 2.0 - 2, y + 4.5), cc, 1.0, true)
				continue
			ci.draw_rect(Rect2(sx, y, seg, 5), rgba(60, 50, 40, 0.9))
			var f := Iso.clamp((uv.hp - i * u.hpPer) / float(u.hpPer), 0, 1)
			var fw := maxi(1 if f > 0 else 0, JS.rnd(seg * f))
			if fw > 0:
				ci.draw_rect(Rect2(sx, y, fw, 5), color)
		var mf := Iso.clamp(uv.morale / float(u.maxMorale), 0, 1)
		var ms: String = "broken" if uv.routing else v.morale_of(uv.morale, u.maxMorale)
		var mw := JS.rnd(bw * mf)
		if mw > 0:
			ci.draw_rect(Rect2(x, y + 6, mw, 2), v.MORALE_COLORS[ms])
		# Icons.
		var ix := [x + bw + 6]
		var icon := func(txt: String, col: Color) -> void:
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			labels.append([ix[0], y, txt, col, tw])
			ix[0] += tw + 7
		var stance = uv.stance
		if uv.routing:
			icon.call("FLEEING", Color.html("#f2efe4"))
		elif stance == "shieldwall":
			icon.call("WALL", Color.html("#e9d58f"))
		elif stance == "spearwall":
			icon.call("SPEARS", Color.html("#e9d58f"))
		elif stance == "overwatch":
			icon.call("WATCH", Color.html("#e9d58f"))
		for st in uv.statuses:
			icon.call(v.STATUS_LABEL[st], v.STATUS_COLOR[st])
		if u.leader:
			icon.call("★", Color.html("#ffcf5a"))
		if u.tags.has("warchief"):
			icon.call("WARCHIEF", Color.html("#ffcf5a"))
		var horn_turn = v._objective().get("hornTurn")
		if u.tags.has("herald") and b.horn == "waiting" and horn_turn != null:
			var left: int = horn_turn - v.ui.turn
			icon.call("HORN NOW" if left <= 0 else "HORN IN %d" % left, Color.html("#ffb070"))
		if player and b.phase == "player" and u.done:
			ci.draw_rect(Rect2(x - 2, y - 2, bw + 4, 12), rgba(15, 10, 6, 0.6))
	for l in labels:
		ci.draw_rect(Rect2(l[0] - 2, l[1] - 3, l[4] + 4, 14), rgba(15, 10, 6, 0.8))
		ci.draw_string(font, Vector2(l[0], l[1] + 8), l[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, l[3])
	# The chosen arrival facing once more over everything, bars included: in a
	# crowded yard it is the one thing the player must not lose.
	var hv: Dictionary = v.ui.hover
	if hv.get("dest") != null and hv.get("facing") != null and not v.busy() and v.selected_unit() != null:
		draw_facing_arrow(ci, hv.dest, hv.facing, 0.8, true, true)
	_draw_wave_labels(ci, w, h, time)


## Over each wave massing beyond the field: how many squads and when they
## march in. A wave whose ground is off screen gets an arrow at the screen
## edge pointing to it.
func _draw_wave_labels(ci: CanvasItem, w: float, h: float, time: float) -> void:
	var staged: Dictionary = v.staged()
	if staged.is_empty():
		return
	var groups := {}
	var waves: Array = v._waves()
	for i in waves.size():
		for uid in waves[i].uids:
			if not staged.has(uid):
				continue
			var due_in: int = staged[uid]
			var p: Vector2 = v._head_pos(v.views[uid])
			if not groups.has(i):
				groups[i] = {"xs": [], "ys": [], "dueIn": due_in}
			groups[i].xs.append(p.x)
			groups[i].ys.append(p.y)
	var used: Array = []
	for i in groups:
		var g: Dictionary = groups[i]
		var wave: Dictionary = waves[i]
		var wx: float = JS.sum(g.xs) / g.xs.size()
		var wy: float = JS.min_of(g.ys) - 30
		var s: Vector2 = v.cam.world_to_screen(wx, wy, w, h)
		var due: int = g.dueIn
		var when := "marches in at the end of this turn" if due <= 0 else ("marches in next turn" if due == 1 else "in %d turns" % due)
		var text := "%s · %d squads · %s" % [wave.label, wave.uids.size(), when]
		var pulse := 0.75 + 0.25 * sin(time * 6) if due <= 0 else 0.85
		var on := s.x > 40 and s.x < w - 40 and s.y > 70 and s.y < h - 40
		if on:
			var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			# Keep clear of the company list (left), the top bar, the info panel
			# (top right), the panels at the bottom, and the other wave labels.
			var lx := Iso.clamp(s.x, 270 + tw / 2, w - 16 - tw / 2)
			var ly := Iso.clamp(s.y, 178 if lx + tw / 2 > w - 300 else 128, h - 210)
			while used.any(func(q): return absf(q.x - lx) < (tw + q.w) / 2 + 6 and absf(q.y - ly) < 24):
				ly += 26
			used.append({"x": lx, "y": ly, "w": tw})
			var r := Rect2(lx - tw / 2 - 8, ly - 16, tw + 16, 22)
			ci.draw_rect(r, rgba(40, 8, 4, 0.82 * pulse))
			ci.draw_rect(r, rgba(255, 100, 80, 0.8 * pulse), false, 1.5)
			var tc := Color.html("#ffb4a0")
			tc.a = pulse
			ci.draw_string(font, Vector2(lx - tw / 2, ly), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tc)
			continue
		# Off screen: an arrow at the border pointing toward the wave.
		var cx := w / 2
		var cy := h / 2
		var dx := s.x - cx
		var dy := s.y - cy
		var k := minf((w / 2 - 70) / maxf(1.0, absf(dx)), (h / 2 - 90) / maxf(1.0, absf(dy)))
		var ax := cx + dx * k
		var ay := cy + dy * k
		var ang := atan2(dy, dx)
		var xf := Transform2D(ang, Vector2(ax, ay))
		var arrow := PackedVector2Array([xf * Vector2(22, 0), xf * Vector2(-10, -14), xf * Vector2(-4, 0), xf * Vector2(-10, 14)])
		var fc := Color.html("#e8503a")
		fc.a = pulse
		fill_poly(ci, arrow, fc)
		stroke_poly(ci, arrow, rgba(30, 8, 4, 0.9 * pulse), 2.0)
		var label := "%d squads %s" % [wave.uids.size(), "this turn" if due <= 0 else ("next turn" if due == 1 else "in %d turns" % due)]
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var lx := Iso.clamp(ax - tw / 2, 8, w - tw - 8)
		var ly := Iso.clamp(ay + (-26 if dy > 0 else 34), 64, h - 10)
		# Clear of the company list on the left, and of any label already placed.
		if lx < 262 and ly < 620:
			lx = 262
		while used.any(func(q): return absf(q.x - lx) < tw and absf(q.y - ly) < 22):
			ly += 24
		used.append({"x": lx, "y": ly, "w": tw})
		ci.draw_rect(Rect2(lx - 6, ly - 14, tw + 12, 19), rgba(40, 8, 4, 0.8 * pulse))
		var lc := Color.html("#ffb4a0")
		lc.a = pulse
		ci.draw_string(font, Vector2(lx, ly), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, lc)


# ---------------------------------------------------------------- screen flash

## Lightning lights up the whole field for an instant; a fireball's burst warms
## it (additive over the world, under the night; the layer's material adds it).
func draw_screen_flash(ci: CanvasItem) -> void:
	var f: Dictionary = v.flash
	if f.a <= 0.01:
		return
	var c: Color = f.color
	ci.draw_rect(Rect2(0, 0, v._w, v._h), Color(c.r + Fx.ADD, c.g, c.b, f.a * 0.2))


# ---------------------------------------------------------------- minimap

## The field drawn once, tile by tile, behind the minimap's markers (buildMinimap).
func draw_minimap_base(ci: CanvasItem) -> void:
	if v.b.map.get("scale") != "large":
		return
	var r: Dictionary = v.minimap_rect()
	ci.draw_rect(Rect2(r.x - 4, r.y - 4, r.w + 8, r.h + 8), rgba(14, 10, 6, 0.82))
	ci.draw_rect(Rect2(r.x - 4, r.y - 4, r.w + 8, r.h + 8), rgba(205, 184, 138, 0.7), false, 1.5)
	var m: Dictionary = v.b.map
	# One triangle array for the whole field (a polygon per tile is a draw call each).
	var geo := Geo.new()
	for g in m.get("outerGround", []):
		_mini_dia(geo, r, g.x, g.y, _terrain_color(g.terrain))
	for t in m.tiles:
		_mini_dia(geo, r, t.x, t.y, _mini_col(t))
	geo.flush(ci)


func _mini_dia(geo: Geo, r: Dictionary, gx: float, gy: float, fill: Color) -> void:
	var px: float = r.x + (Iso.iso_x(gx, gy) - r.ox) * r.k
	var py: float = r.y + (Iso.iso_y(gx, gy) - r.oy) * r.k
	var hw: float = (TW / 2) * r.k + 0.4
	var hh: float = (TH / 2) * r.k + 0.4
	geo.poly(PackedVector2Array([Vector2(px, py - hh), Vector2(px + hw, py), Vector2(px, py + hh), Vector2(px - hw, py)]), fill)


static func _terrain_color(terrain: String) -> Color:
	var t = DB.TERRAIN.get(terrain)
	return Color.html(t.color) if t != null and t.get("color") != null else Color.html("#7fa23a")


static func _mini_col(t: Dictionary) -> Color:
	var p = t.get("prop")
	if p != null:
		var ps: String = p
		if ps.begins_with("tree"):
			return Color.html("#2c4a1e")
		if ps.begins_with("palisade") or ps == "wall_high":
			return Color.html("#5a3a20")
		if ps.begins_with("gate"):
			return Color.html("#c9a35a")
		if ps.begins_with("wall") or ps.begins_with("rock"):
			return Color.html("#8a8a80")
		if ps == "stakes":
			return Color.html("#7a5030")
	return _terrain_color(t.terrain)


## Whether the minimap's static base must be painted again (its rect changed).
func minimap_key() -> String:
	var r: Dictionary = v.minimap_rect()
	return "%s,%s,%s,%s" % [r.x, r.y, r.w, r.h]


## The minimap's live markers: the ground to hold, the squads and the camera's view.
func draw_minimap(ci: CanvasItem) -> void:
	if v.b.map.get("scale") != "large":
		return
	var r: Dictionary = v.minimap_rect()
	var time: float = v.time
	var at := func(gx: float, gy: float) -> Vector2: return Vector2(r.x + (Iso.iso_x(gx, gy) - r.ox) * r.k, r.y + (Iso.iso_y(gx, gy) - r.oy) * r.k)
	# Ground to hold.
	var zc := rgba(255, 80, 60, 0.55) if v._overrun_warn else rgba(255, 215, 106, 0.45)
	for p in v.b.map.get("zone", []):
		var q: Vector2 = at.call(p.x, p.y)
		ci.draw_rect(Rect2(q.x - 1.5, q.y - 1, 3, 2), zc)
	# Squads: the company blue, the horde red, coming waves dark red beyond the edge.
	var staged: Dictionary = v.staged()
	for uv in v.views.values():
		var waiting: bool = uv.reserve and staged.has(uv.uid)
		if not (uv.visible or waiting) or uv.status == "dead" or uv.status == "downed" or uv.status == "fled":
			continue
		var u: Dictionary = v._u(uv.uid)
		var q: Vector2 = at.call(uv.x, uv.y)
		var player: bool = u.faction == "player"
		var col: Color
		if waiting:
			col = rgba(150, 30, 20, 0.6 + 0.3 * sin(time * 4))
		elif player:
			col = Color.html("#ffd76a") if v.ui.selected == uv.uid else Color.html("#7fb4ff")
		else:
			col = Color.html("#d9b0a0") if uv.routing else Color.html("#ff4a36")
		var s := 4.0 if player else 3.4
		ci.draw_rect(Rect2(q.x - s / 2, q.y - s / 2, s, s), col)
	# The camera's view.
	var tl: Vector2 = v.cam.screen_to_world(0, 0, v._w, v._h)
	var br: Vector2 = v.cam.screen_to_world(v._w, v._h, v._w, v._h)
	var x0 := Iso.clamp(r.x + (tl.x - r.ox) * r.k, r.x, r.x + r.w)
	var y0 := Iso.clamp(r.y + (tl.y - r.oy) * r.k, r.y, r.y + r.h)
	var x1 := Iso.clamp(r.x + (br.x - r.ox) * r.k, r.x, r.x + r.w)
	var y1 := Iso.clamp(r.y + (br.y - r.oy) * r.k, r.y, r.y + r.h)
	ci.draw_rect(Rect2(x0, y0, x1 - x0, y1 - y0), Color(1, 1, 1, 0.85), false, 1.2)
