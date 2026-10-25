"""Render review images of goblin_rabble_base.blend (run in a background Blender).

  blender -b goblin_rabble_base.blend --python render_check.py -- <out dir> [original body.fbx]

- chain_<view>.png: the chest from the side and the front. With the original
  Tripo FBX given, it is scaled the same way and shown on the left for comparison.
- lineup.png: the body and the five props, front view.
- fit_front.png, fit_threeq.png: three copies of the body, each with a weapon
  in the right hand and a shield on the left forearm, to judge the sizes.
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
original = Path(argv[1]) if len(argv) > 1 else None

sc = bpy.context.scene
body = bpy.data.objects["GoblinRabble"]
props = {o.name: o for o in bpy.data.collections["Props"].objects}
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


def shoot(name, centre, direction, size, res=(900, 900), near=0.1):
    d = Vector(direction).normalized()
    cam.location = Vector(centre) - d * 10
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    cam.data.ortho_scale = size
    cam.data.clip_start = near
    cam.data.clip_end = 30
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = str(out / f"{name}.png")
    bpy.ops.render.render(write_still=True)


def hide(objs, state):
    for o in objs:
        o.hide_render = state


# Chain: the fixed body, and the original beside it when given.
hide(props.values(), True)
before = None
if original:
    keep = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(original))
    new = [o for o in bpy.data.objects if o not in keep]
    before = next(o for o in new if o.type == "MESH")
    for o in new:
        if o is not before:
            bpy.data.objects.remove(o)
    bpy.context.view_layer.objects.active = before
    for o in bpy.context.selected_objects:
        o.select_set(False)
    before.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    V = np.array([v.co[:] for v in before.data.vertices])
    k = H / (V[:, 2].max() - V[:, 2].min())
    before.data.transform(Matrix.Translation((-np.median(V[:, 0]), -np.median(V[:, 1]), -V[:, 2].min())))
    before.data.transform(Matrix.Scale(k, 4))
# Side: a section through the middle (only x < 0.1 m), so the near arm does not
# hide the chest; the original goblin stands half a metre in front.
z0 = 0.68 * H
if before:
    before.location = (0, -0.55, 0)
shoot("chain_side", (0, -0.275 if before else 0, z0), (-1, 0, 0), 1.2 if before else 0.6,
      (1200, 900) if before else (900, 900), near=10 - 0.1)
if before:
    bpy.data.objects.remove(before)
shoot("chain_front", (0, 0, z0), (0, 1, 0), 0.5)

# Lineup: everything as saved.
hide(props.values(), False)
xs = [(o.matrix_world @ Vector(c)).x for o in [body, *props.values()] for c in o.bound_box]
shoot("lineup", ((min(xs) + max(xs)) / 2, 0, H * 0.5), (0, 1, 0), max(xs) - min(xs) + 0.2, (2000, 700))

# Fit check: three goblins, each holding a weapon and a shield.
V = np.array([v.co[:] for v in body.data.vertices])


def centre_of(x0, x1):
    m = (V[:, 0] > x0) & (V[:, 0] < x1) & (V[:, 2] > 0.6 * H)
    return Vector(V[m].mean(0)), V[m]


# Right hand (his right is -x): the palm, just under the flat T-pose hand.
hand_c, hand = centre_of(-0.76, -0.55)
grip = Vector((hand_c.x + 0.02, hand_c.y, hand[:, 2].min() + 0.01))
# Left forearm: the shield's back against the front of the forearm.
fore_c, fore = centre_of(0.30, 0.46)
strap = Vector((fore_c.x, fore[:, 1].min() - 0.005, fore_c.z))
sets = (("Knife", "ShieldBarrel"), ("Hatchet", "ShieldPlank"), ("Cleaver", "ShieldBarrel"))
step = 1.75
saved = {o.name: o.matrix_world.copy() for o in props.values()}
copies = []
for n, (weapon, shield) in enumerate(sets):
    off = Vector(((n - 1) * step, 0, 0))
    g = body if n == 1 else body.copy()
    if g is not body:
        sc.collection.objects.link(g)
        copies.append(g)
    g.location = off
    for pname, at in ((weapon, grip), (shield, strap)):
        p = props[pname] if n < 2 or pname != "ShieldBarrel" else props[pname].copy()
        if p.name not in props:
            sc.collection.objects.link(p)
            copies.append(p)
        p.matrix_world = Matrix.Translation(at + off)
hide([o for o in props.values() if o.name not in {w for s in sets for w in s}], True)
shoot("fit_front", (0, 0, H * 0.5), (0, 1, 0), 3 * step, (1800, 700))
shoot("fit_threeq", (0, 0, H * 0.5), (0.55, 0.8, -0.25), 3 * step, (1800, 800))
for o in copies:
    bpy.data.objects.remove(o)
for name, m in saved.items():
    props[name].matrix_world = m
print("CHECK_DONE", out)
