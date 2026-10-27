## Amberfeld's first painted camp: approved small woodland concept, mapped
## facilities, authored ground paths and restrained forest atmosphere.
## Presentation only. Building IDs, levels, costs, roster and saves stay in Game.
extends "res://scripts/render/base_view.gd"

const SoldierAnim = preload("res://scripts/render/soldier_anim.gd")
const Wildlife = preload("res://scripts/render/camp_wildlife.gd")
const CAMP_SHADER = preload("res://assets/shaders/camp_woodland.gdshader")
const ART_SIZE := Vector2(2752, 1536)
const DAY := "res://assets/camp/woodland_day.png"
const NIGHT := "res://assets/camp/woodland_night.png"
const ANCHORS := {
	"command": Vector2(.503, .482), "barracks": Vector2(.331, .487),
	"training": Vector2(.689, .489), "quartermaster": Vector2(.480, .315),
	"armoury": Vector2(.580, .291), "infirmary": Vector2(.490, .658),
}
const ZONES := {
	"command": [Vector2(.447,.482), Vector2(.467,.432), Vector2(.502,.387), Vector2(.538,.428), Vector2(.560,.480), Vector2(.543,.529), Vector2(.506,.539), Vector2(.465,.518)],
	"barracks": [Vector2(.229,.474), Vector2(.286,.395), Vector2(.332,.358), Vector2(.373,.396), Vector2(.405,.414), Vector2(.432,.475), Vector2(.433,.535), Vector2(.355,.584), Vector2(.291,.578), Vector2(.245,.538)],
	"training": [Vector2(.688,.387), Vector2(.782,.451), Vector2(.796,.482), Vector2(.761,.535), Vector2(.664,.598), Vector2(.612,.565), Vector2(.590,.519), Vector2(.611,.441)],
	"quartermaster": [Vector2(.404,.319), Vector2(.428,.290), Vector2(.444,.230), Vector2(.495,.219), Vector2(.509,.244), Vector2(.515,.212), Vector2(.565,.222), Vector2(.543,.273), Vector2(.541,.360), Vector2(.475,.407), Vector2(.412,.365)],
	"armoury": [Vector2(.551,.248), Vector2(.573,.245), Vector2(.606,.265), Vector2(.609,.321), Vector2(.584,.332), Vector2(.551,.302)],
	"infirmary": [Vector2(.409,.645), Vector2(.427,.590), Vector2(.453,.595), Vector2(.474,.542), Vector2(.512,.562), Vector2(.525,.612), Vector2(.542,.600), Vector2(.578,.626), Vector2(.594,.681), Vector2(.537,.738), Vector2(.493,.744), Vector2(.443,.706)],
}
## Seconds over which day and night ambience hand over to each other.
const AMBIENCE_FADE := 6.0
## One representative per roster squad, on surveyed open ground. Reversible
## polylines deliberately avoid flattened tent roofs, fences and the ditch.
const ROUTES := [
	[Vector2(.388,.365), Vector2(.433,.410), Vector2(.448,.449), Vector2(.441,.491), Vector2(.444,.523)],
	[Vector2(.447,.540), Vector2(.493,.542), Vector2(.548,.550), Vector2(.568,.493), Vector2(.571,.454), Vector2(.600,.424), Vector2(.646,.390)],
	[Vector2(.642,.476), Vector2(.683,.451), Vector2(.732,.481), Vector2(.688,.529), Vector2(.643,.513)],
]

var night_target := false
var night_blend := 0.0
## Review/accessibility hook: all ambient motion shares the scene's clock and
## lifetime. Disabling it leaves the painting and campaign interactions intact.
var atmosphere_enabled := true
var ambient_birds: Array = []
var _painting: Sprite2D
var _paint_material: ShaderMaterial
var _life: Node2D
var _pins: Node2D
var _shade: Node2D
var _polygons := {}
var _cover_zoom := 1.0
var _size_key := Vector2.ZERO


