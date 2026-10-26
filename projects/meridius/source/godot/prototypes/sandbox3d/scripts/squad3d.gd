## A squad in the 3D sandbox: men of one kind (unit3d.gd, or the footman's
## footman_unit.gd, each on his own controller) who march, stand and fight
## together, each in his own time, so that no two move in step. Its drill
## (DRILLS, the footmen's FOOTMEN unless it says otherwise) is how its kind
## stands and fights:
##   - the formation: two ranks round the squad's centre facing `yaw`, `width`
##     men in the front rank and the rest behind it (three men with a front
##     rank of one stand in a wedge), `file` metres apart in a rank and `rank`
##     metres between the ranks; `stagger` sets the ranks chequered, each rear
##     man behind a gap in the front rank, so his spear or his shot passes it;
##   - the fight: "front" (the front rank strikes while the rear rank stands
##     ready; `wide` spreads the rear rank out to the line), "ranks" (both
##     ranks strike from their places, the rear rank's spears past the front
##     rank's shoulders), "all" (every man to a free place by a foe, round its
##     flanks if `flank`) or "shoot" (the squad halts in range with a clear
##     line and looses: in volleys, each man's shot timed to leave with the
##     others', or at will);
##   - its discipline: how far each man stands off his place and turned off
##     the squad's facing, how long he takes to move off on an order, how his
##     pace and size differ from his mates' (a goblin mob straggles; footmen
##     do not).
##
## A march follows the squad's route (field.path_to from its centre), each man
## walking it at his own place in the formation (a corner wheels it), and the
## men take the places nearest them (assign), so a squad sent the other way
## puts its rear rank in front. Each man sets off after his own short delay,
## walks at his own slightly different pace (the sandbox sets his `rate`),
## comes to rest a little off his exact place and turned a few degrees, and
## breathes and shifts in his own time.
##
## A fight (attack): the foes that stand together with the one attacked
## (LINK) are the foe's front. The squad marches up to face it, its front rank
## at striking distance from the foes' nearest rank (a shooting squad to a
## place in range with a clear line, or it only turns where it stands), and
## strikes as its drill says, each man a few blows in his own time and never
## two blows begun together (GAP). Each man goes for the foe nearest him (one
## his mates already strike counts as a little farther, so that they share the
## foes out), and a man of another squad whom he picks or strikes answers him
## if he can (counter): his squad, at rest, takes up the fight (or turns to
## face a foe still too far off), and he strikes back at the man who came for
## him. A front man who falls is replaced by the rear man nearest his place.
## While it advances it follows a foe who moves. Then the squad re-forms its
## ranks where it fought. Presentation only: the blows land through the
## sandbox (its _on_impact), as any unit's.
extends RefCounted

## The footmen's drill: metres between the men of a rank (the footman's lane
## step) and between the ranks, and the men in the front rank.
const FILE := 1.1
const RANK := 1.5
const WIDTH := 3
## Foes this near one another (metres) stand together as one front.
const LINK := 2.0
const MAX_FOES := 12
## A footman strikes a foe this near (centre to centre; the slash reaches about
## 2 m) and stands this near to strike it when he walks up (the slash's distance).
const REACH := 1.9
const STRIKE_DIST := 1.39
## Men stand at least this far apart; a place this near a foe is taken by it.
const ROOM := 0.8
const FOE_ROOM := 1.0
## The places round a foe a man may take: degrees off the side facing the squad.
const ANGLES := [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 120.0, -120.0, 150.0, -150.0]
## A flanking man (a wolf scout) likes a place this many degrees off the foe's front.
const FLANK := 75.0
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
## A rank that strikes past the one before it ("ranks") stands this far
## beyond its weapon's reach: blows land up to 0.45 m beyond it (unit3d.gd).
const OVERREACH := 0.3
## A volley: how far apart its shots leave (seconds), and the officer's pause
## once every man has reloaded before he gives the word again.
const VOLLEY_SPREAD := Vector2(0.0, 0.22)
const VOLLEY_PAUSE := Vector2(0.35, 0.9)
## While it advances the squad follows its foe when the foe has moved this far
## (metres), at most once every FOLLOW_EVERY seconds.
const FOLLOW := 2.0
const FOLLOW_EVERY := 1.0
## Choosing his foe, a man counts each mate who strikes it already as this
## many metres farther.
const SHARE := 0.6
## A squad at rest takes up a fight with a foe who comes for it this near
## (metres beyond its reach); a farther one it turns to face (more than
## BRACE_TURN radians off its facing) and waits for.
const ANSWER_NEAR := 1.5
const BRACE_TURN := 0.5
## A man of a squad at rest strikes back if he steadies within this many
## seconds of the blow (hit reactions run 1-3.5 s).
const RIPOSTE_WAIT := 4.0
## A man who has struck all his blows is given one to answer a foe with at
## most this many times a fight.
const ANSWERS := 3

