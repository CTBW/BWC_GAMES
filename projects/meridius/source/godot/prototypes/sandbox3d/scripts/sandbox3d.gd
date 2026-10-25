## The 3D unit sandbox: every rigged 3D character of the game on a training
## ground in the battle's look (its relief ground and textures, the painted
## woodland, the fog of war), seen through the game's camera (orthographic,
## 30 degrees down, tiles 128 x 64 px and a soldier 49 px tall at zoom 1, as
## in squad_view.gd). Select a unit, march it over the hills, set it on another
## unit or on the straw dummies, play any of its clips.
##   tools/godot.sh --path . res://prototypes/sandbox3d/scenes/sandbox3d.tscn
##   ... -- --capture=<dir> [--shots=<prefix>]   review captures, then quit
##   ... -- --tour                                a short tour for a video, then quit
## (--clean hides the panels and selection rings for either.)
## The footman squad (squad3d.gd): six footmen in two ranks of three in the
## south of the yard, with a drill line of six straw dummies to fight. Click a
## man to select the squad; it marches, stands and fights together, its front
## rank striking while the rear rank stands ready (or, with "Spread to the
## line", the rear rank stepping up beside it). The squad looks lab
## (prototypes/squad_looks) dresses its men when it is on disk.
## Grown from the footman's sandbox (prototypes/footman_anim), which stays as
## his flat-ground bench for its QA scripts; this scene keeps the names they
## use (footman, dummy, click, march_to_tile, _set_zoom, ...). Nothing here
## touches the game's state, saves or production units. See README.md here.
extends Node3D

const Field3D = preload("res://prototypes/sandbox3d/scripts/field3d.gd")
const Fog3D = preload("res://prototypes/sandbox3d/scripts/fog3d.gd")
const Unit3D = preload("res://prototypes/sandbox3d/scripts/unit3d.gd")
const FootmanUnit = preload("res://prototypes/sandbox3d/scripts/footman_unit.gd")
const Fx3D = preload("res://prototypes/sandbox3d/scripts/fx3d.gd")
const Squad3D = preload("res://prototypes/sandbox3d/scripts/squad3d.gd")
const Roster = preload("res://prototypes/sandbox3d/scripts/roster.gd")
const Dummy3D = preload("res://prototypes/footman_anim/scripts/dummy3d.gd")
const Footman3D = preload("res://prototypes/footman_anim/scripts/footman3d.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const UI = preload("res://scripts/ui/ui.gd")

## Game scale: a squad soldier stands SOLDIER_PX world px tall at zoom 1, a
## tile is TILE_PX wide and a level of height LEVEL_PX high (squad_view.gd,
## formation.gd, the relief shader). The footman's standing height sets the
## metres.
const SOLDIER_PX := 49.0
const TILE_PX := 128.0
const LEVEL_PX := 26.0
const ELEVATION := 30.0
const FOOTMAN_META := "res://prototypes/footman_anim/art3d/footman.json"
## The file spacing of a squad (prototypes formation.gd FILE, in tiles): one step into a lane.
const FILE := 0.41
const FACINGS := {"SE": Vector3(1, 0, 0), "SW": Vector3(0, 0, 1), "NW": Vector3(-1, 0, 0), "NE": Vector3(0, 0, -1)}
const OUTLINE_PX := 2.0
const ZOOM_MIN := 0.6
const ZOOM_MAX := 6.0
## The game's footman sprite (squadgen sheet) for comparison: its scale and
## the squad member scale (squad_view.gd MEMBER_SCALE), idle frames 0 1 2 1.
const SPRITE_DOC := "res://assets/sprites/anim/footman.json"
const MEMBER_SCALE := 0.52
const IDLE_FRAME := 0.42
## Where everyone starts (tiles), in the flat yard: the player's units on its
## west side facing east, the enemy's on the east facing west, dummies between.
const PLAYER_TILES := [Vector2i(11, 15), Vector2i(10, 17), Vector2i(9, 19), Vector2i(10, 13), Vector2i(12, 20), Vector2i(12, 12)]
const ENEMY_TILES := [Vector2i(18, 15), Vector2i(18, 18), Vector2i(19, 13), Vector2i(19, 20)]
const DUMMY_TILES := [Vector2i(13, 16), Vector2i(15, 13)]
## The squad: its men, its centre (tiles) and facing at the start, each man's
## own pace (his playback, so no two keep step), and its drill line: six
## dummies a file apart, a march east of it.
const SQUAD_SIZE := 6
const SQUAD_HOME := Vector2(12.0, 20.0)
const SQUAD_FACING := PI / 2
const SQUAD_RATE := Vector2(0.95, 1.05)
const DRILL := Vector2(16.0, 20.0)
const DRILL_COUNT := 6
## The squad looks lab (prototypes/squad_looks) dresses the squad's men, each
## in his own face, hair, kit and helmet under the company's blue livery, when
## it is on disk; without it they wear the footman export's own look.
const LOOKS := "res://prototypes/squad_looks/scripts/"
const SQUAD_LIVERY := 0
const SQUAD_KIT := "line"
## The camera at the start: the yard with the squad and its drill line in view.
const START := Vector2(13.3, 17.4)
const START_ZOOM := 1.1
const DAY := {"sun": 0.5, "sun_color": Color(1.0, 0.96, 0.88), "ambient": 0.6, "ambient_color": Color(0.86, 0.9, 1.0),
	"paint": Vector3(1, 1, 1), "bg": Color(0.07, 0.09, 0.07)}
const NIGHT := {"sun": 0.3, "sun_color": Color(0.62, 0.72, 1.0), "ambient": 0.42, "ambient_color": Color(0.5, 0.6, 0.95),
	"paint": Vector3(0.42, 0.5, 0.72), "bg": Color(0.02, 0.03, 0.05)}

var ppu := 33.0
var tile_m := 2.72
var level_m := 0.9
var zoom := START_ZOOM
var _zoom_goal := START_ZOOM
var look := "toon"
var outline := true
var follow := false
var fog_on := false
var grid_on := false
var night := false
var lethal := false
var fight_back := true
var speed := 1.0
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var field
var fog
var fx
var world: Node3D
var units: Array = []
var dummies: Array = []
var selected: Array = []
var squad
## The drill line's dummies (also in `dummies`).
var drill: Array = []
## The footman and the first dummy, as the footman's QA scripts know them.
var footman: Node3D
var dummy: Node3D
var focus := Vector3.ZERO
var sprite: Sprite3D
var ui: CanvasLayer
var _sprite_doc: Dictionary
var _sprite_t := 0.0
var _sprite_tex := {}
var _armed := 0
var _dragging := false
var _drag_moved := 0.0
var _hover_tile := Vector2i(-99, -99)
var _hover_unit: Node3D
var _route := {}
var _flash_text := ""
var _flash_t := 0.0
var _counter_from := {}
var _last_target := {}
var _rings: MeshInstance3D
var _ring_mesh: ImmediateMesh
## Each ring's points on the ground, kept while its unit stands still.
var _ring_pts := {}
var _panel_unit: VBoxContainer
var _status: Label
var _info: Label
var _buttons := {}
var _fade_t := 0.0
var _focus_goal := Vector3.INF
var _capturing := false
var _cap_dir := ""
var _cap_only := ""


func _ready() -> void:
	process_priority = 10   # after the units have moved: their feet go on the ground
	# Smooth edges: the 3D is drawn at twice the size and scaled down
	# (the Compatibility renderer drops the ink line under MSAA).
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	get_viewport().scaling_3d_scale = 2.0
	var fm_meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FOOTMAN_META))
	var h: float = fm_meta.get("height_m", 1.7)
	ppu = SOLDIER_PX / (h * cos(deg_to_rad(ELEVATION)))
	tile_m = TILE_PX / (sqrt(2.0) * ppu)
	level_m = LEVEL_PX / (ppu * cos(deg_to_rad(ELEVATION)))
	_build_world()
	field = Field3D.new()
	field.name = "Field"
	add_child(field)
	field.build(tile_m, level_m, ELEVATION, ppu)
	fog = Fog3D.new(field.map)
	field.set_shared("fog_tex", fog.tex)
	field.set_shared("fog_on", false)
	world = Node3D.new()
	world.name = "Units"
	add_child(world)
	fx = Fx3D.new()
	fx.name = "Fx"
	fx.ground = field.ground_y
	add_child(fx)
	_ring_mesh = ImmediateMesh.new()
	_rings = MeshInstance3D.new()
	_rings.name = "Rings"
	_rings.mesh = _ring_mesh
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.vertex_color_use_as_albedo = true
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rings.material_override = rm
	_rings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rings)
	_spawn()
	for m in Roster.missing():
		print("Sandbox: %s left out, not on this computer: %s" % [m.title, ", ".join(m.files)])
	if squad == null:
		print("Sandbox: no footman squad without the footman")
	_build_sprite()
	_build_ui()
	focus = field.on_ground(START) + Vector3(0, 0.85, 0)
	_select([footman] if footman else ([units[0]] if not units.is_empty() else []))
	_apply_look()
	_apply_light()
	get_window().title = "Meridius - 3D unit sandbox"
	var args := OS.get_cmdline_user_args()
	if args.has("--clean"):
		ui.visible = false
		_rings.visible = false
	for arg in args:
		if arg.begins_with("--capture="):
			var only := ""
			for a in args:
				if a.begins_with("--shots="):
					only = a.trim_prefix("--shots=")
			_capture(arg.trim_prefix("--capture="), only)
		elif arg == "--tour":
			_tour()


