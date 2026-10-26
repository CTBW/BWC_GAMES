## The 3D succubus for the sandbox: the FBX exported from
## art/succubus_3d/succubus_anim.blend by art/succubus_3d/tools/export_godot.py,
## with its sidecar (clip lengths, loops, ground speed). Like the footman she
## faces +Z: a direction d on the ground is the yaw atan2(d.x, d.z).
##
## A look test, not a unit: she plays one clip at a time. The one-off clips
## (attack, hit, walk_start, walk_stop, idle_flourish) fall back to idle; the
## death stays down until revive(); walk() paces her to and fro between two
## points at her walk's own ground speed. Standing idle, each succubus plays one
## of idle's variants (the sidecar's variants.idle: the bending flourish) now and
## then, after her own random wait (variants.idle.every_s), so a squad never
## moves in step. Her whip's lash and coil are animated by their bones' scale
## keys in the clips themselves (whip_motion.py); the slash effects at the
## attack's strikes (events.strikes) are whip_fx.gd, a child she drives from
## play() and pose_at().
extends Node3D

const FBX := "res://prototypes/footman_anim/art3d/succubus.fbx"
const META := "res://prototypes/footman_anim/art3d/succubus.json"
const OUTLINE := preload("res://prototypes/footman_anim/shaders/outline3d.gdshader")
const WhipFX = preload("res://prototypes/footman_anim/scripts/whip_fx.gd")
const PREFIX := "SuccubusRig|"
const BLEND := 0.2
const LASH_OUTLINE := 0.35  # the lash's outline, of the others' width (it is 3-6 cm thick)

var meta: Dictionary
var model: Node3D
var player: AnimationPlayer
var fx: MeshInstance3D
var state := "idle"
var playback := 1.0:
	set(v):
		playback = v
		if player:
			player.speed_scale = v
var _outline: ShaderMaterial
var _outline_lash: ShaderMaterial
var _surfaces: Array = []
var _pace_from := Vector3.ZERO
var _pace_to := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _variant_in := 0.0     # seconds of idle before her next idle variant


func _ready() -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string(META))
	model = (load(FBX) as PackedScene).instantiate()
	add_child(model)
	player = model.find_children("*", "AnimationPlayer", true, false)[0]
	for n in meta.clips:
		var a := player.get_animation(PREFIX + n)
		if a:
			a.loop_mode = Animation.LOOP_LINEAR if meta.clips[n].loop else Animation.LOOP_NONE
	fx = WhipFX.new()
	fx.name = "WhipFX"
	add_child(fx)
	fx.setup(self, model.find_children("*", "Skeleton3D", true, false)[0], player, PREFIX + "attack",
		meta.clips.get("attack", {}).get("events", {}), float(meta.get("fps", 30.0)))
	player.animation_finished.connect(_on_finished)
	_outline = ShaderMaterial.new()
	_outline.shader = OUTLINE
	_outline_lash = ShaderMaterial.new()
	_outline_lash.shader = OUTLINE
	_outline_lash.set_shader_parameter("width", 0.03 * LASH_OUTLINE)   # the shader's default, scaled
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).contains("Lash"):
			# The imported LODs drop the lash's blades, ferrule and hook (small loose pieces
			# on a 2 m mesh), leaving a bare rod: keep it at full detail.
			mi.lod_bias = 128.0
		for i in mi.mesh.get_surface_count():
			_surfaces.append([mi, i, mi.mesh.surface_get_material(i)])
	set_look("toon", true)
	_rng.randomize()
	play("idle")


## The same looks as the footman's (sandbox3d/scripts/unit3d.gd set_look).
func set_look(mode: String, outline: bool) -> void:
	for s in _surfaces:
		var src: Material = s[2]
		var m: StandardMaterial3D = src.duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		match mode:
			"toon":
				m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				m.metallic = 0.0
				m.roughness = 1.0
			"flat":
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var lash: bool = String(s[0].name).contains("Lash")
		m.next_pass = (_outline_lash if lash else _outline) if outline else null
		s[0].set_surface_override_material(s[1], m)


func set_outline_width(metres: float) -> void:
	_outline.set_shader_parameter("width", metres)
	_outline_lash.set_shader_parameter("width", metres * LASH_OUTLINE)


func height_m() -> float:
	return float(meta.get("height_m", 1.95))


func play(clip: String) -> void:
	state = clip
	player.play(PREFIX + clip, BLEND)
	fx.on_play(PREFIX + clip)
	if clip == "idle":
		var every: Array = meta.get("variants", {}).get("idle", {}).get("every_s", [9.0, 22.0])
		_variant_in = _rng.randf_range(every[0], every[1])


## One frame of a clip, held (for review captures); play() moves on again.
func pose_at(clip: String, seconds: float) -> void:
	state = "pose"
	player.play(PREFIX + clip, 0.0)
	player.seek(seconds, true)
	player.pause()
	fx.preview(PREFIX + clip, seconds)


## The whip-slash effects on or off.
func set_fx(on: bool) -> void:
	fx.enabled = on
	if not on:
		fx.clear()


## To and fro between `a` and `b` (on the ground) at the walk's own speed.
func walk(a: Vector3, b: Vector3) -> void:
	_pace_from = a
	_pace_to = b
	position = a
	_face(b - a)
	play("walk")


func revive() -> void:
	play("idle")


func _face(d: Vector3) -> void:
	if Vector2(d.x, d.z).length() > 1e-4:
		rotation.y = atan2(d.x, d.z)


func _on_finished(anim: StringName) -> void:
	var clip := String(anim).trim_prefix(PREFIX)
	if clip in ["attack", "hit", "walk_start", "walk_stop"] or clip.begins_with("idle_"):
		play("idle")


func _process(dt: float) -> void:
	if state == "idle":
		_variant_in -= dt * playback
		var variants: Array = meta.get("variants", {}).get("idle", {}).get("clips", [])
		if _variant_in <= 0.0 and not variants.is_empty():
			play(variants[_rng.randi_range(0, variants.size() - 1)])
		return
	if state != "walk":
		return
	var v: Array = meta.clips.walk.root_vel
	var speed := Vector3(v[0], v[1], v[2]).length() * playback
	var to := _pace_to - position
	to.y = 0
	if to.length() < speed * dt:
		var back := _pace_from
		_pace_from = _pace_to
		_pace_to = back
		_face(_pace_to - position)
	else:
		position += to.normalized() * speed * dt
