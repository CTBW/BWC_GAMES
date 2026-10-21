## The battle view (scripts/render/battle_view.gd) attached to real battles:
## deployment, begin, a player move and attack through the pointer, an enemy
## turn (resolved on a worker thread and inline), and full playback to the end
## with no errors or deadlock, including a last stand with waves and the relief.
## Battles come from the original's BattleSetups (tests/fixtures/battle_view/setups,
## tools/parity/battleview_fixtures.ts) and from setup.gd.
## Playback is stepped with view.advance(dt) (no frames in the headless runner).
extends "res://tests/test_case.gd"

const JS = preload("res://scripts/core/js.gd")
const Rng = preload("res://scripts/core/rng.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const Ai = preload("res://scripts/rules/ai.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const Iso = preload("res://scripts/render/iso.gd")
const ViewScene = preload("res://scenes/battle/battle_view.tscn")
const DT := 1.0 / 30.0

var _views: Array = []
var _ended: Array = []


func after_each() -> void:
	for v in _views:
		if is_instance_valid(v):
			v.get_parent().remove_child(v)
			v.free()
	_views.clear()


func _fixture(name: String) -> Dictionary:
	var f := FileAccess.open("res://tests/fixtures/battle_view/setups/%s.json" % name, FileAccess.READ)
	return JS.normalize(JSON.parse_string(f.get_as_text()))


func _view_for(setup: Dictionary, threaded := true):
	var b = Battle.new(setup)
	var v = ViewScene.instantiate()
	v.threaded_rules = threaded
	v.setup(b)
	(Engine.get_main_loop() as SceneTree).root.add_child(v)
	_views.append(v)
	_ended.clear()
	v.ended.connect(func(r): _ended.append(r))
	return v


## Step playback until the view is idle (or `max_s` seconds of game time pass).
func _idle(v, max_s := 120.0) -> bool:
	var t := 0.0
	while t < max_s:
		if v.rules_running():
			OS.delay_msec(2)
		v.advance(DT)
		t += DT
		if not v.busy() and not v.rules_running():
			# A few more frames for the end anim's signal and settling falls.
			for i in 3:
				v.advance(DT)
			if not v.busy():
				return true
	return false


func _screen_of(v, x: int, y: int) -> Vector2:
	var t = Grid.tile_at(v.b.map, x, y)
	var wx := Iso.iso_x(x, y)
	var wy := Iso.iso_y(x, y, t.h if t != null else 0)
	return v.cam.world_to_screen(wx, wy, v._w, v._h)


func test_view_builds_with_the_ui_state_and_squads() -> void:
	var v = _view_for(_fixture("trolls").setup)
	assert_eq(v.views.size(), v.b.units.size(), "one view per squad")
	for k in ["selected", "hover", "ability", "busy", "banner", "log", "showGrid", "danger", "version", "turn", "side"]:
		assert_true(v.ui.has(k), "ui." + k)
	assert_eq(v.ui.banner.text, "Deploy your company")
	assert_not_null(v.ui.selected, "first squad selected for deployment")
	for u in v.b.units:
		var uv = v.views[u.uid]
		assert_eq(uv.members.size(), u.size, "members of " + u.uid)
		assert_eq(uv.alive, u.alive)


func test_small_battle_begin_move_attack_end_turn_and_play_to_the_end() -> void:
	for threaded in [true, false]:
		var v = _view_for(_fixture("trolls").setup, threaded)
		var b = v.b
		var version: int = v.ui.version
		v.begin()
		assert_true(_idle(v), "begin plays out")
		assert_true(v.ui.version > version, "ui_changed while playing")
		assert_eq(v.b.phase, "player")
		assert_eq(v.ui.side, "player")
		assert_eq(v.ui.banner.text, "Your Turn")
		# A player move through the pointer: the selected squad to the reachable tile nearest the foe.
		v.select(v.b.active("player")[0].uid)
		var sel = v.selected_unit()
		var foes: Array = v.b.active("enemy")
		var reach: Dictionary = v.b.reachable(sel)
		var best = null
		for k in reach:
			var p := {"x": k % 1000, "y": floori(k / 1000.0)}
			var d := 1e9
			for f in foes:
				d = minf(d, Grid.manhattan(p, f))
			if best == null or d < best.d:
				best = {"p": p, "d": d}
		assert_not_null(best, "somewhere to go")
		var sp := _screen_of(v, best.p.x, best.p.y)
		v.pointer_move(sp)
		assert_not_null(v.ui.hover.dest, "the move is previewed")
		assert_not_null(v.ui.hover.facing, "with a facing")
		v.pointer_down(sp, 0)
		assert_true(sel.hasMoved, "the squad moved")
		assert_eq([sel.x, sel.y], [best.p.x, best.p.y])
		assert_true(v.busy(), "the march plays")
		assert_true(_idle(v), "the march finishes")
		var sv = v.views[sel.uid]
		assert_almost(sv.x, sel.x, 1e-9, "view on the tile")
		assert_eq(sv.facing, sel.facing, "view faces the way the rules say")
		# An attack: any squad that has a legal target now.
		var attacked := false
		for u in v.b.active("player"):
			if u.hasActed:
				continue
			var ts: Array = v.b.targets(u, u, null)
			if ts.is_empty():
				continue
			v.select(u.uid)
			var t: Dictionary = ts[0]
			var hp_before: int = t.hp
			var tp := _screen_of(v, t.x, t.y)
			tp.y -= 20
			v.pointer_move(tp)
			v.pointer_down(tp, 0)
			if u.hasActed:
				attacked = true
				assert_true(_idle(v), "the attack plays out")
				assert_eq(v.views[t.uid].hp, t.hp, "the bar shows the rules' hp after the blow")
				assert_eq(v.views[t.uid].alive, t.alive if t.status == "active" or t.status == "routing" else 0, "standing soldiers follow the rules")
				break
		if not attacked:
			# Nobody in reach yet: shoot or strike after the AI moves the company.
			v.run_rules(Ai.run_player_auto)
			assert_true(_idle(v), "the company's turn plays out")
		v.end_turn()
		assert_true(_idle(v), "the enemy turn plays out (threaded=%s)" % threaded)
		assert_true(v.b.phase == "player" or v.b.phase == "over", "back to the company or over")
		# The rest of the battle, both sides by the AI.
		var turns := 0
		while v.b.phase == "player" and turns < 40:
			v.run_rules(Ai.run_player_auto)
			assert_true(_idle(v), "player turn %d" % turns)
			if v.b.phase == "player":
				v.end_turn()
				assert_true(_idle(v), "enemy turn %d" % turns)
			turns += 1
		assert_eq(v.b.phase, "over", "the battle ends")
		assert_eq(_ended.size(), 1, "ended fired once")
		if _ended.size() > 0:
			assert_eq(_ended[0], v.b.result, "with the rules' result")
		# Every squad shows what the rules say.
		for u in v.b.units:
			var uv = v.views[u.uid]
			if u.status == "dead" or u.status == "downed":
				assert_eq(uv.alive, 0, u.uid + " fallen")
			elif u.status == "active":
				assert_eq(uv.alive, u.alive, u.uid + " standing")
		after_each()


func test_last_stand_with_waves_and_relief_plays_to_the_end() -> void:
	var fx := _fixture("last_stand")
	var setup: Dictionary = fx.setup
	# Shorten the stand so the relief comes quickly (as reliefshots.mjs does).
	setup.objective.turns = 2
	var v = _view_for(setup, true)
	assert_eq(v.b.map.get("scale"), "large")
	assert_true(v._host != null, "the host masses beyond the approach")
	assert_true(v.night_level > 0.9 if v.b.objective.get("dawn") else true, "a dawn battle opens at night")
	v.begin()
	assert_true(_idle(v, 300), "begin")
	var turns := 0
	var saw_relief := false
	var saw_wave := false
	var timings: Array = []
	while v.b.phase == "player" and turns < 20:
		v.run_rules(Ai.run_player_auto)
		assert_true(_idle(v, 300), "player turn")
		if v.b.phase != "player":
			break
		v.end_turn()
		var t := 0.0
		while (v.busy() or v.rules_running()) and t < 600:
			if v.rules_running():
				OS.delay_msec(2)
			v.advance(DT)
			t += DT
			if v.relief != null:
				saw_relief = true
			if v.staged().size() > 0 or v.ui.banner != null and String(v.ui.banner.text).contains("comes"):
				saw_wave = true
		timings.append(v.last_rules_ms)
		turns += 1
	assert_eq(v.b.phase, "over", "the stand ends")
	assert_eq(_ended.size(), 1, "ended fired")
	if v.b.result == "victory" and v.b.objective.get("dawn"):
		assert_true(saw_relief, "the relief rode in at dawn")
	print("    last stand: %d turns, enemy turns (ms): %s, result %s" % [turns, timings, v.b.result])


func test_reserve_waves_are_staged_and_spawn_onto_the_field() -> void:
	var v = _view_for(_fixture("last_stand").setup, false)
	var reserves := 0
	for u in v.b.units:
		if u.status == "reserve":
			reserves += 1
			assert_true(v.views[u.uid].reserve, "reserve view")
			assert_false(v.views[u.uid].visible, "not on the field yet")
	assert_true(reserves > 0, "waves wait off the field")
	var info = v.next_wave_info()
	assert_not_null(info, "the HUD's next wave")
	if info != null:
		for k in ["label", "count", "edge", "dueIn", "index", "total"]:
			assert_true(info.has(k), "next_wave_info." + k)


func test_rules_on_a_worker_freeze_a_snapshot_for_the_view() -> void:
	var v = _view_for(_fixture("overseer").setup, true)
	v.begin()
	assert_true(_idle(v), "begin")
	var live = v.b
	v.end_turn()
	if v.rules_running():
		assert_true(v.b != live, "the view reads a frozen copy while the rules run")
		assert_eq(v.b.units.size(), live.units.size())
		assert_true(v.busy(), "busy while the rules run")
		v.select_next() # refused quietly while busy? (select reads only the snapshot)
	assert_true(_idle(v), "the enemy turn plays out")
	assert_true(v.b == live, "the live battle is back")


func test_commands_from_the_hud() -> void:
	var v = _view_for(_fixture("scouts_clearing").setup, false)
	v.begin()
	assert_true(_idle(v))
	var u = v.selected_unit()
	assert_not_null(u, "a squad is selected at the start of the turn")
	var first: String = u.uid
	v.select_next()
	assert_ne(v.ui.selected, first, "select_next moves on")
	v.key_action("toggle_grid", true)
	assert_false(v.ui.showGrid, "G hides the grid")
	v.key_action("show_danger", true)
	assert_true(v.ui.danger, "Alt held shows the danger")
	v.key_action("show_danger", false)
	assert_false(v.ui.danger, "released")
	# A stance from the ability bar.
	var done_stance := false
	for s in v.b.active("player"):
		if done_stance:
			break
		for a in s.abilities:
			if v.DB.ABILITIES[a].kind == "stance":
				v.select(s.uid)
				v.set_ability(a)
				assert_true(_idle(v), "the stance plays")
				assert_eq(v.views[s.uid].stance, s.get("stance"), "view shows the stance")
				done_stance = true
				break
	assert_true(done_stance, "some squad has a stance")
	var sel = v.selected_unit()
	if sel != null and not sel.done:
		v.end_unit()
		assert_true(sel.done, "end_unit marks the squad done")
		assert_true(_idle(v))
	v.retreat()
	assert_true(_idle(v), "the withdrawal plays")
	assert_eq(_ended, ["retreat"])


func test_redo_takes_back_a_move() -> void:
	var v = _view_for(_fixture("trolls").setup, false)
	v.begin()
	assert_true(_idle(v))
	var u = v.b.active("player")[0]
	var x0: int = u.x
	var y0: int = u.y
	var reach: Dictionary = v.b.reachable(u)
	for k in reach:
		var p := {"x": k % 1000, "y": floori(k / 1000.0)}
		if p.x != x0 or p.y != y0:
			v.b.move(u.uid, p.x, p.y)
			v.pump()
			break
	assert_true(_idle(v))
	v.redo(u.uid)
	assert_true(_idle(v))
	assert_eq([u.x, u.y], [x0, y0], "back where it stood")
	assert_almost(v.views[u.uid].x, x0, 1e-9, "the view walked back")


func test_formation_casualties_follow_attacks() -> void:
	# Soldiers fall one by one during a melee exchange and the survivors re-form.
	var v = _view_for(_fixture("lab_clearing").setup, false)
	v.begin()
	assert_true(_idle(v))
	var turns := 0
	var saw_dying := false
	while v.b.phase == "player" and turns < 8:
		v.run_rules(Ai.run_player_auto)
		var t := 0.0
		while (v.busy() or v.rules_running()) and t < 120:
			v.advance(DT)
			t += DT
			for uv in v.views.values():
				for m in uv.members:
					if m.dying:
						saw_dying = true
		if v.b.phase == "player":
			v.end_turn()
			assert_true(_idle(v))
		turns += 1
	assert_true(saw_dying, "soldiers fell during the fighting")
	for uv in v.views.values():
		var standing := 0
		for m in uv.members:
			if m.alive:
				standing += 1
			assert_false(m.dying, "every fall has settled")
		assert_eq(standing, uv.alive, "members standing = alive shown")
	assert_true(v.corpses.size() > 0, "the fallen lie on the field")
