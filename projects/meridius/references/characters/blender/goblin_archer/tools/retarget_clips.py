"""Review only: retarget the goblin's Mixamo clips onto GoblinArcherRig, keep the bow clear of
the body, measure every frame and save a scratch copy with the clips (Mixamo motion stays out
of the repo).

  blender -b goblin_archer_rig.blend --python retarget_clips.py -- <animations dir> <out.blend> <measure.json>

Retarget as goblin_rabble/tools/retarget_clips.py (rest-pose difference, bone by bone, in
world space; the hips' motion scaled by the hip-height ratio), keying only the Mixamo body
bones: the fingers keep the grip actions. Options per clip:
  in_place   remove the drift between the first and last frame (its speed is kept as the
             action's root_vel, m/s in Blender x and y)
  loop       the clip loops (its corrections are smoothed round the seam)
  loop_blend ease the last N frames back into the first pose (a loop)
  ground     lift the hips wherever the skinned body dips below the floor (the soles may
             sink FOOT_SINK), widened and averaged so the lift never pops
  sole       raise or lower the hips so the lowest point of the soles stays at its rest
             height, averaged over SOLE_W frames either side (round the seam of a loop)
  hold       `bow_hold` in the clip (1 by default: the hand keeps its turn on the bow;
             0: the clip turns the wrist, as the archer's own Mixamo clips need)
  draw       the attack's shot (draw_bow): the arrow shows from the frame the right hand
             is highest, at the quiver, rides in the fist, turns onto the string as the hand
             reaches the nocking point, and the string's middle then follows the fist. At
             the clip's last frame the arrow is loosed (hidden from the next frame) and the
             string swings back through rest; the last pose is held FOLLOW frames more
  drop       he lets go of the bow at the latest frame, at most RELEASE_LEAD frames before
             it would touch the ground and RELEASE_SEARCH frames earlier than that, from
             which it falls clear of him: the hand opens to GRIP_DEAD and the wrist goes
             back to the clip over RELEASE_EASE frames (`bow_hold` and the grip's influence
             are keyed), and the `Bow` bone is keyed so the bow turns flat about its lowest
             point, which drops to the ground, in the time its middle would take to fall
             there (its side up and its distance from the body the first that keep it clear
             of the body in every later frame)
The hips are placed first, then the left arm corrected. The clips were made for empty
hands, so each frame gets the smallest left-arm correction that keeps the bow clear of the
body and above the ground: the wrist is held at the standard pose's turn on the bow in
every frame (the rig's BowHold does the same at bow_hold 1), the upper arm and the forearm
are eased toward the standard pose, then the elbow bent and the arm lifted out from the
chest, tried only after every ease. Each correction is widened and averaged over
neighbouring frames (round the seam of a loop). The right arm keeps the clip's motion.
The quiver hangs on its strap: where the body (the hood when the head is thrown back)
would come within QUIVER_MIN of it, the `Quiver` bone tips its top out from the back
about the bottom of its back, swings its top away from the head or lifts it off the back,
the smallest turn that clears, widened and averaged as the arm's. Where a leg goes
through the cape, the lower cape (`Cape2`) swings back and then the upper one (the
rig's `cape_back`), widened and averaged the same way. Every clip keys the props' bones,
`bow_hold`, `cape_back` and the grip in its first frame, so switching clips leaves
nothing behind.
Per frame: body triangles that cut through the bow and the quiver (exact triangle overlap,
both trees each way round, as the bow's string is two long thin strands), by the bone
weighing most on them; the quiver's nearest approach to the body; the cape's triangles
below the quiver that cut through the legs, the skirt or the arms; the body's and the
props' lowest points.
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
BOW_GROUND = 0.01    # the bow's lowest point stays this far above the ground
SMOOTH = 3           # frames either side
SOLE_W = 1
RELEASE_LEAD = 4     # frames: he lets go of the bow at least this long before it would touch the ground
RELEASE_SEARCH = 12  # and at most this many frames earlier
RELEASE_EASE = 6     # frames over which the hand opens and the wrist goes back to the clip
GRIP_DEAD = 0.4      # the grip's influence on the open hand
BOW_REST = 0.002     # the dropped bow lies this far above the ground
G = 9.81
QUIVER_MIN = 0.002   # the quiver keeps this far off the body
FOLLOW = 8           # frames the attack holds its last pose after the shot
DRAW_EASE = 3        # frames over which the string's middle goes from rest to the fist
STRING_SNAP = (-0.012, 0.006, -0.003)   # after the shot the string swings this far along its draw (m)
FIST = 0.15          # the fist's middle is this far up the arrow from its nock (the rig's ARROW_WORLD)
ARROW_GRIP = 0.02    # out of the quiver the fingers hold the arrow this far up from its nock
ARROW_OUT = 0.015    # at full draw the arrow's head starts this far past the rest
LATERAL = 0.16       # the fist may move this far out to his right to keep out of his head
LEVEL_EASE = 3       # frames before nocking over which the fist comes onto the arrow's level
TAKE = 2             # frames before nocking from which the fingers may touch the string
QUIVER_TUBE = 0.73   # share of the quiver's length up to its rim (build_archer.py)
CAPE_UP = range(0, 45, 5)      # degrees the upper cape may swing further back off a leg (`cape_back`)
CAPE_LOW = range(0, 85, 5)     # and the lower cape (Cape2)
CAPE_GRID = sorted(((u, l) for u in CAPE_UP for l in CAPE_LOW), key=lambda c: (2 * c[0] + c[1], c[0]))
CLIPS = {
    "idle": ("Idle - Goblin.fbx", {"in_place": True, "loop_blend": 10}),
    "walk": ("Walk - Goblin.fbx", {"in_place": True, "loop": True, "sole": True}),
    "death": ("Death - Goblin.fbx", {"ground": True, "drop": True}),
    "run": ("Running - Goblin Archer.fbx", {"in_place": True, "loop": True, "sole": True}),
    "attack": ("Attack - Goblin Archer.fbx", {"hold": 0.0, "draw": True, "sole": True}),
    "block": ("Hit - Goblin archer.fbx", {"hold": 0.0, "sole": True}),
}
PROPS = ("Bow", "Quiver")
SHOWN = ("Arrow",)   # measured only in the frames the rig's `arrow` shows it

argv = sys.argv[sys.argv.index("--") + 1:]
anim_dir, out_blend, out_json = Path(argv[0]), Path(argv[1]), Path(argv[2])
sc = bpy.context.scene
sc.render.fps = 30
rig = bpy.data.objects["GoblinArcherRig"]
body = bpy.data.objects["GoblinArcher"]
me = body.data
MX = "mixamorig:"
FING = ("Thumb", "Index", "Middle", "Ring")
keyed = {b.name for b in rig.data.bones if b.name.startswith(MX) and not any(f in b.name for f in FING)}
order = []


def visit(b):
    if b.name in keyed:
        order.append(b.name)
    for c in b.children:
        visit(c)


visit(rig.data.bones[MX + "Hips"])
assert set(order) == keyed, keyed - set(order)
T_rest = {n: (rig.matrix_world.to_3x3() @ rig.data.bones[n].matrix_local.to_3x3()).normalized() for n in order}
T_hips = rig.matrix_world @ rig.data.bones[MX + "Hips"].head_local

me.calc_loop_triangles()
TRI = np.array([t.vertices[:] for t in me.loop_triangles])
gname = {g.index: g.name.replace(MX, "") for g in body.vertex_groups}
DOM = []
for v in me.vertices:
    g = max(v.groups, key=lambda g: g.weight, default=None)
    DOM.append(gname[g.group] if g else "-")
DOM = np.array(DOM)
TRI_BONE = DOM[TRI[:, 0]]
LEFT_HAND = np.array([b.startswith("LeftHand") for b in TRI_BONE])
RIGHT_HAND = np.array([b.startswith("RightHand") for b in TRI_BONE])   # holds the arrow
HEAD_TRI = np.isin(TRI_BONE, ["Head", "Neck"])
RCHAIN = tuple(MX + "Right" + p for p in ("Arm", "ForeArm", "Hand"))
rest_z = np.array([v.co.z for v in me.vertices])
floor = np.where(rest_z < FOOT_Z, -FOOT_SINK, 0.0)
SOLE = rest_z < FOOT_Z
# The cape: the second largest part of the mesh (the hood and the cape, one sheet); the
# part of it that hangs from the cape's own bones, below the quiver.
E = np.array([e.vertices[:] for e in me.edges])
lab = np.arange(len(me.vertices))
while True:
    new = lab.copy()
    m = np.minimum(lab[E[:, 0]], lab[E[:, 1]])
    np.minimum.at(new, E[:, 0], m)
    np.minimum.at(new, E[:, 1], m)
    if (new == lab).all():
        break
    lab = new
ids, counts = np.unique(lab, return_counts=True)
IN_CAPE = lab == ids[np.argsort(-counts)[1]]
LOW_CAPE_TRI = IN_CAPE[TRI].all(1) & (rest_z[TRI].max(1) < float(rig["fit"]["cape_top_z"]))
NOT_CAPE_TRI = ~IN_CAPE[TRI].any(1)
LOCAL, PROP_NP, PROP_BVH, PROP_SPHERE = {}, {}, {}, {}
for name in PROPS + SHOWN:
    ob = bpy.data.objects[name]
    vs, fs = [v.co.copy() for v in ob.data.vertices], [list(p.vertices) for p in ob.data.polygons]
    LOCAL[name] = (vs, fs)
    A = np.array([tuple(v) for v in vs])
    c = (A.min(0) + A.max(0)) / 2
    PROP_NP[name], PROP_BVH[name] = A, BVHTree.FromPolygons(vs, fs)
    PROP_SPHERE[name] = (c, float(np.linalg.norm(A - c, axis=1).max()))
# The arrow: its nock at the origin and its head up. Its bare shaft is the longest stretch
# without vertices, between the fletching and the head: its radius is taken where the
# shaft leaves the fletching, its head reaches from the top of the shaft to the tip. The
# longest draw keeps the head out past the rest. The quiver's opening: the middle of its rim.
A_ = PROP_NP["Arrow"]
ARROW_LEN = float(A_[:, 2].max())
r_ = np.hypot(A_[:, 0], A_[:, 1])
zs_ = np.sort(A_[:, 2])
g_ = int(np.argmax(np.diff(zs_)))
ARROW_R = float(np.median(r_[(A_[:, 2] > zs_[g_] - 0.005) & (A_[:, 2] <= zs_[g_])]))
ARROW_HEAD = ARROW_LEN - float(zs_[g_ + 1])
DRAW_MAX = ARROW_LEN - ARROW_HEAD - ARROW_OUT
Q_ = PROP_NP["Quiver"]
zt_ = float(Q_[:, 2].min() + QUIVER_TUBE * np.ptp(Q_[:, 2]))
ring_ = Q_[np.abs(Q_[:, 2] - zt_) < 0.02]
Q_RIM = Vector((float(ring_[:, 0].min() + ring_[:, 0].max()) / 2, float(ring_[:, 1].min() + ring_[:, 1].max()) / 2, zt_))
BB, QB = rig.pose.bones["Bow"], rig.pose.bones["Quiver"]
BB.rotation_mode = QB.rotation_mode = "QUATERNION"
GRIP_L = [rig.pose.bones[f"{MX}LeftHand{c}{i}"].constraints["grip_bow"] for c in FING for i in (1, 2, 3)]
# The quiver turns about the bottom of its back, which rests on the cape (its origin is the
# middle of its back and the bone runs up its long axis, its z out from the back).
Q_PIVOT = Vector((0, float(PROP_NP["Quiver"][:, 2].min()), 0))
KQ = Matrix.Translation((0, QB.bone.length, 0)) @ bpy.data.objects["Quiver"].matrix_parent_inverse @ \
    bpy.data.objects["Quiver"].matrix_basis
# (tip out in degrees, swing its top away from the head in degrees, lift off the back in
# metres), cheapest first. A turn about the bone's z takes its top toward its -x: SWING
# makes a positive swing take it away from the middle of the back.
QGRID = sorted(((b, sw, d) for b in range(0, 55, 5) for sw in (0, 10, 20) for d in (0, 0.03, 0.06)),
               key=lambda c: c[0] / 10 + c[1] / 10 + c[2] / 0.02)
QSCALE = (10, 10, 0.02)
q_top = rig.matrix_world.to_3x3() @ rig.data.bones["Quiver"].matrix_local.to_3x3()
SWING = 1 if (q_top @ Vector((-1, 0, 0))).x * q_top.col[1].x > 0 else -1
RELEASE = None       # the frame the bow is let go in the clip being made
HOLD = 1.0           # its `bow_hold`
print("CLIPS_MESH body %d vertices, %d triangles (cape below the quiver %d); props %s" % (
    len(me.vertices), len(TRI), LOW_CAPE_TRI.sum(), {n: len(LOCAL[n][1]) for n in PROPS}))
print("CLIPS_ARROW %.3f m long, shaft %.1f mm thick, head %.3f m; drawn at most %.3f m from the rest" % (
    ARROW_LEN, 2000 * ARROW_R, ARROW_HEAD, DRAW_MAX))
# The lower cape swings back about its bone's x: the sign that takes its tail back (+y).
CB = rig.pose.bones["Cape2"]
CB.rotation_mode = "QUATERNION"
t0_ = CB.tail.y
CB.rotation_quaternion = Quaternion((1, 0, 0), math.radians(10))
bpy.context.view_layer.update()
CAPE_BACK = 1 if CB.tail.y > t0_ else -1
CB.rotation_quaternion = Quaternion()
bpy.context.view_layer.update()
# The rig's `cape_back` swings the upper cape (Cape1) back through its thigh driver once the
# rig is tagged for the change (not its animation, which would put the keyed value back).
C1 = rig.pose.bones["Cape1"]
t0_ = C1.tail.y
rig["cape_back"] = 0.3
rig.update_tag()
bpy.context.view_layer.update()
assert C1.tail.y > t0_ + 0.01, (t0_, C1.tail.y)
rig["cape_back"] = 0.0
rig.update_tag()
bpy.context.view_layer.update()

# The left-arm correction. The goblin faces -y, so his left is +x.
assert rig.data.bones[MX + "LeftArm"].head_local.x > 0
CHEST = MX + "Spine2"
CHAIN = tuple(MX + "Left" + p for p in ("Arm", "ForeArm", "Hand"))
LAT_CHEST = rig.data.bones[CHEST].matrix_local.to_3x3().inverted() @ Vector((1, 0, 0))
# (upper arm and forearm eased toward the standard pose, elbow bent by degrees, arm lifted
# out by degrees): every ease first, then the bends and lifts on the full ease.
GRID = [(w, 0, 0) for w in (0, .2, .4, .6, .8, 1)] + sorted(
    ((1, a, p) for a in (0, 15, 30, 45, 60, 75) for p in (0, 10, 20, 30, 40, 50) if a or p),
    key=lambda c: c[1] / 25 + c[2] / 20)
SCALE = (1, 25, 20)
assert all(rig[p] == 0 for p in ("bow_ik", "draw_ik", "leg_ik")) and rig["bow_hold"] == 1 and rig["arrow"] == 0
STAND_Q = {n: rig.pose.bones[n].matrix_basis.to_quaternion() for n in CHAIN}


def evaluated():
    ev = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    m = ev.to_mesh()
    co = np.empty(len(m.vertices) * 3)
    m.vertices.foreach_get("co", co)
    ev.to_mesh_clear()
    return co.reshape(-1, 3) @ np.array(body.matrix_world.to_3x3()).T + np.array(body.matrix_world.translation)


def prop_world(name):
    """The prop's world matrix from its bone's pose."""
    ob = bpy.data.objects[name]
    pb = rig.pose.bones[ob.parent_bone]
    return rig.matrix_world @ pb.matrix @ Matrix.Translation((0, pb.bone.length, 0)) @ ob.matrix_parent_inverse @ ob.matrix_basis


def prop_mesh(name):
    """The prop's evaluated vertices in world space (the bow with its string drawn)."""
    ob = bpy.data.objects[name].evaluated_get(bpy.context.evaluated_depsgraph_get())
    m = ob.to_mesh()
    vs = [ob.matrix_world @ v.co for v in m.vertices]
    ob.to_mesh_clear()
    return vs


