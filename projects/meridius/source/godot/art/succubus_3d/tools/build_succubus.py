"""Build the succubus base scene from the Tripo exports (background Blender).

  blender -b --factory-startup --python build_succubus.py -- <tripo_dir> <out.blend> [preview_dir]

<tripo_dir> holds the unpacked exports succubus_{body,wings,tail,whip}_v1_tex/*.fbx
(references/characters/Succubus TRIPO). Run with BLENDER_USER_RESOURCES pointing at a
scratch folder: with --factory-startup and the user's own profile, Blender removes the
Python wheels of the profile's extensions.

1. Imports the textured body and deletes the spike Tripo invented behind her hips (the
   input had no back view): a separate 8-sided tube stuck into the buttocks, reaching
   0.44 body heights behind her. The separate tail mounts there instead.
2. Widens the hips, fills out the buttocks and lengthens the legs (HIP_WIDEN,
   BUTT_FULL, LEG_STRETCH; environment variables override them, 0 keeps Tripo's shape).
3. Scales her to H (horn tips included), feet at z = 0, centred, facing -Y, adds
   black paw pads to the soles (part of the body mesh, material PawPad) and fur tufts
   on the hips and thighs (FUR=0 leaves them out).
4. Imports the wings, tail and whip as separate objects, roughly to scale and parked
   beside her. They are not fitted to the body yet; that comes with rigging.
Saves the .blend with its textures packed.
"""
import math
import os
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

H = 1.95                 # body height in metres, horn tips included
HIP_WIDEN = float(os.environ.get("HIP_WIDEN", 0.15))   # extra hip width at the widest point
BUTT_FULL = float(os.environ.get("BUTT_FULL", 0.10))   # extra depth of the buttocks
LEG_STRETCH = float(os.environ.get("LEG_STRETCH", 0.15))  # extra length from anklet to crotch
ITEMS = {                # largest dimension in metres, and where to park it
    "wings": (2.0, (0.0, 1.4, 1.25)),
    "tail": (0.85, (-1.1, 0.0, 0.6)),
    "whip": (0.55, (1.1, 0.0, 0.6)),
}
argv = sys.argv[sys.argv.index("--") + 1:]
tripo, out_blend = Path(argv[0]), Path(argv[1])
prev = Path(argv[2]) if len(argv) > 2 else None


def import_part(name):
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.fbx(filepath=str(tripo / f"succubus_{name}_v1_tex" / f"succubus_{name}_v1_tex.fbx"))
    new = [o for o in bpy.context.scene.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in new:
        if o is not ob:
            bpy.data.objects.remove(o)
    ob.name = ob.data.name = name.capitalize()
    return ob


def bounds(me):
    V = np.array([v.co[:] for v in me.vertices])
    return V.min(0), V.max(0)


bpy.ops.wm.read_factory_settings(use_empty=True)
body = import_part("body")
body.name = body.data.name = "Succubus"
me = body.data

# 1. The spike: a separate shell in Tripo's units (height 1.0), an 8-sided tube from an
# open end inside the buttocks (y = -0.174) to its tip at y = +0.313. Everything else of
# her ends at y = -0.14, so its connected component is found from the vertices behind
# y = 0.2 and deleted whole; her own surface is not touched.
bm = bmesh.new()
bm.from_mesh(me)
seen = {v for v in bm.verts if v.co.y > 0.2}
stack = list(seen)
while stack:
    v = stack.pop()
    for e in v.link_edges:
        n = e.other_vert(v)
        if n not in seen:
            seen.add(n)
            stack.append(n)
assert 40 <= len(seen) <= 300, f"the spike is not a separate shell ({len(seen)} vertices)"
print("SPIKE verts", len(seen), "y", round(min(v.co.y for v in seen), 3), "to", round(max(v.co.y for v in seen), 3))
bmesh.ops.delete(bm, geom=list(seen), context="VERTS")


# 2. Fuller hips. A smooth band peaking at the widest point of the hips (z 0.47) that
# fades out at the waist (z 0.62) and above the knees (z 0.30): wider sideways, and the
# buttocks fuller backwards. The front panel hangs at x ~ 0 and barely moves.
def band(z, peak=0.47, top=0.62, bottom=0.30):
    if z <= bottom or z >= top:
        return 0.0
    t = (z - peak) / ((top - peak) if z > peak else (peak - bottom))
    return 0.5 * (1 + math.cos(math.pi * t))


hip_v = [v for v in bm.verts if 0.40 < v.co.z < 0.60]
yc = sum(v.co.y for v in hip_v) / len(hip_v)   # centre of the hips, front to back
for v in bm.verts:
    w = band(v.co.z)
    if w:
        v.co.x *= 1 + HIP_WIDEN * w
        if v.co.y > yc:
            v.co.y = yc + (v.co.y - yc) * (1 + BUTT_FULL * w)
print("HIPS widen", HIP_WIDEN, "buttocks", BUTT_FULL, "centre y", round(yc, 3))

# Longer legs: everything between the anklets (z 0.09) and the crotch (z 0.45) is
# stretched upwards; the paws keep their shape and everything above moves up. Step 3
# scales her back to H, so her torso and head end up smaller relative to her legs.
LEG_LO, LEG_HI = 0.09, 0.45
lift = (LEG_HI - LEG_LO) * LEG_STRETCH
for v in bm.verts:
    if v.co.z > LEG_HI:
        v.co.z += lift
    elif v.co.z > LEG_LO:
        v.co.z = LEG_LO + (v.co.z - LEG_LO) * (1 + LEG_STRETCH)
print("LEGS stretch", LEG_STRETCH, "between z", LEG_LO, "and", LEG_HI)
bm.to_mesh(me)
bm.free()

# 3. Size and placement.
lo, hi = bounds(me)
me.transform(Matrix.Translation((-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2])))
me.transform(Matrix.Scale(H / (hi[2] - lo[2]), 4))
me.update()
assert np.mean([v.co.y for v in me.vertices if v.co.z > 0.85 * H]) < 0.02, "expected the face towards -Y"

