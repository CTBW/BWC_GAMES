## The unit bar's minimap (Godot only): the battle's map in its window, turned
## as the field is seen (a diamond: +x down-right, +y down-left), each tile in
## its terrain's colour, darker under woods and props and shaded by height;
## what the company has never seen black, what it saw once dimmed (the fog);
## the squads it sees as markers, the company's blue, the warband's red, the
## selected squad ringed in gold and pulsing. A click on one of the company's
## squads selects it (the view's own `select`). The map is drawn once per
## battle into a small texture; the fog and the markers are read four times a
## second, not every frame.
##
##   var m = preload("res://scripts/ui/unit_bar/bar_minimap.gd").new()
##   m.view = battle_view         # b (map, units), views, fog, ui.selected, select()
extends Control

const DB = preload("res://scripts/data/db.gd")
const Style = preload("res://scripts/ui/unit_bar/bar_style.gd")
const Tip = preload("res://scripts/ui/widgets/tip.gd")

## How flat the diamond is (1 a square turned 45 degrees).
const SQUASH := 0.62
const RATE := 0.25

var view: Object = null:
	set(v):
		view = v
		_map_of = null
		_poll = 0.0
var _map_of: Variant = null
var _map: ImageTexture
var _fog: ImageTexture
var _fog_img: Image
var _marks: Array = []
var _poll := 0.0
var _pulse := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	Tip.attach(self, "[b]The field[/b]\nWhat the company sees of it. Click one of its squads to select it.")


func _ok() -> bool:
	return view != null and is_instance_valid(view) and view.get("b") != null


func _process(dt: float) -> void:
	if not is_visible_in_tree() or not _ok():
		return
	_pulse += dt
	_poll -= dt
	if _poll <= 0.0:
		_poll = RATE
		_read()
	queue_redraw()


## The map's texture (once per battle), the fog and the markers.
func _read() -> void:
	var map: Dictionary = view.b.map
	if _map_of != map:
		_map_of = map
		_build_map(map)
	var w := int(map.w)
	var h := int(map.h)
	var fog: Object = view.get("fog")
	var fogged: bool = fog != null and fog.has_method("enabled") and fog.enabled()
	if _fog_img == null or _fog_img.get_width() != w or _fog_img.get_height() != h:
		_fog_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var st: int = fog.tile_state(x, y) if fogged else 2
			_fog_img.set_pixel(x, y, Color(0, 0, 0, 0.0 if st == 2 else (0.5 if st == 1 else 1.0)))
	if _fog == null or _fog.get_width() != w or _fog.get_height() != h:
		_fog = ImageTexture.create_from_image(_fog_img)
	else:
		_fog.update(_fog_img)
	_marks.clear()
	var views: Dictionary = view.get("views") if view.get("views") is Dictionary else {}
	for u in view.b.units:
		var v: Variant = views.get(u.uid)
		var status: String = str(v.status if v != null else u.status)
		if status != "active" or (v != null and v.reserve):
			continue
		if u.faction != "player" and v != null and view.has_method("squad_visible") and not view.squad_visible(v):
			continue
		_marks.append({"uid": u.uid, "x": int(v.x if v != null else u.x), "y": int(v.y if v != null else u.y), "faction": u.faction,
			"selected": view.ui.get("selected") == u.uid, "routing": v != null and v.routing})


func _build_map(map: Dictionary) -> void:
	var w := int(map.w)
	var h := int(map.h)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var top := 0.0
	for t in map.tiles:
		top = maxf(top, float(t.get("h", 0)))
	for t in map.tiles:
		var c := Color(DB.TERRAIN.get(t.terrain, {}).get("color", "#7fa23a"))
		var prop: Variant = t.get("prop")
		if prop != null:
			var p: Dictionary = DB.PROPS.get(prop, {})
			c = c.darkened(0.45 if str(prop).begins_with("tree") or prop == "bush" else (0.3 if p.get("blocksMove") else 0.15))
		# Higher ground lighter, as the sun on the field's slopes.
		c = c.lightened(0.18 * float(t.get("h", 0)) / maxf(1.0, top))
		img.set_pixel(int(t.x), int(t.y), c)
	_map = ImageTexture.create_from_image(img)


## The map's frame: tile (x, y) to the window's pixels (the diamond fitted and centred).
func _xform() -> Transform2D:
	var map: Dictionary = view.b.map
	var w := float(map.w)
	var h := float(map.h)
	var span := Vector2(w + h, (w + h) * SQUASH)
	var s := minf((size.x - 10.0) / span.x, (size.y - 10.0) / span.y)
	var ox := (size.x - span.x * s) * 0.5 + h * s
	var oy := (size.y - span.y * s) * 0.5
	return Transform2D(Vector2(s, s * SQUASH), Vector2(-s, s * SQUASH), Vector2(ox, oy))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Style.WELL)
	if not _ok() or _map == null:
		return
	var xf := _xform()
	var map: Dictionary = view.b.map
	var full := Rect2(0, 0, float(map.w), float(map.h))
	# The diamond's dark edge, then the field and the fog over it.
	draw_set_transform_matrix(xf)
	draw_rect(full.grow(0.35), Style.INK)
	draw_texture_rect(_map, full, false)
	if _fog != null:
		draw_texture_rect(_fog, full, false)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var k := xf.x.length()
	for m in _marks:
		var c: Vector2 = xf * Vector2(m.x + 0.5, m.y + 0.5)
		var col: Color = Style.MORALE if m.faction == "player" else Style.HP_LOW
		var r := maxf(3.0, k * 0.9)
		if m.selected:
			var p := 0.5 + 0.5 * sin(_pulse * 5.0)
			draw_circle(c, r + 4.0 + 2.0 * p, Color(Style.BRASS_LIGHT, 0.35 + 0.3 * p))
		draw_circle(c, r + 1.5, Style.INK)
		draw_circle(c, r, col.darkened(0.35) if m.routing else col)
		draw_circle(c - Vector2(r, r) * 0.3, r * 0.35, Color(1, 1, 1, 0.35))
	# The window's own inner shadow (it is sunk in the stone).
	draw_rect(Rect2(0, 0, size.x, 5), Color(0, 0, 0, 0.45))
	draw_rect(Rect2(0, 0, 4, size.y), Color(0, 0, 0, 0.3))


func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or not _ok():
		return
	accept_event()
	var t := _xform().affine_inverse() * (e as InputEventMouseButton).position
	var best: Variant = null
	var near := 1.6
	for m in _marks:
		var d := Vector2(m.x + 0.5, m.y + 0.5).distance_to(t)
		if m.faction == "player" and d < near:
			near = d
			best = m.uid
	if best != null and view.has_method("select"):
		view.select(best)
