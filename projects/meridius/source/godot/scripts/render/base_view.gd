## The Amberfeld garrison: painted ground, the forest outside the palisade,
## the six buildings at their levels with nameplates, soldiers strolling
## between them, campfire smoke, and the camera framing of the camp.
## Port of src/render/baseScene.ts (class BaseScene).
##
## Hosting (UI agent):
##   var view = preload("res://scenes/base/base_view.tscn").instantiate()
##   view.setup(func(): return App.game)          # getGame
##   view.building_clicked.connect(App.open_panel) # onBuilding
##   view.changed.connect(...)                     # subscribe/notify (ui.version)
##   view.dim = true / false                       # behind panels: no hover, no
##                                                 # nameplates, darkened
##   view.spawn_walkers(App.game)                  # after the roster changes
## Public state mirrors the class: cam, atmo, fx, terrain, ui {hover?, version},
## dim. The node sits at the viewport origin; the view size is its viewport's
## visible rect (Camera.view_size).
extends Node2D

const Iso = preload("res://scripts/render/iso.gd")
const Rng = preload("res://scripts/core/rng.gd")
const JS = preload("res://scripts/core/js.gd")
const DB = preload("res://scripts/data/db.gd")
const Camera = preload("res://scripts/render/camera.gd")
const Terrain = preload("res://scripts/render/terrain.gd")
const Atmosphere = preload("res://scripts/render/atmosphere.gd")
const Fx = preload("res://scripts/render/fx.gd")
const Assets = preload("res://scripts/render/assets.gd")
const WD = preload("res://scripts/render/world_draw.gd")
const WorldCanvas = preload("res://scripts/render/world_canvas.gd")

const N := 16
const HOME_Y := (8 + 8) * 32.0 - 30.0 # isoY(8, 8) - 30
const HOME_ZOOM := 0.62
## Screen px kept clear above the highest nameplate (top bar) and below the lowest building.
const TOP_CLEAR := 78.0
const BOTTOM_CLEAR := 16.0

const SPOTS := [
	[6, 8], [10, 8], [8, 7], [6.4, 10], [9.4, 9.6], [12.6, 8.6], [5.6, 7], [10.6, 7], [8.8, 10.6], [13.4, 8.6], [7, 9.6], [11.2, 9.6],
]

## Hover and clicks (onBuilding / subscribe).
signal building_clicked(id: String)
signal changed

var get_game: Callable = func() -> Variant: return null
var terrain: Node2D
var cam: RefCounted
var atmo: RefCounted
var fx: RefCounted = Fx.new()
## BaseUi: {hover?: String, version: int}
var ui := {"version": 0}
var dim := false
var time := 0.0

var props: Array = [] # {x, y, prop, v, s}
var stakes: Array = [] # {x, y}
var walkers: Array = []
## Nameplate rectangles in world space from the last frame, for hit-testing.
var plates := {}
var _w := 1920.0
var _h := 1080.0
var rng := Rng.new(7)
var _framed := ""
var _static: Array = [] # sorted static draw items
var _static_levels := ""

var _world: Node2D
var _back: Node2D
var _flash: Node2D
var _front: Node2D
var _air: Node2D
var _plates_node: Node2D
var _bg: Node2D
var _screen: Node2D
var _dim_node: Node2D
var _split_items: Array = [[], [], null]


## The garrison's ground (baseScene constructor): grass inside and out, dirt
## paths from each building to the fire and out of the gate.
static func terrain_input() -> Dictionary:
	var tiles: Array = []
	var path := {}
	var centre := [8, 8.6]
	var line := func(ax0: float, ay0: float, bx0: float, by0: float) -> void:
		# Walk whole tiles: round the endpoints so the loop always terminates.
		var ax := JS.rnd(ax0)
		var ay := JS.rnd(ay0)
		var bx := JS.rnd(bx0)
		var by := JS.rnd(by0)
		var x := ax
		var y := ay
		while x != bx or y != by:
			path[y * 100 + x] = true
			if x != bx:
				x += signi(bx - x)
			else:
				y += signi(by - y)
		path[by * 100 + bx] = true
	for b in DB.BUILDINGS:
		line.call(b.pos[0], b.pos[1] + 1, centre[0], centre[1])
	line.call(centre[0], centre[1], 15, centre[1])
	for y in N:
		for x in N:
			var terrain := "grass"
			if path.has(y * 100 + x):
				terrain = "dirt"
			if JS.hypot(x - centre[0], y - centre[1]) < 1.8:
				terrain = "dirt"
			tiles.append({"x": x, "y": y, "h": 0, "terrain": terrain})
	return {"w": N, "h": N, "border": 8, "tiles": tiles, "seed": 4242, "palette": "base", "res": 22, "scale": 0.75}


