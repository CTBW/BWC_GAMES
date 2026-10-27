"""Build the walk's stop and start steps (background Mixar / Blender).

  mixar.exe --background <rig.blend> --python make_transitions.py

From `stop_src` (Mixamo "Stop Walking - Footmen", retargeted with its travel):

  stop   takes over from the walk at the stride it matches best and slows over
         the source's own steps. Its last step lands the left foot where idle
         has it, and a small settling step brings the right foot to idle's, so
         he ends in his guard stance. Hips, body and both arms ease into idle's
         first frame, which then follows with no blend. The sword and shield
         arms carry on from the walk (the sword's rocking dies away) instead of
         the source's own swing. The source walks square to the front, the walk
         turned into his guard: its hips and body are turned onto the walk's
         where it takes over (its own motion kept on top), so the stop's first
         frame is the walk's, and hold that turn until they ease into idle.
  start  the stop's settle played backwards (the weight shift out of the
         guard), then the walk from the stride that matches. Each planted foot
         is held where it lands while the root gathers speed from rest, so his
         first steps are short and grow into the march.

Both are in place. `root_path` (rig-space x, y per frame, from the first frame)
carries the travel the game moves the figure by. Also stored: stop
"enter_walk_t" (the walk time it takes over at) and start "exit_walk_t" (the
walk time it hands back at). Run after the walk's passes (firm_walk, fix_sword,
sword_swing) and before export. Prints each planted foot's slide.
"""
import math

import bpy
import numpy as np
from mathutils import Matrix, Vector

FPS = 30.0
RAMP = 20  # frames for the start to reach the walk's speed
LEG_IN = 6  # frames for the stop's legs to ease in from the walk's
sc = bpy.context.scene
rig = bpy.data.objects["FootmanRig"]
rig.location = (0, 0, 0)
rig.rotation_euler = (0, 0, 0)
rig.animation_data_create()
PB = rig.pose.bones
NAMES = [pb.name for pb in PB]
ORDER = []


def _visit(bone):
    ORDER.append(bone.name)
    for c in bone.children:
        _visit(c)


for _b in rig.data.bones:
    if _b.parent is None:
        _visit(_b)
LEG = {"mixamorig:%s%s" % (s, n) for s in ("Left", "Right") for n in ("UpLeg", "Leg", "Foot", "ToeBase", "Toe_End")}
ARM = {"mixamorig:%s%s" % (s, n) for s in ("Left", "Right") for n in ("Shoulder", "Arm", "ForeArm", "Hand")}
BODY = [n for n in NAMES if n not in LEG and n not in ARM and n != "mixamorig:Hips"]


def b(n):
    return PB["mixamorig:" + n]


def smooth(x, a, c):
    if c <= a:
        return 1.0 if x >= c else 0.0
    t = min(1.0, max(0.0, (x - a) / (c - a)))
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


def mblend(a, c, w):
    la, ra, _ = a.decompose()
    lc, rc, _ = c.decompose()
    m = ra.slerp(rc, w).to_matrix().to_4x4()
    m.translation = la.lerp(lc, w)
    return m


def set_matrix(pb, m):
    pb.matrix = m
    pb.scale = (1.0, 1.0, 1.0)  # a shear leaves scale on the bone; no clip keys it, so it would hold in every clip
    bpy.context.view_layer.update()


def ik_leg(side, want, foot_rot):
    """Two-bone IK (as firm_walk.py): the ankle onto `want`, the knee bent the
    way the pose bends it, the foot set to the world rotation `foot_rot`. The
    bend is the knee's offset from the pose's own hip-ankle line (not from the
    line to `want`: a knee lying near that line could swap sides from one frame
    to the next), leaning slightly toward the hips' front so it is never zero."""
    up, lo, ft = b(side + "UpLeg"), b(side + "Leg"), b(side + "Foot")
    hip = up.head.copy()
    knee = lo.head.copy()
    l1 = (knee - hip).length
    l2 = (ft.head - knee).length
    d = want - hip
    dist = min(max(d.length, abs(l1 - l2) + 1e-4), l1 + l2 - 1e-4)
    dn = d.normalized()
    own = (ft.head - hip).normalized()
    pole = (knee - hip) - own * (knee - hip).dot(own)
    pole += (b("Hips").matrix.to_3x3() @ Vector((0, 0, 1))).normalized() * 0.02
    pole -= dn * pole.dot(dn)
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


