## 3D footman sandbox: one rigged footman on the battle map's grass, seen
## through the game's camera (orthographic, 30 degrees down, tiles 128 x 64 px
## and a soldier 49 px tall at zoom 1, as in squad_view.gd), with a straw dummy.
##   tools/godot.sh --path . res://prototypes/footman_anim/scenes/footman3d_sandbox.tscn
## Left-click the ground to march there along the tiles, click the dummy to
## attack it. Nothing here touches the game's state, saves or production units.
extends Node3D

const Footman3D = preload("res://prototypes/footman_anim/scripts/footman3d.gd")
const Dummy3D = preload("res://prototypes/footman_anim/scripts/dummy3d.gd")
const Succubus3D = preload("res://prototypes/footman_anim/scripts/succubus3d.gd")
const GROUND := preload("res://prototypes/footman_anim/shaders/ground3d.gdshader")
const GRASS := preload("res://assets/terrain/grass.webp")
## The game's footman sprite (squadgen sheet) for comparison: its scale and
## the squad member scale (squad_view.gd MEMBER_SCALE), idle frames 0 1 2 1.
const SPRITE_DOC := "res://assets/sprites/anim/footman.json"
const MEMBER_SCALE := 0.52
const IDLE_FRAME := 0.42
## Where the comparison sprite stands (tile), beside his start on screen.
const SPRITE_TILE := Vector2i(1, -1)
## The 3D succubus (art/succubus_3d) and one of the game's tree props, for a
## look at a 3D unit among the 2D world art. The tree stands upright (turning
## only about the vertical) and is stretched by 1 / cos(ELEVATION), so the
## painted sprite keeps its shape and the depth buffer sorts her in front of
## or behind it.
const SUCC_TILE := Vector2i(-1, 1)
const TREE_TILE := Vector2i(-2, -1)
const TREE_KEY := "tree_oak"

## Game scale: a squad soldier stands SOLDIER_PX world px tall at zoom 1 and a
## tile is TILE_PX wide (squad_view.gd member_height, formation.gd).
const SOLDIER_PX := 49.0
const TILE_PX := 128.0
const ELEVATION := 30.0
## The file spacing of a squad (prototypes formation.gd FILE, in tiles): one step into a lane.
const FILE := 0.41
const FACINGS := {"SE": Vector3(1, 0, 0), "SW": Vector3(0, 0, 1), "NW": Vector3(-1, 0, 0), "NE": Vector3(0, 0, -1)}
const OUTLINE_PX := 2.0

var ppu := 33.0
var tile_m := 2.72
var zoom := 3.0
var _zoom_goal := 3.0
var look := "toon"
var outline := true
var follow := true
var cam: Camera3D
var sun: DirectionalLight3D
var ground: MeshInstance3D
var ground_mat: ShaderMaterial
var footman: Node3D
var dummy: Node3D
var succ: Node3D
var tree: Sprite3D
var focus := Vector3.ZERO
var sprite: Sprite3D
var _sprite_doc: Dictionary
var _sprite_t := 0.0
var _sprite_tex := {}
var ui: CanvasLayer
var info: Label
var _buttons := {}
var _dragging := false
var _flash_text := ""
var _flash_t := 0.0


