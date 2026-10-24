"""Inspect a Tripo FBX in background Blender: geometry report + smooth-shaded review renders.

  blender -b --factory-startup --python inspect_mesh.py -- <in.fbx> <out_dir> [height_m]

Report (report.json): faces by type, components and their sizes, open (boundary) and
non-manifold edges, degenerate faces, flipped-normal estimate, and the largest flat
patches (faces grown while every normal stays within 4 degrees of the seed normal).
Renders: turnaround (front, 3/4, side, back...), close-ups, a flat-patch map (red = flat
patch bigger than 1% of the surface), and a wireframe front.
"""
import bmesh, bpy, json, math, sys
from collections import deque
from pathlib import Path
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
src, out = Path(argv[0]), Path(argv[1])
H = float(argv[2]) if len(argv) > 2 else 1.82
out.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(src))
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
obj = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = obj.data
zs = [v.co.z for v in me.vertices]
k = H / (max(zs) - min(zs))
xs = [v.co.x for v in me.vertices]; ys = [v.co.y for v in me.vertices]
me.transform(Matrix.Translation((-(max(xs) + min(xs)) / 2, -(max(ys) + min(ys)) / 2, -min(zs))))
me.transform(Matrix.Scale(k, 4))
me.update()

bm = bmesh.new(); bm.from_mesh(me)
bm.faces.ensure_lookup_table(); bm.edges.ensure_lookup_table(); bm.verts.ensure_lookup_table()
rep = {"file": src.name, "verts": len(bm.verts), "faces": len(bm.faces),
       "tris": sum(1 for f in bm.faces if len(f.verts) == 3), "quads": sum(1 for f in bm.faces if len(f.verts) == 4),
       "ngons": sum(1 for f in bm.faces if len(f.verts) > 4)}
rep["boundary_edges"] = sum(1 for e in bm.edges if e.is_boundary)
rep["non_manifold_edges"] = sum(1 for e in bm.edges if not e.is_manifold and not e.is_boundary)
rep["wire_edges"] = sum(1 for e in bm.edges if e.is_wire)
rep["degenerate_faces"] = sum(1 for f in bm.faces if f.calc_area() < 1e-8)
total = sum(f.calc_area() for f in bm.faces)
rep["surface_m2"] = round(total, 4)
# Components.
seen = set(); comps = []
for f0 in bm.faces:
    if f0.index in seen:
        continue
    q = deque([f0]); seen.add(f0.index); fs = []
    while q:
        f = q.popleft(); fs.append(f)
        for e in f.edges:
            for g in e.link_faces:
                if g.index not in seen:
                    seen.add(g.index); q.append(g)
    c = sum((f.calc_center_median() for f in fs), Vector()) / len(fs)
    comps.append({"faces": len(fs), "area": round(sum(f.calc_area() for f in fs), 5), "center": [round(v, 3) for v in c]})
comps.sort(key=lambda c: -c["faces"])
rep["components"] = len(comps)
rep["component_list"] = comps[:40]
# Flat patches.
cos_t = math.cos(math.radians(4))
flat_of = {}
patches = []
for f0 in sorted(bm.faces, key=lambda f: -f.calc_area()):
    if f0.index in flat_of:
        continue
    n0 = f0.normal.copy(); q = deque([f0]); flat_of[f0.index] = len(patches); fs = [f0]
    while q:
        f = q.popleft()
        for e in f.edges:
            for g in e.link_faces:
                if g.index not in flat_of and g.normal.dot(n0) > cos_t:
                    flat_of[g.index] = len(patches); q.append(g); fs.append(g)
    a = sum(f.calc_area() for f in fs)
    c = sum((f.calc_center_median() for f in fs), Vector()) / len(fs)
    patches.append({"faces": len(fs), "area_pct": round(100 * a / total, 2), "center": [round(v, 3) for v in c],
                    "normal": [round(v, 2) for v in n0]})
