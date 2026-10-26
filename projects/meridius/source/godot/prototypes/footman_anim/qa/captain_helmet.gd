## The captain's winged helmet on a squad's captain in the squad looks lab
## (prototypes/squad_looks, as it dresses him): at the game's zooms and
## facings, a turntable of his head through the game's camera, the lab's other
## looks, and a swing. Checks that the helmets came in with their own
## materials (the lab outlines those marked `outline`: not the feathers).
##   tools/godot.sh --path . --resolution 1280x800 --audio-driver Dummy --fixed-fps 30 \
##     -s res://prototypes/footman_anim/qa/captain_helmet.gd [-- only=<prefix>]
## The lab puts the men's barbute (no wings, the trim blue) on every other
## man; it is checked on each of them and one of them is turned round too.
## Writes tests/visual/out/captain_helmet/<shot>.png
extends SceneTree

const MATS := ["res://prototypes/footman_anim/art3d/captain_helmet_gold.tres",
	"res://prototypes/footman_anim/art3d/captain_helmet_silver.tres",
	"res://prototypes/footman_anim/art3d/captain_helmet_gold_feather.tres",
	"res://prototypes/footman_anim/art3d/captain_helmet_silver_feather.tres",
	"res://prototypes/footman_anim/art3d/captain_helmet_dark.tres"]
const MEN_MATS := ["res://prototypes/footman_anim/art3d/captain_helmet_silver.tres",
	"res://prototypes/footman_anim/art3d/footman_helmet_blue.tres",
	"res://prototypes/footman_anim/art3d/captain_helmet_dark.tres"]

var lab: Node3D
var cap: Node3D
var out := ""
var only := ""


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String, zoom: float, focus: Vector3, wait := 4) -> void:
	if only != "" and not name.begins_with(only):
		return
	lab._zoom_goal = zoom
	lab.zoom = zoom
	lab.focus = focus
	lab._apply_look()
	await _frames(wait)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("CAPTURE ", name)


## His head at the moment: the Head bone, a little up to the helmet's middle.
func _head(u: Node3D = cap) -> Vector3:
	var att: Node3D = u.get_meta("head_att")
	return att.global_position + Vector3(0, 0.1, 0)


func _alone(on: bool, who: Node3D = cap) -> void:
	for u in lab._all_men():
		if u != who:
			u.visible = not on


func _helmet(u: Node3D = cap) -> Node3D:
	if not u.has_meta("head_att"):
		return null
	return u.get_meta("head_att").get_node_or_null("Rest/Helmet")


func _check(u: Node3D = cap, want: Array = MATS) -> bool:
	var helm := _helmet(u)
	if helm == null:
		push_error("CAPTAIN_HELMET no Rest/Helmet under %s's head" % u.name)
		return false
	var mats := {}
	var tris := 0
	for mi in helm.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			mats[mi.mesh.surface_get_material(s).resource_path] = true
			tris += mi.mesh.surface_get_array_index_len(s) / 3
	print("CAPTAIN_HELMET materials %s, %d tris, root %s" % [str(mats.keys()), tris, str(helm.transform)])
	return mats.size() == want.size() and want.all(func(p): return mats.has(p))


## Every man but the squads' captains.
func _men() -> Array:
	var out := []
	for sq in lab.squads:
		var them: Array = sq.get("men", [])
		out.append_array(them.slice(1))
	return out


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.trim_prefix("only=")
	out = ProjectSettings.globalize_path("res://tests/visual/out/captain_helmet")
	DirAccess.make_dir_recursive_absolute(out)
	lab = load("res://prototypes/squad_looks/scenes/looks_lab.tscn").instantiate()
	root.add_child(lab)
	await _frames(3)
	# The footman's export is kept out of Git: the lab dresses no one without it.
	if lab.squads.is_empty():
		push_warning("CAPTAIN_HELMET the lab has no men (is footman.glb missing?); nothing to capture.")
		print("CAPTAIN_HELMET_OK false")
		quit(1)
		return
	lab.ui.visible = false
	lab._capturing = true
	cap = lab.squads[0].men[0]
	await _frames(10)
	var men := _men()
	var ok := _check() and not men.is_empty() and men.all(func(u): return _check(u, MEN_MATS))
	print("CAPTAIN_HELMET_OK ", ok)
	var body := cap.global_position + Vector3(0, 1.0, 0)
	# The game's zooms, every man there.
	for z in [1.0, 2.0, 3.2, 6.5]:
		await _shot("zoom_%s" % str(z).replace(".", "_"), z, body)
	for f in ["SE", "SW"]:
		lab._set_facing(f)
		await _frames(2)
		await _shot("facing_%s_3x" % f, 3.2, cap.global_position + Vector3(0, 1.0, 0), 12)
	lab._set_facing("Camera")
	await _frames(2)
	# His head alone, turned round under the game's camera.
	_alone(true)
	var yaw0: float = cap.rotation.y
	for k in 8:
		cap.rotation.y = yaw0 + k * PI / 4.0
		await _frames(2)
		await _shot("turn_%d" % (k * 45), 14.0, _head())
	cap.rotation.y = yaw0
	_alone(false)
	# One of his men, turned round the same way.
	var man: Node3D = men[0]
	_alone(true, man)
	var yaw1: float = man.rotation.y
	for k in 8:
		man.rotation.y = yaw1 + k * PI / 4.0
		await _frames(2)
		await _shot("man_turn_%d" % (k * 45), 14.0, _head(man))
	man.rotation.y = yaw1
	_alone(false, man)
	_alone(true)
	for m in ["flat", "pbr", "toon"]:
		lab._set_look(m)
		await _shot("look_%s" % m, 10.0, _head())
	# A swing, his wings past the blade.
	await _frames(4)
	cap.attack(null, "attack")
	for t in [8, 6, 6, 6, 6]:
		await _frames(t)
		await _shot("swing_%d" % Engine.get_process_frames(), 6.5, cap.global_position + Vector3(0, 1.1, 0), 0)
	_alone(false)
	quit()