# 3b. Black paw pads on the soles: a toe pad behind each of the four claws, where the
# user placed them, and a rounded-triangle main pad behind them, turned with the foot
# (her feet point about 18 degrees outwards). The claws are found by their white
# texture; each toe pad points at its claw. Each pad is a dome draped over the sole: its
# grid is projected up onto the sole by ray casts and pushed out along the sole's
# normal by PAD_THICK * sqrt(1 - r^2), so it hugs the curved underside with no gap.
# The pads join the body mesh (own material), so they follow the feet when rigged.
PAD_THICK = 0.006
# Toe pad centres (|x|, y) in m on her right foot, mirrored to the left: placed by the
# user on a render of the soles (23 Oct 2026), the two feet's marks averaged.
TOE_PADS = [(0.2894, -0.1268), (0.3301, -0.1392), (0.3611, -0.1206), (0.3821, -0.0795)]
TOE_SIZE = (0.0095, 0.010)  # toe pad half-width, half-length (along the toe)
MAIN_BACK = 0.087           # main pad centre behind the claws' centre, along the foot (m)
MAIN_SIZE = (0.034, 0.026)
# Heel reference, read off a ray-cast height map of the soles: from the contact area's
# centre line, this far in front of the sole's back edge (m).
HEEL_FWD = 0.055


def find_claws(sign):
    """Centres (x, y) of the four claws of one foot, from the texture's white."""
    mat = me.materials[0]
    img = next(n for n in mat.node_tree.nodes if n.type == "TEX_IMAGE").image
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)[..., :3]
    uv = me.uv_layers.active.data
    col = {}
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            co = me.vertices[vi].co
            if co.z < 0.10 and np.sign(co.x) == sign:
                u, v = uv[li].uv
                col.setdefault(vi, []).append(px[int(v % 1 * (h - 1)), int(u % 1 * (w - 1))])
    pts = []
    for vi, cs in col.items():
        c = np.mean(cs, 0)
        if c.min() > 0.62 and (c.max() - c.min()) / c.max() < 0.25:
            pts.append(me.vertices[vi].co[:])
    P = np.array(pts)[:, :2]
    # Small clusters first (each claw shows as a tip and a base cluster), then merge the
    # two closest until four are left: a claw's tip and base are 1-3 cm apart, two
    # neighbouring claws at least 3.5 cm.
    groups = []
    for p_ in P:
        for g in groups:
            if min(np.linalg.norm(q - p_) for q in g) < 0.012:
                g.append(p_)
                break
        else:
            groups.append([p_])
    while len(groups) > 4:
        cents = [np.mean(g, 0) for g in groups]
        _, a, b = min((np.linalg.norm(cents[a] - cents[b]), a, b)
                      for a in range(len(groups)) for b in range(a + 1, len(groups)))
        groups[a] += groups.pop(b)
    claws = [np.mean(g, 0) for g in groups]
    assert len(claws) == 4, f"expected 4 claws on the {'left' if sign > 0 else 'right'} foot, found {len(claws)}"
    return claws


