## Editable blocking, metres / seconds, +X forward, +Y up, left = -Z.
## Isolated motion proposals. No battle rules or production animation calls.
extends RefCounted

const CLIPS := ["move", "attack", "shield_bash", "charge"]
const LENGTHS := {"move": 5.6, "attack": 2.4, "shield_bash": 2.5, "charge": 4.8}
const IMPACTS := {"attack": 0.82, "shield_bash": 0.86, "charge": 3.4}
const SWORD_LENGTH := 0.84
const SOLE := 0.075

static func ease01(a: float, b: float, t: float) -> float:
	var u := clampf((t - a) / (b - a), 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)

static func curve(t: float, keys: Array) -> float:
	for i in range(1, keys.size()):
		if t <= keys[i][0]:
			return lerpf(keys[i - 1][1], keys[i][1], ease01(keys[i - 1][0], keys[i][0], t))
	return keys[-1][1]

static func vector_curve(t: float, keys: Array) -> Vector3:
	for i in range(1, keys.size()):
		if t <= keys[i][0]:
			return (keys[i - 1][1] as Vector3).lerp(keys[i][1], ease01(keys[i - 1][0], keys[i][0], t))
	return keys[-1][1]

## Integrated trapezoidal velocity with cosine acceleration/deceleration.
static func travel(t: float, start: float, end: float, ramp: float) -> float:
	var u := clampf(t - start, 0.0, end - start)
	var d := end - start
	if u < ramp:
		return (0.5 * u - ramp * sin(PI * u / ramp) / (2.0 * PI)) / (d - ramp)
	if u > d - ramp:
		var v := d - u
		return 1.0 - (0.5 * v - ramp * sin(PI * v / ramp) / (2.0 * PI)) / (d - ramp)
	return (u - ramp * 0.5) / (d - ramp)

static func base(x := 0.0) -> Dictionary:
	return {"root": Vector3(x, 0.86, 0),
		"left": Vector3(x + 0.16, SOLE, -0.17), "right": Vector3(x - 0.16, SOLE, 0.17),
		"left_down": true, "right_down": true, "left_pitch": 0.0, "right_pitch": 0.0,
		"lean": 0.025, "twist": 0.0,
		"hand_r": Vector3(0.27, 0.34, 0.30), "hand_l": Vector3(0.40, 0.25, -0.22),
		"blade": Vector3(0.56, 0.82, 0.10).normalized(), "shield_tilt": 0.0,
		"phase": "READY", "impact": false}

static func root_x(clip: String, t: float) -> float:
	if clip == "move":
		return lerpf(-1.5, 1.5, travel(t, 0.46, 4.50, 0.46))
	return lerpf(-2.8, 0.17, travel(t, 0.70, 3.30, 0.58))

## Foot anchors are authored in world space. Only a swinging foot moves.
## An entry is [side, lift-off, touchdown, target x, clearance].
static func footsteps(clip: String) -> Array:
	var out: Array = []
	if clip == "move":
		for i in 8:
			var start := 0.5 + i * 0.5
			var land := start + 0.34
			var side := "right" if i % 2 == 0 else "left"
			var x := root_x(clip, land + 0.23)
			if i == 6: x = 1.34
			if i == 7: x = 1.66
			out.append([side, start, land, x, 0.12])
	elif clip == "charge":
		for i in 7:
			var start := 0.73 + i * 0.35
			# A short flight phase distinguishes the run from the walk. The
			# braking steps return to double support before the shield arrives.
			var land := start + (0.40 if i < 5 else 0.24)
			var side := "right" if i % 2 == 0 else "left"
			var x := root_x(clip, land + 0.16)
			if i == 6: x = -0.09
			out.append([side, start, land, x, 0.19 if i < 5 else 0.10])
		out.append(["left", 3.08, 3.29, 0.49, 0.08])
	return out

