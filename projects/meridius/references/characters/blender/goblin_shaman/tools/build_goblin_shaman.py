"""Build the goblin shaman base scene from the Tripo exports (run in a background Blender).

  blender -b --factory-startup --python build_goblin_shaman.py -- <tripo dir> <out.blend>

1. Imports the textured body and the staff from `<model>__take-01.zip` in the Tripo dir
   and copies each base colour to `textures/` next to the .blend.
2. Scales the body to H (1.486 m to the top of his head), feet on the ground, facing -Y
   like the Mixamo clips, centred on his mirror plane (Tripo's model is a few centimetres
   off it) and front to back on the middle of his body at the belt, so he turns on the spot.
3. Scales the staff to LENGTH, long axis Z with the skull up, facing -Y as in the Tripo
   front view, and thins its shaft below the rags so a goblin's three fingers close round
   it: the bare wood to SHAFT_D and the leather grip to GRIP_D, each slice about its own
   middle, so the gnarled bends stay. The skull, the rags and the feathers keep Tripo's
   size. Its origin is on the grip's axis at its middle. It stands beside the body in a
   `Props` collection.
4. Paints tribal markings in dried blood on his skin over Tripo's base colour in
   `textures/` (paint_goblin_shaman.py), before the mask can move his face, so the shaman
   in either mask has the same texture.
5. Gives him his mask (`MaskPlate`, in the `Props` collection), as MASK says. A squad has
   one shaman in each (goblin_shaman_base.blend, goblin_shaman_beak_base.blend).
   * `horned` (the default): the horned skull plate from `goblin_shaman_mask_plate.blend`
     next to the output (trim_mask.py), whose base colour is already in `textures/`,
     fitted to his face: scaled by MASK_SCALE, its eye sockets level with his eyes and
     centred on his mirror plane, then moved back and bent round his head (at most
     MASK_BEND) so its back edge rests on his cheeks and brow. The snout and brow it hides
     are pushed back behind it, MASK_GAP off its inside, and whatever of his head still
     comes closer (at the plate's sides and inside its teeth) is pushed in along the
     plate's inside.
   * `beak`: the bird skull mask with its red band and feather crest, built from code
     round his face (beak_mask.py) and painted into
     `textures/goblin_shaman_beak_mask_basecolor.jpg` (paint_beak_mask.py). His face is
     left as Tripo made it: the skull is carved out round it.
"""
import math
import os
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

# Height of a goblin: the footman's 1.82 m times the battle view's figure heights, 40 px
# for a small unit against 49 for a man (squad_view.gd), as for the other goblins.
H = 1.82 * 40 / 49
# The staff, foot to horn tips: "a little taller than him", as in the brief
# (`../../goblin_shaman/prompts.md`, 2. Staff) and the sprite (`source_crop.png`).
LENGTH = 1.65
# Shaft and grip diameters. The bare wood is the goblin spearman's 3.4 cm less 1 mm;
# the leather grip stands 1.5 mm proud of it, as the wrap does on Tripo's staff (where
# the shaft is 4.6 cm and the grip 5.8 cm at this length, too thick for his fingers).
SHAFT_D = 0.033
GRIP_D = 0.036
# Shares of the staff's length, read off the Tripo mesh's profile (rays round the shaft
# every 0.5% of its length): the bare shaft used to measure it, the leather grip (it is
# thicker than the wood on either side), and the stretch above the grip, past the
# feathers' cord, over which the thinning gives way to Tripo's size before the rags.
BARE = (0.10, 0.32)
GRIP = (0.335, 0.455)
TAPER = (0.46, 0.56)
# The mask: `horned` (Tripo's skull, trimmed to a plate) or `beak` (built from code).
MASK = os.environ.get("MASK", "horned")
assert MASK in ("beak", "horned"), MASK
# The horned plate: metres per unit of the plate (Tripo's mask is 1 high, fang tips to
# horn tips), and the gap left between its inside and the face. 0.34 covers his face from
# the brow to below his mouth and out to his ears (the user chose it over 0.27, 0.31 and 0.37).
MASK_SCALE = float(os.environ.get("MASK_SCALE", "0.34"))
MASK_GAP = 0.003
# How far (metres) the bend round his head may move one point of the plate more than another.
MASK_BEND = float(os.environ.get("MASK_BEND", "0.10"))
# His face under the plate is pushed back behind it: each column of it within TUCK_DEPTH of
# its front, fading out over TUCK_FADE round the plate.
TUCK_DEPTH = 0.06
# The plate's back edge is closed onto his face, the plate within RIM_FADE of it following.
RIM_FADE = float(os.environ.get("RIM_FADE", "0.05"))
TUCK_FADE = 0.03
# What of his head the tuck misses and still comes within MASK_GAP of the plate is pushed in
# along the plate's inside, his face round it following over CLEAR_FADE.
CLEAR_FADE = 0.015

