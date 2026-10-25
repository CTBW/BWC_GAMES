## A squad of footmen in the 3D sandbox: six men (footman_unit.gd, each on
## his own controller) in two ranks of three that march, stand and fight
## together, each in his own time, so that no two move in step.
##
## The formation: the ranks RANK apart round the squad's centre, the men FILE
## apart in each, facing `yaw`. A march follows the squad's route (field.path_to
## from its centre), each man walking it at his own place in the formation (a
## corner wheels it), and the men take the places nearest them (assign), so a
## squad sent the other way puts its rear rank in front. Each man sets off after
## his own short delay, walks at his own slightly different pace (the sandbox
## sets his `rate`), comes to rest a little off his exact place and turned a
## few degrees, and breathes and shifts in his own time (footman3d.gd).
##
## A fight (attack): the foes that stand together with the one attacked
## (LINK) are the foe's front. The squad marches up to face it, its front rank
## at sword's reach from the foe nearest the middle of it, and the front rank
## strikes, each man a few blows in his own time (the slash or now and then the
## stab), while the rear rank stands ready behind it; a front man who falls is
## replaced by the rear man nearest his place. Then the squad re-forms its two
## ranks where it fought. With `wide` on, the rear rank spreads out after a
## moment (SPREAD_AFTER) to stand beside the front rank: each man takes a free
## place in reach of a foe, the places that face the squad first, so against a
## line of foes the squad fights in one line of six and against a lone foe it
## closes round it. Presentation only: the blows land through the sandbox (its
## _on_impact), as any unit's.
extends RefCounted

## Metres between the men of a rank (the footman's lane step) and between the ranks.
const FILE := 1.1
const RANK := 1.5
const WIDTH := 3
## Foes this near one another (metres) stand together as one front.
const LINK := 2.0
const MAX_FOES := 8
## A man strikes a foe this near (centre to centre; the slash reaches about 2 m)
## and stands this near to strike it when he walks up (the slash's distance).
const REACH := 1.9
const STRIKE_DIST := 1.39
## Men stand at least this far apart; a place this near a foe is taken by it.
const ROOM := 0.8
const FOE_ROOM := 1.0
## The places round a foe a man may take: degrees off the side facing the squad.
const ANGLES := [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 120.0, -120.0, 150.0, -150.0]
## Seconds before each man moves on an order: the file leader (the front
## rank's middle man) at once, the rest a little after, the rear rank last.
const LEAD_DELAY := Vector2(0.0, 0.12)
const DELAY := Vector2(0.1, 0.45)
const REAR_DELAY := 0.22
## How far each man stands off his exact place (metres along and across) and
## off the squad's facing (radians).
const JITTER := Vector2(0.07, 0.06)
const YAW_JITTER := 0.07
## The fight: blows each, the pause after a blow, the rear rank's wait after
## the first blow and its men's own delays, the wait before re-forming.
const FRONT_BLOWS := Vector2i(3, 4)
const REAR_BLOWS := Vector2i(2, 3)
const PAUSE := Vector2(0.25, 1.1)
## Seconds between the start of one man's blow and the next man's, so that no
## two swing together.
const GAP := Vector2(0.22, 0.5)
const FIRST_PAUSE := Vector2(0.05, 0.5)
const SPREAD_AFTER := Vector2(1.4, 2.2)
const SPREAD_DELAY := Vector2(0.0, 0.7)
const REFORM_DELAY := Vector2(0.3, 1.2)
## A man this near his new place stays where he is and only turns.
const SETTLE := 0.3

var members: Array = []
var field
## The sandbox: _alive, _hostile, units, dummies, speed, show_route, clear_route.
var host
var title := "Footman squad"
var center := Vector3.ZERO
var yaw := 0.0
## "idle", "march", "fight", "reform".
var mode := "idle"
## The rear rank spreads out to fight beside the front rank (else only the front rank fights).
var wide := false
## The foe's front in the fight, and where the squad formed to face it.
var foes: Array = []
var spread := false
## The first blow of the fight has been struck (till then the squad advances).
var engaged := false
## The foe last attacked (the sandbox's Space strikes it again).
var last_foe: Node3D
var _fight_at := Vector3.ZERO
var _fight_yaw := 0.0
var _spread_in := -1.0
var _gap := 0.0
## The route marks the squad's last order put on the ground.
var _marks := {}
## Per man: {slot, role ("front" / "rear"), act (an order waiting for its
## delay), delay, moving, goal, still (seconds stopped short while moving),
## target, blows, pause, joined (a rear man sent to the line)}.
var _men := {}
var _rng := RandomNumberGenerator.new()