static func apply_steps(p: Dictionary, t: float, steps: Array) -> void:
	for step in steps:
		var side: String = step[0]
		var start: float = step[1]
		var end: float = step[2]
		if t < start: continue
		var from: Vector3 = p[side]
		var to := Vector3(step[3], SOLE, from.z)
		if t >= end:
			p[side] = to
		else:
			var u := (t - start) / (end - start)
			p[side] = from.lerp(to, ease01(start, end, t)) + Vector3.UP * float(step[4]) * pow(sin(PI * u), 1.25)
			p[side + "_down"] = false
			p[side + "_pitch"] = 0.18 * sin(TAU * u)

static func sample(clip: String, t: float) -> Dictionary:
	t = clampf(t, 0.0, float(LENGTHS[clip]))
	if clip == "move" or clip == "charge":
		return locomotion(clip, t)
	return combat(clip, t)

static func locomotion(clip: String, t: float) -> Dictionary:
	var p := base(-1.5 if clip == "move" else -2.8)
	p.root.x = root_x(clip, t)
	apply_steps(p, t, footsteps(clip))
	var fast := clip == "charge"
	var active := ease01(0.4, 0.85, t) * (1.0 - ease01(2.7 if fast else 4.0, 3.3 if fast else 4.5, t))
	var phase := (t - (0.73 if fast else 0.5)) / (0.7 if fast else 1.0)
	p.root.y += active * (0.025 if not fast else 0.045) * sin(TAU * phase * 2.0)
	p.root.z = active * 0.018 * sin(TAU * phase)
	p.lean = 0.025 + active * (0.19 if fast else 0.055)
	p.twist = active * 0.055 * sin(TAU * phase)
	p.hand_r += Vector3(-0.08, -0.05, 0.0) * active * sin(TAU * phase)
	p.hand_l += Vector3(0.015, 0.012, 0.0) * active * cos(TAU * phase)
	p.blade = Vector3(0.45, 0.88, 0.12).normalized()
	p.phase = "STEP / TRANSFER" if active > 0.1 else "SETTLED GUARD"
	if fast:
		var load := ease01(0.28, 0.66, t) * (1.0 - ease01(0.70, 1.02, t))
		p.root.y -= load * 0.075
		p.lean += load * 0.10
		p.hand_r = Vector3(0.02, 0.30, 0.31)
		p.blade = Vector3(-0.3, 0.95, 0.08).normalized()
		var brace := ease01(2.60, 3.14, t)
		var drive := ease01(3.18, 3.40, t) * (1.0 - ease01(3.54, 4.28, t))
		p.hand_l.x = 0.42 + 0.18 * drive
		p.hand_l.y = 0.25
		p.root.y -= brace * 0.045 + drive * 0.025
		p.lean += drive * 0.11
		p.impact = absf(t - 3.4) < 0.025
		p.phase = "LOAD" if t < 0.7 else ("ACCELERATE" if t < 1.25 else ("DRIVE" if t < 2.6 else ("SHORTEN / BRAKE" if t < 3.18 else ("SHIELD CONTACT" if t < 3.55 else "ABSORB / HOLD"))))
	return p

