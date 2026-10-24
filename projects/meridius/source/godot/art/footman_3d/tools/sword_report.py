"""Where the blade meets the body, clip by clip (background Mixar / Blender).

  mixar.exe --background <rig.blend> --python sword_report.py -- [clip,clip...]

For every frame the blade (14 points from guard to tip) is tested against the
posed body (the sword hand's own fist and forearm excepted, as fix_sword.py); a
point is inside when the nearest face's normal and a ray-parity vote agree.
The shield is tested too. Prints per clip: frames with the blade inside, frames
within 1 cm, the deepest cut and the parts (name~ = within 1 cm, not inside). Read-only: nothing is saved.
"""
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
CLIPS = argv[0].split(",") if argv and argv[0] else [
    "idle", "walk", "attack", "block", "hit", "block_hit", "death", "lane", "turn_90", "turn_180", "stop", "start", "run"]
sc = bpy.context.scene
rig = bpy.data.objects["FootmanRig"]
body = bpy.data.objects["Footman"]
sword = bpy.data.objects["Sword"]
shield = bpy.data.objects["Shield"]
rig.location = (0, 0, 0)
rig.rotation_euler = (0, 0, 0)
_own = {g.index for g in body.vertex_groups if g.name in ("mixamorig:RightHand", "mixamorig:RightForeArm")}
_vown = np.zeros(len(body.data.vertices), bool)
for v in body.data.vertices:
    best = max(v.groups, key=lambda g: g.weight, default=None)
    _vown[v.index] = best is not None and best.group in _own
SKIP = {p.index for p in body.data.polygons if sum(_vown[i] for i in p.vertices) * 2 >= len(p.vertices)}
PART = {}
for p in body.data.polygons:
    gs = {}
    for i in p.vertices:
        for g in body.data.vertices[i].groups:
            gs[g.group] = gs.get(g.group, 0) + g.weight
    PART[p.index] = body.vertex_groups[max(gs, key=gs.get)].name.split(":")[-1] if gs else "?"
sv = np.array([v.co[:] for v in sword.data.vertices])
ZS = np.linspace(0.10, float(sv[:, 2].max()) - 0.02, 14)


RAYS = [Vector(v).normalized() for v in ((0.31, 0.12, 0.94), (-0.7, 0.55, 0.45), (0.2, -0.93, 0.3), (0.05, 0.6, -0.8), (-0.9, -0.3, -0.31))]


def is_inside(bvh, q):
    """Ray parity in five directions, majority vote: the nearest face's normal
    alone calls points in the hollows between head, collar and shoulders inside."""
    votes = 0
    for d in RAYS:
        n, o = 0, q.copy()
        for _ in range(16):
            hit = bvh.ray_cast(o, d)
            if hit[0] is None:
                break
            n += 1
            o = hit[0] + d * 1e-4
        votes += n % 2
    return votes >= 3


SH_BVH = BVHTree.FromObject(shield, bpy.context.evaluated_depsgraph_get())  # rigid: its own space


def depth_now():
    """Deepest point of the blade inside the body or the shield (m, > 0 inside;
    < 0 is the clearance) and what it meets."""
    dg = bpy.context.evaluated_depsgraph_get()
    bvh = BVHTree.FromObject(body, dg)
    inv = body.matrix_world.inverted()
    sinv = shield.matrix_world.inverted()
    m = sword.matrix_world
    worst, part = -1.0, None
    for z in ZS:
        w = m @ Vector((0, 0, z))
        q = inv @ w
        near = [h for h in bvh.find_nearest_range(q, 0.2) if h[2] not in SKIP]
        if near:
            loc, nrm, idx, dist = min(near, key=lambda h: h[3])
            d = dist if ((q - loc).dot(nrm) < 0 and is_inside(bvh, q)) else -dist
            if d > worst:
                worst, part = d, PART.get(idx)
        qs = sinv @ w
        hit = SH_BVH.find_nearest(qs, 0.2)
        if hit[0] is not None:
            loc, nrm, idx, dist = hit
            d = dist if ((qs - loc).dot(nrm) < 0 and is_inside(SH_BVH, qs)) else -dist
            if d > worst:
                worst, part = d, "Shield"
    return worst, part


for clip in CLIPS:
    act = bpy.data.actions.get(clip)
    if act is None:
        print("SWORD_REPORT", clip, "missing")
        continue
    rig.animation_data.action = act
    f0, f1 = (int(v) for v in act.frame_range)
    inside, close, deep, parts, at = 0, 0, -1.0, {}, None
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        d, part = depth_now()
        if d > 0:
            inside += 1
            parts[part] = parts.get(part, 0) + 1
        if d > -0.01:
            close += 1
            if d <= 0:
                parts[str(part) + "~"] = parts.get(str(part) + "~", 0) + 1
        if d > deep:
            deep, at = d, f
    print("SWORD_REPORT %-10s inside %3d  within 1 cm %3d  of %3d  deepest %+.1f cm at f%d  %s" % (
        clip, inside, close, f1 - f0 + 1, 100 * deep, at or 0, parts))
