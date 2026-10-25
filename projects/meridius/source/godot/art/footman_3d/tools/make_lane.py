"""Build the step into the lane on his right (background Mixar / Blender).

  mixar.exe --background <rig.blend> --python make_lane.py -- [metres=1.115]

`lane`: from idle's first frame to idle's first frame one file to his right
(default 1.115 m: the squad's file, 0.41 of a 2.72 m tile), in his guard.
His guard is a wide stance on nearly straight legs, so the move is four
short steps of half the distance: the right foot steps out, the left closes
up, twice, as in a shield line; his feet stay on their own lines and never
cross (the left leading would cross them). Each stance is pinned; each swing
lifts the foot a few centimetres and carries it across on an ease. Where the hips go is chosen
frame by frame so that both legs reach their feet with the least bend:
over the planted foot while the other swings, turned with the stride (the
chest turned back, so the shield stays put), then smoothed; they come down
only as far as the wider stances still need. Sword, shield and head keep
idle's guard. The wider stances take the hips down about 6 cm.

In place; `root_path` (rig x, y per frame, from the first frame) carries
the travel and `lane_m` the distance it was built for. The step_lane loop
(the Mixamo strafe) stays in the .blend as it was. Run after make_turns.py
and before clear_blade.py.
"""
import math
import sys

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DIST = float(argv[0]) if argv else 1.115
FPS = 30.0
LIFT = 0.075  # ankle lift at mid-swing
MARGIN = 0.985  # of a leg's full reach, at most (idle's guard stands at 97-98 %)
# (foot, lift frame, landing frame, share of the distance it lands at)
STEPS = [("Right", 3, 13, 0.5), ("Left", 15, 25, 0.5), ("Right", 27, 37, 1.0), ("Left", 39, 49, 1.0)]
N = 58
sc = bpy.context.scene
rig = bpy.data.objects["FootmanRig"]
rig.location = (0, 0, 0)
rig.rotation_euler = (0, 0, 0)
rig.animation_data_create()
PB = rig.pose.bones
NAMES = [pb.name for pb in PB]


def b(n):
    return PB["mixamorig:" + n]


def smooth(x, a, c):
    if c <= a:
        return 1.0 if x >= c else 0.0
    t = min(1.0, max(0.0, (x - a) / (c - a)))
    return t * t * (3 - 2 * t)


def smoother(x, a, c):
    t = min(1.0, max(0.0, (x - a) / float(c - a)))
    return t * t * t * (t * (6 * t - 15) + 10)


def set_matrix(pb, m):
    pb.matrix = m
    pb.scale = (1.0, 1.0, 1.0)  # a shear leaves scale on the bone; no clip keys it, so it would hold in every clip
    bpy.context.view_layer.update()


def ik_leg(side, want, foot_rot):
    """Two-bone IK (as make_transitions.py): the ankle onto `want`, the knee
    kept in its current bend plane, the foot set to the world rotation `foot_rot`."""
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
    m = q1.to_matrix() @ up.matrix.to_3x3()
    m = m.to_4x4()
    m.translation = hip
    set_matrix(up, m)
    knee_now = lo.head.copy()
    q2 = (ft.head - knee_now).rotation_difference(hip + dn * dist - knee_now)
    m = q2.to_matrix() @ lo.matrix.to_3x3()
    m = m.to_4x4()
    m.translation = knee_now
    set_matrix(lo, m)
    m = foot_rot.to_matrix().to_4x4()
    m.translation = ft.head.copy()
    set_matrix(ft, m)


def turn_about(pb, deg, centre):
    if abs(deg) < 1e-5:
        return
    set_matrix(pb, Matrix.Translation(centre) @ Matrix.Rotation(math.radians(deg), 4, "Z") @ Matrix.Translation(-centre) @ pb.matrix)


