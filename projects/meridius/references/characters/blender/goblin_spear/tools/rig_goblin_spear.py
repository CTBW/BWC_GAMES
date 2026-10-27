"""Rig the goblin spearman for Mixamo clips, both hands closed round the spear (background Blender).

  blender -b goblin_spear_base.blend --factory-startup --python rig_goblin_spear.py -- <out.blend>

Starts from goblin_spear_base.blend (build_goblin_spear.py) and follows the goblin
archer's rig_goblin_archer.py:
1. A Mixamo-named armature with finger bones placed on each hand's mesh: four fingers
   and a thumb (Thumb, Index, Middle, Ring and Pinky 1-4). Forearm twist bones, two bones
   down the middle of the cape and two for each skirt flap, front and back.
2. Skin: the body is one shell, the cape and the skirt flaps fused to it. Bone heat on
   the body with the cape and the flaps cut away (they hang free of it below where they
   join: the cape under z 1.0, the flaps under z 0.6); geometric weights on the hands,
   cut from the body past the wrist, so a finger moves only its own skin. The back of
   the fur mantle, where the cape hangs from it, follows the chest, neck and collarbones,
   never the upper arms; the cape goes over to its own bones below that, and the flaps
   below the belt. The eyes follow the head; the studs, horns, rivets, the chest boss
   and the buckle are rigid on the skin under them.
3. Grips, solved on the skin as for the archer: each hand closes round the spear's
   shaft, laid across the palm, at the tilt and the place along it that close the four
   fingers best; the thumb closes the other way, toward the index finger. Both thumbs
   point toward the head. The right (rear) fist holds the bare shaft about 0.4 m from the
   butt, GRIP_R from the grip's middle; the left (front) fist the middle of the leather
   grip. Each grip is a one-frame Action applied by Action constraints on the finger bones.
4. The spear rides the `Spear` bone in the right fist. The left hand holds it through
   `SpearGrip.L`, a child of `Spear` on the shaft's axis at the left fist: moving it along
   its length slides the hand along the shaft, turning it about its length turns the
   hand round the shaft. `HandIK.L`, its child, is where the left hand holds on, and
   `support_ik` (1 by default) keeps the left hand there through IK.
5. Controls as for the archer, mirrored for the spear hand: `SpearCtrl` follows the
   chest and `HandIK.R` follows `SpearCtrl`; `spear_ik` and `leg_ik` (0 by default)
   switch on IK for the right arm and the feet.
6. Standard pose: the skin stays bound to the T-pose, and the one-frame Action `stand`
   holds the spear as in the concept, mirrored: the rear (right) fist at the right hip,
   the head raised about SPEAR_SLOPE above level and pointing about SPEAR_YAW to his
   left, diagonally across him, the front (left) hand reaching forward to the leather
   grip. The spear's place is searched (the fist's place, the spear's heading, slope and
   turn about its length, and the left hand's turn round the shaft and slide along it),
   both arms reaching their hands by IK, for wrists that bend and twist little, the spear
   SPEAR_GAP clear of the body and the forearms clear of the torso and legs. The pose is
   keyed as FK, with the controls where it put them. The blade's flat lies level.
Every control and helper bone is non-deforming and in its own bone collection; the
deforming bones are what a game export keeps.
"""
import itertools
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
FINGERS = ("Index", "Middle", "Ring", "Pinky")   # four fingers and a thumb on each hand
WRIST_U = 0.65      # the wrist, distance from the centre line (both hands)
KNUCKLE_U = 0.775   # the knuckle row
PHALANX = (0.45, 0.30, 0.25)   # finger length shares of the three segments
# Where along the spear each fist holds (spear space: the leather grip's middle is 0, the
# butt -0.805): the right on the bare shaft, past the knot rings round -0.35 if it closes
# better there (each grip slides SLIDES along the shaft), the left on the leather grip.
GRIP_R, GRIP_L = -0.38, 0.0
SLIDES_R, SLIDES_L = (-0.04, -0.02, 0.0, 0.02, 0.04), (-0.02, 0.0, 0.02)
SPEAR_SLOPE = 20    # degrees: the spear's head raised above level in the standard pose
SPEAR_YAW = 45      # degrees it points to his left of straight ahead
SPEAR_GAP = 0.02    # the spear keeps this far off the body in the standard pose
GROUND_Z = 0.08     # its butt this far off the ground
CAPE_FOLLOW = 0.6   # the cape swings back with the trailing thigh, this share of its swing
FLAP_FOLLOW = 0.8   # the flaps swing with the leading (front) and trailing (back) thigh
# The standard pose is searched (below) from these: the middle of the right fist (m; the
# hip joint is at x -0.10, z 0.64), the spear's heading and slope and its turn about its
# length (degrees), and the left hand's turn round the shaft (degrees) and slide along it
# (m, + toward the head) from where its grip was solved. FIST_HOME is the fist's place
# preferred, beside the hip, where the shaft behind it passes outside the thigh. His arms
# are short (0.445 m to the wrist), so the left hand reaches the leather grip only with
# the spear crossing him at about SPEAR_YAW.
STAND = {"x": (-0.18, -0.24, -0.30), "y": (-0.04, -0.12, -0.20), "z": (0.60, 0.68, 0.76),
         "yaw": (35, 45, 55, 65), "slope": (10, 20, 30), "roll": tuple(range(-180, 180, 15)),
         "phi": tuple(range(-90, 91, 15)), "slide": (0.06, 0.03, 0.0, -0.03, -0.06)}
FIST_HOME = np.array([-0.24, -0.12, 0.68])
FOREARM_R = 0.04    # the forearm's radius over the bracer, for the closed-form clearances
# Collarbones (degrees lowered, drawn forward): the left drawn toward the shaft.
COLLAR = {"Right": (6, 0), "Left": (6, 10)}
# Which way each elbow points: out, back and down.
ELBOW_DIR = {"Left": np.array([0.5, 0.3, -1.0]), "Right": np.array([-0.5, 0.4, -1.0])}
# Joints of the left side read off the T-pose (front and side views on a 5 cm grid and
# the hand on a 1 cm grid); the right side mirrors x. The spine's depth is measured below.
J0 = {
    "Head": (0, -0.05, 1.20), "HeadTop_End": (0, -0.06, 1.47),
    "Shoulder": (0.04, 0.03, 1.12), "Arm": (0.205, 0.02, 1.08), "ForeArm": (0.42, 0.005, 1.076),
    "Hand": (WRIST_U, -0.035, 1.07),
    "UpLeg": (0.10, 0.0, 0.64), "Leg": (0.17, -0.03, 0.37), "Foot": (0.18, -0.01, 0.09),
    "ToeBase": (0.20, -0.14, 0.03), "Toe_End": (0.22, -0.23, 0.02),
}
SPINE_Z = {"Hips": 0.68, "Spine": 0.77, "Spine1": 0.87, "Spine2": 0.98, "Neck": 1.13}