func _build_world() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	# From the screen's upper left (world -X), 50 degrees up: shadows fall down
	# and right, as the painted sprites' shadows and the relief's hill shadows.
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-90), 0)
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.55
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 0.1
	cam.far = 400.0
	add_child(cam)
	cam.make_current()


## The roster on its start tiles, and the dummies.
func _spawn() -> void:
	var pi := 0
	var ei := 0
	for p in Roster.available():
		var u: Node3D = FootmanUnit.new() if p.get("controller", "") == "footman" else Unit3D.new()
		u.setup(p)
		u.name = String(p.id).capitalize().replace(" ", "")
		world.add_child(u)
		if p.get("controller", "") == "footman":
			u.tile_m = tile_m
			footman = u
		var t: Vector2i
		if u.faction == "player":
			t = PLAYER_TILES[pi % PLAYER_TILES.size()]
			pi += 1
		else:
			t = ENEMY_TILES[ei % ENEMY_TILES.size()]
			ei += 1
		u.set_meta("home", t)
		u.position = field.on_ground(Vector2(t))
		u.rotation.y = atan2(1.0, 0.0) if u.faction == "player" else atan2(-1.0, 0.0)
		u.impact.connect(_on_impact.bind(u))
		u.release.connect(_on_release.bind(u))
		units.append(u)
	for t in DUMMY_TILES:
		var d := Dummy3D.new()
		d.name = "Dummy%d" % dummies.size()
		d.position = field.on_ground(Vector2(t))
		d.set_meta("home", t)
		world.add_child(d)
		dummies.append(d)
	dummy = dummies[0]
	_spawn_squad()


## The footman squad in two ranks in the south of the yard, facing east toward
## its drill line.
func _spawn_squad() -> void:
	var p: Dictionary = {}
	for q in Roster.available():
		if q.get("controller", "") == "footman":
			p = q
	if p.is_empty():
		return
	squad = Squad3D.new()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var dressed: Script = null
	var looks := []
	if ResourceLoader.exists(LOOKS + "dressed_footman.gd"):
		dressed = load(LOOKS + "dressed_footman.gd")
		var squad_look: Script = load(LOOKS + "squad_look.gd")
		var livery: Dictionary = squad_look.get_script_constant_map().LIVERIES[SQUAD_LIVERY]
		looks = squad_look.squad(SQUAD_SIZE, rng.randi(), livery, SQUAD_KIT)
	var men := []
	for i in SQUAD_SIZE:
		var u: Node3D = dressed.new() if dressed else FootmanUnit.new()
		u.setup(p)
		u.name = "SquadFootman%d" % (i + 1)
		if dressed:
			u.look_spec = looks[i]
		world.add_child(u)
		u.tile_m = tile_m
		var r := rng.randf_range(SQUAD_RATE.x, SQUAD_RATE.y)
		u.set_meta("rate", r)
		u.playback = speed * r
		u.set_meta("squad", squad)
		u.impact.connect(_on_impact.bind(u))
		u.release.connect(_on_release.bind(u))
		units.append(u)
		men.append(u)
	if dressed:
		# Each man glances at his squadmates and at the roster's units.
		load(LOOKS + "unit_look.gd").link(men, _roster())
	var home: Vector3 = field.on_ground(SQUAD_HOME)
	squad.setup(men, field, self, home, SQUAD_FACING)
	squad.place(home, SQUAD_FACING)
	for k in DRILL_COUNT:
		var d := Dummy3D.new()
		d.name = "Drill%d" % k
		var g: Vector2 = DRILL + Vector2(0, (k - (DRILL_COUNT - 1) * 0.5) * Squad3D.FILE / tile_m)
		d.position = field.on_ground(g)
		d.set_meta("home", g)
		world.add_child(d)
		dummies.append(d)
		drill.append(d)


## The roster's units: everyone but the squad's men.
func _roster() -> Array:
	return units.filter(func(u): return not u.has_meta("squad"))


## The squad, when its standing men are the selection.
func _squad_sel():
	if squad == null or selected.is_empty():
		return null
	for u in selected:
		if not is_instance_valid(u) or _squad_of(u) != squad:
			return null
	return squad if selected.filter(func(u): return not u.is_dead()).size() == squad.standing() else null


## The squad `u` serves in, or null (get_meta errors on a missing key even with a null default).
func _squad_of(u: Node3D):
	return u.get_meta("squad") if u.has_meta("squad") else null


## Who a click on `u` selects: his squad's standing men, or him.
func _group_of(u: Node3D) -> Array:
	var sq = _squad_of(u)
	if sq and not u.is_dead():
		return sq.alive()
	return [u]


## The route marks on the ground (the squad's march).
func show_route(marks: Dictionary) -> void:
	_route = marks
	field.mark(_route)


## The route marks off the ground, if they are still `marks` (no newer order's).
func clear_route(marks: Dictionary) -> void:
	if is_same(_route, marks) and not marks.is_empty():
		show_route({})


## Everyone back on their start tiles, alive and idle.
func reset_field() -> void:
	fx.clear()
	for u in units:
		if u.is_dead():
			u.revive()
		if u.has_meta("squad"):
			continue
		u.stop()
		u.position = field.on_ground(Vector2(u.get_meta("home")))
		u.rotation.y = atan2(1.0, 0.0) if u.faction == "player" else atan2(-1.0, 0.0)
	if squad:
		squad.place(field.on_ground(SQUAD_HOME), SQUAD_FACING)
	for d in dummies:
		d.position = field.on_ground(Vector2(d.get_meta("home")))
	_route = {}
	_counter_from.clear()
	field.mark(_route)
	_flash("Units back on their start tiles")


# --- The game's 2D footman beside the 3D one ------------------------------------------

func _build_sprite() -> void:
	_sprite_doc = JSON.parse_string(FileAccess.get_file_as_string(SPRITE_DOC))
	sprite = Sprite3D.new()
	sprite.name = "GameSprite"
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.pixel_size = float(_sprite_doc.scale) * MEMBER_SCALE / ppu
	sprite.visible = false
	add_child(sprite)
	_sprite_frame()


## The sprite's idle frame for the 3D footman's facing (soldier_anim.gd: the
## sheet draws the SW and NE facings; SE and NW are those mirrored), a tile to his left.
func _sprite_frame() -> void:
	if footman == null or not sprite.visible:
		return
	var f := posmod(roundi(footman.rotation.y / (PI / 2)) * -1 + 1, 4)
	var suf := ("f" if f in [0, 1] else "b") + ("s" if f in [0, 2] else "")
	var seq := [0, 1, 2, 1]
	var n := "idle_%s_%d" % [suf, seq[int(_sprite_t / IDLE_FRAME) % 4]]
	var e: Dictionary = _sprite_doc.frames[n][0]
	var r: Array = e.region
	if not _sprite_tex.has(n):
		var at := AtlasTexture.new()
		at.atlas = load(_sprite_doc.file)
		at.region = Rect2(r[0], r[1], r[2], r[3])
		_sprite_tex[n] = at
	sprite.texture = _sprite_tex[n]
	sprite.flip_h = f in [0, 2]
	var ox: float = r[2] * 0.5 - float(e.ax)
	sprite.offset = Vector2(-ox if sprite.flip_h else ox, float(e.ay) - r[3] * 0.5)
	var at_g := footman.position + Vector3(1, 0, -1).normalized() * -tile_m * 0.6
	sprite.position = Vector3(at_g.x, field.ground_y(at_g.x, at_g.z), at_g.z)


