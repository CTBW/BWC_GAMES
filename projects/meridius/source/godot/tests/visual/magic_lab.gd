## Magic and war machine lab, staged like the original's scripts/magiclab.mjs:
## spells, war-machine shots and conditions on a flattened field with the real
## battle view, captured frame by frame; every engine in all four facings; and
## (beyond the original lab) the aiming highlights of a chosen spell, a
## mangonel's stone and the danger overlay with a rock lobber.
##
##   tools/godot.sh --path . -s res://tests/visual/magic_lab.gd -- [stage-filter…]
##
## Output: tests/visual/out/magic/<stage>/NNN.png (1280×760 like the original's
## page), log.txt, and tests/visual/out/magic/sheets/<stage>.png contact sheets
## (6 frames, crop 250,60,780,580, 3 columns: the original's scripts/sheets.mjs),
## to compare with review/magic-lab-v*/sheets of the original. Frames are
## FRAME_DT seconds of battle time apart. Run windowed (not --headless).
extends SceneTree

const JS = preload("res://scripts/core/js.gd")
const Rng = preload("res://scripts/core/rng.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const Setup = preload("res://scripts/rules/setup.gd")
const Soldier = preload("res://scripts/meta/soldier.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const Iso = preload("res://scripts/render/iso.gd")
const DB = preload("res://scripts/data/db.gd")
const OUT := "res://tests/visual/out/magic/"
const W := 1280
const H := 760
const DT := 1.0 / 60.0
## Battle time between captured frames (about the original lab's cadence: its
## page screenshots came some 0.15–0.2 s of battle time apart, unevenly at timeScale 0.5).
const FRAME_DT := 0.16

var vp: SubViewport
var view
var errors: Array = []
var filters: Array = []
var tags := {}
var summary: Array = []


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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "sheets"))
	# Keep the editor's importer away from the captures.
	FileAccess.open(OUT + ".gdignore", FileAccess.WRITE).close()
	vp = SubViewport.new()
	vp.size = Vector2i(W, H)
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
	filters = Array(OS.get_cmdline_user_args())
	await _stages()
	print("---- summary")
	for l in summary:
		print("  ", l)
	print("errors: %d" % errors.size())
	for e in errors.slice(0, 30):
		print("  ", e)
	quit(0 if errors.is_empty() else 1)


