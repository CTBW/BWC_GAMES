extends "res://tests/test_case.gd"

## The 3D unit sandbox (prototypes/sandbox3d): its map and routes, its fog,
## every rigged unit of the roster with the clips the sandbox plays, and the
## footman squad's formation and fight (on stand-in men and ground).

const Field3D = preload("res://prototypes/sandbox3d/scripts/field3d.gd")
const Fog3D = preload("res://prototypes/sandbox3d/scripts/fog3d.gd")
const Roster = preload("res://prototypes/sandbox3d/scripts/roster.gd")
const Squad3D = preload("res://prototypes/sandbox3d/scripts/squad3d.gd")
const Unit3D = preload("res://prototypes/sandbox3d/scripts/unit3d.gd")
const Relief = preload("res://scripts/render/relief.gd")
const Grid = preload("res://scripts/rules/grid.gd")


## The map and its relief only, without the ground, woods and bakes.
func _field() -> Node3D:
	var f: Node3D = Field3D.new()
	f._make_map()
	f.relief = Relief.new(Field3D.W, Field3D.H, Field3D.BORDER, f.map.tiles + f._outer, Field3D.SEED)
	return f


func test_map_has_hills_woods_water_and_a_free_yard() -> void:
	var f := _field()
	var lo := INF
	var hi := -INF
	var kinds := {}
	for t in f.map.tiles:
		lo = minf(lo, float(t.surface_h))
		hi = maxf(hi, float(t.surface_h))
		kinds[t.terrain] = true
	assert_true(hi - lo > 1.5, "hills: relief span %.2f levels" % (hi - lo))
	for k in ["grass", "dirt", "forest", "water"]:
		assert_true(kinds.has(k), "terrain " + k)
	var yard := Vector2i(roundi(Field3D.YARD.x), roundi(Field3D.YARD.y))
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			assert_true(f.walkable(yard + Vector2i(dx, dy)), "yard tile %s is free" % (yard + Vector2i(dx, dy)))
	f.free()


func test_routes_keep_to_walkable_ground_and_reach_the_goal() -> void:
	var f := _field()
	var from: Vector3 = f.on_ground(Field3D.YARD)
	var reached := 0
	for goal in [Vector2i(2, 3), Vector2i(25, 4), Vector2i(4, 24), Vector2i(24, 25), Vector2i(18, 9)]:
		if not f.walkable(goal):
			continue
		var pts: Array = f.path_to(from, goal)
		if not assert_false(pts.is_empty(), "a route to %s" % goal): continue
		reached += 1
		assert_eq(f.tile_of(pts[-1]), goal, "the route ends on its goal")
		var prev: Vector2 = Field3D.YARD
		for p in pts:
			var t: Vector2i = f.tile_of(p)
			assert_true(f.walkable(t), "route tile %s is walkable" % t)
			assert_almost(p.y, f.ground_y(p.x, p.z), 1e-4, "route point on the ground")
			assert_true(f._clear(Vector2(f.tile_of(Vector3(prev.x, 0, prev.y) * f.tile_m)), Vector2(t)), "straight leg %s to %s clears" % [prev, t])
			prev = Vector2(t)
	assert_true(reached >= 3, "most goals are reachable (%d)" % reached)
	# A goal in the water is moved to the nearest dry tile.
	var wet := Vector2i(-1, -1)
	for t in f.map.tiles:
		if t.terrain == "water":
			wet = Vector2i(t.x, t.y)
			break
	if assert_true(wet.x >= 0, "the pond has water"):
		var pts: Array = f.path_to(from, wet)
		assert_false(pts.is_empty(), "a route toward the pond")
		assert_true(f.walkable(f.tile_of(pts[-1])), "it stops on the bank")
	f.free()