def prop_low(name):
    M = np.array(prop_world(name))
    return float((PROP_NP[name] @ M[:3, :3].T + M[:3, 3])[:, 2].min())


def overlap_both(a, b):
    """Index pairs (a's, b's) of overlapping triangles, each tree tested against the other:
    one tree's long thin triangles can escape the test the other way round."""
    return {(i, j) for i, j in a.overlap(b)} | {(i, j) for j, i in b.overlap(a)}


def bow_cuts(P, M, skip_hand=True):
    """Body triangles through the bow at world matrix M (its left hand left out while it
    holds the bow), counted near it only (fast; the final measure below is the exact one)."""
    M = np.array(M)
    c, r = PROP_SPHERE["Bow"]
    near = np.linalg.norm(P - (M[:3, :3] @ c + M[:3, 3]), axis=1) < r + 0.06
    tm = near[TRI].any(1)
    if skip_hand:
        tm &= ~LEFT_HAND
    if not tm.any():
        return 0
    sub = TRI[tm]
    idx = np.unique(sub)
    remap = np.full(len(P), -1)
    remap[idx] = np.arange(len(idx))
    Mi = np.linalg.inv(M)
    bt = BVHTree.FromPolygons((P[idx] @ Mi[:3, :3].T + Mi[:3, 3]).tolist(), remap[sub].tolist())
    return len({a for a, _ in overlap_both(bt, PROP_BVH["Bow"])})