def add_pads():
    bpy.context.view_layer.update()   # ray casts read the evaluated (scaled) mesh
    pad_me = bpy.data.meshes.new("PawPads")
    pbm = bmesh.new()
    V = np.array([v.co[:] for v in me.vertices])
    rings, segs = 4, 16
    misses = 0

    def pad(c, along, size, main):
        """One dome pad centred at c (x, y), its length along the unit vector `along`."""
        nonlocal misses
        across = np.array([along[1], -along[0]])
        grid = [[None] * segs for _ in range(rings)]
        last = [None] * segs   # last hit along each spoke
        for i in range(rings + 1):
            r = i / rings
            for j in range(segs if i else 1):
                a = 2 * math.pi * j / segs
                # the main pad is a soft triangle pointing towards the toes (a = 90 deg)
                k = 1 + (0.10 * math.cos(3 * a + 0.5 * math.pi) if main else 0)
                p = c + across * size[0] * k * r * math.cos(a) + along * size[1] * k * r * math.sin(a)
                ok, loc, nrm, _ = body.ray_cast(Vector((p[0], p[1], -1.0)), Vector((0, 0, 1)))
                if not ok or loc.z > 0.06:   # a gap between toes or a hole in the sole
                    assert i, f"pad centre {p[0]:.3f},{p[1]:.3f} misses the sole"
                    misses += 1
                    loc, nrm = last[j] if last[j] else last_centre
                if i == 0:
                    last_centre = (loc, nrm)
                else:
                    last[j] = (loc, nrm)
                vert = pbm.verts.new(loc + nrm * (PAD_THICK * math.sqrt(max(0.0, 1 - r * r)) + 0.0004))
                if i == 0:
                    centre = vert
                else:
                    grid[i - 1][j] = vert
        faces = []
        for j in range(segs):
            faces.append(pbm.faces.new((centre, grid[0][(j + 1) % segs], grid[0][j])))
            for i in range(rings - 1):
                faces.append(pbm.faces.new((grid[i][j], grid[i][(j + 1) % segs],
                                            grid[i + 1][(j + 1) % segs], grid[i + 1][j])))
        for f in faces:
            f.normal_update()
        if sum(f.normal.z for f in faces) > 0:   # each pad must face down, away from the sole
            bmesh.ops.reverse_faces(pbm, faces=faces)

    for sign in (-1, 1):
        side = V[np.sign(V[:, 0]) == sign]
        contact = side[side[:, 2] < 0.012]
        heel = np.array([(contact[:, 0].min() + contact[:, 0].max()) / 2,
                         side[side[:, 2] < 0.03][:, 1].max() - HEEL_FWD])
        claws = find_claws(sign)
        for ax, ay in TOE_PADS:   # each toe pad points at its own (nearest) claw
            c = np.array([sign * ax, ay])
            cl = min(claws, key=lambda q: np.linalg.norm(q - c))
            pad(c, (cl - c) / np.linalg.norm(cl - c), TOE_SIZE, False)
        axis = np.mean(claws, 0) - heel
        axis /= np.linalg.norm(axis)
        pad(np.mean(claws, 0) - axis * MAIN_BACK, axis, MAIN_SIZE, True)
        print("FOOT", "left" if sign > 0 else "right", "turned out",
              round(math.degrees(math.atan2(abs(axis[0]), -axis[1])), 1), "deg, claws",
              [tuple(np.round(c, 3)) for c in claws])
    pbm.to_mesh(pad_me)
    pbm.free()
    mat = bpy.data.materials.new("PawPad")
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (0.012, 0.012, 0.014, 1)
    bsdf.inputs["Roughness"].default_value = 0.45
    mat.diffuse_color = (0.012, 0.012, 0.014, 1)
    pad_me.materials.append(mat)
    pads = bpy.data.objects.new("PawPads", pad_me)
    bpy.context.scene.collection.objects.link(pads)
    pads.vertex_groups.new(name="PawPads").add(range(len(pad_me.vertices)), 1.0, "REPLACE")  # for the rig
    bpy.ops.object.select_all(action="DESELECT")
    pads.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    print("PADS 10, rays that missed the sole", misses, "faces now", len(me.polygons))


