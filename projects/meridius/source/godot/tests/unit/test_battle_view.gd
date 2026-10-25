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
	assert_false(v.surroundings.props.is_empty(), "terrain surrounds the entry openings")
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


# ---------------------------------------------------------------- spells, war machines, conditions

const Setup = preload("res://scripts/rules/setup.gd")
const Soldier = preload("res://scripts/meta/soldier.gd")
const DBX = preload("res://scripts/data/db.gd")
const Assets = preload("res://scripts/render/assets.gd")
const SquadView = preload("res://scripts/render/squad_view.gd")

## Tags of the squads staged by _lab -> uids.
var _tags := {}


## Squads staged on a flattened field (the original's magiclab.mjs `stage`):
## [{tag, type, x, y, facing, alive?, hurt?, skill?, promoted?}]. Returns the view.
func _lab(units: Array):
	var roll: Dictionary = Setup.roll_encounter("orc_overseer", Rng.new(5), 2)
	roll.mapId = "forest_clearing"
	var army := [Soldier.soldier_to_unit(Soldier.new_soldier(Rng.new(3), "footman", 1, func(): return "army0", 0))]
	var setup: Dictionary = Setup.build_battle(roll, army, {"survivalBonus": 0})
	for t in setup.map.tiles:
		t.erase("prop")
		if t.terrain == "forest" or t.terrain == "brush" or t.terrain == "water":
			t.terrain = "grass"
		t.h = 0
	setup.units = []
	setup.waves = []
	_tags = {}
	for i in units.size():
		var spec: Dictionary = units[i]
		var u: Dictionary
		if DBX.UNIT_TYPES[spec.type].faction == "player":
			var id := "lab%d" % i
			u = Soldier.soldier_to_unit(Soldier.new_soldier(Rng.new(40 + i), spec.type, 1, func(): return id, 0))
		else:
			u = Soldier.make_enemy(spec.type, 1, "lab-e%d" % i, Rng.new(60 + i))
		u.uid = "lab-%s" % spec.tag
		u.x = spec.x
		u.y = spec.y
		u.facing = spec.facing
		if spec.has("alive"):
			u.alive = spec.alive
		u.hp = u.alive * u.hpPer - int(spec.get("hurt", 0))
		if spec.has("skill"):
			u.stats.melee = spec.skill
			u.stats.ranged = spec.skill
		if spec.get("promoted"):
			u.abilities.append("mending_circle")
		setup.units.append(u)
		_tags[spec.tag] = u.uid
	var v = _view_for(setup, false)
	v.b.phase = "player"
	return v


func _unit(v, tag: String) -> Dictionary:
	return v.b.unit(_tags[tag])


## Every squad shown as the rules have it once playback is idle.
func _views_agree(v, label: String) -> void:
	for u in v.b.units:
		var uv = v.views[u.uid]
		if u.status == "active" or u.status == "routing":
			assert_eq(uv.hp, u.hp, "%s: %s hp" % [label, u.uid])
			assert_eq(uv.alive, u.alive, "%s: %s soldiers" % [label, u.uid])
			var ids: Array = u.get("statuses", []).map(func(s): return s.id)
			ids.sort()
			var shown: Array = uv.statuses.duplicate()
			shown.sort()
			assert_eq(shown, ids, "%s: %s conditions" % [label, u.uid])


func test_a_spell_is_chosen_aimed_by_hovering_and_cast_by_clicking() -> void:
	var v = _lab([
		{"tag": "m", "type": "battle_mage", "x": 5, "y": 9, "facing": 3, "skill": 400},
		{"tag": "f", "type": "footman", "x": 5, "y": 7, "facing": 3},
		{"tag": "g1", "type": "goblin_spear", "x": 5, "y": 4, "facing": 1},
		{"tag": "g2", "type": "goblin_rabble", "x": 6, "y": 4, "facing": 1},
		{"tag": "g3", "type": "goblin_spear", "x": 7, "y": 5, "facing": 1},
	])
	var m := _unit(v, "m")
	v.select(m.uid)
	v.key_action("ability_1", true)
	assert_eq(v.ui.ability, "chain_lightning", "1 picks the first active ability, a spell")
	v.pointer_move(_screen_of(v, 5, 4))
	var sp = v.ui.hover.spell
	assert_not_null(sp, "the forecast under the cursor")
	if sp == null:
		return
	assert_true(sp.legal)
	assert_eq(sp.hits.map(func(h): return h.role), ["main", "chain", "chain"], "the arcs it would jump along")
	assert_true(v.ui.hover.preview == null, "no attack forecast while a spell is aimed")
	# A click on another of the company's squads picks it instead.
	v.pointer_down(_screen_of(v, 5, 7), 0)
	assert_eq(v.ui.selected, _tags.f, "another squad selected")
	assert_eq(v.ui.ability, null, "the spell is put away")
	v.select(m.uid)
	v.set_ability("chain_lightning")
	v.pointer_move(_screen_of(v, 5, 4))
	v.pointer_down(_screen_of(v, 5, 4), 0)
	assert_true(m.hasActed, "cast")
	assert_eq(v.ui.ability, null)
	assert_true(_idle(v), "the lightning plays out")
	_views_agree(v, "after the lightning")
	assert_true(v.flash.a < 0.05, "the field's flash has faded")