func _ready() -> void:
	# Smooth edges: the 3D is drawn at twice the size and scaled down
	# (the Compatibility renderer drops the ink line under MSAA).
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	get_viewport().scaling_3d_scale = 2.0
	footman = Footman3D.new()
	footman.name = "Footman"
	add_child(footman)
	# The scale comes from his standing height in the clips' sidecar.
	var h: float = footman.meta.get("height_m", 1.7)
	ppu = SOLDIER_PX / (h * cos(deg_to_rad(ELEVATION)))
	tile_m = TILE_PX / (sqrt(2.0) * ppu)
	footman.tile_m = tile_m
	footman.rotation.y = footman.yaw_of(FACINGS.SE)
	footman.impact.connect(_on_impact)
	dummy = Dummy3D.new()
	dummy.name = "Dummy"
	dummy.position = Vector3(2, 0, 1) * tile_m
	add_child(dummy)
	succ = Succubus3D.new()
	succ.name = "Succubus"
	add_child(succ)
	succ.position = Vector3(SUCC_TILE.x, 0, SUCC_TILE.y) * tile_m
	succ.rotation.y = footman.yaw_of(FACINGS.SE)
	_build_world()
	_build_sprite()
	_build_tree()
	_build_ui()
	focus = Vector3(0, 0.85, 0)
	_apply_look()
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--capture="):
			var only := ""
			for a in args:
				if a.begins_with("--shots="):
					only = a.trim_prefix("--shots=")
			_capture(arg.trim_prefix("--capture="), only, args.has("--seq"))


## Screenshots of the succubus beside the footman, his game sprite and the tree,
## then quit (tools/godot.sh --path . <this scene> -- --capture=<dir>).
## --shots=<prefix> takes only the shots named so (fx_ for the whip slash, with
## and without its effects); --seq then also saves the attack frame by frame at
## 1/120 s with the effects (seq/####.png), for a video.
func _capture(dir: String, only := "", seq := false) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	get_window().size = Vector2i(1280, 800)
	ui.visible = false
	follow = false
	var mid := (succ.position + footman.position + tree.position) / 3.0 + Vector3(0, 0.6, 0)
	var shots := [
		["overview_game_zoom", 1.0, mid, func(): succ.play("idle")],
		["overview_close", 2.0, mid, func(): pass],
		["her_close_idle", 4.0, succ.position + Vector3(0, 1.0, 0), func(): pass],
		["her_close_attack", 4.0, succ.position + Vector3(0, 1.0, 0), func(): succ.play("attack")],
		["her_attack_strike", 2.0, succ.position + Vector3(0, 0.8, 0), func(): succ.play("attack")],
		["her_attack_strike2", 2.0, succ.position + Vector3(0, 0.8, 0), func(): succ.play("attack")],
		["her_flourish_head", 4.0, succ.position + Vector3(0, 1.2, 0), func(): succ.play("idle_flourish")],
		["lash_f28_strike", 2.5, succ.position + Vector3(0, 0.6, 0), func(): succ.pose_at("attack", 27 / 30.0)],
		["lash_f38", 2.5, succ.position + Vector3(0, 0.8, 0), func(): succ.pose_at("attack", 37 / 30.0)],
		["lash_f52_strike2", 2.5, succ.position + Vector3(0, 1.0, 0), func(): succ.pose_at("attack", 51 / 30.0)],
		["lash_f52_close", 8.0, succ.position + Vector3(0, 2.2, 0), func(): succ.pose_at("attack", 51 / 30.0)],
		["flourish_f166", 4.0, succ.position + Vector3(0, 1.2, 0), func(): succ.pose_at("idle_flourish", 165 / 30.0)],
		["flourish_f220", 4.0, succ.position + Vector3(0, 0.9, 0), func(): succ.pose_at("idle_flourish", 219 / 30.0)],
		["walk_past_tree", 2.2, tree.position + Vector3(-0.6, 0.8, 0.6), func(): _succ_walk()],
		["death", 2.4, succ.position + Vector3(0, 0.4, 0), func(): succ.position = Vector3(SUCC_TILE.x, 0, SUCC_TILE.y) * tile_m; succ.play("death")],
	]
	# The whip slash (whip_fx.gd) at held clip times, facing SE and SW, with and
	# without its effects: each strike's sweep, crack and fade, and the first one's recoil.
	var home := Vector3(SUCC_TILE.x, 0, SUCC_TILE.y) * tile_m
	var high := home + Vector3(0, 1.5, 0)
	for f in [["s1_grow", 0.85], ["s1_crack", 26 / 30.0], ["s1_recoil", 28 / 30.0], ["s1_fade", 1.0],
			["s2_grow", 1.68], ["s2_crack", 51 / 30.0], ["s2_fade", 1.82]]:
		shots.append(["fx_se_" + f[0], 3.0, high, _fx_pose.bind(FACINGS.SE, f[1], true)])
	for f in [["s1_crack", 26 / 30.0], ["s2_crack", 51 / 30.0]]:
		shots.append(["fx_se_" + f[0] + "_off", 3.0, high, _fx_pose.bind(FACINGS.SE, f[1], false)])
		shots.append(["fx_sw_" + f[0], 3.0, high, _fx_pose.bind(FACINGS.SW, f[1], true)])
		shots.append(["fx_sw_" + f[0] + "_off", 3.0, high, _fx_pose.bind(FACINGS.SW, f[1], false)])
		shots.append(["fx_game_" + f[0], 1.0, high, _fx_pose.bind(FACINGS.SE, f[1], true)])
		shots.append(["fx_game_" + f[0] + "_off", 1.0, high, _fx_pose.bind(FACINGS.SE, f[1], false)])
	if only != "":
		shots = shots.filter(func(x): return String(x[0]).begins_with(only))
	var waits := {"her_close_attack": 1.25, "her_attack_strike": 0.85, "her_attack_strike2": 1.68,
		"her_flourish_head": 5.5, "walk_past_tree": 1.9, "death": 3.2}
	for s in shots:
		zoom = s[1]
		_zoom_goal = s[1]
		focus = s[2]
		_apply_look()
		s[3].call()
		var t: float = waits.get(s[0], 0.15 if String(s[0]).begins_with("fx_") else 0.6)
		var end := Time.get_ticks_msec() + int(t * 1000.0)
		while Time.get_ticks_msec() < end:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join(s[0] + ".png"))
		print("CAPTURE ", s[0])
	if seq:
		DirAccess.make_dir_recursive_absolute(dir.path_join("seq"))
		zoom = 3.0
		_zoom_goal = 3.0
		focus = Vector3(SUCC_TILE.x, 0, SUCC_TILE.y) * tile_m + Vector3(0, 1.5, 0)
		_apply_look()
		var n := 0
		for i in range(54, 295):
			_fx_pose(FACINGS.SE, i / 120.0, true)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(dir.path_join("seq/%04d.png" % n))
			n += 1
		print("CAPTURE seq ", n)
	get_tree().quit()


