## The 3D battle's shadows on Ashby farm, painted and cast by the sun
## (battle3d.gd `sun_shadows`): the battle at its deployment shown twice from
## the same views, once with the paintings' own shadows and once with the
## sun's, without the fog of war; then each one's frame rate over the field.
##
##   tools/godot.sh --path . --resolution 1920x1080 -s res://tests/visual/battle3d_shadows.gd
## Shots: tests/visual/out/battle3d_shadows/<view>_painted.png, <view>_sun.png.
extends SceneTree

const Battlefields = preload("res://scripts/rules/battlefields.gd")
const Setup = preload("res://scripts/rules/setup.gd")
const Battle = preload("res://scripts/rules/battle.gd")
const Soldier = preload("res://scripts/meta/soldier.gd")
const Rng = preload("res://scripts/core/rng.gd")
const Battle3D = preload("res://scripts/render/battle3d.gd")

const OUT := "res://tests/visual/out/battle3d_shadows/"
## Each view: the grid point looked at and the zoom.
const VIEWS := {
	"farm": [Vector2(14.0, 11.5), 1.0],
	"company": [Vector2(13.0, 19.5), 1.6],
	"woods": [Vector2(5.0, 6.0), 1.0],
	"field": [Vector2(14.0, 13.0), 0.5],
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_run.call_deferred()


func _battle() -> RefCounted:
	var n := [0]
	var next_id := func() -> String:
		n[0] += 1
		return "s%d" % n[0]
	var army := []
	for t in ["footman", "spearman", "crossbowman", "footman", "battle_mage"]:
		army.append(Soldier.soldier_to_unit(Soldier.new_soldier(Rng.new(40 + army.size()), t, 1, next_id, 0)))
	var roll: Dictionary = Setup.roll_encounter("brute_vanguard", Rng.new(3), 1)
	roll.waves = []
	return Battle.new(Setup.build_battle(roll, army, {"title": "Ashby farm", "map": Battlefields.battle_map("ashby")}))


func _run() -> void:
	for mode in ["painted", "sun"]:
		var v = Battle3D.new()
		v.sun_shadows = mode == "sun"
		v.setup(_battle())
		root.add_child(v)
		await v.field.wait_baked()
		# The whole field in sight: no fog of war.
		v.field.set_shared("fog_on", false)
		for name in VIEWS:
			var at: Vector2 = VIEWS[name][0]
			v.focus = v.field.on_ground(at)
			v.zoom = VIEWS[name][1]
			v._zoom_goal = v.zoom
			v._place_camera()
			v._apply_look()
			for i in 20:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := OUT + "%s_%s.png" % [name, mode]
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
			print("shot ", path)
		# Frames over three seconds over the whole field, in the battle's view.
		v.focus = v.field.on_ground(Vector2(14.0, 13.0))
		v.zoom = 0.8
		v._zoom_goal = v.zoom
		var t0 := Time.get_ticks_usec()
		var n := 0
		var slow := 0.0
		while Time.get_ticks_usec() - t0 < 3000000:
			var t1 := Time.get_ticks_usec()
			await process_frame
			slow = maxf(slow, (Time.get_ticks_usec() - t1) / 1000.0)
			n += 1
		print("%s: %.1f fps, slowest frame %.1f ms" % [mode, n / 3.0, slow])
		v.queue_free()
		await process_frame
		await process_frame
	quit(0)
