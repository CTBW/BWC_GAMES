"""Review only: retarget the goblin spearman's Mixamo clips onto GoblinSpearmanRig, move the
spear and the left hand with them, keep the spear clear of the body, measure every frame and
save a scratch copy with the clips (Mixamo motion stays out of the repo).

  blender -b goblin_spear_rig.blend --python retarget_clips.py -- <animations dir> <out.blend> <measure.json> [clip,...]

Retarget as goblin_rabble/tools/retarget_clips.py (rest-pose difference, bone by bone, in
world space; the hips' motion scaled by the hip-height ratio), keying only the Mixamo body
bones: the fingers keep the grip Actions. The spear rides the right fist (the `Spear` bone);
the left hand holds the shaft through the rig's `support_ik`. Options per clip:
  in_place   remove the drift between the first and last frame (its speed is kept as the
             action's root_vel, m/s in Blender x and y)
  loop       the clip loops (its corrections are smoothed round the seam); where its last
             frame does not match its first, the last LOOP_FIX frames are eased into it
  loop_blend ease the last N frames back into the first pose (a loop)
  ground     lift the hips wherever the skinned body dips below the floor (the soles may
             sink FOOT_SINK), widened and averaged so the lift never pops
  sole       raise or lower the hips so the lowest point of the soles stays at its rest
             height, averaged over SOLE_W frames either side (round the seam of a loop)
  hold       the clip was made for empty hands: both arms, collarbones included, keep the
             standard pose (`stand`) on the clip's chest, so he holds the spear levelled.
             The right arm then turns at the shoulder by the carry: the least turn, the same in
             every frame of every hold clip, that keeps the shaft CLEAR off his body (his thighs
             come nearer it in the clips' bent-kneed stances than at rest, and a bend of the
             wrist alone cannot clear them) with the left hand's hold still in reach. It is
             stored on the rig (`carry_arm`) and is part of the standard pose the other clips
             start from
  range      (first, last) source frames to keep
  blend_in   N: start from the idle's first pose and ease into the clip over N frames
  blend_out  N: ease back into the idle's first pose over the last N frames (the game can cut
             between the idle and the clip without a jump). The body is blended before the
             spear is worked out, the arms and the left hand's hold after
  thrust     a two-handed spear thrust: in every frame the right wrist turns the spear onto
             the line from the right fist through the clip's left fist (the least turn). The
             left hand's hold slides along the shaft to that fist (SpearGrip.L's slide) and
             turns round it to the clip's turn of the hand, and the left elbow points as the
             clip's (ElbowPole.L); the slide, the turn and the pole are averaged over SMOOTH
             frames either side. The turn is the nearest that the left arm can reach (with
             REACH_PAD to spare); where none can, the hold slides back toward the right fist
             until one can. Then the shaft is kept CLEAR off the body in three steps:
             1. where the shaft behind the right fist (more than NEAR_FIST from it) comes
                nearer, the spear slides forward through the fist, the least slide up to
                GRIP_SLIDE that clears it, widened and averaged over SMOOTH frames either side
                and none where the clip blends with the idle; the left hand's hold slides back
                by as much, so the left fist stays put
             2. where it still comes nearer (the left forearm, which follows the shaft, and
                the right arm, which carries it, left out), the right arm turns at the
                shoulder: up to ARM_MAX degrees, ARM_STEP a frame at most, the left hand's
                hold sliding back up to HOLD_BACK toward the right fist where the turned shaft
                would be out of its reach
             3. where it still comes nearer (more than NEAR_FIST from the right fist, where
                bending the wrist cannot move it), the right wrist bends it clear: up to
                CLEAR_MAX degrees, CLEAR_STEP a frame at most
             Each turn runs from none CLEAR_PAD frames before a stretch to none CLEAR_PAD
             frames after it, the least turn over the stretch (as the spearman's wrist_clear)
  drop       a death: the arms start in the standard pose and ease into the clip over EASE
             frames, and the left hand lets go of the shaft over the frames LET_GO
             (`support_ik` eased to 0, the left grip opening to GRIP_DEAD). Where the spear
             in the right fist would go through the body, the right arm stays nearer the
             standard pose (the least that clears, widened and averaged). RELEASE_LEAD
             frames before the spear in the fist would touch the ground (or up to
             RELEASE_SEARCH frames earlier, the latest from which it falls clear of him) the
             fist opens to GRIP_DEAD and the spear falls as the archer's bow: it turns level,
             its blade flat, about its lowest point, which drops to the ground, in the time
             its middle would take to fall there. How far it is pushed from the body and
             turned about the vertical are the first that keep it clear of him in every
             later frame
Every clip keys the spear's bone, the left hand's hold, the elbow poles, `support_ik` and both
grips' influence in its first frame, so switching clips leaves nothing behind.
Per frame: body triangles that cut through the spear (the hands holding it left out), by the
bone weighing most on them, the least gap between the body and the spear (mm, the hands
holding it left out), the body's and the spear's lowest points, how far the left hand misses
its hold on the shaft (mm) and each wrist's bend from its forearm (degrees).
"""
import json
import math
import sys
import time
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

FOOT_Z = 0.08        # rest height below which vertices are the soles
FOOT_SINK = 0.01
SMOOTH = 3           # frames either side
SOLE_W = 1
LOOP_FIX = 6         # frames eased into the first where a loop's last frame does not match it
EASE = 12            # frames over which the death's arms leave the standard pose
LET_GO = (3, 9)      # frames over which the left hand lets go of the shaft in the death
RELEASE_LEAD = 4     # frames: the right fist lets go at least this long before the spear touches the ground
RELEASE_SEARCH = 12  # and at most this many frames earlier
RELEASE_EASE = 6     # frames over which the fist opens and the arm goes back to the clip
GRIP_DEAD = 0.4      # the grip's influence on an open hand
SPEAR_GROUND = 0.01  # the spear in the fist stays this far above the ground
SPEAR_REST = 0.002   # the dropped spear's lowest point lies this far above the ground
G = 9.81
CLEAR = 0.005        # m the shaft keeps off the body
CARRY_MAX = 20       # degrees the carry's turn of the right arm may reach
CLEAR_MAX = 24       # degrees the thrust's wrist may bend to clear the body
CLEAR_STEP = 6       # degrees per frame at most
CLEAR_PAD = 6        # frames
NEAR_FIST = 0.06     # m round the right fist that the wrist's bend cannot clear
REACH_PAD = 0.01     # m the left arm keeps short of full stretch
SLIDE_BACK = 0.15    # m the left hand's hold may slide back to be reached
GRIP_SLIDE = 0.24    # m the spear may slide forward through the right fist (which stays on the bare shaft)
ARM_MAX = 30         # degrees the thrust's right arm may turn at the shoulder to clear the body
ARM_STEP = 4         # degrees per frame at most
HOLD_BACK = 0.10     # m the left hand's hold may slide back for reach as the right arm turns
CLIPS = {
    "idle": ("Idle - Goblin.fbx", {"in_place": True, "loop_blend": 10, "hold": True}),
    "walk": ("Walk - Spearmen.fbx", {"in_place": True, "loop": True, "sole": True, "hold": True}),
    # The thrust and its recovery; the source holds its upright guard to frame 99.
    "attack": ("Attack - Goblin Spearmen.fbx", {"range": (1, 64), "blend_in": 8, "blend_out": 12,
                                                "thrust": True, "sole": True}),
    "death": ("Death - Goblin.fbx", {"blend_in": 8, "ground": True, "drop": True}),
}
HOLD = [c for c, (_, o) in CLIPS.items() if o.get("hold")]

