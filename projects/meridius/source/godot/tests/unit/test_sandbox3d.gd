extends "res://tests/test_case.gd"

## The 3D unit sandbox (prototypes/sandbox3d): its map and routes, its fog,
## every rigged unit of the roster with the clips the sandbox plays, the
## succubus's kiss heart, the footman squad's formation and fight, and every
## kind's squad: its size, home and drill, how it fights, and how a squad set
## upon answers (on stand-in men and ground).

const Field3D = preload("res://prototypes/sandbox3d/scripts/field3d.gd")
const Fog3D = preload("res://prototypes/sandbox3d/scripts/fog3d.gd")
const Roster = preload("res://prototypes/sandbox3d/scripts/roster.gd")
const Squad3D = preload("res://prototypes/sandbox3d/scripts/squad3d.gd")
const Unit3D = preload("res://prototypes/sandbox3d/scripts/unit3d.gd")
const KissFX = preload("res://prototypes/sandbox3d/scripts/kiss_fx3d.gd")
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
	# The rigged models carry Mixamo-derived clips and are not in Git: a unit
	# whose files are missing is left out (a fresh clone has none of them).
	for m in Roster.missing():
		print("  (%s left out: %s)" % [m.title, ", ".join(m.files)])
	assert_eq(units.size() + Roster.missing().size(), Roster.UNITS.size())
	for p in units:
		var id := String(p.id)
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
			if String(a.id).begins_with("attack:"):
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
		if id == "footman":
			# His moves come from his clips: the shared code finds them.
			for m in ["can_march", "can_step_turn", "can_charge", "has_block", "can_step_lane"]:
				assert_true(u.call(m), "footman " + m)
		u.free()


## The spearman stands at ease. Now and then he takes up his guard for a loop
## or two and eases back. After a blow or a hit he holds the guard, and
## READY_HOLD after the last he is at ease again.
func test_spearman_stands_at_ease_and_holds_his_guard_in_a_fight() -> void:
	if slow("loads the spearman's model"): return
	var found: Array = Roster.available().filter(func(q): return q.id == "spearman")
	if found.is_empty():
		# His GLB (Mixamo-derived clips) stays local: not in a fresh clone.
		skip("the spearman's model is not on disk")
		return
	var u: Node3D = Unit3D.new()
	u.setup(found[0].duplicate(true))
	(Engine.get_main_loop() as SceneTree).root.add_child(u)
	if not u.is_node_ready():
		u._ready()
	var dt := 1.0 / 30.0
	assert_eq(u.idle_clip(), "idle_rest", "at ease is his idle")
	assert_eq(u._clip, "idle_rest")
	# A minute standing: the guard comes every 10 to 20 s and lasts 1.4 to 2.8 s.
	var spells := []
	var since := -1.0
	for i in 60 * 30:
		var was: String = u._clip
		u._process(dt)
		if was == "idle_rest" and u._clip == "idle":
			since = i * dt
		elif was == "idle" and u._clip == "idle_rest" and since >= 0.0:
			spells.append(i * dt - since)
		assert_true(u._clip in ["idle_rest", "idle"], "only at ease or on guard while standing")
	assert_between(spells.size(), 2, 6, "the guard now and then")
	for s in spells:
		assert_between(s, 1.4 - dt, 2.8 + dt, "the guard held a loop or two")
	# A blow from at ease: then on guard, without the idle's shifts, until
	# READY_HOLD is over. (A hit holds it the same way; take_hit needs the
	# live tree for the blow's direction.)
	u.strike(null, 0)
	assert_eq(u.state, "attack")
	u._on_finished(&"attack")
	assert_eq(u._clip, "idle", "on guard after the blow")
	for i in roundi((Unit3D.READY_HOLD - 0.5) * 30):
		u._process(dt)
		assert_eq(u._clip, "idle", "still on guard %.1f s after the blow" % (i * dt))
	for i in 30:
		u._process(dt)
	assert_eq(u._clip, "idle_rest", "at ease again after the fight")
	u.free()


