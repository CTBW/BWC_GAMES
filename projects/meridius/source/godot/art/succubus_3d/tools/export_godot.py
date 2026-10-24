"""Export the succubus as FBX for Godot (background Blender).

  blender -b succubus_anim.blend --python export_godot.py -- <out.fbx> [texture_px]

Works on the open copy only (the .blend is not saved):
  * the forearm twist bones' constraints baked into keys, then removed, so the clips are
    plain keys on every bone;
  * textures scaled down to `texture_px` (default 1024), as JPEG; the lash's small
    colour-block texture stays PNG (JPEG would bleed its blocks into each other);
  * one FBX: her body, wings, tail, whip and lash on SuccubusRig (deforming bones only),
    all the clips as takes; Y up, the model facing +Z in Godot. The whip and the lash are
    skinned by rig_succubus.py (handle, coil and lash bones); the lash and the coil are
    shown and hidden by their bones' scale keys (whip_motion.py);
  * a sidecar <out>.json as the footman's (prototypes/footman_anim/art3d/footman.json):
    per clip its length, loop, frames, ground speed in Godot axes, the walk's steps and
    the death's settling time; per clip the events whip_motion.py stored (the attack's
    lash out, strikes and lash in), and which clips idle plays now and then.
"""
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = Path(argv[0])
TEX = int(argv[1]) if len(argv) > 1 else 1024
FPS = 30.0
sc = bpy.context.scene
sc.render.fps = int(FPS)
rig = bpy.data.objects["SuccubusRig"]
rig.location = (0, 0, 0)
rig.rotation_euler = (0, 0, 0)
PB = rig.pose.bones
CLIPS = [a.name for a in bpy.data.actions if "frames" in a]


def to_godot(v):
    # Godot (Y up, the model facing +Z) from Blender (Z up, facing -Y): x, z, -y.
    return [round(float(v[0]), 4), round(float(v[2]), 4), round(float(-v[1]), 4)]


def frames_of(act):
    return list(range(1, int(act["frames"]) + 1))


# 1. Bake the twist bones (Copy Rotation from the hand) into each clip, then drop the constraints.
twist = [pb for pb in PB if pb.name.endswith("ForeArmTwist")]
for name in CLIPS:
    act = bpy.data.actions[name]
    rig.animation_data.action = act
    vals = []
    for f in frames_of(act):
        sc.frame_set(f)
        vals.append([(rig.convert_space(pose_bone=pb, matrix=pb.matrix, from_space="POSE", to_space="LOCAL")
                      .to_quaternion()) for pb in twist])
    for f, qs in zip(frames_of(act), vals):
        for pb, q in zip(twist, qs):
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=f)
for pb in twist:
    for c in list(pb.constraints):
        pb.constraints.remove(c)
print("BAKED twist bones", [pb.name for pb in twist])

# 2. (The whip used to be a child of its bone and was bound here; rig_succubus.py skins it.)
assert any(m.type == "ARMATURE" for m in bpy.data.objects["Whip"].modifiers), "rebuild the rig: the whip is not skinned"