func test_frost_chills_on_screen_and_the_bleeding_tick_plays() -> void:
	var v = _lab([
		{"tag": "m", "type": "battle_mage", "x": 5, "y": 9, "facing": 3, "skill": 400},
		{"tag": "o", "type": "orc_warrior", "x": 5, "y": 5, "facing": 1},
		{"tag": "g", "type": "goblin_spear", "x": 6, "y": 5, "facing": 1},
		{"tag": "s", "type": "goblin_shaman", "x": 5, "y": 1, "facing": 1, "skill": 400},
		{"tag": "f", "type": "footman", "x": 3, "y": 4, "facing": 3},
	])
	assert_true(v.b.cast(_tags.m, "frost_blast", {"x": 5, "y": 5}))
	v.pump()
	assert_true(_idle(v))
	assert_true(v.views[_tags.o].statuses.has("chilled"), "the orcs are shown chilled")
	_views_agree(v, "after the frost")
	v.b.phase = "enemy"
	assert_true(v.b.cast(_tags.s, "gutripper", {"x": 3, "y": 4}))
	v.pump()
	assert_true(_idle(v))
	assert_true(v.views[_tags.f].statuses.has("bleeding"), "the footmen are shown bleeding")
	var hp0: int = _unit(v, "f").hp
	v.b._start_turn("player")
	v.pump()
	assert_true(_idle(v))
	assert_true(_unit(v, "f").hp < hp0, "the wound opens again")
	_views_agree(v, "after the bleeding")


func test_self_target_spell_casts_at_once_and_cancel_puts_a_spell_away() -> void:
	var v = _lab([
		{"tag": "m", "type": "battle_mage", "x": 5, "y": 8, "facing": 3, "promoted": true},
		{"tag": "f", "type": "footman", "x": 5, "y": 7, "facing": 3, "alive": 4, "hurt": 20},
		{"tag": "g", "type": "goblin_spear", "x": 5, "y": 3, "facing": 1},
	])
	var m := _unit(v, "m")
	v.select(m.uid)
	v.set_ability("frost_blast")
	v.pointer_move(_screen_of(v, 5, 3))
	assert_not_null(v.ui.hover.spell)
	v.key_action("cancel", true)
	assert_eq(v.ui.ability, null, "Esc puts the spell away")
	assert_eq(v.ui.hover.spell, null, "and its forecast")
	v.set_ability("healing_light")
	v.pointer_down(Vector2(-500, -500), 2)
	assert_eq(v.ui.ability, null, "right click puts it away too")
	v.set_ability("mending_circle")
	assert_true(m.hasActed, "the circle needs no aiming")
	assert_true(_idle(v))
	_views_agree(v, "after the circle")


func test_a_war_machine_aims_its_stone_at_the_enemy_under_the_cursor() -> void:
	var v = _lab([
		{"tag": "m", "type": "mangonel", "x": 5, "y": 10, "facing": 3, "skill": 400},
		{"tag": "f", "type": "footman", "x": 4, "y": 5, "facing": 3},
		{"tag": "g1", "type": "goblin_rabble", "x": 5, "y": 5, "facing": 1},
		{"tag": "g2", "type": "goblin_spear", "x": 5, "y": 9, "facing": 1},
	])
	var m := _unit(v, "m")
	v.select(m.uid)
	v.pointer_move(_screen_of(v, 5, 5))
	var sp = v.ui.hover.spell
	assert_not_null(sp, "the stone is forecast with no ability chosen")
	if sp == null:
		return
	assert_eq(sp.ability, "hurl_stone")
	assert_true(sp.hits.any(func(h): return h.uid == _tags.f and h.ally), "the footmen beside it are caught")
	# Too close for a stone: the crew's own attack instead.
	v.pointer_move(_screen_of(v, 5, 9))
	assert_eq(v.ui.hover.spell, null, "no stone at an adjacent foe")
	assert_not_null(v.ui.hover.preview, "the crew's attack is forecast")
	v.pointer_move(_screen_of(v, 5, 5))
	v.pointer_down(_screen_of(v, 5, 5), 0)
	assert_true(m.hasActed, "the stone flies")
	var saw_atk := false
	var t := 0.0
	while v.busy() and t < 10:
		v.advance(DT)
		t += DT
		if v.views[m.uid].engine_atk > 0:
			saw_atk = true
	assert_true(saw_atk, "the engine shows its loosing pose")
	assert_true(_idle(v))
	_views_agree(v, "after the stone")


