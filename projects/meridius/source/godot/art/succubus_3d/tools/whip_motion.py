"""The whip on the succubus clips (background Blender; after secondary_motion.py, on clips
fresh from retarget_clips.py: it adds to their keys, so a second run is refused).

  blender -b succubus_anim.blend --python whip_motion.py -- [clip,clip...]

1. Her whip arm out of her body. Per frame the left forearm and hand (rigid on their
   bones) and the whip's pommel below her fist are tested against the rest of her skin; where they cut in, the upper arm is
   turned out from her chest (about her chest's forward axis, through the shoulder). The
   angles are chosen for the whole clip at once, the least total of cut-in depth, angle and
   change from frame to frame (dynamic programming), then smoothed, so the arm eases out
   and back (24 Oct 2026: frame 220 of the bending idle, now idle_flourish; the standing
   idle's hand sank 6-7 cm into her fur hips).
2. The coil out of her body and head. The coil and the pommel are tested against her skin
   (her left hand and wrist left out: the fist holds the handle) and her tail; where they
   cut in, the whip is rolled about its handle (the coil swings round the handle in her
   fist) and, if that is not enough, tilted a little in the fist. The turns are chosen for
   the whole stretch at once, the least total of cut-in depth, turn and change from frame to
   frame (dynamic programming), then smoothed, so the whip never snaps round (frame 166 of
   the bending idle: the coil through her head).
3. The attack's lash (rig_succubus.py builds it). Out of the attack it is hidden (Lash_1
   scaled to nothing) and the coil shows. In the attack the coil rolls up into the collar
   while the lash plays out of it (LASH_OUT, at the top of her wind-up), cracks twice as a
   whip (lash_sim: laid back, a loop that runs out to the tip, straight at the crack, an
   S-wave recoil, then it falls and lies on the ground) and is reeled in (LASH_IN) as the
   coil unrolls. The crack frames (STRIKES) are stored as the strikes, with the lash's out
   and in times, in act["events"] (seconds).
4. The attack's follow-through after the second crack (run first, so 1 then keeps the arm
   out of her body as everywhere else). The clip turns her chest on about 90 degrees to her
   left and pulls her whip hand back over her shoulder, so the lash fell behind her. Now her
   chest's turn eases to a stop (CHEST_HOLD) and her hand stops at the target and sinks
   forward (FOLLOW_KEYS, two-bone IK on the upper arm and forearm, the whip along her
   forearm), so the lash falls in front of her; eased in and back onto the clip (FOLLOW).
"""
import json
import math
import sys

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

FPS = 30
CUT = 0.008                 # cut-in deeper than this counts (m)
CUT_ARM = 0.012             # her hand may sink this far into her fur (m)
ARM_ANGLES = np.arange(0, 46, 3)                     # arm turned out, degrees
ROLLS = np.radians(np.arange(-180, 180, 10))         # whip rolled about its handle
TILTS = np.radians([0, -12, 12, -24, 24])            # and tilted in the fist
LASH_OUT = (17, 22)         # attack frames: the lash plays out (coil rolls up a frame ahead)
LASH_IN = (62, 70)          # and is reeled in (the coil unrolls a frame behind)
# The lash as a whip (24 Oct 2026, the user's reference: youtube.com/watch?v=ASK_NEQ3C8Y):
# laid back over her shoulder at the top of the wind-up, then for each strike it straightens
# out of the handle towards the crack point, handle first, so the rest of it rolls over in
# a loop that runs out to the tip; straight at the crack, then it recoils and falls.
LOAD = (15, 18, 22, 24)     # attack frames: laid back (easing in, held from, easing out, gone)
STRIKES = ((24, 27), (49, 52))           # attack frames: the loop starts to run out; the crack
TARGET = Vector((0.0, -2.72, 1.0))       # the cracks aim here: the middle of the tile ahead
ROLL = 1.6                  # the loop runs out faster and faster: progress ** ROLL
LOOP_R = (0.3, 0.06)        # the loop's radius as it starts and at the crack (m)
LOOP_PULL = 0.04            # per substep, the lash beyond the front drawn into the loop
HOLD = (0.0, 0.6)           # after the crack: held straight, then let go over (frames)
RECOIL = 5.0                # once let go, the lash kicked into an S-wave this fast (m/s)
SUBSTEPS = 30
ITERATIONS = 6
GRAVITY = Vector((0, 0, -9.81))
FALL = 3.0                  # the lash falls this many times faster than a stone: it droops
                            # from the crack to her hand in about 8 frames, as in the reference
DRAG = (1.5, 0.8)           # drag on its motion relative to the handle: 1/s, and 1/m times the
                            # speed, so it follows her hand but waves and flails die out
STIFF = (0.0005, 0.0)       # straightening per substep at the handle and at the tip
TAPER = 0.75                # mass per length falls to (1 - TAPER)^2 of the handle's at the tip
# The follow-through after the second crack (24 Oct 2026, the user: the lash must fall forward).
FOLLOW = (50, 52, 72, 92)   # attack frames: eased in, held from the crack, eased back onto the clip
# (frame, direction from her shoulder or None for at TARGET, distance (m)): her hand stops
# at the target, then sinks forward while the lash falls and is reeled in
FOLLOW_KEYS = ((52, None, 0.43), (55, (0.15, -0.95, -0.3), 0.43), (60, (0.2, -0.85, -0.55), 0.41),
               (66, (0.25, -0.65, -0.75), 0.4))
