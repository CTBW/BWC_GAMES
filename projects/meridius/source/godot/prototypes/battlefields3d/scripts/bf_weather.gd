## The weather and the smoke over a 3D battlefield, as CPUParticles3D drawn by
## shaders/bf_particle.gdshader (fog of war and night as the ground):
##   - "snow", "leaves" or "petals" falling over the part of the field the
##     camera looks at (follow() moves the fall with the camera's focus; the
##     particles stay where they fell);
##   - smoke from the chimneys and the burnt barn's embers (bf_field.gd
##     `smoke`), leaning down-wind to the screen's right.
## Every emitter starts a full lifetime in, so a capture shows it in full.
extends Node3D

const ParticleShader = preload("res://prototypes/battlefields3d/shaders/bf_particle.gdshader")
const KIND := {"snow": 0, "leaves": 1, "petals": 2, "smoke": 3, "ember": 4}
## The wind, toward the screen's right (world (1, 0, -1)).
const WIND := Vector3(0.7071, 0.0, -0.7071)

var _fall: CPUParticles3D
var _mats: Array = []
var _emitters: Array = []


func build(weather: String, smoke: Array, map_size: Vector2, tile_m: float) -> void:
	if weather != "":
		_fall = _falling(weather)
		add_child(_fall)
		_emitters.append(_fall)
	for s in smoke:
		var puffs := _smoke(s.kind == "ash")
		puffs.position = s.at
		add_child(puffs)
		_emitters.append(puffs)
		if s.kind == "ash":
			var embers := _embers()
			embers.position = s.at + Vector3(0, -0.6, 0)
			add_child(embers)
			_emitters.append(embers)
	for m in _mats:
		m.set_shader_parameter("map_size", map_size)
		m.set_shader_parameter("tile_m", tile_m)


func follow(focus: Vector3) -> void:
	if _fall:
		_fall.position = focus + Vector3(0, 16, 0)


func set_shared(param: String, value: Variant) -> void:
	for m in _mats:
		m.set_shader_parameter(param, value)


func set_falling(on: bool) -> void:
	if _fall:
		_fall.emitting = on
		_fall.visible = on


func _material(kind: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ParticleShader
	m.set_shader_parameter("kind", KIND[kind])
	_mats.append(m)
	return m


func _emitter(kind: String, amount: int, life: float, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	p.mesh = q
	p.material_override = _material(kind)
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.custom_aabb = AABB(Vector3(-80, -40, -80), Vector3(160, 80, 160))
	return p


## Snow, leaves or petals over a box round the camera's focus.
func _falling(kind: String) -> CPUParticles3D:
	var p: CPUParticles3D
	var colors: Array
	match kind:
		"snow":
			p = _emitter("snow", 2600, 20.0, 0.13)
			p.direction = Vector3(0.2, -1, -0.2)
			p.spread = 12.0
			p.initial_velocity_min = 0.7
			p.initial_velocity_max = 1.3
			p.gravity = WIND * 0.08 + Vector3(0, -0.05, 0)
			p.scale_amount_min = 0.6
			p.scale_amount_max = 1.3
			colors = [Color(1.0, 1.0, 1.0, 0.95), Color(0.9, 0.94, 1.0, 0.85)]
		"leaves":
			p = _emitter("leaves", 260, 16.0, 0.2)
			p.direction = Vector3(0.3, -1, -0.3)
			p.spread = 25.0
			p.initial_velocity_min = 0.6
			p.initial_velocity_max = 1.2
			p.gravity = WIND * 0.25 + Vector3(0, -0.04, 0)
			p.angular_velocity_min = -220.0
			p.angular_velocity_max = 220.0
			p.angle_min = 0.0
			p.angle_max = 360.0
			p.scale_amount_min = 0.7
			p.scale_amount_max = 1.2
			colors = [Color(0.86, 0.45, 0.14), Color(0.93, 0.68, 0.2), Color(0.66, 0.24, 0.1), Color(0.78, 0.56, 0.18)]
		"petals":
			p = _emitter("petals", 420, 18.0, 0.11)
			p.direction = Vector3(0.4, -1, -0.4)
			p.spread = 30.0
			p.initial_velocity_min = 0.4
			p.initial_velocity_max = 0.9
			p.gravity = WIND * 0.3 + Vector3(0, -0.02, 0)
			p.angular_velocity_min = -160.0
			p.angular_velocity_max = 160.0
			p.angle_max = 360.0
			p.scale_amount_min = 0.7
			p.scale_amount_max = 1.2
			colors = [Color(1.0, 0.84, 0.9), Color(1.0, 0.94, 0.96), Color(0.98, 0.72, 0.82)]
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(38, 4, 38)
	# Each particle picks one colour of the season (hue variation on a ramp).
	var ramp := Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offs.append(float(i) / colors.size())
		cols.append(colors[i])
	ramp.offsets = offs
	ramp.colors = cols
	p.color_initial_ramp = ramp
	# Fade in as they enter the box and out before they vanish.
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.06, 0.9, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	p.color_ramp = fade
	return p


## A thread of smoke: pale from a chimney, dark and thick from a burnt roof.
func _smoke(ash: bool) -> CPUParticles3D:
	var p := _emitter("smoke", 30 if ash else 18, 6.5 if ash else 5.5, 1.0)
	p.direction = Vector3.UP
	p.spread = 8.0
	p.initial_velocity_min = 0.45
	p.initial_velocity_max = 0.7
	p.gravity = WIND * 0.22 + Vector3(0, 0.05, 0)
	p.damping_min = 0.02
	p.damping_max = 0.05
	p.angle_max = 360.0
	p.scale_amount_min = 0.38 if ash else 0.26
	p.scale_amount_max = 0.55 if ash else 0.38
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.18 if ash else 0.08
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.45))
	grow.add_point(Vector2(1, 1.9))
	p.scale_amount_curve = grow
	var g := Gradient.new()
	if ash:
		g.offsets = PackedFloat32Array([0.0, 0.12, 0.6, 1.0])
		g.colors = PackedColorArray([Color(0.3, 0.27, 0.25, 0.0), Color(0.3, 0.27, 0.25, 0.75), Color(0.46, 0.44, 0.43, 0.42), Color(0.58, 0.57, 0.56, 0.0)])
	else:
		g.offsets = PackedFloat32Array([0.0, 0.1, 0.55, 1.0])
		g.colors = PackedColorArray([Color(0.86, 0.86, 0.88, 0.0), Color(0.86, 0.86, 0.88, 0.55), Color(0.8, 0.82, 0.86, 0.3), Color(0.78, 0.8, 0.86, 0.0)])
	p.color_ramp = g
	return p


func _embers() -> CPUParticles3D:
	var p := _emitter("ember", 24, 2.4, 0.07)
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.6
	p.gravity = WIND * 0.4 + Vector3(0, 0.2, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.8, 0.2, 0.8)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.6, 0.2, 0.0), Color(1.0, 0.55, 0.15, 1.0), Color(0.9, 0.25, 0.05, 0.0)])
	p.color_ramp = g
	return p
