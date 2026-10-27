## Windowed captures of frame-animated squads (scripts/render/soldier_anim.gd)
## in the battle view at 1920×1080, stepped at a fixed 1/60 s: the four facings
## side by side, a march, a melee blow and the fallen, filmed frame by frame.
##
##   tools/godot.sh --path . -s res://tests/visual/footman_lab.gd -- [unit=<type>] [scenario…]
##
## Scenarios: facings march melee deaths (default: all). unit= picks the squad
## (default footman); the fixtures supply every type's template squad.
## Output: tests/visual/out/<unit>_<scenario>_<frame>.png (crops of the camera).
extends SceneTree

const JS = preload("res://scripts/core/js.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const Soldier = preload("res://scripts/meta/soldier.gd")
const DB = preload("res://scripts/data/db.gd")
const Rng = preload("res://scripts/core/rng.gd")
const OUT := "res://tests/visual/out/"
const DT := 1.0 / 60.0
const ALL := ["facings", "march", "march_ne", "march_nw", "melee", "deaths", "turn"]

var vp: SubViewport
var view
var errors: Array = []
var unit := "footman"
## Camera zoom of the marches (zoom=; the battle's range is about 0.4 to 1.6).
var zoom := 1.5


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
	var tr := TextureRect.new()
	tr.texture = vp.get_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(tr)
	var list: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("unit="):
			unit = a.substr(5)
		elif a.begins_with("zoom="):
			zoom = float(a.substr(5))
		else:
			list.append(a)
	if list.is_empty():
		list = ALL
	for s in list:
		print("scenario ", s)
		await call("_sc_" + s)
	if view != null:
		view.queue_free()
		await process_frame
	print("errors: %d" % errors.size())
	for e in errors.slice(0, 20):
		print("  ", e)
	quit(0 if errors.is_empty() else 1)


# ---------------------------------------------------------------- harness

func _start(enc_case: String) -> void:
	if view != null:
		view.queue_free()
		await process_frame
	var f := FileAccess.open("res://tests/fixtures/battle_view/setups/%s.json" % enc_case, FileAccess.READ)
	view = load("res://scenes/battle/battle_view.tscn").instantiate()
	view.auto_step = false
	view.setup(Battle.new(JS.normalize(JSON.parse_string(f.get_as_text())).setup))
	vp.add_child(view)
	for i in 3:
		view.step_frame(0.0)
		await process_frame
		RenderingServer.force_draw(false)


## A cleared field with only the squads in `specs` ({type, x, y, facing, alive?,
## hp?, skill?}); the first squad's side has the turn.
func _field(enc_case: String, specs: Array) -> Array:
	await _start(enc_case)
	var bt = view.b
	for t in bt.map.tiles:
		t.erase("prop")
		if t.terrain == "forest" or t.terrain == "brush" or t.terrain == "water":
			t.terrain = "grass"
	view.map_changed()
	var tpl: Array = bt.units.duplicate()
	for u in tpl:
		u.status = "fled"
		u.x = -50
		u.y = -50
		view.views[u.uid].visible = false
	var out: Array = []
	for i in specs.size():
		var spec: Dictionary = specs[i]
		var t: Variant = JS.find(tpl, func(x): return x.typeId == spec.type)
		if t == null:
			# A type the fixture has no squad of: made as the rules make a levy.
			t = Soldier.make_enemy(spec.type, 2, "lab-%s" % spec.type, Rng.new(7 + i))
			t.faction = DB.UNIT_TYPES[spec.type].faction
		var u: Dictionary = t.duplicate(true)
		u.uid = "%s-lab%d" % [t.uid, i]
		u.status = "active"
		u.alive = spec.get("alive", u.size)
		u.hp = spec.get("hp", u.alive * u.hpPer)
		u.facing = spec.facing
		u.x = spec.x
		u.y = spec.y
		u.hasMoved = false
		u.hasActed = false
		if spec.has("skill"):
			u.stats.melee = spec.skill
		bt.units.append(u)
		bt.hits_taken[u.uid] = 0
		view.views[u.uid] = view._make_view(u)
		out.append(u)
	bt.phase = "player" if out[0].faction == "player" else "enemy"
	view.ui.selected = null
	view.ui.banner = null
	return out


func _step(secs: float) -> void:
	var n := roundi(secs / DT)
	for i in n:
		while view.rules_running():
			await process_frame
			view.step_frame(0.0)
		view.step_frame(DT)
	if n == 0:
		view.step_frame(0.0)


func _shot(name: String, crop: Rect2i) -> void:
	view.step_frame(0.0)
	await process_frame
	RenderingServer.force_draw(false)
	var img := vp.get_texture().get_image().get_region(crop)
	img.save_png(ProjectSettings.globalize_path(OUT + "%s_%s.png" % [unit, name]))


func _focus(gx: float, gy: float, zoom: float, dy := -40.0) -> void:
	view.cam.tx = (gx - gy) * 64
	view.cam.x = view.cam.tx
	view.cam.ty = (gx + gy) * 32 + dy
	view.cam.y = view.cam.ty
	view.cam.tzoom = zoom
	view.cam.zoom = zoom


## `secs` of play filmed every `every` seconds.
func _film(name: String, secs: float, every: float, crop: Rect2i) -> void:
	var i := 0
	var t := 0.0
	while t <= secs + 1e-6:
		await _shot("%s_%03d" % [name, i], crop)
		await _step(every)
		t += every
		i += 1


# ---------------------------------------------------------------- scenarios

## Four squads, one per facing, breathing where they stand.
func _sc_facings() -> void:
	await _field("overseer", [
		{"type": unit, "x": 4, "y": 6, "facing": 1},
		{"type": unit, "x": 6, "y": 6, "facing": 0},
		{"type": unit, "x": 4, "y": 8, "facing": 3},
		{"type": unit, "x": 6, "y": 8, "facing": 2},
	])
	_focus(5, 7, 1.1)
	await _step(0.5)
	await _film("facings", 1.6, 0.4, Rect2i(360, 140, 1200, 800))


## One squad marching four tiles, turning on the way.
func _sc_march() -> void:
	var us := await _field("overseer", [{"type": unit, "x": 3, "y": 4, "facing": 1}])
	var u: Dictionary = us[0]
	_focus(4, 5.5, 1.35)
	await _step(0.4)
	view.b.move(u.uid, 5, 6)
	view.pump()
	await _film("march", 1.6, 1.0 / 20.0, Rect2i(560, 200, 800, 640))


## The squad facing the filmed one: the horde for the company, the company for the horde.
func _foe(killer := false) -> String:
	if DB.UNIT_TYPES[unit].faction == "player":
		return "troll" if killer else "goblin_spear"
	return "collie_guard" if killer else "footman"


## How far the target stands: archers and casters shoot from three tiles.
func _gap() -> int:
	return 3 if float(DB.UNIT_TYPES[unit].base.get("ranged", 0)) > 0 else 1


## A blow (or a volley) toward the back and toward the front, the slain dropping as it lands.
func _sc_melee() -> void:
	var g := _gap()
	var us := await _field("overseer", [
		{"type": unit, "x": 6, "y": 6 + g - 1, "facing": 3, "skill": 300},
		{"type": _foe(), "x": 6, "y": 5 - g + 1, "facing": 1},
	])
	_focus(6, 5.5, 1.6 if g == 1 else 1.1)
	await _step(0.3)
	view.b.attack(us[0].uid, us[1].uid)
	view.pump()
	await _film("melee_ne", 1.6, 1.0 / 20.0, Rect2i(560, 200, 800, 640))
	us = await _field("overseer", [
		{"type": unit, "x": 6, "y": 5 - g + 1, "facing": 1, "skill": 300},
		{"type": _foe(), "x": 6, "y": 6 + g - 1, "facing": 3},
	])
	_focus(6, 5.5, 1.6 if g == 1 else 1.1)
	await _step(0.3)
	view.b.attack(us[0].uid, us[1].uid)
	view.pump()
	await _film("melee_sw", 1.6, 1.0 / 20.0, Rect2i(560, 200, 800, 640))


## The squad cut down from the front and from behind, falling and left lying.
func _sc_deaths() -> void:
	var us := await _field("trolls", [
		{"type": _foe(true), "x": 6, "y": 5, "facing": 1, "skill": 300},
		{"type": unit, "x": 6, "y": 6, "facing": 3, "hp": 80},
	])
	_focus(6, 5.6, 1.6)
	await _step(0.3)
	view.b.attack(us[0].uid, us[1].uid)
	view.pump()
	await _film("deaths_back", 1.8, 1.0 / 20.0, Rect2i(560, 200, 800, 640))
	us = await _field("trolls", [
		{"type": _foe(true), "x": 6, "y": 7, "facing": 3, "skill": 300},
		{"type": unit, "x": 6, "y": 6, "facing": 1, "hp": 80},
	])
	_focus(6, 6.4, 1.6)
	await _step(0.3)
	view.b.attack(us[0].uid, us[1].uid)
	view.pump()
	await _film("deaths_front", 1.8, 1.0 / 20.0, Rect2i(560, 200, 800, 640))


## Struck at from behind and to the side: the squad faces away from its target
## (as the rules may leave it) and the men turn to strike or shoot, then turn back.
func _sc_turn() -> void:
	var g := _gap()
	var us := await _field("overseer", [
		{"type": unit, "x": 6, "y": 6, "facing": 1, "skill": 300},
		{"type": _foe(), "x": 6, "y": 6 - g, "facing": 1},
	])
	_focus(6, 6 - g / 2.0, 1.6 if g == 1 else 1.1)
	await _step(0.3)
	view.b.attack(us[0].uid, us[1].uid)
	view.pump()
	await _film("turn_back", 2.2, 1.0 / 20.0, Rect2i(560, 200, 800, 640))
	us = await _field("overseer", [
		{"type": unit, "x": 6, "y": 6, "facing": 3, "skill": 300},
		{"type": _foe(), "x": 6 + g, "y": 6, "facing": 2},
	])
	_focus(6 + g / 2.0, 6, 1.6 if g == 1 else 1.1)
	await _step(0.3)
	view.b.attack(us[0].uid, us[1].uid)
	view.pump()
	await _film("turn_side", 2.2, 1.0 / 20.0, Rect2i(560, 200, 800, 640))


## The company's usual march: four tiles toward the upper right (facing 3, -y),
## filmed with the camera fixed so the stride and the heading can be judged.
func _sc_march_ne() -> void:
	await _march_away("march_ne", {"x": 5, "y": 9, "facing": 3}, Vector2i(5, 5), Vector2(5, 7))


## The same away from the camera toward the upper left (facing 2, -x).
func _sc_march_nw() -> void:
	await _march_away("march_nw", {"x": 9, "y": 7, "facing": 2}, Vector2i(5, 7), Vector2(7, 7))


func _march_away(name: String, at: Dictionary, to: Vector2i, cam: Vector2) -> void:
	var spec := at.duplicate()
	spec.type = unit
	var us := await _field("overseer", [spec])
	var u: Dictionary = us[0]
	_focus(cam.x, cam.y, zoom)
	await _step(0.4)
	view.b.move(u.uid, to.x, to.y)
	view.pump()
	var i := 0
	var t := 0.0
	while t <= 2.4 + 1e-6:
		# The view follows a player's march; hold the camera still instead.
		_focus(cam.x, cam.y, zoom)
		await _shot("%s_%03d" % [name, i], Rect2i(560, 140, 800, 700))
		await _step(1.0 / 25.0)
		t += 1.0 / 25.0
		i += 1


## Gaits side by side: footmen, goblin spearmen, orc brutes and trolls march
## four tiles up-right together (lab copies, all on the company's side so the
## rules let them move in one turn), the camera fixed.
func _sc_parade() -> void:
	var kinds := ["footman", "goblin_spear", "orc_brute", "troll"]
	var specs: Array = []
	for i in kinds.size():
		specs.append({"type": kinds[i], "x": 3 + i * 2, "y": 10, "facing": 3})
	var us := await _field("overseer", specs)
	for u in us:
		u.faction = "player"
		u.stats.move = 8
	view.b.phase = "player"
	_focus(6, 8, 0.95)
	await _step(0.5)
	for i in us.size():
		view.b.move(us[i].uid, us[i].x, 6)
	view.pump()
	var i := 0
	var t := 0.0
	while t <= 3.2 + 1e-6:
		_focus(6, 8, 0.95)
		await _shot("parade_%03d" % i, Rect2i(260, 60, 1400, 960))
		await _step(1.0 / 25.0)
		t += 1.0 / 25.0
		i += 1


## Standing about: the same four kinds idle for eight seconds (breathing, swaying, fidgets).
func _sc_idle() -> void:
	var kinds := ["footman", "goblin_spear", "orc_brute", "troll"]
	var specs: Array = []
	for i in kinds.size():
		specs.append({"type": kinds[i], "x": 3 + i * 2, "y": 7, "facing": 1})
	await _field("overseer", specs)
	_focus(6, 7, 1.25)
	await _step(0.5)
	var i := 0
	var t := 0.0
	while t <= 8.0 + 1e-6:
		await _shot("idle_%03d" % i, Rect2i(260, 140, 1400, 800))
		await _step(1.0 / 12.5)
		t += 1.0 / 12.5
		i += 1
