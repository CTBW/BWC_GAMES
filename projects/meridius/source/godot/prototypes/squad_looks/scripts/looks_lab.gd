## The squad looks lab: four footman squads (six, four, three and two men) on
## the grass through the game's camera, to see how a squad's men are told
## apart (squad_look.gd decides who they are, unit_look.gd dresses them).
## Every part of the variety is a layer to switch off, down to six clones.
##   tools/godot.sh --path . res://prototypes/squad_looks/scenes/looks_lab.tscn
##   ... -- --capture=<dir> [--shots=<prefix>]   review captures, then quit
## (--clean hides the panel and the selection rings.)
## Click a man to select his squad; the panel sets its size, livery, kit and
## shield mark, rerolls its men and gives orders to every squad.
extends Node3D

const DressedFootman := preload("res://prototypes/squad_looks/scripts/dressed_footman.gd")
const SquadLook := preload("res://prototypes/squad_looks/scripts/squad_look.gd")
const UnitLook := preload("res://prototypes/squad_looks/scripts/unit_look.gd")
const Squad3D := preload("res://prototypes/sandbox3d/scripts/squad3d.gd")
const Roster := preload("res://prototypes/sandbox3d/scripts/roster.gd")
const UI := preload("res://scripts/ui/ui.gd")
const GROUND := preload("res://prototypes/footman_anim/shaders/ground3d.gdshader")
const GRASS := preload("res://assets/terrain/grass.webp")

const FOOTMAN_GLB := "res://prototypes/footman_anim/art3d/footman.glb"
const FOOTMAN_META := "res://prototypes/footman_anim/art3d/footman.json"
## The game's camera (prototypes/sandbox3d/scripts/sandbox3d.gd): a soldier 49 px tall at zoom 1, 30 degrees down.
const SOLDIER_PX := 49.0
const ELEVATION := 30.0
const OUTLINE_PX := 2.0
const ZOOM_MIN := 0.6
const ZOOM_MAX := 8.0
## Between the squads' centres, along the screen's width.
const SPACING := 4.6
const KITS := ["militia", "line", "guard"]
## The squads at the start: size, livery, kit, mark (-1: the livery's own), seed.
const START := [
	{"n": 6, "livery": 0, "kit": "line", "mark": 0, "seed": 101},
	{"n": 4, "livery": 0, "kit": "guard", "mark": 1, "seed": 202},
	{"n": 3, "livery": 1, "kit": "militia", "mark": -1, "seed": 303},
	{"n": 2, "livery": 2, "kit": "line", "mark": -1, "seed": 404},
]
## The facings: toward the camera, and the game's own two.
const FACINGS := {"Camera": PI / 4, "SE": PI / 2, "SW": 0.0}

var ppu := 33.0
var zoom := 1.0
var _zoom_goal := 1.0
var focus := Vector3(0, 0.85, 0)
var facing := "Camera"
var look := "toon"
var outline := true
var cam: Camera3D
var sun: DirectionalLight3D
var world: Node3D
var squads: Array = []
var selected := 0
var ui: CanvasLayer
var _profile := {}
var _buttons := {}
var _roster: VBoxContainer
var _status: Label
var _rings: Array = []
var _drag := false
var _capturing := false


func _ready() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	get_viewport().scaling_3d_scale = 2.0
	var fm_meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FOOTMAN_META))
	ppu = SOLDIER_PX / (float(fm_meta.get("height_m", 1.7)) * cos(deg_to_rad(ELEVATION)))
	for q in Roster.available():
		if q.id == "footman":
			_profile = q
	_build_world()
	# The footman's export is kept out of Git: a clean clone has no men to dress.
	if not ResourceLoader.exists(FOOTMAN_GLB):
		push_warning("Squad looks lab: %s is missing (it is not in Git); nothing to show." % FOOTMAN_GLB)
		var l := UI.label("The footman model (%s) is missing: it is kept out of Git." % FOOTMAN_GLB, "SmallLabel", 18, UI.LIGHT)
		l.position = Vector2(32, 32)
		var cl := CanvasLayer.new()
		cl.add_child(l)
		add_child(cl)
		return
	world = Node3D.new()
	world.name = "Squads"
	add_child(world)
	UnitLook.layers = {}
	for s in START:
		squads.append(s.duplicate())
	for i in squads.size():
		_spawn(i)
	_build_ui()
	_apply_look()
	get_window().title = "Meridius - squad looks lab"
	var args := OS.get_cmdline_user_args()
	if args.has("--clean"):
		ui.visible = false
	for arg in args:
		if arg.begins_with("--capture="):
			var only := ""
			for a in args:
				if a.begins_with("--shots="):
					only = a.trim_prefix("--shots=")
			_capture(arg.trim_prefix("--capture="), only)