def through(P):
    """Body triangles through the bow in his hand, and 100 more if it dips into the ground
    (nothing once he has let go of it: drop_bow moves it then)."""
    if RELEASE is not None and sc.frame_current > RELEASE:
        return 0
    return (0 if prop_low("Bow") >= BOW_GROUND else 100) + bow_cuts(P, prop_world("Bow"))


def base_pose():
    pbs = rig.pose.bones
    arm, fore, hand = CHAIN
    q = {n: pbs[n].rotation_quaternion.copy() for n in CHAIN}
    W = {n: pbs[n].matrix.to_3x3().normalized() for n in CHAIN}
    ad = (pbs[arm].tail - pbs[arm].head).normalized()
    fd = (pbs[fore].tail - pbs[fore].head).normalized()
    lat = (pbs[CHEST].matrix.to_3x3().normalized() @ LAT_CHEST).normalized()
    return q, W, ad, fd, lat


def eased(q, n, w):
    s = STAND_Q[n].copy()
    s.make_compatible(q)
    return q.slerp(s, w)


def corrected(base, c, hw=1.0):
    """The arm chain's local rotations with correction c: the hand eased by hw to its standard
    turn, the upper arm and the forearm by w; a world turn R of a bone (about its head) is
    the local turn W^-1 R W, the elbow and lift turns taken from the eased pose's directions."""
    arm, fore, hand = CHAIN
    q, W, ad, fd, lat = base
    w, a, p = c
    out = {hand: eased(q[hand], hand, hw), fore: eased(q[fore], fore, w), arm: eased(q[arm], arm, w)}
    if not (a or p):
        return out
    pose_set(out)
    pbs = rig.pose.bones
    We = {n: pbs[n].matrix.to_3x3().normalized() for n in (arm, fore)}
    ad = (pbs[arm].tail - pbs[arm].head).normalized()
    fd = (pbs[fore].tail - pbs[fore].head).normalized()
    ang, axis = min(math.radians(a), max(0.0, math.radians(145) - fd.angle(ad))), ad.cross(fd)
    if ang > 0 and axis.length > 1e-4:     # bent, never past 145 degrees
        out[fore] = out[fore] @ (We[fore].inverted() @ Matrix.Rotation(ang, 3, axis.normalized()) @ We[fore]).to_quaternion()
    ang, axis = min(math.radians(p), ad.angle(lat)), ad.cross(lat)
    if ang > 0 and axis.length > 0.2:
        out[arm] = out[arm] @ (We[arm].inverted() @ Matrix.Rotation(ang, 3, axis.normalized()) @ We[arm]).to_quaternion()
    return out


def pose_set(vals):
    for n, qq in vals.items():
        rig.pose.bones[n].rotation_quaternion = qq
    bpy.context.view_layer.update()


def widen(vals, cyclic, r=SMOOTH):
    """A loop's last frame repeats its first: it wraps over the others and copies the first."""
    n = len(vals)
    m = n - 1 if cyclic else n
    at = (lambda i: vals[i % m]) if cyclic else (lambda i: vals[min(max(i, 0), n - 1)])
    wide = [max(at(j) for j in range(i - r, i + r + 1)) for i in range(m)]
    at = (lambda i: wide[i % m]) if cyclic else (lambda i: wide[min(max(i, 0), n - 1)])
    out = [sum(at(j) for j in range(i - r, i + r + 1)) / (2 * r + 1) for i in range(m)]
    return out + out[:1] if cyclic else out


def ramp(smooth, target, cyclic):
    """Give each frame in target its correction and ramp its neighbours into it over SMOOTH frames."""
    new = [list(c) for c in smooth]
    for g in range(1, len(smooth) + 1):
        d, f = min((abs(g - f), f) for f in target) if target else (None, None)
        if f is None or d > SMOOTH:
            continue
        w = 1 - d / (SMOOTH + 1)
        new[g - 1] = [a + (b - a) * w for a, b in zip(smooth[g - 1], target[f])]
    if cyclic:
        new[-1] = list(new[0])
    return new


def let_go(f):
    """0 while the left hand holds the bow, easing to 1 over RELEASE_EASE frames once it lets go."""
    if RELEASE is None or f <= RELEASE:
        return 0.0
    t = min(1.0, (f - RELEASE) / RELEASE_EASE)
    return t * t * (3 - 2 * t)


def held(f):
    """How far the hand keeps its turn on the bow: the clip's HOLD, then 0 once it lets go."""
    return HOLD * (1 - let_go(f))


def key_hold(n):
    """Key `bow_hold` and the bow grip's influence: the clip's HOLD and a closed grip while the
    hand holds the bow, then the wrist goes back to the clip and the hand opens to GRIP_DEAD."""
    for f in range(1, n + 1) if RELEASE is not None else (1,):
        rig["bow_hold"] = held(f)
        rig.keyframe_insert('["bow_hold"]', frame=f)
        for c in GRIP_L:
            c.influence = 1 - (1 - GRIP_DEAD) * let_go(f)
            c.keyframe_insert("influence", frame=f)