func _init() -> void:
	# This scene has its own image-space camera and never needs the legacy
	# grid layout or its background building/tree atlas requests.
	cam = Camera.new(ART_SIZE.x * .5, ART_SIZE.y * .5, 1.0)
	atmo = Atmosphere.new(77)
	# Picking geometry is available before the first rendered frame, too.
	for id in ZONES:
		var poly := PackedVector2Array()
		for p in ZONES[id]:
			poly.append(p * ART_SIZE)
		_polygons[id] = poly


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_world = Node2D.new()
	_world.name = "WoodlandStage"
	add_child(_world)
	_painting = Sprite2D.new()
	_painting.name = "ApprovedWoodlandPainting"
	_painting.centered = false
	_painting.texture = load(DAY)
	_paint_material = ShaderMaterial.new()
	_paint_material.shader = CAMP_SHADER
	_paint_material.set_shader_parameter("night_texture", load(NIGHT))
	_painting.material = _paint_material
	_world.add_child(_painting)
	terrain = _world
	_life = WorldCanvas.new(_draw_life, "CampLife")
	_world.add_child(_life)
	_pins = WorldCanvas.new(_draw_facilities, "Facilities")
	_world.add_child(_pins)
	_shade = WorldCanvas.new(func(ci: CanvasItem) -> void:
		if dim:
			ci.draw_rect(Rect2(Vector2.ZERO, Vector2(_w, _h)), Color(.025,.035,.035,.38)), "ModalShade")
	add_child(_shade)
	_refresh_view()


## Keep the established camp ambience, without the old visible fire anchor:
## this concept has no campfire at the old grid coordinate.
func _enter_tree() -> void:
	var s := _audio()
	if s != null and s.has_method("set_ambience"):
		s.set_listener(self)
		s.set_ambience(_ambience_id())


func _exit_tree() -> void:
	# Resolve shared sprite requests before releasing a view.
	Assets.collect_loaded(true)
	var s := _audio()
	if s != null and s.has_method("release_ambience"):
		s.release_ambience("camp_night")
	super._exit_tree()


func _ambience_id() -> String:
	return "camp_night" if night_target else "camp"


func spawn_walkers(g: Dictionary) -> void:
	walkers.clear()
	var roster: Array = g.get("roster", [])
	for i in mini(9, roster.size()):
		var route: int = i % ROUTES.size()
		var points: Array = ROUTES[route]
		var segment: int = (i / 3) % (points.size() - 1)
		var p: Vector2 = points[segment] * ART_SIZE
		walkers.append({"type": roster[i].typeId, "variant": int(roster[i].get("variant", 0)),
			"p": p, "route": route, "segment": segment, "direction": 1,
			"wait": 1.0 + i * .8, "phase": i * 1.7, "facing": 1, "speed": 17.0 + i * .9})


func update(dt: float) -> void:
	if not dim:
		cam.pan_keys(dt, 410.0, self)
	_clamp_camera()
	cam.update(dt)
	night_blend = move_toward(night_blend, 1.0 if night_target else 0.0, dt / 2.4)
	for w in walkers:
		if w.wait > 0:
			w.wait -= dt
			continue
		var points: Array = ROUTES[w.route]
		var next_index: int = int(w.segment) + int(w.direction)
		var to: Vector2 = points[next_index] * ART_SIZE
		var delta: Vector2 = to - w.p
		var distance := delta.length()
		if distance <= float(w.speed) * dt:
			w.p = to
			w.segment = next_index
			if next_index == 0 or next_index == points.size() - 1:
				w.direction = -w.direction
				w.wait = 2.5 + float(w.variant % 4)
		else:
			w.p += delta.normalized() * float(w.speed) * dt
			w.phase += dt * 6.0
			w.facing = (0 if delta.x > 0 else 1) if delta.y > 0 else (3 if delta.x > 0 else 2)


