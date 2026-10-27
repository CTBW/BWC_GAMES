"""Carry the footman's finished clips over to the collie (background Blender).

  blender -b collie_rig.blend --python transfer_clips.py -- <footman_rig.blend> <out.blend> [clip,clip...]

<footman_rig.blend> is the footman's rig with his clips (`local/footman_3d/footman_rig.blend`
at the repository root: local, the clips are made from Mixamo clips). FootmanRig and the
clips are appended to the open copy; each clip is sampled on FootmanRig and written onto
CollieRig by rest-pose difference, bone by bone in world space, as
footman_3d/tools/retarget_clips.py does from a Mixamo armature:
    R_collie(t) = R_footman(t) * R_footman_rest^-1 * R_collie_rest
so the collie's bones turn exactly as the footman's turn away from their T-pose: his guard,
his blows, his steps. The hips' motion is scaled by the ratio of the hip heights, and so is
the travel the clips store (root_vel, root_path, lane_m); every other property the clips
carry (frames, source, contact_t, enter_walk_t, ...) is copied. The footman's skirt bones
have no counterpart; the collie's tail, tabard and tasset bones stay at rest for
collie_motion.py. The appended FootmanRig and its clips are removed again; saves <out.blend>.
"""
import sys
from pathlib import Path

import bpy

# The clips footman_3d/tools/export_godot.py sends to the sandbox (it adds turn_90_r itself).
CLIPS = ["idle", "stand", "walk", "attack", "block", "hit", "block_hit", "death", "lane", "turn_90", "turn_180",
         "stop", "start", "run", "charge_hit", "attack_stab", "charge_stab", "attack_thrust", "charge_thrust"]
SCALED = ("root_vel", "root_path", "lane_m")

argv = sys.argv[sys.argv.index("--") + 1:]
src_blend, out_blend = Path(argv[0]), Path(argv[1])
only = argv[2].split(",") if len(argv) > 2 and argv[2] else CLIPS
sc = bpy.context.scene
sc.render.fps = 30
rig = bpy.data.objects["CollieRig"]
rig.location = (0, 0, 0)
rig.rotation_euler = (0, 0, 0)

with bpy.data.libraries.load(str(src_blend), link=False) as (data_from, data_to):
    data_to.objects = ["FootmanRig"]
    data_to.actions = [n for n in only if n in data_from.actions]
src = data_to.objects[0]
sc.collection.objects.link(src)
src.location = (0, 0, 0)
src.rotation_euler = (0, 0, 0)
src.animation_data_create()
SRC_ACTS = {a.name: a for a in data_to.actions}
for a in SRC_ACTS.values():
    a.name = "footman_" + a.name
missing = [n for n in only if n not in SRC_ACTS]
if missing:
    print("TRANSFER_SKIP not in the footman's blend:", ", ".join(missing))

names = [b.name for b in rig.data.bones if b.name in src.data.bones]
order = []   # parents first


def visit(b):
    order.append(b.name)
    for c in b.children:
        visit(c)


for b in rig.data.bones:
    if b.parent is None:
        visit(b)


def rest(ob, n):
    return (ob.matrix_world.to_3x3() @ ob.data.bones[n].matrix_local.to_3x3()).normalized()


T_rest = {n: rest(rig, n) for n in order}
S_rest = {n: rest(src, n) for n in names}
T_hips = rig.matrix_world @ rig.data.bones["mixamorig:Hips"].head_local
S_hips = src.matrix_world @ src.data.bones["mixamorig:Hips"].head_local
ratio = T_hips.z / S_hips.z
print("TRANSFER hips %.3f m (footman %.3f): ratio %.3f" % (T_hips.z, S_hips.z, ratio))


def fcurves(act):
    """An action's F-curves (Blender 4.4+ keeps them per slot in layers)."""
    if hasattr(act, "fcurves"):
        return list(act.fcurves)
    out = []
    for layer in act.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                out += list(bag.fcurves)
    return out


rig.animation_data_create()
for clip in only:
    sact = SRC_ACTS.get(clip)
    if sact is None:
        continue
    src.animation_data.action = sact
    f0, f1 = (int(round(v)) for v in sact.frame_range)
    act = bpy.data.actions.new(clip)
    act.use_fake_user = True
    rig.animation_data.action = act
    prev = {}
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        R = {n: (src.matrix_world.to_3x3() @ src.pose.bones[n].matrix.to_3x3()).normalized() for n in names}
        Rt = {}
        for n in order:
            par = rig.data.bones[n].parent
            if n in R:
                Rt[n] = R[n] @ S_rest[n].inverted() @ T_rest[n]
            else:
                # The collie's own bones (tail, tabard, tassets): at rest under their parent.
                Rt[n] = Rt[par.name] @ T_rest[par.name].inverted() @ T_rest[n]
            if par is None:
                basis = T_rest[n].inverted() @ Rt[n]
            else:
                basis = (T_rest[par.name].inverted() @ T_rest[n]).inverted() @ Rt[par.name].inverted() @ Rt[n]
            q = basis.to_quaternion()
            if n in prev:
                q.make_compatible(prev[n])
            prev[n] = q
            pb = rig.pose.bones[n]
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=f)
        hips = src.matrix_world @ src.pose.bones["mixamorig:Hips"].head
        hb = rig.pose.bones["mixamorig:Hips"]
        hb.location = T_rest["mixamorig:Hips"].inverted() @ ((hips - S_hips) * ratio)
        hb.keyframe_insert("location", frame=f)
    for fc in fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    for k, v in sact.items():
        if k in SCALED:
            v = [x * ratio for x in v] if hasattr(v, "__len__") else v * ratio
        act[k] = v
    act["transfer"] = "footman's %s on FootmanRig, hips x %.3f" % (clip, ratio)
    act["frames"] = f1 - f0 + 1
    print("TRANSFER", clip, f1 - f0 + 1, "frames")

# Only the collie's clips stay.
arm = src.data
bpy.data.objects.remove(src, do_unlink=True)
bpy.data.armatures.remove(arm)
for a in list(SRC_ACTS.values()):
    bpy.data.actions.remove(a)
rig.animation_data.action = bpy.data.actions.get("idle")
sc.frame_start, sc.frame_end = 1, int(rig.animation_data.action["frames"]) if rig.animation_data.action else 1
out_blend.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(out_blend), compress=True)
print("TRANSFER_SAVED", out_blend, len([a for a in bpy.data.actions]), "clips")
