"""Check an export_godot.py GLB against the rig it came from (background Blender), in two runs,
as goblin_spear/tools/check_export.py:

  blender -b brute_clips.blend --python check_export.py -- source <samples.npz>
  blender -b --factory-startup --python check_export.py -- glb <file.glb> <samples.npz>

The first samples the rig's skinned body (its pauldrons with it) and its weapons (the club, or
both clubs from the dual rig), in world space, at six frames of each clip (and the frames round
each weapon's release in the death). The second imports the GLB into
an empty scene and samples its meshes at the same frames of its animations, then reports the
bones, each animation's length and, per clip, how far each source vertex is from the nearest
exported one (the export splits vertices along UV seams, so indices do not match).
"""
import sys

import bpy
import numpy as np
from mathutils.kdtree import KDTree

argv = sys.argv[sys.argv.index("--") + 1:]
MODE = argv[0]
CLIPS = ["idle", "walk", "attack", "death"]
sc = bpy.context.scene


def picks(n, releases=()):
    ks = {round(i * (n - 1) / 5) for i in range(6)}
    for r in releases:
        if r:
            ks |= {k for k in (r - 1, r + 2, r + 8) if 0 <= k < n}
    return sorted(ks)


def world_verts(objs):
    dg = bpy.context.evaluated_depsgraph_get()
    out = []
    for o in objs:
        ev = o.evaluated_get(dg)
        m = ev.to_mesh()
        co = np.empty(len(m.vertices) * 3)
        m.vertices.foreach_get("co", co)
        ev.to_mesh_clear()
        M = np.array(ev.matrix_world)
        out.append(co.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3])
    return np.vstack(out)


if MODE == "source":
    out = argv[1]
    rig = bpy.data.objects["OrcBruteRig"]
    PROPS = ("Club", "ClubLeft") if rig.get("loadout") == "dual" else ("Club",)
    objs = [bpy.data.objects["OrcBrute"]] + [bpy.data.objects[p] for p in PROPS]
    data = {}
    for c in CLIPS:
        act = bpy.data.actions[c]
        rig.animation_data.action = act
        rig.animation_data.action_slot = act.slots[0]
        n = int(act["frames"])
        rel = [int(act.get(p.lower() + "_release", 0)) for p in PROPS]
        for k in picks(n, rel):
            sc.frame_set(k + 1)
            data[f"{c}_{k}"] = world_verts(objs)
        data[f"{c}_frames"] = np.array([n])
        data[f"{c}_release"] = np.array(rel)
    np.savez_compressed(out, **data)
    print("CHECK_SOURCE", out, len(data))
else:
    glb, src = argv[1], argv[2]
    S = np.load(src)
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    sc.render.fps = 30          # the importer keys the animations at the scene's rate
    bpy.ops.import_scene.gltf(filepath=glb)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    shapes = {pb.custom_shape for pb in arm.pose.bones if pb.custom_shape}   # the importer's bone display
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and o not in shapes]
    print("CHECK_GLB bones", len(arm.data.bones), "meshes", sorted(o.name for o in meshes),
          "vertices", sum(len(o.data.vertices) for o in meshes))
    acts = {a.name: a for a in bpy.data.actions}
    print("CHECK_GLB actions", {k: tuple(v.frame_range) for k, v in acts.items()})
    if arm.animation_data is None:
        arm.animation_data_create()
    for t in list(arm.animation_data.nla_tracks):
        arm.animation_data.nla_tracks.remove(t)
    worst_all = 0.0
    for c in CLIPS:
        act = next(a for k, a in acts.items() if k == c or k.endswith("|" + c) or k.startswith(c + "_"))
        arm.animation_data.action = act
        if act.slots:
            arm.animation_data.action_slot = act.slots[0]
        n = int(S[f"{c}_frames"][0])
        rel = [int(r) for r in S[f"{c}_release"]]
        f0 = act.frame_range[0]
        span = act.frame_range[1] - f0
        res = []
        for k in picks(n, rel):
            sc.frame_set(int(round(f0 + k)))
            P = world_verts(meshes)
            tree = KDTree(len(P))
            for i, p in enumerate(P):
                tree.insert(p, i)
            tree.balance()
            Q = S[f"{c}_{k}"]
            d = np.array([tree.find(q)[2] for q in Q])
            res.append((k + 1, round(float(d.max()) * 1000, 2), round(float(np.percentile(d, 99)) * 1000, 2)))
            worst_all = max(worst_all, float(d.max()))
        print("CHECK_CLIP %s frames %d (glb span %.0f): frame, max and p99 distance in mm %s" % (c, n, span, res))
    print("CHECK_WORST_MM %.2f" % (worst_all * 1000))