func setup(men: Array, f, sandbox, at: Vector3, facing: float) -> void:
	members = men
	field = f
	host = sandbox
	center = at
	yaw = facing
	_rng.randomize()
	var front := mini(men.size(), WIDTH)
	for i in men.size():
		_men[men[i]] = {"slot": i, "role": "front" if i < front else "rear", "act": Callable(), "delay": 0.0,
			"moving": false, "goal": men[i].position, "still": 0.0, "target": null, "blows": 0, "pause": 0.0, "joined": false}


# --- Geometry --------------------------------------------------------------------

## The places of n men round `at` facing `facing`: the front rank (up to
## WIDTH, centred, from the men's right to their left) RANK/2 ahead of the
## centre, the rest behind it.
static func slots(at: Vector3, facing: float, n: int) -> Array:
	var fwd := Vector3(sin(facing), 0, cos(facing))
	var left := Vector3(cos(facing), 0, -sin(facing))
	var front := mini(n, WIDTH)
	var out := []
	for r in 2:
		var k := front if r == 0 else n - front
		for i in k:
			out.append(at + fwd * (RANK * 0.5 if r == 0 else -RANK * 0.5) + left * ((i - (k - 1) * 0.5) * FILE))
	return out


## For each point of `from`, the index of the place in `to` it goes to: each
## place to one, the sum of the squared distances least (every permutation;
## a squad is small).
static func assign(from: Array, to: Array) -> Array:
	var st := {"best": [], "cost": INF}
	var used := []
	used.resize(to.size())
	used.fill(false)
	_assign(from, to, 0, [], 0.0, used, st)
	return st.best


static func _assign(from: Array, to: Array, i: int, pick: Array, cost: float, used: Array, st: Dictionary) -> void:
	if cost >= float(st.cost):
		return
	if i == from.size():
		st.cost = cost
		st.best = pick.duplicate()
		return
	for j in to.size():
		if used[j]:
			continue
		used[j] = true
		pick.append(j)
		_assign(from, to, i + 1, pick, cost + flat(from[i] - to[j]).length_squared(), used, st)
		pick.pop_back()
		used[j] = false


## The foes standing together with foe `first`: each within LINK of another (indices).
static func group(points: Array, first: int, link: float = LINK) -> Array:
	var out := [first]
	var i := 0
	while i < out.size() and out.size() < MAX_FOES:
		for j in points.size():
			if j not in out and flat(points[j] - points[out[i]]).length() <= link:
				out.append(j)
		i += 1
	return out.slice(0, MAX_FOES)


## The way to face a foe's front from `from`: square to a line of foes (the
## long axis of where they stand), else straight at the foe `at`.
static func facing(points: Array, from: Vector3, at: Vector3) -> float:
	var to := flat(at - from)
	var dir := to.normalized() if to.length() > 1e-3 else Vector3(0, 0, 1)
	if points.size() >= 2:
		var mid := Vector3.ZERO
		for p in points:
			mid += flat(p)
		mid /= points.size()
		var xx := 0.0
		var xz := 0.0
		var zz := 0.0
		for p in points:
			var d: Vector3 = flat(p) - mid
			xx += d.x * d.x
			xz += d.x * d.z
			zz += d.z * d.z
		# The long axis (and how much longer than the short one it is).
		var th := 0.5 * atan2(2.0 * xz, xx - zz)
		var tr := xx + zz
		var spread_ := sqrt(maxf(0.0, (xx - zz) * (xx - zz) * 0.25 + xz * xz))
		var long := tr * 0.5 + spread_
		var short := tr * 0.5 - spread_
		if long > 4.0 * maxf(short, 1e-6):
			var n := Vector3(-sin(th), 0, cos(th))
			dir = n if n.dot(to) >= 0.0 else -n
	return atan2(dir.x, dir.z)