## The palisade, the forest outside the walls and the decor inside
## (constructor, in the original's Rng order).
static func layout() -> Dictionary:
	var stakes_out: Array = []
	var props_out: Array = []
	var centre := [8, 8.6]
	# Palisade along the perimeter, with a gate on the south-east side.
	for i in range(1, 15):
		stakes_out.append({"x": i, "y": 0.6})
		stakes_out.append({"x": 0.6, "y": i})
		if not (i >= 8 and i <= 10):
			stakes_out.append({"x": 14.4, "y": i})
		stakes_out.append({"x": i, "y": 14.4})
	var r := Rng.new(99)
	# Forest outside the walls.
	for y in range(-8, N + 8):
		for x in range(-8, N + 8):
			var inside := x >= -1 and y >= -1 and x <= 16 and y <= 16
			if inside:
				continue
			var near_road := absf(y - centre[1]) < 1.6 and x > 14
			if near_road:
				continue
			if r.chance(0.7):
				var px := x + r.frange(-0.3, 0.3)
				var py := y + r.frange(-0.3, 0.3)
				var prop := "tree_pine" if r.chance(0.6) else "tree_oak"
				var v := r.rint(0, 9)
				props_out.append({"x": px, "y": py, "prop": prop, "v": v, "s": r.frange(0.85, 1.2)})
	# Decor inside the walls.
	var decor := [
		[8, 8.6, "campfire"], [9.6, 10.4, "crates"], [2.0, 2.2, "crates"], [10.4, 1.8, "crates"],
		[2.2, 13.4, "bush"], [13.4, 13.4, "bush"], [5.8, 2.0, "rock_small"], [2.0, 8.0, "fence_y"],
	]
	for d in decor:
		props_out.append({"x": d[0], "y": d[1], "prop": d[2], "v": floori(d[0] * 3 + d[1]), "s": 1})
	return {"stakes": stakes_out, "props": props_out}


func _init() -> void:
	var keys := ["tree_pine", "tree_oak", "palisade_x", "palisade_y", "gate_tower", "campfire", "crates", "bush", "rock_small", "fence_y"]
	for b in DB.BUILDINGS:
		for lvl in range(1, 4):
			keys.append("b_%s_%d" % [b.id, lvl])
	for t in DB.PLAYER_TYPES:
		keys.append("%s_idle_f" % t)
		keys.append("%s_idle_b" % t)
	Assets.warm_async(keys)
	var l := layout()
	stakes = l.stakes
	props = l.props
	cam = Camera.new(Iso.iso_x(8, 8), HOME_Y, HOME_ZOOM)
	atmo = Atmosphere.new(77)


## getGame (the constructor's first argument); spawns the walkers.
func setup(game_getter: Callable) -> void:
	get_game = game_getter
	var g: Variant = get_game.call()
	if g != null:
		spawn_walkers(g)


func _ready() -> void:
	_bg = WorldCanvas.new(func(ci: CanvasItem) -> void: ci.draw_rect(Rect2(Vector2.ZERO, Vector2(_w, _h)), Color8(0x1b, 0x28, 0x12)), "Background")
	add_child(_bg)
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	terrain = Terrain.build_terrain(terrain_input())
	_world.add_child(terrain)
	_world.add_child(atmo.make_clouds_node(Iso.iso_x(8, 8), Iso.iso_y(8, 8)))
	_back = WorldCanvas.new(func(ci: CanvasItem) -> void: _draw_items(ci, _split_items[0]), "Back")
	_world.add_child(_back)
	_flash = WorldCanvas.new(_draw_flash, "Flash")
	_flash.material = Assets.additive_material()
	_world.add_child(_flash)
	_front = WorldCanvas.new(func(ci: CanvasItem) -> void: _draw_items(ci, _split_items[1]), "Front")
	_world.add_child(_front)
	_air = WorldCanvas.new(func(ci: CanvasItem) -> void: fx.draw_air(ci), "Air")
	_world.add_child(_air)
	_plates_node = WorldCanvas.new(_draw_plates, "Plates")
	_world.add_child(_plates_node)
	_screen = Node2D.new()
	_screen.name = "Screen"
	add_child(_screen)
	_screen.add_child(atmo.make_grade_node())
	_dim_node = WorldCanvas.new(func(ci: CanvasItem) -> void:
		if dim:
			ci.draw_rect(Rect2(Vector2.ZERO, Vector2(_w, _h)), Color(15 / 255.0, 10 / 255.0, 5 / 255.0, 0.45)), "Dim")
	_screen.add_child(_dim_node)
	_refresh_view()


