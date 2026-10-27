"""Frames of the goblin shaman for the Workspace pose viewer, from the game's battle camera
(orthographic, 30 degree elevation) in the four facings, as goblin_rabble/tools/render_clips.py:
flat-lit textures with an outline and cavity, at the rabble's 254.5 px per metre.

The shaman has no animation clips yet, so this renders two of the rig's poses:
* `stand`: the standard pose, one frame.
* `head`: the head turned 40 degrees left and right, nodded 25 degrees down and up and tilted
  15 degrees each way (render_rig.py's mask checks), the neck taking 0.4 of each turn and the
  head 0.6, eased, in 104 frames that loop. It is keyed on a copy of `stand` that is not saved.

  blender -b goblin_shaman_rig.blend --python render_clips.py -- <out dir> <variant>

Frames go to <out dir>/<pose>_<variant>_<facing>/NNNN.png (e.g. head_beak_se/0000.png), for
goblin_rabble/tools/pack_sheets.py.
"""
import math
import os
import sys
import time
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out, variant = Path(argv[0]), argv[1]
sc = bpy.context.scene
rig = bpy.data.objects["GoblinShamanRig"]
MX = "mixamorig:"
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
# 640 x 640 px at the rabble's 560 / 2.2 px per metre holds the staff's top (1.88 m) and its
# foot, out to his right, in all four facings.
W, H = int(os.environ.get("CLIP_W", 640)), int(os.environ.get("CLIP_H", 640))
sc.render.resolution_x, sc.render.resolution_y = W, H
sc.render.resolution_percentage = 100
sc.view_settings.view_transform = "Standard"
CLIP_SCALE = float(os.environ.get("CLIP_SCALE", 2.2 * max(W, H) / 560))
CLIP_Z = float(os.environ.get("CLIP_Z", 0.9))
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


def under_rig(o):
    while o.parent is not None:
        o = o.parent
        if o == rig:
            return True
    return False


for o in sc.objects:
    if o.type == "MESH" and o.name.startswith(("WGT", "Widget")):
        o.hide_render = True
shown = sorted(o.name for o in sc.objects if o.type == "MESH" and not o.hide_render and o.visible_get())
loose = [n for n in shown if not under_rig(bpy.data.objects[n])]
print("SHOWN", variant, shown, "| not under the rig:", loose)
assert not loose, loose

# The head sweep: (frames, (x, y, z) degrees) from the previous key, eased; the last key is the
# first frame again, so it is left out and the clip loops.
SWEEP = [(10, (0, 40, 0)), (20, (0, -40, 0)), (10, (0, 0, 0)),
         (8, (25, 0, 0)), (16, (-25, 0, 0)), (8, (0, 0, 0)),
         (8, (0, 0, 15)), (16, (0, 0, -15)), (8, (0, 0, 0))]
keys = [(0.0, 0.0, 0.0)]
for n, target in SWEEP:
    a = keys[-1]
    for i in range(1, n + 1):
        t = i / n
        t = t * t * (3 - 2 * t)
        keys.append(tuple(a[k] + (target[k] - a[k]) * t for k in range(3)))
keys = keys[:-1]

stand = bpy.data.actions["stand"]
head = stand.copy()
head.name = "head_sweep"
rig.animation_data.action = head
rig.animation_data.action_slot = head.slots[0]
for f, (ax, ay, az) in enumerate(keys, 1):
    for bone, share in ((MX + "Neck", 0.4), (MX + "Head", 0.6)):
        pb = rig.pose.bones[bone]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (Quaternion((1, 0, 0), math.radians(ax * share))
                                  @ Quaternion((0, 1, 0), math.radians(ay * share))
                                  @ Quaternion((0, 0, 1), math.radians(az * share)))
        pb.keyframe_insert("rotation_quaternion", frame=f)
print("SWEEP", len(keys), "frames")

# Game facings: the character faces -Y; the camera looks from the screen's bottom at 30
# degrees. SE = turned 45 degrees to the camera's right, etc.
YAW = {"se": 45, "sw": -45, "ne": 135, "nw": -135}
base = rig.matrix_world.copy()
aim(0, 30, CLIP_SCALE, Vector((0, 0, CLIP_Z)))
t0 = time.time()
for pose, act, n in (("stand", stand, 1), ("head", head, len(keys))):
    rig.animation_data.action = act
    rig.animation_data.action_slot = act.slots[0]
    cid = f"{pose}_{variant}"
    for fk, yaw in YAW.items():
        rig.matrix_world = Matrix.Rotation(math.radians(yaw), 4, "Z") @ base
        d = out / f"{cid}_{fk}"
        d.mkdir(parents=True, exist_ok=True)
        for i in range(n):
            sc.frame_set(i + 1)
            sc.render.filepath = str(d / f"{i:04d}.png")
            bpy.ops.render.render(write_still=True)
        print("RENDERED", cid, fk, n, "frames, %.0f s so far" % (time.time() - t0))
rig.matrix_world = base
print("RENDER_DONE", out)
