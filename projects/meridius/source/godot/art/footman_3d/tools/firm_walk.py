"""Make a retargeted walk step firmly (background Mixar / Blender).

  mixar.exe --background <rig.blend> --python firm_walk.py -- <action> [lift_m] [narrow_m] [upright_deg]

Uses the action's root_vel (its ground speed). Per foot:
  * stance (foot within 4 cm of its lowest point): the ankle is pinned to the
    world spot where it landed (blended in and out over 2 frames), so a planted
    foot does not slide;
  * swing: the ankle is lifted by `lift` metres on a sine arc, so the knee
    comes up and the step is set down instead of skimming the ground;
  * both feet are drawn `narrow` metres toward the body's centre line.
Solved with an analytic two-bone IK on UpLeg / Leg (bend kept in the leg's own
plane), the foot keeps its world orientation. Prints slip and clearance
before and after.
"""
import math
import sys

import bpy
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
NAME = argv[0]
LIFT = float(argv[1]) if len(argv) > 1 else 0.05
NARROW = float(argv[2]) if len(argv) > 2 else 0.03
UPRIGHT = float(argv[3]) if len(argv) > 3 else 0.0  # degrees: chest straightened, chin lifted
sc = bpy.context.scene
rig = bpy.data.objects["FootmanRig"]
rig.rotation_euler = (0, 0, 0)
rig.location = (0, 0, 0)
act = bpy.data.actions[NAME]
rig.animation_data.action = act
f0, f1 = (int(v) for v in act.frame_range)
frames = list(range(f0, f1 + 1))
V = Vector(tuple(act["root_vel"]) + (0.0,))
PB = rig.pose.bones


def b(n):
    return PB["mixamorig:" + n]


def measure():
    res = {}
    for s in ("Left", "Right"):
        A, T = [], []
        for f in frames:
            sc.frame_set(f)
            off = V * ((f - f0) / 30.0)
            A.append(list(b(s + "Foot").head + off))
            T.append(b(s + "ToeBase").head.z)
        A = np.array(A)
        T = np.array(T)
        g = A[:, 2] < A[:, 2].min() + 0.025
        slip = 0.0
        i = 0
        while i < len(g):
            if g[i]:
                j = i
                while j + 1 < len(g) and g[j + 1]:
                    j += 1
                slip = max(slip, float(np.linalg.norm(A[j, :2] - A[i, :2])))
                i = j + 1
            else:
                i += 1
        res[s] = (round(100 * slip, 1), round(100 * float(T[~g].max() - T.min()) if (~g).any() else 0, 1))
    return res


before = measure()
# A loop whose last frame repeats its first is planned cyclically (three
# copies of the cycle laid end to end along the travel, the middle one kept),
# so a stance or a swing that runs over the loop's seam stays one piece and
# the last frame still matches the first.
sc.frame_set(f0)
first = {pb.name: pb.matrix.translation.copy() for pb in PB}
sc.frame_set(f1)
CYCLIC = max((PB[n].matrix.translation - first[n]).length for n in first) < 0.005
U = frames[:-1] if CYCLIC else frames
NU = len(U)
COPIES, MID = (3, NU) if CYCLIC else (1, 0)
# 1. Sample the ankles in the world (with travel) and plan targets.
plan = {}
for s in ("Left", "Right"):
    R = []
    for f in U:
        sc.frame_set(f)
        R.append(b(s + "Foot").head.copy())
    n = NU * COPIES
    A = [R[k % NU] + V * (k / 30.0) for k in range(n)]
    z = np.array([a.z for a in A])
    ground = z < z.min() + 0.04
    tgt = [a.copy() for a in A]
    w = np.zeros(n)
    i = 0
    while i < n:
        if ground[i]:
            j = i
            while j + 1 < n and ground[j + 1]:
                j += 1
            mid = (i + j) // 2
            spot = A[mid].copy()
            spot.z = min(a.z for a in A[i:j + 1])
            for k in range(max(0, i - 2), min(n, j + 3)):
                wk = 1.0 if i <= k <= j else 1.0 - (min(abs(k - i), abs(k - j))) / 3.0
                if wk > w[k]:
                    w[k] = wk
                    tgt[k] = spot
            i = j + 1
        else:
            i += 1
    # Swing lift: a sine arc over each run of swing frames.
    lift = np.zeros(n)
    i = 0
    while i < n:
        if not ground[i]:
            j = i
            while j + 1 < n and not ground[j + 1]:
                j += 1
            L = j - i + 1
            for k in range(i, j + 1):
                lift[k] = LIFT * math.sin(math.pi * (k - i + 1) / (L + 1))
            i = j + 1
        else:
            i += 1
    plan[s] = (A, tgt, w, lift)