## Free places to strike from, best first: round each foe at `dist`, at the
## ANGLES off the side facing `facing_` (the squad's facing), on walkable
## ground (`walkable`, a tile test), clear of the other foes and at least ROOM
## from `taken` (men who stay where they are) and from one another. A foe
## already struck by `loads[i]` men scores worse, as does a place farther round
## it or farther from `near` (the men who will move).
static func places(foe_at: Array, facing_: float, dist: float, taken: Array, loads: Array, near: Array, n: int, walkable: Callable) -> Array:
	var back := -Vector3(sin(facing_), 0, cos(facing_))
	var cands := []
	for i in foe_at.size():
		for a in ANGLES:
			var p: Vector3 = flat(foe_at[i]) + back.rotated(Vector3.UP, deg_to_rad(a)) * dist
			if not walkable.call(p):
				continue
			var ok := true
			for j in foe_at.size():
				if j != i and flat(foe_at[j] - p).length() < FOE_ROOM:
					ok = false
			if not ok:
				continue
			var far := INF
			for q in near:
				far = minf(far, flat(q - p).length())
			var score := float(loads[i]) + absf(a) / 30.0 * 0.6 + (0.25 * far if far < INF else 0.0)
			cands.append({"at": p, "foe": i, "score": score})
	cands.sort_custom(func(x, y): return x.score < y.score)
	var out := []
	for c in cands:
		if out.size() >= n:
			break
		var free := true
		for q in taken:
			if flat(q - c.at).length() < ROOM:
				free = false
		for q in out:
			if flat(q.at - c.at).length() < ROOM:
				free = false
		if free:
			out.append(c)
	return out


static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


static func yaw_to(from: Vector3, at: Vector3) -> float:
	var d := flat(at - from)
	return atan2(d.x, d.z)


# --- The squad -------------------------------------------------------------------

func alive() -> Array:
	return members.filter(func(m): return not m.is_dead())


func standing() -> int:
	return alive().size()


func centroid() -> Vector3:
	var men := alive()
	if men.is_empty():
		return center
	var c := Vector3.ZERO
	for m in men:
		c += m.position
	return c / men.size()


func describe() -> String:
	match mode:
		"march":
			return "marching"
		"reform":
			return "re-forming its ranks"
		"fight":
			if not engaged:
				return "advancing on the foe"
			return "fighting in one line" if spread else "front rank fighting, rear rank ready"
	return "standing in two ranks"


## Everyone on his place at once, standing (the field's reset).
func place(at: Vector3, facing_: float) -> void:
	halt()
	center = at
	yaw = facing_
	var men := alive()
	var spots := slots(at, facing_, men.size())
	for i in men.size():
		var m: Node3D = men[i]
		var b: Dictionary = _men[m]
		b.slot = i
		b.role = "front" if i < WIDTH else "rear"
		var p: Vector3 = spots[i] + _jitter(facing_)
		m.position = Vector3(p.x, field.ground_y(p.x, p.z), p.z)
		m.rotation.y = facing_ + _rng.randf_range(-YAW_JITTER, YAW_JITTER)


## Every man stops where he is.
func halt() -> void:
	mode = "idle"
	host.clear_route(_marks)
	foes = []
	spread = false
	_spread_in = -1.0
	for m in members:
		var b: Dictionary = _men[m]
		b.act = Callable()
		b.moving = false
		b.target = null
		b.blows = 0
		if not m.is_dead():
			m.stop()


## March to `goal` (a ground point: the squad's centre there), facing the way
## it goes or `facing_`. False if there is no way there.
func march_to(goal: Vector3, facing_: float = NAN) -> bool:
	if alive().is_empty():
		return false
	var c := centroid()
	var route: Array = field.path_to(c, field.tile_of(goal))
	if route.is_empty():
		return false
	var end: Vector3 = route[-1]
	if field.tile_of(goal) == field.tile_of(end):
		end = Vector3(goal.x, field.ground_y(goal.x, goal.z), goal.z)
	route = route.slice(0, route.size() - 1)
	if is_nan(facing_):
		var prev: Vector3 = route[-1] if not route.is_empty() else c
		facing_ = yaw_to(prev, end) if flat(end - prev).length() > 0.3 else yaw
	_stop_fight()
	mode = "march"
	_form(end, facing_, route, DELAY)
	return true


## Turn the squad in place to face `facing_` (the men take their new places).
func face(facing_: float) -> void:
	if alive().is_empty():
		return
	_stop_fight()
	mode = "reform"
	_form(centroid(), facing_, [], DELAY)


## Back into two ranks where it stands, facing as it faces.
func reform() -> void:
	if alive().is_empty():
		return
	var at := centroid() if mode != "fight" else _fight_at
	var y := yaw if mode != "fight" else _fight_yaw
	_stop_fight()
	mode = "reform"
	_form(at, y, [], REFORM_DELAY)