FOLLOW_POLE = Vector((0.6, 0.2, -1.0))  # her elbow points down and out
CHEST_HOLD = (25.0, 12.0)   # her chest's turn to her left (degrees from ahead) eases to a stop
                            # past the first, at most the second further
LASH_R = 0.035              # the lash's half-thickness with its blades (rig_succubus.py)
GROUND = LASH_R
HIDDEN = 0.001              # Lash_1's scale when the lash is put away
# Clips that start (and end) in idle's first pose (retarget_clips.py blend_in / blend_out):
# their arm turn and whip roll are pinned there to idle's own, so switching never jumps.
FROM_IDLE = ("idle_flourish", "hit", "death")
TO_IDLE = ("idle_flourish", "hit")
PIN = {}                    # idle's first-frame arm angle index and whip state
# Her legs, body and head for the lash: (from, to, radius); to None = a sphere at from.
CAPSULES = [("mixamorig:Hips", "mixamorig:Neck", 0.17), ("mixamorig:Head", "mixamorig:HeadTop_End", 0.12)] + [
    (f"mixamorig:{s}UpLeg", f"mixamorig:{s}Leg", 0.13) for s in ("Left", "Right")] + [
    (f"mixamorig:{s}Leg", f"mixamorig:{s}Foot", 0.08) for s in ("Left", "Right")]

argv = sys.argv[sys.argv.index("--") + 1:]
sc = bpy.context.scene
rig = bpy.data.objects["SuccubusRig"]
body, whip, tail = (bpy.data.objects[n] for n in ("Succubus", "Whip", "Tail"))
PB, B = rig.pose.bones, rig.data.bones
assert rig.matrix_world == Matrix.Identity(4)
LASH = json.loads(rig["lash"])
LASH_NAMES = [f"Lash_{i + 1}" for i in range(LASH["bones"])]
SEG = LASH["length"] / LASH["bones"]
COLLAR = Vector(rig["whip_collar"])
LOWER = {"mixamorig:LeftForeArm", "LeftForeArmTwist", "mixamorig:LeftHand"}
ARM = LOWER | {"mixamorig:LeftArm", "mixamorig:LeftShoulder"}


def smoothstep(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


def skinned(ob):
    """World positions of an object's evaluated (skinned) vertices."""
    ev = ob.evaluated_get(bpy.context.evaluated_depsgraph_get())
    m = ev.to_mesh()
    co = np.empty(len(m.vertices) * 3)
    m.vertices.foreach_get("co", co)
    ev.to_mesh_clear()
    return co.reshape(-1, 3)


def weights(ob, names):
    """Per vertex: the share of its bone weights on `names`, and its strongest bone."""
    gname = {g.index: g.name for g in ob.vertex_groups}
    share, top = np.zeros(len(ob.data.vertices)), []
    for v in ob.data.vertices:
        gs = [(g.weight, gname[g.group]) for g in v.groups if gname[g.group] in B and g.weight > 1e-4]
        tot = sum(w for w, _ in gs) or 1.0
        share[v.index] = sum(w for w, n in gs if n in names) / tot
        top.append(max(gs)[1] if gs else "")
    return share, top


# Her skin without the pads and tufts (loose shells, the tufts spiky): the faces to test against.
tagged = set()
for g in ("PawPads", "FurTufts"):
    vg = body.vertex_groups.get(g)
    if vg:
        tagged.update(v.index for v in body.data.vertices if any(x.group == vg.index for x in v.groups))
arm_share, top_bone = weights(body, ARM)
low_share, _ = weights(body, LOWER)
polys = [tuple(p.vertices) for p in body.data.polygons if not any(i in tagged for i in p.vertices)]
POLYS_ARM = [p for p in polys if not any(top_bone[i] in ARM for i in p)]          # all but her left arm
WRIST = {"mixamorig:LeftHand", "LeftForeArmTwist"}
POLYS_WHIP = [p for p in polys if not any(top_bone[i] in WRIST for i in p)]       # all but hand and wrist
N_BODY = len(body.data.vertices)
POLYS_TAIL = [tuple(N_BODY + i for i in p.vertices) for p in tail.data.polygons]
ARM_PTS = np.nonzero((low_share > 0.95) & np.array([i not in tagged for i in range(N_BODY)]))[0][::4]
# The whip's test points in the rest pose: the coil (every 6th vertex) and the pommel.
rest_whip = np.array([v.co[:] for v in whip.data.vertices])
coil_g = whip.vertex_groups["WhipCoil"].index
is_coil = np.array([any(g.group == coil_g for g in v.groups) for v in whip.data.vertices])
g_rest = B["WhipGrip"].matrix_local
hdir = Vector(g_rest.col[1][:3]).normalized()
t_ax = (rest_whip - np.array(g_rest.translation)) @ np.array(hdir)
COIL_PTS = rest_whip[is_coil][::6]
POMMEL_PTS = rest_whip[(~is_coil) & (t_ax < -0.06)][::3]
G_REST_INV = np.array(g_rest.inverted())
print("WHIP_MOTION test points: arm", len(ARM_PTS), "coil", len(COIL_PTS), "pommel", len(POMMEL_PTS))


RAYS = [Vector(v) for v in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))]


