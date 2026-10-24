"""Rebuild the Tripo spear with a forged steel head (background Blender).

  blender -b --factory-startup --python build_spear.py -- <spear_tex.fbx> <out.blend> [preview_dir]

The Tripo spear (1 m long, Z up, blade width along X) has a plain wooden collar under the
blade, and a pale blade and butt cap. This script:
1. thins the shaft to a hand-sized grip (SHAFT_D at full length);
2. replaces the wooden collar with a forged octagonal socket that hugs the shaft and flares
   into the blade's flattened neck (bottom ring, mid ridge, mouth ring, two rivets), and
   adds two riveted langets running down the shaft on the blade's flat sides;
3. moves the blue cloth wrap down under the socket, binding the langets;
4. repaints the blade, butt cap and all new steel with faceted cel tones (a polished and a
   darker forged palette, lit from the front left) from a small swatch texture;
5. scales the spear to LENGTH with the butt at the origin.
"""
import math
import sys
from collections import deque
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

LENGTH = 2.40      # m, butt to tip
SHAFT_D = 0.040    # m, shaft diameter at full scale

POL = ["3b4048", "5a616b", "808892", "aab1b9", "e1e5e9"]    # polished steel, dark to light
IRON = ["2b2e33", "43474e", "5f646b", "81868d", "aeb2b7"]   # forged iron
SHAFT, BLADE, WRAP, CAP, COLLAR = range(5)

argv = sys.argv[sys.argv.index("--") + 1:]
src, out_blend = Path(argv[0]), Path(argv[1])
prev = Path(argv[2]) if len(argv) > 2 else None

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(src))
spear = next(o for o in bpy.context.scene.objects if o.type == "MESH")
spear.name = spear.data.name = "Spear"
bpy.context.view_layer.objects.active = spear; spear.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(bpy.context.scene.objects):
    if o is not spear:
        bpy.data.objects.remove(o)
me = spear.data
co = np.array([v.co[:] for v in me.vertices])
L0 = float(co[:, 2].max() - co[:, 2].min())
me.transform(Matrix.Translation((0, 0, -co[:, 2].min())))
me.update()

# Parts: shaft (with collar and cap), blade, two wrap ribbons.
bm = bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table(); bm.verts.ensure_lookup_table()
part_of = {}; parts = []
for f0 in bm.faces:
    if f0.index in part_of:
        continue
    q = deque([f0]); part_of[f0.index] = len(parts); fs = [f0.index]
    while q:
        f = q.popleft()
        for e in f.edges:
            for g in e.link_faces:
                if g.index not in part_of:
                    part_of[g.index] = len(parts); q.append(g); fs.append(g.index)
    parts.append(fs)
pverts = [sorted({v.index for f in fs for v in bm.faces[f].verts}) for fs in parts]
zr = [(min(bm.verts[i].co.z for i in vs), max(bm.verts[i].co.z for i in vs)) for vs in pverts]
shaft = next(i for i in range(len(parts)) if zr[i][0] < 0.01 * L0)
blade = max(range(len(parts)), key=lambda i: zr[i][1])
wraps = [i for i in range(len(parts)) if i not in (shaft, blade)]

sv = np.array([bm.verts[i].co[:] for i in pverts[shaft]])
cx, cy = float(np.median(sv[:, 0])), float(np.median(sv[:, 1]))
sr = np.hypot(sv[:, 0] - cx, sv[:, 1] - cy)
# The shaft is one long quad strip between cap and collar: its radius is the smaller radius
# on the rings bounding that strip.
r_shaft0 = float(np.percentile(sr[(sv[:, 2] > 0.03 * L0) & (sv[:, 2] < 0.75 * L0)], 25))
rings = {}
for (x, y, z), r in zip(sv, sr):
    rings.setdefault(round(float(z), 5), []).append(r)
zc_bot = min(z for z, rs in rings.items() if z > 0.7 * L0 and np.median(rs) > r_shaft0 * 1.12)
cap_rings = [z for z, rs in rings.items() if z < 0.06 * L0 and np.max(rs) > r_shaft0 * 1.08]
zcap_top = max(cap_rings) if cap_rings else 0.02 * L0
bv = np.array([bm.verts[i].co[:] for i in pverts[blade]])
zbl = float(bv[:, 2].min())
print(f"PARTS shaft {shaft} blade {blade} wraps {wraps}; L0={L0:.4f} r_shaft={r_shaft0:.5f} "
      f"collar from z {zc_bot:.4f}; blade from z {zbl:.4f}; cap top {zcap_top:.4f}")