## The footmen's drill, and what every other drill leaves as it is (see the
## header). `rate`: each man's pace against the clip's; `size`: his scale.
const FOOTMEN := {
	"width": WIDTH, "file": FILE, "rank": RANK, "stagger": false, "fight": "front", "wide": false,
	"room": ROOM, "jitter": JITTER, "yaw_jitter": YAW_JITTER, "delay": DELAY, "rear_delay": REAR_DELAY,
	"blows": FRONT_BLOWS, "rear_blows": REAR_BLOWS, "pause": PAUSE, "gap": GAP, "flank": false,
	"volley": false, "standoff": 0.0, "attacks": [], "rate": Vector2(0.95, 1.05), "size": Vector2(1.0, 1.0)}

## Each kind's drill, by the squad's id in Roster.SQUADS. `reach` and
## `strike` (metres: a foe this near is in reach, the front rank stands this
## near to strike) come from the man's first attack where not given;
## `standoff`: how far from its foe a shooting squad halts; `attacks`: the
## clips its men use (else all theirs).
const DRILLS := {
	"footman": {"reach": REACH, "strike": STRIKE_DIST},
	"spearman": {"file": 1.0, "rank": 0.9, "stagger": true, "fight": "ranks", "jitter": Vector2(0.04, 0.04),
		"yaw_jitter": 0.04, "rear_blows": Vector2i(3, 4), "pause": Vector2(0.2, 0.9), "gap": Vector2(0.14, 0.4)},
	"crossbowman": {"file": 1.25, "rank": 1.2, "stagger": true, "fight": "shoot", "volley": true, "standoff": 8.5,
		"blows": Vector2i(2, 2), "rear_blows": Vector2i(2, 2), "jitter": Vector2(0.06, 0.06)},
	"mage": {"width": 1, "file": 1.9, "rank": 1.5, "fight": "shoot", "standoff": 6.5, "blows": Vector2i(2, 3),
		"rear_blows": Vector2i(2, 3), "pause": Vector2(0.3, 1.0), "gap": Vector2(0.35, 0.8),
		"attacks": ["FireballCast", "ChainLightningCast", "FrostNovaCast", "EarthFistCast"]},
	"wolf_scout": {"width": 1, "file": 1.5, "rank": 1.3, "fight": "all", "flank": true, "room": 0.9,
		"jitter": Vector2(0.12, 0.12), "yaw_jitter": 0.14, "delay": Vector2(0.0, 0.25), "rear_delay": 0.1,
		"blows": Vector2i(2, 3), "rear_blows": Vector2i(2, 3), "pause": Vector2(0.2, 0.8), "gap": Vector2(0.15, 0.4)},
	"succubus": {"width": 1, "file": 2.2, "rank": 1.7, "fight": "all", "room": 1.4, "jitter": Vector2(0.1, 0.1),
		"yaw_jitter": 0.1, "blows": Vector2i(2, 3), "rear_blows": Vector2i(2, 3), "gap": Vector2(0.3, 0.7),
		"attacks": ["attack"]},
	"goblin_rabble": {"width": 5, "file": 0.82, "rank": 1.0, "wide": true, "room": 0.62,
		"jitter": Vector2(0.16, 0.14), "yaw_jitter": 0.24, "delay": Vector2(0.05, 0.9), "rear_delay": 0.15,
		"blows": Vector2i(2, 4), "rear_blows": Vector2i(2, 4), "pause": Vector2(0.15, 0.8), "gap": Vector2(0.1, 0.3),
		"rate": Vector2(0.9, 1.1), "size": Vector2(0.92, 1.06)},
	"goblin_archer": {"width": 4, "file": 1.0, "rank": 1.05, "stagger": true, "fight": "shoot", "volley": true,
		"standoff": 7.5, "blows": Vector2i(3, 3), "rear_blows": Vector2i(3, 3), "jitter": Vector2(0.1, 0.09),
		"yaw_jitter": 0.12, "delay": Vector2(0.05, 0.6), "rate": Vector2(0.92, 1.08), "size": Vector2(0.94, 1.05)},
	"goblin_spearman": {"width": 4, "file": 0.85, "rank": 0.75, "stagger": true, "fight": "ranks",
		"jitter": Vector2(0.05, 0.05), "yaw_jitter": 0.08, "delay": Vector2(0.05, 0.6), "rear_blows": Vector2i(3, 4),
		"gap": Vector2(0.12, 0.35), "rate": Vector2(0.92, 1.08), "size": Vector2(0.95, 1.04)},
	"orc_brute": {"file": 1.5, "rank": 1.7, "wide": true, "room": 1.05, "jitter": Vector2(0.1, 0.08),
		"yaw_jitter": 0.1, "delay": Vector2(0.05, 0.55), "blows": Vector2i(2, 3), "rear_blows": Vector2i(2, 3),
		"pause": Vector2(0.4, 1.2), "gap": Vector2(0.3, 0.6), "rate": Vector2(0.94, 1.06), "size": Vector2(0.96, 1.05)},
}