def cut_depth(bvh, pts, cut=CUT):
    """Summed depth of points inside the surface, beyond `cut` (m), and how many. A point
    is inside when the nearest surface faces away from it and five of six rays along the
    axes leave through a back face (the nearest face alone misreads her fur's hem)."""
    tot, n = 0.0, 0
    for p in pts:
        p = Vector(p)
        loc, nrm, _, _ = bvh.find_nearest(p)
        if loc is None:
            continue
        d = -(p - loc).dot(nrm)
        if d <= cut:
            continue
        back = 0
        for k, r in enumerate(RAYS):
            hit, hn, _, _ = bvh.ray_cast(p, r)
            back += hit is not None and hn.dot(r) > 0
            if back + (5 - k) < 5:
                break
        if back >= 5:
            tot += min(d, 0.06)
            n += 1
    return tot, n


def key(pb, path, frame):
    pb.keyframe_insert(path, frame=frame)


def smooth_series(x, sigma, loop):
    """Gaussian smoothing (wrapping round for loops)."""
    if sigma <= 0:
        return x
    r = int(3 * sigma)
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    pad = np.concatenate([x[-r - 1:-1], x, x[1:r + 1]]) if loop else np.concatenate([np.repeat(x[:1], r), x, np.repeat(x[-1:], r)])
    return np.convolve(pad, k, mode="valid")


def dilate(x, r, loop):
    n = len(x)
    return np.array([max(x[(i + k) % n] if loop else x[min(n - 1, max(0, i + k))] for k in range(-r, r + 1)) for i in range(n)])


def chest_axes():
    """Her chest's forward and left directions, posed (armature space)."""
    sp = PB["mixamorig:Spine2"]
    R = sp.matrix.to_3x3() @ B["mixamorig:Spine2"].matrix_local.to_3x3().inverted()
    return (R @ Vector((0, -1, 0))).normalized(), (R @ Vector((1, 0, 0))).normalized()


def grip_dir():
    return (PB["WhipGrip"].matrix.to_3x3() @ Vector((0, 1, 0))).normalized()


def turn_about(pb, at, q):
    """Turn a posed bone (and so its children) by q about the point `at` (armature space)."""
    pb.matrix = Matrix.Translation(at) @ q.to_matrix().to_4x4() @ Matrix.Translation(-at) @ pb.matrix
    bpy.context.view_layer.update()


# 4. -------------------------------------------------------------------------------------
def follow_key(f, S):
    """The follow-through's hand target at frame f: her shoulder S plus a direction and reach."""
    keys = [(k, (TARGET - S).normalized() if v is None else Vector(v).normalized(), r) for k, v, r in FOLLOW_KEYS]
    if f <= keys[0][0]:
        return S + keys[0][1] * keys[0][2]
    for (k0, v0, r0), (k1, v1, r1) in zip(keys, keys[1:]):
        if f <= k1:
            t = smoothstep((f - k0) / (k1 - k0))
            return S + v0.lerp(v1, t).normalized() * (r0 + (r1 - r0) * t)
    return S + keys[-1][1] * keys[-1][2]


def follow_through(n):
    """Step 4 on the attack: the chest's turn eased to a stop and the arm's IK, keyed per frame."""
    a, b, c, e = FOLLOW
    spine = [PB[f"mixamorig:{x}"] for x in ("Spine", "Spine1", "Spine2")]
    upper, fore, hand = PB["mixamorig:LeftArm"], PB["mixamorig:LeftForeArm"], PB["mixamorig:LeftHand"]
    edited = spine + [upper, fore, hand]
    sc.frame_set(a - 1)
    prev = {pb.name: pb.rotation_quaternion.copy() for pb in edited}
    most = [0.0, 0.0]
    for f in range(a, min(e, n) + 1):
        sc.frame_set(f)
        fwd, _ = chest_axes()
        over = math.degrees(math.atan2(fwd.x, -fwd.y)) - CHEST_HOLD[0]
        cut = over - CHEST_HOLD[1] * (1 - math.exp(-over / CHEST_HOLD[1])) if over > 0 else 0.0
        for pb in spine:
            if cut > 0.01:
                turn_about(pb, pb.head.copy(), Quaternion((0, 0, 1), math.radians(-cut / 3)))
        w = smoothstep((f - a) / (b - a)) * (1 - smoothstep((f - c) / (e - c)))
        if w > 1e-3:
            S, E0, H0 = upper.head.copy(), fore.head.copy(), hand.head.copy()
            la, lb = (E0 - S).length, (H0 - E0).length
            H = H0.lerp(follow_key(max(f, b), S), w)
            u = H - S
            dist = min(u.length, 0.98 * (la + lb))
            u.normalize()
            H = S + u * dist
            cos_a = max(-1.0, min(1.0, (la * la + dist * dist - lb * lb) / (2 * la * dist)))
            pole, pref = E0 - S, FOLLOW_POLE.copy()
            pole -= u * pole.dot(u)
            pref -= u * pref.dot(u)
            p = (pole.normalized() if pole.length > 1e-4 else pref.normalized()).lerp(pref.normalized(), w)
            p -= u * p.dot(u)
            p.normalize()
            E = S + (u * cos_a + p * math.sqrt(1 - cos_a * cos_a)) * la
            turn_about(upper, S, (E0 - S).rotation_difference(E - S))
            E1 = fore.head.copy()
            turn_about(fore, E1, (hand.head - E1).rotation_difference(H - E1))
            # the whip along her forearm, as the reference's lash runs along the arm's line
            q = grip_dir().rotation_difference((H - E1).normalized())
            turn_about(hand, hand.head.copy(), Quaternion().slerp(q, w))
            most[1] = max(most[1], (hand.head - H0).length)
        most[0] = max(most[0], cut)
        for pb in edited:
            qk = pb.rotation_quaternion.copy()
            qk.make_compatible(prev[pb.name])
            prev[pb.name] = qk
            pb.rotation_quaternion = qk
            key(pb, "rotation_quaternion", f)
    return most


