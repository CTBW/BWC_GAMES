"""Keep the sword out of the body (background Mixar / Blender).

  mixar.exe --background <rig.blend> --python fix_sword.py -- [clip,clip...]

For every frame of each clip the blade is tested against the posed body mesh
(BVH of the evaluated, skinned mesh). Where it enters the body, or comes within
MARGIN of it, the sword wrist is turned about the wrist by the smallest angle
that clears it, trying outward (away from the spine), forward and to the
body's right. The per-frame corrections are widened over neighbouring frames
and smoothed so the blade eases away instead of popping, then keyed on
RightHand. Prints the frames that intersect before and after.
"""
import math
import sys

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
CLIPS = argv[0].split(",") if argv and argv[0] else ["idle", "walk", "block", "hit", "step_lane", "attack", "turn_90", "turn_180"]
MARGIN = 0.025
# Largest wrist turn allowed per clip: the cut itself must not be bent away.
CAP = {"attack": 25}
sc = bpy.context.scene
rig = bpy.data.objects["FootmanRig"]
body = bpy.data.objects["Footman"]
sword = bpy.data.objects["Sword"]
rig.rotation_euler = (0, 0, 0)
HAND = "mixamorig:RightHand"
sv = np.array([v.co[:] for v in sword.data.vertices])
# The sword hand's own fist and forearm are not "the body" here.
_own = {g.index for g in body.vertex_groups if g.name in ("mixamorig:RightHand", "mixamorig:RightForeArm")}
_vown = np.zeros(len(body.data.vertices), bool)
for v in body.data.vertices:
    best = max(v.groups, key=lambda g: g.weight, default=None)
    _vown[v.index] = best is not None and best.group in _own
SKIP = {p.index for p in body.data.polygons if sum(_vown[i] for i in p.vertices) * 2 >= len(p.vertices)}
zs = np.linspace(0.10, float(sv[:, 2].max()) - 0.02, 14)


def blade_points():
    m = sword.matrix_world
    return [m @ Vector((0, 0, z)) for z in zs]


POLY_GROUP = {}
for _p in body.data.polygons:
    _gs = {}
    for _i in _p.vertices:
        for _g in body.data.vertices[_i].groups:
            _gs[_g.group] = _gs.get(_g.group, 0) + _g.weight
    POLY_GROUP[_p.index] = body.vertex_groups[max(_gs, key=_gs.get)].name.split(":")[-1] if _gs else "?"
LAST_PART = [None]


def hits(bvh, inv, pts):
    """Deepest intrusion (m, positive = inside or too close) over the blade samples."""
    worst = -1.0
    worst_p = None
    for p in pts:
        q = inv @ p
        near = [h for h in bvh.find_nearest_range(q, 0.2) if h[2] not in SKIP]
        if not near:
            continue
        loc, nrm, idx, dist = min(near, key=lambda h: h[3])
        inside = (q - loc).dot(nrm) < 0
        depth = (dist + MARGIN) if inside else (MARGIN - dist)
        if depth > worst:
            worst, worst_p = depth, p
            LAST_PART[0] = POLY_GROUP.get(idx)
    return worst, worst_p


def spine_point(p):
    a = rig.matrix_world @ rig.pose.bones["mixamorig:Hips"].head
    b = rig.matrix_world @ rig.pose.bones["mixamorig:HeadTop_End"].head
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return a + ab * t


def bvh_now():
    dg = bpy.context.evaluated_depsgraph_get()
    return BVHTree.FromObject(body, dg), body.matrix_world.inverted()


def rotate_hand(rotvec):
    pb = rig.pose.bones[HAND]
    if rotvec.length < 1e-6:
        return
    R = Quaternion(rotvec.normalized(), rotvec.length).to_matrix().to_4x4()
    head = pb.matrix.translation.copy()
    m = Matrix.Translation(head) @ R @ Matrix.Translation(-head) @ pb.matrix
    pb.matrix = m
    pb.scale = (1.0, 1.0, 1.0)  # a shear leaves scale on the bone; no clip keys it, so it would hold in every clip