## A stand-in caster for the kiss heart: casting, at her own playback.
class Caster extends Node3D:
	var state := "attack"
	var playback := 1.0


## The kiss heart reaches a target 5 m away about half a second after the
## release (as in the Blender study) and calls `land` once; the heart, its
## puffs and the veil are gone by 2 s, the mark holds over the target until
## MARK_HOLD and every card goes back to the pool. A cast cut short before
## the release lets the heart go and lands nothing.
func test_kiss_heart_lands_once_and_its_cards_return() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var fx: Node3D = KissFX.new()
	tree.root.add_child(fx)
	if not fx.is_node_ready():
		fx._ready()
	var caster := Caster.new()
	var target := Node3D.new()
	target.position = Vector3(0, 0, 5)
	tree.root.add_child(caster)
	tree.root.add_child(target)
	var landed := []
	var t := [0.0]
	fx.launch(caster, target, func(who): landed.append([who, t[0]]))
	var step := 1.0 / 60.0
	while t[0] < 2.0:
		fx._process(step)
		t[0] += step
	assert_eq(landed.size(), 1, "the kiss lands once")
	if landed.size() == 1:
		assert_true(landed[0][0] == target, "on its target")
		assert_between(landed[0][1] - KissFX.BREATH, 0.45, 0.58, "seconds from the release to the contact")
	assert_true(fx._kisses.is_empty() and fx._puffs.is_empty() and fx._veils.is_empty(), "the heart and its fog are gone")
	assert_eq(fx._marks.size(), 1, "the mark holds")
	while t[0] < 2.0 + KissFX.MARK_HOLD:
		fx._process(step)
		t[0] += step
	assert_true(fx._marks.is_empty(), "the mark goes")
	assert_eq(fx._spare.size(), fx._cards, "every card back in the pool")
	# Cut short: struck before the release.
	fx.launch(caster, target, func(who): landed.append([who, t[0]]))
	fx._process(step)
	caster.state = "hit"
	for i in 60:
		fx._process(step)
	assert_eq(landed.size(), 1, "a cut cast lands nothing")
	assert_true(fx._kisses.is_empty(), "and its heart goes")
	assert_eq(fx._spare.size(), fx._cards, "every card back in the pool after the cut")
	for n in [fx, caster, target]:
		n.free()


## The brutes' faces and kit: no two men of the squad share a face, each wears
## its own meshes and none of the others', the scar paints his body, and a
## pauldron taken off is gone; some men carry a club in each fist.
func test_orc_brute_faces_dress_each_man() -> void:
	var squad: Dictionary = Roster.SQUADS.filter(func(s): return s.id == "orc_brute")[0]
	var brute: Dictionary = Roster.UNITS.filter(func(p): return p.id == "orc_brute")[0]
	var dual: Dictionary = Roster.UNITS.filter(func(p): return p.id == "orc_brute_dual")[0]
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(brute.meta))
	assert_true(squad.units.has("orc_brute") and squad.units.has("orc_brute_dual"), "one club and two clubs in the squad")
	assert_eq(squad.faces.size(), int(squad.size), "a face for every brute")
	assert_eq(squad.kit.size(), int(squad.size), "a kit for every brute")
	var seen := {}
	for f in squad.faces:
		var key := "+".join(PackedStringArray(f))
		assert_false(seen.has(key), "two brutes with the face " + key)
		seen[key] = true
		for k in f:
			assert_true(meta.faces.has(k), "the sidecar has the face " + k)
	for kit in squad.kit:
		for k in kit:
			assert_true(meta.kit.has(k), "the sidecar has the kit " + k)
	if FileAccess.file_exists(dual.meta):
		var dual_meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dual.meta))
		assert_eq(dual_meta.faces, meta.faces, "the two-club brute has the same faces")
		assert_eq(dual_meta.kit, meta.kit, "and the same kit")
	if slow("loads the orc brutes once a face and a kit"): return
	if not ResourceLoader.exists(brute.model) or not ResourceLoader.exists(dual.model):
		print("  (the orc brutes' GLBs are not on disk)")
		return
	var tree := Engine.get_main_loop() as SceneTree
	# Each face on the one-club brute, each kit on the two-club brute.
	var looks := []
	for f in squad.faces:
		looks.append([brute, f, []])
	for kit in squad.kit:
		looks.append([dual, [], kit])
	for look in looks:
		var p: Dictionary = look[0].duplicate(true)
		var f: Array = look[1]
		var kit: Array = look[2]
		p["face"] = f
		p["kit"] = kit
		var u: Node3D = Unit3D.new()
		u.setup(p)
		tree.root.add_child(u)
		if not u.is_node_ready():
			u._ready()
		var key := "%s %s" % [p.id, "+".join(PackedStringArray(f + kit))]
		assert_eq(u.model.find_child("JawPlate", true, false) != null, f.has("jaw"), key + ": the jaw plate")
		assert_eq(u.model.find_child("Beard", true, false) != null, f.has("beard"), key + ": the beard")
		var body := u.model.find_child("OrcBrute", true, false) as MeshInstance3D
		var tex: Texture2D = (body.get_active_material(0) as StandardMaterial3D).albedo_texture
		assert_eq(tex.resource_path.ends_with("orc_brute_body_scar_basecolor.jpg"), f.has("scar"), key + ": the scar")
		assert_eq(u.model.find_child("PauldronLeft", true, false) != null, not kit.has("no_left_pauldron"), key + ": the left pauldron")
		assert_eq(u.model.find_child("PauldronRight", true, false) != null, not kit.has("no_right_pauldron"), key + ": the right pauldron")
		assert_true(u.model.find_child("Club", true, false) != null, key + ": the club")
		assert_eq(u.model.find_child("ClubLeft", true, false) != null, p.id == "orc_brute_dual", key + ": the left club")
		u.free()


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