def key_all(f):
    for n in NAMES:
        PB[n].keyframe_insert("rotation_quaternion", frame=f)
    b("Hips").keyframe_insert("location", frame=f)


def new_action(name, src_name):
    for a in [a for a in bpy.data.actions if a.name == name]:
        bpy.data.actions.remove(a)
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    act["source"] = src_name
    rig.animation_data.action = act
    for pb in PB:
        pb.rotation_mode = "QUATERNION"
    return act


def legs_rel(pose):
    h = pose["m"]["mixamorig:Hips"].translation
    base = Vector((h.x, h.y, 0))
    return {n: pose["m"]["mixamorig:" + n].translation - base for n in ("LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase", "Hips")}


def gap(ra, rb):
    return max((ra[n] - rb[n]).length for n in ra)


def runs(mask):
    """(start, end) index pairs of the True runs."""
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
    """Frames a foot is on the ground: ankle within 4.5 cm of its lowest and
    moving under 0.4 m/s across the ground. Runs shorter than 3 frames drop."""
    z = np.array([p.z for p in P])
    spd = np.array([0.0] + [(P[k].xy - P[k - 1].xy).length * FPS for k in range(1, len(P))])
    spd[0] = spd[1] if len(spd) > 1 else 0.0
    m = (z < z.min() + 0.045) & (spd < 0.4)
    for i, j in runs(m):
        if j - i < 2:
            m[i:j + 1] = False
    return m


def plant(P, mask, spots, toe=None):
    """Ankle targets: each stance holds its spot (`spots[i]`, default where it
    landed; the ankle keeps its own rise and fall), and each swing runs from
    the spot it leaves to the spot it lands on along the source's path. With
    `toe` (the toe's planted mask) a swing only starts to move over once the
    toe leaves the ground; until then the heel rises as in the source."""
    rs = runs(mask)
    D = [spots.get(i, spots.get(i - len(rs), P[a])) for i, (a, _) in enumerate(rs)]
    off = [D[i] - P[a] for i, (a, _) in enumerate(rs)]
    # The offset a stance leaves with: its spot across the ground, and the height
    # offset it held (the heel has risen since it landed; it must not drop back).
    lv = [Vector((D[i].x - P[e].x, D[i].y - P[e].y, off[i].z)) for i, (_, e) in enumerate(rs)]
    tgt = []
    for k in range(len(P)):
        t = None
        for i, (a, e) in enumerate(rs):
            if a <= k <= e:
                t = Vector((D[i].x, D[i].y, P[k].z + off[i].z))
                break
        if t is None:
            prev = max((i for i, (a, e) in enumerate(rs) if e < k), default=None)
            nxt = min((i for i, (a, e) in enumerate(rs) if a > k), default=None)
            if prev is None and nxt is None:
                t = P[k].copy()
            elif prev is None:
                t = P[k] + off[nxt] * smooth(k, 0, rs[nxt][0])
            elif nxt is None:
                t = P[k] + lv[prev]
            else:
                lift = rs[prev][1]
                if toe is not None:
                    while lift < rs[nxt][0] - 2 and toe[lift]:
                        lift += 1
                u = smooth(k, lift, rs[nxt][0])
                t = P[k] + lv[prev] * (1 - u) + off[nxt] * u
        tgt.append(t)
    return tgt, rs


def slide(act, path):
    """Largest slide of a planted foot (cm, world = pose + root path)."""
    rig.animation_data.action = act
    f0, f1 = (int(v) for v in act.frame_range)
    worst = {}
    for s in ("Left", "Right"):
        P = []
        for i, f in enumerate(range(f0, f1 + 1)):
            sc.frame_set(f)
            p = b(s + "Foot").head.copy()
            P.append(p + Vector((path[i][0], path[i][1], 0)))
        g = planted(P)
        w = 0.0
        for i, j in runs(g):
            w = max(w, max((P[k].xy - P[i].xy).length for k in range(i, j + 1)))
        worst[s] = round(100 * w, 1)
    return worst