func _stages() -> void:
	await _stage("lightning", [
		{"tag": "m", "type": "battle_mage", "x": 5, "y": 9, "facing": 3, "skill": 400},
		{"tag": "f", "type": "footman", "x": 5, "y": 7, "facing": 3},
		{"tag": "g1", "type": "goblin_spear", "x": 5, "y": 4, "facing": 1},
		{"tag": "g2", "type": "goblin_rabble", "x": 6, "y": 4, "facing": 1},
		{"tag": "g3", "type": "goblin_spear", "x": 7, "y": 5, "facing": 1},
	], {"cast": ["m", "chain_lightning", "g1"]}, {"focus": {"x": 6, "y": 6}})
	await _stage("frost", [
		{"tag": "m", "type": "battle_mage", "x": 5, "y": 9, "facing": 3, "skill": 400},
		{"tag": "f", "type": "spearman", "x": 4, "y": 7, "facing": 3},
		{"tag": "o", "type": "orc_warrior", "x": 5, "y": 5, "facing": 1},
		{"tag": "g", "type": "goblin_spear", "x": 6, "y": 5, "facing": 1},
	], {"cast": ["m", "frost_blast", "o"]}, {"focus": {"x": 5, "y": 7}})
	await _stage("heal", [
		{"tag": "m", "type": "battle_mage", "x": 5, "y": 9, "facing": 3, "promoted": true},
		{"tag": "f", "type": "footman", "x": 5, "y": 7, "facing": 3, "alive": 4, "hurt": 20},
		{"tag": "g", "type": "goblin_spear", "x": 5, "y": 6, "facing": 1},
	], {"cast": ["m", "healing_light", "f"]}, {"focus": {"x": 5, "y": 8}, "zoom": 1.5})
	await _stage("circle", [
		{"tag": "m", "type": "battle_mage", "x": 5, "y": 8, "facing": 3, "promoted": true},
		{"tag": "f", "type": "footman", "x": 5, "y": 7, "facing": 3, "alive": 4, "hurt": 20},
		{"tag": "s", "type": "spearman", "x": 4, "y": 8, "facing": 3, "hurt": 25},
		{"tag": "g", "type": "goblin_spear", "x": 5, "y": 4, "facing": 1},
	], {"cast": ["m", "mending_circle", "m"]}, {"focus": {"x": 5, "y": 7.5}, "zoom": 1.4})
	await _stage("fireball", [
		{"tag": "s", "type": "goblin_shaman", "x": 5, "y": 2, "facing": 1, "skill": 400},
		{"tag": "g", "type": "goblin_spear", "x": 5, "y": 5, "facing": 1},
		{"tag": "f1", "type": "footman", "x": 5, "y": 6, "facing": 3},
		{"tag": "f2", "type": "crossbowman", "x": 6, "y": 6, "facing": 3},
	], {"cast": ["s", "fireball", "f1"]}, {"focus": {"x": 5, "y": 4}})
	await _stage("bloodlust", [
		{"tag": "s", "type": "goblin_shaman", "x": 5, "y": 2, "facing": 1},
		{"tag": "b", "type": "orc_brute", "x": 5, "y": 5, "facing": 1},
		{"tag": "f", "type": "footman", "x": 5, "y": 7, "facing": 3},
	], {"cast": ["s", "bloodlust", "b"]}, {"focus": {"x": 5, "y": 4}, "zoom": 1.5})
	await _stage("gutripper", [
		{"tag": "s", "type": "goblin_shaman", "x": 5, "y": 2, "facing": 1, "skill": 400},
		{"tag": "f", "type": "footman", "x": 5, "y": 6, "facing": 3},
	], {"cast": ["s", "gutripper", "f"]}, {"focus": {"x": 5, "y": 4}, "zoom": 1.5})
	await _stage("bleeding-tick", [
		{"tag": "f", "type": "spearman", "x": 5, "y": 6, "facing": 3},
		{"tag": "g", "type": "goblin_spear", "x": 5, "y": 2, "facing": 1},
	], {"turn": "player", "with": [["f", "bleeding", 2, 30]]}, {"focus": {"x": 5, "y": 6}, "zoom": 1.7})
	# Not magic: a squad broken by a free attack while passing through an ally's
	# tile backs off to its own (Godot only; the archived original left it there).
	await _stage("fallback", [
		{"tag": "f", "type": "footman", "x": 5, "y": 9, "facing": 3, "morale": 1},
		{"tag": "s", "type": "spearman", "x": 5, "y": 8, "facing": 3},
		{"tag": "g", "type": "goblin_spear", "x": 6, "y": 8, "facing": 2, "skill": 400},
	], {"move": ["f", 4, 8, 2]}, {"focus": {"x": 5, "y": 8.5}, "zoom": 1.6})
	await _stage("ballista", [
		{"tag": "b", "type": "ballista", "x": 5, "y": 10, "facing": 3, "skill": 400},
		{"tag": "g1", "type": "goblin_spear", "x": 5, "y": 6, "facing": 1},
		{"tag": "g2", "type": "goblin_rabble", "x": 5, "y": 5, "facing": 1},
	], {"attack": ["b", "g1"]}, {"focus": {"x": 5, "y": 8}})
	await _stage("mangonel", [
		{"tag": "m", "type": "mangonel", "x": 5, "y": 10, "facing": 3, "skill": 400},
		{"tag": "f", "type": "footman", "x": 4, "y": 5, "facing": 3},
		{"tag": "g1", "type": "goblin_rabble", "x": 5, "y": 4, "facing": 1},
		{"tag": "g2", "type": "goblin_spear", "x": 6, "y": 4, "facing": 1},
	], {"cast": ["m", "hurl_stone", "g1"]}, {"focus": {"x": 5, "y": 7}, "zoom": 1.0})
	await _stage("rock-lobber", [
		{"tag": "r", "type": "rock_lobber", "x": 5, "y": 1, "facing": 1},
		{"tag": "f", "type": "footman", "x": 5, "y": 7, "facing": 3},
		{"tag": "s", "type": "spearman", "x": 6, "y": 7, "facing": 3},
	], {"cast": ["r", "lob_rock", "f"]}, {"focus": {"x": 5, "y": 4}, "zoom": 1.0})
	await _stage("war-wagon", [
		{"tag": "w", "type": "war_wagon", "x": 5, "y": 5, "facing": 1, "skill": 400},
		{"tag": "f", "type": "footman", "x": 5, "y": 6, "facing": 3},
	], {"attack": ["w", "f"]}, {"focus": {"x": 5, "y": 6}, "zoom": 1.7})
	await _stage("mage-bolts", [
		{"tag": "m", "type": "battle_mage", "x": 5, "y": 9, "facing": 3, "skill": 400},
		{"tag": "g", "type": "goblin_spear", "x": 5, "y": 5, "facing": 1},
	], {"attack": ["m", "g"]}, {"focus": {"x": 5, "y": 7}, "zoom": 1.3})
	await _stage("wreck", [
		{"tag": "b", "type": "ballista", "x": 5, "y": 6, "facing": 3, "alive": 1, "hurt": 18},
		{"tag": "o", "type": "orc_brute", "x": 5, "y": 5, "facing": 1, "skill": 400},
	], {"attack": ["o", "b"]}, {"focus": {"x": 5, "y": 5.5}, "zoom": 1.7})
	await _stage("conditions", [
		{"tag": "a", "type": "goblin_spear", "x": 4, "y": 5, "facing": 1},
		{"tag": "b", "type": "orc_brute", "x": 6, "y": 5, "facing": 1},
		{"tag": "c", "type": "footman", "x": 5, "y": 7, "facing": 3},
		{"tag": "m", "type": "battle_mage", "x": 4, "y": 8, "facing": 3},
		{"tag": "w", "type": "war_wagon", "x": 7, "y": 7, "facing": 2},
		{"tag": "bl", "type": "ballista", "x": 6, "y": 9, "facing": 3},
	], {"statuses": [["a", "chilled"], ["b", "bloodlust"], ["c", "bleeding"], ["w", "chilled"], ["bl", "bloodlust"]]}, {"focus": {"x": 5, "y": 7}, "zoom": 1.35, "frames": 6, "minFrames": 3})
	# Every war machine in all four facings, with its crew.
	var parade: Array = []
	var types := ["ballista", "mangonel", "rock_lobber", "war_wagon"]
	for i in types.size():
		for j in 4:
			parade.append({"tag": "%s%d" % [types[i], j], "type": types[i], "x": 2 + j * 3, "y": 1 + i * 3, "facing": j})
	await _stage("engines-facings", parade, {"statuses": []}, {"focus": {"x": 6.5, "y": 5.5}, "zoom": 0.95, "frames": 3, "minFrames": 1})
	for pair in [["engines-close-company", ["ballista", "mangonel"]], ["engines-close-host", ["rock_lobber", "war_wagon"]]]:
		var close: Array = []
		for i in pair[1].size():
			for j in 4:
				close.append({"tag": "%s%d" % [pair[1][i], j], "type": pair[1][i], "x": 3 + j * 2, "y": 4 + i * 2, "facing": j})
		await _stage(pair[0], close, {"statuses": []}, {"focus": {"x": 6, "y": 5}, "zoom": 1.7, "frames": 3, "minFrames": 1})
	# The interface: a spell chosen and aimed, a mangonel's stone aimed by hovering, the danger overlay.
	await _stage("aim-lightning", [
		{"tag": "m", "type": "battle_mage", "x": 5, "y": 9, "facing": 3},
		{"tag": "f", "type": "footman", "x": 5, "y": 7, "facing": 3},
		{"tag": "g1", "type": "goblin_spear", "x": 5, "y": 4, "facing": 1},
		{"tag": "g2", "type": "goblin_rabble", "x": 6, "y": 4, "facing": 1},
		{"tag": "g3", "type": "goblin_spear", "x": 7, "y": 5, "facing": 1},
	], {"aim": ["m", "chain_lightning", "g1"]}, {"focus": {"x": 6, "y": 6}, "frames": 2, "minFrames": 1})
	await _stage("aim-heal", [
		{"tag": "m", "type": "battle_mage", "x": 5, "y": 10, "facing": 3},
		{"tag": "f", "type": "footman", "x": 4, "y": 5, "facing": 3},
		{"tag": "g1", "type": "goblin_rabble", "x": 5, "y": 5, "facing": 1},
		{"tag": "h", "type": "footman", "x": 4, "y": 9, "facing": 3, "alive": 3, "hurt": 20},
	], {"aim": ["m", "healing_light", "h"]}, {"focus": {"x": 5, "y": 8}, "frames": 2, "minFrames": 1})
	await _stage("aim-mangonel", [
		{"tag": "m", "type": "mangonel", "x": 5, "y": 10, "facing": 3},
		{"tag": "f", "type": "footman", "x": 4, "y": 5, "facing": 3},
		{"tag": "g1", "type": "goblin_rabble", "x": 5, "y": 5, "facing": 1},
		{"tag": "g2", "type": "goblin_spear", "x": 6, "y": 5, "facing": 1},
	], {"aim": ["m", null, "g1"]}, {"focus": {"x": 5, "y": 7.5}, "zoom": 1.0, "frames": 2, "minFrames": 1})
	await _stage("danger-lobber", [
		{"tag": "f", "type": "footman", "x": 5, "y": 9, "facing": 3},
		{"tag": "r", "type": "rock_lobber", "x": 5, "y": 1, "facing": 1},
	], {"danger": true}, {"focus": {"x": 5, "y": 5}, "zoom": 0.8, "frames": 2, "minFrames": 1})