func _build_world() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.3, 0.38, 0.22)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.86, 0.9, 1.0)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = e
	add_child(we)
	sun = DirectionalLight3D.new()
	# From the screen's upper left, 50 degrees up, as in the sandbox.
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-90), 0)
	sun.light_energy = 0.5
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.55
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	ground.mesh = pm
	var gm := ShaderMaterial.new()
	gm.shader = GROUND
	gm.set_shader_parameter("tile", 128.0 / (sqrt(2.0) * ppu))
	gm.set_shader_parameter("grass_tex", GRASS)
	ground.material_override = gm
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 0.1
	cam.far = 300.0
	add_child(cam)
	cam.make_current()


# --- Squads ----------------------------------------------------------------

## The screen's right along the ground.
func _right() -> Vector3:
	return Vector3(1, 0, -1).normalized()


func _centre(i: int) -> Vector3:
	return _right() * (i - (squads.size() - 1) * 0.5) * SPACING


## Squad i's men as squad_look.gd has them.
func _looks(i: int) -> Array:
	var s: Dictionary = squads[i]
	var mark: Dictionary = SquadLook.MARKS[s.mark] if s.mark >= 0 else {}
	return SquadLook.squad(s.n, s.seed, SquadLook.LIVERIES[s.livery], s.kit, mark)


## Squad i's men anew (after a change of its size).
func _spawn(i: int) -> void:
	var s: Dictionary = squads[i]
	for u in s.get("men", []):
		u.queue_free()
	var looks := _looks(i)
	var men := []
	var rng := RandomNumberGenerator.new()
	rng.seed = s.seed
	for k in s.n:
		var u: Node3D = DressedFootman.new()
		u.setup(_profile)
		u.name = "Squad%dMan%d" % [i + 1, k + 1]
		u.look_spec = looks[k]
		world.add_child(u)
		# His own pace, as in the sandbox's squad.
		u.playback = rng.randf_range(0.95, 1.05)
		men.append(u)
	s.men = men
	_place(i)
	_link()


## Squad i in its ranks, facing the lab's way.
func _place(i: int) -> void:
	var s: Dictionary = squads[i]
	var f: float = FACINGS[facing]
	var pts := Squad3D.slots(_centre(i), f, s.n)
	for k in s.men.size():
		var u: Node3D = s.men[k]
		u.position = pts[k]
		u.rotation.y = f
		u.path.clear()


## Every man glances at his own squad and the squads beside it.
func _link() -> void:
	for i in squads.size():
		var others := []
		for j in [i - 1, i + 1]:
			if j >= 0 and j < squads.size():
				others += squads[j].get("men", [])
		UnitLook.link(squads[i].get("men", []), others)


## Squad i's men in their new looks (same men, new clothes): after a reroll
## or a change of livery, kit or mark.
func _restyle(i: int) -> void:
	var looks := _looks(i)
	var men: Array = squads[i].men
	for k in men.size():
		men[k].look_spec = looks[k]
		UnitLook.restyle(men[k], looks[k], look, outline)
	_apply_look()


func _all_men() -> Array:
	var out := []
	for s in squads:
		out += s.get("men", [])
	return out


func _resize(i: int, d: int) -> void:
	var s: Dictionary = squads[i]
	var n := clampi(s.n + d, 1, 6)
	if n == s.n:
		return
	s.n = n
	_spawn(i)
	_apply_look()
	_refresh()