func _refresh_view() -> void:
	if _world == null:
		return
	Assets.collect_loaded()
	var size := Camera.view_size(self)
	_w = size.x
	_h = size.y
	_frame({}, _w, _h)
	_world.transform = cam.transform(size)
	_paint_material.set_shader_parameter("night_mix", night_blend)
	_paint_material.set_shader_parameter("elapsed", time)
	_paint_material.set_shader_parameter("atmosphere_strength", 1.0 if atmosphere_enabled else 0.0)
	ambient_birds = Wildlife.sample(time, night_blend) if atmosphere_enabled else []
	if dim and ui.has("hover"):
		ui.erase("hover")
		_notify()
	_life.queue_redraw()
	_pins.queue_redraw()
	_shade.queue_redraw()


func _frame(_g: Dictionary, w: float, h: float) -> void:
	var size := Vector2(w, h)
	if size == _size_key:
		return
	_size_key = size
	_cover_zoom = maxf(w / ART_SIZE.x, h / ART_SIZE.y)
	frame_camp()
	cam.x = cam.tx
	cam.y = cam.ty
	cam.zoom = cam.tzoom


func frame_camp() -> void:
	cam.tx = ART_SIZE.x * .5
	cam.ty = ART_SIZE.y * .5
	cam.tzoom = _cover_zoom


func _clamp_camera() -> void:
	cam.tzoom = clampf(cam.tzoom, _cover_zoom, _cover_zoom * 1.65)
	# Clamp against BOTH the current and target zoom while easing/dragging.
	var half := Vector2(_w, _h) * .5 / maxf(_cover_zoom, minf(cam.zoom, cam.tzoom))
	for axis in [0, 1]:
		half[axis] = minf(half[axis], ART_SIZE[axis] * .5)
	cam.tx = clampf(cam.tx, half.x, ART_SIZE.x - half.x)
	cam.ty = clampf(cam.ty, half.y, ART_SIZE.y - half.y)
	cam.x = clampf(cam.x, half.x, ART_SIZE.x - half.x)
	cam.y = clampf(cam.y, half.y, ART_SIZE.y - half.y)


func wheel(delta: float) -> void:
	if not dim:
		cam.wheel(delta, _cover_zoom, _cover_zoom * 1.65)


func set_night(enabled: bool) -> void:
	night_target = enabled
	# The day's birds and murmur ebb away as the owls and crickets come in,
	# while the camp's own ambience is the one playing.
	var s := _audio()
	if s != null and s.has_method("ambience_id") and s.ambience_id() in ["camp", "camp_night"]:
		s.set_ambience(_ambience_id(), AMBIENCE_FADE)
	_notify()


func building_world_position(id: String) -> Vector2:
	return ANCHORS.get(id, Vector2(.5,.5)) * ART_SIZE


func building_label(id: String) -> String:
	var g: Variant = _game()
	var b := DB.building_by_id(id)
	if g == null or b.is_empty():
		return ""
	return str(b.levels[_level(g, id) - 1].name)


func building_at(sx: float, sy: float) -> Variant:
	if _game() == null:
		return null
	var world: Vector2 = cam.screen_to_world(sx, sy, _w, _h)
	for id in plates:
		var r: Dictionary = plates[id]
		if Rect2(r.x, r.y, r.w, r.h).has_point(world):
			return id
	for id in _polygons:
		if Geometry2D.is_point_in_polygon(world, _polygons[id]):
			return id
	return null


func _input(e: InputEvent) -> void:
	if not dim:
		cam.drag_motion(e, self)
		_clamp_camera()
	elif cam.dragging:
		cam.dragging = false


func _unhandled_input(e: InputEvent) -> void:
	if dim:
		return
	super._unhandled_input(e)


