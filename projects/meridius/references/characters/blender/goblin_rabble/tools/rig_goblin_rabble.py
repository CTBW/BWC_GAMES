"""Rig the goblin rabble for Mixamo clips, with hands that close round each weapon (background Blender).

  blender -b goblin_rabble_base.blend --factory-startup --python rig_goblin_rabble.py -- <out.blend>

Starts from goblin_rabble_base.blend (build_rabble.py) and follows the spearman's
rig_spearman.py, with these additions:
1. A Mixamo-named armature with finger bones (Thumb, Index, Middle, Ring and Pinky
   1-4) placed on each hand's mesh, forearm twist bones, and secondary bones for the
   collar chain and the loincloth's front and back flaps.
2. Skin: bone heat on the body shell; geometric weights on the hands, so a finger
   moves only its own skin; the separate shells (wrist wraps, loincloth) take the
   weights of the body under them; belt, collar, arm rag, eyes and tusks are rigid.
3. Grips: for each weapon the four fingers are solved, in their own bending planes,
   to wrap round its handle without passing through it, the handle laid across the
   palm as in a hammer grip, at the tilt and the place along the handle that close
   the fingers best. The thumb closes the other way, toward the index finger's
   middle segment. The left hand makes a clenched fist behind the shield. Each grip
   is a one-frame Action, applied by Action constraints on the finger bones, so
   clips without finger keys show the grip and finger keys still add to it.
4. Props: the weapons ride the `Weapon` bone in the right hand, the shields the
   `Shield` bone on the outside of the left forearm. The rig's `loadout` property
   switches the three loadouts: 0 knife and barrel shield, 1 hatchet and plank
   shield, 2 cleaver and barrel shield (props shown and grips chosen by drivers).
   Each shield is tilted about SHIELD_TILT outward, so its upper end stands off the
   shoulder when the arm hangs, and rests on the forearm with the fist pressed to its
   back: the tilt (per shield) and the left wrist's bend are fitted so that the back
   is SHIELD_GAP over both, with no skin through it in the T-pose or the standard
   pose (6). The rag tied round the left upper arm lies under
   both shields: its two tails, which stood 7 cm up through them, are removed, and
   its knot and band are pressed down to RAG_CLEAR under each shield's back.
   Two leather straps round the forearm hold each shield, STRAP_CLEAR off the skin
   and nailed to the board at both ends, and the barrel shield has a handle, a round
   bar on two posts, that the fist closes round. They are one object per shield
   (`ShieldBarrelStraps`, `ShieldPlankStraps`), textured from
   textures/goblin_rabble_straps_basecolor.jpg (paint_straps.py). The left hand
   holds its fist on the shield whatever a clip does to the wrist (`ShieldFist`,
   `shield_fist`).
5. Controls, after the reference video (hands following a weapon): `WeaponCtrl`
   follows the chest through a Child Of constraint, and `HandIK.R` follows
   `WeaponCtrl` through another; with `weapon_ik` at 1 the right arm reaches for
   `HandIK.R` (IK with an elbow pole), so moving the weapon moves the hand.
   `shield_ik` and `leg_ik` do the same for the left arm and the feet. All three
   are 0 by default, so Mixamo clips drive the arms and legs as they are.
6. Standard pose: the skin stays bound to the T-pose, which the Mixamo clips are
   retargeted from, and the one-frame Action `stand` (the rig's Action when the
   file opens) lets the arms hang at the sides as STAND sets out: the weapon points
   forward and the shield faces out. It also keys the controls where the hands and
   elbows are, so switching the IK on keeps the pose.
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
from mathutils.geometry import convex_hull_2d

H = 1.26
MX = "mixamorig:"
SIDES = (("Left", 1), ("Right", -1))
FINGERS = ("Index", "Middle", "Ring", "Pinky")
KNUCKLE_U = 0.655   # the knuckle row, distance from the centre line (both hands)
PHALANX = (0.45, 0.30, 0.25)   # finger length shares of the three segments
FIST_R = 0.008                 # the left hand closes round a rod this thick: a clenched fist
SHIELD_AT = 0.83               # shield's back centre, as a share of elbow to wrist: low enough
                               # that the back of the fist lies on its flat middle, not its edge
SHIELD_TILT = 6                # degrees: each shield's upper end turned outward, off the shoulder,
SHIELD_TILT_FIT = 2            # give or take this, fitted per shield so its back meets the fist too
SHIELD_GAP = 0.001             # each shield's back rests this far over the forearm and the fist
WRIST_BACK = range(-6, 13)     # degrees the left wrist may bend toward the back of the hand (- palm)
RAG_CLEAR = 0.0015             # the arm rag stays this far under each shield's back
SHIELD_SLIDE = range(0, 41, 5) # mm a shield may slide toward the hand, so no skin cuts its rim
STRAP_AT = (0.18, 0.82)        # leather straps round the forearm, as shares of elbow to wrist
STRAP_W, STRAP_T = 0.026, 0.004   # each strap's width and thickness
STRAP_CLEAR = 0.0015           # the straps stay this far off the skin
STRAP_FLARE, STRAP_TAB = 0.008, 0.022   # from the arm's side to each strap's nail; its end nailed flat
STRAP_SHIFT = range(-24, 25, 2)   # mm a strap may move along the forearm to lie flat on one plank
HANDLE_POST = (0.018, 0.022)   # the barrel handle's posts, along the bar and across it
# The standard pose (degrees): collarbones lowered, upper arms 14 out from hanging
# straight down and 6 forward, elbows bent 20 forward, wrists turned 20 toward the
# little finger (the weapon then points forward, level).
STAND = {"collar": 6, "out": 14, "forward": 6, "elbow": 20, "wrist": 20}
# Joints of the left side read off the T-pose (front and side views at 1 mm per pixel);
# the right side mirrors x. The spine's depth is measured below.
J0 = {
    "Head": (0, 0.03, 1.045), "HeadTop_End": (0, 0.03, 1.26),
    "Shoulder": (0.03, 0.08, 0.93), "Arm": (0.155, 0.122, 0.915), "ForeArm": (0.345, 0.131, 0.894),
    "Hand": (0.555, 0.075, 0.895),
    "UpLeg": (0.095, 0.035, 0.555), "Leg": (0.135, -0.035, 0.33), "Foot": (0.153, -0.012, 0.075),
    "ToeBase": (0.16, -0.115, 0.025), "Toe_End": (0.18, -0.20, 0.02),
}
SPINE_Z = {"Hips": 0.58, "Spine": 0.66, "Spine1": 0.74, "Spine2": 0.83, "Neck": 0.965}
LOADOUTS = (("Knife", "ShieldBarrel"), ("Hatchet", "ShieldPlank"), ("Cleaver", "ShieldBarrel"))

argv = sys.argv[sys.argv.index("--") + 1:]
out_blend = Path(argv[0]).resolve()
sc = bpy.context.scene
body = bpy.data.objects["GoblinRabble"]
PROPS = {n: bpy.data.objects[n] for n in ("Knife", "Hatchet", "Cleaver", "ShieldBarrel", "ShieldPlank")}
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


def is_rag(P):
    """The rag tied round the left upper arm: its band, knot and tails."""
    return P[:, 2].min() > 0.84 and 0.2 < abs(P[:, 0].mean()) < 0.36


# --- Shield placement and the rag under it ----------------------------------------
# The shields lie on the back of the left forearm, their back centre SHIELD_AT of the
# way from the elbow to the wrist; their height runs across the forearm, toward the
# thumb. Each is tilted SHIELD_TILT outward about that cross axis, so its upper end
# stands off the shoulder when the arm hangs, and then set SHIELD_GAP over the highest
# skin, wrap or hand under it. The rag is pressed down under them after that. The
# standard pose fits each shield's tilt and height again, with the fist (below).
el, wr = Vector(J0["ForeArm"]), Vector(J0["Hand"])
f_dir = (wr - el).normalized()
up_n = Vector((f_dir.y, -f_dir.x, 0)).normalized()     # across the forearm, toward the thumb
if up_n.y > 0:
    up_n = -up_n
sa = el.lerp(wr, SHIELD_AT)


def shield_frame(tilt):
    """A shield with its back centre on the forearm's axis, tilted `tilt` degrees. Shield
    local: x along the forearm toward the shoulder, y back (+) to front (-), z across. Its
    front faces +z before the tilt, which lifts the shoulder end (+x)."""
    return (frame_matrix(sa, Vector((up_n.y, -up_n.x, 0)), Vector((0, 0, -1)), up_n)
            @ Matrix.Rotation(math.radians(-tilt), 4, "Z"))


S_frame = shield_frame(SHIELD_TILT)
FACE = np.array([0.0, 0.0, 1.0])
bm = bmesh.new()
bm.from_mesh(body.data)
rag_parts = [p for p in shells(bm) if len(p) < 300 and is_rag(V[p])]
rag = np.zeros(N, bool)
rag[np.concatenate(rag_parts)] = True


def shield_face(M):
    return (M.to_3x3() @ Vector((0, -1, 0))).normalized()


TREES = {}


def shield_tree(sn):
    """A BVH tree of the shield's own mesh, in its own frame."""
    if sn not in TREES:
        me_s = PROPS[sn].data
        TREES[sn] = BVHTree.FromPolygons([v.co.copy() for v in me_s.vertices], [list(f.vertices) for f in me_s.polygons])
    return TREES[sn]


