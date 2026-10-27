"""Review only: retarget the orc brute's Mixamo clips onto OrcBruteRig, keep the club clear of
the body, measure every frame and save a scratch copy with the clips (Mixamo motion stays out
of the repo).

  blender -b orc_brute_rig.blend --python retarget_clips.py -- <animations dir> <out.blend> <measure.json>
  blender -b orc_brute_dual_rig.blend --python retarget_clips.py -- <animations dir> <out.blend> <measure.json>

Retarget as goblin_rabble/tools/retarget_clips.py (rest-pose difference, bone by bone, in
world space; the hips' motion scaled by the hip-height ratio), keying only the Mixamo body
bones: the fingers keep the grip actions. What he carries follows the rig's loadout (CARRY,
rig_orc_brute.py; the user, 26 October 2026). orc_brute_rig.blend (`club_knife`): the club
alone; the rig still has the knife and its grip for the left fist, but the saved copy drops
the Knife object and the left hand keeps the knife's grip at EMPTY_GRIP, an empty,
half-closed hand, its arm corrected to keep the hand out of the body (below).
orc_brute_dual_rig.blend (`dual`): a club in each fist, each arm corrected for its own.
Options per clip:
  in_place   remove the drift between the first and last frame (its speed is kept as the
             action's root_vel, m/s in Blender x and y)
  loop       the clip loops (its corrections are smoothed round the seam); where its last
             frame does not match its first, the last LOOP_FIX frames are eased into it
  loop_blend ease the last N frames back into the first pose (a loop)
  ground     lift the hips wherever the skinned body dips below the floor (the soles may
             sink FOOT_SINK), widened and averaged so the lift never pops
  sole       raise or lower the hips so the lowest point of the soles stays at its rest
             height, averaged over SOLE_W frames either side (round the seam of a loop)
  drop       a death: each weapon's hand lets go of it as the archer's of the bow
             (goblin_archer/tools/retarget_clips.py), at the latest frame, at most RELEASE_LEAD
             frames before the weapon in the fist would come within RELEASE_NEAR of the
             ground (his fists stop a few centimetres short of it) and RELEASE_SEARCH
             frames earlier than that, from which it falls clear of him: the hand opens to
             GRIP_DEAD over RELEASE_EASE frames (the grip's influence is keyed), and the
             weapon's bone is keyed so the weapon turns onto its flat (its local y up or down)
             about its lowest point, which drops to the ground, in the time its middle would
             take to fall there; it comes to rest with both ends on the ground (tipped about
             the line across it), WEAPON_REST above it. The side it lands on, its spin and how
             far it is pushed from the body are the first that keep it clear of the body, and
             of any weapon dropped before it, in every later frame. The releases are planned
             before the arms are corrected (below), so a weapon let go is left to its fall; one
             the fist brings near the ground only once the arms are corrected (the dual
             brute's left club: his arm holds it up as made) is planned from there and the
             arms corrected again from the clip as made
The clips were made for empty hands on a slimmer body, so each frame gets the smallest
correction of each arm that keeps its weapon clear of the body (its own hand left out), of
any other weapon while both are held, and WEAPON_GROUND above the ground, and the hand
itself, empty or holding, clear of the body (its own forearm left out; the brute's thighs
and belly stand in the way of Mixamo's hanging arms), and the arm no more than FOOT_SINK
below the floor (a correction must not push a fallen arm into the ground; in a death the
fist is keyed open after its release before the arms are corrected): the collarbone, the upper arm, the forearm and the hand eased toward the standard
pose (the rig's `stand`), then the elbow bent and the arm lifted out from the chest on the
full ease, tried only after every ease. Each correction is widened and averaged over
neighbouring frames (round the seam of a loop); a frame still through then gets the nearest
clear grid point, kept in the later rounds, its neighbours ramped into it over SMOOTH
frames. Every clip keys the
weapons' bones and the grips' influence in its first frame, so switching clips leaves
nothing behind.
Per frame and per weapon: body triangles that cut through it (exact triangle overlap, both
trees each way round), by the bone weighing most on them, its own hand left out while it
holds the weapon; triangles of two weapons that cut each other; the body's and the
weapons' lowest points. Per frame and per hand, empty or holding: body triangles through the
hand (its own forearm left out).
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
WEAPON_GROUND = 0.01  # a weapon in the fist stays this far above the ground
REPAIRS = 10         # rounds of the repair below at most
RELEASE_NEAR = 0.10  # a dying hand lets go as its weapon comes this near the ground (his fists stop short of it)
RELEASE_LEAD = 4     # frames: a hand lets go at least this long before then
RELEASE_SEARCH = 12  # and at most this many frames earlier
RELEASE_EASE = 6     # frames over which the hand opens
GRIP_DEAD = 0.4      # the grip's influence on the open hand
WEAPON_REST = 0.002  # a dropped weapon lies this far above the ground
G = 9.81
CLIPS = {
    "idle": ("Orc - Idle.fbx", {"in_place": True, "loop_blend": 10}),
    "walk": ("Orc - Walk.fbx", {"in_place": True, "loop": True, "sole": True}),
    "attack": ("Attack - Orc brute.fbx", {"sole": True}),
    "death": ("Orc - Death.fbx", {"ground": True, "drop": True}),
}
# Per loadout of the rig: each weapon he carries, the side whose fist holds it; and each grip
# of the rig with no weapon in it, the side it closes, held at EMPTY_GRIP (1 closes it round
# the weapon it was solved on).
CARRY = {"club_knife": ({"Club": "Right"}, {"Knife": "Left"}),
         "dual": ({"Club": "Right", "ClubLeft": "Left"}, {})}
EMPTY_GRIP = 0.7

argv = sys.argv[sys.argv.index("--") + 1:]
anim_dir, out_blend, out_json = Path(argv[0]), Path(argv[1]), Path(argv[2])
sc = bpy.context.scene
sc.render.fps = 30
rig = bpy.data.objects["OrcBruteRig"]
body = bpy.data.objects["OrcBrute"]
LOADOUT = rig.get("loadout", "club_knife")
WEAPONS, EMPTY = CARRY[LOADOUT]
print("CLIPS_LOADOUT", LOADOUT, WEAPONS, "empty", EMPTY)
me = body.data
MX = "mixamorig:"
FING = ("Thumb", "Index", "Middle", "Ring", "Pinky")
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
HAND = {s: np.array([b.startswith(s + "Hand") for b in TRI_BONE]) for s in ("Right", "Left")}
rest_z = np.array([v.co.z for v in me.vertices])
floor = np.where(rest_z < FOOT_Z, -FOOT_SINK, 0.0)
SOLE = rest_z < FOOT_Z
LOCAL, PROP_NP, PROP_BVH, PROP_SPHERE = {}, {}, {}, {}
for name in WEAPONS:
    ob = bpy.data.objects[name]
    vs, fs = [v.co.copy() for v in ob.data.vertices], [list(p.vertices) for p in ob.data.polygons]
    LOCAL[name] = (vs, fs)
    A = np.array([tuple(v) for v in vs])
    c = (A.min(0) + A.max(0)) / 2
    PROP_NP[name], PROP_BVH[name] = A, BVHTree.FromPolygons(vs, fs)
    PROP_SPHERE[name] = (c, float(np.linalg.norm(A - c, axis=1).max()))
print("CLIPS_MESH body %d vertices, %d triangles; weapons %s" % (len(me.vertices), len(TRI), {n: len(LOCAL[n][1]) for n in WEAPONS}))

PB = rig.pose.bones
WB = {name: PB[bpy.data.objects[name].parent_bone] for name in WEAPONS}
assert all(WB[n].name == n and WB[n].parent.name == MX + s + "Hand" for n, s in WEAPONS.items()), WB
GRIPS = {name: [c for pb in PB for c in pb.constraints if c.type == "ACTION" and c.name == "grip_" + name.lower()]
         for name in list(WEAPONS) + list(EMPTY)}
assert all(len(g) == 15 for g in GRIPS.values()), {n: len(g) for n, g in GRIPS.items()}
assert all(rig[p] == 0 for p in rig.keys() if p.endswith("_ik"))

# The arm corrections. The orc faces -y, so his left is +x.
assert rig.data.bones[MX + "LeftArm"].head_local.x > 0
CHEST = MX + "Spine2"
SIDES = {}
for name, side in list(WEAPONS.items()) + [(None, s) for s in EMPTY.values()]:
    lat = Vector((1 if side == "Left" else -1, 0, 0))
    SIDES[side] = {"weapon": name, "chain": tuple(MX + side + p for p in ("Shoulder", "Arm", "ForeArm", "Hand")),
                   "lat_chest": rig.data.bones[CHEST].matrix_local.to_3x3().inverted() @ lat}
# A hand and its own forearm, left out of what may cut through the hand; the vertices of
# each arm, collarbone to fingertips.
OWN = {s: HAND[s] | np.array([b.startswith(s + "ForeArm") for b in TRI_BONE]) for s in ("Right", "Left")}
ARM_V = {s: np.array([d.startswith(tuple(s + p for p in ("Shoulder", "Arm", "ForeArm", "Hand"))) for d in DOM])
         for s in ("Right", "Left")}
# (collarbone, upper arm, forearm and hand eased toward the standard pose, elbow bent by
# degrees, arm lifted out by degrees): every ease first, then the bends and lifts on the full ease.
GRID = [(w, 0, 0) for w in (0, .2, .4, .6, .8, 1)] + sorted(
    ((1, a, p) for a in (0, 15, 30, 45, 60, 75) for p in (0, 10, 20, 30, 40, 50) if a or p),
    key=lambda c: c[1] / 25 + c[2] / 20)
SCALE = (1, 25, 20)
# The standard pose: the rig is saved with its `stand` action on.
assert rig.animation_data.action.name == "stand", rig.animation_data.action
sc.frame_set(1)
STAND_Q = {n: PB[n].matrix_basis.to_quaternion() for s in SIDES.values() for n in s["chain"]}
assert any(q.angle > 0.05 for q in STAND_Q.values())
RELEASE = {}         # the frame each weapon is let go in the clip being made


def evaluated():
    ev = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    m = ev.to_mesh()
    co = np.empty(len(m.vertices) * 3)
    m.vertices.foreach_get("co", co)
    ev.to_mesh_clear()
    return co.reshape(-1, 3) @ np.array(body.matrix_world.to_3x3()).T + np.array(body.matrix_world.translation)


def prop_world(name):
    """The weapon's world matrix from its bone's pose."""
    ob = bpy.data.objects[name]
    pb = PB[ob.parent_bone]
    return rig.matrix_world @ pb.matrix @ Matrix.Translation((0, pb.bone.length, 0)) @ ob.matrix_parent_inverse @ ob.matrix_basis


def pts(name, M):
    Mn = np.array(M)
    return PROP_NP[name] @ Mn[:3, :3].T + Mn[:3, 3]


def prop_low(name):
    return float(pts(name, prop_world(name))[:, 2].min())


def overlap_both(a, b):
    """Index pairs (a's, b's) of overlapping triangles, each tree tested against the other:
    one tree's long thin triangles can escape the test the other way round."""
    return {(i, j) for i, j in a.overlap(b)} | {(i, j) for j, i in b.overlap(a)}