# 1. -------------------------------------------------------------------------------------
def arm_costs(n):
    """Per frame and arm angle (ARM_ANGLES): the cut-in cost; and the turn's sign."""
    cost = np.tile(ARM_ANGLES * 0.01, (n, 1))     # a little for the angle itself
    sign = None
    for f in range(1, n + 1):
        sc.frame_set(f)
        co = skinned(body)
        # her forearm and hand, and the whip's pommel below her fist (rolling cannot move it)
        pts = np.vstack([co[ARM_PTS], whip_points(PB["WhipGrip"].matrix.copy(), np.eye(4), False)])
        bvh = BVHTree.FromPolygons(co.tolist(), POLYS_ARM, all_triangles=False)
        base, cnt = cut_depth(bvh, pts, CUT_ARM)
        if cnt < 2:
            continue
        fwd, left = chest_axes()
        h = np.array(PB["mixamorig:LeftArm"].head)
        if sign is None:   # which way about the forward axis turns the arm out (to her left)
            R = np.array(Matrix.Rotation(math.radians(5), 3, fwd))
            hand = np.array(PB["mixamorig:LeftHand"].head) - h
            sign = 1.0 if (R @ hand - hand) @ np.array(left) > 0 else -1.0
        for k, a in enumerate(ARM_ANGLES):
            R = np.array(Matrix.Rotation(math.radians(sign * a), 3, fwd))
            d, c = cut_depth(bvh, (pts - h) @ R.T + h, CUT_ARM) if k else (base, cnt)
            cost[f - 1, k] += 40.0 * d
    return cost, sign


def dp_path(cost, move):
    """The sequence of states with the least total cost plus move[a, b] per change."""
    n, m = cost.shape
    acc = cost[0].copy()
    back = np.zeros((n, m), dtype=int)
    for i in range(1, n):
        tot = acc[:, None] + move            # from state a (rows) to b (columns)
        back[i] = np.argmin(tot, axis=0)
        acc = tot[back[i], np.arange(m)] + cost[i]
    path = [int(np.argmin(acc))]
    for i in range(n - 1, 0, -1):
        path.append(int(back[i][path[-1]]))
    return path[::-1]


def seam(x, loop, k=12):
    """For a loop: ease the last k frames to the first frame's value."""
    x = np.array(x, dtype=float)
    if loop and len(x) > k:
        for j in range(k):
            w = smoothstep((j + 1) / k)
            x[len(x) - k + j] = x[len(x) - k + j] * (1 - w) + x[0] * w
    return x


def pin(cost, clip, key_):
    """Hold the first (and last) frame to idle's own state, for clips that blend with it."""
    if key_ in PIN:
        for row, on in ((0, clip in FROM_IDLE), (-1, clip in TO_IDLE)):
            if on:
                keep = cost[row, PIN[key_]]
                cost[row] = 1e3
                cost[row, PIN[key_]] = keep
    return cost


def arm_need(n, loop=False, clip=""):
    """Per frame: the arm's turn out (degrees), and its sign."""
    cost, sign = arm_costs(n)
    if sign is None and "arm" not in PIN:
        return np.zeros(n), 1.0
    move = 0.05 * np.abs(ARM_ANGLES[:, None] - ARM_ANGLES[None, :])
    path = dp_path(pin(cost, clip, "arm"), move)
    if clip == "idle":
        PIN["arm"] = path[0]
        PIN["arm_sign"] = sign
    sign = sign if sign is not None else PIN.get("arm_sign", 1.0)
    ang = ARM_ANGLES[path].astype(float)
    return np.clip(smooth_series(seam(ang, loop), 1.5, loop), 0, None), sign


def arm_pass(act, n, loop, clip):
    ang, sign = arm_need(n, loop, clip)
    if not ang.any():
        return 0.0
    for f in range(1, n + 1):
        a = float(ang[f - 1])
        if a < 0.05:
            continue
        sc.frame_set(f)
        fwd, _ = chest_axes()
        pb = PB["mixamorig:LeftArm"]
        h = pb.head.copy()
        pb.matrix = Matrix.Translation(h) @ Matrix.Rotation(math.radians(sign * a), 4, fwd) @ Matrix.Translation(-h) @ pb.matrix
        bpy.context.view_layer.update()
        key(pb, "rotation_quaternion", f)
    return float(ang.max())


