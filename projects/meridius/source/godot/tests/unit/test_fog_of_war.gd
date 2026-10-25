extends "res://tests/unit/test_battle_base.gd"

const Soldier = preload("res://scripts/meta/soldier.gd")
const Sight = preload("res://scripts/rules/visibility.gd")
const Fields = preload("res://scripts/rules/terrain_test_fields.gd")
const Lab = preload("res://scripts/render/terrain_lab.gd")

func fixture() -> Dictionary:
	var map: Dictionary = Fields.make(0).map
	for t in map.tiles:
		t.terrain = "grass"
		t.h = 0
		t.surface_h = 0.0
		t.erase("prop")
	var a := Soldier.make_enemy("crossbowman", 1, "scout", Rng.new(12))
	a.faction = "player"
	a.x = 5
	a.y = 10
	var e := Soldier.make_enemy("goblin_spear", 1, "sentry", Rng.new(13))
	e.x = 18
	e.y = 10
	return {"seed": 12, "map": map, "units": [a, e], "fogOfWar": true}

func test_sight_is_shared_symmetric_and_remembers_ground_not_enemies() -> void:
	var b = Battle.new(fixture())
	var a: Dictionary = b.units[0]
	var e: Dictionary = b.units[1]
	assert_false(b.visible_to("player", e))
	assert_false(b.visible_to("enemy", a))
	assert_false(b.preview(a, e).legal)
	assert_eq(b.known_unit_at("player", e.x, e.y), null)
	a.x = 12
	assert_true(b.visible_to("player", e))
	assert_true(b.visible_to("enemy", a))
	a.x = 5
	assert_false(b.visible_to("player", e))
	assert_true(b.explored.player.has(Grid.key(18, 10)))
	assert_false(b.visible_tiles("player").has(Grid.key(18, 10)))
	var ally := a.duplicate(true)
	ally.uid = "ally"
	ally.x = 16
	b.units.append(ally)
	assert_true(b.visible_to("player", e), "allied sight is shared")

func test_woodland_traversal_concealment_and_solid_obstacles() -> void:
	var setup := fixture()
	var t: Dictionary = Grid.tile_at(setup.map, 8, 10)
	t.terrain = "forest"
	t.prop = "tree_oak"
	setup.units[1].x = 8
	var b = Battle.new(setup)
	assert_true(Grid.tile_passable(b.map, 8, 10))
	assert_false(b.visible_to("player", b.units[1]), "occupants concealed beyond two tiles")
	b.units[0].x = 6
	assert_true(b.visible_to("player", b.units[1]))
	t.prop = "rock_large"
	assert_false(Grid.tile_passable(b.map, 8, 10))
	t.prop = "tree_oak"
	b.units[1].x = 20
	b.phase = "player"
	assert_true(b.move("scout", 8, 10), "walk onto tree tile")
	assert_eq(Vector2i(b.units[0].x, b.units[0].y), Vector2i(8, 10))
	assert_false(b.can_redo("scout").ok, "scouting is committed")

func test_combat_reveal_expires_and_ai_scouts_without_hidden_targets() -> void:
	var b = Battle.new(fixture())
	b.phase = "enemy"
	var e: Dictionary = b.units[1]
	var start := Vector2i(e.x, e.y)
	Ai.act_unit(b, e)
	assert_ne(Vector2i(e.x, e.y), start, "AI explores when no enemy is visible")
	assert_false(b.events.any(func(event): return event.t == "attack"), "no attack against an unseen enemy")
	b.reveal_combat(e)
	assert_true(b.visible_to("player", e))
	b._start_turn("enemy")
	# Put the sentry beyond sight after expiry to check the reveal itself.
	e.x = 22
	assert_false(b.visible_to("player", e))

func test_playback_hides_enemy_body_hover_and_keeps_canopy_solid_over_unseen_units() -> void:
	var lab = Lab.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(lab)
	lab.prepare(3)
	lab.auto_step = false
	var e: Dictionary = lab.b.unit("woodland-sentry")
	assert_false(lab.unit_visible(e))
	var p = lab.Iso.iso(e.x, e.y, lab._tile_h(e.x, e.y))
	var sp = lab.cam.to_screen(p, Vector2(lab._w, lab._h))
	assert_eq(lab.resolve_pointer(sp.x, sp.y).unit, null)
	# Future rule positions must not reveal anything before movement playback.
	lab.b.units[0].x = 7
	lab.b.units[0].y = 7
	lab.fog.refresh(1.0)
	assert_false(lab.unit_visible(e), "fog follows presented positions")
	var uv = lab.views["terrain-0"]
	uv.x = 7
	uv.y = 7
	lab.fog.refresh(1.0)
	assert_true(lab.unit_visible(e), "approaching reveals woodland sentry")
	uv.x = 5
	uv.y = 10
	lab.fog.refresh(1.0)
	assert_false(lab.unit_visible(e))
	assert_eq(lab.fog.tile_state(7, 6), 1, "explored woodland stays remembered")
	lab.get_parent().remove_child(lab)
	lab.free()
