"""Aim a thrust's blade at the target (background Mixar / Blender).

  mixar.exe --background <rig.blend> --python aim_thrust.py -- <clip> <in0> <in1> <out0> <out1> [pitch_deg]

Mixamo's "Attack thrust" drives the fist forward with the knuckles up, for a
weapon that leaves the fist forward; his sword leaves it upward, so at full
reach the blade stands upright. The wrist turns the blade onto the line ahead
(forward, -Y, tipped `pitch_deg` down, default 10): not at all before frame
`in0`, fully from `in1` to `out0`, and not at all again from `out1`, eased in
between. The turn is the shortest from the blade's own direction each frame,
so the wrist bends no more than it must. Prints the largest wrist turn and the
tip's farthest reach; run clear_blade.py after.
"""
import math
import sys

import bpy
from mathutils import Quaternion, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
CLIP = argv[0]
IN0, IN1, OUT0, OUT1 = (int(v) for v in argv[1:5])
PITCH = math.radians(float(argv[5]) if len(argv) > 5 else 10.0)
sc = bpy.context.scene
rig = bpy.data.objects["FootmanRig"]
rig.location = (0, 0, 0)
rig.rotation_euler = (0, 0, 0)
sword = bpy.data.objects["Sword"]
hand = rig.pose.bones["mixamorig:RightHand"]
rig.animation_data.action = bpy.data.actions["idle"]
sc.frame_set(1)
tip_local = max((v.co for v in sword.data.vertices), key=lambda co: ((sword.matrix_world @ co) - rig.matrix_world @ hand.head).length).copy()
AIM = Vector((0.0, -math.cos(PITCH), -math.sin(PITCH)))


def smooth(x, a, c):
    t = min(1.0, max(0.0, (x - a) / float(c - a)))
    return t * t * (3 - 2 * t)


act = bpy.data.actions[CLIP]
rig.animation_data.action = act
f0, f1 = (int(v) for v in act.frame_range)
turn, reach = 0.0, 0.0
for f in range(f0, f1 + 1):
    w = smooth(f, IN0, IN1) * (1.0 - smooth(f, OUT0, OUT1))
    sc.frame_set(f)
    if w > 0.0:
        grip = rig.matrix_world @ hand.head
        blade = (sword.matrix_world @ tip_local - grip).normalized()
        q = Quaternion().slerp(blade.rotation_difference(AIM), w)
        m = hand.matrix.copy()
        rot = (q.to_matrix() @ m.to_3x3()).to_4x4()
        rot.translation = m.translation
        hand.matrix = rot
        hand.scale = (1.0, 1.0, 1.0)  # a shear leaves scale on the bone; no clip keys it, so it would hold in every clip
        bpy.context.view_layer.update()
        hand.keyframe_insert("rotation_quaternion", frame=f)
        turn = max(turn, math.degrees(q.angle))
    reach = max(reach, -(sword.matrix_world @ tip_local).y)
print("AIM_THRUST %s: blade on the line ahead (%.0f deg down) f%d-%d, eased in from f%d and out by f%d; wrist turned up to %.0f deg; tip reaches %.2f m" % (
    CLIP, math.degrees(PITCH), IN1, OUT0, IN0, OUT1, turn, reach))
rig.animation_data.action = bpy.data.actions["idle"]
bpy.ops.wm.save_mainfile(compress=True)
print("AIM_SAVED")
