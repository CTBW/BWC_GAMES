"""Review images and measurements of goblin_rabble_rig.blend (run in a background Blender).

  blender -b goblin_rabble_rig.blend --python render_rig.py -- <out dir>

For each loadout (the rig's `loadout` property, 0 to 2), in the standard pose (the
`stand` Action) unless named otherwise:
- RIG_CHECK lines: hand vertices inside the weapon and weapon vertices inside the hand
  (count and deepest, mm), and how near each finger comes to the weapon (mm); the same
  for the left fist and the barrel shield's handle (on `ShieldBarrelStraps`).
- RIG_STAND lines: how near the forearms, hands and props come to the torso, skirt
  and legs (mm).
- RIG_PROPS lines, in the standard pose and the T-pose: body triangles that cut
  through each prop and the shield's straps, by bone, and how far the skin and the arm
  rag stay under the shield's back (mm).
- grip_<weapon>.png: the right hand from six sides, turned with the hand so the
  views match at rest and in any pose.
- shield_<shield>.png: the shield on the hanging left arm from six sides.
- body_<loadout>.png: the whole goblin, front, three-quarter and side from his left
  (shield), three-quarter from his right (weapon) and back.
- tpose_<loadout>.png: the T-pose the skin is bound to, front and three-quarter.
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
rig = bpy.data.objects["GoblinRabbleRig"]
body = bpy.data.objects["GoblinRabble"]
MX = "mixamorig:"
LOADOUTS = (("Knife", "ShieldBarrel"), ("Hatchet", "ShieldPlank"), ("Cleaver", "ShieldBarrel"))
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
    bpy.context.view_layer.update()


def turned(bone_name):
    """How the pose has turned a bone from its rest (world rotation; the rig sits at the origin)."""
    pb = rig.pose.bones[bone_name]
    return pb.matrix.to_3x3() @ pb.bone.matrix_local.to_3x3().inverted()


# The hand shells: the parts of the body mesh that reach furthest out on either side.
me = body.data
E = np.zeros(2 * len(me.edges), dtype=np.int64)
me.edges.foreach_get("vertices", E)
E = E.reshape(-1, 2)
N = len(me.vertices)
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
HAND = {s: np.nonzero(lab == lab[np.argmax(V0[:, 0] * k)])[0] for s, k in (("Right", -1), ("Left", 1))}
RAG = np.concatenate([np.nonzero(lab == k)[0] for k in np.unique(lab)
                      if (lab == k).sum() < 300 and V0[lab == k, 2].min() > 0.84 and 0.2 < V0[lab == k, 0].mean() < 0.36])
me.calc_loop_triangles()
TRI = np.array([t.vertices[:] for t in me.loop_triangles])
group_of = {g.index: g.name for g in body.vertex_groups}


def finger_of(vi, side):
    """The finger whose bones weigh most on vertex vi, or None for the palm."""
    best, w = None, 0.0
    for g in me.vertices[vi].groups:
        n = group_of[g.group]
        for f in FINGERS:
            if n.startswith(f"mixamorig:{side}Hand{f}") and g.weight > w:
                best, w = f, g.weight
    return best


FINGER_OF = {s: np.array([finger_of(int(v), s) or "" for v in HAND[s]]) for s in HAND}
# Which arm each vertex moves with (1 left, -1 right, 0 neither: torso, skirt, legs, head).
ARM = np.zeros(N, int)
for v in me.vertices:
    w = {1: 0.0, -1: 0.0}
    for g in v.groups:
        n = group_of[g.group]
        for s, side in ((1, "Left"), (-1, "Right")):
            if n.startswith((MX + side + "Arm", MX + side + "ForeArm", MX + side + "Hand", side + "ForeArm")):
                w[s] += g.weight
    ARM[v.index] = 1 if w[1] > 0.5 else (-1 if w[-1] > 0.5 else 0)
ARM[RAG] = 1


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
    # Where the deepest hand vertices are: their finger (or the palm) and the height on the prop.
    inv = bpy.data.objects[prop_name].matrix_world.inverted()
    for j in np.argsort(-hd)[:6]:
        if hd[j] > 0:
            print("RIG_CHECK   in prop", FINGER_OF[side][j] or "palm", "%.1f mm" % (hd[j] * 1000),
                  "at prop z %+.3f" % (inv @ Vector(P[idx[j]])).z)


def bone_of(vi):
    g = max(me.vertices[vi].groups, key=lambda g: g.weight, default=None)
    return group_of[g.group].replace(MX, "") if g else "-"


def props_check(label, weapon, shield, P):
    """Body triangles through each prop (exact triangle overlap), by the bone that weighs
    most on them (the hand holding the weapon touches it on purpose), and how far the
    skin and the arm rag stay under the shield's back."""
    btree = BVHTree.FromPolygons([Vector(p) for p in P], TRI.tolist())
    for name in (n for n in (weapon, shield, shield + "Straps") if n in bpy.data.objects):
        _, tree = world_mesh(bpy.data.objects[name])
        by = {}
        for i, _ in btree.overlap(tree):
            by.setdefault(bone_of(int(TRI[i][0])), set()).add(i)
        print("RIG_PROPS", label, name, "body triangles through it:", {g: len(t) for g, t in by.items()} or 0)
    ob = bpy.data.objects[shield]
    n = (ob.matrix_world.to_3x3() @ Vector((0, -1, 0))).normalized()
    _, tree = world_mesh(ob)
    near = np.nonzero(np.linalg.norm(P - np.array(ob.matrix_world.translation), axis=1) < 0.4)[0]
    for what, idx in (("skin", np.setdiff1d(near, RAG)), ("rag", RAG)):
        gaps = []
        for p in P[idx]:
            hit = tree.ray_cast(Vector(p) - n * 0.3, n, 0.6)[0]
            if hit is not None and (Vector(p) - hit).dot(n) < 0.15:   # not in front of it (the ear)
                gaps.append((hit - Vector(p)).dot(n))
        print("RIG_PROPS", label, what, "under", shield, ": %d vertices, nearest %.1f mm under its back"
              % (len(gaps), min(gaps) * 1000 if gaps else float("nan")))