# 2. -------------------------------------------------------------------------------------
STATES = [(r, t) for t in TILTS for r in ROLLS]
S_ROLL = np.array([s[0] for s in STATES])
S_TILT = np.array([s[1] for s in STATES])
S_ID = STATES.index((0.0, 0.0)) if (0.0, 0.0) in STATES else int(np.argmin(np.abs(S_ROLL) + np.abs(S_TILT)))
STATE_M = [np.array((Quaternion((0, 1, 0), r) @ Quaternion((1, 0, 0), t)).to_matrix().to_4x4()) for r, t in STATES]
TURN_COST = np.abs(np.angle(np.exp(1j * S_ROLL))) * 0.15 + np.abs(S_TILT) * 1.5
MOVE_W = 2.5   # per radian of change between frames


def whip_points(G, Rc, coil_on):
    pts = np.vstack([COIL_PTS, POMMEL_PTS]) if coil_on else POMMEL_PTS
    M = np.array(G) @ Rc @ G_REST_INV
    return pts @ M[:3, :3].T + M[:3, 3]


def frame_bvh(f):
    """Her skin (without hand and wrist) and tail at frame f, and the whip grip's pose."""
    sc.frame_set(f)
    co = np.vstack([skinned(body), skinned(tail)])
    return BVHTree.FromPolygons(co.tolist(), POLYS_WHIP + POLYS_TAIL, all_triangles=False), PB["WhipGrip"].matrix.copy()


def whip_pass(act, n, loop, coil_vis, clip):
    """Roll (and tilt) the whip about its grip where the coil or the pommel cuts into her."""
    pen0 = np.zeros(n)
    for f in range(1, n + 1):
        bvh, G = frame_bvh(f)
        d, c = cut_depth(bvh, whip_points(G, np.eye(4), coil_vis[f - 1] > 0.5))
        pen0[f - 1] = d if c >= 2 else 0.0
    trouble = dilate((pen0 > 0).astype(float), 12, loop) > 0
    if "whip" in PIN and PIN["whip"] != S_ID:   # pinned ends: worked out like trouble
        if clip in FROM_IDLE:
            trouble[:12] = True
        if clip in TO_IDLE:
            trouble[-12:] = True
    if not trouble.any():
        if clip == "idle":
            PIN["whip"] = S_ID
        return 0, 0
    cost = np.zeros((n, len(STATES)))
    for f in range(1, n + 1):
        if not trouble[f - 1]:
            cost[f - 1] = 1e3
            cost[f - 1, S_ID] = 0.0
            continue
        bvh, G = frame_bvh(f)
        for k, Rc in enumerate(STATE_M):
            d, _ = cut_depth(bvh, whip_points(G, Rc, coil_vis[f - 1] > 0.5))
            cost[f - 1, k] = 60.0 * d + TURN_COST[k]
    dr = np.abs(np.angle(np.exp(1j * (S_ROLL[:, None] - S_ROLL[None, :]))))
    path = dp_path(pin(cost, clip, "whip"), MOVE_W * (dr + np.abs(S_TILT[:, None] - S_TILT[None, :])))
    if clip == "idle":
        PIN["whip"] = path[0]
    roll = seam(np.unwrap(S_ROLL[path]), loop)
    tilt = seam(S_TILT[path], loop)
    roll, tilt = smooth_series(roll, 1.5, loop), smooth_series(tilt, 1.5, loop)
    left = 0
    for f in range(1, n + 1):
        q = Quaternion((0, 1, 0), float(roll[f - 1])) @ Quaternion((1, 0, 0), float(tilt[f - 1]))
        pb = PB["WhipGrip"]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = q
        key(pb, "rotation_quaternion", f)
    for f in range(1, n + 1):
        if trouble[f - 1]:
            bvh, G = frame_bvh(f)      # with the turn just keyed
            d, c = cut_depth(bvh, whip_points(G, np.eye(4), coil_vis[f - 1] > 0.5))
            left += c >= 2
    return int((pen0 > 0).sum()), left


# 3. -------------------------------------------------------------------------------------
def visibility(clip, n):
    """Per frame: the lash's scale (0 put away) and the coil's."""
    if clip != "attack":
        return np.zeros(n), np.ones(n)
    f = np.arange(1, n + 1)
    lash = np.array([smoothstep((x - LASH_OUT[0]) / (LASH_OUT[1] - LASH_OUT[0])) *
                     (1 - smoothstep((x - LASH_IN[0]) / (LASH_IN[1] - LASH_IN[0]))) for x in f])
    coil = np.array([1 - smoothstep((x - LASH_OUT[0] + 1) / (LASH_OUT[1] - LASH_OUT[0])) +
                     smoothstep((x - LASH_IN[0] - 1) / (LASH_IN[1] - LASH_IN[0])) for x in f])
    return lash, np.clip(coil, 0, 1)


def capsules():
    out = []
    for a, b, r in CAPSULES:
        pa = PB[a].head.copy()
        pb_ = PB[b].head.copy() if b in PB else PB[a].tail.copy()
        out.append((pa, pb_, r))
    return out


def push_out(p, caps):
    for a, b, r in caps:
        ab = b - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / max(1e-9, ab.length_squared)))
        q = a + ab * t
        d = p - q
        if d.length < r + LASH_R:
            p = q + (d.normalized() if d.length > 1e-6 else Vector((0, 0, 1))) * (r + LASH_R)
    return p