# ---------------------------------------------------------------- harness

func _wanted(name: String) -> bool:
	if filters.is_empty():
		return true
	for f in filters:
		if name.contains(f):
			return true
	return false


## Stage squads on a flattened field and run one action (magiclab.mjs `stage`).
## `units`: [{tag, type, x, y, facing, alive?, skill?, hurt?, promoted?}].
## `action`: {cast: [tag, spell, tag]} | {attack: [tag, tag]} | {turn: faction}
## | {statuses: [[tag, id]]} | {aim: [tag, spell|null, tag]} | {danger: true};
## `with`: conditions already on squads [[tag, id, turns, power]].
func _stage(name: String, units: Array, action: Dictionary, opts := {}) -> void:
	if not _wanted(name):
		return
	if view != null:
		view.queue_free()
		view = null
		await process_frame
	var roll: Dictionary = Setup.roll_encounter("orc_overseer", Rng.new(5), 2)
	roll.mapId = "forest_clearing"
	var army := [Soldier.soldier_to_unit(Soldier.new_soldier(Rng.new(3), "footman", 1, func(): return "army0", 0))]
	var setup: Dictionary = Setup.build_battle(roll, army, {"survivalBonus": 0})
	var bt = Battle.new(setup)
	for t in bt.map.tiles:
		t.erase("prop")
		if t.terrain == "forest" or t.terrain == "brush" or t.terrain == "water":
			t.terrain = "grass"
		t.h = 0
	# Only the staged squads take the field.
	bt.units.clear()
	bt.setup.waves = []
	bt.wave_state = []
	tags = {}
	for i in units.size():
		var spec: Dictionary = units[i]
		var u: Dictionary
		if DB.UNIT_TYPES[spec.type].faction == "player":
			var id := "lab%d" % i
			u = Soldier.soldier_to_unit(Soldier.new_soldier(Rng.new(40 + i), spec.type, int(spec.get("level", 1)), func(): return id, 0))
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
		if spec.has("morale"):
			u.morale = spec.morale
		bt.units.append(u)
		bt.hits_taken[u.uid] = 0
		tags[spec.tag] = u.uid
	bt.phase = "player"
	view = load("res://scenes/battle/battle_view.tscn").instantiate()
	view.auto_step = false
	view.threaded_rules = false
	view.setup(bt)
	vp.add_child(view)
	var f: Dictionary = opts.get("focus", units[0])
	view.ui.selected = null
	view.ui.banner = null
	view.ui.showGrid = false
	var z: float = opts.get("zoom", 1.25)
	view.cam.tx = (f.x - f.y) * 64
	view.cam.x = view.cam.tx
	view.cam.ty = (f.x + f.y) * 32 - 40
	view.cam.y = view.cam.ty
	view.cam.tzoom = z
	view.cam.zoom = z
	for i in 3:
		view.step_frame(0.0)
		await process_frame
		RenderingServer.force_draw(false)
	await _step(0.3)
	var ok := true
	var note := ""
	for w in action.get("with", []):
		var u = bt.unit(tags[w[0]])
		u.statuses.append({"id": w[1], "turns": w[2], "power": w[3]})
		view.views[u.uid].statuses.append(w[1])
	if action.has("cast"):
		var c: Array = action.cast
		var u = bt.unit(tags[c[0]])
		bt.phase = "player" if u.faction == "player" else "enemy"
		var tile = bt.unit(tags[c[2]])
		var at := {"x": tile.x, "y": tile.y}
		ok = bt.cast(u.uid, c[1], at)
		if not ok:
			var pv: Dictionary = bt.spell_preview(u, c[1], at)
			note = "cast refused: %s" % pv.get("reason", bt.can_cast(u, c[1]).get("reason", "?"))
	elif action.has("attack"):
		var c: Array = action.attack
		var u = bt.unit(tags[c[0]])
		bt.phase = "player" if u.faction == "player" else "enemy"
		ok = bt.attack(u.uid, tags[c[1]])
		if not ok:
			note = "attack refused: %s" % bt.preview(u, bt.unit(tags[c[1]])).get("reason", "?")
	elif action.has("move"):
		var c: Array = action.move
		var u = bt.unit(tags[c[0]])
		bt.phase = "player" if u.faction == "player" else "enemy"
		ok = bt.move(u.uid, c[1], c[2], c[3])
		if not ok:
			note = "move refused"
		else:
			note = "ends on %d,%d facing %d, %s" % [u.x, u.y, u.facing, u.status]
	elif action.has("statuses"):
		# Lay conditions directly (for a still of how they look).
		for s in action.statuses:
			var u = bt.unit(tags[s[0]])
			u.statuses.append({"id": s[1], "turns": 2, "power": 6})
			view.views[u.uid].statuses.append(s[1])
	elif action.has("turn"):
		bt._start_turn(action.turn)
	elif action.has("aim"):
		# Through the view's own input: select, choose the spell, hover the target.
		var c: Array = action.aim
		view.select(tags[c[0]])
		view.cam.tx = (f.x - f.y) * 64
		view.cam.x = view.cam.tx
		view.cam.ty = (f.x + f.y) * 32 - 40
		view.cam.y = view.cam.ty
		if c[1] != null:
			view.set_ability(c[1])
		var t = bt.unit(tags[c[2]])
		view.step_frame(0.0)
		view.pointer_move(_screen_of(t.x, t.y, -20.0))
		var sp = view.ui.hover.get("spell")
		note = "aim %s: ability %s, spell %s, preview %s" % [c[2], view.ui.ability, ("legal=%s hits=%d %s" % [sp.legal, sp.hits.size(), sp.get("reason", "")]) if sp != null else "null", "yes" if view.ui.hover.get("preview") != null else "no"]
		ok = sp != null and sp.legal
	elif action.has("danger"):
		view.key_action("show_danger", true)
	view.pump()
	var dir := OUT + name + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for old in DirAccess.get_files_at(ProjectSettings.globalize_path(dir)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + old))
	var frames: int = opts.get("frames", 40)
	var min_frames: int = opts.get("minFrames", 14)
	var shots: Array = []
	for i in frames:
		var img := await _shot()
		var path := dir + "%03d.png" % i
		img.save_png(ProjectSettings.globalize_path(path))
		shots.append(path)
		if not view.busy() and i > min_frames:
			break
		await _step(FRAME_DT)
	var lines: Array = []
	for l in view.ui.log:
		lines.push_front(l.text)
	var fa := FileAccess.open(dir + "log.txt", FileAccess.WRITE)
	fa.store_string("%s\n%s%s" % ["ok" if ok else "REFUSED", note + "\n" if note != "" else "", "\n".join(lines)])
	fa.close()
	_sheet(name, shots)
	var line := "%s %s (%d frames) %s" % [name, "ok" if ok else "REFUSED", shots.size(), " | ".join(lines.slice(maxi(0, lines.size() - 3)))]
	if note != "":
		line += " [" + note + "]"
	summary.append(line)
	print(line)


