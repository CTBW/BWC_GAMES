## Ambient birds sampled from the camp's presentation clock. No timers, spawned
## nodes, campaign RNG or persistent particle pool; at most five silhouettes.
extends RefCounted

const Rng = preload("res://scripts/core/rng.gd")
const ART_SIZE := Vector2(2752, 1536)
const MAX_BIRDS := 5
const INTERVAL := 32.0
const FLIGHT_TIME := 9.0
# Surveyed crown tips in the approved painting, followed by an outward flight.
const ROOSTS := [
	[Vector2(.835, .610), Vector2(.900, .450), Vector2(1.035, .310)],
	[Vector2(.055, .345), Vector2(.110, .160), Vector2(.280, -.040)],
	[Vector2(.770, .665), Vector2(.860, .530), Vector2(1.025, .420)],
]


static func sample(elapsed: float, night: float) -> Array:
	var birds: Array = []
	if elapsed < 4.0 or night >= .98:
		return birds
	var flock := floori((elapsed - 4.0) / INTERVAL)
	var since := elapsed - 4.0 - flock * INTERVAL
	var roost: Array = ROOSTS[flock % ROOSTS.size()]
	var count := 3 + int(Rng.hash2(flock, 64) * 3.0)
	for i in mini(count, MAX_BIRDS):
		var age := since - i * .24
		if age <= 0.0 or age >= FLIGHT_TIME:
			continue
		var t := age / FLIGHT_TIME
		var launch: Vector2 = roost[0] * ART_SIZE + Vector2(i * 4.0, i * 2.0)
		var bend: Vector2 = roost[1] * ART_SIZE + Vector2(i * 13.0, -i * 8.0)
		var end: Vector2 = roost[2] * ART_SIZE + Vector2(i * 18.0, i * 10.0)
		var p := launch.lerp(bend, t).lerp(bend.lerp(end, t), t)
		p.y += sin(age * 2.4 + i * .8) * 2.5 * t
		var alpha := smoothstep(0.0, .30, age) * (1.0 - smoothstep(.76, 1.0, t)) * (1.0 - night)
		birds.append({"p": p, "age": age, "phase": i * 1.9, "scale": lerpf(1.0, .56, t), "alpha": alpha})
	return birds


static func draw(ci: CanvasItem, birds: Array) -> void:
	for bird in birds:
		var p: Vector2 = bird.p
		var age: float = bird.age
		var scale: float = bird.scale
		# Fast takeoff wingbeats settle into short glides; each bird is out of phase.
		var glide := smoothstep(.55, .90, sin(age * 1.25 + float(bird.phase))) * smoothstep(1.0, 2.5, age)
		var flap := lerpf(sin(age * TAU * 4.3 + float(bird.phase)), -.12, glide)
		var span := (8.0 - absf(flap) * 1.4) * scale
		var lift := flap * 5.0 * scale
		var bank := sin(age * .7 + float(bird.phase)) * .22
		var color := Color(.105, .145, .135, float(bird.alpha) * .94)
		var wing := PackedVector2Array([
			Vector2(-span, lift + 1.8 * scale), Vector2(-span * .48, lift * .38 - scale),
			Vector2.ZERO, Vector2(span * .48, lift * .38 - scale), Vector2(span, lift + 1.8 * scale)])
		for j in wing.size():
			wing[j] = p + wing[j].rotated(bank)
		ci.draw_polyline(wing, color, 1.65 * scale, true)
		ci.draw_line(p + Vector2(0, -1.8 * scale), p + Vector2(1, 3.2 * scale), color, 1.8 * scale, true)
