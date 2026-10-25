## The 3D battlefields: four places of the Meridius frontier in four seasons,
## built from the battle's own pieces (its relief ground and textures, the
## painted woodland and the terrain kits' houses, ruins and farm things, the
## fog of war) and seen through the game's camera (orthographic, 30 degrees
## down, tiles 128 x 64 px and a soldier 49 px tall at zoom 1, as the 3D
## sandbox in prototypes/sandbox3d). No units: scouts (invisible eyes, placed
## with a click) uncover the fog by the battle's sight rules.
##   tools/godot.sh --path . res://prototypes/battlefields3d/scenes/battlefields3d.tscn
##   ... -- --field=<id>                                  open on a field
##   ... -- --capture=<dir> [--clean] [--fields=a,b]      review captures, then quit
## Nothing here touches the game's state, saves or production scenes. See README.md here.
extends Node3D

const Field = preload("res://prototypes/battlefields3d/scripts/bf_field.gd")
const Fields = preload("res://prototypes/battlefields3d/scripts/bf_fields.gd")
const Fog = preload("res://prototypes/battlefields3d/scripts/bf_fog.gd")
const Weather = preload("res://prototypes/battlefields3d/scripts/bf_weather.gd")
const Grid = preload("res://scripts/rules/grid.gd")
const UI = preload("res://scripts/ui/ui.gd")

const SOLDIER_PX := 49.0
const TILE_PX := 128.0
const LEVEL_PX := 26.0
const ELEVATION := 30.0
const FOOTMAN_META := "res://prototypes/footman_anim/art3d/footman.json"
const ZOOM_MIN := 0.5
const ZOOM_MAX := 4.0
const MAX_SCOUTS := 8
## The night's paint over the day's colours, per season (moonlit snow stays pale).
const NIGHT_PAINT := {"summer": Vector3(0.42, 0.5, 0.72), "autumn": Vector3(0.44, 0.48, 0.68),
	"winter": Vector3(0.5, 0.58, 0.84), "spring": Vector3(0.42, 0.5, 0.72)}
const BG := {"day": Color(0.07, 0.09, 0.07), "night": Color(0.02, 0.03, 0.05), "winter": Color(0.1, 0.11, 0.13)}

var ppu := 33.0
var tile_m := 2.72
var level_m := 0.9
var zoom := 1.0
var _zoom_goal := 1.0
var fog_on := false
var night := false
var grid_on := false
var weather_on := true
var clean := false
var field_id := ""
var cam: Camera3D
var env: Environment
var field
var fog
var weather
var focus := Vector3.ZERO
var scouts: Array = []
var ui: CanvasLayer
var _blurb: Label
var _info: Label
var _status: Label
var _buttons := {}
var _dragging := false
var _drag_moved := 0.0
var _hover_tile := Vector2i(-99, -99)
var _flash_text := ""
var _flash_t := 0.0
var _capturing := false
var _cap_dir := ""


func _ready() -> void:
	# Smooth edges: the 3D is drawn at twice the size and scaled down.
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	get_viewport().scaling_3d_scale = 2.0
	var fm_meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FOOTMAN_META))
	var h: float = fm_meta.get("height_m", 1.7)
	ppu = SOLDIER_PX / (h * cos(deg_to_rad(ELEVATION)))
	tile_m = TILE_PX / (sqrt(2.0) * ppu)
	level_m = LEVEL_PX / (ppu * cos(deg_to_rad(ELEVATION)))
	_build_world()
	var args := OS.get_cmdline_user_args()
	clean = args.has("--clean")
	var first: String = Fields.IDS[0]
	for a in args:
		if a.begins_with("--field="):
			first = a.trim_prefix("--field=")
	_build_ui()
	load_field(first)
	get_window().title = "Meridius - 3D battlefields"
	if clean:
		ui.visible = false
	for arg in args:
		if arg.begins_with("--capture="):
			var only: Array = []
			for a in args:
				if a.begins_with("--fields="):
					only = Array(a.trim_prefix("--fields=").split(","))
			_capture(arg.trim_prefix("--capture="), only)


func _build_world() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	add_child(we)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 0.1
	cam.far = 400.0
	add_child(cam)
	cam.make_current()


## Builds a field (dropping the one shown), its fog of war and its weather.
func load_field(id: String) -> void:
	if Fields.make(id).is_empty():
		return
	if field:
		field.queue_free()
		weather.queue_free()
	field_id = id
	field = Field.new()
	field.name = "Field"
	add_child(field)
	field.build(id, tile_m, level_m, ELEVATION, ppu)
	fog = Fog.new(field.map)
	field.set_shared("fog_tex", fog.tex)
	field.set_shared("fog_on", fog_on)
	field.mat.set_shader_parameter("grid_on", grid_on)
	weather = Weather.new()
	weather.name = "Weather"
	add_child(weather)
	weather.build(field.data.weather, field.smoke, Vector2(Field.W, Field.H), tile_m)
	weather.set_shared("fog_tex", fog.tex)
	weather.set_shared("fog_on", fog_on)
	weather.set_falling(weather_on)
	scouts = field.data.scouts.duplicate()
	focus = field.on_ground(field.data.focus)
	weather.follow(focus)
	_mark_scouts()
	_apply_light()
	if _blurb:
		_blurb.text = "%s\n%s" % [field.data.name.to_upper(), field.data.blurb]
	_refresh()


