"""Build the goblin archer base scene from the Tripo exports (run in a background Blender).

  blender -b --factory-startup --python build_archer.py -- <tripo dir> <out.blend>

1. Imports the textured body, bow, quiver and arrow from `<model>__take-01.zip` in
   the Tripo dir and copies each base colour to `textures/` next to the .blend.
2. Scales the body to H (1.486 m to the tip of the hood), feet on the ground,
   centred, facing -Y like the Mixamo clips. The cape is left as Tripo made it: one
   sheet from the shoulders that hangs about 14 degrees behind him, 8 to 10 cm clear
   of the back of his rag skirt, so the legs keep clear of it in a stride.
3. Scales each prop to its length, long axis Z, front facing -Y as in the Tripo
   front view, and puts its origin where the rig holds it: the bow on the axis of
   its handle at the middle of the grip (its string on +X), the quiver at the middle
   of its back (+Y) halfway up the tube, the arrow at the nock on the shaft's axis
   (its head up). The props stand beside the body in a `Props` collection.
"""
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

# Height of an archer goblin: the footman's 1.82 m times the battle view's figure
# heights, 40 px for a small unit against 49 for a man (squad_view.gd), measured to
# the tip of his hood.
H = 1.82 * 40 / 49
# Prop lengths in metres along the long axis, read off the archer concept against
# the goblin's height: the bow about three quarters of his height, the arrow and
# the quiver (with the fletchings) each about as long as his arm.
PROPS = {
    "bow": ("Bow", 1.10),
    "quiver": ("Quiver", 0.62),
    "arrow": ("Arrow", 0.62),
}
QUIVER_TUBE = 0.73   # share of the quiver's length up to its rim; the fletchings stand above

argv = sys.argv[sys.argv.index("--") + 1:]
tripo, out_blend = Path(argv[0]), Path(argv[1]).resolve()
tex_dir = out_blend.parent / "textures"
tex_dir.mkdir(parents=True, exist_ok=True)
unzip = Path(tempfile.mkdtemp(prefix="archer_"))

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
            dst = tex_dir / f"goblin_archer_{asset}_basecolor{src.suffix}"
            shutil.copyfile(src, dst)
            node.image.name = dst.stem
            node.image.filepath = str(dst)
            node.image.reload()
    return obj


def verts(obj):
    return np.array([v.co[:] for v in obj.data.vertices])


def axis_centre(P, z, half=0.012):
    """Middle of a slice's cross-section (3rd to 97th percentile), so stray points do not pull it."""
    q = P[np.abs(P[:, 2] - z) < half]
    return (float((np.percentile(q[:, 0], 3) + np.percentile(q[:, 0], 97)) / 2),
            float((np.percentile(q[:, 1], 3) + np.percentile(q[:, 1], 97)) / 2))


# --- Body -------------------------------------------------------------------
body = import_model("body", "GoblinArcher")
V = verts(body)
k = H / (V[:, 2].max() - V[:, 2].min())
body.data.transform(Matrix.Translation((-np.median(V[:, 0]), -np.median(V[:, 1]), -V[:, 2].min())))
body.data.transform(Matrix.Scale(k, 4))
V = verts(body)
print("ARCHER_BODY height %.3f, x %.3f to %.3f, y %.3f to %.3f" % (
    np.ptp(V[:, 2]), V[:, 0].min(), V[:, 0].max(), V[:, 1].min(), V[:, 1].max()))

# --- Props ------------------------------------------------------------------
col = bpy.data.collections.new("Props")
sc.collection.children.link(col)
x_at = 1.0
for asset, (name, length) in PROPS.items():
    obj = import_model(asset, name)
    P = verts(obj)
    s = length / (P[:, 2].max() - P[:, 2].min())
    obj.data.transform(Matrix.Translation((-(P[:, 0].min() + P[:, 0].max()) / 2,
                                           -(P[:, 1].min() + P[:, 1].max()) / 2, -P[:, 2].min())))
    obj.data.transform(Matrix.Scale(s, 4))
    P = verts(obj)
    if asset == "bow":
        # The grip is the middle of the bow. Its cross-section leaves out the string,
        # the straight strand on +X at the brace height.
        zg = length / 2
        q = P[np.abs(P[:, 2] - zg) < 0.03]
        handle = q[q[:, 0] < q[:, 0].max() - 0.05]
        x, y = axis_centre(handle, zg, 0.03)
        origin = Vector((x, y, zg))
        string = float(q[:, 0].max())
        print("ARCHER_BOW grip %.3f deep, %.3f wide; string %.3f behind the grip's axis" % (
            np.ptp(handle[:, 0]), np.ptp(handle[:, 1]), string - x))
    elif asset == "quiver":
        # The middle of the back (+Y), halfway up the tube.
        zm = QUIVER_TUBE * length / 2
        tree_p = BVHTree.FromPolygons([v.co.copy() for v in obj.data.vertices],
                                      [list(p.vertices) for p in obj.data.polygons])
        x, _ = axis_centre(P[P[:, 2] < QUIVER_TUBE * length], zm, 0.05)
        hit = tree_p.ray_cast(Vector((x, 1.0, zm)), Vector((0, -1, 0)), 2.0)
        origin = Vector((x, hit[0].y if hit[0] else float(P[:, 1].max()), zm))
    else:
        # The nock: the bottom of the shaft, on its axis (read on the bare shaft, between
        # the fletching and the head, whose long quads have vertices only at their ends).
        x, y = axis_centre(P, 0.565 * length, 0.29 * length)
        origin = Vector((x, y, 0.0))
    obj.data.transform(Matrix.Translation(-origin))
    for c in obj.users_collection:
        c.objects.unlink(obj)
    col.objects.link(obj)
    P = verts(obj)
    obj.location = (x_at + (P[:, 0].max() - P[:, 0].min()) / 2, 0.0, -P[:, 2].min())
    x_at += (P[:, 0].max() - P[:, 0].min()) + 0.12
    print("ARCHER_PROP", name, "length", length, "width", round(float(np.ptp(P[:, 0])), 3),
          "depth", round(float(np.ptp(P[:, 1])), 3), "origin above the bottom", round(float(-P[:, 2].min()), 3))

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
print("ARCHER_SAVED", out_blend)