func _notify() -> void:
	ui.version += 1
	changed.emit()


# ---------------------------------------------------------------- sound

## On screen the camp is heard: its ambience, the fire crackling where it burns
## (placed by this view's camera), and its camera places other sounds.
func _enter_tree() -> void:
	var s := _audio()
	if s == null or not s.has_method("set_ambience"):
		return
	s.set_listener(self)
	s.set_ambience("camp")
	s.set_anchor("campfire", Vector2(Iso.iso_x(8, 8.6), Iso.iso_y(8, 8.6)))


func _exit_tree() -> void:
	var s := _audio()
	if s == null or not s.has_method("set_ambience"):
		return
	s.clear_listener(self)
	s.clear_anchor("campfire")
	s.release_ambience("camp")


## The Sfx autoload, or null (tools and tests run the view without it).
func _audio() -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	return ml.root.get_node_or_null("Sfx") if ml != null else null


func spawn_walkers(g: Dictionary) -> void:
	walkers = []
	var roster: Array = g.get("roster", [])
	for i in mini(9, roster.size()):
		var s: Dictionary = roster[i]
		var spot: Array = SPOTS[i % SPOTS.size()]
		walkers.append({"type": s.typeId, "variant": int(s.get("variant", 0)), "x": float(spot[0]), "y": float(spot[1]), "tx": float(spot[0]), "ty": float(spot[1]), "wait": 1 + i * 0.7, "facing": 1, "phase": i * 1.7})


# ---------------------------------------------------------------- update


func _process(delta: float) -> void:
	var dt := minf(0.05, delta)
	time += dt
	update(dt)
	_refresh_view()


func update(dt: float) -> void:
	cam.pan_keys(dt, 600.0, self)
	cam.update(dt)
	atmo.update(dt, _w, _h)
	fx.update(dt)
	for w in walkers:
		if w.wait > 0:
			w.wait -= dt
			if w.wait <= 0:
				var spot: Array = rng.pick(SPOTS)
				w.tx = spot[0] + rng.frange(-0.4, 0.4)
				w.ty = spot[1] + rng.frange(-0.4, 0.4)
			continue
		var dx: float = w.tx - w.x
		var dy: float = w.ty - w.y
		var d := JS.hypot(dx, dy)
		if d < 0.05:
			w.wait = 2 + rng.next() * 5
			continue
		var sp := 0.9 * dt
		w.x += (dx / d) * minf(sp, d)
		w.y += (dy / d) * minf(sp, d)
		w.phase += dt * 9
		w.facing = (0 if dx > 0 else 2) if absf(dx) > absf(dy) else (1 if dy > 0 else 3)
	# Campfire smoke and sparks.
	if randf() < dt * 6:
		fx.burst(Iso.iso_x(8, 8.6), Iso.iso_y(8, 8.6) - 20, 10, 1, {"shape": "puff", "color": "rgba(210,210,205,1)", "speed": 6, "vz": 40, "gravity": -8, "size": 10, "max": 3, "drag": 0.2})
	if randf() < dt * 4:
		fx.burst(Iso.iso_x(8, 8.6), Iso.iso_y(8, 8.6) - 10, 5, 1, {"shape": "dot", "color": "#ffb347", "speed": 10, "vz": 60, "gravity": -10, "size": 2.5, "max": 1.4, "drag": 0.5})


func _game() -> Variant:
	return get_game.call() if get_game.is_valid() else null


func _level(g: Dictionary, id: String) -> int:
	return int(g.get("buildings", {}).get(id, 1))