def lash_guides(clip, grip, N):
    """The whip's guides for `clip`: (load, strikes). load(ft, P1) gives the laid-back
    targets and their pull per substep (or None); each strike is (start, crack, aim), the
    aim the crack point a lash length from the handle towards TARGET (frames, Vector)."""
    if clip != "attack":
        return None, []
    strikes_ = []
    for f0, f1 in STRIKES:
        C, d = grip[f1 - 1]
        p1 = C + d * SEG
        strikes_.append((f0, f1, p1 + (TARGET - p1).normalized() * SEG * (N - 1)))
    C, d = grip[STRIKES[0][1] - 1]
    back = -(TARGET - C)
    back.z = 0.0
    back.normalize()

    def load(ft, p1):
        a, b, c, e = LOAD
        pull = 0.25 * smoothstep((ft - a) / (b - a)) * (1 - smoothstep((ft - c) / (e - c)))
        if pull <= 0:
            return None
        pts, p = [], p1.copy()
        for k in range(2, N + 1):      # up out of her fist, curving back behind her
            ang = math.radians(75 - 65 * (k - 2) / (N - 2))
            p = p + (back * math.cos(ang) + Vector((0, 0, math.sin(ang)))) * SEG
            pts.append(p)
        return pts, pull

    return load, strikes_


def lash_sim(n, lash_vis, clip="attack"):
    """The lash as a whip from the collar, per frame: its points (unscaled, exact lengths).

    A tapered rope (Verlet, SUBSTEPS per frame: gravity times FALL, drag on its motion
    relative to the handle, a little stiffer by the handle, kept out of the ground, her
    legs, body and head; the tip a sixteenth of the handle's mass per length, so a wave
    speeds up as it runs out). In the attack it is laid back over her shoulder at the top
    of the wind-up (LOAD), and for each strike the points from the handle out to a front
    that runs to the tip, faster and faster, are held on the straight line from the handle
    to the crack point: the rest rolls over in a loop and the tip whips round onto the line
    at the crack. Then the line lets go (HOLD), an S-wave is kicked into the lash (RECOIL)
    and it droops, hangs from her hand and lies on the ground as a rope."""
    N = LASH["bones"]
    grip = []
    caps = []
    for f in range(1, n + 1):
        sc.frame_set(f)
        G = PB["WhipGrip"].matrix.copy()
        grip.append((G @ g_rest.inverted() @ COLLAR, (G.to_3x3() @ Vector((0, 1, 0))).normalized()))
        caps.append(capsules())
    load, strikes_ = lash_guides(clip, grip, N)
    C0, d0 = grip[0]
    P = [C0 + d0 * SEG * k for k in range(N + 1)]
    prev = [p.copy() for p in P]
    dt = 1.0 / (FPS * SUBSTEPS)
    stiff = [0.0, 0.0] + [STIFF[1] + (STIFF[0] - STIFF[1]) * (1 - (k - 2) / (N - 2)) ** 2 for k in range(2, N + 1)]
    inv_m = [0.0, 0.0] + [1.0 / (1 - TAPER * (k - 1) / (N - 1)) ** 2 for k in range(2, N + 1)]
    out = [list(P)]
    sides = {}
    kicked = set()
    for f in range(2, n + 1):
        (Ca, da), (Cb, db) = grip[f - 2], grip[f - 1]
        for s in range(1, SUBSTEPS + 1):
            tau = s / SUBSTEPS
            ft = f - 1 + tau
            C = Ca.lerp(Cb, tau)
            d = da.lerp(db, tau).normalized()
            hv = C + d * SEG - P[1]       # the handle's step: drag acts on motion relative to it
            P[0], P[1] = C, C + d * SEG
            prev[0], prev[1] = P[0].copy(), P[1].copy()
            held = [0.0] * (N + 1)
            line = None
            loop = []
            for si, (f0, f1, aim) in enumerate(strikes_):
                if si in sides and si not in kicked and ft > f1 + HOLD[0] + HOLD[1]:
                    kicked.add(si)          # the recoil: an S-wave out to the tip, as in the reference
                    line_ = (aim - P[1]).normalized()
                    nrm_ = sides[si] - line_ * sides[si].dot(line_)
                    nrm_.normalize()
                    for k in range(2, N + 1):
                        x = (k - 1) / (N - 1)
                        prev[k] -= nrm_ * (RECOIL * math.sqrt(x) * math.sin(2 * math.pi * x) * dt)
                if f0 <= ft <= f1 + HOLD[0] + HOLD[1]:
                    u = min(1.0, (ft - f0) / (f1 - f0))
                    front = SEG + SEG * (N - 1) * u ** ROLL
                    let_go = 1 - smoothstep((ft - f1 - HOLD[0]) / HOLD[1])
                    line = (aim - P[1]).normalized()
                    if si not in sides:       # the loop rolls over on the side the lash is
                        off = P[N] - P[1]
                        off -= line * off.dot(line)
                        sides[si] = off.normalized() if off.length > 0.05 else Vector((0, 0, 1))
                    nrm = sides[si] - line * sides[si].dot(line)
                    nrm.normalize()
                    r = LOOP_R[1] + (LOOP_R[0] - LOOP_R[1]) * (1 - u)
                    q = P[1] + line * (front - SEG)
                    for k in range(2, N + 1):
                        held[k] = let_go * smoothstep((front + SEG - k * SEG) / (2 * SEG))
                        past = k * SEG - front    # beyond the front: round the loop, then back
                        if past > 0:
                            if past < math.pi * r:
                                a = past / r
                                at = q + nrm * (r - r * math.cos(a)) + line * (r * math.sin(a))
                            else:
                                at = q + nrm * (2 * r) - line * (past - math.pi * r)
                            loop.append((k, at, LOOP_PULL * let_go))
            for k in range(2, N + 1):
                v = P[k] - prev[k] - hv
                v = hv + v * math.exp(-(DRAG[0] + DRAG[1] * v.length / dt) * dt)
                prev[k] = P[k].copy()
                P[k] = P[k] + v + GRAVITY * FALL * dt * dt
                if stiff[k]:
                    P[k] = P[k] + (2 * P[k - 1] - P[k - 2] - P[k]) * stiff[k] * (1 - held[k])
            guide = load(ft, P[1]) if load else None
            if guide:
                for k in range(2, N + 1):
                    P[k] = P[k].lerp(guide[0][k - 2], guide[1])
            if line is not None:
                for k in range(2, N + 1):
                    if held[k]:
                        P[k] = P[k].lerp(P[1] + line * SEG * (k - 1), held[k])
                for k, at, pull in loop:
                    P[k] = P[k].lerp(at, pull * (1 - held[k]))
            im = [inv_m[k] * (1 - held[k]) for k in range(N + 1)]
            for _ in range(ITERATIONS):
                for k in range(1, N):
                    ia, ib = im[k], im[k + 1]
                    if ia + ib <= 0:
                        continue
                    dl = P[k + 1] - P[k]
                    L = dl.length or 1e-9
                    corr = dl * ((L - SEG) / L / (ia + ib))
                    P[k] = P[k] + corr * ia
                    P[k + 1] = P[k + 1] - corr * ib
            for k in range(2, N + 1):
                if held[k] > 0.99:
                    continue
                q = push_out(P[k], caps[f - 1])
                prev[k] += q - P[k]           # pushed out, not flung: keeps its own velocity
                if q.z < GROUND:
                    q.z = GROUND
                    prev[k].x += (q.x - prev[k].x) * 0.5   # friction on the ground
                    prev[k].y += (q.y - prev[k].y) * 0.5
                P[k] = q
        D = [P[0], P[1]]
        for k in range(2, N + 1):     # exact lengths for the bones
            D.append(D[-1] + (P[k] - D[-1]).normalized() * SEG)
        out.append(D)
    return out