var members: Array = []
var field
## The sandbox: _alive, _hostile, units, dummies, speed, show_route, clear_route
## (and _line_clear, for a shooting squad's line).
var host
var id := "footman"
var title := "Footman squad"
var faction := "player"
var drill: Dictionary = FOOTMEN
var center := Vector3.ZERO
var yaw := 0.0
## "idle", "march", "fight", "reform".
var mode := "idle"
## The rear rank spreads out to fight beside the front rank (else only the
## front rank fights); a "front" drill's own choice.
var wide := false
## A shooting squad looses in volleys (else at will).
var volley := false
## The foe's front in the fight, and where the squad formed to face it.
var foes: Array = []
var spread := false
## The first blow of the fight has been struck (till then the squad advances).
var engaged := false
## The squad took up this fight because it was set upon (counter), not by order.
var answering := false
## The foe last attacked (the sandbox's Space strikes it again).
var last_foe: Node3D
## A foe this near is in reach (a shooting squad's: its longest shot), and the
## front rank stands this near it to strike (a shooting squad halts this far off).
var reach := REACH
var strike_dist := STRIKE_DIST
var _fight_at := Vector3.ZERO
var _fight_yaw := 0.0
var _spread_in := -1.0
var _gap := 0.0
## The foe the squad advances on and where he stood, to follow him if he moves.
var _anchor: Node3D
var _anchor_at := Vector3.ZERO
var _follow_in := 0.0
## A shooting squad's moves to shoot again since its last shot (_reaim).
var _retries := 0
## The route marks the squad's last order put on the ground.
var _marks := {}
## Per man: {slot, role ("front" / "rear"), act (an order waiting for its
## delay), delay, moving, goal, still (seconds stopped short while moving),
## target, blows, pause, joined (a rear man sent to the line), counter (the
## foe who came for him, whom he answers), answers (the blows he was given
## to answer with this fight), riposte and riposte_in (the foe he strikes back
## at when he has steadied, his squad at rest; the time left), swing (a blow
## or shot begun that has not left yet)}.
var _men := {}
var _rng := RandomNumberGenerator.new()


## The drill of squad `squad_id` (DRILLS over FOOTMEN).
static func drill_for(squad_id: String) -> Dictionary:
	var d := FOOTMEN.duplicate()
	d.merge(DRILLS.get(squad_id, {}), true)
	return d


func setup(men: Array, f, sandbox, at: Vector3, facing: float, drill_: Dictionary = {}) -> void:
	members = men
	field = f
	host = sandbox
	center = at
	yaw = facing
	drill = drill_ if not drill_.is_empty() else drill_for("footman")
	wide = bool(drill.wide)
	volley = bool(drill.volley)
	_rng.randomize()
	_measure()
	var front := mini(men.size(), int(drill.width))
	for i in men.size():
		_men[men[i]] = {"slot": i, "role": "front" if i < front else "rear", "act": Callable(), "delay": 0.0,
			"moving": false, "goal": men[i].position, "still": 0.0, "target": null, "blows": 0, "pause": 0.0,
			"joined": false, "counter": null, "riposte": null, "riposte_in": 0.0, "answers": 0, "swing": false}


## Reach and striking distance from the drill, or from the first man's attacks.
func _measure() -> void:
	var lead: Node3D = members[0] if not members.is_empty() else null
	if shooting():
		reach = 0.0
		if lead and lead.has_method("squad_attacks"):
			for i in lead.squad_attacks(drill.attacks):
				if lead.is_ranged(i):
					reach = maxf(reach, lead.reach(i))
		reach = reach if reach > 0.0 else 10.0
		strike_dist = minf(float(drill.standoff), reach * 0.8)
	else:
		var r: float = lead.reach(0) if lead and lead.has_method("reach") else STRIKE_DIST
		if drill.fight == "ranks":
			strike_dist = maxf(0.8, r + OVERREACH - float(drill.rank))
			reach = r + 0.45
		else:
			strike_dist = r
			reach = r + 0.35
	reach = float(drill.get("reach", reach))
	strike_dist = float(drill.get("strike", strike_dist))


func shooting() -> bool:
	return drill.fight == "shoot"


# --- Geometry --------------------------------------------------------------------

## The places of n men round `at` facing `facing` in drill d: the front rank
## (up to its width, centred, from the men's right to their left) half a rank
## ahead of the centre, the rest behind it; chequered if the drill staggers
## its ranks (each rank a quarter file to its side).
static func slots(at: Vector3, facing: float, n: int, d: Dictionary = FOOTMEN) -> Array:
	var fwd := Vector3(sin(facing), 0, cos(facing))
	var left := Vector3(cos(facing), 0, -sin(facing))
	var front := mini(n, int(d.width))
	var rank: float = d.rank
	var file: float = d.file
	var shift := file * 0.25 if d.stagger and n > front else 0.0
	var out := []
	for r in 2:
		var k := front if r == 0 else n - front
		for i in k:
			var across := (i - (k - 1) * 0.5) * file + (-shift if r == 0 else shift)
			out.append(at + fwd * (rank * 0.5 if r == 0 else -rank * 0.5) + left * across)
	return out


