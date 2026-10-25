"""Build the turns in his guard (background Mixar / Blender).

  mixar.exe --background <rig.blend> --python make_turns.py -- [speed_180] [ease]

From Mixamo's "Turning - Footman" (`turn_90`; the first run keeps it as
`turn_90_src`, which every later run builds from):

  turn_90   exactly 90 degrees (the source turns 99): the whole figure turns
            back by the difference as it goes. It starts and ends on idle's
            first frame (the end turned by 90 degrees). Each foot keeps its
            two stances pinned where idle has it, before and after the turn,
            so nothing slides.
  turn_180  the same turn twice, the second half from the first half's end,
            played `speed_180` (default 1.25) times as fast: four shuffled
            steps (left, right, left, right), the guard held throughout, from
            idle's stance to idle's stance turned about. (Mixamo's "Turning 180
            degress - Footman" turns in mid-stride, from a walking stance with
            a foot in the air, so it cannot start or end in the guard.)

Both are retimed to set off and come round gently (`ease`, default 0.35: the
share of a smoothstep in the timing; the source turns at full speed from its
first frame to its last), over the same length.

The turns keep their yaw on the hips here; export_godot.py moves it to the
root (`root_yaw`). Run after the arm passes and before clear_blade.py.
Prints, per clip, how far each ankle ends from its target (IK reach).
"""
import math
import sys

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SPEED_180 = float(argv[0]) if argv else 1.25
EASE = float(argv[1]) if len(argv) > 1 else 0.35
SOFT = 0.975  # of a leg's reach, where the IK starts to give (idle's guard stands at 97-98 %)
FPS = 30.0
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
    if c <= a:
        return 1.0 if x >= c else 0.0
    t = min(1.0, max(0.0, (x - a) / (c - a)))
    return t * t * (3 - 2 * t)


def set_matrix(pb, m):
    pb.matrix = m
    pb.scale = (1.0, 1.0, 1.0)  # a shear leaves scale on the bone; no clip keys it, so it would hold in every clip
    bpy.context.view_layer.update()


def mblend(a, c, w):
    la, ra, _ = a.decompose()
    lc, rc, _ = c.decompose()
    m = ra.slerp(rc, w).to_matrix().to_4x4()
    m.translation = la.lerp(lc, w)
    return m


def hips_yaw():
    # As export_godot.py: the facing of the hip line about Z.
    r = b("RightUpLeg").head - b("LeftUpLeg").head
    fwd = Vector((0, 0, 1)).cross(r)
    return math.degrees(math.atan2(fwd.x, -fwd.y))


def ik_leg(side, want, foot_rot):
    """Two-bone IK (as make_transitions.py): the ankle onto `want`, the knee
    kept in its current bend plane, the foot set to the world rotation `foot_rot`.
    Soft near full reach: past SOFT of it the leg straightens ever more slowly
    and never locks (the ankle falls a few millimetres short), so a knee
    cannot snap straight from one frame to the next."""
    up, lo, ft = b(side + "UpLeg"), b(side + "Leg"), b(side + "Foot")
    hip = up.head.copy()
    knee = lo.head.copy()
    l1 = (knee - hip).length
    l2 = (ft.head - knee).length
    d = want - hip
    reach = l1 + l2
    dist = d.length
    if dist > SOFT * reach:
        give = (1.0 - SOFT) * reach
        dist = SOFT * reach + give * (1.0 - math.exp(-(dist - SOFT * reach) / give))
    dist = min(max(dist, abs(l1 - l2) + 1e-4), reach - 1e-4)
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


def runs(mask):
    out, i = [], 0
    while i < len(mask):
        if mask[i]:
            j = i
            while j + 1 < len(mask) and mask[j + 1]:
                j += 1
            out.append((i, j))
            i = j + 1
        else:
            i += 1
    return out


def planted(P):
    """As make_transitions.py: within 4.5 cm of its lowest and under 0.4 m/s across the ground."""
    z = np.array([p.z for p in P])
    spd = np.array([0.0] + [(P[k].xy - P[k - 1].xy).length * FPS for k in range(1, len(P))])
    spd[0] = spd[1] if len(spd) > 1 else 0.0
    m = (z < z.min() + 0.045) & (spd < 0.4)
    for i, j in runs(m):
        if j - i < 2:
            m[i:j + 1] = False
    return m


