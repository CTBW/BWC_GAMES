## Head-and-shoulders portraits of the 3D figures (Godot only), as Warcraft
## III's animated portrait: a copy of the man himself (his model, face, kit
## and livery, from the battle's own figure) stands in a small stage of his own
## (a SubViewport with its own world, toon light and a portrait camera on his
## head), breathing in his idle; he flinches when his squad is struck. He is
## shown on black, as the old games' portraits: a pool a few shades off black
## behind him, in hard steps (the composite's). A faint glow of his colours
## round him (his livery, else his side's, his back lit in them) is off for now
## (GLOW_STRENGTH).
##
##   var p = preload("res://scripts/ui/unit_bar/head_portrait.gd").new()
##   p.show_figure(figure, type_id, variant)   figure: the battle's man (Node3D) or a
##                                             spec {script, profile, look_spec?}; null for none
##   p.flinch()                                his hit reaction
##   p.live = false                            stops rendering (hidden bar)
##   p.glow = color                            his glow, when on (set from the figure: glow_of)
## Where no figure can be made (no model on disk, a headless run) the baked
## portrait of the unit type (Assets "portrait_<type>") shows instead; the same
## crop is kept, so the two read alike.
##
## Stills (the squad's mini portraits):
##   HeadPortrait.still(figure, host) -> Texture2D or null   (null until taken;
##   `host` is any node in the tree; one is taken per frame, in a shared stage)
##   HeadPortrait.studio(host).still_ready                     signal (key) when one is taken
##   HeadPortrait.still_material(figure)                       their black (and glow)
extends Control

const Style = preload("res://scripts/ui/unit_bar/bar_style.gd")
const Assets = preload("res://scripts/render/assets.gd")

## Render size of the live stage (twice the portrait's size: crisp at 1440p).
const STAGE := Vector2i(352, 312)
const STILL := Vector2i(128, 128)
## The camera: field of view, how far round to the figure's left (radians; a
## little, so the helmet has form and the shield on his left arm stays low)
## and how high above his eyes (the slope of its line to them).
const FOV := 21.0
const TURN := 0.2
const RISE := 0.1
## How much of him the frame holds below his head's centre (metres of a 1.7 m
## man: his shoulders) and above the top of his head or of his helmet's gear.
const BELOW := 0.36
const ABOVE := 0.06
## The stills are tighter (the squad grid's small faces).
const STILL_ZOOM := 0.8
## The camera follows his head only when it moves far (a hit's stagger), not
## his breathing: none below FOLLOW.x metres, FOLLOW_MAX of it from FOLLOW.y.
const FOLLOW := Vector2(0.03, 0.14)
const FOLLOW_MAX := 0.9
## The glow round him: 0 off (for now), 0.5 a faint one.
const GLOW_STRENGTH := 0.0
const COMPOSITE := """
shader_type canvas_item;
// The stage's picture on black, as the portraits of the old games: behind him
// a pool only a few shades off black, in hard steps (back_bands of them, the
// black counted; back_peak the brightest: 15 of 255, steps of 5), no
// smooth gradient. A faint glow of the unit's colour round his silhouette
// when glow_strength > 0 (breathing a little), a hit flash, a glint; `gray`
// for the fallen.
// The pool's middle (uv) and its reach (picture heights) to the black.
uniform vec2 back_centre = vec2(0.5, 0.42);
uniform float back_reach = 0.7;
uniform float back_peak = 0.0588;
uniform int back_bands = 4;
uniform vec4 glow_color : source_color = vec4(0.32, 0.5, 1.0, 1.0);
// How far the glow reaches (texels of the picture) and how bright it is.
uniform float glow_radius = 40.0;
uniform float glow_strength = 0.0;
uniform float flash = 0.0;
uniform float glint = -1.0;
uniform float gray = 0.0;
// The vertex colour and modulate (fragment's COLOR has the texture in it too).
varying vec4 tint;
void vertex() {
	tint = COLOR;
}
// The pool's shade at uv (`aspect` the picture's width over its height): the
// band it falls in, its edges a pixel soft so they do not crawl.
float pool(vec2 uv, float aspect) {
	vec2 d = (uv - back_centre) * vec2(aspect, 1.0);
	float n = float(back_bands);
	float x = clamp(1.0 - length(d) / back_reach, 0.0, 0.999) * n;
	float w = max(fwidth(x), 0.0001);
	float k = floor(x) + smoothstep(1.0 - w, 1.0, fract(x));
	return back_peak * min(k, n - 1.0) / (n - 1.0);
}
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec3 halo = vec3(0.0);
	if (glow_strength > 0.0) {
		// How much of him is near: five rings of samples, the nearer weighing
		// more, each turned a little so their gaps do not line up.
		float g = 0.0;
		float total = 0.0;
		for (int ring = 1; ring <= 5; ring++) {
			float r = glow_radius * float(ring) / 5.0;
			float w = 1.18 - float(ring) * 0.18;
			for (int i = 0; i < 16; i++) {
				float t = (float(i) + float(ring) * 0.31) * 0.3927;
				g += texture(TEXTURE, UV + vec2(cos(t), sin(t)) * TEXTURE_PIXEL_SIZE * r).a * w;
			}
			total += 16.0 * w;
		}
		g = smoothstep(0.0, 0.6, g / total);
		float breath = 0.9 + 0.1 * sin(TIME * 1.7);
		halo = glow_color.rgb * g * glow_strength * breath;
	}
	vec3 back = vec3(pool(UV, TEXTURE_PIXEL_SIZE.y / TEXTURE_PIXEL_SIZE.x));
	vec3 fig = c.rgb / max(c.a, 0.001);
	vec3 o = mix(back + halo, fig, c.a);
	o = mix(o, vec3(dot(o, vec3(0.3, 0.59, 0.11))) * 0.6, gray);
	o = mix(o, vec3(1.0, 0.92, 0.85), flash * c.a);
	if (glint > -0.5) {
		float d = UV.x + UV.y * 0.7 - glint * 2.4 + 0.35;
		o += vec3(1.0, 0.96, 0.8) * smoothstep(0.12, 0.0, abs(d)) * 0.3 * c.a;
	}
	COLOR = vec4(o, 1.0) * tint;
}
"""

