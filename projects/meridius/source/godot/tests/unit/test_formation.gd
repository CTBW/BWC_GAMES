## Squad formations and the soldiers' bodies (formation.gd, squad_view.gd).
## Ports of the 'formations' and 'squad view' cases of the original's
## tests/squad.test.ts, plus golden parity against the original's
## formation.ts / squadView.ts (tools/parity/battleview_fixtures.ts ->
## tests/fixtures/battle_view/formation.json).
extends "res://tests/test_case.gd"

const Formation = preload("res://scripts/render/formation.gd")
const SquadView = preload("res://scripts/render/squad_view.gd")
const SoldierAnim = preload("res://scripts/render/soldier_anim.gd")
const JS = preload("res://scripts/core/js.gd")

var golden: Dictionary


func before_all() -> void:
	var f := FileAccess.open("res://tests/fixtures/battle_view/formation.json", FileAccess.READ)
	golden = JSON.parse_string(f.get_as_text())


func _inside(x: float, y: float) -> bool:
	return absf(x) / 64.0 + absf(y) / 32.0 < 0.95


func _unit(i: int) -> Dictionary:
	return JS.normalize(golden.members[i].unit)


func _pts(arr: Array) -> Array:
	var out: Array = []
	for p in arr:
		out.append({"x": float(p.x), "y": float(p.y)})
	return out


func test_keeps_every_soldier_inside_the_tile_for_every_strength_and_facing() -> void:
	for st in [[6, ""], [3, ""], [9, "goblin_rabble"], [4, "wolf_rider"], [4, "goblin_horn"]]:
		var size: int = st[0]
		for n in range(1, size + 1):
			for f in 4:
				for tight in [0.84, 1.0]:
					var slots := Formation.formation_slots(n, size, f, tight, st[1])
					assert_eq(slots.size(), n, "count %s/%d f%d" % [st, n, f])
					for s in slots:
						assert_true(_inside(s.x, s.y), "inside %s n%d f%d %s" % [st, n, f, s])


func test_rabble_stands_nine_to_a_tile_in_three_ranks_of_three() -> void:
	var nine := Formation.formation_slots(9, 9, 1, 1.0, "goblin_rabble")
	var ranks := {}
	for s in nine:
		var y := JS.rnd(s.y)
		ranks[y] = ranks.get(y, 0) + 1
	assert_eq(ranks.size(), 3)
	for y in ranks:
		assert_eq(ranks[y], 3)


func test_six_stand_in_two_ranks_of_three_trolls_in_a_triangle() -> void:
	var six := Formation.formation_slots(6, 6, 1)
	var ranks := {}
	for s in six:
		var y := JS.rnd(s.y)
		ranks[y] = ranks.get(y, 0) + 1
	assert_eq(ranks.size(), 2)
	for y in ranks:
		assert_eq(ranks[y], 3)
	var tri := Formation.formation_slots(3, 3, 1)
	var front := tri.filter(func(s): return s.y > 0)
	var back := tri.filter(func(s): return s.y < 0)
	assert_eq(front.size(), 2)
	assert_eq(back.size(), 1)
	assert_true(absf(back[0].x) < absf(front[0].x), "the troll behind stands between the two in front")


func test_closes_up_around_the_centre_as_soldiers_fall() -> void:
	for n in range(1, 7):
		var slots := Formation.formation_slots(n, 6, 1)
		var cx := 0.0
		for s in slots:
			cx += s.x
		cx /= n
		assert_true(absf(cx) < 6, "centred %d" % n)
		for i in n:
			for j in range(i + 1, n):
				assert_true(JS.hypot(slots[i].x - slots[j].x, (slots[i].y - slots[j].y) * 2) > 14, "spacing %d (%d,%d)" % [n, i, j])


func test_assigns_slots_with_the_least_movement_and_keeps_the_champion_front_centre() -> void:
	var from := Formation.formation_slots(6, 6, 1)
	var to := Formation.formation_slots(5, 6, 1)
	var pick := Formation.assign_slots(from.slice(0, 5), to)
	var uniq := {}
	for p in pick:
		uniq[p] = true
	assert_eq(uniq.size(), 5)
	var champ := Formation.assign_slots(from, Formation.formation_slots(6, 6, 1), 4)
	assert_eq(champ[4], 1)


