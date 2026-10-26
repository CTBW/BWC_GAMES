"""Rig the goblin shaman for Mixamo clips, his right hand closed round the staff (background Blender).

  blender -b goblin_shaman_base.blend --factory-startup --python rig_goblin_shaman.py -- <out.blend>

Starts from goblin_shaman_base.blend or goblin_shaman_beak_base.blend (build_goblin_shaman.py,
the horned and the beak mask) and follows the goblin
archer's rig_goblin_archer.py, with the spearman's skirt flaps (rig_goblin_spear.py):
1. A Mixamo-named armature with finger bones placed on each hand's mesh: three fingers
   and a thumb (Thumb, Index, Middle and Ring 1-4). Forearm twist bones, two bones down
   the red front flap and two down the back of the skirt.
2. Skin: the body is one shell with the skirt fused to it, and each leg is a shell of its
   own. Bone heat on the body with the skirt cut away below CUT_Z, where it hangs free of
   the legs, and on each leg with that leg's bones and the hips; geometric weights on the
   hands, cut from the body past the wrist, so a finger moves only its own skin. Below
   the belt the front flap hangs from its own bones; the skirt hangs from the back bones
   down the middle of its back and, toward the sides, from the hips and the thigh it
   covers, as the rabble's does. The face round the mask follows the head alone, so the
   mask, rigid on the head, keeps its gap. The eyes and tusks follow the head; the
   necklace, its fangs and the skull pendant are rigid on the chest; the belt's skull,
   pouches, bone and feathers are rigid on the hips.
3. Grips, solved on the skin as for the archer: the right hand closes round the staff's
   leather grip, laid across the palm, at the tilt and the place along it (within SLIDES
   of its middle) that close the three fingers best; the thumb closes the other way,
   toward the index finger. The left hand curls loosely round a rod RELAX_R thick. Each
   grip is a one-frame Action applied by Action constraints on the finger bones.
4. Props: the staff rides the `Staff` bone in the right fist, its skull toward the thumb
   and turned STAFF_ROLL about its length, so the skull faces away from the wrist (ahead
   when the forearm points forward). The mask plate rides the `Mask` bone, a child of the
   head. The right hand holds its turn on the staff whatever a clip does to the wrist
   (`StaffHold`, `staff_hold`).
5. Controls as for the archer, mirrored for the staff hand: `StaffCtrl` follows the chest
   and `HandIK.R` follows `StaffCtrl`; `HandIK.L` follows the chest; `staff_ik`, `cast_ik`
   and `leg_ik` (0 by default) switch on IK for the right arm, the left arm and the feet.
6. Standard pose: the skin stays bound to the T-pose, and the one-frame Action `stand`
   lets the arms hang, the left as the rabble's. The right arm's angles (with the hand's
   roll) are searched for the staff held beside him nearest upright, its skull facing
   ahead and its foot as low as the grip allows, STAFF_GAP clear of the body and the mask
   and, seen from the front, clear of his head (HEAD_CLEAR).
Every control and helper bone is non-deforming and in its own bone collection; the
deforming bones are what a game export keeps.
"""
import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

H = 1.82 * 40 / 49
MX = "mixamorig:"
SIDES = (("Left", 1), ("Right", -1))
FINGERS = ("Index", "Middle", "Ring")   # three fingers and a thumb on each hand
WRIST_U = 0.69      # the wrist, distance from the centre line (both hands)
KNUCKLE_U = 0.778   # the knuckle row (the fingers part from 0.784, index first)
PHALANX = (0.45, 0.30, 0.25)   # finger length shares of the three segments
RELAX_R = 0.02      # the left hand curls loosely round a rod this thick
SLIDES = (-0.04, -0.02, 0.0, 0.02, 0.04)   # the fist's places along the staff's grip from its middle
STAFF_ROLL = -90    # degrees about its length: its skull, facing -y in its own space, away from the wrist
CUT_Z = 0.64        # below this the skirt hangs free of the body: a front flap, the wrap and two tatters
FLAP_FOLLOW = 0.8   # the flaps swing with the leading (front) and trailing (back) thigh
SKIRT_LEG = 0.7     # the skirt's sides follow the thigh they cover this far at the hem
MASK_HEAD = (0.015, 0.045)   # the face within the first of these of the mask follows the head alone,
MASK_NECK = (1.17, 1.21)     # fading out by the second, and from the second height up
STAFF_GAP = 0.02    # the staff keeps this far off the body and the mask in the standard pose,
HEAD_CLEAR = 0.22   # and between his shoulders and the top of his head (HEAD_ZS) this far out to his
HEAD_ZS = (1.12, 1.50)   # right, clear of his head and ears seen from the front (the skull may rise above it)
GROUND_Z = 0.02     # its foot at least this far off the ground,
FOOT_Z = 0.04       # and preferably no higher than this (the grip is at his hip height, so a fist
                    # that holds the staff upright keeps its foot well off the ground)