## For each point of `from`, the index of the place in `to` it goes to: each
## place to one, the sum of the squared distances least (the Hungarian
## method; `from` is no longer than `to`).
static func assign(from: Array, to: Array) -> Array:
	var n := from.size()
	var m := to.size()
	var out := []
	out.resize(n)
	if n == 0 or m < n:
		out.fill(0)
		return out
	var cost := []
	for i in n:
		var row := PackedFloat64Array()
		for j in m:
			row.append(flat(from[i] - to[j]).length_squared())
		cost.append(row)
	# Potentials of the rows and columns, the row on each column (1-based, 0 none).
	var u := PackedFloat64Array()
	u.resize(n + 1)
	var v := PackedFloat64Array()
	v.resize(m + 1)
	var p := PackedInt32Array()
	p.resize(m + 1)
	var way := PackedInt32Array()
	way.resize(m + 1)
	for i in range(1, n + 1):
		p[0] = i
		var j0 := 0
		var minv := PackedFloat64Array()
		minv.resize(m + 1)
		minv.fill(INF)
		var used := []
		used.resize(m + 1)
		used.fill(false)
		while true:
			used[j0] = true
			var i0 := p[j0]
			var delta := INF
			var j1 := 0
			for j in range(1, m + 1):
				if used[j]:
					continue
				var cur: float = cost[i0 - 1][j - 1] - u[i0] - v[j]
				if cur < minv[j]:
					minv[j] = cur
					way[j] = j0
				if minv[j] < delta:
					delta = minv[j]
					j1 = j
			for j in m + 1:
				if used[j]:
					u[p[j]] += delta
					v[j] -= delta
				else:
					minv[j] -= delta
			j0 = j1
			if p[j0] == 0:
				break
		while j0 != 0:
			var j1 := way[j0]
			p[j0] = p[j1]
			j0 = j1
	for j in range(1, m + 1):
		if p[j] != 0:
			out[p[j] - 1] = j - 1
	return out


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
## ground (`walkable`, a tile test), clear of the other foes and at least
## `room` from `taken` (men who stay where they are) and from one another. A
## foe already struck by `loads[i]` men scores worse, as does a place farther
## round it (farther from its flank, if `flank`) or farther from `near` (the
## men who will move).
static func places(foe_at: Array, facing_: float, dist: float, taken: Array, loads: Array, near: Array, n: int,
		walkable: Callable, room: float = ROOM, flank: bool = false) -> Array:
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
			var off := absf(absf(a) - FLANK) if flank else absf(a)
			var score := float(loads[i]) + off / 30.0 * 0.6 + (0.25 * far if far < INF else 0.0)
			cands.append({"at": p, "foe": i, "score": score})
	cands.sort_custom(func(x, y): return x.score < y.score)
	var out := []
	for c in cands:
		if out.size() >= n:
			break
		var free := true
		for q in taken:
			if flat(q - c.at).length() < room:
				free = false
		for q in out:
			if flat(q.at - c.at).length() < room:
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


## How the squad stands: "a wedge", "two ranks of five", "one rank of two".
func formation() -> String:
	var n := standing()
	var front := mini(n, int(drill.width))
	var words := ["no", "one", "two", "three", "four", "five", "six"]
	if n > front:
		if front == 1:
			return "a wedge"
		return "two ranks of %s" % words[mini(front, 6)]
	return "one rank of %s" % words[mini(n, 6)]


func describe() -> String:
	match mode:
		"march":
			return "marching"
		"reform":
			return "re-forming its ranks"
		"fight":
			if not engaged:
				return "moving into range" if shooting() else "advancing on the foe"
			match drill.fight:
				"shoot":
					return "loosing in volleys" if volley else "loosing at will"
				"ranks":
					return "both ranks striking"
				"all":
					return "closing round the foe"
			return "fighting in one line" if spread else "front rank fighting, rear rank ready"
	return "standing in " + formation()


## Everyone on his place at once, standing (the field's reset).
func place(at: Vector3, facing_: float) -> void:
	halt()
	center = at
	yaw = facing_
	var men := alive()
	var spots := slots(at, facing_, men.size(), drill)
	for i in men.size():
		var m: Node3D = men[i]
		var b: Dictionary = _men[m]
		b.slot = i
		b.role = "front" if i < int(drill.width) else "rear"
		var p: Vector3 = spots[i] + _jitter(facing_)
		m.position = Vector3(p.x, field.ground_y(p.x, p.z), p.z)
		m.rotation.y = facing_ + _rng.randf_range(-drill.yaw_jitter, drill.yaw_jitter)


## Every man stops where he is.
func halt() -> void:
	mode = "idle"
	host.clear_route(_marks)
	foes = []
	spread = false
	_spread_in = -1.0
	_anchor = null
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
		facing_ = march_facing(goal)
	_stop_fight()
	mode = "march"
	_form(end, facing_, route, drill.delay)
	return true


## The way the squad will face after marching to `goal`: the way it goes
## there (as it stands, for a step of less than a metre).
func march_facing(goal: Vector3) -> float:
	var c := centroid()
	return yaw_to(c, goal) if flat(goal - c).length() > 1.0 else yaw


## Turn the squad in place to face `facing_` (the men take their new places).
func face(facing_: float) -> void:
	if alive().is_empty():
		return
	_stop_fight()
	mode = "reform"
	_form(centroid(), facing_, [], drill.delay)