static var _composite: Shader
static var _studio: Studio

## Draw the stage (false: frozen and not rendered).
var live := true:
	set(v):
		live = v
		if _vp:
			_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if v and _figure != null else SubViewport.UPDATE_DISABLED
var faction := "player"
## The glow round him and the light on his back, when on: the unit's colour (glow_of).
var glow := Color(0.32, 0.5, 1.0):
	set(v):
		glow = v
		if _view:
			(_view.material as ShaderMaterial).set_shader_parameter("glow_color", v)
		if _vp:
			_tint_rim(_vp, v)
var _vp: SubViewport
var _cam: Camera3D
var _view: TextureRect
var _fallback: TextureRect
var _figure: Node3D
var _source: Variant = null
var _type_id := ""
var _variant := 0
var _flash := 0.0
var _glint := -1.0
var _glint_in := 3.0
var _framed := 0
## The framing (aim, span, head) taken when he was staged, and the camera's aim now.
var _frame: Dictionary = {}
var _aim := Vector3.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_build()


## Its pieces, made with it (it works before it is in the tree, as in the headless tests).
func _build() -> void:
	_fallback = TextureRect.new()
	_fallback.name = "Baked"
	_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fallback.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fallback.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_fallback)
	_view = TextureRect.new()
	_view.name = "Live"
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_view.material = _composite_material()
	add_child(_view)


func _draw() -> void:
	# Black, as the old games' portraits (the composite's pool is over it).
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)


static func is_rendering() -> bool:
	return DisplayServer.get_name() != "headless"


## Shows `figure` (or the type's baked portrait when it cannot be staged).
func show_figure(figure: Variant, type_id: String, variant := 0) -> void:
	_type_id = type_id
	_variant = variant
	_set_fallback()
	if is_same(figure, _source) and _figure != null:
		return
	_source = figure
	_clear_figure()
	if figure == null or not is_rendering():
		_view.texture = null
		return
	var u := make_figure(figure)
	if u == null or not is_inside_tree():
		_view.texture = null
		return
	_ensure_stage()
	glow = glow_of(figure)
	_figure = u
	_vp.add_child(u)
	dress_for_portrait(u, 0.006)
	_framed = 3
	_frame = {}
	_fallback.visible = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if live else SubViewport.UPDATE_DISABLED
	_view.texture = _vp.get_texture()
	queue_redraw()