func test_fog_sees_explores_and_forgets() -> void:
	var f := _field()
	var fog = Fog3D.new(f.map)
	var eye := Vector2i(roundi(Field3D.YARD.x), roundi(Field3D.YARD.y))
	fog.update([{"x": eye.x, "y": eye.y}], 0.1)
	assert_true(fog.seen.has(Grid.key(eye.x, eye.y)), "the eye's tile is seen")
	assert_false(fog.seen.has(Grid.key(0, 0)), "the far corner is not")
	var first: int = fog.explored.size()
	assert_eq(first, fog.seen.size())
	fog.update([{"x": 4, "y": 4}], 0.1)
	assert_true(fog.explored.has(Grid.key(eye.x, eye.y)), "explored ground stays explored")
	assert_true(fog.seen.has(Grid.key(4, 4)), "the eye moved: its new tile is seen")
	assert_true(fog.explored.size() > fog.seen.size())
	fog.forget()
	assert_eq(fog.explored.size(), fog.seen.size(), "forgetting keeps only what is seen")
	# The fog texture eases toward the state and then settles.
	for i in 200:
		fog.update([{"x": 4, "y": 4}], 0.1)
	assert_true(fog._settled)
	assert_almost(fog._img.get_pixel(4, 4).r, 1.0, 0.01, "seen tile is clear")
	assert_almost(fog._img.get_pixel(eye.x, eye.y).g, 0.0, 0.01, "forgotten tile is dark again")
	f.free()


func test_sidecar_events_in_every_form() -> void:
	assert_eq(Unit3D._events({"contact": 1.2, "lift": 0.4}), [[0.4, "lift"], [1.2, "contact"]])
	assert_eq(Unit3D._events({"step": [0.5, 0.1]}), [[0.1, "step"], [0.5, "step"]])
	assert_eq(Unit3D._events({"slash": [[0.3, "a"], [0.2, "b"]]}), [[0.2, "slash:b"], [0.3, "slash:a"]])
	assert_eq(Unit3D._events([{"time": 0.8, "name": "strike_left"}, {"seconds": 0.5, "name": "cast"}]), [[0.5, "cast"], [0.8, "strike_left"]])
	assert_eq(Unit3D._events(null), [])


func test_every_rigged_unit_loads_with_its_clips() -> void:
	if slow("loads every rigged 3D model"): return
	var tree := Engine.get_main_loop() as SceneTree
	var units: Array = Roster.available()
	# The footman's GLB and the wolf scout's export are not in Git: a unit whose
	# files are missing is left out, but the sandbox's own exports are there.
	for m in Roster.missing():
		print("  (%s left out: %s)" % [m.title, ", ".join(m.files)])
		for f in m.files:
			assert_false(String(f).begins_with(Roster.ART), "the sandbox's own export " + f)
	assert_eq(units.size() + Roster.missing().size(), Roster.UNITS.size())
	assert_true(units.size() >= 3, "at least the sandbox's own units")
	for p in units:
		var id := String(p.id)
		if p.get("controller", "") == "footman":
			_check_footman(p)
			continue
		# The whip effect samples posed bones, which needs the live tree; the
		# suite runs outside it, before the tree readies nodes.
		p.erase("fx")
		var u: Node3D = Unit3D.new()
		u.setup(p)
		tree.root.add_child(u)
		if not u.is_node_ready():
			u._ready()
		assert_true(u.has_clip(u.idle_clip()), id + " idle")
		assert_true(u.has_clip(String(u.profile.get("walk", "walk"))), id + " walk")
		assert_true(u.has_clip(String(u.profile.get("death", "death"))), id + " death")
		assert_between(u.height_m(), 1.2, 2.6, id + " height")
		assert_between(u.walk_speed(), 0.3, 3.0, id + " walk speed")
		var attacks := 0
		for a in u.actions():
			if a.get("target", false):
				attacks += 1
				var atk: Dictionary = u.attack_info(int(String(a.id).get_slice(":", 1)))
				assert_false(u.clips[atk.clip].events.is_empty(), "%s %s has its blow timed" % [id, atk.clip])
				# A missile that says where it leaves (the archer's arrow) leaves from his hands.
				var from: Vector3 = u.missile_from(int(String(a.id).get_slice(":", 1)))
				if from != Vector3.INF:
					assert_between(from.y - u.position.y, 0.6, u.height_m(), "%s %s leaves at hand height" % [id, atk.clip])
					assert_between(Vector2(from.x - u.position.x, from.z - u.position.z).length(), 0.2, 1.2,
						"%s %s leaves within arm's reach" % [id, atk.clip])
		assert_true(attacks > 0, id + " has an attack")
		u.free()


