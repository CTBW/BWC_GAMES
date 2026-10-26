## The Meridius Workspace's height chart (workspace/2026-10-20_meridius/unit-heights.html):
## every sandbox unit (roster.gd) in its idle at the first frame, from the front and
## from its right side, drawn by an orthographic camera at PX_PER_M in the game's toon
## look, and measured from the drawing's opaque pixels: with its gear, and its body
## alone (the held weapons and shields hidden, UNITS' `gear`). The footman wears his
## squad's dress (squad_looks), as in the sandbox's squad.
## Writes the cut-out pictures (WebP) and units.js (window.UNIT_HEIGHTS) to the tab's
## folder, unit-heights/. Needs a window (no --headless):
##   tools/godot.sh --path . --audio-driver Dummy -s res://tests/visual/unit_heights.gd
extends SceneTree

const Roster = preload("res://prototypes/sandbox3d/scripts/roster.gd")
const Unit3D = preload("res://prototypes/sandbox3d/scripts/unit3d.gd")
const Squad3D = preload("res://prototypes/sandbox3d/scripts/squad3d.gd")
const Sandbox = preload("res://prototypes/sandbox3d/scripts/sandbox3d.gd")
const LOOKS := "res://prototypes/squad_looks/scripts/"
const OUT := "res://../../../../workspace/2026-10-20_meridius/unit-heights/"
const PX_PER_M := 400.0
## 5 m across and 3.6 m high, the ground GROUND_M above the bottom edge.
const VIEW := Vector2i(2000, 1440)
const GROUND_M := 0.2
## The ink line, as thin at this scale as the game's 2 px at its usual zoom looks.
const OUTLINE_M := 0.007
const MARGIN_PX := 10
## Charted in this order; `gear`: the names of its held gear's meshes (globs, as
## String.match), `squad`: its squad in Roster.SQUADS (its drill's file spacing and
## men's sizes).
const UNITS := [
	{"id": "footman", "gear": ["Shield", "Sword"], "squad": "footman"},
	{"id": "spearman", "gear": ["Spear"], "squad": "spearman"},
	{"id": "crossbowman", "gear": ["crossbowman_crossbow", "crossbowman_bolt"], "squad": "crossbowman"},
	{"id": "mage", "gear": ["Staff_*"], "squad": "mage"},
	{"id": "wolf_scout", "gear": ["WolfScout_Dagger_*"], "squad": "wolf_scout"},
	{"id": "wolf_scout_2", "gear": ["WolfScout_Dagger_*"], "squad": "wolf_scout_2"},
	{"id": "succubus", "gear": ["Whip*"], "squad": "succubus"},
	{"id": "goblin_rabble_knife", "gear": ["Knife", "ShieldBarrel*"], "squad": "goblin_rabble"},
	{"id": "goblin_archer", "gear": ["Bow", "Arrow"], "squad": "goblin_archer"},
	{"id": "goblin_spearman", "gear": ["Spear"], "squad": "goblin_spearman"},
	{"id": "orc_brute", "gear": ["Club*"], "squad": "orc_brute"},
]
## Camera and key light per view. The camera looks at the unit (it faces +Z) from
## `cam`; the light comes from the picture's upper left and a little in front.
const VIEWS := {
	"front": {"cam": Vector3(0, 0, 10), "light": Vector3(-0.6, 0.9, 1.0)},
	"side": {"cam": Vector3(-10, 0, 0), "light": Vector3(-1.0, 0.9, -0.6)},
}

var vp: SubViewport
var cam: Camera3D
var sun: DirectionalLight3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(640, 360)
	_build()
	var out := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(out.path_join("img"))
	var have := {}
	for p in Roster.available():
		have[p.id] = p
	var squads := {}
	for s in Roster.SQUADS:
		squads[s.id] = s
	var rows := []
	for spec in UNITS:
		if not have.has(spec.id):
			print("HEIGHTS skipped ", spec.id, ": not on disk")
			continue
		var p: Dictionary = have[spec.id]
		var u := _unit(p)
		vp.add_child(u)
		await process_frame
		_freeze(u)
		var row := {"id": p.id, "title": p.title, "faction": p.faction, "scale": float(p.get("scale", 1.0)),
			"height_m": u.height_m(), "idle": _idle(u)}
		var s: Dictionary = squads.get(spec.squad, {})
		var d: Dictionary = Squad3D.drill_for(String(s.get("drill", spec.squad)))
		row["squad"] = {"title": s.get("title", ""), "size": s.get("size", 1), "file_m": d.file, "rank_m": d.rank,
			"scale_range": [d.size.x, d.size.y]}
		var gear := _gear(u, spec.gear)
		row["gear_meshes"] = gear.map(func(mi): return String(mi.name))
		for view in VIEWS:
			_aim(VIEWS[view])
			u.set_look("toon", true)
			u.set_outline_width(OUTLINE_M)
			var full := await _grab()
			_show(gear, false)
			var bare := await _grab()
			_show(gear, true)
			u.set_look("flat", false)
			var full_box := _box(await _grab(), "%s %s with gear" % [p.id, view])
			_show(gear, false)
			var body_box := _box(await _grab(), "%s %s body" % [p.id, view])
			_show(gear, true)
			row[view] = {
				"full": full_box, "body": body_box,
				"img": _save(full, out, "%s_%s.webp" % [p.id, view]),
				"img_body": _save(bare, out, "%s_%s_body.webp" % [p.id, view]),
			}
		print("HEIGHTS %s: body %.3f m tall, %.3f m wide, %.3f m deep" % [p.id,
			row.front.body.top, row.front.body.right - row.front.body.left, row.side.body.right - row.side.body.left])
		rows.append(row)
		u.queue_free()
		await process_frame
	var cos_e := cos(deg_to_rad(Sandbox.ELEVATION))
	var fm_h := float(JSON.parse_string(FileAccess.get_file_as_string(Sandbox.FOOTMAN_META)).get("height_m", 1.7))
	var ppu := Sandbox.SOLDIER_PX / (fm_h * cos_e)
	var data := {
		"captured": Time.get_date_string_from_system(), "px_per_m": PX_PER_M,
		"game": {"ppu": ppu, "elevation_deg": Sandbox.ELEVATION, "tile_m": Sandbox.TILE_PX / (sqrt(2.0) * ppu),
			"soldier_px": Sandbox.SOLDIER_PX, "outline_px": Sandbox.OUTLINE_PX},
		"units": rows,
	}
	var f := FileAccess.open(out.path_join("units.js"), FileAccess.WRITE)
	f.store_string("// Written by projects/meridius/source/godot/tests/visual/unit_heights.gd. Do not edit.\n")
	f.store_string("window.UNIT_HEIGHTS = " + JSON.stringify(data, "  ") + ";\n")
	f.close()
	print("HEIGHTS wrote ", rows.size(), " units to ", out)
	quit()