## Her attack held at clip time `t`, facing `dir`, with or without the slash effects.
func _fx_pose(dir: Vector3, t: float, on: bool) -> void:
	succ.position = Vector3(SUCC_TILE.x, 0, SUCC_TILE.y) * tile_m
	succ.rotation.y = footman.yaw_of(dir)
	succ.set_fx(on)
	succ.pose_at("attack", t)


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.3, 0.38, 0.22)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.86, 0.9, 1.0)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)
	sun = DirectionalLight3D.new()
	# From the screen's upper left (world -X), 50 degrees up: shadows fall down and right.
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-90), 0)
	sun.light_energy = 0.5
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.55
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	ground = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	ground.mesh = pm
	ground_mat = ShaderMaterial.new()
	ground_mat.shader = GROUND
	ground_mat.set_shader_parameter("tile", tile_m)
	ground_mat.set_shader_parameter("grass_tex", GRASS)
	ground.material_override = ground_mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 0.1
	cam.far = 300.0
	add_child(cam)
	cam.make_current()


## The game's own footman (soldier 0 of the sheet), standing on the next tile at the game's scale.
func _build_sprite() -> void:
	_sprite_doc = JSON.parse_string(FileAccess.get_file_as_string(SPRITE_DOC))
	sprite = Sprite3D.new()
	sprite.name = "GameSprite"
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.pixel_size = float(_sprite_doc.scale) * MEMBER_SCALE / ppu
	sprite.position = Vector3(SPRITE_TILE.x, 0, SPRITE_TILE.y) * tile_m
	add_child(sprite)
	_sprite_frame()


