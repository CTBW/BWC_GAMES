"""Contact sheets of the succubus clips (background Blender).

  blender -b succubus_anim.blend --python render_clips.py -- <out dir> <clip,clip...> [step] [views]

For each clip, every `step` frames, from each view: "se" / "sw" / "ne" / "nw" are the game's
camera (orthographic, 30 degrees down) with her turned to that facing; "side", "front"
and "back" are level. Flat-lit textures with an outline, close to the game's look. Writes one PNG per
frame (<clip>_<view>_<frame>.png).
"""
import math
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out = Path(argv[0])
clips = argv[1].split(",")
step = int(argv[2]) if len(argv) > 2 else 4
views = (argv[3] if len(argv) > 3 else "se,side").split(",")
out.mkdir(parents=True, exist_ok=True)
sc = bpy.context.scene
rig = bpy.data.objects["SuccubusRig"]
sc.render.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light = "FLAT"
sh.color_type = "TEXTURE"
sh.show_object_outline = True
sh.object_outline_color = (0.09, 0.07, 0.07)
sh.show_cavity = True
sh.cavity_type = "WORLD"
sc.display.render_aa = "8"
sc.render.film_transparent = False
sc.world = bpy.data.worlds.new("w")
sc.world.color = (0.18, 0.18, 0.2)
sc.render.resolution_x, sc.render.resolution_y = 360, 420
cam_d = bpy.data.cameras.new("cam")
cam_d.type = "ORTHO"
cam = bpy.data.objects.new("cam", cam_d)
sc.collection.objects.link(cam)
sc.camera = cam
YAW = {"se": 45, "sw": -45, "ne": 135, "nw": -135}


def aim(view, target):
    if view in YAW:
        rig.rotation_euler = Euler((0, 0, math.radians(YAW[view])))
        el, az = math.radians(30), 0.0
    else:
        rig.rotation_euler = Euler((0, 0, 0))
        el, az = 0.0, math.radians({"side": 90, "back": 180}.get(view, 0))
    d = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    cam.location = target + d * 10
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    cam_d.ortho_scale = 3.2


for clip in clips:
    act = bpy.data.actions[clip]
    rig.animation_data.action = act
    n = int(act["frames"])
    for view in views:
        paths = []
        for f in range(1, n + 1, step):
            sc.frame_set(f)
            hips = rig.matrix_world @ rig.pose.bones["mixamorig:Hips"].head
            aim(view, Vector((hips.x, hips.y, 1.05)))
            p = out / f"{clip}_{view}_{f:03d}.png"
            sc.render.filepath = str(p)
            bpy.ops.render.render(write_still=True)
            paths.append(p)
        print("CLIP_FRAMES", clip, view, len(paths))
    rig.rotation_euler = Euler((0, 0, 0))
print("CLIPS_DONE")