## Step `secs` of battle time at 1/60 s.
func _step(secs: float) -> void:
	var n := roundi(secs / DT)
	for i in n:
		view.step_frame(DT)
	if n == 0:
		view.step_frame(0.0)


func _shot() -> Image:
	view.step_frame(0.0)
	await process_frame
	RenderingServer.force_draw(false)
	return vp.get_texture().get_image()


func _screen_of(gx: float, gy: float, dy := 0.0) -> Vector2:
	return view.cam.world_to_screen(Iso.iso_x(gx, gy), Iso.iso_y(gx, gy, 0) + dy, W, H)


## A contact sheet: 6 frames evenly picked, cropped to the action, 3 columns (sheets.mjs).
func _sheet(name: String, shots: Array) -> void:
	var per := 6
	var pick: Array = shots
	if shots.size() > per:
		pick = []
		for i in per:
			pick.append(shots[roundi(float(i * (shots.size() - 1)) / (per - 1))])
	var crop := Rect2i(250, 60, 780, 580)
	var cols := 3
	var rows := ceili(pick.size() / float(cols))
	var sheet := Image.create(cols * crop.size.x, rows * crop.size.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(0x14, 0x10, 0x0c))
	for i in pick.size():
		var img := Image.load_from_file(ProjectSettings.globalize_path(pick[i]))
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, crop, Vector2i((i % cols) * crop.size.x, (i / cols) * crop.size.y))
	sheet.save_png(ProjectSettings.globalize_path(OUT + "sheets/%s.png" % name))