def correct_arm(clip, n, cyclic):
    t0, evals = time.time(), 0
    found, bases = [], []
    for f in range(1, n + 1):
        sc.frame_set(f)
        base = base_pose()
        bases.append(base)
        best = None
        for c in GRID:
            pose_set(corrected(base, c, held(f)))
            k = through(evaluated())
            evals += 1
            if best is None or k < best[0]:
                best = (k, c)
            if k == 0:
                break
        pose_set(base[0])
        found.append(best)
    cols = list(zip(*[c for _, c in found]))
    smooth = [list(c) for c in zip(*[widen(list(col), cyclic) for col in cols])]
    if cyclic:
        smooth[-1] = list(smooth[0])
    left = [i + 1 for i, (k, _) in enumerate(found) if k]
    print("CLIP_FIX %s: corrected %d of %d frames, largest %s; best grid point still through in %d frames %s"
          % (clip, sum(1 for _, c in found if any(c)), n, tuple(round(max(col), 2) for col in cols), len(left), left[:12]))

    def key_all():
        prev = {}
        for f in range(1, n + 1):
            sc.frame_set(f)
            vals = corrected(bases[f - 1], smooth[f - 1], held(f))
            for nm, qq in vals.items():
                if nm in prev:
                    qq.make_compatible(prev[nm])
                prev[nm] = qq
                rig.pose.bones[nm].rotation_quaternion = qq
                rig.pose.bones[nm].keyframe_insert("rotation_quaternion", frame=f)

    key_all()
    # Where the widened corrections still meet the body, give the frame the nearest clear
    # grid point and ramp its neighbours into it over SMOOTH frames, until every frame is clear.
    for it in range(4):
        fails = []
        for f in range(1, n + 1):
            sc.frame_set(f)
            if through(evaluated()):
                fails.append(f)
        print("CLIP_FIX %s repair %d: still through %s" % (clip, it, fails))
        if not fails:
            break
        target = {}
        for f in fails:
            sc.frame_set(f)
            cur = smooth[f - 1]
            for c in sorted(GRID, key=lambda c: sum(abs(a - b) / k for a, b, k in zip(c, cur, SCALE))):
                pose_set(corrected(bases[f - 1], c, held(f)))
                evals += 1
                if not through(evaluated()):
                    target[f] = c
                    break
        smooth = ramp(smooth, target, cyclic)
        key_all()
    print("CLIP_FIX %s: %d evaluations in %.0f s" % (clip, evals, time.time() - t0))
    return [[round(x, 3) for x in c] for c in smooth]


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


def find_release(n):
    """The frame he lets go of the bow: RELEASE_LEAD frames before the bow in his hand would
    first come within BOW_GROUND of the ground (None if it never does)."""
    for f in range(1, n + 1):
        sc.frame_set(f)
        if prop_low("Bow") < BOW_GROUND:
            return max(2, f - RELEASE_LEAD)
    return None


def pts(name, M):
    Mn = np.array(M)
    return PROP_NP[name] @ Mn[:3, :3].T + Mn[:3, 3]


def key_bone(pb, f):
    pb.keyframe_insert("location", frame=f)
    pb.keyframe_insert("rotation_quaternion", frame=f)


def drop_bow(n):
    """Let go of the bow at the latest frame from RELEASE back RELEASE_SEARCH frames from which
    it falls clear of the body (re-keying the hand's hold for that frame), or where the
    fewest body triangles meet it, and key its fall."""
    global RELEASE
    latest, tried = RELEASE, []
    for r in range(latest, max(1, latest - RELEASE_SEARCH) - 1, -1):
        RELEASE = r
        key_hold(n)
        tried.append(fall(n))
        if not tried[-1][0]:
            break
    best = min(tried, key=lambda t: (t[0], -t[1]["release"]))
    RELEASE = best[1]["release"]
    key_hold(n)
    return key_fall(n, *best)


def fall(n):
    """The bow's fall from RELEASE: it turns flat about its lowest point, which drops to the
    ground, in the time its middle would take to fall freely to the ground (the turn eased in
    as the fall), keeping the hand's speed along the ground and slowing to a stop; it ends
    lying flat, BOW_REST above the ground, and stays. The side it lands on and how far it is
    pushed away from the body are the first that keep it clear of the body in every frame
    after it is let go (the open hand counted once RELEASE_EASE frames are past). Returns
    (body triangles through it, its description, its world matrix per frame)."""
    sc.frame_set(RELEASE - 1)
    o_prev = prop_world("Bow").translation.copy()
    sc.frame_set(RELEASE)
    M0 = prop_world("Bow")
    P0 = pts("Bow", M0)
    low = Vector(P0[np.argmin(P0[:, 2])].tolist())
    vel = M0.translation - o_prev
    vel.z = 0.0
    normal = (M0.to_3x3() @ Vector((0, 1, 0))).normalized()
    mid = float((P0[:, 2].min() + P0[:, 2].max()) / 2)
    T = max(3, math.ceil(30 * math.sqrt(2 * mid / G)))
    frames = range(RELEASE + 1, n + 1)
    bodies = {}
    for f in frames:
        sc.frame_set(f)
        bodies[f] = evaluated()

    def world(t, up, extra, spin=0.0):
        s = min(1.0, (t / T) ** 2)
        R = Matrix.Rotation(math.radians(spin) * s, 4, "Z") @ \
            Quaternion().slerp(normal.rotation_difference(up), s).to_matrix().to_4x4()
        u = min(t, T)
        piv = Vector((low.x, low.y, max(0.0, low.z - 0.5 * G * (t / 30) ** 2)))
        piv += vel * (u - u * u / (2 * T)) + extra * (u / T)
        M = Matrix.Translation(piv) @ R @ Matrix.Translation(-low) @ M0
        z = float(pts("Bow", M)[:, 2].min())
        return Matrix.Translation((0, 0, BOW_REST - z if t >= T else max(0.0, BOW_REST - z))) @ M

    side = Vector((0, 0, 1.0 if normal.z >= 0 else -1.0))
    land = pts("Bow", world(T, side, Vector()))
    away = Vector((*(land.mean(0)[:2] - bodies[n].mean(0)[:2]), 0.0)).normalized()
    best = None
    ways = sorted(((k, a, u, sp) for k in range(9) for a in ((0,) if k == 0 else (0, 45, -45))
                   for u in (side, -side) for sp in (0, 30, -30, 60, -60)),
                  key=lambda c: c[0] + (c[1] != 0) * 0.5 + (c[2] != side) * 0.25 + abs(c[3]) / 30)
    for k, ang, up, sp in ways:
        push = Matrix.Rotation(math.radians(ang), 3, "Z") @ away * (0.05 * k)
        Ms = {f: world(f - RELEASE, up, push, sp) for f in frames}
        cuts = sum(bow_cuts(bodies[f], Ms[f], f <= RELEASE + RELEASE_EASE) for f in frames)
        if best is None or cuts < best[0]:
            best = (cuts, k, ang, up, sp, Ms)
        if not cuts:
            break
    cuts, k, ang, up, sp, Ms = best
    info = {"release": RELEASE, "lies_from": RELEASE + T, "let_go_lowest_m": round(low.z, 3),
            "turn_deg": round(math.degrees(normal.angle(up)), 1), "turned_over": up.z != side.z,
            "pushed_m": round(0.05 * k, 2), "push_turn_deg": ang, "spin_deg": sp, "cuts": cuts}
    return cuts, info, Ms


def key_fall(n, cuts, info, Ms):
    """Key the `Bow` bone to the fall's world matrices (at rest up to the release)."""
    frames = range(RELEASE + 1, n + 1)
    ob = bpy.data.objects["Bow"]
    K = Matrix.Translation((0, BB.bone.length, 0)) @ ob.matrix_parent_inverse @ ob.matrix_basis
    BB.matrix_basis = Matrix.Identity(4)
    key_bone(BB, 1)
    key_bone(BB, RELEASE)
    prev = BB.rotation_quaternion.copy()
    for f in frames:
        sc.frame_set(f)
        BB.matrix = rig.matrix_world.inverted() @ Ms[f] @ K.inverted()
        q = BB.rotation_quaternion.copy()
        q.make_compatible(prev)
        BB.rotation_quaternion = q
        prev = q
        key_bone(BB, f)
    err = 0.0
    for f in frames:
        sc.frame_set(f)
        err = max(err, float(np.abs(np.array(prop_world("Bow")) - np.array(Ms[f])).max()))
    assert err < 1e-4, err
    print("CLIP_DROP let go at frame %d (lowest point %.3f m up), turns %.0f deg and lies flat from frame %d%s,"
          " spun %d deg, pushed %.2f m from the body; body triangles through it after the release: %d"
          % (RELEASE, info["let_go_lowest_m"], info["turn_deg"], info["lies_from"],
             " turned over" if info["turned_over"] else "", info["spin_deg"], info["pushed_m"], cuts))
    return info