## Back into its ranks where it stands, facing as it faces.
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
	answering = false
	_retries = 0
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
	if shooting():
		_aim(t0, mid, c)
	else:
		_fight_yaw = facing(pts, c, t0.position)
		var fwd := Vector3(sin(_fight_yaw), 0, cos(_fight_yaw))
		# The front rank strikes the foes' nearest rank: across from t0, as deep as the nearest foe.
		var near := INF
		for p in pts:
			near = minf(near, flat(p - t0.position).dot(fwd))
		_fight_at = t0.position + fwd * minf(near, 0.0) - fwd * (strike_dist + float(drill.rank) * 0.5)
		if not field.walkable(field.tile_of(_fight_at)):
			var back := flat(c - t0.position).normalized()
			_fight_at = t0.position + back * (strike_dist + float(drill.rank) * 0.5)
			_fight_yaw = yaw_to(_fight_at, t0.position)
	_fight_at.y = field.ground_y(_fight_at.x, _fight_at.z)
	_anchor = t0
	_anchor_at = t0.position
	_follow_in = FOLLOW_EVERY
	spread = false
	engaged = false
	_spread_in = -1.0
	_gap = 0.0
	for m in members:
		var b: Dictionary = _men[m]
		b.target = null
		b.joined = false
		b.counter = null
		b.answers = 0
		b.pause = _rng.randf_range(FIRST_PAUSE.x, FIRST_PAUSE.y)
	# Up to the foe in formation (straight in when it is near), then fight.
	var route: Array = []
	if flat(_fight_at - c).length() > 2.0 * field.tile_m:
		route = field.path_to(c, field.tile_of(_fight_at))
		route = route.slice(0, maxi(0, route.size() - 1))
	_form(_fight_at, _fight_yaw, route, drill.delay)
	center = _fight_at
	yaw = _fight_yaw
	for m in men:
		var b: Dictionary = _men[m]
		var k: Vector2i = drill.blows if b.role == "front" else drill.rear_blows
		b.blows = _rng.randi_range(k.x, k.y)
	mode = "fight"


## Where a shooting squad looses at the front round `t0` (its middle `mid`)
## from `c`: where it stands, if the foe is in range there with a clear line
## (it only turns), else the nearest walkable place `strike_dist` off with a
## clear line, its men's places on walkable ground (the way it comes first,
## then round the foe).
func _aim(t0: Node3D, mid: Vector3, c: Vector3) -> void:
	var d := flat(t0.position - c).length()
	var depth := float(drill.rank)
	if d <= reach - depth - 0.5 and _line(c, t0.position):
		_fight_at = c
		_fight_yaw = yaw_to(c, mid)
		return
	var from := flat(c - t0.position).normalized() if d > 1e-3 else Vector3(-1, 0, 0)
	for a in [0.0, 20.0, -20.0, 40.0, -40.0, 60.0, -60.0, 90.0, -90.0, 130.0, -130.0, 180.0]:
		for k in [1.0, 0.75, 1.2]:
			var p: Vector3 = t0.position + from.rotated(Vector3.UP, deg_to_rad(a)) * strike_dist * k
			var y := yaw_to(p, mid)
			if not _line(p, t0.position):
				continue
			if slots(p, y, standing(), drill).all(func(s): return field.walkable(field.tile_of(s))):
				_fight_at = p
				_fight_yaw = y
				return
	_fight_at = c
	_fight_yaw = yaw_to(c, mid)


## A clear line of sight between two ground points (the sandbox's rule; any, without one).
func _line(a: Vector3, b: Vector3) -> bool:
	return not host.has_method("_line_clear") or host._line_clear(a, b)


func _stop_fight() -> void:
	foes = []
	spread = false
	engaged = false
	_spread_in = -1.0
	_anchor = null
	for m in members:
		var b: Dictionary = _men[m]
		b.target = null
		b.blows = 0
		b.joined = false
		b.counter = null
		b.riposte = null
		b.act = Callable()


## Man m of this squad is attacked by `foe` (who picked him or struck him):
## he answers him if he can. A squad at rest takes up the fight with the
## foe's front when the foe is near (a shooting squad when he is in range),
## else it turns to face him and waits for him; then m strikes back at him,
## if he can reach him (or step up to him), rear rank or not. His squad
## answers even if he fell.
## A squad that answers is `answering`: once it has re-formed, its foe's
## remaining blows do not set it on again (else two squads would take turns
## at it for ever, the blows being only shown); m only strikes back from
## where he stands (_riposte).
func counter(m: Node3D, foe: Node3D) -> void:
	if not _men.has(m) or not host._alive(foe) or alive().is_empty():
		return
	if "fight_back" in host and not host.fight_back:
		return
	var d := flat(foe.position - m.position).length()
	if at_rest():
		var theirs = host._squad_of(foe) if host.has_method("_squad_of") else null
		if theirs and theirs != self and theirs.answering and theirs.mode == "fight":
			_riposte(m, foe, d)
			return
		if d > (reach if shooting() else reach + ANSWER_NEAR):
			var y := yaw_to(centroid(), foe.position)
			if mode == "idle" and absf(angle_difference(yaw, y)) > BRACE_TURN:
				face(y)
			return
		attack(foe)
		answering = true
	# A foe a little beyond his reach he steps up to (a far shooter he leaves be).
	if m.is_dead() or mode != "fight" or (not shooting() and d > reach + ANSWER_NEAR):
		return
	var b: Dictionary = _men[m]
	if foe not in foes:
		foes.append(foe)
	b.counter = foe
	b.joined = true
	if not shooting() and d <= reach:
		b.target = foe
	# A man who has struck all his blows keeps one to answer with, unless
	# the foe is himself answering him (a strike back is not answered), up to
	# ANSWERS times a fight (so that every fight ends).
	var theirs = host._squad_of(foe) if host.has_method("_squad_of") else null
	if int(b.blows) < 1 and b.answers < ANSWERS and not (theirs and theirs._men.has(foe) and theirs._men[foe].counter == m):
		b.blows = 1
		b.answers += 1


