"""Review only: retarget the goblin's Mixamo idle, walk and death onto GoblinShamanRig, carry the
staff in front of him, keep it clear of his body and his mask, measure every frame and save a
scratch copy with the clips (Mixamo motion stays out of the repo).

  blender -b goblin_shaman_rig.blend --python retarget_clips.py -- <animations dir> <out.blend> <measure.json> [clip,...]

Either variant's rig: goblin_shaman_rig.blend (the skull mask) or goblin_shaman_beak_rig.blend
(the beak mask). Retarget as goblin_rabble/tools/retarget_clips.py (rest-pose difference, bone
by bone, in world space; the hips' motion scaled by the hip-height ratio), keying only the
Mixamo body bones: the fingers keep the grip Actions. No attack yet: he will mostly cast spells
(the user, 27 October 2026). Options per clip:
  in_place   remove the drift between the first and last frame (its speed is kept as the
             action's root_vel, m/s in Blender x and y)
  loop       the clip loops; its last frame must match its first
  loop_blend ease the last N frames back into the first pose (a loop)
  ground     raise or lower the hips so the skinned body's lowest point lies on the floor in
             every frame (a death has no airborne frame), averaged over a frame either side
             but never left below it. A drop settles again with its final arm and open hand.
  sole       raise or lower the hips so the lowest point of the soles stays at its rest
             height, averaged over SOLE_W frames either side (round the seam of a loop)
  blend_in   N: start from the idle's first pose and ease into the clip over N frames
  head_lag   N: with blend_in, the neck and head keep the idle's turn N frames longer (the
             death's: until he may first let go of the staff, which they would otherwise meet)
  hold       the clip was made for empty hands. His right arm, collarbone included, keeps the
             standard pose (`stand`) on the clip's chest, so he carries the staff upright in
             front of his right side with his hand at chest height, as his concept's idle and
             walk do (source/godot/art/raw/goblin_shaman/f_base.png and f_walk_a.png). Its
             foot stays off the ground: the approved staff's grip is 0.65 m from its foot, and
             the user chose to carry it so rather than lengthen it or lower the hand (27
             October 2026). The clip's chest leans and twists the arm and the staff with it,
             so in every frame the hand turns at the wrist to take back UPRIGHT of the staff's
             sway from its standard axis: he keeps it upright as he walks, as the concept's walk
             does, and it sways a little. Where the chest dips (the walk's right footfall) and
             the staff's foot would come nearer the ground than STAFF_LOW, the fist rises: the
             elbow bends and the arm turns at the shoulder. The arm then turns at the shoulder by the carry: the least turn,
             the same in every frame of every hold clip, that keeps the staff CLEAR off his
             body (the right hand holding it left out) and his mask. It is stored on the rig
             (`carry_arm`).
  concept    his concept's stance laid over a hold clip (f_base.png, f_walk_a.png; the user, 27
             October 2026): the hips sink CROUCH with the feet kept where they are, the knees
             bending deeper and turned KNEE_OUT outward; the chest leans `hunch` degrees further
             forward, shared by Spine, Spine1 and Spine2 (the idle's own chest leans 3 degrees
             back and the walk's 6 forward, so the idle takes 18 and the walk 5, and both lean
             about 10 degrees forward from the spine to the neck), and the head turns HEAD_KEEP
             of it back, so he still looks ahead; the left arm holds his fetish hand out in front of his hip
             (`stand`'s arm, bent further to put the wrist at FETISH from the shoulder) and keeps
             the `left` share of the clip's own left-arm motion about it. The death blends in
             from the idle's first pose with all of this, its raised fist and its wrist.
  drop      a death. The right arm keeps the carry until he lets go of the staff, between
             RELEASE frames: the fist opens to GRIP_DEAD and the arm eases into the clip's over
             RELEASE_EASE frames. The staff falls as the spearman's spear: it turns to lie on
             the ground about its lowest point, which drops to the ground, in the time its
             middle would take to fall there. It lies on the side that brings its shaft
             lowest, tipped so that both its ends rest on the ground. When he lets go, which way
             it falls (FALL_WAYS, degrees to his right of ahead), how far it is pushed from him
             and its spin are the first that keep it out of his body, and CLEAR off his mask, in
             every later frame.
Every clip keys the staff's bone and the right grip's influence in its first frame, so
switching clips leaves nothing behind.
Per frame: the least gap between the staff and his body (the right hand holding it left out)
and between the staff and his mask (mm, negative where they cut each other), the body
triangles through the staff by the bone weighing most on them, and the body's and the staff's
lowest points.
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
SOLE_W = 1
CLEAR = 0.01         # m the carried staff keeps off his body and his mask
PAD = 0.04           # m round the staff within which gaps are measured
CARRY_MAX = 20       # degrees the carry's turn of the right arm may reach
UPRIGHT = 0.8        # share of the carried staff's sway that the wrist takes back
STAFF_LOW = 0.12     # m the carried staff's foot keeps off the ground
CROUCH = 0.06        # m the concept's hips sink below the clip's
KNEE_OUT = 15        # degrees the crouch turns each knee outward about its hip-ankle line
HEAD_KEEP = 0.7      # share of the hunch the head turns back
FETISH = (0.20, 0.17, -0.33)   # m: the concept's left wrist out from, ahead of and above his left shoulder in `stand`
RELEASE = (4, 12)    # frames: the death's right hand lets go of the staff in this range (the first that clears)
RELEASE_EASE = 6     # frames over which the fist opens and the arm goes over to the clip's
GRIP_DEAD = 0.4      # the grip's influence on an open hand
FALL_WAYS = (45, 90, 135, 0, 180)   # degrees to his right of ahead the staff may fall, preferred first
STAFF_REST = 0.002   # the fallen staff's lowest point lies this far above the ground
G = 9.81
CLIPS = {
    "idle": ("Idle - Goblin.fbx", {"in_place": True, "loop_blend": 10, "hold": True, "concept": {"hunch": 18, "left": 1.0}}),
    "walk": ("Walk - Goblin.fbx", {"in_place": True, "loop": True, "sole": True, "hold": True, "concept": {"hunch": 5, "left": 0.35}}),
    "death": ("Death - Goblin.fbx", {"blend_in": 8, "head_lag": RELEASE[0], "ground": True, "drop": True}),
}

argv = sys.argv[sys.argv.index("--") + 1:]
anim_dir, out_blend, out_json = Path(argv[0]), Path(argv[1]), Path(argv[2])
ONLY = argv[3].split(",") if len(argv) > 3 and argv[3] else list(CLIPS)
assert "death" not in ONLY or "idle" in ONLY, "the death blends in from the idle"
HOLD = [c for c in ONLY if CLIPS[c][1].get("hold")]
sc = bpy.context.scene
sc.render.fps = 30
rig = bpy.data.objects["GoblinShamanRig"]
body = bpy.data.objects["GoblinShaman"]
staff = bpy.data.objects["Staff"]
mask = bpy.data.objects["MaskPlate"]
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
assert rig.matrix_world == Matrix.Identity(4) and body.matrix_world == Matrix.Identity(4)
T_rest = {n: RB[n].matrix_local.to_3x3().normalized() for n in order}
T_hips = RB[MX + "Hips"].head_local.copy()
RIGHT = [MX + "Right" + p for p in ("Shoulder", "Arm", "ForeArm", "Hand")]
LEFT = [MX + "Left" + p for p in ("Shoulder", "Arm", "ForeArm", "Hand")]
GRIP_R = [c for pb in PB for c in pb.constraints if c.type == "ACTION" and c.name == "grip_staff"]
assert GRIP_R
assert rig["staff_ik"] == 0 and rig["cast_ik"] == 0 and rig["leg_ik"] == 0 and rig["staff_hold"] == 1


def put(pb, M):
    """Set a pose bone's matrix (rig space) and leave no scale behind: an unkeyed scale stays
    into the next frame, whose matrices start from it, and grows."""
    pb.matrix = M
    pb.scale = (1, 1, 1)
    bpy.context.view_layer.update()


def two_bone(S, l1, l2, T, pole):
    """The middle joint of a two-bone chain (lengths l1, l2) from S that reaches T, bent toward
    `pole` (a direction)."""
    d = T - S
    D = d.length
    assert D < l1 + l2 - 1e-4, (D, l1 + l2)
    u = d / D
    a = (l1 * l1 - l2 * l2 + D * D) / (2 * D)
    p = (pole - u * pole.dot(u)).normalized()
    return S + u * a + p * math.sqrt(max(0.0, l1 * l1 - a * a))


def frame(u, n):
    u = u.normalized()
    n = (n - u * n.dot(u)).normalized()
    return Matrix((u, n, u.cross(n))).transposed()


def aim(up, low, S, E, W, E1, T):
    """Turn a two-bone chain (pose bones `up` from S to E and `low` from E to W) so its middle
    joint lies at E1 and its end at T, each bone turned with its bend plane (so the joint stays a
    hinge). Set, not keyed."""
    n0, n1 = (E - S).cross(W - E), (E1 - S).cross(T - E1)
    assert n0.length > 1e-4 and n1.length > 1e-4
    Ru = frame(E1 - S, n1) @ frame(E - S, n0).transposed()
    Rl = frame(T - E1, n1) @ frame(W - E, n0).transposed()
    old = low.matrix.copy()
    MS = Matrix.Translation(S)
    put(up, MS @ Ru.to_4x4() @ MS.inverted() @ up.matrix)
    put(low, Matrix.Translation(E1) @ Rl.to_4x4() @ Matrix.Translation(-E) @ old)

# The standard pose: the right arm's and the controls' keys in `stand`.
STAND = bpy.data.actions["stand"]
rig.animation_data.action = STAND
rig.animation_data.action_slot = STAND.slots[0]
sc.frame_set(1)
STAND_Q0 = {n: PB[n].rotation_quaternion.copy() for n in RIGHT}     # before the carry
STAND_Q = {n: q.copy() for n, q in STAND_Q0.items()}
CTRL = ("StaffCtrl", "HandIK.L", "ElbowPole.L", "ElbowPole.R")
STAND_C = {n: (PB[n].location.copy(), PB[n].rotation_quaternion.copy()) for n in CTRL}
STAND_AXIS = (PB["Staff"].matrix.to_3x3() @ Vector((0, 1, 0))).normalized()   # up the staff
assert staff.parent_bone == "Staff" and mask.parent_type == "BONE"
K_STAFF = Matrix.Translation((0, RB["Staff"].length, 0)) @ staff.matrix_parent_inverse @ staff.matrix_basis
_err = max(abs(a - b) for ra, rb in zip(PB["Staff"].matrix @ K_STAFF, staff.matrix_world) for a, b in zip(ra, rb))
assert _err < 1e-5, _err
_mb = RB[mask.parent_bone]
K_MASK = Matrix.Translation((0, _mb.length, 0)) @ mask.matrix_parent_inverse @ mask.matrix_basis
_err = max(abs(a - b) for ra, rb in zip(PB[_mb.name].matrix @ K_MASK, mask.matrix_world) for a, b in zip(ra, rb))
assert _err < 1e-5, _err
# The concept's left arm: `stand`'s, bent to put the wrist at FETISH from the shoulder (he faces -y).
_S, _E, _W = (PB[n].head.copy() for n in LEFT[1:])
_T = _S + Vector((FETISH[0], -FETISH[1], FETISH[2]))
_E1 = two_bone(_S, (_E - _S).length, (_W - _E).length, _T, _E - _S)
aim(PB[LEFT[1]], PB[LEFT[2]], _S, _E, _W, _E1, _T)
assert (PB[LEFT[3]].head - _T).length < 1e-3
CONCEPT_L = {n: PB[n].rotation_quaternion.copy() for n in LEFT}
print("CLIPS_FETISH left elbow bent %.0f deg (from %.0f in stand)" % (
    math.degrees((_E1 - _S).angle(_T - _E1)), math.degrees((_E - _S).angle(_W - _E))))
rig.animation_data.action = None
for n in order + ["Staff"]:
    PB[n].rotation_mode = "QUATERNION"
    PB[n].matrix_basis = Matrix.Identity(4)
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
VHAND_R = np.array([b.startswith("RightHand") for b in DOM])
THAND_R = VHAND_R[TRI].any(1)
VNONE, TNONE = np.zeros(len(DOM), bool), np.zeros(len(TRI), bool)
# Each vertex's share of the right arm (RightArm and the bones below it; the armature
# normalises the weights), for moving the skin with a turn of the arm in the carry's search.
_vg = {g.index: g.name for g in body.vertex_groups}
_arm = {b.name for b in RB[MX + "RightArm"].children_recursive} | {MX + "RightArm"}
W_ARM = np.zeros(len(me.vertices))
for v in me.vertices:
    ws = [(g.weight, _vg[g.group]) for g in v.groups if _vg[g.group] in RB and RB[_vg[g.group]].use_deform]
    tot = sum(w for w, _ in ws)
    if tot > 0:
        W_ARM[v.index] = sum(w for w, n in ws if n in _arm) / tot
rest_z = np.array([v.co.z for v in me.vertices])
SOLE = rest_z < FOOT_Z
SV = np.array([v.co[:] for v in staff.data.vertices])
SF = [list(p.vertices) for p in staff.data.polygons]
mask.data.calc_loop_triangles()
MV = np.array([v.co[:] for v in mask.data.vertices])
MT = np.array([t.vertices[:] for t in mask.data.loop_triangles])
print("CLIPS_MESH body %d vertices, %d triangles; staff %d vertices; mask %d vertices" % (
    len(me.vertices), len(TRI), len(SV), len(MV)))


def evaluated():
    ev = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    m = ev.to_mesh()
    co = np.empty(len(m.vertices) * 3)
    m.vertices.foreach_get("co", co)
    ev.to_mesh_clear()
    return co.reshape(-1, 3)


def staff_world():
    return PB["Staff"].matrix @ K_STAFF


def mask_world():
    return PB[mask.parent_bone].matrix @ K_MASK


def pts(V, M):
    Mn = np.array(M)
    return V @ Mn[:3, :3].T + Mn[:3, 3]


def gap(P, T, Q, skip_t=None, skip_v=None, bones=None):
    """The least gap (m) between a mesh (vertices P, triangles T) and the staff at the points Q,
    both in world space: the nearest of P's vertices (not in skip_v) to the staff, or, where
    triangles of T (not in skip_t) cut through it, minus a millimetre per triangle. With bones
    (a name per triangle of T), also the cutting triangles by bone."""
    lo, hi = Q.min(0) - PAD, Q.max(0) + PAD
    vin = np.all((P > lo) & (P < hi), axis=1)
    tm = vin[T].any(1)
    if skip_t is not None:
        tm &= ~skip_t
    if not tm.any():
        return (1.0, {}) if bones is not None else 1.0
    qt = BVHTree.FromPolygons(Q.tolist(), SF)
    sub = T[tm]
    idx = np.unique(sub)
    remap = np.full(len(P), -1)
    remap[idx] = np.arange(len(idx))
    bt = BVHTree.FromPolygons(P[idx].tolist(), remap[sub].tolist())
    hit = {a for a, _ in bt.overlap(qt)}
    if hit:
        g = -0.001 * len(hit)
    else:
        vm = vin if skip_v is None else vin & ~skip_v
        g = min((qt.find_nearest(Vector(p))[3] for p in P[vm]), default=1.0)
    if bones is None:
        return g
    by = {}
    for i in hit:
        b = str(bones[tm][i])
        by[b] = by.get(b, 0) + 1
    return g, by


def facing():
    """His facing on the ground, square to the hip line (his right is -x at rest, he faces -y)."""
    r = PB[MX + "RightUpLeg"].head - PB[MX + "LeftUpLeg"].head
    return Vector((0, 0, 1)).cross(Vector((r.x, r.y, 0))).normalized()


def smoothstep(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def set_action(name):
    act = bpy.data.actions[name]
    rig.animation_data.action = act
    rig.animation_data.action_slot = act.slots[0]
    return act


def key_rest(f):
    """The controls as `stand` has them, the staff's bone at rest in the fist, StaffHold (the
    hand's turn) at rest and the right grip closed, keyed at frame f."""
    for n in CTRL:
        PB[n].location, PB[n].rotation_quaternion = STAND_C[n]
        PB[n].keyframe_insert("location", frame=f)
        PB[n].keyframe_insert("rotation_quaternion", frame=f)
    for n in ("Staff", "StaffHold"):
        PB[n].matrix_basis = Matrix.Identity(4)
        PB[n].keyframe_insert("location", frame=f)
        PB[n].keyframe_insert("rotation_quaternion", frame=f)
    key_grip(f, 1.0)