argv = sys.argv[sys.argv.index("--") + 1:]
out_blend = Path(argv[0]).resolve()
sc = bpy.context.scene
body = bpy.data.objects["GoblinSpearman"]
spear = bpy.data.objects["Spear"]
V = np.array([v.co[:] for v in body.data.vertices])
N = len(V)
assert abs(V[:, 2].max() - H) < 0.005 and abs(V[:, 2].min()) < 0.005
SP_V = np.array([v.co[:] for v in spear.data.vertices])
SP_F = [list(p.vertices) for p in spear.data.polygons]
SP_BUTT, SP_TIP = float(SP_V[:, 2].min()), float(SP_V[:, 2].max())


def unit(v):
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


def smooth_step(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


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


body.data.calc_loop_triangles()
TRIS = np.zeros(3 * len(body.data.loop_triangles), dtype=np.int64)
body.data.loop_triangles.foreach_get("vertices", TRIS)
TRIS = TRIS.reshape(-1, 3)
EDGES = np.zeros(2 * len(body.data.edges), dtype=np.int64)
body.data.edges.foreach_get("vertices", EDGES)
EDGES = EDGES.reshape(-1, 2)
BODY_TRIS = TRIS.tolist()


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


# --- Shells and the parts fused to the body ---------------------------------------
bm = bmesh.new()
bm.from_mesh(body.data)
parts = shells(bm)
bm.free()
main = max(range(len(parts)), key=lambda k: len(parts[k]))
in_main = np.zeros(N, bool)
in_main[parts[main]] = True
kind = {}
for k, p in enumerate(parts):
    if k == main:
        continue
    lo, hi, c = V[p].min(0), V[p].max(0), V[p].mean(0)
    if abs(c[0]) > 0.40:
        kind[k] = "stud_L" if c[0] > 0 else "stud_R"   # the bracer studs
    elif c[2] < 0.85:
        kind[k] = "buckle"      # the belt buckle and its prong
    elif c[2] > 1.18 and abs(c[0]) < 0.08 and c[1] < -0.15:
        kind[k] = "eye"         # in front of the face, under the brow
    elif c[1] > 0.15 and c[2] < 1.15:
        kind[k] = "rivet"       # on the back of the mantle
    elif c[2] < 1.12 and c[1] < -0.1 and abs(c[0]) < 0.17:
        kind[k] = "boss"        # the round boss on the chest strap
    else:
        kind[k] = "horn"        # on the mantle and the left shoulder
counts = {}
for kd in kind.values():
    counts[kd] = counts.get(kd, 0) + 1
print("RIG_SHELLS main %d vertices," % len(parts[main]), counts)
assert counts.get("eye") == 2 and counts.get("stud_L") == counts.get("stud_R") == 6 and counts.get("boss") == 1


def fused(mask, test):
    """The one connected part of the main shell under `mask` that passes `test` (its centroid)."""
    found = [c for c in components(in_main & mask) if len(c) > 30 and test(V[c].mean(0))]
    assert len(found) == 1, f"{len(found)} parts found"
    m = np.zeros(N, bool)
    m[found[0]] = True
    return m


# The cape hangs free of the back below z 1.0 (it joins the mantle between 1.0 and 1.03),
# the skirt's front and back flaps below z 0.6 (above, the pelvis and the skirt are one loop).
CAPE = fused(V[:, 2] < 1.0, lambda c: c[1] > 0.15)
FLAP_F = fused(V[:, 2] < 0.60, lambda c: c[1] < -0.12 and abs(c[0]) < 0.05)
FLAP_B = fused(V[:, 2] < 0.60, lambda c: 0.08 < c[1] < 0.18 and abs(c[0]) < 0.05)
CORE = in_main & ~CAPE & ~FLAP_F & ~FLAP_B
print("RIG_PARTS cape %d, front flap %d, back flap %d, core %d vertices" % (CAPE.sum(), FLAP_F.sum(), FLAP_B.sum(), CORE.sum()))
T3 = TRIS[CORE[TRIS].all(1)]
bvh = BVHTree.FromPolygons([Vector(p) for p in V], T3.tolist())


def torso_mid(z):
    """Halfway between the front and the back of the body (the cape left out) at height z."""
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
def measure_hand(side, s):
    """Joints (armature space) and radii of the four fingers and the thumb. The hand is
    the body shell past the wrist (a little short of it, for the blend into the forearm)."""
    U = V[:, 0] * s
    in_hand = in_main & (U > WRIST_U - 0.03)
    idx = np.nonzero(in_hand)[0]
    for u_web in np.arange(0.77, 0.84, 0.002):     # past the webs the four fingers are apart
        comps = [c for c in components(in_hand & (U > u_web)) if len(c) >= 12]
        if len(comps) == len(FINGERS):
            break
    assert len(comps) == len(FINGERS), f"{side} hand: the fingers were not found"
    comps.sort(key=lambda c: V[c, 1].mean())         # index (front) to pinky
    in_fingers = np.zeros(N, bool)
    hand = {"idx": idx, "fingers": {}, "web": float(u_web)}
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
    print("RIG_WEB", side, "the fingers part at %.3f" % HANDS[side]["web"])
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
# tested against the spear's surface, sampled as a signed distance field.
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
    own space (vertices P, faces F) between heights z0 and z1 and read back trilinearly."""

    def __init__(self, P, F, z0, z1, step=0.002):
        tree = BVHTree.FromPolygons([Vector(p) for p in P], F)
        near = P[(P[:, 2] > z0 - 0.02) & (P[:, 2] < z1 + 0.02)]
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
        self.s, self.step, self.u0, self.y0 = s, 0.003, WRIST_U - 0.025, -0.17
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
    """Low when every phalanx just touches the shaft, nothing passes into it or into the palm,
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
    """Low when the thumb wraps the shaft without passing into it, the fingers or the palm,
    its last phalanx resting on the index finger's middle one (or on the shaft)."""
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
    """The shaft's frame: its axis across the palm (crossing the middle finger's line at U,
    turned tau toward the wrist on the little finger's side), slid sigma along itself and
    pressed up until it just touches the palm. Columns x, y, z of R: z the axis toward the
    thumb (the spear's head), x toward the wrist; o the field's origin on the axis."""
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
    """Closest approach of each phalanx to the shaft (mm; negative is inside), the angles and
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
    # Where the fist sits along the field's axis: the middle of the palm, projected on it.
    best["fist_z"] = float((hand.still.mean(0) - best["o"]) @ best["R"][:, 2])
    return best


def spear_grip(side, s, z, sigmas, label):
    """A grip on the spear round spear height z: solved on the spear moved down by z, so
    the field's origin is on the axis at z. Returns it with `spear`, the spear's frame in the
    T-pose hand, and `fist`, the fist's height along the spear."""
    P = SP_V - np.array([0.0, 0.0, z])
    grip = solve_grip(GripHand(side, s), PropField(P, SP_F, -0.12, 0.12), sigmas, label)
    grip["spear"] = grip["frame"] @ Matrix.Translation((0, 0, -z))
    grip["fist"] = z + grip["fist_z"]
    return grip


GRIPS = {"Right": spear_grip("Right", -1, GRIP_R, SLIDES_R, "SpearR"),
         "Left": spear_grip("Left", 1, GRIP_L, SLIDES_L, "SpearL")}
F_R, F_L = GRIPS["Right"]["spear"], GRIPS["Left"]["spear"]
print("RIG_FISTS right at spear z %+.3f (%.3f m from the butt), left at %+.3f; %.3f m apart" % (
    GRIPS["Right"]["fist"], GRIPS["Right"]["fist"] - SP_BUTT, GRIPS["Left"]["fist"],
    GRIPS["Left"]["fist"] - GRIPS["Right"]["fist"]))


# --- Armature ------------------------------------------------------------------
arm_data = bpy.data.armatures.new("GoblinSpearmanRig")
rig = bpy.data.objects.new("GoblinSpearmanRig", arm_data)
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


def mid_line(mask, z_list):
    """Points down the middle of a hanging part: its median depth near the centre line at each height."""
    P = V[mask & (np.abs(V[:, 0]) < 0.06)]
    pts = []
    for z in z_list:
        q = P[np.abs(P[:, 2] - z) < 0.03]
        pts.append(Vector((0, float(np.median(q[:, 1])), z)))
    return pts


# Cape: two bones down its middle, from where it parts from the mantle to its hem.
cz = V[CAPE, 2]
z0, z1 = float(cz.max()) - 0.05, float(V[CAPE & (np.abs(V[:, 0]) < 0.06), 2].min()) + 0.02
c0, c1, c2 = mid_line(CAPE, (z0, (z0 + z1) / 2, z1))
new_bone("Cape1", c0, c1, MX + "Spine2", False, FRONT)
new_bone("Cape2", c1, c2, "Cape1", True, FRONT)
# Skirt flaps: two bones each, from under the belt down.
for name, mask in (("FlapFront", FLAP_F), ("FlapBack", FLAP_B)):
    fz = V[mask, 2]
    z0, z1 = float(fz.max()) - 0.02, float(V[mask & (np.abs(V[:, 0]) < 0.06), 2].min()) + 0.01
    p0, p1, p2 = mid_line(mask, (z0, (z0 + z1) / 2, z1))
    new_bone(name + "1", p0, p1, MX + "Hips", False, FRONT)
    new_bone(name + "2", p1, p2, name + "1", True, FRONT)

# The spear's bone: its head on the shaft's axis in the right fist, along the spear toward
# its head; the bone's z axis is the spear's -y (the leaf's flat face).
AX_R = F_R.col[2].xyz
sb = new_bone("Spear", F_R @ Vector((0, 0, GRIPS["Right"]["fist"])),
              F_R @ Vector((0, 0, GRIPS["Right"]["fist"] + 0.15)), MX + "RightHand", False)
sb.align_roll(-F_R.col[1].xyz)
# The left hand's hold on the shaft, and where the left hand is when it holds there: its
# rest moved as the spear in the left T-pose hand moves onto the spear in the right one.
gl = new_bone("SpearGrip.L", F_R @ Vector((0, 0, GRIPS["Left"]["fist"])),
              F_R @ Vector((0, 0, GRIPS["Left"]["fist"] + 0.08)), "Spear", False)
gl.roll = sb.roll
HL_REST = EB[MX + "LeftHand"].matrix.copy()
ikl = new_bone("HandIK.L", (0, 0, 0), (0, EB[MX + "LeftHand"].length, 0), "SpearGrip.L", False)
ikl.matrix = F_R @ F_L.inverted() @ HL_REST

# Controls (parentless; Child Of constraints do the following, as for the archer).
sc_ = new_bone("SpearCtrl", sb.head, sb.tail)
sc_.roll = sb.roll
hb = EB[MX + "RightHand"]
ikr = new_bone("HandIK.R", hb.head, hb.tail)
ikr.roll = hb.roll
for side, s in SIDES:
    elbow = J[side + "ForeArm"]
    new_bone("ElbowPole." + side[0], elbow + Vector((0, 0.30, 0)), elbow + Vector((0, 0.36, 0)), MX + "Spine2")
    fb = EB[MX + side + "Foot"]
    fk_ = new_bone("FootIK." + side[0], fb.head, fb.tail)
    fk_.roll = fb.roll
    knee = J[side + "Leg"]
    new_bone("KneePole." + side[0], knee + Vector((0, -0.35, 0)), knee + Vector((0, -0.41, 0)), "FootIK." + side[0])
bpy.ops.object.mode_set(mode="OBJECT")

PROP_BONES = ("Spear",)
DEFORM_SKIP = ("HeadTop_End", "Toe_End", "Thumb4", "Index4", "Middle4", "Ring4", "Pinky4")
CONTROL = {"SpearCtrl", "SpearGrip.L"} | {f"{p}.{c}" for p in ("HandIK", "ElbowPole", "FootIK", "KneePole") for c in "LR"}
for b in arm_data.bones:
    b.use_deform = b.name not in CONTROL and b.name not in PROP_BONES and not b.name.endswith(DEFORM_SKIP)
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
    """Bone-heat weights of some vertices (on a temporary copy, so the rest neither shades
    them nor takes part), for the bones in `allow` only."""
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


core_idx = np.nonzero(CORE)[0]
BODY_BONES = [n for n in DEF if n.startswith(MX) and arm_data.bones[n] not in COLL["Fingers"]]
heat_rows(core_idx, set(BODY_BONES))
print("RIG_SKIN body heat done, filled by nearest bone", fill_empty(core_idx, BODY_BONES))

# Forearm twist: the wrist half of each forearm moves onto its twist bone.
for side, s in SIDES:
    fa, tw = BI[MX + side + "ForeArm"], BI[side + "ForeArmTwist"]
    e, w = np.array(J[side + "ForeArm"]), np.array(J[side + "Hand"])
    t = ((V - e) @ (w - e)) / ((w - e) @ (w - e))
    k = smooth_step((t - 0.3) / 0.6) * CORE
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


# The other parts take the weights of the body surface nearest them (bvh: the core).
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
    """One weight row for the whole part: the mean of the body's under it, kept to `keep`."""
    W[idx] = masked(transfer(idx).mean(0)[None], keep, keep[0])[0]


CHEST = [MX + n for n in ("Spine2", "Spine1", "Neck")]
UPPER = [MX + n for n in ("Spine2", "Spine1", "Neck", "LeftShoulder", "RightShoulder")]
# The back of the mantle, where the cape hangs from it, keeps to the chest, neck and
# collarbones, so the cape's top holds still when the arms move.
k = (smooth_step((V[:, 1] - 0.04) / 0.08) * smooth_step((V[:, 2] - 0.93) / 0.05)
     * smooth_step((0.36 - np.abs(V[:, 0])) / 0.06) * CORE)
mb = np.nonzero(k > 0)[0]
W[mb] = (1 - k[mb, None]) * W[mb] + k[mb, None] * masked(W[mb], UPPER, MX + "Spine2")
print("RIG_SKIN mantle back kept to the chest: %d vertices" % len(mb))

# Small parts: each group of touching parts (a horn on its base, the buckle and its
# prong) moves as one.
groups = []
for k_, kd in kind.items():
    lo, hi = V[parts[k_]].min(0) - 0.005, V[parts[k_]].max(0) + 0.005
    for g_ in groups:
        if g_["kind"] == kd and (lo <= g_["hi"]).all() and (hi >= g_["lo"]).all():
            g_["parts"].append(k_)
            g_["lo"], g_["hi"] = np.minimum(g_["lo"], lo), np.maximum(g_["hi"], hi)
            break
    else:
        groups.append({"kind": kd, "parts": [k_], "lo": lo, "hi": hi})
for g_ in groups:
    idx = np.concatenate([parts[k_] for k_ in g_["parts"]])
    kd = g_["kind"]
    side = "Left" if V[idx, 0].mean() > 0 else "Right"
    if kd == "eye":
        W[idx] = 0
        W[idx, BI[MX + "Head"]] = 1
    elif kd.startswith("stud"):
        rigid(idx, [MX + side + "ForeArm", side + "ForeArmTwist"])
    elif kd == "buckle":
        rigid(idx, [MX + "Hips", MX + "Spine"])
    elif kd == "boss":
        rigid(idx, CHEST)
    elif kd == "rivet":
        rigid(idx, UPPER)
    else:
        rigid(idx, [MX + "Spine2", MX + side + "Shoulder", MX + side + "Arm", MX + "Neck"])
print("RIG_SKIN small parts in %d groups" % len(groups))

# Cape: the chest and collarbones at its top, its own bones below.
idx = np.nonzero(CAPE)[0]
rows = masked(transfer(idx), UPPER, MX + "Spine2")
z = V[idx, 2]
b1, b2 = arm_data.bones["Cape1"], arm_data.bones["Cape2"]
k1 = smooth_step((b1.head_local.z + 0.03 - z) / 0.08)
k2 = smooth_step((b2.head_local.z + 0.06 - z) / 0.12)
rows *= (1 - k1)[:, None]
rows[:, BI["Cape1"]] += k1 * (1 - k2)
rows[:, BI["Cape2"]] += k1 * k2
W[idx] = rows
# Flaps: the pelvis at their top, their own bones below.
for name, mask in (("FlapFront", FLAP_F), ("FlapBack", FLAP_B)):
    idx = np.nonzero(mask)[0]
    b1, b2 = arm_data.bones[name + "1"], arm_data.bones[name + "2"]
    z = V[idx, 2]
    k1 = smooth_step((b1.head_local.z + 0.005 - z) / 0.03)            # 0 at the belt, 1 below it
    k2 = smooth_step((b2.head_local.z + 0.03 - z) / 0.06)             # onto the lower bone round the middle
    rows = masked(transfer(idx), [MX + "Hips", MX + "Spine"], MX + "Hips") * (1 - k1)[:, None]
    rows[:, BI[b1.name]] += k1 * (1 - k2)
    rows[:, BI[b2.name]] += k1 * k2
    W[idx] = rows

# Clean up: at most four bones per vertex, nothing under 1%, rows summing to one.
order = np.argsort(-W, axis=1)
W[np.arange(N)[:, None], order[:, 4:]] = 0
W[W < 0.01] = 0
W /= W.sum(1, keepdims=True)
assert np.isfinite(W).all() and np.allclose(W.sum(1), 1)
for g_ in [g_ for g_ in body.vertex_groups if g_.name in BI]:
    body.vertex_groups.remove(g_)
for n, j in BI.items():
    nz = np.nonzero(W[:, j])[0]
    if len(nz):
        vg = body.vertex_groups.new(name=n)
        for vi in nz:
            vg.add([int(vi)], float(W[vi, j]), "REPLACE")
body.parent = rig
mod = body.modifiers.new("Armature", "ARMATURE")
mod.object = rig
print("RIG_SKIN groups", len([g_ for g_ in body.vertex_groups if g_.name in BI]),
      "max influences", int((W > 0).sum(1).max()))


# --- The spear on its bone ---------------------------------------------------------
def mount(obj, bone_name, world):
    bone = arm_data.bones[bone_name]
    obj.parent = rig
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    obj.matrix_parent_inverse = Matrix.Translation((0, -bone.length, 0))
    obj.matrix_basis = bone.matrix_local.inverted() @ world


for c in spear.users_collection:
    c.objects.unlink(spear)
sc.collection.objects.link(spear)
mount(spear, "Spear", F_R)
props = bpy.data.collections.get("Props")
if props is not None and not props.objects:
    bpy.data.collections.remove(props)

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
for side in ("Right", "Left"):
    reset_pose()
    pose_hand(GRIPS[side])
    act = bpy.data.actions.new("grip_spear_" + side[0].lower())
    act.use_fake_user = True
    rig.animation_data.action = act
    for f in CHAINS:
        for i in range(1, 4):
            pb = rig.pose.bones[f"{MX}{side}Hand{f}{i}"]
            pb.keyframe_insert("rotation_quaternion", frame=1)
    rig.animation_data.action = None
    GRIP_ACTIONS[side] = act
reset_pose()

for p, d, v in (("support_ik", "Left hand holds the shaft at HandIK.L (SpearGrip.L slides and turns it)", 1.0),
                ("spear_ik", "Right hand follows HandIK.R, which follows SpearCtrl", 0.0),
                ("leg_ik", "Feet follow FootIK.L and FootIK.R", 0.0)):
    rig[p] = v
    rig.id_properties_ui(p).update(min=0.0, max=1.0, description=d)


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


for side, act in GRIP_ACTIONS.items():
    for f in CHAINS:
        for i in range(1, 4):
            pb = rig.pose.bones[f"{MX}{side}Hand{f}{i}"]
            c = pb.constraints.new("ACTION")
            c.name = act.name
            c.action = act
            if hasattr(c, "action_slot") and len(act.slots):
                c.action_slot = act.slots[0]
            c.use_eval_time = True
            c.eval_time = 0.0
            c.frame_start, c.frame_end = 1, 2
            c.mix_mode = "BEFORE_FULL"


# --- Controls --------------------------------------------------------------------
mod.show_viewport = False   # the pole searches below update the scene many times


def child_of(pb, target):
    c = pb.constraints.new("CHILD_OF")
    c.target, c.subtarget = rig, target
    c.inverse_matrix = rig.data.bones[target].matrix_local.inverted()
    return c


child_of(rig.pose.bones["SpearCtrl"], MX + "Spine2").name = "follow chest"
child_of(rig.pose.bones["HandIK.R"], "SpearCtrl").name = "follow spear"
# SpearGrip.L slides along the shaft and turns about it, nothing else.
pb = rig.pose.bones["SpearGrip.L"]
pb.rotation_mode = "XYZ"
pb.lock_location = (True, False, True)
pb.lock_rotation = (True, False, True)
pb.lock_scale = (True, True, True)


def add_ik(chain_bone, end_bone, target, pole, prop, calib=None):
    """IK on a two-bone chain, its pole angle set so the rest pose stays where it is with the
    target on the end bone's rest (`calib`: where to hold a target that rests elsewhere while
    the angle is found)."""
    pb = rig.pose.bones[chain_bone]
    c = pb.constraints.new("IK")
    c.target, c.subtarget = rig, target
    c.pole_target, c.pole_subtarget = rig, pole
    c.chain_count = 2
    root = rig.pose.bones[chain_bone].parent.name
    rest = {n: rig.pose.bones[n].matrix.copy() for n in (chain_bone, root)}
    if calib is not None:
        set_world(rig.pose.bones[target], calib)

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
    if calib is not None:
        rig.pose.bones[target].matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    print("RIG_IK", chain_bone, "pole angle %.1f (from the bones %.1f)" % (best[1], ang), "rest error %.5f" % best[0])


add_ik(MX + "LeftForeArm", MX + "LeftHand", "HandIK.L", "ElbowPole.L", "support_ik", calib=HL_REST)
add_ik(MX + "RightForeArm", MX + "RightHand", "HandIK.R", "ElbowPole.R", "spear_ik")
add_ik(MX + "RightLeg", MX + "RightFoot", "FootIK.R", "KneePole.R", "leg_ik")
add_ik(MX + "LeftLeg", MX + "LeftFoot", "FootIK.L", "KneePole.L", "leg_ik")

# Each twist bone copies most of its hand's roll about the forearm.
for side, _ in SIDES:
    c = rig.pose.bones[side + "ForeArmTwist"].constraints.new("COPY_ROTATION")
    c.target, c.subtarget = rig, MX + side + "Hand"
    c.use_x = c.use_z = False
    c.target_space = c.owner_space = "LOCAL"
    c.influence = 0.85


def thigh_driver(bone, expr):
    """Turn a bone about its x axis by an expression of the thighs' swing (l, r: forward +)."""
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
    drv.expression = expr


# The front flap swings forward with the leading thigh; the back flap and the cape back
# with the trailing one.
thigh_driver("FlapFront1", f"{FLAP_FOLLOW} * max(0, l, r)")
thigh_driver("FlapBack1", f"{FLAP_FOLLOW} * min(0, l, r)")
thigh_driver("Cape1", f"{CAPE_FOLLOW} * min(0, l, r)")

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
    side = "L" if ("Left" in n or n.endswith(".L")) else ("R" if ("Right" in n or n.endswith(".R") or n == "Spear") else "C")
    pb.color.palette = {"L": "THEME04", "R": "THEME01", "C": "THEME09"}[side]
    if n == "SpearCtrl":
        pb.custom_shape, pb.custom_shape_scale_xyz = W_CUBE, (0.2, 1.0, 0.2)
    elif n == "SpearGrip.L":
        pb.custom_shape, pb.custom_shape_scale_xyz = W_RING, (0.6, 0.6, 0.6)
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


def pose_collar(side, s, down, protract=0):
    """The collarbone lowered and drawn forward (degrees)."""
    set_turn(MX + side + "Shoulder", turn("Z", -s * protract) @ turn("Y", s * down))


def spear_place(fist, yaw, slope, roll):
    """Where the spear goes (4x4, its own space to the armature's): the middle of the right
    fist at `fist`, its head raised `slope` and turned `yaw` to his left of straight ahead
    (degrees), turned `roll` about its length from where its x axis lies level."""
    yaw, slope, roll = (math.radians(v) for v in (yaw, slope, roll))
    a = np.array([math.cos(slope) * math.sin(yaw), -math.cos(slope) * math.cos(yaw), math.sin(slope)])
    x = unit(np.cross(a, (0.0, 0.0, 1.0)))
    R = np.stack([x, np.cross(a, x), a], 1) @ np.array(Matrix.Rotation(roll, 3, "Z"))
    M = np.eye(4)
    M[:3, :3], M[:3, 3] = R, np.array(fist) - R @ (0, 0, GRIPS["Right"]["fist"])
    return M


def npm(M):
    return np.array(M)


def two_bone(sh, tgt, L1, L2, pole):
    """Elbows of a two-bone arm from the shoulder sh to targets tgt (K, 3), bending toward `pole`."""
    d = tgt - sh
    r = np.linalg.norm(d, axis=1)
    u = d / r[:, None]
    rc = np.minimum(r, 0.999 * (L1 + L2))
    ca = np.clip((L1 ** 2 + rc ** 2 - L2 ** 2) / (2 * L1 * rc), -1, 1)
    p = pole[None] - (u @ pole)[:, None] * u
    p /= np.linalg.norm(p, axis=1, keepdims=True)
    return sh + L1 * (ca[:, None] * u + np.sqrt(1 - ca ** 2)[:, None] * p), r


sc.frame_set(1)
reset_pose()
mod.show_viewport = True
bpy.context.view_layer.update()
pbs = rig.pose.bones
group_names = {g_.index: g_.name for g_ in body.vertex_groups}
DOM = np.array([group_names[max(v.groups, key=lambda g_: g_.weight).group] if len(v.groups) else ""
                for v in body.data.vertices])
IN_HANDS = np.array([any(d.startswith(MX + side + "Hand") for side in ("Left", "Right")) for d in DOM])
NO_HAND_TRIS = TRIS[~IN_HANDS[TRIS].any(1)].tolist()
ARM_SET = tuple(MX + side + n for side in ("Left", "Right") for n in ("ForeArm", "Hand")) + ("LeftForeArmTwist", "RightForeArmTwist")
TORSO_SET = tuple(MX + n for n in ("Hips", "Spine", "Spine1", "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg")) + (
    "Cape1", "Cape2", "FlapFront1", "FlapFront2", "FlapBack1", "FlapBack2")
FOREARM_TRIS = TRIS[np.isin(DOM, ARM_SET)[TRIS].all(1)].tolist()
TORSO_TRIS = TRIS[np.isin(DOM, TORSO_SET)[TRIS].all(1)].tolist()
# The spear's surface sampled every 5 mm along its edges: the shaft is long quads with
# vertices only at its rings, so its vertices alone miss most of it. Inside a fist (6 cm
# either side of its middle along the shaft) its clearance is the grip's.
SP_E = np.array([e.vertices[:] for e in spear.data.edges])
SP_S = [SP_V]
for a, b in SP_E:
    n = int(np.linalg.norm(SP_V[b] - SP_V[a]) / 0.005)
    if n > 1:
        t = np.arange(1, n)[:, None] / n
        SP_S.append(SP_V[a] + t * (SP_V[b] - SP_V[a]))
SP_S = np.concatenate(SP_S)
FISTS = [GRIPS[side]["fist"] for side in ("Right", "Left")]
IN_FIST = np.any([np.abs(SP_S[:, 2] - z) < 0.06 for z in FISTS], 0)
FIST_F = np.array([np.any([np.abs(SP_V[f, 2] - z).max() < 0.06 for z in FISTS]) for f in SP_F])


def spear_axis(Mw):
    """The spear's head: degrees above level, degrees to his left of straight ahead, and how
    far it points ahead (its unit vector's -y)."""
    a = Mw[:3, 2]
    return {"slope": math.degrees(math.asin(a[2])), "yaw": math.degrees(math.atan2(a[0], -a[1])), "ahead": float(-a[1])}


def spear_fit(P):
    """The spear against the posed body P (its hands left out): body triangles through it,
    its nearest approach outside the fists, its butt's height and its heading; and forearm
    and hand triangles through the torso, the legs, the cape and the flaps."""
    tree = BVHTree.FromPolygons([Vector(p) for p in P], NO_HAND_TRIS)
    Mw = npm(spear.matrix_world)
    Sw = SP_V @ Mw[:3, :3].T + Mw[:3, 3]
    st = BVHTree.FromPolygons([Vector(q) for q in Sw], SP_F)
    pairs = {(f, i) for f, i in st.overlap(tree)} | {(f, i) for i, f in tree.overlap(st)}
    cuts = sum(1 for f, _ in pairs if not FIST_F[f])
    Ss = SP_S[~IN_FIST] @ Mw[:3, :3].T + Mw[:3, 3]
    d = np.array([tree.find_nearest(Vector(q), 0.3)[3] or 0.3 for q in Ss])
    at = BVHTree.FromPolygons([Vector(p) for p in P], FOREARM_TRIS)
    tt = BVHTree.FromPolygons([Vector(p) for p in P], TORSO_TRIS)
    return {"cuts": cuts, "shaft": float(d.min()), "butt": float((Mw @ np.r_[0, 0, SP_BUTT, 1])[2]),
            "arm_cuts": len(at.overlap(tt)), **spear_axis(Mw)}


def wrist_bend(side):
    """Degrees the hand bends from the forearm's line."""
    f = pbs[MX + side + "ForeArm"].matrix.to_3x3().col[1]
    return math.degrees(f.angle(pbs[MX + side + "Hand"].matrix.to_3x3().col[1]))


# The pose is searched as the spear's place: where the right fist is, the spear's heading,
# slope and turn about its length, and the left hand's turn round the shaft and slide
# along it; both arms reach their hands by IK. Every place is ranked first in closed form
# (two-bone arms, no skin): how far each arm reaches, how far each wrist bends and twists,
# the spear's slope and heading, the fist's place and the left hand's slide. The best
# places are measured against the body the pose leaves still (all but the arms): the
# shaft and the forearms must keep clear of it, and the shaft of the forearms. The best
# few hundred of those are posed on the rig, both arms on IK, and ranked again with the
# wrists' true bend and twist; then the skin is checked in that order until the spear
# and the forearms are clear of the body.
mod.show_viewport = False
SH = {}
for side, s in SIDES:
    pose_collar(side, s, *COLLAR[side])
    SH[side] = np.array(pbs[MX + side + "Arm"].head)
L1 = arm_data.bones[MX + "LeftArm"].length
L2 = arm_data.bones[MX + "LeftForeArm"].length
SPEAR_REST = npm(arm_data.bones["Spear"].matrix_local)
SGL = npm(arm_data.bones["SpearGrip.L"].matrix_local)
HIKL = npm(arm_data.bones["HandIK.L"].matrix_local)
HR = npm(arm_data.bones[MX + "RightHand"].matrix_local)
FR = npm(F_R)
# Each forearm's rest frame for the twist: along it, and its bend's axis (the rest arm is
# bent a little, in the plane the IK keeps it in).
FORE0 = {}
for side, _ in SIDES:
    a_, e_, w_ = (np.array(arm_data.bones[MX + side + n].head_local) for n in ("Arm", "ForeArm", "Hand"))
    FORE0[side] = (unit(w_ - e_), unit(np.cross(e_ - a_, w_ - e_)),
                   np.array(arm_data.bones[MX + side + "Hand"].matrix_local.to_3x3()))


def grip_l(slide, phi):
    """SpearGrip.L's pose (local): slid along the shaft and turned round it."""
    M = np.eye(4)
    M[:3, :3] = np.array(Matrix.Rotation(math.radians(phi), 3, "Y"))
    M[1, 3] = slide
    return M


def frames(y, n):
    """Rotations (K, 3, 3) with columns y, n (made square to y) and y x n."""
    n = unit(n - (n * y).sum(-1, keepdims=True) * y)
    return np.stack([y, n, np.cross(y, n)], -1)


def arm_reach(side, T):
    """An arm reaching hand poses T (K, 4, 4) in closed form: its elbows, the reach (share of
    the arm's length), the wrist's bend and twist (degrees; the twist is the hand's turn
    about its length against the forearm, from rest) and the reach's cost."""
    wr, hand = T[:, :3, 3], T[:, :3, :3]
    elbow, r = two_bone(SH[side], wr, L1, L2, unit(ELBOW_DIR[side]))
    y = unit(wr - elbow)
    bend = np.degrees(np.arccos(np.clip((y * hand[:, :, 1]).sum(1), -1, 1)))
    y0, n0, h0 = FORE0[side]
    R = frames(y, np.cross(elbow - SH[side], wr - elbow)) @ frames(y0[None], n0[None])[0].T
    Q = np.swapaxes(R @ h0, 1, 2) @ hand
    qw = np.sqrt(np.maximum(0, 1 + Q[:, 0, 0] + Q[:, 1, 1] + Q[:, 2, 2])) / 2
    qy = np.sign(Q[:, 0, 2] - Q[:, 2, 0]) * np.sqrt(np.maximum(0, 1 - Q[:, 0, 0] + Q[:, 1, 1] - Q[:, 2, 2])) / 2
    twist = np.degrees(2 * np.arctan2(qy, qw))
    twist = (twist + 180) % 360 - 180
    reach = r / (L1 + L2)
    return elbow, reach, 200 * np.maximum(0, reach - 0.92) + 200 * np.maximum(0, 0.5 - reach), bend, twist


def wrist_cost(bend, twist):
    return 0.5 * np.maximum(0, np.asarray(bend) - 15) + 0.3 * np.maximum(0, np.abs(twist) - 40)


LEFT = list(itertools.product(STAND["slide"], STAND["phi"]))
B_L = np.stack([SGL @ grip_l(sl, ph) @ np.linalg.inv(SGL) @ HIKL for sl, ph in LEFT])
SLIDE = np.array([sl for sl, _ in LEFT])
PLACES = list(itertools.product(*[STAND[k_] for k_ in ("x", "y", "z", "yaw", "slope", "roll")]))
S_ALL = np.stack([spear_place(p[:3], *p[3:]) for p in PLACES])
A_ALL = S_ALL @ np.linalg.inv(FR)                  # how the pose moves the right hand and all it holds
T_R = A_ALL @ HR
EL_R, REACH_R, C_R, BEND_R, TW_R = arm_reach("Right", T_R)
K = np.arange(len(PLACES))
JL = np.zeros(len(PLACES), int)
C_L = np.zeros(len(PLACES))
EL_L, T_LJ = np.zeros((len(PLACES), 3)), np.zeros((len(PLACES), 4, 4))
BEND_L, TW_L = np.zeros(len(PLACES)), np.zeros(len(PLACES))
for c0 in range(0, len(PLACES), 1000):              # the left hand's best hold on the shaft, per place
    sl_ = slice(c0, c0 + 1000)
    T = (A_ALL[sl_, None] @ B_L[None]).reshape(-1, 4, 4)
    el, rc, cr, bd, tw = (a.reshape(-1, len(LEFT), *a.shape[1:]) for a in arm_reach("Left", T))
    c = cr + wrist_cost(bd, tw) + 30 * np.abs(SLIDE)[None]
    j = np.argmin(c, 1)
    i = np.arange(len(j))
    JL[sl_], C_L[sl_], EL_L[sl_], BEND_L[sl_], TW_L[sl_] = j, cr[i, j] + 30 * np.abs(SLIDE[j]), el[i, j], bd[i, j], tw[i, j]
    T_LJ[sl_] = T.reshape(-1, len(LEFT), 4, 4)[i, j]
P_ = np.array(PLACES, float)
BUTT = (S_ALL @ np.r_[0, 0, SP_BUTT, 1])[:, 2]
C_PLACE = (0.3 * np.abs(P_[:, 4] - SPEAR_SLOPE) + 0.2 * np.abs(P_[:, 3] - SPEAR_YAW)
           + 10 * np.linalg.norm(P_[:, :3] - FIST_HOME, axis=1) + C_R + C_L)
C_PLACE[BUTT < GROUND_Z] = np.inf
COST1 = C_PLACE + wrist_cost(BEND_R, TW_R) + wrist_cost(BEND_L, TW_L)

# Clearances in closed form. The still body: every triangle no arm or collarbone moves.
ARM_GROUPS = {g_.index for g_ in body.vertex_groups if any(t in g_.name for t in ("Shoulder", "Arm", "Hand"))}
MOVES = np.array([sum(g_.weight for g_ in v.groups if g_.group in ARM_GROUPS) for v in body.data.vertices]) > 0.01
STILL = BVHTree.FromPolygons([Vector(p) for p in V], TRIS[~MOVES[TRIS].any(1)].tolist())
# The spear's axis every 2 cm with its radius there, the fists (7 cm either side) left out.
AX_Z = np.arange(SP_BUTT + 0.01, SP_TIP - 0.01, 0.02)
AX_R = np.array([max(float(np.linalg.norm(SP_V[np.abs(SP_V[:, 2] - z) < 0.03, :2], axis=1).max(initial=0)),
                     float(spear["shaft_r"])) for z in AX_Z])
keep = np.all([np.abs(AX_Z - f) > 0.07 for f in FISTS], 0)
AX_Z, AX_R = AX_Z[keep], AX_R[keep]
AX_H = np.c_[np.zeros((len(AX_Z), 2)), AX_Z, np.ones(len(AX_Z))]


def seg_pts(a, b, n=6):
    t = np.linspace(0, 1, n)[:, None]
    return a + t * (b - a)


def closed_clearance(k):
    """The shaft's and the forearms' clearance (m) from the still body, and the shaft's
    from the forearms, at place k."""
    pts = (S_ALL[k] @ AX_H.T).T[:, :3]
    shaft = min((STILL.find_nearest(Vector(p), 0.2)[3] or 0.2) - r for p, r in zip(pts, AX_R))
    fore, cross = 0.2, 0.2
    for el, wr in ((EL_R[k], T_R[k, :3, 3]), (EL_L[k], T_LJ[k, :3, 3])):
        q = seg_pts(el, wr)
        fore = min(fore, min((STILL.find_nearest(Vector(p), 0.2)[3] or 0.2) for p in q) - FOREARM_R)
        ab = wr - el
        t = np.clip(((pts - el) @ ab) / (ab @ ab), 0, 1)
        cross = min(cross, float((np.linalg.norm(pts - (el + t[:, None] * ab), axis=1) - AX_R).min()) - FOREARM_R)
    return shaft, fore, cross


ORDER, n_seen = [], 0
for k in np.argsort(COST1):
    if not np.isfinite(COST1[k]) or len(ORDER) >= 300:
        break
    n_seen += 1
    shaft, fore, cross = closed_clearance(k)
    if shaft >= SPEAR_GAP / 2 and fore >= 0 and cross >= 0.005:
        ORDER.append(int(k))
print("RIG_STAND_PLACES %d places, %d holds on the shaft each; %d clear of %d ranked; best closed-form costs"
      % (len(PLACES), len(LEFT), len(ORDER), n_seen), np.round(COST1[ORDER[:5]], 1).tolist())
rig["spear_ik"] = rig["support_ik"] = 1.0
rig.update_tag()


def pose_place(k, j):
    """Pose place k with the left hand's hold j, both arms on IK, each elbow pole out from
    the closed-form elbow."""
    set_world(pbs["SpearCtrl"], Matrix((A_ALL[k] @ SPEAR_REST).tolist()))
    sl, ph = LEFT[j]
    g = pbs["SpearGrip.L"]
    g.location = (0, sl, 0)
    g.rotation_euler = (0, math.radians(ph), 0)
    for side, elbow, wr in (("Right", EL_R[k], T_R[k, :3, 3]), ("Left", EL_L[k], T_LJ[k, :3, 3])):
        u, d = unit(wr - SH[side]), unit(ELBOW_DIR[side])
        pole = pbs["ElbowPole." + side[0]]
        M = pole.bone.matrix_local.copy()
        M.translation = Vector(elbow + 0.3 * unit(d - (d @ u) * u))
        set_world(pole, M)


def wrist(side):
    """The wrist's bend from the forearm's line, its twist about it from rest (degrees) and
    how far the hand is from its IK target (mm)."""
    f, h = pbs[MX + side + "ForeArm"], pbs[MX + side + "Hand"]
    bend = math.degrees(f.matrix.to_3x3().col[1].angle(h.matrix.to_3x3().col[1]))
    carried = f.matrix @ f.bone.matrix_local.inverted() @ h.bone.matrix_local
    twist = math.degrees((carried.inverted() @ h.matrix).to_quaternion().to_swing_twist("Y")[1])
    return bend, twist, (h.head - pbs["HandIK." + side[0]].head).length * 1000


scored = []
for k in ORDER:
    j = int(JL[k])
    pose_place(k, j)
    w = {side: wrist(side) for side, _ in SIDES}
    cost = C_PLACE[k] + sum(float(wrist_cost(b, t)) for b, t, _ in w.values())
    cost += 1000 * any(m > 5 for _, _, m in w.values())
    scored.append((cost, k, j, w))
    if len(scored) <= 3:
        print("RIG_STAND_TWIST closed form R %.0f L %.0f, posed" % (TW_R[k], TW_L[k]),
              {s_: np.round(v, 1).tolist() for s_, v in w.items()})
scored.sort(key=lambda r: r[0])
mod.show_viewport = True
STAND_PICK, checked = None, 0
for cost, k, j, w in scored[:150]:
    pose_place(k, j)
    fit = spear_fit(posed_mesh())
    checked += 1
    if (not fit["cuts"] and fit["shaft"] >= SPEAR_GAP and not fit["arm_cuts"] and fit["butt"] >= GROUND_Z
            and all(b <= 35 and abs(t) <= 80 and m < 5 for b, t, m in w.values())):
        STAND_PICK = (cost, k, j, w, fit)
        break
    if checked <= 5:
        print("RIG_STAND_REJECT", dict(zip(("x", "y", "z", "yaw", "slope", "roll"), PLACES[k])), LEFT[j],
              {s_: np.round(v, 1).tolist() for s_, v in w.items()}, {k_: round(v, 3) for k_, v in fit.items()})
assert STAND_PICK, "no place of the spear is clear of the body"
cost, k, j, w, fit = STAND_PICK
STAND_PLACE = dict(zip(("x", "y", "z", "yaw", "slope", "roll"), PLACES[k]))
STAND_PLACE.update(slide=LEFT[j][0], phi=LEFT[j][1])
print("RIG_STAND_SEARCH the %d. checked fits (cost %.1f): %s; wrists (bend, twist, miss mm) %s; %s" % (
    checked, cost, STAND_PLACE, {s_: np.round(v, 1).tolist() for s_, v in w.items()},
    {k_: round(v, 3) for k_, v in fit.items()}))
pose_place(k, j)
# Both arms as IK has put them, keyed as they are, so the pose holds with the IK off too.
ik_pose = {(side, n): pbs[MX + side + n].matrix.copy() for side, _ in SIDES for n in ("Arm", "ForeArm", "Hand")}
rig["spear_ik"] = rig["support_ik"] = 0.0
rig.update_tag()
bpy.context.view_layer.update()
for side, _ in SIDES:
    for n in ("Arm", "ForeArm", "Hand"):
        set_world(pbs[MX + side + n], ik_pose[(side, n)])
rig["support_ik"] = 1.0
rig.update_tag()
bpy.context.view_layer.update()
# The control exactly where the pose put the spear (the chest is at rest, so its Child Of
# constraint changes nothing): HandIK.R follows SpearCtrl onto the right hand.
set_world(pbs["SpearCtrl"], pbs["Spear"].matrix.copy())
stand = bpy.data.actions.new("stand")
stand.use_fake_user = True
rig.animation_data.action = stand
for side, _ in SIDES:
    for n in ("Shoulder", "Arm", "ForeArm", "Hand"):
        pbs[MX + side + n].keyframe_insert("rotation_quaternion", frame=1)
for n in ("SpearCtrl", "ElbowPole.L", "ElbowPole.R"):
    pbs[n].keyframe_insert("location", frame=1)
    pbs[n].keyframe_insert("rotation_quaternion", frame=1)
pbs["SpearGrip.L"].keyframe_insert("location", frame=1)
pbs["SpearGrip.L"].keyframe_insert("rotation_euler", frame=1)
bpy.context.view_layer.update()
fk = {n: pbs[MX + n].matrix.copy() for n in ("RightHand", "LeftHand", "RightForeArm", "LeftForeArm")}


def ik_moves(prop, value):
    rig[prop] = value
    rig.update_tag()
    bpy.context.view_layer.update()
    out_ = {n: "%.1f mm %.1f deg" % ((pbs[MX + n].matrix.translation - M.translation).length * 1000,
                                       math.degrees(pbs[MX + n].matrix.to_quaternion().rotation_difference(
                                           M.to_quaternion()).angle)) for n, M in fk.items()}
    rig[prop] = 1.0 - value
    rig.update_tag()
    bpy.context.view_layer.update()
    return out_


print("RIG_STAND fists: right", np.round(np.array(pbs["Spear"].head), 3).tolist(), "left",
      np.round(np.array(pbs["SpearGrip.L"].head), 3).tolist())
print("RIG_STAND spear heading", {k_: round(v, 1) for k_, v in spear_axis(npm(spear.matrix_world)).items()},
      "| spear_ik on moves", ik_moves("spear_ik", 1.0), "| support_ik off moves", ik_moves("support_ik", 0.0))

# The blade's flat level in the standard pose: the spear turned about its own axis in the
# fist (the shaft is round, so the grip is the same).
Mw = npm(spear.matrix_world)
rho = math.atan2(-Mw[2, 0], Mw[2, 1])
if abs(rho) > math.pi / 2:
    rho -= math.copysign(math.pi, rho)
mount(spear, "Spear", F_R @ Matrix.Rotation(rho, 4, "Z"))
bpy.context.view_layer.update()
print("RIG_BLADE turned %.1f deg about the shaft; its width now rises %.3f" % (
    math.degrees(rho), spear.matrix_world.to_3x3().col[0].normalized().z))

# --- Checks in the standard pose and the T-pose ------------------------------------
P = posed_mesh()
STAND_FIT = spear_fit(P)
STAND_FIT["bend_L"], STAND_FIT["bend_R"] = wrist_bend("Left"), wrist_bend("Right")
print("RIG_CHECK_STAND", {k_: round(v, 3) for k_, v in STAND_FIT.items()})
assert not STAND_FIT["cuts"] and not STAND_FIT["arm_cuts"]
rig.animation_data.action = None
rig["support_ik"] = 0.0
reset_pose()
TPOSE_FIT = spear_fit(posed_mesh())
print("RIG_CHECK_TPOSE", {k_: round(v, 3) for k_, v in TPOSE_FIT.items()})
rig["support_ik"] = 1.0
rig.animation_data.action = stand
if hasattr(rig.animation_data, "action_slot") and len(stand.slots):
    rig.animation_data.action_slot = stand.slots[0]
rig.update_tag()
sc.frame_set(1)
bpy.context.view_layer.update()

# --- Save ---------------------------------------------------------------------
rig["grip"] = {w: {"across_palm_at": round(g_["U"], 4), "tilt_deg": g_["tilt"], "slide": g_["slide"],
                   "fist_z": round(g_["fist"], 4), "energy": round(g_["E"], 2), "closest_mm": g_["closest_mm"]}
               for w, g_ in GRIPS.items()}
rig["stand"] = {k_: float(v) for k_, v in STAND_PLACE.items()}
rig["fit"] = {"stand": {k_: round(v, 4) for k_, v in STAND_FIT.items()},
              "tpose": {k_: round(v, 4) for k_, v in TPOSE_FIT.items()}, "blade_turn_deg": round(math.degrees(rho), 2)}
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