func _cycle(i: int, what: String) -> void:
	var s: Dictionary = squads[i]
	match what:
		"livery":
			s.livery = (s.livery + 1) % SquadLook.LIVERIES.size()
		"kit":
			s.kit = KITS[(KITS.find(s.kit) + 1) % KITS.size()]
		"mark":
			s.mark = s.mark + 1 if s.mark + 1 < SquadLook.MARKS.size() else -1
		"reroll":
			s.seed = randi()
	_restyle(i)
	_refresh()


# --- Layers, look and orders -------------------------------------------------

func _set_layer(layer: String, on: bool) -> void:
	UnitLook.layers[layer] = on
	for u in _all_men():
		UnitLook.refresh(u)
	_refresh()


func _set_layers(on: bool) -> void:
	for l in UnitLook.LAYERS:
		UnitLook.layers[l] = on
	for u in _all_men():
		UnitLook.refresh(u)
	_refresh()


## Layers on up to and including `last` (in LAYERS' order), the rest off.
func _layers_upto(last: String) -> void:
	var on := true
	for l in UnitLook.LAYERS:
		UnitLook.layers[l] = on
		if l == last:
			on = false
	for u in _all_men():
		UnitLook.refresh(u)
	_refresh()


func _apply_look() -> void:
	var w := OUTLINE_PX / (ppu * zoom)
	for u in _all_men():
		u.set_look(look, outline)
		u.set_outline_width(w)


func _set_look(m: String) -> void:
	look = m
	_apply_look()
	_refresh()


func _set_facing(f: String) -> void:
	facing = f
	for i in squads.size():
		_place(i)
		for u in squads[i].men:
			u.stop()
	_refresh()


func _order(what: String) -> void:
	for u in _all_men():
		match what:
			"idle":
				u.set_block(false)
				u.stance = ""
				if u.is_dead():
					u.revive()
				else:
					u.stop()
			"block":
				if u.is_dead():
					u.revive()
				u.set_block(true)
				u.stance = "block"
			"swing":
				# Not all at once: a squad's men never strike in step.
				get_tree().create_timer(randf() * 0.5).timeout.connect(func(): u.attack(null, "attack" if randf() < 0.65 else "attack_stab"))
			"hit":
				get_tree().create_timer(randf() * 0.4).timeout.connect(func(): u.hit())
			"march":
				var f := Vector3(sin(u.rotation.y), 0, cos(u.rotation.y))
				var home: Vector3 = u.position
				var yaw: float = u.rotation.y
				u.order_move([home + f * 3.0], func(): u.order_move([home], func(): u.face(yaw)))


func _set_zoom(z: float) -> void:
	_zoom_goal = clampf(z, ZOOM_MIN, ZOOM_MAX)


func _select(i: int, frame := false) -> void:
	selected = clampi(i, 0, squads.size() - 1)
	if frame:
		focus = _centre(selected) + Vector3(0, 0.85, 0)
	_refresh()