def past_back(Q, shields):
    """How far each point is past the back of the shield over it, along that shield's
    face (the most over the (name, world matrix) pairs in `shields`; -inf where no
    shield is over it). A point more than 0.15 m past a back stands in front of that
    shield, as the ear does over the shoulder, and is not under it. The points are taken
    into each shield's own (rigid) frame, so its tree is built once."""
    d = np.full(len(Q), -np.inf)
    face = Vector((0, -1, 0))
    for sn, M in shields:
        tree = shield_tree(sn)
        Mi = M.inverted()
        for i, q in enumerate(Q):
            ql = Mi @ Vector(q)
            hit = tree.ray_cast(ql - face * 0.3, face, 0.6)[0]
            if hit is not None and (ql - hit).dot(face) < 0.15:
                d[i] = max(d[i], (ql - hit).dot(face))
    return d


def under(M, P, keep):
    """The points of P near enough the shield at M to be under it."""
    return np.nonzero(keep & (np.linalg.norm(P - np.array(M.translation), axis=1) < 0.4))[0]


SHIELD_WORLD = {}
for sn in ("ShieldBarrel", "ShieldPlank"):
    idx = under(S_frame, V, ~rag)
    d = past_back(V[idx], [(sn, S_frame)])
    lift = float(d.max()) + SHIELD_GAP
    SHIELD_WORLD[sn] = Matrix.Translation(shield_face(S_frame) * lift) @ S_frame
    print("RIG_SHIELD %s tilted %d deg outward, %.1f mm over the forearm's axis; the skin nearest it is at local x %+.2f"
          % (sn, SHIELD_TILT, lift * 1000, (S_frame.inverted() @ Vector(V[idx[d.argmax()]])).x))
S0 = SHIELD_WORLD["ShieldBarrel"].translation.copy()

# Each part of the rag is squashed toward its lowest point, straight down, until it is
# RAG_CLEAR under every shield's back. A part that would keep less than half its height
# goes: the two tails, which stand up through both shields. The band and knot stay.
shields = list(SHIELD_WORLD.items())
drop = []
for p in rag_parts:
    d = past_back(V[p], shields)
    h = V[p] @ FACE - (V[p] @ FACE).min()
    need = d + RAG_CLEAR
    m = (need > 0) & (h > 1e-6)
    k = float(np.min(1 - need[m] / h[m])) if m.any() else 1.0
    if k < 0.5:
        drop.extend(p.tolist())
        print("RIG_RAG removed a part of %d vertices, up to %.1f mm through a shield" % (len(p), d.max() * 1000))
        continue
    for i, hh in zip(p, h):
        bm.verts[i].co -= Vector(FACE) * float(hh * (1 - k))
    V[p] -= FACE * (h * (1 - k))[:, None]
    print("RIG_RAG part of %d vertices: %d too near a shield, squashed to %.2f of its height, now %.1f mm under it"
          % (len(p), m.sum(), k, -past_back(V[p], shields).max() * 1000))
bmesh.ops.delete(bm, geom=[bm.verts[i] for i in drop], context="VERTS")
bm.to_mesh(body.data)
bm.free()
body.data.update()
V = np.array([v.co[:] for v in body.data.vertices])
N = len(V)
rag = np.delete(rag, drop)

# --- Shells ------------------------------------------------------------------
bm = bmesh.new()
bm.from_mesh(body.data)
parts = shells(bm)
bm.free()
chain_vg = body.vertex_groups["Chain"]
in_chain = np.zeros(N, bool)
for v in body.data.vertices:
    in_chain[v.index] = any(g.group == chain_vg.index and g.weight > 0.5 for g in v.groups)
main = max(range(len(parts)), key=lambda k: len(parts[k]))
kind = {}
for k, p in enumerate(parts):
    P = V[p]
    lo, hi, c = P.min(0), P.max(0), P.mean(0)
    ax = sorted((abs(lo[0]), abs(hi[0])))
    if k == main:
        kind[k] = "body"
    elif in_chain[p].all():
        kind[k] = "chain"
    elif len(p) > 300 and abs(c[0]) > 0.5:
        kind[k] = "hand_L" if c[0] > 0 else "hand_R"
    elif lo[0] * hi[0] > 0 and ax[0] > 0.40 and ax[1] < 0.60:
        kind[k] = "wrap"
    elif lo[2] > 1.0 and hi[1] < -0.05:
        kind[k] = "head"        # eyes and tusks
    elif is_rag(P):
        kind[k] = "rag"         # the rag on the left arm and its knot
    elif lo[2] > 0.88 and abs(c[0]) < 0.12:
        kind[k] = "collar"      # the collar and the rivets at its back
    elif lo[2] > 0.48 and hi[2] < 0.63:
        kind[k] = "belt"        # belt, skull charm, fangs and buckles
    elif hi[2] - lo[2] > 0.25 and hi[0] - lo[0] < 0.22:
        kind[k] = "flap_F" if c[1] < 0 else "flap_B"
    else:
        kind[k] = "skirt"
counts = {}
for k in kind.values():
    counts[k] = counts.get(k, 0) + 1
print("RIG_SHELLS", counts)
assert counts.get("hand_L") == 1 and counts.get("hand_R") == 1 and counts.get("chain", 0) >= 5
B = V[parts[main]]


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
    """Joints (armature space) and radii of the four fingers and the thumb, from the hand's shell."""
    idx = parts[next(k for k, v in kind.items() if v == "hand_" + side[0])]
    U = V[:, 0] * s
    in_hand = np.zeros(N, bool)
    in_hand[idx] = True
    for u_web in np.arange(0.656, 0.70, 0.002):     # past the webs the four fingers are apart
        comps = [c for c in components(in_hand & (U > u_web)) if len(c) >= 12]
        if len(comps) == 4:
            break
    assert len(comps) == 4, f"{side} hand: the four fingers were not found"
    comps.sort(key=lambda c: V[c, 1].mean())         # index (front) to pinky
    in_fingers = np.zeros(N, bool)
    hand = {"idx": idx, "fingers": {}}
    for name, c in zip(FINGERS, comps):
        in_fingers[c] = True
        F = np.c_[U[c], V[c, 1:]]
        tip_u = F[:, 0].max()
        L = tip_u - 0.004 - KNUCKLE_U
        pts, rad = [], []
        for u in (KNUCKLE_U, KNUCKLE_U + PHALANX[0] * L, KNUCKLE_U + (PHALANX[0] + PHALANX[1]) * L, tip_u - 0.004):
            uu = min(max(u, u_web + 0.008), tip_u - 0.008)
            d = np.abs(F[:, 0] - uu)
            q = F[d <= max(0.005, np.sort(d)[9])]    # within 5 mm, at least the ten nearest
            pts.append((s * u, (q[:, 1].min() + q[:, 1].max()) / 2, (q[:, 2].min() + q[:, 2].max()) / 2))
            rad.append(min(np.ptp(q[:, 1]), np.ptp(q[:, 2])) / 2)
        hand["fingers"][name] = (np.array(pts), np.array(rad))
    # Thumb: what hangs below and in front of the palm. Its two phalanges lie along its axis.
    th = components(in_hand & ~in_fingers & (U > 0.585) & (V[:, 1] < 0.01) & (V[:, 2] < 0.875))[0]
    T = np.c_[U[th], V[th, 1:]]
    cen = T.mean(0)
    ax = np.linalg.svd(T - cen)[2][0]
    ax = ax if ax[0] > 0 else -ax
    t = (T - cen) @ ax
    trad = float(np.median(np.linalg.norm((T - cen) - np.outer(t, ax), axis=1)))
    mcp, tip = cen + ax * (t.min() + 0.006), cen + ax * (t.max() - 0.004)
    # The metacarpal starts in the heel of the hand, by the wrist and in from the thumb.
    u_cmc = J0["Hand"][0] + 0.012
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
    """Skin weights of the hand's shell: each vertex to the nearest bones of its own finger
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
    return names, R, smooth_step((P[:, 0] * s - 0.535) / 0.04)


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
    own space between heights z0 and z1 and read back trilinearly."""

    def __init__(self, obj, z0, z1, step=0.002):
        me = obj.data
        P = np.array([v.co[:] for v in me.vertices])
        tree = BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [list(p.vertices) for p in me.polygons])
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
    """A round rod along z, what the left hand closes round for a loose fist."""

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
        self.s, self.step, self.u0, self.y0 = s, 0.003, 0.53, -0.05
        us = self.u0 + self.step * np.arange(int((KNUCKLE_U + 0.02 - self.u0) / self.step) + 1)
        ys = self.y0 + self.step * np.arange(int(0.20 / self.step) + 1)
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
        palm = idx[~hd["in_fingers"][idx] & ~np.isin(idx, hd["thumb_idx"])]
        n = np.linalg.svd(V[palm] - V[palm].mean(0))[2][2]
        self.n = n if n[2] < 0 else -n
        # Along the hand: the four fingers' mean direction in the palm's plane (the wrist to
        # the middle knuckle runs some 20 degrees off it), so the spread is even about it.
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
        for ci in range(1, 5):
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
              "spread in (deg)", [round(math.degrees(self.phi[ci]), 1) for ci in range(1, 5)],
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
    turned tau toward the wrist on the pinky side), slid sigma along itself and pressed up
    until it just touches the palm. Columns x, y, z of R: z the axis toward the thumb, -x the
    edge, facing out of the fist; o the prop's origin."""
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
    for ci in range(1, 5):
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
    for ci, f in enumerate(CHAINS):
        P, Wp, seg, _ = hand.chains[ci]
        Rs, ts = thumb_pose(hand, X[None]) if ci == 0 else finger_pose(hand, ci, Ts[ci][None])
        Q = moved(Rs, ts, P, Wp)
        sd = sdf(Q)[0] * 1000
        ang = (X[:3] / DEG).tolist() + (X[3:] / DEG).tolist() if ci == 0 else (Ts[ci] / DEG).tolist()
        extra = " to its rest %.1f mm" % (np.linalg.norm(Q[0, seg == 3].mean(0) - target) * 1000) if ci == 0 else ""
        print("RIG_GRIP", label, f, "angles", np.round(ang, 1).tolist(), "closest per phalanx (mm)",
              [round(float(sd[seg == i].min()), 1) for i in (1, 2, 3)], "deepest %.1f" % sd.min() + extra)