order = sorted(range(len(patches)), key=lambda i: -patches[i]["area_pct"])
rep["flat_patches_over_1pct"] = [patches[i] for i in order if patches[i]["area_pct"] >= 1.0]
rep["flat_patch_area_pct_total_over_1pct"] = round(sum(p["area_pct"] for p in rep["flat_patches_over_1pct"]), 2)
big = {i for i in order if patches[i]["area_pct"] >= 1.0}
(out / "report.json").write_text(json.dumps(rep, indent=1))
print("REPORT", json.dumps({k: v for k, v in rep.items() if k not in ("component_list", "flat_patches_over_1pct")}))

# Materials: neutral clay + flat-patch highlight via vertex colours.
col = me.color_attributes.new("flat", "BYTE_COLOR", "CORNER")
for poly in me.polygons:
    c = (0.85, 0.2, 0.2, 1) if flat_of.get(poly.index) in big else (0.8, 0.8, 0.8, 1)
    for li in poly.loop_indices:
        col.data[li].color = c
bm.free()
for p in me.polygons:
    p.use_smooth = True
if hasattr(me, "set_sharp_from_angle"):
    me.set_sharp_from_angle(angle=math.radians(60))

sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light = "STUDIO"; sh.color_type = "SINGLE"; sh.single_color = (0.78, 0.78, 0.78)
sh.show_cavity = True; sh.cavity_type = "BOTH"; sh.cavity_ridge_factor = 1.0; sh.cavity_valley_factor = 1.0
sh.show_object_outline = False; sh.show_specular_highlight = True
sc.display.render_aa = "16"
sc.render.film_transparent = False
sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.16, 0.16, 0.18)
sc.render.resolution_x, sc.render.resolution_y = 900, 1100
cam_d = bpy.data.cameras.new("cam"); cam_d.type = "ORTHO"
cam = bpy.data.objects.new("cam", cam_d); sc.collection.objects.link(cam); sc.camera = cam


def shot(name, yaw, tgt, size, pitch=8, color="SINGLE", res=(900, 1100), wire=False):
    sc.render.resolution_x, sc.render.resolution_y = res
    sh.color_type = color
    cam_d.ortho_scale = size
    a = math.radians(yaw); p = math.radians(pitch)
    d = Vector((math.sin(a) * math.cos(p), -math.cos(a) * math.cos(p), math.sin(p)))
    cam.location = Vector(tgt) + d * 10
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    obj.show_wire = wire; obj.show_all_edges = wire
    sc.display.shading.show_xray = False
    if wire:
        sh.light = "FLAT"; sh.single_color = (0.62, 0.62, 0.62); sh.show_cavity = False
    sc.render.filepath = str(out / f"{name}.png")
    bpy.ops.render.render(write_still=True)
    if wire:
        sh.light = "STUDIO"; sh.single_color = (0.78, 0.78, 0.78); sh.show_cavity = True


mid = (0, 0, H * 0.5)
for nm, yaw in [("t0_front", 0), ("t1_fr34", 40), ("t2_side_r", 90), ("t3_br34", 140), ("t4_back", 180),
                ("t5_bl34", 220), ("t6_side_l", 270), ("t7_fl34", 320)]:
    shot(nm, yaw, mid, H * 1.18)
shot("c_face", 0, (0, 0, H * 0.9), 0.42, res=(800, 800))
shot("c_face34", 35, (0, 0, H * 0.9), 0.42, res=(800, 800))
shot("c_torso", 0, (0, 0, H * 0.66), 0.75, res=(800, 800))
shot("c_back", 180, (0, 0, H * 0.62), 0.95, res=(800, 800))
shot("c_boots", 25, (0, 0, H * 0.14), 0.7, res=(900, 600))
shot("c_hand_r", 0, (-H * 0.42, 0, H * 0.81), 0.35, res=(800, 600))
shot("c_top", 0, (0, 0, H * 0.6), H * 1.2, pitch=80, res=(1000, 1000))
shot("f_front", 0, mid, H * 1.18, color="VERTEX")
shot("f_back", 180, mid, H * 1.18, color="VERTEX")
shot("w_front", 0, mid, H * 1.18, wire=True)
shot("w_back", 180, mid, H * 1.18, wire=True)
print("DONE")