## Attack `target` and the foes standing with it (see the header).
func attack(target: Node3D) -> void:
	var men := alive()
	if men.is_empty() or not host._alive(target):
		return
	last_foe = target
	# The foe's front: the foes standing together with the target.
	var cands: Array = [target]
	for n in host.units + host.dummies:
		if n != target and n.visible and host._alive(n) and host._hostile(men[0], n):
			cands.append(n)
	var at := cands.map(func(n): return n.position)
	foes = group(at, 0).map(func(i): return cands[i])
	var pts := foes.map(func(n): return n.position)
	# The squad faces the foe nearest the middle of the front.
	var mid := Vector3.ZERO
	for p in pts:
		mid += flat(p)
	mid /= pts.size()
	var t0: Node3D = target
	for f in foes:
		if flat(f.position - mid).length() < flat(t0.position - mid).length() - 0.2:
			t0 = f
	var c := centroid()
	_fight_yaw = facing(pts, c, t0.position)
	var fwd := Vector3(sin(_fight_yaw), 0, cos(_fight_yaw))
	_fight_at = t0.position - fwd * (STRIKE_DIST + RANK * 0.5)
	if not field.walkable(field.tile_of(_fight_at)):
		var back := flat(c - t0.position).normalized()
		_fight_at = t0.position + back * (STRIKE_DIST + RANK * 0.5)
		_fight_yaw = yaw_to(_fight_at, t0.position)
	_fight_at.y = field.ground_y(_fight_at.x, _fight_at.z)
	spread = false
	engaged = false
	_spread_in = -1.0
	_gap = 0.0
	for m in members:
		var b: Dictionary = _men[m]
		b.target = null
		b.joined = false
		b.pause = _rng.randf_range(FIRST_PAUSE.x, FIRST_PAUSE.y)
	# Up to the foe in formation (straight in when it is near), then fight.
	var route: Array = []
	if flat(_fight_at - c).length() > 2.0 * field.tile_m:
		route = field.path_to(c, field.tile_of(_fight_at))
		route = route.slice(0, maxi(0, route.size() - 1))
	_form(_fight_at, _fight_yaw, route, DELAY)
	center = _fight_at
	yaw = _fight_yaw
	for m in men:
		var b: Dictionary = _men[m]
		b.blows = _rng.randi_range(FRONT_BLOWS.x, FRONT_BLOWS.y) if b.role == "front" else _rng.randi_range(REAR_BLOWS.x, REAR_BLOWS.y)
	mode = "fight"


func _stop_fight() -> void:
	foes = []
	spread = false
	engaged = false
	_spread_in = -1.0
	for m in members:
		var b: Dictionary = _men[m]
		b.target = null
		b.blows = 0
		b.joined = false


## The men to their places in the formation at `at` facing `facing_`, along
## `route` (the squad's corners before it, maybe none), each after his own
## delay (`lag`, seconds; the file leader first, the rear rank last).
func _form(at: Vector3, facing_: float, route: Array, lag: Vector2) -> void:
	var men := alive()
	center = at
	yaw = facing_
	var spots := slots(at, facing_, men.size())
	var pick := assign(men.map(func(m): return m.position), spots)
	var front := mini(men.size(), WIDTH)
	var marks := {}
	for p in route:
		marks[field.tile_of(p)] = 1
	marks[field.tile_of(at)] = 2
	for i in men.size():
		var m: Node3D = men[i]
		var b: Dictionary = _men[m]
		var j: int = pick[i]
		b.slot = j
		b.role = "front" if j < front else "rear"
		var off: Vector3 = (spots[j] - at).rotated(Vector3.UP, -facing_)
		var goal: Vector3 = spots[j] + _jitter(facing_)
		goal.y = field.ground_y(goal.x, goal.z)
		var pts := []
		for k in route.size():
			var q: Vector3 = route[k] + off.rotated(Vector3.UP, _heading(route, k, at, facing_))
			pts.append(Vector3(q.x, field.ground_y(q.x, q.z), q.z))
		pts.append(goal)
		if not _clear_path(m.position, pts):
			pts = _detour(m.position, goal)
		var lead := j == (front - 1) / 2
		var delay := _rng.randf_range(LEAD_DELAY.x, LEAD_DELAY.y) if lead else _rng.randf_range(lag.x, lag.y)
		if b.role == "rear":
			delay += REAR_DELAY
		_walk(m, pts, facing_ + _rng.randf_range(-YAW_JITTER, YAW_JITTER), delay)
	_marks = marks
	host.show_route(marks)