def cuts(name, P, M, skip_hand):
    """Body triangles through the weapon at world matrix M (its own hand left out while it
    holds the weapon), counted near it only (fast; the final measure below is the exact one)."""
    M = np.array(M)
    c, r = PROP_SPHERE[name]
    near = np.linalg.norm(P - (M[:3, :3] @ c + M[:3, 3]), axis=1) < r + 0.06
    tm = near[TRI].any(1)
    if skip_hand:
        tm &= ~HAND[WEAPONS[name]]
    if not tm.any():
        return 0
    sub = TRI[tm]
    idx = np.unique(sub)
    remap = np.full(len(P), -1)
    remap[idx] = np.arange(len(idx))
    Mi = np.linalg.inv(M)
    bt = BVHTree.FromPolygons((P[idx] @ Mi[:3, :3].T + Mi[:3, 3]).tolist(), remap[sub].tolist())
    return len({a for a, _ in overlap_both(bt, PROP_BVH[name])})


def held(name, f):
    return name not in RELEASE or f <= RELEASE[name]


def crossed(name):
    """Triangle pairs of two weapons through each other while both fists hold them."""
    other = next((m for m in WEAPONS if m != name), None)
    if other is None:
        return 0
    f = sc.frame_current
    if not (held(name, f) and held(other, f)):
        return 0
    M = prop_world(name).inverted() @ prop_world(other)
    (c, r), (co, ro) = PROP_SPHERE[name], PROP_SPHERE[other]
    if (M @ Vector(co) - Vector(c)).length > r + ro:
        return 0
    return len(overlap_both(PROP_BVH[name], BVHTree.FromPolygons([M @ v for v in LOCAL[other][0]], LOCAL[other][1])))