argv = sys.argv[sys.argv.index("--") + 1:]
anim_dir, out_blend, out_json = Path(argv[0]), Path(argv[1]), Path(argv[2])
ONLY = argv[3].split(",") if len(argv) > 3 and argv[3] else list(CLIPS)
sc = bpy.context.scene
sc.render.fps = 30
rig = bpy.data.objects["GoblinSpearmanRig"]
body = bpy.data.objects["GoblinSpearman"]
spear = bpy.data.objects["Spear"]
me = body.data
PB, RB = rig.pose.bones, rig.data.bones
MX = "mixamorig:"
FING = ("Thumb", "Index", "Middle", "Ring", "Pinky")
keyed = {b.name for b in RB if b.name.startswith(MX) and not any(f in b.name for f in FING)}
order = []


def visit(b):
    if b.name in keyed:
        order.append(b.name)
    for c in b.children:
        visit(c)


visit(RB[MX + "Hips"])
assert set(order) == keyed, keyed - set(order)
assert rig.matrix_world == Matrix.Identity(4)
T_rest = {n: (rig.matrix_world.to_3x3() @ RB[n].matrix_local.to_3x3()).normalized() for n in order}
T_hips = rig.matrix_world @ RB[MX + "Hips"].head_local
ARM = [MX + s + p for s in ("Left", "Right") for p in ("Shoulder", "Arm", "ForeArm", "Hand")]
RIGHT = [MX + "Right" + p for p in ("Shoulder", "Arm", "ForeArm", "Hand")]
GRIPS = {s: [c for pb in PB for c in pb.constraints if c.type == "ACTION" and c.name == "grip_spear_" + s]
         for s in ("r", "l")}
assert all(len(v) == 15 for v in GRIPS.values()), {k: len(v) for k, v in GRIPS.items()}
assert rig["spear_ik"] == 0 and rig["leg_ik"] == 0 and rig["support_ik"] == 1

# The standard pose: the arms' and the controls' keys in `stand`.
STAND = bpy.data.actions["stand"]
rig.animation_data.action = STAND
if len(STAND.slots):
    rig.animation_data.action_slot = STAND.slots[0]
sc.frame_set(1)
STAND_Q = {n: PB[n].rotation_quaternion.copy() for n in ARM}
STAND_Q0 = {n: q.copy() for n, q in STAND_Q.items()}     # before the carry
CTRL =("SpearCtrl", "ElbowPole.L", "ElbowPole.R")
STAND_C = {n: (PB[n].location.copy(), PB[n].rotation_quaternion.copy()) for n in CTRL}
STAND_SG = (PB["SpearGrip.L"].location.copy(), PB["SpearGrip.L"].rotation_euler.copy())
print("CLIPS_STAND left hold: slide %.3f m, turn %.1f deg" % (STAND_SG[0].y, math.degrees(STAND_SG[1].y)))
rig.animation_data.action = None
for pb in PB:
    pb.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()

me.calc_loop_triangles()
TRI = np.array([t.vertices[:] for t in me.loop_triangles])
gname = {g.index: g.name.replace(MX, "") for g in body.vertex_groups}
DOM = []
for v in me.vertices:
    g = max(v.groups, key=lambda g: g.weight, default=None)
    DOM.append(gname[g.group] if g else "-")
DOM = np.array(DOM)
TRI_BONE = DOM[TRI[:, 0]]
HAND = {s: np.array([b.startswith(s + "Hand") for b in TRI_BONE]) for s in ("Right", "Left")}
NONE = np.zeros(len(TRI), bool)
VHAND = {s: np.array([b.startswith(s + "Hand") for b in DOM]) for s in ("Right", "Left")}
VNONE = np.zeros(len(DOM), bool)
VLARM = np.array([b.startswith("LeftForeArm") or b.startswith("LeftHand") for b in DOM])
# Each vertex's share of the right arm (RightArm and the bones below it; the armature
# normalises the weights).
_vg = {g.index: g.name for g in body.vertex_groups}
_arm = {b.name for b in RB[MX + "RightArm"].children_recursive} | {MX + "RightArm"}
W_ARM = np.zeros(len(me.vertices))
for v in me.vertices:
    ws = [(g.weight, _vg[g.group]) for g in v.groups if _vg[g.group] in RB and RB[_vg[g.group]].use_deform]
    tot = sum(w for w, _ in ws)
    if tot > 0:
        W_ARM[v.index] = sum(w for w, n in ws if n in _arm) / tot
rest_z = np.array([v.co.z for v in me.vertices])
floor = np.where(rest_z < FOOT_Z, -FOOT_SINK, 0.0)
SOLE = rest_z < FOOT_Z

# The spear: its vertices and faces in its own space (the shaft on z, the head up).
SP_V = np.array([v.co[:] for v in spear.data.vertices])
SP_F = [list(p.vertices) for p in spear.data.polygons]
SP_BVH = BVHTree.FromPolygons([Vector(v) for v in SP_V], SP_F)
SP_Z = (float(SP_V[:, 2].min()), float(SP_V[:, 2].max()))
SP_R = float(np.hypot(SP_V[:, 0], SP_V[:, 1]).max())
# Its radius along its length, in PROF_BIN steps (between its rings, interpolated), each step
# the widest of it and its neighbours.
PROF_BIN = 0.01
_nb = int(math.ceil((SP_Z[1] - SP_Z[0]) / PROF_BIN)) + 1
_bi = np.clip(((SP_V[:, 2] - SP_Z[0]) / PROF_BIN).astype(int), 0, _nb - 1)
_pr = np.full(_nb, -1.0)
np.maximum.at(_pr, _bi, np.hypot(SP_V[:, 0], SP_V[:, 1]))
_has = np.where(_pr >= 0)[0]
_pr = np.interp(np.arange(_nb), _has, _pr[_has])
PROF = np.maximum(_pr, np.maximum(np.r_[_pr[:1], _pr[:-1]], np.r_[_pr[1:], _pr[-1:]]))
K_SPEAR =Matrix.Translation((0, PB["Spear"].bone.length, 0)) @ spear.matrix_parent_inverse @ spear.matrix_basis
assert spear.parent_bone == "Spear"
assert (K_SPEAR.to_3x3() @ Vector((0, 0, 1)) - Vector((0, 1, 0))).length < 1e-6     # the shaft on the bone's y
Z_FIST = -K_SPEAR.translation.y     # the right fist's place on the shaft (the Spear bone's head)
# The left fist's point on the shaft in the left hand's frame (the hold's head in HandIK.L's
# rest), the fists' distance at rest, and the chains Spear -> SpearGrip.L -> HandIK.L and
# RightHand -> Spear in rest space.
OFF_L = RB["HandIK.L"].matrix_local.inverted() @ RB["SpearGrip.L"].head_local
D0 = (RB["SpearGrip.L"].head_local - RB["Spear"].head_local).length
REL_S_SG = RB["Spear"].matrix_local.inverted() @ RB["SpearGrip.L"].matrix_local
REL_SG_HIK = RB["SpearGrip.L"].matrix_local.inverted() @ RB["HandIK.L"].matrix_local
REL_H_S = RB[MX + "RightHand"].matrix_local.inverted() @ RB["Spear"].matrix_local
REACH_L = RB[MX + "LeftArm"].length + RB[MX + "LeftForeArm"].length
assert abs((RB["SpearGrip.L"].matrix_local.col[1].xyz - RB["Spear"].matrix_local.col[1].xyz).length) < 1e-4
print("CLIPS_MESH body %d vertices, %d triangles; spear %d faces, z %.3f to %.3f, reach %.3f off its axis; fists %.3f m apart"
      % (len(me.vertices), len(TRI), len(SP_F), SP_Z[0], SP_Z[1], SP_R, D0))
for pb in PB:
    if pb.name != "SpearGrip.L":
        pb.rotation_mode = "QUATERNION"


def evaluated():
    ev = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    m = ev.to_mesh()
    co = np.empty(len(m.vertices) * 3)
    m.vertices.foreach_get("co", co)
    ev.to_mesh_clear()
    return co.reshape(-1, 3) @ np.array(body.matrix_world.to_3x3()).T + np.array(body.matrix_world.translation)


