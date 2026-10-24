"""Close-up renders of chosen frames (background Mixar / Blender).

  mixar.exe --background <rig.blend> --python render_frames.py -- <out dir> <action:frame:facing:scale[:bone]> ...

Same camera and look as render_preview.py; `scale` is the orthographic size
(smaller = closer) and `bone` the bone the camera centres on.
"""
import math
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out = Path(argv[0])
out.mkdir(parents=True, exist_ok=True)
sc = bpy.context.scene
rig = bpy.data.objects["FootmanRig"]
sc.render.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light = "FLAT"
sh.color_type = "TEXTURE"
sh.show_object_outline = True
sh.object_outline_color = (0.09, 0.07, 0.07)
sh.show_cavity = True
sh.cavity_type = "WORLD"
sc.display.render_aa = "8"
sc.render.film_transparent = True
sc.render.resolution_x = 520
sc.render.resolution_y = 560
cam_data = bpy.data.cameras.new("CloseCam")
cam_data.type = "ORTHO"
cam = bpy.data.objects.new("CloseCam", cam_data)
sc.collection.objects.link(cam)
sc.camera = cam
YAW = {"se": 45, "sw": -45, "ne": 135, "nw": -135, "front": 0, "right": 90, "left": -90}
rig.animation_data_create()
for spec in argv[1:]:
    parts = spec.split(":")
    act, frame, facing, scale = parts[0], int(parts[1]), parts[2], float(parts[3])
    bone = parts[4] if len(parts) > 4 else None
    if act == "rest":
        rig.animation_data.action = None
        for pb in rig.pose.bones:
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.location = (0, 0, 0)
    else:
        rig.animation_data.action = bpy.data.actions[act]
    rig.rotation_euler = Euler((0, 0, math.radians(YAW[facing])))
    sc.frame_set(frame)
    bpy.context.view_layer.update()
    target = Vector((0, 0, 0.9))
    if bone:
        target = rig.matrix_world @ rig.pose.bones["mixamorig:" + bone].head
    el = math.radians(0 if facing in ("front", "right", "left") else 30)
    d = Vector((0, -math.cos(el), math.sin(el)))
    cam.location = target + d * 8
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    cam_data.ortho_scale = scale
    sc.render.filepath = str(out / f"{act}_{facing}_f{frame:03d}{'_' + bone if bone else ''}.png")
    bpy.ops.render.render(write_still=True)
rig.rotation_euler = Euler((0, 0, 0))
print("FRAMES_DONE", out)