def sub_tree(P, tris):
    idx = np.unique(tris)
    remap = np.full(len(P), -1)
    remap[idx] = np.arange(len(idx))
    return BVHTree.FromPolygons(P[idx].tolist(), remap[tris].tolist())


def hand_cuts(P, side, near_only=True):
    """Body triangles through the side's hand, its own forearm left out; near_only counts only
    those near the hand (fast; the final measure below takes them all)."""
    hand = TRI[HAND[side]]
    tm = ~OWN[side]
    if near_only:
        hv = P[np.unique(hand)]
        c = (hv.min(0) + hv.max(0)) / 2
        near = np.linalg.norm(P - c, axis=1) < float(np.linalg.norm(hv - c, axis=1).max()) + 0.06
        tm &= near[TRI].any(1)
    if not tm.any():
        return {}
    ids = np.nonzero(tm)[0]
    by = {}
    for t in {j for _, j in overlap_both(sub_tree(P, hand), sub_tree(P, TRI[ids]))}:
        b = str(TRI_BONE[ids[t]])
        by[b] = by.get(b, 0) + 1
    return by


def through(P, side):
    """Body triangles through the side's weapon, the other weapon's through it while both are
    held, and 100 more if it dips into the ground (nothing once the hand has let go of it: its
    fall is keyed then); body triangles through the hand, empty or holding; and 100 more if
    the arm dips more than FOOT_SINK into the ground."""
    k = sum(hand_cuts(P, side).values()) + (100 if P[ARM_V[side], 2].min() < -FOOT_SINK else 0)
    name = SIDES[side]["weapon"]
    if name is None or not held(name, sc.frame_current):
        return k
    return k + (0 if prop_low(name) >= WEAPON_GROUND else 100) + cuts(name, P, prop_world(name), True) + crossed(name)