argv = sys.argv[sys.argv.index("--") + 1:]
tripo, out_blend = Path(argv[0]), Path(argv[1]).resolve()
tex_dir = out_blend.parent / "textures"
tex_dir.mkdir(parents=True, exist_ok=True)
plate_blend = Path(os.environ.get("MASK_PLATE", out_blend.parent / "goblin_shaman_mask_plate.blend"))
mask_tex = tex_dir / "goblin_shaman_mask_basecolor.jpg"
if MASK == "horned" and not mask_tex.exists():
    shutil.copyfile(plate_blend.parent / "textures" / mask_tex.name, mask_tex)
unzip = Path(tempfile.mkdtemp(prefix="goblin_shaman_"))

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
            dst = tex_dir / f"goblin_shaman_{asset}_basecolor{src.suffix}"
            shutil.copyfile(src, dst)
            node.image.name = dst.stem
            node.image.filepath = str(dst)
            node.image.reload()
    return obj


def verts(obj):
    return np.array([v.co[:] for v in obj.data.vertices])


def set_verts(obj, P):
    obj.data.vertices.foreach_set("co", P.astype(np.float32).ravel())
    obj.data.update()


def islands(obj):
    """The mesh's separate parts (vertex index lists), largest first."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    seen, out = set(), []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack, part = [v], []
        while stack:
            w = stack.pop()
            if w.index in seen:
                continue
            seen.add(w.index)
            part.append(w.index)
            stack.extend(e.other_vert(w) for e in w.link_edges)
        out.append(part)
    bm.free()
    return sorted(out, key=len, reverse=True)


def split_both(obj):
    """Its faces as triangles, each quad split along both diagonals (so a check holds
    whichever way a later step splits it), and the face each triangle came from."""
    tris, face_of = [], []
    for p in obj.data.polygons:
        v = list(p.vertices)
        if len(v) == 4:
            new = [v[:3], [v[0], v[2], v[3]], v[1:], [v[1], v[3], v[0]]]
        else:
            new = [[v[0], v[k], v[k + 1]] for k in range(1, len(v) - 1)]
        tris += new
        face_of += [p.index] * len(new)
    return tris, np.array(face_of)


def tree_of(P, obj, keep=None):
    faces = [list(p.vertices) for p in obj.data.polygons]
    if keep is not None:
        faces = [f for f in faces if keep[f].all()]
    return BVHTree.FromPolygons([Vector(p) for p in P], faces)


# --- Body -------------------------------------------------------------------
body = import_model("body", "GoblinShaman")
V = verts(body)
k = H / (V[:, 2].max() - V[:, 2].min())
body.data.transform(Matrix.Translation((-np.median(V[:, 0]), -np.median(V[:, 1]), -V[:, 2].min())))
body.data.transform(Matrix.Scale(k, 4))
V = verts(body)
# Centre him on his mirror plane, which the median misses by a few centimetres: the
# middle of each pair of mirrored parts (legs, eyes, tusks, necklace fangs), the median
# of those. Tripo's pairs differ by a few vertices, so a pair may differ by 10%.
parts = islands(body)
cents = np.array([(len(p), *V[p].mean(0)) for p in parts[1:]])
mids = [(a[1] + b[1]) / 2 for i, a in enumerate(cents) for b in cents[i + 1:]
        if abs(a[0] - b[0]) <= 0.1 * a[0] and abs(a[2] - b[2]) < 0.01 and abs(a[3] - b[3]) < 0.01
        and abs(a[1] - b[1]) > 0.02]
assert len(mids) >= 4, f"only {len(mids)} mirrored pairs"
dx = -float(np.median(mids))
# Front to back: the middle of the body's main shell at the belt (the skirt below it and
# the pouches are left out), as the spearman is centred on his pelvis.
main = np.array(parts[0])
M = V[main]
belt = M[(M[:, 2] > 0.70) & (M[:, 2] < 0.80) & (np.abs(M[:, 0] + dx) < 0.15)]
dy = -float((np.percentile(belt[:, 1], 3) + np.percentile(belt[:, 1], 97)) / 2)
body.data.transform(Matrix.Translation((dx, dy, 0)))
V = verts(body)
print("SHAMAN_CENTRE %d mirrored pairs, moved x %+.4f (spread %.4f), y %+.4f" % (
    len(mids), dx, float(np.ptp(mids)), dy))
print("SHAMAN_BODY height %.3f, x %.3f to %.3f, y %.3f to %.3f, %d vertices, %d faces, %d parts" % (
    np.ptp(V[:, 2]), V[:, 0].min(), V[:, 0].max(), V[:, 1].min(), V[:, 1].max(),
    len(V), len(body.data.polygons), len(parts)))

# --- Staff ------------------------------------------------------------------
staff = import_model("staff", "Staff")
P = verts(staff)
P -= (0.0, 0.0, P[:, 2].min())
P *= LENGTH / np.ptp(P[:, 2])
L = LENGTH
s_parts = islands(staff)
in_main = np.zeros(len(P), bool)
in_main[s_parts[0]] = True
s_tree = tree_of(P, staff, in_main)


def slice_centre(z, win=0.01):
    """Middle of the main shell's cross-section at height z (3rd to 97th percentile of its
    vertices within a window that grows until it holds a ring)."""
    while True:
        q = P[in_main & (np.abs(P[:, 2] - z) < win * L)]
        if len(q) >= 8:
            return np.array([(np.percentile(q[:, 0], 3) + np.percentile(q[:, 0], 97)) / 2,
                              (np.percentile(q[:, 1], 3) + np.percentile(q[:, 1], 97)) / 2])
        win *= 1.5


def ring_radius(z, c):
    """Median distance from the middle to the surface, 16 rays round the slice."""
    rs = []
    for a in np.linspace(0, 2 * math.pi, 16, endpoint=False):
        d = Vector((math.cos(a), math.sin(a), 0))
        hit = s_tree.ray_cast(Vector((c[0], c[1], z)) + d * 0.3, -d, 0.6)
        if hit[0] is not None:
            rs.append(0.3 - hit[3])
    return float(np.median(rs))


ts = np.arange(0.0, TAPER[1] + 0.011, 0.005)
CEN = np.array([slice_centre(t * L) for t in ts])
# Smooth the middles a little (5 slices), so one knot does not pull its slice aside.
ker = np.ones(5) / 5
CEN = np.c_[np.convolve(np.pad(CEN[:, 0], 2, mode="edge"), ker, "valid"),
            np.convolve(np.pad(CEN[:, 1], 2, mode="edge"), ker, "valid")]
d_bare = 2 * float(np.median([ring_radius(t * L, c) for t, c in zip(ts, CEN) if BARE[0] <= t <= BARE[1]]))
d_grip = 2 * float(np.median([ring_radius(t * L, c) for t, c in zip(ts, CEN) if GRIP[0] + 0.01 <= t <= GRIP[1] - 0.01]))
s_bare, s_grip = SHAFT_D / d_bare, GRIP_D / d_grip


def shrink(t):
    """Scale across the staff at share t of its length: the bare wood's, the grip's (with a
    0.5% blend at each end of the wrap) and back to 1 over TAPER."""
    g = np.clip(np.minimum(t - GRIP[0] + 0.0025, GRIP[1] + 0.0025 - t) / 0.005, 0, 1)
    s = s_bare + (s_grip - s_bare) * g
    up = np.clip((t - TAPER[0]) / (TAPER[1] - TAPER[0]), 0, 1)
    up = up * up * (3 - 2 * up)
    return s + (1 - s) * up


t_v = P[:, 2] / L
low = in_main & (t_v < TAPER[1])
c_v = np.c_[np.interp(t_v[low], ts, CEN[:, 0]), np.interp(t_v[low], ts, CEN[:, 1])]
P[low, :2] = c_v + shrink(t_v[low])[:, None] * (P[low, :2] - c_v)
# The origin: the middle of the leather grip, on its axis.
g_mask = (ts >= GRIP[0]) & (ts <= GRIP[1])
gc = CEN[g_mask].mean(0)
gz = (GRIP[0] + GRIP[1]) / 2 * L
P -= (gc[0], gc[1], gz)
set_verts(staff, P)
s_tree = tree_of(P, staff, in_main)
d_after = 2 * float(np.median([ring_radius(t * L - gz, c - gc) for t, c in zip(ts, CEN) if BARE[0] <= t <= BARE[1]]))
g_after = 2 * float(np.median([ring_radius(t * L - gz, c - gc) for t, c in zip(ts, CEN) if GRIP[0] + 0.01 <= t <= GRIP[1] - 0.01]))
lean = math.degrees(math.atan2(np.linalg.norm(CEN[g_mask][-1] - CEN[g_mask][0]), (GRIP[1] - GRIP[0]) * L))
print("SHAMAN_STAFF length %.3f; shaft %.4f thinned to %.4f (x%.3f), grip %.4f to %.4f (x%.3f); "
      "grip %.3f-%.3f m from the foot, its axis %.1f deg off Z; the foot %.3f below the origin" % (
          L, d_bare, d_after, s_bare, d_grip, g_after, s_grip, GRIP[0] * L, GRIP[1] * L, lean, -P[:, 2].min()))
staff["length"] = L
staff["shaft_r"] = d_after / 2
staff["grip_r"] = g_after / 2
staff["grip"] = ((GRIP[0] - (GRIP[0] + GRIP[1]) / 2) * L, (GRIP[1] - (GRIP[0] + GRIP[1]) / 2) * L)
col = bpy.data.collections.new("Props")
sc.collection.children.link(col)
for c in staff.users_collection:
    c.objects.unlink(staff)
col.objects.link(staff)
staff.location = (1.15, 0.0, -P[:, 2].min())

# --- Body paint -------------------------------------------------------------
# The markings on his skin, painted over Tripo's base colour for his body as Tripo made it.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from paint_goblin_shaman import paint_body

paint_body(body, next((unzip / "body").rglob("*_basecolor.jpg")), tex_dir / "goblin_shaman_body_basecolor.jpg")

# --- Mask -------------------------------------------------------------------
if MASK == "beak":
    from beak_mask import build_mask
    from paint_beak_mask import paint_mask

    mask = build_mask(body)
    paint_mask(mask, tex_dir / "goblin_shaman_beak_mask_basecolor.jpg")
else:
    # The horned plate.
    with bpy.data.libraries.load(str(plate_blend), link=False) as (src, dst):
        dst.objects = ["MaskPlate"]
    mask = dst.objects[0]
    col.objects.link(mask)
    for img in bpy.data.images:
        if img.name.startswith("goblin_shaman_mask_basecolor"):
            img.filepath = str(mask_tex)
            img.reload()
    Q = verts(mask)
    q_tree = tree_of(Q, mask)
    # Its eye sockets: the pits in the front face between the cheekbones and the brow, read
    # on a 1 cm grid (in the plate's units) as how far each point lies behind the most
    # forward point within 0.08 of it along its row, so the sides of the face, which slope
    # back beyond the sockets' rims, do not count.
    FX = np.arange(0.0, 0.42, 0.01)
    rows = []
    for z in np.arange(0.30, 0.66, 0.01):
        ys = []
        for x in FX:
            hit = q_tree.ray_cast(Vector((x, -5.0, z)), Vector((0, 1, 0)), 10.0)[0]
            ys.append(hit.y if hit is not None else np.nan)
        ys = np.array(ys)
        for i, x in enumerate(FX):
            near_ = ys[np.abs(FX - x) <= 0.08]
            if np.isfinite(ys[i]) and np.isfinite(near_).sum() > 8:
                rows.append((x, z, ys[i] - np.nanmin(near_)))
    rows = np.array(rows)
    pit = rows[:, 2] > 0.04
    sock = np.array([np.average(rows[pit, 0], weights=rows[pit, 2]), np.average(rows[pit, 1], weights=rows[pit, 2])])
    # His eyes: the two small parts in front of the face under the brow.
    eyes = [V[p] for p in parts if 1.25 < V[p][:, 2].mean() < H - 0.08 and V[p][:, 1].mean() < -0.15
            and np.ptp(V[p][:, 0]) < 0.08 and len(p) < 100 and V[p][:, 2].min() > 1.28]
    assert len(eyes) == 2, f"{len(eyes)} eyes found"
    eye_c = np.mean([e.mean(0) for e in eyes], 0)
    eye_x = float(np.mean([abs(e.mean(0)[0]) for e in eyes]))
    # Scale and lift the plate so its sockets are level with his eyes, on his mirror plane.
    S = MASK_SCALE
    Q = (Q - (0.0, 0.0, sock[1])) * S + (0.0, 0.0, eye_c[2])
    # Fit it to his face. Its back edge (the cut) should rest on his cheeks and brow, but his
    # snout and brow stand further forward than the plate is hollow, so:
    # 1. The plate is moved back and bent round his head, each point straight back (which
    #    keeps the front view) by a + b x^2 + c dz + d dz^2, dz from the sockets' level: the
    #    bend, at most MASK_BEND between its least and most moved points, that brings its back
    #    edge closest to his face, with a tenth of the edge (the tightest) on it.
    # 2. The bend cannot follow his temples and brow exactly, so its back edge is then closed
    #    onto his face: each edge point moved to MASK_GAP off the nearest point of his face,
    #    the plate near it following by its distance from the edge, fading out over RIM_FADE.
    # 3. What of his face is then less than MASK_GAP behind the plate's inside is pushed back
    #    behind it: on a 2 mm grid, straight back, each column of his face within TUCK_DEPTH
    #    of its front as one (so nothing folds), fading out over TUCK_FADE round the plate
    #    and over the next 4 cm of depth. It is all hidden under the plate.
    b_tree = tree_of(V, body)
    cut_y = Q[:, 1].max()
    rim_idx = np.nonzero(Q[:, 1] > cut_y - 0.002)[0]
    rim_room = []
    for q in Q[rim_idx]:
        face = b_tree.ray_cast(Vector((q[0], -2.0, q[2])), Vector((0, 1, 0)), 4.0)[0]
        if face is not None:
            rim_room.append((q[0] ** 2, q[2] - eye_c[2], face.y - MASK_GAP - q[1]))
    rim_room = np.array(rim_room)
    qx2, qdz = Q[:, 0] ** 2, Q[:, 2] - eye_c[2]
    best = (-1.0, 0.0, 0.0, 0.0, 0.0)
    for b in np.linspace(0.0, 8.0, 33) if MASK_BEND > 0 else [0.0]:
        for c in np.linspace(-0.5, 0.5, 41) if MASK_BEND > 0 else [0.0]:
            for d in np.linspace(-3.0, 4.0, 29) if MASK_BEND > 0 else [0.0]:
                if np.ptp(b * qx2 + c * qdz + d * qdz ** 2) > MASK_BEND + 1e-9:
                    continue
                fr = b * rim_room[:, 0] + c * rim_room[:, 1] + d * rim_room[:, 1] ** 2
                a = float(np.percentile(rim_room[:, 2] - fr, 10))
                score = float(np.mean(np.minimum(a + fr, rim_room[:, 2])))
                if score > best[0]:
                    best = (score, a, b, c, d)
    _, shift, bend_b, bend_c, bend_d = best
    bend = shift + bend_b * qx2 + bend_c * qdz + bend_d * qdz ** 2
    Q[:, 1] += bend
    snap = []
    for i in rim_idx:
        loc, nrm, _, _ = b_tree.find_nearest(Vector(Q[i]), 0.1)
        if loc is not None:
            snap.append((*Q[i], *(loc + nrm * MASK_GAP - Vector(Q[i]))))
    snap = np.array(snap)
    d_rim = np.linalg.norm(Q[:, None, :] - Q[None, rim_idx, :], axis=2).min(1)
    d_snap = np.linalg.norm(Q[:, None, :] - snap[None, :, :3], axis=2)
    w_snap = np.exp(-(d_snap / 0.01) ** 2) + 1e-12
    t = np.clip(1 - d_rim / RIM_FADE, 0, 1)
    closing = (w_snap[:, :, None] * snap[None, :, 3:]).sum(1) / w_snap.sum(1)[:, None] * (t * t * (3 - 2 * t))[:, None]
    Q += closing
    set_verts(mask, Q)
    q_tree = tree_of(Q, mask)
    GX = np.arange(Q[:, 0].min() - TUCK_FADE, Q[:, 0].max() + TUCK_FADE + 1e-9, 0.002)
    GZ = np.arange(Q[:, 2].min() - TUCK_FADE, Q[:, 2].max() + TUCK_FADE + 1e-9, 0.002)
    push = np.zeros((len(GZ), len(GX)))
    front = np.full(push.shape, np.nan)
    covered = np.zeros(push.shape, bool)
    for i, z in enumerate(GZ):
        for j, x in enumerate(GX):
            face = b_tree.ray_cast(Vector((x, -2.0, z)), Vector((0, 1, 0)), 4.0)[0]
            back = q_tree.ray_cast(Vector((x, 2.0, z)), Vector((0, -1, 0)), 4.0)[0]
            covered[i, j] = back is not None
            if face is not None:
                front[i, j] = face.y
                if back is not None:
                    push[i, j] = max(0.0, back.y + MASK_GAP - face.y)
    # Beyond the plate (round it and between its teeth) the push fades out, smoothly, over
    # TUCK_FADE from the nearest pushed point.
    n, m = push.shape
    r = int(round(TUCK_FADE / 0.002))
    fade = push.copy()
    for di in range(-r, r + 1):
        for dj in range(-r, r + 1):
            t = math.hypot(di, dj) / r
            if 0 < t <= 1:
                moved = np.zeros_like(push)
                moved[max(0, di):n + min(0, di), max(0, dj):m + min(0, dj)] =                 push[max(0, -di):n - max(0, di), max(0, -dj):m - max(0, dj)]
                fade = np.maximum(fade, moved * (1 - t) ** 2 * (1 + 2 * t))
    push = np.where(covered, push, fade)
    gi = np.clip(np.round((V[:, 2] - GZ[0]) / 0.002).astype(int), 0, n - 1)
    gj = np.clip(np.round((V[:, 0] - GX[0]) / 0.002).astype(int), 0, m - 1)
    inside = (V[:, 2] >= GZ[0]) & (V[:, 2] <= GZ[-1]) & (V[:, 0] >= GX[0]) & (V[:, 0] <= GX[-1])
    depth = V[:, 1] - front[gi, gj]
    w = np.where(inside & np.isfinite(depth), np.clip((TUCK_DEPTH + 0.04 - np.nan_to_num(depth, nan=1.0)) / 0.04, 0, 1), 0)
    tuck = push[gi, gj] * w
    V[:, 1] += tuck
    # 4. The tuck moves his face straight back, so it misses where the plate runs front to back
    #    past him: its sides at his temples and the inside of its teeth at the corners of his
    #    mouth. Whatever of his head lies under the plate's inside (a ray from 3 cm inside his
    #    head out through the vertex meets it) and less than MASK_GAP off it is pushed in along
    #    the inside's normal to MASK_GAP off it, his face round it following over CLEAR_FADE; a
    #    small part (a tusk) moves as one. Repeated until nothing comes closer. The bend leaves
    #    the plate's quads out of flat, so each is measured split both ways.
    FN = np.array([np.cross(Q[f[1]] - Q[f[0]], Q[f[2]] - Q[f[0]]) for f in (list(p.vertices) for p in mask.data.polygons)])
    FC = np.array([Q[list(p.vertices)].mean(0) for p in mask.data.polygons])
    head_y = float(np.median(V[V[:, 2] > eye_c[2] - 0.15][:, 1]))
    inner = (FN[:, 0] * -FC[:, 0] + FN[:, 1] * (head_y - FC[:, 1])) > 0
    q_tris, q_face = split_both(mask)
    in_tree = BVHTree.FromPolygons([Vector(q) for q in Q], [t for t, f in zip(q_tris, q_face) if inner[f]])
    part_of = np.zeros(len(V), int)
    for n_, p in enumerate(parts):
        part_of[p] = n_
    small = np.array([len(p) < 100 for p in parts])
    cleared = np.zeros(len(V))
    passes = 0
    for _ in range(8):
        move = {}
        for i in np.nonzero(np.linalg.norm(V - Q.mean(0), axis=1) < np.ptp(Q, 0).max())[0]:
            p = Vector(V[i])
            loc, nrm, _, _ = in_tree.find_nearest(p, 0.03)
            if loc is None:
                continue
            hit, hn, _, _ = in_tree.ray_cast(p + nrm * 0.03, -nrm, 0.06)
            if hit is None:
                continue
            off_in = (p - hit).dot(hn)
            if off_in < MASK_GAP - 1e-5:
                move[i] = np.array(hn[:]) * (MASK_GAP - off_in)
        if not move:
            break
        D = np.zeros_like(V)
        idx = np.array(list(move))
        vec = np.array([move[i] for i in idx])
        for i, d in zip(idx, vec):
            if small[part_of[i]]:
                continue
            same = np.nonzero(part_of == part_of[i])[0]
            t = np.linalg.norm(V[same] - V[i], axis=1) / CLEAR_FADE
            w = np.where(t < 1, (1 - t) ** 2 * (1 + 2 * t), 0.0)
            bigger = w * np.linalg.norm(d) > np.linalg.norm(D[same], axis=1)
            D[same[bigger]] = d * w[bigger, None]
        for n_ in {part_of[i] for i in idx if small[part_of[i]]}:
            own = [k for k, i in enumerate(idx) if part_of[i] == n_]
            D[parts[n_]] = vec[own][np.argmax(np.linalg.norm(vec[own], axis=1))]
        V += D
        cleared += np.linalg.norm(D, axis=1)
        passes += 1
    set_verts(body, V)
    b_tree = tree_of(V, body)
    b_tris, _ = split_both(body)
    cuts = len({q_face[a] for a, _ in BVHTree.FromPolygons([Vector(q) for q in Q], q_tris).overlap(
        BVHTree.FromPolygons([Vector(v) for v in V], b_tris))})
    near = np.array([b_tree.find_nearest(Vector(q), 0.1)[3] or 0.1 for q in Q])
    # How far the plate's back edge (the cut) stands off his face, round its rim.
    off = np.array([b_tree.find_nearest(Vector(q), 0.3)[3] or 0.3 for q in Q[rim_idx]])
    mask["scale"] = S
    mask["gap"] = MASK_GAP
    mask["bend"] = (shift, bend_b, bend_c, bend_d)
    mask["rim_fade"] = RIM_FADE
    print("SHAMAN_MASK sockets at x +-%.3f z %.3f (plate units) on his eyes at x +-%.3f z %.3f; scale %.3f: "
          "%.3f m tall, %.3f wide, %.3f deep; moved %.3f back, bent b %.2f c %.2f d %.2f (%.1f to %.1f mm more); "
          "edge moved up to %.1f mm (%.1f across); his face pushed back up to %.1f mm (%d vertices more than 1 mm), then in up to %.1f mm (%d vertices more than 1 mm, %d passes); nearest the body %.1f mm, %d mask faces "
          "through it; back edge %.1f to %.1f mm off the face (median %.1f, 90%% within %.1f); fangs to z %.3f, horns to z %.3f" % (
              sock[0], sock[1], eye_x, eye_c[2], S, np.ptp(Q[:, 2]), np.ptp(Q[:, 0]), np.ptp(Q[:, 1]), shift,
              bend_b, bend_c, bend_d, (bend - shift).min() * 1000, (bend - shift).max() * 1000,
              np.linalg.norm(snap[:, 3:], axis=1).max() * 1000, np.abs(closing[:, 0]).max() * 1000, tuck.max() * 1000, int((tuck > 0.001).sum()), cleared.max() * 1000, int((cleared > 0.001).sum()), passes, near.min() * 1000, cuts, off.min() * 1000,
              off.max() * 1000, np.median(off) * 1000, np.percentile(off, 90) * 1000, Q[:, 2].min(), Q[:, 2].max()))
    print("SHAMAN_MASK_SOCKET_SPACING plate %.3f m against his eyes %.3f m" % (2 * sock[0] * S, 2 * eye_x))

# Each image's path is a fixed-size buffer too: fill it, then write the path relative
# to the .blend (the textures are next to it), so neither the unzip folder nor the
# absolute path stays behind it.
for img in bpy.data.images:
    if img.filepath_raw:
        rel = "//" + Path(bpy.path.abspath(img.filepath_raw)).resolve().relative_to(out_blend.parent).as_posix()
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
print("SHAMAN_SAVED", out_blend)
