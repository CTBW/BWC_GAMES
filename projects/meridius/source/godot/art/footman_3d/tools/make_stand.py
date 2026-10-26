"""Build his standing idle from the guard (background Mixar / Blender).

  mixar.exe --background <rig.blend> --python make_stand.py

From `stand_src` (Mixamo "Standing Idle - Footman", retargeted in place): the
quiet idle he plays at rest, breathing in his guard. Its first pose is the
sword-and-shield guard that "Sword And Shield Idle" starts on, the guard every
other clip starts and ends on (idle's first frame). The blade passes turned the
sword wrist on idle (10 degrees at its first frame); the stand gets the same pose:

  * every bone starts on idle's first pose (rotation and the hips' place) and
    then moves as it moves in the source from the source's first frame;
  * the loop closes exactly: what is left between the last and the first frame
    (a few hundredths of a degree) is spread over the clip.

So the stand, the guard idle and every clip that starts or ends on the guard meet
with no blend. The stand's own motion is small (the sword arm turns up to about
7 degrees). Prints how far its first frame is from idle's, the loop seam and the
largest turn from its first frame. Run after the guard idle's passes; the blade
check (sword_report.py) then runs on it as on every clip.
"""
import math

import bpy
from mathutils import Quaternion

sc = bpy.context.scene
rig = bpy.data.objects["FootmanRig"]
rig.rotation_euler = (0, 0, 0)
src = bpy.data.actions["stand_src"]
idle = bpy.data.actions["idle"]
bones = [pb.name for pb in rig.pose.bones]
f0, f1 = (int(v) for v in src.frame_range)
N = f1 - f0 + 1


def sample(act, frames):
    rig.animation_data.action = act
    out = []
    for f in frames:
        sc.frame_set(f)
        out.append({n: (rig.pose.bones[n].rotation_quaternion.copy(), rig.pose.bones[n].location.copy()) for n in bones})
    return out


guard = sample(idle, [1])[0]
raw = sample(src, range(f0, f1 + 1))

# Each bone: idle's first pose, then the source's own motion from its first frame.
poses = []
for fr in raw:
    p = {}
    for n in bones:
        q0, l0 = raw[0][n]
        q, l = fr[n]
        gq, gl = guard[n]
        p[n] = ((gq @ (q0.inverted() @ q)).normalized(), gl + (l - l0))
    poses.append(p)
# Close the loop: spread the last frame's residual from the first over the clip.
for n in bones:
    qe = (poses[-1][n][0].inverted() @ poses[0][n][0]).normalized()
    le = poses[0][n][1] - poses[-1][n][1]
    for i in range(N):
        w = i / (N - 1)
        q, l = poses[i][n]
        poses[i][n] = ((q @ Quaternion().slerp(qe, w)).normalized(), l + le * w)

old = bpy.data.actions.get("stand")
if old is not None:
    bpy.data.actions.remove(old)
stand = bpy.data.actions.new("stand")
stand.use_fake_user = True
stand["source"] = src.get("source", "Standing Idle - Footman.fbx")
stand["built_from"] = "stand_src on idle's first pose"
stand["frames"] = N
stand["root_vel"] = [0.0, 0.0]
rig.animation_data.action = stand
for i, p in enumerate(poses):
    for n in bones:
        pb = rig.pose.bones[n]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion, pb.location = p[n]
        pb.scale = (1.0, 1.0, 1.0)  # no clip keys scale; a stray one would hold in every clip
        pb.keyframe_insert("rotation_quaternion", frame=i + 1)
        if n == "mixamorig:Hips":
            pb.keyframe_insert("location", frame=i + 1)


def world(act, f):
    rig.animation_data.action = act
    sc.frame_set(f)
    bpy.context.view_layer.update()
    return {n: (rig.pose.bones[n].matrix.to_quaternion(), rig.pose.bones[n].head.copy()) for n in bones}


def gap(a, b):
    turn = max(math.degrees(a[n][0].rotation_difference(b[n][0]).angle) for n in a)
    move = max((a[n][1] - b[n][1]).length for n in a)
    return "%.2f deg, %.2f cm" % (turn, 100 * move)


g, s1 = world(idle, 1), world(stand, 1)
most = max(max(math.degrees(s1[n][0].rotation_difference(q).angle) for n, (q, _) in world(stand, f).items())
           for f in range(1, N + 1))
print("STAND frames", N, "| first frame from idle's first:", gap(s1, g), "| loop seam:", gap(world(stand, N), s1),
      "| largest turn from its first frame: %.1f deg" % most)
rig.animation_data.action = idle
sc.frame_set(1)
bpy.ops.wm.save_mainfile(compress=True)
print("STAND_SAVED", bpy.data.filepath)
