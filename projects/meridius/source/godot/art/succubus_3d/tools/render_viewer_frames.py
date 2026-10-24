"""Render every frame of the succubus clips for the Workspace pose viewer (background Blender).

  blender -b succubus_anim.blend --python render_viewer_frames.py -- <out dir> [clip[:wide],clip...] [facings]

As crossbowman_3d/tools/render_clips.py: the game's camera (orthographic, 30 degrees
down), flat textures with an outline, transparent film, 200 px per metre, one PNG per
frame at 30 fps in <out>/<clip>_<facing>/NNNN.png and <out>/render_info.json. Her canvas
is larger (her wings span 2 m and reach 1.9 m up); a clip marked ":wide" (start and stop
walking, which travel 1.5 m, the death, which falls 1.3 m aside, and the attack, whose
lash reaches 2.5 m from her) gets one twice as wide and tall. crossbowman_3d/tools/build_sheets.py packs the frames.
"""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out = Path(argv[0])
out.mkdir(parents=True, exist_ok=True)
specs = argv[1].split(",") if len(argv) > 1 and argv[1] else \
    ["idle", "idle_flourish", "walk", "walk_start:wide", "walk_stop:wide", "attack:wide", "hit", "death:wide"]
facings = (argv[2] if len(argv) > 2 else "sw,se,nw,ne").split(",")
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
sc.render.film_transparent = True
cam_data = bpy.data.cameras.new("ClipCam")
cam_data.type = "ORTHO"
cam = bpy.data.objects.new("ClipCam", cam_data)
sc.collection.objects.link(cam)
sc.camera = cam
W, H = 760, 680
SCALE = W / 200.0          # 200 px per metre, as the other rigs' viewers
YAW = {"se": 45, "sw": -45, "ne": 135, "nw": -135}
el = math.radians(30)
d = Vector((0, -math.cos(el), math.sin(el)))
cam.location = Vector((0, 0, 1.0)) + d * 10
cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
rig.animation_data_create()
info = {}
for spec in specs:
    name, _, wide = spec.partition(":")
    k = 2.0 if wide == "wide" else 1.0
    sc.render.resolution_x, sc.render.resolution_y = int(W * k), int(H * k)
    cam_data.ortho_scale = SCALE * k
    act = bpy.data.actions[name]
    rig.animation_data.action = act
    n = int(act["frames"])
    for fk in facings:
        rig.rotation_euler = Euler((0, 0, math.radians(YAW[fk])))
        dd = out / f"{name}_{fk}"
        dd.mkdir(parents=True, exist_ok=True)
        for i, f in enumerate(range(1, n + 1)):
            sc.frame_set(f)
            sc.render.filepath = str(dd / f"{i:04d}.png")
            bpy.ops.render.render(write_still=True)
    info[name] = {"frames": n, "canvas": [int(W * k), int(H * k)]}
    print("CLIP_RENDERED", name, n, "frames x", len(facings), "facings", flush=True)
rig.rotation_euler = Euler((0, 0, 0))
(out / "render_info.json").write_text(json.dumps(info, indent=1))
print("RENDER_DONE", out)