def solve_grip(hand, field, sigmas, label, refine=6):
    tried = []
    for U in np.arange(0.605, 0.6551, 0.01):
        for tau in (6, 12, 18):
            for sigma in sigmas:
                R, o = place(hand, U, tau * DEG, sigma, field)
                sdf = lambda Q, R=R, o=o: field((Q - o) @ R)
                E, Ts = 2.0 * (sigma * 1000) ** 2 / 1000, {}
                for ci in range(1, 5):
                    e = finger_energy(hand, ci, FLEX_GRID, sdf, coarse=True)
                    E += float(e.min())
                    Ts[ci] = FLEX_GRID[int(np.argmin(e))]
                tried.append((E, U, tau, sigma, R, o, Ts))
    tried.sort(key=lambda r: r[0])
    best = None
    for _, U, tau, sigma, R, o, Ts in tried[:refine]:
        sdf = lambda Q, R=R, o=o: field((Q - o) @ R)
        E = 2.0 * (sigma * 1000) ** 2 / 1000
        for ci in range(1, 5):
            Ts[ci], e = pattern(lambda T, ci=ci: finger_energy(hand, ci, T, sdf), Ts[ci],
                                np.array([4, 2, 1, 0.5]) * DEG, *FLEX_LIM)
            E += e
        X, et, target = solve_thumb(hand, Ts, sdf, R, o)
        print("RIG_PLACE", label, "U %.3f tilt %d slide %+.3f" % (U, tau, sigma), "fingers %.1f thumb %.1f" % (E, et))
        if best is None or E + et < best["E"]:
            best = {"E": E + et, "U": float(U), "tilt": tau, "slide": sigma, "R": R, "o": o, "Ts": dict(Ts), "X": X,
                    "side": hand.side, "target": target}
    sdf = lambda Q: field((Q - best["o"]) @ best["R"])
    grip_report(hand, best["Ts"], best["X"], sdf, best["target"], label)
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


GRIPS = {}
right = GripHand("Right", -1)
# Slides tried along each handle (positive: the hand lower, toward its end). The cleaver's
# hand keeps below the blade's heel, whose corner juts over the index finger.
SLIDES = {"Knife": (-0.03, -0.015, 0.0, 0.015, 0.03), "Hatchet": (-0.03, -0.015, 0.0, 0.015, 0.03),
          "Cleaver": (-0.015, 0.0, 0.015, 0.03, 0.045)}
for w in ("Knife", "Hatchet", "Cleaver"):
    GRIPS[w] = solve_grip(right, PropField(PROPS[w], -0.13, 0.15), SLIDES[w], w)
GRIPS["Fist"] = solve_grip(GripHand("Left", 1), Rod(FIST_R), (0.0,), "Fist")


# --- Armature ------------------------------------------------------------------
arm_data = bpy.data.armatures.new("GoblinRabbleRig")
rig = bpy.data.objects.new("GoblinRabbleRig", arm_data)
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
    for f in ("Thumb",) + FINGERS:
        par = MX + side + "Hand"
        for i in range(1, 4):
            nm = f"{MX}{side}Hand{f}{i}"
            new_bone(nm, J[f"{side}Hand{f}{i}"], J[f"{side}Hand{f}{i + 1}"], par, i > 1, DOWN)
            par = nm
        tip = J[f"{side}Hand{f}4"]
        new_bone(f"{MX}{side}Hand{f}4", tip, tip + (tip - J[f"{side}Hand{f}3"]).normalized() * 0.012, par, True, DOWN)
    tw = new_bone(side + "ForeArmTwist", J[side + "ForeArm"].lerp(J[side + "Hand"], 0.45), J[side + "Hand"],
                  MX + side + "ForeArm", False, DOWN)
    new_bone(MX + side + "UpLeg", J[side + "UpLeg"], J[side + "Leg"], MX + "Hips", False, FRONT)
    new_bone(MX + side + "Leg", J[side + "Leg"], J[side + "Foot"], MX + side + "UpLeg", True, FRONT)
    new_bone(MX + side + "Foot", J[side + "Foot"], J[side + "ToeBase"], MX + side + "Leg", True, FRONT)
    new_bone(MX + side + "ToeBase", J[side + "ToeBase"], J[side + "Toe_End"], MX + side + "Foot", True, FRONT)
    te = J[side + "Toe_End"]
    new_bone(MX + side + "Toe_End", te, te + (te - J[side + "ToeBase"]).normalized() * 0.03, MX + side + "ToeBase",
             True, FRONT)

# Collar chain: three bones from the ring down, the links two, three and two to a bone.
links = sorted([p for k, p in enumerate(parts) if kind[k] == "chain"], key=lambda p: -V[p, 2].max())
top = V[links[0]][np.argmax(V[links[0], 2])]
CHAIN_GROUPS = [links[0:2], links[2:5], links[5:]]
ends = [Vector((0, top[1], top[2]))]
for g in CHAIN_GROUPS[:-1]:
    lo = V[np.concatenate(g)]
    nxt = V[CHAIN_GROUPS[CHAIN_GROUPS.index(g) + 1][0]]
    p = (lo[np.argmin(lo[:, 2])] + nxt[np.argmax(nxt[:, 2])]) / 2
    ends.append(Vector((0, p[1], p[2])))
last = V[np.concatenate(CHAIN_GROUPS[-1])]
ends.append(Vector((0, last[np.argmin(last[:, 2])][1], last[:, 2].min())))
par = MX + "Spine2"
for i in range(3):
    new_bone(f"Chain{i + 1}", ends[i], ends[i + 1], par, i > 0, FRONT)
    par = f"Chain{i + 1}"


# Loincloth flaps: two bones each, from the belt down.
def flap_points(k_name):
    p = np.concatenate([parts[k] for k, v in kind.items() if v == k_name])
    P = V[p]
    z0, z1 = P[:, 2].max() - 0.02, P[:, 2].min()
    pts = []
    for z in (z0, (z0 + z1) / 2, z1):
        q = P[np.abs(P[:, 2] - z) < 0.03]
        pts.append(Vector((0, float(np.median(q[:, 1])), z)))
    return pts


for tag, k_name in (("Front", "flap_F"), ("Back", "flap_B")):
    p0, p1, p2 = flap_points(k_name)
    new_bone(f"Flap{tag}1", p0, p1, MX + "Hips", False, FRONT)
    new_bone(f"Flap{tag}2", p1, p2, f"Flap{tag}1", True, FRONT)

# Weapon and shield bones: their rest frames are the knife's grip and the shield's back.
FW = GRIPS["Knife"]["frame"]
wb = new_bone("Weapon", FW.col[3].xyz, FW.col[3].xyz + FW.col[2].xyz * 0.12, MX + "RightHand", False)
wb.align_roll(-FW.col[1].xyz)
sb = new_bone("Shield", S0, S0 + up_n * 0.15, MX + "LeftForeArm", False)
sb.align_roll(Vector((0, 0, 1)))

# Controls (parentless; Child Of constraints do the following, as in the reference video).
wc = new_bone("WeaponCtrl", wb.head, wb.tail)
wc.roll = wb.roll
for side, s in SIDES:
    hb = EB[MX + side + "Hand"]
    ik = new_bone("HandIK." + side[0], hb.head, hb.tail)
    ik.roll = hb.roll
    elbow = J[side + "ForeArm"]
    new_bone("ElbowPole." + side[0], elbow + Vector((0, 0.30, 0)), elbow + Vector((0, 0.36, 0)), MX + "Spine2")
    fb = EB[MX + side + "Foot"]
    fk = new_bone("FootIK." + side[0], fb.head, fb.tail)
    fk.roll = fb.roll
    knee = J[side + "Leg"]
    new_bone("KneePole." + side[0], knee + Vector((0, -0.35, 0)), knee + Vector((0, -0.41, 0)), "FootIK." + side[0])
new_bone("ChainGravity", ends[0] + Vector((0, 0, -0.6)), ends[0] + Vector((0, 0, -0.66)))
bpy.ops.object.mode_set(mode="OBJECT")

DEFORM_SKIP = ("HeadTop_End", "Toe_End", "Thumb4", "Index4", "Middle4", "Ring4", "Pinky4")
CONTROL = {"Weapon", "Shield", "WeaponCtrl", "ChainGravity"} | {f"{p}.{c}" for p in ("HandIK", "ElbowPole", "FootIK", "KneePole") for c in "LR"}
for b in arm_data.bones:
    b.use_deform = b.name not in CONTROL and not b.name.endswith(DEFORM_SKIP)
COLL = {"Body": [], "Fingers": [], "Twist": [], "Secondary": [], "Props": [], "Controls": []}
for b in arm_data.bones:
    n = b.name
    if n in ("Weapon", "Shield"):
        COLL["Props"].append(b)
    elif n in CONTROL:
        COLL["Controls"].append(b)
    elif any(f in n for f in ("Thumb", "Index", "Middle", "Ring", "Pinky")):
        COLL["Fingers"].append(b)
    elif "Twist" in n:
        COLL["Twist"].append(b)
    elif n.startswith(("Chain", "Flap")):
        COLL["Secondary"].append(b)
    else:
        COLL["Body"].append(b)
for cname, bones in COLL.items():
    bc = arm_data.collections.new(cname)
    for b in bones:
        bc.assign(b)