# The left arm's standard pose (degrees), as the rabble's: collarbone lowered, upper arm
# out from hanging straight down and forward, elbow bent forward, wrist turned toward the
# little finger, hand rolled about its length. The right arm's is searched (below) from
# the ranges in STAND_R.
STAND_L = {"collar": 6, "out": 14, "forward": 6, "elbow": 20, "wrist": 20, "roll": 0}
STAND_R = {"collar": (6,), "out": (14, 20, 26, 32), "forward": (-20, -10, 0, 10), "elbow": range(50, 111, 10),
           "wrist": (-20, -10, 0, 10), "roll": range(0, 61, 10)}
# Joints of the left side read off the T-pose (front and side views on a 5 cm grid and
# the hand on a 1 cm grid); the right side mirrors x. The spine's depth is measured below.
# His head sits far forward of his chest, so the neck leans forward to it.
J0 = {
    "Head": (0, -0.08, 1.235), "HeadTop_End": (0, -0.15, 1.47),
    "Shoulder": (0.04, 0.03, 1.13), "Arm": (0.20, 0.02, 1.12), "ForeArm": (0.44, -0.005, 1.075),
    "Hand": (WRIST_U, -0.11, 1.063),
    "UpLeg": (0.105, -0.02, 0.645), "Leg": (0.18, -0.055, 0.40), "Foot": (0.222, -0.03, 0.095),
    "ToeBase": (0.25, -0.16, 0.03), "Toe_End": (0.265, -0.255, 0.02),
}
SPINE_Z = {"Hips": 0.68, "Spine": 0.77, "Spine1": 0.87, "Spine2": 0.98, "Neck": 1.14}

argv = sys.argv[sys.argv.index("--") + 1:]
out_blend = Path(argv[0]).resolve()
sc = bpy.context.scene
body = bpy.data.objects["GoblinShaman"]
staff = bpy.data.objects["Staff"]
mask = bpy.data.objects["MaskPlate"]
V = np.array([v.co[:] for v in body.data.vertices])
N = len(V)
assert abs(V[:, 2].max() - H) < 0.005 and abs(V[:, 2].min()) < 0.005
ST_V = np.array([v.co[:] for v in staff.data.vertices])     # the staff's own space: grip middle at 0, skull up
ST_F = [list(p.vertices) for p in staff.data.polygons]
ST_FOOT = float(ST_V[:, 2].min())
G_LO, G_HI = staff["grip"]
ROLL = Matrix.Rotation(math.radians(STAFF_ROLL), 4, "Z")
MASK_WORLD = mask.matrix_world.copy()
MASK_V = np.array([(MASK_WORLD @ v.co)[:] for v in mask.data.vertices])
MASK_F = [list(p.vertices) for p in mask.data.polygons]


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


def components(mask_):
    """Connected parts of the vertices in `mask_` (through the mesh's edges), largest first."""
    lab = np.where(mask_, np.arange(N), N)
    e = EDGES[mask_[EDGES[:, 0]] & mask_[EDGES[:, 1]]]
    while True:   # each vertex takes the smallest label among its neighbours, until none changes
        new = lab.copy()
        m = np.minimum(lab[e[:, 0]], lab[e[:, 1]])
        np.minimum.at(new, e[:, 0], m)
        np.minimum.at(new, e[:, 1], m)
        if (new == lab).all():
            break
        lab = new
    return sorted((np.nonzero(lab == k)[0] for k in np.unique(lab[mask_])), key=len, reverse=True)


# --- Shells and the skirt ------------------------------------------------------------
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
    lo, hi = V[p].min(0), V[p].max(0)
    if lo[2] < 0.01:
        kind[k] = "leg"
    elif lo[2] > 1.2:
        kind[k] = "head"        # the eyes and the tusks
    elif lo[2] > 0.95:
        kind[k] = "chest"       # the necklace's cord, its fangs and the skull pendant
    elif hi[2] < 0.9:
        kind[k] = "belt"        # the belt's skull, the pouches, the bone and the feathers
    else:
        kind[k] = "other"
counts = {}
for kd in kind.values():
    counts[kd] = counts.get(kd, 0) + 1
print("RIG_SHELLS main %d vertices," % len(parts[main]), counts)
assert counts == {"leg": 2, "head": 5, "chest": 7, "belt": 10}

