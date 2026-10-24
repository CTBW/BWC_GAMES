"""Check an exported succubus FBX against its source (background Blender).

  blender -b succubus_anim.blend --python verify_fbx.py -- <exported.fbx>

Samples bone heads of the source rig per clip, then imports the FBX into an empty scene
and compares: bone and mesh counts, every clip present with its length, the bone heads
at the same frames, and each mesh's skinned position mid-clip (in Blender's axes, as the
importer converts them back).
"""
import sys

import bpy
import numpy as np

fbx = sys.argv[sys.argv.index("--") + 1]
sc = bpy.context.scene
rig = bpy.data.objects["SuccubusRig"]
SAMPLE = ["mixamorig:Hips", "mixamorig:Head", "mixamorig:LeftHand", "mixamorig:RightFoot", "Tail_6", "WingLeft_3",
          "WingRight_3", "Loincloth_3", "WhipGrip", "WhipCoil", "Lash_8", "Lash_16"]
SAMPLE = [n for n in SAMPLE if n in rig.pose.bones]
def mesh_boxes():
    """Per mesh object: the centre and size of its evaluated (skinned) vertices, world space."""
    out = {}
    dg = bpy.context.evaluated_depsgraph_get()
    for o in bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        ev = o.evaluated_get(dg)
        m = ev.to_mesh()
        co = np.empty(len(m.vertices) * 3)
        m.vertices.foreach_get("co", co)
        ev.to_mesh_clear()
        M = np.array(o.matrix_world)
        co = co.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3]
        out[o.name] = (co.min(0) + co.max(0)) / 2, co.max(0) - co.min(0)
    return out


src = {}
src_boxes = {}
src_bones = sorted(b.name for b in rig.data.bones if b.use_deform or b.name == "WhipGrip")
for act in [a for a in bpy.data.actions if "frames" in a]:
    rig.animation_data.action = act
    n = int(act["frames"])
    fr = sorted({1, n // 3, (2 * n) // 3, n})
    pts = {}
    for f in fr:
        sc.frame_set(f)
        pts[f] = np.array([list(rig.matrix_world @ rig.pose.bones[b].head) for b in SAMPLE])
    src[act.name] = (n, pts)
    sc.frame_set(n // 2)
    src_boxes[act.name] = mesh_boxes()

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=fbx, automatic_bone_orientation=False)
sc = bpy.context.scene
arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
bones = sorted(b.name for b in arm.data.bones)
print("VERIFY bones", len(bones), "source deforming", len(src_bones), "missing", sorted(set(src_bones) - set(bones))[:8])
print("VERIFY meshes", sorted(m.name for m in meshes), "skinned", [m.name for m in meshes if any(md.type == "ARMATURE" for md in m.modifiers)])
imgs = [i for i in bpy.data.images if i.size[0] > 0]
print("VERIFY textures", [(i.name, tuple(i.size)) for i in imgs])
worst = 0.0
for name, (n, pts) in src.items():
    act = next((a for a in bpy.data.actions if a.name == name or a.name.endswith("|" + name)), None)
    if act is None:
        print("VERIFY clip", name, "MISSING")
        continue
    arm.animation_data_create()
    arm.animation_data.action = act
    f0, f1 = (int(round(v)) for v in act.frame_range)
    errs = []
    for f, P in pts.items():
        sc.frame_set(f0 + f - 1)
        Q = np.array([list(arm.matrix_world @ arm.pose.bones[b].head) for b in SAMPLE])
        errs.append(float(np.max(np.linalg.norm(P - Q, axis=1))))
    worst = max(worst, max(errs))
    sc.frame_set(f0 + n // 2 - 1)
    got = mesh_boxes()
    for mname, (c, size) in src_boxes[name].items():
        if mname in got:
            d = float(np.linalg.norm(got[mname][0] - c))
            worst = max(worst, d)
            if d > 0.005:
                print(f"VERIFY clip {name} mesh {mname} centre off by {100 * d:.1f} cm")
    print(f"VERIFY clip {name:11s} as {act.name!r} frames {f1 - f0 + 1} (source {n})  max bone offset {100 * max(errs):.2f} cm")
print("VERIFY worst %.2f cm" % (100 * worst))
