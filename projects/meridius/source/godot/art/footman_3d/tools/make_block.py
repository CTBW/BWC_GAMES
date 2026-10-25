"""Rebuild the footman's block from the sword-and-shield guard (background Mixar / Blender).

  mixar.exe --background <rig.blend> --python make_block.py -- [raise_deg] [inward_deg] [lean_deg] [frames]

Mixamo's "Standing Block Idle" is a shieldless arms-crossed block: with a
shield on the forearm it turns the shield edge-on. The block is built from the
guard of "Sword And Shield Idle" instead (shield square in front, eagle out):
its calm opening is taken, the shield arm is lifted at the shoulder while the
forearm keeps its world orientation (the shield rises and stays upright, face
forward), the shield is drawn a little toward the body's centre, the chest
leans in behind it, both arms hold still on the breathing body, and the end
blends back into the start so it loops.
The Mixamo block is kept as the action "block_mixamo".
"""
import math
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RAISE = float(argv[0]) if len(argv) > 0 else 22.0
INWARD = float(argv[1]) if len(argv) > 1 else 8.0
LEAN = float(argv[2]) if len(argv) > 2 else 5.0
N = int(argv[3]) if len(argv) > 3 else 60
BLEND = 14

sc = bpy.context.scene
rig = bpy.data.objects["FootmanRig"]
rig.rotation_euler = (0, 0, 0)
old = bpy.data.actions.get("block")
if old is not None and old.get("built_from") != "guard":
    old.name = "block_mixamo"
    old.use_fake_user = True
elif old is not None:
    bpy.data.actions.remove(old)
idle = bpy.data.actions["idle"]
bones = [pb.name for pb in rig.pose.bones]

# 1. Sample the guard's opening (basis values).
rig.animation_data.action = idle
base = []
for f in range(1, N + 1):
    sc.frame_set(f)
    base.append({n: (rig.pose.bones[n].rotation_quaternion.copy(), rig.pose.bones[n].location.copy()) for n in bones})
# A raised guard holds still: both arms keep the opening's pose (the idle's
# sword fidgets would swing the blade half a metre), riding on the breathing body.
ARMS = [n for n in bones if any(n.endswith(s + x) for s in ("Left", "Right") for x in ("Shoulder", "Arm", "ForeArm", "Hand"))]
for i in range(1, N):
    for n in ARMS:
        base[i][n] = base[0][n]
# 2. Loop: the last frames ease back into the first.
for i in range(N - BLEND, N):
    w = (i - (N - BLEND) + 1) / BLEND
    w = w * w * (3 - 2 * w)
    for n in bones:
        q, l = base[i][n]
        q0, l0 = base[0][n]
        base[i][n] = (q.slerp(q0, w), l.lerp(l0, w))

block = bpy.data.actions.new("block")
block.use_fake_user = True
block["built_from"] = "guard"
block["frames"] = N
block["source"] = "Sword And Shield Idle.fbx (guard, shield arm raised %g deg, inward %g, lean %g)" % (RAISE, INWARD, LEAN)
rig.animation_data.action = block

X = Vector((1, 0, 0))  # the body's left; the rig faces -Y
Z = Vector((0, 0, 1))
r_raise = Quaternion(X, -math.radians(RAISE))   # a forward-pointing arm swings up
r_in = Quaternion(Z, -math.radians(INWARD))     # the left arm swings toward the centre
r_lean = Quaternion(X, math.radians(LEAN))      # the chest tips forward


def set_world_rot(pb, world_rot):
    """Give a pose bone this armature-space rotation, keeping its head where it is."""
    m = world_rot.to_matrix().to_4x4()
    m.translation = pb.matrix.translation
    pb.matrix = m
    pb.scale = (1.0, 1.0, 1.0)  # a shear leaves scale on the bone; no clip keys it, so it would hold in every clip


for i in range(N):
    for n in bones:
        pb = rig.pose.bones[n]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion, pb.location = base[i][n]
    bpy.context.view_layer.update()
    sp = rig.pose.bones["mixamorig:Spine1"]
    set_world_rot(sp, r_lean @ sp.matrix.to_quaternion())
    bpy.context.view_layer.update()
    arm = rig.pose.bones["mixamorig:LeftArm"]
    fore = rig.pose.bones["mixamorig:LeftForeArm"]
    fore_world = fore.matrix.to_quaternion()
    set_world_rot(arm, r_in @ r_raise @ arm.matrix.to_quaternion())
    bpy.context.view_layer.update()
    # The forearm keeps its own orientation: the shield rises, upright, face forward.
    set_world_rot(fore, r_in @ fore_world)
    bpy.context.view_layer.update()
    for n in bones:
        pb = rig.pose.bones[n]
        pb.keyframe_insert("rotation_quaternion", frame=i + 1)
        if n == "mixamorig:Hips":
            pb.keyframe_insert("location", frame=i + 1)

sh = bpy.data.objects["Shield"]
sc.frame_set(1)
print("BLOCK_BUILT frames", N, "shield centre", [round(v, 3) for v in sh.matrix_world.translation],
      "shield up", [round(v, 2) for v in (sh.matrix_world.to_3x3() @ Vector((0, 0, 1)))],
      "shield face", [round(v, 2) for v in (sh.matrix_world.to_3x3() @ Vector((0, -1, 0)))])
bpy.ops.wm.save_mainfile(compress=True)
print("BLOCK_SAVED", bpy.data.filepath)