# --- Every kind's squad -----------------------------------------------------------

func test_roster_squads_have_their_sizes_and_drills() -> void:
	var sizes := {"footman": 6, "spearman": 6, "crossbowman": 6, "mage": 3, "wolf_scout": 3, "wolf_scout_2": 3,
		"succubus": 3, "goblin_rabble": 10, "goblin_archer": 8, "goblin_spearman": 8, "orc_brute": 6}
	var ids := {}
	for p in Roster.UNITS:
		ids[p.id] = p
	var served := {}
	for s in Roster.SQUADS:
		assert_eq(int(s.size), int(sizes.get(s.id, -1)), s.id + " size")
		assert_true(Squad3D.DRILLS.has(String(s.get("drill", s.id))), s.id + " has its drill")
		for u in s.units:
			assert_true(ids.has(u), "%s's men (%s) are in the roster" % [s.id, u])
			served[u] = true
	for id in sizes:
		assert_true(Roster.SQUADS.any(func(s): return s.id == id), id + " has a squad")
	for p in Roster.UNITS:
		assert_true(served.has(p.id), p.id + " serves in a squad")
	# The goblins in two ranks of four, the rabble two of five, threes in a wedge.
	assert_eq(int(Squad3D.drill_for("goblin_archer").width), 4)
	assert_eq(int(Squad3D.drill_for("goblin_spearman").width), 4)
	assert_eq(int(Squad3D.drill_for("goblin_rabble").width), 5)
	for id in ["mage", "wolf_scout", "succubus"]:
		assert_eq(int(Squad3D.drill_for(id).width), 1, id + " stands in a wedge")