# --- UI ------------------------------------------------------------------------------------

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	# The left column: the roster and the selected unit, scrolling within the
	# screen's height (the footer's line stays clear).
	var side := UI.panel("DarkPanel", [16, 22])
	side.anchor_bottom = 1.0
	side.offset_left = 16
	side.offset_top = 16
	side.offset_right = 16 + 412
	side.offset_bottom = -76
	root.add_child(side)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	var col := UI.vbox(8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(col)
	col.add_child(UI.cinzel("3D UNIT SANDBOX", 22, 700, UI.LIGHT_TITLE))
	col.add_child(_note("Every rigged 3D character on the battle's ground. Click a unit to select it, the ground to march, a foe or a dummy to attack."))
	col.add_child(_head("ROSTER"))
	var roster := UI.grid(2, 6, 6)
	roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for u in _roster():
		var b := _button(u.title(), func(): _pick([u]), "roster:" + str(u.get_instance_id()), true)
		b.add_theme_color_override("font_color", UI.BLUE_BRIGHT if u.faction == "player" else UI.RED_BRIGHT)
		roster.add_child(b)
	col.add_child(roster)
	var gone: Array = Roster.missing().map(func(m): return m.title)
	if not gone.is_empty():
		var why := "Not on this computer: %s (their model files are missing)." % ", ".join(gone)
		if squad == null:
			why += " The footman squad needs the footman."
		col.add_child(_note(why))
	if squad:
		col.add_child(_head("SQUADS"))
		var sb := _button("Footman squad  ·  %d men" % squad.members.size(), func(): _pick(squad.alive()), "squad", true)
		sb.add_theme_color_override("font_color", UI.BLUE_BRIGHT)
		col.add_child(sb)
	_panel_unit = UI.vbox(6)
	col.add_child(_panel_unit)
	# The right column: what is under the cursor, then the scene's settings.
	var right := UI.panel("DarkPanel", [16, 22])
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -16 - 404
	right.offset_right = -16
	right.offset_top = 16
	root.add_child(right)
	var rc := UI.vbox(8)
	right.add_child(rc)
	_info = UI.label("", "SmallLabel", 15, UI.DARK_MUTED)
	_info.custom_minimum_size.y = 66
	rc.add_child(_info)
	rc.add_child(_head("SCENE"))
	rc.add_child(_row([["Fog of war", func(): _toggle("fog")], ["Forget explored", func(): _forget()]], ["tog:Fog of war"]))
	rc.add_child(_row([["Grid", func(): _toggle("grid")], ["Night", func(): _toggle("night")], ["Follow", func(): _toggle("follow")]], ["tog:Grid", "tog:Night", "tog:Follow"]))
	rc.add_child(_row([["Outline", func(): _toggle("outline")], ["Shadows", func(): _toggle("shadow")], ["2D sprite", func(): _toggle("sprite")]], ["tog:Outline", "tog:Shadows", "tog:2D sprite"]))
	rc.add_child(_row([["Lethal blows", func(): _toggle("lethal")], ["Fight back", func(): _toggle("fight")]], ["tog:Lethal blows", "tog:Fight back"]))
	rc.add_child(UI.label("LOOK", "SmallLabel", 13, UI.DARK_MUTED))
	rc.add_child(_row([["Toon", func(): _set_look("toon")], ["Flat", func(): _set_look("flat")], ["PBR", func(): _set_look("pbr")]], ["look:Toon", "look:Flat", "look:PBR"]))
	rc.add_child(UI.label("TIME", "SmallLabel", 13, UI.DARK_MUTED))
	rc.add_child(_row([["0.25x", func(): _set_speed(0.25)], ["0.5x", func(): _set_speed(0.5)], ["1x", func(): _set_speed(1.0)], ["2x", func(): _set_speed(2.0)]], ["spd:0.25x", "spd:0.5x", "spd:1x", "spd:2x"]))
	rc.add_child(UI.label("CAMERA", "SmallLabel", 13, UI.DARK_MUTED))
	rc.add_child(_row([["1x", func(): _set_zoom(1.0)], ["2x", func(): _set_zoom(2.0)], ["3x", func(): _set_zoom(3.0)], ["Field", func(): _frame_field()]], []))
	rc.add_child(_row([["Revive all", func(): _revive_all()], ["Reset field", func(): reset_field()]], []))
	rc.add_child(_button("Quit the sandbox", func(): get_tree().quit()))
	# The status line over the field and the help line under it.
	var top := UI.panel("DarkPanel", [8, 16])
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(0, 16)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(top)
	_status = UI.label("", "SmallLabel", 17, UI.LIGHT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_status)
	var help := UI.panel("DarkPanel", [8, 16])
	help.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	help.position.y -= 16
	help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(help)
	help.add_child(UI.label("Left click: select · march · attack   Right click: order   Right / middle drag, WASD: pan   Wheel: zoom   Tab: next unit   1-8: attacks   H hit · K die · R revive · Space strike · F follow · G grid · V fog · N night · Esc: deselect", "SmallLabel", 15, UI.DARK_MUTED))
	_refresh_unit_panel()
	_refresh()


func _head(t: String) -> Control:
	var l := UI.cinzel(t, 15, 700, UI.GOLD)
	return l


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


## A row of buttons; those whose "group:label" key is in `toggles` show their state.
func _row(items: Array, toggles: Array) -> HBoxContainer:
	var h := UI.hbox(6)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for it in items:
		var key := ""
		for k in toggles:
			if String(k).get_slice(":", 1) == it[0]:
				key = k
		h.add_child(_button(it[0], it[1], key, key != ""))
	return h


## The selected unit's part of the panel: what it is, its attacks and
## stances, its reactions and every clip it has.
func _refresh_unit_panel() -> void:
	if _panel_unit == null:
		return
	UI.clear(_panel_unit)
	for k in _buttons.keys():
		if String(k).begins_with("u:"):
			_buttons.erase(k)
	var u := _sel()
	if u == null:
		_panel_unit.add_child(_note("No unit selected."))
		return
	var sq = _squad_sel()
	if sq:
		_squad_panel(sq)
		return
	_panel_unit.add_child(_head(u.title().to_upper() + ("  ·  PLAYER" if u.faction == "player" else "  ·  ENEMY")))
	_panel_unit.add_child(_note(u.profile.get("blurb", "")))
	var acts: Array = u.actions()
	var g := UI.grid(2, 6, 6)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := 0
	for a in acts:
		n += 1
		var label: String = a.label
		if String(a.id).begins_with("attack:") and n <= 8:
			label = "%d  %s" % [n, a.label]
		g.add_child(_button(label, _do_action.bind(a.id), "u:" + a.id, a.get("toggle", false)))
	_panel_unit.add_child(g)
	_panel_unit.add_child(_row([["Hit", func(): _react("hit")], ["Death", func(): _react("die")], ["Revive", func(): _react("revive")], ["Stop", func(): _react("stop")]], []))
	if u == footman:
		_panel_unit.add_child(_row([["Walk pace", func(): _set_pace("walk")], ["Game pace", func(): _set_pace("game")]], ["pace:Walk pace", "pace:Game pace"]))
		_panel_unit.add_child(_row([["Turn, then walk", func(): _set_step_turns(true)], ["Turn as he walks", func(): _set_step_turns(false)]], ["start:Turn, then walk", "start:Turn as he walks"]))
	_panel_unit.add_child(UI.label("ALL CLIPS", "SmallLabel", 13, UI.DARK_MUTED))
	var cg := UI.grid(2, 4, 4)
	cg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c in u.clip_names():
		var b := _button(String(c).capitalize(), _play_clip.bind(c))
		b.custom_minimum_size.y = 28
		b.add_theme_font_size_override("font_size", 13)
		b.tooltip_text = c
		cg.add_child(b)
	_panel_unit.add_child(cg)


## The squad's part of the panel: its orders, how it fights, its reactions and its men.
func _squad_panel(sq) -> void:
	_panel_unit.add_child(_head("FOOTMAN SQUAD  ·  PLAYER"))
	_panel_unit.add_child(_note("Six footmen in two ranks of three, each in his own time. Click the ground to march them in formation, a foe or a dummy to attack: the front rank strikes while the rear rank stands ready behind it, and after a few blows each the squad re-forms its ranks. Spread to the line: the rear rank steps up beside the front rank, so all six strike."))
	var g := UI.grid(2, 6, 6)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for a in [["1  Attack", "attack"], ["Re-form", "reform"], ["Wheel left  (Q)", "wheel_l"], ["Wheel right  (E)", "wheel_r"], ["About face", "about"], ["Halt", "halt"]]:
		g.add_child(_button(a[0], _squad_action.bind(a[1])))
	_panel_unit.add_child(g)
	_panel_unit.add_child(UI.label("IN A FIGHT", "SmallLabel", 13, UI.DARK_MUTED))
	_panel_unit.add_child(_row([["Front rank only", func(): _set_wide(false)], ["Spread to the line", func(): _set_wide(true)]], ["sq:Front rank only", "sq:Spread to the line"]))
	_panel_unit.add_child(_row([["Hit", func(): _react("hit")], ["Death", func(): _react("die")], ["Revive", func(): _react("revive")], ["Stop", func(): _react("stop")]], []))
	_panel_unit.add_child(UI.label("ITS MEN (ONE ALONE: HIS CLIPS)", "SmallLabel", 13, UI.DARK_MUTED))
	var men := UI.grid(6, 4, 4)
	men.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in sq.members.size():
		var m: Node3D = sq.members[i]
		var b := _button(str(i + 1), func(): _select([m]))
		b.custom_minimum_size.y = 30
		men.add_child(b)
	_panel_unit.add_child(men)


func _squad_action(id: String) -> void:
	var sq = _squad_sel()
	if sq == null:
		return
	match id:
		"attack":
			var t := _squad_target(sq)
			if t:
				sq.attack(t)
			else:
				_flash("No foe or dummy within eight tiles of the squad")
		"reform":
			sq.reform()
		"wheel_l":
			sq.face(sq.yaw + PI / 2)
		"wheel_r":
			sq.face(sq.yaw - PI / 2)
		"about":
			sq.face(sq.yaw + PI)
		"halt":
			sq.halt()
	_refresh()


## The squad's foe: the one it fought last if still standing, else the
## nearest foe or dummy within eight tiles of it.
func _squad_target(sq) -> Node3D:
	var at: Vector3 = sq.centroid()
	var last: Node3D = sq.last_foe
	if last and _alive(last) and last.visible and last.position.distance_to(at) < 8.0 * tile_m:
		return last
	var best: Node3D = null
	var bd := 8.0 * tile_m
	for n in units + dummies:
		if _hostile(sq.members[0], n) and _alive(n) and n.visible:
			var d: float = n.position.distance_to(at)
			if d < bd:
				bd = d
				best = n
	return best


func _set_wide(on: bool) -> void:
	if squad:
		squad.wide = on
	_refresh()


func _refresh() -> void:
	var u := _sel()
	var on := {
		"tog:Fog of war": fog_on, "tog:Grid": grid_on, "tog:Night": night, "tog:Follow": follow,
		"tog:Outline": outline, "tog:Shadows": sun.shadow_enabled, "tog:2D sprite": sprite != null and sprite.visible,
		"tog:Lethal blows": lethal, "tog:Fight back": fight_back,
		"look:Toon": look == "toon", "look:Flat": look == "flat", "look:PBR": look == "pbr",
		"spd:0.25x": speed == 0.25, "spd:0.5x": speed == 0.5, "spd:1x": speed == 1.0, "spd:2x": speed == 2.0,
	}
	for x in units:
		on["roster:" + str(x.get_instance_id())] = x in selected
	on["squad"] = _squad_sel() != null
	if squad:
		on["sq:Spread to the line"] = squad.wide
		on["sq:Front rank only"] = not squad.wide
	if u:
		for s in u.profile.get("stances", []):
			on["u:stance:" + s] = u.stance == s
		if u == footman:
			on["u:stance:block"] = footman.block_held
			on["pace:Walk pace"] = footman.pace == "walk"
			on["pace:Game pace"] = footman.pace == "game"
			on["start:Turn, then walk"] = footman.step_turns
			on["start:Turn as he walks"] = not footman.step_turns
	for k in on:
		if _buttons.has(k) and is_instance_valid(_buttons[k]):
			_buttons[k].set_pressed_no_signal(on[k])


func _flash(t: String) -> void:
	_flash_text = t
	_flash_t = 3.0


# --- Settings ---------------------------------------------------------------------------

func _toggle(what: String) -> void:
	match what:
		"fog":
			fog_on = not fog_on
			field.set_shared("fog_on", fog_on)
		"grid":
			grid_on = not grid_on
			field.mat.set_shader_parameter("grid_on", grid_on)
		"night":
			night = not night
			_apply_light()
		"follow":
			follow = not follow
		"outline":
			outline = not outline
		"shadow":
			sun.shadow_enabled = not sun.shadow_enabled
		"sprite":
			sprite.visible = not sprite.visible
			_sprite_frame()
		"lethal":
			lethal = not lethal
		"fight":
			fight_back = not fight_back
	_apply_look()
	_refresh()


func _forget() -> void:
	fog.forget()
	_flash("Explored ground forgotten: only what is seen now stays clear")


func _apply_light() -> void:
	var p: Dictionary = NIGHT if night else DAY
	sun.light_energy = p.sun
	sun.light_color = p.sun_color
	env.ambient_light_energy = p.ambient
	env.ambient_light_color = p.ambient_color
	env.background_color = p.bg
	field.set_shared("night", p.paint)
	field.mat.set_shader_parameter("deep", Vector3(p.bg.r, p.bg.g, p.bg.b))


func _set_pace(p: String) -> void:
	if footman == null:
		return
	footman.pace = p
	if footman.state == "walk":
		footman._start_walk()
	_refresh()


func _set_step_turns(on: bool) -> void:
	if footman:
		footman.step_turns = on
	_refresh()


func _set_look(m: String) -> void:
	look = m
	_apply_look()
	_refresh()


func _set_zoom(z: float) -> void:
	_zoom_goal = clampf(z, ZOOM_MIN, ZOOM_MAX) if not _capturing else z
	_refresh()


func _set_speed(s: float) -> void:
	speed = s
	for u in units:
		u.playback = s * float(u.get_meta("rate", 1.0))
	for d in dummies:
		d.playback = s
	_refresh()


func _apply_look() -> void:
	var w := OUTLINE_PX / (ppu * zoom)
	for u in units:
		u.set_look(look, outline)
		u.set_outline_width(w)
	for d in dummies:
		d.set_outline(outline, w)


func _frame_field() -> void:
	focus = field.on_ground(Vector2(Field3D.W, Field3D.H) * 0.5 - Vector2(0.5, 0.5))
	follow = false
	_set_zoom(0.62)


# --- Selection and orders ------------------------------------------------------------

func _sel() -> Node3D:
	return selected[0] if not selected.is_empty() and is_instance_valid(selected[0]) else null


func _select(list: Array) -> void:
	selected = list.filter(func(x): return x != null)
	_armed = 0
	_refresh_unit_panel()
	_refresh()


## Tab: the next of the roster's units, then the squad.
func select_next() -> void:
	var entries: Array = _roster().map(func(u): return [u])
	if squad and squad.standing() > 0:
		entries.append(squad.alive())
	if entries.is_empty():
		return
	var i := -1
	for k in entries.size():
		if selected.has(entries[k][0]):
			i = k
	_pick(entries[(i + 1) % entries.size()])


## Select from the panel or with Tab: the camera eases over to the selection
## if it is out of view.
func _pick(list: Array) -> void:
	_select(list)
	if list.is_empty() or _capturing:
		return
	var c := Vector3.ZERO
	for u in list:
		c += u.position
	c /= list.size()
	var at := cam.unproject_position(c)
	var view := get_viewport().get_visible_rect().size
	if not Rect2(view * Vector2(0.3, 0.2), view * Vector2(0.4, 0.6)).has_point(at):
		follow = false
		_focus_goal = c + Vector3(0, 0.85, 0)


func _is_unit(n: Node3D) -> bool:
	return n != null and n.has_method("take_hit")


func _alive(n: Node3D) -> bool:
	return n != null and is_instance_valid(n) and (not _is_unit(n) or not n.is_dead())


## A foe for `u`: a unit of the other side, or a dummy.
func _hostile(u: Node3D, n: Node3D) -> bool:
	return n != null and n != u and (not _is_unit(n) or n.faction != u.faction)


func _do_action(id: String) -> void:
	var u := _sel()
	if u == null:
		return
	if id.begins_with("attack:"):
		_armed = int(id.get_slice(":", 1))
		for s in selected:
			var t := _target_for(s)
			if t:
				order_attack(s, t, _armed)
			elif s == u:
				_counter_from.erase(s)
				s.strike(null, _armed)
	elif id.begins_with("stance:"):
		u.toggle_stance(id.get_slice(":", 1))
	elif id == "charge":
		var t := _target_for(u)
		if t and not u.charge(t):
			_flash("Too close to charge (it needs a run of %d tiles): he walks up instead" % Footman3D.CHARGE_MIN_TILES)
	elif id == "counter":
		var t := _target_for(u)
		if t:
			u.counter(t)
	elif id == "lane":
		u.step_lane(FILE * tile_m)
	_refresh()


## Who `u` should strike: the foe it struck last if still standing and near,
## else the nearest foe within six tiles.
func _target_for(u: Node3D) -> Node3D:
	var last: Node3D = _last_target.get(u)
	if last and _alive(last) and last.visible and last.position.distance_to(u.position) < 6.0 * tile_m:
		return last
	var best: Node3D = null
	var bd := 6.0 * tile_m
	for n in units + dummies:
		if _hostile(u, n) and _alive(n) and n.visible:
			var d: float = n.position.distance_to(u.position)
			if d < bd:
				bd = d
				best = n
	return best


## A reaction for the selection; a group's men each a moment apart.
func _react(what: String) -> void:
	var sq = _squad_sel()
	if sq and what == "stop":
		sq.halt()
	for u in selected:
		var go := func():
			if not is_instance_valid(u):
				return
			match what:
				"hit":
					u.take_hit(u.position + Vector3(sin(u.rotation.y), 0, cos(u.rotation.y)), false)
				"die":
					u.die()
				"revive":
					u.revive()
				"stop":
					u.stop()
		if selected.size() > 1 and what != "stop":
			get_tree().create_timer(randf() * 0.3 / maxf(speed, 0.1)).timeout.connect(go)
		else:
			go.call()


func _play_clip(c: String) -> void:
	for u in selected:
		if u.has_clip(c):
			u.play_clip(c)


func _revive_all() -> void:
	for u in units:
		if u.is_dead():
			u.revive()


## March the selected units to a tile; a group spreads over the tiles round it.
func march_to_tile(t: Vector2i) -> void:
	var movers := selected.filter(func(u): return not u.is_dead())
	if movers.is_empty() and footman and selected.is_empty():
		movers = [footman]
	var goals := _spread(t, movers.size())
	movers.sort_custom(func(a, b): return a.position.distance_to(field.on_ground(Vector2(t))) < b.position.distance_to(field.on_ground(Vector2(t))))
	_route = {}
	for i in movers.size():
		var u: Node3D = movers[i]
		var g: Vector2i = goals[i] if i < goals.size() else t
		var pts: Array = field.path_to(u.position, g)
		if pts.is_empty():
			_flash("No way there for the %s" % u.title())
			continue
		for p in pts:
			_route[field.tile_of(p)] = 1
		_route[g] = 2
		u.order_move(pts)
	field.mark(_route)


## n walkable tiles nearest to t (t first), for a group to stand on.
func _spread(t: Vector2i, n: int) -> Array:
	var out := []
	for r in range(0, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := t + Vector2i(dx, dy)
				if field.walkable(c):
					out.append(c)
				if out.size() >= n:
					return out
	return out


## Bring `u` within reach of `target` (or within range, with a clear line
## for a missile) and strike with attack i. A route that ends short tries
## again, twice, then strikes from where it stands.
func order_attack(u: Node3D, target: Node3D, i: int, tries := 0) -> void:
	if tries == 0:
		_counter_from.erase(u)
	if u.is_dead() or not _alive(target):
		return
	_last_target[u] = target
	var to: Vector3 = target.position - u.position
	to.y = 0
	var d := to.length()
	var r: float = u.reach(i)
	var ranged: bool = u.is_ranged(i)
	if (ranged and d <= r and _line_clear(u.position, target.position)) or (not ranged and d <= r + 0.35) or tries >= 2:
		u.strike(target, i)
		return
	var spot: Vector3
	if ranged:
		spot = _firing_spot(u, target, r)
	else:
		var from := -to.normalized() if d > 1e-3 else Vector3(1, 0, 0)
		spot = target.position + from * r
	var goal: Vector2i = field.tile_of(spot)
	var pts: Array = []
	if field._clear(Vector2(field.tile_of(u.position)), Vector2(goal)):
		pts = [field.on_ground(Vector2(spot.x, spot.z) / tile_m)]
	else:
		pts = field.path_to(u.position, goal)
		if not pts.is_empty() and not ranged:
			pts[-1] = field.on_ground(Vector2(spot.x, spot.z) / tile_m)
	if pts.is_empty():
		u.strike(target, i)
		return
	u.order_move(pts, order_attack.bind(u, target, i, tries + 1))


## A clear line of sight between two ground points (the battle's rule).
func _line_clear(a: Vector3, b: Vector3) -> bool:
	var ta: Vector2i = field.tile_of(a)
	var tb: Vector2i = field.tile_of(b)
	if not field.in_field(ta) or not field.in_field(tb):
		return true
	return not Grid.line_of_sight(field.map, {"x": ta.x, "y": ta.y}, {"x": tb.x, "y": tb.y}).blocked


## The walkable tile nearest the shooter within range of the target with a clear line.
func _firing_spot(u: Node3D, target: Node3D, r: float) -> Vector3:
	var tt: Vector2i = field.tile_of(target.position)
	var reach_t := int(floor(r / tile_m))
	var best := u.position
	var bd := INF
	for dy in range(-reach_t, reach_t + 1):
		for dx in range(-reach_t, reach_t + 1):
			var c := tt + Vector2i(dx, dy)
			var p: Vector3 = field.on_ground(Vector2(c))
			if not field.walkable(c) or p.distance_to(target.position) > r * 0.92 or p.distance_to(target.position) < 1.5:
				continue
			if not _line_clear(p, target.position):
				continue
			var cost: float = p.distance_to(u.position)
			if cost < bd:
				bd = cost
				best = p
	return best


func _on_impact(target: Node3D, landed: bool, _reach: float, who: Node3D) -> void:
	_flash(who.title() + ": " + String(who.last_impact))
	# A strike back is not answered, all its hits (the wolf's twin daggers) alike.
	var counter: bool = _counter_from.has(who)
	if target == null or not is_instance_valid(target):
		return
	var h: float = target.height_m() if target.has_method("height_m") else 1.5
	fx.spark(target.position + Vector3(0, h * 0.6, 0) - _dir(who, target) * 0.25, landed)
	if landed:
		_blow(who, target, counter)


func _on_release(target: Node3D, kind: String, who: Node3D) -> void:
	_flash(who.title() + ": " + String(who.last_impact))
	fx.launch(kind, who, target, _missile_land.bind(who, kind))


func _missile_land(target: Node3D, who: Node3D, kind: String) -> void:
	if kind == "frost":
		for n in units + dummies:
			if _hostile(who, n) and _alive(n) and n.position.distance_to(who.position) < 3.4:
				_blow(who, n, _counter_from.has(who))
		return
	if target and _alive(target):
		_blow(who, target, _counter_from.has(who))


## A landed blow: the dummy rocks, a unit flinches (or falls, with lethal
## blows on) and, if it is free and the striker within its reach, strikes back
## once when it has steadied (a strike back is not answered).
func _blow(who: Node3D, target: Node3D, counter: bool) -> void:
	if not _is_unit(target):
		target.struck(who.position)
		return
	if target.is_dead():
		return
	target.take_hit(who.position, lethal)
	if lethal or counter or not fight_back or not _is_unit(who) or who.faction == target.faction:
		return
	var sq = _squad_of(target)
	if sq:
		# A squad answers together: struck while it stands, it attacks the striker.
		if sq.mode in ["idle", "reform"]:
			sq.attack(who)
		return
	_fight_back(target, who)


## The struck unit answers once its hit reaction has played out (hit clips run 1-3.5 s),
## unless it died, was given another order or the attacker is out of its reach.
func _fight_back(target: Node3D, who: Node3D) -> void:
	var waited := 0.0
	while waited < 5.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1 * maxf(speed, 0.1)
		if not is_instance_valid(target) or target.is_dead() or not _alive(who):
			return
		if target.state not in ["hit", "block_hit", "charge_hit"]:
			break
	if target.state not in ["idle", "block"] or target.path.size() > 0:
		return
	var d: float = Vector2(who.position.x - target.position.x, who.position.z - target.position.z).length()
	if target.is_ranged(0) or d <= target.reach(0) + 0.5:
		_counter_from[target] = true
		target.strike(who, 0)


func _dir(a: Node3D, b: Node3D) -> Vector3:
	var d := b.position - a.position
	d.y = 0
	return d.normalized() if d.length() > 1e-3 else Vector3.ZERO


# --- Footman compatibility (the footman_anim QA scripts) ---------------------------------

## The footman strikes the dummy if it is close and roughly ahead, else the air.
func _attack() -> void:
	if footman == null:
		return
	var to: Vector3 = dummy.position - footman.position
	to.y = 0
	var near := to.length() < 3.0 and rad_to_deg(absf(angle_difference(footman.rotation.y, footman.yaw_of(to)))) < 80.0
	footman.attack(dummy if near else null)


# --- Picking ------------------------------------------------------------------------------

func _ground_at(screen: Vector2) -> Variant:
	return field.pick(cam.project_ray_origin(screen), cam.project_ray_normal(screen))


## The unit or dummy under a screen point: near its body anywhere from its feet
## to its head, on screen; the one nearest the camera wins.
func _pick_body(screen: Vector2) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for n in units + dummies:
		if not n.visible:
			continue
		var h: float = n.height_m() if n.has_method("height_m") else 1.7
		for f in [0.1, 0.35, 0.6, 0.85]:
			var p := cam.unproject_position(n.position + Vector3(0, h * f, 0))
			var d := p.distance_to(screen)
			if d < 0.34 * ppu * zoom:
				var depth := cam.global_position.distance_to(n.position)
				if depth < bd:
					bd = depth
					best = n
	return best


## A left click: a friend is selected (Shift adds), a foe or dummy attacked
## by the selection, the ground marched to. With `order_only` (right click) it
## never selects.
func click(screen: Vector2, add := false, order_only := false) -> void:
	var hit := _pick_body(screen)
	var lead := _sel()
	if hit and _is_unit(hit) and not order_only:
		if lead == null or hit.faction == lead.faction or add or Input.is_key_pressed(KEY_CTRL):
			if add:
				if hit in selected:
					selected.erase(hit)
					_select(selected.duplicate())
				else:
					_select(selected + [hit])
			else:
				_select(_group_of(hit))
			return
	var sq = _squad_sel()
	if hit and lead and _hostile(lead, hit) and sq:
		sq.attack(hit)
		return
	if hit and lead and _hostile(lead, hit):
		for u in selected:
			if _hostile(u, hit) and not u.is_dead():
				order_attack(u, hit, _armed)
		return
	if hit == dummy and lead == null and footman:
		footman.attack_target(dummy)
		return
	var g = _ground_at(screen)
	if g == null:
		return
	var t: Vector2i = field.tile_of(g)
	if not field.in_field(t):
		return
	if sq:
		if not sq.march_to(g):
			_flash("No way there for the squad")
		return
	march_to_tile(t)


# --- Input --------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_set_zoom(_zoom_goal * 1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_set_zoom(_zoom_goal / 1.12)
		elif event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if event.pressed:
				_dragging = true
				_drag_moved = 0.0
			else:
				_dragging = false
				if event.button_index == MOUSE_BUTTON_RIGHT and _drag_moved < 6.0:
					click(event.position, false, true)
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			click(event.position, event.shift_pressed)
	elif event is InputEventMouseMotion:
		if _dragging:
			_drag_moved += event.relative.length()
			if _drag_moved >= 6.0:
				follow = false
				_focus_goal = Vector3.INF
				_pan(event.relative)
		_hover(event.position)
	elif event is InputEventKey and not event.echo:
		var u := _sel()
		if event.keycode == KEY_B and footman and u == footman:
			footman.set_block(event.pressed)
			_refresh()
			return
		if not event.pressed:
			return
		if _squad_sel() and event.keycode in [KEY_1, KEY_SPACE, KEY_Q, KEY_E]:
			_squad_action({KEY_1: "attack", KEY_SPACE: "attack", KEY_Q: "wheel_l", KEY_E: "wheel_r"}[event.keycode])
			return
		if event.keycode >= KEY_1 and event.keycode <= KEY_8:
			var i: int = event.keycode - KEY_1
			if u and i < u.profile.get("attacks", []).size():
				_do_action("attack:%d" % i)
			return
		match event.keycode:
			KEY_TAB: select_next()
			KEY_ESCAPE: _select([])
			KEY_SPACE:
				if u:
					_do_action("attack:%d" % _armed)
			KEY_H: _react("hit")
			KEY_K: _react("die")
			KEY_R: _react("revive")
			KEY_F: _toggle("follow")
			KEY_G: _toggle("grid")
			KEY_V: _toggle("fog")
			KEY_N: _toggle("night")
			KEY_C:
				if u and u.has_method("charge"):
					_do_action("charge")
			KEY_X:
				if u and u.has_method("counter"):
					_do_action("counter")
			KEY_L:
				if u and u.has_method("step_lane"):
					_do_action("lane")
			KEY_P:
				if footman:
					_set_pace("game" if footman.pace == "walk" else "walk")
			KEY_Q:
				if u:
					u.turn_to(u.position + Vector3(sin(u.rotation.y + PI / 2), 0, cos(u.rotation.y + PI / 2)))
			KEY_E:
				if u:
					u.turn_to(u.position + Vector3(sin(u.rotation.y - PI / 2), 0, cos(u.rotation.y - PI / 2)))


func _pan(rel: Vector2) -> void:
	var k := 1.0 / (ppu * zoom)
	var right := Vector3(1, 0, -1).normalized()
	var down := Vector3(1, 0, 1).normalized()
	focus -= right * rel.x * k + down * rel.y * k / sin(deg_to_rad(ELEVATION))


func _hover(screen: Vector2) -> void:
	if _capturing:
		return
	_hover_unit = _pick_body(screen)
	var g = _ground_at(screen)
	_hover_tile = field.tile_of(g) if g != null else Vector2i(-99, -99)
	field.mat.set_shader_parameter("hover", Vector2(_hover_tile) if _hover_unit == null else Vector2(-99, -99))


# --- Frame ---------------------------------------------------------------------------------

func _process(dt: float) -> void:
	# Feet on the ground: the units have moved this frame (they process first).
	for n in units + dummies:
		n.position.y = field.ground_y(n.position.x, n.position.z)
	var keys := Vector2(Input.get_axis("cam_left", "cam_right"), Input.get_axis("cam_up", "cam_down"))
	if keys.length() > 0.0 and not _capturing:
		follow = false
		_focus_goal = Vector3.INF
		_pan(-keys * 900.0 * dt)
	var old := zoom
	zoom = lerpf(zoom, _zoom_goal, minf(1.0, dt * 10.0))
	if absf(zoom - old) > 1e-4:
		_apply_look()
	if squad:
		squad.tick(dt)
	var lead := _sel()
	var sq = _squad_sel()
	if follow and lead:
		_focus_goal = Vector3.INF
		var at: Vector3 = sq.centroid() if sq else lead.position
		focus = focus.lerp(at + Vector3(0, 0.85, 0), minf(1.0, dt * 4.0))
	elif _focus_goal != Vector3.INF:
		focus = focus.lerp(_focus_goal, minf(1.0, dt * 5.0))
		if focus.distance_to(_focus_goal) < 0.05:
			_focus_goal = Vector3.INF
	var lo := -3.0 * tile_m
	var hi := (Field3D.W + 2.0) * tile_m
	focus.x = clampf(focus.x, lo, hi)
	focus.z = clampf(focus.z, lo, hi)
	var el := deg_to_rad(ELEVATION)
	var d := Vector3(cos(el) * sin(PI / 4), sin(el), cos(el) * cos(PI / 4))
	cam.position = focus + d * 80.0
	cam.look_at(focus, Vector3.UP)
	cam.size = get_viewport().get_visible_rect().size.y / (ppu * zoom)
	sun.directional_shadow_max_distance = clampf(40.0 / zoom + 40.0, 40.0, 140.0)
	_update_fog(dt)
	_fade_t -= dt
	if _fade_t <= 0.0:
		_fade_t = 0.1
		_fade_crowns()
	_draw_rings()
	_flash_t = maxf(0.0, _flash_t - dt)
	_sprite_t += dt * speed
	_sprite_frame()
	_hud()


func _update_fog(dt: float) -> void:
	var eyes := []
	for u in units:
		if u.faction == "player" and not u.is_dead():
			var t: Vector2i = field.tile_of(u.position)
			if field.in_field(t):
				eyes.append({"x": t.x, "y": t.y})
	fog.update(eyes, dt)
	for u in units:
		u.visible = not fog_on or u.faction == "player" or fog.shows(field.tile_of(u.position))
	for d in dummies:
		d.visible = not fog_on or fog.explored.has(Grid.key(field.tile_of(d.position).x, field.tile_of(d.position).y))


## Tree crowns fade while a figure stands behind them (the battle's canopy fade).
func _fade_crowns() -> void:
	var view := Vector3(1, 0, 1).normalized()   # towards the camera, on the ground
	var figs := []
	for u in units:
		if u.visible:
			figs.append([u.position, cam.unproject_position(u.position + Vector3(0, u.height_m() * 0.6, 0))])
	for c in field.cards:
		if not String(c.kind).begins_with("tree"):
			continue
		var on := false
		var foot: Vector3 = c.foot
		var sf := cam.unproject_position(foot)
		var half: float = c.half_w * ppu * zoom
		var top: float = c.top * ppu * zoom
		for f in figs:
			# Behind the trunk (farther from the camera) and inside the crown on screen.
			if (f[0] - foot).dot(view) > -0.3:
				continue
			var sh: Vector2 = f[1]
			if absf(sh.x - sf.x) < half * 0.8 and sh.y < sf.y + 4.0 and sh.y > sf.y - top:
				on = true
				break
		field.set_card_faded(c, on)


## Selection rings on the ground under the selected units (gold) and the foe
## under the cursor (red), draped over the relief.
func _draw_rings() -> void:
	_ring_mesh.clear_surfaces()
	var rings := []
	for u in selected:
		if is_instance_valid(u) and u.visible:
			rings.append([u.position, Color(1.0, 0.84, 0.4, 0.95) if u.faction == "player" else Color(1.0, 0.55, 0.4, 0.95), 0.62])
	var lead := _sel()
	if _hover_unit and lead and _hostile(lead, _hover_unit) and _hover_unit.visible:
		rings.append([_hover_unit.position, Color(1.0, 0.3, 0.22, 0.95), 0.6])
	if rings.is_empty():
		return
	_ring_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rings:
		var col: Color = r[1]
		var pts := _ring_points(r[0], r[2])
		for i in range(0, pts.size() - 2, 2):
			for k in [0, 1, 3, 0, 3, 2]:
				_ring_mesh.surface_set_color(col)
				_ring_mesh.surface_add_vertex(pts[i + k])
	_ring_mesh.surface_end()


## A ring's points on the ground round `c`, inner and outer by turns. Sampling
## the relief is the costly part (a squad's six rings on the march), so the
## ground is sampled at eight points round the ring and eased between them,
## and a ring is kept while its unit stands still.
func _ring_points(c: Vector3, rad: float) -> PackedVector3Array:
	var key := Vector4(snappedf(c.x, 0.01), snappedf(c.y, 0.01), snappedf(c.z, 0.01), rad)
	if _ring_pts.has(key):
		return _ring_pts[key]
	if _ring_pts.size() > 64:
		_ring_pts.clear()
	var n := 40
	var m := 8
	var hs := PackedFloat32Array()
	for j in m:
		var a := TAU * j / m
		hs.append(field.ground_y(c.x + cos(a) * rad, c.z + sin(a) * rad) + 0.05)
	var pts := PackedVector3Array()
	for i in n + 1:
		var a := TAU * i / n
		var f := float(i * m) / n
		var j := int(f) % m
		var y := lerpf(hs[j], hs[(j + 1) % m], f - floorf(f))
		for rr in [rad - 0.07, rad]:
			pts.append(Vector3(c.x + cos(a) * rr, y, c.z + sin(a) * rr))
	_ring_pts[key] = pts
	return pts


func _hud() -> void:
	var u := _sel()
	var s := ""
	var sq = _squad_sel()
	if sq:
		s = "Footman squad · %s · %d of %d standing" % [sq.describe(), sq.standing(), sq.members.size()]
	elif u:
		var clip: String = String(u.player.current_animation)
		var shown := clip.get_slice("|", clip.get_slice_count("|") - 1)
		s = "%s · %s · %s %.2f s · %.2f m/s" % [u.title(), u.state, shown, u.player.current_animation_position, u.speed_now]
		if selected.size() > 1:
			s += "  (+%d)" % (selected.size() - 1)
	else:
		s = "Nothing selected"
	if _flash_t > 0.0:
		s += "\n" + _flash_text
	_status.text = s
	var hits := 0
	for d in dummies:
		hits += d.hits
	var t := _hover_tile
	var tinfo := ""
	if field.in_field(t):
		var tile: Dictionary = field.tile(t.x, t.y)
		tinfo = "tile %d,%d · %s%s · height %.1f" % [t.x, t.y, tile.terrain, (" · " + String(tile.prop)) if tile.has("prop") else "", float(tile.surface_h)]
	_info.text = "%s\nzoom %.2f · tile %.2f m · level %.2f m\nhits on the dummies %d · FPS %d" % [tinfo, zoom, tile_m, level_m, hits, Engine.get_frames_per_second()]


# --- Captures ------------------------------------------------------------------------------

## Review shots of the field, every unit, a march over the hill, the fog and
## the night, every unit's strike caught at its blow, a duel and the mage's
## spells, then quit:
##   tools/godot.sh --path . <this scene> -- --capture=<dir> [--shots=<prefix>]
## With --shots only the shots whose names start with the prefix are saved
## (the scenes before them still play, so the state is the same).
func _capture(dir: String, only := "") -> void:
	_capturing = true
	_cap_dir = dir
	_cap_only = only
	DirAccess.make_dir_recursive_absolute(dir)
	get_window().size = Vector2i(1600, 900)
	field.mat.set_shader_parameter("hover", Vector2(-99, -99))
	await _wait(1.0)
	var yard: Vector3 = field.on_ground(Field3D.YARD) + Vector3(0, 0.8, 0)
	# The field and the yard.
	await _shot("field_overview", 0.62, field.on_ground(Vector2(13.5, 13.5)))
	await _shot("yard_game_zoom", 1.0, yard)
	await _shot("yard_close", 2.0, yard)
	for u in _roster():
		_select([u])
		await _shot("unit_" + String(u.profile.id), 3.2, u.position + Vector3(0, u.height_m() * 0.5, 0), 0.4)
		await _shot("portrait_" + String(u.profile.id), 6.0, u.position + Vector3(0, u.height_m() * 0.5, 0), 0.3)
	# The player's units march up the north-east hill, the camera following.
	_select(_roster().filter(func(x): return x.faction == "player"))
	march_to_tile(Vector2i(18, 9))
	follow = true
	await _shot("march_start", 1.6, Vector3.INF, 2.5)
	await _shot("march_mid", 1.6, Vector3.INF, 5.0)
	var end := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < end and selected.any(func(x): return x.state != "idle" and x.state != "block"):
		await get_tree().process_frame
	await _shot("march_arrived", 1.6, Vector3.INF, 1.0)
	follow = false
	# The fog of war from the hill; the night with and without it.
	_toggle("fog")
	await _shot("fog_scouting", 0.8, field.on_ground(Vector2(15, 12)), 1.5)
	_toggle("night")
	await _shot("fog_night", 0.8, field.on_ground(Vector2(15, 12)), 0.6)
	_toggle("fog")
	await _shot("night", 1.6, field.on_ground(Vector2(17, 10)) + Vector3(0, 0.8, 0), 0.8)
	_toggle("night")
	reset_field()
	await _shot("pond", 1.6, field.on_ground(Vector2(6.5, 20.5)), 0.6)
	if squad:
		await _squad_shots()
	# Every unit strikes a dummy: caught as the blow lands (or the missile leaves).
	for u in _roster():
		reset_field()
		var d: Node3D = dummies[0]
		var at: float = u.reach(0) * 0.85 if not u.is_ranged(0) else 6.0
		u.position = d.position + Vector3(-1, 0, 0.35).normalized() * at
		u.rotation.y = u.yaw_of(d.position - u.position) if u.has_method("yaw_of") else atan2(d.position.x - u.position.x, d.position.z - u.position.z)
		_select([u])
		var mid: Vector3 = u.position.lerp(d.position, 0.5) + Vector3(0, 0.9, 0)
		await _shot("", 2.4, mid, 0.3)
		order_attack(u, d, 0)
		await _await_blow(u, 8.0)
		await _shot("strike_" + String(u.profile.id), 2.4, Vector3.INF, 0.06)
		await _shot("strike_" + String(u.profile.id) + "_after", 2.4, Vector3.INF, 0.5)
	# A duel: the footman cuts at the wolf scout, who strikes back.
	var wolf := _unit("wolf_scout")
	if footman and wolf:
		reset_field()
		wolf.position = footman.position + Vector3(1.6, 0, 0.2)
		wolf.rotation.y = atan2(-1.0, 0.0)
		_select([footman])
		await _shot("", 2.4, footman.position.lerp(wolf.position, 0.5) + Vector3(0, 0.9, 0), 0.3)
		order_attack(footman, wolf, 0)
		await _await_blow(footman, 6.0)
		await _shot("duel_blow", 2.4, Vector3.INF, 0.1)
		await _await_blow(wolf, 4.0)
		await _shot("duel_counter", 2.4, Vector3.INF, 0.06)
	# Lethal blows: the spearman runs the succubus through.
	var spear := _unit("spearman")
	var succ := _unit("succubus")
	if spear and succ:
		reset_field()
		_toggle("lethal")
		succ.position = spear.position + Vector3(2.2, 0, 0.3)
		succ.rotation.y = atan2(-1.0, 0.0)
		await _shot("", 2.2, spear.position.lerp(succ.position, 0.5) + Vector3(0, 0.9, 0), 0.3)
		order_attack(spear, succ, 0)
		await _await_blow(spear, 6.0)
		await _shot("lethal_fall", 2.2, Vector3.INF, 0.9)
		await _shot("lethal_dead", 2.2, Vector3.INF, 2.5)
		_toggle("lethal")
	# The mage's four spells at a dummy, each caught in flight.
	var mage := _unit("mage")
	if mage:
		for i in 4:
			reset_field()
			var d: Node3D = dummies[1]
			var r: float = minf(mage.reach(i) * 0.8, 6.0)
			mage.position = d.position + Vector3(-1, 0, 0.35).normalized() * r
			mage.rotation.y = atan2(d.position.x - mage.position.x, d.position.z - mage.position.z)
			_select([mage])
			await _shot("", 2.0, mage.position.lerp(d.position, 0.5) + Vector3(0, 0.9, 0), 0.3)
			order_attack(mage, d, i)
			await _await_blow(mage, 8.0)
			var kind := String(mage.attack_info(i).get("missile", "spell"))
			await _shot("spell_" + kind, 2.0, Vector3.INF, 0.18 if kind != "earth" else 0.45)
	get_tree().quit()


## The squad's shots: its ranks at rest, the march to the drill line, the
## front rank's blows with the rear rank ready, the ranks again, the same fight
## spread to a line of six, a march north and a lone foe. Prints who struck
## when (SQUAD lines).
func _squad_shots() -> void:
	reset_field()
	await _shot("squad_start_view", START_ZOOM, field.on_ground(START) + Vector3(0, 0.85, 0), 0.5)
	_select(squad.alive())
	var rest: Vector3 = squad.centroid() + Vector3(0, 0.9, 0)
	await _shot("squad_ranks", 3.0, rest, 1.0)
	await _shot("squad_ranks_close", 4.5, rest, 0.4)
	var line_at: Vector3 = drill[2].position.lerp(drill[3].position, 0.5)
	var fight_at: Vector3 = line_at - Vector3(1.6, 0, 0) + Vector3(0, 0.9, 0)
	await _shot("squad_field", 1.4, squad.centroid().lerp(line_at, 0.5) + Vector3(0, 0.9, 0), 0.3)
	var blows := []
	var t0 := [Time.get_ticks_msec()]
	var logs := {}
	for m in squad.members:
		logs[m] = func(_t, _l, _r):
			blows.append({"man": squad.members.find(m) + 1, "rank": squad._men[m].role, "s": (Time.get_ticks_msec() - t0[0]) / 1000.0})
		m.impact.connect(logs[m])
	var table := func(): return blows.map(func(b): return [b.man, b.rank, snappedf(b.s, 0.01)])
	# The front rank only (the default).
	squad.attack(drill[2])
	follow = true
	await _shot("squad_march", 1.8, Vector3.INF, 4.0)
	await _until(func(): return not blows.is_empty(), 40.0)
	follow = false
	await _shot("squad_front_rank", 2.4, fight_at, 0.12)
	await _until(func(): return _men_struck(blows) >= 3, 20.0)
	await _shot("squad_front_rank_all", 2.4, fight_at, 0.1)
	await _until(func(): return squad.mode == "reform", 40.0)
	await _shot("squad_reforming", 2.4, fight_at, 1.2)
	await _until(func(): return squad.mode == "idle", 30.0)
	await _shot("squad_reformed", 2.4, fight_at, 0.8)
	print("SQUAD front rank only, blows (man, rank, seconds): ", table.call())
	print("SQUAD rear rank held back: ", blows.all(func(b): return b.rank == "front"), ", men striking: ", _men_struck(blows))
	print("SQUAD re-formed: farthest man %.2f m off his place" % _squad_off())
	# The same fight spread to the line.
	blows.clear()
	t0[0] = Time.get_ticks_msec()
	squad.wide = true
	squad.attack(drill[2])
	await _until(func(): return _men_struck(blows) >= squad.standing(), 40.0)
	await _shot("squad_line", 2.4, fight_at, 0.1)
	await _until(func(): return squad.mode == "idle", 40.0)
	squad.wide = false
	print("SQUAD spread to the line, blows: ", table.call())
	print("SQUAD first three blows by the front rank: ", blows.slice(0, 3).all(func(b): return b.rank == "front"), ", men striking: ", _men_struck(blows))
	print("SQUAD re-formed after the line: farthest man %.2f m off his place" % _squad_off())
	for m in squad.members:
		m.impact.disconnect(logs[m])
	# A march north into the yard, the ranks wheeling with the route.
	squad.march_to(field.on_ground(Vector2(14.0, 18.3)))
	follow = true
	await _shot("squad_wheel", 2.0, Vector3.INF, 5.0)
	await _until(func(): return squad.mode == "idle", 30.0)
	await _shot("squad_arrived", 2.0, Vector3.INF, 0.5)
	follow = false
	# A lone foe: the front rank turns on it.
	var wolf := _unit("wolf_scout")
	if wolf:
		wolf.position = field.on_ground(Vector2(16.5, 16.5))
		wolf.rotation.y = Squad3D.yaw_to(wolf.position, squad.centroid())
		squad.attack(wolf)
		await _until(func(): return squad.engaged, 30.0)
		await _shot("squad_lone_foe", 2.4, wolf.position.lerp(squad.center, 0.5) + Vector3(0, 0.9, 0), 0.6)
		await _until(func(): return squad.mode == "idle", 40.0)
	reset_field()


## How many of the squad's men struck the blows logged.
static func _men_struck(blows: Array) -> int:
	var seen := {}
	for b in blows:
		seen[b.man] = true
	return seen.size()


## The farthest any of the squad's men stands from his place, metres.
func _squad_off() -> float:
	var err := 0.0
	var spots: Array = Squad3D.slots(squad.center, squad.yaw, squad.standing())
	for m in squad.alive():
		err = maxf(err, Squad3D.flat(m.position - spots[squad._men[m].slot]).length())
	return err


## Until `cond` holds (or `timeout` seconds pass).
func _until(cond: Callable, timeout: float) -> void:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await get_tree().process_frame
	if not cond.call():
		print("CAPTURE waited %.0f s in vain" % timeout)


## One review shot: the camera at `zoom` over `at` (Vector3.INF keeps it
## where it is), `wait` seconds later. A shot with no name only places the camera.
func _shot(shot: String, z: float, at: Vector3, wait := 0.3) -> void:
	zoom = z
	_zoom_goal = z
	if at != Vector3.INF:
		focus = at
	_apply_look()
	await _wait(wait)
	if shot == "" or (_cap_only != "" and not shot.begins_with(_cap_only)):
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_cap_dir.path_join(shot + ".png"))
	print("CAPTURE ", shot)


## Until `u` lands a blow or lets a missile go (or `timeout` seconds pass).
func _await_blow(u: Node3D, timeout: float) -> void:
	var done := [false]
	var on_impact := func(_t, _l, _r): done[0] = true
	var on_release := func(_t, _k): done[0] = true
	u.impact.connect(on_impact)
	u.release.connect(on_release)
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not done[0] and Time.get_ticks_msec() < end:
		await get_tree().process_frame
	u.impact.disconnect(on_impact)
	u.release.disconnect(on_release)
	if not done[0]:
		print("CAPTURE no blow from the %s in %.0f s" % [u.title(), timeout])


# --- The tour ------------------------------------------------------------------------------

## A short tour for a video, panels hidden: the field, the roster, a march
## over the hill, the fog by day and night, a duel, every kind of strike, the
## mage's spells, a lethal thrust and the footman squad's fight, then quit.
## Timed in game time, so the movie maker can record it frame by frame:
##   tools/godot.sh --path . --resolution 1600x900 --fixed-fps 30 --write-movie <file.avi> <this scene> -- --tour
func _tour() -> void:
	_capturing = true
	ui.visible = false
	_rings.visible = false
	field.mat.set_shader_parameter("hover", Vector2(-99, -99))
	var yard: Vector3 = field.on_ground(Field3D.YARD) + Vector3(0, 0.8, 0)
	# The field, then down into the yard and along the roster.
	await _glide(field.on_ground(Vector2(13.5, 13.5)), 0.62, 0.0)
	await _hold(1.2)
	await _glide(yard, 1.5, 3.5)
	for u in _roster():
		await _glide(u.position + Vector3(0, u.height_m() * 0.5, 0), 3.0, 0.8)
		await _hold(0.5)
	# The player's units march up the north-east hill.
	_select(_roster().filter(func(x): return x.faction == "player"))
	march_to_tile(Vector2i(18, 9))
	await _glide(_sel().position + Vector3(0, 0.85, 0), 1.6, 1.0)
	follow = true
	var left := 9.0
	while left > 0.0 and selected.any(func(x): return x.state != "idle" and x.state != "block"):
		await get_tree().process_frame
		left -= get_process_delta_time()
	await _hold(0.6)
	follow = false
	_route = {}
	field.mark(_route)
	# The fog of war from the hill, by day and by night.
	_toggle("fog")
	await _glide(field.on_ground(Vector2(15, 12)), 0.8, 2.0)
	await _hold(1.2)
	_toggle("night")
	await _hold(1.8)
	_toggle("fog")
	await _glide(field.on_ground(Vector2(17, 10)) + Vector3(0, 0.8, 0), 1.6, 1.5)
	await _hold(1.2)
	_toggle("night")
	# A duel: the footman cuts at the wolf scout, who strikes back.
	var wolf := _unit("wolf_scout")
	if footman and wolf:
		reset_field()
		wolf.position = footman.position + Vector3(1.6, 0, 0.2)
		wolf.rotation.y = atan2(-1.0, 0.0)
		_select([footman])
		await _glide(footman.position.lerp(wolf.position, 0.5) + Vector3(0, 0.9, 0), 3.2, 0.0)
		await _hold(0.4)
		order_attack(footman, wolf, 0)
		await _hold(3.6)
	# The crossbow, the succubus's whip and the mage's four spells at a dummy.
	for id in ["crossbowman", "succubus"]:
		var u := _unit(id)
		if u:
			await _strike(u, dummies[0], 0, 6.0 if u.is_ranged(0) else u.reach(0) * 0.85, 2.4)
	var mage := _unit("mage")
	if mage:
		for i in 4:
			await _strike(mage, dummies[1], i, minf(mage.reach(i) * 0.8, 6.0), 2.2)
	# Lethal blows: the spearman runs the succubus through.
	var spear := _unit("spearman")
	var succ := _unit("succubus")
	if spear and succ:
		reset_field()
		_toggle("lethal")
		succ.position = spear.position + Vector3(2.2, 0, 0.3)
		succ.rotation.y = atan2(-1.0, 0.0)
		await _glide(spear.position.lerp(succ.position, 0.5) + Vector3(0, 0.9, 0), 3.0, 0.0)
		await _hold(0.4)
		order_attack(spear, succ, 0)
		await _hold(3.8)
		_toggle("lethal")
	# The footman squad: up to the drill line in formation, the front rank's
	# blows while the rear rank stands ready, then its ranks again.
	if squad:
		reset_field()
		_select(squad.alive())
		await _glide(squad.centroid() + Vector3(0, 0.9, 0), 2.6, 1.5)
		await _hold(0.8)
		squad.attack(drill[2])
		follow = true
		await _hold_until(func(): return squad.engaged, 20.0)
		follow = false
		var line_at: Vector3 = drill[2].position.lerp(drill[3].position, 0.5)
		await _glide(line_at - Vector3(1.6, -0.9, 0), 3.4, 1.0)
		await _hold_until(func(): return squad.mode == "idle", 25.0)
		await _hold(1.0)
	# Back out over the yard.
	reset_field()
	await _glide(yard, 2.2, 0.0)
	await _hold(0.4)
	await _glide(field.on_ground(Vector2(13.5, 14.5)), 0.75, 3.0)
	await _hold(1.0)
	get_tree().quit()


## `u` strikes `d` with attack `i` from `dist` metres, the camera close on both.
func _strike(u: Node3D, d: Node3D, i: int, dist: float, hold: float) -> void:
	reset_field()
	u.position = d.position + Vector3(-1, 0, 0.35).normalized() * dist
	u.rotation.y = atan2(d.position.x - u.position.x, d.position.z - u.position.z)
	_select([u])
	await _glide(u.position.lerp(d.position, 0.5) + Vector3(0, 0.9, 0), 2.6 if dist > 3.0 else 3.2, 0.0)
	await _hold(0.4)
	order_attack(u, d, i)
	await _hold(hold)


## The camera eased to `at` and `z` over `t` seconds of game time (at once if 0).
func _glide(at: Vector3, z: float, t: float) -> void:
	var f0 := focus
	var z0 := zoom
	var s := 0.0
	while true:
		var k := smoothstep(0.0, 1.0, s / t) if t > 0.0 else 1.0
		focus = f0.lerp(at, k)
		zoom = lerpf(z0, z, k)
		_zoom_goal = zoom
		_apply_look()
		await get_tree().process_frame
		if k >= 1.0:
			return
		s += get_process_delta_time()


func _hold(t: float) -> void:
	var left := t
	while left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()


## Until `cond` holds, at most `t` seconds of game time (the tour's movie runs on it).
func _hold_until(cond: Callable, t: float) -> void:
	var left := t
	while left > 0.0 and not cond.call():
		await get_tree().process_frame
		left -= get_process_delta_time()


func _unit(id: String) -> Node3D:
	for u in units:
		if u.profile.id == id:
			return u
	return null


func _wait(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
