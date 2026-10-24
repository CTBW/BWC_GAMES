"""Inspect a long prop (spear) FBX: straightness of the shaft, parts, open edges, and close-up renders.

  blender -b --factory-startup --python inspect_prop.py -- <in.fbx> <out_dir> [length_m]
"""
import bmesh, bpy, json, math, sys
from collections import deque
from pathlib import Path
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
src, out = Path(argv[0]), Path(argv[1]); out.mkdir(parents=True, exist_ok=True)
L = float(argv[2]) if len(argv) > 2 else 2.4
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(src))
ms = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in ms:
    o.select_set(True)
bpy.context.view_layer.objects.active = ms[0]
if len(ms) > 1:
    bpy.ops.object.join()
obj = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = obj.data
V = [v.co.copy() for v in me.vertices]
ext = [max(v[i] for v in V) - min(v[i] for v in V) for i in range(3)]
ax = ext.index(max(ext))
k = L / ext[ax]
lo = min(v[ax] for v in V)
c = [(max(v[i] for v in V) + min(v[i] for v in V)) / 2 for i in range(3)]
T = Matrix.Translation(Vector([-c[0], -c[1], -c[2]]))
me.transform(T); me.transform(Matrix.Scale(k, 4))
# Put the long axis on Z.
if ax == 0:
    me.transform(Matrix.Rotation(math.radians(-90), 4, "Y"))
elif ax == 1:
    me.transform(Matrix.Rotation(math.radians(90), 4, "X"))
me.update()
zs = [v.co.z for v in me.vertices]
me.transform(Matrix.Translation((0, 0, -min(zs)))); me.update()

bm = bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
rep = {"verts": len(bm.verts), "faces": len(bm.faces), "boundary_edges": sum(e.is_boundary for e in bm.edges),
       "non_manifold": sum((not e.is_manifold) and (not e.is_boundary) for e in bm.edges),
       "extent_m": [round(e * k, 3) for e in ext]}
seen = set(); parts = []
for f0 in bm.faces:
    if f0.index in seen:
        continue
    q = deque([f0]); seen.add(f0.index); n = 0; zz = []
    while q:
        f = q.popleft(); n += 1; zz += [v.co.z for v in f.verts]
        for e in f.edges:
            for g in e.link_faces:
                if g.index not in seen:
                    seen.add(g.index); q.append(g)
    parts.append({"faces": n, "z": [round(min(zz), 3), round(max(zz), 3)]})
rep["parts"] = parts
# Shaft straightness: centre of the cross-section every 5 cm.
prof = []
H = max(v.co.z for v in bm.verts)
for i in range(1, 60):
    z = H * i / 60
    sl = [v.co for v in bm.verts if abs(v.co.z - z) < H / 120]
    if len(sl) >= 3:
        cx = sum(p.x for p in sl) / len(sl); cy = sum(p.y for p in sl) / len(sl)
        r = max(math.hypot(p.x - cx, p.y - cy) for p in sl)
        prof.append((round(z, 3), round(cx * 1000, 1), round(cy * 1000, 1), round(r * 1000, 1)))
rep["profile_mm"] = prof
(out / "report.json").write_text(json.dumps(rep, indent=1))
print("REPORT", json.dumps({k2: v for k2, v in rep.items() if k2 != "profile_mm"}))
bm.free()
for p in me.polygons:
    p.use_smooth = True
if hasattr(me, "set_sharp_from_angle"):
    me.set_sharp_from_angle(angle=math.radians(40))
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading; sh.light = "STUDIO"; sh.color_type = "TEXTURE" if me.uv_layers and obj.active_material else "SINGLE"
sh.single_color = (0.78, 0.78, 0.78); sh.show_cavity = True; sh.cavity_type = "BOTH"
sc.display.render_aa = "16"
sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.16, 0.16, 0.18)
cam_d = bpy.data.cameras.new("cam"); cam_d.type = "ORTHO"
cam = bpy.data.objects.new("cam", cam_d); sc.collection.objects.link(cam); sc.camera = cam


def shot(name, yaw, z, size, res):
    sc.render.resolution_x, sc.render.resolution_y = res
    cam_d.ortho_scale = size
    a = math.radians(yaw); d = Vector((math.sin(a), -math.cos(a), 0.05)).normalized()
    cam.location = Vector((0, 0, z)) + d * 10
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = str(out / f"{name}.png"); bpy.ops.render.render(write_still=True)


for nm, yaw in [("full_0", 0), ("full_90", 90)]:
    shot(nm, yaw, L / 2, L * 1.05, (300, 1300))
for nm, yaw in [("head_0", 0), ("head_45", 45), ("head_90", 90)]:
    shot(nm, yaw, L - 0.25, 0.55, (500, 600))
shot("butt", 30, 0.08, 0.2, (400, 400))
print("DONE")