## Man m of a squad at rest, struck by `foe` (`d` metres off), strikes back
## once from where he stands when he has steadied (within RIPOSTE_WAIT
## seconds), if the foe is still in his reach; the squad stays as it is. A
## blow from a squad at rest is a strike back, which nobody answers (the
## sandbox's _blow).
func _riposte(m: Node3D, foe: Node3D, d: float) -> void:
	if m.is_dead() or d > reach:
		return
	_men[m].riposte = foe
	_men[m].riposte_in = RIPOSTE_WAIT


## Man m's blow or shot has left (the sandbox's _on_impact and _on_release).
func swung(m: Node3D) -> void:
	if _men.has(m):
		_men[m].swing = false


## Man m is struck, before his hit reaction. A hit that cuts his swing short
## (his blow had not left) gives him the blow back, else a man struck often
## enough would spend all his blows on swings that never land and never
## answer his foes. A hit while he turns to strike only delays his swing.
func struck(m: Node3D) -> void:
	if not _men.has(m) or m.state != "attack":
		return
	var b: Dictionary = _men[m]
	if b.swing and mode == "fight":
		b.blows += 1
	b.swing = false


## The squad is not fighting: its men's blows are strikes back (_riposte).
func at_rest() -> bool:
	return mode in ["idle", "reform"]


## Man m goes for foe t (a new foe, or he strikes now): a man of another
## squad answers him (counter).
func _claim(m: Node3D, t: Node3D, striking := false) -> void:
	var b: Dictionary = _men[m]
	var fresh: bool = b.target != t
	b.target = t
	if t == null or not (fresh or striking) or not host.has_method("_squad_of"):
		return
	var sq = host._squad_of(t)
	if sq and sq != self:
		sq.counter(t, m)


## The men to their places in the formation at `at` facing `facing_`, along
## `route` (the squad's corners before it, maybe none), each after his own
## delay (`lag`, seconds; the file leader first, the rear rank last).
func _form(at: Vector3, facing_: float, route: Array, lag: Vector2) -> void:
	var men := alive()
	center = at
	yaw = facing_
	var spots := slots(at, facing_, men.size(), drill)
	var pick := assign(men.map(func(m): return m.position), spots)
	var front := mini(men.size(), int(drill.width))
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
			delay += float(drill.rear_delay)
		_walk(m, pts, facing_ + _rng.randf_range(-drill.yaw_jitter, drill.yaw_jitter), delay)
	_marks = marks
	host.show_route(marks)


## The squad's heading at corner k of its route: halfway between the legs in and out.
func _heading(route: Array, k: int, at: Vector3, facing_: float) -> float:
	var from: Vector3 = route[k - 1] if k > 0 else centroid()
	var to: Vector3 = route[k + 1] if k + 1 < route.size() else at
	var d := flat(route[k] - from).normalized() + flat(to - route[k]).normalized()
	return atan2(d.x, d.z) if d.length() > 1e-3 else facing_


func _jitter(facing_: float) -> Vector3:
	var j: Vector2 = drill.jitter
	return Vector3(_rng.randf_range(-j.y, j.y), 0, _rng.randf_range(-j.x, j.x)).rotated(Vector3.UP, facing_)


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
		if b.riposte:
			b.riposte_in -= sdt
			var f: Node3D = b.riposte
			if not at_rest() or b.riposte_in <= 0.0 or not host._alive(f):
				b.riposte = null
			elif _settled(m):
				b.riposte = null
				if flat(f.position - m.position).length() <= reach and _line(m.position, f.position):
					b.counter = f
					_strike(m, f)
	match mode:
		"march", "reform":
			if alive().all(func(m): return _settled(m)):
				mode = "idle"
				host.clear_route(_marks)
		"fight":
			if shooting():
				_shoot(sdt)
			else:
				_fight(sdt)


func _settled(m: Node3D) -> bool:
	var b: Dictionary = _men[m]
	return not b.moving and not b.act.is_valid() and m.state in ["idle", "block"]


## While the squad advances, its foe has moved off: it turns to follow him.
func _follow(sdt: float) -> bool:
	if engaged or _anchor == null or not host._alive(_anchor):
		return false
	_follow_in -= sdt
	if _follow_in > 0.0 or flat(_anchor.position - _anchor_at).length() < FOLLOW:
		return false
	var was := answering
	var given := {}
	for m in members:
		given[m] = _men[m].answers
	attack(_anchor)
	answering = was
	for m in members:
		_men[m].answers = given[m]
	return true


