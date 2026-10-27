## Stride warping for unit3d.gd's march: his steps lengthened or shortened
## along his heading by `stride`, so a march stretched to land on its target
## keeps his feet planted where the walk's own stride would slip them. Each
## foot's offset from his hips along his heading is scaled by `stride`, and the
## leg reaches it (two-bone IK): the knee bends in the plane the clip has it,
## the foot keeps its turn, and the hips come down as far as the farther-
## reaching leg needs to keep its extension from the clip. At 1.0 it leaves the
## pose alone.
extends SkeletonModifier3D

## The most the hips come down, as a share of the leg's extension.
const MAX_DROP := 0.1

var stride := 1.0
## His heading and up in the skeleton's space.
var forward := Vector3(0, 0, 1)
var up := Vector3.UP
var hips := -1
## Each leg's thigh, shin and foot bones.
var legs: Array = []


## Finds the hips and legs (`bone` finds a bone by its name's end, -1 if
## missing); `basis` turns the skeleton's space into his. False without them.
func setup(bone: Callable, basis: Basis) -> bool:
	hips = bone.call("Hips")
	for side in ["Left", "Right"]:
		var leg := [bone.call(side + "UpLeg"), bone.call(side + "Leg"), bone.call(side + "Foot")]
		if leg.has(-1):
			return false
		legs.append(leg)
	var inv := basis.inverse()
	forward = (inv * Vector3(0, 0, 1)).normalized()
	up = (inv * Vector3.UP).normalized()
	return hips >= 0


func _process_modification_with_delta(_delta: float) -> void:
	if absf(stride - 1.0) < 1e-4 or hips < 0:
		return
	var sk := get_skeleton()
	var h := sk.get_bone_global_pose(hips)
	# Where each foot goes, and how far the hips must come down for the leg
	# reaching farthest to keep its extension.
	var plans := []
	var drop := 0.0
	for leg in legs:
		var a := sk.get_bone_global_pose(leg[0]).origin
		var b := sk.get_bone_global_pose(leg[1]).origin
		var foot := sk.get_bone_global_pose(leg[2])
		var c := foot.origin
		var target := c + forward * (c - h.origin).dot(forward) * (stride - 1.0)
		var reach := (c - a).length()
		var depth := (a - target).dot(up)
		var flat := (target - a) + up * depth
		var room := reach * reach - flat.length_squared()
		if room > 0.0:
			drop = maxf(drop, minf(depth - sqrt(room), MAX_DROP * reach))
		# The knee's side of the line from hip to ankle (forward, for a straight leg).
		var line := (c - a).normalized()
		var pole := (b - a) - line * (b - a).dot(line)
		if pole.length() < 1e-3 * (b - a).length():
			pole = forward
		plans.append([target, pole.normalized(), foot.basis])
	if drop > 0.0:
		h.origin -= up * drop
		sk.set_bone_global_pose(hips, h)
	for i in legs.size():
		_reach(sk, legs[i], plans[i][0], plans[i][1], plans[i][2])


## Thigh and shin turned so the ankle is on `target` (or as near as the leg
## reaches), the knee toward `pole`; the foot keeps `foot_basis`.
func _reach(sk: Skeleton3D, leg: Array, target: Vector3, pole: Vector3, foot_basis: Basis) -> void:
	var thigh := sk.get_bone_global_pose(leg[0])
	var a := thigh.origin
	var b := sk.get_bone_global_pose(leg[1]).origin
	var c := sk.get_bone_global_pose(leg[2]).origin
	var l1 := (b - a).length()
	var l2 := (c - b).length()
	var to := target - a
	var d := clampf(to.length(), absf(l1 - l2) + 1e-4, l1 + l2 - 1e-4)
	var dir := to.normalized()
	var side := (pole - dir * pole.dot(dir)).normalized()
	var x := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var knee := a + dir * x + side * sqrt(maxf(l1 * l1 - x * x, 0.0))
	thigh.basis = Basis(Quaternion((b - a).normalized(), (knee - a).normalized())) * thigh.basis
	sk.set_bone_global_pose(leg[0], thigh)
	var shin := sk.get_bone_global_pose(leg[1])
	c = sk.get_bone_global_pose(leg[2]).origin
	shin.basis = Basis(Quaternion((c - shin.origin).normalized(), (a + dir * d - shin.origin).normalized())) * shin.basis
	sk.set_bone_global_pose(leg[1], shin)
	var foot := sk.get_bone_global_pose(leg[2])
	sk.set_bone_global_pose(leg[2], Transform3D(foot_basis, foot.origin))