def base_pose(side):
    chain = SIDES[side]["chain"]
    q = {n: PB[n].rotation_quaternion.copy() for n in chain}
    lat = (PB[CHEST].matrix.to_3x3().normalized() @ SIDES[side]["lat_chest"]).normalized()
    return q, lat


def eased(q, n, w):
    s = STAND_Q[n].copy()
    s.make_compatible(q)
    return q.slerp(s, w)


def pose_set(vals):
    for n, qq in vals.items():
        PB[n].rotation_quaternion = qq
    bpy.context.view_layer.update()


def corrected(side, base, c):
    """The arm chain's local rotations with correction c: the chain eased by w toward the
    standard pose; a world turn R of a bone (about its head) is the local turn W^-1 R W, the
    elbow and lift turns taken from the eased pose's directions."""
    _, arm, fore, _ = chain = SIDES[side]["chain"]
    q, lat = base
    w, a, p = c
    out = {n: eased(q[n], n, w) for n in chain}
    if not (a or p):
        return out
    pose_set(out)
    We = {n: PB[n].matrix.to_3x3().normalized() for n in (arm, fore)}
    ad = (PB[arm].tail - PB[arm].head).normalized()
    fd = (PB[fore].tail - PB[fore].head).normalized()
    ang, axis = min(math.radians(a), max(0.0, math.radians(145) - fd.angle(ad))), ad.cross(fd)
    if ang > 0 and axis.length > 1e-4:     # bent, never past 145 degrees
        out[fore] = out[fore] @ (We[fore].inverted() @ Matrix.Rotation(ang, 3, axis.normalized()) @ We[fore]).to_quaternion()
    ang, axis = min(math.radians(p), ad.angle(lat)), ad.cross(lat)
    if ang > 0 and axis.length > 0.2:
        out[arm] = out[arm] @ (We[arm].inverted() @ Matrix.Rotation(ang, 3, axis.normalized()) @ We[arm]).to_quaternion()
    return out


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


def correct_arms(clip, n, cyclic):
    t0, evals = time.time(), 0
    found, bases = {s: [] for s in SIDES}, {s: [] for s in SIDES}
    for f in range(1, n + 1):
        sc.frame_set(f)
        for side in SIDES:
            base = base_pose(side)
            bases[side].append(base)
            best = None
            for c in GRID:
                pose_set(corrected(side, base, c))
                k = through(evaluated(), side)
                evals += 1
                if best is None or k < best[0]:
                    best = (k, c)
                if k == 0:
                    break
            pose_set(base[0])
            found[side].append(best)
    smooth = {}
    for side in SIDES:
        cols = list(zip(*[c for _, c in found[side]]))
        smooth[side] = [list(c) for c in zip(*[widen(list(col), cyclic) for col in cols])]
        if cyclic:
            smooth[side][-1] = list(smooth[side][0])
        left = [i + 1 for i, (k, _) in enumerate(found[side]) if k]
        print("CLIP_FIX %s %s: corrected %d of %d frames, largest %s; best grid point still through in %d frames %s"
              % (clip, side, sum(1 for _, c in found[side] if any(c)), n,
                 tuple(round(max(col), 2) for col in cols), len(left), left[:12]))

    def key_all():
        prev = {}
        for f in range(1, n + 1):
            sc.frame_set(f)
            vals = {}
            for side in SIDES:
                vals.update(corrected(side, bases[side][f - 1], smooth[side][f - 1]))
            for nm, qq in vals.items():
                if nm in prev:
                    qq.make_compatible(prev[nm])
                prev[nm] = qq
                PB[nm].rotation_quaternion = qq
                PB[nm].keyframe_insert("rotation_quaternion", frame=f)

    key_all()
    # Where the widened corrections still meet the body (the other arm's correction counts
    # now), give the frame the nearest clear grid point and ramp its neighbours into it over
    # SMOOTH frames, until every frame is clear. A frame given its point keeps it in the later
    # rounds (the ramps start again from the widened corrections), so a run of failing
    # neighbours cannot trade the failure back and forth.
    widened = {s: [list(c) for c in smooth[s]] for s in SIDES}
    pinned = {s: {} for s in SIDES}
    for it in range(REPAIRS):
        fails = {}
        for f in range(1, n + 1):
            sc.frame_set(f)
            P = evaluated()
            for side in SIDES:
                if through(P, side):
                    fails.setdefault(side, []).append(f)
        print("CLIP_FIX %s repair %d: still through %s" % (clip, it, fails))
        if not fails:
            break
        for side, fs in fails.items():
            for f in fs:
                sc.frame_set(f)
                cur = smooth[side][f - 1]
                for c in sorted(GRID, key=lambda c: sum(abs(a - b) / k for a, b, k in zip(c, cur, SCALE))):
                    pose_set(corrected(side, bases[side][f - 1], c))
                    evals += 1
                    if not through(evaluated(), side):
                        pinned[side][f] = c
                        break
            smooth[side] = ramp(widened[side], pinned[side], cyclic)
        key_all()
    print("CLIP_FIX %s: %d evaluations in %.0f s" % (clip, evals, time.time() - t0))
    return {s: [[round(x, 3) for x in c] for c in smooth[s]] for s in SIDES}


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