# --- Panel -------------------------------------------------------------------

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	var side := UI.panel("DarkPanel", [16, 22])
	side.anchor_bottom = 1.0
	side.offset_left = 16
	side.offset_top = 16
	side.offset_right = 16 + 412
	side.offset_bottom = -16
	root.add_child(side)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	var col := UI.vbox(8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	col.add_child(UI.cinzel("SQUAD LOOKS LAB", 22, 700, UI.LIGHT_TITLE))
	col.add_child(_note("One footman model, every man his own. Switch the layers off to see the squads as clones."))
	col.add_child(_head("LAYERS"))
	var grid := UI.grid(2, 6, 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for l in UnitLook.LAYERS:
		var b := _button(UnitLook.LAYER_TITLES[l], func(): _set_layer(l, not UnitLook.on(l)), "layer:" + l, true)
		grid.add_child(b)
	col.add_child(grid)
	col.add_child(_row([["Everything", func(): _set_layers(true)], ["Clones", func(): _set_layers(false)]]))
	col.add_child(_head("SQUADS"))
	for i in squads.size():
		var top := UI.hbox(6)
		var sb := _button("", func(): _select(i, true), "squad:%d" % i, true)
		sb.size_flags_stretch_ratio = 4.0
		top.add_child(sb)
		for d in [-1, 1]:
			var b := _button("-" if d < 0 else "+", func(): _resize(i, d))
			b.clip_text = false
			b.custom_minimum_size.x = 40
			b.size_flags_horizontal = Control.SIZE_FILL
			top.add_child(b)
		col.add_child(top)
		col.add_child(_row([["Livery", func(): _cycle(i, "livery")], ["Kit", func(): _cycle(i, "kit")],
			["Mark", func(): _cycle(i, "mark")], ["Reroll", func(): _cycle(i, "reroll")]]))
	col.add_child(_head("THE SELECTED SQUAD"))
	_roster = UI.vbox(4)
	col.add_child(_roster)
	col.add_child(_head("ORDERS"))
	col.add_child(_row([["Stand", func(): _order("idle")], ["Block", func(): _order("block")], ["Swing", func(): _order("swing")]]))
	col.add_child(_row([["Take a hit", func(): _order("hit")], ["March", func(): _order("march")]]))
	col.add_child(UI.label("FACING", "SmallLabel", 13, UI.DARK_MUTED))
	col.add_child(_row([["Camera", func(): _set_facing("Camera")], ["SE", func(): _set_facing("SE")], ["SW", func(): _set_facing("SW")]], "face"))
	col.add_child(UI.label("LOOK", "SmallLabel", 13, UI.DARK_MUTED))
	col.add_child(_row([["Toon", func(): _set_look("toon")], ["Flat", func(): _set_look("flat")], ["PBR", func(): _set_look("pbr")]], "look"))
	col.add_child(UI.label("CAMERA", "SmallLabel", 13, UI.DARK_MUTED))
	col.add_child(_row([["1x", func(): _set_zoom(1.0)], ["2x", func(): _set_zoom(2.0)], ["3x", func(): _set_zoom(3.0)], ["6x", func(): _set_zoom(6.0)]]))
	col.add_child(_button("Quit the lab", func(): get_tree().quit()))
	var top_panel := UI.panel("DarkPanel", [8, 16])
	top_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top_panel.position = Vector2(0, 16)
	top_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(top_panel)
	_status = UI.label("", "SmallLabel", 17, UI.LIGHT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_panel.add_child(_status)
	var help := UI.panel("DarkPanel", [8, 16])
	help.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	help.position.y -= 16
	help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(help)
	help.add_child(UI.label("Click: select a squad   Right / middle drag, WASD: pan   Wheel: zoom   Tab: next squad   1-7: layers   C: clones / everything   R: reroll   B block · Space swing · M march · H hit", "SmallLabel", 15, UI.DARK_MUTED))
	_refresh()


func _head(t: String) -> Control:
	return UI.cinzel(t, 15, 700, UI.GOLD)


func _note(t: String) -> Label:
	var l := UI.label(t, "SmallLabel", 15, UI.DARK_MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 340
	return l


func _button(text: String, cb: Callable, key := "", toggle := false) -> Button:
	var b := UI.button(text, "DarkButton", cb)
	b.toggle_mode = toggle
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 34
	b.add_theme_font_size_override("font_size", 15)
	b.clip_text = true
	if key != "":
		_buttons[key] = b
	return b


## A row of buttons; with a `group`, each shows whether it is the group's choice.
func _row(items: Array, group := "") -> HBoxContainer:
	var h := UI.hbox(6)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for it in items:
		h.add_child(_button(it[0], it[1], group + ":" + it[0] if group != "" else "", group != ""))
	return h


func _squad_title(i: int) -> String:
	var s: Dictionary = squads[i]
	var mark := "" if s.mark < 0 else " · mark %d" % (s.mark + 1)
	return "%s · %s%s · %d" % [SquadLook.LIVERIES[s.livery].name, s.kit, mark, s.n]


func _refresh() -> void:
	if _status == null:
		return
	for l in UnitLook.LAYERS:
		_buttons["layer:" + l].set_pressed_no_signal(UnitLook.on(l))
	for i in squads.size():
		var b: Button = _buttons["squad:%d" % i]
		b.text = _squad_title(i)
		b.set_pressed_no_signal(i == selected)
	for f in FACINGS:
		_buttons["face:" + f].set_pressed_no_signal(f == facing)
	for m in ["Toon", "Flat", "PBR"]:
		_buttons["look:" + m].set_pressed_no_signal(m.to_lower() == look)
	for c in _roster.get_children():
		c.queue_free()
	for m in _looks(selected):
		var l := UI.label(SquadLook.describe(m), "SmallLabel", 14, UI.LIGHT if m.leader else UI.DARK_MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 340
		_roster.add_child(l)
	var on := UnitLook.LAYERS.filter(func(l): return UnitLook.on(l))
	var what := "Everything on" if on.size() == UnitLook.LAYERS.size() else ("Clones: every layer off" if on.is_empty() else "Layers: " + ", ".join(on.map(func(l): return UnitLook.LAYER_TITLES[l].to_lower())))
	_status.text = "%s   ·   zoom %.1fx" % [what, _zoom_goal]


# --- Camera and input --------------------------------------------------------

func _process(dt: float) -> void:
	if world == null:
		return
	var old := zoom
	zoom = lerpf(zoom, _zoom_goal, minf(1.0, dt * 10.0)) if not _capturing else _zoom_goal
	if absf(zoom - old) > 1e-4:
		_apply_look()
		_refresh()
	var pan := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	for k in [[KEY_A, Vector2.LEFT], [KEY_D, Vector2.RIGHT], [KEY_W, Vector2.UP], [KEY_S, Vector2.DOWN]]:
		if Input.is_physical_key_pressed(k[0]):
			pan += k[1]
	if pan != Vector2.ZERO and not _capturing:
		var up := Vector3(-1, 0, -1).normalized()
		focus += (_right() * pan.x - up * pan.y) * dt * 9.0 / zoom
	var el := deg_to_rad(ELEVATION)
	var d := Vector3(cos(el) * sin(PI / 4), sin(el), cos(el) * cos(PI / 4))
	cam.position = focus + d * 60.0
	cam.look_at(focus, Vector3.UP)
	cam.size = get_viewport().get_visible_rect().size.y / (ppu * zoom)
	_draw_rings()


## Gold rings under the selected squad's men.
func _draw_rings() -> void:
	var men: Array = squads[selected].get("men", []) if not squads.is_empty() else []
	while _rings.size() < 6:
		var r := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.36
		tm.outer_radius = 0.42
		tm.rings = 32
		r.mesh = tm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(UI.GOLD_BRIGHT, 0.8)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		r.material_override = m
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		r.scale = Vector3(1, 0.05, 1)
		add_child(r)
		_rings.append(r)
	var show := ui.visible and not _capturing
	for k in _rings.size():
		var r: MeshInstance3D = _rings[k]
		r.visible = show and k < men.size() and is_instance_valid(men[k])
		if r.visible:
			r.position = Vector3(men[k].position.x, 0.01, men[k].position.z)


func _unhandled_input(e: InputEvent) -> void:
	if _capturing:
		return
	if e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_set_zoom(_zoom_goal * 1.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				_set_zoom(_zoom_goal / 1.15)
			MOUSE_BUTTON_LEFT:
				var i := _squad_at(e.position)
				if i >= 0:
					_select(i)
	if e is InputEventMouseButton and e.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		_drag = e.pressed
	if e is InputEventMouseMotion and _drag:
		var up := Vector3(-1, 0, -1).normalized()
		# One screen pixel is 1 / (ppu * zoom) m across, and 1 / sin(30) more along the ground.
		focus -= (_right() * e.relative.x - up * e.relative.y / sin(deg_to_rad(ELEVATION))) / (ppu * zoom)
	if e is InputEventKey and e.pressed and not e.echo:
		var k: int = e.physical_keycode
		if k >= KEY_1 and k <= KEY_7:
			var l: String = UnitLook.LAYERS[k - KEY_1]
			_set_layer(l, not UnitLook.on(l))
		match k:
			KEY_C:
				_set_layers(UnitLook.LAYERS.any(func(l): return not UnitLook.on(l)))
			KEY_R:
				_cycle(selected, "reroll")
			KEY_TAB:
				_select((selected + 1) % squads.size(), true)
			KEY_B:
				_order("block")
			KEY_SPACE:
				_order("swing")
			KEY_M:
				_order("march")
			KEY_H:
				_order("hit")
			KEY_ESCAPE:
				_order("idle")


## The squad of the man nearest a screen point (his chest within 40 px).
func _squad_at(p: Vector2) -> int:
	var best := -1
	var bd := 40.0 * maxf(zoom, 1.0)
	for i in squads.size():
		for u in squads[i].men:
			var d := cam.unproject_position(u.global_position + Vector3(0, 1.0, 0)).distance_to(p)
			if d < bd:
				bd = d
				best = i
	return best


# --- Captures ----------------------------------------------------------------

## The review shots: the squads as clones and as men at the game's zoom and
## close, the layers added one by one, a portrait row, and a few orders.
func _capture(dir: String, only := "") -> void:
	dir = ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	get_window().size = Vector2i(1280, 800)
	_capturing = true
	var panel_was := ui.visible
	var mid := Vector3(0, 0.85, 0)
	var first := _centre(0) + Vector3(0, 0.95, 0)
	var ranks := Squad3D.slots(_centre(0), FACINGS.Camera, 6)
	var front: Vector3 = ranks[1] + Vector3(0, 1.55, 0)
	var heads: Vector3 = ranks[1] + Vector3(0, 1.62, 0)
	var rear: Vector3 = ranks[4] + Vector3(0, 1.62, 0)
	var shots := [
		["01_clones_game_zoom", 1.0, mid, func(): _set_layers(false)],
		["02_men_game_zoom", 1.0, mid, func(): _set_layers(true)],
		["03_clones_2x", 2.0, mid, func(): _set_layers(false)],
		["04_men_2x", 2.0, mid, func(): _set_layers(true)],
		["05_clones_3x", 3.2, first, func(): _set_layers(false)],
	]
	var k := 6
	for l in UnitLook.LAYERS:
		shots.append(["%02d_plus_%s_3x" % [k, l], 3.2, first, _layers_upto.bind(l)])
		k += 1
	shots += [
		["13_portraits_6x", 6.5, front, func(): _set_layers(true)],
		["14_portraits_clones_6x", 6.5, front, func(): _set_layers(false)],
		["15_block_2x", 2.0, mid, func(): _set_layers(true); _order("block")],
		["16_swing_2x", 2.0, mid, func(): _order("idle"); _order("swing")],
		["17_facing_se_2x", 2.0, mid, func(): _order("idle"); _set_facing("SE")],
		["18_heads_12x", 12.0, heads, func(): _set_facing("Camera"); _set_layers(true)],
		["19_heads_clones_12x", 12.0, heads, func(): _set_layers(false)],
		["20_heads_rear_12x", 12.0, rear, func(): _set_layers(true)],
		["21_panel", 1.0, mid, func(): ui.visible = true],
	]
	if only != "":
		shots = shots.filter(func(x): return String(x[0]).begins_with(only))
	var waits := {"15_block_2x": 1.0, "16_swing_2x": 0.9, "17_facing_se_2x": 0.5}
	for s in shots:
		ui.visible = false
		_zoom_goal = s[1]
		zoom = s[1]
		focus = s[2]
		s[3].call()
		_apply_look()
		_refresh()
		var t: float = waits.get(s[0], 0.4)
		var end := Time.get_ticks_msec() + int(t * 1000.0)
		while Time.get_ticks_msec() < end:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join(s[0] + ".png"))
		print("CAPTURE ", s[0])
	ui.visible = panel_was
	get_tree().quit()
