## Windowed captures of the battle view at 1920×1080, staged like the
## original's review scripts (squadcheck, combatlab, formations, facingstand,
## maps, reliefshots, hordeshots) and stepped at a fixed 1/60 s so they line
## up with tools/parity/battleview_shots.ts (the same scenes from the original).
##
##   tools/godot.sh --path . -s res://tests/visual/battle_shots.gd -- [scenario…]
##
## Scenarios: deploy march lab formations facing night relief stand horde (default: all).
## Output: tests/visual/out/battle_<scenario>_<frame>.png. The original's: battle_ref_*.png.
extends SceneTree

const JS = preload("res://scripts/core/js.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const Ai = preload("res://scripts/rules/ai.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const Iso = preload("res://scripts/render/iso.gd")
const OUT := "res://tests/visual/out/"
const DT := 1.0 / 60.0
const ALL := ["deploy", "march", "lab", "formations", "facing", "night", "relief", "stand", "horde"]

var vp: SubViewport
var view
var errors: Array = []


class Catcher extends Logger:
	var sink: Array

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			sink.append("%s (%s:%d)" % [rationale if rationale != "" else code, file, line])


func _initialize() -> void:
	var c := Catcher.new()
	c.sink = errors
	OS.add_logger(c)
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	vp = SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	root.add_child(vp)
	# Show the capture in the window too (scaled down).
	var tr := TextureRect.new()
	tr.texture = vp.get_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(tr)
	var list: Array = Array(OS.get_cmdline_user_args())
	if list.is_empty():
		list = ALL
	for s in list:
		print("scenario ", s)
		await call("_sc_" + s)
	print("errors: %d" % errors.size())
	for e in errors.slice(0, 20):
		print("  ", e)
	quit(0 if errors.is_empty() else 1)


# ---------------------------------------------------------------- harness

func _fixture(name: String) -> Dictionary:
	var f := FileAccess.open("res://tests/fixtures/battle_view/setups/%s.json" % name, FileAccess.READ)
	return JS.normalize(JSON.parse_string(f.get_as_text()))


func _start(setup: Dictionary, night := false) -> void:
	if view != null:
		view.queue_free()
		await process_frame
	view = load("res://scenes/battle/battle_view.tscn").instantiate()
	view.auto_step = false
	view.setup(Battle.new(setup))
	if night:
		view.atmo.night = true
	vp.add_child(view)
	# The ground and the host paint themselves in the first frames.
	for i in 3:
		view.step_frame(0.0)
		await process_frame
		RenderingServer.force_draw(false)


## Step `secs` of battle time at 1/60 s (waiting for rules on the worker).
func _step(secs: float) -> void:
	var n := roundi(secs / DT)
	for i in n:
		while view.rules_running():
			await process_frame
			view.step_frame(0.0)
		view.step_frame(DT)
	if n == 0:
		view.step_frame(0.0)


func _idle(max_s := 60.0) -> void:
	var t := 0.0
	var n := 0
	while t < max_s:
		await _step(DT * 6)
		t += DT * 6
		n += 1
		if not view.busy() and not view.rules_running():
			return
		if OS.has_environment("BV_DEBUG") and n % 50 == 0:
			print("    idle t=%.1f busy=%s rules=%s anims=%d queue=%d fx=%s" % [t, view.busy(), view.rules_running(), view._anims.size(), view._queue.size(), view.BattleDeps.fx_busy(view.fx)])


func _shot(name: String, crop := Rect2i()) -> void:
	view.step_frame(0.0)
	# One iteration records the queued _draw()s; then draw now ourselves, so a
	# minimized or hidden window (which Godot does not draw) cannot stall the run.
	await process_frame
	RenderingServer.force_draw(false)
	var img := vp.get_texture().get_image()
	if crop.size != Vector2i.ZERO:
		img = img.get_region(crop)
	img.save_png(ProjectSettings.globalize_path(OUT + "battle_%s.png" % name))
	if OS.has_environment("BV_DEBUG"):
		print("    shot %s at %d ms" % [name, Time.get_ticks_msec()])


func _focus(gx: float, gy: float, zoom: float, dy := -40.0) -> void:
	view.cam.tx = (gx - gy) * 64
	view.cam.x = view.cam.tx
	view.cam.ty = (gx + gy) * 32 + dy
	view.cam.y = view.cam.ty
	view.cam.tzoom = zoom
	view.cam.zoom = zoom


func _screen_of(gx: float, gy: float) -> Vector2:
	var t = Grid.tile_at(view.b.map, roundi(gx), roundi(gy))
	return view.cam.world_to_screen(Iso.iso_x(gx, gy), Iso.iso_y(gx, gy, t.h if t != null else 0), 1920, 1080)


# ---------------------------------------------------------------- scenarios

## squadcheck.mjs: the deployed company (moss trolls, new game 7, seed 7).
func _sc_deploy() -> void:
	await _start(_fixture("trolls").setup)
	await _step(1.5)
	await _shot("deploy")
	var u = view.b.active("player")[0]
	var v = view.views[u.uid]
	view.cam.tzoom = 1.5
	view.cam.tx = (v.x - v.y) * 64
	view.cam.ty = (v.x + v.y) * 32 - 40
	await _step(1.5)
	await _shot("deploy_closeup")


## squadcheck.mjs: two turns of marching in formation and the enemy's answer.
func _sc_march() -> void:
	await _start(_fixture("trolls").setup)
	await _step(0.5)
	view.begin()
	await _idle()
	view.cam.tzoom = 0.86
	for t in 2:
		var b = view.b
		for u in b.active("player"):
			if u.get("shot") != null:
				continue
			var reach: Dictionary = b.reachable(u)
			var best = null
			for k in reach:
				var p := {"x": k % 1000, "y": floori(k / 1000.0)}
				if best == null or p.y < best.y:
					best = p
			if best != null:
				b.move(u.uid, best.x, best.y)
		view.pump()
		for i in 6:
			await _step(0.26)
			await _shot("march_t%d_%d" % [t, i])
		await _idle()
		view.end_turn()
		for i in 10:
			await _step(0.2)
			await _shot("march_t%d_enemy_%d" % [t, i])
		await _idle()


## combatlab.mjs: one exchange on a cleared field, frame by frame.
func _stage(enc_case: String, a: Dictionary, bspec: Dictionary, opts := {}) -> Dictionary:
	await _start(_fixture(enc_case).setup)
	var bt = view.b
	for t in bt.map.tiles:
		t.erase("prop")
		if t.terrain == "forest" or t.terrain == "brush":
			t.terrain = "grass"
	view.map_changed()
	var tpl: Array = bt.units.duplicate()
	for u in tpl:
		u.status = "fled"
		u.x = -50
		u.y = -50
		view.views[u.uid].visible = false
	var make := func(spec: Dictionary, tag: String) -> Dictionary:
		var t: Dictionary = JS.find(tpl, func(x): return x.typeId == spec.type)
		var u: Dictionary = t.duplicate(true)
		u.uid = "%s-%s" % [t.uid, tag]
		u.status = "active"
		u.alive = spec.get("alive", u.size)
		u.hp = spec.get("hp", u.alive * u.hpPer)
		u.facing = spec.facing
		u.x = spec.x
		u.y = spec.y
		if spec.has("skill"):
			u.stats.melee = spec.skill
			u.stats.ranged = spec.skill
		bt.units.append(u)
		bt.hits_taken[u.uid] = 0
		view.views[u.uid] = view._make_view(u)
		return u
	var ua: Dictionary = make.call(a, "a")
	var ub: Dictionary = make.call(bspec, "b")
	if opts.get("findShot"):
		var tiles: Array = bt.map.tiles.duplicate()
		JS.sort(tiles, func(p, q): return JS.hypot(p.x - a.x, p.y - a.y) - JS.hypot(q.x - a.x, q.y - a.y))
		for t in tiles:
			if JS.hypot(t.x - ub.x, t.y - ub.y) < 3.5:
				continue
			ua.x = t.x
			ua.y = t.y
			if bt.can_shoot(ua, ub).ok:
				break
		view.views[ua.uid] = view._make_view(ua)
	bt.phase = "player" if ua.faction == "player" else "enemy"
	view.ui.selected = null
	view.ui.banner = null
	var mx: float = (ua.x + ub.x) / 2.0
	var my: float = (ua.y + ub.y) / 2.0
	_focus(mx, my, opts.get("zoom", 1.9))
	await _step(0.28)
	if opts.has("move"):
		bt.move(ua.uid, opts.move.x, opts.move.y)
	bt.attack(ua.uid, ub.uid)
	view.pump()
	return {"a": ua, "b": ub}


func _film(name: String, secs := 2.4, every := 0.1) -> void:
	var crop := Rect2i(480, 180, 960, 720)
	var i := 0
	var t := 0.0
	while t <= secs + 1e-6:
		await _shot("%s_%02d" % [name, i], crop)
		await _step(every)
		t += every
		i += 1


func _sc_lab() -> void:
	await _stage("overseer", {"type": "footman", "x": 6, "y": 6, "facing": 3, "skill": 300}, {"type": "goblin_spear", "x": 6, "y": 5, "facing": 1})
	await _film("lab_melee")
	await _stage("trolls", {"type": "troll", "x": 6, "y": 5, "facing": 1, "skill": 300}, {"type": "footman", "x": 6, "y": 6, "facing": 3})
	await _film("lab_troll")
	await _stage("overseer", {"type": "crossbowman", "x": 4, "y": 8, "facing": 3, "skill": 300}, {"type": "goblin_spear", "x": 6, "y": 4, "facing": 1}, {"zoom": 1.35, "findShot": true})
	await _film("lab_volley")
	await _stage("camp", {"type": "orc_warlord", "x": 6, "y": 5, "facing": 1, "skill": 300}, {"type": "footman", "x": 6, "y": 6, "facing": 3, "alive": 4})
	await _film("lab_warlord")


## formations.mjs: rows of squads at each facing and strength.
func _rows(enc_case: String, rows: Array) -> void:
	await _start(_fixture(enc_case).setup)
	var b = view.b
	for t in b.map.tiles:
		t.erase("prop")
		t.h = 0
	view.map_changed()
	var templates: Array = b.units.duplicate()
	for u in templates:
		u.status = "fled"
		u.x = -50
		u.y = -50
		view.views[u.uid].visible = false
	for r in rows.size():
		var row: Dictionary = rows[r]
		for c in row.squads.size():
			var sq: Dictionary = row.squads[c]
			var tp = JS.find(templates, func(x): return x.typeId == sq.type)
			if tp == null:
				tp = templates[0]
			var u: Dictionary = tp.duplicate(true)
			u.uid = "%s-g%d%d" % [tp.uid, r, c]
			u.status = "active"
			u.alive = sq.alive
			u.hp = sq.alive * u.hpPer
			u.facing = row.facing
			u.x = 3 + c * 2
			u.y = 2 + r * 2
			b.units.append(u)
			view.views[u.uid] = view._make_view(u)
	view.ui.selected = null
	view.ui.banner = null
	_focus(3 + 5, 2 + rows.size(), 1.25, -30)
	await _step(0.9)


func _sc_formations() -> void:
	var rows: Array = []
	for f in 4:
		var sq: Array = []
		var c := 0
		for a in [6, 5, 4, 3, 2, 1]:
			sq.append({"type": "footman" if c % 2 else "spearman", "alive": a})
			c += 1
		rows.append({"facing": f, "squads": sq})
	await _rows("overseer", rows)
	await _shot("formations_player")
	rows = []
	for f in 4:
		rows.append({"facing": f, "squads": [{"type": "troll", "alive": 3}, {"type": "troll", "alive": 2}, {"type": "troll", "alive": 1}, {"type": "goblin_spear", "alive": 6}, {"type": "goblin_archer", "alive": 5}, {"type": "goblin_spear", "alive": 3}]})
	await _rows("trolls", rows)
	await _shot("formations_trolls")
	rows = []
	for f in 4:
		var sq: Array = []
		for a in [6, 5, 4, 3, 2, 1]:
			sq.append({"type": "orc_warlord", "alive": a})
		rows.append({"facing": f, "squads": sq})
	await _rows("camp", rows)
	await _shot("formations_warlord")


## facingstand.mjs: the last stand at its opening zoom, a squad moved to a gate
## with the cursor pointed at the edge it should face.
func _sc_facing() -> void:
	await _start(_fixture("last_stand").setup)
	await _step(1.5)
	view.begin()
	await _idle()
	await _step(0.8)
	var b = view.b
	var foes: Array = b.active("enemy")
	var best = null
	for u in b.active("player"):
		var reach: Dictionary = b.reachable(u)
		for g in b.map.tiles:
			if not String(g.get("prop", "")).begins_with("gate"):
				continue
			if not reach.has(g.y * 1000 + g.x):
				continue
			var d: int = absi(u.x - g.x) + absi(u.y - g.y)
			if d < 2:
				continue
			if best == null or d < best.d:
				best = {"uid": u.uid, "gate": [g.x, g.y], "d": d}
	if best == null:
		print("  no gate in reach")
		return
	var gx: int = best.gate[0]
	var gy: int = best.gate[1]
	var nf = null
	for f in foes:
		var d: int = absi(f.x - gx) + absi(f.y - gy)
		if nf == null or d < nf.d:
			nf = {"d": d, "x": f.x, "y": f.y}
	var dx: int = nf.x - gx
	var dy: int = nf.y - gy
	var out := [signi(dx), 0] if absi(dx) >= absi(dy) else [0, signi(dy)]
	view.select(best.uid)
	await _step(0.3)
	await _shot("facing_selected")
	# Point at the gate tile's edge on the enemy's side.
	var p := _screen_of(gx + out[0] * 0.33, gy + out[1] * 0.33)
	view.pointer_move(p)
	await _step(0.4)
	await _shot("facing_gate")
	var clip := Rect2i(clampi(roundi(p.x) - 320, 0, 1280), clampi(roundi(p.y) - 210, 0, 660), 640, 420)
	await _shot("facing_gate_crop", clip)
	print("  facing plan ", best, " out ", out, " hover facing ", view.ui.hover.facing, " facings ", view.ui.hover.facings)
	view.pointer_down(p, 0)
	await _idle()
	await _step(0.4)
	await _shot("facing_arrived", clip)
	# Turn another squad on the spot: point at the edge of its own tile behind it.
	var tu = JS.find(view.b.active("player"), func(q): return not q.hasMoved and q.typeId != "militia")
	view.select(tu.uid)
	var back: Array = [[-1, 0], [0, -1], [1, 0], [0, 1]][tu.facing]
	await _step(0.3)
	var own := _screen_of(tu.x + back[0] * 0.36, tu.y + back[1] * 0.36)
	view.pointer_move(own)
	await _step(0.3)
	await _shot("facing_turn", Rect2i(clampi(roundi(own.x) - 320, 0, 1280), clampi(roundi(own.y) - 210, 0, 660), 640, 420))


## maps.mjs: a night raid lit by torches, and one in the dark.
func _sc_night() -> void:
	await _start(_fixture("night_torch").setup, true)
	await _step(1.8)
	await _shot("night_torch")
	await _start(_fixture("night_dark").setup, true)
	await _step(1.8)
	await _shot("night_dark")


## reliefshots.mjs: the last stand played by the AI to its last turn, then the dawn and the riders.
func _sc_relief() -> void:
	var setup: Dictionary = _fixture("last_stand").setup
	setup.objective.turns = 2
	await _start(setup)
	await _step(1.5)
	await _shot("relief_start")
	view.begin()
	await _idle(120)
	for guard in 10:
		var b = view.b
		if b.phase != "player":
			break
		view.run_rules(Ai.run_player_auto)
		await _idle(120)
		var last: bool = view.b.turn >= view.b.objective.turns
		view.end_turn()
		if not last:
			await _idle(240)
			continue
		var t := 0.0
		while view.relief == null and t < 240:
			await _step(DT * 6)
			t += DT * 6
		if view.relief == null:
			print("  no relief: ", view.b.phase, " ", view.b.result)
			return
		var t0 := 0.0
		for at in [0.2, 0.8, 1.4, 2.0, 2.6, 3.2, 4.0, 5.0]:
			await _step(at - t0)
			t0 = at
			await _shot("relief_%s" % JS.to_fixed(at, 1))
		await _idle(60)
		return


## The last stand at its opening (minimap, massing host, wave labels).
func _sc_stand() -> void:
	await _start(_fixture("last_stand").setup)
	await _step(1.5)
	await _shot("stand_deploy")
	view.begin()
	await _idle(120)
	await _step(0.5)
	await _shot("stand_turn1")
	await _start(_fixture("last_stand").setup, true)
	await _step(1.5)
	await _shot("stand_night")


## hordeshots.mjs: the horde on the field, turn by turn (the frame rate is
## measured by battle_fps.gd, in the root window).
func _sc_horde() -> void:
	await _start(_fixture("last_stand").setup)
	await _step(1.0)
	view.begin()
	await _idle(120)
	for t in 3:
		if view.b.phase != "player":
			break
		view.run_rules(Ai.run_player_auto)
		await _idle(240)
		view.end_turn()
		await _step(2.2)
		await _shot("horde_t%d_enemy" % t)
		print("  turn %d: enemy rules %.1f ms on the worker, snapshot %.1f ms" % [t + 1, view.last_rules_ms, view.last_snapshot_ms])
		await _idle(240)
		await _shot("horde_t%d_start" % (t + 1))