func test_casualties_are_the_soldiers_nearest_the_blow_champion_last() -> void:
	var slots := Formation.formation_slots(6, 6, 1)
	var all := [0, 1, 2, 3, 4, 5]
	var dead := Formation.pick_casualties(slots, all, 2, {"x": -1.0, "y": 0.0})
	# A blow from the left takes the left file, front and rear.
	for d in dead:
		assert_true(slots[d].x < -20, "left file %d" % d)
	assert_false(Formation.pick_casualties(slots, all, 5, {"x": -1.0, "y": 0.0}, 2).has(2), "the protected soldier is spared")


func test_soldiers_fall_survivors_reform_nobody_lost_or_doubled() -> void:
	var u := _unit(0) # footmen(7)
	var members := SquadView.make_members(u)
	assert_eq(SquadView.standing(members).size(), 6)
	var corpses: Array = []
	var fallen := SquadView.kill_members(members, 2, {"x": -1.0, "y": 0.0}, -1)
	assert_eq(fallen.size(), 2)
	SquadView.reform(members, u.size, u.facing, {"dur": 0.3})
	for i in 60:
		SquadView.step_members(members, 1.0 / 30, func(m): corpses.append(m.id))
	corpses.sort()
	var fallen_ids := fallen.map(func(m): return m.id)
	fallen_ids.sort()
	assert_eq(corpses, fallen_ids)
	var live := SquadView.standing(members)
	assert_eq(live.size(), 4)
	var want := Formation.formation_slots(4, 6, u.facing).map(func(s): return "%s,%s" % [JS.to_fixed(s.x, 1), JS.to_fixed(s.y, 1)])
	want.sort()
	var got := live.map(func(m): return "%s,%s" % [JS.to_fixed(m.x, 1), JS.to_fixed(m.y, 1)])
	got.sort()
	assert_eq(got, want)


func test_the_warlord_keeps_the_front_centre_and_falls_last() -> void:
	var w := _unit(2) # makeEnemy('orc_warlord', 1, 'w', new Rng(2))
	var members := SquadView.make_members(w)
	var champ := SquadView.champion_of(w)
	assert_eq(champ, 0)
	assert_eq(members[0].type, "orc_warlord")
	for m in members.slice(1):
		assert_eq(m.type, "orc_warrior")
	var front: Dictionary = Formation.formation_slots(6, 6, w.facing)[1]
	assert_eq([members[0].to_x, members[0].to_y], [front.x, front.y])
	SquadView.kill_members(members, 5, {"x": 1.0, "y": 1.0}, champ)
	assert_eq(SquadView.standing(members).map(func(m): return m.id), [0])


func test_member_scale_and_height() -> void:
	# Trolls were doubled in size for the pixel-art figures (MIGRATION.md).
	assert_eq(SquadView.member_height("troll"), 132.0)
	assert_eq(SquadView.member_height("goblin_rabble"), 34.0)
	assert_eq(SquadView.member_height("footman"), 49.0)
	assert_eq(SquadView.member_scale({"typeId": "troll", "size": 3}), SquadView.BIG_MEMBER_SCALE)
	assert_eq(SquadView.member_scale({"typeId": "footman", "size": 6}), SquadView.MEMBER_SCALE)
	assert_eq(SquadView.member_scale({"typeId": "wolf_rider", "size": 4}), 0.5)


# ---------------------------------------------------------------- golden parity

func test_formation_slots_match_the_original() -> void:
	for g in golden.slots:
		var got := Formation.formation_slots(int(g.n), int(g.size), int(g.f), float(g.tight), g.type)
		var label := "slots n%d size%d f%d tight%s %s" % [g.n, g.size, g.f, g.tight, g.type]
		if not assert_eq(got.size(), g.slots.size(), label):
			continue
		for i in got.size():
			assert_eq(got[i].x, g.slots[i].x, label + " x%d" % i)
			assert_eq(got[i].y, g.slots[i].y, label + " y%d" % i)


func test_assign_slots_matches_the_original() -> void:
	for g in golden.assign:
		var got := Formation.assign_slots(_pts(g.positions), _pts(g.slots), int(g.pinned))
		assert_eq(got, g.out, "assign %s" % JSON.stringify(g.positions).substr(0, 60))