func _bsprite(g: Dictionary, b: Dictionary) -> Dictionary:
	return Assets.sprite("b_%s_%d" % [b.id, _level(g, b.id)])


## The view's frame: camera transform, framing, draw lists, redraws (render()).
func _refresh_view() -> void:
	var view := Camera.view_size(self)
	_w = view.x
	_h = view.y
	var g: Variant = _game()
	if g != null:
		_frame(g, _w, _h)
	_world.transform = cam.transform(view)
	_build_items(g)
	atmo.redraw(view, time)
	for n in [_bg, _back, _flash, _front, _air, _plates_node, _dim_node]:
		n.queue_redraw()


# ---------------------------------------------------------------- framing


## Frames the camp for the viewport and building levels. The home view is
## kept whenever it shows every building and nameplate; on short viewports
## the camera rises until the tallest nameplate clears the top bar, and zooms
## out only if the camp then no longer fits.
func _frame(g: Dictionary, w: float, h: float) -> void:
	var lv := ""
	for b in DB.BUILDINGS:
		lv += str(_level(g, b.id))
	var key := "%dx%d:%s" % [roundi(w), roundi(h), lv]
	if key == _framed:
		return
	var first := _framed == ""
	_framed = key
	var top := INF
	var bottom := -INF
	for b in DB.BUILDINGS:
		var s := _bsprite(g, b)
		var y := Iso.iso_y(b.pos[0], b.pos[1])
		top = minf(top, y - s.ay * s.scale)
		bottom = maxf(bottom, y + (s.h - s.ay) * s.scale)
	var zoom := HOME_ZOOM
	var cy := HOME_Y
	if (top - cy) * zoom + h / 2 < TOP_CLEAR:
		cy = top + (h / 2 - TOP_CLEAR) / zoom
	if (bottom - cy) * zoom + h / 2 > h - BOTTOM_CLEAR:
		zoom = maxf(0.4, (h - TOP_CLEAR - BOTTOM_CLEAR) / (bottom - top))
		cy = top + (h / 2 - TOP_CLEAR) / zoom
	cam.tx = Iso.iso_x(8, 8)
	cam.ty = cy
	cam.tzoom = zoom
	if first:
		cam.x = cam.tx
		cam.y = cy
		cam.zoom = zoom


# ---------------------------------------------------------------- picking


func building_at(sx: float, sy: float) -> Variant:
	var g: Variant = _game()
	if g == null:
		return null
	var wp: Vector2 = cam.screen_to_world(sx, sy, _w, _h)
	var placed: Array = []
	for b in DB.BUILDINGS:
		var s := _bsprite(g, b)
		placed.append({"b": b, "s": s, "x": Iso.iso_x(b.pos[0], b.pos[1]), "y": Iso.iso_y(b.pos[0], b.pos[1])})
	placed = JS.sort(placed, func(p, q): return (q.b.pos[0] + q.b.pos[1]) - (p.b.pos[0] + p.b.pos[1]))
	# Nameplates are drawn on top, then sprites front to back: the first
	# opaque hit is the building the player sees under the cursor.
	for id in plates:
		var r: Dictionary = plates[id]
		if wp.x >= r.x and wp.x <= r.x + r.w and wp.y >= r.y and wp.y <= r.y + r.h:
			return id
	for p in placed:
		var s: Dictionary = p.s
		if Assets.opaque_at(s, (wp.x - p.x) / s.scale + s.ax, (wp.y - p.y) / s.scale + s.ay):
			return p.b.id
	# Open ground inside a building's plot (the drill field between dummies).
	var best: Variant = null
	var bd := INF
	for p in placed:
		var s: Dictionary = p.s
		var top: float = p.y - s.ay * s.scale
		var half: float = (s.w * s.scale) / 2.0
		if wp.x > p.x - half * 0.8 and wp.x < p.x + half * 0.8 and wp.y > top + 10 and wp.y < p.y + 30:
			var d: float = absf(wp.x - p.x) + absf(wp.y - (p.y - 60))
			if d < bd:
				bd = d
				best = p.b.id
	return best


func pointer_move(sx: float, sy: float) -> void:
	var id: Variant = null if dim else building_at(sx, sy)
	if id != ui.get("hover"):
		if id == null:
			ui.erase("hover")
		else:
			ui["hover"] = id
		_notify()


