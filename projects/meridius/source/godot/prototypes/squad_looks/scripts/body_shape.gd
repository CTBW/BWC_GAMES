## A squad man's build and his glances, on top of whatever clip plays: a
## SkeletonModifier3D, so the Skeleton3D runs it after the AnimationPlayer
## every frame (unit_look.gd adds it).
##  - Build: the head and the chest (Spine1, so the shoulders, arms and head
##    with it) scaled a few percent. The legs are never scaled: the stride and
##    the root motion stay the clip's, so no foot slides.
##  - Glances: at rest (idle, block) he now and then turns his head, toward a
##    squadmate or a foe (`look_at`) or just off to one side, and back; the neck
##    takes a third of the turn. `glance` (0..1) is how restless he is.
extends SkeletonModifier3D

var head_scale := 1.0
var chest_scale := 1.0
var glance := 0.0
## The footman (his `state`): glances only while he stands.
var unit: Node3D
## Nodes he may glance at.
var look_at: Array = []
var _head := -1
var _neck := -1
var _chest := -1
var _yaw := 0.0
var _pitch := 0.0
var _goal := Vector2.ZERO
var _goal_node: Node3D
var _wait := 0.0
var _on := 0.0
var _rng := RandomNumberGenerator.new()
## The head bone's forward (the model's +Z at rest) in its own space.
var _fwd := Vector3.BACK

const MAX_YAW := deg_to_rad(50.0)


func _ready() -> void:
	_rng.randomize()
	_wait = _rng.randf_range(0.5, 3.0)
	var sk := get_skeleton()
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		if n.ends_with("Head"):
			_head = i
		elif n.ends_with("Neck"):
			_neck = i
		elif n.ends_with("Spine1"):
			_chest = i
	if _head >= 0:
		_fwd = sk.get_bone_global_rest(_head).basis.inverse() * Vector3.BACK


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or _head < 0:
		return
	if _chest >= 0 and chest_scale != 1.0:
		sk.set_bone_pose_scale(_chest, sk.get_bone_pose_scale(_chest) * chest_scale)
	if head_scale != 1.0:
		sk.set_bone_pose_scale(_head, sk.get_bone_pose_scale(_head) * head_scale)
	var resting: bool = unit != null and glance > 0.0 and String(unit.get("state")) in ["idle", "block"]
	_on = move_toward(_on, 1.0 if resting else 0.0, delta * 2.5)
	if _on <= 0.0:
		_yaw = 0.0
		_pitch = 0.0
		return
	_wait -= delta
	if _wait <= 0.0:
		_pick()
	var hp := sk.get_bone_global_pose(_head)
	if _goal_node != null and is_instance_valid(_goal_node):
		# Toward the node, from his head, relative to where the clip has him face.
		var at := sk.global_transform.affine_inverse() * (_goal_node.global_position + Vector3(0, 1.5, 0))
		var d := at - hp.origin
		var fwd := hp.basis * _fwd
		var want := angle_difference(atan2(fwd.x, fwd.z), atan2(d.x, d.z))
		_goal.x = clampf(want, -MAX_YAW, MAX_YAW) if absf(want) < deg_to_rad(110.0) else 0.0
	var k := 1.0 - exp(-delta * 7.0)
	_yaw = lerpf(_yaw, _goal.x, k)
	_pitch = lerpf(_pitch, _goal.y, k)
	var up := Vector3.UP
	if _neck >= 0:
		var np := sk.get_bone_global_pose(_neck)
		np.basis = Basis(up, _yaw * 0.35 * _on) * np.basis
		sk.set_bone_global_pose(_neck, np)
		hp = sk.get_bone_global_pose(_head)
	var side := Basis(up, _yaw) * Vector3.RIGHT
	hp.basis = Basis(up, _yaw * 0.65 * _on) * Basis(side, _pitch * _on) * hp.basis
	sk.set_bone_global_pose(_head, hp)


## The next glance: a squadmate or a foe, off to one side, or back ahead.
func _pick() -> void:
	_goal_node = null
	var r := _rng.randf()
	var others := look_at.filter(func(n): return is_instance_valid(n) and n != unit)
	if r < 0.4 and not others.is_empty():
		_goal_node = others[_rng.randi() % others.size()]
		_goal.y = _rng.randf_range(-0.05, 0.08)
	elif r < 0.7:
		_goal = Vector2(_rng.randf_range(-1.0, 1.0) * MAX_YAW * 0.7 * glance, _rng.randf_range(-0.08, 0.14))
	else:
		_goal = Vector2.ZERO
	_wait = _rng.randf_range(1.2, 4.5) / (0.6 + glance)