kind = bm.faces.layers.int.new("kind")
for f in bm.faces:
    p = part_of[f.index]
    c = f.calc_center_median()
    f[kind] = (BLADE if p == blade else WRAP if p in wraps else
               COLLAR if c.z > zc_bot - 0.001 * L0 else CAP if c.z < zcap_top + 0.002 * L0 else SHAFT)

u = L0  # sizes below are fractions of the spear's length
zt = zbl + 0.0040 * u                 # socket mouth, just above the blade's lowest point
zb = zt - 0.072 * u                   # socket bottom (about 17 cm at full length)
s = (SHAFT_D / 2) / (r_shaft0 * LENGTH / L0)
r_shaft = r_shaft0 * s
LANG_T = 0.0011 * u

# 1. Remove the wooden collar (hidden inside the socket from now on), run the shaft up into
#    the socket, and thin the shaft.
bmesh.ops.delete(bm, geom=[f for f in bm.faces if f[kind] == COLLAR], context="FACES_ONLY")
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
for v in bm.verts:
    lf = v.link_faces
    if lf and all(f[kind] in (SHAFT, CAP) for f in lf):
        v.co.x = cx + (v.co.x - cx) * s
        v.co.y = cy + (v.co.y - cy) * s
        if v.co.z > 0.7 * L0:
            v.co.z = zb + 0.035 * u
# 3. Wrap: move it down under the socket, fitted around shaft + langet.
wv = [v for v in bm.verts if v.link_faces and v.link_faces[0][kind] == WRAP]
wz = np.array([v.co.z for v in wv]); wr = np.array([math.hypot(v.co.x - cx, v.co.y - cy) for v in wv])
w_in = float(np.percentile(wr, 5))
target_in = r_shaft + LANG_T + 0.0002 * u
dz = (zb - 0.0012 * u) - float(wz.max())
for v in wv:
    rx, ry = v.co.x - cx, v.co.y - cy
    r = math.hypot(rx, ry)
    k = (target_in + (r - w_in)) / r if r > 1e-9 else 1     # keep the ribbon's thickness
    v.co.x = cx + rx * k; v.co.y = cy + ry * k; v.co.z += dz
wrap_z = (float(wz.min()) + dz, float(wz.max()) + dz)

# Blade neck at the socket mouth (the socket must contain it).
neck = bv[bv[:, 2] < zt + 0.004 * u]
nx = float(np.abs(neck[:, 0] - cx).max()); ny = float(np.abs(neck[:, 1] - cy).max())

# 2. New steel: socket, rivets, langets (built into the same bmesh, tagged by a second layer).
part = bm.faces.layers.int.new("steel")   # 0 Tripo face, 1 socket, 2 socket band, 3 rivet, 4 langet
for f in bm.faces:
    f[part] = 0


def ring(z, ax, ay, n=8):
    k = 1 / math.cos(math.pi / n)
    return [bm.verts.new((cx + ax * k * math.cos(math.pi / n + 2 * math.pi * i / n),
                          cy + ay * k * math.sin(math.pi / n + 2 * math.pi * i / n), z)) for i in range(n)]


def loft(rows, tags, cap_bot=True, cap_top=True, tag_caps=1):
    for (a, b), t in zip(zip(rows, rows[1:]), tags):
        n = len(a)
        for i in range(n):
            f = bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i])); f[part] = t
    if cap_bot:
        f = bm.faces.new(list(reversed(rows[0]))); f[part] = tag_caps
    if cap_top:
        f = bm.faces.new(rows[-1]); f[part] = tag_caps


ab = r_shaft + 0.0017 * u                    # body apothem at the bottom (hugs the shaft)
axt, ayt = nx + 0.0006 * u, ny + 0.0010 * u  # at the mouth: the blade's flattened neck
band = 0.0013 * u
lerp = lambda t: (ab + (axt - ab) * t, ab + (ayt - ab) * t)
t_r = 0.42
prof = [  # z, ax, ay, tag of the faces from this row up to the next
    (zb, ab + band, ab + band, 2), (zb + 0.0060 * u, ab + band, ab + band, 2), (zb + 0.0060 * u, ab, ab, 1),
    (zb + 0.0072 * u, ab, ab, 1),
    (zb + t_r * (zt - zb) - 0.0018 * u, *lerp(t_r - 0.03), 2),
    (zb + t_r * (zt - zb), *[a + 0.0007 * u for a in lerp(t_r)], 2),
    (zb + t_r * (zt - zb) + 0.0018 * u, *lerp(t_r + 0.03), 1),
    (zt - 0.0058 * u, axt, ayt, 2), (zt - 0.0058 * u, axt + 0.0009 * u, ayt + 0.0009 * u, 2),
    (zt, axt + 0.0009 * u, ayt + 0.0009 * u, 2)]
