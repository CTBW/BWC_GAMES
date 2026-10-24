"""Report where the spear passes through the spearman, per clip and frame (background Blender).

  blender -b <rig.blend> --python spear_clearance.py -- [clip,clip...]

The body has open shells (cape, sleeves, tabard), so "inside" is not well defined. Instead
the shaft's axis is walked in 4 cm steps and every step is ray-cast against the deformed
body: a hit means the spear crosses a surface there. The fists' grip zones are left out.
Prints, per clip, the frames with crossings, where along the spear (m from the butt) and
the nearest bone at each crossing.
"""
import sys
from collections import Counter

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
sc = bpy.context.scene
rig = bpy.data.objects["SpearmanRig"]
body = bpy.data.objects["Spearman"]
spear = bpy.data.objects["Spear"]
PB, B = rig.pose.bones, rig.data.bones
fist_off = {s: B[f"mixamorig:{s}Hand"].matrix_local.inverted() @ Vector(rig[f"fist_{s.lower()}"]) for s in ("Right", "Left")}
clips = argv[0].split(",") if argv and argv[0] else [a.name[:-7] for a in bpy.data.actions if a.name.endswith("__spear")]
STEP, L = 0.04, 2.40
deform = [b.name for b in B if b.use_deform]


def nearest_bone(p):
    best, bn = 1e9, ""
    for n in deform:
        pb = PB[n]
        a, b = pb.head, pb.tail
        ab = b - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / max(1e-9, ab.length_squared)))
        d = (p - (a + ab * t)).length
        if d < best:
            best, bn = d, n.replace("mixamorig:", "")
    return bn


report = {}
for clip in clips:
    rig.animation_data.action = bpy.data.actions[clip]
    spear.animation_data.action = bpy.data.actions[clip + "__spear"]
    n = int(bpy.data.actions[clip]["frames"])
    bad, where = [], Counter()
    for f in range(1, n + 1):
        sc.frame_set(f)
        dg = bpy.context.evaluated_depsgraph_get()
        ev = body.evaluated_get(dg)
        me = ev.to_mesh()
        bvh = BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
        ev.to_mesh_clear()
        hands = [PB[f"mixamorig:{s}Hand"].matrix @ fist_off[s] for s in ("Right", "Left")]
        M = spear.matrix_world
        hits = []
        t = 0.0
        while t < L - 1e-6:
            p0, p1 = M @ Vector((0, 0, t)), M @ Vector((0, 0, min(L, t + STEP)))
            d = p1 - p0
            loc, nrm, idx, dist = bvh.ray_cast(p0, d.normalized(), d.length)
            if loc is not None and min((loc - h).length for h in hands) > 0.10:
                hits.append((round(t, 2), nearest_bone(loc)))
            t += STEP
        if hits:
            bad.append(f)
            for _, bn in hits:
                where[bn] += 1
    report[clip] = (len(bad), n)
    print("CLEAR", clip, f"{len(bad)}/{n} frames cross the body", dict(where.most_common(4)), "frames", bad[:30])