arm_data.collections["Twist"].is_visible = False
DEF = [b.name for b in arm_data.bones if b.use_deform]
BI = {n: i for i, n in enumerate(DEF)}
print("RIG_BONES", len(arm_data.bones), "deforming", len(DEF))

# --- Skin ------------------------------------------------------------------------
W = np.zeros((N, len(DEF)))


def heat_rows(vids):
    """Bone-heat weights of one shell (on a temporary copy, so the other shells
    neither shade it nor take part), for the body bones only."""
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
        b.use_deform = saved[b.name] and b.name.startswith(MX) and b not in COLL["Fingers"]
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


body_idx = parts[main]
heat_rows(body_idx)
segs = [(n, np.array(arm_data.bones[n].head_local), np.array(arm_data.bones[n].tail_local)) for n in DEF
        if not n.startswith(("Chain", "Flap")) and "Twist" not in n and arm_data.bones[n] not in COLL["Fingers"]]


empty = body_idx[W[body_idx].sum(1) < 1e-3]
if len(empty):
    D = np.stack([seg_d(V[empty], a, b) for _, a, b in segs], 1)
    for vi, j in zip(empty, D.argmin(1)):
        W[vi, BI[segs[j][0]]] = 1.0
print("RIG_SKIN body heat done, filled by nearest bone", len(empty))

# Forearm twist: the wrist half of each forearm moves onto its twist bone.
for side, s in SIDES:
    fa, tw = BI[MX + side + "ForeArm"], BI[side + "ForeArmTwist"]
    e, w = np.array(J[side + "ForeArm"]), np.array(J[side + "Hand"])
    t = ((V - e) @ (w - e)) / ((w - e) @ (w - e))
    k = smooth_step((t - 0.3) / 0.6)
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


def rigid(idx, keep=None):
    """One weight row for the whole shell: the mean of the body's under it."""
    row = transfer(idx).mean(0)
    if keep:
        mask = np.zeros(len(DEF), bool)
        for n in keep:
            mask[BI[n]] = True
        row = row * mask
    W[idx] = row / row.sum()


for k, kd in kind.items():
    idx = parts[k]
    if kd == "wrap":
        side = "Left" if V[idx, 0].mean() > 0 else "Right"
        s = 1 if side == "Left" else -1
        rows = transfer(idx)
        u = V[idx, 0] * s
        kk = smooth_step((u - 0.53) / 0.06)[:, None] * 0.6
        hand_row = np.zeros(len(DEF))
        hand_row[BI[MX + side + "Hand"]] = 1
        W[idx] = rows * (1 - kk) + hand_row * kk
    elif kd == "head":
        W[idx] = 0
        W[idx, BI[MX + "Head"]] = 1
    elif kd == "collar":
        pass   # with the rivets, below
    elif kd == "rag":
        rigid(idx, [MX + "LeftArm", MX + "LeftShoulder"])
    elif kd == "belt":
        rigid(idx, [MX + "Hips", MX + "Spine"])
    elif kd == "chain":
        W[idx] = 0
        g = next(i for i, grp in enumerate(CHAIN_GROUPS) if any(np.array_equal(idx, p) for p in grp))
        W[idx, BI[f"Chain{g + 1}"]] = 1
    elif kd == "skirt":
        # Hips at the belt, toward the thigh it covers lower down (blended across the middle).
        z = V[idx, 2]
        x = V[idx, 0]
        kk = (smooth_step((0.56 - z) / 0.20) * 0.7)[:, None]
        legs = np.zeros((len(idx), len(DEF)))
        sig = smooth_step((x + 0.035) / 0.07)
        legs[:, BI[MX + "LeftUpLeg"]] = sig
        legs[:, BI[MX + "RightUpLeg"]] = 1 - sig
        hips = np.zeros(len(DEF))
        hips[BI[MX + "Hips"]] = 1
        W[idx] = hips * (1 - kk) + legs * kk
collar_idx = np.concatenate([parts[k] for k, v in kind.items() if v == "collar"])
rigid(collar_idx, [MX + "Spine2", MX + "Neck", MX + "Spine1"])
belt_row = W[np.concatenate([parts[k] for k, v in kind.items() if v == "belt"])][0]
for tag, k_name in (("Front", "flap_F"), ("Back", "flap_B")):
    idx = np.concatenate([parts[k] for k, v in kind.items() if v == k_name])
    b1, b2 = arm_data.bones[f"Flap{tag}1"], arm_data.bones[f"Flap{tag}2"]
    z = V[idx, 2]
    ztop, zmid = b1.head_local.z, b2.head_local.z
    k1 = smooth_step((ztop + 0.005 - z) / 0.03)            # 0 at the belt, 1 below it
    k2 = smooth_step((zmid + 0.03 - z) / 0.06)             # onto the lower bone round the middle
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


for w in ("Knife", "Hatchet", "Cleaver"):
    mount(PROPS[w], "Weapon", GRIPS[w]["frame"])
for sn, M in SHIELD_WORLD.items():
    mount(PROPS[sn], "Shield", M)

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
for gname in ("Knife", "Hatchet", "Cleaver", "Fist"):
    side = GRIPS[gname]["side"]
    reset_pose()
    pose_hand(GRIPS[gname])
    act = bpy.data.actions.new("grip_" + gname.lower())
    act.use_fake_user = True
    rig.animation_data.action = act
    for f in ("Thumb",) + FINGERS:
        for i in range(1, 4):
            pb = rig.pose.bones[f"{MX}{side}Hand{f}{i}"]
            pb.keyframe_insert("rotation_quaternion", frame=1)
    rig.animation_data.action = None
    GRIP_ACTIONS[gname] = (act, side)
reset_pose()

rig["loadout"] = 0
rig.id_properties_ui("loadout").update(min=0, max=2, description="0 knife and barrel shield, 1 hatchet and plank shield, 2 cleaver and barrel shield")
for p, d in (("weapon_ik", "Right hand follows WeaponCtrl through HandIK.R"),
             ("shield_ik", "Left hand follows HandIK.L"), ("leg_ik", "Feet follow FootIK.L and FootIK.R")):
    rig[p] = 0.0
    rig.id_properties_ui(p).update(min=0.0, max=1.0, description=d)


def drive(owner, path, expr, prop, index=-1):
    fc = owner.driver_add(path, index) if index >= 0 else owner.driver_add(path)
    drv = fc.driver
    drv.type = "SCRIPTED"
    var = drv.variables.new()
    var.name = prop.split("_")[0] if prop != "loadout" else "loadout"
    var.type = "SINGLE_PROP"
    var.targets[0].id = rig
    var.targets[0].data_path = f'["{prop}"]'
    drv.expression = expr.replace("$", var.name)
    return drv


for gname, (act, side) in GRIP_ACTIONS.items():
    for f in ("Thumb",) + FINGERS:
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
            if gname != "Fist":
                k = ("Knife", "Hatchet", "Cleaver").index(gname)
                drive(c, "influence", f"1 - min(abs($ - {k}), 1)", "loadout")

for k, w in enumerate(("Knife", "Hatchet", "Cleaver")):
    for path in ("hide_viewport", "hide_render"):
        drive(PROPS[w], path, f"min(abs($ - {k}), 1)", "loadout")
for path in ("hide_viewport", "hide_render"):
    drive(PROPS["ShieldBarrel"], path, "1 - min(abs($ - 1), 1)", "loadout")
    drive(PROPS["ShieldPlank"], path, "min(abs($ - 1), 1)", "loadout")


# --- Controls --------------------------------------------------------------------
mod.show_viewport = False   # the pole searches below update the scene many times


def child_of(pb, target):
    c = pb.constraints.new("CHILD_OF")
    c.target, c.subtarget = rig, target
    c.inverse_matrix = rig.data.bones[target].matrix_local.inverted()
    return c


child_of(rig.pose.bones["WeaponCtrl"], MX + "Spine2").name = "follow chest"
child_of(rig.pose.bones["HandIK.R"], "WeaponCtrl").name = "follow weapon"
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


add_ik(MX + "RightForeArm", MX + "RightHand", "HandIK.R", "ElbowPole.R", "weapon_ik")
add_ik(MX + "LeftForeArm", MX + "LeftHand", "HandIK.L", "ElbowPole.L", "shield_ik")
add_ik(MX + "RightLeg", MX + "RightFoot", "FootIK.R", "KneePole.R", "leg_ik")
add_ik(MX + "LeftLeg", MX + "LeftFoot", "FootIK.L", "KneePole.L", "leg_ik")

# Each twist bone copies most of its hand's roll about the forearm.
for side, _ in SIDES:
    c = rig.pose.bones[side + "ForeArmTwist"].constraints.new("COPY_ROTATION")
    c.target, c.subtarget = rig, MX + side + "Hand"
    c.use_x = c.use_z = False
    c.target_space = c.owner_space = "LOCAL"
    c.influence = 0.85

# The chain hangs toward ChainGravity, which keeps under the ring as the chest moves.
cg = rig.pose.bones["ChainGravity"]
c = child_of(cg, MX + "Spine2")
c.use_rotation_x = c.use_rotation_y = c.use_rotation_z = False
c.use_scale_x = c.use_scale_y = c.use_scale_z = False
c.inverse_matrix = Matrix.Translation(rig.data.bones[MX + "Spine2"].head_local).inverted()   # location only
c = rig.pose.bones["Chain1"].constraints.new("DAMPED_TRACK")
c.target, c.subtarget, c.track_axis, c.influence = rig, "ChainGravity", "TRACK_Y", 0.85