## The footman's own controller needs the live tree: check his model's clips.
func _check_footman(p: Dictionary) -> void:
	var model: Node = (load(p.model) as PackedScene).instantiate()
	var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	var clips := ["idle", "walk", "hit", "death"]
	for atk in p.get("attacks", []):
		clips.append(atk.clip)
	for c in clips:
		assert_true(player.has_animation(c), "footman " + c)
	model.free()


# --- The footman squad -----------------------------------------------------------

func test_squad_stands_in_two_ranks_of_three() -> void:
	var at := Vector3(10, 0, 20)
	var y := PI / 2
	var fwd := Vector3(sin(y), 0, cos(y))
	var left := Vector3(cos(y), 0, -sin(y))
	var spots: Array = Squad3D.slots(at, y, 6)
	assert_eq(spots.size(), 6)
	for i in 6:
		var d: Vector3 = spots[i] - at
		assert_almost(d.dot(fwd), Squad3D.RANK * (0.5 if i < 3 else -0.5), 1e-5, "man %d's rank" % i)
		assert_almost(d.dot(left), ((i % 3) - 1) * Squad3D.FILE, 1e-5, "man %d's file" % i)
	# Five men: the front rank full, the two behind it centred.
	var five: Array = Squad3D.slots(at, y, 5)
	assert_almost((five[3] - at).dot(left) + (five[4] - at).dot(left), 0.0, 1e-5, "the short rear rank is centred")


func test_squad_men_take_the_nearest_places() -> void:
	var spots: Array = Squad3D.slots(Vector3.ZERO, 0.0, 6)
	var shuffled := [spots[4], spots[0], spots[5], spots[2], spots[1], spots[3]]
	assert_eq(Squad3D.assign(shuffled, spots), [4, 0, 5, 2, 1, 3])
	# About face: the rear rank becomes the front rank instead of six men
	# walking through one another.
	var pick: Array = Squad3D.assign(spots, Squad3D.slots(Vector3.ZERO, PI, 6))
	for i in 3:
		assert_true(pick[i] >= 3, "front man %d goes to the new rear rank" % i)
		assert_true(pick[i + 3] < 3, "rear man %d goes to the new front rank" % i)


func test_squad_finds_the_foes_front_and_faces_it() -> void:
	# A line of six a file apart (along z), and a straggler farther off.
	var pts := []
	for k in 6:
		pts.append(Vector3(20, 0, k * Squad3D.FILE))
	pts.append(Vector3(20, 0, 6 * Squad3D.FILE + 4.0))
	var front: Array = Squad3D.group(pts, 2)
	front.sort()
	assert_eq(front, [0, 1, 2, 3, 4, 5], "the line, not the straggler")
	# Square to the line from the west; straight at a lone foe.
	assert_almost(Squad3D.facing(pts.slice(0, 6), Vector3(10, 0, 0), pts[2]), PI / 2, 1e-4, "east, square to the line")
	assert_almost(Squad3D.facing([pts[0]], Vector3(20, 0, -10), pts[0]), 0.0, 1e-4, "south, at the lone foe")


