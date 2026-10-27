"""Rig the goblin archer for Mixamo clips, with his left hand closed round the bow (background Blender).

  blender -b goblin_archer_base.blend --factory-startup --python rig_goblin_archer.py -- <out.blend>

Starts from goblin_archer_base.blend (build_archer.py) and follows the rabble's
rig_goblin_rabble.py:
1. A Mixamo-named armature with finger bones placed on each hand's mesh: the archer's
   hands have three fingers and a thumb (Thumb, Index, Middle and Ring 1-4). Forearm
   twist bones, two bones down the middle of the cape and two for the front rag flap.
2. Skin: bone heat on the body shell and, separately, on the boots, which are his feet;
   geometric weights on the hands, which are part of the body shell and are cut from it
   past the wrist, so a finger moves only its own skin. The hood and the cape follow the
   head, neck, chest and collarbones, never the upper arms; below the quiver the cape
   hangs from its own bones, the upper one swung back by the trailing thigh (a driver)
   and further by the rig's `cape_back` (radians, keyed by a clip where a leg goes back
   into it). Belt, pouch, skull, fangs, necklace and eyes are rigid; the chest strap
   takes the weights of the chest under it.
3. Grips, solved on the skin as for the rabble: the left hand closes round the bow's
   grip, its handle laid across the palm, at the tilt and the place along the grip that
   close the three fingers best; the thumb closes the other way, toward the index
   finger. The right hand curls loosely round a rod RELAX_R thick. Each grip is a
   one-frame Action applied by Action constraints on the finger bones.
4. Props: the bow rides the `Bow` bone in the left hand, its string toward the elbow
   and its upper limb on the thumb's side, as it is held to shoot. The quiver rides the
   `Quiver` bone on the chest, slung diagonally across the back over the cape with its
   opening above the right shoulder, QUIVER_GAP clear of the cape and the hood. The
   arrow rides the `Arrow` bone in the right hand and is hidden while the rig's `arrow`
   property is 0. The `String` bone, a child of `Bow` at the middle of the string, pulls
   the string's middle vertices (a Hook modifier on the bow) when he draws. The left
   hand holds its turn on the bow whatever a clip does to the wrist (`BowHold`,
   `bow_hold`).
5. Controls as for the rabble, mirrored for the bow hand: `BowCtrl` follows the chest
   and `HandIK.L` follows `BowCtrl`; `bow_ik`, `draw_ik` and `leg_ik` (0 by default)
   switch on IK for the left arm, the right arm and the feet.
6. Standard pose: the skin stays bound to the T-pose, and the one-frame Action `stand`
   lets the arms hang. The left elbow is bent so the bow is held low beside the left
   leg, its upper limb raised forward: the left arm's angles (with the hand's roll) are
   searched for the bow BOW_SLOPE above level and as near upright beside him as it
   goes, with BOW_GAP clear of the body and the cape and the string clear of the hip.
Every control and helper bone is non-deforming and in its own bone collection; the
deforming bones are what a game export keeps.
"""
import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

H = 1.82 * 40 / 49
MX = "mixamorig:"
SIDES = (("Left", 1), ("Right", -1))
FINGERS = ("Index", "Middle", "Ring")   # three fingers and a thumb on each hand
WRIST_U = 0.655     # the wrist, distance from the centre line (both hands)
KNUCKLE_U = 0.738   # the knuckle row
PHALANX = (0.45, 0.30, 0.25)   # finger length shares of the three segments
RELAX_R = 0.02      # the right hand curls loosely round a rod this thick
BOW_SLOPE = 40      # degrees: the bow's upper limb raised forward in the standard pose
BOW_GAP = 0.02      # the bow keeps this far off the body and the cape in the standard pose
STRING_GAP = 0.003  # its string this far off the forearm, which it passes close to
QUIVER_TILT = 30    # degrees from upright, the opening toward the right shoulder
QUIVER_PITCH = 6    # degrees its top leans back from the cape's slope, away from the hood
HOOD_BACK = 0.6     # share of the head's turn the back of the hood leaves to the neck and chest
QUIVER_RIM = (-0.10, 1.17)   # x and height of the middle of the quiver's rim
QUIVER_GAP = 0.006  # the quiver keeps this far off the cape and the hood
QUIVER_TUBE = 0.73  # share of the quiver's length up to its rim (build_archer.py)
CAPE_FOLLOW = 0.6   # the cape swings back with the trailing thigh, this share of its swing
# The right arm's standard pose (degrees): collarbone lowered, upper arm out from
# hanging straight down and forward, elbow bent forward, wrist turned toward the little
# finger, hand rolled about its length (+: palm forward). The left arm's is searched
# (below) from the ranges in STAND_L.
STAND_R = {"collar": 6, "out": 12, "forward": 4, "elbow": 15, "wrist": 0, "roll": 0}
STAND_L = {"collar": (6,), "out": (10, 15, 20, 25), "forward": (0, 10, 20), "elbow": range(20, 81, 10),
           "wrist": (-10, 0, 10, 20), "roll": (-40, -20, 0, 20, 40)}
BOW_LEAN = 0.5      # cost per degree the bow leans in or out of upright beside him
# Joints of the left side read off the T-pose (front and side views on a 5 cm grid and
# the hand on a 1 cm grid); the right side mirrors x. The spine's depth is measured below.
J0 = {
    "Head": (0, 0.045, 1.20), "HeadTop_End": (0, 0.045, 1.42),
    "Shoulder": (0.04, 0.07, 1.10), "Arm": (0.195, 0.06, 1.065), "ForeArm": (0.415, 0.07, 1.062),
    "Hand": (WRIST_U, -0.012, 1.048),
    "UpLeg": (0.105, 0.06, 0.655), "Leg": (0.15, 0.05, 0.38), "Foot": (0.18, 0.10, 0.085),
    "ToeBase": (0.215, -0.02, 0.03), "Toe_End": (0.24, -0.095, 0.02),
}
SPINE_Z = {"Hips": 0.685, "Spine": 0.77, "Spine1": 0.865, "Spine2": 0.97, "Neck": 1.12}

argv = sys.argv[sys.argv.index("--") + 1:]
out_blend = Path(argv[0]).resolve()
sc = bpy.context.scene
body = bpy.data.objects["GoblinArcher"]
PROPS = {n: bpy.data.objects[n] for n in ("Bow", "Quiver", "Arrow")}
V = np.array([v.co[:] for v in body.data.vertices])
N = len(V)
assert abs(V[:, 2].max() - H) < 0.005 and abs(V[:, 2].min()) < 0.005


def unit(v):
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


