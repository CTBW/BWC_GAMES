"""Build a charge strike: the run braking into an attack (background Mixar / Blender).

  mixar.exe --background <rig.blend> --python make_charge.py -- [attack] [out] [lead] [land_a] [carry_m]

Defaults: the attack `attack`, written as `charge_hit`, leading with the Left
foot. The strike takes over the run as the other (back) foot lands, and the
lead foot's next landing in the run becomes the attack's front foot, planted
where the attack plants it (found in the clips: the frame from which the lead
foot stands where it strikes from). It ends in the attack's last pose (idle's
stance), so idle follows with no blend:

  * the ground speed falls evenly from the run's to nothing at the blow, so by
    the time the front foot plants he moves about as the attack's lunge does;
    from there on it is the attack itself, played where that foot stands;
  * the front foot's last swing reaches on to that spot (a longer braking
    step), the back foot stays planted until it peels off, then drops in behind
    as the attack's back foot (a low step, no kick-up);
  * spine, head and arms ease from the run into the attack's wind-up, so the
    sword is up as the foot lands and the cut meets the target at the attack's
    own time after that landing; hips height and turn ease the same way.

For an attack that stands (Mixamo's stab), `land_a` names the attack frame
the front foot plants on (the moment before the blow drives out), and
`carry_m` lets the speed left at the landing carry his hips on over the
planted feet, up to that far, through the blow, then back as he recovers.

In place: `root_path` (rig-space x, y per frame, from the first frame) carries
the travel; it leaves at the run's speed and stops where the attack stands.
Also stored: "enter_run_t" (the run time it takes over at) and "contact_t".
Run after the run's and the attack's passes (firm_walk, clear_blade) and
before export; clear_blade.py may follow. Prints each planted foot's slide.
"""
import math
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ATTACK = argv[0] if len(argv) > 0 and argv[0] else "attack"
OUT = argv[1] if len(argv) > 1 and argv[1] else "charge_hit"
F = argv[2] if len(argv) > 2 and argv[2] else "Left"  # the lead (front) foot
LAND_OVERRIDE = int(argv[3]) if len(argv) > 3 and argv[3] else 0
CARRY = float(argv[4]) if len(argv) > 4 and argv[4] else 0.0
B = "Right" if F == "Left" else "Left"
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
    """Two-bone IK (as make_transitions.py): the ankle onto `want`, the knee
    kept in its current bend plane, the foot set to the rotation `foot_rot`."""
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


def flat(v):
    return Vector((v.x, v.y, 0.0))


def foot(pose, side, part="Foot"):
    return pose["m"]["mixamorig:" + side + part].translation


# --- sources ------------------------------------------------------------------
run = bpy.data.actions["run"]
rf0, rf1 = (int(v) for v in run.frame_range)
NR = rf1 - rf0  # the cycle (its last frame repeats its first)
RUN = {f: grab(run, f) for f in range(rf0, rf1)}
att = bpy.data.actions[ATTACK]
af0, af1 = (int(v) for v in att.frame_range)
A = {a: grab(att, a) for a in range(af0, af1 + 1)}
V = Vector(tuple(run["root_vel"]) + (0.0,))
DIR = V.normalized()


def run_frame(f):
    return rf0 + (f - rf0) % NR


def landing(side):
    """The run frame a foot lands on: its ankle within 2 cm of its lowest."""
    z = {f: foot(RUN[f], side).z for f in RUN}
    lo = min(z.values()) + 0.02
    return next(f for f in RUN if z[f] < lo and z[run_frame(f - 1)] >= lo)


# Contact: the attack's sword tip reaches farthest forward (as export_godot.py).
sword = bpy.data.objects["Sword"]
rig.animation_data.action = bpy.data.actions["idle"]
sc.frame_set(1)
hand0 = b("RightHand").head.copy()
tip_local = max((v.co for v in sword.data.vertices), key=lambda co: ((sword.matrix_world @ co) - hand0).length).copy()
reach = {}
rig.animation_data.action = att
for a in A:
    sc.frame_set(a)
    reach[a] = -(sword.matrix_world @ tip_local).y
# The first frame within 1.5 cm of the farthest (a thrust holds its reach).
CONTACT_A = next(a for a in sorted(reach) if reach[a] >= max(reach.values()) - 0.015)
# The attack's front foot is planted from LAND_A: from there to the blow it stands
# within 5 cm of where it strikes from, its ankle within 3.5 cm of its height then.
at_blow = foot(A[CONTACT_A], F)
LAND_A = CONTACT_A
while LAND_A > af0 and (flat(foot(A[LAND_A - 1], F)) - flat(at_blow)).length < 0.05 and foot(A[LAND_A - 1], F).z < at_blow.z + 0.035:
    LAND_A -= 1
