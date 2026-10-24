## Shared atmosphere: drifting cloud shadows, warm light grading, vignette and
## ambient motes. Port of src/render/atmosphere.ts (class Atmosphere).
##
## The canvas original switches composite modes ('multiply', 'soft-light',
## 'screen') inside one draw; in Godot each mode needs its own CanvasItem
## material, so the drawing is done by two nodes this object makes:
##   var atmo = Atmosphere.new(seed)
##   world.add_child(atmo.make_clouds_node(cx, cy))  # world px, after the ground
##                                                   # (drawClouds(ctx, cx, cy))
##   screen.add_child(atmo.make_grade_node())        # screen px, over the world
##                                                   # (drawGrade(ctx, w, h, time))
## and every frame:
##   atmo.update(dt, w, h); atmo.redraw(Vector2(w, h), time)
## The grade node draws, in order: the grade pass (soft-light gradient and
## screen sun glow by day; the flat 'multiply' night tint unless
## own_night_mask), the motes, the vignette.
extends RefCounted

const Rng = preload("res://scripts/core/rng.gd")
const WD = preload("res://scripts/render/world_draw.gd")
const WorldCanvas = preload("res://scripts/render/world_canvas.gd")
const CloudShader = preload("res://assets/shaders/atmo_cloud.gdshader")
const GradeShader = preload("res://assets/shaders/atmo_grade.gdshader")
const VignetteShader = preload("res://assets/shaders/atmo_vignette.gdshader")

## Mote: {x, y, vx, vy, life, size, kind: pollen|leaf|firefly|ember, phase}
var motes: Array = []
## Cloud: {x, y, r, s}
var clouds: Array = []
var night := false
## The scene draws its own lit darkness mask; skip the flat night tint.
var own_night_mask := false
var warmth := 1.0

var _clouds_node: Node2D
var _grade_node: Node2D
var _grade_rect: Node2D
var _motes_node: Node2D
var _vignette: Node2D
var _view := Vector2(1920, 1080)
var _time := 0.0
var _cx := 0.0
var _cy := 0.0


func _init(seed: float = 1.0) -> void:
	for i in 7:
		clouds.append({
			"x": Rng.hash2(i, 1, seed) * 3000.0 - 1500.0,
			"y": Rng.hash2(i, 2, seed) * 2000.0 - 1000.0,
			"r": 260.0 + Rng.hash2(i, 3, seed) * 380.0,
			"s": 0.6 + Rng.hash2(i, 4, seed) * 0.6,
		})


func update(dt: float, w: float, h: float) -> void:
	for c in clouds:
		c.x += 14.0 * c.s * dt
		c.y += 5.0 * c.s * dt
		if c.x > 2200.0:
			c.x = -2200.0
		if c.y > 1500.0:
			c.y = -1500.0
	var want := 26 if night else 34
	while motes.size() < want:
		var kind := "firefly" if night else ("leaf" if randf() < 0.18 else "pollen")
		var leaf := kind == "leaf"
		motes.append({
			"x": randf() * w,
			"y": randf() * h,
			"vx": 18.0 + randf() * 20.0 if leaf else 6.0 + randf() * 8.0,
			"vy": 10.0 + randf() * 14.0 if leaf else -2.0 + randf() * 4.0,
			"life": 6.0 + randf() * 8.0,
			"size": 3.0 + randf() * 2.0 if leaf else 1.0 + randf() * 1.6,
			"kind": kind,
			"phase": randf() * 10.0,
		})
	for m in motes:
		m.life -= dt
		m.phase += dt
		m.x += (m.vx + sin(m.phase * 1.3) * 8.0) * dt
		m.y += (m.vy + cos(m.phase * 0.9) * 5.0) * dt
	motes = motes.filter(func(m): return m.life > 0 and m.x < w + 20 and m.y < h + 20)