## The sprite's idle frame for the 3D footman's facing (soldier_anim.gd: the
## sheet draws the SW and NE facings; SE and NW are those mirrored).
func _sprite_frame() -> void:
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
	# The frame's foot point (ax, ay) on the ground.
	var ox: float = r[2] * 0.5 - float(e.ax)
	sprite.offset = Vector2(-ox if sprite.flip_h else ox, float(e.ay) - r[3] * 0.5)


## One of the game's tree props on a tile, at the game's scale, in two parts.
## Above its foot point it stands upright (turning only about the vertical,
## stretched by 1 / cos(ELEVATION) so the painted sprite keeps its shape), so
## the depth buffer sorts a 3D unit in front of or behind it. Below the foot
## point the sprite holds the tree's painted shadow on the ground: an upright
## quad would sink under the ground there and cut it off, so that part lies
## flat on the ground instead (stretched by 1 / sin(ELEVATION), turned to face
## the camera), and units walk over it.
func _build_tree() -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites.json"))
	var e: Dictionary = doc[TREE_KEY][0]
	var tex := _without_haze(load(e.file))
	var w := float(e.w)
	var h := float(e.h)
	var ax := float(e.ax)
	var ay := float(e.ay)
	var at := Vector3(TREE_TILE.x, 0, TREE_TILE.y) * tile_m
	var el := deg_to_rad(ELEVATION)
	tree = _prop_part(tex, Rect2(0, 0, w, ay), Vector2(w * 0.5 - ax, ay * 0.5), float(e.scale))
	tree.name = "Tree"
	tree.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	tree.scale = Vector3(1, 1.0 / cos(el), 1)
	tree.position = at
	add_child(tree)
	var flat := _prop_part(tex, Rect2(0, ay, w, h - ay), Vector2(w * 0.5 - ax, -(h - ay) * 0.5), float(e.scale))
	flat.name = "TreeShadow"
	flat.rotation = Vector3(-PI / 2, PI / 4, 0)   # flat, the image's foot towards the camera
	flat.scale = Vector3(1, 1.0 / sin(el), 1)
	flat.position = at + Vector3(0, 0.003, 0)
	add_child(flat)