func test_pick_casualties_matches_the_original() -> void:
	for g in golden.casualties:
		var standing: Array = JS.normalize(g.standing)
		var got := Formation.pick_casualties(_pts(g.positions), standing, int(g.k), g.from, int(g.protected))
		assert_eq(got, g.out, "casualties k%d from %s" % [g.k, g.from])


func test_make_members_matches_the_original() -> void:
	for g in golden.members:
		var u: Dictionary = JS.normalize(g.unit)
		# Trolls are twice as big and stand wider since 22 Oct 2026 (MIGRATION.md); see test_trolls_doubled.
		if u.typeId == "troll":
			continue
		var ms := SquadView.make_members(u)
		assert_eq(ms.size(), g.members.size(), u.uid)
		for i in ms.size():
			var m = ms[i]
			var w: Dictionary = g.members[i]
			var label := "%s #%d" % [u.uid, i]
			assert_eq(m.id, w.id, label + " id")
			assert_eq(m.alive, w.alive, label + " alive")
			assert_almost(m.x, w.x, 1e-9, label + " x")
			assert_almost(m.y, w.y, 1e-9, label + " y")
			assert_almost(m.to_x, w.toX, 1e-9, label + " toX")
			assert_almost(m.to_y, w.toY, 1e-9, label + " toY")
			assert_almost(m.phase, w.phase, 1e-9, label + " phase")
			assert_eq(m.type, w.type, label + " type")
			assert_eq(m.variant, w.variant, label + " variant")
			assert_eq(m.fall_flip, w.fallFlip, label + " fallFlip")


func test_fall_and_reform_sequence_matches_the_original() -> void:
	var s: Dictionary = golden.sequence
	var u: Dictionary = JS.normalize(s.unit)
	var ms := SquadView.make_members(u)
	# The golden is the original's half-second fall. Footmen now fall frame by
	# frame over SoldierAnim.DEATH (MIGRATION.md, "Footman animation"); every
	# other figure keeps 0.5 s, which the rest of the sequence checks.
	assert_almost(ms[0].death_dur, SoldierAnim.DEATH, 1e-9, "footmen fall frame by frame")
	for m in ms:
		m.death_dur = 0.5
	var fallen := SquadView.kill_members(ms, 2, {"x": -1.0, "y": 0.0}, -1)
	assert_eq(fallen.map(func(m): return m.id), JS.normalize(s.fallen))
	SquadView.reform(ms, u.size, u.facing, {"dur": 0.3, "stagger": 0.04})
	var corpses: Array = []
	var fi := 0
	for i in 60:
		SquadView.step_members(ms, 1.0 / 30, func(m): corpses.append(m.id))
		if i % 6 == 0:
			var want: Array = s.frames[fi]
			fi += 1
			for k in ms.size():
				var m = ms[k]
				var label := "frame %d member %d" % [i, k]
				assert_almost(m.x, want[k][0], 1e-9, label + " x")
				assert_almost(m.y, want[k][1], 1e-9, label + " y")
				assert_almost(m.death_t, want[k][2], 1e-9, label + " deathT")
				assert_almost(m.flash, want[k][3], 1e-9, label + " flash")
				assert_almost(m.t, want[k][4], 1e-9, label + " t")
	assert_eq(corpses, JS.normalize(s.corpses))
	assert_eq(SquadView.standing(ms).size(), int(s.standing))


# ---------------------------------------------------------------- war machines and casters

