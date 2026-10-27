"""Build the orc brute base scene from the Tripo exports (run in a background Blender).

  blender -b --factory-startup --python build_orc_brute.py -- <tripo dir> <out.blend>

1. Imports the textured body, club and knife from `<model>__take-01.zip` in the
   Tripo dir and copies each base colour to `textures/` next to the .blend.
2. Scales the body to H (2.006 m to the top of his head), feet on the ground,
   centred, facing -Y like the Mixamo clips.
3. Gives the club's grip a solid core. Tripo modelled the grip as the leather wrap
   alone, one open sheet round an empty middle, so between the turns of the wrap
   one could see through the handle. The core is a closed tube from inside the
   knob to inside the shaft, following the wrap 1.5 mm under its outer surface,
   textured with the wrap's own dark leather.
4. Scales each weapon to its length, long axis Z, front facing -Y as in the Tripo
   front view, and puts its origin where the rig holds it: the club on its grip's
   axis just above the knob, the knife on its handle's axis halfway between the
   pommel and the guard. The weapons stand beside the body in a `Props` collection.
"""
import math
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

# Height of an orc brute: the footman's 1.82 m times the battle view's figure
# heights, 54 px for an orc against 49 for a man (member_height in squad_view.gd),
# measured to the top of his head.
H = 1.82 * 54 / 49
# Weapon lengths in metres, read off the user's sprite against his height (he is
# about 470 px tall there; the club about 190 px and the knife about 160 px, both
# foreshortened): a war club as long as his arm, a long fighting knife.
PROPS = {
    "club": ("Club", 0.85),
    "knife": ("Knife", 0.60),
}
CORE_MARGIN = 0.0015   # the core's surface under the club's outer surface (m)
CORE_SIDES = 20
CORE_STEP = 0.006     # between the core's rings (m)
FIST_ABOVE_KNOB = 0.07  # the middle of the fist above the top of the club's knob (m)

argv = sys.argv[sys.argv.index("--") + 1:]
tripo, out_blend = Path(argv[0]), Path(argv[1]).resolve()
tex_dir = out_blend.parent / "textures"
tex_dir.mkdir(parents=True, exist_ok=True)
unzip = Path(tempfile.mkdtemp(prefix="orc_brute_"))

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.unit_settings.system = "METRIC"


def import_model(asset, name):
    """Import `<asset>__take-01.zip`; return the mesh with its transforms applied."""
    folder = unzip / asset
    with zipfile.ZipFile(tripo / f"{asset}__take-01.zip") as z:
        z.extractall(folder)
    fbx = next(folder.glob("*.fbx"))
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(fbx))
    new = [o for o in bpy.data.objects if o not in before]
    obj = next(o for o in new if o.type == "MESH")
    for o in new:
        if o is not obj:
            bpy.data.objects.remove(o)
    obj.name = obj.data.name = name
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mat = obj.data.materials[0]
    mat.name = name
    for node in mat.node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image:
            src = Path(bpy.path.abspath(node.image.filepath))
            dst = tex_dir / f"orc_brute_{asset}_basecolor{src.suffix}"
            shutil.copyfile(src, dst)
            node.image.name = dst.stem
            node.image.filepath = str(dst)
            node.image.reload()
    return obj


def verts(obj):
    return np.array([v.co[:] for v in obj.data.vertices])


def section_centre(P, z, half):
    """Middle of a slice's cross-section (3rd to 97th percentile), so stray points do not pull it."""
    q = P[np.abs(P[:, 2] - z) < half]
    return np.array([(np.percentile(q[:, i], 3) + np.percentile(q[:, i], 97)) / 2 for i in (0, 1)])


def width_profile(P, length, n=200):
    zs = np.linspace(0, length, n)
    w = np.array([np.ptp(P[np.abs(P[:, 2] - z) < length / n, 0]) if (np.abs(P[:, 2] - z) < length / n).any() else 0.0
                  for z in zs])
    return zs, w


def tree_of(obj):
    return BVHTree.FromPolygons([v.co.copy() for v in obj.data.vertices],
                                [list(p.vertices) for p in obj.data.polygons])