# --- references ---------------------------------------------------------------
walk = bpy.data.actions["walk"]
wf0, wf1 = (int(v) for v in walk.frame_range)
W = [grab(walk, f) for f in range(wf0, wf1)]  # one cycle (the last frame repeats the first)
NW = len(W)
WREL = [legs_rel(p) for p in W]
V = Vector(tuple(walk["root_vel"]) + (0.0,))
IDLE = grab(bpy.data.actions["idle"], int(bpy.data.actions["idle"].frame_range[0]))
src = bpy.data.actions["stop_src"]
sf0, sf1 = (int(v) for v in src.frame_range)
SRC = [grab(src, f) for f in range(sf0, sf1 + 1)]

# --- the stop -----------------------------------------------------------------
# Where the walk hands over: the early source frame nearest a walk stride.
best = None
for k in range(0, 12):
    r = legs_rel(SRC[k])
    j = min(range(NW), key=lambda j: gap(WREL[j], r))
    g = gap(WREL[j], r)
    if best is None or g < best[0]:
        best = (g, k, j)
G_IN, K0, WK = best
AL = [p["m"]["mixamorig:LeftFoot"].translation.copy() for p in SRC]
AR = [p["m"]["mixamorig:RightFoot"].translation.copy() for p in SRC]
gl, gr = planted(AL), planted(AR)
rl, rr = runs(gl), runs(gr)
LL, LS = rl[-1][0], rl[-2][1]  # the last left landing, and the toe-off before it
RL = rr[-1][0]
E = min(len(SRC) - 1, LL + 30)
RS0, RS1 = LL + 6, LL + 20
P_L, P_R = AL[LL].copy(), AR[RL].copy()
IL = IDLE["m"]["mixamorig:LeftFoot"].translation.copy()
IR = IDLE["m"]["mixamorig:RightFoot"].translation.copy()
IH = IDLE["m"]["mixamorig:Hips"].copy()
F = (P_L + P_R) / 2 - (IL + IR) / 2
F.z = 0.0
Q_L, Q_R = F + IL, F + IR
RL_IDLE = IDLE["m"]["mixamorig:LeftFoot"].to_quaternion()
RR_IDLE = IDLE["m"]["mixamorig:RightFoot"].to_quaternion()
print("STOP_PLAN takes over at source f%d from walk f%d (legs %.1f cm); left lands f%d (lift f%d), right f%d; settle to f%d" % (
    K0 + 1, WK + 1, 100 * G_IN, LL + 1, LS + 1, RL + 1, E + 1))
TOE_L = planted([p["m"]["mixamorig:LeftToeBase"].translation.copy() for p in SRC])
TOE_R = planted([p["m"]["mixamorig:RightToeBase"].translation.copy() for p in SRC])
TL, _ = plant(AL, gl, {len(rl) - 1: Q_L.copy()}, TOE_L)
TR, _ = plant(AR, gr, {}, TOE_R)
print("STOP_PLAN feet moved to idle's stance: left %.1f cm, right %.1f cm" % (100 * (Q_L - P_L).length, 100 * (Q_R - P_R).length))

# The source's hips and body turned onto the walk's where it takes over (its
# hips by some 40 degrees: the walk is turned into his guard). This also carries
# the walk's straightened chest (firm_walk.py's upright) into the stop.
TURN_H = W[WK]["m"]["mixamorig:Hips"].to_quaternion() @ SRC[K0]["m"]["mixamorig:Hips"].to_quaternion().inverted()
TURN = {n: W[WK]["q"][n] @ SRC[K0]["q"][n].inverted() for n in BODY}
print("STOP_PLAN hips turned %.1f deg onto the walk's" % math.degrees(TURN_H.angle))

