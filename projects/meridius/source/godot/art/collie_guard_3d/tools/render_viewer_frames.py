"""Render every frame of the collie's clips for the Workspace pose viewer (background Blender).

  blender -b collie_anim.blend --python render_viewer_frames.py -- <out dir> [clip[=name][:wide],...] [facings]

As the footman's (footman_3d/tools/render_preview.py, mode "clip"), whose clips he plays:
the game's camera (orthographic, 30 degrees down), flat textures with an outline, cavity,
transparent film, 2.6 m over 560 px (215 px per metre), 520 x 560 px; a clip marked ":wide" (the guard,
the blows, the charges and the death, which carry him out of that frame) gets 1000 x 960 px with the same
centre. One PNG per frame at 30 fps in <out>/<name>_<facing>/NNNN.png, and
<out>/render_info.json. "=name" renames a clip to the game's name, as export_godot.py does
(the .blend's "stand" is his idle, its "idle" the guard idle). The facings default to all
four; run one per process to render them side by side.
crossbowman_3d/tools/build_sheets.py packs the frames.
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
specs = argv[1].split(",") if len(argv) > 1 and argv[1] else [
    "stand=idle", "idle=idle_guard:wide", "start", "walk", "stop", "attack:wide", "block", "hit", "block_hit",
    "death:wide", "lane=step_lane", "turn_90", "turn_180", "run", "charge_hit:wide", "attack_stab:wide",
    "charge_stab:wide", "attack_thrust:wide", "charge_thrust:wide"]
facings = (argv[2] if len(argv) > 2 and argv[2] else "sw,se,nw,ne").split(",")
sc = bpy.context.scene
rig = bpy.data.objects["CollieRig"]
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
W, H = 520, 560
YAW = {"se": 45, "sw": -45, "ne": 135, "nw": -135}
el = math.radians(30)
d = Vector((0, -math.cos(el), math.sin(el)))
cam.location = Vector((0, 0, 0.9)) + d * 10
cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
rig.animation_data_create()
info = {}
for spec in specs:
    spec, _, wide = spec.partition(":")
    clip, _, name = spec.partition("=")
    name = name or clip
    w, h = (1000, 960) if wide == "wide" else (W, H)
    sc.render.resolution_x, sc.render.resolution_y = w, h
    cam_data.ortho_scale = 2.6 * max(w, h) / H
    act = bpy.data.actions[clip]
    rig.animation_data.action = act
    f0, f1 = (int(round(v)) for v in act.frame_range)
    for fk in facings:
        rig.rotation_euler = Euler((0, 0, math.radians(YAW[fk])))
        dd = out / f"{name}_{fk}"
        dd.mkdir(parents=True, exist_ok=True)
        for i, f in enumerate(range(f0, f1 + 1)):
            sc.frame_set(f)
            sc.render.filepath = str(dd / f"{i:04d}.png")
            bpy.ops.render.render(write_still=True)
    info[name] = {"frames": f1 - f0 + 1, "canvas": [w, h]}
    print("CLIP_RENDERED", name, f1 - f0 + 1, "frames x", len(facings), "facings", flush=True)
rig.rotation_euler = Euler((0, 0, 0))
(out / "render_info.json").write_text(json.dumps(info, indent=1))
print("RENDER_DONE", out)