## Cloud shadows in world space (drawClouds). `ci` must use cloud_material().
func draw_clouds(ci: CanvasItem, cx: float, cy: float) -> void:
	if night:
		return
	for c in clouds:
		var x: float = cx + c.x
		var y: float = cy + c.y
		var m: float = c.r * 1.05
		var pts := PackedVector2Array([Vector2(x - m, y - m), Vector2(x + m, y - m), Vector2(x + m, y + m), Vector2(x - m, y + m)])
		var uv := PackedVector2Array([Vector2(-1.05, -1.05), Vector2(1.05, -1.05), Vector2(1.05, 1.05), Vector2(-1.05, 1.05)])
		ci.draw_polygon(pts, PackedColorArray([Color.WHITE]), uv)


## Motes in screen space (the middle part of drawGrade).
func draw_motes(ci: CanvasItem, time: float) -> void:
	for m in motes:
		var a := minf(1.0, m.life / 1.5)
		if m.kind == "firefly":
			var glow := 0.5 + 0.5 * sin(m.phase * 3.0 + time)
			WD.fill_circle(ci, Vector2(m.x, m.y), 2.0, Color(230 / 255.0, 1.0, 140 / 255.0, 0.8 * a * glow))
			WD.fill_circle(ci, Vector2(m.x, m.y), 7.0, Color(230 / 255.0, 1.0, 140 / 255.0, 0.15 * a * glow))
		elif m.kind == "leaf":
			ci.draw_set_transform(Vector2(m.x, m.y), m.phase * 2.0, Vector2.ONE)
			ci.draw_rect(Rect2(-m.size, -m.size * 0.45, m.size * 2.0, m.size * 0.9), Color(200 / 255.0, 170 / 255.0, 70 / 255.0, 0.8 * a))
			ci.draw_set_transform_matrix(Transform2D.IDENTITY)
		else:
			ci.draw_rect(Rect2(m.x, m.y, m.size, m.size), Color(1.0, 248 / 255.0, 220 / 255.0, 0.55 * a))


static func cloud_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = CloudShader
	return mat


## The world-space cloud-shadow node, centred on (cx, cy) (usually the map centre).
func make_clouds_node(cx: float, cy: float) -> Node2D:
	_cx = cx
	_cy = cy
	_clouds_node = WorldCanvas.new(func(ci: CanvasItem) -> void: draw_clouds(ci, _cx, _cy), "Clouds")
	_clouds_node.material = cloud_material()
	return _clouds_node


## The screen-space grade node (grade pass, motes, vignette).
func make_grade_node() -> Node2D:
	_grade_node = Node2D.new()
	_grade_node.name = "Atmosphere"
	_grade_rect = WorldCanvas.new(func(ci: CanvasItem) -> void:
		var mode := 0
		if night:
			mode = 2 if own_night_mask else 1
		var mat: ShaderMaterial = ci.material
		mat.set_shader_parameter("view_size", _view)
		mat.set_shader_parameter("warmth", warmth)
		mat.set_shader_parameter("mode", mode)
		if mode != 2:
			ci.draw_rect(Rect2(Vector2.ZERO, _view), Color.WHITE), "Grade")
	var gm := ShaderMaterial.new()
	gm.shader = GradeShader
	_grade_rect.material = gm
	_grade_node.add_child(_grade_rect)
	_motes_node = WorldCanvas.new(func(ci: CanvasItem) -> void: draw_motes(ci, _time), "Motes")
	_grade_node.add_child(_motes_node)
	_vignette = WorldCanvas.new(func(ci: CanvasItem) -> void:
		var mat: ShaderMaterial = ci.material
		mat.set_shader_parameter("view_size", _view)
		ci.draw_rect(Rect2(Vector2.ZERO, _view), Color.WHITE), "Vignette")
	var vm := ShaderMaterial.new()
	vm.shader = VignetteShader
	_vignette.material = vm
	_grade_node.add_child(_vignette)
	return _grade_node


## Redraws the atmosphere's nodes for this frame (view size in screen px).
func redraw(view: Vector2, time: float, cx: float = NAN, cy: float = NAN) -> void:
	_view = view
	_time = time
	if not is_nan(cx):
		_cx = cx
		_cy = cy
	for n in [_clouds_node, _grade_rect, _motes_node, _vignette]:
		if n != null and is_instance_valid(n):
			n.queue_redraw()