# The flaps swing forward with the leading thigh (front) and back with the trailing one.
for tag, fn in (("Front", "max(0, l, r)"), ("Back", "min(0, l, r)")):
    pb = rig.pose.bones[f"Flap{tag}1"]
    pb.rotation_mode = "XYZ"
    fc = pb.driver_add("rotation_euler", 0)
    drv = fc.driver
    drv.type = "SCRIPTED"
    for vn, side in (("l", "Left"), ("r", "Right")):
        var = drv.variables.new()
        var.name, var.type = vn, "TRANSFORMS"
        t = var.targets[0]
        t.id, t.bone_target = rig, MX + side + "UpLeg"
        t.transform_type, t.transform_space, t.rotation_mode = "ROT_X", "LOCAL_SPACE", "SWING_TWIST_Y"
    drv.expression = f"0.8 * {fn}"

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
    side = "L" if ("Left" in n or n.endswith(".L")) else ("R" if ("Right" in n or n.endswith(".R")) else "C")
    pb.color.palette = {"L": "THEME04", "R": "THEME01", "C": "THEME09"}[side]
    if n in ("WeaponCtrl",):
        pb.custom_shape, pb.custom_shape_scale_xyz = W_CUBE, (0.25, 1.0, 0.25)
    elif n.startswith(("HandIK", "FootIK")):
        pb.custom_shape, pb.custom_shape_scale_xyz = W_RING, (1.0, 1.0, 1.0)
    elif n.startswith(("ElbowPole", "KneePole", "ChainGravity")):
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


# Each arm turns down about the front-to-back axis (palm toward the thigh, the back of
# the forearm and the shield outward), then forward; elbow and wrist bend about the
# axis that is vertical at rest, the elbow forward and the wrist the other way.
sc.frame_set(1)
reset_pose()
mod.show_viewport = True
bpy.context.view_layer.update()
P_REST = posed_mesh()   # the T-pose (the grips still apply), for the shields' fit below
pbs = rig.pose.bones
ARM_TURN, FORE = {}, {}
for side, s in SIDES:
    set_turn(MX + side + "Shoulder", turn("Y", s * STAND["collar"]))
    b = arm_data.bones[MX + side + "Arm"]
    d = b.tail_local - b.head_local
    below = math.degrees(math.atan2(-d.z, abs(d.x)))        # its slope down at rest
    ARM_TURN[side] = turn("X", -STAND["forward"]) @ turn("Y", s * (90 - STAND["out"] - below))
    set_turn(MX + side + "Arm", ARM_TURN[side])
    fore = FORE[side] = ARM_TURN[side] @ turn("Z", -s * STAND["elbow"])
    set_turn(MX + side + "ForeArm", fore)
    set_turn(MX + side + "Hand", fore @ turn("Z", s * STAND["wrist"]))

# --- The left fist and the shields --------------------------------------------------
# A strapped shield rests on the forearm, with the fist pressed to its back. For each
# bend of the left wrist in WRIST_BACK (toward the back of the hand, after its turn
# toward the little finger) and each tilt within SHIELD_TILT_FIT of SHIELD_TILT, a
# shield is set down along its face until the highest skin under it, here and in the
# T-pose, is SHIELD_GAP under its back and the rag RAG_CLEAR. What is then left over
# the forearm's highest point and over the fist's is air. The fit takes the least air
# (in half millimetres) over both shields, then the tilts nearest SHIELD_TILT, then the
# least bend of the wrist. Then each shield slides toward the hand, SHIELD_SLIDE
# millimetres at a time, and is set down again, until no body triangle passes through
# it in either pose: the barrel's rim, round and wider than the board, otherwise cuts
# the upper arm above the elbow, where no skin is under it to lift it clear.
HAND_L =np.array([sum(g.weight for g in v.groups if body.vertex_groups[g.group].name.startswith(MX + "LeftHand")) > 0.5
                   for v in body.data.vertices])
ARM_SKIN = ~rag & ~HAND_L
on_bone = pbs["Shield"].matrix @ arm_data.bones["Shield"].matrix_local.inverted()
TILTS = [SHIELD_TILT + k * 0.5 for k in range(-2 * SHIELD_TILT_FIT, 2 * SHIELD_TILT_FIT + 1)]


def highest(P, sn, M):
    """How far the arm skin, the fist and the rag reach past the back of the shield at M
    (the most of each; - is under it)."""
    idx = under(M, P, np.ones(len(P), bool))
    d = np.full(len(P), -np.inf)
    d[idx] = past_back(P[idx], [(sn, M)])
    return tuple(float(d[m].max()) for m in (ARM_SKIN, HAND_L, rag))


def seat(arm, fist, cloth, arm0, fist0, cloth0):
    """The height over the forearm's axis at which a shield rests on the skin reaching
    the given distances past its back, here and in the T-pose (0), and what is then
    left under its back."""
    lift = max(max(arm, fist, arm0, fist0) + SHIELD_GAP, max(cloth, cloth0) + RAG_CLEAR)
    return lift, {"forearm": lift - arm, "fist": lift - fist, "rag": lift - cloth,
                  "T-pose forearm": lift - arm0, "T-pose fist": lift - fist0, "T-pose rag": lift - cloth0}


body.data.calc_loop_triangles()
BODY_TRIS = [list(t.vertices) for t in body.data.loop_triangles]


def cut_through(sn, M, body_tree):
    """How many body triangles in `body_tree` pass through the shield at world matrix M."""
    me_s = PROPS[sn].data
    tree = BVHTree.FromPolygons([M @ v.co for v in me_s.vertices], [list(f.vertices) for f in me_s.polygons])
    return len({a for a, _ in body_tree.overlap(tree)})


at_rest = {(sn, t): highest(P_REST, sn, shield_frame(t)) for sn in SHIELD_WORLD for t in TILTS}
fits = []
for e in WRIST_BACK:
    set_turn(MX + "LeftHand", FORE["Left"] @ turn("Z", STAND["wrist"]) @ turn("Y", -e))
    P = posed_mesh()
    per = {}
    for sn in SHIELD_WORLD:
        for t in TILTS:
            arm, fist, cloth = highest(P, sn, on_bone @ shield_frame(t))
            lift, gaps = seat(arm, fist, cloth, *at_rest[sn, t])
            key = (round((2 * lift - 2 * SHIELD_GAP - arm - fist) * 2000) / 2, abs(t - SHIELD_TILT))
            if sn not in per or key < per[sn][0]:
                per[sn] = (key, t, lift, gaps)
    fits.append(((sum(p[0][0] for p in per.values()), sum(p[0][1] for p in per.values()), abs(e)), e, per))
    print("RIG_FIT_TRY wrist %+d:" % e, " | ".join("%s tilt %.1f air %.1f mm" % (sn, p[1], p[0][0]) for sn, p in per.items()))
_, WRIST_BACK_DEG, per = min(fits, key=lambda f: f[0])
set_turn(MX + "LeftHand", FORE["Left"] @ turn("Z", STAND["wrist"]) @ turn("Y", -WRIST_BACK_DEG))
SHIELD_FIT = {"left_wrist_back_deg": WRIST_BACK_DEG}
P = posed_mesh()
trees = [BVHTree.FromPolygons([Vector(p) for p in Q], BODY_TRIS) for Q in (P, P_REST)]
for sn, (_, t, lift, gaps) in per.items():
    for mm in SHIELD_SLIDE:
        M = shield_frame(t) @ Matrix.Translation((-mm / 1000, 0, 0))
        if mm:
            lift, gaps = seat(*highest(P, sn, on_bone @ M), *highest(P_REST, sn, M))
        M = Matrix.Translation(shield_face(M) * lift) @ M
        cuts = (cut_through(sn, on_bone @ M, trees[0]), cut_through(sn, M, trees[1]))
        if not any(cuts):
            break
        print("RIG_FIT_SLIDE %s %d mm toward the hand: %d body triangles through it standing, %d in the T-pose"
              % (sn, mm, *cuts))
    SHIELD_WORLD[sn] = M
    mount(PROPS[sn], "Shield", SHIELD_WORLD[sn])
    SHIELD_FIT[sn] = {"tilt_deg": t, "over_forearm_axis_mm": round(lift * 1000, 1), "toward_hand_mm": mm,
                      "body_triangles_through": sum(cuts)}
    print("RIG_FIT %s tilted %.1f deg, %d mm toward the hand, %.1f mm over the forearm's axis; under its back (mm): %s%s"
          % (sn, t, mm, lift * 1000, ", ".join("%s %.1f" % (k, v * 1000) for k, v in gaps.items()),
             "" if not any(cuts) else "; STILL %d body triangles through it" % sum(cuts)))
print("RIG_FIT the left wrist bends %+d deg toward the back of the hand" % WRIST_BACK_DEG)

# The controls where the pose put the hands and elbows (the chest is at rest, so their
# Child Of constraints change nothing): HandIK.R follows WeaponCtrl onto the right hand.
set_world(pbs["WeaponCtrl"], pbs["Weapon"].matrix.copy())
set_world(pbs["HandIK.L"], pbs[MX + "LeftHand"].matrix.copy())
for side, s in SIDES:
    pole = pbs["ElbowPole." + side[0]]
    M = (ARM_TURN[side] @ pole.bone.matrix_local.to_3x3()).to_4x4()
    M.translation = pbs[MX + side + "ForeArm"].head + ARM_TURN[side] @ (
        pole.bone.head_local - arm_data.bones[MX + side + "ForeArm"].head_local)
    set_world(pole, M)
stand = bpy.data.actions.new("stand")
stand.use_fake_user = True
rig.animation_data.action = stand
for side, _ in SIDES:
    for n in ("Shoulder", "Arm", "ForeArm", "Hand"):
        pbs[MX + side + n].keyframe_insert("rotation_quaternion", frame=1)