def smooth_step(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def frame_matrix(origin, x, y, z):
    M = Matrix.Identity(4)
    for i in range(3):
        M[i][0], M[i][1], M[i][2], M[i][3] = x[i], y[i], z[i], origin[i]
    return M


def shells(bm):
    """The mesh's separate parts (vertex index arrays) through its edges."""
    bm.verts.ensure_lookup_table()
    island = np.full(len(bm.verts), -1)
    out = []
    for v in bm.verts:
        if island[v.index] >= 0:
            continue
        k, stack, part = len(out), [v], []
        island[v.index] = k
        while stack:
            w = stack.pop()
            part.append(w.index)
            for e in w.link_edges:
                o = e.other_vert(w)
                if island[o.index] < 0:
                    island[o.index] = k
                    stack.append(o)
        out.append(np.array(part))
    return out


# --- Shells ------------------------------------------------------------------
bm = bmesh.new()
bm.from_mesh(body.data)
parts = shells(bm)
bm.free()
by_size = sorted(range(len(parts)), key=lambda k: -len(parts[k]))
main, hood = by_size[0], by_size[1]
kind = {}
for k, p in enumerate(parts):
    P = V[p]
    lo, hi, c = P.min(0), P.max(0), P.mean(0)
    if k == main:
        kind[k] = "body"
    elif k == hood:
        kind[k] = "hood"        # the hood and the cape, one open sheet
    elif lo[2] < 0.01:
        kind[k] = "boot"
    elif lo[2] > 1.1 and hi[1] < -0.1:
        kind[k] = "head"        # the eyes
    elif hi[2] - lo[2] > 0.25 and lo[2] > 0.75:
        kind[k] = "strap"       # the chest strap
    elif hi[2] - lo[2] > 0.25 and c[1] < 0:
        kind[k] = "flap_F"      # the front rag flap
    elif lo[2] > 0.78:
        kind[k] = "chest"       # the necklace, its fangs and the strap's buckle
    elif lo[2] > 0.45 and hi[2] < 0.80:
        kind[k] = "belt"        # belt, skull, pouch and the fangs on the belt
    else:
        kind[k] = "other"
counts = {}
for k in kind.values():
    counts[k] = counts.get(k, 0) + 1
print("RIG_SHELLS", counts)
assert V[parts[hood], 2].max() > H - 0.01 and counts.get("boot") == 2 and counts.get("flap_F") == 1
assert counts.get("strap") == 1 and counts.get("head") == 2


body.data.calc_loop_triangles()
TRIS = np.zeros(3 * len(body.data.loop_triangles), dtype=np.int64)
body.data.loop_triangles.foreach_get("vertices", TRIS)
TRIS = TRIS.reshape(-1, 3)
EDGES = np.zeros(2 * len(body.data.edges), dtype=np.int64)
body.data.edges.foreach_get("vertices", EDGES)
EDGES = EDGES.reshape(-1, 2)
in_main = np.zeros(N, bool)
in_main[parts[main]] = True
T3 = TRIS[in_main[TRIS].all(1)]
bvh = BVHTree.FromPolygons([Vector(p) for p in V], T3.tolist())
BODY_TRIS = TRIS.tolist()


def torso_mid(z):
    """Halfway between the front and the back of the body (its main shell) at height z."""
    ys = []
    for x in (-0.03, 0.0, 0.03):
        f = bvh.ray_cast(Vector((x, -1.0, z)), Vector((0, 1, 0)), 2.0)[0]
        b = bvh.ray_cast(Vector((x, 1.0, z)), Vector((0, -1, 0)), 2.0)[0]
        if f is not None and b is not None:
            ys.append((f.y + b.y) / 2)
    return float(np.mean(ys))


J = {}
for n, z in SPINE_Z.items():
    J[n] = Vector((0, torso_mid(z), z))
J["Head"], J["HeadTop_End"] = Vector(J0["Head"]), Vector(J0["HeadTop_End"])
for side, s in SIDES:
    for n in ("Shoulder", "Arm", "ForeArm", "Hand", "UpLeg", "Leg", "Foot", "ToeBase", "Toe_End"):
        x, y, z = J0[n]
        J[side + n] = Vector((s * x, y, z))
print("RIG_SPINE", {n: [round(c, 3) for c in J[n]] for n in SPINE_Z})


# --- Hands: fingers, thumb and palm ----------------------------------------------
def components(mask):
    """Connected parts of the vertices in `mask` (through the mesh's edges), largest first."""
    lab = np.where(mask, np.arange(N), N)
    e = EDGES[mask[EDGES[:, 0]] & mask[EDGES[:, 1]]]
    while True:   # each vertex takes the smallest label among its neighbours, until none changes
        new = lab.copy()
        m = np.minimum(lab[e[:, 0]], lab[e[:, 1]])
        np.minimum.at(new, e[:, 0], m)
        np.minimum.at(new, e[:, 1], m)
        if (new == lab).all():
            break
        lab = new
    return sorted((np.nonzero(lab == k)[0] for k in np.unique(lab[mask])), key=len, reverse=True)


def measure_hand(side, s):
    """Joints (armature space) and radii of the three fingers and the thumb. The hand is
    the body shell past the wrist (a little short of it, for the blend into the forearm)."""
    U = V[:, 0] * s
    in_hand = in_main & (U > WRIST_U - 0.03)
    idx = np.nonzero(in_hand)[0]
    for u_web in np.arange(0.745, 0.79, 0.002):     # past the webs the three fingers are apart
        comps = [c for c in components(in_hand & (U > u_web)) if len(c) >= 12]
        if len(comps) == len(FINGERS):
            break
    assert len(comps) == len(FINGERS), f"{side} hand: the fingers were not found"
    comps.sort(key=lambda c: V[c, 1].mean())         # index (front) to ring
    in_fingers = np.zeros(N, bool)
    hand = {"idx": idx, "fingers": {}}
    for name, c in zip(FINGERS, comps):
        in_fingers[c] = True
        F = np.c_[U[c], V[c, 1:]]
        tip_u = F[:, 0].max()
        L = tip_u - 0.004 - KNUCKLE_U
        pts, rad = [], []
        for u in (KNUCKLE_U, KNUCKLE_U + PHALANX[0] * L, KNUCKLE_U + (PHALANX[0] + PHALANX[1]) * L, tip_u - 0.004):
            uu = min(max(u, u_web + 0.008), tip_u - 0.008)   # by the knuckle: the finger just past the web
            d = np.abs(F[:, 0] - uu)
            q = F[d <= max(0.005, np.sort(d)[9])]    # within 5 mm, at least the ten nearest
            pts.append((s * u, (q[:, 1].min() + q[:, 1].max()) / 2, (q[:, 2].min() + q[:, 2].max()) / 2))
            rad.append(min(np.ptp(q[:, 1]), np.ptp(q[:, 2])) / 2)
        hand["fingers"][name] = (np.array(pts), np.array(rad))
    # Thumb: what hangs below and in front of the palm. Its two phalanges lie along its axis.
    th = components(in_hand & ~in_fingers & (U > WRIST_U + 0.02) & (V[:, 1] < -0.055) & (V[:, 2] < 1.02))[0]
    T = np.c_[U[th], V[th, 1:]]
    cen = T.mean(0)
    ax = np.linalg.svd(T - cen)[2][0]
    ax = ax if ax[0] > 0 else -ax
    t = (T - cen) @ ax
    trad = float(np.median(np.linalg.norm((T - cen) - np.outer(t, ax), axis=1)))
    mcp, tip = cen + ax * (t.min() + 0.006), cen + ax * (t.max() - 0.004)
    # The metacarpal starts in the heel of the hand, by the wrist and in from the thumb.
    u_cmc = WRIST_U + 0.012
    q = V[in_hand & ~in_fingers & (np.abs(U - u_cmc) < 0.008)]
    cmc = np.array([u_cmc, mcp[1] + 0.012, (q[:, 2].min() + q[:, 2].max()) / 2])
    hand["thumb"] = (np.array([cmc, mcp, mcp + 0.55 * (tip - mcp), tip]) * np.array([s, 1, 1]), trad)
    hand["in_fingers"], hand["thumb_idx"] = in_fingers, th
    return hand


HANDS = {side: measure_hand(side, s) for side, s in SIDES}
for side, s in SIDES:
    for name, (pts, rad) in HANDS[side]["fingers"].items():
        for i in range(4):
            J[f"{side}Hand{name}{i + 1}"] = Vector(pts[i])
        print("RIG_FINGER", side, name, "length %.3f" % np.linalg.norm(pts[3] - pts[0]), "radii", np.round(rad, 4),
              "y %.3f" % pts[0][1])
    tj, trad = HANDS[side]["thumb"]
    for i in range(4):
        J[f"{side}HandThumb{i + 1}"] = Vector(tj[i])
    print("RIG_THUMB", side, np.round(tj, 3).tolist(), "radius %.4f" % trad)


def seg_d(p, a, b):
    ab = b - a
    t = np.clip(((p - a) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(p - (a + np.outer(t, ab)), axis=1)


CHAINS = ("Thumb",) + FINGERS


def hand_lbs(side, s):
    """Skin weights of the hand: each vertex to the nearest bones of its own finger
    (inverse distance), the palm to the hand; and k, the share left to the hand at the wrist
    (the rest goes to the forearm's twist bone)."""
    P = V[HANDS[side]["idx"]]
    wrist = np.array(J[side + "Hand"])
    fan = [(wrist, np.array(J[f"{side}Hand{f}1"])) for f in CHAINS]
    names, dists = [MX + side + "Hand"], [np.min([seg_d(P, a, b) for a, b in fan], 0)]
    for f in CHAINS:
        for i in range(1, 4):
            names.append(f"{MX}{side}Hand{f}{i}")
            dists.append(seg_d(P, np.array(J[f"{side}Hand{f}{i}"]), np.array(J[f"{side}Hand{f}{i + 1}"])))
    R = 1.0 / (np.stack(dists, 1) + 1e-4) ** 8
    R /= R.sum(1, keepdims=True)
    # Three bones at most (the twist bone makes four), as the skin keeps: the grips are
    # solved with the weights the Armature modifier will use.
    R[np.arange(len(R))[:, None], np.argsort(-R, axis=1)[:, 3:]] = 0
    R[R < 0.02] = 0
    R /= R.sum(1, keepdims=True)
    return names, R, smooth_step((P[:, 0] * s - (WRIST_U - 0.02)) / 0.04)


# --- Grips -------------------------------------------------------------------------
# Each grip is solved on the skin itself: points on the hand's triangles move with the
# skin weights above (linear blend skinning, as the Armature modifier does) and are
# tested against the prop's surface, sampled as a signed distance field.
DEG = math.pi / 180


def rot_mats(axis, ang):
    """Rotations (M, 3, 3) about one unit axis (3,) or one axis per angle (M, 3), by angles (M,)."""
    axis = np.broadcast_to(axis, (len(ang), 3))
    K = np.zeros((len(ang), 3, 3))
    K[:, 0, 1], K[:, 0, 2], K[:, 1, 2] = -axis[:, 2], axis[:, 1], -axis[:, 0]
    K = K - K.transpose(0, 2, 1)
    s, c = np.sin(ang)[:, None, None], np.cos(ang)[:, None, None]
    return np.eye(3)[None] + s * K + (1 - c) * (K @ K)


def seg_dist(Q, A, Bp):
    """Distances (M, S, K) from points Q (M, S, 3) to segments A-B (K, 3)."""
    ab = Bp - A
    q = Q[:, :, None, :] - A[None, None]
    t = np.clip((q * ab[None, None]).sum(-1) / (ab ** 2).sum(-1)[None, None], 0, 1)
    return np.linalg.norm(q - t[..., None] * ab[None, None], axis=-1)


class PropField:
    """Signed distance to a prop's surface (negative inside), sampled every 2 mm in the prop's
    own space between heights z0 and z1 and read back trilinearly. `keep` leaves out the
    vertices (and their faces) that the hand never meets, such as the bow's string."""

    def __init__(self, obj, z0, z1, keep=None, step=0.002):
        me = obj.data
        P = np.array([v.co[:] for v in me.vertices])
        keep = np.ones(len(P), bool) if keep is None else keep(P)
        faces = [list(p.vertices) for p in me.polygons if keep[list(p.vertices)].all()]
        tree = BVHTree.FromPolygons([v.co.copy() for v in me.vertices], faces)
        near = P[keep & (P[:, 2] > z0 - 0.02) & (P[:, 2] < z1 + 0.02)]
        self.lo = np.r_[near[:, :2].min(0) - 0.016, z0]
        self.n = np.ceil((np.r_[near[:, :2].max(0) + 0.016, z1] - self.lo) / step).astype(int) + 1
        self.step = step
        self.G = np.empty(self.n)
        axes = [self.lo[i] + step * np.arange(self.n[i]) for i in range(3)]
        for i, x in enumerate(axes[0]):
            for j, y in enumerate(axes[1]):
                for k, z in enumerate(axes[2]):
                    p = Vector((x, y, z))
                    loc, nrm, _, dist = tree.find_nearest(p)
                    self.G[i, j, k] = dist if (p - loc).dot(nrm) >= 0 else -dist

    def __call__(self, Q):
        g = (Q - self.lo) / self.step
        gc = np.clip(g, 0, self.n - 1.000001)
        out = np.linalg.norm(g - gc, axis=-1) * self.step    # beyond the grid: add the distance to it
        i = gc.astype(int)
        f = gc - i
        val = 0.0
        for dx in (0, 1):
            for dy in (0, 1):
                for dz in (0, 1):
                    w = ((f[..., 0] if dx else 1 - f[..., 0]) * (f[..., 1] if dy else 1 - f[..., 1])
                         * (f[..., 2] if dz else 1 - f[..., 2]))
                    val = val + w * self.G[i[..., 0] + dx, i[..., 1] + dy, i[..., 2] + dz]
        return val + out


class Rod:
    """A round rod along z, what the right hand curls round for a relaxed hand."""

    def __init__(self, r):
        self.r = r

    def __call__(self, Q):
        return np.linalg.norm(Q[..., :2], axis=-1) - self.r


class PalmField:
    """Height of the palm's underside (rays cast up at the triangles a grip leaves in place);
    `inside` gives how far points are above it, into the palm, or -1 off the palm."""

    def __init__(self, side, s, still):
        idx = HANDS[side]["idx"]
        loc = np.full(N, -1)
        loc[idx] = np.arange(len(idx))
        tri = TRIS[(loc[TRIS] >= 0).all(1)]
        tri = tri[(still[loc[tri]] > 0.5).all(1)]
        tree = BVHTree.FromPolygons([Vector(p) for p in V], tri.tolist())
        self.s, self.step, self.u0, self.y0 = s, 0.003, WRIST_U - 0.025, -0.13
        us = self.u0 + self.step * np.arange(int((KNUCKLE_U + 0.02 - self.u0) / self.step) + 1)
        ys = self.y0 + self.step * np.arange(int(0.22 / self.step) + 1)
        self.Z = np.full((len(us), len(ys)), np.nan)
        for i, u in enumerate(us):
            for j, y in enumerate(ys):
                hit = tree.ray_cast(Vector((s * u, y, 0.5)), Vector((0, 0, 1)), 1.0)[0]
                if hit is not None:
                    self.Z[i, j] = hit.z

    def inside(self, Q):
        g0 = (Q[..., 0] * self.s - self.u0) / self.step
        g1 = (Q[..., 1] - self.y0) / self.step
        i, j = np.floor(g0).astype(int), np.floor(g1).astype(int)
        ok = (i >= 0) & (j >= 0) & (i < self.Z.shape[0] - 1) & (j < self.Z.shape[1] - 1)
        i, j = np.clip(i, 0, self.Z.shape[0] - 2), np.clip(j, 0, self.Z.shape[1] - 2)
        fi, fj = g0 - i, g1 - j
        Z = self.Z
        z = (Z[i, j] * (1 - fi) * (1 - fj) + Z[i + 1, j] * fi * (1 - fj)
             + Z[i, j + 1] * (1 - fi) * fj + Z[i + 1, j + 1] * fi * fj)
        out = Q[..., 2] - z
        return np.where(ok & np.isfinite(out), out, -1.0)


def spread_pick(P, k):
    """k of the points P, each as far as possible from those picked before: an even cover."""
    if len(P) <= k:
        return np.arange(len(P))
    pick = [int(np.argmin(P[:, 0]))]
    d = np.linalg.norm(P - P[pick[0]], axis=1)
    for _ in range(k - 1):
        pick.append(int(np.argmax(d)))
        d = np.minimum(d, np.linalg.norm(P - P[pick[-1]], axis=1))
    return np.array(pick)


def moved(Rs, ts, P, Wp):
    """Points P (S, 3) moved by segment transforms Rs (M, K, 3, 3), ts (M, K, 3) with weights
    Wp (S, 1 + K), of which column 0 stays in place: (M, S, 3)."""
    Q = Wp[None, :, 0, None] * P[None]
    for j in range(Rs.shape[1]):
        Q = Q + Wp[None, :, j + 1, None] * (np.einsum("mab,sb->msa", Rs[:, j], P) + ts[:, j, None])
    return Q


NF = len(CHAINS)


class GripHand:
    """One hand's skin samples, frame, palm and joint chains."""

    def __init__(self, side, s):
        self.side, self.s = side, s
        hd = HANDS[side]
        names, R, k = hand_lbs(side, s)
        Wv = R * k[:, None]
        Wv[:, 0] += 1 - k                       # the forearm's share stays in place like the hand's
        idx = hd["idx"]
        loc = np.full(N, -1)
        loc[idx] = np.arange(len(idx))
        tri = loc[TRIS[(loc[TRIS] >= 0).all(1)]]
        P, Wl = [V[idx]], [Wv]
        for b in ((1, 1, 0), (0, 1, 1), (1, 0, 1), (1, 1, 1), (4, 1, 1), (1, 4, 1), (1, 1, 4)):
            b = np.array(b, float) / sum(b)
            P.append(np.einsum("j,tjk->tk", b, V[idx][tri]))
            Wl.append(np.einsum("j,tjk->tk", b, Wv[tri]))
        self.P, self.W = np.concatenate(P), np.concatenate(Wl)
        self.palm = PalmField(side, s, Wv[:, 0])
        # Frame: along the hand (d), the palm's normal (n, out of the palm), toward the thumb (t).
        palm = idx[~hd["in_fingers"][idx] & ~np.isin(idx, hd["thumb_idx"]) & (V[idx, 0] * s > WRIST_U)]
        n = np.linalg.svd(V[palm] - V[palm].mean(0))[2][2]
        self.n = n if n[2] < 0 else -n
        # Along the hand: the fingers' mean direction in the palm's plane, so the spread is
        # even about it.
        d = sum(unit(np.array(J[f"{side}Hand{f}4"] - J[f"{side}Hand{f}1"])) for f in FINGERS)
        self.d = unit(d - (d @ self.n) * self.n)
        t = unit(np.cross(self.n, self.d))
        self.t = t if t[1] < 0 else -t
        self.still = self.P[self.W[:, 0] > 0.8]
        rest_in = self.palm.inside(self.P)
        self.chains, self.coarse = {}, {}
        for ci, f in enumerate(CHAINS):
            w = self.W[:, 1 + 3 * ci:4 + 3 * ci]
            m = w.sum(1) > 0.05
            Wp = np.c_[1 - w[m].sum(1), w[m]]
            seg = np.argmax(Wp, 1)
            ch = (self.P[m], Wp, seg, rest_in[m] < -0.008)
            self.chains[ci] = ch
            # The coarse search sees an even cover of every segment, the skin by the knuckle
            # (mostly the hand's) too, so it ranks placements as the full sample set does.
            pick = np.concatenate([np.nonzero(seg == i)[0][spread_pick(self.P[m][seg == i], 24 if ci else 16)]
                                   for i in (0, 1, 2, 3)])
            self.coarse[ci] = tuple(a[pick] for a in ch)
        self.fj = {ci: np.array([J[f"{side}Hand{f}{i}"] for i in range(1, 5)]) for ci, f in enumerate(CHAINS)}
        self.frad = {ci: hd["fingers"][f][1] for ci, f in enumerate(FINGERS, 1)}
        self.fk, self.phi = {}, {}
        for ci in range(1, NF):
            Jf = self.fj[ci]
            df = unit(Jf[3] - Jf[0])
            self.fk[ci] = unit(np.cross(df, self.n))          # flexion turns the finger toward the palm side
            dp = unit(df - (df @ self.n) * self.n)
            # Closing the hand draws the spread fingers in, most of the way to parallel.
            self.phi[ci] = 0.7 * math.atan2(self.n @ np.cross(dp, self.d), dp @ self.d)
        tj, self.trad = hd["thumb"]
        self.td = unit(tj[3] - tj[0])
        pc = V[palm].mean(0)
        dt = unit(tj[3] - tj[1])
        m = pc - tj[1]
        self.tk = unit(np.cross(dt, unit(m - (m @ dt) * dt)))   # the thumb flexes toward the palm
        print("RIG_HANDFRAME", side, "d", np.round(self.d, 3).tolist(), "n", np.round(self.n, 3).tolist(),
              "spread in (deg)", [round(math.degrees(self.phi[ci]), 1) for ci in range(1, NF)],
              "samples", len(self.P))


def finger_pose(hand, ci, T):
    """Rotations (M, 3, 3, 3) and translations (M, 3, 3) of a finger's three segments: drawn in
    by its spread angle about the palm's normal, then flexed by T (M, 3) at each joint."""
    Jf, k = hand.fj[ci], hand.fk[ci]
    Rn = rot_mats(hand.n, np.array([hand.phi[ci]]))[0]
    Rs, ts = [], []
    cum = np.zeros(len(T))
    for i in range(3):
        cum = cum + T[:, i]
        Ri = Rn @ rot_mats(k, cum)
        ts.append(Jf[0] - Ri @ Jf[0] if i == 0 else Rs[-1] @ Jf[i] + ts[-1] - Ri @ Jf[i])
        Rs.append(Ri)
    return np.stack(Rs, 1), np.stack(ts, 1)


def thumb_pose(hand, X):
    """X (M, 5): the metacarpal's rotation vector, then the flexions of the two phalanges."""
    Jt, k = hand.fj[0], hand.tk
    ang = np.linalg.norm(X[:, :3], axis=1)
    R1 = rot_mats(X[:, :3] / np.maximum(ang, 1e-9)[:, None], ang)
    t1 = Jt[0] - R1 @ Jt[0]
    R2 = R1 @ rot_mats(k, X[:, 3])
    t2 = R1 @ Jt[1] + t1 - R2 @ Jt[1]
    R3 = R1 @ rot_mats(k, X[:, 3] + X[:, 4])
    t3 = R2 @ Jt[2] + t2 - R3 @ Jt[2]
    return np.stack([R1, R2, R3], 1), np.stack([t1, t2, t3], 1)


def finger_energy(hand, ci, T, sdf, coarse=False):
    """Low when every phalanx just touches the handle, nothing passes into it or into the palm,
    and the end joint bends about 0.7 times the middle one, as fingers do."""
    P, Wp, seg, palm_ok = (hand.coarse if coarse else hand.chains)[ci]
    E = np.zeros(len(T))
    for c in range(0, len(T), 3000):
        Tc = T[c:c + 3000]
        Q = moved(*finger_pose(hand, ci, Tc), P, Wp)
        sd = sdf(Q) * 1000
        e = 50 * (np.maximum(0, 0.3 - sd) ** 2).sum(1)
        for i in (1, 2, 3):
            e += np.maximum(0, sd[:, seg == i].min(1) - 0.3) ** 2
        m = palm_ok & (seg >= 2)
        e += 50 * (np.maximum(0, hand.palm.inside(Q[:, m]) * 1000 + 0.3) ** 2).sum(1)
        Td = Tc / DEG
        e += 0.005 * (Td[:, 2] - 0.7 * Td[:, 1]) ** 2 + 0.00005 * (Td ** 2).sum(1)
        E[c:c + 3000] = e
    return E


def thumb_energy(hand, X, sdf, caps, target, coarse=False):
    """Low when the thumb wraps the handle without passing into it, the fingers or the palm,
    its last phalanx resting on the index finger's middle one (or on the handle)."""
    P, Wp, seg, palm_ok = (hand.coarse if coarse else hand.chains)[0]
    E = np.zeros(len(X))
    for c in range(0, len(X), 2000):
        Xc = X[c:c + 2000]
        Q = moved(*thumb_pose(hand, Xc), P, Wp)
        sd = sdf(Q) * 1000
        sf = (seg_dist(Q, caps[0], caps[1]) - caps[2]).min(-1) * 1000
        e = 50 * (np.maximum(0, 0.3 - sd) ** 2).sum(1)
        e += 50 * (np.maximum(0, 0.3 - sf[:, seg >= 2]) ** 2).sum(1)
        m = palm_ok & (seg >= 2)
        e += 50 * (np.maximum(0, hand.palm.inside(Q[:, m]) * 1000 + 0.3) ** 2).sum(1)
        e += 2 * np.maximum(0, np.minimum(sd, sf)[:, seg == 3].min(1) - 0.3) ** 2
        e += np.maximum(0, sd[:, seg == 2].min(1) - 0.3) ** 2
        e += 0.02 * (np.linalg.norm(Q[:, seg == 3].mean(1) - target, axis=-1) * 1000) ** 2
        Xd = Xc / DEG
        twist = (Xc[:, :3] @ hand.td) / DEG
        e += 0.0005 * (Xd ** 2).sum(1) + 0.01 * np.maximum(0, np.abs(twist) - 20) ** 2
        E[c:c + 2000] = e
    return E


def pattern(f, x, steps, lo, hi):
    """Compass search: try a step either way along each coordinate, keep any improvement."""
    e = float(f(x[None])[0])
    for step in steps:
        while True:
            cand = np.repeat(x[None], 2 * len(x), 0)
            for i in range(len(x)):
                cand[2 * i, i] += step
                cand[2 * i + 1, i] -= step
            cand = np.clip(cand, lo, hi)
            ec = f(cand)
            j = int(np.argmin(ec))
            if ec[j] >= e - 1e-9:
                break
            x, e = cand[j].copy(), float(ec[j])
    return x, e


FLEX_GRID = np.stack(np.meshgrid(np.arange(-7.5, 90.1, 7.5), np.arange(0, 105.1, 7.5), np.arange(0, 82.6, 7.5),
                                 indexing="ij"), -1).reshape(-1, 3) * DEG
FLEX_LIM = (np.array([-8, 0, 0]) * DEG, np.array([95, 110, 85]) * DEG)   # a gripping knuckle hardly overextends
g = np.arange(-90, 90.1, 15) * DEG
gf = np.arange(0, 75.1, 15) * DEG
THUMB_ROT = np.stack(np.meshgrid(g, g, g, indexing="ij"), -1).reshape(-1, 3)
THUMB_ROT = THUMB_ROT[np.linalg.norm(THUMB_ROT, axis=1) <= 105 * DEG]
THUMB_FLEX = np.stack(np.meshgrid(gf, gf, indexing="ij"), -1).reshape(-1, 2)
THUMB_LIM = (np.array([-120, -120, -120, -10, -10]) * DEG, np.array([120, 120, 120, 80, 85]) * DEG)


def place(hand, U, tau, sigma, field):
    """The handle's frame: its axis across the palm (crossing the middle finger's line at U,
    turned tau toward the wrist on the little finger's side), slid sigma along itself and
    pressed up until it just touches the palm. Columns x, y, z of R: z the axis toward the
    thumb, x toward the wrist (the bow's string side); o the prop's origin."""
    a = math.cos(tau) * hand.t + math.sin(tau) * hand.d
    x = -unit(hand.d - (hand.d @ a) * a)
    R = np.stack([x, np.cross(a, x), a], 1)
    ref = np.array(J[f"{hand.side}HandMiddle1"]) + (U - KNUCKLE_U) * hand.d + sigma * a
    lo, hi = 0.0, 0.10
    for _ in range(30):
        h = (lo + hi) / 2
        if field((hand.still - (ref + h * hand.n)) @ R).min() < 0.0002:
            lo = h
        else:
            hi = h
    return R, ref + hi * hand.n


def solve_thumb(hand, Ts, sdf, R, o):
    caps_a, caps_b, caps_r = [], [], []
    for ci in range(1, NF):
        Rs, ts = finger_pose(hand, ci, Ts[ci][None])
        Jf = hand.fj[ci]
        jp = [Jf[0]] + [Rs[0, i] @ Jf[i + 1] + ts[0, i] for i in range(3)]
        rad = hand.frad[ci]
        for i in range(3):
            caps_a.append(jp[i])
            caps_b.append(jp[i + 1])
            caps_r.append((rad[i] + rad[i + 1]) / 2)
        if ci == 1:
            mid = (jp[1] + jp[2]) / 2
            out = mid - o
            out = unit(out - (out @ R[:, 2]) * R[:, 2])
            target = mid + out * ((rad[1] + rad[2]) / 2 + 0.8 * hand.trad)
    caps = (np.array(caps_a), np.array(caps_b), np.array(caps_r))
    frame = np.stack([hand.t, hand.d, hand.n], 1)
    X = np.c_[np.repeat(THUMB_ROT @ frame.T, len(THUMB_FLEX), 0), np.tile(THUMB_FLEX, (len(THUMB_ROT), 1))]
    E = thumb_energy(hand, X, sdf, caps, target, coarse=True)
    x0 = X[int(np.argmin(E))]
    f = lambda Xc: thumb_energy(hand, Xc, sdf, caps, target)
    best = pattern(f, x0, np.array([8, 4, 2, 1, 0.5]) * DEG, *THUMB_LIM)
    for k in np.argsort(E)[1:40]:           # a second start well away from the first
        if np.linalg.norm(X[k] - x0) > 30 * DEG:
            other = pattern(f, X[k], np.array([8, 4, 2, 1, 0.5]) * DEG, *THUMB_LIM)
            if other[1] < best[1]:
                best = other
            break
    return best[0], best[1], target


def grip_report(hand, Ts, X, sdf, target, label):
    """Closest approach of each phalanx to the handle (mm; negative is inside), the angles and
    how far the thumb's last phalanx is from where it should rest."""
    out = {}
    for ci, f in enumerate(CHAINS):
        P, Wp, seg, _ = hand.chains[ci]
        Rs, ts = thumb_pose(hand, X[None]) if ci == 0 else finger_pose(hand, ci, Ts[ci][None])
        Q = moved(Rs, ts, P, Wp)
        sd = sdf(Q)[0] * 1000
        ang = (X[:3] / DEG).tolist() + (X[3:] / DEG).tolist() if ci == 0 else (Ts[ci] / DEG).tolist()
        extra = " to its rest %.1f mm" % (np.linalg.norm(Q[0, seg == 3].mean(0) - target) * 1000) if ci == 0 else ""
        out[f] = [round(float(sd[seg == i].min()), 1) for i in (1, 2, 3)]
        print("RIG_GRIP", label, f, "angles", np.round(ang, 1).tolist(), "closest per phalanx (mm)",
              out[f], "deepest %.1f" % sd.min() + extra)
    return out


def solve_grip(hand, field, sigmas, label, refine=6):
    tried = []
    for U in np.arange(KNUCKLE_U - 0.05, KNUCKLE_U + 0.0001, 0.01):
        for tau in (6, 12, 18):
            for sigma in sigmas:
                R, o = place(hand, U, tau * DEG, sigma, field)
                sdf = lambda Q, R=R, o=o: field((Q - o) @ R)
                E, Ts = 2.0 * (sigma * 1000) ** 2 / 1000, {}
                for ci in range(1, NF):
                    e = finger_energy(hand, ci, FLEX_GRID, sdf, coarse=True)
                    E += float(e.min())
                    Ts[ci] = FLEX_GRID[int(np.argmin(e))]
                tried.append((E, U, tau, sigma, R, o, Ts))
    tried.sort(key=lambda r: r[0])
    best = None
    for _, U, tau, sigma, R, o, Ts in tried[:refine]:
        sdf = lambda Q, R=R, o=o: field((Q - o) @ R)
        E = 2.0 * (sigma * 1000) ** 2 / 1000
        for ci in range(1, NF):
            Ts[ci], e = pattern(lambda T, ci=ci: finger_energy(hand, ci, T, sdf), Ts[ci],
                                np.array([4, 2, 1, 0.5]) * DEG, *FLEX_LIM)
            E += e
        X, et, target = solve_thumb(hand, Ts, sdf, R, o)
        print("RIG_PLACE", label, "U %.3f tilt %d slide %+.3f" % (U, tau, sigma), "fingers %.1f thumb %.1f" % (E, et))
        if best is None or E + et < best["E"]:
            best = {"E": E + et, "U": float(U), "tilt": tau, "slide": sigma, "R": R, "o": o, "Ts": dict(Ts), "X": X,
                    "side": hand.side, "target": target}
    sdf = lambda Q: field((Q - best["o"]) @ best["R"])
    best["closest_mm"] = grip_report(hand, best["Ts"], best["X"], sdf, best["target"], label)
    # The pose of each finger bone, as a rigid transform of its rest (armature space).
    D = {}
    for ci, f in enumerate(CHAINS):
        Rs, ts = thumb_pose(hand, best["X"][None]) if ci == 0 else finger_pose(hand, ci, best["Ts"][ci][None])
        for i in range(3):
            M = np.eye(4)
            M[:3, :3], M[:3, 3] = Rs[0, i], ts[0, i]
            D[f"{MX}{hand.side}Hand{f}{i + 1}"] = M
    best["D"] = D
    F = np.eye(4)
    F[:3, :3], F[:3, 3] = best["R"], best["o"]
    best["frame"] = Matrix(F.tolist())
    return best


BOW_V = np.array([v.co[:] for v in PROPS["Bow"].data.vertices])
STRING_X = float(BOW_V[np.abs(BOW_V[:, 2]) < 0.03, 0].max())   # the string, at the brace height
GRIPS = {"Bow": solve_grip(GripHand("Left", 1), PropField(PROPS["Bow"], -0.10, 0.10, lambda P: P[:, 0] < STRING_X - 0.05),
                           (-0.02, -0.01, 0.0, 0.01, 0.02), "Bow"),
         "Relax": solve_grip(GripHand("Right", -1), Rod(RELAX_R), (0.0,), "Relax")}


# --- Armature ------------------------------------------------------------------
arm_data = bpy.data.armatures.new("GoblinArcherRig")
rig = bpy.data.objects.new("GoblinArcherRig", arm_data)
sc.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
EB = arm_data.edit_bones


def new_bone(name, head, tail, parent=None, connect=False, roll=None):
    b = EB.new(name)
    b.head, b.tail = Vector(head), Vector(tail)
    if parent:
        b.parent = EB[parent]
        b.use_connect = connect and (b.head - b.parent.tail).length < 1e-5
    if roll is not None:
        b.align_roll(Vector(roll))
    return b


DOWN, FRONT = (0, 0, -1), (0, -1, 0)
CHAIN = [("Hips", None, "Spine"), ("Spine", "Hips", "Spine1"), ("Spine1", "Spine", "Spine2"),
         ("Spine2", "Spine1", "Neck"), ("Neck", "Spine2", "Head"), ("Head", "Neck", "HeadTop_End")]
for name, parent, tail in CHAIN:
    new_bone(MX + name, J[name], J[tail], parent and MX + parent, True, FRONT)
new_bone(MX + "HeadTop_End", J["HeadTop_End"], J["HeadTop_End"] + Vector((0, 0, 0.05)), MX + "Head", True, FRONT)
for side, s in SIDES:
    new_bone(MX + side + "Shoulder", J[side + "Shoulder"], J[side + "Arm"], MX + "Spine2", False, DOWN)
    new_bone(MX + side + "Arm", J[side + "Arm"], J[side + "ForeArm"], MX + side + "Shoulder", True, DOWN)
    new_bone(MX + side + "ForeArm", J[side + "ForeArm"], J[side + "Hand"], MX + side + "Arm", True, DOWN)
    new_bone(MX + side + "Hand", J[side + "Hand"], J[side + "HandMiddle1"], MX + side + "ForeArm", True, DOWN)
    for f in CHAINS:
        par = MX + side + "Hand"
        for i in range(1, 4):
            nm = f"{MX}{side}Hand{f}{i}"
            new_bone(nm, J[f"{side}Hand{f}{i}"], J[f"{side}Hand{f}{i + 1}"], par, i > 1, DOWN)
            par = nm
        tip = J[f"{side}Hand{f}4"]
        new_bone(f"{MX}{side}Hand{f}4", tip, tip + (tip - J[f"{side}Hand{f}3"]).normalized() * 0.012, par, True, DOWN)
    new_bone(side + "ForeArmTwist", J[side + "ForeArm"].lerp(J[side + "Hand"], 0.45), J[side + "Hand"],
             MX + side + "ForeArm", False, DOWN)
    new_bone(MX + side + "UpLeg", J[side + "UpLeg"], J[side + "Leg"], MX + "Hips", False, FRONT)
    new_bone(MX + side + "Leg", J[side + "Leg"], J[side + "Foot"], MX + side + "UpLeg", True, FRONT)
    new_bone(MX + side + "Foot", J[side + "Foot"], J[side + "ToeBase"], MX + side + "Leg", True, FRONT)
    new_bone(MX + side + "ToeBase", J[side + "ToeBase"], J[side + "Toe_End"], MX + side + "Foot", True, FRONT)
    te = J[side + "Toe_End"]
    new_bone(MX + side + "Toe_End", te, te + (te - J[side + "ToeBase"]).normalized() * 0.03, MX + side + "ToeBase",
             True, FRONT)


def part_points(k_name, z_list, x_half=None):
    """Points down the middle of a shell kind: its median depth at each height."""
    p = np.concatenate([parts[k] for k, v in kind.items() if v == k_name])
    P = V[p]
    if x_half is not None:
        P = P[np.abs(P[:, 0]) < x_half]
    pts = []
    for z in z_list:
        q = P[np.abs(P[:, 2] - z) < 0.03]
        pts.append(Vector((0, float(np.median(q[:, 1])), z)))
    return pts


# Front rag flap: two bones from the belt down.
fp = V[np.concatenate([parts[k] for k, v in kind.items() if v == "flap_F"])]
z0, z1 = fp[:, 2].max() - 0.02, fp[:, 2].min()
p0, p1, p2 = part_points("flap_F", (z0, (z0 + z1) / 2, z1))
new_bone("FlapFront1", p0, p1, MX + "Hips", False, FRONT)
new_bone("FlapFront2", p1, p2, "FlapFront1", True, FRONT)
bpy.ops.object.mode_set(mode="OBJECT")
mount_frames = {}


# --- Quiver on the back ------------------------------------------------------------
# Slung diagonally across the back, over the cape, its opening above the right shoulder
# (-x) where the right hand reaches for an arrow: its axis runs QUIVER_TILT from upright,
# in the plane of the cape where it lies on the back but leaning QUIVER_PITCH further back
# (its top away from the hood), and its back faces the goblin. It is then moved straight
# back until it is QUIVER_GAP clear of every shell.
cape = V[parts[hood]]
# The cape is a sparse sheet of long quads with few vertices down its middle: find its
# middle by casting rays at it from behind.
CAPE_TREE = BVHTree.FromPolygons([Vector(p) for p in V], TRIS[np.isin(TRIS, parts[hood]).all(1)].tolist())


def cape_y(z, x=0.0):
    hit = CAPE_TREE.ray_cast(Vector((x, 2.0, z)), Vector((0, -1, 0)), 3.0)[0]
    return hit.y if hit is not None else float("nan")


zs = np.arange(0.80, 1.021, 0.02)
cape_slope = float(np.polyfit(zs, [cape_y(z) for z in zs], 1)[0])     # dy/dz of the cape's middle on the back
slope = math.tan(math.atan(cape_slope) + math.radians(QUIVER_PITCH))
t_up = unit(np.array([0.0, slope, 1.0]))
n_out = unit(np.array([0.0, 1.0, -slope]))
z_q = unit(math.cos(math.radians(QUIVER_TILT)) * t_up + math.sin(math.radians(QUIVER_TILT)) * np.array([-1.0, 0, 0]))
y_q = -n_out
x_q = np.cross(y_q, z_q)
QV = np.array([v.co[:] for v in PROPS["Quiver"].data.vertices])
QF = [list(p.vertices) for p in PROPS["Quiver"].data.polygons]
half_tube = QUIVER_TUBE * (QV[:, 2].max() - QV[:, 2].min()) / 2
rim = np.array([QUIVER_RIM[0], 0.0, QUIVER_RIM[1]])
o0 = rim - half_tube * z_q
o0[1] = 0.0
ALL_TREE = BVHTree.FromPolygons([Vector(p) for p in V], BODY_TRIS)


def quiver_world(dy):
    return frame_matrix(o0 + np.array([0, dy, 0]), x_q, y_q, z_q)


def quiver_clear(M, tree, P):
    """Body triangles through the quiver at M, and the nearest any shell comes to it."""
    Mn = np.array(M)
    Qw = QV @ Mn[:3, :3].T + Mn[:3, 3]
    qt = BVHTree.FromPolygons([Vector(q) for q in Qw], QF)
    cuts = len({(a, b) for a, b in qt.overlap(tree)} | {(a, b) for b, a in tree.overlap(qt)})
    near = min((qt.find_nearest(Vector(p), 0.05)[3] or 1.0) for p in P[(P[:, 1] > 0.1) & (P[:, 2] > 0.6)])
    return cuts, near


lo_, hi_ = 0.0, 0.6
for _ in range(25):
    m_ = (lo_ + hi_) / 2
    cuts, near = quiver_clear(quiver_world(m_), ALL_TREE, V)
    if cuts or near < QUIVER_GAP:
        lo_ = m_
    else:
        hi_ = m_
QUIVER_WORLD = quiver_world(hi_)
cuts, near = quiver_clear(QUIVER_WORLD, ALL_TREE, V)
Qw = QV @ np.array(QUIVER_WORLD)[:3, :3].T + np.array(QUIVER_WORLD)[:3, 3]
print("RIG_QUIVER cape %.1f deg from upright, the quiver %.1f; back at y %.3f; %.1f mm from the nearest shell, %d triangles through it;"
      " it reaches z %.3f to %.3f, x %.3f to %.3f" % (math.degrees(math.atan(-cape_slope)), math.degrees(math.atan(-slope)), hi_, near * 1000, cuts,
                                                       Qw[:, 2].min(), Qw[:, 2].max(), Qw[:, 0].min(), Qw[:, 0].max()))
assert not cuts and near >= QUIVER_GAP - 1e-4
CAPE_TOP = float(Qw[:, 2].min()) - 0.02     # the cape hangs from its own bones below the quiver

bpy.ops.object.mode_set(mode="EDIT")
EB = arm_data.edit_bones
# Cape: two bones down its middle, from just under the quiver to its lowest point.
# Its hem is ragged: the end is the lowest point where a ray from behind still meets it.
z_bot = float(cape[np.abs(cape[:, 0]) < 0.05, 2].min()) + 0.01
while not math.isfinite(cape_y(z_bot)):
    z_bot += 0.005
c0, c1, c2 = (Vector((0, cape_y(z), z)) for z in (CAPE_TOP, (CAPE_TOP + z_bot) / 2, z_bot))
assert all(math.isfinite(c.y) for c in (c0, c1, c2))
new_bone("Cape1", c0, c1, MX + "Spine2", False, FRONT)
new_bone("Cape2", c1, c2, "Cape1", True, FRONT)

# Prop bones: their rest frames are the bow's grip, the quiver's back and the arrow's nock.
FB = GRIPS["Bow"]["frame"]
bb = new_bone("Bow", FB.col[3].xyz, FB.col[3].xyz + FB.col[2].xyz * 0.12, MX + "LeftHand", False)
bb.align_roll(-FB.col[1].xyz)
QW = QUIVER_WORLD
qb = new_bone("Quiver", QW.col[3].xyz, QW.col[3].xyz + QW.col[2].xyz * 0.15, MX + "Spine2", False)
qb.align_roll(-QW.col[1].xyz)
# The arrow lies in the loose right fist along the rod it curls round, its head toward the
# thumb and the nock 0.15 m behind the fist.
FR = GRIPS["Relax"]["frame"]
ARROW_WORLD = FR @ Matrix.Translation((0, 0, -0.15))
ab = new_bone("Arrow", ARROW_WORLD.col[3].xyz, ARROW_WORLD.col[3].xyz + ARROW_WORLD.col[2].xyz * 0.12,
              MX + "RightHand", False)
ab.align_roll(-ARROW_WORLD.col[1].xyz)
# The string's nocking point: the middle of its two strands, which meet there.
STRING_MID = np.nonzero((BOW_V[:, 0] > STRING_X - 0.01) & (np.abs(BOW_V[:, 2]) < 0.01))[0]
nock = FB @ Vector(BOW_V[STRING_MID].mean(0).tolist())
sb = new_bone("String", nock, nock + FB.col[0].xyz * 0.06, "Bow", False)
sb.align_roll(FB.col[2].xyz)

# Controls (parentless; Child Of constraints do the following, as for the rabble).
bc_ = new_bone("BowCtrl", bb.head, bb.tail)
bc_.roll = bb.roll
for side, s in SIDES:
    hb = EB[MX + side + "Hand"]
    ik = new_bone("HandIK." + side[0], hb.head, hb.tail)
    ik.roll = hb.roll
    elbow = J[side + "ForeArm"]
    new_bone("ElbowPole." + side[0], elbow + Vector((0, 0.30, 0)), elbow + Vector((0, 0.36, 0)), MX + "Spine2")
    fb = EB[MX + side + "Foot"]
    fk_ = new_bone("FootIK." + side[0], fb.head, fb.tail)
    fk_.roll = fb.roll
    knee = J[side + "Leg"]
    new_bone("KneePole." + side[0], knee + Vector((0, -0.35, 0)), knee + Vector((0, -0.41, 0)), "FootIK." + side[0])
bpy.ops.object.mode_set(mode="OBJECT")

PROP_BONES = ("Bow", "Quiver", "Arrow", "String")
DEFORM_SKIP = ("HeadTop_End", "Toe_End", "Thumb4", "Index4", "Middle4", "Ring4")
CONTROL = set(PROP_BONES) | {"BowCtrl"} | {f"{p}.{c}" for p in ("HandIK", "ElbowPole", "FootIK", "KneePole") for c in "LR"}
for b in arm_data.bones:
    b.use_deform = b.name not in CONTROL and not b.name.endswith(DEFORM_SKIP)
COLL = {"Body": [], "Fingers": [], "Twist": [], "Secondary": [], "Props": [], "Controls": []}
for b in arm_data.bones:
    n = b.name
    if n in PROP_BONES:
        COLL["Props"].append(b)
    elif n in CONTROL:
        COLL["Controls"].append(b)
    elif any(f in n for f in CHAINS):
        COLL["Fingers"].append(b)
    elif "Twist" in n:
        COLL["Twist"].append(b)
    elif n.startswith(("Cape", "Flap")):
        COLL["Secondary"].append(b)
    else:
        COLL["Body"].append(b)
for cname, bones in COLL.items():
    bcol = arm_data.collections.new(cname)
    for b in bones:
        bcol.assign(b)
arm_data.collections["Twist"].is_visible = False
DEF = [b.name for b in arm_data.bones if b.use_deform]
BI = {n: i for i, n in enumerate(DEF)}
print("RIG_BONES", len(arm_data.bones), "deforming", len(DEF))

# --- Skin ------------------------------------------------------------------------
W = np.zeros((N, len(DEF)))


def heat_rows(vids, allow):
    """Bone-heat weights of some shells (on a temporary copy, so the other shells neither
    shade them nor take part), for the bones in `allow` only."""
    me = body.data.copy()
    me.attributes.new("orig", "INT", "POINT").data.foreach_set("value", np.arange(N, dtype=np.int32))
    tmp = bpy.data.objects.new("_heat", me)
    sc.collection.objects.link(tmp)
    bmh = bmesh.new()
    bmh.from_mesh(me)
    dl = bmh.verts.layers.deform.active
    if dl:
        bmh.verts.layers.deform.remove(dl)
    keep = set(vids.tolist())
    bmesh.ops.delete(bmh, geom=[v for v in bmh.verts if v.index not in keep], context="VERTS")
    bmh.to_mesh(me)
    bmh.free()
    orig = np.zeros(len(me.vertices), dtype=np.int32)
    me.attributes["orig"].data.foreach_get("value", orig)
    saved = {b.name: b.use_deform for b in arm_data.bones}
    for b in arm_data.bones:
        b.use_deform = saved[b.name] and b.name in allow
    bpy.ops.object.select_all(action="DESELECT")
    tmp.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    for b in arm_data.bones:
        b.use_deform = saved[b.name]
    gi = {g.index: g.name for g in tmp.vertex_groups}
    for v in me.vertices:
        for g in v.groups:
            if gi[g.group] in BI:
                W[orig[v.index], BI[gi[g.group]]] = g.weight
    bpy.data.objects.remove(tmp)
    bpy.data.meshes.remove(me)


def fill_empty(idx, names):
    """Vertices bone heat left without weights take the nearest of the bones `names`."""
    empty = idx[W[idx].sum(1) < 1e-3]
    if len(empty):
        segs = [(n, np.array(arm_data.bones[n].head_local), np.array(arm_data.bones[n].tail_local)) for n in names]
        D = np.stack([seg_d(V[empty], a, b) for _, a, b in segs], 1)
        for vi, j in zip(empty, D.argmin(1)):
            W[vi, BI[segs[j][0]]] = 1.0
    return len(empty)


body_idx = parts[main]
BODY_BONES = [n for n in DEF if n.startswith(MX) and arm_data.bones[n] not in COLL["Fingers"]]
heat_rows(body_idx, set(BODY_BONES))
print("RIG_SKIN body heat done, filled by nearest bone", fill_empty(body_idx, BODY_BONES))
boot_idx = np.concatenate([parts[k] for k, v in kind.items() if v == "boot"])
LEG_BONES = [MX + side + n for side, _ in SIDES for n in ("Leg", "Foot", "ToeBase")]
heat_rows(boot_idx, set(LEG_BONES))
print("RIG_SKIN boots heat done, filled by nearest bone", fill_empty(boot_idx, LEG_BONES))

# Forearm twist: the wrist half of each forearm moves onto its twist bone.
for side, s in SIDES:
    fa, tw = BI[MX + side + "ForeArm"], BI[side + "ForeArmTwist"]
    e, w = np.array(J[side + "ForeArm"]), np.array(J[side + "Hand"])
    t = ((V - e) @ (w - e)) / ((w - e) @ (w - e))
    k = smooth_step((t - 0.3) / 0.6) * in_main
    W[:, tw] += W[:, fa] * k
    W[:, fa] *= 1 - k

# Hands: the weights the grips were solved with.
for side, s in SIDES:
    names, R, k = hand_lbs(side, s)
    idx = HANDS[side]["idx"]
    rows = np.zeros((len(idx), len(DEF)))
    for j, n in enumerate(names):
        rows[:, BI[n]] = R[:, j] * k
    rows[:, BI[side + "ForeArmTwist"]] += 1 - k
    W[idx] = rows


# The other shells take the weights of the body surface nearest them (bvh: the main shell).
def transfer(idx):
    rows = np.zeros((len(idx), len(DEF)))
    for r, vi in enumerate(idx):
        loc, _, ti, _ = bvh.find_nearest(Vector(V[vi]))
        a, b, c = (V[j] for j in T3[ti])
        v0, v1, v2 = b - a, c - a, np.array(loc) - a
        d00, d01, d11, d20, d21 = v0 @ v0, v0 @ v1, v1 @ v1, v2 @ v0, v2 @ v1
        den = d00 * d11 - d01 * d01 + 1e-12
        wb_, wc_ = (d11 * d20 - d01 * d21) / den, (d00 * d21 - d01 * d20) / den
        bary = np.clip([1 - wb_ - wc_, wb_, wc_], 0, 1)
        rows[r] = bary @ W[T3[ti]] / bary.sum()
    return rows


def masked(rows, keep, fallback):
    """Rows kept to the bones `keep` (renormalised); a row with none of them goes to `fallback`."""
    mask = np.zeros(len(DEF))
    for n in keep:
        mask[BI[n]] = 1
    rows = rows * mask
    s_ = rows.sum(1)
    rows[s_ < 1e-6, BI[fallback]] = 1
    return rows / rows.sum(1, keepdims=True)


def rigid(idx, keep):
    """One weight row for the whole shell: the mean of the body's under it, kept to `keep`."""
    W[idx] = masked(transfer(idx).mean(0)[None], keep, keep[0])[0]


CHEST = [MX + n for n in ("Spine2", "Spine1", "Neck")]
HOOD = [MX + n for n in ("Spine2", "Head", "Neck", "Spine1", "LeftShoulder", "RightShoulder")]
TORSO = [MX + n for n in ("Spine1", "Spine2", "Spine", "Hips", "Neck", "LeftShoulder", "RightShoulder")]
for k, kd in kind.items():
    idx = parts[k]
    if kd == "head":
        W[idx] = 0
        W[idx, BI[MX + "Head"]] = 1
    elif kd == "belt":
        rigid(idx, [MX + "Hips", MX + "Spine"])
    elif kd == "chest":
        rigid(idx, CHEST)
    elif kd == "strap":
        W[idx] = masked(transfer(idx), TORSO, MX + "Spine1")
    elif kd == "other":
        W[idx] = transfer(idx)
    elif kd == "hood":
        # The hood and the top of the cape follow the head, neck, chest and collarbones
        # under them; below the quiver the cape goes over to its own bones.
        rows = masked(transfer(idx), HOOD, MX + "Spine2")
        z = V[idx, 2]
        # The back of the hood rests on the neck and the shoulders: it leaves HOOD_BACK of the
        # head's turn to them, so it swings less toward the quiver when the head turns.
        hb_k = HOOD_BACK * smooth_step((V[idx, 1] - 0.06) / 0.10) * smooth_step((z - 1.10) / 0.06)
        moved_ = rows[:, BI[MX + "Head"]] * hb_k
        rows[:, BI[MX + "Head"]] -= moved_
        rows[:, BI[MX + "Neck"]] += 0.6 * moved_
        rows[:, BI[MX + "Spine2"]] += 0.4 * moved_
        # The cape on the back, under the quiver, moves with the chest as the quiver does,
        # so the gap between them holds whatever the shoulders and the neck do.
        back = smooth_step((1.10 - z) / 0.08) * smooth_step((V[idx, 1] - 0.12) / 0.04)
        rows *= (1 - back)[:, None]
        rows[:, BI[MX + "Spine2"]] += back
        b1, b2 = arm_data.bones["Cape1"], arm_data.bones["Cape2"]
        k1 = smooth_step((b1.head_local.z + 0.03 - z) / 0.08)
        k2 = smooth_step((b2.head_local.z + 0.06 - z) / 0.12)
        rows *= (1 - k1)[:, None]
        rows[:, BI["Cape1"]] += k1 * (1 - k2)
        rows[:, BI["Cape2"]] += k1 * k2
        W[idx] = rows
belt_row = W[np.concatenate([parts[k] for k, v in kind.items() if v == "belt"])][0]
idx = np.concatenate([parts[k] for k, v in kind.items() if v == "flap_F"])
b1, b2 = arm_data.bones["FlapFront1"], arm_data.bones["FlapFront2"]
z = V[idx, 2]
k1 = smooth_step((b1.head_local.z + 0.005 - z) / 0.03)            # 0 at the belt, 1 below it
k2 = smooth_step((b2.head_local.z + 0.03 - z) / 0.06)             # onto the lower bone round the middle
rows = np.zeros((len(idx), len(DEF)))
rows += belt_row * (1 - k1)[:, None]
rows[:, BI[b1.name]] += k1 * (1 - k2)
rows[:, BI[b2.name]] += k1 * k2
W[idx] = rows

# Clean up: at most four bones per vertex, nothing under 1%, rows summing to one.
order = np.argsort(-W, axis=1)
W[np.arange(N)[:, None], order[:, 4:]] = 0
W[W < 0.01] = 0
W /= W.sum(1, keepdims=True)
assert np.isfinite(W).all() and np.allclose(W.sum(1), 1)
for g in [g for g in body.vertex_groups if g.name in BI]:
    body.vertex_groups.remove(g)
for n, j in BI.items():
    nz = np.nonzero(W[:, j])[0]
    if len(nz):
        vg = body.vertex_groups.new(name=n)
        for vi in nz:
            vg.add([int(vi)], float(W[vi, j]), "REPLACE")
body.parent = rig
mod = body.modifiers.new("Armature", "ARMATURE")
mod.object = rig
print("RIG_SKIN groups", len([g for g in body.vertex_groups if g.name in BI]),
      "max influences", int((W > 0).sum(1).max()))

# --- Props on their bones ------------------------------------------------------


def mount(obj, bone_name, world):
    bone = arm_data.bones[bone_name]
    obj.parent = rig
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    obj.matrix_parent_inverse = Matrix.Translation((0, -bone.length, 0))
    obj.matrix_basis = bone.matrix_local.inverted() @ world


mount(PROPS["Bow"], "Bow", GRIPS["Bow"]["frame"])
mount(PROPS["Quiver"], "Quiver", QUIVER_WORLD)
mount(PROPS["Arrow"], "Arrow", ARROW_WORLD)
vg = PROPS["Bow"].vertex_groups.new(name="String")
vg.add(STRING_MID.tolist(), 1.0, "REPLACE")
hook = PROPS["Bow"].modifiers.new("String", "HOOK")
hook.object, hook.subtarget, hook.vertex_group = rig, "String", "String"
hook.falloff_type = "NONE"
# No change at rest: the hook's matrix is bow^-1 @ string bone @ this inverse.
hook.matrix_inverse = (rig.matrix_world @ arm_data.bones["String"].matrix_local).inverted() @ rig.matrix_world @ FB
print("RIG_STRING %d vertices at the nocking point, %.3f m behind the grip's axis" % (len(STRING_MID), STRING_X))

# --- Grip actions and their constraints ----------------------------------------
rig.animation_data_create()
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="POSE")
for pb in rig.pose.bones:
    pb.rotation_mode = "QUATERNION"


def set_world(pb, M):
    pb.matrix = M
    bpy.context.view_layer.update()


def pose_hand(grip):
    """Pose one hand's fingers and thumb as the grip solution: each bone's rest moved by the
    rigid transform the solver gave its segment (parents first, so each sees its parent posed)."""
    for name in sorted(grip["D"]):
        pb = rig.pose.bones[name]
        set_world(pb, Matrix(grip["D"][name].tolist()) @ pb.bone.matrix_local)


def reset_pose():
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()


GRIP_ACTIONS = {}
for gname in ("Bow", "Relax"):
    side = GRIPS[gname]["side"]
    reset_pose()
    pose_hand(GRIPS[gname])
    act = bpy.data.actions.new("grip_" + gname.lower())
    act.use_fake_user = True
    rig.animation_data.action = act
    for f in CHAINS:
        for i in range(1, 4):
            pb = rig.pose.bones[f"{MX}{side}Hand{f}{i}"]
            pb.keyframe_insert("rotation_quaternion", frame=1)
    rig.animation_data.action = None
    GRIP_ACTIONS[gname] = (act, side)
reset_pose()

for p, d in (("bow_ik", "Left hand follows BowCtrl through HandIK.L"),
             ("draw_ik", "Right hand follows HandIK.R"), ("leg_ik", "Feet follow FootIK.L and FootIK.R")):
    rig[p] = 0.0
    rig.id_properties_ui(p).update(min=0.0, max=1.0, description=d)
rig["arrow"] = 0
rig.id_properties_ui("arrow").update(min=0, max=1, description="1 shows the arrow in the right hand")
rig["cape_back"] = 0.0
rig.id_properties_ui("cape_back").update(min=0.0, max=1.5, description="Swings the upper cape further back (radians)")


def drive(owner, path, expr, prop, index=-1):
    fc = owner.driver_add(path, index) if index >= 0 else owner.driver_add(path)
    drv = fc.driver
    drv.type = "SCRIPTED"
    var = drv.variables.new()
    var.name = prop.split("_")[0]
    var.type = "SINGLE_PROP"
    var.targets[0].id = rig
    var.targets[0].data_path = f'["{prop}"]'
    drv.expression = expr.replace("$", var.name)
    return drv


for gname, (act, side) in GRIP_ACTIONS.items():
    for f in CHAINS:
        for i in range(1, 4):
            pb = rig.pose.bones[f"{MX}{side}Hand{f}{i}"]
            c = pb.constraints.new("ACTION")
            c.name = "grip_" + gname.lower()
            c.action = act
            if hasattr(c, "action_slot") and len(act.slots):
                c.action_slot = act.slots[0]
            c.use_eval_time = True
            c.eval_time = 0.0
            c.frame_start, c.frame_end = 1, 2
            c.mix_mode = "BEFORE_FULL"
for path in ("hide_viewport", "hide_render"):
    drive(PROPS["Arrow"], path, "$ < 0.5", "arrow")


# --- Controls --------------------------------------------------------------------
mod.show_viewport = False   # the pole searches below update the scene many times


def child_of(pb, target):
    c = pb.constraints.new("CHILD_OF")
    c.target, c.subtarget = rig, target
    c.inverse_matrix = rig.data.bones[target].matrix_local.inverted()
    return c


child_of(rig.pose.bones["BowCtrl"], MX + "Spine2").name = "follow chest"
child_of(rig.pose.bones["HandIK.L"], "BowCtrl").name = "follow bow"
child_of(rig.pose.bones["HandIK.R"], MX + "Spine2").name = "follow chest"


def add_ik(chain_bone, end_bone, target, pole, prop):
    pb = rig.pose.bones[chain_bone]
    c = pb.constraints.new("IK")
    c.target, c.subtarget = rig, target
    c.pole_target, c.pole_subtarget = rig, pole
    c.chain_count = 2
    root = rig.pose.bones[chain_bone].parent.name
    rest = {n: rig.pose.bones[n].matrix.copy() for n in (chain_bone, root)}

    def err(ang):
        c.pole_angle = math.radians(ang)
        bpy.context.view_layer.update()
        return sum(abs(a - b) for n in rest
                   for ra, rb in zip(rig.pose.bones[n].matrix.to_3x3(), rest[n].to_3x3()) for a, b in zip(ra, rb))

    # The pole angle that leaves the rest pose where it is: from the root's x axis to the
    # pole's direction square to the root, signed about the root (as Blender measures it).
    b, m = arm_data.bones[root], arm_data.bones[chain_bone]
    along = b.tail_local - b.head_local
    normal = (m.tail_local - b.head_local).cross(arm_data.bones[pole].head_local - b.head_local)
    proj = normal.cross(along)
    x_axis = b.matrix_local.to_3x3().col[0]
    ang = math.degrees(x_axis.angle(proj)) * (-1 if x_axis.cross(proj).angle(along) < 1 else 1)
    c.influence = 1.0
    best = min((err(a), a) for a in np.arange(ang - 3, ang + 3.01, 0.5))
    c.pole_angle = math.radians(best[1])
    drive(c, "influence", "$", prop)
    eb = rig.pose.bones[end_bone]
    cr = eb.constraints.new("COPY_ROTATION")
    cr.target, cr.subtarget = rig, target
    drive(cr, "influence", "$", prop)
    print("RIG_IK", chain_bone, "pole angle %.1f (from the bones %.1f)" % (best[1], ang), "rest error %.5f" % best[0])


add_ik(MX + "LeftForeArm", MX + "LeftHand", "HandIK.L", "ElbowPole.L", "bow_ik")
add_ik(MX + "RightForeArm", MX + "RightHand", "HandIK.R", "ElbowPole.R", "draw_ik")
add_ik(MX + "RightLeg", MX + "RightFoot", "FootIK.R", "KneePole.R", "leg_ik")
add_ik(MX + "LeftLeg", MX + "LeftFoot", "FootIK.L", "KneePole.L", "leg_ik")

# Each twist bone copies most of its hand's roll about the forearm.
for side, _ in SIDES:
    c = rig.pose.bones[side + "ForeArmTwist"].constraints.new("COPY_ROTATION")
    c.target, c.subtarget = rig, MX + side + "Hand"
    c.use_x = c.use_z = False
    c.target_space = c.owner_space = "LOCAL"
    c.influence = 0.85


def thigh_driver(bone, expr, prop=None):
    """Turn a bone about its x axis by an expression of the thighs' swing (l, r: forward +)
    and the rig's property `prop` (p)."""
    pb = rig.pose.bones[bone]
    pb.rotation_mode = "XYZ"
    drv = pb.driver_add("rotation_euler", 0).driver
    drv.type = "SCRIPTED"
    for vn, side in (("l", "Left"), ("r", "Right")):
        var = drv.variables.new()
        var.name, var.type = vn, "TRANSFORMS"
        t = var.targets[0]
        t.id, t.bone_target = rig, MX + side + "UpLeg"
        t.transform_type, t.transform_space, t.rotation_mode = "ROT_X", "LOCAL_SPACE", "SWING_TWIST_Y"
    if prop:
        var = drv.variables.new()
        var.name, var.type = "p", "SINGLE_PROP"
        var.targets[0].id = rig
        var.targets[0].data_path = f'["{prop}"]'
    drv.expression = expr


# The flap swings forward with the leading thigh; the cape back with the trailing one and
# with `cape_back`.
thigh_driver("FlapFront1", "0.8 * max(0, l, r)")
thigh_driver("Cape1", f"{CAPE_FOLLOW} * min(0, l, r) - p", "cape_back")

# Look: bone colours by side, widgets on the controls.
widgets = bpy.data.collections.new("Widgets")
sc.collection.children.link(widgets)


def widget(name, verts, edges):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, edges, [])
    o = bpy.data.objects.new(name, me)
    widgets.objects.link(o)
    return o


ring = [(math.cos(t), 0, math.sin(t)) for t in np.linspace(0, 2 * math.pi, 24, endpoint=False)]
W_RING = widget("WGT_ring", ring, [(i, (i + 1) % 24) for i in range(24)])
cube = [(x, y, z) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
W_CUBE = widget("WGT_cube", cube, [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)])
diamond = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
W_DIAM = widget("WGT_diamond", diamond, [(0, 2), (2, 1), (1, 3), (3, 0), (0, 4), (4, 1), (1, 5), (5, 0), (2, 4), (4, 3), (3, 5), (5, 2)])
widgets.hide_viewport = widgets.hide_render = True
for pb in rig.pose.bones:
    n = pb.name
    side = "L" if ("Left" in n or n.endswith(".L") or n == "Bow") else ("R" if ("Right" in n or n.endswith(".R")) else "C")
    pb.color.palette = {"L": "THEME04", "R": "THEME01", "C": "THEME09"}[side]
    if n == "BowCtrl":
        pb.custom_shape, pb.custom_shape_scale_xyz = W_CUBE, (0.25, 1.0, 0.25)
    elif n.startswith(("HandIK", "FootIK")):
        pb.custom_shape, pb.custom_shape_scale_xyz = W_RING, (1.0, 1.0, 1.0)
    elif n.startswith(("ElbowPole", "KneePole")):
        pb.custom_shape, pb.custom_shape_scale_xyz = W_DIAM, (0.3, 0.3, 0.3)
arm_data.display_type = "OCTAHEDRAL"
rig.show_in_front = True
bpy.ops.object.mode_set(mode="OBJECT")


# --- Standard pose ---------------------------------------------------------------
def turn(axis, deg):
    return Matrix.Rotation(math.radians(deg), 3, axis)


def set_turn(name, R):
    """Pose a bone turned by R (world) from its rest, about its posed head."""
    pb = rig.pose.bones[name]
    M = (R @ pb.bone.matrix_local.to_3x3()).to_4x4()
    M.translation = pb.head
    set_world(pb, M)


def posed_mesh():
    ev = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    P = np.array([(ev.matrix_world @ v.co)[:] for v in ev.to_mesh().vertices])
    ev.to_mesh_clear()
    return P


def pose_arm(side, s, st):
    """Each arm turns down about the front-to-back axis (palm toward the thigh), then
    forward; elbow and wrist bend about the axis that is vertical at rest, the elbow
    forward and the wrist the other way (toward the little finger)."""
    set_turn(MX + side + "Shoulder", turn("Y", s * st["collar"]))
    b = arm_data.bones[MX + side + "Arm"]
    d = b.tail_local - b.head_local
    below = math.degrees(math.atan2(-d.z, abs(d.x)))        # its slope down at rest
    arm_turn = turn("X", -st["forward"]) @ turn("Y", s * (90 - st["out"] - below))
    set_turn(MX + side + "Arm", arm_turn)
    fore = arm_turn @ turn("Z", -s * st["elbow"])
    set_turn(MX + side + "ForeArm", fore)
    h = arm_data.bones[MX + side + "Hand"]
    roll = Matrix.Rotation(math.radians(-s * st["roll"]), 3, (h.tail_local - h.head_local).normalized())
    set_turn(MX + side + "Hand", fore @ turn("Z", s * st["wrist"]) @ roll)
    return arm_turn


sc.frame_set(1)
reset_pose()
mod.show_viewport = True
bpy.context.view_layer.update()
P_REST = posed_mesh()   # the T-pose (the grips still apply)
pbs = rig.pose.bones
HAND_L = np.array([sum(g.weight for g in v.groups if body.vertex_groups[g.group].name.startswith(MX + "LeftHand")) > 0.5
                   for v in body.data.vertices])
NO_HAND_TRIS = TRIS[~HAND_L[TRIS].any(1)].tolist()
BOW_F = [list(p.vertices) for p in PROPS["Bow"].data.polygons]
# The bow's surface sampled every 5 mm along its edges: the string is two long strands
# with vertices only at the tips and the nocking point, so its vertices alone miss it.
BOW_E = np.array([e.vertices[:] for e in PROPS["Bow"].data.edges])
BOW_S = [BOW_V]
for a, b in BOW_E:
    n = int(np.linalg.norm(BOW_V[b] - BOW_V[a]) / 0.005)
    if n > 1:
        t = np.arange(1, n)[:, None] / n
        BOW_S.append(BOW_V[a] + t * (BOW_V[b] - BOW_V[a]))
BOW_S = np.concatenate(BOW_S)
IS_STRING = BOW_S[:, 0] > STRING_X - 0.02
IN_HAND = np.abs(BOW_S[:, 2]) < 0.10           # the handle, inside the fist: its clearance is the grip's
HANDLE_F = np.array([(np.abs(BOW_V[f, 2]) < 0.10).all() for f in BOW_F])
GROUND_Z = 0.05      # the bow's lowest point stays this far off the ground


def bow_fit(P):
    """The bow against the posed body P (its left hand left out): body triangles through
    it, its limbs' and its string's nearest approach, its lowest point and its slope."""
    tree = BVHTree.FromPolygons([Vector(p) for p in P], NO_HAND_TRIS)
    Mw = np.array(PROPS["Bow"].matrix_world)
    Bw = BOW_V @ Mw[:3, :3].T + Mw[:3, 3]
    bt = BVHTree.FromPolygons([Vector(q) for q in Bw], BOW_F)
    # Both ways round: one tree's thin, long triangles (the string) can escape the other's test.
    pairs = {(f, i) for f, i in bt.overlap(tree)} | {(f, i) for i, f in tree.overlap(bt)}
    cuts = sum(1 for f, _ in pairs if not HANDLE_F[f])
    Sw = BOW_S @ Mw[:3, :3].T + Mw[:3, 3]
    d = np.array([tree.find_nearest(Vector(q), 0.3)[3] or 0.3 for q in Sw])
    return {"cuts": cuts, "handle_cuts": len(pairs) - cuts, "limbs": float(d[~IS_STRING & ~IN_HAND].min()),
            "handle": float(d[~IS_STRING & IN_HAND].min()), "string": float(d[IS_STRING].min()),
            "low": float(Sw[:, 2].min()), **bow_axis()}


def bow_axis():
    """The bow's upper limb: degrees above level, degrees it leans out (+) or in toward
    the body (-) from upright beside him, and how far it points ahead (unit vector's -y)."""
    axis = np.array(PROPS["Bow"].matrix_world)[:3, 2]
    return {"slope": math.degrees(math.asin(axis[2])), "lean": math.degrees(math.asin(axis[0])),
            "ahead": float(-axis[1])}


ARM_TURN = {"Right": pose_arm("Right", -1, STAND_R)}
# First every pose is ranked by the bow's angle alone (the skin is not needed for that),
# then the skin is checked pose by pose in that order until the bow is clear of it.
keys = list(STAND_L)
ranked = []
mod.show_viewport = False
for vals in np.array(np.meshgrid(*[STAND_L[k] for k in keys], indexing="ij")).reshape(len(keys), -1).T:
    st = {k: int(v) for k, v in zip(keys, vals)}
    pose_arm("Left", 1, st)
    ax = bow_axis()
    if ax["ahead"] > 0:
        cost = (abs(ax["slope"] - BOW_SLOPE) + BOW_LEAN * abs(ax["lean"]) + 0.1 * abs(st["wrist"])
                + 0.1 * abs(st["roll"]) + 0.03 * abs(st["elbow"] - 40) + 0.05 * st["forward"] + 0.05 * (st["out"] - 10))
        ranked.append((cost, st))
mod.show_viewport = True
ranked.sort(key=lambda r: r[0])
STAND_L_PICK, checked = None, 0
for cost, st in ranked[:400]:
    pose_arm("Left", 1, st)
    fit = bow_fit(posed_mesh())
    checked += 1
    if (not fit["cuts"] and fit["limbs"] >= BOW_GAP and fit["string"] >= STRING_GAP and fit["low"] >= GROUND_Z):
        STAND_L_PICK = st
        break
    if checked <= 5:
        print("RIG_STAND_REJECT", st, {k: round(v, 3) for k, v in fit.items()})
assert STAND_L_PICK, "no left-arm pose holds the bow clear"
print("RIG_STAND_SEARCH %d poses ranked, the %d. checked fits (cost %.1f): %s: %s" % (
    len(ranked), checked, cost, STAND_L_PICK, {k: round(v, 3) for k, v in fit.items()}))
ARM_TURN["Left"] = pose_arm("Left", 1, STAND_L_PICK)
for side, s in SIDES:
    pole = pbs["ElbowPole." + side[0]]
    M = (ARM_TURN[side] @ pole.bone.matrix_local.to_3x3()).to_4x4()
    M.translation = pbs[MX + side + "ForeArm"].head + ARM_TURN[side] @ (
        pole.bone.head_local - arm_data.bones[MX + side + "ForeArm"].head_local)
    set_world(pole, M)
# The controls where the pose put the hands (the chest is at rest, so their Child Of
# constraints change nothing): HandIK.L follows BowCtrl onto the left hand.
set_world(pbs["BowCtrl"], pbs["Bow"].matrix.copy())
set_world(pbs["HandIK.R"], pbs[MX + "RightHand"].matrix.copy())
stand = bpy.data.actions.new("stand")
stand.use_fake_user = True
rig.animation_data.action = stand
for side, _ in SIDES:
    for n in ("Shoulder", "Arm", "ForeArm", "Hand"):
        pbs[MX + side + n].keyframe_insert("rotation_quaternion", frame=1)
for n in ("BowCtrl", "HandIK.R", "ElbowPole.L", "ElbowPole.R"):
    pbs[n].keyframe_insert("location", frame=1)
    pbs[n].keyframe_insert("rotation_quaternion", frame=1)
bpy.context.view_layer.update()
fk = {n: pbs[MX + n].matrix.copy() for n in ("RightHand", "LeftHand", "RightForeArm", "LeftForeArm")}
rig["bow_ik"] = rig["draw_ik"] = 1.0
rig.update_tag()
bpy.context.view_layer.update()
moved_ = {n: ((pbs[MX + n].matrix.translation - M.translation).length * 1000,
              math.degrees(pbs[MX + n].matrix.to_quaternion().rotation_difference(M.to_quaternion()).angle))
          for n, M in fk.items()}
rig["bow_ik"] = rig["draw_ik"] = 0.0
rig.update_tag()
bpy.context.view_layer.update()
print("RIG_STAND bow's upper limb points", [round(c, 2) for c in pbs["Bow"].matrix.to_3x3().col[1].normalized()],
      "| IK on moves", {n: "%.1f mm %.1f deg" % m for n, m in moved_.items()})

# --- The bow hand's hold -------------------------------------------------------------
# Whatever a clip does to the left wrist, the hand keeps the turn from the forearm it has
# in `stand`, so the bow keeps its angle: the helper bone `BowHold` sits on the forearm
# where the hand is in `stand`, and a Copy Rotation constraint on the hand (after the
# IK's, so it wins) follows it as much as the rig's `bow_hold` says (1 by default; 0
# gives the wrist back to the clips and HandIK.L, as a shooting clip needs).
hold_rest = (arm_data.bones[MX + "LeftForeArm"].matrix_local @ pbs[MX + "LeftForeArm"].matrix.inverted()
             @ pbs[MX + "LeftHand"].matrix)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
EB = arm_data.edit_bones
hb_ = EB.new("BowHold")
hb_.head, hb_.tail = Vector((0, 0, 0)), Vector((0, 0.08, 0))
hb_.matrix = hold_rest
hb_.parent = EB[MX + "LeftForeArm"]
hb_.use_deform = False
bpy.ops.object.mode_set(mode="OBJECT")
mech = arm_data.collections.new("Mechanics")
mech.assign(arm_data.bones["BowHold"])
mech.is_visible = False
pbs = rig.pose.bones
pbs["BowHold"].rotation_mode = "QUATERNION"
pbs["BowHold"].color.palette = "THEME04"
rig["bow_hold"] = 1.0
rig.id_properties_ui("bow_hold").update(
    min=0.0, max=1.0, description="Left hand keeps its turn on the bow (0: clips and HandIK.L turn it)")
c = pbs[MX + "LeftHand"].constraints.new("COPY_ROTATION")
c.name = "hold the bow"
c.target, c.subtarget = rig, "BowHold"
drive(c, "influence", "$", "bow_hold")
rig.update_tag()
sc.frame_set(1)
bpy.context.view_layer.update()
held = math.degrees(pbs[MX + "LeftHand"].matrix.to_quaternion().rotation_difference(fk["LeftHand"].to_quaternion()).angle)
print("RIG_HOLD BowHold on the left forearm; the held hand is %.3f deg from the keyed one;" % held,
      "bones", len(arm_data.bones), "deforming", len([b for b in arm_data.bones if b.use_deform]))
assert held < 0.1

# --- Checks in the standard pose and the T-pose ------------------------------------
P = posed_mesh()
STAND_FIT = bow_fit(P)
tree_stand = BVHTree.FromPolygons([Vector(p) for p in P], BODY_TRIS)
q_on_bone = pbs["Quiver"].matrix @ arm_data.bones["Quiver"].matrix_local.inverted()
q_cuts, q_near = quiver_clear(q_on_bone @ QUIVER_WORLD, tree_stand, P)
print("RIG_CHECK_STAND bow", {k: round(v, 3) for k, v in STAND_FIT.items()},
      "| quiver %.1f mm from the nearest shell, %d triangles through it" % (q_near * 1000, q_cuts))
assert not STAND_FIT["cuts"] and not q_cuts
rig.animation_data.action = None
reset_pose()
P_T = posed_mesh()
TPOSE_FIT = bow_fit(P_T)
print("RIG_CHECK_TPOSE bow", {k: round(v, 3) for k, v in TPOSE_FIT.items()})
rig.animation_data.action = stand
if hasattr(rig.animation_data, "action_slot") and len(stand.slots):
    rig.animation_data.action_slot = stand.slots[0]
sc.frame_set(1)
bpy.context.view_layer.update()

# --- Save ---------------------------------------------------------------------
rig["grip"] = {w: {"across_palm_at": round(g["U"], 4), "tilt_deg": g["tilt"], "slide": g["slide"],
                   "energy": round(g["E"], 2), "closest_mm": g["closest_mm"]} for w, g in GRIPS.items()}
rig["stand_left"] = STAND_L_PICK
rig["fit"] = {"bow_stand": {k: round(v, 4) for k, v in STAND_FIT.items()},
              "bow_tpose": {k: round(v, 4) for k, v in TPOSE_FIT.items()},
              "quiver": {"tilt_deg": QUIVER_TILT, "gap_mm": round(q_near * 1000, 1), "back_y": round(hi_, 4)},
              "cape_top_z": round(CAPE_TOP, 4)}
# Paths are saved in fixed-size fields, which keep the tail of a longer path written
# before: overwrite them first. Image paths are written with forward slashes.
for img in bpy.data.images:
    if img.filepath_raw:
        p = img.filepath_raw.replace("\\", "/")
        img.filepath_raw = "//" + "_" * 700
        img.filepath_raw = p
for screen in bpy.data.screens:
    for area in screen.areas:
        for space in area.spaces:
            if space.type == "FILE_BROWSER" and space.params is not None:
                space.params.directory = b"//" + b"_" * 700
                space.params.directory = b"//"
out_blend.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(out_blend), relative_remap=True, compress=True)
print("RIG_SAVED", out_blend)
