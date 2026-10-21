## Squad formations on the battle grid. Port of src/render/formation.ts.
##
## A squad is one gameplay unit standing on one tile (its anchor); each visible
## soldier keeps a local offset from that anchor. Offsets are in world pixels on
## the ground plane as seen on screen (+x right, +y toward the camera), so the
## rows read as orderly ranks from the bottom-left camera. Every slot keeps the
## feet well inside the tile diamond (|x|/64 + |y|/32 < 0.92 for a 128×64 tile).
##
## Slots are `{x, y}` Dictionaries of floats (doubles, so ties in the slot
## assignment break exactly as in the original). Presentation only.
## Use through `const Formation = preload("res://scripts/render/formation.gd")`.
extends RefCounted

const JS = preload("res://scripts/core/js.gd")

## Column spacing, half the gap between ranks, and the sideways lean toward the facing.
const COL := 30.0
const ROW := 11.0
const LEAN := 4.0

## Wider spacing for big creatures (trolls), fewer of them per tile.
const BIG_COL := 27.0
const BIG_ROW := 10.0

## Riders on wolves need room: two abreast, two deep.
const MOUNT_COL := 46.0
const MOUNT_ROW := 12.0

## Goblin rabble packs three ranks of three into a tile.
const SWARM_COL := 25.0
const SWARM_ROW := 11.0


## Facings 0 and 1 face the camera (front rank is the lower one on screen).
static func faces_camera(f: int) -> bool:
	return f == 0 or f == 1


## Screen-horizontal sign of the facing: 1 and 2 look left, 0 and 3 look right.
static func side_sign(f: int) -> float:
	return -1.0 if (f == 1 or f == 2) else 1.0


## Slots for `n` standing soldiers of a squad whose full strength is `size`,
## front rank first. Six stand in two ranks of three; casualties close up the
## ranks so the block stays centred on the anchor. Three-strong squads (trolls)
## stand in a triangle with one behind.
static func formation_slots(n: int, size: int, facing: int, tight: float = 1.0, type_id: String = "") -> Array:
	var fs := 1.0 if faces_camera(facing) else -1.0 # +y is the front rank
	var ls := side_sign(facing)
	var out: Array = []
	if type_id == "wolf_rider":
		var col := MOUNT_COL * tight
		var row := MOUNT_ROW * tight
		var lean := LEAN * tight
		var half := col / 2.0
		if n <= 0:
			return out
		if n == 1:
			out.append(_p(0, 0))
			return out
		if n == 2:
			out.append(_p(-half + ls * lean * 0.5, fs * 2))
			out.append(_p(half + ls * lean * 0.5, fs * 2))
			return out
		out.append(_p(-half + ls * lean, fs * row))
		out.append(_p(half + ls * lean, fs * row))
		if n == 3:
			out.append(_p(-ls * lean, -fs * row))
			return out
		out.append(_p(-half - ls * lean, -fs * row))
		out.append(_p(half - ls * lean, -fs * row))
		return out
	if size >= 7 and n >= 7:
		# Three ranks: three in front, three in the middle, the rest behind.
		var col := SWARM_COL * tight
		var row := SWARM_ROW * tight
		var lean := LEAN * tight
		var rest := n - 6
		var back: Array = [-col, 0.0, col] if rest == 3 else ([-col / 2.0, col / 2.0] if rest == 2 else [0.0])
		for r in [1, 0, -1]:
			var xs: Array = back if r == -1 else [-col, 0.0, col]
			for x in xs:
				out.append(_p(x + ls * lean * r, fs * row * r))
		return out
	var big := size <= 3
	var col := (BIG_COL if big else COL) * tight
	var row := (BIG_ROW if big else ROW) * tight
	var lean := LEAN * tight
	var half := col / 2.0
	if n <= 0:
		return out
	if n == 1:
		out.append(_p(0, 0))
		return out
	if n == 2:
		# Shoulder to shoulder, nudged toward the facing so the pair still reads as a rank.
		var k := 1.7 if big else 1.15
		out.append(_p(-half * k + ls * lean * 0.5, fs * 2))
		out.append(_p(half * k + ls * lean * 0.5, fs * 2))
		return out
	var front := func(xs: Array) -> void:
		for x in xs:
			out.append(_p(x + ls * lean, fs * row))
	var behind := func(xs: Array) -> void:
		for x in xs:
			out.append(_p(x - ls * lean, -fs * row))
	if big and n == 3:
		# Triangle: two in front, one behind and between them.
		front.call([-col, col])
		out.append(_p(-ls * lean, -fs * row * 1.3))
		return out
	if n == 3:
		front.call([-half, half])
		behind.call([0.0])
	elif n == 4:
		front.call([-half, half])
		behind.call([-half, half])
	elif n == 5:
		front.call([-col, 0.0, col])
		behind.call([-half, half])
	else:
		# Six (and anything larger is clamped to two ranks of three).
		front.call([-col, 0.0, col])
		behind.call([-col, 0.0, col])
	return out