func pointer_down(sx: float, sy: float, button: int) -> void:
	if button != MOUSE_BUTTON_LEFT or dim:
		return
	var id: Variant = building_at(sx, sy)
	if id != null:
		building_clicked.emit(id)


func wheel(delta: float) -> void:
	cam.wheel(delta, 0.4, 1.3)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var p := Camera.view_local(self, e.position)
		pointer_move(p.x, p.y)
	elif e is InputEventMouseButton and e.pressed:
		var p := Camera.view_local(self, e.position)
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			wheel(-1)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			wheel(1)
		else:
			cam.drag_input(e, self)
			pointer_down(p.x, p.y, e.button_index)


func _input(e: InputEvent) -> void:
	cam.drag_motion(e, self)


# ---------------------------------------------------------------- drawing


## Static draw items (props, palisade, gate towers, buildings) sorted once per
## building-level change; walkers are merged in each frame. Same order as the
## original's stable sort of the whole list by depth.
func _build_items(g: Variant) -> void:
	var lv := ""
	if g != null:
		for b in DB.BUILDINGS:
			lv += str(_level(g, b.id))
	if lv != _static_levels or _static.is_empty():
		_static_levels = lv
		var items: Array = []
		for p in props:
			var s := Assets.sprite(p.prop, p.v)
			var flip: bool = not s.get("noShadow", false) and Rng.hash2(p.x * 9, p.y * 9) > 0.5
			items.append({"d": p.x + p.y, "k": 0, "s": s, "x": Iso.iso_x(p.x, p.y), "y": Iso.iso_y(p.x, p.y), "flip": flip, "sc": float(p.s), "tree": str(p.prop).begins_with("tree"), "px": float(p.x)})
		var palisade_art := Assets.has_art("palisade_x") and Assets.has_art("palisade_y")
		for st in stakes:
			if palisade_art:
				var along_x: bool = st.y == 0.6 or st.y == 14.4
				var ps := Assets.sprite("palisade_x" if along_x else "palisade_y", floori(st.x * 3 + st.y * 7))
				items.append({"d": st.x + st.y, "k": 1, "s": ps, "x": Iso.iso_x(st.x, st.y), "y": Iso.iso_y(st.x, st.y)})
			else:
				items.append({"d": st.x + st.y, "k": 2, "gx": float(st.x), "gy": float(st.y)})
		if Assets.has_art("gate_tower"):
			for gt in [[14.5, 7.4], [14.5, 10.6]]:
				var gs := Assets.sprite("gate_tower")
				items.append({"d": gt[0] + gt[1] + 0.2, "k": 1, "s": gs, "x": Iso.iso_x(gt[0], gt[1]), "y": Iso.iso_y(gt[0], gt[1])})
		if g != null:
			for b in DB.BUILDINGS:
				items.append({"d": b.pos[0] + b.pos[1] + 0.6, "k": 3, "id": b.id, "s": _bsprite(g, b), "x": Iso.iso_x(b.pos[0], b.pos[1]), "y": Iso.iso_y(b.pos[0], b.pos[1])})
		for i in items.size():
			items[i]["i"] = i
		_static = JS.sort(items, func(p, q): return p.d - q.d)
	# Walkers, sorted stably, merged after equal-depth static items.
	var moving: Array = []
	for wk in walkers:
		moving.append({"d": wk.x + wk.y + 0.1, "k": 4, "w": wk})
	moving = JS.sort(moving, func(p, q): return p.d - q.d)
	var all: Array = []
	var i := 0
	var j := 0
	while i < _static.size() or j < moving.size():
		if j >= moving.size() or (i < _static.size() and _static[i].d <= moving[j].d):
			all.append(_static[i])
			i += 1
		else:
			all.append(moving[j])
			j += 1
	# Split at the hovered building: its additive flash is drawn right after it.
	var hov: Variant = ui.get("hover")
	var cut := all.size()
	var hov_item: Variant = null
	if hov != null:
		for k in all.size():
			if all[k].k == 3 and all[k].id == hov:
				cut = k + 1
				hov_item = all[k]
				break
	_split_items = [all.slice(0, cut), all.slice(cut), hov_item]