func test_squads_bench_and_drill_line_stand_apart_on_open_ground() -> void:
	var f := _field()
	var ids := {}
	for p in Roster.UNITS:
		ids[p.id] = p
	var k: Dictionary = load("res://prototypes/sandbox3d/scripts/sandbox3d.gd").get_script_constant_map()
	var groups := {}
	for s in Roster.SQUADS:
		var player: bool = ids[s.units[0]].faction == "player"
		var at: Vector3 = Vector3(s.home.x, 0, s.home.y) * f.tile_m
		var d: Dictionary = Squad3D.drill_for(String(s.get("drill", s.id)))
		var spots: Array = Squad3D.slots(at, k.PLAYER_FACING if player else k.ENEMY_FACING, int(s.size), d)
		for p in spots:
			assert_true(f.walkable(f.tile_of(p)), "%s's man at %s on open ground" % [s.id, f.tile_of(p)])
		groups[s.id] = spots
	var bench := []
	for i in Roster.UNITS.size():
		var t: Vector2 = k.BENCH + k.BENCH_STEP * i
		bench.append(Vector3(t.x, 0, t.y) * f.tile_m)
	for t in k.DUMMY_TILES:
		bench.append(Vector3(t.x, 0, t.y) * f.tile_m)
	for i in k.DRILL_COUNT:
		var g: Vector2 = k.DRILL + Vector2(0, (i - (k.DRILL_COUNT - 1) * 0.5) * Squad3D.FILE / f.tile_m)
		bench.append(Vector3(g.x, 0, g.y) * f.tile_m)
	for p in bench:
		assert_true(f.walkable(f.tile_of(p)), "bench, dummy or drill line at %s on open ground" % f.tile_of(p))
	groups["the bench, its dummies and the drill line"] = bench
	# No two squads (or a squad and the bench) near enough to count as one front.
	var names := groups.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var near := INF
			for p in groups[names[i]]:
				for q in groups[names[j]]:
					near = minf(near, Squad3D.flat(p - q).length())
			assert_true(near > Squad3D.LINK + 1.0, "%s and %s %.1f m apart" % [names[i], names[j], near])
	f.free()


func test_drills_stand_as_their_kinds_do() -> void:
	var y := PI / 2
	var fwd := Vector3(sin(y), 0, cos(y))
	var left := Vector3(cos(y), 0, -sin(y))
	# The rabble: two ranks of five, a file apart.
	var rd: Dictionary = Squad3D.drill_for("goblin_rabble")
	var rabble: Array = Squad3D.slots(Vector3.ZERO, y, 10, rd)
	assert_eq(rabble.size(), 10)
	for i in 10:
		assert_almost(rabble[i].dot(fwd), rd.rank * (0.5 if i < 5 else -0.5), 1e-5, "rabble man %d's rank" % i)
		assert_almost(absf(rabble[i].dot(left)), absf(((i % 5) - 2) * rd.file), 1e-5, "rabble man %d's file" % i)
	# The archers: two ranks of four, each rear man behind a gap in the front rank.
	var ad: Dictionary = Squad3D.drill_for("goblin_archer")
	var arch: Array = Squad3D.slots(Vector3.ZERO, y, 8, ad)
	for i in range(4, 8):
		var gap := INF
		for j in 4:
			gap = minf(gap, absf(arch[i].dot(left) - arch[j].dot(left)))
		assert_almost(gap, ad.file * 0.5, 1e-5, "archer %d stands behind a gap" % i)
	# Three in a wedge: the point ahead in the middle, two behind either side.
	var w: Array = Squad3D.slots(Vector3.ZERO, y, 3, Squad3D.drill_for("mage"))
	assert_almost(w[0].dot(left), 0.0, 1e-5, "the wedge's point in the middle")
	assert_true(w[0].dot(fwd) > w[1].dot(fwd) and w[0].dot(fwd) > w[2].dot(fwd), "the point ahead")
	assert_almost(w[1].dot(left), -w[2].dot(left), 1e-5, "the two behind either side")
	var r := _kind_rig("goblin_rabble", 10, 0)
	assert_eq(r.squad.formation(), "two ranks of five")
	_free_squad(r)
	r = _kind_rig("wolf_scout", 3, 0)
	assert_eq(r.squad.formation(), "a wedge")
	_free_squad(r)


func test_ten_men_take_the_nearest_places() -> void:
	var d: Dictionary = Squad3D.drill_for("goblin_rabble")
	var spots: Array = Squad3D.slots(Vector3.ZERO, 0.0, 10, d)
	var order := [7, 2, 9, 0, 5, 3, 8, 1, 6, 4]
	assert_eq(Squad3D.assign(order.map(func(i): return spots[i]), spots), order)
	var pick: Array = Squad3D.assign(spots, Squad3D.slots(Vector3.ZERO, PI, 10, d))
	for i in 5:
		assert_true(pick[i] >= 5, "front man %d goes to the new rear rank" % i)
		assert_true(pick[i + 5] < 5, "rear man %d goes to the new front rank" % i)


