## Windowed captures of the magic-and-machines interface in the running game
## (scenes/main.tscn, the App store driving the flow): the Barracks with a
## specialist recruit, the roster detail of mages, a ballista and a mangonel,
## the field manual's Magic & Machines page, and a battle with mages and both
## machines against the shamans: spell buttons, the spell forecast over an
## enemy for Chain Lightning (chosen by its button, aimed by the pointer) and
## for the mangonel's stone (aimed by hovering an enemy), the casts, the
## conditions on squads' cards and the enemy turn. For comparison with the
## original's captures in projects/meridius/review/magic-ui-v2/ (and
## magic-ui-v1/barracks.png), made by ../game/scripts/magicui.mjs.
##
##   tools/godot.sh --path . --resolution 1920x1080 -s res://tests/visual/capture_magic.gd [-- names…]
##
## Writes tests/visual/out/magic_<name>.png. Names (default: all): barracks,
## detail_mage, detail_ballista, detail_mangonel, manual, deploy, mage_panel,
## mage_tooltip, mage_forecast, mage_cast, mangonel_forecast, mangonel_cast, unit_panel,
## enemy_turn, after_enemy_turn, mangonel_moved, conditions, unit_info, chilled_info.
extends SceneTree

const OUT := "res://tests/visual/out/"
const DB = preload("res://scripts/data/db.gd")
const Rng = preload("res://scripts/core/rng.gd")
const Iso = preload("res://scripts/render/iso.gd")
const Soldier = preload("res://scripts/meta/soldier.gd")
const H = preload("res://scripts/ui/hud_common.gd")

const ARMY := ["footman", "spearman", "battle_mage", "ballista", "mangonel", "crossbowman"]

var app: Node
var main: Node
var only: PackedStringArray


func _initialize() -> void:
	only = OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_run.call_deferred()


func _want(name: String) -> bool:
	return only.is_empty() or only.has(name)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	if not _want(name):
		return
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + "magic_%s.png" % name))
	print("captured ", name, " ", img.get_size())


func _hud() -> Node:
	return main.screen_host.get_child(0) if main.screen_host.get_child_count() > 0 else null


func _press(text: String) -> bool:
	var h := _hud()
	for b in H.buttons(h):
		if not b.is_queued_for_deletion() and (str(b.name) == text or H.button_text(b).contains(text)) and not b.disabled:
			b.pressed.emit()
			return true
	print("no button ", text)
	return false


func _specialist(t: String) -> bool:
	var def: Dictionary = DB.UNIT_TYPES[t]
	return def.has("crew") or (def.get("tags", []) as Array).has("caster")