# Below CUT_Z the body shell is only the skirt, in separate pieces: the red front flap,
# the wrap round the sides and the back, and two narrow tatters beside the flap.
FLAP_F, WRAP, TATTER = (np.zeros(N, bool) for _ in range(3))
for c in components(in_main & (V[:, 2] < CUT_Z)):
    cen = V[c].mean(0)
    if len(c) > 30 and cen[1] < -0.12 and abs(cen[0]) < 0.05:
        FLAP_F[c] = True
    elif len(c) > 100 and cen[1] > 0:
        WRAP[c] = True
    else:
        TATTER[c] = True
SKIRT = FLAP_F | WRAP | TATTER
CORE = in_main & ~SKIRT
print("RIG_PARTS front flap %d, wrap %d, tatters %d, core %d vertices" % (FLAP_F.sum(), WRAP.sum(), TATTER.sum(), CORE.sum()))
assert FLAP_F.sum() > 50 and WRAP.sum() > 100
T3 = TRIS[CORE[TRIS].all(1)]
bvh = BVHTree.FromPolygons([Vector(p) for p in V], T3.tolist())
# The whole shell for the torso's depth: the core has a gap where the skirt is cut away.
bvh_main = BVHTree.FromPolygons([Vector(p) for p in V], TRIS[in_main[TRIS].all(1)].tolist())


def torso_mid(z):
    """Halfway between the front and the back of the body at height z."""
    ys = []
    for x in (-0.03, 0.0, 0.03):
        f = bvh_main.ray_cast(Vector((x, -1.0, z)), Vector((0, 1, 0)), 2.0)[0]
        b = bvh_main.ray_cast(Vector((x, 1.0, z)), Vector((0, -1, 0)), 2.0)[0]
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
    """Joints (armature space) and radii of the three fingers and the thumb. The hand is
    the body shell past the wrist (a little short of it, for the blend into the forearm)."""
    U = V[:, 0] * s
    in_hand = in_main & (U > WRIST_U - 0.03)
    idx = np.nonzero(in_hand)[0]
    for u_web in np.arange(0.76, 0.84, 0.002):     # past the webs the three fingers are apart
        comps = [c for c in components(in_hand & (U > u_web)) if len(c) >= 12]
        if len(comps) == len(FINGERS):
            break
    assert len(comps) == len(FINGERS), f"{side} hand: the fingers were not found"
    comps.sort(key=lambda c: V[c, 1].mean())         # index (front) to ring
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
    # Thumb: what hangs below the front of the palm. Its two phalanges lie along its axis.
    th = components(in_hand & ~in_fingers & (U > WRIST_U + 0.035) & (V[:, 1] < -0.16) & (V[:, 2] < 1.025))[0]
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
    print("RIG_THUMB", side, np.round(tj, 3).tolist(), "radius %.4f" % trad, "%d vertices" % len(HANDS[side]["thumb_idx"]))


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