def new_action(name, note):
    for a in [a for a in bpy.data.actions if a.name == name]:
        bpy.data.actions.remove(a)
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    act["source"] = note
    rig.animation_data.action = act
    for pb in PB:
        pb.rotation_mode = "QUATERNION"
    return act


def rz(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Z")


# --- the source -----------------------------------------------------------------
if "turn_90_src" not in bpy.data.actions:
    keep = bpy.data.actions["turn_90"].copy()
    keep.name = "turn_90_src"
    keep.use_fake_user = True
src = bpy.data.actions["turn_90_src"]
rig.animation_data.action = src
f0, f1 = (int(v) for v in src.frame_range)
SRC = []
for f in range(f0, f1 + 1):
    sc.frame_set(f)
    SRC.append({
        "q": {n: PB[n].rotation_quaternion.copy() for n in NAMES},
        "hips": b("Hips").matrix.copy(),
        "yaw": hips_yaw(),
        "ank": {s: b(s + "Foot").head.copy() for s in ("Left", "Right")},
    })
NS = len(SRC)
YAW = np.degrees(np.unwrap(np.radians([p["yaw"] for p in SRC])))
DY = YAW - YAW[0]
TOTAL = float(DY[-1])
SCALE = 90.0 / TOTAL
idle = bpy.data.actions["idle"]
rig.animation_data.action = idle
sc.frame_set(int(idle.frame_range[0]))
IDLE_Q = {n: PB[n].rotation_quaternion.copy() for n in NAMES}
IDLE_HIPS = b("Hips").matrix.copy()
IDLE_ANK = {s: b(s + "Foot").head.copy() for s in ("Left", "Right")}
IDLE_ROT = {s: b(s + "Foot").matrix.to_quaternion() for s in ("Left", "Right")}
print("TURNS source turns %.1f deg over %d frames; scaled by %.3f to 90" % (TOTAL, NS, SCALE))


def half(theta, ease_in, ease_out):
    """One 90-degree turn starting at heading `theta`: per source frame the
    body (local rotations, hips matrix) and each foot's ankle target and
    rotation. `ease_in` / `ease_out`: frames over which the body eases from /
    into idle's own pose (turned), so the turn begins and ends exactly on it."""
    out = []
    feet = {}
    for s in ("Left", "Right"):
        # The source path turned the way this half turns.
        P = [rz(theta + (SCALE - 1.0) * DY[k]) @ SRC[k]["ank"][s] for k in range(NS)]
        down = planted([SRC[k]["ank"][s] for k in range(NS)])
        rs = runs(down)
        a0, a1 = rz(theta) @ IDLE_ANK[s], rz(theta + 90.0) @ IDLE_ANK[s]
        q0 = (rz(theta) @ IDLE_ROT[s].to_matrix().to_4x4()).to_quaternion()
        q1 = (rz(theta + 90.0) @ IDLE_ROT[s].to_matrix().to_4x4()).to_quaternion()
        # One step: from the end of the first stance to the start of the last
        # (the right foot lands on the source's last frame).
        lift = rs[0][1]
        land = rs[-1][0] if len(rs) > 1 else NS - 1
        tgt, rot = [], []
        for k in range(NS):
            if k <= lift:
                t, r = a0.copy(), q0.copy()
                t.z = a0.z + (P[k].z - P[0].z)
            elif k >= land:
                t, r = a1.copy(), q1.copy()
                t.z = a1.z + (P[k].z - P[-1].z)
            else:
                u = smooth(k, lift, land)
                t = P[k] + (a0 - P[lift]) * (1 - u) + (a1 - P[land]) * u
                r = q0.slerp(q1, u)
            tgt.append(t)
            rot.append(r)
        feet[s] = (tgt, rot, lift, land)
    for k in range(NS):
        w_in = 1.0 - smooth(k, 0, ease_in) if ease_in else 0.0
        w_out = smooth(k, NS - 1 - ease_out, NS - 1) if ease_out else 0.0
        q = {}
        for n in NAMES:
            # The legs ease in as the source has them (its first frame is idle's
            # stance): easing them too would swing the knees' bend, which the IK keeps.
            q[n] = SRC[k]["q"][n].slerp(IDLE_Q[n], max(0.0 if n in LEG else w_in, w_out))
        # The hips as the source moves them from its first frame (idle's): they
        # draw back off the front foot as it lifts, and holding them would pull
        # that leg straight. Into the end, toward idle's hips at the heading
        # reached so far, so the turn itself never stalls.
        hips = rz(theta + (SCALE - 1.0) * DY[k]) @ SRC[k]["hips"]
        if w_out > 0:
            hips = mblend(hips, rz(theta + SCALE * DY[k]) @ IDLE_HIPS, w_out)
        out.append({"q": q, "hips": hips,
                    "feet": {s: (feet[s][0][k], feet[s][1][k]) for s in feet}})
    steps = {s: (feet[s][2], feet[s][3]) for s in feet}
    return out, steps


def sample(seq, x):
    """The pose at fractional index x of a sequence of per-frame poses."""
    i = int(math.floor(x))
    j = min(i + 1, len(seq) - 1)
    u = x - i
    a, c = seq[i], seq[j]
    return {
        "q": {n: a["q"][n].slerp(c["q"][n], u) for n in NAMES},
        "hips": mblend(a["hips"], c["hips"], u),
        "feet": {s: (a["feet"][s][0].lerp(c["feet"][s][0], u), a["feet"][s][1].slerp(c["feet"][s][1], u)) for s in a["feet"]},
    }


def build(name, seq, n_out, note):
    act = new_action(name, note)
    worst = 0.0
    for i in range(n_out):
        u = i / float(n_out - 1)
        p = sample(seq, (len(seq) - 1) * ((1.0 - EASE) * u + EASE * u * u * (3 - 2 * u)))
        for n in NAMES:
            PB[n].rotation_quaternion = p["q"][n]
        bpy.context.view_layer.update()
        set_matrix(b("Hips"), p["hips"])
        for s, (t, r) in p["feet"].items():
            ik_leg(s, t, r)
            worst = max(worst, (b(s + "Foot").head - t).length)
        for n in NAMES:
            PB[n].keyframe_insert("rotation_quaternion", frame=i + 1)
        b("Hips").keyframe_insert("location", frame=i + 1)
    act.frame_range = (1, n_out)
    act["frames"] = n_out
    # The end against idle's stance, turned.
    rig.animation_data.action = act
    sc.frame_set(n_out)
    yaw_end = hips_yaw()
    sc.frame_set(1)
    yaw_0 = hips_yaw()
    turn = ((yaw_end - yaw_0 + 180.0) % 360.0) - 180.0
    sc.frame_set(n_out)
    end_gap = max((b(s + "Foot").head - rz(turn) @ IDLE_ANK[s]).length for s in ("Left", "Right"))
    print("TURN %-8s %d frames (%.2f s), turns %.1f deg; ankles off target at most %.1f cm; end off idle's stance %.1f cm" % (
        name, n_out, (n_out - 1) / FPS, turn if abs(turn) < 179.5 else 180.0, 100 * worst, 100 * end_gap))
    return act


h1, st1 = half(0.0, 3, 6)
build("turn_90", h1, NS, "Turning - Footman, turned exactly 90 degrees, pinned to idle's stance at both ends")
# The 180: the first half eases into idle's pose turned (its stance), the second starts from it.
a, _ = half(0.0, 3, 4)
c, _ = half(90.0, 0, 6)
seq = a + c[1:]
n180 = int(round((len(seq) - 1) / SPEED_180)) + 1
build("turn_180", seq, n180, "Turning - Footman twice (%.2fx), from idle's stance to idle's stance turned about" % SPEED_180)
print("TURN steps (source frames, lift-land):", {s: (v[0] + 1, v[1] + 1) for s, v in st1.items()})
rig.animation_data.action = bpy.data.actions["idle"]
bpy.ops.wm.save_mainfile(compress=True)
print("TURNS_SAVED")
