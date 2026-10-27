"""Rig the orc brute for Mixamo clips, the club in his right fist and the knife in his left (background Blender).

  blender -b orc_brute_base.blend --factory-startup --python rig_orc_brute.py -- <out.blend> [loadout]

The loadout (LOADOUTS) is what his fists hold: `club_knife` (the default, orc_brute_rig.blend)
the club and the knife; `dual` (orc_brute_dual_rig.blend, the squad's two-club men, 26 October
2026) a club in each, the left one ClubLeft, a copy of the club, with no knife in the file.
Each weapon's grip, bone and standard pose are its own, so the steps below hold for either.

Starts from orc_brute_base.blend (build_orc_brute.py) and follows the goblins' rigs:
rig_goblin_spear.py for the four-fingered hands and the grips, rig_goblin_archer.py
for a prop in each hand and the arms' standard pose.
1. A Mixamo-named armature with finger bones placed on each hand's mesh: four fingers
   and a thumb (Thumb, Index, Middle, Ring and Pinky 1-4). Forearm twist bones and two
   bones down each loincloth flap, front and back.
2. Skin: bone heat on the body shell and, separately, on the boots, which are his feet
   and shins. Each hand is a shell of its own, its cuff inside the bracer; it takes
   geometric weights, so a finger moves only its own skin. The bracers are his forearms
   and go over from the forearm to its twist bone toward the wrist. The fur kilt follows
   the hips and its own thigh; the loincloth flaps hang from their own bones below the
   belt. The belt follows the waist under it and the skull buckle and the studs ride it
   whole; the chest straps take the weights of the chest under them and the rings ride
   the straps. A pauldron plate takes PLATE_RIGID of one row for the whole plate and the
   rest from the shoulder under it, so it follows the arm without folding; the spikes
   ride their plates and bracers whole. Eyes, teeth, tusks and earrings follow the head.
3. Grips, solved on the skin as for the goblins: each hand closes round its weapon's
   grip, laid across the palm, at the tilt and the place along it that close the four
   fingers best; the thumb closes the other way, toward the index finger. The right fist
   holds the club just above its knob, the left the knife between the pommel and the
   guard, the knife's edge toward the knuckles (or, in `dual`, its club as the right).
   Each grip is a one-frame Action applied by Action constraints on the finger bones.
4. The club rides the `Club` bone in the right hand, the knife the `Knife` bone in the left
   (in `dual`, ClubLeft the `ClubLeft` bone).
5. Controls as for the goblins: `HandIK.L` and `HandIK.R` follow the chest; each arm's
   `<its weapon>_ik` (`club_ik`, and `knife_ik` or `clubleft_ik`) and `leg_ik` (0 by
   default) switch on IK for that arm and for the feet.
6. Standard pose: the skin stays bound to the T-pose, and the one-frame Action `stand`
   lets the arms hang with the weapons held low, as in the concept: the club's head
   forward, down and out to his right, the knife's blade forward, down and in. Each arm's
   angles (with the hand's roll) are searched for its weapon's aim (STAND_AIM), the weapon
   WEAPON_GAP clear of the body and the forearm and the fist ARM_GAP clear of the rest.
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

H = 1.82 * 54 / 49   # his height (build_orc_brute.py)
MX = "mixamorig:"
SIDES = (("Left", 1), ("Right", -1))
FINGERS = ("Index", "Middle", "Ring", "Pinky")   # four fingers and a thumb on each hand
WRIST_U = 0.835     # the wrist, distance from the centre line (both hands)
KNUCKLE_U = 0.975   # the knuckle row
PHALANX = (0.45, 0.30, 0.25)   # finger length shares of the three segments
# The weapons in their own space (build_orc_brute.py): long axis +z toward the head or the
# blade, origin on the grip's axis where the middle of the fist belongs. The club's knob
# ends at z -0.070 and its leather wrap at +0.204; the knife's pommel is at -0.0995 and its
# guard at +0.0995. A grip is solved on the weapon's surface between heights z, with the
# middle finger's line slid along the axis by `slides` from the origin. The fist's middle
# is about 27 mm from that line toward the little finger, so a slide of -0.027 centres the
# fist on the origin; the club's little finger clears the knob below about -0.03. The cost
# of a slide counts from `home`.
CLUB = {"z": (-0.12, 0.14), "slides": (-0.055, -0.045, -0.035, -0.025, -0.015), "home": -0.035}
LOADOUTS = {
    "club_knife": {
        "Club": {"side": "Right", "s": -1, **CLUB},
        "Knife": {"side": "Left", "s": 1, "z": (-0.12, 0.12),
                  "slides": (-0.047, -0.037, -0.027, -0.017, -0.007), "home": -0.027},
    },
    "dual": {"Club": {"side": "Right", "s": -1, **CLUB}, "ClubLeft": {"side": "Left", "s": 1, **CLUB}},
}
BASE_WEAPONS = ("Club", "Knife")   # the weapons in orc_brute_base.blend
COPY_OF = {"ClubLeft": "Club"}     # a weapon that is a copy of one of those
FIST_HALF = 0.08    # the fist covers this much of the grip either side of its middle
# Standard pose: each weapon's aim (degrees below level, negative; and turned out from
# straight ahead, + away from his body on that side), its clearances, and the angles the
# arms are searched over: collarbone lowered, upper arm out from hanging straight down and
# forward, elbow bent forward, wrist turned toward the little finger, hand rolled about its
# length (+: palm forward).
STAND_AIM = {"Club": (-30, 25), "Knife": (-35, -20), "ClubLeft": (-30, 25)}
WEAPON_GAP = 0.02   # each weapon keeps this far off the body
ARM_GAP = 0.01      # each forearm and fist this far off the torso, kilt and legs
GROUND_Z = 0.05     # the weapons' lowest point this far off the ground
STAND = {"collar": (6,), "out": (8, 12, 16, 20), "forward": (0, 8, 16), "elbow": (10, 20, 30, 40, 50, 60),
         "wrist": (-20, -10, 0, 10, 20, 30, 40), "roll": (-40, -20, 0, 20, 40)}
FLAP_FOLLOW = 0.8   # the loincloth flaps swing with the leading (front) and trailing (back) thigh
PLATE_RIGID = 0.5   # share of a pauldron plate's weights that is one row for the whole plate
# Joints of the left side read off the T-pose (front and side views of the bare skin on a
# 5 cm grid, the hand on a 1 cm grid); the right side mirrors x. The spine's, the neck's
# and the head's depth is measured below, halfway through the body at these heights.
J0 = {
    "Shoulder": (0.07, 0.06, 1.64), "Arm": (0.27, 0.085, 1.585), "ForeArm": (0.567, 0.085, 1.548),
    "Hand": (WRIST_U, 0.0, 1.548),
    "UpLeg": (0.135, 0.02, 0.96), "Leg": (0.175, 0.03, 0.555), "Foot": (0.20, 0.04, 0.12),
    "ToeBase": (0.21, -0.15, 0.03), "Toe_End": (0.22, -0.26, 0.02),
}
SPINE_Z = {"Hips": 1.00, "Spine": 1.12, "Spine1": 1.25, "Spine2": 1.40, "Neck": 1.66, "Head": 1.76}
HEAD_MID_Z = 1.92   # the top of the head is straight above the head's middle at this height

argv = sys.argv[sys.argv.index("--") + 1:]
out_blend = Path(argv[0]).resolve()
LOADOUT = argv[1] if len(argv) > 1 else "club_knife"
WEAPONS = LOADOUTS[LOADOUT]
assert sorted(w["side"] for w in WEAPONS.values()) == ["Left", "Right"], "one weapon a fist"
sc = bpy.context.scene
body = bpy.data.objects["OrcBrute"]
for n, src_name in COPY_OF.items():
    if n in WEAPONS:
        src = bpy.data.objects[src_name]
        o = src.copy()
        o.data = src.data.copy()
        o.name = o.data.name = n
        for coll in src.users_collection:
            coll.objects.link(o)
for n in BASE_WEAPONS:
    if n not in WEAPONS:
        bpy.data.objects.remove(bpy.data.objects[n], do_unlink=True)
PROPS = {n: bpy.data.objects[n] for n in WEAPONS}
IK_PROP = {w["side"]: n.lower() + "_ik" for n, w in WEAPONS.items()}
print("RIG_LOADOUT", LOADOUT, {n: w["side"] for n, w in WEAPONS.items()})
V = np.array([v.co[:] for v in body.data.vertices])
N = len(V)
assert abs(V[:, 2].max() - H) < 0.005 and abs(V[:, 2].min()) < 0.005


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


# --- Shells ------------------------------------------------------------------------
bm = bmesh.new()
bm.from_mesh(body.data)
parts = shells(bm)
bm.free()
main = max(range(len(parts)), key=lambda k: len(parts[k]))
kind = {}
for k, p in enumerate(parts):
    P = V[p]
    lo, hi, c = P.min(0), P.max(0), P.mean(0)
    sd = "L" if c[0] > 0 else "R"
    if k == main:
        kind[k] = "body"
    elif lo[2] < 0.01:
        kind[k] = "boot"                    # boot, foot and shin, with its fur cuff
    elif abs(c[0]) > 0.88:
        kind[k] = "hand_" + sd              # the hand, its cuff inside the bracer
    elif abs(c[0]) > 0.58:
        kind[k] = ("bracer_" if len(p) > 60 else "bspike_") + sd    # bracer halves and their spikes
    elif lo[2] > 1.70 and abs(c[0]) < 0.16:
        kind[k] = "head"                    # eyes, teeth, tusks and earrings
    elif lo[2] > 1.50:
        kind[k] = ("plate_" if len(p) > 60 else "pspike_") + sd     # pauldron plates and their spikes
    elif lo[2] > 1.30 and hi[2] - lo[2] < 0.16 and abs(c[0]) < 0.06:
        kind[k] = "ring"                    # the straps' rings, front and back
    elif lo[2] > 1.20:
        kind[k] = "strap"                   # the chest straps
    elif lo[2] > 1.0:
        kind[k] = "belt" if hi[0] - lo[0] > 0.3 else "belt_bit"     # the belt; its skull buckle and studs
    elif c[1] > 0.15:
        kind[k] = "flap_B"                  # the loincloth's back flap
    elif abs(c[0]) < 0.06:
        kind[k] = "flap_F"                  # and its front flap
    else:
        kind[k] = "kilt_" + sd              # the fur kilt's halves
counts = {}
for kd in kind.values():
    counts[kd] = counts.get(kd, 0) + 1
print("RIG_SHELLS main %d vertices," % len(parts[main]), dict(sorted(counts.items())))
EXPECT = {"body": 1, "boot": 2, "hand_L": 1, "hand_R": 1, "bracer_L": 2, "bracer_R": 2, "plate_L": 2, "plate_R": 2,
          "ring": 2, "strap": 4, "belt": 1, "flap_F": 1, "flap_B": 1, "kilt_L": 1, "kilt_R": 1}
assert all(counts.get(kd) == n for kd, n in EXPECT.items()), "unexpected shells"
assert counts["head"] >= 9 and counts["belt_bit"] >= 5


def of(*kinds):
    """Vertex indices of every shell of these kinds."""
    return np.concatenate([parts[k] for k, kd in kind.items() if kd in kinds])


in_main = np.zeros(N, bool)
in_main[parts[main]] = True
HAND = {}
for side, _ in SIDES:
    HAND[side] = np.zeros(N, bool)
    HAND[side][of("hand_" + side[0])] = True
T3 = TRIS[in_main[TRIS].all(1)]
bvh = BVHTree.FromPolygons([Vector(p) for p in V], T3.tolist())


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
J["HeadTop_End"] = Vector((0, torso_mid(HEAD_MID_Z), H - 0.01))
for side, s in SIDES:
    for n in ("Shoulder", "Arm", "ForeArm", "Hand", "UpLeg", "Leg", "Foot", "ToeBase", "Toe_End"):
        x, y, z = J0[n]
        J[side + n] = Vector((s * x, y, z))
print("RIG_SPINE", {n: [round(c, 3) for c in J[n]] for n in list(SPINE_Z) + ["HeadTop_End"]})


# --- Hands: fingers, thumb and palm ----------------------------------------------
def measure_hand(side, s):
    """Joints (armature space) and radii of the four fingers and the thumb, on the hand's
    own shell (its cuff, inside the bracer, starts a little short of the wrist)."""
    U = V[:, 0] * s
    in_hand = HAND[side]
    idx = np.nonzero(in_hand)[0]
    # Past the webs the four fingers are apart; the thumb's tip, short of the knuckles,
    # is not one of them.
    for u_web in np.arange(KNUCKLE_U, 1.03, 0.002):
        comps = [c for c in components(in_hand & (U > u_web)) if len(c) >= 12 and U[c].max() > KNUCKLE_U + 0.05]
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
        L = tip_u - 0.005 - KNUCKLE_U
        pts, rad = [], []
        for u in (KNUCKLE_U, KNUCKLE_U + PHALANX[0] * L, KNUCKLE_U + (PHALANX[0] + PHALANX[1]) * L, tip_u - 0.005):
            uu = min(max(u, u_web + 0.008), tip_u - 0.008)   # by the knuckle: the finger just past the web
            d = np.abs(F[:, 0] - uu)
            q = F[d <= max(0.007, np.sort(d)[9])]    # within 7 mm, at least the ten nearest
            pts.append((s * u, (q[:, 1].min() + q[:, 1].max()) / 2, (q[:, 2].min() + q[:, 2].max()) / 2))
            rad.append(min(np.ptp(q[:, 1]), np.ptp(q[:, 2])) / 2)
        hand["fingers"][name] = (np.array(pts), np.array(rad))
    # Thumb: what hangs below and in front of the palm. Its two phalanges lie along its axis.
    th = components(in_hand & ~in_fingers & (U > WRIST_U + 0.065) & (V[:, 1] < -0.055) & (V[:, 2] < 1.53))[0]
    T = np.c_[U[th], V[th, 1:]]
    cen = T.mean(0)
    ax = np.linalg.svd(T - cen)[2][0]
    ax = ax if ax[0] > 0 else -ax
    t = (T - cen) @ ax
    trad = float(np.median(np.linalg.norm((T - cen) - np.outer(t, ax), axis=1)))
    mcp, tip = cen + ax * (t.min() + 0.008), cen + ax * (t.max() - 0.005)
    # The metacarpal starts in the heel of the hand, by the wrist and in from the thumb.
    u_cmc = WRIST_U + 0.02
    q = V[in_hand & ~in_fingers & (np.abs(U - u_cmc) < 0.01)]
    cmc = np.array([u_cmc, mcp[1] + 0.016, (q[:, 2].min() + q[:, 2].max()) / 2])
    hand["thumb"] = (np.array([cmc, mcp, mcp + 0.55 * (tip - mcp), tip]) * np.array([s, 1, 1]), trad)
    hand["in_fingers"], hand["thumb_idx"] = in_fingers, th
    print("RIG_THUMB_SHELL", side, "%d vertices, u %.3f to %.3f, y %.3f to %.3f, z %.3f to %.3f" % (
        len(th), U[th].min(), U[th].max(), V[th, 1].min(), V[th, 1].max(), V[th, 2].min(), V[th, 2].max()))
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
    return names, R, smooth_step((P[:, 0] * s - (WRIST_U - 0.03)) / 0.06)


# --- Grips -------------------------------------------------------------------------
# Each grip is solved on the skin itself: points on the hand's triangles move with the
# skin weights above (linear blend skinning, as the Armature modifier does) and are
# tested against the weapon's surface, sampled as a signed distance field.
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
    own space (vertices P, faces F) between heights z0 and z1 and read back trilinearly. The
    size is the distance to the nearest surface. Its sign is the side of the nearest face where
    the nearest point lies inside that face; where it lies on an edge or a corner, the face's side
    misleads (beside the open rim of a wrap band everything beyond would read inside), so the
    sign there is the generalized winding number's, which open bands and nested shells keep."""

    def __init__(self, P, F, z0, z1, step=0.002):
        tree = BVHTree.FromPolygons([Vector(p) for p in P], F)
        near = P[(P[:, 2] > z0 - 0.02) & (P[:, 2] < z1 + 0.02)]
        self.lo = np.r_[near[:, :2].min(0) - 0.016, z0]
        self.n = np.ceil((np.r_[near[:, :2].max(0) + 0.016, z1] - self.lo) / step).astype(int) + 1
        self.step = step
        axes = [self.lo[i] + step * np.arange(self.n[i]) for i in range(3)]
        Q = np.stack(np.meshgrid(*axes, indexing="ij"), -1).reshape(-1, 3)
        dist, sign, edge = np.empty(len(Q)), np.ones(len(Q)), np.zeros(len(Q), bool)
        for k, q in enumerate(Q):
            p = Vector(q)
            loc, nrm, _, d = tree.find_nearest(p)
            dot = (p - loc).dot(nrm)
            dist[k] = d
            sign[k] = 1.0 if dot >= 0 else -1.0
            edge[k] = d > 1e-6 and abs(dot) < 0.999 * d
        tri = np.array([(f[0], f[i], f[i + 1]) for f in F for i in range(1, len(f) - 1)])
        T = P[tri]
        T = T[(T[:, :, 2].max(1) > z0 - 0.15) & (T[:, :, 2].min(1) < z1 + 0.15)]
        idx = np.nonzero(edge)[0]
        for c in range(0, len(idx), 256):
            sub = idx[c:c + 256]
            A, B, C = (T[None, :, i] - Q[sub, None] for i in range(3))
            la, lb, lc = (np.linalg.norm(X, axis=-1) for X in (A, B, C))
            num = (A * np.cross(B, C)).sum(-1)
            den = la * lb * lc + (A * B).sum(-1) * lc + (A * C).sum(-1) * lb + (B * C).sum(-1) * la
            wind = np.arctan2(num, den).sum(1) / (2 * math.pi)
            sign[sub] = np.where(np.abs(wind) > 0.5, -1.0, 1.0)
        self.G = (dist * sign).reshape(self.n)
        print("RIG_FIELD %d samples, %d signed by winding number" % (len(Q), len(idx)))

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
        self.s, self.step, self.u0, self.y0 = s, 0.003, WRIST_U - 0.03, -0.15
        us = self.u0 + self.step * np.arange(int((KNUCKLE_U + 0.02 - self.u0) / self.step) + 1)
        ys = self.y0 + self.step * np.arange(int(0.24 / self.step) + 1)
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
    thumb (the weapon's head or blade), x toward the wrist; o the prop's origin."""
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


def solve_grip(hand, field, sigmas, home, label, refine=6):
    tried = []
    for U in np.arange(KNUCKLE_U - 0.07, KNUCKLE_U + 0.0001, 0.014):
        for tau in (6, 12, 18):
            for sigma in sigmas:
                R, o = place(hand, U, tau * DEG, sigma, field)
                sdf = lambda Q, R=R, o=o: field((Q - o) @ R)
                E, Ts = 2.0 * ((sigma - home) * 1000) ** 2 / 1000, {}
                for ci in range(1, NF):
                    e = finger_energy(hand, ci, FLEX_GRID, sdf, coarse=True)
                    E += float(e.min())
                    Ts[ci] = FLEX_GRID[int(np.argmin(e))]
                tried.append((E, U, tau, sigma, R, o, Ts))
    tried.sort(key=lambda r: r[0])
    best = None
    for _, U, tau, sigma, R, o, Ts in tried[:refine]:
        sdf = lambda Q, R=R, o=o: field((Q - o) @ R)
        E = 2.0 * ((sigma - home) * 1000) ** 2 / 1000
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


PV = {n: np.array([v.co[:] for v in o.data.vertices]) for n, o in PROPS.items()}
PF = {n: [list(p.vertices) for p in o.data.polygons] for n, o in PROPS.items()}
GRIPS = {}
for name, w in WEAPONS.items():
    GRIPS[name] = solve_grip(GripHand(w["side"], w["s"]), PropField(PV[name], PF[name], *w["z"]),
                             w["slides"], w["home"], name)
    print("RIG_FIST", name, "the fist's middle at z %+.3f along the weapon" % GRIPS[name]["fist_z"])


# --- Armature ------------------------------------------------------------------
arm_data = bpy.data.armatures.new("OrcBruteRig")
rig = bpy.data.objects.new("OrcBruteRig", arm_data)
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
new_bone(MX + "HeadTop_End", J["HeadTop_End"], J["HeadTop_End"] + Vector((0, 0, 0.06)), MX + "Head", True, FRONT)
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
        new_bone(f"{MX}{side}Hand{f}4", tip, tip + (tip - J[f"{side}Hand{f}3"]).normalized() * 0.015, par, True, DOWN)
    new_bone(side + "ForeArmTwist", J[side + "ForeArm"].lerp(J[side + "Hand"], 0.45), J[side + "Hand"],
             MX + side + "ForeArm", False, DOWN)
    new_bone(MX + side + "UpLeg", J[side + "UpLeg"], J[side + "Leg"], MX + "Hips", False, FRONT)
    new_bone(MX + side + "Leg", J[side + "Leg"], J[side + "Foot"], MX + side + "UpLeg", True, FRONT)
    new_bone(MX + side + "Foot", J[side + "Foot"], J[side + "ToeBase"], MX + side + "Leg", True, FRONT)
    new_bone(MX + side + "ToeBase", J[side + "ToeBase"], J[side + "Toe_End"], MX + side + "Foot", True, FRONT)
    te = J[side + "Toe_End"]
    new_bone(MX + side + "Toe_End", te, te + (te - J[side + "ToeBase"]).normalized() * 0.04, MX + side + "ToeBase",
             True, FRONT)


def mid_line(idx, z_list):
    """Points down the middle of a hanging part: the median depth of its vertices near the
    centre line at each height (the nearest eight, if few are within 3 cm)."""
    P = V[idx]
    P = P[np.abs(P[:, 0]) < 0.06]
    pts = []
    for z in z_list:
        q = P[np.abs(P[:, 2] - z) < 0.03]
        if len(q) < 3:
            q = P[np.argsort(np.abs(P[:, 2] - z))[:8]]
        pts.append(Vector((0, float(np.median(q[:, 1])), z)))
    return pts


# Loincloth flaps: two bones each, from under the belt down.
for name, kd in (("FlapFront", "flap_F"), ("FlapBack", "flap_B")):
    idx = of(kd)
    fz = V[idx, 2]
    z0, z1 = float(fz.max()) - 0.02, float(V[idx][np.abs(V[idx, 0]) < 0.06, 2].min()) + 0.01
    p0, p1, p2 = mid_line(idx, (z0, (z0 + z1) / 2, z1))
    new_bone(name + "1", p0, p1, MX + "Hips", False, FRONT)
    new_bone(name + "2", p1, p2, name + "1", True, FRONT)

# Weapon bones: their rest frames are the grips' (the weapon's origin, along its axis);
# each bone's z axis is the weapon's -y.
for name, w in WEAPONS.items():
    F = GRIPS[name]["frame"]
    wb = new_bone(name, F.col[3].xyz, F.col[3].xyz + F.col[2].xyz * 0.15, MX + w["side"] + "Hand", False)
    wb.align_roll(-F.col[1].xyz)

# Controls (parentless; Child Of constraints do the following, as for the goblins).
for side, s in SIDES:
    hb = EB[MX + side + "Hand"]
    ik = new_bone("HandIK." + side[0], hb.head, hb.tail)
    ik.roll = hb.roll
    elbow = J[side + "ForeArm"]
    new_bone("ElbowPole." + side[0], elbow + Vector((0, 0.40, 0)), elbow + Vector((0, 0.48, 0)), MX + "Spine2")
    fb = EB[MX + side + "Foot"]
    fk_ = new_bone("FootIK." + side[0], fb.head, fb.tail)
    fk_.roll = fb.roll
    knee = J[side + "Leg"]
    new_bone("KneePole." + side[0], knee + Vector((0, -0.47, 0)), knee + Vector((0, -0.55, 0)), "FootIK." + side[0])
bpy.ops.object.mode_set(mode="OBJECT")

PROP_BONES = tuple(WEAPONS)
DEFORM_SKIP = ("HeadTop_End", "Toe_End", "Thumb4", "Index4", "Middle4", "Ring4", "Pinky4")
CONTROL = set(PROP_BONES) | {f"{p}.{c}" for p in ("HandIK", "ElbowPole", "FootIK", "KneePole") for c in "LR"}
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


body_idx = parts[main]
BODY_BONES = [n for n in DEF if n.startswith(MX) and arm_data.bones[n] not in COLL["Fingers"]]
heat_rows(body_idx, set(BODY_BONES))
print("RIG_SKIN body heat done, filled by nearest bone", fill_empty(body_idx, BODY_BONES))
boot_idx = of("boot")
LEG_BONES = [MX + side + n for side, _ in SIDES for n in ("Leg", "Foot", "ToeBase")]
heat_rows(boot_idx, set(LEG_BONES))
print("RIG_SKIN boots heat done, filled by nearest bone", fill_empty(boot_idx, LEG_BONES))

# Bracers: the forearm, going over to its twist bone toward the wrist.
for side, s in SIDES:
    idx = of("bracer_" + side[0])
    e, w = np.array(J[side + "ForeArm"]), np.array(J[side + "Hand"])
    t = ((V[idx] - e) @ (w - e)) / ((w - e) @ (w - e))
    k = smooth_step((t - 0.3) / 0.6)
    W[idx] = 0
    W[idx, BI[MX + side + "ForeArm"]] = 1 - k
    W[idx, BI[side + "ForeArmTwist"]] = k

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


def rigid_on(idx, base):
    """One weight row for a whole shell: the mean of the rows of the vertices of `base`
    (a shell it sits on, already weighted) nearest its own."""
    d = np.linalg.norm(V[idx][:, None] - V[base][None], axis=-1)
    W[idx] = W[base[np.unique(d.argmin(1))]].mean(0)


WAIST = [MX + n for n in ("Hips", "Spine", "Spine1")]
TORSO = [MX + n for n in ("Hips", "Spine", "Spine1", "Spine2", "Neck", "LeftShoulder", "RightShoulder")]
belt_idx = of("belt")
W[belt_idx] = masked(transfer(belt_idx), WAIST, MX + "Spine")
strap_idx = of("strap")
W[strap_idx] = masked(transfer(strap_idx), TORSO, MX + "Spine2")
for side, s in SIDES:
    keep = [MX + n for n in ("Spine2", "Spine1", "Neck", side + "Shoulder", side + "Arm")]
    for k, kd in kind.items():
        if kd == "plate_" + side[0]:
            rows = masked(transfer(parts[k]), keep, MX + side + "Shoulder")
            W[parts[k]] = (1 - PLATE_RIGID) * rows + PLATE_RIGID * rows.mean(0)
    for k, kd in kind.items():
        if kd == "kilt_" + side[0]:
            W[parts[k]] = masked(transfer(parts[k]), [MX + "Hips", MX + "Spine", MX + side + "UpLeg"], MX + "Hips")
plate_idx = of("plate_L", "plate_R")
for k, kd in kind.items():
    if kd == "belt_bit":
        rigid_on(parts[k], belt_idx)
    elif kd == "ring":
        rigid_on(parts[k], strap_idx)
    elif kd.startswith("pspike_"):
        rigid_on(parts[k], plate_idx)
    elif kd.startswith("bspike_"):
        rigid_on(parts[k], of("bracer_" + kd[-1]))
    elif kd == "head":
        W[parts[k]] = 0
        W[parts[k], BI[MX + "Head"]] = 1
# Flaps: the pelvis at their top, their own bones below.
for name, kd in (("FlapFront", "flap_F"), ("FlapBack", "flap_B")):
    idx = of(kd)
    b1, b2 = arm_data.bones[name + "1"], arm_data.bones[name + "2"]
    z = V[idx, 2]
    k1 = smooth_step((b1.head_local.z + 0.005 - z) / 0.03)            # 0 at the belt, 1 below it
    k2 = smooth_step((b2.head_local.z + 0.03 - z) / 0.06)             # onto the lower bone round the middle
    rows = masked(transfer(idx), [MX + "Hips", MX + "Spine"], MX + "Hips") * (1 - k1)[:, None]
    rows[:, BI[b1.name]] += k1 * (1 - k2)
    rows[:, BI[b2.name]] += k1 * k2
    W[idx] = rows
unset = np.nonzero(W.sum(1) < 1e-6)[0]
assert not len(unset), f"{len(unset)} vertices without weights"

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

# --- Weapons on their bones ------------------------------------------------------


def mount(obj, bone_name, world):
    bone = arm_data.bones[bone_name]
    obj.parent = rig
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    obj.matrix_parent_inverse = Matrix.Translation((0, -bone.length, 0))
    obj.matrix_basis = bone.matrix_local.inverted() @ world


for name in WEAPONS:
    mount(PROPS[name], name, GRIPS[name]["frame"])

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
for name, w in WEAPONS.items():
    side = w["side"]
    reset_pose()
    pose_hand(GRIPS[name])
    act = bpy.data.actions.new("grip_" + name.lower())
    act.use_fake_user = True
    rig.animation_data.action = act
    for f in CHAINS:
        for i in range(1, 4):
            pb = rig.pose.bones[f"{MX}{side}Hand{f}{i}"]
            pb.keyframe_insert("rotation_quaternion", frame=1)
    rig.animation_data.action = None
    GRIP_ACTIONS[name] = (act, side)
reset_pose()

for p, d in ((IK_PROP["Left"], "Left hand follows HandIK.L"), (IK_PROP["Right"], "Right hand follows HandIK.R"),
             ("leg_ik", "Feet follow FootIK.L and FootIK.R")):
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


for name, (act, side) in GRIP_ACTIONS.items():
    for f in CHAINS:
        for i in range(1, 4):
            pb = rig.pose.bones[f"{MX}{side}Hand{f}{i}"]
            c = pb.constraints.new("ACTION")
            c.name = "grip_" + name.lower()
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


for side, _ in SIDES:
    child_of(rig.pose.bones["HandIK." + side[0]], MX + "Spine2").name = "follow chest"


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


add_ik(MX + "LeftForeArm", MX + "LeftHand", "HandIK.L", "ElbowPole.L", IK_PROP["Left"])
add_ik(MX + "RightForeArm", MX + "RightHand", "HandIK.R", "ElbowPole.R", IK_PROP["Right"])
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


# The front flap swings forward with the leading thigh, the back flap back with the trailing one.
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
diamond = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
W_DIAM = widget("WGT_diamond", diamond, [(0, 2), (2, 1), (1, 3), (3, 0), (0, 4), (4, 1), (1, 5), (5, 0), (2, 4), (4, 3), (3, 5), (5, 2)])
widgets.hide_viewport = widgets.hide_render = True
for pb in rig.pose.bones:
    n = pb.name
    side = WEAPONS[n]["side"][0] if n in WEAPONS else (
        "L" if ("Left" in n or n.endswith(".L")) else "R" if ("Right" in n or n.endswith(".R")) else "C")
    pb.color.palette = {"L": "THEME04", "R": "THEME01", "C": "THEME09"}[side]
    if n.startswith(("HandIK", "FootIK")):
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
group_names = {g_.index: g_.name for g_ in body.vertex_groups}
DOM = np.array([group_names[max(v.groups, key=lambda g_: g_.weight).group] if len(v.groups) else ""
                for v in body.data.vertices])
# Per side: the hand (left out of its weapon's clearance), the forearm with its bracer and
# the hand (kept ARM_GAP off the rest of the body, the upper arm left out too).
IN_HAND, LIMB, OTHER_TRIS, NO_HAND_TRIS = {}, {}, {}, {}
for side, _ in SIDES:
    IN_HAND[side] = np.array([d.startswith(MX + side + "Hand") for d in DOM])
    LIMB[side] = IN_HAND[side] | np.isin(DOM, [MX + side + "ForeArm", side + "ForeArmTwist"])
    OTHER_TRIS[side] = TRIS[~(LIMB[side] | (DOM == MX + side + "Arm"))[TRIS].any(1)].tolist()
    NO_HAND_TRIS[side] = TRIS[~IN_HAND[side][TRIS].any(1)].tolist()


def weapon_axis(name):
    """The weapon's aim: degrees above level (its head or blade), degrees turned out from
    straight ahead (+: away from his body on that side), and how far it points ahead."""
    ax = np.array(PROPS[name].matrix_world)[:3, 2]
    ax = ax / np.linalg.norm(ax)
    s = WEAPONS[name]["s"]
    return {"slope": math.degrees(math.asin(ax[2])), "turn": math.degrees(math.atan2(s * ax[0], -ax[1])),
            "ahead": float(-ax[1])}


FIST_F = {n: np.array([(np.abs(PV[n][f, 2] - GRIPS[n]["fist_z"]) < FIST_HALF).all() for f in PF[n]]) for n in WEAPONS}
BEYOND = {n: PV[n][:, 2] > GRIPS[n]["fist_z"] + FIST_HALF for n in WEAPONS}


def weapon_fit(name, P):
    """The weapon against the posed body P (its own hand left out): body triangles through
    it outside the fist, the nearest the body comes to it beyond the fist, its lowest point,
    and the forearm and fist's nearest approach to the rest of the body (the upper arm left
    out); with its aim."""
    side = WEAPONS[name]["side"]
    tree = BVHTree.FromPolygons([Vector(p) for p in P], NO_HAND_TRIS[side])
    Mw = np.array(PROPS[name].matrix_world)
    Pw = PV[name] @ Mw[:3, :3].T + Mw[:3, 3]
    wt = BVHTree.FromPolygons([Vector(q) for q in Pw], PF[name])
    pairs = {(f, i) for f, i in wt.overlap(tree)} | {(f, i) for i, f in tree.overlap(wt)}
    cuts = sum(1 for f, _ in pairs if not FIST_F[name][f])
    gap = min(tree.find_nearest(Vector(q), 0.3)[3] or 0.3 for q in Pw[BEYOND[name]])
    rest = BVHTree.FromPolygons([Vector(p) for p in P], OTHER_TRIS[side])
    arm = min(rest.find_nearest(Vector(q), 0.3)[3] or 0.3 for q in P[LIMB[side]])
    arm_cuts = len(rest.overlap(BVHTree.FromPolygons([Vector(p) for p in P], TRIS[LIMB[side][TRIS].all(1)].tolist())))
    return {"cuts": cuts, "gap": float(gap), "low": float(Pw[:, 2].min()), "arm": float(arm), "arm_cuts": arm_cuts,
            **weapon_axis(name)}


def stand_cost(name, st):
    slope, turn_ = STAND_AIM[name]
    ax = weapon_axis(name)
    if ax["ahead"] <= 0:
        return None
    return (abs(ax["slope"] - slope) + 0.5 * abs(ax["turn"] - turn_) + 0.1 * abs(st["wrist"]) + 0.1 * abs(st["roll"])
            + 0.03 * abs(st["elbow"] - 30) + 0.05 * st["forward"] + 0.05 * (st["out"] - 8))


keys = list(STAND)
GRID = [{k: int(v) for k, v in zip(keys, vals)}
        for vals in np.array(np.meshgrid(*[STAND[k] for k in keys], indexing="ij")).reshape(len(keys), -1).T]
ARM_TURN, STAND_PICK, STAND_FIT = {}, {}, {}
for name, w in WEAPONS.items():
    side, s = w["side"], w["s"]
    # First every pose is ranked by the weapon's aim alone (the skin is not needed for
    # that), then the skin is checked pose by pose in that order until all is clear.
    ranked = []
    mod.show_viewport = False
    for st in GRID:
        pose_arm(side, s, st)
        cost = stand_cost(name, st)
        if cost is not None:
            ranked.append((cost, st))
    mod.show_viewport = True
    ranked.sort(key=lambda r: r[0])
    checked = 0
    for cost, st in ranked[:400]:
        pose_arm(side, s, st)
        fit = weapon_fit(name, posed_mesh())
        checked += 1
        if (not fit["cuts"] and not fit["arm_cuts"] and fit["gap"] >= WEAPON_GAP and fit["arm"] >= ARM_GAP
                and fit["low"] >= GROUND_Z):
            STAND_PICK[side], STAND_FIT[name] = st, fit
            break
        if checked <= 5:
            print("RIG_STAND_REJECT", name, st, {k: round(v, 3) for k, v in fit.items()})
    assert side in STAND_PICK, f"no {side.lower()} arm pose holds the {name.lower()} clear"
    print("RIG_STAND_SEARCH %s: %d poses ranked, the %d. checked fits (cost %.1f): %s: %s" % (
        name, len(ranked), checked, cost, st, {k: round(v, 3) for k, v in fit.items()}))
    ARM_TURN[side] = pose_arm(side, s, STAND_PICK[side])
for side, s in SIDES:
    pole = pbs["ElbowPole." + side[0]]
    M = (ARM_TURN[side] @ pole.bone.matrix_local.to_3x3()).to_4x4()
    M.translation = pbs[MX + side + "ForeArm"].head + ARM_TURN[side] @ (
        pole.bone.head_local - arm_data.bones[MX + side + "ForeArm"].head_local)
    set_world(pole, M)
    # The hand's control where the pose put the hand (the chest is at rest, so its Child Of
    # constraint changes nothing).
    set_world(pbs["HandIK." + side[0]], pbs[MX + side + "Hand"].matrix.copy())
stand = bpy.data.actions.new("stand")
stand.use_fake_user = True
rig.animation_data.action = stand
for side, _ in SIDES:
    for n in ("Shoulder", "Arm", "ForeArm", "Hand"):
        pbs[MX + side + n].keyframe_insert("rotation_quaternion", frame=1)
for n in ("HandIK.L", "HandIK.R", "ElbowPole.L", "ElbowPole.R"):
    pbs[n].keyframe_insert("location", frame=1)
    pbs[n].keyframe_insert("rotation_quaternion", frame=1)
bpy.context.view_layer.update()
fk = {n: pbs[MX + n].matrix.copy() for n in ("RightHand", "LeftHand", "RightForeArm", "LeftForeArm")}
rig[IK_PROP["Left"]] = rig[IK_PROP["Right"]] = 1.0
rig.update_tag()
bpy.context.view_layer.update()
moved_ = {n: ((pbs[MX + n].matrix.translation - M.translation).length * 1000,
              math.degrees(pbs[MX + n].matrix.to_quaternion().rotation_difference(M.to_quaternion()).angle))
          for n, M in fk.items()}
rig[IK_PROP["Left"]] = rig[IK_PROP["Right"]] = 0.0
rig.update_tag()
bpy.context.view_layer.update()
print("RIG_STAND aims", {n: {k: round(v, 1) for k, v in weapon_axis(n).items()} for n in WEAPONS},
      "| IK on moves", {n: "%.1f mm %.1f deg" % m for n, m in moved_.items()})

# --- Checks in the standard pose and the T-pose ------------------------------------
P = posed_mesh()
STAND_FIT = {n: weapon_fit(n, P) for n in WEAPONS}
print("RIG_CHECK_STAND", {n: {k: round(v, 3) for k, v in f.items()} for n, f in STAND_FIT.items()})
assert not any(f["cuts"] or f["arm_cuts"] for f in STAND_FIT.values())
rig.animation_data.action = None
reset_pose()
P_T = posed_mesh()
TPOSE_FIT = {n: weapon_fit(n, P_T) for n in WEAPONS}
print("RIG_CHECK_TPOSE", {n: {k: round(v, 3) for k, v in f.items()} for n, f in TPOSE_FIT.items()})
rig.animation_data.action = stand
if hasattr(rig.animation_data, "action_slot") and len(stand.slots):
    rig.animation_data.action_slot = stand.slots[0]
sc.frame_set(1)
bpy.context.view_layer.update()

# --- Save ---------------------------------------------------------------------
rig["grip"] = {w: {"across_palm_at": round(g_["U"], 4), "tilt_deg": g_["tilt"], "slide": g_["slide"],
                   "fist_z": round(g_["fist_z"], 4), "energy": round(g_["E"], 2), "closest_mm": g_["closest_mm"]}
               for w, g_ in GRIPS.items()}
rig["stand"] = STAND_PICK
rig["loadout"] = LOADOUT
rig["fit"] = {"stand": {n: {k: round(v, 4) for k, v in f.items()} for n, f in STAND_FIT.items()},
              "tpose": {n: {k: round(v, 4) for k, v in f.items()} for n, f in TPOSE_FIT.items()}}
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