add_pads()
lo, hi = bounds(me)
me.transform(Matrix.Translation((0, 0, -lo[2])))   # the pads are now the lowest point
me.update()

# 3c. Fur tufts on the hips and thighs (FUR=0 leaves them out). The fur is the part of
# the texture between the stocking tops (z 0.72) and the suit (z 1.16) that is not dark.
# Each clump is one or two pointed spikes, sprouting from a mesh vertex, pointing down the
# leg and tilted out from the surface, so the silhouette turns jagged. All of a spike's
# vertices take the UV of its root, so it has the colour of the fur under it. A denser
# fringe of longer clumps hangs over the gold bands at the stocking tops. Spikes stay
# away from the suit and the front panel; the inner thighs get short ones.
FUR = os.environ.get("FUR", "1") != "0"
FUR_Z = (0.70, 1.17)
SPACING, FRINGE_SPACING = 0.024, 0.016
LEN, FRINGE_LEN = (0.020, 0.034), (0.028, 0.040)
TILT, FRINGE_TILT = math.radians(22), math.radians(12)


def vertex_colours():
    """Mean texture colour per vertex (over its loops) and one UV per vertex."""
    img = next(n for n in me.materials[0].node_tree.nodes if n.type == "TEX_IMAGE").image
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)[..., :3]
    uv = np.empty(len(me.loops) * 2, dtype=np.float32)
    me.uv_layers.active.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    lv = np.empty(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", lv)
    c = px[(uv[:, 1] % 1 * (h - 1)).astype(int), (uv[:, 0] % 1 * (w - 1)).astype(int)]
    col = np.zeros((len(me.vertices), 3))
    cnt = np.zeros(len(me.vertices))
    np.add.at(col, lv, c)
    np.add.at(cnt, lv, 1)
    vuv = np.zeros((len(me.vertices), 2))
    vuv[lv] = uv          # any one loop's UV
    return col / np.maximum(cnt, 1)[:, None], vuv


def add_fur():
    from mathutils import kdtree
    col, vuv = vertex_colours()
    co = np.array([v.co[:] for v in me.vertices])
    nrm = np.array([v.normal[:] for v in me.vertices])
    pad_mats = {i for i, m in enumerate(me.materials) if m.name == "PawPad"}
    on_pad = set()
    for p in me.polygons:
        if p.material_index in pad_mats:
            on_pad.update(p.vertices)
    val = col.max(1)
    dark = val < 0.30
    zone = (co[:, 2] > FUR_Z[0] - 0.08) & (co[:, 2] < FUR_Z[1] + 0.08)
    kd_dark = kdtree.KDTree(int((dark & zone).sum()))
    for i in np.nonzero(dark & zone)[0]:
        kd_dark.insert(co[i], int(i))
    kd_dark.balance()
    fur = [i for i in np.nonzero(~dark & zone & (co[:, 2] > FUR_Z[0]) & (co[:, 2] < FUR_Z[1])
                                 & (np.abs(co[:, 0]) > 0.04))[0] if i not in on_pad]
    rng = np.random.default_rng(7)
    rng.shuffle(fur)
    sites = []   # (vertex index, fringe)
    for i in fur:
        near = kd_dark.find_range(co[i], 0.035)
        below = any(co[i][2] - c[2] > 0.005 for c, _, _ in near)
        level = any(abs(co[i][2] - c[2]) <= 0.005 or c[2] > co[i][2] for c, _, _ in near)
        fringe = below and co[i][2] < 0.86
        if not fringe and (level or any(d < 0.03 for _, _, d in near)):
            continue      # next to the suit or the front panel
        sp = FRINGE_SPACING if fringe else SPACING
        if any(np.linalg.norm(co[i] - co[j]) < sp for j, _ in sites):
            continue
        sites.append((i, fringe))
    tb = bmesh.new()
    uvl = tb.loops.layers.uv.new(me.uv_layers.active.name)
    down = Vector((0, 0, -1))
    n_spikes = 0

    def spike(p, n, d, b, L, w, uvv):
        nonlocal n_spikes
        A = tb.verts.new(p + b * (w / 2) - n * 0.003)
        B = tb.verts.new(p - b * (w / 2) - n * 0.003)
        C = tb.verts.new(p + n * (w * 0.12) - d * (w * 0.2))   # a low ridge: no bump where the spike faces the camera
        T = tb.verts.new(p + d * L)
        for f in ((A, C, T), (C, B, T), (B, A, T), (A, B, C)):
            face = tb.faces.new(f)
            for lp in face.loops:
                lp[uvl].uv = uvv
        n_spikes += 1

    for i, fringe in sites:
        p, n = Vector(co[i]), Vector(nrm[i]).normalized()
        side = math.copysign(1, co[i][0])
        inner = n.x * side < -0.4
        t = down - n * n.dot(down)
        if t.length < 0.2:          # surface facing straight down: let it hang
            t = down
        t.normalize()
        tilt = FRINGE_TILT if fringe else TILT
        d = (t * math.cos(tilt) + n * math.sin(tilt)).normalized()
        b = n.cross(t).normalized()
        L = rng.uniform(*(FRINGE_LEN if fringe else LEN)) * (0.55 if inner else 1.0)
        uvv = tuple(vuv[i])
        spike(p, n, d, b, L, L * 0.45, uvv)
        if rng.random() < 0.6:      # a second, shorter spike beside it: a jagged clump
            ang = math.radians(rng.choice((-18, 18)))
            d2 = (Matrix.Rotation(ang, 3, n) @ d).normalized()
            spike(p + b * (L * 0.45 * 0.4 * math.copysign(1, ang)), n, d2, b, L * 0.65, L * 0.3, uvv)
    tb.normal_update()
    bmesh.ops.recalc_face_normals(tb, faces=tb.faces)
    fur_me = bpy.data.meshes.new("FurTufts")
    tb.to_mesh(fur_me)
    tb.free()
    fur_me.materials.append(me.materials[0])
    ob = bpy.data.objects.new("FurTufts", fur_me)
    bpy.context.scene.collection.objects.link(ob)
    ob.vertex_groups.new(name="FurTufts").add(range(len(fur_me.vertices)), 1.0, "REPLACE")  # for the rig
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    print("FUR clumps", len(sites), "fringe", sum(f for _, f in sites), "spikes", n_spikes,
          "faces now", len(me.polygons))


if FUR:
    add_fur()

# 4. Items, parked beside her.
items = {}
for name, (size, at) in ITEMS.items():
    ob = import_part(name)
    lo, hi = bounds(ob.data)
    ob.data.transform(Matrix.Translation(Vector(-(lo + hi) / 2)))
    ob.data.transform(Matrix.Scale(size / max(hi - lo), 4))
    ob.location = at
    items[name] = ob

for o in [body, *items.values()]:
    for m in o.data.materials:
        if m and m.use_nodes:
            ims = [n for n in m.node_tree.nodes if n.type == "TEX_IMAGE"]
            if ims:
                m.node_tree.nodes.active = ims[0]
bpy.ops.file.pack_all()
out_blend.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(out_blend))
print("SAVED", out_blend, "body faces", len(me.polygons),
      {k: len(o.data.polygons) for k, o in items.items()})