for n in ("WeaponCtrl", "HandIK.L", "ElbowPole.L", "ElbowPole.R"):
    pbs[n].keyframe_insert("location", frame=1)
    pbs[n].keyframe_insert("rotation_quaternion", frame=1)
bpy.context.view_layer.update()
fk = {n: pbs[MX + n].matrix.copy() for n in ("RightHand", "LeftHand", "RightForeArm", "LeftForeArm")}
rig["weapon_ik"] = rig["shield_ik"] = 1.0
rig.update_tag()
bpy.context.view_layer.update()
moved = {n: ((pbs[MX + n].matrix.translation - M.translation).length * 1000,
             math.degrees(pbs[MX + n].matrix.to_quaternion().rotation_difference(M.to_quaternion()).angle))
         for n, M in fk.items()}
rig["weapon_ik"] = rig["shield_ik"] = 0.0
rig.update_tag()
bpy.context.view_layer.update()
print("RIG_STAND weapon points", [round(c, 2) for c in pbs["Weapon"].matrix.to_3x3().col[1].normalized()],
      "| IK on moves", {n: "%.1f mm %.1f deg" % m for n, m in moved.items()})

# --- The fist's hold -----------------------------------------------------------------
# The fist holds the shield, so whatever a clip does to the left wrist, the hand keeps
# the turn from the forearm it has in `stand`: the helper bone `ShieldFist` sits on the
# forearm where the hand is in `stand`, and a Copy Rotation constraint on the hand
# (after the IK's, so it wins) follows it as much as the rig's `shield_fist` says (1 by
# default; 0 gives the wrist back to the clips and HandIK.L). The T-pose then shows the
# fist bent as it holds the shield.
fist_rest = (arm_data.bones[MX + "LeftForeArm"].matrix_local @ pbs[MX + "LeftForeArm"].matrix.inverted()
             @ pbs[MX + "LeftHand"].matrix)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
EB = arm_data.edit_bones
fb = EB.new("ShieldFist")
fb.head, fb.tail = Vector((0, 0, 0)), Vector((0, 0.08, 0))
fb.matrix = fist_rest
fb.parent = EB[MX + "LeftForeArm"]
fb.use_deform = False
bpy.ops.object.mode_set(mode="OBJECT")
mech = arm_data.collections.new("Mechanics")
mech.assign(arm_data.bones["ShieldFist"])
mech.is_visible = False
pbs = rig.pose.bones
pbs["ShieldFist"].rotation_mode = "QUATERNION"
pbs["ShieldFist"].color.palette = "THEME04"
rig["shield_fist"] = 1.0
rig.id_properties_ui("shield_fist").update(
    min=0.0, max=1.0, description="Left hand keeps the fist that holds the shield (0: clips and HandIK.L turn it)")
c = pbs[MX + "LeftHand"].constraints.new("COPY_ROTATION")
c.name = "hold the shield"
c.target, c.subtarget = rig, "ShieldFist"
drive(c, "influence", "$", "shield_fist")
rig.update_tag()
sc.frame_set(1)
bpy.context.view_layer.update()
held = math.degrees(pbs[MX + "LeftHand"].matrix.to_quaternion().rotation_difference(fk["LeftHand"].to_quaternion()).angle)
print("RIG_HOLD ShieldFist on the left forearm; the held fist is %.3f deg from the keyed one;" % held,
      "bones", len(arm_data.bones), "deforming", len([b for b in arm_data.bones if b.use_deform]))
assert held < 0.1


def tpose_mesh():
    """The body in the T-pose (the grips and the fist's hold still apply), then back in `stand`."""
    rig.animation_data.action = None
    reset_pose()
    Q = posed_mesh()
    rig.animation_data.action = stand
    if hasattr(rig.animation_data, "action_slot") and len(stand.slots):
        rig.animation_data.action_slot = stand.slots[0]
    sc.frame_set(1)
    bpy.context.view_layer.update()
    return Q


# --- Shields in the standard pose ---------------------------------------------------
# The keyed pose and the T-pose, both with the fist held, checked: the forearm and the
# fist SHIELD_GAP and the rag RAG_CLEAR under each shield's back, and no body triangle
# through it.
P = posed_mesh()
P_T = tpose_mesh()
on_bone = pbs["Shield"].matrix @ arm_data.bones["Shield"].matrix_local.inverted()
trees = [BVHTree.FromPolygons([Vector(p) for p in Q], BODY_TRIS) for Q in (P, P_T)]
for sn, M in SHIELD_WORLD.items():
    for label, Q, Mw, tree in (("STAND", P, on_bone @ M, trees[0]), ("TPOSE", P_T, M, trees[1])):
        arm, fist, cloth = highest(Q, sn, Mw)
        cuts = cut_through(sn, Mw, tree)
        print("RIG_SHIELD_%s %s: the forearm %.1f mm, the fist %.1f mm and the rag %.1f mm under its back; "
              "%d body triangles through it" % (label, sn, -arm * 1000, -fist * 1000, -cloth * 1000, cuts))
        assert -max(arm, fist) > SHIELD_GAP - 1e-4 and -cloth > RAG_CLEAR - 1e-4 and not cuts, (sn, label)

# --- Straps and the barrel's handle ---------------------------------------------------
# Two leather straps hold each shield on the forearm, STRAP_AT of the way from the
# elbow to the wrist. Each runs in the shield's own frame, square to the forearm: round
# the outline of the arm skin within its width, standing and in the T-pose, grown by
# STRAP_CLEAR, pulled taut from STRAP_FLARE beside the arm on one side to the other, its
# ends nailed flat on the board for STRAP_TAB with two round-headed nails each. A strap
# moves up to STRAP_SHIFT mm along the forearm where that lays its ends on more even
# board (on the plank shield, onto one plank rather than over a gap or a step), and its
# ends tilt with the board under them. The barrel shield also gets the handle its fist
# closes round: a round bar along the rod the fist was solved for, as thick as that rod
# (FIST_R) less what the skin's triangles cut off it between their vertices, on two posts
# just beside the fist, standing on the barrel's face (a single sheet, which a post set
# into it would come through). Each shield's straps (and handle) are one object,
# `ShieldBarrelStraps` or `ShieldPlankStraps`, on the `Shield` bone and shown with their
# shield. The straps are painted in
# textures/goblin_rabble_straps_basecolor.jpg (tools/paint_straps.py); the handle takes
# the wood of the barrel's own texture.
STRAP_TILE = 0.104                                          # the strap texture repeats every 104 mm
STRAP_V = {"ShieldBarrel": (0.752, 0.998), "ShieldPlank": (0.502, 0.748)}   # each shield's strap face
LEATHER_V = 0.38                                            # plain leather, for the straps' sides
RIVET_V, RIVET_R = 1 - 672 / 1024, 25 / 1024                # the nail heads, 16 in a row
WOOD = (Vector((0.7275, 0.7236)), Vector((0.574, 0.819)), 1.036)   # the barrel's wood: centre, grain, UV per m
# A strap's section, (across, out) as shares of its width and thickness: flat underneath,
# its upper edges bevelled.
PROFILE = ((-0.5, 0.0), (0.5, 0.0), (0.5, 0.55), (0.5 - 0.6 * STRAP_T / STRAP_W, 1.0),
           (-0.5 + 0.6 * STRAP_T / STRAP_W, 1.0), (-0.5, 0.55))
ARM_L = np.isin(W.argmax(1), [BI[n] for n in DEF if n.startswith(
    (MX + "LeftArm", MX + "LeftForeArm", "LeftForeArmTwist", MX + "LeftHand"))]) & ~rag
EA = np.zeros(2 * len(body.data.edges), dtype=np.int64)
body.data.edges.foreach_get("vertices", EA)
EA = EA.reshape(-1, 2)
EA = EA[ARM_L[EA].all(1)]


class Kit:
    """A mesh built face by face, each face with its UVs, material and part."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.part = []

    def vert(self, co):
        return self.bm.verts.new(Vector(co))

    def face(self, verts, uvs, part, mat=0):
        f = self.bm.faces.new(verts)
        f.material_index = mat
        for loop, uv in zip(f.loops, uvs):
            loop[self.uv].uv = uv
        self.part.append(part)


def hull_2d(Q):
    """The convex hull of 2D points, as indices in order round it."""
    h = np.array(convex_hull_2d([Vector(q) for q in Q]))
    c = Q[h].mean(0)
    return h[np.argsort(np.arctan2(Q[h, 1] - c[1], Q[h, 0] - c[0]))].tolist()


def section(L, xs, hw):
    """The arm skin (shield-local points L) between the planes x = xs - hw and xs + hw, seen
    along x, (y, z): its vertices there and where its edges cross the two planes."""
    out = [L[ARM_L & (np.abs(L[:, 0] - xs) <= hw)][:, 1:]]
    a, b = L[EA[:, 0]], L[EA[:, 1]]
    for X in (xs - hw, xs + hw):
        m = (a[:, 0] - X) * (b[:, 0] - X) < 0
        t = (X - a[m, 0]) / (b[m, 0] - a[m, 0])
        out.append((a[m] + (b[m] - a[m]) * t[:, None])[:, 1:])
    return np.concatenate(out)


def ray_board(sn, x, z):
    """The height (local y) of the shield's back at (x, z), or None through a gap or a hole."""
    hit = shield_tree(sn).ray_cast(Vector((x, 0.3, z)), Vector((0, -1, 0)), 0.6)[0]
    return None if hit is None else hit.y