def spear_world():
    return rig.matrix_world @ PB["Spear"].matrix @ K_SPEAR


def spear_pts(M):
    Mn = np.array(M)
    return SP_V @ Mn[:3, :3].T + Mn[:3, 3]


def spear_cuts(P, M, skip):
    """Body triangles (not in `skip`) through the spear at world matrix M, counted near its
    shaft only (a capsule round it)."""
    Mn = np.array(M)
    a = Mn[:3, :3] @ np.array([0, 0, SP_Z[0]]) + Mn[:3, 3]
    ab = Mn[:3, :3] @ np.array([0, 0, SP_Z[1] - SP_Z[0]])
    t = np.clip((P - a) @ ab / (ab @ ab), 0, 1)
    near = np.linalg.norm(P - (a + t[:, None] * ab), axis=1) < SP_R + 0.03
    tm = near[TRI].any(1) & ~skip
    if not tm.any():
        return {}
    sub = TRI[tm]
    idx = np.unique(sub)
    remap = np.full(len(P), -1)
    remap[idx] = np.arange(len(idx))
    Mi = np.linalg.inv(Mn)
    bt = BVHTree.FromPolygons((P[idx] @ Mi[:3, :3].T + Mi[:3, 3]).tolist(), remap[sub].tolist())
    hit = {a_ for a_, _ in bt.overlap(SP_BVH)} | {a_ for _, a_ in SP_BVH.overlap(bt)}
    bones = TRI_BONE[tm]
    by = {}
    for i in hit:
        by[str(bones[i])] = by.get(str(bones[i]), 0) + 1
    return by


def gap(P, M, skip_v, near=None, who=False):
    """The least gap (m) between the body's vertices (not in skip_v, nor within NEAR_FIST of
    `near`) and the spear at world matrix M, square to its axis at each vertex's place along it
    (negative inside it); with who, also the bone weighing most on the nearest vertex."""
    Mi = np.linalg.inv(np.array(M))
    L = P @ Mi[:3, :3].T + Mi[:3, 3]
    z = L[:, 2]
    m = (z > SP_Z[0] - CLEAR) & (z < SP_Z[1] + CLEAR) & ~skip_v
    if near is not None:
        m &= np.linalg.norm(P - np.array(near), axis=1) > NEAR_FIST
    if not m.any():
        return (1.0, "-") if who else 1.0
    i = np.where(m)[0]
    e = np.hypot(L[i, 0], L[i, 1]) - PROF[np.clip(((z[i] - SP_Z[0]) / PROF_BIN).astype(int), 0, len(PROF) - 1)]
    t = np.maximum(np.maximum(SP_Z[0] - z[i], z[i] - SP_Z[1]), 0.0)     # past either end
    g = np.where(t > 0, np.hypot(np.maximum(e, 0.0), t), e)
    k = int(np.argmin(g))
    return (float(g[k]), str(DOM[i[k]])) if who else float(g[k])


def facing():
    """His facing on the ground, square to the hip line (his right is -x at rest, he faces -y)."""
    r = PB[MX + "RightUpLeg"].head - PB[MX + "LeftUpLeg"].head
    return Vector((0, 0, 1)).cross(Vector((r.x, r.y, 0))).normalized()


def wrist_bend(side):
    f = PB[MX + side + "ForeArm"].matrix.to_3x3().col[1]
    return math.degrees(f.angle(PB[MX + side + "Hand"].matrix.to_3x3().col[1]))


def widen(vals, cyclic, r=SMOOTH):
    """A loop's last frame repeats its first: it wraps over the others and copies the first."""
    n = len(vals)
    m = n - 1 if cyclic else n
    at = (lambda i: vals[i % m]) if cyclic else (lambda i: vals[min(max(i, 0), n - 1)])
    wide = [max(at(j) for j in range(i - r, i + r + 1)) for i in range(m)]
    at = (lambda i: wide[i % m]) if cyclic else (lambda i: wide[min(max(i, 0), n - 1)])
    out = [sum(at(j) for j in range(i - r, i + r + 1)) / (2 * r + 1) for i in range(m)]
    return out + out[:1] if cyclic else out


def average(vals, r=SMOOTH):
    n = len(vals)
    return [sum(vals[min(max(j, 0), n - 1)] for j in range(i - r, i + r + 1)) / (2 * r + 1) for i in range(n)]