func _draw_facilities(ci: CanvasItem) -> void:
	plates.clear()
	var g: Variant = _game()
	if dim or g == null:
		return
	var zoom: float = cam.zoom
	var index := 0
	for b in DB.BUILDINGS:
		index += 1
		var point := building_world_position(b.id)
		var hovered: bool = ui.get("hover") == b.id
		var radius := (12.0 if hovered else 9.0) / zoom
		var fill := Color(.075,.105,.10,.92 if hovered else .76)
		var gold := Color(.96,.79,.43,1.0 if hovered else .80)
		if hovered:
			var polygon: PackedVector2Array = _polygons[b.id]
			ci.draw_colored_polygon(polygon, Color(1,.78,.35,.055))
			var line := polygon.duplicate()
			line.append(line[0])
			ci.draw_polyline(line, Color(1,.83,.47,.63), 1.25 / zoom, true)
		ci.draw_circle(point, radius, fill)
		ci.draw_arc(point, radius, 0, TAU, 32, gold, 1.0 / zoom, true)
		WD.draw_text(ci, point.x, point.y + 4.0 / zoom, str(index), 12.0 / zoom, gold, zoom)
		var rect := Rect2(point - Vector2.ONE * radius * 1.4, Vector2.ONE * radius * 2.8)
		plates[b.id] = {"x":rect.position.x, "y":rect.position.y, "w":rect.size.x, "h":rect.size.y}
		if hovered:
			var lvl := _level(g, b.id)
			var label: String = "%s  ·  %s" % [building_label(b.id), ["I","II","III"][lvl - 1]]
			var width := (WD.text_width(label, 16) + 30.0) / zoom
			var box := Rect2(point.x - width * .5, point.y - 49.0 / zoom, width, 28.0 / zoom)
			ci.draw_style_box(_pin_style(), box)
			WD.draw_text(ci, point.x, point.y - 30.0 / zoom, label, 16.0 / zoom, Color(1,.93,.75), zoom)


var _label_style: StyleBoxFlat
func _pin_style() -> StyleBoxFlat:
	if _label_style == null:
		_label_style = StyleBoxFlat.new()
		_label_style.bg_color = Color(.06,.09,.085,.94)
		_label_style.border_color = Color(.70,.53,.27,.85)
		_label_style.set_border_width_all(1)
		_label_style.set_corner_radius_all(3)
	return _label_style


func _draw_life(ci: CanvasItem) -> void:
	var ordered := JS.sort(walkers, func(a,b): return a.p.y - b.p.y)
	for w in ordered:
		var walking: bool = w.wait <= 0
		var flip := SoldierAnim.flip_of(w.facing)
		var s: Dictionary
		if SoldierAnim.animated(w.type):
			var suffix := SoldierAnim.suffix(w.facing, w.type)
			var frame := floori(fposmod(w.phase, TAU) / TAU * 3.0) if walking else 0
			s = SoldierAnim.frame(w.type, "%s_%s_%d" % ["walk" if walking else "idle", suffix, frame], w.variant)
		else:
			s = Assets.sprite("%s_idle_%s" % [w.type, "f" if w.facing in [0,1] else "b"], w.variant)
		if s.is_empty():
			continue
		var p: Vector2 = w.p
		var scale := 38.0 / maxf(1, float(s.h) * float(s.scale))
		var tint := Color.WHITE.lerp(Color(.48,.59,.70), night_blend * .78)
		ci.draw_colored_polygon(WD.ellipse(p.x + 4, p.y + 1, 12, 4, -.2, 20), Color(.07,.08,.055,.3))
		Assets.draw_sprite(ci, s, p.x, p.y - (absf(sin(w.phase)) * .6 if walking else 0.0), flip, scale, tint)
	# Slow airborne leaf specks along the forest margins, never a screen-filling effect.
	if not atmosphere_enabled:
		return
	for i in 18:
		var phase := Rng.hash2(i, 73)
		var x := fposmod(phase * ART_SIZE.x + time * (3.0 + phase * 3.0), ART_SIZE.x)
		var y := fposmod(Rng.hash2(i, 21) * ART_SIZE.y + time * 5.0, ART_SIZE.y)
		if x > ART_SIZE.x * .22 and x < ART_SIZE.x * .81 and y > ART_SIZE.y * .19 and y < ART_SIZE.y * .83:
			continue
		var pos := Vector2(x + sin(time * .7 + i) * 10, y)
		var alpha := .40 * (1.0 - night_blend * .6)
		ci.draw_line(pos, pos + Vector2(3 + sin(time + i) * 2, 1.5), Color(.79,.68,.35,alpha), 1.2, true)
	Wildlife.draw(ci, ambient_birds)
