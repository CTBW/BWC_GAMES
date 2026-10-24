## Windowed captures of the squad skills in the running game (scenes/main.tscn,
## the App store driving the flow): the ability bar of footmen (promoted, so
## all four keys), spearmen, crossbowmen and the Border Collie Royal Guard,
## the tooltips of Square, Defend and Lick Wounds (disabled beside an enemy or
## not), and the forecast of a Charge aimed at an enemy.
##
##   tools/godot.sh --path . --resolution 1920x1080 -s res://tests/visual/capture_skills.gd [-- names…]
##
## Writes tests/visual/out/skills_<name>.png and skills_<name>_bar.png (the
## bottom of the screen). Names (default: all): bar_footman, bar_spearman,
## bar_crossbowman, bar_collie_guard, tip_square, tip_defend, tip_lick, charge_forecast,
## use_growl, stances, tip_howl, use_howl.
extends SceneTree

const OUT := "res://tests/visual/out/"
const H = preload("res://scripts/ui/hud_common.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const Iso = preload("res://scripts/render/iso.gd")
const Soldier = preload("res://scripts/meta/soldier.gd")

const ARMY := ["footman", "spearman", "crossbowman", "collie_guard", "footman", "crossbowman"]

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
	img.save_png(ProjectSettings.globalize_path(OUT + "skills_%s.png" % name))
	var h := mini(380, img.get_height())
	img.get_region(Rect2i(0, img.get_height() - h, img.get_width(), h)).save_png(ProjectSettings.globalize_path(OUT + "skills_%s_bar.png" % name))
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


func _run() -> void:
	app = root.get_node("App")
	app.save_path = "user://capture_skills_save.json"
	app.mark_manual_seen()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 1200:
		await process_frame
		if app.screen == "title":
			break
	app.new_game(4)
	await _frames(20)
	app.debug_test_battle("raiding_party", {"seed": 11, "army": ARMY, "level": 3})
	await _frames(60)
	var bv = app.battle_view
	var b = bv.b
	# The footmen are promoted veterans: Shield Bash on key 4.
	for u in b.units:
		if u.typeId == "footman" and not u.abilities.has("shieldbash"):
			u.abilities.append("shieldbash")
	_press("Begin")
	await _wait_idle(bv)
	await _frames(10)

	for t in ["footman", "spearman", "crossbowman", "collie_guard"]:
		var u := _of_type(b, t)
		if u.is_empty():
			continue
		bv.select(u.uid)
		await _frames(15)
		await _shot("bar_" + t)

	var sp := _of_type(b, "spearman")
	bv.select(sp.uid)
	await _frames(10)
	await _tip_on("Ability_square")
	await _shot("tip_square")
	_tip_off("Ability_square")

	var c := _of_type(b, "collie_guard")
	bv.select(c.uid)
	await _frames(10)
	await _tip_on("Ability_defend")
	await _shot("tip_defend")
	_tip_off("Ability_defend")
	# Lick Wounds: wounded hounds, then an enemy set down beside them (disabled, with the reason).
	c.hp = c.hp - 30
	var foe: Dictionary = b.active("enemy")[0]
	var spot: Variant = null
	for d in Grid.DIRS:
		var p := {"x": int(c.x) + d.x, "y": int(c.y) + d.y}
		if Grid.tile_passable(b.map, p.x, p.y) and Grid.unit_at(b.units, p.x, p.y) == null:
			spot = p
			break
	var home := {"x": foe.x, "y": foe.y}
	if spot != null:
		foe.x = spot.x
		foe.y = spot.y
		bv._sync_views()
	bv.select(c.uid)
	await _frames(10)
	await _tip_on("Ability_lick_wounds")
	await _shot("tip_lick")
	_tip_off("Ability_lick_wounds")
	foe.x = home.x
	foe.y = home.y
	bv._sync_views()

	# A Charge aimed at the nearest enemy the hounds can run at.
	bv.select(c.uid)
	await _frames(5)
	_press("Ability_hound_charge")
	await _frames(5)
	var best: Variant = null
	var bd := 1e9
	for e in b.active("enemy"):
		var d := Grid.dist(c, e)
		if d < bd:
			bd = d
			best = e
	if best != null:
		var p: Variant = _unit_point(bv, best.uid)
		if p != null:
			bv.pointer_move(p)
			await _frames(10)
	await _shot("charge_forecast")
	bv.set_ability(null)

	# The skills used: Growl (the shout and the cowed), Square and Defend (stance tags).
	var foe2: Dictionary = b.active("enemy")[0]
	for d in Grid.DIRS:
		var p := {"x": int(c.x) + d.x * 2, "y": int(c.y) + d.y * 2}
		if Grid.tile_passable(b.map, p.x, p.y) and Grid.unit_at(b.units, p.x, p.y) == null:
			foe2.x = p.x
			foe2.y = p.y
			bv._sync_views()
			break
	bv.select(c.uid)
	await _frames(5)
	_press("Ability_growl")
	await _frames(20)
	await _shot("use_growl")
	await _wait_idle(bv)
	bv.select(_of_type(b, "spearman").uid)
	await _frames(5)
	_press("Ability_square")
	await _wait_idle(bv)
	var f := _of_type(b, "footman")
	bv.select(f.uid)
	await _frames(5)
	_press("Ability_defend")
	await _wait_idle(bv)
	bv.select(null)
	await _frames(10)
	await _shot("stances")

	# Promoted veterans: Howl in Growl's place on key 1.
	c.abilities = Soldier.kit("collie_guard", true)
	bv.select(c.uid)
	await _frames(10)
	await _tip_on("Ability_howl")
	await _shot("tip_howl")
	_tip_off("Ability_howl")
	# Howl's wider rings (3 tiles to Growl's 2), with the hounds free to act again.
	c.hasActed = false
	bv.select(c.uid)
	await _frames(5)
	_press("Ability_howl")
	await _frames(20)
	await _shot("use_howl")
	await _wait_idle(bv)
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


## A screen point over a squad that picks it (as capture_magic.gd).
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
