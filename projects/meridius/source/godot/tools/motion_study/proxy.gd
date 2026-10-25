## Simple articulated footman: cream tunic, blue cloth, left shield, right sword.
## Code-native blocking geometry, not a replacement for the approved sprite art.
extends Node3D
const Motion = preload("res://tools/motion_study/motion.gd")
var parts: Dictionary = {}
var blue: StandardMaterial3D
var cream: StandardMaterial3D
var leather: StandardMaterial3D
var steel: StandardMaterial3D
var skin: StandardMaterial3D
var dark: StandardMaterial3D
var gold: StandardMaterial3D
var planted: StandardMaterial3D
var lifted: StandardMaterial3D

static func material(color: String, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.roughness = 0.72
	m.metallic = metal
	return m

func build(red := false) -> void:
	blue = material("a2544e" if red else "315d8c")
	cream = material("c5bda5")
	leather = material("473d36")
	steel = material("9caab1", 0.55)
	skin = material("b99375")
	dark = material("28323b")
	gold = material("d4ae68", 0.35)
	planted = material("76c6b8")
	lifted = material("d6a762")
	box("pelvis", Vector3(0.25, 0.19, 0.36), leather)
	box("body", Vector3(0.31, 0.44, 0.46), cream)
	box("belt", Vector3(0.33, 0.065, 0.48), leather)
	box("buckle", Vector3(0.035, 0.055, 0.09), gold)
	box("scarf", Vector3(0.34, 0.12, 0.50), blue)
	box("cape", Vector3(0.065, 0.46, 0.42), blue)
	box("head", Vector3(0.25, 0.29, 0.245), skin)
	box("hair", Vector3(0.26, 0.105, 0.26), leather)
	box("nose", Vector3(0.055, 0.055, 0.065), skin)
	box("brow", Vector3(0.018, 0.027, 0.17), dark)
	for side in ["left", "right"]:
		for part in ["thigh", "shin", "upper", "fore"]:
			rod(side + part, 0.083 if part == "thigh" else 0.061, blue if part == "thigh" else (leather if part == "shin" or part == "fore" else cream))
		for part in ["knee", "elbow", "shoulder"]:
			sphere(side + part, 0.085 if part == "shoulder" else 0.065, steel if part == "knee" else leather)
		box(side + "foot", Vector3(0.29, 0.15, 0.16), leather)
		sphere(side + "hand", 0.065, leather)
		box(side + "tabard", Vector3(0.26, 0.26, 0.17), cream)
		box(side + "contact", Vector3(0.35, 0.009, 0.23), planted)
	box("shield", Vector3(0.11, 0.66, 0.49), steel)
	box("shieldface", Vector3(0.014, 0.59, 0.42), blue)
	box("shieldstripe", Vector3(0.018, 0.39, 0.045), cream)
	box("shieldbar", Vector3(0.019, 0.045, 0.24), cream)
	rod("grip", 0.029, leather)
	box("guard", Vector3(0.045, 0.055, 0.23), gold)
	box("blade", Vector3(0.075, 0.68, 0.025), steel)
	sphere("pommel", 0.035, gold)
	# Pointed blade tip, kept rigidly attached to the hand/blade basis.
	var tip := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0
	cone.bottom_radius = 0.040
	cone.height = 0.12
	cone.radial_segments = 4
	tip.mesh = cone
	tip.material_override = steel
	add_child(tip)
	parts.tip = tip

func box(key: String, size: Vector3, mat: Material) -> void:
	var n := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	n.mesh = mesh
	n.material_override = mat
	add_child(n)
	parts[key] = n

func rod(key: String, radius: float, mat: Material) -> void:
	var n := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.87
	mesh.bottom_radius = radius
	mesh.height = 1.0
	mesh.radial_segments = 8
	n.mesh = mesh
	n.material_override = mat
	add_child(n)
	parts[key] = n

func sphere(key: String, radius: float, mat: Material) -> void:
	var n := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 10
	mesh.rings = 5
	n.mesh = mesh
	n.material_override = mat
	add_child(n)
	parts[key] = n

static func bone_basis(direction: Vector3) -> Basis:
	var y := direction.normalized()
	var other := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.95 else Vector3.FORWARD
	var z := other.cross(y).normalized()
	return Basis(y.cross(z).normalized(), y, z)

func segment(key: String, a: Vector3, b: Vector3) -> void:
	parts[key].position = (a + b) * 0.5
	parts[key].basis = bone_basis(b - a) * Basis.from_scale(Vector3(1, a.distance_to(b), 1))

func set_pose(p: Dictionary) -> void:
	var hip: Vector3 = p.root
	var torso := Basis(Vector3.UP, p.twist) * Basis(Vector3.BACK, -p.lean)
	parts.pelvis.position = hip
	for entry in [["body", Vector3(0, 0.28, 0)], ["belt", Vector3(0, 0.08, 0)], ["buckle", Vector3(0.18, 0.08, 0)],
		["scarf", Vector3(0, 0.48, 0)], ["cape", Vector3(-0.20, 0.28, 0)],
		["head", Vector3(0.015, 0.69, 0)], ["hair", Vector3(-0.005, 0.83, 0)],
		["nose", Vector3(0.16, 0.69, 0)], ["brow", Vector3(0.147, 0.745, 0)]]:
		parts[entry[0]].position = hip + torso * entry[1]
		parts[entry[0]].basis = torso
	for side in ["left", "right"]:
		var sign_side := -1.0 if side == "left" else 1.0
		var h := hip + Vector3(0, -0.025, sign_side * 0.135)
		var ankle: Vector3 = p[side]
		var k := Motion.knee(h, ankle, Vector3.RIGHT, 0.45, 0.44)
		segment(side + "thigh", h, k)
		segment(side + "shin", k, ankle)
		parts[side + "knee"].position = k
		parts[side + "foot"].position = ankle + Vector3(0.055, 0, 0)
		parts[side + "foot"].rotation = Vector3(0, 0, p[side + "_pitch"])
		parts[side + "tabard"].position = hip + Vector3(0.025, -0.14, sign_side * 0.105)
		parts[side + "tabard"].rotation.z = clampf((k.x - h.x) * -0.8, -0.3, 0.3)
		var sh := hip + torso * Vector3(0, 0.45, sign_side * 0.265)
		var hand: Vector3 = hip + p["hand_l" if side == "left" else "hand_r"]
		var elbow := Motion.knee(sh, hand, Vector3(-0.30, -0.6, sign_side * 0.8), 0.29, 0.30)
		segment(side + "upper", sh, elbow)
		segment(side + "fore", elbow, hand)
		parts[side + "shoulder"].position = sh
		parts[side + "elbow"].position = elbow
		parts[side + "hand"].position = hand
		parts[side + "contact"].position = Vector3(ankle.x + 0.055, 0.007, ankle.z)
		parts[side + "contact"].material_override = planted if p[side + "_down"] else lifted
	var shield: Vector3 = hip + p.hand_l
	for entry in [["shield", Vector3.ZERO], ["shieldface", Vector3(0.063, 0, 0)], ["shieldstripe", Vector3(0.074, 0, 0)], ["shieldbar", Vector3(0.076, 0.08, 0)]]:
		parts[entry[0]].position = shield + entry[1]
	var hand: Vector3 = hip + p.hand_r
	var direction: Vector3 = p.blade
	var sword_basis := bone_basis(direction)
	segment("grip", hand - direction * 0.09, hand + direction * 0.04)
	parts.guard.position = hand + direction * 0.05
	parts.guard.basis = sword_basis
	parts.blade.position = hand + direction * 0.44
	parts.blade.basis = sword_basis
	parts.tip.position = hand + direction * 0.78
	parts.tip.basis = sword_basis
	parts.pommel.position = hand - direction * 0.10
