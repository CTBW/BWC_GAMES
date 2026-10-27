extends "res://tests/test_case.gd"

const Lab = preload("res://scripts/render/unit_playground.gd")
const DB = preload("res://scripts/data/db.gd")
var lab


func before_each() -> void:
	lab = Lab.new()
	lab.prepare()
	(Engine.get_main_loop() as SceneTree).root.add_child(lab)
	lab.looping = false


func after_each() -> void:
	lab.get_parent().remove_child(lab)
	lab.free()


func _step(seconds: float) -> void:
	for i in ceili(seconds * 60):
		lab.tick(1.0 / 60.0)


func test_roster_clips_and_invulnerable_dummy() -> void:
	for type_id in DB.UNIT_TYPES:
		lab.choose_unit(type_id)
		for clip in Lab.CLIPS:
			lab.choose_clip(clip)
			_step(4.0)
			assert_false(lab.busy(), type_id + " " + clip + " must finish")
			assert_eq(lab.views[Lab.TARGET].alive, 1, "dummy survives " + type_id)
			assert_eq(lab.views[Lab.TARGET].hp, lab.b.unit(Lab.TARGET).maxHp)
			if clip == "Fall":
				assert_eq(lab.views[Lab.SUBJECT].alive, 0)
			else:
				assert_true(lab.views[Lab.SUBJECT].alive > 0)


func test_approach_from_every_facing_and_repeat_attacks() -> void:
	for type_id in ["footman", "crossbowman", "battle_mage", "ballista"]:
		lab.choose_unit(type_id)
		for facing in 4:
			lab.set_facing(facing)
			lab.choose_clip("Attack")
			lab.looping = true
			_step(8.0)
			var u: Dictionary = lab.b.unit(Lab.SUBJECT)
			var distance := 3 if u.has("shot") else 1
			assert_eq(Vector2i(u.x, u.y), Lab.DUMMY_AT - Vector2i(lab.Grid.DX[facing], lab.Grid.DY[facing]) * distance)
			assert_eq(lab.views[Lab.TARGET].alive, 1)
			assert_eq(lab.corpses.size(), 0)


func test_pause_exact_frame_step_speed_and_cancel() -> void:
	lab.choose_clip("March")
	_step(0.2)
	lab.playing = false
	var before: float = lab.time
	var x: float = lab.views[Lab.SUBJECT].x
	var y: float = lab.views[Lab.SUBJECT].y
	_step(0.5)
	assert_eq(lab.time, before)
	assert_eq(lab.views[Lab.SUBJECT].x, x)
	assert_eq(lab.views[Lab.SUBJECT].y, y)
	lab.tick(0.0, true)
	assert_almost(lab.time - before, 1.0 / 60.0)
	lab.playing = true
	lab.playback_rate = 0.25
	before = lab.time
	lab.tick(1.0 / 60.0)
	assert_almost(lab.time - before, 1.0 / 240.0)
	lab.choose_unit("troll")
	assert_false(lab.busy())
	assert_eq(lab.views[Lab.SUBJECT].members[0].type, "troll")
	assert_eq(lab.fx.projectiles.size(), 0)
	assert_eq(lab.corpses.size(), 0)


func test_walk_avoids_occupied_tiles_and_comparison_is_independent() -> void:
	lab.comparison = "troll"
	lab.reset_subject()
	var route: Array = lab.practice_path(Vector2i(8, 10), Vector2i(8, 12))
	assert_true(route.size() > 3, "detour around dummy")
	for p in route:
		assert_ne(Vector2i(p.x, p.y), Lab.DUMMY_AT)
	lab.march_to(Vector2i(5, 7))
	_step(3.0)
	assert_almost(lab.views[Lab.SUBJECT].x, 5)
	assert_almost(lab.views[Lab.SUBJECT].y, 7)
	assert_almost(lab.views[Lab.COMPARISON].x, 11)
	assert_almost(lab.views[Lab.COMPARISON].y, 6)
	lab.march_to(Lab.DUMMY_AT)
	assert_false(lab.busy())
	lab.solo = true
	lab.reset_subject()
	assert_eq(lab.views[Lab.SUBJECT].members.size(), 1)
	lab.choose_unit("ballista")
	assert_true(lab.views[Lab.SUBJECT].members.size() > 1, "engines retain their crews")