func test_squad_finds_free_places_beside_the_front_rank() -> void:
	var foes := []
	for k in 6:
		foes.append(Vector3(0, 0, (k - 2.5) * Squad3D.FILE))
	# The front rank stands before the middle three foes; three more places.
	var back := Vector3(Squad3D.STRIKE_DIST, 0, 0)
	var taken := [foes[1] - back, foes[2] - back, foes[3] - back]
	var near := taken.map(func(p): return p - Vector3(Squad3D.RANK, 0, 0))
	var out: Array = Squad3D.places(foes, PI / 2, Squad3D.STRIKE_DIST, taken, [0, 1, 1, 1, 0, 0], near, 3, func(_p): return true)
	assert_eq(out.size(), 3)
	var all: Array = taken + out.map(func(o): return o.at)
	var struck := []
	for c in out:
		assert_almost(c.at.x, -Squad3D.STRIKE_DIST, 1e-4, "in the line, facing its foe")
		for q in all:
			if q != c.at:
				assert_true(Squad3D.flat(q - c.at).length() >= Squad3D.ROOM - 1e-4, "room between the men")
		struck.append(c.foe)
	struck.sort()
	assert_eq(struck, [0, 4, 5], "each before a foe nobody strikes")


func test_squad_front_rank_fights_and_the_ranks_reform() -> void:
	var r := _squad_fight(false)
	assert_false(r.blows.is_empty(), "the squad struck")
	var men := {}
	for b in r.blows:
		assert_eq(b.role, "front", "only the front rank strikes")
		men[b.man] = true
	assert_eq(men.size(), 3, "every front man strikes")
	_assert_staggered(r.blows)
	assert_eq(r.squad.mode, "idle", "the fight ended")
	_assert_in_ranks(r.squad)
	_free_squad(r)


func test_squad_spread_to_the_line_lets_all_six_strike() -> void:
	var r := _squad_fight(true)
	var men := {}
	for b in r.blows:
		men[b.man] = true
	assert_eq(men.size(), 6, "every man strikes")
	for b in r.blows.slice(0, 3):
		assert_eq(b.role, "front", "the front rank strikes first")
	_assert_staggered(r.blows)
	assert_eq(r.squad.mode, "idle", "the fight ended")
	_assert_in_ranks(r.squad)
	_free_squad(r)


func test_squad_closes_up_when_a_front_man_falls() -> void:
	var r := _squad_rig()
	var sq = r.squad
	sq.attack(r.foes[2])
	_run(r, 9.0, false)
	assert_false(r.blows.is_empty(), "the fight began")
	var fallen: Node3D = r.blows[0].man
	fallen.dead = true
	var t0: float = r.host.now
	_run(r, 90.0)
	var men := {}
	for b in r.blows.filter(func(b): return b.t > t0):
		men[b.man] = true
	assert_false(men.has(fallen), "the fallen man strikes no more")
	assert_eq(men.size(), 3, "a rear man took his place and struck")
	assert_eq(sq.mode, "idle", "the fight ended")
	_assert_in_ranks(sq)
	_free_squad(r)


func _squad_fight(wide: bool) -> Dictionary:
	var r := _squad_rig()
	r.squad.wide = wide
	r.squad.attack(r.foes[2])
	_run(r, 90.0)
	return r


## Six stand-in men in two ranks facing east, 8 m from a line of six foes.
func _squad_rig() -> Dictionary:
	var host := FakeHost.new()
	var men := []
	for i in 6:
		var m := FakeMan.new()
		m.host = host
		men.append(m)
	for k in 6:
		var f := Node3D.new()
		f.position = Vector3(20, 0, 20 + (k - 2.5) * Squad3D.FILE)
		host.dummies.append(f)
	var sq = Squad3D.new()
	host.squad = sq
	sq.setup(men, FakeField.new(), host, Vector3(12, 0, 20), PI / 2)
	sq.place(Vector3(12, 0, 20), PI / 2)
	return {"squad": sq, "host": host, "foes": host.dummies, "blows": host.blows}