func test_each_man_goes_for_the_foe_nearest_him() -> void:
	var r := _kind_rig("footman", 6, 6)
	r.squad.attack(r.foes[2])
	_run(r, 90.0)
	var first := {}
	for b in r.blows:
		if not first.has(b.man):
			first[b.man] = b
	assert_eq(first.size(), 3, "the front rank struck")
	for m in first:
		var b: Dictionary = first[m]
		var near: Node3D = null
		for f in r.foes:
			if near == null or Squad3D.flat(f.position - b.pos).length() < Squad3D.flat(near.position - b.pos).length():
				near = f
		assert_eq(b.target, near, "a front man's first blow at the foe nearest him")
	var struck := {}
	for b in r.blows:
		struck[b.target] = true
	assert_true(struck.size() >= 3, "the front rank shares the foes out")
	_free_squad(r)


func test_both_ranks_of_spears_strike_from_their_places() -> void:
	for id in ["spearman", "goblin_spearman"]:
		var n := 6 if id == "spearman" else 8
		var r := _kind_rig(id, n, 6)
		var sq = r.squad
		sq.attack(r.foes[2])
		_run(r, 120.0)
		var roles := {}
		var spots: Array = Squad3D.slots(sq.center, sq.yaw, n, sq.drill)
		for b in r.blows:
			roles[b.role] = true
			if b.role == "rear":
				assert_true(Squad3D.flat(b.pos - spots[b.slot]).length() < Squad3D.SETTLE + 0.2, id + " rear man strikes from his place")
		assert_true(roles.has("front") and roles.has("rear"), id + ": both ranks strike")
		_assert_staggered(r.blows, sq.drill.gap.x)
		assert_eq(sq.mode, "idle", id + ": the fight ended")
		_free_squad(r)


func test_shooters_loose_in_volleys_or_at_will() -> void:
	var r := _kind_rig("crossbowman", 6, 6)
	r.squad.attack(r.foes[2])
	_run(r, 90.0)
	var groups := []
	for b in r.blows:
		if groups.is_empty() or b.t - groups[-1][-1] > 1.0:
			groups.append([b.t])
		else:
			groups[-1].append(b.t)
	assert_eq(r.blows.size(), 12, "two shots each")
	assert_eq(groups.size(), 2, "in two volleys")
	for g in groups:
		assert_eq(g.size(), 6, "every man looses in the volley")
		assert_true(g[-1] - g[0] <= Squad3D.VOLLEY_SPREAD.y + 0.05, "the volley's shots leave together (%.2f s)" % (g[-1] - g[0]))
	assert_eq(r.squad.mode, "idle", "the fight ended")
	_free_squad(r)
	r = _kind_rig("crossbowman", 6, 6)
	r.squad.volley = false
	r.squad.attack(r.foes[2])
	_run(r, 90.0)
	assert_eq(r.blows.size(), 12, "at will: two shots each")
	_assert_staggered(r.blows)
	_free_squad(r)


func test_a_wedge_closes_round_its_foe() -> void:
	var r := _kind_rig("wolf_scout", 3, 1)
	var foe: Node3D = r.foes[0]
	r.squad.attack(foe)
	_run(r, 90.0)
	var at := {}
	for b in r.blows:
		if not at.has(b.man):
			at[b.man] = b.pos
	assert_eq(at.size(), 3, "every wolf strikes")
	var angles := []
	for m in at:
		assert_true(Squad3D.flat(at[m] - foe.position).length() <= r.squad.reach + 0.05, "a wolf strikes from within reach")
		for o in at:
			if o != m:
				assert_true(Squad3D.flat(at[m] - at[o]).length() >= float(r.squad.drill.room) - 0.05, "room between the wolves")
		var d := Squad3D.flat(at[m] - foe.position)
		angles.append(atan2(d.x, d.z))
	var spread := 0.0
	for a in angles:
		for b in angles:
			spread = maxf(spread, absf(angle_difference(a, b)))
	assert_true(spread > deg_to_rad(60.0), "round the foe, not in a file (%.0f degrees)" % rad_to_deg(spread))
	_free_squad(r)