func _prop_part(tex: Texture2D, region: Rect2, offset: Vector2, scale_px: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.region_enabled = true
	s.region_rect = region
	s.offset = offset
	s.shaded = false
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS   # soft edges blended; opaque parts write depth
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # the shadow is painted in
	s.pixel_size = scale_px / ppu
	return s


## The Blender prop renders carry a faint black haze over their whole frame (alpha
## 1-20 of 255): blended in 2D it vanishes into the ground, in 3D it shows as a box.
## Its level is taken off every pixel's alpha, which keeps the painted shadow soft.
func _without_haze(tex: Texture2D, floor_a := 22) -> Texture2D:
	var img := tex.get_image()
	img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	var k := 255.0 / (255.0 - floor_a)
	for i in range(3, data.size(), 4):
		data[i] = clampi(roundi((data[i] - floor_a) * k), 0, 255)
	var out := Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
	out.generate_mipmaps()
	return ImageTexture.create_from_image(out)


# --- UI -----------------------------------------------------------------------

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(340, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.12, 0.88)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	panel.add_theme_stylebox_override("panel", sb)
	ui.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	col.add_child(_title("FOOTMAN 3D · SANDBOX"))
	col.add_child(_small("Sandbox only: production units are untouched. Click the ground to march, the dummy to attack it."))
	col.add_child(_title("ACTIONS"))
	col.add_child(_row([["Attack", func(): _attack()], ["Charge", func(): _charge()], ["Block", func(): _toggle_block()], ["Hit", func(): footman.hit()]], "act"))
	col.add_child(_row([["Counter", func(): _counter()], ["Step lane", func(): footman.step_lane(FILE * tile_m)], ["Death", func(): footman.die()], ["Revive", func(): footman.revive()]], "act2"))
	col.add_child(_title("SUCCUBUS (3D, FBX)"))
	col.add_child(_row([["Idle", func(): succ.play("idle")], ["Walk", func(): _succ_walk()], ["Attack", func(): succ.play("attack")]], "succ"))
	col.add_child(_row([["Hit", func(): succ.play("hit")], ["Death", func(): succ.play("death")], ["Revive", func(): succ.revive()]], "succ2"))
	col.add_child(_row([["Flourish", func(): succ.play("idle_flourish")], ["Slash FX", func(): _toggle("fx")]], "succ3"))
	col.add_child(_title("FACE  (Q / E turn)"))
	var fr := []
	for k in FACINGS:
		var dir: Vector3 = FACINGS[k]
		fr.append([k, func(): footman.face(footman.yaw_of(dir))])
	col.add_child(_row(fr, "face"))
	col.add_child(_title("PACE"))
	col.add_child(_row(_pace_items(), "pace"))
	col.add_child(_row([["Turn, then walk", func(): _set_step_turns(true)], ["Turn as he walks", func(): _set_step_turns(false)]], "start"))
	col.add_child(_title("LOOK"))
	col.add_child(_row([["Toon", func(): _set_look("toon")], ["Flat", func(): _set_look("flat")], ["PBR", func(): _set_look("pbr")]], "look"))
	col.add_child(_row([["Outline", func(): _toggle("outline")], ["Shadow", func(): _toggle("shadow")], ["Follow", func(): _toggle("follow")]], "tog"))
	col.add_child(_row([["Game sprite beside him", func(): _toggle("sprite")]], "tog"))
	col.add_child(_title("VIEW"))
	col.add_child(_row([["Game zoom 1x", func(): _set_zoom(1.0)], ["Close 3x", func(): _set_zoom(3.0)]], "zoom"))
	col.add_child(_row([["0.25x", func(): _set_speed(0.25)], ["1x", func(): _set_speed(1.0)]], "spd"))
	info = _small("")
	col.add_child(info)
	var hint := Label.new()
	hint.text = "Click ground: march · click dummy: attack · Space attack · C charge · X counter · B block · H hit · K die · R revive · L lane · Q/E turn · P pace · wheel zoom · right-drag pan"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	hint.position = Vector2(12, 0)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_top = -30
	ui.add_child(hint)
	_refresh()


func _title(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.95, 0.84, 0.55))
	return l


func _small(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.86, 0.9, 0.92))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 316
	return l