stop = new_action("stop", "Stop Walking - Footmen.fbx: joins the walk, ends in idle's guard")
HXY = []
for i, k in enumerate(range(K0, E + 1)):
    s = SRC[k]
    w_body = smooth(k, LL - 6, LL + 24)
    w_arm = smooth(k, K0 + 3, LL)
    w_end = smooth(k, E - 8, E)
    wk = W[(WK + i) % NW]
    q = {}
    for n in NAMES:
        if n in ARM:
            q[n] = wk["q"][n].slerp(IDLE["q"][n], w_arm)
        elif n in BODY:
            q[n] = (TURN[n] @ s["q"][n]).slerp(IDLE["q"][n], w_body)
        else:
            q[n] = s["q"][n].copy()
    put(q, s["loc"])
    hips_src = s["m"]["mixamorig:Hips"]
    hips_on = (TURN_H @ hips_src.to_quaternion()).to_matrix().to_4x4()
    hips_on.translation = hips_src.translation
    m_h = mblend(hips_on, Matrix.Translation(F) @ IH, w_body)
    set_matrix(b("Hips"), m_h)
    # The legs keep the source's line (square to the front, as the walk's are):
    # the turn is taken back out at the thighs.
    back = (mblend(hips_src, Matrix.Translation(F) @ IH, w_body).to_quaternion() @ m_h.to_quaternion().inverted()).to_matrix()
    for side in ("Left", "Right"):
        up = b(side + "UpLeg")
        m = (back @ up.matrix.to_3x3()).to_4x4()
        m.translation = up.head.copy()
        set_matrix(up, m)
    # Feet: the last left step lands at idle's left; the right takes a settling step to idle's right.
    w_l = smooth(k, next((x for x in range(LS, LL) if not TOE_L[x]), LS), LL + 4)
    t_l = TL[k]
    r_l = s["m"]["mixamorig:LeftFoot"].to_quaternion().slerp(RL_IDLE, w_l)
    # The settling step: up first, across while lifted, then down.
    lin = min(1.0, max(0.0, (k - RS0) / (RS1 - RS0)))
    w_r = smooth(k, RS0 + 2, RS1 - 2)
    t_r = TR[k] + (Q_R - TR[RL]) * w_r * (1.0 if k >= RS0 else 0.0) + Vector((0, 0, 0.065 * math.sin(math.pi * lin)))
    r_r = s["m"]["mixamorig:RightFoot"].to_quaternion().slerp(RR_IDLE, smooth(k, RS0, RS1))
    ik_leg("Left", t_l, r_l)
    ik_leg("Right", t_r, r_r)
    # The source's stride is only the nearest to the walk's (its toes up to 18 cm
    # off): the legs ease in from the walk's, so the first frame is the walk's.
    w_in = smooth(i, 0, LEG_IN)
    if w_in < 1.0:
        for n in LEG:
            PB[n].rotation_quaternion = wk["q"][n].slerp(PB[n].rotation_quaternion, w_in)
        bpy.context.view_layer.update()
    if w_end > 0:
        for n in LEG:
            PB[n].rotation_quaternion = PB[n].rotation_quaternion.slerp(IDLE["q"][n], w_end)
        bpy.context.view_layer.update()
    key_all(i + 1)
    HXY.append(b("Hips").matrix.translation.xy.copy())
NS = len(HXY)
stop.frame_range = (1, NS)
# Travel to the root: the hips ease from the walk's in-place spot to idle's.
w0 = W[WK]["m"]["mixamorig:Hips"].translation.xy
ih = IH.translation.xy
root = [HXY[i] - w0.lerp(ih, smooth(i, 0, NS - 1)) for i in range(NS)]
r0 = root[0].copy()
for i in range(NS):
    sc.frame_set(i + 1)
    m = b("Hips").matrix.copy()
    m.translation.x -= root[i].x
    m.translation.y -= root[i].y
    set_matrix(b("Hips"), m)
    b("Hips").keyframe_insert("location", frame=i + 1)
STOP_PATH = [[round(float(r.x - r0.x), 4), round(float(r.y - r0.y), 4)] for r in root]
stop["root_path"] = sum(STOP_PATH, [])
stop["enter_walk_t"] = WK / FPS
stop["frames"] = NS
iLL = LL - K0

# --- the start ----------------------------------------------------------------
# A: the stop's settle backwards, from idle's guard to the moment its last step landed.
A = [grab(stop, f) for f in range(NS, iLL, -1)]
A_PATH = [Vector(STOP_PATH[NS - 1 - j]) - Vector(STOP_PATH[NS - 1]) for j in range(len(A))]
a_end = A[-1]
WS = min(range(NW), key=lambda j: gap(WREL[j], legs_rel(a_end)))
# B: the walk from that stride, the root gathering speed from rest.
NB = RAMP + NW
vel = [V * smooth(j, 0, RAMP) for j in range(NB)]
B_PATH = []
acc = A_PATH[-1].to_3d()
for j in range(NB):
    if j:
        acc = acc + vel[j] / FPS
    B_PATH.append(acc.copy())