func _fight(sdt: float) -> void:
	foes = foes.filter(func(f): return host._alive(f))
	var men := alive()
	if foes.is_empty() or men.is_empty():
		_end_fight()
		return
	if _follow(sdt):
		return
	if _spread_in > 0.0:
		_spread_in -= sdt
		if _spread_in <= 0.0:
			_spread()
	if drill.fight in ["front", "ranks"]:
		_close_up()
	_gap -= sdt
	var done := true
	var front_only: bool = drill.fight == "front"
	# The man who has waited longest strikes first, once the last blow is GAP old.
	var next: Node3D = null
	for m in men:
		var b: Dictionary = _men[m]
		# A rear man who never joins the line has no blows to strike.
		var waits: bool = front_only and b.role == "rear" and not b.joined
		if b.blows > 0 and not (waits and (not wide or spread)):
			done = false
		if not _settled(m) or b.blows <= 0 or waits:
			continue
		var t: Node3D = b.target
		if t == null or not host._alive(t) or flat(t.position - m.position).length() > reach:
			t = _nearest(m, true)
			_claim(m, t)
		if t == null:
			# A spear in the rear rank keeps its place; anyone else goes to a
			# free place by the foe nearest him (else by any foe), or he is done.
			var near: Array = []
			if not (drill.fight == "ranks" and b.role == "rear"):
				var f := _nearest(m)
				near = _free(1, [m], f)
				if near.is_empty():
					near = _free(1, [m])
			if near.is_empty():
				b.blows = 0
				continue
			_claim(m, foes[near[0].foe])
			_walk(m, [near[0].at], yaw_to(near[0].at, b.target.position), 0.1)
			continue
		b.pause -= sdt
		if b.pause <= 0.0 and (next == null or b.pause < _men[next].pause):
			next = m
	if next and _gap <= 0.0:
		var b: Dictionary = _men[next]
		_claim(next, b.target, true)
		_strike(next, b.target)
		_engage()
		b.blows -= 1
		b.pause = _rng.randf_range(drill.pause.x, drill.pause.y)
		_gap = _rng.randf_range(drill.gap.x, drill.gap.y)
		if front_only and b.role == "front" and wide and not spread and _spread_in < 0.0:
			_spread_in = _rng.randf_range(SPREAD_AFTER.x, SPREAD_AFTER.y)
	if done and men.all(func(m): return _settled(m)):
		_end_fight()


## The first blow or shot of the fight: the advance is over.
func _engage() -> void:
	if not engaged:
		host.clear_route(_marks)
	engaged = true


## A shooting squad's fight: each man who has the foe in range with a clear
## line looses at the foe fewest of his mates aim at. In a volley every man
## waits for the others to have reloaded, then all loose together (each
## starts his shot so early that it leaves with the rest); at will each looses
## when he is ready, GAP after the last.
func _shoot(sdt: float) -> void:
	foes = foes.filter(func(f): return host._alive(f))
	var men := alive()
	if foes.is_empty() or men.is_empty():
		_end_fight()
		return
	if _follow(sdt):
		return
	var ready := []
	var busy := false
	var blocked := false
	var loads := {}
	for m in men:
		var b: Dictionary = _men[m]
		if b.blows <= 0:
			continue
		if not _settled(m):
			busy = true
			continue
		var t := _mark(m, loads)
		if t == null:
			blocked = true
			continue
		_claim(m, t)
		loads[t] = int(loads.get(t, 0)) + 1
		ready.append(m)
	if blocked and ready.is_empty() and not busy:
		_reaim(sdt)
		return
	if volley:
		# The officer's pause runs once every man has reloaded.
		if not busy and not ready.is_empty():
			_gap -= sdt
			if _gap <= 0.0:
				_volley(ready)
	else:
		_gap -= sdt
		var next: Node3D = null
		for m in ready:
			var b: Dictionary = _men[m]
			b.pause -= sdt
			if b.pause <= 0.0 and (next == null or b.pause < _men[next].pause):
				next = m
		if next and _gap <= 0.0:
			var b: Dictionary = _men[next]
			_loose(next, b.target, 0.0)
			b.pause = _rng.randf_range(drill.pause.x, drill.pause.y)
			_gap = _rng.randf_range(drill.gap.x, drill.gap.y)
	if not busy and ready.is_empty() and men.all(func(m): return _men[m].blows <= 0 and _settled(m)):
		_end_fight()


## Every ready man looses at his mark, each shot timed to leave with the
## slowest one's (its draw or aim the longest), give or take VOLLEY_SPREAD.
func _volley(ready: Array) -> void:
	var plans := []
	var lead := 0.0
	for m in ready:
		var b: Dictionary = _men[m]
		var i: int = m.pick_attack(b.target, drill.attacks) if m.has_method("squad_attacks") else 0
		var l: float = m.hit_lead(i) if m.has_method("hit_lead") else 0.0
		plans.append([m, i, l])
		lead = maxf(lead, l)
	for p in plans:
		_loose(p[0], _men[p[0]].target, lead - float(p[2]) + _rng.randf_range(VOLLEY_SPREAD.x, VOLLEY_SPREAD.y), p[1])
	_gap = _rng.randf_range(VOLLEY_PAUSE.x, VOLLEY_PAUSE.y)