def board_top(sn, x, z):
    """The shield's back at (x, z), where a handle's post stands."""
    y = ray_board(sn, x, z)
    assert y is not None, "%s: x %+.3f, z %+.3f is off the shield" % (sn, x, z)
    return y


def board_line(sn, xs, z0, z1, nz=3):
    """The shield's back under a strap's width at xs, from z0 to z1, as the line across it
    (along x) laid on its highest points: (height at xs, slope, the most air under the line,
    the share of rays through a gap or a hole), or None if most rays go through."""
    q = [(x - xs, ray_board(sn, x, z)) for x in np.linspace(xs - STRAP_W / 2, xs + STRAP_W / 2, 7)
         for z in np.linspace(z0, z1, nz)]
    hit = np.array([(dx, y) for dx, y in q if y is not None])
    if len(hit) < len(q) / 2:
        return None
    slope = float(np.polyfit(hit[:, 0], hit[:, 1], 1)[0])
    rest = hit[:, 1] - slope * hit[:, 0]
    return float(rest.max()), slope, float(rest.max() - rest.min()), 1 - len(hit) / len(q)


def footing(sn, xs, za, zb):
    """How badly a strap at xs would lie on the board, its nailed ends from za and zb out:
    the most air under either end (mm), each ray through a gap or a hole adding 10 mm
    times its share."""
    worst = 0.0
    for z0, z1 in ((za - STRAP_TAB, za), (zb, zb + STRAP_TAB)):
        line = board_line(sn, xs, z0, z1, nz=6)
        if line is None:
            return float("inf")
        worst = max(worst, line[2] * 1000 + 10 * line[3])
    return worst


def outline(Q):
    """The skin points Q, (y, z) seen along the forearm, as their convex outline grown by
    STRAP_CLEAR (rounded at its corners), and where a strap round them is nailed down on
    either side (z)."""
    hull = Q[hull_2d(Q)]
    ang = np.radians(np.arange(0, 360, 4))
    U = np.stack([np.cos(ang), np.sin(ang)], 1)
    S = hull[np.argmax(hull @ U.T, axis=0)] + STRAP_CLEAR * U
    return S, S[:, 1].min() - STRAP_FLARE, S[:, 1].max() + STRAP_FLARE


def strap_path(sn, xs, S, za, zb):
    """A strap's underside in the plane x = xs, as (y, z) points from one end to the other,
    and the board's slope across it (along x) where it lies on the board: flat on the board
    for STRAP_TAB, then taut over the outline S from za to zb, and flat again on the other
    side. Also its nails, (y of the underside, slope, z) on each flat end."""

    def on_board(z):
        line = board_line(sn, xs, z - 0.001, z + 0.001)
        assert line is not None, "%s: a strap end at x %+.3f, z %+.3f is off the shield" % (sn, xs, z)
        return line[0] + 0.0003, line[1]

    (ya, sa), (yb, sb) = on_board(za), on_board(zb)
    pts = np.vstack([S, [[ya, za], [yb, zb]]])
    tilt = np.r_[np.zeros(len(S)), sa, sb]
    h = hull_2d(pts)
    k = h.index(len(S))
    h = h[k:] + h[:k]
    j = h.index(len(S) + 1)
    over = max((h[:j + 1], [h[0]] + h[j:][::-1]), key=lambda c: pts[c, 0].max())   # the way over the arm
    ends = []
    for z0, z1 in ((za - STRAP_TAB, za), (zb, zb + STRAP_TAB)):
        zs = np.linspace(z0, z1, 12)
        b = [on_board(z) for z in zs]
        ends.append((np.array([[y, z] for (y, _), z in zip(b, zs)]), np.array([s for _, s in b])))
    path = np.vstack([ends[0][0][:-1], pts[over], ends[1][0][1:]])
    slopes = np.r_[ends[0][1][:-1], tilt[over], ends[1][1][1:]]
    keep = [0]
    for i in range(1, len(path)):
        if np.linalg.norm(path[i] - path[keep[-1]]) > 0.0008 or i == len(path) - 1:
            keep.append(i)
    return path[keep], slopes[keep], [(*on_board(z), z) for z in (za - STRAP_TAB / 2, zb + STRAP_TAB / 2)]


def sweep_strap(kit, xs, path, slopes, v_face):
    """The strap's section (PROFILE) swept along `path` in the plane x = xs, mitred at the
    bends and tilted across with the board where it lies on it; returns its length."""
    T = np.diff(path, axis=0)
    T /= np.linalg.norm(T, axis=1, keepdims=True)
    Ns = np.stack([T[:, 1], -T[:, 0]], 1)                  # away from the arm and the board
    Nv = np.vstack([Ns[:1], Ns[:-1] + Ns[1:], Ns[-1:]])
    Nv /= np.linalg.norm(Nv, axis=1, keepdims=True)
    Nv[1:-1] /= np.maximum((Nv[1:-1] * Ns[1:]).sum(1), 0.5)[:, None]
    s_in = np.r_[0, np.cumsum(np.linalg.norm(np.diff(path, axis=0), axis=1))]
    outer = path + Nv * STRAP_T
    s_out = np.r_[0, np.cumsum(np.linalg.norm(np.diff(outer, axis=0), axis=1))]
    rings = [[kit.vert((xs + a * STRAP_W, p[0] + s * a * STRAP_W + n[0] * h * STRAP_T, p[1] + n[1] * h * STRAP_T))
              for a, h in PROFILE] for p, n, s in zip(path, Nv, slopes)]

    def uv(i, p, k):
        a, h = PROFILE[p]
        if k in (2, 3, 4):                                  # the face and its bevels
            return s_out[i] / STRAP_TILE, v_face[0] + (a + 0.5) * (v_face[1] - v_face[0])
        if k == 0:                                          # the underside
            return s_in[i] / STRAP_TILE, LEATHER_V + (a + 0.5) * 0.08
        return s_in[i] / STRAP_TILE, LEATHER_V + 0.09 + h * 0.02
    for i in range(len(path) - 1):
        for k in range(6):
            p, q = k, (k + 1) % 6
            kit.face([rings[i][p], rings[i][q], rings[i + 1][q], rings[i + 1][p]],
                     [uv(i, p, k), uv(i, q, k), uv(i + 1, q, k), uv(i + 1, p, k)], "strap")
    for ring in (rings[0], rings[-1]):
        kit.face(ring, [(0.02 + a * 0.02, LEATHER_V + 0.02 + h * 0.03) for a, h in PROFILE], "strap")
    return s_in[-1]


def dome(kit, base, up, r, h, sprite, part):
    """A round nail head of radius r and height h on `base`, facing `up`, painted as one of
    the atlas's nail heads."""
    up = up.normalized()
    e1 = up.orthogonal().normalized()
    e2 = up.cross(e1)
    uc = ((sprite % 16) * 64 + 32) / 1024
    rings = []
    for phi in (0.0, 0.6, 1.1):
        cr, sr = math.cos(phi), math.sin(phi)
        rings.append([(kit.vert(base + (e1 * math.cos(t) + e2 * math.sin(t)) * (r * cr) + up * (h * sr)),
                       (uc + RIVET_R * cr * math.cos(t), RIVET_V + RIVET_R * cr * math.sin(t)))
                      for t in np.linspace(0, 2 * math.pi, 12, endpoint=False)])
    top = (kit.vert(base + up * h), (uc, RIVET_V))
    for lo, hi in zip(rings, rings[1:] + [None]):
        for j in range(12):
            q = (j + 1) % 12
            if hi is None:
                kit.face([lo[j][0], lo[q][0], top[0]], [lo[j][1], lo[q][1], top[1]], part)
            else:
                kit.face([lo[j][0], lo[q][0], hi[q][0], hi[j][0]], [lo[j][1], lo[q][1], hi[q][1], hi[j][1]], part)
    kit.face([v for v, _ in rings[0]][::-1], [uv for _, uv in rings[0]][::-1], part)


def wood(s1, s2, off):
    """UVs on the barrel's wood: s1 metres along the grain, s2 across it."""
    c, g, k = WOOD
    return c + Vector(off) + g * (s1 * k) + Vector((-g.y, g.x)) * (s2 * k)


