"""Render review images of goblin_spear_base.blend (run in a background Blender).

  blender -b goblin_spear_base.blend --python render_check.py -- <out dir>

- body_<view>.png: the body from the front, the side, the back and three-quarter.
- lineup.png: the body and the spear, front view.
- spear_<view>.png: the spear's head and grip, front and side.
- fit_front.png, fit_threeq.png: the spear laid across both T-pose hands, to judge
  its length and the shaft against the hands.
"""
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out = Path(argv[0])
out.mkdir(parents=True, exist_ok=True)

sc = bpy.context.scene
body = bpy.data.objects["GoblinSpearman"]
spear = bpy.data.objects["Spear"]
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
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    cam.data.ortho_scale = size
    cam.data.clip_start = 0.1
    cam.data.clip_end = 30
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = str(out / f"{name}.png")
    bpy.ops.render.render(write_still=True)


# The body alone, four views.
spear.hide_render = True
for name, d in (("front", (0, 1, 0)), ("side", (-1, 0, 0)), ("back", (0, -1, 0)), ("threeq", (0.7, 0.7, -0.15))):
    shoot("body_" + name, (0, 0, H / 2), d, H * 1.12)
spear.hide_render = False

# Lineup, as saved.
xs = [(o.matrix_world @ Vector(c)).x for o in (body, spear) for c in o.bound_box]
zs = [(o.matrix_world @ Vector(c)).z for o in (body, spear) for c in o.bound_box]
shoot("lineup", ((min(xs) + max(xs)) / 2, 0, max(zs) / 2), (0, 1, 0), max(zs) * 1.08, (1100, 1100))

# The spear's head and grip, front and side.
P = np.array([(spear.matrix_world @ v.co)[:] for v in spear.data.vertices])
top, low = P[:, 2].max(), P[:, 2].min()
body.hide_render = True
for name, d in (("front", (0, 1, 0)), ("side", (-1, 0, 0))):
    shoot("spear_head_" + name, (spear.location.x, 0, top - 0.25), d, 0.55)
    shoot("spear_grip_" + name, (spear.location.x, 0, spear.location.z), d, 0.45)
body.hide_render = False

# Fit: the spear held level just in front of the T-pose arms, its grip at the right
# hand (his right is -x) and its head out past it.
V = np.array([v.co[:] for v in body.data.vertices])
hand = V[(V[:, 0] < -0.5 * V[:, 0].max()) & (V[:, 2] > 0.6 * H)]
hand = hand[hand[:, 0] < hand[:, 0].min() + 0.09]
at = Vector(hand.mean(0))
at.y = hand[:, 1].min() - spear["shaft_r"] - 0.005
saved = spear.matrix_world.copy()
spear.matrix_world = Matrix.Translation(at) @ Matrix.Rotation(math.radians(-90), 4, "Y")
shoot("fit_front", (0, 0, H * 0.55), (0, 1, 0), 3.2, (1600, 900))
shoot("fit_threeq", (0, 0, H * 0.55), (0.55, 0.8, -0.25), 3.2, (1600, 900))
spear.matrix_world = saved
print("CHECK_DONE", out, "body height %.3f, spear %.3f long" % (H, top - low))