func _run() -> void:
	app = root.get_node("App")
	app.save_path = "user://capture_magic_save.json"
	app.mark_manual_seen()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	# The boot (loading screen, warm-up) ends on the title screen.
	for i in 1200:
		await process_frame
		if app.screen == "title":
			break
	app.new_game(4)
	await _frames(20)
	var g: Dictionary = app.game

	# The Barracks: this muster's specialist is a squad of battle mages.
	var mage_recruit: Dictionary = Soldier.new_soldier(Rng.new(4), "battle_mage", 1, func(): return "cap_mage", 0)
	g.recruits = g.recruits.filter(func(r): return not _specialist(r.typeId))
	g.recruits.append(mage_recruit)
	app.open_panel("barracks")
	await _frames(20)
	await _shot("barracks")
	app.open_panel(null)
	await _frames(5)

	# The roster detail of the specialists.
	for t in ["battle_mage", "ballista", "mangonel"]:
		var so: Dictionary = Soldier.new_soldier(Rng.new(17), t, 2, func(): return "cap_" + t, 0)
		g.roster.append(so)
		app.open_soldier(so.id)
		await _frames(15)
		await _shot("detail_" + {"battle_mage": "mage", "ballista": "ballista", "mangonel": "mangonel"}[t])
		app.open_soldier(null)
		await _frames(3)
	g.roster = g.roster.filter(func(so): return not str(so.id).begins_with("cap_"))

	# The field manual's new page.
	app.open_manual("magic")
	await _frames(15)
	await _shot("manual")
	app.open_manual(null)
	await _frames(5)

	# A battle with mages and both machines against the shamans.
	app.debug_test_battle("shaman_fire", {"seed": 11, "army": ARMY, "level": 2})
	await _frames(60)
	var bv = app.battle_view
	await _shot("deploy")
	_press("Begin")
	await _wait_idle(bv)
	await _frames(10)
	var b = bv.b

	# 1. The mages: Chain Lightning chosen with its button, forecast on hover, cast with a click.
	var mage := _of_type(b, "battle_mage")
	if mage.is_empty():
		print("no mages")
		quit(1)
		return
	if _target_for(b, mage, "chain_lightning") == null:
		_close_in(bv, mage, "chain_lightning")
		await _wait_idle(bv)
	bv.select(mage.uid)
	await _frames(20)
	await _shot("mage_panel")
	await _tip_on("Ability_chain_lightning")
	await _shot("mage_tooltip")
	_tip_off("Ability_chain_lightning")
	_press("Ability_chain_lightning")
	await _frames(5)
	var t1: Variant = _target_for(b, mage, "chain_lightning")
	if t1 != null:
		await _hover_unit(bv, t1.uid)
		if bv.ui.hover.get("spell") == null:
			print("the view gave no spell preview: setting it by hand")
			bv.ui.hover.spell = b.spell_preview(mage, "chain_lightning", {"x": int(t1.x), "y": int(t1.y)})
			bv.ui.hover.unit = t1.uid
			bv.notify()
		await _frames(8)
		await _shot("mage_forecast")
		var p: Variant = _unit_point(bv, t1.uid)
		if p != null:
			bv.pointer_down(p, 0)
		else:
			b.cast(mage.uid, "chain_lightning", {"x": int(t1.x), "y": int(t1.y)})
			bv.pump()
		await _frames(40)
		await _shot("mage_cast")
		await _wait_idle(bv)
	else:
		print("no lightning target")

	# 2. The mangonel: hover an enemy to aim the stone (no button needed), click to loose.
	var mg := _of_type(b, "mangonel")
	bv.select(mg.uid)
	await _frames(15)
	var t2: Variant = _target_for(b, mg, "hurl_stone")
	if t2 != null:
		await _hover_unit(bv, t2.uid)
		if bv.ui.hover.get("spell") == null:
			print("the view gave no stone preview: setting it by hand")
			bv.ui.hover.spell = b.spell_preview(mg, "hurl_stone", {"x": int(t2.x), "y": int(t2.y)})
			bv.ui.hover.unit = t2.uid
			bv.notify()
		await _frames(8)
		await _shot("mangonel_forecast")
		var p2: Variant = _unit_point(bv, t2.uid)
		if p2 != null:
			bv.pointer_down(p2, 0)
		else:
			b.cast(mg.uid, "hurl_stone", {"x": int(t2.x), "y": int(t2.y)})
			bv.pump()
		await _frames(50)
		await _shot("mangonel_cast")
		await _wait_idle(bv)
	else:
		print("no mangonel target in range")

	# 3. The rest of the company plays itself; the mages' card with spent spells.
	app.debug_player_turn()
	await _wait_idle(bv)
	bv.select(mage.uid)
	bv.pointer_move(Vector2(960, 1000))
	await _frames(15)
	await _shot("unit_panel")

	# 4. The enemy turn with its shamans.
	_press("EndTurn")
	var seen := -1
	for i in 900:
		await process_frame
		if bv.ui.side == "enemy" and seen < 0:
			seen = i
		if seen >= 0 and i - seen >= 90:
			break
	await _shot("enemy_turn")
	await _wait_idle(bv)
	await _frames(20)
	await _shot("after_enemy_turn")

	# A war machine that has moved cannot loose: the reason on its button.
	var mg2 := _of_type(b, "mangonel")
	if not mg2.is_empty():
		for k in b.reachable(mg2):
			var p := {"x": int(k) % 1000, "y": int(k) / 1000}
			if (p.x != mg2.x or p.y != mg2.y) and b.move(mg2.uid, p.x, p.y):
				break
		bv.pump()
		await _wait_idle(bv)
		bv.select(mg2.uid)
		await _frames(10)
		await _tip_on("Ability_hurl_stone")
		await _shot("mangonel_moved")
		_tip_off("Ability_hurl_stone")

	# 5. Conditions: a squad's chips on its card, and a hovered squad's.
	var touched: Variant = null
	for u in b.active():
		if not (u.get("statuses", []) as Array).is_empty():
			touched = u
			if u.faction == "player":
				break
	if touched == null:
		print("no conditions after the enemy turn: laying some on by hand")
		mage.statuses = [{"id": "bleeding", "turns": 2, "power": 6}]
		var foe: Dictionary = b.active("enemy")[0]
		foe.statuses = [{"id": "chilled", "turns": 1}]
		for pair in [[mage, ["bleeding"]], [foe, ["chilled"]]]:
			var vw = bv.views.get(pair[0].uid)
			if vw != null and "statuses" in vw:
				vw.statuses = pair[1]
		touched = foe
		bv.notify()
	var own: Variant = null
	for u in b.active("player"):
		if not (u.get("statuses", []) as Array).is_empty():
			own = u
	if own == null:
		own = mage
		mage.statuses = [{"id": "bleeding", "turns": 2, "power": 6}]
	bv.select(own.uid)
	await _frames(10)
	var foe2: Variant = null
	for u in b.active("enemy"):
		if not (u.get("statuses", []) as Array).is_empty():
			foe2 = u
	if foe2 == null:
		foe2 = b.active("enemy")[0]
		foe2.statuses = [{"id": "chilled", "turns": 1}]
	bv.set_ability(null)
	await _hover_unit(bv, foe2.uid)
	await _frames(10)
	await _shot("conditions")
	await _hover_unit(bv, mage.uid)
	await _frames(10)
	await _shot("unit_info")
	# Nothing selected: the chilled enemy's own card.
	bv.select(null)
	await _hover_unit(bv, foe2.uid)
	await _frames(10)
	await _shot("chilled_info")
	print("done")
	quit(0)


