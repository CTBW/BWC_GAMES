"""Check an export_godot.py GLB against the rig it came from (background Blender), in two runs,
as goblin_rabble/tools/check_export.py:

  blender -b archer_clips.blend --python check_export.py -- source <samples.npz>
  blender -b --factory-startup --python check_export.py -- glb <file.glb> <samples.npz>

The first samples the rig's skinned body and props, in world space, at six frames of each
clip (and the shot's frame); the arrow only where it shows. The second imports the GLB into
an empty scene and samples its meshes at the same frames of its animations, then reports the
bones, each animation's length and, per clip, how far each source vertex is from the nearest
exported one (the export splits vertices along UV seams, so indices do not match), and how
long the exported arrow is (0 where it is hidden at zero scale).
"""
import sys

import bpy
import numpy as np
from mathutils.kdtree import KDTree

argv = sys.argv[sys.argv.index("--") + 1:]
MODE = argv[0]
CLIPS = ["idle", "walk", "run", "attack", "block", "death"]
PROPS = ("Bow", "Quiver", "Arrow")
SHOT = 32
sc = bpy.context.scene


def picks(c, n):
    ks = {round(i * (n - 1) / 5) for i in range(6)}
    if c == "attack":
        ks |= {SHOT - 1, SHOT}
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
    rig = bpy.data.objects["GoblinArcherRig"]
    data = {}
    for c in CLIPS:
        act = bpy.data.actions[c]
        rig.animation_data.action = act
        rig.animation_data.action_slot = act.slots[0]
        n = int(act["frames"])
        for k in picks(c, n):
            sc.frame_set(k + 1)
            shown = float(rig["arrow"]) >= 0.5
            objs = [bpy.data.objects["GoblinArcher"]] + [bpy.data.objects[p] for p in PROPS if p != "Arrow" or shown]
            data[f"{c}_{k}"] = world_verts(objs)
            data[f"{c}_{k}_arrow"] = np.array([shown])
        data[f"{c}_frames"] = np.array([n])
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
    arrow = next(o for o in meshes if o.name.startswith("Arrow"))
    print("CHECK_GLB bones", len(arm.data.bones), "meshes", sorted(o.name for o in meshes),
          "vertices", sum(len(o.data.vertices) for o in meshes))
    acts = {a.name: a for a in bpy.data.actions}
    print("CHECK_GLB actions", {k: tuple(v.frame_range) for k, v in acts.items()})
    if arm.animation_data is None:
        arm.animation_data_create()
    for t in list(arm.animation_data.nla_tracks):
        arm.animation_data.nla_tracks.remove(t)
    worst_all, arrow_bad = 0.0, []
    for c in CLIPS:
        act = next(a for k, a in acts.items() if k == c or k.endswith("|" + c) or k.startswith(c + "_"))
        arm.animation_data.action = act
        if act.slots:
            arm.animation_data.action_slot = act.slots[0]
        n = int(S[f"{c}_frames"][0])
        f0 = act.frame_range[0]
        span = act.frame_range[1] - f0
        res = []
        for k in picks(c, n):
            sc.frame_set(int(round(f0 + k)))
            P = world_verts(meshes)
            tree = KDTree(len(P))
            for i, p in enumerate(P):
                tree.insert(p, i)
            tree.balance()
            Q = S[f"{c}_{k}"]
            d = np.array([tree.find(q)[2] for q in Q])
            A = world_verts([arrow])
            length = float(np.linalg.norm(A.max(0) - A.min(0)))
            shown = bool(S[f"{c}_{k}_arrow"][0])
            if (length > 0.3) != shown:
                arrow_bad.append((c, k + 1, round(length, 3)))
            res.append((k + 1, round(float(d.max()) * 1000, 2), round(float(np.percentile(d, 99)) * 1000, 2),
                        round(length, 3)))
            worst_all = max(worst_all, float(d.max()))
        print("CHECK_CLIP %s frames %d (glb span %.0f): frame, max and p99 distance in mm, arrow length m %s" % (
            c, n, span, res))
    print("CHECK_ARROW wrong visibility", arrow_bad)
    print("CHECK_WORST_MM %.2f" % (worst_all * 1000))