class Rod:
    """A round rod along z, what the left hand curls round for a relaxed hand."""

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
        self.s, self.step, self.u0, self.y0 = s, 0.003, WRIST_U - 0.025, -0.25
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
    thumb (the staff's skull), x toward the wrist; o the field's origin on the axis."""
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
    # Where the fist sits along the field's axis: the middle of the palm, projected on it.
    best["fist_z"] = float((hand.still.mean(0) - best["o"]) @ best["R"][:, 2])
    return best


# The staff is solved turned STAFF_ROLL about its length, as it is mounted.
ST_ROLLED = ST_V @ np.array(ROLL.to_3x3()).T
GRIPS = {"Staff": solve_grip(GripHand("Right", -1), PropField(ST_ROLLED, ST_F, -0.12, 0.12), SLIDES, "Staff"),
         "Relax": solve_grip(GripHand("Left", 1), Rod(RELAX_R), (0.0,), "Relax")}
STAFF_WORLD = GRIPS["Staff"]["frame"] @ ROLL
FIST = GRIPS["Staff"]["frame"] @ Vector((0, 0, GRIPS["Staff"]["fist_z"]))
print("RIG_STAFF_GRIP the fist at %+.3f along the staff from the grip's middle (the grip runs %+.3f to %+.3f)" % (
    GRIPS["Staff"]["fist_z"], G_LO, G_HI))
assert G_LO + 0.03 < GRIPS["Staff"]["fist_z"] < G_HI - 0.03


# --- Armature ------------------------------------------------------------------
arm_data = bpy.data.armatures.new("GoblinShamanRig")
rig = bpy.data.objects.new("GoblinShamanRig", arm_data)
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


def mid_line(mask_, z_list):
    """Points down the middle of a hanging part: its median depth near the centre line at each height."""
    P = V[mask_ & (np.abs(V[:, 0]) < 0.06)]
    pts = []
    for z in z_list:
        q = P[np.abs(P[:, 2] - z) < 0.03]
        pts.append(Vector((0, float(np.median(q[:, 1])), z)))
    return pts


# Skirt: two bones down the front flap and two down the middle of the wrap's back, from
# under the belt to the hem.
for name, mask_ in (("FlapFront", FLAP_F), ("FlapBack", WRAP)):
    z0 = float(V[mask_, 2].max()) - 0.02
    z1 = float(V[mask_ & (np.abs(V[:, 0]) < 0.06), 2].min()) + 0.01
    p0, p1, p2 = mid_line(mask_, (z0, (z0 + z1) / 2, z1))
    new_bone(name + "1", p0, p1, MX + "Hips", False, FRONT)
    new_bone(name + "2", p1, p2, name + "1", True, FRONT)

# Prop bones. The staff's head is on its axis in the right fist, along the staff toward the
# skull; the mask's at the middle of the plate, up, its z axis ahead.
FS = GRIPS["Staff"]["frame"]
sb = new_bone("Staff", FIST, FIST + FS.col[2].xyz * 0.12, MX + "RightHand", False)
sb.align_roll(-STAFF_WORLD.col[1].xyz)
MASK_C = Vector(((MASK_V.min(0) + MASK_V.max(0)) / 2).tolist())
new_bone("Mask", MASK_C, MASK_C + Vector((0, 0, 0.10)), MX + "Head", False, FRONT)

# Controls (parentless; Child Of constraints do the following, as for the archer).
sc_ = new_bone("StaffCtrl", sb.head, sb.tail)
sc_.roll = sb.roll
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

PROP_BONES = ("Staff", "Mask")
DEFORM_SKIP = ("HeadTop_End", "Toe_End", "Thumb4", "Index4", "Middle4", "Ring4")
CONTROL = set(PROP_BONES) | {"StaffCtrl"} | {f"{p}.{c}" for p in ("HandIK", "ElbowPole", "FootIK", "KneePole") for c in "LR"}
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
    elif n.startswith("Flap"):
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
    gi = {g_.index: g_.name for g_ in tmp.vertex_groups}
    for v in me.vertices:
        for g_ in v.groups:
            if gi[g_.group] in BI:
                W[orig[v.index], BI[gi[g_.group]]] = g_.weight
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
for side, s in SIDES:
    leg_idx = np.concatenate([parts[k] for k, v in kind.items() if v == "leg" and V[parts[k], 0].mean() * s > 0])
    LEG_BONES = [MX + "Hips"] + [MX + side + n for n in ("UpLeg", "Leg", "Foot", "ToeBase")]
    heat_rows(leg_idx, set(LEG_BONES))
    print("RIG_SKIN", side, "leg heat done, filled by nearest bone", fill_empty(leg_idx, LEG_BONES))

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

# The face round the mask follows the head alone, so the mask (rigid on the head) keeps
# its gap to it however the neck bends; the throat below MASK_NECK keeps its heat weights.
MASK_TREE = BVHTree.FromPolygons([Vector(q) for q in MASK_V], MASK_F)
fi_ = np.nonzero(CORE & (V[:, 2] > MASK_NECK[0]))[0]
d_ = np.array([MASK_TREE.find_nearest(Vector(V[i]), 0.2)[3] or 0.2 for i in fi_])
k = smooth_step((MASK_HEAD[1] - d_) / (MASK_HEAD[1] - MASK_HEAD[0])) * smooth_step(
    (V[fi_, 2] - MASK_NECK[0]) / (MASK_NECK[1] - MASK_NECK[0]))
W[fi_] *= (1 - k)[:, None]
W[fi_, BI[MX + "Head"]] += k
print("RIG_SKIN face round the mask: %d vertices on the head alone, %d more blended" % ((k > 0.999).sum(), ((k > 0.01) & (k <= 0.999)).sum()))


# The other shells take the weights of the body surface nearest them (bvh: the core).
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
    mask_ = np.zeros(len(DEF))
    for n in keep:
        mask_[BI[n]] = 1
    rows = rows * mask_
    s_ = rows.sum(1)
    rows[s_ < 1e-6, BI[fallback]] = 1
    return rows / rows.sum(1, keepdims=True)


def rigid(idx, keep):
    """One weight row for the whole shell: the mean of the body's under it, kept to `keep`."""
    W[idx] = masked(transfer(idx).mean(0)[None], keep, keep[0])[0]


CHEST = [MX + n for n in ("Spine2", "Spine1", "Neck")]
PELVIS = [MX + "Hips", MX + "Spine"]
for k_, kd in kind.items():
    idx = parts[k_]
    if kd == "head":
        W[idx] = 0
        W[idx, BI[MX + "Head"]] = 1
    elif kd == "chest":
        rigid(idx, CHEST)
    elif kd == "belt":
        rigid(idx, PELVIS)
    elif kd == "other":
        W[idx] = transfer(idx)


def flap_rows(idx, name):
    """The pelvis at a flap's top, its own bones below."""
    b1, b2 = arm_data.bones[name + "1"], arm_data.bones[name + "2"]
    z = V[idx, 2]
    k1 = smooth_step((b1.head_local.z + 0.005 - z) / 0.03)            # 0 at the belt, 1 below it
    k2 = smooth_step((b2.head_local.z + 0.03 - z) / 0.06)             # onto the lower bone round the middle
    rows = masked(transfer(idx), PELVIS, MX + "Hips") * (1 - k1)[:, None]
    rows[:, BI[b1.name]] += k1 * (1 - k2)
    rows[:, BI[b2.name]] += k1 * k2
    return rows


def side_rows(idx):
    """The pelvis at the top, toward the thigh it covers lower down (blended across the
    middle), as the rabble's skirt."""
    z, x = V[idx, 2], V[idx, 0]
    kk = smooth_step((CUT_Z - z) / 0.20) * SKIRT_LEG
    sig = smooth_step((x + 0.035) / 0.07)
    rows = masked(transfer(idx), PELVIS + [MX + "LeftUpLeg", MX + "RightUpLeg"], MX + "Hips") * (1 - kk)[:, None]
    rows[:, BI[MX + "LeftUpLeg"]] += kk * sig
    rows[:, BI[MX + "RightUpLeg"]] += kk * (1 - sig)
    return rows


idx = np.nonzero(FLAP_F)[0]
W[idx] = flap_rows(idx, "FlapFront")
# The wrap: on the back bones down the middle of its back, over to the thighs at its sides.
idx = np.nonzero(WRAP)[0]
side_k = smooth_step((np.abs(V[idx, 0]) - 0.05) / 0.10)[:, None]
W[idx] = flap_rows(idx, "FlapBack") * (1 - side_k) + side_rows(idx) * side_k
idx = np.nonzero(TATTER)[0]
W[idx] = side_rows(idx)

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


# --- Props on their bones ------------------------------------------------------
def mount(obj, bone_name, world):
    bone = arm_data.bones[bone_name]
    obj.parent = rig
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    obj.matrix_parent_inverse = Matrix.Translation((0, -bone.length, 0))
    obj.matrix_basis = bone.matrix_local.inverted() @ world


for obj in (staff, mask):
    for c in obj.users_collection:
        c.objects.unlink(obj)
    sc.collection.objects.link(obj)
mount(staff, "Staff", STAFF_WORLD)
mount(mask, "Mask", MASK_WORLD)
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
for gname in ("Staff", "Relax"):
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

for p, d in (("staff_ik", "Right hand follows StaffCtrl through HandIK.R"),
             ("cast_ik", "Left hand follows HandIK.L"), ("leg_ik", "Feet follow FootIK.L and FootIK.R")):
    rig[p] = 0.0
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


# --- Controls --------------------------------------------------------------------
mod.show_viewport = False   # the pole searches below update the scene many times


def child_of(pb, target):
    c = pb.constraints.new("CHILD_OF")
    c.target, c.subtarget = rig, target
    c.inverse_matrix = rig.data.bones[target].matrix_local.inverted()
    return c


child_of(rig.pose.bones["StaffCtrl"], MX + "Spine2").name = "follow chest"
child_of(rig.pose.bones["HandIK.R"], "StaffCtrl").name = "follow staff"
child_of(rig.pose.bones["HandIK.L"], MX + "Spine2").name = "follow chest"


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


add_ik(MX + "RightForeArm", MX + "RightHand", "HandIK.R", "ElbowPole.R", "staff_ik")
add_ik(MX + "LeftForeArm", MX + "LeftHand", "HandIK.L", "ElbowPole.L", "cast_ik")
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


# The front flap swings forward with the leading thigh, the back of the skirt back with
# the trailing one.
thigh_driver("FlapFront1", f"{FLAP_FOLLOW} * max(0, l, r)")
thigh_driver("FlapBack1", f"{FLAP_FOLLOW} * min(0, l, r)")

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
    side = "L" if ("Left" in n or n.endswith(".L")) else ("R" if ("Right" in n or n.endswith(".R") or n.startswith("Staff")) else "C")
    pb.color.palette = {"L": "THEME04", "R": "THEME01", "C": "THEME09"}[side]
    if n == "StaffCtrl":
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
pbs = rig.pose.bones
HAND_R = np.array([sum(g_.weight for g_ in v.groups if body.vertex_groups[g_.group].name.startswith(MX + "RightHand")) > 0.5
                   for v in body.data.vertices])
NO_HAND_TRIS = TRIS[~HAND_R[TRIS].any(1)].tolist()
IN_HAND = (ST_V[:, 2] > G_LO - 0.01) & (ST_V[:, 2] < G_HI + 0.01)   # the grip, inside the fist: its clearance is the grip's
HANDLE_F = np.array([IN_HAND[f].all() for f in ST_F])


def staff_axis():
    """The staff's lean from upright (degrees: total, ahead +, out to his right +), which way
    its skull faces (degrees from ahead, + toward his right) and the height of its foot."""
    M = np.array(staff.matrix_world)
    axis, face = M[:3, 2], -M[:3, 1]
    foot = M[:3, :3] @ np.array([0, 0, ST_FOOT]) + M[:3, 3]
    return {"tilt": math.degrees(math.acos(min(1.0, axis[2]))), "ahead": math.degrees(math.asin(-axis[1])),
            "out": math.degrees(math.asin(-axis[0])), "facing": math.degrees(math.atan2(-face[0], -face[1])),
            "foot": float(foot[2])}


def staff_world():
    Mw = np.array(staff.matrix_world)
    return ST_V @ Mw[:3, :3].T + Mw[:3, 3]


def head_clear(Sw):
    """How far out to his right the staff stays beside his head (the least, m)."""
    up = (Sw[:, 2] > HEAD_ZS[0]) & (Sw[:, 2] < HEAD_ZS[1])
    return float(-Sw[up, 0].max()) if up.any() else 1.0


def staff_fit(P):
    """The staff against the posed body P (its right hand left out) and the mask: triangles
    through it, its nearest approach outside the fist, its lowest point and its angles."""
    tree = BVHTree.FromPolygons([Vector(p) for p in P], NO_HAND_TRIS)
    Sw = staff_world()
    st = BVHTree.FromPolygons([Vector(q) for q in Sw], ST_F)
    pairs = {(f, i) for f, i in st.overlap(tree)} | {(f, i) for i, f in tree.overlap(st)}
    cuts = sum(1 for f, _ in pairs if not HANDLE_F[f])
    d = np.array([tree.find_nearest(Vector(q), 0.3)[3] or 0.3 for q in Sw[~IN_HAND]])
    Mm = np.array(mask.matrix_world)
    mt = BVHTree.FromPolygons([Vector(q) for q in np.array([v.co[:] for v in mask.data.vertices]) @ Mm[:3, :3].T + Mm[:3, 3]],
                              MASK_F)
    dm = [mt.find_nearest(Vector(q), 0.3)[3] or 0.3 for q in Sw]
    return {"cuts": cuts + len(st.overlap(mt)), "handle_cuts": len(pairs) - cuts, "gap": float(d.min()),
            "mask_gap": float(min(dm)), "head_clear": head_clear(Sw), "low": float(Sw[:, 2].min()), **staff_axis()}


pose_arm("Left", 1, STAND_L)
ARM_TURN = {"Left": pose_arm("Left", 1, STAND_L)}
# First every pose is ranked by the staff's angles alone (the skin is not needed for that),
# then the skin is checked pose by pose in that order until the staff is clear of it.
# A lean in toward his head costs twice a lean out.
keys = list(STAND_R)
ranked, lowest = [], 1.0
mod.show_viewport = False
for vals in np.array(np.meshgrid(*[STAND_R[k] for k in keys], indexing="ij")).reshape(len(keys), -1).T:
    st = {k: int(v) for k, v in zip(keys, vals)}
    pose_arm("Right", -1, st)
    ax = staff_axis()
    if ax["foot"] >= GROUND_Z and head_clear(staff_world()) >= HEAD_CLEAR:
        lowest = min(lowest, ax["foot"])
        cost = (ax["tilt"] + 2 * max(0.0, -ax["out"]) + 0.2 * abs(ax["facing"]) + 20 * max(0.0, ax["foot"] - FOOT_Z)
                + 0.1 * abs(st["wrist"]) + 0.1 * abs(st["roll"]) + 0.03 * abs(st["elbow"] - 70) + 0.05 * abs(st["forward"])
                + 0.05 * (st["out"] - 14))
        ranked.append((cost, st))
mod.show_viewport = True
print("RIG_STAND_RANK %d poses clear of the head; the lowest foot among them %.3f" % (len(ranked), lowest))
ranked.sort(key=lambda r: r[0])
STAND_R_PICK, checked = None, 0
for cost, st in ranked[:400]:
    pose_arm("Right", -1, st)
    fit = staff_fit(posed_mesh())
    checked += 1
    if not fit["cuts"] and min(fit["gap"], fit["mask_gap"]) >= STAFF_GAP and fit["low"] >= GROUND_Z:
        STAND_R_PICK = st
        break
    if checked <= 5:
        print("RIG_STAND_REJECT", st, "cost %.1f" % cost, {k: round(v, 3) for k, v in fit.items()})
assert STAND_R_PICK, "no right-arm pose holds the staff clear"
print("RIG_STAND_SEARCH %d poses ranked, the %d. checked fits (cost %.1f): %s: %s" % (
    len(ranked), checked, cost, STAND_R_PICK, {k: round(v, 3) for k, v in fit.items()}))
ARM_TURN["Right"] = pose_arm("Right", -1, STAND_R_PICK)
for side, s in SIDES:
    pole = pbs["ElbowPole." + side[0]]
    M = (ARM_TURN[side] @ pole.bone.matrix_local.to_3x3()).to_4x4()
    M.translation = pbs[MX + side + "ForeArm"].head + ARM_TURN[side] @ (
        pole.bone.head_local - arm_data.bones[MX + side + "ForeArm"].head_local)
    set_world(pole, M)
# The controls where the pose put the hands (the chest is at rest, so their Child Of
# constraints change nothing): HandIK.R follows StaffCtrl onto the right hand.
set_world(pbs["StaffCtrl"], pbs["Staff"].matrix.copy())
set_world(pbs["HandIK.L"], pbs[MX + "LeftHand"].matrix.copy())
stand = bpy.data.actions.new("stand")
stand.use_fake_user = True
rig.animation_data.action = stand
for side, _ in SIDES:
    for n in ("Shoulder", "Arm", "ForeArm", "Hand"):
        pbs[MX + side + n].keyframe_insert("rotation_quaternion", frame=1)
for n in ("StaffCtrl", "HandIK.L", "ElbowPole.L", "ElbowPole.R"):
    pbs[n].keyframe_insert("location", frame=1)
    pbs[n].keyframe_insert("rotation_quaternion", frame=1)
bpy.context.view_layer.update()
fk = {n: pbs[MX + n].matrix.copy() for n in ("RightHand", "LeftHand", "RightForeArm", "LeftForeArm")}
rig["staff_ik"] = rig["cast_ik"] = 1.0
rig.update_tag()
bpy.context.view_layer.update()
moved_ = {n: ((pbs[MX + n].matrix.translation - M.translation).length * 1000,
              math.degrees(pbs[MX + n].matrix.to_quaternion().rotation_difference(M.to_quaternion()).angle))
          for n, M in fk.items()}
rig["staff_ik"] = rig["cast_ik"] = 0.0
rig.update_tag()
bpy.context.view_layer.update()
print("RIG_STAND staff", {k: round(v, 3) for k, v in staff_axis().items()},
      "| IK on moves", {n: "%.1f mm %.1f deg" % m for n, m in moved_.items()})

# --- The staff hand's hold -------------------------------------------------------------
# Whatever a clip does to the right wrist, the hand keeps the turn from the forearm it has
# in `stand`, so the staff stays upright: the helper bone `StaffHold` sits on the forearm
# where the hand is in `stand`, and a Copy Rotation constraint on the hand (after the
# IK's, so it wins) follows it as much as the rig's `staff_hold` says (1 by default; 0
# gives the wrist back to the clips and HandIK.R, as a casting clip with the staff needs).
hold_rest = (arm_data.bones[MX + "RightForeArm"].matrix_local @ pbs[MX + "RightForeArm"].matrix.inverted()
             @ pbs[MX + "RightHand"].matrix)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
EB = arm_data.edit_bones
hb_ = EB.new("StaffHold")
hb_.head, hb_.tail = Vector((0, 0, 0)), Vector((0, 0.08, 0))
hb_.matrix = hold_rest
hb_.parent = EB[MX + "RightForeArm"]
hb_.use_deform = False
bpy.ops.object.mode_set(mode="OBJECT")
mech = arm_data.collections.new("Mechanics")
mech.assign(arm_data.bones["StaffHold"])
mech.is_visible = False
pbs = rig.pose.bones
pbs["StaffHold"].rotation_mode = "QUATERNION"
pbs["StaffHold"].color.palette = "THEME01"
rig["staff_hold"] = 1.0
rig.id_properties_ui("staff_hold").update(
    min=0.0, max=1.0, description="Right hand keeps its turn on the staff (0: clips and HandIK.R turn it)")
c = pbs[MX + "RightHand"].constraints.new("COPY_ROTATION")
c.name = "hold the staff"
c.target, c.subtarget = rig, "StaffHold"
drive(c, "influence", "$", "staff_hold")
rig.update_tag()
sc.frame_set(1)
bpy.context.view_layer.update()
held = math.degrees(pbs[MX + "RightHand"].matrix.to_quaternion().rotation_difference(fk["RightHand"].to_quaternion()).angle)
print("RIG_HOLD StaffHold on the right forearm; the held hand is %.3f deg from the keyed one;" % held,
      "bones", len(arm_data.bones), "deforming", len([b for b in arm_data.bones if b.use_deform]))
assert held < 0.1


# --- Checks in the standard pose and the T-pose ------------------------------------
def mask_fit(P):
    """Body triangles through the mask and the nearest any body vertex comes to it."""
    tree = BVHTree.FromPolygons([Vector(p) for p in P], BODY_TRIS)
    Mw = np.array(mask.matrix_world)
    Qw = np.array([v.co[:] for v in mask.data.vertices]) @ Mw[:3, :3].T + Mw[:3, 3]
    mt = BVHTree.FromPolygons([Vector(q) for q in Qw], MASK_F)
    pairs = {(a, b) for a, b in mt.overlap(tree)} | {(a, b) for b, a in tree.overlap(mt)}
    near = P[(P[:, 2] > Qw[:, 2].min() - 0.08) & (P[:, 1] < Qw[:, 1].max() + 0.08)]
    d = [mt.find_nearest(Vector(p), 0.1)[3] or 0.1 for p in near]
    return len(pairs), float(min(d))


P = posed_mesh()
STAND_FIT = staff_fit(P)
m_cuts, m_near = mask_fit(P)
print("RIG_CHECK_STAND staff", {k: round(v, 3) for k, v in STAND_FIT.items()},
      "| mask %d triangles through it, nearest %.1f mm" % (m_cuts, m_near * 1000))
assert not STAND_FIT["cuts"]
# The head and the neck turned and bent as clips do (degrees about the bones' own axes:
# x nods, y turns, z tilts): the face under the mask moves with it.
HEAD_TESTS = {"turn_l": (0, 40, 0), "turn_r": (0, -40, 0), "nod_down": (25, 0, 0), "nod_up": (-25, 0, 0),
              "tilt_r": (0, 0, 15), "tilt_l": (0, 0, -15)}
MASK_TESTS = {}
for name, (ax_, ay_, az_) in HEAD_TESTS.items():
    for bn, share in (("Neck", 0.4), ("Head", 0.6)):
        q = Quaternion((1, 0, 0), math.radians(ax_ * share)) @ Quaternion((0, 1, 0), math.radians(ay_ * share)) @ Quaternion(
            (0, 0, 1), math.radians(az_ * share))
        pbs[MX + bn].rotation_quaternion = q
    bpy.context.view_layer.update()
    MASK_TESTS[name] = mask_fit(posed_mesh())
for bn in ("Neck", "Head"):
    pbs[MX + bn].rotation_quaternion = (1, 0, 0, 0)
bpy.context.view_layer.update()
print("RIG_CHECK_MASK", {n: "%d through, %.1f mm" % (c_, d_ * 1000) for n, (c_, d_) in MASK_TESTS.items()})
rig.animation_data.action = None
reset_pose()
P_T = posed_mesh()
TPOSE_FIT = staff_fit(P_T)
t_cuts, t_near = mask_fit(P_T)
print("RIG_CHECK_TPOSE staff", {k: round(v, 3) for k, v in TPOSE_FIT.items()},
      "| mask %d triangles through it, nearest %.1f mm" % (t_cuts, t_near * 1000))
rig.animation_data.action = stand
if hasattr(rig.animation_data, "action_slot") and len(stand.slots):
    rig.animation_data.action_slot = stand.slots[0]
sc.frame_set(1)
bpy.context.view_layer.update()

# --- Save ---------------------------------------------------------------------
rig["grip"] = {w: {"across_palm_at": round(g_["U"], 4), "tilt_deg": g_["tilt"], "slide": g_["slide"],
                   "energy": round(g_["E"], 2), "closest_mm": g_["closest_mm"]} for w, g_ in GRIPS.items()}
rig["stand_right"] = STAND_R_PICK
rig["fit"] = {"staff_stand": {k: round(v, 4) for k, v in STAND_FIT.items()},
              "staff_tpose": {k: round(v, 4) for k, v in TPOSE_FIT.items()},
              "mask_stand": {"through": m_cuts, "nearest_mm": round(m_near * 1000, 1)},
              "mask_head_tests": {n: {"through": c_, "nearest_mm": round(d_ * 1000, 1)} for n, (c_, d_) in MASK_TESTS.items()}}
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