if LAND_OVERRIDE:
    LAND_A = LAND_OVERRIDE
RUN_IN = landing(B)
N_RUN = (landing(F) - RUN_IN) % NR  # run frames until the front foot lands
SHIFT = (LAND_A - af0) - N_RUN  # attack frames skipped (or held) before the landing
LAND = N_RUN
CONTACT = LAND + (CONTACT_A - LAND_A)
N = LAND + (af1 - LAND_A) + 1


def att_frame(i):
    return min(af1, max(af0, af0 + i + SHIFT)) if i < LAND else LAND_A + (i - LAND)


R = {i: RUN[run_frame(RUN_IN + i)] for i in range(LAND + 1)}

# --- the plan (world = the clip's ground, from the root's first spot) ------------
# The ground speed falls evenly to nothing at the blow; up to the landing that
# is the hips' travel, from there the attack carries them.
speed = [V.length * max(0.0, 1.0 - i / float(CONTACT)) for i in range(LAND + 1)]
rr = [Vector()]
for i in range(1, LAND + 1):
    rr.append(rr[-1] + DIR * speed[i - 1] / FPS)
HM = [rr[i] + flat(R[i]["m"]["mixamorig:Hips"].translation) for i in range(LAND + 1)]
O = HM[LAND] - flat(A[LAND_A]["m"]["mixamorig:Hips"].translation)  # where the attack stands
W_F = O + foot(A[LAND_A], F)
W_BB = O + foot(A[LAND_A], B)
PF = [rr[i] + foot(R[i], F) for i in range(LAND + 1)]
PB_ = [rr[i] + foot(R[i], B) for i in range(LAND + 1)]
W_B = PB_[0].copy()
# The speed left at the landing beyond the attack's own lunge carries the hips
# on (rising to CARRY over K frames, slowing evenly), held through the blow,
# then easing back to the attack's own place as he recovers.
v_att = (A[min(af1, LAND_A + 1)]["m"]["mixamorig:Hips"].translation - A[LAND_A]["m"]["mixamorig:Hips"].translation).dot(DIR)
e = max(0.0, speed[LAND] / FPS - v_att) if CARRY > 0 else 0.0
K = max(3, int(round(2 * CARRY / e))) if e > 0 else 0
D = e * K / 2.0


def carry(i):
    if K == 0 or i < LAND:
        return 0.0
    t = i - LAND
    up = e * t - e * t * t / (2.0 * K) if t <= K else D
    return up * (1.0 - smooth(i, CONTACT + 6, N - 6))


# The back foot peels off where its toe leaves the ground in the run.
toe0 = foot(R[0], B, "ToeBase").z
LIFT = next((i for i in range(1, LAND) if foot(R[i], B, "ToeBase").z > toe0 + 0.04), LAND - 4)
print("CHARGE_PLAN %s from %s, %s foot leading: takes over at run f%d (%.2f m/s, %s foot down), %s foot lands at clip f%d = attack f%d (%d attack frames %s), blow at attack f%d; %s foot peels off at clip f%d" % (
    OUT, ATTACK, F, RUN_IN, V.length, B, F, LAND + 1, LAND_A, abs(SHIFT), "skipped" if SHIFT >= 0 else "held", CONTACT_A, B, LIFT + 1))
if K:
    print("CHARGE_PLAN %.2f m/s left at the landing beyond the attack's own (%.2f); the hips carry on %.2f m over %d frames" % (e * FPS, v_att * FPS, D, K))
print("CHARGE_PLAN front foot lands %.2f m on from the run's own landing; back foot steps %.2f m to the back stance" % (
    (flat(W_F) - flat(PF[LAND])).length, (flat(W_BB) - flat(W_B)).length))

# --- build ----------------------------------------------------------------------
for a_ in [a_ for a_ in bpy.data.actions if a_.name == OUT]:
    bpy.data.actions.remove(a_)
act = bpy.data.actions.new(OUT)
act.use_fake_user = True
act["source"] = "run (from f%d) braking into %s (from f%d), %s foot leading" % (RUN_IN, ATTACK, LAND_A, F)
rig.animation_data.action = act
for pb in PB:
    pb.rotation_mode = "QUATERNION"