def reach(delta):
    """Move the right wrist by `delta` (armature space): the elbow stays in the arm's plane,
    the upper arm and the forearm turn by the shortest arcs that put the elbow and the wrist
    there, and the hand keeps its turn. The bones' scale stays 1: no clip keys it, so any
    rounding left in it would build up over the calls and stay in every clip."""
    pbs = rig.pose.bones
    arm, fore, hand = (pbs[nm] for nm in RCHAIN)
    S, E, W = arm.head.copy(), fore.head.copy(), hand.head.copy()
    Hr = hand.matrix.to_quaternion().to_matrix()
    a, b = (E - S).length, (W - E).length
    T = W + delta
    d = min((T - S).length, 0.999 * (a + b))
    u = (T - S).normalized()
    sw = (W - S).normalized()
    pole = (E - S) - sw * (E - S).dot(sw)
    v = (pole - u * pole.dot(u)).normalized()
    ca = (a * a + d * d - b * b) / (2 * a * d)
    E2 = S + (u * ca + v * math.sqrt(max(0.0, 1 - ca * ca))) * a

    def turn(pb, frm, to):
        h = pb.head.copy()
        pb.matrix = Matrix.Translation(h) @ frm.rotation_difference(to).to_matrix().to_4x4() @ \
            Matrix.Translation(-h) @ pb.matrix
        pb.scale = (1, 1, 1)
        bpy.context.view_layer.update()

    turn(arm, E - S, E2 - S)
    turn(fore, hand.head - fore.head, T - fore.head)
    M = Hr.to_4x4()
    M.translation = hand.head
    hand.matrix = M
    for pb in (arm, fore, hand):
        pb.location = (0, 0, 0)
        pb.scale = (1, 1, 1)
    bpy.context.view_layer.update()


def arrow_world(nock, z, y):
    """The arrow's world matrix: its nock at `nock`, its shaft along z, its fletching's roll by y."""
    z = z.normalized()
    y = (y - z * y.dot(z)).normalized()
    N = Matrix((y.cross(z), y, z)).transposed().to_4x4()
    N.translation = nock
    return N