rows = [ring(z, ax, ay) for z, ax, ay, _ in prof]
loft(rows, [t for *_, t in prof[:-1]], tag_caps=2)


def rivet(center, normal, r):
    nrm = normal.normalized(); t1 = nrm.orthogonal().normalized(); t2 = nrm.cross(t1)
    rows = [[bm.verts.new(center + (t1 * math.cos(a) + t2 * math.sin(a)) * r * rr + nrm * r * hh)
             for a in (2 * math.pi * i / 8 for i in range(8))]
            for rr, hh in ((1.0, 0.0), (0.92, 0.35), (0.7, 0.62), (0.38, 0.8))]
    loft(rows, [3, 3, 3], cap_bot=False, cap_top=True, tag_caps=3)


zrv = zb + 0.28 * (zt - zb)
axr, _ = lerp(0.28)
for sgn in (1, -1):                      # on the octagon's flats facing the blade edges (+-X)
    rivet(Vector((cx + sgn * axr, cy, zrv)), Vector((sgn, 0, 0)), 0.0019 * u)

LANG_W = 0.0070 * u
lang_top, lang_bot = zb + 0.0030 * u, zb - 0.092 * u
for sgn in (1, -1):                      # on the blade's flat sides (+-Y)
    zs = np.linspace(lang_top, lang_bot, 9)
    widths = [LANG_W] * 6 + [LANG_W * 0.7, LANG_W * 0.38, LANG_W * 0.06]
    grid = {}
    for side, rad in (("i", r_shaft - 0.0002 * u), ("o", r_shaft + LANG_T)):
        for kk, (z, w) in enumerate(zip(zs, widths)):
            for j, t in enumerate((-1, -0.5, 0, 0.5, 1)):
                ang = (t * w / 2) / r_shaft
                grid[side, kk, j] = bm.verts.new((cx + rad * math.sin(ang), cy + sgn * rad * math.cos(ang), z))
    quads = []
    for kk in range(8):
        for j in range(4):
            quads.append([grid["o", kk, j], grid["o", kk, j + 1], grid["o", kk + 1, j + 1], grid["o", kk + 1, j]])
            quads.append([grid["i", kk, j], grid["i", kk + 1, j], grid["i", kk + 1, j + 1], grid["i", kk, j + 1]])
        for j in (0, 4):
            quads.append([grid["i", kk, j], grid["o", kk, j], grid["o", kk + 1, j], grid["i", kk + 1, j]])
    for kk in (0, 8):
        for j in range(4):
            quads.append([grid["i", kk, j], grid["i", kk, j + 1], grid["o", kk, j + 1], grid["o", kk, j]])
    for qd in quads:
        f = bm.faces.new(qd); f[part] = 4
    for z in (lang_top - 0.030 * u, lang_top - 0.066 * u):
        rivet(Vector((cx, cy + sgn * (r_shaft + LANG_T), z)), Vector((0, sgn, 0)), 0.0015 * u)

bmesh.ops.recalc_face_normals(bm, faces=[f for f in bm.faces if f[part] > 0])

# Swatch texture: top row polished steel, bottom row forged iron; 5 tones each.
W, H = 5 * 8, 2 * 8
img = bpy.data.images.new("spear_steel", W, H)
px = np.zeros((H, W, 4), np.float32)
for rowi, pal in enumerate((POL, IRON)):
    for j, hx in enumerate(pal):
        px[(1 - rowi) * 8:(2 - rowi) * 8, j * 8:(j + 1) * 8] = [*(int(hx[k:k + 2], 16) / 255 for k in (0, 2, 4)), 1]  # byte image: pixels are sRGB
img.pixels = px.ravel()
out_blend.parent.mkdir(parents=True, exist_ok=True)
img.filepath_raw = str(out_blend.with_name("spear_steel.png")); img.file_format = "PNG"
img.save(); img.pack()