func _build() -> void:
	vp = SubViewport.new()
	vp.size = VIEW
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 2.0
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Sandbox.DAY.ambient_color
	env.ambient_light_energy = Sandbox.DAY.ambient
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Sandbox.DAY.sun_color
	sun.light_energy = Sandbox.DAY.sun
	vp.add_child(sun)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = VIEW.y / PX_PER_M
	cam.near = 0.1
	cam.far = 40.0
	vp.add_child(cam)
	cam.make_current()


## The sandbox's unit for profile `p`; the footman in his squad's dress (sandbox3d.gd).
func _unit(p: Dictionary) -> Node3D:
	if p.id == "footman" and ResourceLoader.exists(LOOKS + "dressed_footman.gd"):
		var squad_look: Script = load(LOOKS + "squad_look.gd")
		var livery: Dictionary = squad_look.get_script_constant_map().LIVERIES[Sandbox.SQUAD_LIVERY]
		var u: Node3D = load(LOOKS + "dressed_footman.gd").new()
		u.setup(p)
		# Man 1: a man of the line, not the captain in his winged helmet.
		u.look_spec = squad_look.squad(6, 1, livery, Sandbox.SQUAD_KIT)[1]
		return u
	var unit := Unit3D.new()
	unit.setup(p)
	return unit


func _idle(u: Node3D) -> String:
	return u.idle_clip() if u.has_method("idle_clip") else "idle"


## Holds the idle's first frame: no clock, no idle variants, no steering.
func _freeze(u: Node3D) -> void:
	u.set_process(false)
	u.set_physics_process(false)
	var clip := _idle(u)
	var anim: String = u.clips[clip].anim if u.get("clips") is Dictionary and u.clips.has(clip) else clip
	u.player.play(anim, 0.0)
	u.player.seek(0.0, true)
	u.player.speed_scale = 0.0


func _gear(u: Node3D, parts: Array) -> Array:
	var out := []
	for mi in u.find_children("*", "MeshInstance3D", true, false):
		for part in parts:
			if String(mi.name).match(part):
				out.append(mi)
				break
	return out


func _show(meshes: Array, on: bool) -> void:
	for mi in meshes:
		mi.visible = on


func _aim(v: Dictionary) -> void:
	var at := Vector3(0, VIEW.y / PX_PER_M * 0.5 - GROUND_M, 0)
	cam.look_at_from_position(at + v.cam, at)
	sun.look_at_from_position(v.light, Vector3.ZERO)


func _grab() -> Image:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()


## The opaque pixels' extent in metres: top and bottom above the ground, left and
## right of the unit's centre as the picture shows it.
func _box(img: Image, what: String) -> Dictionary:
	var r := img.get_used_rect()
	if r.position.x <= 0 or r.position.y <= 0 or r.end.x >= VIEW.x or r.end.y >= VIEW.y:
		push_warning("HEIGHTS %s touches the picture's edge: %s" % [what, r])
	var gy := VIEW.y - GROUND_M * PX_PER_M
	var cx := VIEW.x * 0.5
	return {"top": snappedf((gy - r.position.y) / PX_PER_M, 0.001), "bottom": snappedf((gy - r.end.y) / PX_PER_M, 0.001),
		"left": snappedf((r.position.x - cx) / PX_PER_M, 0.001), "right": snappedf((r.end.x - cx) / PX_PER_M, 0.001)}


## Cuts the picture to its opaque pixels and a margin and saves it; returns its
## file and where it stands, in metres, as the box above.
func _save(img: Image, dir: String, file: String) -> Dictionary:
	var r := img.get_used_rect().grow(MARGIN_PX).intersection(Rect2i(Vector2i.ZERO, VIEW))
	var cut := img.get_region(r)
	cut.save_webp(dir.path_join("img").path_join(file), true, 0.9)
	var gy := VIEW.y - GROUND_M * PX_PER_M
	var cx := VIEW.x * 0.5
	return {"file": "img/" + file, "px": [r.size.x, r.size.y],
		"top": (gy - r.position.y) / PX_PER_M, "left": (r.position.x - cx) / PX_PER_M,
		"w": r.size.x / PX_PER_M, "h": r.size.y / PX_PER_M}