def smoothstep(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def let_go(name, f):
    """0 while the hand holds the weapon, easing to 1 over RELEASE_EASE frames once it lets go."""
    if held(name, f):
        return 0.0
    return smoothstep((f - RELEASE[name]) / RELEASE_EASE)


def key_bone(pb, f):
    pb.keyframe_insert("location", frame=f)
    pb.keyframe_insert("rotation_quaternion", frame=f)


def key_grip(name, n):
    """Key the grip's influence: closed while the hand holds the weapon, then opening to GRIP_DEAD."""
    for f in range(1, n + 1) if name in RELEASE else (1,):
        for c in GRIPS[name]:
            c.influence = 1 - (1 - GRIP_DEAD) * let_go(name, f)
            c.keyframe_insert("influence", frame=f)


def key_rest(name):
    pb = WB[name]
    pb.rotation_mode = "QUATERNION"
    pb.matrix_basis = Matrix.Identity(4)
    key_bone(pb, 1)


def find_release(name, n):
    """The frame the hand lets go: RELEASE_LEAD frames before the weapon in it would first come
    within RELEASE_NEAR of the ground (None if it never does)."""
    for f in range(1, n + 1):
        sc.frame_set(f)
        if prop_low(name) < RELEASE_NEAR:
            return max(2, f - RELEASE_LEAD)
    return None


def fall(name, n, other):
    """The weapon's fall from its release: it turns onto its flat about its lowest point, which
    drops to the ground, in the time its middle would take to fall freely there (the turn eased
    in as the fall), keeping the hand's speed along the ground and slowing to a stop; it ends
    tipped so both its ends lie on the ground, WEAPON_REST above it, and stays. The side it
    lands on, its spin and how far it is pushed from the body are the first that keep it clear
    of the body in every frame after the release (the open hand counted once RELEASE_EASE frames
    are past) and of `other` (the weapon dropped before it, or the one still in the other fist:
    its name and its world matrix per frame).
    Returns (triangles through it, its description, its world matrix per frame)."""
    r0 = RELEASE[name]
    sc.frame_set(r0 - 1)
    o_prev = prop_world(name).translation.copy()
    sc.frame_set(r0)
    M0 = prop_world(name)
    P0 = pts(name, M0)
    low = Vector(P0[np.argmin(P0[:, 2])].tolist())
    vel = M0.translation - o_prev
    vel.z = 0.0
    normal = (M0.to_3x3() @ Vector((0, 1, 0))).normalized()
    mid = float((P0[:, 2].min() + P0[:, 2].max()) / 2)
    T = max(3, math.ceil(30 * math.sqrt(2 * mid / G)))
    frames = range(r0 + 1, n + 1)
    bodies = {}
    for f in frames:
        sc.frame_set(f)
        bodies[f] = evaluated()
    loc_z = PROP_NP[name][:, 2]
    # Its two ends: the quarter of its length at either end (not halves by vertex count: the
    # club's spiked head holds most of its vertices).
    z0, z1 = float(loc_z.min()), float(loc_z.max())
    ends = (loc_z < z0 + 0.25 * (z1 - z0), loc_z > z1 - 0.25 * (z1 - z0))

    def flat(up):
        """The turn that puts the weapon on its flat (local y along `up`), then tips it about the
        line across it until both ends touch."""
        R = normal.rotation_difference(up).to_matrix()
        Q = pts(name, R.to_4x4() @ M0)
        axis = R @ M0.to_3x3() @ Vector((0, 0, 1))
        across = axis.cross(Vector((0, 0, 1)))
        if across.length < 1e-4:
            return R
        across.normalize()
        a_lo = Q[ends[0]][np.argmin(Q[ends[0], 2])]
        a_hi = Q[ends[1]][np.argmin(Q[ends[1], 2])]
        run = float(np.dot(a_hi - a_lo, np.array(axis.normalized())))
        # A positive turn about `across` (axis x Z) raises the upper end: lower it by its rise.
        tip = -math.atan2(float(a_hi[2] - a_lo[2]), run)
        for _ in range(3):      # the lowest points move as it tips: settle
            Rt = Matrix.Rotation(tip, 3, across) @ R
            Q = pts(name, Rt.to_4x4() @ M0)
            dz = float(Q[ends[1], 2].min() - Q[ends[0], 2].min())
            if abs(dz) < 1e-4:
                break
            tip -= math.atan2(dz, abs(run))
        return Matrix.Rotation(tip, 3, across) @ R

    def world(t, Rl, extra, spin=0.0):
        s = min(1.0, (t / T) ** 2)
        R = Matrix.Rotation(math.radians(spin) * s, 4, "Z") @ \
            Quaternion().slerp(Rl.to_quaternion(), s).to_matrix().to_4x4()
        u = min(t, T)
        piv = Vector((low.x, low.y, max(0.0, low.z - 0.5 * G * (t / 30) ** 2)))
        piv += vel * (u - u * u / (2 * T)) + extra * (u / T)
        M = Matrix.Translation(piv) @ R @ Matrix.Translation(-low) @ M0
        z = float(pts(name, M)[:, 2].min())
        return Matrix.Translation((0, 0, WEAPON_REST - z if t >= T else max(0.0, WEAPON_REST - z))) @ M

    side = Vector((0, 0, 1.0 if normal.z >= 0 else -1.0))
    lands = {1: flat(side), -1: flat(-side)}
    land = pts(name, world(T, lands[1], Vector()))
    away = Vector((*(land.mean(0)[:2] - bodies[n].mean(0)[:2]), 0.0)).normalized()
    otree = {f: BVHTree.FromPolygons([M @ v for v in LOCAL[other[0]][0]], LOCAL[other[0]][1])
             for f, M in other[1].items()} if other else {}
    best = None
    ways = sorted(((k, a, u, sp) for k in range(9) for a in ((0,) if k == 0 else (0, 45, -45))
                   for u in (1, -1) for sp in (0, 30, -30, 60, -60)),
                  key=lambda c: c[0] + (c[1] != 0) * 0.5 + (c[2] != 1) * 0.25 + abs(c[3]) / 30)
    for k, ang, u, sp in ways:
        push = Matrix.Rotation(math.radians(ang), 3, "Z") @ away * (0.05 * k)
        Ms = {f: world(f - r0, lands[u], push, sp) for f in frames}
        hits = sum(cuts(name, bodies[f], Ms[f], f <= r0 + RELEASE_EASE) for f in frames)
        for f, ot in otree.items():
            if f in Ms:
                hits += len(overlap_both(BVHTree.FromPolygons([Ms[f] @ v for v in LOCAL[name][0]], LOCAL[name][1]), ot))
        if best is None or hits < best[0]:
            best = (hits, k, ang, u, sp, Ms)
        if not hits:
            break
    hits, k, ang, u, sp, Ms = best
    info = {"release": r0, "lies_from": r0 + T, "let_go_lowest_m": round(low.z, 3),
            "turn_deg": round(math.degrees(Quaternion().rotation_difference(lands[u].to_quaternion()).angle), 1),
            "turned_over": u != 1, "pushed_m": round(0.05 * k, 2), "push_turn_deg": ang, "spin_deg": sp, "cuts": hits}
    ax = (lands[u] @ M0.to_3x3() @ Vector((0, 0, 1))).normalized()
    info["tilt_deg"] = round(math.degrees(math.asin(max(-1.0, min(1.0, ax.z)))), 1)
    return hits, info, Ms


def key_fall(name, n, info, Ms):
    """Key the weapon's bone to the fall's world matrices (at rest up to the release)."""
    r0 = RELEASE[name]
    pb = WB[name]
    ob = bpy.data.objects[name]
    K = Matrix.Translation((0, pb.bone.length, 0)) @ ob.matrix_parent_inverse @ ob.matrix_basis
    pb.rotation_mode = "QUATERNION"
    pb.matrix_basis = Matrix.Identity(4)
    key_bone(pb, 1)
    key_bone(pb, r0)
    prev = pb.rotation_quaternion.copy()
    for f in range(r0 + 1, n + 1):
        sc.frame_set(f)
        pb.matrix = rig.matrix_world.inverted() @ Ms[f] @ K.inverted()
        q = pb.rotation_quaternion.copy()
        q.make_compatible(prev)
        pb.rotation_quaternion = q
        prev = q
        key_bone(pb, f)
    err = 0.0
    for f in range(r0 + 1, n + 1):
        sc.frame_set(f)
        err = max(err, float(np.abs(np.array(prop_world(name)) - np.array(Ms[f])).max()))
    assert err < 1e-4, (name, err)
    print("CLIP_DROP %s let go at frame %d (lowest point %.3f m up), turns %.0f deg and lies from frame %d%s,"
          " %.1f deg off level, spun %d deg, pushed %.2f m from the body; triangles through it after the release: %d"
          % (name, r0, info["let_go_lowest_m"], info["turn_deg"], info["lies_from"],
             " turned over" if info["turned_over"] else "", info["tilt_deg"], info["spin_deg"], info["pushed_m"],
             info["cuts"]))
    assert abs(info["tilt_deg"]) < 20, (name, info["tilt_deg"])


def drop(n):
    """Each hand lets go of its weapon, the first to near the ground first: at the latest frame
    from its release back RELEASE_SEARCH frames from which it falls clear (re-keying the grip),
    or where the fewest triangles meet it, and its fall is keyed."""
    latest = {name: find_release(name, n) or RELEASE.get(name) for name in WEAPONS}
    out, other = {}, None
    for name in sorted((m for m in WEAPONS if latest[m] is not None), key=lambda m: latest[m]):
        if other is None:
            # The first to drop falls clear of any other weapon still in its fist (up to the
            # latest that fist could let go; its own fall is checked against this one's).
            o = next((m for m in WEAPONS if m != name), None)
            path = {}
            for f in range(1, (latest[o] or n) + 1 if o else 1):
                sc.frame_set(f)
                path[f] = prop_world(o)
            first = (o, path) if o else None
        tried = []
        for r in range(latest[name], max(1, latest[name] - RELEASE_SEARCH) - 1, -1):
            RELEASE[name] = r
            key_grip(name, n)
            tried.append(fall(name, n, other or first))
            if not tried[-1][0]:
                break
        hits, info, Ms = min(tried, key=lambda t: (t[0], -t[1]["release"]))
        RELEASE[name] = info["release"]
        key_grip(name, n)
        key_fall(name, n, info, Ms)
        out[name] = info
        other = (name, Ms)
    for name in WEAPONS:
        if latest[name] is None:
            print("CLIP_DROP %s: never nears the ground, held throughout" % name)
            key_rest(name)
    return out


def plan_release(clip, n):
    """Each weapon not yet planned is let go RELEASE_LEAD frames before it nears the ground (its
    grip keyed open from then), so the arm corrections leave it alone once dropped; drop()
    then settles the release."""
    for name in WEAPONS:
        if name not in RELEASE:
            r = find_release(name, n)
            if r is not None:
                RELEASE[name] = r
                key_grip(name, n)
    print("CLIP_RELEASE_PLAN %s: %s" % (clip, {nm: RELEASE.get(nm) for nm in WEAPONS}))


report = {}
rig.animation_data_create()
for clip, (fbx, opt) in CLIPS.items():
    RELEASE.clear()
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
    # Every clip keys the weapons' bones at rest and the grips closed in its first frame, the
    # empty grips at EMPTY_GRIP.
    for name in WEAPONS:
        key_rest(name)
        key_grip(name, n_fr)
    for name in EMPTY:
        for c in GRIPS[name]:
            c.influence = EMPTY_GRIP
            c.keyframe_insert("influence", frame=1)
    if opt.get("drop"):
        plan_release(clip, n_fr)
    fixes = correct_arms(clip, n_fr, act.use_cyclic)
    if opt.get("drop") and len(RELEASE) < len(WEAPONS):
        # A weapon the fist never brings near the ground in the clip as made (his arm holds it
        # up) may near it once the arms are corrected; then the arms are corrected again from
        # the clip as made with that release.
        planned = len(RELEASE)
        plan_release(clip, n_fr)
        if len(RELEASE) > planned:
            for side in SIDES:
                for nm in SIDES[side]["chain"]:
                    prev = None
                    for i in range(n_fr):
                        qq = local[i][nm].copy()
                        if prev is not None:
                            qq.make_compatible(prev)
                        prev = qq
                        PB[nm].rotation_quaternion = qq
                        PB[nm].keyframe_insert("rotation_quaternion", frame=i + 1)
            fixes = correct_arms(clip, n_fr, act.use_cyclic)
    drops = drop(n_fr) if opt.get("drop") else None
    for name, info in (drops or {}).items():
        act[name.lower() + "_release"] = info["release"]
    if opt.get("in_place"):
        dur = max(1, n_fr - 1) / 30.0
        act["root_vel"] = [drift.x * ratio / dur, drift.y * ratio / dur]
    print("CLIP", clip, fbx, f"{f0}-{f1}", n_fr, "frames (%.2f s), hip ratio %.3f, missing bones %s, in-place drift %.3f m, ground lift up to %.3f m"
          % ((n_fr - 1) / 30, ratio, missing, drift.length * ratio, max(lift)),
          "sole shift %.3f to %.3f m" % (min(lift), max(lift)) if opt.get("sole") else "",
          "seam %.1f deg, hips %.1f cm" % (math.degrees(seam), 100 * seam_hips))

    # Every frame: what cuts through the weapons, the weapons through each other, the lowest points.
    rows = []
    for i in range(n_fr):
        sc.frame_set(i + 1)
        P = evaluated()
        btree = BVHTree.FromPolygons([Vector(p) for p in P], TRI.tolist())
        row = {"lowest": round(float(P[:, 2].min()), 4), "hips": [round(c, 3) for c in hb.matrix.translation],
               "props_low": {nm: round(prop_low(nm), 4) for nm in WEAPONS}}
        ptrees = {}
        for name, side in WEAPONS.items():
            M = prop_world(name)
            vs, fs = LOCAL[name]
            ptrees[name] = BVHTree.FromPolygons([M @ v for v in vs], fs)
            tris = {a for a, _ in overlap_both(btree, ptrees[name])}
            if name not in RELEASE or i + 1 <= RELEASE[name] + RELEASE_EASE:
                tris = {t for t in tris if not HAND[side][t]}
            by = {}
            for t in tris:
                by[str(TRI_BONE[t])] = by.get(str(TRI_BONE[t]), 0) + 1
            row[name] = by
        row["weapons"] = len(overlap_both(*ptrees.values())) if len(ptrees) == 2 else 0
        for side in ("Right", "Left"):
            row["hand_" + side] = hand_cuts(P, side, near_only=False)
        rows.append(row)
    scaled = [pb.name for pb in PB if (Vector(pb.scale) - Vector((1, 1, 1))).length > 1e-5]
    assert not scaled, ("bones left scaled", scaled)
    report[clip] = {"source": fbx, "frames": n_fr, "rows": rows, "fixes": fixes, "drop": drops,
                    "lift": [round(x, 4) for x in lift],
                    "seam_deg": round(math.degrees(seam), 2), "seam_hips_cm": round(100 * seam_hips, 2),
                    "root_vel": list(act.get("root_vel", [0.0, 0.0]))}
    low = [r["lowest"] for r in rows]
    print("CLIP_GROUND", clip, "lowest point from %.3f to %.3f m; weapons' lowest %s" % (
        min(low), max(low), {nm: round(min(r["props_low"][nm] for r in rows), 3) for nm in WEAPONS}))
    for name in WEAPONS:
        hit = [(i + 1, sum(r[name].values()), r[name]) for i, r in enumerate(rows) if r[name]]
        if hit:
            worst = max(hit, key=lambda h: h[1])
            bones = {}
            for _, _, by in hit:
                for b, c in by.items():
                    bones[b] = max(bones.get(b, 0), c)
            print("CLIP_PROP %s %s: body through it in %d of %d frames (%s to %s); worst frame %d, %d triangles %s; bones %s"
                  % (clip, name, len(hit), n_fr, hit[0][0], hit[-1][0], worst[0], worst[1], worst[2], bones))
        else:
            print("CLIP_PROP %s %s: clear in all %d frames" % (clip, name, n_fr))
    ww = [(i + 1, r["weapons"]) for i, r in enumerate(rows) if r["weapons"]]
    print("CLIP_WEAPONS %s: weapons through each other in %d frames %s" % (clip, len(ww), ww[:10]))
    for side in ("Right", "Left"):
        hit = [(i + 1, sum(r["hand_" + side].values()), r["hand_" + side]) for i, r in enumerate(rows) if r["hand_" + side]]
        worst = max(hit, key=lambda h: h[1]) if hit else None
        print("CLIP_HAND %s %s (%s): body through the hand in %d of %d frames%s" % (
            clip, side, "empty" if SIDES.get(side, {}).get("weapon", "") is None else "holding", len(hit), n_fr,
            "; frames %s; worst frame %d, %d triangles %s" % (
                [h[0] for h in hit][:20], worst[0], worst[1], worst[2]) if hit else ""))

out_json.write_text(json.dumps(report), encoding="utf-8")
for name in EMPTY:
    bpy.data.objects.remove(bpy.data.objects[name], do_unlink=True)
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