def draw_bow(n, shot):
    """The attack's shot, keyed on the right arm, the `String` and `Arrow` bones and the rig's
    `arrow`. The arrow rests beside the handle on the archer's left, as low as clears the bow
    hand and the forearm, and is nocked on the string at the rest's height (the string's
    middle slides up it, so it stays straight). The arrow shows from the frame the fist is
    highest, by the quiver, held near its nock and pointing back into the quiver's opening
    (or the first other way that keeps it out of him: up over his shoulder, as the hand
    holds it, at the bow), and turns to point at the bow until the frame the fist comes
    nearest the nocking point, where its nock goes onto the string. The fist comes onto the
    arrow's level (the rest's height in the bow's frame) over LEVEL_EASE frames before
    that, so the arrow stays level from the string to the rest. From then the string
    follows the fist (eased in over DRAW_EASE frames), and the fist stops at the anchor: no
    further from the rest than DRAW_MAX, so the arrow's head stays out past the bow. In
    every frame from the quiver on, the fist moves out to the archer's right, up to
    LATERAL and along the arrow's level, as far as keeps it, the arrow and the string out
    of him (widened and averaged over SMOOTH frames); the right arm reaches there with its
    elbow in the clip's plane and the hand's turn kept. At `shot` the arrow is loosed:
    hidden from the next frame, the string swinging back through rest (STRING_SNAP)."""
    SB, AB = rig.pose.bones["String"], rig.pose.bones["Arrow"]
    for pb in (SB, AB):
        pb.rotation_mode = "QUATERNION"
        pb.matrix_basis = Matrix.Identity(4)
    ob = bpy.data.objects["Arrow"]
    KA = Matrix.Translation((0, AB.bone.length, 0)) @ ob.matrix_parent_inverse @ ob.matrix_basis
    rw, rwi = rig.matrix_world, rig.matrix_world.inverted()
    head = rig.pose.bones[MX + "Head"]
    SBM, A0, BOWM, RIM, fist, nock0, base_q = {}, {}, {}, {}, {}, {}, {}
    for f in range(1, n + 1):
        sc.frame_set(f)
        SBM[f], A0[f], BOWM[f] = SB.matrix.copy(), prop_world("Arrow"), prop_world("Bow")
        RIM[f] = prop_world("Quiver") @ Q_RIM
        fist[f] = A0[f].translation + A0[f].to_3x3().col[2].normalized() * FIST
        nock0[f] = rw @ SBM[f].translation
        base_q[f] = {nm: rig.pose.bones[nm].rotation_quaternion.copy() for nm in RCHAIN}

    # The arrow rest, in the bow's frame (x toward the string, z up the upper limb): the
    # arrow lies level in that frame, from the string anywhere between brace and full draw
    # to the rest, clear of the bow hand and the forearm in every frame from the quiver on.
    top = max(range(1, shot + 1), key=lambda f: fist[f].z)
    under = np.char.startswith(DOM, "LeftHand") | np.char.startswith(DOM, "LeftForeArm")
    Hb = []
    for f in range(top, shot + 1, 2):
        sc.frame_set(f)
        Bi = np.array(BOWM[f].inverted())
        Hb.append(evaluated()[under] @ Bi[:3, :3].T + Bi[:3, 3])
    Hb = np.concatenate(Hb)
    brace = float((BOWM[shot].inverted() @ nock0[shot]).x)

    def clear(N, R):
        dv = R - N
        t = np.clip((Hb - N) @ dv / (dv @ dv), 0.0, ARROW_LEN / np.linalg.norm(dv))
        return np.linalg.norm(Hb - (N + t[:, None] * dv), axis=1).min() >= ARROW_R + 0.002

    B = PROP_NP["Bow"]
    half = float(np.abs(B[(np.abs(B[:, 2]) < 0.05) & (B[:, 0] < B[:, 0].max() - 0.03), 1]).max())
    left = Vector((0, 0, 1)).cross(BOWM[shot].translation - nock0[shot]).normalized()
    side = 1.0 if (BOWM[shot].to_3x3() @ Vector((0, 1, 0))).dot(left) > 0 else -1.0
    y_r = side * (half + ARROW_R + 0.002)
    for z_r in np.arange(0.0, 0.25, 0.002):
        R = np.array([0.0, y_r, z_r])
        if all(clear(np.array([x, 0.0, z_r]), R) for x in np.linspace(brace, DRAW_MAX, 6)):
            break
    z_r = float(z_r)
    REST = Vector((0.0, y_r, z_r))
    REST_W = {f: BOWM[f] @ REST for f in range(1, n + 1)}
    NOCK = {f: nock0[f] + BOWM[f].to_3x3().col[2].normalized() * z_r for f in range(1, n + 1)}
    nockf = min(range(top, shot + 1), key=lambda f: (fist[f] - NOCK[f]).length)
    snap_dir = None

    def smooth(t):
        t = min(1.0, max(0.0, t))
        return t * t * (3 - 2 * t)

    def level(f):
        """How far the fist comes onto the arrow's level: fully from nocking, eased in before."""
        return smooth((f - nockf + LEVEL_EASE) / LEVEL_EASE)

    def fwd():
        return (rw.to_3x3() @ head.matrix.to_3x3().col[2]).normalized()

    def bow_y(f):
        return BOWM[f].to_3x3() @ Vector((0, 1, 0))

    def nocked(f, at):
        return arrow_world(at, REST_W[f] - at, bow_y(f))

    starts = {
        "out of the quiver": lambda f, fi, A: arrow_world(fi, RIM[f] - fi, A.to_3x3().col[1]),
        "up over his shoulder": lambda f, fi, A: arrow_world(fi, Vector((0, 0, 1)) - 0.35 * fwd(), A.to_3x3().col[1]),
        "as in the hand": lambda f, fi, A: A,
        "toward the bow": lambda f, fi, A: nocked(f, fi),
    }

    def place(f, k, how):
        """Pose frame f with the fist k m out to the archer's right; return (arrow's world
        matrix, the string's point, the fist)."""
        sc.frame_set(f)
        SB.matrix_basis = AB.matrix_basis = Matrix.Identity(4)
        pose_set(base_q[f])
        A = prop_world("Arrow")
        fi = A.translation + A.to_3x3().col[2].normalized() * FIST
        move = Vector()
        w = level(f)
        if w:
            lo = BOWM[f].inverted() @ fi
            move = (BOWM[f] @ Vector((lo.x, lo.y, z_r)) - fi) * w
        if k:
            u = (REST_W[f] - fi - move).normalized()
            out = -(rw.to_3x3() @ head.matrix.to_3x3().col[0])
            out -= u * out.dot(u)
            bz = BOWM[f].to_3x3().col[2].normalized()
            bz -= u * bz.dot(u)
            if bz.length > 1e-6:
                out -= bz.normalized() * out.dot(bz.normalized()) * w
            move += out.normalized() * k
        if f >= nockf:
            d = REST_W[f] - fi - move
            if d.length > DRAW_MAX:
                move += d.normalized() * (d.length - DRAW_MAX)
        if move.length:
            reach(rwi.to_3x3() @ move)
            A = prop_world("Arrow")
            fi = A.translation + A.to_3x3().col[2].normalized() * FIST
        if f < nockf:
            at = nock0[f]
        elif f <= shot:
            at = NOCK[f].lerp(fi, smooth((f - nockf + 1) / DRAW_EASE))
        else:
            j = f - shot - 1
            at = NOCK[f] + snap_dir * (STRING_SNAP[j] if j < len(STRING_SNAP) else 0.0)
        SB.matrix_basis = SBM[f].inverted() @ Matrix.Translation(rwi @ at - SBM[f].translation) @ SBM[f]
        if top <= f < nockf:
            w = smooth((f - top) / max(1, nockf - top))
            q = starts[how](f, fi, A).to_quaternion().slerp(nocked(f, fi).to_quaternion(), w)
            z = q.to_matrix().col[2]
            M = arrow_world(fi - z * ARROW_GRIP, z, q.to_matrix().col[1])
        elif nockf <= f <= shot:
            M = nocked(f, at)
        else:
            M = A
        ABM = AB.matrix.copy()
        AB.matrix_basis = ABM.inverted() @ rwi @ M @ KA.inverted()
        bpy.context.view_layer.update()
        return M, at, fi

    def cost(f, M, parts=False):
        """Body triangles through the arrow where it shows (the fist on it left out) and
        through the bow and its string (the bow hand left out, and the fingers on the string
        from TAKE frames before nocking to the shot), and fist triangles into the head; with
        `parts`, those by the bone weighing most on them."""
        P = evaluated()
        bt = BVHTree.FromPolygons([Vector(p) for p in P], TRI.tolist())
        cut = {}
        if top <= f <= shot:
            vs, fs = LOCAL["Arrow"]
            cut["arrow"] = {t for t, _ in overlap_both(bt, BVHTree.FromPolygons([M @ v for v in vs], fs))
                            if not RIGHT_HAND[t]}
        hand = nockf - TAKE <= f <= shot
        cut["bow"] = {t for t, _ in overlap_both(bt, BVHTree.FromPolygons(prop_mesh("Bow"), LOCAL["Bow"][1]))
                      if not (LEFT_HAND[t] or (hand and RIGHT_HAND[t]))}
        ht = BVHTree.FromPolygons([Vector(p) for p in P], TRI[HEAD_TRI].tolist())
        rt = BVHTree.FromPolygons([Vector(p) for p in P], TRI[RIGHT_HAND].tolist())
        fist_in = len(overlap_both(ht, rt))
        if not parts:
            return sum(len(v) for v in cut.values()) + fist_in
        out = {}
        for nm, tris in cut.items():
            for t in tris:
                out.setdefault(nm, {})
                out[nm][str(TRI_BONE[t])] = out[nm].get(str(TRI_BONE[t]), 0) + 1
        if fist_in:
            out["fist in the head"] = fist_in
        return out

    def search(frames, how):
        out = {}
        for f in frames:
            best = None
            for k in np.arange(0.0, LATERAL + 1e-6, 0.01):
                c = cost(f, place(f, float(k), how)[0])
                if best is None or c < best[0]:
                    best = (c, float(k))
                if not c:
                    break
            out[f] = best
        return out

    snap_dir = (place(shot, 0.0, None)[1] - NOCK[shot]).normalized()
    found = search(range(nockf, n + 1), None)
    tried = {}
    for how in starts:
        tried[how] = search(range(top, nockf), how)
        if not sum(c for c, _ in tried[how].values()):
            break
    how = min(tried, key=lambda h: (sum(c for c, _ in tried[h].values()), sum(k for _, k in tried[h].values())))
    found.update(tried[how])
    need = [found[f][1] if f in found else 0.0 for f in range(1, n + 1)]
    lat = widen(need, False) if any(need) else need

    prev, left = {}, {}
    for f in range(1, n + 1):
        M, at, fi = place(f, lat[f - 1], how)
        if top <= f <= shot + len(STRING_SNAP):
            c = cost(f, M, True)
            if c:
                left[f] = c
        for nm in RCHAIN:
            pb = rig.pose.bones[nm]
            qq = pb.rotation_quaternion.copy()
            if nm in prev:
                qq.make_compatible(prev[nm])
            pb.rotation_quaternion = prev[nm] = qq
            pb.keyframe_insert("rotation_quaternion", frame=f)
        key_bone(SB, f)
        qq = AB.rotation_quaternion.copy()
        if "Arrow" in prev:
            qq.make_compatible(prev["Arrow"])
        AB.rotation_quaternion = prev["Arrow"] = qq
        key_bone(AB, f)
        if f == shot:
            info_shot = (at, fi)
    for f, v in ((1, 0), (top - 1, 0), (top, 1), (shot, 1), (shot + 1, 0)):
        rig["arrow"] = v
        rig.keyframe_insert('["arrow"]', frame=f)
    for fc in rig.animation_data.action.layers[0].strips[0].channelbag(rig.animation_data.action_slot).fcurves:
        if fc.data_path in ('["arrow"]',):
            for kp in fc.keyframe_points:
                kp.interpolation = "CONSTANT"

    at, fi = info_shot
    aim = (REST_W[shot] - at).normalized()
    info = {"arrow_from": top, "nocked": nockf, "shot": shot, "pulled_from": how,
            "nock_to_rest_m": round((REST_W[shot] - at).length, 3),
            "string_drawn_m": round((at - NOCK[shot]).length, 3),
            "rest_up_m": round(z_r, 3), "rest_side_m": round(y_r, 3),
            "aim_deg": round(math.degrees(math.asin(max(-1.0, min(1.0, aim.z)))), 1),
            "fist_out_m": [round(x, 3) for x in lat], "still_through": {str(f): c for f, c in left.items()}}
    print("CLIP_SHOT arrow from frame %d (%s), nocked at %d, loosed at %d; %.3f m from the nock to the rest"
          " (the string drawn %.3f m); rest %.3f m up the bow, %.3f m beside it; aimed %.1f deg above level;"
          " the fist out to his right up to %.2f m; still through in %s"
          % (top, how, nockf, shot, info["nock_to_rest_m"], info["string_drawn_m"], z_r, y_r, info["aim_deg"],
             max(lat), left))
    return info


def cape_cuts(P):
    """Body triangles through the cape below the quiver (pairs)."""
    ctree = BVHTree.FromPolygons([Vector(p) for p in P], TRI[LOW_CAPE_TRI].tolist())
    otree = BVHTree.FromPolygons([Vector(p) for p in P], TRI[NOT_CAPE_TRI].tolist())
    return len(overlap_both(ctree, otree))


