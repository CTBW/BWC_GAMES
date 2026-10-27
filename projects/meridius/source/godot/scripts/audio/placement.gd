## Where a world sound sits in the stereo field and how loud it is, from the
## active view's camera (Godot addition).
##
## Positional sound is played by AudioStreamPlayer2D voices that sfx.gd keeps
## in a 2D space of its own, beside a current AudioListener2D at its origin.
## Godot only pans them: a voice is put at `x = pan · view width` and its
## distance attenuation is off (attenuation 0, huge max_distance). Loudness is
## worked out here instead, because Godot's 2D falloff is by screen distance
## from the centre: zooming out would bring every sound closer and make it
## louder, the opposite of what the camera shows. The views draw the world
## through a Node2D transform (camera.gd), not a Camera2D, so a listener in
## the world would not follow the camera either.
##
## Godot 4.7.2's 2D pan law, measured with an AudioEffectCapture
## (audio/general/2d_panning_strength 0.5, panning_strength 1): the right gain
## is 0.5 + 0.25 · clamp(x / view width, -1, 1) and the left 1 minus that, so
## a centred 2D voice is 6.02 dB below an AudioStreamPlayer. `voice_db()`
## puts that back and evens out the slight power rise toward the sides.
##
##   var p = Placement.place(screen_pt, view_size, cam.zoom)   # {pan -1..1, db}
##   player2d.position.x = Placement.pan_x(p.pan, viewport_width)
##   player2d.volume_db = event_db + p.db + Placement.voice_db(p.pan)
extends RefCounted

## How far toward the speakers a sound at the screen edge pans (1 = as far as Godot's law goes).
const EDGE_PAN := 0.75
## dB lost per half a screen beyond the edge of the view.
const OFF_DB := 12.0
## dB lost each time the camera zooms out by half (zoom 1 = the design level), and the floor of it.
const ZOOM_DB := 4.0
const ZOOM_FLOOR_DB := -8.0
## Quieter than this is not played at all (it would only take a voice).
const CULL_DB := -36.0
## A centred 2D voice is this much quieter than a flat one (measured, see above).
const CENTRE_DB := 6.0206


## {pan, db} of a sound at `screen` (view-local px) in a view of `view` px at camera `zoom`.
static func place(screen: Vector2, view: Vector2, zoom: float) -> Dictionary:
	var half := Vector2(maxf(1.0, view.x * 0.5), maxf(1.0, view.y * 0.5))
	var rel := (screen - half) / half # -1..1 across the screen
	var pan := clampf(rel.x * EDGE_PAN, -1.0, 1.0)
	var out := Vector2(maxf(0.0, absf(rel.x) - 1.0), maxf(0.0, absf(rel.y) - 1.0)).length()
	var db := -OFF_DB * out + zoom_db(zoom)
	return {"pan": pan, "db": db}


## Level change for the camera's zoom: 0 at zoom 1 or closer, quieter when zoomed out.
static func zoom_db(zoom: float) -> float:
	if zoom >= 1.0:
		return 0.0
	return maxf(ZOOM_FLOOR_DB, ZOOM_DB * log(maxf(zoom, 1e-3)) / log(2.0))


## The local x of a 2D voice beside the listener for `pan`.
static func pan_x(pan: float, view_width: float) -> float:
	return clampf(pan, -1.0, 1.0) * view_width


## Gain that makes a 2D voice at `pan` as loud as a flat voice: the 6 dB
## back, less the power the linear law adds off centre (+0.97 dB at the side).
static func voice_db(pan: float) -> float:
	var k := 0.5 * clampf(pan, -1.0, 1.0)
	return CENTRE_DB - 10.0 * log(1.0 + k * k) / log(10.0)


static func audible(db: float) -> bool:
	return db > CULL_DB