def smoothstep(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def key_controls(f, sg=None, pole_l=None):
    """The spear's bone at rest in the fist, the left hand's hold and the poles as `stand`
    has them (or as given), keyed at frame f."""
    for n in CTRL:
        PB[n].location, PB[n].rotation_quaternion = STAND_C[n]
        if n == "ElbowPole.L" and pole_l is not None:
            PB[n].location = pole_l
        PB[n].keyframe_insert("location", frame=f)
        PB[n].keyframe_insert("rotation_quaternion", frame=f)
    g = PB["SpearGrip.L"]
    g.location, g.rotation_euler = sg if sg is not None else STAND_SG
    g.keyframe_insert("location", frame=f)
    g.keyframe_insert("rotation_euler", frame=f)


def key_spear_rest(f):
    s = PB["Spear"]
    s.matrix_basis = Matrix.Identity(4)
    s.keyframe_insert("location", frame=f)
    s.keyframe_insert("rotation_quaternion", frame=f)


def key_support(f, v):
    rig["support_ik"] = v
    rig.keyframe_insert('["support_ik"]', frame=f)


def key_grip(side, f, v):
    for c in GRIPS[side]:
        c.influence = v
        c.keyframe_insert("influence", frame=f)


def ground_lift(n):
    need = []
    for f in range(1, n + 1):
        sc.frame_set(f)
        need.append(max(0.0, float(np.max(floor - evaluated()[:, 2]))))
    wide = [max(need[max(0, i - 2):i + 3]) for i in range(n)]
    return [sum(wide[max(0, i - 2):i + 3]) / len(wide[max(0, i - 2):i + 3]) for i in range(n)]


def sole_follow(n, cyclic):
    """Per frame, the hips' rise that puts the lowest sole point at its rest height."""
    rest = float(rest_z[SOLE].min())
    need = []
    for f in range(1, n + 1):
        sc.frame_set(f)
        need.append(rest - float(evaluated()[SOLE, 2].min()))
    m = n - 1 if cyclic else n      # a loop's last frame repeats its first
    at = (lambda i: need[i % m]) if cyclic else (lambda i: need[min(max(i, 0), n - 1)])
    out = [sum(at(j) for j in range(i - SOLE_W, i + SOLE_W + 1)) / (2 * SOLE_W + 1) for i in range(m)]
    return out + out[:1] if cyclic else out


# --- The thrust ----------------------------------------------------------------------------

def hold_at(S, slide, phi):
    """HandIK.L's pose matrix with the hold slid and turned so, the spear's bone at S."""
    return S @ REL_S_SG @ Matrix.Translation((0, slide, 0)) @ Matrix.Rotation(phi, 4, "Y") @ REL_SG_HIK


def thrust(clip, n):
    """Turn the right wrist so the spear runs through the clip's left fist; slide and turn the
    left hand's hold there and point its elbow as the clip's (support_ik off while reading the
    clip's left arm)."""
    key_support(1, 0.0)
    hand = PB[MX + "RightHand"]
    turned, slides, phis, poles, backs, ahead = [], [], [], [], [], 0
    prev_q, prev_phi = None, None
    for f in range(1, n + 1):
        sc.frame_set(f)
        HL = PB[MX + "LeftHand"].matrix.copy()
        qL = HL @ OFF_L
        H0 = hand.matrix.copy()
        H = H0.copy()
        for _ in range(6):
            S = H @ REL_H_S
            p, a = S.translation, S.col[1].xyz.normalized()
            R = a.rotation_difference((qL - p).normalized()).to_matrix().to_4x4()
            H = Matrix.Translation(H.translation) @ R @ Matrix.Translation(-H.translation) @ H
        S = H @ REL_H_S
        p, d = S.translation, S.col[1].xyz.normalized()
        ahead += (qL - p).dot(facing()) > 0
        turned.append(math.degrees(H0.to_quaternion().rotation_difference(H.to_quaternion()).angle))
        hand.matrix = H
        hand.location, hand.scale = (0, 0, 0), (1, 1, 1)
        q = hand.rotation_quaternion.copy()
        if prev_q is not None:
            q.make_compatible(prev_q)
        hand.rotation_quaternion = prev_q = q
        hand.keyframe_insert("rotation_quaternion", frame=f)
        slide = (qL - p).dot(d) - D0
        # The hold's turn round the shaft nearest the clip's turn of the hand, of those the left
        # arm reaches; where it reaches none, the hold slides back toward the right fist.
        qHL = HL.to_quaternion()
        sh = PB[MX + "LeftArm"].head.copy()

        def turns(sl, angles):
            out = []
            for a_ in angles:
                Mh = hold_at(S, sl, math.radians(a_))
                if (Mh.translation - sh).length <= REACH_L - REACH_PAD:
                    out.append((qHL.rotation_difference(Mh.to_quaternion()).angle, a_))
            return out

        best = None
        for back in np.arange(0.0, SLIDE_BACK + 1e-9, 0.01):
            near = turns(slide - back, range(0, 360, 3))
            if near:
                a0 = min(near)[1]
                best = min(turns(slide - back, np.arange(a0 - 3, a0 + 3.01, 0.25)) or near)[1]
                slide -= back
                backs.append(back)
                break
        if best is None:        # out of reach even slid back: the nearest the hand comes
            slide -= SLIDE_BACK
            backs.append(SLIDE_BACK)
            best = min(((hold_at(S, slide, math.radians(a_)).translation - sh).length, a_) for a_ in range(0, 360, 3))[1]
        phi = math.radians(best)
        if prev_phi is not None:
            phi += 2 * math.pi * round((prev_phi - phi) / (2 * math.pi))
        phis.append(phi)
        prev_phi = phi
        slides.append(slide)
        # The left elbow's pole: out from the clip's elbow, square to the shoulder-wrist line.
        Sh, E, W = PB[MX + "LeftArm"].head, PB[MX + "LeftForeArm"].head, HL.translation
        u = (W - Sh).normalized()
        v = (E - Sh) - u * (E - Sh).dot(u)
        poles.append(E + 0.3 * v.normalized() if v.length > 1e-3 else (poles[-1] if poles else E))
    slides, phis = average(slides), average(phis)
    poles = [Vector(c) for c in zip(*[average([p[i] for p in poles]) for i in range(3)])]
    for f in range(1, n + 1):
        sc.frame_set(f)
        pp = PB["ElbowPole.L"]
        M = pp.matrix.copy()
        M.translation = poles[f - 1]
        pp.matrix = M
        bpy.context.view_layer.update()
        key_controls(f, (Vector((0, slides[f - 1], 0)), Vector((0, phis[f - 1], 0))), pp.location.copy())
    key_support(1, 1.0)
    print("CLIP_THRUST %s: right wrist turned %.0f to %.0f deg (median %.0f) to lay the spear through the left fist;"
          " the left fist ahead of the right in %d of %d frames; slide %.3f to %.3f m, hold turn %.0f to %.0f deg;"
          " hold slid back for reach in %d frames, up to %.2f m"
          % (clip, min(turned), max(turned), float(np.median(turned)), ahead, n, min(slides), max(slides),
             math.degrees(min(phis)), math.degrees(max(phis)), sum(1 for b in backs if b > 0), max(backs)))
    return {"wrist_turn_deg": [round(t, 1) for t in turned], "slide": [round(s, 4) for s in slides],
            "hold_turn_deg": [round(math.degrees(p), 1) for p in phis], "slid_back": [round(b, 3) for b in backs]}


# --- The carry, the blends and the wrist's clearance -----------------------------------------

DIRS = [Vector((math.cos(a), 0, math.sin(a))) for a in (math.radians(30 * k) for k in range(12))]


def bend(k, a):
    """A bend of a bone (the right wrist or arm): a degrees about DIRS[k] (square to its length)."""
    return Matrix.Rotation(math.radians(a), 4, DIRS[k]) if a else Matrix.Identity(4)


def set_action(name):
    act = bpy.data.actions[name]
    rig.animation_data.action = act
    rig.animation_data.action_slot = act.slots[0]
    return act


def set_carry(recompute):
    """The carry (see the module's `hold`): the right arm's turn at the shoulder, found from
    every frame of the hold clips and keyed into them, or read from the rig; either way part of
    STAND_Q from now on. The search moves the skin with the arm by each vertex's share of it
    (as linear blend skinning does); measure() then checks the real one."""
    arm = PB[MX + "RightArm"]
    if recompute:
        t0 = time.time()
        frames = []
        for c in HOLD:
            act = set_action(c)
            for f in range(1, int(act["frames"]) + 1):
                sc.frame_set(f)
                arm.rotation_quaternion = STAND_Q0[arm.name]
                bpy.context.view_layer.update()
                g = PB["SpearGrip.L"]
                frames.append((c, f, evaluated(), PB[MX + "RightHand"].matrix.copy(), arm.matrix.copy(),
                               PB[MX + "LeftArm"].head.copy(), g.location.y, g.rotation_euler.y))

        def margin(fr, D):
            _, _, P, H, A, sh, sl, ph = fr
            R = A @ D @ A.inverted()            # the turn at the shoulder in the rig's space
            S = R @ H @ REL_H_S
            if (hold_at(S, sl, ph).translation - sh).length > REACH_L - REACH_PAD:
                return -1.0
            Rn = np.array(R)
            Pn = P + W_ARM[:, None] * (P @ Rn[:3, :3].T + Rn[:3, 3] - P)
            return gap(Pn, S @ K_SPEAR, VHAND["Right"] | VHAND["Left"])

        base = [(gap(fr[2], fr[3] @ REL_H_S @ K_SPEAR, VHAND["Right"] | VHAND["Left"], who=True), fr[0], fr[1])
                for fr in frames]
        worst = min(base)
        print("CLIP_CARRY before: least gap %.1f mm (%s, %s frame %d); %d of %d frames nearer than %.0f mm"
              % (worst[0][0] * 1000, worst[0][1], worst[1], worst[2], sum(1 for b in base if b[0][0] < CLEAR),
                 len(frames), CLEAR * 1000))
        frames = [fr for _, fr in sorted(zip([b[0][0] for b in base], frames), key=lambda t: t[0])]
        found = None
        for a in range(0, CARRY_MAX + 1):
            ok = []
            for k in (range(12) if a else [0]):
                D = bend(k, a)
                m = 1.0
                for fr in frames:
                    m = min(m, margin(fr, D))
                    if m < CLEAR:
                        break
                if m >= CLEAR:
                    ok.append((m, k))
            if ok:
                found = (a, max(ok)[1], max(ok)[0])
                break
        assert found is not None, "no turn of the right arm up to %d deg clears the hold clips" % CARRY_MAX
        a, k, m = found
        rig["carry_arm"] = [k, a]
        ax = (frames[0][4].to_3x3() @ DIRS[k]).normalized()
        print("CLIP_CARRY right arm turned %d deg at the shoulder about %d deg (rig axis %.2f %.2f %.2f in the"
              " worst frame): least gap %.1f mm over %d frames (%.0f s)"
              % (a, 30 * k, *ax, m * 1000, len(frames), time.time() - t0))
    k, a = (int(v) for v in rig["carry_arm"])
    q = STAND_Q0[arm.name] @ bend(k, a).to_quaternion()
    STAND_Q[arm.name] = q
    if recompute:
        for c in HOLD:
            act = set_action(c)
            for f in range(1, int(act["frames"]) + 1):
                arm.rotation_quaternion = q
                arm.keyframe_insert("rotation_quaternion", frame=f)
    return {"dir_deg": 30 * k, "deg": a}


def first_pose(name):
    """The body bones' turns and the hips' offset in the first frame of an action."""
    set_action(name)
    sc.frame_set(1)
    hb = PB[MX + "Hips"]
    return {n: PB[n].rotation_quaternion.copy() for n in order}, T_rest[MX + "Hips"] @ hb.location


def blend_weights(n, opt):
    bi, bo = opt.get("blend_in", 0), opt.get("blend_out", 0)
    return [max(1 - smoothstep(i / bi) if bi else 0.0, smoothstep((i - (n - 1 - bo)) / bo) if bo else 0.0)
            for i in range(n)]


def blend_arms(n, wts, q0):
    """Ease the arms, the left hand's hold and its elbow's pole into the idle's first pose."""
    g, pole = PB["SpearGrip.L"], PB["ElbowPole.L"]
    for i, w in enumerate(wts):
        if w <= 0:
            continue
        f = i + 1
        sc.frame_set(f)
        for nm in ARM:
            a, b = PB[nm].rotation_quaternion.copy(), q0[nm].copy()
            b.make_compatible(a)
            PB[nm].rotation_quaternion = a.slerp(b, w)
            PB[nm].keyframe_insert("rotation_quaternion", frame=f)
        phi = g.rotation_euler.y
        phi0 = STAND_SG[1].y + 2 * math.pi * round((phi - STAND_SG[1].y) / (2 * math.pi))
        g.location = g.location.lerp(STAND_SG[0], w)
        g.rotation_euler = (STAND_SG[1].x, phi + (phi0 - phi) * w, STAND_SG[1].z)
        g.keyframe_insert("location", frame=f)
        g.keyframe_insert("rotation_euler", frame=f)
        pole.location = pole.location.lerp(STAND_C["ElbowPole.L"][0], w)
        pole.keyframe_insert("location", frame=f)


def turn_states(top, step):
    """No turn, then a turn about each of DIRS by 2, 4, ... top degrees; each one's 2D vector
    and the states within `step` degrees of it."""
    states = [(0, 0)] + [(k, a) for k in range(12) for a in range(2, top + 1, 2)]
    vec = [Vector((math.cos(math.radians(30 * k)), math.sin(math.radians(30 * k)))) * a for k, a in states]
    near = [[(j, (vec[i] - vec[j]).length_squared) for j in range(len(states))
             if (vec[i] - vec[j]).length <= step + 1e-6] for i in range(len(states))]
    return states, vec, near


def clear_pass(n, tester, top, step):
    """Where tester(f)(no turn) fails, the least-turn path of states (turn_states(top, step))
    from no turn CLEAR_PAD frames before each stretch to no turn CLEAR_PAD frames after it,
    every frame cleared (Viterbi). tester(f)(D) is None where the turn D fails, else a value
    kept for that frame. Returns [(frame, state, value)] for the turned frames, the stretches as
    (first, last, largest turn) and, where none clears, (first, last, frames none clears)."""
    states, vec, near = turn_states(top, step)
    rot = [bend(k, a) for k, a in states]
    bad = [f for f in range(1, n + 1) if tester(f)(Matrix.Identity(4)) is None]
    groups = []
    for f in bad:
        if groups and f - groups[-1][-1] <= 2 * CLEAR_PAD:
            groups[-1].append(f)
        else:
            groups.append([f])
    turned, out, left = [], [], []
    for grp in groups:
        span = list(range(max(1, grp[0] - CLEAR_PAD), min(n, grp[-1] + CLEAR_PAD) + 1))
        val = {}
        for f in span:
            clear = tester(f)
            val[f] = [clear(R) for R in rot]
        cost = [0.0] + [math.inf] * (len(states) - 1)
        back = []
        for f in span:
            cur, arg = [math.inf] * len(states), [0] * len(states)
            for i in range(len(states)):
                if val[f][i] is not None:
                    for j, d2 in near[i]:
                        c = cost[j] + d2 + 0.2 * vec[i].length_squared
                        if c < cur[i]:
                            cur[i], arg[i] = c, j
            back.append(arg)
            cost = cur
        end = min((i for i in range(len(states)) if vec[i].length <= step + 1e-6),
                  key=lambda i: cost[i] + vec[i].length_squared)
        if cost[end] == math.inf:
            left.append((grp[0], grp[-1], [f for f in span if all(v is None for v in val[f])]))
            continue
        path, i = [], end
        for arg in reversed(back):
            path.append(i)
            i = arg[i]
        path.reverse()
        turned += [(f, states[i], val[f][i]) for f, i in zip(span, path) if i]
        out.append((span[0], span[-1], max(states[i][1] for i in path)))
    return turned, out, left


def grip_slide(clip, n, wts):
    """Step 1 of the thrust's clearance (see the module's `thrust`)."""
    sp_b, g = PB["Spear"], PB["SpearGrip.L"]
    need = []
    for f in range(1, n + 1):
        sc.frame_set(f)
        P, S = evaluated(), sp_b.matrix.copy()
        Mi = np.linalg.inv(np.array(S @ K_SPEAR))
        z = (P @ Mi[:3, :3].T + Mi[:3, 3])[:, 2]
        skip = vskip(f, False) | (z > Z_FIST - NEAR_FIST)
        best = (-1.0, 0.0)
        for sl in np.arange(0.0, GRIP_SLIDE + 1e-9, 0.01):
            m = gap(P, S @ Matrix.Translation((0, sl, 0)) @ K_SPEAR, skip)
            if m >= CLEAR:
                best = (m, sl)
                break
            best = max(best, (m, sl))
        need.append(float(best[1]))
    slide = [min(GRIP_SLIDE, v * (1 - (wts[i] if wts else 0.0))) for i, v in enumerate(widen(need, False))]
    for f in range(1, n + 1):
        sc.frame_set(f)
        sp_b.location = (0, slide[f - 1], 0)
        sp_b.keyframe_insert("location", frame=f)
        g.location.y -= slide[f - 1]
        g.keyframe_insert("location", frame=f)
    moved = [f for f in range(1, n + 1) if slide[f - 1] > 0.001]
    print("CLIP_SLIDE %s: the spear slides forward through the right fist in frames %s, up to %.3f m (frame %d)"
          % (clip, [moved[0], moved[-1]] if moved else [], max(slide), 1 + int(np.argmax(slide))))
    return {"grip_slide": [round(v, 4) for v in slide]}


def arm_clear(clip, n):
    """Step 2 of the thrust's clearance (see the module's `thrust`)."""
    arm, g = PB[MX + "RightArm"], PB["SpearGrip.L"]
    backs = np.arange(0.0, HOLD_BACK + 1e-9, 0.01)

    def tester(f):
        sc.frame_set(f)
        P, A, Sp = evaluated(), arm.matrix.copy(), PB["Spear"].matrix.copy()
        sl, ph, sh = g.location.y, g.rotation_euler.y, PB[MX + "LeftArm"].head.copy()
        skip = vskip(f, False) | VLARM | (W_ARM > 0.5)
        far = max(REACH_L - REACH_PAD, (hold_at(Sp, sl, ph).translation - sh).length)

        def clear(D):
            R = A @ D @ A.inverted()            # the turn at the shoulder in the rig's space
            S = R @ Sp
            b = next((float(b) for b in backs if (hold_at(S, sl - b, ph).translation - sh).length <= far + 1e-6), None)
            if b is None:
                return None
            Rn = np.array(R)
            Pn = P + W_ARM[:, None] * (P @ Rn[:3, :3].T + Rn[:3, 3] - P)
            return b if gap(Pn, S @ K_SPEAR, skip) >= CLEAR else None
        return clear

    turned, out, left = clear_pass(n, tester, ARM_MAX, ARM_STEP)
    back = [0.0] * n
    for f, (k, a), b in turned:
        sc.frame_set(f)
        arm.rotation_quaternion = arm.rotation_quaternion @ Quaternion(DIRS[k], math.radians(a))
        arm.keyframe_insert("rotation_quaternion", frame=f)
        back[f - 1] = b
    back = widen(back, False) if any(back) else back
    for f in range(1, n + 1):
        if back[f - 1] > 0:
            sc.frame_set(f)
            g.location.y -= back[f - 1]
            g.keyframe_insert("location", frame=f)
    print("CLIP_ARM %s: right arm turned at the shoulder in %s (first, last frame, largest turn deg), the left"
          " hold slid back up to %.3f m; not cleared %s" % (clip, out, max(back), left))
    return {"turned": out, "not_cleared": left, "hold_back": [round(v, 4) for v in back]}


def wrist_clear(clip, n):
    """Step 3 of the thrust's clearance (see the module's `thrust`)."""
    hand = PB[MX + "RightHand"]

    def tester(f):
        sc.frame_set(f)
        P, H, Sb = evaluated(), hand.matrix.copy(), PB["Spear"].matrix_basis.copy()
        g = PB["SpearGrip.L"]
        sl, ph, sh = g.location.y, g.rotation_euler.y, PB[MX + "LeftArm"].head.copy()
        skip = vskip(f, False)
        far = max(REACH_L - REACH_PAD, (hold_at(H @ REL_H_S @ Sb, sl, ph).translation - sh).length)

        def clear(B):
            S = H @ B @ REL_H_S @ Sb
            ok = ((hold_at(S, sl, ph).translation - sh).length <= far + 1e-6
                  and gap(P, S @ K_SPEAR, skip, near=(H @ B @ REL_H_S).translation) >= CLEAR)
            return True if ok else None
        return clear

    turned, out, left = clear_pass(n, tester, CLEAR_MAX, CLEAR_STEP)
    for f, (k, a), _ in turned:
        sc.frame_set(f)
        hand.rotation_quaternion = hand.rotation_quaternion @ Quaternion(DIRS[k], math.radians(a))
        hand.keyframe_insert("rotation_quaternion", frame=f)
    print("CLIP_CLEAR %s: right wrist bent in %s (first, last frame, largest bend deg); not cleared %s"
          % (clip, out, left))
    return {"bent": out, "not_cleared": left}


# --- The death -----------------------------------------------------------------------------

RELEASE = None


def support(f, drop):
    if not drop:
        return 1.0
    return 1.0 - smoothstep((f - LET_GO[0]) / (LET_GO[1] - LET_GO[0]))


def skip_mask(f, drop):
    m = HAND["Right"].copy() if (RELEASE is None or f <= RELEASE + RELEASE_EASE) else NONE.copy()
    if support(f, drop) > 0:
        m |= HAND["Left"]
    return m


def vskip(f, drop):
    """skip_mask's hands, by vertex."""
    m = VHAND["Right"].copy() if (RELEASE is None or f <= RELEASE + RELEASE_EASE) else VNONE.copy()
    if support(f, drop) > 0:
        m |= VHAND["Left"]
    return m


def set_right(clipq, stq, w):
    for nm in RIGHT:
        q, s = clipq[nm].copy(), stq[nm].copy()
        s.make_compatible(q)
        PB[nm].rotation_quaternion = q.slerp(s, w)
    bpy.context.view_layer.update()


def find_release(n):
    for f in range(1, n + 1):
        sc.frame_set(f)
        if float(spear_pts(spear_world())[:, 2].min()) < SPEAR_GROUND:
            return max(2, f - RELEASE_LEAD)
    return None


def right_clear(clip, n, clipq, base_w):
    """The least extra pull of the right arm toward the standard pose that keeps the spear in
    the fist out of the body, per frame; widened and averaged."""
    t0, evals, extra = time.time(), 0, []
    for f in range(1, n + 1):
        sc.frame_set(f)
        w0 = base_w[f - 1]
        best = None
        for w in [w0] + [x / 10 for x in range(11) if x / 10 > w0 + 1e-6]:
            set_right(clipq[f - 1], STAND_Q, w)
            k = sum(spear_cuts(evaluated(), spear_world(), skip_mask(f, True)).values())
            evals += 1
            if best is None or k < best[0]:
                best = (k, w)
            if k == 0:
                break
        extra.append(best[1] - w0)
        if best[0]:
            print("CLIP_FIX %s frame %d: still %d triangles through the spear at the standard pose" % (clip, f, best[0]))
    sm = widen(extra, False)
    print("CLIP_FIX %s right arm: pulled toward the standard pose in %d of %d frames, up to %.2f; %d evaluations in %.0f s"
          % (clip, sum(1 for e in extra if e > 0), n, max(sm), evals, time.time() - t0))
    return sm


def fall(n):
    """The spear's fall from RELEASE (see the module's `drop`). Returns (body triangles through
    it, its description, its world matrix per frame)."""
    sc.frame_set(RELEASE - 1)
    o_prev = spear_world().translation.copy()
    sc.frame_set(RELEASE)
    M0 = spear_world()
    P0 = spear_pts(M0)
    low = Vector(P0[np.argmin(P0[:, 2])].tolist())
    vel = M0.translation - o_prev
    vel.z = 0.0
    a = M0.col[2].xyz.normalized()
    a_h = Vector((a.x, a.y, 0))
    a_h = a_h.normalized() if a_h.length > 0.2 else facing()
    R1 = a.rotation_difference(a_h)
    x1 = R1 @ M0.col[0].xyz.normalized()
    e1 = Vector((0, 0, 1)).cross(a_h).normalized()
    th = math.atan2(x1.dot(a_h.cross(e1)), x1.dot(e1))
    if th > math.pi / 2:
        th -= math.pi
    elif th < -math.pi / 2:
        th += math.pi
    TURN = Quaternion(a_h, -th) @ R1
    mid = float((P0[:, 2].min() + P0[:, 2].max()) / 2)
    T = max(3, math.ceil(30 * math.sqrt(2 * mid / G)))
    frames = range(RELEASE + 1, n + 1)
    bodies = {}
    for f in frames:
        sc.frame_set(f)
        bodies[f] = evaluated()

    def world(t, extra, spin):
        s = min(1.0, (t / T) ** 2)
        R = Matrix.Rotation(math.radians(spin) * s, 4, "Z") @ Quaternion().slerp(TURN, s).to_matrix().to_4x4()
        u = min(t, T)
        piv = Vector((low.x, low.y, max(0.0, low.z - 0.5 * G * (t / 30) ** 2)))
        piv += vel * (u - u * u / (2 * T)) + extra * (u / T)
        M = Matrix.Translation(piv) @ R @ Matrix.Translation(-low) @ M0
        z = float(spear_pts(M)[:, 2].min())
        return Matrix.Translation((0, 0, SPEAR_REST - z if t >= T else max(0.0, SPEAR_REST - z))) @ M

    land = spear_pts(world(T, Vector(), 0))
    away = Vector((*(land.mean(0)[:2] - bodies[n].mean(0)[:2]), 0.0)).normalized()
    best = None
    ways = sorted(((k, ang, sp) for k in range(9) for ang in ((0,) if k == 0 else (0, 45, -45))
                   for sp in (0, 30, -30, 60, -60)), key=lambda c: c[0] + (c[1] != 0) * 0.5 + abs(c[2]) / 30)
    for k, ang, sp in ways:
        push = Matrix.Rotation(math.radians(ang), 3, "Z") @ away * (0.05 * k)
        Ms = {f: world(f - RELEASE, push, sp) for f in frames}
        cuts = sum(sum(spear_cuts(bodies[f], Ms[f], HAND["Right"] if f <= RELEASE + RELEASE_EASE else NONE).values())
                   for f in frames)
        if best is None or cuts < best[0]:
            best = (cuts, k, ang, sp, Ms)
        if not cuts:
            break
    cuts, k, ang, sp, Ms = best
    info = {"release": RELEASE, "lies_from": RELEASE + T, "let_go_lowest_m": round(low.z, 3),
            "tilt_deg": round(math.degrees(a.angle(a_h)), 1), "roll_deg": round(math.degrees(-th), 1),
            "pushed_m": round(0.05 * k, 2), "push_turn_deg": ang, "spin_deg": sp, "cuts": cuts}
    return cuts, info, Ms


def drop(clip, n, clipq, base_w):
    """The death's spear: the right arm's pull, the release and the fall, keyed."""
    global RELEASE
    RELEASE = None
    for f in range(1, n + 1):
        key_support(f, support(f, True))
        key_grip("l", f, 1 - (1 - GRIP_DEAD) * (1 - support(f, True)))
    extra = right_clear(clip, n, clipq, base_w)

    def key_right():
        prev = {}
        for f in range(1, n + 1):
            e = extra[f - 1]
            if RELEASE is not None and f > RELEASE:
                e *= 1 - smoothstep((f - RELEASE) / RELEASE_EASE)
            sc.frame_set(f)
            set_right(clipq[f - 1], STAND_Q, min(1.0, base_w[f - 1] + e))
            for nm in RIGHT:
                q = PB[nm].rotation_quaternion.copy()
                if nm in prev:
                    q.make_compatible(prev[nm])
                PB[nm].rotation_quaternion = prev[nm] = q
                PB[nm].keyframe_insert("rotation_quaternion", frame=f)

    key_right()
    latest = find_release(n)
    if latest is None:
        print("CLIP_DROP %s: the spear never comes near the ground; he keeps it" % clip)
        return None
    tried = []
    for r in range(latest, max(2, latest - RELEASE_SEARCH) - 1, -1):
        RELEASE = r
        key_right()
        tried.append(fall(n))
        if not tried[-1][0]:
            break
    cuts, info, Ms = min(tried, key=lambda t: (t[0], -t[1]["release"]))
    RELEASE = info["release"]
    key_right()
    for f in range(1, n + 1):
        key_grip("r", f, 1 - (1 - GRIP_DEAD) * smoothstep((f - RELEASE) / RELEASE_EASE) if f > RELEASE else 1.0)
    sb = PB["Spear"]
    key_spear_rest(1)
    key_spear_rest(RELEASE)
    prev = sb.rotation_quaternion.copy()
    for f in range(RELEASE + 1, n + 1):
        sc.frame_set(f)
        sb.matrix = rig.matrix_world.inverted() @ Ms[f] @ K_SPEAR.inverted()
        q = sb.rotation_quaternion.copy()
        q.make_compatible(prev)
        sb.rotation_quaternion = prev = q
        sb.scale = (1, 1, 1)
        sb.keyframe_insert("location", frame=f)
        sb.keyframe_insert("rotation_quaternion", frame=f)
    err = 0.0
    for f in range(RELEASE + 1, n + 1):
        sc.frame_set(f)
        err = max(err, float(np.abs(np.array(spear_world()) - np.array(Ms[f])).max()))
    assert err < 1e-4, err
    print("CLIP_DROP %s: let go at frame %d (lowest point %.3f m up), tilts %.0f deg and lies level from frame %d,"
          " spun %d deg, pushed %.2f m from the body; body triangles through it after the release: %d"
          % (clip, RELEASE, info["let_go_lowest_m"], info["tilt_deg"], info["lies_from"], info["spin_deg"],
             info["pushed_m"], cuts))
    return info


# --- The clips -----------------------------------------------------------------------------

report = json.loads(out_json.read_text(encoding="utf-8")) if out_json.exists() else {}
rig.animation_data_create()
made = {}


def make(clip):
    """Retarget one clip onto the rig, key it and work out the spear and the hands."""
    global RELEASE
    fbx, opt = CLIPS[clip]
    RELEASE = None
    blend = opt.get("blend_in") or opt.get("blend_out")
    if blend:
        q0, h0 = first_pose("idle")
    if clip in bpy.data.actions:
        bpy.data.actions.remove(bpy.data.actions[clip])
    before, acts_before = set(bpy.data.objects), set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=str(anim_dir / fbx))
    new_objs = [o for o in bpy.data.objects if o not in before]
    src = next(o for o in new_objs if o.type == "ARMATURE")
    f0, f1 = (int(round(v)) for v in src.animation_data.action.frame_range)
    if "range" in opt:
        f0, f1 = max(f0, opt["range"][0]), min(f1, opt["range"][1])
    smw = src.matrix_world
    missing = [n for n in order if src.data.bones.get(n) is None]
    S_rest = {n: (smw.to_3x3() @ src.data.bones[n].matrix_local.to_3x3()).normalized() for n in order if n not in missing}
    s_hips = smw @ src.data.bones[MX + "Hips"].head_local
    ratio = T_hips.z / s_hips.z
    samples = []
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        R = {n: (smw.to_3x3() @ src.pose.bones[n].matrix.to_3x3()).normalized() for n in S_rest}
        samples.append((R, (smw @ src.pose.bones[MX + "Hips"].head).copy()))
    n_fr = len(samples)
    drift = samples[-1][1] - samples[0][1] if opt.get("in_place") else Vector()
    drift.z = 0.0
    local = []
    for R, _ in samples:
        Rt, q = {}, {}
        for n in order:
            par = RB[n].parent
            pn = par.name if par is not None and par.name in T_rest else None
            Rt[n] = R[n] @ S_rest[n].inverted() @ T_rest[n] if n in R else (
                Rt[pn] @ T_rest[pn].inverted() @ T_rest[n] if pn else T_rest[n])
            basis = T_rest[n].inverted() @ Rt[n] if pn is None else \
                (T_rest[pn].inverted() @ T_rest[n]).inverted() @ Rt[pn].inverted() @ Rt[n]
            q[n] = basis.to_quaternion()
        local.append(q)
    hips_off = [(h - s_hips - drift * (i / max(1, n_fr - 1))) * ratio for i, (_, h) in enumerate(samples)]
    clipq = [{nm: q[nm].copy() for nm in ARM} for q in local]
    base_w = [1.0] * n_fr
    if opt.get("hold"):
        for q in local:
            q.update({nm: STAND_Q[nm].copy() for nm in ARM})
    if opt.get("drop"):
        base_w = [1 - smoothstep(i / EASE) for i in range(n_fr)]
        for i, q in enumerate(local):
            for nm in ARM:
                s = STAND_Q[nm].copy()
                s.make_compatible(q[nm])
                q[nm] = q[nm].slerp(s, base_w[i])
    wts = blend_weights(n_fr, opt) if blend else None
    if blend:           # the body; the arms once the spear is worked out
        for i, w in enumerate(wts):
            if w <= 0:
                continue
            for n in order:
                if n not in ARM:
                    b = q0[n].copy()
                    b.make_compatible(local[i][n])
                    local[i][n] = local[i][n].slerp(b, w)
            hips_off[i] = hips_off[i].lerp(h0, w)
    nb = opt.get("loop_blend", 0)
    if opt.get("loop"):
        gap = max(local[-1][n].rotation_difference(local[0][n]).angle for n in order)
        if math.degrees(gap) > 0.5 or (hips_off[-1] - hips_off[0]).length > 0.005:
            print("CLIP_SEAM %s: last frame %.1f deg and %.1f cm off the first; easing the last %d frames into it"
                  % (clip, math.degrees(gap), 100 * (hips_off[-1] - hips_off[0]).length, LOOP_FIX))
            nb = LOOP_FIX
    for k in range(nb):
        i = n_fr - nb + k
        w = smoothstep((k + 1) / nb)
        for n in order:
            a, b = local[i][n], local[0][n].copy()
            b.make_compatible(a)
            local[i][n] = a.slerp(b, w)
        hips_off[i] = hips_off[i].lerp(hips_off[0], w)
    act = bpy.data.actions.new(clip)
    act.use_fake_user = True
    rig.animation_data.action = act
    prev = {}
    hb = PB[MX + "Hips"]
    for i in range(n_fr):
        for n in order:
            pb = PB[n]
            qq = local[i][n]
            if n in prev:
                qq.make_compatible(prev[n])
            prev[n] = qq
            pb.rotation_quaternion = qq
            pb.keyframe_insert("rotation_quaternion", frame=i + 1)
        hb.location = T_rest[MX + "Hips"].inverted() @ hips_off[i]
        hb.keyframe_insert("location", frame=i + 1)
    key_controls(1)
    key_spear_rest(1)
    key_support(1, 1.0)
    key_grip("r", 1, 1.0)
    key_grip("l", 1, 1.0)
    for o in new_objs:
        bpy.data.objects.remove(o, do_unlink=True)
    for a in set(bpy.data.actions) - acts_before:
        if a is not act:
            bpy.data.actions.remove(a)
    act["source"] = fbx
    act["frames"] = n_fr
    act.use_frame_range = True
    act.frame_start, act.frame_end = 1, n_fr
    act.use_cyclic = bool(opt.get("loop") or opt.get("loop_blend"))
    seam = max(local[-1][n].rotation_difference(local[0][n]).angle for n in order)
    seam_hips = (hips_off[-1] - hips_off[0]).length
    if act.use_cyclic:
        assert math.degrees(seam) < 0.5 and seam_hips < 0.005, (clip, math.degrees(seam), seam_hips)
    lift = [0.0] * n_fr
    if opt.get("ground") or opt.get("sole"):
        lift = ground_lift(n_fr) if opt.get("ground") else sole_follow(n_fr, act.use_cyclic)
        for i in range(n_fr):
            hb.location = T_rest[MX + "Hips"].inverted() @ (hips_off[i] + Vector((0, 0, lift[i])))
            hb.keyframe_insert("location", frame=i + 1)
    if opt.get("in_place"):
        dur = max(1, n_fr - 1) / 30.0
        act["root_vel"] = [drift.x * ratio / dur, drift.y * ratio / dur]
    print("CLIP", clip, fbx, f"{f0}-{f1}", n_fr, "frames (%.2f s), hip ratio %.3f, missing bones %s, in-place drift %.3f m, ground lift up to %.3f m"
          % ((n_fr - 1) / 30, ratio, missing, drift.length * ratio, max(lift)),
          "sole shift %.3f to %.3f m" % (min(lift), max(lift)) if opt.get("sole") else "",
          "seam %.1f deg, hips %.1f cm" % (math.degrees(seam), 100 * seam_hips))
    extra = {}
    if opt.get("thrust"):
        extra["thrust"] = thrust(clip, n_fr)
        if blend:
            blend_arms(n_fr, wts, q0)
        extra["slide"] = grip_slide(clip, n_fr, wts)
        extra["arm"] = arm_clear(clip, n_fr)
        extra["clear"] = wrist_clear(clip, n_fr)
    if opt.get("drop"):
        extra["drop"] = drop(clip, n_fr, clipq, base_w)
    if RELEASE is not None:
        act["spear_release"] = RELEASE
    made[clip] = {"source": fbx, "frames": n_fr, "range": [f0, f1], "lift": [round(x, 4) for x in lift],
                  "seam_deg": round(math.degrees(seam), 2), "seam_hips_cm": round(100 * seam_hips, 2),
                  "root_vel": list(act.get("root_vel", [0.0, 0.0])), **extra}