for clip in CLIPS:
    act = bpy.data.actions.get(clip)
    if act is None:
        continue
    rig.animation_data.action = act
    f0, f1 = (int(round(v)) for v in act.frame_range)
    frames = list(range(f0, f1 + 1))
    corr = []
    before = 0
    parts = {}
    for f in frames:
        sc.frame_set(f)
        bvh, inv = bvh_now()
        depth, p = hits(bvh, inv, blade_points())
        if depth <= 0:
            corr.append(Vector())
            continue
        before += 1
        parts[LAST_PART[0]] = parts.get(LAST_PART[0], 0) + 1
        blade_dir = (sword.matrix_world.to_3x3() @ Vector((0, 0, 1))).normalized()
        out = p - spine_point(p)
        out.z *= 0.3
        cands = [out.normalized(), Vector((0, -1, 0)), Vector((-1, 0, 0))]
        best = None
        base = rig.pose.bones[HAND].matrix.copy()
        for c in cands:
            axis = blade_dir.cross(c)
            if axis.length < 1e-3:
                continue
            axis.normalize()
            for deg in range(3, CAP.get(clip, 40) + 1, 3):
                rv = axis * math.radians(deg)
                rig.pose.bones[HAND].matrix = base
                rig.pose.bones[HAND].scale = (1.0, 1.0, 1.0)
                bpy.context.view_layer.update()
                rotate_hand(rv)
                bpy.context.view_layer.update()
                d2, _ = hits(bvh, inv, blade_points())
                if d2 <= 0:
                    if best is None or deg < best[0]:
                        best = (deg, rv)
                    break
        if best is None:
            # Not clearable within the cap: turn as far as allowed toward the best candidate.
            axis = blade_dir.cross(cands[0])
            best = (CAP.get(clip, 40), axis.normalized() * math.radians(CAP.get(clip, 40)) if axis.length > 1e-3 else Vector())
        rig.pose.bones[HAND].matrix = base
        rig.pose.bones[HAND].scale = (1.0, 1.0, 1.0)
        bpy.context.view_layer.update()
        corr.append(best[1] if best else Vector())
    # Widen (hold the largest correction 5 frames either side) and smooth.
    C = np.array([c[:] for c in corr])
    n = len(C)
    mag = np.linalg.norm(C, axis=1)
    W = C.copy()
    for i in range(n):
        lo, hi = max(0, i - 5), min(n, i + 6)
        j = lo + int(np.argmax(mag[lo:hi]))
        if mag[j] > np.linalg.norm(W[i]):
            W[i] = C[j]
    k = np.exp(-0.5 * (np.arange(-6, 7) / 3.0) ** 2)
    k /= k.sum()
    S = np.stack([np.convolve(np.pad(W[:, a], 6, mode="edge"), k, mode="valid") for a in range(3)], 1) * 1.15
    # Apply and key.
    prev = None
    for f, rv in zip(frames, S):
        sc.frame_set(f)
        rotate_hand(Vector(rv))
        pb = rig.pose.bones[HAND]
        q = pb.rotation_quaternion.copy()
        if prev is not None:
            q.make_compatible(prev)
        pb.rotation_quaternion = q
        prev = q
        pb.keyframe_insert("rotation_quaternion", frame=f)
    after = 0
    for f in frames:
        sc.frame_set(f)
        bvh, inv = bvh_now()
        if hits(bvh, inv, blade_points())[0] > MARGIN * 0.6:
            after += 1
    print("SWORD_CLEAR", clip, "frames intersecting before", before, "after", after, "of", len(frames),
          "max correction %.1f deg" % math.degrees(float(np.linalg.norm(S, axis=1).max())), "touching", parts)
rig.animation_data.action = bpy.data.actions.get("idle")
bpy.ops.wm.save_mainfile(compress=True)
print("SWORD_SAVED")