func _draw_items(ci: CanvasItem, items: Array) -> void:
	for it in items:
		match it.k:
			0:
				Assets.draw_cast_shadow(ci, it.s, it.x, it.y, it.flip, it.sc, 0.16)
				Assets.draw_sprite(ci, it.s, it.x, it.y, it.flip, it.sc, Color.WHITE, 1.0, sin(time * 0.9 + it.px) * 0.01 if it.tree else 0.0)
			1:
				Assets.draw_sprite(ci, it.s, it.x, it.y)
			2:
				_draw_stakes(ci, it.gx, it.gy)
			3:
				Assets.draw_cast_shadow(ci, it.s, it.x, it.y, false, 1.0, 0.2)
				Assets.draw_sprite(ci, it.s, it.x, it.y)
			4:
				var wk: Dictionary = it.w
				var front: bool = wk.facing == 0 or wk.facing == 1
				var flip: bool = wk.facing == 0 or wk.facing == 2
				var s := Assets.sprite("%s_idle_%s" % [wk.type, "f" if front else "b"], wk.variant)
				var x := Iso.iso_x(wk.x, wk.y)
				var walking: bool = wk.wait <= 0
				var y := Iso.iso_y(wk.x, wk.y) - (absf(sin(wk.phase)) * 4.0 if walking else 0.0)
				ci.draw_colored_polygon(WD.ellipse(x, Iso.iso_y(wk.x, wk.y) + 2, 22, 10, 0.0, 28), Color(20 / 255.0, 25 / 255.0, 10 / 255.0, 0.3))
				Assets.draw_sprite(ci, s, x, y, flip, 0.8, Color.WHITE, 1.0 + sin(time * 2 + wk.phase) * 0.012)


func _draw_flash(ci: CanvasItem) -> void:
	var it: Variant = _split_items[2]
	if it == null:
		return
	Assets.draw_flash(ci, it.s, it.x, it.y, false, 1.0, 0.18 + 0.06 * sin(time * 5))


func _draw_plates(ci: CanvasItem) -> void:
	var g: Variant = _game()
	if g == null or dim:
		return
	var z: float = cam.zoom
	for b in DB.BUILDINGS:
		var lvl := _level(g, b.id)
		var s := _bsprite(g, b)
		var x := Iso.iso_x(b.pos[0], b.pos[1])
		var y: float = Iso.iso_y(b.pos[0], b.pos[1]) - s.ay * s.scale + 6
		var label: String = b.levels[lvl - 1].name
		var hov: bool = ui.get("hover") == b.id
		var size := (17.0 if hov else 15.0) / maxf(0.5, z)
		var tw := WD.text_width(label, size * z) / z + 22.0 / z
		var rect := Rect2(x - tw / 2, y - size * 1.1, tw, size * 1.5)
		plates[b.id] = {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y}
		ci.draw_rect(rect, Color(70 / 255.0, 45 / 255.0, 20 / 255.0, 0.92) if hov else Color(40 / 255.0, 28 / 255.0, 16 / 255.0, 0.8))
		ci.draw_rect(rect, Color8(0xff, 0xd7, 0x6a) if hov else Color(200 / 255.0, 170 / 255.0, 110 / 255.0, 0.6), false, 1.5 / z, true)
		WD.draw_text(ci, x, y, label, size, Color8(0xff, 0xe9, 0xa8) if hov else Color8(0xef, 0xe3, 0xc4), z)


func _draw_stakes(ci: CanvasItem, gx: float, gy: float) -> void:
	var x := Iso.iso_x(gx, gy)
	var y := Iso.iso_y(gx, gy)
	for i in range(-1, 2):
		var sx := x + i * 20 * (-1 if gx == 14.4 or gx == 0.6 else 1)
		var sy := y + i * 10
		var hgt := 56 + Rng.hash2(gx * 13 + i, gy * 7) * 14
		var poly := PackedVector2Array([Vector2(sx - 7, sy), Vector2(sx - 7, sy - hgt), Vector2(sx, sy - hgt - 12), Vector2(sx + 7, sy - hgt), Vector2(sx + 7, sy)])
		ci.draw_colored_polygon(poly, Color8(0x7a, 0x55, 0x32))
		var loop := poly.duplicate()
		loop.append(poly[0])
		ci.draw_polyline(loop, Color8(0x2a, 0x1d, 0x14), 2.0, true)
		ci.draw_rect(Rect2(sx - 6, sy - hgt, 4, hgt), Color(1.0, 230 / 255.0, 180 / 255.0, 0.25))