plan = {}
for s in ("Left", "Right"):
    nat = []  # where the walk alone would put the ankle, in the world
    rot = []
    for j in range(NB):
        p = W[(WS + j) % NW]
        nat.append(p["m"]["mixamorig:%sFoot" % s].translation + B_PATH[j])
        rot.append(p["m"]["mixamorig:%sFoot" % s].to_quaternion())
    z = np.array([W[(WS + j) % NW]["m"]["mixamorig:%sFoot" % s].translation.z for j in range(NB)])
    down = z < z.min() + 0.04
    start_at = a_end["m"]["mixamorig:%sFoot" % s].translation + A_PATH[-1].to_3d()
    start_rot = a_end["m"]["mixamorig:%sFoot" % s].to_quaternion()
    tgt, trot = [None] * NB, [None] * NB
    spot, spot_rot = start_at.copy(), start_rot.copy()
    j = 0
    held = True  # the foot starts on the ground where the settle left it
    while j < NB:
        if held and (down[j] or j == 0):
            k = j
            while k + 1 < NB and down[k + 1]:
                k += 1
            if not down[j]:
                k = j
            for m in range(j, k + 1):
                tgt[m], trot[m] = spot.copy(), spot_rot.copy()
            j = k + 1
            held = False
            continue
        # A swing: from where the foot stands to where the walk would land it.
        k = j
        while k + 1 < NB and not down[k + 1]:
            k += 1
        land = min(NB - 1, k + 1)
        off0 = spot - nat[max(0, j - 1)]
        r_from = spot_rot
        for m in range(j, land + 1):
            u = smooth(m, j - 1, land)
            tgt[m] = nat[m] + off0 * (1.0 - u)
            trot[m] = r_from.slerp(rot[m], u)
        # Land and stay put for its stance.
        spot = tgt[land].copy()
        spot_rot = trot[land].copy()
        k2 = land
        while k2 + 1 < NB and down[k2 + 1]:
            k2 += 1
        for m in range(land, k2 + 1):
            tgt[m], trot[m] = spot.copy(), spot_rot.copy()
        j = k2 + 1
    plan[s] = (tgt, trot)
start = new_action("start", "stop's settle backwards, then the walk gathering speed")
for i, p in enumerate(A):
    put(p["q"], p["loc"])
    key_all(i + 1)
nA = len(A)
for j in range(NB):
    p = W[(WS + j) % NW]
    w = smooth(j, 0, 16)
    q = {n: a_end["q"][n].slerp(p["q"][n], w) for n in NAMES}
    put(q, a_end["loc"].lerp(p["loc"], w))
    for s in ("Left", "Right"):
        tgt, trot = plan[s]
        want = tgt[j] - B_PATH[j]
        # The walk's own ankle path takes over as the pins release (both end on it).
        ik_leg(s, want, trot[j])
    key_all(nA + j + 1)
start.frame_range = (1, nA + NB)
START_PATH = [[round(float(v.x), 4), round(float(v.y), 4)] for v in A_PATH] + [[round(float(v.x), 4), round(float(v.y), 4)] for v in B_PATH]
start["root_path"] = sum(START_PATH, [])
start["exit_walk_t"] = ((WS + NB - 1) % NW) / FPS
start["frames"] = nA + NB
end_gap = gap(legs_rel(grab(start, nA + NB)), WREL[(WS + NB - 1) % NW])

print("STOP", NS, "frames, %.2f s, travels %.2f m; joins the walk at %.3f s" % ((NS - 1) / FPS, Vector(STOP_PATH[-1]).length, WK / FPS),
      "slide cm", slide(stop, STOP_PATH))
print("START", nA + NB, "frames (settle backwards %d, gathering %d), travels %.2f m; walk from %.3f s, hands over at %.3f s (legs off the walk %.1f cm)" % (
    nA, NB, Vector(START_PATH[-1]).length, WS / FPS, start["exit_walk_t"], 100 * end_gap), "slide cm", slide(start, START_PATH))
rig.animation_data.action = bpy.data.actions["idle"]
bpy.ops.wm.save_mainfile(compress=True)
print("TRANSITIONS_SAVED")