## Up to `seconds` of the fight at 30 frames a second (till it is over, if `until_idle`).
func _run(r: Dictionary, seconds: float, until_idle := true) -> void:
	var dt := 1.0 / 30.0
	var end: float = r.host.now + seconds
	while r.host.now < end:
		r.host.now += dt
		for m in r.squad.members:
			m.tick(dt)
		r.squad.tick(dt)
		if until_idle and r.squad.mode == "idle":
			break


func _assert_staggered(blows: Array) -> void:
	for i in range(1, blows.size()):
		var gap: float = blows[i].t - blows[i - 1].t
		assert_true(gap >= Squad3D.GAP.x - 0.04, "blows %d and %d %.2f s apart" % [i - 1, i, gap])


func _assert_in_ranks(sq) -> void:
	var spots: Array = Squad3D.slots(sq.center, sq.yaw, sq.standing())
	var front := 0
	for m in sq.alive():
		var b: Dictionary = sq._men[m]
		assert_true(Squad3D.flat(m.position - spots[b.slot]).length() < Squad3D.SETTLE + 0.1, "man on his place")
		if b.role == "front":
			front += 1
	assert_eq(front, mini(sq.standing(), Squad3D.WIDTH), "a full front rank")


## Frees the stand-ins and breaks the squad's ties to its host (they hold each other).
func _free_squad(r: Dictionary) -> void:
	r.host.squad = null
	r.squad._men.clear()
	for m in r.squad.members:
		m.free()
	for f in r.foes:
		f.free()


## A man who walks at 1 m/s, turns at once and strikes for 1.5 s.
class FakeMan extends Node3D:
	var host
	var state := "idle"
	var path: Array = []
	var dead := false
	var _then := Callable()
	var _busy := 0.0

	func is_dead() -> bool:
		return dead

	func stop() -> void:
		path.clear()
		state = "idle"

	func order_move(pts: Array, then := Callable()) -> void:
		path = pts.duplicate()
		_then = then
		state = "walk"

	func turn_to(at: Vector3, _after := Callable()) -> void:
		var d := at - position
		rotation.y = atan2(d.x, d.z)

	func strike_at(t: Node3D) -> void:
		turn_to(t.position)
		state = "attack"
		_busy = 1.5
		host.blows.append({"man": self, "t": host.now, "role": host.squad._men[self].role})

	func tick(dt: float) -> void:
		if dead:
			return
		if state == "attack":
			_busy -= dt
			if _busy <= 0.0:
				state = "idle"
		elif state == "walk":
			var step := dt
			while not path.is_empty() and step > 0.0:
				var d: Vector3 = path[0] - position
				if d.length() <= step:
					position = path[0]
					step -= d.length()
					path.pop_front()
				else:
					position += d.normalized() * step
					step = 0.0
			if path.is_empty():
				state = "idle"
				var f := _then
				_then = Callable()
				if f.is_valid():
					f.call()


class FakeHost:
	var squad
	var units: Array = []
	var dummies: Array = []
	var blows: Array = []
	var speed := 1.0
	var now := 0.0

	func _alive(n) -> bool:
		return n != null and not (n.has_method("is_dead") and n.is_dead())

	func _hostile(_a, b) -> bool:
		return b in dummies

	func show_route(_marks) -> void:
		pass

	func clear_route(_marks) -> void:
		pass


## Level open ground, 2.72 m tiles, every way straight.
class FakeField:
	var tile_m := 2.72

	func tile_of(p: Vector3) -> Vector2i:
		return Vector2i(roundi(p.x / tile_m), roundi(p.z / tile_m))

	func walkable(_t: Vector2i) -> bool:
		return true

	func ground_y(_x: float, _z: float) -> float:
		return 0.0

	func _clear(_a: Vector2, _b: Vector2) -> bool:
		return true

	func path_to(_from: Vector3, goal: Vector2i) -> Array:
		return [Vector3(goal.x * tile_m, 0, goal.y * tile_m)]