def lash_keys(act, n, lash_vis, coil_vis):
    """Key the lash bones and the coil's scale; returns the tip's speed per frame (m/s)."""
    for pb in [PB[x] for x in LASH_NAMES] + [PB["WhipCoil"]]:
        pb.rotation_mode = "QUATERNION"
    shown = [f for f in range(1, n + 1) if lash_vis[f - 1] > 1e-3]
    pts = lash_sim(n, lash_vis, act.name) if shown else None
    rel = {x: B[x].parent.matrix_local.inverted() @ B[x].matrix_local for x in LASH_NAMES}
    tip = []
    prev_q = {}
    for f in range(1, n + 1):
        g = float(lash_vis[f - 1])
        c = float(coil_vis[f - 1])
        PB["WhipCoil"].scale = (max(c, HIDDEN),) * 3
        key(PB["WhipCoil"], "scale", f)
        if g <= 1e-3 or pts is None:
            PB[LASH_NAMES[0]].scale = (HIDDEN,) * 3
            for x in LASH_NAMES:
                PB[x].rotation_quaternion = Quaternion()
                key(PB[x], "rotation_quaternion", f)
            key(PB[LASH_NAMES[0]], "scale", f)
            tip.append(None)
            continue
        sc.frame_set(f)
        D = pts[f - 1]
        M = PB["WhipGrip"].matrix.copy()
        for k, x in enumerate(LASH_NAMES):
            pb = PB[x]
            if k == 0:
                q = Quaternion()
                pb.scale = (g, g, g)
                key(pb, "scale", f)
            else:
                F = (M @ rel[x]).to_3x3().normalized()
                want = (D[k + 1] - D[k]).normalized()
                turn = (F @ Vector((0, 1, 0))).rotation_difference(want)
                q = (F.inverted() @ turn.to_matrix() @ F).to_quaternion()
            if x in prev_q:
                q.make_compatible(prev_q[x])
            prev_q[x] = q
            pb.rotation_quaternion = q
            key(pb, "rotation_quaternion", f)
            sm = Matrix.Diagonal((g, g, g, 1.0)) if k == 0 else Matrix.Identity(4)
            M = M @ rel[x] @ q.to_matrix().to_4x4() @ sm
        C = D[0]
        tip.append(C + (D[-1] - C) * g)
    speed = [0.0] * n
    for i in range(1, n):
        if tip[i] is not None and tip[i - 1] is not None:
            speed[i] = (tip[i] - tip[i - 1]).length * FPS
    return speed