## A dressed footman's ink line is shared with the field's men: the portrait
## leaves his off (the glow round his silhouette is the composite's); the others
## keep their own, drawn `width` metres wide for the close-up. After his
## _ready (which sets his look), when he is not ready yet.
static func dress_for_portrait(u: Node3D, width: float) -> void:
	if not u.is_node_ready():
		u.ready.connect(dress_for_portrait.bind(u, width), CONNECT_ONE_SHOT)
		return
	if _dressed(u):
		u.set_look("toon", false)
	elif u.has_method("set_outline_width"):
		u.set_outline_width(width)


static func _dressed(u: Node3D) -> bool:
	var spec: Variant = u.get("look_spec")
	return spec is Dictionary and not (spec as Dictionary).is_empty()


func flinch() -> void:
	_flash = 1.0
	if _figure != null and is_instance_valid(_figure) and _figure.has_method("hit") and not _figure.is_dead():
		_figure.hit()


func has_figure() -> bool:
	return _figure != null


func _process(dt: float) -> void:
	if _framed > 0 and _figure != null:
		# Framed once the clip has posed him (his first frames).
		_framed -= 1
		if _framed == 0:
			_frame = framing(_figure)
			_aim = _frame.aim
			place_camera(_cam, _aim, _frame.span)
	elif not _frame.is_empty() and _figure != null and is_instance_valid(_figure) and live:
		var dev: Vector3 = head_centre(_figure) - _frame.head
		var w := smoothstep(FOLLOW.x, FOLLOW.y, dev.length()) * FOLLOW_MAX
		_aim = _aim.lerp(_frame.aim + dev * w, 1.0 - exp(-dt * 6.0))
		place_camera(_cam, _aim, _frame.span)
	var mat := _view.material as ShaderMaterial
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - dt * 4.0)
		mat.set_shader_parameter("flash", _flash * 0.8)
	_glint_in -= dt
	if _glint_in <= 0.0:
		_glint = -0.2
		_glint_in = randf_range(5.0, 9.0)
	if _glint > -0.5:
		_glint += dt * 1.1
		if _glint > 1.3:
			_glint = -1.0
		mat.set_shader_parameter("glint", _glint)


func _set_fallback() -> void:
	var s := Assets.sprite("portrait_" + _type_id, _variant) if _type_id != "" else {}
	if s.is_empty() or s.get("tex") == null:
		_fallback.texture = null
		return
	var at := AtlasTexture.new()
	at.atlas = s.tex
	at.region = s.region
	_fallback.texture = at


func _clear_figure() -> void:
	if _figure != null and is_instance_valid(_figure):
		_figure.queue_free()
	_figure = null
	if _fallback:
		_fallback.visible = true
	if _vp:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _ensure_stage() -> void:
	if _vp != null:
		return
	_vp = SubViewport.new()
	_vp.name = "Stage"
	_cam = _build_stage(_vp, STAGE)
	add_child(_vp)


static func _composite_material() -> ShaderMaterial:
	if _composite == null:
		_composite = Shader.new()
		_composite.code = COMPOSITE
	var m := ShaderMaterial.new()
	m.shader = _composite
	m.set_shader_parameter("glow_strength", GLOW_STRENGTH)
	return m


## The portrait's look for a still (the squad grid's faces): black and its
## pool, his glow (a narrower one, for the small picture).
static func still_material(figure: Variant) -> ShaderMaterial:
	var m := _composite_material()
	m.set_shader_parameter("glow_color", glow_of(figure))
	m.set_shader_parameter("glow_radius", 16.0)
	return m


## A unit's colour for his glow: his squad's livery (a dressed footman's), else
## his side's (blue, a foe's red), bright and saturated as a light.
static func glow_of(figure: Variant) -> Color:
	var spec: Variant = null
	if figure is Node3D and is_instance_valid(figure) or figure is Dictionary:
		spec = figure.get("look_spec")
	var c: Color = Style.PLAYER if faction_of(figure) == "player" else Style.ENEMY
	if spec is Dictionary and spec.get("livery") is Color:
		c = spec.livery
	return Color.from_hsv(c.h, clampf(c.s * 1.6, 0.55, 0.85), 1.0)


## A figure's side ("player" unless it says otherwise): the man's, or a spec's profile's.
static func faction_of(figure: Variant) -> String:
	if figure is Node3D and is_instance_valid(figure) and figure.get("faction") != null:
		return String(figure.get("faction"))
	if figure is Dictionary:
		return String(figure.get("profile", {}).get("faction", "player"))
	return "player"