## Give each soldier a slot so the whole squad moves as little as possible
## when the formation changes (turning, closing ranks after a casualty).
## `pinned` soldiers (a champion) take the front-centre slot.
static func assign_slots(positions: Array, slots: Array, pinned: int = -1) -> Array[int]:
	var n := positions.size()
	var out: Array[int] = []
	out.resize(n)
	out.fill(-1)
	if n == 0:
		return out
	var free: Array[int] = []
	for i in slots.size():
		free.append(i)
	if pinned >= 0 and pinned < n:
		# Front-centre: slots come front rank first, so pick the most central of those.
		var front_count := 3 if slots.size() >= 5 else (2 if slots.size() >= 2 else 1)
		var best := 0
		for i in range(1, front_count):
			if absf(slots[i].x) < absf(slots[best].x):
				best = i
		out[pinned] = best
		free.erase(best)
	var who: Array[int] = []
	for i in n:
		if out[i] < 0:
			who.append(i)
	# Exhaustive search is tiny (at most 6! = 720 orders); fall back to greedy beyond that.
	if who.size() <= 6:
		var st := {"best_cost": INF, "best_perm": [], "perm": [], "used": {}}
		_rec(0, 0.0, who, free, positions, slots, st)
		var bp: Array = st.best_perm
		for k in who.size():
			out[who[k]] = bp[k]
		return out
	for w in who:
		var best: int = free[0]
		var best_d := INF
		for si in free:
			var p: Dictionary = positions[w]
			var s: Dictionary = slots[si]
			var d: float = (p.x - s.x) ** 2 + (p.y - s.y) ** 2
			if d < best_d:
				best_d = d
				best = si
		out[w] = best
		free.erase(best)
	return out


static func _rec(k: int, cost: float, who: Array[int], free: Array[int], positions: Array, slots: Array, st: Dictionary) -> void:
	if cost >= st.best_cost:
		return
	if k == who.size():
		st.best_cost = cost
		st.best_perm = st.perm.duplicate()
		return
	var used: Dictionary = st.used
	var perm: Array = st.perm
	for si in free:
		if used.has(si):
			continue
		var p: Dictionary = positions[who[k]]
		var s: Dictionary = slots[si]
		var d: float = (p.x - s.x) ** 2 + (p.y - s.y) ** 2
		used[si] = true
		perm.append(si)
		_rec(k + 1, cost + d, who, free, positions, slots, st)
		perm.pop_back()
		used.erase(si)


## Which soldiers fall to a blow: the `k` standing nearest the attacker (by
## their offsets plus the direction of the attack). A protected soldier (the
## warlord among his guard) falls only when nobody else is left.
static func pick_casualties(positions: Array, standing: Array, k: int, from: Variant, protected_idx: int = -1) -> Array:
	var len := JS.hypot(from.x, from.y)
	if len == 0.0:
		len = 1.0
	var dx: float = from.x / len
	var dy: float = from.y / len
	var order := standing.duplicate()
	JS.sort(order, func(a, b) -> float:
		var pa: float = -1e6 if a == protected_idx else positions[a].x * dx + positions[a].y * dy * 2
		var pb: float = -1e6 if b == protected_idx else positions[b].x * dx + positions[b].y * dy * 2
		return pb - pa)
	return order.slice(0, maxi(0, mini(k, standing.size())))


## A slot / point `{x, y}`.
static func _p(x: float, y: float) -> Dictionary:
	return {"x": x, "y": y}
