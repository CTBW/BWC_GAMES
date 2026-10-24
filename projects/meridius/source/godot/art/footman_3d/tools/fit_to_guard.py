"""Fit a standing clip to his guard (background Mixar / Blender).

  mixar.exe --background <rig.blend> --python fit_to_guard.py -- <source> <out> [ease_in] [ease_out]

For a clip made in another stance (Mixamo's "Stab - Footmen" stands narrower
and higher than his sword-and-shield guard), so that it starts and ends on
idle's first frame as the attack does:

  * his feet stay in idle's stance, each moving only as it moves in the source
    from its own first frame (a heel rising, a toe turning); the legs are
    solved to reach them (two-bone IK, the knee kept in its bend plane);
  * the hips do what the source's do, shifted onto that stance (the source's
    first frame lands on idle's first);
  * spine, head and arms ease from idle's first pose into the source's over
    `ease_in` frames (default 6) and back over the last `ease_out` (default 10);
    the legs' knees and toes ease the same way before they are solved.

Prints each foot's largest move from idle's spot, and the largest move of a
hand, foot or the head in one frame.
"""
import math
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
EASE_IN = int(argv[2]) if len(argv) > 2 else 6
EASE_OUT = int(argv[3]) if len(argv) > 3 else 10
sc = bpy.context.scene
rig = bpy.data.objects["FootmanRig"]
rig.location = (0, 0, 0)
rig.rotation_euler = (0, 0, 0)
rig.animation_data_create()
PB = rig.pose.bones
NAMES = [pb.name for pb in PB]
LEG = {"mixamorig:%s%s" % (s, n) for s in ("Left", "Right") for n in ("UpLeg", "Leg", "Foot", "ToeBase", "Toe_End")}


def b(n):
    return PB["mixamorig:" + n]


def smooth(x, a, c):
    t = min(1.0, max(0.0, (x - a) / float(c - a)))
    return t * t * (3 - 2 * t)


def grab(action, f):
    rig.animation_data.action = action
    sc.frame_set(f)
    return {
        "q": {n: PB[n].rotation_quaternion.copy() for n in NAMES},
        "loc": b("Hips").location.copy(),
        "m": {n: PB[n].matrix.copy() for n in NAMES},
    }


def put(q, loc):
    for n in NAMES:
        PB[n].rotation_quaternion = q[n]
    b("Hips").location = loc
    bpy.context.view_layer.update()


def set_matrix(pb, m):
    pb.matrix = m
    pb.scale = (1.0, 1.0, 1.0)  # a shear leaves scale on the bone; no clip keys it, so it would hold in every clip
    bpy.context.view_layer.update()


def ik_leg(side, want, foot_rot):
    """Two-bone IK (as make_transitions.py)."""
    up, lo, ft = b(side + "UpLeg"), b(side + "Leg"), b(side + "Foot")
    hip = up.head.copy()
    knee = lo.head.copy()
    l1 = (knee - hip).length
    l2 = (ft.head - knee).length
    d = want - hip
    dist = min(max(d.length, abs(l1 - l2) + 1e-4), l1 + l2 - 1e-4)
    dn = d.normalized()
    pole = (knee - hip) - dn * (knee - hip).dot(dn)
    pole = pole.normalized() if pole.length > 1e-6 else Vector((0, -1, 0))
    a = (l1 * l1 + dist * dist - l2 * l2) / (2 * dist)
    h = math.sqrt(max(0.0, l1 * l1 - a * a))
    knee_new = hip + dn * a + pole * h
    q1 = (knee - hip).rotation_difference(knee_new - hip)
    m = (q1.to_matrix() @ up.matrix.to_3x3()).to_4x4()
    m.translation = hip
    set_matrix(up, m)
    knee_now = lo.head.copy()
    q2 = (ft.head - knee_now).rotation_difference(hip + dn * dist - knee_now)
    m = (q2.to_matrix() @ lo.matrix.to_3x3()).to_4x4()
    m.translation = knee_now
    set_matrix(lo, m)
    m = foot_rot.to_matrix().to_4x4()
    m.translation = ft.head.copy()
    set_matrix(ft, m)


src = bpy.data.actions[SRC]
f0, f1 = (int(v) for v in src.frame_range)
S = [grab(src, f) for f in range(f0, f1 + 1)]
N = len(S)
I = grab(bpy.data.actions["idle"], int(bpy.data.actions["idle"].frame_range[0]))
HIP_OFF = I["m"]["mixamorig:Hips"].translation - S[0]["m"]["mixamorig:Hips"].translation
FEET = ("Left", "Right")
for a_ in [a_ for a_ in bpy.data.actions if a_.name == OUT]:
    bpy.data.actions.remove(a_)
act = bpy.data.actions.new(OUT)
act.use_fake_user = True
act["source"] = "%s fitted to idle's guard (eased %d in, %d out)" % (SRC, EASE_IN, EASE_OUT)
rig.animation_data.action = act
for pb in PB:
    pb.rotation_mode = "QUATERNION"
for i, s in enumerate(S):
    # 1 at both ends (idle's pose), 0 through the middle (the source's).
    w = max(1.0 - smooth(i, 0, EASE_IN), smooth(i, N - 1 - EASE_OUT, N - 1))
    # The legs ease too, so at the ends the solver starts from idle's own legs
    # (its knees, its toes) and the pose is idle's exactly.
    q = {n: s["q"][n].slerp(I["q"][n], w) for n in NAMES}
    put(q, s["loc"])
    hm = b("Hips").matrix.copy()
    hm.translation = s["m"]["mixamorig:Hips"].translation + HIP_OFF
    set_matrix(b("Hips"), hm)
    for side in FEET:
        n = "mixamorig:%sFoot" % side
        want = I["m"][n].translation + (s["m"][n].translation - S[0]["m"][n].translation)
        rot = (s["m"][n].to_quaternion() @ S[0]["m"][n].to_quaternion().inverted()) @ I["m"][n].to_quaternion()
        ik_leg(side, want, rot)
    for n in NAMES:
        PB[n].keyframe_insert("rotation_quaternion", frame=i + 1)
    b("Hips").keyframe_insert("location", frame=i + 1)
act.frame_range = (1, N)
act["frames"] = N

worst = {}
for side in FEET:
    n = "mixamorig:%sFoot" % side
    m = 0.0
    for i in range(N):
        sc.frame_set(i + 1)
        m = max(m, (PB[n].head.xy - I["m"][n].translation.xy).length)
    worst[side] = round(100 * m, 1)
jump, prev = 0.0, None
for i in range(N):
    sc.frame_set(i + 1)
    cur = {n: PB[n].matrix.translation.copy() for n in ("mixamorig:LeftHand", "mixamorig:RightHand", "mixamorig:Head", "mixamorig:LeftFoot", "mixamorig:RightFoot")}
    if prev:
        jump = max(jump, max((cur[n] - prev[n]).length for n in cur))
    prev = cur
sc.frame_set(1)
first = max((PB[n].matrix.translation - I["m"][n].translation).length for n in NAMES)
sc.frame_set(N)
last = max((PB[n].matrix.translation - I["m"][n].translation).length for n in NAMES)
print("FIT %s -> %s: %d frames; feet off idle's spots at most %s cm; first/last frame off idle's first %.1f / %.1f cm; largest one-frame move %.1f cm" % (
    SRC, OUT, N, worst, 100 * first, 100 * last, 100 * jump))
rig.animation_data.action = bpy.data.actions["idle"]
bpy.ops.wm.save_mainfile(compress=True)
print("FIT_SAVED")
