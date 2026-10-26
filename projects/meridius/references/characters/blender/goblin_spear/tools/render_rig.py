"""Review images and measurements of goblin_spear_rig.blend (run in a background Blender).

  blender -b goblin_spear_rig.blend --python render_rig.py -- <out dir>

In the standard pose (the `stand` Action) unless named otherwise:
- RIG_CHECK lines: each hand's vertices inside the spear and the spear's vertices inside
  the hand (count and deepest, mm), and how near each finger comes to the shaft (mm).
- RIG_STAND lines: how near the forearms, hands and the spear come to the torso, the
  skirt, the cape and the legs (mm).
- RIG_PROPS lines, in the standard pose and the T-pose: body triangles that cut through
  the spear, by the bone that weighs most on them (the fists hold it on purpose).
- grip_right.png, grip_left.png: each hand from six sides, turned with the hand so the
  views match at rest and in any pose.
- body.png: the whole goblin, front, three-quarter from his left and from his right,
  side from his left and back.
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
rig = bpy.data.objects["GoblinSpearmanRig"]
body = bpy.data.objects["GoblinSpearman"]
spear = bpy.data.objects["Spear"]
MX = "mixamorig:"
FINGERS = ("Thumb", "Index", "Middle", "Ring", "Pinky")
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
    """'stand' (the standard pose) or 'tpose' (rest, the left hand off the shaft; the grips
    still apply)."""
    if name == "stand":
        rig["support_ik"] = 1.0
        rig.animation_data.action = STAND
        if hasattr(rig.animation_data, "action_slot") and len(STAND.slots):
            rig.animation_data.action_slot = STAND.slots[0]
    else:
        rig["support_ik"] = 0.0
        rig.animation_data.action = None
        for pb in rig.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
    rig.update_tag()
    bpy.context.view_layer.update()


def turned(bone_name):
    """How the pose has turned a bone from its rest (world rotation; the rig sits at the origin)."""
    pb = rig.pose.bones[bone_name]
    return pb.matrix.to_3x3() @ pb.bone.matrix_local.to_3x3().inverted()


me = body.data
N = len(me.vertices)
me.calc_loop_triangles()
TRI = np.array([t.vertices[:] for t in me.loop_triangles])
group_of = {g.index: g.name for g in body.vertex_groups}


def bone_of(vi):
    g = max(me.vertices[vi].groups, key=lambda g: g.weight, default=None)
    return group_of[g.group].replace(MX, "") if g else "-"


DOM = np.array([bone_of(i) for i in range(N)])
# Each hand: the vertices its hand and finger bones weigh most on.
HAND = {s: np.nonzero(np.char.startswith(DOM.astype(str), s + "Hand"))[0] for s in ("Right", "Left")}
FINGER_OF = {s: np.array([next((f for f in FINGERS if d.startswith(f"{s}Hand{f}")), "") for d in DOM[HAND[s]]])
             for s in HAND}
# Which arm each vertex moves with (1 left, -1 right, 0 neither: torso, skirt, cape, legs, head).
ARM = np.zeros(N, int)
for v in me.vertices:
    w = {1: 0.0, -1: 0.0}
    for g in v.groups:
        n = group_of[g.group]
        for s, side in ((1, "Left"), (-1, "Right")):
            if n.startswith((MX + side + "Arm", MX + side + "ForeArm", MX + side + "Hand", side + "ForeArm")):
                w[s] += g.weight
    ARM[v.index] = 1 if w[1] > 0.5 else (-1 if w[-1] > 0.5 else 0)


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


def check(label, side, P):
    idx = HAND[side]
    W, tree = world_mesh(spear)
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
    print("RIG_CHECK", label, side, "hand in spear: %d verts, deepest %.1f mm" % ((hd > 0).sum(), hd.max() * 1000),
          "| spear in hand: %d verts, deepest %.1f mm" % ((wd > 0).sum(), wd.max() * 1000), "| nearest per finger", near)
    inv = spear.matrix_world.inverted()
    for j in np.argsort(-wd)[:4]:
        if wd[j] > 0:
            loc_, _, ti, _ = htree.find_nearest(Vector(W[j]))
            print("RIG_CHECK   spear in hand %.1f mm" % (wd[j] * 1000), "at spear", np.round(spear.data.vertices[int(j)].co[:], 3).tolist(),
                  "under", DOM[tri[ti][0]] if ti is not None else "-")
    for j in np.argsort(-hd)[:6]:
        if hd[j] > 0:
            print("RIG_CHECK   in spear", FINGER_OF[side][j] or "palm", "%.1f mm" % (hd[j] * 1000),
                  "at spear z %+.3f" % (inv @ Vector(P[idx[j]])).z)


def props_check(label, P):
    """Body triangles through the spear (exact triangle overlap), by the bone that weighs
    most on them."""
    btree = BVHTree.FromPolygons([Vector(p) for p in P], TRI.tolist())
    _, tree = world_mesh(spear)
    by = {}
    for i, _ in btree.overlap(tree):
        by.setdefault(DOM[TRI[i][0]], set()).add(i)
    print("RIG_PROPS", label, "body triangles through the spear:", {g: len(t) for g, t in by.items()} or 0)


def stand_check(P):
    """Clearances in the standard pose."""
    rest = np.nonzero(ARM == 0)[0]
    kd = KDTree(len(rest))
    for j, i in enumerate(rest):
        kd.insert(Vector(P[i]), j)
    kd.balance()
    near = {}
    for s, side in ((1, "left"), (-1, "right")):
        idx = np.nonzero(ARM == s)[0]
        idx = idx[P[idx, 2] < np.percentile(P[idx, 2], 60)]    # the lower part: forearm and hand
        near[side + " forearm and hand"] = min(kd.find(Vector(P[i]))[2] for i in idx)
    W, _ = world_mesh(spear)
    near["spear"] = min(kd.find(Vector(p))[2] for p in W)
    print("RIG_STAND nearest the torso, skirt, cape and legs (mm):", {k: round(v * 1000, 1) for k, v in near.items()})
    props_check("stand", P)


GRIP_VIEWS = {"front": (0, 1, -0.25), "back": (0, -1, -0.25), "top": (0, 0, -1), "bottom": (0, 0, 1),
              "outside": (1, 0, -0.2), "threeq": (0.6, 0.7, 0.4)}
BODY_VIEWS = {"front": (0, 1, -0.1), "threeq_left": (-0.6, 0.8, -0.2), "threeq_right": (0.6, 0.8, -0.2),
              "side_left": (-1, 0, -0.05), "back": (0, -1, -0.1)}
pose("stand")
P = evaluated()
for side in ("Right", "Left"):
    check("stand", side, P)
stand_check(P)
for side, s in (("Right", -1), ("Left", 1)):
    R = turned(MX + side + "Hand")
    c = P[HAND[side]].mean(0)
    files = []
    for n, d in GRIP_VIEWS.items():
        d = Vector((d[0] * -s, d[1], d[2])) if n in ("outside", "threeq") else Vector(d)
        up = Vector((0, 1, 0)) if abs(d.normalized().z) > 0.9 else Vector((0, 0, 1))
        files.append(shoot(out / f"_g{n}.png", c, R @ d, 0.26, up=R @ up))
    sheet(f"grip_{side.lower()}", files, 3)
files = [shoot(out / f"_b{n}.png", (0, 0, 0.78), d, 2.0, (700, 700)) for n, d in BODY_VIEWS.items()]
sheet("body", files, 5)
pose("tpose")
props_check("tpose", evaluated())
files = [shoot(out / f"_t{n}.png", (0, 0, 0.74), d, 2.2, (700, 700))
         for n, d in (("front", (0, 1, 0)), ("threeq", (0.55, 0.8, -0.25)))]
sheet("tpose", files, 2)
pose("stand")
print("RIG_REVIEW_DONE", out)