def tone_uv(n, pal_row):
    """Cel tone that reads the same from the front and the back (the spear turns in the
    hands): the -X side of every ridge is lit, the +X side mid, faces looking down darker."""
    n = n.normalized()
    j = 3 if n.x < -0.38 else 2 if n.x < 0.38 else 1
    if n.z > 0.55:
        j = min(j + 1, 4)
    elif n.z < -0.55:
        j = max(j - 1, 0)
    if pal_row == 0:
        j = min(j + 1, 4)       # polished parts one step brighter
    return ((j + 0.5) / 5, 1 - (pal_row + 0.5) / 2)


mat = bpy.data.materials.new("SpearSteel"); mat.use_nodes = True
nt = mat.node_tree
bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = img; tex.interpolation = "Closest"
nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
nt.nodes.active = tex
bsdf.inputs["Metallic"].default_value = 0.8; bsdf.inputs["Roughness"].default_value = 0.35
for m in me.materials:  # Workbench shows each material's active image node
    if m and m.use_nodes:
        im_nodes = [n for n in m.node_tree.nodes if n.type == "TEX_IMAGE"]
        if im_nodes:
            m.node_tree.nodes.active = im_nodes[0]
me.materials.append(mat)
steel = len(me.materials) - 1
uvl = bm.loops.layers.uv.active
for f in bm.faces:
    if f[part] > 0 or f[kind] in (BLADE, CAP):
        f.material_index = steel
        if f[kind] == BLADE:
            # Two-tone blade as in the concept art: lit on the -X side of the ridge, mid
            # grey on the other, the bevel under the widest point a step darker.
            j = 4 if f.normal.x < 0 else 2
            j -= 1 if f.normal.z < -0.3 else 0
            uvv = ((j + 0.5) / 5, 0.75)
        else:
            uvv = tone_uv(f.normal, 1 if f[part] in (1, 4) else 0)
        for lp in f.loops:
            lp[uvl].uv = uvv
        f.smooth = False
    else:
        f.smooth = True
bm.to_mesh(me); bm.free()
me.transform(Matrix.Translation((-cx, -cy, 0)))
me.transform(Matrix.Scale(LENGTH / L0, 4))
me.update()
spear["meridius_note"] = "Tripo spear with a forged steel socket, langets and rivets (build_spear.py)"
spear["shaft_r"] = SHAFT_D / 2
spear["grip_hint"] = "butt at the origin, tip along +Z"
k = LENGTH / L0
print(f"SPEAR faces={len(me.polygons)} length={LENGTH} shaft_d={2 * r_shaft * k:.4f} "
      f"socket z {zb * k:.3f}-{zt * k:.3f} neck {2 * nx * k:.3f}x{2 * ny * k:.3f} wrap z {wrap_z[0] * k:.3f}-{wrap_z[1] * k:.3f}")
bpy.ops.wm.save_as_mainfile(filepath=str(out_blend))

if prev:
    prev.mkdir(parents=True, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.color_type = "TEXTURE"; sh.show_object_outline = True
    sh.object_outline_color = (0.09, 0.07, 0.07); sh.show_cavity = True; sh.cavity_type = "WORLD"
    sc.display.render_aa = "16"
    sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.2, 0.2, 0.22)
    cam_d = bpy.data.cameras.new("cam"); cam_d.type = "ORTHO"
    cam = bpy.data.objects.new("cam", cam_d); sc.collection.objects.link(cam); sc.camera = cam

    def shot(name, yaw, z, size, res, light="FLAT"):
        sh.light = light
        sc.render.resolution_x, sc.render.resolution_y = res
        cam_d.ortho_scale = size
        a = math.radians(yaw); d = Vector((math.sin(a), -math.cos(a), 0.12)).normalized()
        cam.location = Vector((0, 0, z)) + d * 10
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = str(prev / f"{name}.png"); bpy.ops.render.render(write_still=True)

    zh = zb * k + 0.20
    for nm, yaw in [("head_0", 0), ("head_35", 35), ("head_90", 90), ("head_200", 200)]:
        shot(nm, yaw, zh, 0.85, (480, 720))
        shot(nm + "_studio", yaw, zh, 0.85, (480, 720), "STUDIO")
    shot("full", 25, LENGTH / 2, LENGTH * 1.04, (260, 1100))
    shot("butt", 25, 0.06, 0.18, (360, 360))
print("DONE")