## The stage's back light takes the unit's colour (his edges catch it) while
## the glow is on; a cool white otherwise.
static func _tint_rim(vp: SubViewport, c: Color) -> void:
	var rim: DirectionalLight3D = vp.get_node_or_null("Rim")
	if rim != null and GLOW_STRENGTH > 0.0:
		rim.light_color = c.lerp(Color.WHITE, 0.25)


## A stage: its own world, a clear background, a warm key light from the top
## left, a warm fill from the right, a cool rim from behind (in the unit's
## colour while the glow is on: _tint_rim); returns its camera.
static func _build_stage(vp: SubViewport, px: Vector2i) -> Camera3D:
	vp.size = px
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.78)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.92, 0.8)
	key.light_energy = 0.95
	key.rotation = Vector3(deg_to_rad(-38), deg_to_rad(-30), 0)
	vp.add_child(key)
	# A warm fill from the front right, so the side away from the key (a
	# wing, a cheek) stays its colour in the toon shadow.
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(1.0, 0.86, 0.66)
	fill.light_energy = 0.3
	fill.rotation = Vector3(deg_to_rad(-12), deg_to_rad(40), 0)
	vp.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.name = "Rim"
	rim.light_color = Color(0.6, 0.72, 1.0)
	rim.light_energy = 1.3
	rim.rotation = Vector3(deg_to_rad(-20), deg_to_rad(160), 0)
	vp.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = FOV
	cam.near = 0.05
	cam.far = 30.0
	cam.position = Vector3(0, 1.5, 3)
	vp.add_child(cam)
	cam.current = true
	return cam


## A copy of the battle's man (same script, profile, face, kit and look), or of a
## spec {script, profile, look_spec?}; null when his model is not on disk.
static func make_figure(src: Variant) -> Node3D:
	var scr: Script = null
	var prof: Dictionary = {}
	var look: Dictionary = {}
	if src is Node3D and is_instance_valid(src):
		scr = (src as Node3D).get_script()
		var p: Variant = src.get("profile")
		prof = (p as Dictionary).duplicate(true) if p is Dictionary else {}
		var l: Variant = src.get("look_spec")
		look = l if l is Dictionary else {}
	elif src is Dictionary:
		scr = src.get("script")
		prof = (src.get("profile", {}) as Dictionary).duplicate(true)
		look = src.get("look_spec", {})
	if scr == null or prof.is_empty() or not ResourceLoader.exists(String(prof.get("model", ""))):
		return null
	prof.erase("scale")
	var u: Node3D = scr.new()
	u.setup(prof)
	if not look.is_empty() and "look_spec" in u:
		u.look_spec = look
	u.name = "Sitter"
	return u


## Where the camera looks and how much it holds (metres, top to bottom): his
## head and shoulders, the top of the frame over his head or over the gear on
## it (the captain's wings), whichever is higher. `zoom` < 1 is tighter.
## {aim, span, head} in the stage's space; `head` is head_centre's.
static func framing(u: Node3D, zoom := 1.0) -> Dictionary:
	var h: float = u.height_m() if u.has_method("height_m") else 1.7
	var k := clampf(h / 1.7, 0.6, 2.2)
	var c := head_centre(u)
	var top := c.y + 0.12 * k
	var sk: Skeleton3D = u.get("skeleton")
	if sk != null:
		var tip := _bone(sk, "headtop_end")
		if tip >= 0:
			top = (sk.global_transform * sk.get_bone_global_pose(tip)).origin.y
		# Gear on his head (a helmet's crest or wings) and how high it reaches.
		for att in sk.find_children("*", "BoneAttachment3D", true, false):
			if not String(att.bone_name).to_lower().ends_with("head"):
				continue
			for mi in att.find_children("*", "MeshInstance3D", true, false):
				if mi.is_visible_in_tree():
					top = maxf(top, (mi.global_transform * mi.get_aabb()).end.y - ABOVE * k * 0.6)
	top += ABOVE * k
	var bottom := c.y - BELOW * k * zoom
	top = c.y + (top - c.y) * lerpf(1.0, zoom, 0.5)
	return {"aim": Vector3(c.x, (top + bottom) * 0.5, c.z), "span": top - bottom, "head": c}