# --- UI -----------------------------------------------------------------------------------

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	var side := UI.panel("DarkPanel", [16, 22])
	side.offset_left = 16
	side.offset_top = 16
	side.offset_right = 16 + 380
	root.add_child(side)
	var col := UI.vbox(8)
	side.add_child(col)
	col.add_child(UI.cinzel("3D BATTLEFIELDS", 22, 700, UI.LIGHT_TITLE))
	col.add_child(_note("Four places of the frontier in four seasons, in the battle's look. Click the ground to post a scout: the fog of war lifts by the battle's sight rules."))
	col.add_child(_head("FIELDS"))
	var fields := UI.grid(2, 6, 6)
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in Fields.IDS:
		var f := Fields.make(id)
		fields.add_child(_button("%s · %s" % [f.name, f.season], func(): load_field(id), "field:" + id, true))
	col.add_child(fields)
	_blurb = _note("")
	col.add_child(_blurb)
	var right := UI.panel("DarkPanel", [16, 22])
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -16 - 380
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
	rc.add_child(_row([["Night", func(): _toggle("night")], ["Weather", func(): _toggle("weather")], ["Grid", func(): _toggle("grid")]], ["tog:Night", "tog:Weather", "tog:Grid"]))
	rc.add_child(_row([["Reset scouts", func(): _reset_scouts()], ["Clear scouts", func(): _clear_scouts()]], []))
	rc.add_child(UI.label("CAMERA", "SmallLabel", 13, UI.DARK_MUTED))
	rc.add_child(_row([["Field", func(): _frame_field()], ["1x", func(): _set_zoom(1.0)], ["2x", func(): _set_zoom(2.0)], ["3x", func(): _set_zoom(3.0)]], []))
	rc.add_child(_button("Quit", func(): get_tree().quit()))
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
	help.add_child(UI.label("Left click: post or recall a scout   Right click: recall the nearest   Right / middle drag, WASD: pan   Wheel: zoom   1-4: fields   V fog · N night · T weather · G grid · X forget · Home: whole field", "SmallLabel", 15, UI.DARK_MUTED))


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


func _refresh() -> void:
	var on := {"tog:Fog of war": fog_on, "tog:Night": night, "tog:Weather": weather_on, "tog:Grid": grid_on}
	for id in Fields.IDS:
		on["field:" + id] = id == field_id
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
			weather.set_shared("fog_on", fog_on)
		"grid":
			grid_on = not grid_on
			field.mat.set_shader_parameter("grid_on", grid_on)
		"night":
			night = not night
			_apply_light()
		"weather":
			weather_on = not weather_on
			weather.set_falling(weather_on)
	_refresh()


func _forget() -> void:
	fog.forget()
	_flash("Explored ground forgotten: only what the scouts see now stays clear")


func _apply_light() -> void:
	var season: String = field.season
	var paint: Vector3 = NIGHT_PAINT[season] if night else Vector3.ONE
	var bg: Color = BG.night if night else (BG.winter if season == "winter" else BG.day)
	env.background_color = bg
	field.set_shared("night", paint)
	field.mat.set_shader_parameter("deep", Vector3(bg.r, bg.g, bg.b))
	field.set_glow(night)
	weather.set_shared("night", paint)


func _set_zoom(z: float) -> void:
	_zoom_goal = clampf(z, ZOOM_MIN, ZOOM_MAX) if not _capturing else z


func _frame_field() -> void:
	focus = field.on_ground(Vector2(Field.W, Field.H) * 0.5 - Vector2(0.5, 0.5))
	_set_zoom(0.62)


# --- Scouts ------------------------------------------------------------------------------

func _mark_scouts() -> void:
	var m := {}
	if not clean:
		for s in scouts:
			m[s] = 2
	field.mark(m)


func _reset_scouts() -> void:
	scouts = field.data.scouts.duplicate()
	_mark_scouts()


func _clear_scouts() -> void:
	scouts.clear()
	_mark_scouts()


func _ground_at(screen: Vector2) -> Variant:
	return field.pick(cam.project_ray_origin(screen), cam.project_ray_normal(screen))


