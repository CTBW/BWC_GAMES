## The forest ring's near side (scripts/render/battle_draw.gd draw_outer,
## outer_props, _ring_fades): its trees go to the sorted pass, so they stand in
## front of the field's edge rows, and fade over the squads, the ghost and the
## tile under the pointer behind them, all of them over one squad together no
## more than one field prop does.
extends "res://tests/test_case.gd"

const JS = preload("res://scripts/core/js.gd")
const Iso = preload("res://scripts/render/iso.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const ViewScene = preload("res://scenes/battle/battle_view.tscn")


func _fixture(name: String) -> Dictionary:
	var f := FileAccess.open("res://tests/fixtures/battle_view/setups/%s.json" % name, FileAccess.READ)
	return JS.normalize(JSON.parse_string(f.get_as_text()))


func _view(b):
	var v = ViewScene.instantiate()
	v.threaded_rules = false
	v.setup(b)
	(Engine.get_main_loop() as SceneTree).root.add_child(v)
	return v


func _free(v) -> void:
	v.get_parent().remove_child(v)
	v.free()


## The near side as draw_outer leaves it for the sorted pass.
func _fill_ring(v) -> Array:
	var ring: Array = v._draw._ring
	ring.clear()
	for pr in v._draw.outer_props():
		if pr.near:
			pr["ri"] = ring.size()
			ring.append(pr)
	return ring


## The squads as draw_sorted bins them: column -> [x, y, d, view].
func _boxes(v) -> Dictionary:
	var boxes := {}
	for uv in v.views.values():
		if not v.squad_visible(uv) or uv.reserve:
			continue
		var p: Vector2 = v._view_pos(uv)
		var col := floori(p.x / 128.0)
		if not boxes.has(col):
			boxes[col] = []
		boxes[col].append([p.x, p.y, uv.x + uv.y, uv])
	return boxes


func test_only_the_near_side_of_the_ring_is_sorted() -> void:
	for name in ["scouts_clearing", "river", "camp"]:
		var b = Battle.new(_fixture(name).setup)
		var v = _view(b)
		var props: Array = v._draw.outer_props()
		var near := 0
		var far := 0
		for pr in props:
			var beyond: bool = pr.x >= b.map.w or pr.y >= b.map.h
			assert_eq(pr.near, beyond, "%s: %d,%d is on the near side only beyond the field's near edges" % [name, pr.x, pr.y])
			assert_true(pr.sc >= 0.9 and pr.sc <= 1.25, "%s: ring prop scale %.2f" % [name, pr.sc])
			assert_true(is_equal_approx(pr.k, pr.s.scale * pr.sc), "%s: the box follows the scale" % name)
			if pr.near:
				near += 1
			else:
				far += 1
		assert_true(near > 20 and far > 20, "%s: both sides have trees (%d near, %d far)" % [name, near, far])
		_free(v)


func test_near_trees_fade_over_squads_no_more_than_one_prop_veils() -> void:
	var faded_any := false
	for name in ["scouts_clearing", "river", "camp"]:
		var b = Battle.new(_fixture(name).setup)
		var v = _view(b)
		var ring := _fill_ring(v)
		v.ui.hover = v._empty_hover()
		var fades: Dictionary = v._draw._ring_fades(_boxes(v), null)
		# Every faded tree covers a soldier; together they leave each squad
		# veiled by at most 0.28.
		var veil := {}
		for i in fades:
			var a: float = fades[i]
			assert_true(a > 0.0 and a <= 0.28 + 1e-6, "%s: ring tree %d fades to %.3f" % [name, i, a])
			var pr: Dictionary = ring[i]
			var over := false
			for uv in v.views.values():
				if not v.squad_visible(uv) or uv.reserve or uv.x + uv.y > pr.d + 0.2:
					continue
				for m in uv.members:
					if m.alive and v._draw._covers_body(pr, v._member_pos(uv, m) - Vector2(0, uv.hop)):
						over = true
						veil[uv.uid] = veil.get(uv.uid, 1.0) * (1.0 - a)
						break
			assert_true(over, "%s: ring tree %d fades only over a soldier" % [name, i])
		for uid in veil:
			assert_true(1.0 - veil[uid] <= 0.28 + 1e-4, "%s: squad %s veiled %.3f" % [name, uid, 1.0 - veil[uid]])
		faded_any = faded_any or not fades.is_empty()
		_free(v)
	assert_true(faded_any, "squads at the near edge fade the trees in front of them")


func test_near_trees_fade_over_the_tile_under_the_pointer() -> void:
	var b = Battle.new(_fixture("scouts_clearing").setup)
	var v = _view(b)
	var ring := _fill_ring(v)
	# A field tile on the near edge row hidden by a tree of the ring.
	var hit := -1
	var tile = null
	for t in b.map.tiles:
		if t.y != b.map.h - 1 and t.x != b.map.w - 1:
			continue
		var at := Vector2(Iso.iso_x(t.x, t.y), Iso.iso_y(t.x, t.y, v._tile_h(t.x, t.y)))
		for pr in ring:
			if pr.d > t.x + t.y and v._draw._covers(pr, at):
				hit = pr.ri
				tile = t
				break
		if tile != null:
			break
	assert_true(tile != null, "a ring tree hides an edge tile")
	v.ui.hover = v._empty_hover()
	assert_false(v._draw._ring_fades({}, null).has(hit), "no fade without the pointer")
	v.ui.hover["tile"] = {"x": tile.x, "y": tile.y}
	var fades: Dictionary = v._draw._ring_fades({}, null)
	assert_true(fades.has(hit) and fades[hit] <= 0.28 + 1e-6, "the tree over the hovered tile fades")
	_free(v)
