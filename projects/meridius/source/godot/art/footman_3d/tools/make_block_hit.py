"""A hit taken behind the raised shield (background Mixar / Blender).

  mixar.exe --background <rig.blend> --python make_block_hit.py -- [recoil_deg]

`block_hit` is the hit clip's reaction layered onto the block: every bone
keeps the block's first-frame pose and adds what the hit does away from its
own first frame (the hit starts and ends in idle's first pose). The shield
arm also gives `recoil_deg` (default 10) at the shoulder as the blow lands,
easing back, so the shield takes the jolt instead of dropping out of guard.
It starts and ends in the block's first pose, so block follows with no blend.
"""
import math
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RECOIL = math.radians(float(argv[0]) if argv else 10.0)
FPS = 30.0
sc = bpy.context.scene
rig = bpy.data.objects["FootmanRig"]
rig.location = (0, 0, 0)
rig.rotation_euler = (0, 0, 0)
PB = rig.pose.bones
NAMES = [pb.name for pb in PB]


def grab(name, f):
    rig.animation_data.action = bpy.data.actions[name]
    sc.frame_set(f)
    return {n: PB[n].rotation_quaternion.copy() for n in NAMES}, PB["mixamorig:Hips"].location.copy()


hit = bpy.data.actions["hit"]
h0, h1 = (int(v) for v in hit.frame_range)
base_q, base_loc = grab("hit", h0)
blk_q, blk_loc = grab("block", int(bpy.data.actions["block"].frame_range[0]))
frames = []
for f in range(h0, h1 + 1):
    frames.append(grab("hit", f))
# Where the blow lands: the hit's hips are pushed back fastest.
rig.animation_data.action = hit
hips = []
for f in range(h0, h1 + 1):
    sc.frame_set(f)
    hips.append(PB["mixamorig:Hips"].head.copy())
speed = [0.0] + [(hips[k] - hips[k - 1]).length for k in range(1, len(hips))]
impact = max(range(len(speed)), key=lambda k: speed[k])
for a in [a for a in bpy.data.actions if a.name == "block_hit"]:
    bpy.data.actions.remove(a)
act = bpy.data.actions.new("block_hit")
act.use_fake_user = True
act["source"] = "hit layered onto block (shield kept raised, %d deg recoil)" % round(math.degrees(RECOIL))
rig.animation_data.action = act
for i, (q, loc) in enumerate(frames):
    for n in NAMES:
        d = base_q[n].inverted() @ q[n]
        PB[n].rotation_quaternion = blk_q[n] @ d
    PB["mixamorig:Hips"].location = blk_loc + (loc - base_loc)
    bpy.context.view_layer.update()
    # The shield arm recoils at the shoulder: a quick push back, a slower return.
    t = (i - impact) / FPS
    k = 0.0 if t < -0.05 else (math.sin(min(1.0, (t + 0.05) / 0.1) * math.pi / 2) if t < 0.05 else math.exp(-(t - 0.05) / 0.16))
    if k > 1e-4:
        arm = PB["mixamorig:LeftArm"]
        r = (PB["mixamorig:RightArm"].head - arm.head).normalized()  # to his right
        h = arm.matrix.translation.copy()
        # A negative turn about the right-pointing shoulder line takes the arm back.
        arm.matrix = Matrix.Translation(h) @ Matrix.Rotation(-RECOIL * k, 4, r) @ Matrix.Translation(-h) @ arm.matrix
        arm.scale = (1.0, 1.0, 1.0)  # a shear leaves scale on the bone; no clip keys it, so it would hold in every clip
        bpy.context.view_layer.update()
    for n in NAMES:
        PB[n].keyframe_insert("rotation_quaternion", frame=i + 1)
    PB["mixamorig:Hips"].keyframe_insert("location", frame=i + 1)
act.frame_range = (1, len(frames))
act["frames"] = len(frames)
print("BLOCK_HIT", len(frames), "frames, blow at f%d" % (impact + 1))
rig.animation_data.action = bpy.data.actions["idle"]
bpy.ops.wm.save_mainfile(compress=True)