def gauss(x, sigma):
    k = np.arange(-int(3 * sigma), int(3 * sigma) + 1)
    w = np.exp(-0.5 * (k / sigma) ** 2)
    w /= w.sum()
    pad = np.concatenate([np.full(len(k) // 2, x[0]), x, np.full(len(k) // 2, x[-1])])
    return np.convolve(pad, w, mode="valid")


# --- idle's guard -------------------------------------------------------------
idle = bpy.data.actions["idle"]
rig.animation_data.action = idle
sc.frame_set(int(idle.frame_range[0]))
IDLE_Q = {n: PB[n].rotation_quaternion.copy() for n in NAMES}
IDLE_LOC = b("Hips").location.copy()
IDLE_HIPS = b("Hips").matrix.copy()
ANK = {s: b(s + "Foot").head.copy() for s in ("Left", "Right")}
FROT = {s: b(s + "Foot").matrix.to_quaternion() for s in ("Left", "Right")}
REACH = {s: (b(s + "Leg").head - b(s + "UpLeg").head).length + (b(s + "Foot").head - b(s + "Leg").head).length for s in ANK}
RIGHT = Vector((-1.0, 0.0, 0.0))  # his right: the right foot stands on that side of the left
assert (ANK["Right"] - ANK["Left"]).dot(RIGHT) > 0
# A lifted foot hangs a little toe down: about its own side axis, the way that lowers the toe.
TOE_TILT = {}
for s in ANK:
    toe = b(s + "ToeBase").head - b(s + "Foot").head
    side = Vector((toe.x, toe.y, 0.0)).normalized().cross(Vector((0, 0, 1)))
    lower = min((1.0, -1.0), key=lambda g: (Quaternion(side, math.radians(10 * g)) @ toe).z)
    TOE_TILT[s] = (side, lower)

# --- the plan -------------------------------------------------------------------
share = {s: [0.0] * N for s in ANK}  # how far across each foot is, per frame
lift = {s: [0.0] * N for s in ANK}
swinging = [None] * N
for s, a, c, to in STEPS:
    frm = max([st[3] for st in STEPS if st[0] == s and st[2] <= a] or [0.0])
    for i in range(N):
        if i >= a:
            share[s][i] = frm + (to - frm) * smoother(i, a, c)
        if a < i < c:
            u = (i - a) / float(c - a)
            lift[s][i] = LIFT * math.sin(math.pi * u ** 0.85)
            swinging[i] = s
# The feet, where they stand (or swing) each frame, in the world.
FEET = [{sd: ANK[sd] + RIGHT * (DIST * share[sd][i]) + Vector((0, 0, lift[sd][i])) for sd in ANK} for i in range(N)]
MEAN = [0.5 * DIST * (share["Left"][i] + share["Right"][i]) for i in range(N)]
HIPS0 = IDLE_HIPS.translation.copy()
HJ = {sd: b(sd + "UpLeg").head - HIPS0 for sd in ANK}  # hip joints about the hips


def need_drop(i, off, deg):
    """How far the hips must come down at frame i with the hips moved by `off`
    (world xy) and turned `deg`, for both legs to reach their ankles."""
    worst = 0.0
    rot = Matrix.Rotation(math.radians(deg), 3, "Z")
    for sd, t in FEET[i].items():
        hj = HIPS0 + off + rot @ HJ[sd]
        dh = (hj.xy - t.xy).length
        r = MARGIN * REACH[sd]
        if dh >= r:
            return 9.0
        worst = max(worst, hj.z - t.z - math.sqrt(r * r - dh * dh))
    return max(worst, 0.0)


# Per frame, the hips' best place and turn near the feet's mean, then smoothed.
GX = np.linspace(-0.22, 0.22, 23)
GY = np.linspace(-0.10, 0.10, 11)
GT = np.linspace(-24.0, 24.0, 13)
best = []
for i in range(N):
    centre = RIGHT * MEAN[i]
    top = None
    for dx in GX:
        for dy in GY:
            off = centre + Vector((dx, dy, 0.0))
            for deg in GT:
                c = need_drop(i, off, deg) + 0.08 * math.hypot(dx, dy) + 0.0006 * abs(deg)
                if top is None or c < top[0]:
                    top = (c, off.x, off.y, deg)
    best.append(top[1:])
best = np.array(best)
best[0] = (0.0, 0.0, 0.0)
best[-1] = (RIGHT.x * DIST, RIGHT.y * DIST, 0.0)
for col in range(3):
    best[:, col] = gauss(best[:, col], 3.0)
best[0] = (0.0, 0.0, 0.0)
best[-1] = (RIGHT.x * DIST, RIGHT.y * DIST, 0.0)
ROOT = [Vector((float(x), float(y), 0.0)) for x, y, _ in best]
twist = [float(t) for _, _, t in best]

# --- build ----------------------------------------------------------------------
for act in [x for x in bpy.data.actions if x.name == "lane"]:
    bpy.data.actions.remove(act)
lane = bpy.data.actions.new("lane")
lane.use_fake_user = True
lane["source"] = "procedural: four steps into the lane on his right, in idle's guard"
rig.animation_data.action = lane
for pb in PB:
    pb.rotation_mode = "QUATERNION"


def targets(i):
    out = {}
    for s in ANK:
        t = FEET[i][s] - ROOT[i]
        side, g = TOE_TILT[s]
        r = Quaternion(side, math.radians(10 * g * lift[s][i] / LIFT)) @ FROT[s]
        out[s] = (t, r)
    return out


def pose(i, drop):
    for n in NAMES:
        PB[n].rotation_quaternion = IDLE_Q[n]
    b("Hips").location = IDLE_LOC
    bpy.context.view_layer.update()
    m = IDLE_HIPS.copy()
    m.translation -= Vector((0, 0, drop))
    set_matrix(b("Hips"), m)
    turn_about(b("Hips"), twist[i], b("Hips").head.copy())
    turn_about(b("Spine"), -twist[i], b("Spine").head.copy())


# How far the hips must still come down on the smoothed path, eased.
need = np.array([need_drop(i, ROOT[i], twist[i]) for i in range(N)])
wide = np.array([max(need[max(0, i - 3):i + 4]) for i in range(N)])
drop = gauss(wide, 2.5)
drop[0] = drop[-1] = 0.0
worst = 0.0
for i in range(N):
    pose(i, float(drop[i]))
    for s, (t, r) in targets(i).items():
        ik_leg(s, t, r)
        worst = max(worst, (b(s + "Foot").head - t).length)
    for n in NAMES:
        PB[n].keyframe_insert("rotation_quaternion", frame=i + 1)
    b("Hips").keyframe_insert("location", frame=i + 1)
lane.frame_range = (1, N)
lane["frames"] = N
lane["lane_m"] = DIST
lane["root_path"] = sum([[round(float(r.x), 4), round(float(r.y), 4)] for r in ROOT], [])
sc.frame_set(N)
end_gap = max((b(s + "Foot").head - ANK[s]).length for s in ANK)
print("LANE hips per frame (x cm, y cm, turn deg, down cm):", " ".join("%d:%.0f,%.0f,%.0f,%.1f" % (i + 1, 100 * r.x, 100 * r.y, t, 100 * d) for i, (r, t, d) in enumerate(zip(ROOT, twist, drop)) if i % 3 == 0))
print("LANE %d frames (%.2f s), %.3f m to his right; hips down at most %.1f cm; ankles off target at most %.1f cm; end off idle's stance %.1f cm" % (
    N, (N - 1) / FPS, DIST, 100 * float(drop.max()), 100 * worst, 100 * end_gap))
rig.animation_data.action = idle
bpy.ops.wm.save_mainfile(compress=True)
print("LANE_SAVED")