def measure(clip):
    """Every frame: what cuts through the spear, the least gap, the lowest points, the left
    hand's miss and the wrists; into the report and printed."""
    global RELEASE
    opt = CLIPS[clip][1]
    act = set_action(clip)
    n_fr = int(act["frames"])
    RELEASE = act.get("spear_release")
    dr = opt.get("drop", False)
    hb = PB[MX + "Hips"]
    rows = []
    for i in range(n_fr):
        f = i + 1
        sc.frame_set(f)
        P = evaluated()
        M = spear_world()
        sup = support(f, dr)
        g, who = gap(P, M, vskip(f, dr), who=True)
        rows.append({"cuts": spear_cuts(P, M, skip_mask(f, dr)), "gap_mm": round(g * 1000, 1), "gap_bone": who,
                     "lowest": round(float(P[:, 2].min()), 4), "spear_low": round(float(spear_pts(M)[:, 2].min()), 4),
                     "hips": [round(c, 3) for c in hb.matrix.translation], "support": round(sup, 3),
                     "miss_mm": round((PB[MX + "LeftHand"].head - PB["HandIK.L"].head).length * 1000, 1) if sup >= 1 else None,
                     "bend": {s: round(wrist_bend(s), 1) for s in ("Left", "Right")}})
    if clip in made:
        report[clip] = made[clip]
    report.setdefault(clip, {})["rows"] = rows
    near = min(range(n_fr), key=lambda i: rows[i]["gap_mm"])
    print("CLIP_GAP %s: least gap %.1f mm (frame %d, %s); nearer than %.0f mm in %d of %d frames"
          % (clip, rows[near]["gap_mm"], near + 1, rows[near]["gap_bone"], CLEAR * 1000,
             sum(1 for r in rows if r["gap_mm"] < CLEAR * 1000), n_fr))
    low = [r["lowest"] for r in rows]
    hit = [(i + 1, sum(r["cuts"].values()), r["cuts"]) for i, r in enumerate(rows) if r["cuts"]]
    miss = [r["miss_mm"] for r in rows if r["miss_mm"] is not None]
    print("CLIP_GROUND", clip, "lowest point from %.3f to %.3f m; the spear's lowest %.3f m" % (
        min(low), max(low), min(r["spear_low"] for r in rows)))
    print("CLIP_HANDS %s: left hand off its hold up to %.1f mm; wrist bends up to left %.0f, right %.0f deg" % (
        clip, max(miss or [0]), max(r["bend"]["Left"] for r in rows), max(r["bend"]["Right"] for r in rows)))
    if hit:
        worst = max(hit, key=lambda h: h[1])
        bones = {}
        for _, _, by in hit:
            for b, c in by.items():
                bones[b] = max(bones.get(b, 0), c)
        print("CLIP_SPEAR %s: body through it in %d of %d frames %s; worst frame %d, %d triangles %s; bones %s"
              % (clip, len(hit), n_fr, [h[0] for h in hit][:20], worst[0], worst[1], worst[2], bones))
    else:
        print("CLIP_SPEAR %s: clear in all %d frames" % (clip, n_fr))


# The hold clips first: the carry comes from them, and the others start from it.
recompute = any(c in ONLY for c in HOLD)
for clip in CLIPS:
    if clip in ONLY:
        make(clip)
    if clip == HOLD[-1]:
        report["carry"] = set_carry(recompute)
for clip in CLIPS:
    if clip in ONLY or (recompute and clip in HOLD):
        measure(clip)

out_json.write_text(json.dumps(report), encoding="utf-8")
first = next(c for c in CLIPS if c in bpy.data.actions)
rig.animation_data.action = bpy.data.actions[first]
rig.animation_data.action_slot = bpy.data.actions[first].slots[0]
sc.frame_start, sc.frame_end = 1, int(bpy.data.actions[first]["frames"])
sc.frame_set(1)
for screen in bpy.data.screens:
    for area in screen.areas:
        for space in area.spaces:
            if space.type == "FILE_BROWSER" and space.params is not None:
                space.params.directory = b"//" + b"_" * 700
                space.params.directory = b"//"
bpy.ops.wm.save_as_mainfile(filepath=str(out_blend), relative_remap=True, compress=True)
print("CLIPS_SAVED", out_blend)