func test_a_squad_set_upon_answers_and_the_fight_ends() -> void:
	var host := FakeHost.new()
	var a = _side_squad(host, "player", Vector3(12, 0, 20), PI / 2)
	var b = _side_squad(host, "enemy", Vector3(20, 0, 20), -PI / 2)
	host.squad = a
	host.units = a.members + b.members
	a.attack(b.members[1])
	var answered := false
	var dt := 1.0 / 30.0
	while host.now < 150.0:
		host.now += dt
		for m in host.units:
			m.tick(dt)
		a.tick(dt)
		b.tick(dt)
		if b.mode == "fight" and b.answering:
			answered = true
		if host.now > 2.0 and a.mode == "idle" and b.mode == "idle":
			break
	assert_true(answered, "the squad set upon took up the fight")
	assert_eq(a.mode, "idle", "the attackers' fight ended")
	assert_eq(b.mode, "idle", "the answer ended too: no endless exchange")
	# Every man struck strikes back at a man who struck him.
	var struck := {}
	for x in host.blows:
		if x.man in a.members:
			if not struck.has(x.target):
				struck[x.target] = []
			struck[x.target].append(x)
	assert_false(struck.is_empty(), "the attackers struck")
	for t in struck:
		var t0: float = struck[t][0].t
		var by: Array = struck[t].map(func(x): return x.man)
		assert_true(host.blows.any(func(y): return y.man == t and y.t > t0 and y.target in by), "the man struck strikes back at his striker")
	_free_sides(host, a, b)


func test_a_squad_at_rest_strikes_back_from_its_places() -> void:
	var host := FakeHost.new()
	var a = _side_squad(host, "player", Vector3(12, 0, 20), PI / 2)
	var b = _side_squad(host, "enemy", Vector3(15, 0, 20), -PI / 2)
	host.squad = a
	host.units = a.members + b.members
	# The foes answer a fight that is over for the squad: its man struck
	# strikes back once from his place, and the squad stays at rest.
	b.attack(a.members[1])
	b.answering = true
	var m: Node3D = a.members[1]
	var foe: Node3D = b.members[1]
	var at := m.position
	a.counter(m, foe)
	var dt := 1.0 / 30.0
	while host.now < 3.0:
		host.now += dt
		for n in a.members:
			n.tick(dt)
		a.tick(dt)
	assert_eq(a.mode, "idle", "the squad stays at rest")
	var back: Array = host.blows.filter(func(x): return x.man == m)
	assert_eq(back.size(), 1, "the man struck strikes back once")
	assert_true(not back.is_empty() and back[0].target == foe, "at the man who struck him")
	assert_almost(Squad3D.flat(m.position - at).length(), 0.0, 1e-4, "from his place")
	# Set upon by foes who are not answering, it takes up the fight.
	b.answering = false
	a.counter(m, foe)
	assert_eq(a.mode, "fight", "the squad takes up the fight")
	assert_true(a.answering, "as the one set upon")
	_free_sides(host, a, b)