if prev:
    prev.mkdir(parents=True, exist_ok=True)
    for o in items.values():
        o.hide_render = True
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sc.display.render_aa = "16"
    sc.world = bpy.data.worlds.new("w")
    sc.world.color = (0.18, 0.18, 0.2)
    cam_d = bpy.data.cameras.new("cam")
    cam_d.type = "ORTHO"
    cam = bpy.data.objects.new("cam", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam

    def shot(name, yaw, look):
        if look == "clay":
            sh.light = "STUDIO"; sh.color_type = "SINGLE"; sh.single_color = (0.78, 0.78, 0.78)
            sh.show_cavity = True; sh.cavity_type = "BOTH"; sh.show_object_outline = False
        else:
            sh.light = "FLAT"; sh.color_type = "TEXTURE"; sh.show_object_outline = True
            sh.object_outline_color = (0.09, 0.07, 0.07); sh.show_cavity = True; sh.cavity_type = "WORLD"
        sc.render.resolution_x, sc.render.resolution_y = 760, 760
        cam_d.ortho_scale = 2.2
        a = math.radians(yaw)
        d = Vector((math.sin(a), -math.cos(a), 0.14)).normalized()
        cam.location = Vector((0, 0, H / 2)) + d * 10
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = str(prev / f"{name}_{look}.png")
        bpy.ops.render.render(write_still=True)

    for nm, yaw in [("front", 0), ("side", 90), ("back34", 145), ("back", 180)]:
        shot(nm, yaw, "clay")
        shot(nm, yaw, "tex")
print("DONE")