def stand_check(label, weapon, shield, P):
    """Clearances in the standard pose."""
    rest = np.nonzero(ARM == 0)[0]
    kd = KDTree(len(rest))
    for j, i in enumerate(rest):
        kd.insert(Vector(P[i]), j)
    kd.balance()
    near = {}
    for s, side in ((1, "left"), (-1, "right")):
        idx = np.nonzero((ARM == s) & (P[:, 2] < 0.80))[0]
        near[side + " forearm and hand"] = min(kd.find(Vector(P[i]))[2] for i in idx)
    for name in (weapon, shield):
        W, _ = world_mesh(bpy.data.objects[name])
        near[name] = min(kd.find(Vector(p))[2] for p in W)
    print("RIG_STAND", label, "nearest the torso, skirt and legs (mm):", {k: round(v * 1000, 1) for k, v in near.items()})
    props_check("stand " + label, weapon, shield, P)


GRIP_VIEWS = {"front": (0, 1, -0.25), "back": (0, -1, -0.25), "top": (0, 0, -1), "bottom": (0, 0, 1),
              "outside": (1, 0, -0.2), "threeq": (0.6, 0.7, 0.4)}
SHIELD_VIEWS = {"out": (-1, 0, -0.1), "front_out": (-0.55, 0.75, -0.35), "front": (0, 1, -0.15),
                "back": (0, -1, -0.15), "top": (-0.25, 0.1, -1), "under": (-0.4, 0.45, 0.8)}
BODY_VIEWS = {"front": (0, 1, -0.1), "threeq_left": (-0.6, 0.8, -0.2), "side_left": (-1, 0, -0.05),
              "threeq_right": (0.6, 0.8, -0.2), "back": (0, -1, -0.1)}
for k, (weapon, shield) in enumerate(LOADOUTS):
    rig["loadout"] = k
    pose("stand")
    P = evaluated()
    check(f"loadout {k} {weapon}", "Right", weapon, P)
    if shield + "Straps" in bpy.data.objects and shield == "ShieldBarrel":
        check(f"loadout {k} handle", "Left", shield + "Straps", P)
    stand_check(f"loadout {k}", weapon, shield, P)
    # The grip, from the same sides of the hand as at rest.
    R = turned(MX + "RightHand")
    c = P[HAND["Right"]].mean(0)
    files = []
    for n, d in GRIP_VIEWS.items():
        up = Vector((0, 1, 0)) if abs(Vector(d).normalized().z) > 0.9 else Vector((0, 0, 1))
        files.append(shoot(out / f"_g{n}.png", c, R @ Vector(d), 0.26, up=R @ up))
    sheet(f"grip_{weapon.lower()}", files, 3)
    if weapon != "Cleaver":
        ob = bpy.data.objects[shield]
        c = ob.matrix_world.translation.lerp(Vector(P[HAND["Left"]].mean(0)), 0.3)
        files = [shoot(out / f"_s{n}.png", c, d, 0.78) for n, d in SHIELD_VIEWS.items()]
        sheet(f"shield_{shield.lower()}", files, 3)
    files = [shoot(out / f"_b{n}.png", (0, 0, 0.64), d, 1.5) for n, d in BODY_VIEWS.items()]
    sheet(f"body_{k}_{weapon.lower()}", files, 5)
    pose("tpose")
    props_check(f"tpose loadout {k}", weapon, shield, evaluated())
    files = [shoot(out / f"_t{n}.png", (0, 0, 0.66), d, 1.9, (700, 700))
             for n, d in (("front", (0, 1, 0)), ("threeq", (0.55, 0.8, -0.25)))]
    sheet(f"tpose_{k}_{weapon.lower()}", files, 2)
pose("stand")
rig["loadout"] = 0
print("RIG_REVIEW_DONE", out)
