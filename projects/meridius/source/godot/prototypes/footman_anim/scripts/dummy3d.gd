## Straw training dummy for the 3D sandbox: a post, a straw sack, a crossbar
## and a head. A blow rocks it away from the attacker on a spring about its
## foot and flashes it warm; a miss does nothing.
extends Node3D

const OUTLINE := preload("res://prototypes/footman_anim/shaders/outline3d.gdshader")
const RADIUS := 0.24

var hits := 0
var playback := 1.0
var _axis := Vector3.RIGHT
var _th := 0.0
var _w := 0.0
var _flash := 0.0
var _pivot: Node3D
var _mats: Array = []
var _outline: ShaderMaterial


func _ready() -> void:
	_outline = ShaderMaterial.new()
	_outline.shader = OUTLINE
	_pivot = Node3D.new()
	add_child(_pivot)
	var wood := Color(0.42, 0.3, 0.19)
	var straw := Color(0.86, 0.72, 0.42)
	var sack := Color(0.74, 0.6, 0.38)
	_part(_cyl(0.3, 0.3, 0.06), Vector3(0, 0.03, 0), wood)
	_part(_cyl(0.05, 0.05, 1.7), Vector3(0, 0.85, 0), wood)
	_part(_capsule(RADIUS, 0.85), Vector3(0, 1.08, 0), sack)
	var bar := _part(_cyl(0.04, 0.04, 1.0), Vector3(0, 1.36, 0), wood)
	bar.rotation.z = PI / 2
	_part(_sphere(0.15), Vector3(0, 1.62, 0), straw)


func _cyl(top: float, bottom: float, h: float) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 14
	return m


func _capsule(r: float, h: float) -> Mesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 16
	return m


func _sphere(r: float) -> Mesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 16
	m.rings = 8
	return m


func _part(mesh: Mesh, at: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.roughness = 1.0
	mat.next_pass = _outline
	mi.material_override = mat
	_mats.append([mat, col])
	_pivot.add_child(mi)
	return mi


func set_outline(on: bool, width: float) -> void:
	_outline.set_shader_parameter("width", width)
	for m in _mats:
		m[0].next_pass = _outline if on else null


## A blow from `from` (a ground position): it rocks away from it.
func struck(from: Vector3) -> void:
	hits += 1
	var away := position - from
	away.y = 0
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	_axis = Vector3.UP.cross(away).normalized()
	_w += 4.2
	_flash = 1.0


func _process(dt: float) -> void:
	var sdt := dt * playback
	# A stiff, lightly damped spring about the foot.
	_w += (-60.0 * _th - 5.0 * _w) * sdt
	_th += _w * sdt
	_pivot.transform = Transform3D(Basis(_axis, _th), Vector3.ZERO)
	_flash = maxf(0.0, _flash - sdt * 5.0)
	for m in _mats:
		m[0].albedo_color = m[1].lerp(Color(1.0, 0.86, 0.6), _flash * 0.6)