def correct_cape(clip, n, cyclic):
    """Swing the cape back where a leg goes through it: per frame the cheapest CAPE_GRID pair
    that clears it (the lower cape, Cape2, before the upper one through the rig's
    `cape_back`), each widened and averaged over SMOOTH frames, then raised where it still
    meets him, the lower cape first. Keyed in every frame (at rest where it needs nothing)."""
    def pose(u, lo):
        rig["cape_back"] = math.radians(u)
        rig.update_tag()
        CB.rotation_quaternion = Quaternion((1, 0, 0), math.radians(CAPE_BACK * lo))
        bpy.context.view_layer.update()

    need = []
    for f in range(1, n + 1):
        sc.frame_set(f)
        pose(0, 0)
        c = (0, 0)
        if cape_cuts(evaluated()):
            c = CAPE_GRID[-1]
            for c_ in CAPE_GRID[1:]:
                pose(*c_)
                if not cape_cuts(evaluated()):
                    c = c_
                    break
        need.append(c)
    up, low = ([float(c[i]) for c in need] for i in (0, 1))
    up, low = (widen(v, cyclic) if any(v) else v for v in (up, low))
    for it in range(6):
        left = []
        for f in range(1, n + 1):
            sc.frame_set(f)
            pose(up[f - 1], low[f - 1])
            CB.keyframe_insert("rotation_quaternion", frame=f)
            rig.keyframe_insert('["cape_back"]', frame=f)
            if (up[f - 1] < CAPE_UP[-1] or low[f - 1] < CAPE_LOW[-1]) and cape_cuts(evaluated()):
                left.append(f)
        if not left or it == 5:
            break
        for f in left:
            for g in range(max(1, f - SMOOTH), min(n, f + SMOOTH) + 1):
                t = 5 * (1 - abs(g - f) / (SMOOTH + 1))
                if low[g - 1] < CAPE_LOW[-1]:
                    low[g - 1] = min(CAPE_LOW[-1], low[g - 1] + t)
                else:
                    up[g - 1] = min(CAPE_UP[-1], up[g - 1] + t)
    if any(u or lo for u, lo in need):
        print("CLIP_CAPE_FIX %s: the lower cape swung back in %d of %d frames, up to %.0f deg, the upper one"
              " further in %d, up to %.0f deg; still through in %s"
              % (clip, sum(1 for x in low if x > 0.5), n, max(low), sum(1 for x in up if x > 0.5), max(up), left))
    return {"upper_deg": [round(x, 1) for x in up], "lower_deg": [round(x, 1) for x in low]}


def quiver_basis(c):
    """The `Quiver` bone's own turn for correction c (tip out, swing, lift) about the bottom of its back."""
    b, sw, d = c
    return (Matrix.Translation(Q_PIVOT + Vector((0, 0, d))) @ Matrix.Rotation(math.radians(b), 4, "X")
            @ Matrix.Rotation(math.radians(SWING * sw), 4, "Z") @ Matrix.Translation(-Q_PIVOT))


def quiver_scene(f):
    """At frame f: the quiver bone's pose matrix without its own turn, and a tree of the body
    triangles near the quiver."""
    sc.frame_set(f)
    P = evaluated()
    PM0 = QB.matrix @ QB.matrix_basis.inverted()
    M = np.array(rig.matrix_world @ PM0 @ KQ)
    c, r = PROP_SPHERE["Quiver"]
    near = np.linalg.norm(P - (M[:3, :3] @ c + M[:3, 3]), axis=1) < r + 0.25
    return PM0, BVHTree.FromPolygons(P.tolist(), TRI[near[TRI].any(1)].tolist())


def quiver_hits(scene, c):
    """Body triangles through the quiver with correction c, or 1 if the body comes within QUIVER_MIN."""
    PM0, bt = scene
    Q = pts("Quiver", rig.matrix_world @ PM0 @ quiver_basis(c) @ KQ)
    cuts = len(overlap_both(bt, BVHTree.FromPolygons(Q.tolist(), LOCAL["Quiver"][1])))
    return cuts or int(any(bt.find_nearest(Vector(q), QUIVER_MIN)[0] is not None for q in Q[::4]))


def correct_quiver(clip, n, cyclic):
    """Per frame, the cheapest QGRID turn that keeps the quiver off the body, widened and
    averaged over neighbouring frames, repaired as the arm's, and keyed in every frame."""
    t0, evals = time.time(), 0
    scenes, found = [], []
    for f in range(1, n + 1):
        scenes.append(quiver_scene(f))
        best = None
        for c in QGRID:
            k = quiver_hits(scenes[-1], c)
            evals += 1
            if best is None or k < best[0]:
                best = (k, c)
            if k == 0:
                break
        found.append(best)
    cols = list(zip(*[c for _, c in found]))
    smooth = [list(c) for c in zip(*[widen(list(col), cyclic) for col in cols])]
    if cyclic:
        smooth[-1] = list(smooth[0])
    left = [i + 1 for i, (k, _) in enumerate(found) if k]
    print("CLIP_QUIVER_FIX %s: turned in %d of %d frames, largest %s; best grid point still too close in %d frames %s"
          % (clip, sum(1 for _, c in found if any(c)), n, tuple(round(max(col), 3) for col in cols), len(left), left[:12]))
    for it in range(4):
        fails = [f for f in range(1, n + 1) if quiver_hits(scenes[f - 1], smooth[f - 1])]
        print("CLIP_QUIVER_FIX %s repair %d: still too close %s" % (clip, it, fails))
        if not fails:
            break
        target = {}
        for f in fails:
            for c in sorted(QGRID, key=lambda c: sum(abs(a - b) / k for a, b, k in zip(c, smooth[f - 1], QSCALE))):
                evals += 1
                if not quiver_hits(scenes[f - 1], c):
                    target[f] = c
                    break
        smooth = ramp(smooth, target, cyclic)
    prev = None
    for f in range(1, n + 1):
        QB.matrix_basis = quiver_basis(smooth[f - 1])
        if prev is not None:
            q = QB.rotation_quaternion.copy()
            q.make_compatible(prev)
            QB.rotation_quaternion = q
        prev = QB.rotation_quaternion.copy()
        key_bone(QB, f)
    print("CLIP_QUIVER_FIX %s: %d evaluations in %.0f s" % (clip, evals, time.time() - t0))
    return [[round(x, 3) for x in c] for c in smooth]


