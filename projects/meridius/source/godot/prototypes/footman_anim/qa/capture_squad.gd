## Squad capture for the reference pack: the six-man squad attacking the dummy,
## marching into a tile, or standing in formation, stepped at 1/30 s into a
## fixed SubViewport (effects and shake included).
##   tools/godot.sh --path . --audio-driver Dummy -s res://prototypes/footman_anim/qa/capture_squad.gd -- scenario=attack facing=0 secs=4 [twos=1]
extends SceneTree

const Squad = preload("res://prototypes/footman_anim/scripts/squad.gd")
const Dummy = preload("res://prototypes/footman_anim/scripts/dummy.gd")
const FX = preload("res://prototypes/footman_anim/scripts/fx.gd")
const Ground = preload("res://prototypes/footman_anim/scripts/ground.gd")
const Formation = preload("res://prototypes/footman_anim/scripts/formation.gd")
const Footman = preload("res://prototypes/footman_anim/scripts/footman.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {"scenario": "attack", "facing": "0", "secs": "4", "twos": "0", "w": "640", "h": "420", "zoom": "2.6",
		"out": "res://tests/visual/out/footman_proto/squad"}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var f := int(args.facing)
	var vp := SubViewport.new()
	vp.size = Vector2i(int(args.w), int(args.h))
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	root.add_child(vp)
	var world := Node2D.new()
	vp.add_child(world)
	var ground := Ground.new()
	ground.radius = 4
	world.add_child(ground)
	var fx_g := FX.new()
	world.add_child(fx_g)
	var units := Node2D.new()
	units.y_sort_enabled = true
	world.add_child(units)
	var fx := FX.new()
	world.add_child(fx)
	var cam := Camera2D.new()
	cam.zoom = Vector2.ONE * float(args.zoom)
	world.add_child(cam)
	cam.make_current()
	var available := []
	for k in Footman.FACING_KEYS:
		if FileAccess.file_exists("res://prototypes/footman_anim/motion/%s.tres" % k):
			available.append(k)
	var dirv: Vector2 = Formation.GRID_DIRS[f]
	var squad := Squad.new()
	squad.y_sort_enabled = true
	units.add_child(squad)
	squad.fx = fx
	squad.sound = false
	var scenario: String = args.scenario
	squad.spawn(available, -dirv * 2.0 if scenario == "march" else Vector2.ZERO, f, 20261023)
	var twos: bool = args.twos == "1"
	for m in squad.members:
		m.set_process(false)
		m.on_twos = twos
		m.stepped.connect(func(so, side, at): if so.state in ["walk", "step_lane"]: fx_g.dust(fx_g.to_local(at), Footman.screen_dir(so.facing)))
	squad.set_process(false)
	fx.set_process(false)
	fx_g.set_process(false)
	var dummy: Node2D = null
	cam.position = Vector2(0, -40)
	if scenario == "attack":
		dummy = Dummy.new()
		dummy.position = Formation.iso(dirv)
		dummy.fx = fx
		units.add_child(dummy)
		dummy.set_process(false)
		squad.attack(dummy, true)
		cam.position = Formation.iso(dirv * 0.5) + Vector2(0, -40)
	elif scenario == "march":
		cam.position = Formation.iso(-dirv * 0.9) + Vector2(0, -40)
	var name := "%s_%s%s" % [scenario, Footman.FACING_KEYS[f], "_twos" if twos else ""]
	var dir := ProjectSettings.globalize_path(args.out + "/" + name)
	DirAccess.make_dir_recursive_absolute(dir)
	var n := int(float(args.secs) * 30.0)
	var base_cam := cam.position
	var marched := false
	for i in n:
		var dt := 1.0 / 30.0
		if scenario == "march" and not marched and i >= 12:
			marched = true
			squad.march_to(Vector2.ZERO)
		for k in 2:
			for m in squad.members:
				m._process(dt * 0.5)
			squad._process(dt * 0.5)
			if dummy:
				dummy._process(dt * 0.5)
			fx._process(dt * 0.5)
			fx_g._process(dt * 0.5)
			await process_frame
		cam.position = base_cam + fx.shake_offset(dt)
		await process_frame
		vp.get_texture().get_image().save_png(dir + "/%04d.png" % i)
	print("SQUAD ", name, " ", n, " blows ", squad.damage_ticks)
	quit()