def see_through(obj, axis_xy, z0, z1, n_z=60, n_a=48):
    """Rays from outside toward the axis that reach it without touching the mesh."""
    tree = tree_of(obj)
    misses = 0
    for z in np.linspace(z0, z1, n_z):
        c = Vector((axis_xy[0], axis_xy[1], z))
        for a in np.linspace(0, 2 * math.pi, n_a, endpoint=False):
            d = Vector((math.cos(a), math.sin(a), 0))
            if tree.ray_cast(c + d * 0.5, -d, 0.5)[0] is None:
                misses += 1
    return misses, n_z * n_a


# --- Body -------------------------------------------------------------------
body = import_model("body", "OrcBrute")
V = verts(body)
k = H / (V[:, 2].max() - V[:, 2].min())
body.data.transform(Matrix.Translation((-np.median(V[:, 0]), -np.median(V[:, 1]), -V[:, 2].min())))
body.data.transform(Matrix.Scale(k, 4))
V = verts(body)
print("BRUTE_BODY height %.3f, x %.3f to %.3f, y %.3f to %.3f" % (
    np.ptp(V[:, 2]), V[:, 0].min(), V[:, 0].max(), V[:, 1].min(), V[:, 1].max()))


# --- Club grip core ---------------------------------------------------------
def build_grip_core(obj, length):
    """Close the club's hollow grip with a core under the wrap; return (axis, knob top)."""
    P = verts(obj)
    # The knob: the widest section in the bottom tenth; its top is where the width
    # first drops under 85% of that above it. Sections 6 mm thick, so a thin slice
    # between the knob's rings does not read as its top.
    zs = np.linspace(0, 0.2 * length, 120)
    w = np.array([np.ptp(P[np.abs(P[:, 2] - z) < 0.003, 0]) if (np.abs(P[:, 2] - z) < 0.003).sum() > 3 else np.nan
                  for z in zs])
    w = np.where(np.isnan(w), np.interp(zs, zs[~np.isnan(w)], w[~np.isnan(w)]), w)
    low = zs < 0.1 * length
    i_knob = int(np.argmax(np.where(low, w, 0)))
    i_top = i_knob + int(np.argmax(w[i_knob:] < 0.85 * w[i_knob]))
    knob_top = float(zs[i_top])
    # The shaft's bottom end is open under the wrap's top band (up to 0.39 of the
    # length); the core runs from inside the knob to just above that.
    z0, z1 = 0.07 * length, 0.40 * length
    # The grip's axis: a straight line through the middles of its sections.
    zc = np.linspace(0.12 * length, 0.36 * length, 12)
    C = np.array([section_centre(P, z, 0.006) for z in zc])
    fit = [np.polyfit(zc, C[:, i], 1) for i in (0, 1)]

    def axis_at(z):
        return Vector((np.polyval(fit[0], z), np.polyval(fit[1], z), z))

    tree = tree_of(obj)
    rings = np.arange(z0, z1 + 1e-6, CORE_STEP)
    angles = np.linspace(0, 2 * math.pi, CORE_SIDES, endpoint=False)

    def outer(z, a):
        c = axis_at(z)
        d = Vector((math.cos(a), math.sin(a), 0))
        hit = tree.ray_cast(c + d * 0.5, -d, 0.5)[0]
        return np.nan if hit is None else (hit - c).length

    R = np.array([[outer(z, a) for a in angles] for z in rings])
    # The outer surface sampled 4 times as densely round and every 1.5 mm along. Each
    # core vertex takes the smallest outer radius over the faces it touches, so the
    # flat faces between the vertices stay under the wrap's turns too.
    sub = 4
    zd = np.arange(z0 - CORE_STEP, z1 + CORE_STEP + 1e-6, 0.0015)
    ad = np.linspace(0, 2 * math.pi, sub * CORE_SIDES, endpoint=False)
    Rd = np.array([[outer(z, a) for a in ad] for z in zd])
    core = np.full_like(R, np.nan)
    for i, z in enumerate(rings):
        rows = np.abs(zd - z) <= CORE_STEP + 1e-6
        for j in range(CORE_SIDES):
            cols = [(sub * j + k) % (sub * CORE_SIDES) for k in range(-sub, sub + 1)]
            block = Rd[np.ix_(rows, cols)]
            if np.isfinite(block).any():
                core[i, j] = np.nanmin(block)
    # Directions that see through the wrap everywhere near a vertex take their
    # neighbours' radius.
    for _ in range(20):
        nan = np.isnan(core)
        if not nan.any():
            break
        nb = np.stack([np.roll(core, s, axis=1) for s in (-1, 1)] +
                      [np.roll(core, s, axis=0) for s in (-1, 1)])
        core[nan] = np.nanmin(nb, axis=0)[nan]
    core = core - CORE_MARGIN

    # UVs: a small patch of the wrap's own dark leather. The wrap is the loose part
    # that fills the middle of the grip; take the texel colour at each of its loops
    # and use the one nearest the wrap's median colour.
    me = obj.data
    uv = me.uv_layers.active.data
    img = next(n.image for n in me.materials[0].node_tree.nodes if n.type == "TEX_IMAGE" and n.image)
    px = np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4)
    mid = 0.5 * (z0 + z1)
    cand = []
    for poly in me.polygons:
        if abs(poly.center.z - mid) < 0.08 * length and (Vector(poly.center.xy) - axis_at(poly.center.z).xy).length < 0.05:
            for li in poly.loop_indices:
                u, v = uv[li].uv
                x = min(max(int(u * img.size[0]), 0), img.size[0] - 1)
                y = min(max(int(v * img.size[1]), 0), img.size[1] - 1)
                cand.append((u, v, *px[y, x, :3]))
    cand = np.array(cand)
    med = np.median(cand[:, 2:], axis=0)
    u0, v0 = cand[np.argmin(np.linalg.norm(cand[:, 2:] - med, axis=1)), :2]
    print("BRUTE_CORE leather texel rgb %.2f %.2f %.2f at uv %.4f %.4f" % (*med, u0, v0))

    bm = bmesh.new()
    bm.from_mesh(me)
    uvl = bm.loops.layers.uv.active
    ring_verts = []
    for i, z in enumerate(rings):
        c = axis_at(z)
        ring_verts.append([bm.verts.new(c + Vector((math.cos(a), math.sin(a), 0)) * core[i, j])
                           for j, a in enumerate(angles)])
    new_faces = []
    for i in range(len(rings) - 1):
        for j in range(CORE_SIDES):
            jn = (j + 1) % CORE_SIDES
            new_faces.append(bm.faces.new((ring_verts[i][j], ring_verts[i][jn],
                                           ring_verts[i + 1][jn], ring_verts[i + 1][j])))
    new_faces.append(bm.faces.new(list(reversed(ring_verts[0]))))
    new_faces.append(bm.faces.new(ring_verts[-1]))
    for f in new_faces:
        f.material_index = 0
        f.smooth = True
        for loop in f.loops:
            co = loop.vert.co
            a = math.atan2(co.y - axis_at(co.z).y, co.x - axis_at(co.z).x) % (2 * math.pi)
            loop[uvl].uv = (u0 + 0.003 * a / (2 * math.pi), v0 + 0.003 * (co.z - z0) / (z1 - z0))
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    me.update()
    # The check, on a grid 3 times finer again round and every 2 mm along: where the
    # outer surface lies inside the core, the core fills a slit or groove in the wrap
    # (wanted); it must never stand above the wrap's own surface around that spot
    # (the highest outer radius within 4 mm along and 9 degrees round).
    zg = np.arange(z0, z1, 0.002)
    ag = np.linspace(0, 2 * math.pi, 3 * sub * CORE_SIDES, endpoint=False)
    G = np.array([[outer(z, a) for a in ag] for z in zg])
    Cg = np.empty_like(G)
    for gi, z in enumerate(zg):
        i = min(int((z - z0) / CORE_STEP), len(rings) - 2)
        t = (z - rings[i]) / CORE_STEP
        fj = ag / (2 * math.pi) * CORE_SIDES
        j = fj.astype(int) % CORE_SIDES
        u = fj - fj.astype(int)
        jn = (j + 1) % CORE_SIDES
        Cg[gi] = ((1 - t) * ((1 - u) * core[i, j] + u * core[i, jn]) +
                  t * ((1 - u) * core[i + 1, j] + u * core[i + 1, jn]))
    Gf = np.where(np.isnan(G), -np.inf, G)
    top = Gf.copy()
    for di in range(-2, 3):
        for dj in range(-6, 7):
            top = np.maximum(top, np.roll(np.roll(Gf, di, axis=0), dj, axis=1))
    filling = (Cg > np.where(np.isnan(G), 0, G)).sum()
    hole = np.isinf(top)   # see-through all round the spot: the core is the only surface
    above = np.where(hole, -np.inf, Cg - top)
    gi, gj = np.unravel_index(int(np.argmax(above)), Cg.shape)
    print("BRUTE_CORE fills slits on %d of %d samples (in open holes %d); highest above the wrap around it "
          "%.2f mm (z %.3f m, %.0f deg)" % (filling, G.size, int(hole.sum()), above[gi, gj] * 1000, zg[gi],
                                          math.degrees(ag[gj])))
    print("BRUTE_CORE rings %d x %d sides, z %.3f to %.3f m, radius %.1f to %.1f mm (outer surface %.1f to %.1f mm)" % (
        len(rings), CORE_SIDES, z0, z1, core.min() * 1000, core.max() * 1000,
        np.nanmin(R) * 1000, np.nanmax(R) * 1000))
    print("BRUTE_CORE see-through directions before: %d of %d" % (int(np.isnan(R).sum()), R.size))
    return axis_at, knob_top


