"""Export the Sovereign Kiss cast for the Godot sandbox (background Blender; saves nothing).

  blender -b <kiss blend> --python export_kiss_godot.py -- <out.fbx> <textures dir>

Run on the kiss blend (README, Sovereign Kiss) after kiss_heart.py. Writes:
  * <out.fbx>: SuccubusRig alone (deforming bones, no meshes) with sovereign_kiss as its one
    take, as export_godot.py exports her (the forearm twist bones baked into keys, Y up, the
    model facing +Z). It is made from a Mixamo clip, so it stays local: <out.fbx> belongs in
    the repository's local/ folder. The sandbox adds it to her model at run time
    (prototypes/sandbox3d/scripts/local_clips.gd), where it is on disk.
  * <out>.json, the sidecar: the clip's length, frames and events as in succubus.json
    (kiss_release, and kiss_breath, where kiss_heart.py's breath starts gathering at her
    lips, BREATH frames before it), `shot_from`, KissSocket's tail at the release in the
    model's axes (where the heart leaves), and `socket`, that point at every frame.
  * kiss_heart_sdf.png and kiss_puff_sdf.png in <textures dir>: kiss_heart.py's heart and
    puff shapes (signed distance in R, the heart's highlight in G), 256 px, for the
    sandbox's fog shader.
"""
import json
import sys
from pathlib import Path

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = Path(argv[0])
TEX_DIR = Path(argv[1])
CLIP = "sovereign_kiss"
FPS = 30.0
TEX = 256
BREATH = 5                     # frames before kiss_release that kiss_heart.py's breath starts
sc = bpy.context.scene
sc.render.fps = int(FPS)
rig = bpy.data.objects["SuccubusRig"]
rig.location = (0, 0, 0)
rig.rotation_euler = (0, 0, 0)
PB = rig.pose.bones
act = bpy.data.actions[CLIP]
frames = list(range(1, int(act["frames"]) + 1))


def to_godot(v):
    # Godot (Y up, the model facing +Z) from Blender (Z up, facing -Y): x, z, -y.
    return [round(float(v[0]), 4), round(float(v[2]), 4), round(float(-v[1]), 4)]


# 1. Bake the twist bones (Copy Rotation from the hand) into the clip, then drop the constraints.
rig.animation_data.action = act
if act.slots:
    rig.animation_data.action_slot = act.slots[0]
twist = [pb for pb in PB if pb.name.endswith("ForeArmTwist")]
vals = []
for f in frames:
    sc.frame_set(f)
    vals.append([rig.convert_space(pose_bone=pb, matrix=pb.matrix, from_space="POSE", to_space="LOCAL")
                 .to_quaternion() for pb in twist])
for f, qs in zip(frames, vals):
    for pb, q in zip(twist, qs):
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = q
        pb.keyframe_insert("rotation_quaternion", frame=f)
for pb in twist:
    for c in list(pb.constraints):
        pb.constraints.remove(c)

# 2. The sidecar: where the heart leaves, every frame.
events = json.loads(act.get("events", "{}"))
events["kiss_breath"] = round(events["kiss_release"] - BREATH / FPS, 4)
release = round(events["kiss_release"] * FPS) + 1
socket = []
for f in frames:
    sc.frame_set(f)
    socket.append(to_godot(rig.matrix_world @ PB["KissSocket"].tail))
info = {"length": round((frames[-1] - 1) / FPS, 4), "loop": False, "frames": len(frames),
        "root_vel": [0.0, 0.0, 0.0], "root_motion": False, "events": events,
        "shot_from": socket[release - 1], "socket": socket}
meta = {"fps": FPS, "source": "local/succubus_3d/succubus_sovereign_kiss_fog.blend", "forward": [0, 0, 1],
        "clips": {CLIP: info}}

# 3. Export the rig with the one clip.
act.frame_range = (frames[0], frames[-1])
act.use_frame_range = True
sc.frame_start, sc.frame_end = frames[0], frames[-1]
sc.frame_set(1)
for o in bpy.data.objects:
    o.select_set(o is rig)
bpy.context.view_layer.objects.active = rig
OUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.fbx(
    filepath=str(OUT), use_selection=True, object_types={"ARMATURE"},
    apply_unit_scale=True, apply_scale_options="FBX_SCALE_UNITS", axis_forward="-Z", axis_up="Y",
    use_armature_deform_only=True, add_leaf_bones=False, primary_bone_axis="Y", secondary_bone_axis="X",
    bake_anim=True, bake_anim_use_all_bones=True, bake_anim_use_nla_strips=False, bake_anim_use_all_actions=False,
    bake_anim_force_startend_keying=True, bake_anim_step=1.0, bake_anim_simplify_factor=0.0,
)
OUT.with_suffix(".json").write_text(json.dumps(meta, indent=1))

# 4. The fog's shapes.
TEX_DIR.mkdir(parents=True, exist_ok=True)
for name, file in (("SK_HeartSDF", "kiss_heart_sdf.png"), ("SK_PuffSDF", "kiss_puff_sdf.png")):
    img = bpy.data.images[name].copy()
    img.scale(TEX, TEX)
    img.filepath_raw = str(TEX_DIR / file)
    img.file_format = "PNG"
    img.save()
    print("TEXTURE", TEX_DIR / file)
print("KISS_EXPORT %s: %d frames, release at frame %d, from %s" % (OUT, len(frames), release, info["shot_from"]))