## Man m shoots at `t` (attack i, or one that reaches) after `delay` seconds.
func _loose(m: Node3D, t: Node3D, delay: float, i := -1) -> void:
	var b: Dictionary = _men[m]
	b.blows -= 1
	b.act = func():
		if host._alive(t):
			_claim(m, t, true)
			_strike(m, t, i)
	b.delay = delay
	_retries = 0
	_engage()


## No man of a shooting squad who has shots left has a foe in range with a
## clear line (they moved off): it moves to shoot at the foe nearest it, each
## man keeping the shots he has left, at most once every FOLLOW_EVERY seconds
## and twice without a shot between; then the men with no shot are done.
func _reaim(sdt: float) -> void:
	_follow_in -= sdt
	if _follow_in > 0.0:
		return
	if _retries >= 2:
		for m in alive():
			if _mark(m, {}) == null:
				_men[m].blows = 0
		return
	var c := centroid()
	var best: Node3D = null
	for f in foes:
		if best == null or flat(f.position - c).length() < flat(best.position - c).length():
			best = f
	var left := {}
	for m in members:
		left[m] = [_men[m].blows, _men[m].answers]
	var was := answering
	var tries := _retries + 1
	attack(best)
	answering = was
	_retries = tries
	for m in members:
		_men[m].blows = left[m][0]
		_men[m].answers = left[m][1]


## Man m strikes `t` with attack i, or one of his drill's that reaches it.
func _strike(m: Node3D, t: Node3D, i := -1) -> void:
	_men[m].swing = true
	if not m.has_method("squad_attacks"):
		m.strike_at(t)
		return
	m.strike_at(t, i if i >= 0 else m.pick_attack(t, drill.attacks))


## The foe man m shoots at: the one who came for him, if he can, else of the
## foes in his reach with a clear line the nearest, each mate who aims at one
## already (`loads`) counting SHARE farther.
func _mark(m: Node3D, loads: Dictionary) -> Node3D:
	var c: Node3D = _men[m].counter
	if c and host._alive(c) and flat(c.position - m.position).length() <= reach and _line(m.position, c.position):
		return c
	var best: Node3D = null
	var bs := INF
	for f in foes:
		var d := flat(f.position - m.position).length()
		if d > reach or not _line(m.position, f.position):
			continue
		var s := d + float(loads.get(f, 0)) * SHARE * 3.0
		if s < bs:
			bs = s
			best = f
	return best


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
			spots = slots(_fight_at, _fight_yaw, members.size(), drill)
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
		b.blows = _rng.randi_range(drill.blows.x, drill.blows.y)
		b.pause = _rng.randf_range(FIRST_PAUSE.x, FIRST_PAUSE.y)
		var goal: Vector3 = at + _jitter(_fight_yaw)
		goal.y = field.ground_y(goal.x, goal.z)
		_walk(best, [goal], _fight_yaw, _rng.randf_range(SPREAD_DELAY.x, SPREAD_DELAY.y))


## The foe nearest man m (in his reach only, if `in_reach`): the one who came
## for him if he answers him, else each foe a mate strikes already counting
## SHARE farther, so that the men share the foes out.
func _nearest(m: Node3D, in_reach := false) -> Node3D:
	var c: Node3D = _men[m].counter
	if c and host._alive(c) and c in foes and (not in_reach or flat(c.position - m.position).length() <= reach):
		return c
	var loads := {}
	for o in alive():
		if o != m and _men[o].target:
			loads[_men[o].target] = int(loads.get(_men[o].target, 0)) + 1
	var best: Node3D = null
	var bs := INF
	for f in foes:
		var d := flat(f.position - m.position).length()
		if in_reach and d > reach:
			continue
		var s := d + float(loads.get(f, 0)) * SHARE
		if s < bs:
			bs = s
			best = f
	return best


## n free places by the foes (by foe `only`, if given) for the men `movers` (see places()).
func _free(n: int, movers: Array, only: Node3D = null) -> Array:
	var list: Array = foes if only == null else [only]
	var taken := []
	var loads := []
	loads.resize(list.size())
	loads.fill(0)
	for m in alive():
		var b: Dictionary = _men[m]
		if m not in movers:
			taken.append(b.goal if b.moving else m.position)
		var i := list.find(b.target)
		if i >= 0 and m not in movers:
			loads[i] += 1
	var walk := func(p: Vector3) -> bool: return field.walkable(field.tile_of(p))
	var out := places(list.map(func(f): return f.position), _fight_yaw, strike_dist, taken, loads,
		movers.map(func(m): return m.position), n, walk, float(drill.room), bool(drill.flank))
	# Each place by its foe's index in the squad's foes.
	for o in out:
		o.foe = foes.find(list[o.foe])
	return out


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
		_claim(m, foes[free[k].foe])
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