func _row(items: Array, group: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	for it in items:
		var b := Button.new()
		b.text = it[0]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 32
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(it[1])
		b.toggle_mode = group in ["pace", "start", "look", "tog", "zoom", "spd"] or it[0] in ["Block", "Slash FX"]
		_buttons[group + ":" + String(it[0])] = b
		h.add_child(b)
	return h


## The paces offered, each named by its time a tile.
func _paces() -> Array:
	return ["walk", "game"]


func _pace_label(p: String) -> String:
	if p == "walk":
		return "Walk %.1f s/tile" % (tile_m / footman.clip_speed("walk"))
	return "Game %.2f s/tile" % Footman3D.GAME_TILE_TIME


func _pace_items() -> Array:
	var items := []
	for p in _paces():
		items.append([_pace_label(p), func(): _set_pace(p)])
	return items


func _refresh() -> void:
	var on := {
		"look:Toon": look == "toon", "look:Flat": look == "flat", "look:PBR": look == "pbr",
		"tog:Outline": outline, "tog:Shadow": sun.shadow_enabled, "tog:Follow": follow, "tog:Game sprite beside him": sprite.visible,
		"start:Turn, then walk": footman.step_turns, "start:Turn as he walks": not footman.step_turns,
		"zoom:Game zoom 1x": absf(_zoom_goal - 1.0) < 0.01, "zoom:Close 3x": absf(_zoom_goal - 3.0) < 0.01,
		"spd:0.25x": footman.playback < 0.5, "spd:1x": footman.playback >= 0.5,
		"act:Block": footman.block_held,
		"succ3:Slash FX": succ.fx.enabled,
	}
	for p in _paces():
		on["pace:" + _pace_label(p)] = footman.pace == p
	for k in on:
		if _buttons.has(k):
			_buttons[k].set_pressed_no_signal(on[k])


# --- Settings -----------------------------------------------------------------

func _set_pace(p: String) -> void:
	footman.pace = p
	if footman.state == "walk":
		footman._start_walk()
	_refresh()


func _set_step_turns(on: bool) -> void:
	footman.step_turns = on
	_refresh()


func _set_look(m: String) -> void:
	look = m
	_apply_look()
	_refresh()


func _toggle(what: String) -> void:
	match what:
		"outline": outline = not outline
		"shadow": sun.shadow_enabled = not sun.shadow_enabled
		"follow": follow = not follow
		"sprite": sprite.visible = not sprite.visible
		"fx": succ.set_fx(not succ.fx.enabled)
	_apply_look()
	_refresh()


func _toggle_block() -> void:
	footman.set_block(not footman.block_held)
	_refresh()


func _set_zoom(z: float) -> void:
	_zoom_goal = z
	_refresh()


func _set_speed(s: float) -> void:
	footman.playback = s
	dummy.playback = s
	succ.playback = s
	_refresh()


func _apply_look() -> void:
	footman.set_look(look, outline)
	var w := OUTLINE_PX / (ppu * zoom)
	footman.set_outline_width(w)
	dummy.set_outline(outline, w)
	succ.set_look(look, outline)
	succ.set_outline_width(w)


## She paces three tiles past the tree and back.
func _succ_walk() -> void:
	var a := Vector3(SUCC_TILE.x, 0, SUCC_TILE.y) * tile_m
	succ.walk(a, a + Vector3(-3, 0, -3) * tile_m * 0.7)


# --- Orders -------------------------------------------------------------------

func _attack() -> void:
	var to: Vector3 = dummy.position - footman.position
	to.y = 0
	# The dummy counts as the target when it is close and roughly ahead.
	var near := to.length() < 3.0 and rad_to_deg(absf(angle_difference(footman.rotation.y, footman.yaw_of(to)))) < 80.0
	footman.attack(dummy if near else null)


## The dummy strikes and he strikes back (the game's counterattack).
func _counter() -> void:
	footman.counter(dummy)


## Charge the dummy (the game's shield_charge): a run of two tiles or more
## braking into the strike; nearer, he walks up and strikes.
func _charge() -> void:
	if footman.charge(dummy):
		return
	_flash_text = ("Too close to charge (it needs a run of %d tiles): he walks up instead" % Footman3D.CHARGE_MIN_TILES) if footman.can_charge() else "No charge clip in the export"
	_flash_t = 2.5


func _on_impact(target: Node3D, landed: bool, _reach: float) -> void:
	if target != null and landed:
		target.struck(footman.position)
	_flash_text = footman.last_impact
	_flash_t = 2.5


## Grid path along the tiles: from where he stands to the tile centre, first
## along X then along Z (the game's squads move tile to tile).
func tile_path(from: Vector3, to_tile: Vector2i) -> Array:
	var pts := []
	var cur := Vector2i(roundi(from.x / tile_m), roundi(from.z / tile_m))
	var c := Vector3(cur.x, 0, cur.y) * tile_m
	if from.distance_to(c) > 0.05:
		pts.append(c)
	if to_tile.x != cur.x:
		pts.append(Vector3(to_tile.x, 0, cur.y) * tile_m)
	if to_tile.y != cur.y:
		pts.append(Vector3(to_tile.x, 0, to_tile.y) * tile_m)
	return pts


func march_to_tile(t: Vector2i) -> void:
	ground_mat.set_shader_parameter("focus", Vector2(t.x, t.y))
	ground_mat.set_shader_parameter("focus_on", 1.0)
	footman.march(tile_path(footman.position, t))


func _ground_at(screen: Vector2) -> Variant:
	var o := cam.project_ray_origin(screen)
	var n := cam.project_ray_normal(screen)
	if absf(n.y) < 1e-4:
		return null
	var t := -o.y / n.y
	return o + n * t


func _picks_dummy(screen: Vector2) -> bool:
	# Near the dummy's post anywhere from its foot to its head, on screen.
	for hgt in [0.2, 0.6, 1.0, 1.4, 1.7]:
		var p := cam.unproject_position(dummy.position + Vector3(0, hgt, 0))
		if p.distance_to(screen) < 0.32 * ppu * zoom:
			return true
	return false


# --- Input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_set_zoom(clampf(_zoom_goal * 1.12, 0.45, 8.0))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_set_zoom(clampf(_zoom_goal / 1.12, 0.45, 8.0))
		elif event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = event.pressed
			if event.pressed:
				follow = false
				_refresh()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			click(event.position)
	elif event is InputEventMouseMotion and _dragging:
		var k := 1.0 / (ppu * zoom)
		var right := Vector3(1, 0, -1).normalized()
		var down := Vector3(1, 0, 1).normalized()
		focus -= right * event.relative.x * k + down * event.relative.y * k / sin(deg_to_rad(ELEVATION))
	elif event is InputEventKey and not event.echo:
		if event.keycode == KEY_B:
			footman.set_block(event.pressed)
			_refresh()
			return
		if not event.pressed:
			return
		match event.keycode:
			KEY_SPACE: _attack()
			KEY_C: _charge()
			KEY_X: _counter()
			KEY_H: footman.hit()
			KEY_K: footman.die()
			KEY_R: footman.revive()
			KEY_L: footman.step_lane(FILE * tile_m)
			KEY_Q: footman.face(footman.rotation.y + PI / 2)
			KEY_E: footman.face(footman.rotation.y - PI / 2)
			KEY_P: _set_pace(_paces()[(_paces().find(footman.pace) + 1) % _paces().size()])
			KEY_F:
				follow = not follow
				_refresh()


## A left click at a screen position: the dummy is attacked, the ground marched to.
func click(screen: Vector2) -> void:
	if _picks_dummy(screen):
		footman.attack_target(dummy)
		return
	var g = _ground_at(screen)
	if g == null:
		return
	march_to_tile(Vector2i(roundi(g.x / tile_m), roundi(g.z / tile_m)))


# --- Frame --------------------------------------------------------------------

func _process(dt: float) -> void:
	var old := zoom
	zoom = lerpf(zoom, _zoom_goal, minf(1.0, dt * 10.0))
	if absf(zoom - old) > 1e-4:
		_apply_look()
	if follow:
		focus = focus.lerp(footman.position + Vector3(0, 0.85, 0), minf(1.0, dt * 4.0))
	var el := deg_to_rad(ELEVATION)
	var d := Vector3(cos(el) * sin(PI / 4), sin(el), cos(el) * cos(PI / 4))
	cam.position = focus + d * 60.0
	cam.look_at(focus, Vector3.UP)
	cam.size = get_viewport().get_visible_rect().size.y / (ppu * zoom)
	_flash_t = maxf(0.0, _flash_t - dt)
	_sprite_t += dt * footman.playback
	_sprite_frame()
	var sl := ""
	for s in footman.slides.slice(-4):
		sl += "%s %.1f · " % [s[0].substr(0, 1), s[1] * 100.0]
	var st: String = footman.state
	var clip: String = footman.player.current_animation
	info.text = "%s · %s %.2f s · zoom %.2f\nspeed %.2f m/s (%.2f tiles/s) · tile %.2f m\nplanted-foot slide, cm: %s\nhits on the dummy %d%s\nFPS %d" % [
		st, clip, footman.player.current_animation_position, zoom,
		footman.speed_now, footman.speed_now / tile_m, tile_m,
		sl if sl != "" else "–", dummy.hits,
		("\n" + _flash_text) if _flash_t > 0.0 else "", Engine.get_frames_per_second()]
