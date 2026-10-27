extends "res://tests/test_case.gd"

const Fields = preload("res://scripts/rules/terrain_test_fields.gd")
const Relief = preload("res://scripts/render/relief.gd")
const Lab = preload("res://scripts/render/terrain_lab.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const Iso = preload("res://scripts/render/iso.gd")


func test_surface_projection_round_trip_and_shader_height_data() -> void:
	for which in 3:
		var m: Dictionary = Fields.make(which).map
		var r = Relief.new(m.w, m.h, m.border, m.tiles + m.outerGround, m.seed)
		var im: Image = r.height_image()
		for t in m.tiles:
			assert_almost(r.surface(t.x, t.y), t.surface_h, 0.00001)
			assert_almost(im.get_pixel(t.x + m.border, t.y + m.border).r, t.surface_h, 0.00001)
			# Off-centre points catch picking based on rounded tactical heights.
			var p := Vector2(t.x + 0.23, t.y - 0.31)
			var wp := Iso.iso(p.x, p.y, r.surface(p.x, p.y))
			assert_true(r.unproject(wp).distance_to(p) < 0.0001, "surface picking must round-trip")
			# No folded screen projection on these fixtures: bisection is valid.
			var ahead := p + Vector2(0.02, 0.02)
			assert_true(Iso.iso_y(ahead.x, ahead.y, r.surface(ahead.x, ahead.y)) > wp.y)


func test_paths_cross_each_field_and_ford_without_climbing_illegal_steps() -> void:
	for which in 3:
		var setup: Dictionary = Fields.make(which)
		var m: Dictionary = setup.map
		var first: Dictionary = setup.units[0]
		var todo: Array = [{"x": first.x, "y": first.y}]
		var seen := {Grid.key(first.x, first.y): true}
		var i := 0
		while i < todo.size():
			var a: Dictionary = todo[i]
			i += 1
			for b in Grid.neighbors(m, a):
				var key := Grid.key(b.x, b.y)
				if not seen.has(key) and Grid.tile_passable(m, b.x, b.y) and Grid.can_step(m, a, b):
					seen[key] = true
					todo.append(b)
		assert_true(seen.has(Grid.key(20, 12)), "east exit reachable on field %d" % which)
		assert_true(todo.size() > 250, "useful connected patrol area")
		if which == 1:
			assert_false(Grid.tile_passable(m, 14, 3), "deep water blocks movement")
			assert_eq(Grid.tile_at(m, 13, 12).terrain, "shallows")
			assert_true(seen.has(Grid.key(13, 12)), "ford reachable")


func test_real_pointer_move_patrol_height_and_repeat_movement() -> void:
	var lab = Lab.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(lab)
	lab.prepare(0)
	lab.auto_step = false
	var u: Dictionary = lab.b.unit("terrain-0")
	for dest in [Vector2i(6, 13), Vector2i(6, 11)]:
		var p := Iso.iso(dest.x, dest.y, lab._tile_h(dest.x, dest.y))
		var sp: Vector2 = lab.cam.world_to_screen(p.x, p.y, lab._w, lab._h)
		assert_eq(lab._tile_at_screen(sp.x, sp.y), {"x": dest.x, "y": dest.y})
		lab.walk_at(sp)
		for i in 240:
			lab.advance(1.0 / 60.0)
			var uv = lab.views[u.uid]
			assert_almost(uv.h, lab.terrain_surface.surface(uv.x, uv.y), 0.00001)
			for member in uv.members:
				var pos: Vector2 = lab._member_pos(uv, member)
				var xy: Vector2 = lab.terrain_surface.unproject(pos)
				assert_true(is_finite(xy.x) and is_finite(xy.y))
		assert_false(lab.busy())
		assert_eq(Vector2i(u.x, u.y), dest, "pointer command follows real path rules")
		assert_false(u.hasMoved, "patrol can keep inspecting after arrival")
		assert_eq(lab.b.phase, "player", "no empty-enemy victory in the test lab")
	lab.get_parent().remove_child(lab)
	lab.free()