func test_a_swing_cut_short_by_a_hit_is_given_back() -> void:
	var r := _squad_rig()
	var sq = r.squad
	sq.attack(r.foes[2])
	_run_until(r, func(): return not r.blows.is_empty(), 30.0)
	assert_false(r.blows.is_empty(), "a man strikes")
	var m: Node3D = r.blows[0].man
	var b: Dictionary = sq._men[m]
	var left: int = b.blows
	# Struck before his blow left: the hit reaction ends his swing.
	sq.struck(m)
	m.state = "idle"
	assert_eq(int(b.blows), left + 1, "the blow cut short is given back")
	# Struck after it left (or while he only turns to strike): he keeps what he has.
	_run_until(r, func(): return r.blows.size() > 1 and r.blows[-1].man == m, 30.0)
	left = b.blows
	sq.swung(m)
	sq.struck(m)
	assert_eq(int(b.blows), left, "a blow that left is spent")
	b.swing = true
	m.state = "idle"
	sq.struck(m)
	assert_eq(int(b.blows), left, "a hit while he turns only delays his swing")
	assert_true(b.swing, "his swing is still to come")
	# A footman's step turn to strike: the hit ends it and the blow after it.
	m.state = "turn"
	sq.struck(m)
	m.state = "idle"
	assert_eq(int(b.blows), left + 1, "a blow lost with the footman's turn is given back")
	assert_false(b.swing, "and no swing is left to come")
	# GIVE_BACK (2) blows given back this fight: a third swing cut short is spent.
	assert_eq(Squad3D.GIVE_BACK, 2)
	b.swing = true
	m.state = "attack"
	sq.struck(m)
	m.state = "idle"
	assert_eq(int(b.blows), left + 1, "no more than GIVE_BACK blows given back a fight")
	assert_false(b.swing, "the swing cut short is over")
	# A new fight gives him his GIVE_BACK again.
	sq.attack(r.foes[2])
	assert_eq(int(b.given), 0, "a new fight, none given back yet")
	_run(r, 90.0)
	assert_eq(sq.mode, "idle", "the fight ends")
	_free_squad(r)


func _free_sides(host, a, b) -> void:
	for m in host.units:
		m.free()
	a._men.clear()
	b._men.clear()
	host.squad = null


## Six stand-in footmen of `side` in two ranks at `at` facing `yaw`.
func _side_squad(host, side: String, at: Vector3, yaw: float):
	var men := []
	var sq = Squad3D.new()
	for i in 6:
		var m := FakeMan.new()
		m.host = host
		m.set_meta("side", side)
		m.set_meta("squad", sq)
		men.append(m)
	sq.setup(men, FakeField.new(), host, at, yaw)
	sq.place(at, yaw)
	return sq


## n stand-in men of squad kind `id` in its drill facing east, 8 m from a
## line of `foes` dummies a file apart.
func _kind_rig(id: String, n: int, foes: int) -> Dictionary:
	var host := FakeHost.new()
	var men := []
	for i in n:
		var m := FakeMan.new()
		m.host = host
		men.append(m)
	for k in foes:
		var f := Node3D.new()
		f.position = Vector3(20, 0, 20 + (k - (foes - 1) * 0.5) * Squad3D.FILE)
		host.dummies.append(f)
	var sq = Squad3D.new()
	host.squad = sq
	sq.setup(men, FakeField.new(), host, Vector3(12, 0, 20), PI / 2, Squad3D.drill_for(id))
	sq.place(Vector3(12, 0, 20), PI / 2)
	return {"squad": sq, "host": host, "foes": host.dummies, "blows": host.blows}

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


## The fight until `done` holds, for at most `seconds`.
func _run_until(r: Dictionary, done: Callable, seconds: float) -> void:
	var dt := 1.0 / 30.0
	var end: float = r.host.now + seconds
	while r.host.now < end and not done.call():
		r.host.now += dt
		for m in r.squad.members:
			m.tick(dt)
		r.squad.tick(dt)


func _assert_staggered(blows: Array, least: float = Squad3D.GAP.x) -> void:
	for i in range(1, blows.size()):
		var gap: float = blows[i].t - blows[i - 1].t
		assert_true(gap >= least - 0.04, "blows %d and %d %.2f s apart" % [i - 1, i, gap])


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
		var sq = get_meta("squad") if has_meta("squad") else host.squad
		var b: Dictionary = sq._men[self]
		host.blows.append({"man": self, "t": host.now, "role": b.role, "slot": b.slot, "target": t, "pos": position})

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

	## A dummy, or a man of the other side (his "side" meta).
	func _hostile(a, b) -> bool:
		return b in dummies or (a.has_meta("side") and b.has_meta("side") and a.get_meta("side") != b.get_meta("side"))

	func _squad_of(n):
		return n.get_meta("squad") if n.has_meta("squad") else null

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
