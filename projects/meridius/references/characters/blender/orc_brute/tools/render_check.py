"""Render review images of orc_brute_base.blend (run in a background Blender).

  blender -b orc_brute_base.blend --python render_check.py -- <out dir>

- lineup.png: the body and the two props, front view.
- body_<view>.png: the body from the front, back, both sides and three-quarter.
- holes_<view>.png: the same views with every back face drawn bright red, so a
  hole or an open shell the camera can look into shows at once.
- grip_<prop>_<deg>.png: each prop's grip from four sides, textured, and
  holes_grip_<prop>_<deg>.png the same with back faces in red.
- fit_front.png, fit_threeq.png: the club at the right hand and the knife at the
  left, to judge the sizes.
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
body = bpy.data.objects["OrcBrute"]
props = {o.name: o for o in bpy.data.collections["Props"].objects}
H = max((body.matrix_world @ Vector(c)).z for c in body.bound_box)

cam = bpy.data.objects.new("CheckCam", bpy.data.cameras.new("CheckCam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
sc.view_settings.view_transform = "Standard"


def workbench():
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.color_type = "TEXTURE"
    sh.show_object_outline = True
    sh.show_backface_culling = False
    sh.background_type = "VIEWPORT"
    sh.background_color = (0.43, 0.44, 0.47)


def eevee():
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = engine
            break
        except TypeError as err:
            print(err)
    world = sc.world or bpy.data.worlds.new("CheckWorld")
    sc.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.43, 0.44, 0.47, 1)
    bg.inputs[1].default_value = 1.0


def mark_back_faces():
    """Every material: back faces become flat red emission, front faces unchanged."""
    for mat in {s.material for o in [body, *props.values()] for s in o.material_slots if s.material}:
        nt = mat.node_tree
        mat.use_backface_culling = False
        outp = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        link = next(l for l in nt.links if l.to_node == outp and l.to_socket.name == "Surface")
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        red = nt.nodes.new("ShaderNodeEmission")
        red.inputs["Color"].default_value = (1, 0, 0, 1)
        red.inputs["Strength"].default_value = 1.0
        mix = nt.nodes.new("ShaderNodeMixShader")
        src = link.from_socket
        nt.links.remove(link)
        nt.links.new(geo.outputs["Backfacing"], mix.inputs[0])
        nt.links.new(src, mix.inputs[1])
        nt.links.new(red.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], outp.inputs["Surface"])


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


# He faces -Y: the front camera looks along +Y.
VIEWS = {"front": (0, 1, 0), "back": (0, -1, 0), "right": (1, 0, 0), "left": (-1, 0, 0),
         "threeq": (0.55, 0.8, -0.2)}


def body_views(prefix):
    hide(props.values(), True)
    for view, d in VIEWS.items():
        size = 2.4 if view in ("front", "back", "threeq") else 2.2
        shoot(f"{prefix}_{view}", (0, 0.05, H * 0.5), d, size, (1400, 1400))
    hide(props.values(), False)


def grip_views(prefix):
    """Each prop alone, its grip filling the frame, from four sides."""
    for name, p in props.items():
        others = [o for o in [body, *props.values()] if o is not p]
        hide(others, True)
        P = np.array([(p.matrix_world @ v.co)[:] for v in p.data.vertices])
        L = np.ptp(P[:, 2])
        z_mid = P[:, 2].min() + 0.22 * L
        c = Vector(((P[:, 0].min() + P[:, 0].max()) / 2, (P[:, 1].min() + P[:, 1].max()) / 2, z_mid))
        for deg in (0, 90, 180, 270):
            a = math.radians(deg)
            shoot(f"{prefix}_{name.lower()}_{deg:03d}", c, (math.sin(a), math.cos(a), -0.15), 0.48 * L, (900, 900))
        hide(others, False)


workbench()
xs = [(o.matrix_world @ Vector(c)).x for o in [body, *props.values()] for c in o.bound_box]
shoot("lineup", ((min(xs) + max(xs)) / 2, 0, H * 0.5), (0, 1, 0), max(max(xs) - min(xs), 2 * H) + 0.2, (2200, 1100))
body_views("body")
grip_views("grip")

# Fit: the club at the right hand (his right is -x), the knife at the left. The palm
# is the lowest point of the flat T-pose hand, a little in from the fingertips.
V = np.array([v.co[:] for v in body.data.vertices])


def hand(sign):
    m = (sign * V[:, 0] > 0.80) & (V[:, 2] > 0.6 * H)
    q = V[m]
    c = q.mean(0)
    return Vector((c[0], c[1], q[:, 2].min() + 0.015))


saved = {o.name: o.matrix_world.copy() for o in props.values()}
props["Club"].matrix_world = Matrix.Translation(hand(-1))
props["Knife"].matrix_world = Matrix.Translation(hand(1))
shoot("fit_front", (0, 0, H * 0.55), (0, 1, 0), 2.6, (1600, 1400))
shoot("fit_threeq", (0, 0, H * 0.55), (0.55, 0.8, -0.25), 2.6, (1600, 1400))
for n, m in saved.items():
    props[n].matrix_world = m

eevee()
mark_back_faces()
sc.render.resolution_percentage = 100
body_views("holes")
grip_views("holes_grip")
print("CHECK_DONE", out)
