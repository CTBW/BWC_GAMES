"""Give a walk a calm sword arm (background Mixar / Blender).

  mixar.exe --background <rig.blend> --python sword_swing.py -- <action> [amp_deg] [forearm_deg] [lag_s] [base]

The sword arm (RightShoulder, RightArm, RightForeArm, RightHand) is replaced by
one steady carry, rocked as a pendulum from the shoulder about the shoulder
line. The carry (`base`) is his idle guard, idle's first frame (default
"idle": the walk starts and stops with the sword where idle holds it), or
"mean", the clip's own mean pose. The swing goes forward with the left foot, back with the
right, `amp_deg` each way (default 9), the forearm following `forearm_deg`
(default 4) a little later. The wrist keeps one angle, so the blade rocks with
the arm instead of rolling round. Where the blade would touch the body, one
constant turn of the wrist (the smallest that clears every frame) is added.
Runs after firm_walk.py and fix_sword.py on a walk (it replaces fix_sword's
per-frame wrist turns on this arm). Prints contact frames before and after.
"""
import math
import sys

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
NAME = argv[0]
AMP = math.radians(float(argv[1]) if len(argv) > 1 else 9.0)
FORE = math.radians(float(argv[2]) if len(argv) > 2 else 4.0)
LAG = float(argv[3]) if len(argv) > 3 else 0.05
BASE = argv[4] if len(argv) > 4 else "idle"
MARGIN = 0.025
FPS = 30.0
sc = bpy.context.scene
rig = bpy.data.objects["FootmanRig"]
body = bpy.data.objects["Footman"]
sword = bpy.data.objects["Sword"]
rig.location = (0, 0, 0)
rig.rotation_euler = (0, 0, 0)
PB = rig.pose.bones
CHAIN = ["mixamorig:RightShoulder", "mixamorig:RightArm", "mixamorig:RightForeArm", "mixamorig:RightHand"]
act = bpy.data.actions[NAME]
rig.animation_data.action = act
f0, f1 = (int(v) for v in act.frame_range)
frames = list(range(f0, f1 + 1))
T = (f1 - f0) / FPS  # one cycle; the last frame repeats the first

# The sword hand's own fist and forearm are not "the body" (as fix_sword.py).
_own = {g.index for g in body.vertex_groups if g.name in ("mixamorig:RightHand", "mixamorig:RightForeArm")}
_vown = np.zeros(len(body.data.vertices), bool)
for v in body.data.vertices:
    best = max(v.groups, key=lambda g: g.weight, default=None)
    _vown[v.index] = best is not None and best.group in _own
SKIP = {p.index for p in body.data.polygons if sum(_vown[i] for i in p.vertices) * 2 >= len(p.vertices)}
sv = np.array([v.co[:] for v in sword.data.vertices])
ZS = np.linspace(0.10, float(sv[:, 2].max()) - 0.02, 14)


def contacts():
    """Frames where the blade is inside the body or within MARGIN of it."""
    n = 0
    for f in frames:
        sc.frame_set(f)
        dg = bpy.context.evaluated_depsgraph_get()
        bvh = BVHTree.FromObject(body, dg)
        inv = body.matrix_world.inverted()
        m = sword.matrix_world
        for z in ZS:
            q = inv @ (m @ Vector((0, 0, z)))
            near = [h for h in bvh.find_nearest_range(q, 0.2) if h[2] not in SKIP]
            if not near:
                continue
            loc, nrm, idx, dist = min(near, key=lambda h: h[3])
            inside = (q - loc).dot(nrm) < 0
            if inside or dist < MARGIN:
                n += 1
                break
    return n


# Left footfall: the sword arm is furthest forward a moment after it.
left_down = None
z = []
for f in frames:
    sc.frame_set(f)
    z.append(PB["mixamorig:LeftFoot"].head.z)
z = np.array(z)
g = z < z.min() + 0.03
for k in range(1, len(g)):
    if g[k] and not g[k - 1]:
        left_down = (frames[k] - f0) / FPS
        break
T_FWD = (left_down or 0.0) + LAG

# The carry: idle's guard, or each bone's mean local rotation over the cycle.
samples = {n: [] for n in CHAIN}
for f in frames[:-1]:
    sc.frame_set(f)
    for n in CHAIN:
        samples[n].append(PB[n].rotation_quaternion.copy())
MEAN = {}
for n, qs in samples.items():
    acc = Vector((0, 0, 0, 0))
    for q in qs:
        v = Vector(q)
        acc += v if v.dot(Vector(qs[0])) >= 0 else -v
    MEAN[n] = Quaternion(acc.normalized())
if BASE == "idle":
    rig.animation_data.action = bpy.data.actions["idle"]
    sc.frame_set(int(bpy.data.actions["idle"].frame_range[0]))
    MEAN = {n: PB[n].rotation_quaternion.copy() for n in CHAIN}
    rig.animation_data.action = act

before = contacts()


def turn_about(pb, axis, ang):
    if abs(ang) < 1e-7:
        return
    h = pb.matrix.translation.copy()
    pb.matrix = Matrix.Translation(h) @ Matrix.Rotation(ang, 4, axis) @ Matrix.Translation(-h) @ pb.matrix
    pb.scale = (1.0, 1.0, 1.0)  # a shear leaves scale on the bone; no clip keys it, so it would hold in every clip
    bpy.context.view_layer.update()


def apply(wrist_axis_key=None, wrist_ang=0.0):
    for f in frames:
        sc.frame_set(f)
        for n in CHAIN:
            PB[n].rotation_quaternion = MEAN[n]
        bpy.context.view_layer.update()
        t = (f - f0) / FPS
        # The shoulder line (to his right) and the chest's forward and up.
        r = (PB["mixamorig:RightArm"].head - PB["mixamorig:LeftArm"].head).normalized()
        fwd = Vector((0, 0, 1)).cross(r).normalized()
        up = r.cross(fwd).normalized()
        # A positive turn about his right-pointing shoulder line swings the hand forward.
        turn_about(PB["mixamorig:RightArm"], r, AMP * math.cos(2 * math.pi * (t - T_FWD) / T))
        turn_about(PB["mixamorig:RightForeArm"], r, FORE * math.cos(2 * math.pi * (t - T_FWD - 0.06) / T))
        if wrist_axis_key:
            turn_about(PB["mixamorig:RightHand"], {"r": r, "f": fwd, "u": up}[wrist_axis_key], wrist_ang)
        for n in CHAIN:
            PB[n].keyframe_insert("rotation_quaternion", frame=f)


apply()
after = contacts()
chosen = "none"
if after:
    best = None
    for deg in (4, 8, 12, 16, 20):
        for key in ("r", "f", "u"):
            for sgn in (1, -1):
                apply(key, math.radians(sgn * deg))
                n = contacts()
                if n == 0:
                    best = (key, sgn * deg)
                    break
            if best:
                break
        if best:
            break
    if best:
        apply(best[0], math.radians(best[1]))
        chosen = "%s %+d deg" % best
    else:
        apply()
    after = contacts()
act["sword_swing"] = "base %s, amp %.1f, forearm %.1f, lag %.2f s, wrist %s" % (BASE, math.degrees(AMP), math.degrees(FORE), LAG, chosen)
print("SWORD_SWING", NAME, "base", BASE, "forward at %.2f s of %.2f" % (T_FWD, T), "contact frames before", before, "after", after, "of", len(frames), "wrist offset", chosen)
bpy.ops.wm.save_mainfile(compress=True)