def run(clip):
    act = bpy.data.actions[clip]
    if act.get("whip_motion"):
        raise SystemExit(f"{clip}: whip_motion.py has run on it already; retarget it afresh")
    n = int(act["frames"])
    loop = bool(act.get("loop"))
    rig.animation_data.action = act
    for x in ["WhipGrip", "WhipCoil", "mixamorig:LeftArm"] + LASH_NAMES:
        PB[x].rotation_mode = "QUATERNION"
    if clip == "attack":
        cut, moved = follow_through(n)
        print("WHIP_FOLLOW chest turn cut up to %.1f deg, hand moved up to %.2f m" % (cut, moved))
    arm = arm_pass(act, n, loop, clip)
    lash_vis, coil_vis = visibility(clip, n)
    hit, left = whip_pass(act, n, loop, coil_vis, clip)
    speed = lash_keys(act, n, lash_vis, coil_vis)
    ev = json.loads(act.get("events", "{}"))
    if clip == "attack":
        ev["lash_out"] = round((LASH_OUT[1] - 1) / FPS, 4)
        ev["strikes"] = [round((f1 - 1) / FPS, 4) for _, f1 in STRIKES]
        ev["lash_in"] = round((LASH_IN[0] - 1) / FPS, 4)
        print("WHIP_LASH tip speed at the cracks", ["%d: %.1f m/s" % (f1, speed[f1 - 1]) for _, f1 in STRIKES],
              "peak %.1f m/s at frame %d" % (max(speed), speed.index(max(speed)) + 1))
    act["events"] = json.dumps(ev)
    act["whip_motion"] = True
    for fc in act.fcurves if hasattr(act, "fcurves") else []:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    print("WHIP_MOTION", clip, n, "frames: arm turned out up to %.1f deg;" % arm,
          "whip cut in on", hit, "frames, after the turns", left)


if argv and argv[0] == "arms":     # -- arms <clip,clip>: the arm turn each frame needs
    for c in argv[1].split(","):
        rig.animation_data.action = bpy.data.actions[c]
        need, _ = arm_need(int(bpy.data.actions[c]["frames"]), bool(bpy.data.actions[c].get("loop")))
        print("ARMS", c, "frames turned", int((need > 0.5).sum()), "max %.0f" % need.max(),
              "profile", " ".join(str(int(round(x))) for x in need))
    sys.exit(0)
if argv and argv[0] == "lash":     # -- lash <out.json>: the attack's lash as simulated now, unkeyed
    rig.animation_data.action = bpy.data.actions["attack"]
    n_ = int(bpy.data.actions["attack"]["frames"])
    pts_ = lash_sim(n_, visibility("attack", n_)[0], "attack")
    json.dump({"frames": [[list(p) for p in D] for D in pts_], "strikes": STRIKES, "target": list(TARGET)},
              open(argv[1], "w"))
    print("WHIP_LASH_DUMP", argv[1])
    sys.exit(0)
if argv and argv[0] == "probe":   # -- probe <clip> <frame,frame...>: cut-in before any fix
    import time
    rig.animation_data.action = bpy.data.actions[argv[1]]
    for f in (int(x) for x in argv[2].split(",")):
        t0 = time.time()
        sc.frame_set(f)
        co = skinned(body)
        bvh = BVHTree.FromPolygons(co.tolist(), POLYS_ARM, all_triangles=False)
        inside = cut_depth(bvh, [np.array(PB["mixamorig:Spine1"].head)])
        arm = cut_depth(bvh, co[ARM_PTS], CUT_ARM)
        bvh_w, G = frame_bvh(f)
        coil = cut_depth(bvh_w, whip_points(G, np.eye(4), True)[:len(COIL_PTS)])
        pom = cut_depth(bvh_w, whip_points(G, np.eye(4), True)[len(COIL_PTS):])
        print("PROBE frame %d: spine inside %s; arm %.3f m (%d pts); coil %.3f (%d); pommel %.3f (%d); %.2f s"
              % (f, inside[1] == 1, arm[0], arm[1], coil[0], coil[1], pom[0], pom[1], time.time() - t0))
        hits = {}
        for vi in ARM_PTS:
            loc, nrm, fi, _ = bvh.find_nearest(Vector(co[vi]))
            d = -(Vector(co[vi]) - loc).dot(nrm)
            if d > CUT_ARM and cut_depth(bvh, [co[vi]], CUT_ARM)[1]:
                where = top_bone[POLYS_ARM[fi][0]]
                hits.setdefault(where, []).append(round(d * 100, 1))
                hits.setdefault("from " + top_bone[vi], []).append(1)
        print("  arm cut-in by region (cm):", {k: (len(v), max(v)) for k, v in hits.items()})
        whits = {}
        names = top_bone + ["Tail"] * len(tail.data.vertices)
        allp = POLYS_WHIP + POLYS_TAIL
        for label, pts in (("coil", whip_points(G, np.eye(4), True)[:len(COIL_PTS)]),
                           ("pommel", whip_points(G, np.eye(4), True)[len(COIL_PTS):])):
            for q in pts:
                if cut_depth(bvh_w, [q])[1]:
                    loc, nrm, fi, _ = bvh_w.find_nearest(Vector(q))
                    k_ = label + " in " + names[allp[fi][0]]
                    whits[k_] = whits.get(k_, 0) + 1
        print("  whip cut-in by region:", whits)
    sys.exit(0)
clips = argv[0].split(",") if argv and argv[0] else [a.name for a in bpy.data.actions if "frames" in a]
clips.sort(key=lambda c: c != "idle")   # idle first: the others pin to it
for c in clips:
    run(c)
rig.animation_data.action = bpy.data.actions.get("idle")
bpy.ops.wm.save_mainfile(compress=True)
print("WHIP_MOTION_SAVED", bpy.data.filepath)