static func combat(clip: String, t: float) -> Dictionary:
	var bash := clip == "shield_bash"
	var p := base(-0.70)
	if not bash:
		apply_steps(p, t, [["left", 0.38, 0.65, -0.32, 0.09], ["left", 1.56, 1.94, -0.54, 0.08]])
		var drive := curve(t, [[0, 0], [0.35, 0], [0.62, -0.04], [0.82, 0.09], [1.15, 0.07], [1.94, 0]])
		p.root.x += drive
		p.root.y -= curve(t, [[0, 0], [0.6, 0.045], [0.82, 0.025], [1.35, 0.035], [1.94, 0]])
		p.twist = curve(t, [[0, 0], [0.62, -0.34], [0.86, 0.34], [1.18, 0.27], [1.85, 0]])
		p.lean = curve(t, [[0, 0.025], [0.62, -0.035], [0.86, 0.12], [1.2, 0.10], [1.94, 0.025]])
		p.hand_r = vector_curve(t, [[0, p.hand_r], [0.28, p.hand_r], [0.62, Vector3(-0.12, 0.64, 0.37)],
			[0.82, Vector3(0.46, 0.38, 0.14)], [1.05, Vector3(0.34, 0.20, 0.12)], [1.28, Vector3(0.32, 0.22, 0.12)], [1.94, p.hand_r]])
		p.blade = vector_curve(t, [[0, p.blade], [0.28, p.blade], [0.62, Vector3(-0.67, 0.72, 0.15)],
			[0.82, Vector3(0.970, -0.23, 0.076)], [1.05, Vector3(0.55, -0.83, 0.05)], [1.28, Vector3(0.65, -0.75, 0.05)], [1.94, p.blade]]).normalized()
		p.hand_l.x = 0.40 - 0.045 * ease01(0.3, 0.62, t) * (1.0 - ease01(1.1, 1.8, t))
		p.phase = "GUARD" if t < 0.28 else ("LOAD / LEAD STEP" if t < 0.65 else ("PLANT / CUT" if t < 0.82 else ("CONTACT / FOLLOW-THROUGH" if t < 1.28 else ("RECOVER / STEP BACK" if t < 1.94 else "GUARD"))))
	else:
		apply_steps(p, t, [["left", 0.39, 0.69, -0.15, 0.10], ["right", 1.26, 1.57, -0.60, 0.08]])
		p.root.x += curve(t, [[0, 0], [0.34, 0], [0.60, -0.055], [0.86, 0.22], [1.05, 0.20], [1.75, 0.18]])
		p.root.y -= curve(t, [[0, 0], [0.58, 0.09], [0.86, 0.04], [1.1, 0.075], [1.75, 0.025]])
		p.lean = curve(t, [[0, 0.025], [0.58, -0.04], [0.86, 0.14], [1.1, 0.08], [1.75, 0.04]])
		p.hand_l.x = curve(t, [[0, 0.40], [0.34, 0.40], [0.58, 0.26], [0.86, 0.60], [0.98, 0.58], [1.55, 0.40]])
		p.hand_l.y = 0.25
		p.hand_r = Vector3(0.08, 0.33, 0.32)
		p.blade = Vector3(0.22, 0.97, 0.11).normalized()
		p.phase = "GUARD" if t < 0.34 else ("REAR-LEG LOAD" if t < 0.69 else ("PLANT / DRIVE" if t < 0.86 else ("SHIELD CONTACT / ABSORB" if t < 1.25 else "REAR FOOT CATCH-UP")))
	p.impact = absf(t - float(IMPACTS[clip])) < 0.025
	return p

static func target_position(clip: String) -> Vector3:
	if clip == "attack":
		var p := sample(clip, IMPACTS[clip])
		var tip: Vector3 = p.root + p.hand_r + p.blade * SWORD_LENGTH
		return Vector3(tip.x + 0.485, 0, tip.z - 0.22)
	return Vector3(0.66 if clip == "shield_bash" else 1.31, 0, -0.44)

static func defender(clip: String, t: float) -> Dictionary:
	var p := base()
	var hit: float = IMPACTS.get(clip, 99.0)
	var recoil := ease01(hit, hit + 0.14, t) * (1.0 - ease01(hit + 0.28, hit + 0.80, t))
	p.root.y -= 0.04
	p.lean = 0.05 - 0.12 * recoil
	p.hand_l.x = 0.43 - 0.07 * recoil
	p.hand_r = Vector3(0.06, 0.34, 0.31)
	p.blade = Vector3(0.1, 0.98, 0.1).normalized()
	if clip != "attack":
		var retreat := ease01(hit + 0.05, hit + 0.50, t)
		p.root.x -= 0.10 * retreat
		apply_steps(p, t, [["right", hit + 0.05, hit + 0.38, -0.36, 0.08]])
	return p

## Analytic two-bone IK with fixed lengths. Pole selects an anatomical bend.
static func knee(a: Vector3, b: Vector3, pole: Vector3, upper: float, lower: float) -> Vector3:
	var delta := b - a
	var d := clampf(delta.length(), 0.001, upper + lower - 0.0001)
	var axis := delta.normalized()
	var bend := (pole - axis * pole.dot(axis)).normalized()
	var along := (upper * upper - lower * lower + d * d) / (2.0 * d)
	return a + axis * along + bend * sqrt(maxf(0.0, upper * upper - along * along))