func _hud_button(name: String) -> Control:
	var h := _hud()
	for b in H.buttons(h):
		if str(b.name) == name and not b.is_queued_for_deletion():
			return b
	print("no button ", name)
	return null


## Shows a HUD button's tooltip as the pointer over it does.
func _tip_on(name: String) -> void:
	var btn := _hud_button(name)
	if btn == null:
		return
	var e := InputEventMouseMotion.new()
	e.position = btn.size * 0.5
	e.global_position = btn.get_global_rect().get_center()
	btn.gui_input.emit(e)
	await _frames(3)


func _tip_off(name: String) -> void:
	var btn := _hud_button(name)
	if btn != null:
		btn.mouse_exited.emit()


func _wait_idle(bv) -> void:
	for i in 3000:
		await process_frame
		if not bv.busy():
			return


func _of_type(b, t: String) -> Dictionary:
	for u in b.active("player"):
		if u.typeId == t:
			return u
	return {}


## The enemy a spell or a stone could reach from the squad, nearest first.
func _target_for(b, u: Dictionary, spell: String) -> Variant:
	var best: Variant = null
	var bd := 1e9
	for t in b.living():
		if t.faction != "enemy" or not b.spell_preview(u, spell, {"x": int(t.x), "y": int(t.y)}).legal:
			continue
		var d := Vector2(t.x - u.x, t.y - u.y).length()
		if d < bd:
			bd = d
			best = t
	return best


## Walk the squad toward the enemy until the spell can reach it (moves only).
func _close_in(bv, u: Dictionary, spell: String) -> void:
	var b = bv.b
	var foes: Array = b.living().filter(func(t): return t.faction == "enemy")
	var best: Variant = null
	var bd := -1.0
	for k in b.reachable(u):
		var p := {"x": int(k) % 1000, "y": int(k) / 1000}
		var ok := false
		var near := 1e9
		for t in foes:
			if b.spell_preview(u, spell, {"x": int(t.x), "y": int(t.y)}, {"from": p, "movedTiles": 0}).legal:
				ok = true
			near = minf(near, Vector2(t.x - p.x, t.y - p.y).length())
		if ok and near > bd:
			bd = near
			best = p
	if best != null and (best.x != u.x or best.y != u.y):
		b.move(u.uid, best.x, best.y)
	bv.pump()


## A view-local point on the squad's figures that the view resolves to it.
func _unit_point(bv, uid: String) -> Variant:
	var v = bv.views.get(uid)
	if v == null:
		return null
	var z: float = bv.cam.zoom
	var base: Vector2 = bv.cam.world_to_screen(Iso.iso_x(v.x, v.y), Iso.iso_y(v.x, v.y, v.h), bv._w, bv._h)
	for oy in [-24, -36, -12, -48, 0]:
		for ox in [0, -14, 14, -28, 28]:
			var p: Vector2 = base + Vector2(ox, oy) * z
			var rp: Dictionary = bv.resolve_pointer(p.x, p.y)
			if rp.unit != null and rp.unit.uid == uid:
				return p
	return base


## Points at a squad through the view's pointer (as the mouse does).
func _hover_unit(bv, uid: String) -> void:
	var p: Variant = _unit_point(bv, uid)
	if p != null:
		bv.pointer_move(p)
	await _frames(5)