func test_the_ballista_bolt_runs_through_and_a_destroyed_crew_leaves_a_wreck() -> void:
	var v = _lab([
		{"tag": "b", "type": "ballista", "x": 5, "y": 10, "facing": 3, "skill": 400},
		{"tag": "g1", "type": "goblin_spear", "x": 5, "y": 6, "facing": 1},
		{"tag": "g2", "type": "goblin_rabble", "x": 5, "y": 5, "facing": 1},
	])
	assert_true(v.b.attack(_tags.b, _tags.g1))
	var through: Array = v.b.events.filter(func(e): return e.t == "attack" and e.get("via") != null)
	assert_eq(through.size(), 1, "the bolt goes on through")
	if through.size() == 1:
		assert_true(v._involved(through[0]).has(_tags.g1), "the squad it passed through is part of it")
	v.pump()
	assert_true(_idle(v))
	_views_agree(v, "after the bolt")
	# A wrecked engine.
	var w = _lab([
		{"tag": "b", "type": "ballista", "x": 5, "y": 6, "facing": 3, "alive": 1, "hurt": 18},
		{"tag": "o", "type": "orc_brute", "x": 5, "y": 5, "facing": 1, "skill": 400},
	])
	var uv = w.views[_tags.b]
	var u := _unit(w, "b")
	var eng = w._draw.engine_of(uv, u)
	assert_not_null(eng, "the engine stands among its crew")
	assert_eq(eng.s.key, "ballista_idle_b", "facing away: the back view")
	# Pointing at the engine picks the squad.
	var s: Dictionary = eng.s
	var hit := false
	for py in range(0, s.h, 6):
		for px in range(0, s.w, 6):
			if Assets.opaque_at(s, px, py):
				var k: float = s.scale * SquadView.member_scale(u)
				var wx: float = eng.x - (px - s.ax) * k if eng.flip else eng.x + (px - s.ax) * k
				var wy: float = eng.y + (py - s.ay) * k
				hit = w._draw.body_covers(uv, u, wx, wy)
				break
		if hit:
			break
	assert_true(hit, "the engine's pixels count for hit tests")
	w.b.phase = "enemy"
	assert_true(w.b.attack(_tags.o, _tags.b))
	w.pump()
	assert_true(_idle(w))
	assert_ne(u.status, "active", "the crew are gone")
	var wrecks: Array = w.corpses.filter(func(c): return c.type == "ballista")
	assert_eq(wrecks.size(), 1, "the engine is left as a wreck")
	assert_false(w._draw._engine_stands(uv), "and is no longer drawn standing")


func test_the_danger_overlay_counts_a_lobbers_stones() -> void:
	var v = _lab([
		{"tag": "f", "type": "footman", "x": 5, "y": 11, "facing": 3},
		{"tag": "r", "type": "rock_lobber", "x": 5, "y": 1, "facing": 1},
	])
	v.b.setup["fogOfWar"] = false # This test isolates the lobber range, not visibility.
	var d: Dictionary = v._draw._danger_tiles()
	assert_true(d.has(Grid.key(5, 9)), "eight tiles away, beyond its march, a stone can fall")
	assert_false(d.has(Grid.key(5, 11)), "ten tiles away it cannot")


func test_a_charge_aimed_too_close_runs_in_from_the_nearest_side_with_a_full_run() -> void:
	# ../../docs/squad-skills.md: the cursor on the side facing the hounds is
	# one tile off, too short a run, so the charge comes in from the closest
	# side that gives it two; a plain attack still takes the side under the cursor.
	var v = _lab([
		{"tag": "h", "type": "collie_guard", "x": 5, "y": 9, "facing": 3},
		{"tag": "g", "type": "goblin_spear", "x": 5, "y": 7, "facing": 1},
	])
	var h := _unit(v, "h")
	var g := _unit(v, "g")
	var near: Vector2 = _screen_of(v, 5, 7).lerp(_screen_of(v, 5, 8), 0.35)
	v.select(h.uid)
	v.pointer_move(near)
	var plain = v.ui.hover.preview
	assert_not_null(plain, "a forecast with the cursor on the goblins")
	if plain == null:
		return
	assert_eq([plain.moveFirst, plain.from], [true, {"x": 5, "y": 8}], "a plain attack steps to the side under the cursor")
	v.set_ability("hound_charge")
	v.pointer_move(near)
	var pv = v.ui.hover.preview
	assert_true(pv.legal, "charges: %s" % pv.get("reason"))
	assert_ne(pv.from, {"x": 5, "y": 8}, "not from the side one tile off")
	assert_eq(Grid.manhattan(pv.from, g), 1, "from beside the goblins")
	var path = v.b.path_to(h, pv.from.x, pv.from.y)
	assert_true(path != null and path.size() - 1 >= 2, "with a run of two tiles or more")
	assert_true(pv.mods.map(func(m): return m[0]).has("Charge"), "the charge's bonus in the forecast")
	# Out of sight in the woods, three tiles off: no side helps, the reason stays.
	g.y = 6
	Grid.tile_at(v.b.map, 5, 6).terrain = "forest"
	v.b.refresh_sight(true)
	assert_false(v.b.visible_to("player", g), "hidden in the woods")
	var hidden = v._preview_against(h, g)
	assert_false(hidden.legal, "no charge at a squad out of sight")
	assert_eq(hidden.get("reason"), "Target is hidden by fog of war")