def key_grip(f, v):
    for c in GRIP_R:
        c.influence = v
        c.keyframe_insert("influence", frame=f)


def key_right(f, quats):
    for n in RIGHT:
        PB[n].rotation_quaternion = quats[n]
        PB[n].keyframe_insert("rotation_quaternion", frame=f)


def settle(n):
    """Raise or lower the keyed hips in every frame so the body's lowest point lies on the floor,
    averaged over a frame either side but never left below it. Returns the rise per frame (m)."""
    need = []
    for f in range(1, n + 1):
        sc.frame_set(f)
        need.append(-float(evaluated()[:, 2].min()))
    rise = [max(need[i], sum(need[max(0, i - 1):i + 2]) / len(need[max(0, i - 1):i + 2])) for i in range(n)]
    hb = PB[MX + "Hips"]
    up = T_rest[MX + "Hips"].inverted().to_3x3() @ Vector((0, 0, 1))
    for f in range(1, n + 1):
        sc.frame_set(f)
        hb.location = hb.location + up * rise[f - 1]
        hb.keyframe_insert("location", frame=f)
    return rise


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


def staff_axis():
    return (PB["Staff"].matrix.to_3x3() @ Vector((0, 1, 0))).normalized()


def upright(n):
    """Turn the right hand at the wrist in every frame by UPRIGHT of the turn that brings the
    staff's axis back to STAND_AXIS: the least turn, so the staff keeps the chest's twist about
    its length. The hand copies the turn of StaffHold (on the forearm), so the turn is keyed there. Returns the largest sway from STAND_AXIS
    before and after (degrees)."""
    hold = PB["StaffHold"]
    before = after = 0.0
    prev = None
    for f in range(1, n + 1):
        sc.frame_set(f)
        a = staff_axis()
        before = max(before, math.degrees(a.angle(STAND_AXIS)))
        C = Quaternion().slerp(a.rotation_difference(STAND_AXIS), UPRIGHT).to_matrix().to_4x4()
        h = Matrix.Translation(hold.matrix.translation)
        put(hold, h @ C @ h.inverted() @ hold.matrix)
        q = hold.rotation_quaternion.copy()
        if prev is not None:
            q.make_compatible(prev)
        hold.rotation_quaternion = prev = q
        hold.keyframe_insert("rotation_quaternion", frame=f)
        bpy.context.view_layer.update()
        after = max(after, math.degrees(staff_axis().angle(STAND_AXIS)))
    return before, after


def raise_fist(n, cyclic):
    """Raise the right fist wherever the staff's foot comes nearer the ground than STAFF_LOW, by
    the shortfall widened and averaged over two frames either side (round the seam of a loop):
    the elbow bends to the new reach and the arm turns at the shoulder to bring the wrist
    straight up. Returns the largest rise (m)."""
    need = []
    for f in range(1, n + 1):
        sc.frame_set(f)
        need.append(max(0.0, STAFF_LOW - float(pts(SV, staff_world())[:, 2].min())))
    m = n - 1 if cyclic else n      # a loop's last frame repeats its first
    at = (lambda v, i: v[i % m]) if cyclic else (lambda v, i: v[min(max(i, 0), m - 1)])
    wide = [max(at(need, j) for j in range(i - 2, i + 3)) for i in range(m)]
    rise = [sum(at(wide, j) for j in range(i - 2, i + 3)) / 5 for i in range(m)]
    rise = rise + rise[:1] if cyclic else rise
    arm, fore, hand = PB[MX + "RightArm"], PB[MX + "RightForeArm"], PB[MX + "RightHand"]
    prev = {}
    for f in range(1, n + 1):
        sc.frame_set(f)
        d = rise[f - 1]
        if d > 1e-5:
            S, E, W = arm.head.copy(), fore.head.copy(), hand.head.copy()
            T = W + Vector((0, 0, d))
            l1, l2 = (E - S).length, (W - E).length

            def inner(D):
                return math.acos(max(-1.0, min(1.0, (l1 * l1 + l2 * l2 - D * D) / (2 * l1 * l2))))
            delta = inner((W - S).length) - inner((T - S).length)
            hinge = (E - S).cross(W - E).normalized()
            R = min((Matrix.Rotation(sg * delta, 4, hinge) for sg in (1, -1)),
                    key=lambda r: abs((E + r.to_3x3() @ (W - E) - S).length - (T - S).length))
            W1 = E + R.to_3x3() @ (W - E)
            MS, ME = Matrix.Translation(S), Matrix.Translation(E)
            A = MS @ (W1 - S).rotation_difference(T - S).to_matrix().to_4x4() @ MS.inverted()
            fore_new = A @ ME @ R @ ME.inverted() @ fore.matrix
            put(arm, A @ arm.matrix)
            put(fore, fore_new)
            assert (hand.head - T).length < 1e-3, (f, (hand.head - T).length)
        for b in (arm, fore):
            q = b.rotation_quaternion.copy()
            if b.name in prev:
                q.make_compatible(prev[b.name])
            b.rotation_quaternion = prev[b.name] = q
            b.keyframe_insert("rotation_quaternion", frame=f)
    return max(rise)


def left_swing(local, k):
    """Per frame, the clip's left-arm turns about their mean, scaled by k (bone by bone, local)."""
    out = [{} for _ in local]
    for n in LEFT:
        acc = Quaternion((0, 0, 0, 0))
        for q in local:
            c = q[n].copy()
            c.make_compatible(local[0][n])
            acc = acc + c
        mean = acc.normalized()
        for i, q in enumerate(local):
            d = mean.inverted() @ q[n]
            if d.w < 0:
                d.negate()
            out[i][n] = Quaternion().slerp(d, k)
    return out


def knee_bend(H, K, A):
    return math.degrees((K - H).angle(A - K))


def stance(n, hunch):
    """The module's `concept` crouch and hunch, keyed in every frame (the left arm is keyed with
    the clip). Returns each knee's bend from straight (degrees: least and most, before and after)."""
    hb = PB[MX + "Hips"]
    up_l = T_rest[MX + "Hips"].inverted() @ Vector((0, 0, 1))
    chest = [PB[MX + s] for s in ("Spine", "Spine1", "Spine2")]
    head = PB[MX + "Head"]
    legs = {s: [PB[MX + s + b] for b in ("UpLeg", "Leg", "Foot")] for s in ("Left", "Right")}
    bends = {s: ([], []) for s in legs}
    prev = {}
    for f in range(1, n + 1):
        sc.frame_set(f)
        left = Vector((0, 0, 1)).cross(facing())        # his left: he leans forward about it
        was = {s: ([b.head.copy() for b in bs], bs[2].matrix.copy()) for s, bs in legs.items()}
        hb.location = hb.location - up_l * CROUCH
        bpy.context.view_layer.update()
        for b, a in [(b, hunch / len(chest)) for b in chest] + [(head, -hunch * HEAD_KEEP)]:
            P = Matrix.Translation(b.head)
            put(b, P @ Matrix.Rotation(math.radians(a), 4, left) @ P.inverted() @ b.matrix)
        for s, (up, kn, ft) in legs.items():
            (H, K, A), M = was[s]
            H1 = up.head.copy()
            ax = (A - H1).normalized()
            out = left if s == "Left" else -left
            pole = max((Quaternion(ax, math.radians(sg * KNEE_OUT)) @ (K - H) for sg in (1, -1)), key=lambda p: p.dot(out))
            K1 = two_bone(H1, (K - H).length, (A - K).length, A, pole)
            aim(up, kn, H1, K + H1 - H, A + H1 - H, K1, A)
            put(ft, M)                          # the foot as it was
            assert (ft.head - A).length < 1e-3, (f, s, (ft.head - A).length)
            bends[s][0].append(knee_bend(H, K, A))
            bends[s][1].append(knee_bend(H1, K1, A))
        for b in chest + [head] + legs["Left"] + legs["Right"]:
            q = b.rotation_quaternion.copy()
            if b.name in prev:
                q.make_compatible(prev[b.name])
            b.rotation_quaternion = prev[b.name] = q
            b.keyframe_insert("rotation_quaternion", frame=f)
        hb.keyframe_insert("location", frame=f)
    return {s: [round(min(b[0])), round(max(b[0])), round(min(b[1])), round(max(b[1]))] for s, b in bends.items()}


# --- The retarget ----------------------------------------------------------------------------

report, CLIPQ, FIRST = {}, {}, {}
rig.animation_data_create()
for clip in ONLY:
    fbx, opt = CLIPS[clip]
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
            par = RB[n].parent
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
        w = smoothstep((k + 1) / nb)
        for n in order:
            a, b = local[i][n], local[0][n].copy()
            b.make_compatible(a)
            local[i][n] = a.slerp(b, w)
        hips_off[i] = hips_off[i].lerp(hips_off[0], w)
    nb = opt.get("blend_in", 0)
    if nb:
        q0, h0 = FIRST["idle"]
        lag = opt.get("head_lag", 0)
        for i in range(min(nb + lag, n_fr)):
            for n in order:
                d = lag if n in (MX + "Neck", MX + "Head") else 0
                if i - d >= nb:
                    continue
                a, b = q0[n].copy(), local[i][n]
                a.make_compatible(b)
                local[i][n] = a.slerp(b, smoothstep((i - d) / nb))
            if i < nb:
                hips_off[i] = h0.lerp(hips_off[i], smoothstep(i / nb))
    FIRST[clip] = (local[0], hips_off[0])
    CLIPQ[clip] = [{n: q[n].copy() for n in RIGHT} for q in local]
    act = bpy.data.actions.new(clip)
    act.use_fake_user = True
    rig.animation_data.action = act
    prev = {}
    hb = PB[MX + "Hips"]
    if "concept" in opt:
        swing = left_swing(local, opt["concept"]["left"])
    for i in range(n_fr):
        for n in order:
            if n in RIGHT and opt.get("hold"):
                qq = STAND_Q[n].copy()
            elif n in LEFT and "concept" in opt:
                qq = CONCEPT_L[n] @ swing[i][n]
            else:
                qq = local[i][n]
            if n in prev:
                qq.make_compatible(prev[n])
            prev[n] = qq
            PB[n].rotation_quaternion = qq
            PB[n].keyframe_insert("rotation_quaternion", frame=i + 1)
        hb.location = T_rest[MX + "Hips"].inverted() @ hips_off[i]
        hb.keyframe_insert("location", frame=i + 1)
    key_rest(1)
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
    if opt.get("sole"):
        lift = sole_follow(n_fr, act.use_cyclic)
        for i in range(n_fr):
            hb.location = T_rest[MX + "Hips"].inverted() @ (hips_off[i] + Vector((0, 0, lift[i])))
            hb.keyframe_insert("location", frame=i + 1)
    elif opt.get("ground"):
        lift = settle(n_fr)
    knees = None
    if "concept" in opt:
        knees = stance(n_fr, opt["concept"]["hunch"])
        if clip == "idle":
            sc.frame_set(1)
            FIRST[clip] = ({n: PB[n].rotation_quaternion.copy() for n in order}, T_rest[MX + "Hips"] @ hb.location)
    sway, rise = (0.0, 0.0), 0.0
    if opt.get("hold"):
        s0, _ = upright(n_fr)
        rise = raise_fist(n_fr, act.use_cyclic)
        sway = (s0, upright(n_fr)[1])
    if opt.get("in_place"):
        act["root_vel"] = [drift.x * ratio / (max(1, n_fr - 1) / 30.0), drift.y * ratio / (max(1, n_fr - 1) / 30.0)]
    report[clip] = {"source": fbx, "frames": n_fr, "lift": [round(x, 4) for x in lift],
                    "seam_deg": round(math.degrees(seam), 2), "seam_hips_cm": round(100 * seam_hips, 2),
                    "root_vel": [round(v, 4) for v in act.get("root_vel", [0.0, 0.0])],
                    "staff_sway_deg": [round(s, 1) for s in sway], "fist_rise_m": round(rise, 4)}
    if knees:
        report[clip]["concept"] = {"crouch_m": CROUCH, "knee_out_deg": KNEE_OUT, "hunch_deg": opt["concept"]["hunch"],
                                   "left_swing": opt["concept"]["left"], "knee_bend_deg": knees}
    print("CLIP", clip, fbx, f"{f0}-{f1}", n_fr, "frames (%.2f s), hip ratio %.3f, missing bones %s, in-place drift %.3f m"
          % ((n_fr - 1) / 30, ratio, missing, drift.length * ratio),
          "lift %.3f to %.3f m" % (min(lift), max(lift)), "seam %.1f deg, hips %.1f cm" % (math.degrees(seam), 100 * seam_hips),
          "root_vel", report[clip]["root_vel"], "staff sway %.1f deg, %.1f after the wrist;" % sway, "fist raised up to %.3f m" % rise,
          "; knees bent %s deg (left, right: least, most)" % knees if knees else "")


# --- The carry -------------------------------------------------------------------------------

DIRS = [Vector((math.cos(a), 0, math.sin(a))) for a in (math.radians(30 * k) for k in range(12))]


def bend(k, a):
    """A turn of the right arm at the shoulder: a degrees about DIRS[k] (square to its length)."""
    return Matrix.Rotation(math.radians(a), 4, DIRS[k]) if a else Matrix.Identity(4)


def set_carry():
    """The carry (see the module's `hold`), found from every frame of the hold clips and keyed
    into them. The search moves the skin with the arm by each vertex's share of it (as linear
    blend skinning does); measure() then checks the real one."""
    arm = PB[MX + "RightArm"]
    t0 = time.time()
    frames = []
    for c in HOLD:
        act = set_action(c)
        for f in range(1, int(act["frames"]) + 1):
            sc.frame_set(f)
            frames.append((c, f, evaluated(), staff_world(), arm.matrix.copy(), pts(MV, mask_world())))

    def margin(fr, D):
        _, _, P, S, A, Mq = fr
        R = A @ D @ A.inverted()            # the turn at the shoulder in the rig's space
        Rn = np.array(R)
        Pn = P + W_ARM[:, None] * (P @ Rn[:3, :3].T + Rn[:3, 3] - P)
        Q = pts(SV, R @ S)
        return min(gap(Pn, TRI, Q, THAND_R, VHAND_R), gap(Mq, MT, Q))

    base = [margin(fr, Matrix.Identity(4)) for fr in frames]
    w = int(np.argmin(base))
    print("CLIP_CARRY before: least gap %.1f mm (%s frame %d); %d of %d frames nearer than %.0f mm"
          % (base[w] * 1000, frames[w][0], frames[w][1], sum(1 for b in base if b < CLEAR), len(frames), CLEAR * 1000))
    frames = [fr for _, fr in sorted(zip(base, frames), key=lambda t: t[0])]
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
          " worst frame): least gap %.1f mm over %d frames (%.0f s)" % (a, 30 * k, *ax, m * 1000, len(frames), time.time() - t0))
    STAND_Q[arm.name] = STAND_Q0[arm.name] @ bend(k, a).to_quaternion()
    for c in HOLD:
        act = set_action(c)
        for f in range(1, int(act["frames"]) + 1):
            sc.frame_set(f)                 # on each frame's own turn (a raised fist)
            arm.rotation_quaternion = arm.rotation_quaternion @ bend(k, a).to_quaternion()
            arm.keyframe_insert("rotation_quaternion", frame=f)
    return {"dir_deg": 30 * k, "deg": a, "least_gap_mm": round(m * 1000, 1)}


# --- The death -------------------------------------------------------------------------------

def right_at(clip, f, release, holds):
    """The right arm's turns at frame f: holds[f - 1] (the idle's first, see `hold_turns`) until
    the release, then eased into the clip's."""
    w = smoothstep((f - release) / RELEASE_EASE) if f > release else 0.0
    out = {}
    for n in RIGHT:
        a, b = holds[f - 1][n].copy(), CLIPQ[clip][f - 1][n]
        a.make_compatible(b)
        out[n] = a.slerp(b, w)
    return out


def hold_turns(clip, n):
    """The idle's first right arm for each of the clip's n frames, its shoulder turned to keep the
    idle's turn relative to his hips: his back straightens out of the idle's hunch as he falls,
    which would otherwise tip the held staff back into his face."""
    set_action("idle")
    sc.frame_set(1)
    held = {b: PB[b].rotation_quaternion.copy() for b in RIGHT}
    sh, hips = PB[RIGHT[0]], PB[MX + "Hips"]
    rel = hips.matrix.to_quaternion().inverted() @ sh.matrix.to_quaternion()
    set_action(clip)
    holds = []
    for f in range(1, n + 1):
        sc.frame_set(f)
        M = Matrix.LocRotScale(sh.matrix.translation, hips.matrix.to_quaternion() @ rel, None)
        q = rig.convert_space(pose_bone=sh, matrix=M, from_space="POSE", to_space="LOCAL").to_quaternion()
        q.make_compatible(held[RIGHT[0]])
        holds.append({**held, RIGHT[0]: q})
    return holds


def grip_at(f, release):
    """The right grip's influence at frame f: closed until the release, then opening."""
    return 1 - (1 - GRIP_DEAD) * smoothstep((f - release) / RELEASE_EASE) if f > release else 1.0


def rest_turn(M0, way):
    """The turn that lays the staff (world matrix M0) down with its top toward `way` (a level
    direction): level, then rolled about its length so its bare shaft below the fist lies
    lowest, then tipped so both its ends rest on the ground."""
    S = pts(SV, M0)
    B = M0 @ K_STAFF.inverted()                  # the Staff bone: its head the fist, its y up the staff
    a, fist = B.col[1].xyz.normalized(), np.array(B.translation)
    R1 = a.rotation_difference(way)
    c = Vector(S.mean(0))
    t_ = (S - fist) @ np.array(a)
    shaft = S[(t_ > -0.55) & (t_ < -0.05)]
    best = None
    for deg in range(0, 360, 15):
        R = Quaternion(way, math.radians(deg)) @ R1
        Rm = np.array(R.to_matrix())
        Z = (S - np.array(c)) @ Rm.T
        h = float(((shaft - np.array(c)) @ Rm.T)[:, 2].mean() - Z[:, 2].min())
        if best is None or h < best[0]:
            best = (h, R)
    R = best[1]
    e = Vector((0, 0, 1)).cross(way).normalized()
    ends = (t_ < t_.min() + 0.3, t_ > t_.max() - 0.3)
    tip = None
    for deg10 in range(-300, 301, 5):
        Rt = Quaternion(e, math.radians(deg10 / 10)) @ R
        Z = ((S - np.array(c)) @ np.array(Rt.to_matrix()).T)[:, 2]
        d = abs(float(Z[ends[0]].min() - Z[ends[1]].min()))
        if tip is None or d < tip[0]:
            tip = (d, Rt, deg10 / 10)
    return tip[1], {"shaft_up_m": round(best[0], 3), "tip_deg": tip[2]}


def fall(release, n, bodies, masks):
    """The staff's fall from frame `release` (see the module's `drop`). Returns (cuts, mm short of
    CLEAR off the mask summed over the frames, its description, its world matrix per later frame)."""
    sc.frame_set(release - 1)
    o_prev = staff_world().translation.copy()
    sc.frame_set(release)
    M0 = staff_world()
    P0 = pts(SV, M0)
    low = Vector(P0[np.argmin(P0[:, 2])].tolist())
    vel = M0.translation - o_prev
    vel.z = 0.0
    fwd = facing()
    mid = float((P0[:, 2].min() + P0[:, 2].max()) / 2)
    T = max(3, math.ceil(30 * math.sqrt(2 * mid / G)))
    frames = range(release + 1, n + 1)

    def world(turn, t, extra, spin):
        s = min(1.0, (t / T) ** 2)
        R = Matrix.Rotation(math.radians(spin) * s, 4, "Z") @ Quaternion().slerp(turn, s).to_matrix().to_4x4()
        u = min(t, T)
        piv = Vector((low.x, low.y, max(0.0, low.z - 0.5 * G * (t / 30) ** 2)))
        piv += vel * (u - u * u / (2 * T)) + extra * (u / T)
        M = Matrix.Translation(piv) @ R @ Matrix.Translation(-low) @ M0
        z = float(pts(SV, M)[:, 2].min())
        return Matrix.Translation((0, 0, STAFF_REST - z if t >= T else max(0.0, STAFF_REST - z))) @ M

    best = None
    for way_deg in FALL_WAYS:
        way = Matrix.Rotation(math.radians(-way_deg), 3, "Z") @ fwd      # to his right of ahead
        turn, lie = rest_turn(M0, way)
        away = Vector((way.x, way.y, 0)).normalized()
        for k, sp in ((0, 0), (1, 0), (0, 30), (0, -30), (2, 0), (1, 30), (1, -30), (3, 0)):
            Ms = {f: world(turn, f - release, away * (0.05 * k), sp) for f in frames}
            cuts = near = 0
            for f in frames:
                Q = pts(SV, Ms[f])
                skip = THAND_R if f <= release + RELEASE_EASE else TNONE
                g = gap(bodies[f], TRI, Q, skip)
                cuts += round(-g * 1000) if g < 0 else 0
                g = gap(masks[f], MT, Q)
                cuts += round(-g * 1000) if g < 0 else 0
                near += round((CLEAR - g) * 1000) if 0 <= g < CLEAR else 0
            if best is None or (cuts, near) < best[0]:
                best = ((cuts, near), way_deg, k, sp, lie, Ms)
            if not cuts + near:
                break
        if not sum(best[0]):
            break
    (cuts, near), way_deg, k, sp, lie, Ms = best
    info = {"release": release, "lies_from": release + T, "let_go_lowest_m": round(low.z, 3), "falls_deg_right_of_ahead": way_deg,
            "pushed_m": round(0.05 * k, 2), "spin_deg": sp, "cuts": cuts, "near_mask_mm": near, **lie}
    return cuts, near, info, Ms