def handle(kit, sn, Ms, P):
    """The barrel's handle, in its own frame (the shield standing at Ms): a round bar along
    the rod the fist was solved round, on two posts beside the fist, nailed through."""
    Fl = (Ms.inverted() @ pbs[MX + "LeftHand"].matrix @ arm_data.bones[MX + "LeftHand"].matrix_local.inverted()
          @ GRIPS["Fist"]["frame"])
    o, a = Fl.translation, Fl.col[2].xyz.normalized()
    up = Vector((0, 1, 0))
    al = Vector((a.x, 0, a.z)).normalized()                # along the bar and across it, on the board
    ac = up.cross(al)
    pa, pc = HANDLE_POST
    # The hand skin a post would meet: within a post's width of the bar's line and below
    # the post's top. The posts stand 4 mm beyond it on either side.
    Mi = np.array(Ms.inverted())
    d = P[HAND_L] @ Mi[:3, :3].T + Mi[:3, 3] - np.array(o)
    t, u = d @ np.array(a), d @ np.array(ac)
    block = (np.abs(u) < pc / 2 + 0.003) & (d[:, 1] < t * a.y + 0.3 * FIST_R + 0.003)
    posts = (t[block].min() - 0.004 - pa / 2, t[block].max() + 0.004 + pa / 2)
    tb = (posts[0] - pa / 2 - 0.003, posts[1] + pa / 2 + 0.003)
    # The bar's radius: the rod's, less what the hand's triangles cut off it between their
    # vertices, sampled across each triangle, with 0.2 mm to spare.
    tri = np.array(BODY_TRIS)
    tri = tri[HAND_L[tri].any(1)]
    bc = np.array([(i, j, 6 - i - j) for i in range(7) for j in range(7 - i)]) / 6
    S = np.einsum("kc,tcd->tkd", bc, (P @ Mi[:3, :3].T + Mi[:3, 3] - np.array(o))[tri]).reshape(-1, 3)
    ts_ = S @ np.array(a)
    rad = np.linalg.norm(S - ts_[:, None] * np.array(a), axis=1)[(ts_ > tb[0]) & (ts_ < tb[1])]
    r = min(FIST_R, float(rad.min()) - 0.0002)
    assert r > 0.7 * FIST_R, "the fist's skin comes %.1f mm into the handle's rod" % ((FIST_R - rad.min()) * 1000)
    e1 = (up - a * a.dot(up)).normalized()                  # away from the board
    e2 = a.cross(e1)
    step = 2 * math.pi / 10
    ts = (tb[0], tb[0] + 0.0015, tb[1] - 0.0015, tb[1])
    rings = [[kit.vert(o + a * tt + (e1 * math.cos(j * step) + e2 * math.sin(j * step)) * (r * f))
              for j in range(10)] for tt, f in zip(ts, (0.75, 1, 1, 0.75))]
    for i in range(3):
        for j in range(10):
            q = (j + 1) % 10
            kit.face([rings[i][j], rings[i][q], rings[i + 1][q], rings[i + 1][j]],
                     [wood(ts[i], j * step * r, (0, 0)), wood(ts[i], (j + 1) * step * r, (0, 0)),
                      wood(ts[i + 1], (j + 1) * step * r, (0, 0)), wood(ts[i + 1], j * step * r, (0, 0))],
                     "handle", 1)
    cap = [wood(0.006 * math.cos(j * step), 0.006 * math.sin(j * step), (0.05, 0)) for j in range(10)]
    kit.face(rings[0][::-1], cap[::-1], "handle", 1)
    kit.face(rings[-1], cap, "handle", 1)
    sq = ((-1, -1), (1, -1), (1, 1), (-1, 1))
    tall = []
    for k, tp in enumerate(posts):
        c = o + a * tp

        def corner(sa, sc, shrink=0.0):
            return Vector((c.x, 0, c.z)) + al * (sa * (pa / 2 - shrink)) + ac * (sc * (pc / 2 - shrink))
        foot = [corner(sa, sc) for sa in (-1, 0, 1) for sc in (-1, 0, 1)]
        yb = min(board_top(sn, p.x, p.z) for p in foot) + 0.0002  # on the board: it is a single sheet
        yt = c.y + 0.3 * r
        bot = [kit.vert(corner(*s) + up * yb) for s in sq]
        top = [kit.vert(corner(*s, 0.0015) + up * yt) for s in sq]
        off = (0.03 * k - 0.04, -0.03)                      # each post its own piece of the wood
        for j in range(4):
            q = (j + 1) % 4
            w = pa if j % 2 == 0 else pc
            kit.face([bot[j], bot[q], top[q], top[j]],
                     [wood(0, 0, off), wood(0, w, off), wood(yt - yb, w, off), wood(yt - yb, 0, off)], "handle", 1)
        kit.face(top, [wood(s[0] * pa / 2, s[1] * pc / 2, off) for s in sq], "handle", 1)
        kit.face(bot[::-1], [wood(s[0] * pa / 2, s[1] * pc / 2, off) for s in sq[::-1]], "handle", 1)
        dome(kit, o + a * tp + e1 * (r - 0.0012), e1, 0.0035, 0.0024, 9 + k, "handle")
        tall.append(yt - yb)
    return {"bar_mm": round((tb[1] - tb[0]) * 1000, 1), "bar_radius_mm": round(r * 1000, 1),
            "posts_tall_mm": [round(x * 1000, 1) for x in tall],
            "fist_across_mm": round((t[block].max() - t[block].min()) * 1000, 1)}


straps_mat = PROPS["ShieldBarrel"].data.materials[0].copy()
straps_mat.name = "GoblinRabbleStraps"
img = bpy.data.images.load(str(Path(bpy.data.filepath).parent / "textures" / "goblin_rabble_straps_basecolor.jpg"))
img.name = "goblin_rabble_straps_basecolor"
img.filepath = "//textures/goblin_rabble_straps_basecolor.jpg"   # relative, like the other textures
tex = [n for n in straps_mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image]
assert len(tex) == 1
tex[0].image, tex[0].extension = img, "REPEAT"
el_w, wr_w = pbs[MX + "LeftForeArm"].head.copy(), pbs[MX + "LeftHand"].head.copy()
for sn, M in SHIELD_WORLD.items():
    Ms = on_bone @ M
    Mi_s, Mi_t = np.array(Ms.inverted()), np.array(M.inverted())
    Ls, Lt = P @ Mi_s[:3, :3].T + Mi_s[:3, 3], P_T @ Mi_t[:3, :3].T + Mi_t[:3, 3]
    xe, xw = (Ms.inverted() @ el_w).x, (Ms.inverted() @ wr_w).x
    kit = Kit()
    info, nail = {"at_x_mm": [], "shifted_mm": [], "long_mm": []}, 0
    for share in STRAP_AT:
        x0 = xe + (xw - xe) * share
        _, za, zb = outline(np.vstack([section(L, x0, STRAP_W / 2 + 0.001) for L in (Ls, Lt)]))
        mm = min(STRAP_SHIFT, key=lambda m: (round(footing(sn, x0 + m / 1000, za, zb) * 2) / 2, abs(m)))
        xs = x0 + mm / 1000
        path, slopes, nails = strap_path(sn, xs, *outline(np.vstack([section(L, xs, STRAP_W / 2 + 0.001)
                                                                    for L in (Ls, Lt)])))
        info["at_x_mm"].append(round(xs * 1000, 1))
        info["shifted_mm"].append(mm)
        info["long_mm"].append(round(float(sweep_strap(kit, xs, path, slopes, STRAP_V[sn])) * 1000, 1))
        print("RIG_STRAP %s at %.2f of the forearm, moved %+d mm onto even board (%.1f mm of air under its ends)"
              % (sn, share, mm, footing(sn, xs, za, zb)))
        for y, sl, z in nails:
            for dx in (-STRAP_W / 4, STRAP_W / 4):
                dome(kit, Vector((xs + dx, y + sl * dx + STRAP_T - 0.0004, z)), Vector((-sl, 1, 0)), 0.004, 0.0022,
                     nail, "strap")
                nail += 1
    if sn == "ShieldBarrel":
        info["handle"] = handle(kit, sn, Ms, P)
    bmesh.ops.recalc_face_normals(kit.bm, faces=kit.bm.faces)
    me = bpy.data.meshes.new(sn + "Straps")
    kit.bm.to_mesh(me)
    kit.bm.free()
    me.materials.append(straps_mat)
    if "handle" in info:
        me.materials.append(PROPS[sn].data.materials[0])
    me.shade_smooth()
    me.set_sharp_from_angle(angle=math.radians(40))
    ob = bpy.data.objects.new(sn + "Straps", me)
    for coll in PROPS[sn].users_collection:
        coll.objects.link(ob)
    mount(ob, "Shield", M)
    for path_ in ("hide_viewport", "hide_render"):
        drive(ob, path_, "1 - min(abs($ - 1), 1)" if sn == "ShieldBarrel" else "min(abs($ - 1), 1)", "loadout")
    # Checks, standing and in the T-pose: no body triangle through a strap, how near the
    # arm skin comes to the straps, and the handle touching only the fist closed round it.
    strap_faces = [list(me.polygons[i].vertices) for i, p in enumerate(kit.part) if p == "strap"]
    handle_faces = [list(me.polygons[i].vertices) for i, p in enumerate(kit.part) if p == "handle"]
    board_cuts = len({i for i, _ in BVHTree.FromPolygons([v.co for v in me.vertices], strap_faces).overlap(shield_tree(sn))})
    for label, Mw, tree, Q in (("standing", Ms, trees[0], P[ARM_L]), ("T-pose", M, trees[1], P_T[ARM_L])):
        V_w = [Mw @ v.co for v in me.vertices]
        through = {}
        for part, faces in (("straps", strap_faces), ("handle", handle_faces)):
            if faces:
                hits = {}
                for i, _ in tree.overlap(BVHTree.FromPolygons(V_w, faces)):
                    hits.setdefault(DEF[int(W[BODY_TRIS[i][0]].argmax())].replace(MX, ""), set()).add(i)
                through[part] = {b: len(s_) for b, s_ in hits.items()}
        st = BVHTree.FromPolygons(V_w, strap_faces)
        near = min((st.find_nearest(Vector(q), 0.05)[3] or 1.0) for q in Q)
        info["nearest_skin_mm" if label == "standing" else "nearest_skin_tpose_mm"] = round(near * 1000, 1)
        print("RIG_STRAPS %s %s: body triangles through the straps %s, the handle %s; the arm skin %.1f mm "
              "from the straps at the nearest; %d strap faces through the shield" % (
                  sn, label, through["straps"] or 0, through.get("handle", "-") or 0, near * 1000, board_cuts))
        assert not through["straps"], (sn, label)
        assert all(b.startswith("LeftHand") for b in through.get("handle", {})), (sn, label)
    SHIELD_FIT[sn]["straps"] = info
    print("RIG_STRAPS", sn, info)

# --- Save ---------------------------------------------------------------------
rig["grip"] = {w: {"across_palm_at": round(g["U"], 4), "tilt_deg": g["tilt"], "slide": g["slide"],
                   "energy": round(g["E"], 2)} for w, g in GRIPS.items()}
rig["shield_fit"] = SHIELD_FIT
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
