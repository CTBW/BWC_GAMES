## Isometric projection shared by every scene (2:1 diamonds, upper-left light).
## Port of src/render/iso.ts. World pixels are the original's world pixels.
##
## The original's `Camera` interface is scripts/render/camera.gd (fields x, y,
## zoom, tx, ty, tzoom, shake); `make_camera`, `update_camera`,
## `world_to_screen` and `screen_to_world` below work on it exactly as the TS
## functions do on the plain object.
extends RefCounted

const CameraScript = preload("res://scripts/render/camera.gd")

const TW := 128 # tile width in world pixels
const TH := 64 # tile height
const LH := 26 # pixels per height level


static func iso_x(x: float, y: float) -> float:
	return (x - y) * (TW / 2.0)


static func iso_y(x: float, y: float, h: float = 0.0) -> float:
	return (x + y) * (TH / 2.0) - h * LH


## Both coordinates at once (iso_x, iso_y).
static func iso(x: float, y: float, h: float = 0.0) -> Vector2:
	return Vector2((x - y) * (TW / 2.0), (x + y) * (TH / 2.0) - h * LH)


## Inverse projection on the ground plane (h = 0).
static func from_iso(sx: float, sy: float) -> Vector2:
	var a := sx / (TW / 2.0)
	var b := sy / (TH / 2.0)
	return Vector2((a + b) / 2.0, (b - a) / 2.0)


static func make_camera(x: float = 0.0, y: float = 0.0, zoom: float = 1.0) -> RefCounted:
	return CameraScript.new(x, y, zoom)


static func update_camera(c: RefCounted, dt: float) -> void:
	c.update(dt)


static func world_to_screen(c: RefCounted, wx: float, wy: float, vw: float, vh: float) -> Vector2:
	return Vector2((wx - c.x) * c.zoom + vw / 2.0, (wy - c.y) * c.zoom + vh / 2.0)


static func screen_to_world(c: RefCounted, sx: float, sy: float, vw: float, vh: float) -> Vector2:
	return Vector2((sx - vw / 2.0) / c.zoom + c.x, (sy - vh / 2.0) / c.zoom + c.y)


static func ease_out_cubic(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)


static func ease_in_out_quad(t: float) -> float:
	return 2.0 * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0


static func clamp(v: float, a: float, b: float) -> float:
	return maxf(a, minf(b, v))


static func lerp(a: float, b: float, t: float) -> float:
	return a + (b - a) * t