## Posts a scout on the clicked tile, or recalls the one standing there.
func click(screen: Vector2, recall := false) -> void:
	var g = _ground_at(screen)
	if g == null:
		return
	var t: Vector2i = field.tile_of(g)
	if not field.in_field(t):
		return
	if recall:
		if scouts.is_empty():
			return
		var best: Vector2i = scouts[0]
		for s in scouts:
			if Vector2(s - t).length() < Vector2(best - t).length():
				best = s
		scouts.erase(best)
	elif scouts.has(t):
		scouts.erase(t)
	else:
		if scouts.size() >= MAX_SCOUTS:
			scouts.pop_front()
		scouts.append(t)
		if not fog_on:
			_flash("Scout posted: turn the fog of war on (V) to see what it sees")
	_mark_scouts()


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
					click(event.position, true)
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			click(event.position)
	elif event is InputEventMouseMotion:
		if _dragging:
			_drag_moved += event.relative.length()
			if _drag_moved >= 6.0:
				_pan(event.relative)
		_hover(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_4:
			load_field(Fields.IDS[event.keycode - KEY_1])
			return
		match event.keycode:
			KEY_V: _toggle("fog")
			KEY_N: _toggle("night")
			KEY_G: _toggle("grid")
			KEY_T: _toggle("weather")
			KEY_X: _forget()
			KEY_HOME: _frame_field()


func _pan(rel: Vector2) -> void:
	var k := 1.0 / (ppu * zoom)
	var right := Vector3(1, 0, -1).normalized()
	var down := Vector3(1, 0, 1).normalized()
	focus -= right * rel.x * k + down * rel.y * k / sin(deg_to_rad(ELEVATION))


func _hover(screen: Vector2) -> void:
	if _capturing:
		return
	var g = _ground_at(screen)
	_hover_tile = field.tile_of(g) if g != null else Vector2i(-99, -99)
	field.mat.set_shader_parameter("hover", Vector2(_hover_tile))


# --- Frame ---------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if field == null:
		return
	var keys := Vector2(Input.get_axis("cam_left", "cam_right"), Input.get_axis("cam_up", "cam_down"))
	if keys.length() > 0.0 and not _capturing:
		_pan(-keys * 900.0 * dt)
	zoom = lerpf(zoom, _zoom_goal, minf(1.0, dt * 10.0))
	var lo := -4.0 * tile_m
	var hi := (Field.W + 3.0) * tile_m
	focus.x = clampf(focus.x, lo, hi)
	focus.z = clampf(focus.z, lo, hi)
	var el := deg_to_rad(ELEVATION)
	var d := Vector3(cos(el) * sin(PI / 4), sin(el), cos(el) * cos(PI / 4))
	cam.position = focus + d * 80.0
	cam.look_at(focus, Vector3.UP)
	cam.size = get_viewport().get_visible_rect().size.y / (ppu * zoom)
	var eyes := []
	for s in scouts:
		eyes.append({"x": s.x, "y": s.y})
	fog.update(eyes, dt)
	weather.follow(focus)
	_flash_t = maxf(0.0, _flash_t - dt)
	_hud()


func _hud() -> void:
	var s := "%s · %s%s · %d scouts" % [field.data.name, field.season, " · frozen" if field.data.frozen else "", scouts.size()]
	if _flash_t > 0.0:
		s += "\n" + _flash_text
	_status.text = s
	var t := _hover_tile
	var tinfo := ""
	if field.in_field(t):
		var tile: Dictionary = field.tile(t.x, t.y)
		var sight := ""
		if fog_on:
			sight = " · seen" if fog.shows(t) else (" · explored" if fog.explored.has(Grid.key(t.x, t.y)) else " · unexplored")
		tinfo = "tile %d,%d · %s%s · height %.1f%s" % [t.x, t.y, tile.terrain, (" · " + String(tile.prop)) if tile.has("prop") else "", float(tile.surface_h), sight]
	_info.text = "%s\nzoom %.2f · tile %.2f m · level %.2f m\nFPS %d" % [tinfo, zoom, tile_m, level_m, Engine.get_frames_per_second()]


# --- Captures ------------------------------------------------------------------------------

## Review shots of every field (or those named by --fields): the whole field,
## the game's zoom, a close look, the fog of war by the scouts by day and by
## night, and the night without fog, then quit.
func _capture(dir: String, only: Array) -> void:
	_capturing = true
	_cap_dir = dir
	DirAccess.make_dir_recursive_absolute(dir)
	get_window().size = Vector2i(1600, 900)
	for id in Fields.IDS:
		if not only.is_empty() and id not in only:
			continue
		load_field(id)
		field.mat.set_shader_parameter("hover", Vector2(-99, -99))
		await field.wait_baked()
		await _wait(1.0)
		var data: Dictionary = field.data
		var mid: Vector3 = field.on_ground(Vector2(13.5, 13.5))
		var at: Vector3 = field.on_ground(data.focus)
		var close: Vector3 = field.on_ground(data.close)
		await _shot(id + "_overview", 0.62, mid)
		await _shot(id + "_game", 1.0, at)
		await _shot(id + "_close", 2.0, close)
		_toggle("fog")
		await _shot(id + "_fog", 0.8, at, 1.8)
		_toggle("night")
		await _shot(id + "_fog_night", 0.8, at, 0.6)
		_toggle("fog")
		await _shot(id + "_night", 1.4, close, 0.8)
		_toggle("night")
	get_tree().quit()


func _shot(shot: String, z: float, at: Vector3, wait := 0.4) -> void:
	zoom = z
	_zoom_goal = z
	focus = at
	await _wait(wait)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_cap_dir.path_join(shot + ".png"))
	print("CAPTURE ", shot)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout
