"""Review only: retarget the goblin's four Mixamo clips onto GoblinRabbleRig, keep the props
clear of the body, measure every frame and save a scratch copy with the clips (Mixamo motion
stays out of the repo).

  blender -b goblin_rabble_rig.blend --python retarget_clips.py -- <animations dir> <out.blend> <measure.json>

Retarget as spearman_3d/tools/retarget_clips.py (rest-pose difference, bone by bone, in
world space; the hips' motion scaled by the hip-height ratio), keying only the Mixamo body
bones: the fingers keep the grip actions. Options per clip:
  in_place   remove the drift between the first and last frame (its speed is kept as the
             action's root_vel, m/s in Blender x and y)
  loop       the clip loops (its corrections are smoothed round the seam)
  loop_blend ease the last N frames back into the first pose (a loop)
  ground     lift the hips wherever the skinned body or a prop dips below the floor (the
             soles may sink FOOT_SINK), widened and averaged so the lift never pops
  sole       raise or lower the hips so the lowest point of the soles stays at its rest
             height (the planted foot on the ground; the retarget's shorter legs make the
             walk's feet sink at the heel strike and float at mid-stance), averaged over
             SOLE_W frames either side (round the seam of a loop)
The clips were made for empty hands, so each frame gets the smallest arm correction that
keeps the props clear of the body:
  left   the wrist held at the standard fist in every frame (the hand grips the strapped
         shield, so the fist stays pressed to its back; the rig's ShieldFist hold does the
         same at shield_fist 1); then the elbow opened, the arm
         lifted out from the chest, the forearm rolled to turn the shield away from the
         upper arm (cheapest first), against both shields and their straps (and the
         barrel's handle); one roll direction per stretch
  right  the whole arm eased toward the standard pose, against all three weapons (the right
         hand holding them is left out); where no ease clears them (the walk's back swing,
         the weapon pointing forward into the leg swinging through), the elbow bent or the
         arm lifted out from the chest, tried only after every ease
Each correction is widened and averaged over neighbouring frames (round the seam of a loop).
Per frame and per prop of all three loadouts: body triangles that cut through the prop
(exact triangle overlap), by the bone weighing most on them, the body's lowest point and
each prop's lowest point.
"""
import json
import math
import sys
import time
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

FOOT_Z = 0.08        # rest height below which vertices are the soles
FOOT_SINK = 0.01
PROP_SINK = 0.0
SMOOTH = 3           # frames either side
SOLE_W = 1
CLIPS = {
    "idle": ("Idle - Goblin.fbx", {"in_place": True, "loop_blend": 10}),
    "walk": ("Walk - Goblin.fbx", {"in_place": True, "loop": True, "sole": True}),
    "attack": ("Attack - Goblin Rabble.fbx", {}),
    "death": ("Death - Goblin.fbx", {"ground": True}),
}
PROPS = {"Knife": "Weapon", "Hatchet": "Weapon", "Cleaver": "Weapon", "ShieldBarrel": "Shield", "ShieldPlank": "Shield",
         "ShieldBarrelStraps": "Shield", "ShieldPlankStraps": "Shield"}

argv = sys.argv[sys.argv.index("--") + 1:]
anim_dir, out_blend, out_json = Path(argv[0]), Path(argv[1]), Path(argv[2])
sc = bpy.context.scene
sc.render.fps = 30
rig = bpy.data.objects["GoblinRabbleRig"]
body = bpy.data.objects["GoblinRabble"]
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
RIGHT_HAND = np.array([b.startswith("RightHand") for b in TRI_BONE])
rest_z = np.array([v.co.z for v in me.vertices])
floor = np.where(rest_z < FOOT_Z, -FOOT_SINK, 0.0)
SOLE = rest_z < FOOT_Z
LOCAL, PROP_NP, PROP_BVH, PROP_SPHERE = {}, {}, {}, {}
for name in PROPS:
    ob = bpy.data.objects[name]
    vs, fs = [v.co.copy() for v in ob.data.vertices], [list(p.vertices) for p in ob.data.polygons]
    LOCAL[name] = (vs, fs)
    A = np.array([tuple(v) for v in vs])
    c = (A.min(0) + A.max(0)) / 2
    PROP_NP[name], PROP_BVH[name] = A, BVHTree.FromPolygons(vs, fs)
    PROP_SPHERE[name] = (c, float(np.linalg.norm(A - c, axis=1).max()))
print("CLIPS_MESH body %d vertices, %d triangles; props %s" % (len(me.vertices), len(TRI), {n: len(LOCAL[n][1]) for n in PROPS}))

# The arm corrections. The goblin faces -y, so his left is +x.
assert rig.data.bones[MX + "LeftArm"].head_local.x > 0
CHEST = MX + "Spine2"
SIDES = {
    "Left": {"props": ("ShieldBarrel", "ShieldPlank", "ShieldBarrelStraps", "ShieldPlankStraps"), "exclude": None,
             "lat": Vector((1, 0, 0)), "elbow": 1},
    "Right": {"props": ("Knife", "Hatchet", "Cleaver"), "exclude": RIGHT_HAND, "lat": Vector((-1, 0, 0)), "elbow": -1},
}
for side, s in SIDES.items():
    s["chain"] = tuple(MX + side + p for p in ("Arm", "ForeArm", "Hand"))
    s["lat_chest"] = rig.data.bones[CHEST].matrix_local.to_3x3().inverted() @ s["lat"]
# Left (hand at the fist, elbow opened by degrees, arm lifted out by degrees, forearm
# rolled by degrees to turn the shield away from the upper arm), cheapest first; right (the arm
# eased to the standard pose, then the clip's own arm with the elbow bent or lifted out).
GRID = {
    "Left": sorted(((w, a, p, r) for w in (1,) for a in (0, 15, 30, 45, 60)
                    for p in (0, 10, 20, 30, 40) for r in (0, 15, 30, 45)),
                   key=lambda c: c[0] + c[1] / 25 + c[2] / 20 + c[3] / 20),
    "Right": [(w, 0, 0, 0) for w in (0, .2, .4, .6, .8, 1)]
    + sorted(((0, a, p, 0) for a in (0, 15, 30, 45) for p in (0, 10, 20, 30) if a or p),
             key=lambda c: c[1] / 25 + c[2] / 20),
}
assert all(rig[p] == 0 for p in ("weapon_ik", "shield_ik", "leg_ik"))
STAND_Q = {n: rig.pose.bones[n].matrix_basis.to_quaternion() for s in SIDES.values() for n in s["chain"]}


def evaluated():
    ev = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    m = ev.to_mesh()
    co = np.empty(len(m.vertices) * 3)
    m.vertices.foreach_get("co", co)
    ev.to_mesh_clear()
    return co.reshape(-1, 3) @ np.array(body.matrix_world.to_3x3()).T + np.array(body.matrix_world.translation)


def prop_world(name):
    """The prop's world matrix from its bone's pose (the props of other loadouts are hidden,
    and a hidden object's matrix_world is not kept up to date)."""
    ob = bpy.data.objects[name]
    pb = rig.pose.bones[ob.parent_bone]
    return rig.matrix_world @ pb.matrix @ Matrix.Translation((0, pb.bone.length, 0)) @ ob.matrix_parent_inverse @ ob.matrix_basis


def prop_low(name):
    M = np.array(prop_world(name))
    return float((PROP_NP[name] @ M[:3, :3].T + M[:3, 3])[:, 2].min())


def through(P, side):
    """Body triangles through the side's props, counted near each prop only (fast; the final
    measure below is the exact one)."""
    total = 0
    for name in SIDES[side]["props"]:
        M = np.array(prop_world(name))
        c, r = PROP_SPHERE[name]
        near = np.linalg.norm(P - (M[:3, :3] @ c + M[:3, 3]), axis=1) < r * np.linalg.norm(M[:3, :3], axis=0).max() + 0.06
        tm = near[TRI].any(1)
        if SIDES[side]["exclude"] is not None:
            tm &= ~SIDES[side]["exclude"]
        if not tm.any():
            continue
        sub = TRI[tm]
        idx = np.unique(sub)
        remap = np.full(len(P), -1)
        remap[idx] = np.arange(len(idx))
        Mi = np.linalg.inv(M)
        bt = BVHTree.FromPolygons((P[idx] @ Mi[:3, :3].T + Mi[:3, 3]).tolist(), remap[sub].tolist())
        total += len({a for a, _ in bt.overlap(PROP_BVH[name])})
    return total


def base_pose(side):
    pbs = rig.pose.bones
    arm, fore, hand = SIDES[side]["chain"]
    q = {n: pbs[n].rotation_quaternion.copy() for n in (arm, fore, hand)}
    W = {n: pbs[n].matrix.to_3x3().normalized() for n in (arm, fore, hand)}
    ad = (pbs[arm].tail - pbs[arm].head).normalized()
    fd = (pbs[fore].tail - pbs[fore].head).normalized()
    lat = (pbs[CHEST].matrix.to_3x3().normalized() @ SIDES[side]["lat_chest"]).normalized()
    # The roll's sign: the way that turns the shield's face (from the forearm to the barrel's
    # centre) away from the upper arm.
    sign = 1.0
    if side == "Left":
        nrm = rig.matrix_world.inverted() @ prop_world("ShieldBarrel") @ Vector(PROP_SPHERE["ShieldBarrel"][0]) - pbs[fore].head
        nrm -= nrm.dot(fd) * fd
        up = -ad - (-ad).dot(fd) * fd
        if nrm.length > 1e-4 and up.length > 1e-4:
            sign = -1.0 if fd.cross(nrm.normalized()).dot(up.normalized()) > 0 else 1.0
    return q, W, ad, fd, lat, sign


def eased(q, n, w):
    s = STAND_Q[n].copy()
    s.make_compatible(q)
    return q.slerp(s, w)


def corrected(side, base, c, sign=None):
    """The arm chain's local rotations with correction c. A world turn R of a bone (about its
    head) is the local turn W^-1 R W; the elbow and lift turns are taken from the uncorrected
    pose, which leaves each one independent of the others."""
    arm, fore, hand = SIDES[side]["chain"]
    q, W, ad, fd, lat, s0 = base
    w, a, p, r = c
    sign = s0 if sign is None else sign
    if side == "Right":
        out = {n: eased(q[n], n, w) for n in (arm, fore, hand)}
        if not (a or p):
            return out
    else:
        out = {hand: eased(q[hand], hand, w), fore: q[fore].copy(), arm: q[arm].copy()}
    R = Matrix.Identity(3)
    if SIDES[side]["elbow"] > 0:      # opened, never past straight
        ang, axis = min(math.radians(a), max(0.0, fd.angle(ad) - math.radians(5))), fd.cross(ad)
    else:                             # bent, never past 145 degrees
        ang, axis = min(math.radians(a), max(0.0, math.radians(145) - fd.angle(ad))), ad.cross(fd)
    if ang > 0 and axis.length > 1e-4:
        R = Matrix.Rotation(ang, 3, axis.normalized())
    if r:
        R = R @ Matrix.Rotation(sign * math.radians(r), 3, fd)
    if a or r:
        out[fore] = out[fore] @ (W[fore].inverted() @ R @ W[fore]).to_quaternion()
    ang, axis = min(math.radians(p), ad.angle(lat)), ad.cross(lat)
    if ang > 0 and axis.length > 0.2:
        out[arm] = out[arm] @ (W[arm].inverted() @ Matrix.Rotation(ang, 3, axis.normalized()) @ W[arm]).to_quaternion()
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


def correct_arms(clip, n, cyclic):
    t0, evals = time.time(), 0
    found, bases = {s: [] for s in SIDES}, {s: [] for s in SIDES}
    for f in range(1, n + 1):
        sc.frame_set(f)
        for side in SIDES:
            base = base_pose(side)
            bases[side].append(base)
            best = None
            for c in GRID[side]:
                pose_set(corrected(side, base, c))
                k = through(evaluated(), side)
                evals += 1
                if best is None or k < best[0]:
                    best = (k, c, base[5])
                if k == 0:
                    break
            if f == 1 and side == "Left":   # a pose set by hand must survive the update
                pose_set(corrected(side, base, (1, 30, 40, 0)))
                hand = SIDES[side]["chain"][2]
                turned = rig.pose.bones[hand].matrix.to_quaternion().rotation_difference(base[1][hand].to_quaternion()).angle
                assert turned > 0.01, turned
            pose_set(base[0])
            found[side].append(best)
    smooth, roll_sign = {}, {}
    for side in SIDES:
        cols = list(zip(*[c for _, c, _ in found[side]]))
        smooth[side] = [list(c) for c in zip(*[widen(list(col), cyclic) for col in cols])]
        # One roll direction over each stretch of rolled frames, so the shield never flips.
        rs, signs = [c[3] for c in smooth[side]], [s for _, _, s in found[side]]
        if cyclic:
            smooth[side][-1] = list(smooth[side][0])
        roll_sign[side], i, against = [1.0] * n, 0, 0
        while i < n:
            if rs[i] <= 0:
                i += 1
                continue
            j = i
            while j < n and rs[j] > 0:
                j += 1
            tot = sum(found[side][k][1][3] * signs[k] for k in range(i, j)) or sum(signs[i:j])
            for k in range(i, j):
                roll_sign[side][k] = 1.0 if tot >= 0 else -1.0
                against += roll_sign[side][k] != signs[k]
            i = j
        if cyclic:
            roll_sign[side][-1] = roll_sign[side][0]
        left = [i + 1 for i, (k, _, _) in enumerate(found[side]) if k]
        print("CLIP_FIX %s %s: corrected %d of %d frames, largest %s; best grid point still through in %d frames %s; roll against the frame's own way in %d"
              % (clip, side, sum(1 for _, c, _ in found[side] if any(c)), n,
                 tuple(round(max(col), 2) for col in cols), len(left), left[:12], against))

    def key_all():
        prev = {}
        for f in range(1, n + 1):
            vals = {}
            for side in SIDES:
                vals.update(corrected(side, bases[side][f - 1], smooth[side][f - 1], roll_sign[side][f - 1]))
            for nm, qq in vals.items():
                if nm in prev:
                    qq.make_compatible(prev[nm])
                prev[nm] = qq
                rig.pose.bones[nm].rotation_quaternion = qq
                rig.pose.bones[nm].keyframe_insert("rotation_quaternion", frame=f)

    key_all()
    # The widened corrections can still meet the body where they are not monotonic (a roll that
    # turns the shield off the upper arm into the thigh): give each such frame the nearest clear
    # grid point and ramp its neighbours into it over SMOOTH frames, until every frame is clear.
    scale = (1, 25, 20, 20)
    for it in range(4):
        fails = {}
        for f in range(1, n + 1):
            sc.frame_set(f)
            for side in SIDES:
                if through(evaluated(), side):
                    fails.setdefault(side, []).append(f)
        print("CLIP_FIX %s repair %d: still through %s" % (clip, it, {sd: fs for sd, fs in fails.items()}))
        if not fails:
            break
        for side, fs in fails.items():
            target = {}
            for f in fs:
                sc.frame_set(f)
                cur = smooth[side][f - 1]
                for c in sorted(GRID[side], key=lambda c: sum(abs(a - b) / k for a, b, k in zip(c, cur, scale))):
                    pose_set(corrected(side, bases[side][f - 1], c, roll_sign[side][f - 1]))
                    evals += 1
                    if not through(evaluated(), side):
                        target[f] = c
                        break
            new = [list(c) for c in smooth[side]]
            for g in range(1, n + 1):
                d, f = min((abs(g - f), f) for f in target) if target else (None, None)
                if f is None or d > SMOOTH:
                    continue
                w = 1 - d / (SMOOTH + 1)
                new[g - 1] = [a + (b - a) * w for a, b in zip(smooth[side][g - 1], target[f])]
            if cyclic:
                new[-1] = list(new[0])
            smooth[side] = new
        key_all()
    print("CLIP_FIX %s: %d evaluations in %.0f s" % (clip, evals, time.time() - t0))
    return {s: [[round(x, 3) for x in c] + [roll_sign[s][i]] for i, c in enumerate(smooth[s])] for s in SIDES}


def ground_lift(n):
    need = []
    for f in range(1, n + 1):
        sc.frame_set(f)
        body_need = float(np.max(floor - evaluated()[:, 2]))
        props_need = max(-PROP_SINK - prop_low(nm) for nm in PROPS)
        need.append(max(0.0, body_need, props_need))
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
    # The seam: how far the last frame's bones are from the first's (0 for a clean loop).
    seam = max(local[-1][n].rotation_difference(local[0][n]).angle for n in order)
    seam_hips = (hips_off[-1] - hips_off[0]).length
    if act.use_cyclic:
        assert math.degrees(seam) < 0.5 and seam_hips < 0.005, (clip, math.degrees(seam), seam_hips)
    fixes = correct_arms(clip, n_fr, act.use_cyclic)
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

    # Every frame: what cuts through the props, and the lowest points.
    rows = []
    for i in range(n_fr):
        sc.frame_set(i + 1)
        P = evaluated()
        btree = BVHTree.FromPolygons([Vector(p) for p in P], TRI.tolist())
        row = {"lowest": round(float(P[:, 2].min()), 4), "hips": [round(c, 3) for c in hb.matrix.translation],
               "props_low": {nm: round(prop_low(nm), 4) for nm in PROPS}}
        for name, bone in PROPS.items():
            M = prop_world(name)
            vs, fs = LOCAL[name]
            tris = {a for a, _ in btree.overlap(BVHTree.FromPolygons([M @ v for v in vs], fs))}
            if bone == "Weapon":
                tris = {t for t in tris if not RIGHT_HAND[t]}
            by = {}
            for t in tris:
                by[str(TRI_BONE[t])] = by.get(str(TRI_BONE[t]), 0) + 1
            row[name] = by
        rows.append(row)
    report[clip] = {"source": fbx, "frames": n_fr, "rows": rows, "fixes": fixes, "lift": [round(x, 4) for x in lift],
                    "seam_deg": round(math.degrees(seam), 2), "seam_hips_cm": round(100 * seam_hips, 2),
                    "root_vel": list(act.get("root_vel", [0.0, 0.0]))}
    low = [r["lowest"] for r in rows]
    print("CLIP_GROUND", clip, "lowest point from %.3f to %.3f m; props' lowest %s" % (
        min(low), max(low), {nm: round(min(r["props_low"][nm] for r in rows), 3) for nm in PROPS}))
    for name in PROPS:
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