# 2. Apply per frame: target in rig space = world target minus travel. A
# cyclic clip's last frame takes the first frame's targets.
for idx, f in enumerate(frames):
    sc.frame_set(f)
    k = MID + (idx if idx < NU else 0)
    off = V * (k / 30.0)
    for s in ("Left", "Right"):
        A, tgt, w, lift = plan[s]
        want = (A[k] * (1 - w[k]) + tgt[k] * w[k]) - off
        want.z += lift[k]
        side = 1.0 if s == "Left" else -1.0
        want.x -= side * NARROW
        up, lo, ft = b(s + "UpLeg"), b(s + "Leg"), b(s + "Foot")
        foot_rot = ft.matrix.to_3x3().copy()
        hip = up.head.copy()
        knee = lo.head.copy()
        l1 = (knee - hip).length
        l2 = (ft.head - knee).length
        d = want - hip
        dist = min(max(d.length, abs(l1 - l2) + 1e-4), l1 + l2 - 1e-4)
        dn = d.normalized()
        # Bend plane: keep the current knee direction (pole).
        pole = (knee - hip) - dn * (knee - hip).dot(dn)
        pole = pole.normalized() if pole.length > 1e-6 else Vector((0, -1, 0))
        a = (l1 * l1 + dist * dist - l2 * l2) / (2 * dist)
        h = math.sqrt(max(0.0, l1 * l1 - a * a))
        knee_new = hip + dn * a + pole * h
        # Upper leg: turn its direction onto the new knee.
        q1 = (knee - hip).rotation_difference(knee_new - hip)
        m = up.matrix.copy()
        r = q1.to_matrix() @ m.to_3x3()
        m2 = r.to_4x4()
        m2.translation = hip
        up.matrix = m2
        up.scale = (1.0, 1.0, 1.0)  # a shear leaves scale on the bone; no clip keys it, so it would hold in every clip
        bpy.context.view_layer.update()
        # Lower leg: from the knee onto the target.
        knee_now = lo.head.copy()
        q2 = (ft.head - knee_now).rotation_difference(hip + dn * dist - knee_now)
        m = lo.matrix.copy()
        r = q2.to_matrix() @ m.to_3x3()
        m3 = r.to_4x4()
        m3.translation = knee_now
        lo.matrix = m3
        lo.scale = (1.0, 1.0, 1.0)
        bpy.context.view_layer.update()
        # The foot keeps its world orientation (flat when planted).
        m4 = foot_rot.to_4x4()
        m4.translation = ft.head.copy()
        ft.matrix = m4
        ft.scale = (1.0, 1.0, 1.0)
        bpy.context.view_layer.update()
        for pb in (up, lo, ft):
            pb.keyframe_insert("rotation_quaternion", frame=f)
    if UPRIGHT:
        from mathutils import Matrix, Quaternion
        for bn, deg in (("Spine1", UPRIGHT), ("Head", UPRIGHT * 0.8)):
            pb = b(bn)
            m = pb.matrix.copy()
            r = Quaternion(Vector((1, 0, 0)), -math.radians(deg)).to_matrix() @ m.to_3x3()
            m2 = r.to_4x4()
            m2.translation = m.translation
            pb.matrix = m2
            pb.scale = (1.0, 1.0, 1.0)
            bpy.context.view_layer.update()
            pb.keyframe_insert("rotation_quaternion", frame=f)
after = measure()
print("FIRM_WALK", NAME, "cyclic" if CYCLIC else "open", "before (slip cm, toe clearance cm)", before, "after", after)
bpy.ops.wm.save_mainfile(compress=True)