## The squad's heading at corner k of its route: halfway between the legs in and out.
func _heading(route: Array, k: int, at: Vector3, facing_: float) -> float:
	var from: Vector3 = route[k - 1] if k > 0 else centroid()
	var to: Vector3 = route[k + 1] if k + 1 < route.size() else at
	var d := flat(route[k] - from).normalized() + flat(to - route[k]).normalized()
	return atan2(d.x, d.z) if d.length() > 1e-3 else facing_


func _jitter(facing_: float) -> Vector3:
	return Vector3(_rng.randf_range(-JITTER.y, JITTER.y), 0, _rng.randf_range(-JITTER.x, JITTER.x)).rotated(Vector3.UP, facing_)


## Every leg on walkable ground (the field's straight-line test).
func _clear_path(from: Vector3, pts: Array) -> bool:
	var a := from
	for p in pts:
		if not field.walkable(field.tile_of(p)) or not field._clear(_grid(a), _grid(p)):
			return false
		a = p
	return true


func _detour(from: Vector3, goal: Vector3) -> Array:
	var pts: Array = field.path_to(from, field.tile_of(goal))
	if pts.is_empty():
		return [goal]
	pts[-1] = goal
	return pts


func _grid(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z) / field.tile_m


## Man m walks the points after `delay` seconds and faces `facing_` there.
func _walk(m: Node3D, pts: Array, facing_: float, delay: float) -> void:
	var b: Dictionary = _men[m]
	b.goal = pts[-1]
	b.moving = true
	b.still = 0.0
	b.act = func():
		if pts.size() == 1 and flat(pts[0] - m.position).length() < SETTLE:
			_arrived(m, facing_)
		else:
			m.order_move(pts, _arrived.bind(m, facing_))
	b.delay = delay


func _arrived(m: Node3D, facing_: float) -> void:
	var b: Dictionary = _men[m]
	b.moving = false
	if not m.is_dead():
		m.turn_to(m.position + Vector3(sin(facing_), 0, cos(facing_)))


## Each frame, after the men have moved (the sandbox calls it).
func tick(dt: float) -> void:
	var sdt := dt * float(host.speed)
	for m in members:
		var b: Dictionary = _men[m]
		if m.is_dead():
			b.act = Callable()
			b.moving = false
			continue
		if b.act.is_valid():
			b.delay -= sdt
			if b.delay <= 0.0:
				var a: Callable = b.act
				b.act = Callable()
				a.call()
			continue
		# A walk cut short (a blow taken on the way): he is not walking any more.
		if b.moving and m.state in ["idle", "block"] and m.path.is_empty():
			b.still += sdt
			if b.still > 0.6:
				b.moving = false
		else:
			b.still = 0.0
	match mode:
		"march", "reform":
			if alive().all(func(m): return _settled(m)):
				mode = "idle"
				host.clear_route(_marks)
		"fight":
			_fight(sdt)


func _settled(m: Node3D) -> bool:
	var b: Dictionary = _men[m]
	return not b.moving and not b.act.is_valid() and m.state in ["idle", "block"]


func _fight(sdt: float) -> void:
	foes = foes.filter(func(f): return host._alive(f))
	var men := alive()
	if foes.is_empty() or men.is_empty():
		_end_fight()
		return
	if _spread_in > 0.0:
		_spread_in -= sdt
		if _spread_in <= 0.0:
			_spread()
	_close_up()
	_gap -= sdt
	var done := true
	# The man who has waited longest strikes first, once the last blow is GAP old.
	var next: Node3D = null
	for m in men:
		var b: Dictionary = _men[m]
		# A rear man who never joins the line has no blows to strike.
		var waits: bool = b.role == "rear" and not b.joined
		if b.blows > 0 and not (waits and (not wide or spread)):
			done = false
		if not _settled(m) or b.blows <= 0 or waits:
			continue
		var t: Node3D = b.target
		if t == null or not host._alive(t) or flat(t.position - m.position).length() > REACH:
			t = _in_reach(m)
			b.target = t
		if t == null:
			# No foe in reach: to a free place by one, or he is done.
			var near: Array = _free(1, [m])
			if near.is_empty():
				b.blows = 0
				continue
			b.target = foes[near[0].foe]
			_walk(m, [near[0].at], yaw_to(near[0].at, b.target.position), 0.1)
			continue
		b.pause -= sdt
		if b.pause <= 0.0 and (next == null or b.pause < _men[next].pause):
			next = m
	if next and _gap <= 0.0:
		var b: Dictionary = _men[next]
		next.strike_at(b.target)
		if not engaged:
			host.clear_route(_marks)
		engaged = true
		b.blows -= 1
		b.pause = _rng.randf_range(PAUSE.x, PAUSE.y)
		_gap = _rng.randf_range(GAP.x, GAP.y)
		if b.role == "front" and wide and not spread and _spread_in < 0.0:
			_spread_in = _rng.randf_range(SPREAD_AFTER.x, SPREAD_AFTER.y)
	if done and men.all(func(m): return _settled(m)):
		_end_fight()


