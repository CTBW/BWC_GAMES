## The world camera shared by the battle, garrison and campaign views.
## Port of the `Camera` interface and `updateCamera` of src/render/iso.ts, plus
## the input behaviour the original spread over its scenes and engine:
##   - keyboard pan (`cam_*` actions; 600 world px/s at zoom 1 in the garrison,
##     700 on the campaign map and in battle), applied to the target (tx, ty);
##   - wheel zoom: tzoom × 0.9 per notch down, × 1.1 per notch up, clamped
##     per scene (garrison 0.4–1.3, campaign 0.25–1.2, battle minZoom–1.6);
##   - drag pan with the right or middle button (src/render/engine.ts +
##     store.ts onDrag): target and position move together, no smoothing;
##   - smoothing: x, y, zoom approach tx, ty, tzoom with k = 1 - 0.0008^dt.
##
## Screen coordinates are the view's local canvas pixels (the original's CSS
## pixels): the view node sits at the viewport origin and the view size is its
## viewport's visible rect, which canvas_items stretch keeps at 1920×1080 or
## wider. `view_local()` turns an InputEvent position into that space for any
## host (root viewport, SubViewport, stretched window).
##
## Usage in a view (Node2D):
##   var cam = Camera.new(x, y, zoom)
##   func _process(dt): cam.pan_keys(dt, 600.0, self); cam.update(dt)
##                      world_node.transform = cam.transform(view_size)
##   func _unhandled_input(e): cam.drag_input(e, self) / cam.wheel(...)
##   func _input(e): cam.drag_motion(e, self)   # keeps dragging over the HUD
extends RefCounted

var x: float ## world px at screen centre
var y: float
var zoom: float
## Target values for smooth motion.
var tx: float
var ty: float
var tzoom: float
var shake := 0.0

## Drag-pan state (engine.ts `dragging`, `dragStart`).
var dragging := false
var drag_start := Vector2.ZERO


func _init(x0: float = 0.0, y0: float = 0.0, zoom0: float = 1.0) -> void:
	x = x0
	y = y0
	zoom = zoom0
	tx = x0
	ty = y0
	tzoom = zoom0


## updateCamera.
func update(dt: float) -> void:
	var k := 1.0 - pow(0.0008, dt)
	x += (tx - x) * k
	y += (ty - y) * k
	zoom += (tzoom - zoom) * k
	shake = maxf(0.0, shake - dt * 2.5)


func world_to_screen(wx: float, wy: float, vw: float, vh: float) -> Vector2:
	return Vector2((wx - x) * zoom + vw / 2.0, (wy - y) * zoom + vh / 2.0)


func screen_to_world(sx: float, sy: float, vw: float, vh: float) -> Vector2:
	return Vector2((sx - vw / 2.0) / zoom + x, (sy - vh / 2.0) / zoom + y)


func to_screen(world: Vector2, view: Vector2) -> Vector2:
	return world_to_screen(world.x, world.y, view.x, view.y)


func to_world(screen: Vector2, view: Vector2) -> Vector2:
	return screen_to_world(screen.x, screen.y, view.x, view.y)


## The world → screen transform for a node that draws in world pixels
## (translate(w/2 + sx, h/2 + sy) · scale(zoom) · translate(-x, -y)).
## `sx`, `sy` is a screen-space shake offset.
func transform(view: Vector2, sx: float = 0.0, sy: float = 0.0) -> Transform2D:
	return Transform2D(0.0, Vector2(zoom, zoom), 0.0, Vector2(view.x / 2.0 + sx - x * zoom, view.y / 2.0 + sy - y * zoom))


## Keyboard panning of the target (WASD / arrows through the cam_* actions).
## Keys typed into a text field do not pan (the original ignored INPUT/TEXTAREA).
func pan_keys(dt: float, speed: float, host: Node = null) -> void:
	if host != null and _typing(host):
		return
	var pan := speed * dt / zoom
	if Input.is_action_pressed("cam_up"):
		ty -= pan
	if Input.is_action_pressed("cam_down"):
		ty += pan
	if Input.is_action_pressed("cam_left"):
		tx -= pan
	if Input.is_action_pressed("cam_right"):
		tx += pan


## Wheel zoom (scene `wheel(delta)`): delta > 0 is a notch toward the user.
func wheel(delta: float, lo: float, hi: float) -> void:
	tzoom = clampf(tzoom * (0.9 if delta > 0 else 1.1), lo, hi)


## store.ts onDrag: the target and the camera move together.
func drag(dx: float, dy: float) -> void:
	tx -= dx / zoom
	ty -= dy / zoom
	x = tx
	y = ty


## Starts a drag on a right/middle press. Call from the view's
## _unhandled_input (so presses on the HUD do not pan). Returns true when the
## event started a drag.
func drag_input(e: InputEvent, host: CanvasItem) -> bool:
	if e is InputEventMouseButton and e.pressed and (e.button_index == MOUSE_BUTTON_RIGHT or e.button_index == MOUSE_BUTTON_MIDDLE):
		dragging = true
		drag_start = view_local(host, e.position)
		return true
	return false


## Continues/ends a drag. Call from the view's _input so the drag follows the
## pointer over HUD panels and ends on release anywhere (window pointerup).
func drag_motion(e: InputEvent, host: CanvasItem) -> void:
	if not dragging:
		return
	if e is InputEventMouseMotion:
		var p := view_local(host, e.position)
		drag(p.x - drag_start.x, p.y - drag_start.y)
		drag_start = p
	elif e is InputEventMouseButton and not e.pressed and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		dragging = false


## An InputEvent position (viewport canvas coordinates) in the host view's
## local pixels: correct under window resizing, canvas_items stretch and when
## the view lives in a SubViewport.
static func view_local(host: CanvasItem, event_pos: Vector2) -> Vector2:
	return host.get_global_transform_with_canvas().affine_inverse() * event_pos


## The view's size in its local pixels (the original's window w, h).
static func view_size(host: CanvasItem) -> Vector2:
	var r := host.get_viewport_rect().size
	var s := host.get_global_transform_with_canvas().get_scale()
	return Vector2(r.x / maxf(1e-6, absf(s.x)), r.y / maxf(1e-6, absf(s.y)))


static func _typing(host: Node) -> bool:
	var vp := host.get_viewport()
	if vp == null:
		return false
	var f := vp.gui_get_focus_owner()
	return f is LineEdit or f is TextEdit
