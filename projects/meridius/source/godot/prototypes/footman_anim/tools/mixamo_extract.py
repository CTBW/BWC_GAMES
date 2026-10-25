"""Sample Mixamo FBX clips into plain joint tracks for the footman prototype.

Runs in a disposable background Blender (factory settings, no user scene):

  blender -b --factory-startup --python mixamo_extract.py -- <fbx dir> <out dir>

For every FBX it writes <out>/<slug>.json with the frame rate, frame count and,
per frame, the world position (metres, Blender Z-up) of every mixamorig joint
the 2D rig uses, plus the full world matrix of both hands (sword and shield
orientation). Nothing is retargeted here; tools/bake_motion.py does that.
"""
import json
import re
import sys
from pathlib import Path

import bpy

PREFIX = "mixamorig:"
JOINTS = ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "HeadTop_End",
          "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "LeftHandMiddle1",
          "RightShoulder", "RightArm", "RightForeArm", "RightHand", "RightHandMiddle1",
          "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "LeftToe_End",
          "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase", "RightToe_End"]
MATRICES = ["LeftHand", "RightHand", "Hips", "Spine2", "Head"]


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def bone_name(rig, short):
    for candidate in (PREFIX + short, short):
        if candidate in rig.pose.bones:
            return candidate
    for b in rig.pose.bones:
        if b.name.endswith(":" + short) or b.name.endswith(short):
            return b.name
    return None


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    src, out = Path(argv[0]), Path(argv[1])
    out.mkdir(parents=True, exist_ok=True)
    summary = []
    for fbx in sorted(src.glob("*.fbx")):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.fbx(filepath=str(fbx))
        scene = bpy.context.scene
        rig = next(o for o in scene.objects if o.type == "ARMATURE")
        action = rig.animation_data.action
        start, end = (int(round(v)) for v in action.frame_range)
        names = {j: bone_name(rig, j) for j in JOINTS}
        missing = [j for j, n in names.items() if n is None]
        frames = []
        for f in range(start, end + 1):
            scene.frame_set(f)
            mw = rig.matrix_world
            joints = {}
            for j, n in names.items():
                if n is None:
                    continue
                pb = rig.pose.bones[n]
                joints[j] = [round(v, 5) for v in (mw @ pb.head)]
            mats = {}
            for j in MATRICES:
                n = names.get(j)
                if n is None:
                    continue
                m = mw @ rig.pose.bones[n].matrix
                mats[j] = [[round(m[r][c], 5) for c in range(4)] for r in range(4)]
            frames.append({"joints": joints, "matrices": mats})
        fps = scene.render.fps / scene.render.fps_base
        doc = {"source": fbx.name, "fps": fps, "start": start, "end": end,
               "frames": frames, "missing": missing, "armature": rig.name,
               "scale": list(rig.scale)}
        (out / (slug(fbx.stem) + ".json")).write_text(json.dumps(doc), encoding="utf-8")
        summary.append({"file": fbx.name, "slug": slug(fbx.stem), "fps": fps,
                        "frames": len(frames), "missing": missing})
    (out / "_index.json").write_text(json.dumps(summary, indent=1), encoding="utf-8")
    print("MIXAMO_EXTRACT", json.dumps(summary))


main()