def drop(clip):
    """The death's staff: the carry, the release and the fall, keyed. It starts from the idle's
    first right arm (the fist raised by the crouch), kept relative to his hips until he lets go
    (`hold_turns`), and wrist (StaffHold), which keeps its turn until he lets go and turns back to
    rest as the fist opens."""
    set_action("idle")
    sc.frame_set(1)
    wrist = PB["StaffHold"].rotation_quaternion.copy()
    n = int(set_action(clip)["frames"])
    holds = hold_turns(clip, n)

    def key_wrist(release):
        hold = PB["StaffHold"]
        for f in range(1, n + 1):
            try:
                hold.keyframe_delete("rotation_quaternion", frame=f)
            except RuntimeError:
                pass
        for f, q in ((1, wrist), (release, wrist), (release + RELEASE_EASE, Quaternion())):
            hold.rotation_quaternion = q
            hold.keyframe_insert("rotation_quaternion", frame=f)
    key_wrist(RELEASE[0])
    # His open right hand reaches lower than the fist the clip was grounded with: settle again
    # (the carried arm before the release does not touch the floor).
    for f in range(1, n + 1):
        key_right(f, right_at(clip, f, RELEASE[0], holds))
        key_grip(f, grip_at(f, RELEASE[0]))
    report[clip]["lift"] = [round(a + b, 4) for a, b in zip(report[clip]["lift"], settle(n))]
    tried = []
    for release in range(RELEASE[0], RELEASE[1] + 1):
        for f in range(1, n + 1):
            key_right(f, right_at(clip, f, release, holds))
        key_wrist(release)
        bodies, masks, before = {}, {}, 0
        for f in range(1, n + 1):
            sc.frame_set(f)
            bodies[f], masks[f] = evaluated(), pts(MV, mask_world())
            if f <= release:
                Q = pts(SV, staff_world())
                g = min(gap(bodies[f], TRI, Q, THAND_R, VHAND_R), gap(masks[f], MT, Q))
                before += round(-g * 1000) if g < 0 else 0
        cuts, near, info, Ms = fall(release, n, bodies, masks)
        info["cuts_before"] = before
        tried.append((cuts + before, near, release, info, Ms))
        print("CLIP_DROP %s: let go at frame %d: %d cutting triangles before, %d in the fall, %d mm short of %d mm off"
              " the mask" % (clip, release, before, cuts, near, CLEAR * 1000))
        if not cuts + before + near:
            break
    _, _, release, info, Ms = min(tried, key=lambda t: t[:3])
    bpy.data.actions[clip]["staff_release"] = release     # read by export_godot.py
    for f in range(1, n + 1):
        key_right(f, right_at(clip, f, release, holds))
        key_grip(f, grip_at(f, release))
    sb = PB["Staff"]
    key_rest(1)
    key_rest(release)
    key_wrist(release)
    prev = sb.rotation_quaternion.copy()
    for f in range(release + 1, n + 1):
        sc.frame_set(f)
        sb.matrix = Ms[f] @ K_STAFF.inverted()
        q = sb.rotation_quaternion.copy()
        q.make_compatible(prev)
        sb.rotation_quaternion = prev = q
        sb.scale = (1, 1, 1)
        sb.keyframe_insert("location", frame=f)
        sb.keyframe_insert("rotation_quaternion", frame=f)
        sb.keyframe_insert("scale", frame=f)
    err = 0.0
    for f in range(release + 1, n + 1):
        sc.frame_set(f)
        err = max(err, float(np.abs(np.array(staff_world()) - np.array(Ms[f])).max()))
    assert err < 1e-4, err
    print("CLIP_DROP %s: let go at frame %d (its lowest point %.3f m up); falls %d deg to his right of ahead,"
          " lies from frame %d with its shaft %.3f m up, tipped %.1f deg, spun %d deg, pushed %.2f m; cutting triangles"
          " %d before the release and %d in the fall" % (clip, release, info["let_go_lowest_m"], info["falls_deg_right_of_ahead"],
                                                       info["lies_from"], info["shaft_up_m"], info["tip_deg"], info["spin_deg"],
                                                       info["pushed_m"], info["cuts_before"], info["cuts"]))
    return info


# --- Measure and save ------------------------------------------------------------------------

def measure(clip, release=None):
    act = set_action(clip)
    n = int(act["frames"])
    rows = []
    for f in range(1, n + 1):
        sc.frame_set(f)
        P = evaluated()
        Q = pts(SV, staff_world())
        held = release is None or f <= release + RELEASE_EASE
        gb, by = gap(P, TRI, Q, THAND_R if held else None, VHAND_R if held else None, bones=TRI_BONE)
        gm = gap(pts(MV, mask_world()), MT, Q)
        rows.append({"staff_body_mm": round(gb * 1000, 1), "staff_mask_mm": round(gm * 1000, 1), "through": by,
                     "lowest": round(float(P[:, 2].min()), 4), "staff_low": round(float(Q[:, 2].min()), 4),
                     "staff_tilt_deg": round(math.degrees(staff_axis().angle(STAND_AXIS)), 1)})
    gb = [r["staff_body_mm"] for r in rows]
    gm = [r["staff_mask_mm"] for r in rows]
    cut = [i + 1 for i, r in enumerate(rows) if r["through"]]
    bones = {}
    for r in rows:
        for b, c in r["through"].items():
            bones[b] = max(bones.get(b, 0), c)
    print("CLIP_STAFF %s: least gap to the body %.1f mm (frame %d), to the mask %.1f mm (frame %d); body through it in"
          " %d frames %s %s; staff's lowest point %.3f to %.3f m, off its standard axis up to %.1f deg; body's lowest"
          " %.3f to %.3f m"
          % (clip, min(gb), int(np.argmin(gb)) + 1, min(gm), int(np.argmin(gm)) + 1, len(cut), cut[:12], bones,
             min(r["staff_low"] for r in rows), max(r["staff_low"] for r in rows), max(r["staff_tilt_deg"] for r in rows),
             min(r["lowest"] for r in rows), max(r["lowest"] for r in rows)))
    report[clip]["rows"] = rows


if HOLD:
    carry = set_carry()
    for c in HOLD:
        report[c]["carry"] = carry
for clip in ONLY:
    rel = None
    if CLIPS[clip][1].get("drop"):
        report[clip]["drop"] = drop(clip)
        rel = report[clip]["drop"]["release"]
    measure(clip, rel)

out_json.write_text(json.dumps(report), encoding="utf-8")
first = ONLY[0]
set_action(first)
sc.frame_start, sc.frame_end = 1, report[first]["frames"]
sc.frame_set(1)
for screen in bpy.data.screens:
    for area in screen.areas:
        for space in area.spaces:
            if space.type == "FILE_BROWSER" and space.params is not None:
                space.params.directory = b"//" + b"_" * 700
                space.params.directory = b"//"
bpy.ops.wm.save_as_mainfile(filepath=str(out_blend), relative_remap=True, compress=True)
print("CLIPS_SAVED", out_blend)
