"""Build the spearman base scene from the Tripo exports (background Blender).

  blender -b --factory-startup --python build_spearman.py -- <body_tex.fbx> <spear.blend> <out.blend> [preview_dir]

Run with BLENDER_USER_RESOURCES pointing at a scratch folder: with --factory-startup and the
user's own profile, Blender removes the Python wheels of the profile's extensions.

1. Imports the textured Tripo body (v4: cape regenerated twice with Edit Mesh), scales it to
   1.82 m, feet at z = 0, centred, facing -Y.
2. Deletes the long slivers at the tabard's side slits that hang below the skirt hem.
3. Adds cloth folds to the cape's back, which Tripo left as a broad, nearly flat panel
   (no back view in the input): vertical folds fanning out towards the hem, displaced
   outwards only, so the cape never moves into the torso; the cape faces there are
   subdivided first so the folds are smooth.
4. Appends the forged-steel spear from build_spear.py's .blend (a separate object).
Saves the .blend with its textures packed; rigging comes next.
"""
import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

H = 1.82
argv = sys.argv[sys.argv.index("--") + 1:]
body_fbx, spear_blend, out_blend = Path(argv[0]), Path(argv[1]), Path(argv[2])
prev = Path(argv[3]) if len(argv) > 3 else None

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(body_fbx))
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = body.data.name = "Spearman"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(bpy.context.scene.objects):
    if o is not body:
        bpy.data.objects.remove(o)
me = body.data
V = np.array([v.co[:] for v in me.vertices])
k = H / (V[:, 2].max() - V[:, 2].min())
me.transform(Matrix.Translation((-(V[:, 0].max() + V[:, 0].min()) / 2, -(V[:, 1].max() + V[:, 1].min()) / 2, -V[:, 2].min())))
me.transform(Matrix.Scale(k, 4))
me.update()
assert np.mean([v.co.y for v in me.vertices if v.co.z > 1.55]) < 0.05, "expected the face towards -Y"

bm = bmesh.new(); bm.from_mesh(me)

# 2. Slit slivers: long thin faces in front, below the belt.
sliver = []
for f in bm.faces:
    ls = sorted(e.calc_length() for e in f.edges)
    c = f.calc_center_median()
    if ls[0] > 0 and ls[-1] / ls[0] > 12 and ls[-1] > 0.08 and c.z < 0.85 and c.y < 0.02 and 0.04 < abs(c.x) < 0.26:
        sliver.append(f)
print("SLIVERS", len(sliver), [tuple(round(x, 3) for x in f.calc_center_median()) for f in sliver])
bmesh.ops.delete(bm, geom=sliver, context="FACES")

# 3. Cape folds. Outermost back surface as a height map y_out(x, z).
X0, X1, Z0, Z1, CELL = -0.36, 0.36, 0.80, 1.52, 0.01
nx, nz = int((X1 - X0) / CELL) + 1, int((Z1 - Z0) / CELL) + 1
yout = np.full((nz, nx), -1.0)
for v in bm.verts:
    x, y, z = v.co
    if X0 <= x <= X1 and Z0 <= z <= Z1 and y > 0.03:
        i, j = int((z - Z0) / CELL), int((x - X0) / CELL)
        yout[i, j] = max(yout[i, j], y)
for _ in range(3):  # fill small holes in the map
    pad = np.pad(yout, 1, constant_values=-1.0)
    nb = np.max([pad[1 + di:nz + 1 + di, 1 + dj:nx + 1 + dj] for di in (-1, 0, 1) for dj in (-1, 0, 1)], axis=0)
    yout = np.where(yout < 0, nb, yout)

Z_TOP, Z_FULL, AMP, LAM = 1.40, 1.08, 0.016, 0.080
SHELL = 0.032   # vertices this close to the outermost back surface belong to the cape
clamp01 = lambda t: min(max(t, 0.0), 1.0)
smooth = lambda t: t * t * (3 - 2 * t)


