"""Review images and measurements of goblin_archer_rig.blend (run in a background Blender).

  blender -b goblin_archer_rig.blend --python render_rig.py -- <out dir>

In the standard pose (the `stand` Action) unless named otherwise:
- RIG_CHECK lines: left-hand vertices inside the bow and bow vertices inside the hand
  (count and deepest, mm), and how near each finger comes to the bow (mm).
- RIG_STAND lines: how near the forearms, hands, the bow and the quiver come to the
  torso, skirt, legs and cape (mm).
- RIG_PROPS lines, in the standard pose and the T-pose: body triangles that cut through
  each prop, by bone, and the nearest the quiver comes to the cape and the hood (mm).
- grip_bow.png: the left hand on the bow from six sides, turned with the hand so the
  views match at rest and in any pose; grip_relax.png: the loose right hand, with the
  arrow shown.
- quiver.png: the quiver on his back from behind, both sides, above and the back
  three-quarters.
- body_stand.png: the whole goblin, front, three-quarter and side from his left (bow),
  three-quarter from his right and back; body_arrow.png: front and right three-quarter
  with the arrow shown.
- tpose.png: the T-pose the skin is bound to, front and three-quarter.
"""
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

out = Path(sys.argv[sys.argv.index("--") + 1:][0])
out.mkdir(parents=True, exist_ok=True)
sc = bpy.context.scene
sc.frame_set(1)
rig = bpy.data.objects["GoblinArcherRig"]
body = bpy.data.objects["GoblinArcher"]
MX = "mixamorig:"
FINGERS = ("Thumb", "Index", "Middle", "Ring")
STAND = bpy.data.actions["stand"]

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
rig.hide_render = True
cam = bpy.data.objects.new("ReviewCam", bpy.data.cameras.new("ReviewCam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"


def shoot(path, centre, direction, size, res=(600, 600), up=None):
    """Render looking along `direction` with `up` at the top (default world up, or the
    goblin's back, +y, when looking straight up or down)."""
    d = Vector(direction).normalized()
    cam.location = Vector(centre) - d * 5
    if up is None:
        up = Vector((0, 1, 0)) if abs(d.z) > 0.9 else Vector((0, 0, 1))
    x = d.cross(Vector(up)).normalized()
    cam.rotation_euler = Matrix((x, (-d).cross(x), -d)).transposed().to_euler()
    cam.data.ortho_scale = size
    cam.data.clip_start, cam.data.clip_end = 0.1, 20
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return path


def sheet(name, files, cols):
    """Tile the renders (all one size) into one PNG, left to right and top to bottom."""
    imgs = [bpy.data.images.load(str(f)) for f in files]
    w, h = imgs[0].size
    rows = math.ceil(len(imgs) / cols)
    canvas = np.ones((rows * h, cols * w, 4), np.float32)
    for k, im in enumerate(imgs):
        px = np.empty(w * h * 4, np.float32)
        im.pixels.foreach_get(px)
        r, c = divmod(k, cols)
        canvas[(rows - 1 - r) * h:(rows - r) * h, c * w:(c + 1) * w] = px.reshape(h, w, 4)
    img = bpy.data.images.new(name, cols * w, rows * h, alpha=True)
    img.pixels.foreach_set(canvas.ravel())
    img.filepath_raw = str(out / f"{name}.png")
    img.file_format = "PNG"
    img.save()
    for im in imgs:
        bpy.data.images.remove(im)
    for f in files:
        Path(f).unlink()


def pose(name):
    """'stand' (the standard pose) or 'tpose' (rest; the grips still apply)."""
    if name == "stand":
        rig.animation_data.action = STAND
        if hasattr(rig.animation_data, "action_slot") and len(STAND.slots):
            rig.animation_data.action_slot = STAND.slots[0]
    else:
        rig.animation_data.action = None
        for pb in rig.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
    rig.update_tag()
    sc.frame_set(1)
    bpy.context.view_layer.update()


def show_arrow(on):
    rig["arrow"] = int(on)
    rig.update_tag()
    sc.frame_set(1)
    bpy.context.view_layer.update()


def turned(bone_name):
    """How the pose has turned a bone from its rest (world rotation; the rig sits at the origin)."""
    pb = rig.pose.bones[bone_name]
    return pb.matrix.to_3x3() @ pb.bone.matrix_local.to_3x3().inverted()


me = body.data
N = len(me.vertices)
E = np.zeros(2 * len(me.edges), dtype=np.int64)
me.edges.foreach_get("vertices", E)
E = E.reshape(-1, 2)
lab = np.arange(N)
while True:
    new = lab.copy()
    m = np.minimum(lab[E[:, 0]], lab[E[:, 1]])
    np.minimum.at(new, E[:, 0], m)
    np.minimum.at(new, E[:, 1], m)
    if (new == lab).all():
        break
    lab = new
V0 = np.array([v.co[:] for v in me.vertices])
sizes = {k: (lab == k).sum() for k in np.unique(lab)}
by_size = sorted(sizes, key=lambda k: -sizes[k])
CAPE = np.nonzero(lab == by_size[1])[0]     # the hood and the cape, one sheet
me.calc_loop_triangles()
TRI = np.array([t.vertices[:] for t in me.loop_triangles])
group_of = {g.index: g.name for g in body.vertex_groups}


def weight_of(vi, prefixes):
    return sum(g.weight for g in me.vertices[vi].groups if group_of[g.group].startswith(prefixes))


HAND = {side: np.array([v for v in range(N) if weight_of(v, MX + side + "Hand") > 0.5]) for side in ("Left", "Right")}


def finger_of(vi, side):
    """The finger whose bones weigh most on vertex vi, or None for the palm."""
    best, w = None, 0.0
    for g in me.vertices[vi].groups:
        n = group_of[g.group]
        for f in FINGERS:
            if n.startswith(f"{MX}{side}Hand{f}") and g.weight > w:
                best, w = f, g.weight
    return best


FINGER_OF = {s: np.array([finger_of(int(v), s) or "" for v in HAND[s]]) for s in HAND}
# Which arm each vertex moves with (1 left, -1 right, 0 neither: torso, skirt, legs, head, cape).
ARM = np.zeros(N, int)
for v in range(N):
    l = weight_of(v, (MX + "LeftArm", MX + "LeftForeArm", MX + "LeftHand", "LeftForeArm"))
    r = weight_of(v, (MX + "RightArm", MX + "RightForeArm", MX + "RightHand", "RightForeArm"))
    ARM[v] = 1 if l > 0.5 else (-1 if r > 0.5 else 0)


def evaluated():
    dg = bpy.context.evaluated_depsgraph_get()
    ob = body.evaluated_get(dg)
    m = ob.to_mesh()
    P = np.array([(ob.matrix_world @ v.co)[:] for v in m.vertices])
    ob.to_mesh_clear()
    return P


def world_mesh(obj):
    M = obj.matrix_world
    P = np.array([(M @ v.co)[:] for v in obj.data.vertices])
    return P, BVHTree.FromPolygons([Vector(p) for p in P], [list(p.vertices) for p in obj.data.polygons])


def inside(tree, P, reach=0.02):
    """Depth (m) of each point inside the surface in `tree` (0 outside or out of reach)."""
    d = np.zeros(len(P))
    for i, p in enumerate(P):
        loc, nrm, _, dist = tree.find_nearest(Vector(p), reach)
        if loc is not None and (Vector(p) - loc).dot(nrm) < 0:
            d[i] = dist
    return d


def check(label, side, prop_name, P):
    idx = HAND[side]
    W, tree = world_mesh(bpy.data.objects[prop_name])
    hd = inside(tree, P[idx])
    loc = np.full(N, -1)
    loc[idx] = np.arange(len(idx))
    tri = TRI[(loc[TRI] >= 0).all(1)]
    htree = BVHTree.FromPolygons([Vector(p) for p in P], tri.tolist())
    wd = inside(htree, W)
    near = {}
    for f in FINGERS:
        q = P[idx[FINGER_OF[side] == f]]
        near[f] = round(min(tree.find_nearest(Vector(p))[3] for p in q) * 1000, 1)
    print("RIG_CHECK", label, "hand in prop: %d verts, deepest %.1f mm" % ((hd > 0).sum(), hd.max() * 1000),
          "| prop in hand: %d verts, deepest %.1f mm" % ((wd > 0).sum(), wd.max() * 1000), "| nearest per finger", near)
    inv = bpy.data.objects[prop_name].matrix_world.inverted()
    for j in np.argsort(-hd)[:6]:
        if hd[j] > 0:
            print("RIG_CHECK   in prop", FINGER_OF[side][j] or "palm", "%.1f mm" % (hd[j] * 1000),
                  "at prop z %+.3f" % (inv @ Vector(P[idx[j]])).z)


def bone_of(vi):
    g = max(me.vertices[vi].groups, key=lambda g: g.weight, default=None)
    return group_of[g.group].replace(MX, "") if g else "-"


def props_check(label, P):
    """Body triangles through each prop (exact triangle overlap), by the bone that weighs
    most on them (the left hand holds the bow on purpose), and the quiver's gap."""
    btree = BVHTree.FromPolygons([Vector(p) for p in P], TRI.tolist())
    for name in ("Bow", "Quiver", "Arrow"):
        _, tree = world_mesh(bpy.data.objects[name])
        by = {}
        for i, _ in btree.overlap(tree):
            by.setdefault(bone_of(int(TRI[i][0])), set()).add(i)
        print("RIG_PROPS", label, name, "body triangles through it:", {g: len(t) for g, t in by.items()} or 0)
    _, qtree = world_mesh(bpy.data.objects["Quiver"])
    gaps = {}
    for what, idx in (("cape and hood", CAPE), ("body", np.setdiff1d(np.arange(N), CAPE))):
        d = [qtree.find_nearest(Vector(p), 0.1)[3] for p in P[idx]]
        gaps[what] = round(min(x for x in d if x is not None) * 1000, 1) if any(x is not None for x in d) else None
    print("RIG_PROPS", label, "quiver nearest (mm):", gaps)


def stand_check(P):
    """Clearances in the standard pose."""
    rest = np.nonzero(ARM == 0)[0]
    kd = KDTree(len(rest))
    for j, i in enumerate(rest):
        kd.insert(Vector(P[i]), j)
    kd.balance()
    near = {}
    for s, side in ((1, "left"), (-1, "right")):
        idx = np.nonzero((ARM == s) & (P[:, 2] < 0.85))[0]
        near[side + " forearm and hand"] = min(kd.find(Vector(P[i]))[2] for i in idx)
    W, _ = world_mesh(bpy.data.objects["Bow"])
    near["bow"] = min(kd.find(Vector(p))[2] for p in W)
    print("RIG_STAND nearest the torso, skirt, legs and cape (mm):", {k: round(v * 1000, 1) for k, v in near.items()},
          "| bow lowest z %.3f" % W[:, 2].min())
    props_check("stand", P)


GRIP_VIEWS = {"front": (0, 1, -0.25), "back": (0, -1, -0.25), "top": (0, 0, -1), "bottom": (0, 0, 1),
              "outside": (-1, 0, -0.2), "threeq": (-0.6, 0.7, 0.4)}
QUIVER_VIEWS = {"back": (0, -1, -0.1), "back_right": (0.6, -0.8, -0.2), "right": (1, 0, -0.05),
                "left": (-1, 0, -0.05), "back_left": (-0.6, -0.8, -0.2), "top": (0, 0.25, -1)}
BODY_VIEWS = {"front": (0, 1, -0.1), "threeq_left": (-0.6, 0.8, -0.2), "side_left": (-1, 0, -0.05),
              "threeq_right": (0.6, 0.8, -0.2), "back": (0, -1, -0.1)}

pose("stand")
show_arrow(False)
P = evaluated()
check("stand bow", "Left", "Bow", P)
stand_check(P)
# The grips, from the same sides of each hand as at rest (the right hand's views mirrored).
for side, name, s in (("Left", "grip_bow", 1), ("Right", "grip_relax", -1)):
    show_arrow(side == "Right")
    R = turned(MX + side + "Hand")
    c = P[HAND[side]].mean(0)
    files = []
    for n, d in GRIP_VIEWS.items():
        d = Vector((d[0] * s, d[1], d[2]))
        up = Vector((0, 1, 0)) if abs(d.normalized().z) > 0.9 else Vector((0, 0, 1))
        files.append(shoot(out / f"_g{n}.png", c, R @ d, 0.26, up=R @ up))
    sheet(name, files, 3)
show_arrow(False)
files = [shoot(out / f"_q{n}.png", (0, 0.2, 1.05), d, 0.85) for n, d in QUIVER_VIEWS.items()]
sheet("quiver", files, 3)
files = [shoot(out / f"_b{n}.png", (0, 0, 0.74), d, 1.62) for n, d in BODY_VIEWS.items()]
sheet("body_stand", files, 5)
show_arrow(True)
files = [shoot(out / f"_a{n}.png", (0, 0, 0.74), BODY_VIEWS[n], 1.62) for n in ("front", "threeq_right")]
sheet("body_arrow", files, 2)
show_arrow(False)
pose("tpose")
props_check("tpose", evaluated())
files = [shoot(out / f"_t{n}.png", (0, 0, 0.74), d, 1.95, (700, 700))
         for n, d in (("front", (0, 1, 0)), ("threeq", (0.55, 0.8, -0.25)))]
sheet("tpose", files, 2)
pose("stand")
print("RIG_REVIEW_DONE", out)
