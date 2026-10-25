"""Frames of the goblin's clips for the Workspace pose viewer, from the game's battle camera
(orthographic, 30 degree elevation) in the four facings, as spearman_3d/tools/render_preview.py
mode "clip": flat-lit textures with an outline and cavity.

  blender -b goblin_clips.blend --python render_clips.py -- <out dir> <id=action:loadout> ...

Frames go to <out dir>/<id>_<facing>/NNNN.png, every frame of the action.
"""
import math
import os
import sys
import time
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out, specs = Path(argv[0]), argv[1:]
sc = bpy.context.scene
rig = bpy.data.objects["GoblinRabbleRig"]
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
# The frame (CLIP_W x CLIP_H px) at a fixed 560 / 2.2 px per metre, so a wider frame shows
# more round the goblin rather than a smaller goblin. 780 x 580 holds every frame of the
# death in all four facings.
W, H = int(os.environ.get("CLIP_W", 780)), int(os.environ.get("CLIP_H", 580))
sc.render.resolution_x, sc.render.resolution_y = W, H
sc.render.resolution_percentage = 100
sc.view_settings.view_transform = "Standard"
CLIP_SCALE = float(os.environ.get("CLIP_SCALE", 2.2 * max(W, H) / 560))
CLIP_Z = float(os.environ.get("CLIP_Z", 0.62))
cam_data = bpy.data.cameras.new("PreviewCam")
cam_data.type = "ORTHO"
cam = bpy.data.objects.new("PreviewCam", cam_data)
sc.collection.objects.link(cam)
sc.camera = cam


def aim(az_deg, elev_deg, scale, target, dist=8.0):
    az, el = math.radians(az_deg), math.radians(elev_deg)
    d = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    cam.location = target + d * dist
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    cam_data.ortho_scale = scale


# Game facings: the character faces -Y; the camera looks from the screen's bottom at 30
# degrees. SE = turned 45 degrees to the camera's right, etc.
YAW = {"se": 45, "sw": -45, "ne": 135, "nw": -135}
base = rig.matrix_world.copy()
aim(0, 30, CLIP_SCALE, Vector((0, 0, CLIP_Z)))
t0 = time.time()
for spec in specs:
    cid, _, rest = spec.partition("=")
    aname, _, loadout = rest.partition(":")
    act = bpy.data.actions[aname]
    rig.animation_data.action = act
    rig.animation_data.action_slot = act.slots[0]
    rig["loadout"] = int(loadout)
    n = int(act["frames"])
    for fk, yaw in YAW.items():
        rig.matrix_world = Matrix.Rotation(math.radians(yaw), 4, "Z") @ base
        d = out / f"{cid}_{fk}"
        d.mkdir(parents=True, exist_ok=True)
        for i in range(n):
            sc.frame_set(i + 1)
            sc.render.filepath = str(d / f"{i:04d}.png")
            bpy.ops.render.render(write_still=True)
        print("RENDERED", cid, fk, n, "frames, %.0f s so far" % (time.time() - t0))
    shown = sorted(o.name for o in rig.children if o.type == "MESH" and not o.hide_render)
    print("LOADOUT", cid, loadout, shown)
rig.matrix_world = base
print("RENDER_DONE", out)