def fold(x, z):
    """Outward fold depth: rounded ridges with broad valleys, fanning out downwards, zero at
    the top, at the sides and just above the hem (Tripo's own wavy hem stays as it is)."""
    t = clamp01((Z_TOP - z) / (Z_TOP - Z_FULL))
    a = AMP * smooth(t) * smooth(clamp01((z - Z_HEM) / 0.07))
    w = 1.0 - smooth(clamp01((abs(x) - 0.15) / 0.10))
    xs = x / (0.6 + 0.4 * t)
    ph = 2 * math.pi * xs / LAM + 0.4 * math.sin(7.0 * x + 4.0 * z)
    return a * w * (0.5 + 0.5 * math.sin(ph)) ** 1.6


def is_cape(co):
    x, y, z = co
    if not (-0.30 <= x <= 0.30 and Z0 <= z <= Z_TOP and y > 0.03):
        return False
    i, j = int((z - Z0) / CELL), int((x - X0) / CELL)
    return y > yout[i, j] - SHELL


# The hem: lowest cape vertex in the middle of the back.
Z_HEM = min(v.co.z for v in bm.verts if abs(v.co.x) < 0.12 and is_cape(v.co)) + 0.02
cape_faces = [f for f in bm.faces if all(is_cape(v.co) and Z_HEM <= v.co.z <= Z_TOP for v in f.verts)]
print("CAPE_FACES", len(cape_faces), "hem z", round(Z_HEM, 3))
edges = list({e for f in cape_faces for e in f.edges})
bmesh.ops.subdivide_edges(bm, edges=edges, cuts=3, use_grid_fill=True, smooth=0.0)
moved = 0
for v in bm.verts:
    if is_cape(v.co) and Z_HEM <= v.co.z <= Z_TOP:
        d = fold(v.co.x, v.co.z)
        if d > 0:
            v.co.y += d
            moved += 1
print("CAPE_VERTS_MOVED", moved)
bm.to_mesh(me); bm.free()
for p in me.polygons:
    p.use_smooth = True
me.update()

# 4. The spear, as its own object.
with bpy.data.libraries.load(str(spear_blend), link=False) as (src, dst):
    dst.objects = [n for n in src.objects if n == "Spear"]
spear = dst.objects[0]
bpy.context.scene.collection.objects.link(spear)
spear.location = (0.55, 0.25, 0.0)  # parked beside him until it is put in his hands
for m in list(me.materials) + list(spear.data.materials):
    if m and m.use_nodes:
        ims = [n for n in m.node_tree.nodes if n.type == "TEX_IMAGE"]
        if ims:
            m.node_tree.nodes.active = ims[0]
bpy.ops.file.pack_all()
out_blend.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(out_blend))
print("SAVED", out_blend, "body faces", len(me.polygons), "spear faces", len(spear.data.polygons))

if prev:
    prev.mkdir(parents=True, exist_ok=True)
    spear.hide_render = True
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sc.display.render_aa = "16"
    sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.18, 0.18, 0.2)
    cam_d = bpy.data.cameras.new("cam"); cam_d.type = "ORTHO"
    cam = bpy.data.objects.new("cam", cam_d); sc.collection.objects.link(cam); sc.camera = cam

    def shot(name, yaw, z, size, res, look):
        if look == "clay":
            sh.light = "STUDIO"; sh.color_type = "SINGLE"; sh.single_color = (0.78, 0.78, 0.78)
            sh.show_cavity = True; sh.cavity_type = "BOTH"; sh.show_object_outline = False
        else:
            sh.light = "FLAT"; sh.color_type = "TEXTURE"; sh.show_object_outline = True
            sh.object_outline_color = (0.09, 0.07, 0.07); sh.show_cavity = True; sh.cavity_type = "WORLD"
        sc.render.resolution_x, sc.render.resolution_y = res
        cam_d.ortho_scale = size
        a = math.radians(yaw); d = Vector((math.sin(a), -math.cos(a), 0.14)).normalized()
        cam.location = Vector((0, 0, z)) + d * 10
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = str(prev / f"{name}.png"); bpy.ops.render.render(write_still=True)

    for nm, yaw in [("back", 180), ("back34", 145), ("side", 90), ("front34", 330)]:
        shot(nm + "_clay", yaw, 1.05, 1.5, (700, 820), "clay")
        shot(nm + "_tex", yaw, 1.05, 1.5, (700, 820), "tex")
print("DONE")