func _engines() -> Dictionary:
	var f := FileAccess.open("res://tests/fixtures/battle_view/formation_engines.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


func test_engine_and_caster_slots_match_the_original() -> void:
	# tools/parity/battleview_engines.ts: crews around their engines, casters in the
	# ordinary triangle, trolls in the wide one.
	var g := _engines()
	for c in g.slots:
		if c.type == "troll":
			continue
		var got := Formation.formation_slots(int(c.n), int(c.size), int(c.f), float(c.tight), c.type)
		var label := "%s n%d f%d t%s" % [c.type, c.n, c.f, c.tight]
		if not assert_eq(got.size(), c.slots.size(), label + " count"):
			continue
		for i in got.size():
			assert_almost(got[i].x, c.slots[i].x, 1e-9, label + " x%d" % i)
			assert_almost(got[i].y, c.slots[i].y, 1e-9, label + " y%d" % i)
	for e in g.engine:
		var o := Formation.engine_offset(int(e.f))
		assert_almost(o.x, e.offset.x, 1e-9, "engine offset x f%d" % e.f)
		assert_almost(o.y, e.offset.y, 1e-9, "engine offset y f%d" % e.f)


func test_crews_scales_heights_and_members_match_the_original() -> void:
	var g := _engines()
	for c in g.members:
		var u: Dictionary = JS.normalize(c.unit)
		if u.typeId == "troll":
			continue
		assert_almost(SquadView.member_scale(u), c.scale, 1e-12, u.typeId + " scale")
		assert_almost(SquadView.member_height(u.typeId), c.height, 1e-12, u.typeId + " height")
		var ms := SquadView.make_members(u)
		assert_eq(ms.size(), c.members.size(), u.typeId + " members")
		for i in mini(ms.size(), c.members.size()):
			var w: Dictionary = c.members[i]
			var label := "%s #%d" % [u.typeId, i]
			assert_eq(ms[i].type, w.type, label + " type")
			assert_eq(ms[i].alive, w.alive, label + " alive")
			assert_almost(ms[i].x, w.x, 1e-9, label + " x")
			assert_almost(ms[i].y, w.y, 1e-9, label + " y")
			assert_eq(ms[i].variant, w.variant, label + " variant")


func test_crews_stand_on_their_tile_and_a_wagon_is_shoved_from_behind() -> void:
	for type in ["ballista", "mangonel", "rock_lobber", "war_wagon"]:
		for f in 4:
			var fwd := Formation.ground_offset(f, 1, 0)
			var eo := Formation.engine_offset(f)
			assert_true(eo.x * fwd.x + eo.y * fwd.y > 0, "%s f%d: the engine stands forward of the centre" % [type, f])
			for n in range(1, 4):
				var slots := Formation.formation_slots(n, 3, f, 1.0, type)
				assert_eq(slots.size(), n, "%s n%d f%d" % [type, n, f])
				for s in slots:
					assert_true(_inside(s.x, s.y), "%s n%d f%d inside %s" % [type, n, f, s])
					if type == "war_wagon":
						assert_true(s.x * fwd.x + s.y * fwd.y < 0, "the wagon's crew push from behind (f%d)" % f)
	# Three mages stand like three men, not like trolls.
	var mages := Formation.formation_slots(3, 3, 1, 1.0, "battle_mage")
	var trolls := Formation.formation_slots(3, 3, 1, 1.0, "troll")
	assert_ne(mages, trolls, "casters do not take the trolls' wide triangle")
	assert_almost(absf(mages[0].x - mages[1].x), Formation.COL, 1e-9, "front pair a column apart")
	var crew := SquadView.make_members({"uid": "c1", "typeId": "rock_lobber", "size": 3, "alive": 3, "facing": 1, "variant": 0})
	for m in crew:
		assert_eq(m.type, "goblin_rabble", "a lobber's crew are goblins")


## Trolls doubled (Godot only): their slots are the original's wide triangle
## spread by TROLL_SPREAD sideways, still inside the tile; ranks unchanged.
func test_trolls_doubled() -> void:
	for f in 4:
		for t in [1.0, 0.84]:
			var old := Formation.formation_slots(3, 3, f, t, "")
			var got := Formation.formation_slots(3, 3, f, t, "troll")
			assert_eq(got.size(), 3)
			for i in 3:
				assert_almost(got[i].y, old[i].y, 1e-9, "troll f%d rank %d" % [f, i])
				assert_true(absf(got[i].x) / 64.0 + absf(got[i].y) / 32.0 < 0.92, "troll f%d slot %d inside the tile" % [f, i])
			assert_true(absf(got[0].x - got[1].x) > absf(old[0].x - old[1].x), "trolls stand wider")
	assert_eq(SquadView.member_scale({"typeId": "troll", "size": 3}), SquadView.BIG_MEMBER_SCALE)