## The middle of his head (between the Head bone and the top of his skull),
## in the stage's space; 0.9 of his height above his feet without a skeleton.
static func head_centre(u: Node3D) -> Vector3:
	var h: float = u.height_m() if u.has_method("height_m") else 1.7
	var sk: Skeleton3D = u.get("skeleton")
	if sk == null:
		return u.global_position + Vector3(0, h * 0.9, 0)
	var head := _bone(sk, "head")
	if head < 0:
		return u.global_position + Vector3(0, h * 0.9, 0)
	var p := (sk.global_transform * sk.get_bone_global_pose(head)).origin
	var tip := _bone(sk, "headtop_end")
	if tip >= 0:
		return (p + (sk.global_transform * sk.get_bone_global_pose(tip)).origin) * 0.5
	return p + Vector3(0, 0.1 * clampf(h / 1.7, 0.6, 2.2), 0)


## The first bone whose name ends in `suffix` (any case), or -1.
static func _bone(sk: Skeleton3D, suffix: String) -> int:
	for i in sk.get_bone_count():
		if sk.get_bone_name(i).to_lower().ends_with(suffix):
			return i
	return -1


## The camera in front of the aim, TURN round to his left and RISE above, far
## enough back for `span` metres top to bottom.
static func place_camera(cam: Camera3D, aim: Vector3, span: float) -> void:
	var dir := Vector3(sin(TURN), RISE, cos(TURN)).normalized()
	cam.position = aim + dir * (span * 0.5 / tan(deg_to_rad(cam.fov * 0.5)))
	cam.look_at(aim, Vector3.UP)


# --- Stills ----------------------------------------------------------------------------------

## The shared stage the stills are taken in, one man at a time, kept at the
## tree's root while the game runs.
class Studio extends SubViewport:
	signal still_ready(key: String)
	var stills := {}
	var queue: Array = []
	var busy := false

	## Stills asked for before the studio entered the tree.
	func _ready() -> void:
		_next.call_deferred()

	func want(key: String, figure: Variant) -> void:
		if stills.has(key) or queue.any(func(j): return j.key == key):
			return
		queue.append({"key": key, "figure": figure})
		if not busy:
			_next.call_deferred()

	## Stage the next man, let his idle pose him, render once, keep the picture.
	func _next() -> void:
		if busy or queue.is_empty() or not is_inside_tree():
			return
		busy = true
		var job: Dictionary = queue.pop_front()
		var u: Node3D = load("res://scripts/ui/unit_bar/head_portrait.gd").make_figure(job.figure)
		if u == null:
			stills[job.key] = null
			busy = false
			_next.call_deferred()
			return
		var hp: Script = load("res://scripts/ui/unit_bar/head_portrait.gd")
		hp._tint_rim(self, hp.glow_of(job.figure))
		add_child(u)
		hp.dress_for_portrait(u, 0.004)
		await get_tree().process_frame
		await get_tree().process_frame
		var f: Dictionary = hp.framing(u, hp.STILL_ZOOM)
		hp.place_camera(get_camera_3d(), f.aim, f.span)
		render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var img := get_texture().get_image()
		stills[job.key] = ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null
		u.queue_free()
		busy = false
		still_ready.emit(job.key)
		_next.call_deferred()


## The still headshot of a figure, or null until it has been taken (it is queued;
## the studio's `still_ready(key)` says when). Keyed by the figure (the man).
static func still(figure: Variant, host: Node) -> Texture2D:
	if figure == null or not is_rendering():
		return null
	var st := studio(host)
	if st == null:
		return null
	var key := still_key(figure)
	if st.stills.has(key):
		return st.stills[key]
	st.want(key, figure)
	return null


static func still_key(figure: Variant) -> String:
	if figure is Object:
		return "n%d" % (figure as Object).get_instance_id()
	return "s%d" % hash(figure)


## The studio (made at the tree's root on first use, from `host`'s tree).
static func studio(host: Node = null) -> Studio:
	if _studio != null and is_instance_valid(_studio):
		return _studio
	if host == null or not host.is_inside_tree():
		return null
	_studio = Studio.new()
	_studio.name = "HeadshotStudio"
	_build_stage(_studio, STILL)
	host.get_tree().root.add_child.call_deferred(_studio)
	return _studio


static func clear_stills() -> void:
	if _studio != null and is_instance_valid(_studio):
		_studio.stills.clear()
		_studio.queue.clear()