report = {}
rig.animation_data_create()
for clip, (fbx, opt) in CLIPS.items():
    before, acts_before = set(bpy.data.objects), set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=str(anim_dir / fbx))
    new_objs = [o for o in bpy.data.objects if o not in before]
    src = next(o for o in new_objs if o.type == "ARMATURE")
    f0, f1 = (int(round(v)) for v in src.animation_data.action.frame_range)
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
    if opt.get("draw"):
        samples += [samples[-1]] * FOLLOW
    n_fr = len(samples)
    drift = samples[-1][1] - samples[0][1] if opt.get("in_place") else Vector()
    drift.z = 0.0
    local = []
    for R, _ in samples:
        Rt, q = {}, {}
        for n in order:
            par = rig.data.bones[n].parent
            pn = par.name if par is not None and par.name in T_rest else None
            Rt[n] = R[n] @ S_rest[n].inverted() @ T_rest[n] if n in R else (
                Rt[pn] @ T_rest[pn].inverted() @ T_rest[n] if pn else T_rest[n])
            basis = T_rest[n].inverted() @ Rt[n] if pn is None else \
                (T_rest[pn].inverted() @ T_rest[n]).inverted() @ Rt[pn].inverted() @ Rt[n]
            q[n] = basis.to_quaternion()
        local.append(q)
    hips_off = [(h - s_hips - drift * (i / max(1, n_fr - 1))) * ratio for i, (_, h) in enumerate(samples)]
    nb = opt.get("loop_blend", 0)
    for k in range(nb):
        i = n_fr - nb + k
        w = (k + 1) / nb
        w = w * w * (3 - 2 * w)
        for n in order:
            a, b = local[i][n], local[0][n].copy()
            b.make_compatible(a)
            local[i][n] = a.slerp(b, w)
        hips_off[i] = hips_off[i].lerp(hips_off[0], w)
    act = bpy.data.actions.new(clip)
    act.use_fake_user = True
    rig.animation_data.action = act
    prev = {}
    hb = rig.pose.bones[MX + "Hips"]
    for i in range(n_fr):
        for n in order:
            pb = rig.pose.bones[n]
            pb.rotation_mode = "QUATERNION"
            qq = local[i][n]
            if n in prev:
                qq.make_compatible(prev[n])
            prev[n] = qq
            pb.rotation_quaternion = qq
            pb.keyframe_insert("rotation_quaternion", frame=i + 1)
        hb.location = T_rest[MX + "Hips"].inverted() @ hips_off[i]
        hb.keyframe_insert("location", frame=i + 1)
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
    HOLD = float(opt.get("hold", 1.0))
    rig["bow_hold"] = HOLD
    RELEASE = find_release(n_fr) if opt.get("drop") else None
    key_hold(n_fr)
    fixes = correct_arm(clip, n_fr, act.use_cyclic)
    if RELEASE is not None:
        drop = drop_bow(n_fr)
        act["bow_release"] = RELEASE
    else:
        drop = None
        BB.matrix_basis = Matrix.Identity(4)
        key_bone(BB, 1)
    shot = None
    if opt.get("draw"):
        shot = draw_bow(n_fr, n_fr - FOLLOW)
        act["shot_frame"] = shot["shot"]
    else:
        # Every clip keys the string and the arrow at rest, the arrow hidden.
        for nm in ("String", "Arrow"):
            pb = rig.pose.bones[nm]
            pb.rotation_mode = "QUATERNION"
            pb.matrix_basis = Matrix.Identity(4)
            key_bone(pb, 1)
        rig["arrow"] = 0
        rig.keyframe_insert('["arrow"]', frame=1)
    quiver_fixes = correct_quiver(clip, n_fr, act.use_cyclic)
    cape_fixes = correct_cape(clip, n_fr, act.use_cyclic)
    if opt.get("in_place"):
        dur = max(1, n_fr - 1) / 30.0
        act["root_vel"] = [drift.x * ratio / dur, drift.y * ratio / dur]
    print("CLIP", clip, fbx, f"{f0}-{f1}", n_fr, "frames (%.2f s), hip ratio %.3f, missing bones %s, in-place drift %.3f m, ground lift up to %.3f m"
          % ((n_fr - 1) / 30, ratio, missing, drift.length * ratio, max(lift)),
          "sole shift %.3f to %.3f m" % (min(lift), max(lift)) if opt.get("sole") else "",
          "seam %.1f deg, hips %.1f cm" % (math.degrees(seam), 100 * seam_hips))

    # Every frame: what cuts through the props and the cape, the quiver's gap, the lowest points.
    rows = []
    for i in range(n_fr):
        sc.frame_set(i + 1)
        P = evaluated()
        btree = BVHTree.FromPolygons([Vector(p) for p in P], TRI.tolist())
        row = {"lowest": round(float(P[:, 2].min()), 4), "hips": [round(c, 3) for c in hb.matrix.translation],
               "props_low": {nm: round(prop_low(nm), 4) for nm in PROPS}}
        for name in PROPS + SHOWN:
            if name in SHOWN and not rig.get("arrow"):
                row[name] = {}
                continue
            M = prop_world(name)
            vs, fs = LOCAL[name]
            ptree = BVHTree.FromPolygons(prop_mesh(name) if name == "Bow" else [M @ v for v in vs], fs)
            tris = {a for a, _ in overlap_both(btree, ptree)}
            if name == "Bow" and (RELEASE is None or i + 1 <= RELEASE + RELEASE_EASE):
                tris = {t for t in tris if not LEFT_HAND[t]}
            if name == "Arrow" or (name == "Bow" and shot and shot["nocked"] - TAKE <= i + 1 <= shot["shot"]):
                tris = {t for t in tris if not RIGHT_HAND[t]}   # the fist on the arrow and the string
            by = {}
            for t in tris:
                by[str(TRI_BONE[t])] = by.get(str(TRI_BONE[t]), 0) + 1
            row[name] = by
            if name == "Quiver":
                c, r = PROP_SPHERE[name]
                Mn = np.array(M)
                near = np.linalg.norm(P - (Mn[:3, :3] @ c + Mn[:3, 3]), axis=1) < r + 0.05
                d = [ptree.find_nearest(Vector(p), 0.05)[3] for p in P[near]]
                d = [x for x in d if x is not None]
                row["quiver_gap_mm"] = round(min(d) * 1000, 1) if d else 50.0
        ctree = BVHTree.FromPolygons([Vector(p) for p in P], TRI[LOW_CAPE_TRI].tolist())
        otree = BVHTree.FromPolygons([Vector(p) for p in P], TRI[NOT_CAPE_TRI].tolist())
        other = np.nonzero(NOT_CAPE_TRI)[0]
        by = {}
        for _, j in overlap_both(ctree, otree):
            b = str(TRI_BONE[other[j]])
            by[b] = by.get(b, 0) + 1
        row["cape"] = by
        rows.append(row)
    scaled = [pb.name for pb in rig.pose.bones if (Vector(pb.scale) - Vector((1, 1, 1))).length > 1e-5]
    assert not scaled, ("bones left scaled", scaled)
    report[clip] = {"source": fbx, "frames": n_fr, "rows": rows, "fixes": fixes, "quiver_fixes": quiver_fixes,
                    "drop": drop, "shot": shot, "cape_fixes": cape_fixes, "lift": [round(x, 4) for x in lift],
                    "seam_deg": round(math.degrees(seam), 2), "seam_hips_cm": round(100 * seam_hips, 2),
                    "root_vel": list(act.get("root_vel", [0.0, 0.0]))}
    low = [r["lowest"] for r in rows]
    print("CLIP_GROUND", clip, "lowest point from %.3f to %.3f m; props' lowest %s" % (
        min(low), max(low), {nm: round(min(r["props_low"][nm] for r in rows), 3) for nm in PROPS}))
    gaps = [r["quiver_gap_mm"] for r in rows]
    print("CLIP_QUIVER %s: nearest the body %.1f mm (frame %d), %.1f mm at the median" % (
        clip, min(gaps), int(np.argmin(gaps)) + 1, float(np.median(gaps))))
    for name in PROPS + SHOWN + ("cape",):
        hit = [(i + 1, sum(r[name].values()), r[name]) for i, r in enumerate(rows) if r[name]]
        if hit:
            worst = max(hit, key=lambda h: h[1])
            bones = {}
            for _, _, by in hit:
                for b, c in by.items():
                    bones[b] = max(bones.get(b, 0), c)
            print("CLIP_PROP %s %s: through it in %d of %d frames (%s to %s); worst frame %d, %d triangles %s; bones %s"
                  % (clip, name, len(hit), n_fr, hit[0][0], hit[-1][0], worst[0], worst[1], worst[2], bones))
        else:
            print("CLIP_PROP %s %s: clear in all %d frames" % (clip, name, n_fr))

out_json.write_text(json.dumps(report), encoding="utf-8")
rig.animation_data.action = bpy.data.actions["idle"]
rig.animation_data.action_slot = bpy.data.actions["idle"].slots[0]
sc.frame_start, sc.frame_end = 1, report["idle"]["frames"]
sc.frame_set(1)
for screen in bpy.data.screens:
    for area in screen.areas:
        for space in area.spaces:
            if space.type == "FILE_BROWSER" and space.params is not None:
                space.params.directory = b"//" + b"_" * 700
                space.params.directory = b"//"
bpy.ops.wm.save_as_mainfile(filepath=str(out_blend), relative_remap=True, compress=True)
print("CLIPS_SAVED", out_blend)