root = []
for i in range(N):
    a = att_frame(i)
    if i >= LAND:
        put(A[a]["q"], A[a]["loc"])
        root.append(O.copy())
        c = carry(i)
        if c > 1e-5:
            # The hips carried on, the feet held where the attack has them.
            hm = b("Hips").matrix.copy()
            hm.translation = hm.translation + DIR * c
            set_matrix(b("Hips"), hm)
            for side in ("Left", "Right"):
                n = "mixamorig:%sFoot" % side
                ik_leg(side, A[a]["m"][n].translation, A[a]["m"][n].to_quaternion())
            for side in ("Left", "Right"):
                n = "mixamorig:%sToeBase" % side
                PB[n].rotation_quaternion = A[a]["q"][n]
            bpy.context.view_layer.update()
    else:
        s = R[i]
        w_up = smooth(i, 1, LAND)
        w_root = smooth(i, 2, LAND)
        q = {n: (s["q"][n].copy() if n in LEG else s["q"][n].slerp(A[a]["q"][n], w_up)) for n in NAMES}
        put(q, s["loc"])
        off = flat(s["m"]["mixamorig:Hips"].translation).lerp(flat(A[a]["m"]["mixamorig:Hips"].translation), w_root)
        rt = HM[i] - off
        root.append(rt)
        # Hips: the momentum path (from the root), height and turn eased to the attack's.
        hm = b("Hips").matrix.copy()
        hz = s["m"]["mixamorig:Hips"].translation.z * (1 - w_up) + A[a]["m"]["mixamorig:Hips"].translation.z * w_up
        hm.translation = Vector((HM[i].x - rt.x, HM[i].y - rt.y, hz))
        set_matrix(b("Hips"), hm)
        # Front foot: the run's swing, carried on to the attack's front spot.
        tf = PF[i] + (W_F - PF[LAND]) * smooth(i, 0, LAND)
        rf = s["m"]["mixamorig:%sFoot" % F].to_quaternion().slerp(A[LAND_A]["m"]["mixamorig:%sFoot" % F].to_quaternion(), smooth(i, LAND - 5, LAND))
        # Back foot: planted (keeping the run's heel rise), then a low step back into the attack's stance.
        if i <= LIFT:
            tb = Vector((W_B.x, W_B.y, PB_[i].z))
            rb = s["m"]["mixamorig:%sFoot" % B].to_quaternion()
        else:
            u = smooth(i, LIFT, LAND)
            lin = (i - LIFT) / float(LAND - LIFT)
            tb = Vector((W_B.x, W_B.y, PB_[LIFT].z)).lerp(W_BB, u) + Vector((0, 0, 0.05 * math.sin(math.pi * lin)))
            rb = R[LIFT]["m"]["mixamorig:%sFoot" % B].to_quaternion().slerp(A[LAND_A]["m"]["mixamorig:%sFoot" % B].to_quaternion(), u)
        ik_leg(F, tf - rt, rf)
        ik_leg(B, tb - rt, rb)
        # The toes as the run has them, easing to the attack's.
        for side in ("Left", "Right"):
            n = "mixamorig:%sToeBase" % side
            PB[n].rotation_quaternion = s["q"][n].slerp(A[a]["q"][n], w_up)
        bpy.context.view_layer.update()
    for n in NAMES:
        PB[n].keyframe_insert("rotation_quaternion", frame=i + 1)
    b("Hips").keyframe_insert("location", frame=i + 1)
act.frame_range = (1, N)
act["frames"] = N
path = [[round(float(p.x - root[0].x), 4), round(float(p.y - root[0].y), 4)] for p in root]
act["root_path"] = sum(path, [])
act["enter_run_t"] = (RUN_IN - rf0) / FPS
act["contact_t"] = CONTACT / FPS

# --- check: planted feet in the world (pose + root path) ----------------------------
worst = {}
for side in ("Left", "Right"):
    P = []
    for i in range(N):
        sc.frame_set(i + 1)
        P.append(b(side + "Foot").head + Vector((path[i][0], path[i][1], 0)))
    zlo = min(p.z for p in P)
    w, at = 0.0, None
    for i in range(N):
        down = P[i].z < zlo + 0.045
        if down and at is None:
            at = P[i]
        elif not down:
            at = None
        if at is not None:
            w = max(w, (P[i].xy - at.xy).length)
    worst[side] = round(100 * w, 1)
jump = 0.0
prev = None
for i in range(N):
    sc.frame_set(i + 1)
    cur = {n: PB[n].matrix.translation + Vector((path[i][0], path[i][1], 0)) for n in ("mixamorig:Hips", "mixamorig:LeftHand", "mixamorig:RightHand", "mixamorig:Head", "mixamorig:LeftFoot", "mixamorig:RightFoot")}
    if prev:
        jump = max(jump, max((cur[n] - prev[n]).length for n in cur))
    prev = cur
print("CHARGE_HIT %s: %d frames, %.2f s; travels %.2f m (stops at clip f%d); takes over at run %.3f s; contact %.3f s; planted-foot slide cm %s; largest move of a hand, foot or the head in one frame %.1f cm" % (
    OUT, N, (N - 1) / FPS, Vector(path[-1]).length, LAND + 1, act["enter_run_t"], act["contact_t"], worst, 100 * jump))
rig.animation_data.action = bpy.data.actions["idle"]
bpy.ops.wm.save_mainfile(compress=True)
print("CHARGE_SAVED")