# 3. Measure the clips for the sidecar.
clips = {}
for name in CLIPS:
    act = bpy.data.actions[name]
    rig.animation_data.action = act
    fr = frames_of(act)
    hips, ank = [], {"Left": [], "Right": []}
    for f in fr:
        sc.frame_set(f)
        hips.append(rig.matrix_world @ PB["mixamorig:Hips"].head)
        for s in ank:
            ank[s].append((rig.matrix_world @ PB[f"mixamorig:{s}Foot"].head).z)
    t = lambda f: round((f - fr[0]) / FPS, 4)
    vel = act.get("root_vel", [0.0, 0.0])
    info = {"length": t(fr[-1]), "loop": bool(act.get("loop", False)), "frames": len(fr),
            "root_vel": to_godot((vel[0], vel[1], 0.0)), "root_motion": bool(act.get("root_motion", False)),
            "hips_drift": to_godot(hips[-1] - hips[0]), "events": json.loads(act.get("events", "{}"))}
    if name in ("walk", "walk_start", "walk_stop"):
        steps = []
        for s, z in ank.items():
            z = np.array(z)
            g = z < z.min() + 0.03
            for k in range(1, len(g)):
                if g[k] and not g[k - 1]:
                    steps.append([t(fr[k]), s])
        info["events"]["steps"] = sorted(steps)
    if name == "death":
        still = len(fr) - 1
        while still > 1 and (hips[still] - hips[still - 1]).length < 0.004:
            still -= 1
        info["events"]["settled"] = t(fr[still])
    if info["loop"]:
        sc.frame_set(fr[0])
        a = {pb.name: pb.matrix.copy() for pb in PB}
        sc.frame_set(fr[-1])
        info["loop_seam_cm"] = round(100 * max((PB[n].matrix.translation - a[n].translation).length for n in a), 2)
    clips[name] = info
    print("CLIP", name, json.dumps(info))

# 4. Export.
# Scaled textures written to files next to the FBX for the export to embed (scaling the
# packed images alone left the 4K originals in the FBX), removed afterwards.
tmp = OUT.parent / (OUT.stem + "_tex")
tmp.mkdir(parents=True, exist_ok=True)
for img in [i for i in bpy.data.images if i.size[0] > 0]:
    if img.size[0] > TEX:
        img.scale(TEX, TEX)
    small = img.size[0] <= 256
    path = tmp / (Path(img.name).stem + (".png" if small else ".jpg"))
    img.filepath_raw = str(path)
    img.file_format = "PNG" if small else "JPEG"
    img.save(filepath=str(path), quality=90)
    if img.packed_file:
        img.unpack(method="REMOVE")      # drop the packed 4K original; the file above remains
    img.filepath = str(path)
    img.reload()
    print("TEXTURE", img.name, tuple(img.size))
for a in bpy.data.actions:
    a.frame_range = (1, int(a["frames"])) if "frames" in a else a.frame_range
    a.use_frame_range = "frames" in a
rig.animation_data.action = bpy.data.actions["idle"]
sc.frame_set(1)
keep = {rig} | {o for o in bpy.data.objects if o.type == "MESH" and o.parent is rig}
for o in bpy.data.objects:
    o.select_set(o in keep)
OUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.fbx(
    filepath=str(OUT), use_selection=True, object_types={"ARMATURE", "MESH"},
    apply_unit_scale=True, apply_scale_options="FBX_SCALE_UNITS", axis_forward="-Z", axis_up="Y",
    use_armature_deform_only=True, add_leaf_bones=False, primary_bone_axis="Y", secondary_bone_axis="X",
    bake_anim=True, bake_anim_use_all_bones=True, bake_anim_use_nla_strips=False, bake_anim_use_all_actions=True,
    bake_anim_force_startend_keying=True, bake_anim_step=1.0, bake_anim_simplify_factor=0.0,
    path_mode="COPY", embed_textures=True, mesh_smooth_type="FACE", use_mesh_modifiers=False,
)
# idle's variants: played now and then from idle, each unit at its own random interval
variants = {"idle": {"clips": [c for c in CLIPS if c.startswith("idle_")], "every_s": [9.0, 22.0]}}
meta = {"fps": FPS, "source": "art/succubus_3d/succubus_anim.blend", "forward": [0, 0, 1], "variants": variants,
        "height_m": round(float(max(v.co.z for v in bpy.data.objects["Succubus"].data.vertices)), 3),
        "objects": sorted(o.name for o in keep if o.type == "MESH"), "clips": clips}
OUT.with_suffix(".json").write_text(json.dumps(meta, indent=1))
import shutil
shutil.rmtree(tmp, ignore_errors=True)
print("EXPORT_DONE", OUT, OUT.stat().st_size)