## A front man down: the rear man nearest his place steps up into it and
## fights in his stead.
func _close_up() -> void:
	var spots: Array = []
	for d in members:
		var bd: Dictionary = _men[d]
		if not d.is_dead() or bd.role != "front":
			continue
		bd.role = "fallen"
		bd.blows = 0
		if spots.is_empty():
			spots = slots(_fight_at, _fight_yaw, members.size())
		var at: Vector3 = spots[mini(bd.slot, spots.size() - 1)]
		var best: Node3D = null
		for m in alive():
			var b: Dictionary = _men[m]
			if b.role == "rear" and not b.joined and (best == null or flat(m.position - at).length() < flat(best.position - at).length()):
				best = m
		if best == null:
			continue
		var b: Dictionary = _men[best]
		b.role = "front"
		b.slot = bd.slot
		b.target = null
		b.blows = _rng.randi_range(FRONT_BLOWS.x, FRONT_BLOWS.y)
		b.pause = _rng.randf_range(FIRST_PAUSE.x, FIRST_PAUSE.y)
		var goal: Vector3 = at + _jitter(_fight_yaw)
		goal.y = field.ground_y(goal.x, goal.z)
		_walk(best, [goal], _fight_yaw, _rng.randf_range(SPREAD_DELAY.x, SPREAD_DELAY.y))


## The foe in reach of man m he faces best (near and ahead).
func _in_reach(m: Node3D) -> Node3D:
	var best: Node3D = null
	var bs := INF
	for f in foes:
		var d := flat(f.position - m.position)
		if d.length() > REACH:
			continue
		var off := absf(angle_difference(m.rotation.y, atan2(d.x, d.z)))
		var s := d.length() + off * 0.8
		if s < bs:
			bs = s
			best = f
	return best


## n free places by the foes for the men `movers` (see places()).
func _free(n: int, movers: Array) -> Array:
	var taken := []
	var loads := []
	loads.resize(foes.size())
	loads.fill(0)
	for m in alive():
		var b: Dictionary = _men[m]
		if m not in movers:
			taken.append(b.goal if b.moving else m.position)
		var i := foes.find(b.target)
		if i >= 0 and m not in movers:
			loads[i] += 1
	var walk := func(p: Vector3) -> bool: return field.walkable(field.tile_of(p))
	return places(foes.map(func(f): return f.position), _fight_yaw, STRIKE_DIST, taken, loads,
		movers.map(func(m): return m.position), n, walk)


## The rear rank spreads out to the line: each man to a free place by a foe,
## the places shared out so that the men's ways are short and do not cross.
func _spread() -> void:
	spread = true
	var rear := alive().filter(func(m): return _men[m].role == "rear" and not _men[m].joined)
	if rear.is_empty():
		return
	var free := _free(rear.size(), rear)
	var pick := assign(free.map(func(p): return p.at), rear.map(func(m): return m.position))
	for m in rear:
		_men[m].joined = true
	for k in free.size():
		var m: Node3D = rear[pick[k]]
		var b: Dictionary = _men[m]
		b.target = foes[free[k].foe]
		b.pause = _rng.randf_range(FIRST_PAUSE.x, FIRST_PAUSE.y)
		_walk(m, [free[k].at], yaw_to(free[k].at, b.target.position), _rng.randf_range(SPREAD_DELAY.x, SPREAD_DELAY.y))


func _end_fight() -> void:
	var at := _fight_at
	var y := _fight_yaw
	_stop_fight()
	if alive().is_empty():
		mode = "idle"
		return
	mode = "reform"
	_form(at, y, [], REFORM_DELAY)
