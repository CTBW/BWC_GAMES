"""Render review images of goblin_shaman_base.blend (run in a background Blender).

  blender -b goblin_shaman_base.blend --python render_check.py -- <out dir>

- body_<view>.png: the body with the mask on, front, side, back and three-quarter.
- head_<view>.png: the head and the mask close up from the front, the side, three-quarter,
  above and behind, to judge the fit round the face and the ears.
- lineup.png: the body and the staff, front view.
- staff_<part>_<view>.png: the staff's skull and grip, front and side.
"""
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out = Path(argv[0])
out.mkdir(parents=True, exist_ok=True)

sc = bpy.context.scene
body = bpy.data.objects["GoblinShaman"]
staff = bpy.data.objects["Staff"]
mask = bpy.data.objects["MaskPlate"]
H = max((body.matrix_world @ Vector(c)).z for c in body.bound_box)

try:
    sc.render.engine = "BLENDER_WORKBENCH"
except TypeError as err:
    print(err)
sh = sc.display.shading
sh.light = "STUDIO"
sh.color_type = "TEXTURE"
sh.show_object_outline = True
sh.background_type = "VIEWPORT"
sh.background_color = (0.43, 0.44, 0.47)
sc.view_settings.view_transform = "Standard"

cam = bpy.data.objects.new("CheckCam", bpy.data.cameras.new("CheckCam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"


def shoot(name, centre, direction, size, res=(900, 900)):
    d = Vector(direction).normalized()
    cam.location = Vector(centre) - d * 10
    up = Vector((0, 1, 0)) if abs(d.z) > 0.9 else Vector((0, 0, 1))
    cam.rotation_euler = d.to_track_quat("-Z", "Y" if up.z else "Z").to_euler()
    if abs(d.z) > 0.9:
        cam.rotation_euler = (0, 0, 0) if d.z < 0 else (3.14159265, 0, 0)
    cam.data.ortho_scale = size
    cam.data.clip_start = 0.1
    cam.data.clip_end = 30
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = str(out / f"{name}.png")
    bpy.ops.render.render(write_still=True)


staff.hide_render = True
for name, d in (("front", (0, 1, 0)), ("side", (-1, 0, 0)), ("back", (0, -1, 0)), ("threeq", (0.7, 0.7, -0.15))):
    shoot("body_" + name, (0, 0, H / 2), d, H * 1.12)
M = np.array([(mask.matrix_world @ v.co)[:] for v in mask.data.vertices])
hc = Vector((0, float(M[:, 1].mean()) + 0.06, float(M[:, 2].mean()) - 0.02))
for name, d in (("front", (0, 1, 0)), ("side", (-1, 0, 0)), ("threeq", (0.7, 0.7, -0.1)),
                ("top", (0, 0, -1)), ("back34", (-0.6, -0.8, -0.2)), ("under", (0.3, 0.5, 0.8))):
    shoot("head_" + name, hc, d, 0.48)
staff.hide_render = False

xs = [(o.matrix_world @ Vector(c)).x for o in (body, staff) for c in o.bound_box]
zs = [(o.matrix_world @ Vector(c)).z for o in (body, staff) for c in o.bound_box]
shoot("lineup", ((min(xs) + max(xs)) / 2, 0, max(zs) / 2), (0, 1, 0), max(max(zs), max(xs) - min(xs)) * 1.08, (1100, 1100))

P = np.array([(staff.matrix_world @ v.co)[:] for v in staff.data.vertices])
top = P[:, 2].max()
body.hide_render = mask.hide_render = True
for name, d in (("front", (0, 1, 0)), ("side", (-1, 0, 0))):
    shoot("staff_head_" + name, (staff.location.x, 0, top - 0.25), d, 0.55)
    shoot("staff_grip_" + name, (staff.location.x, 0, staff.location.z), d, 0.45)
body.hide_render = mask.hide_render = False
print("CHECK_DONE", out, "body height %.3f, staff %.3f long" % (H, top - P[:, 2].min()))