# --- Props ------------------------------------------------------------------
col = bpy.data.collections.new("Props")
sc.collection.children.link(col)
x_at = 0.9
for asset, (name, length) in PROPS.items():
    obj = import_model(asset, name)
    P = verts(obj)
    s = length / (P[:, 2].max() - P[:, 2].min())
    obj.data.transform(Matrix.Translation((-(P[:, 0].min() + P[:, 0].max()) / 2,
                                           -(P[:, 1].min() + P[:, 1].max()) / 2, -P[:, 2].min())))
    obj.data.transform(Matrix.Scale(s, 4))
    P = verts(obj)
    if asset == "club":
        axis_at, knob_top = build_grip_core(obj, length)
        miss, total = see_through(obj, tuple(axis_at(0.2 * length).xy), 0.04 * length, 0.42 * length)
        print("BRUTE_CORE see-through rays after, along the whole grip: %d of %d" % (miss, total))
        origin = axis_at(knob_top + FIST_ABOVE_KNOB)
        print("BRUTE_CLUB knob top %.3f m, fist centre %.3f m, wrap to %.3f m" % (
            knob_top, origin.z, 0.37 * length))
    else:
        # Guard: the widest slice in the lower half; the grip halfway between it and the pommel.
        zs, w = width_profile(P, length)
        lower = zs < 0.5 * length
        guard = float(zs[lower][np.argmax(w[lower])])
        origin = Vector((*section_centre(P, guard * 0.5, 0.015), guard * 0.5))
        miss, total = see_through(obj, tuple(origin.xy), 0.02 * length, guard - 0.01)
        print("BRUTE_KNIFE guard %.3f m, grip centre %.3f m; see-through rays along the grip: %d of %d" % (
            guard, origin.z, miss, total))
    obj.data.transform(Matrix.Translation(-origin))
    for c in obj.users_collection:
        c.objects.unlink(obj)
    col.objects.link(obj)
    P = verts(obj)
    obj.location = (x_at + (P[:, 0].max() - P[:, 0].min()) / 2, 0.0, -P[:, 2].min())
    x_at += (P[:, 0].max() - P[:, 0].min()) + 0.15
    print("BRUTE_PROP", name, "length", length, "width", round(float(np.ptp(P[:, 0])), 3),
          "depth", round(float(np.ptp(P[:, 1])), 3), "origin above the bottom", round(float(-P[:, 2].min()), 3),
          "faces", len(obj.data.polygons))

# Each image's path is a fixed-size buffer too: fill it, then write the path relative
# to the .blend (the textures are next to it), so neither the unzip folder nor the
# absolute path stays behind it.
for img in bpy.data.images:
    if img.filepath_raw:
        rel = "//" + Path(img.filepath_raw).resolve().relative_to(out_blend.parent).as_posix()
        img.filepath_raw = "//" + "_" * 700
        img.filepath_raw = rel
# Every screen's File Browser keeps the folder it last showed (the user's Documents
# folder by default) in a fixed-size buffer: fill it before shortening it, so no
# bytes of the old path stay in the file.
for screen in bpy.data.screens:
    for area in screen.areas:
        for space in area.spaces:
            if space.type == "FILE_BROWSER" and space.params is not None:
                space.params.directory = b"//" + b"_" * 700
                space.params.directory = b"//"
bpy.ops.wm.save_as_mainfile(filepath=str(out_blend), relative_remap=True, compress=True)
shutil.rmtree(unzip, ignore_errors=True)
print("BRUTE_SAVED", out_blend)
