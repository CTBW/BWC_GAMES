"""Paint the goblin shaman's beak mask: bone, red cloth and barred feathers (background Blender).

  blender -b goblin_shaman_beak_base.blend --factory-startup --python paint_beak_mask.py -- [<out.jpg>]

build_goblin_shaman.py paints the mask this way after beak_mask.build_mask. Run alone, it
paints the base scene's mask again, into `textures/goblin_shaman_beak_mask_basecolor.jpg`
(or <out.jpg>); nothing in it is random but seeded, so the texture comes out the same
but for a level on a few texels (Cycles' bake).
1. Cycles bakes the mask's own ambient occlusion into its UVs (AO_DIST), at half size.
2. The skull (beak_mask.SKULL_UV): each texel gets the point it shows. Bone, mottled and
   grained, stained brown in patches and in its creases (from the occlusion), dark in its
   hollows (the openings and nostrils, Skull.carves), dark grey in its eye sockets and the
   holes through them (Skull.eyes), cracked as the reference is (CRACKS, drawn as seen from
   the front).
3. The band (BAND_UV): red cloth, woven, darker along its edges and inside, creased.
4. The feathers (FEATHER_UV): three patterns, cream at the root, brown with cream bars
   above, dark at the tip, a pale shaft and fine barbs.
The mask takes one material, MATERIAL, with this texture linked by relative path.
"""
import sys
import time
from pathlib import Path

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from beak_mask import (BAND_UV, BAND_W, FEATHER_L, FEATHER_UV, FEATHER_W, QUILL, SKULL_UV, Skull,  # noqa: E402
                       band_profile, feather_hw)
from paint_goblin_shaman import fbm, noise, smooth  # noqa: E402

SIZE = 2048
MATERIAL = "GoblinShamanBeakMask"
AO_DIST = 0.03
# Colours (sRGB).
BONE = np.array([[0.95, 0.91, 0.80], [0.84, 0.77, 0.62]])
STAIN = np.array([0.56, 0.45, 0.31])
PIT = np.array([[0.36, 0.27, 0.19], [0.07, 0.05, 0.04]])
EYE = np.array([[0.30, 0.30, 0.31], [0.16, 0.16, 0.17]])
CRACK = np.array([0.30, 0.21, 0.14])
CLOTH = np.array([[0.70, 0.15, 0.10], [0.40, 0.06, 0.05]])
CREAM, TAN = np.array([0.96, 0.93, 0.85]), np.array([0.74, 0.58, 0.40])
BROWN, DARK = np.array([0.46, 0.30, 0.17]), np.array([0.20, 0.12, 0.07])
SHAFT = np.array([0.93, 0.89, 0.79])
# The three feather patterns: root colour, upper colour, bars' colour, where the upper
# begins (of the length), bars over the upper part.
PATTERNS = ((CREAM, BROWN, CREAM, 0.42, 4.5),
            (TAN, DARK, TAN, 0.30, 5.5),
            (CREAM, TAN, BROWN, 0.55, 3.5))
# Cracks as seen from the front: start (x, z from his eyes), heading (deg from straight
# down toward +x), length (m); each wanders and branches (seeded).
CRACKS = (((-0.010, 0.088), -5.0, 0.060), ((-0.060, 0.086), 20.0, 0.032), ((0.045, 0.088), 12.0, 0.036),
          ((0.114, 0.022), 30.0, 0.036), ((-0.118, 0.012), -25.0, 0.030), ((0.090, -0.040), 20.0, 0.026),
          ((-0.025, -0.020), -15.0, 0.035), ((0.012, -0.055), 5.0, 0.045))
SEED = 11


def lerp(a, b, t):
    return a + (b - a) * np.asarray(t)[..., None]


def texels(me, size, box):
    """(texel index, point, normal) of every texel a UV triangle within `box` covers."""
    me.calc_loop_triangles()
    n = len(me.loop_triangles)
    loops = np.empty(n * 3, np.int32)
    me.loop_triangles.foreach_get("loops", loops)
    tv = np.empty(n * 3, np.int32)
    me.loop_triangles.foreach_get("vertices", tv)
    tv = tv.reshape(n, 3)
    uv = np.empty(len(me.loops) * 2, np.float32)
    me.uv_layers.active.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)[loops].reshape(n, 3, 2)
    (b0, c0), (b1, c1) = box
    inside = ((uv[..., 0] >= b0) & (uv[..., 0] <= b1) & (uv[..., 1] >= c0) & (uv[..., 1] <= c1)).all(1)
    uv = uv * size - 0.5
    co = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    vn = np.empty(len(me.vertices) * 3, np.float32)
    me.vertex_normals.foreach_get("vector", vn)
    vn = vn.reshape(-1, 3)
    idx, pos, nrm = [], [], []
    for k in np.nonzero(inside)[0]:
        p = uv[k]
        x0, y0 = np.maximum(np.floor(p.min(0)).astype(int), 0)
        x1, y1 = np.minimum(np.ceil(p.max(0)).astype(int), size - 1)
        a, b, c = p
        d = (b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1])
        if x1 < x0 or y1 < y0 or abs(d) < 1e-9:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        w1 = ((xs - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (ys - a[1])) / d
        w2 = ((b[0] - a[0]) * (ys - a[1]) - (xs - a[0]) * (b[1] - a[1])) / d
        w0 = 1 - w1 - w2
        m = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if m.any():
            w = np.stack([w0[m], w1[m], w2[m]], 1)
            idx.append(ys[m] * size + xs[m])
            pos.append(w @ co[tv[k]])
            nrm.append(w @ vn[tv[k]])
    nrm = np.concatenate(nrm)
    return np.concatenate(idx), np.concatenate(pos), nrm / np.linalg.norm(nrm, axis=1)[:, None]


def bake_ao(ob, size):
    """The mask's own ambient occlusion in its UVs, `size` square (1 open, 0 shut)."""
    sc = bpy.context.scene
    engine = sc.render.engine
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 48
    if sc.world is None:
        sc.world = bpy.data.worlds.new("Bake")
    sc.world.light_settings.distance = AO_DIST
    img = bpy.data.images.new("MaskAO", size, size, float_buffer=True)
    added = []
    for m in ob.data.materials:
        node = m.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = img
        m.node_tree.nodes.active = node
        added.append((m, node))
    hidden = [o for o in bpy.data.objects if o is not ob and not o.hide_render]
    for o in hidden:
        o.hide_render = True
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    sc.render.bake.target = "IMAGE_TEXTURES"
    bpy.ops.object.bake(type="AO", margin=6, use_clear=True)
    for o in hidden:
        o.hide_render = False
    for m, node in added:
        m.node_tree.nodes.remove(node)
    sc.render.engine = engine
    px = np.empty(size * size * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(size, size, 4)[..., 0]


def crack_segments(rng):
    """[(a, b, width at a, width at b)] in (x, z) from his eyes."""
    segs = []

    def walk(p, heading, length, width, depth):
        step = 0.0028
        n = max(2, int(length / step))
        h = np.radians(heading)
        p = np.array(p, float)
        for k in range(n):
            h += rng.normal(0, np.radians(14))
            q = p + step * np.array((np.sin(h), -np.cos(h)))
            w0, w1 = width * (1 - 0.75 * k / n), width * (1 - 0.75 * (k + 1) / n)
            segs.append((p, q, w0, w1))
            if depth < 2 and k > 2 and rng.random() < 0.10:
                walk(q, np.degrees(h) + rng.choice((-1, 1)) * rng.uniform(30, 55), length * rng.uniform(0.25, 0.45),
                     w0 * 0.7, depth + 1)
            p = q
    for start, heading, length in CRACKS:
        walk(start, heading, length, 0.0014, 0)
    return segs


def paint_skull(sk, idx, P, N, ao):
    rel = P - sk.E
    col = lerp(BONE[0], BONE[1], smooth(fbm(rel, 0.035, 5, 3), -0.35, 0.65))
    col *= (1 + 0.05 * fbm(rel, 0.008, 7, 2) + 0.03 * noise(rel, 0.0022, 9))[:, None]
    col = lerp(col, STAIN, 0.45 * smooth(fbm(rel, 0.018, 13, 3), 0.25, 0.65))
    # Grime in its creases.
    crease = np.clip((0.9 - ao) / 0.5, 0, 1)
    col = lerp(col, STAIN * 0.75, 0.6 * crease)
    col *= (0.62 + 0.38 * ao)[:, None]
    # Its hollows dark, darker deeper in (below where the bone would be without them).
    pit = 1 - smooth(sk.carves(P), 0.0004, 0.0025)
    deep = smooth(-sk.shape(P, hollows=False), 0.001, 0.010)
    col = lerp(col, lerp(PIT[0], PIT[1], deep), 0.97 * pit)
    eye = 1 - smooth(sk.eyes(P), 0.0004, 0.0025)
    col = lerp(col, lerp(EYE[0], EYE[1], deep), 0.97 * eye)
    # Cracks on its front.
    front = smooth(-N[:, 1], 0.1, 0.4) * (1 - pit)
    xz = rel[:, [0, 2]]
    dark = np.zeros(len(P))
    for a, b, w0, w1 in crack_segments(np.random.default_rng(SEED)):
        lo, hi = np.minimum(a, b) - 0.004, np.maximum(a, b) + 0.004
        near = np.nonzero((xz[:, 0] > lo[0]) & (xz[:, 0] < hi[0]) & (xz[:, 1] > lo[1]) & (xz[:, 1] < hi[1]))[0]
        if not len(near):
            continue
        q = xz[near] - a
        ab = b - a
        t = np.clip(q @ ab / (ab @ ab), 0, 1)
        d = np.linalg.norm(q - t[:, None] * ab, axis=1)
        w = w0 + (w1 - w0) * t
        dark[near] = np.maximum(dark[near], np.maximum(1 - smooth(d, 0.35 * w, w), 0.3 * (1 - smooth(d, w, 3.5 * w))))
    col = lerp(col, CRACK, 0.9 * dark * front)
    return np.clip(col, 0, 1)


def paint_band(size):
    """The band's texels: (texel index, colour)."""
    u0, u1 = BAND_UV
    xs = np.arange(int(np.floor(u0 * size)), int(np.ceil(u1 * size)))
    X, Y = np.meshgrid(xs, np.arange(size))
    a = np.clip(((X.ravel() + 0.5) / size - u0) / (u1 - u0), 0, 1)
    prof = band_profile()
    per = np.r_[0, np.cumsum(np.linalg.norm(np.roll(prof, -1, 0) - prof, axis=1))]
    ring = np.r_[prof, prof[:1]]
    h = np.interp(a, per / per[-1], ring[:, 0])
    o = np.interp(a, per / per[-1], ring[:, 1])
    along = (Y.ravel() + 0.5) / size * 0.86
    zero = np.zeros(h.size)
    Q = np.stack([along, h, zero], 1)
    col = lerp(CLOTH[0], CLOTH[1], 0.35 + 0.35 * fbm(Q, 0.05, 21, 3))
    weave = 0.5 + 0.5 * np.sin(2 * np.pi * along / 0.0014) * np.sin(2 * np.pi * h / 0.0014)
    thread = np.sin(2 * np.pi * h / 0.0011 + 2.0 * noise(Q, 0.01, 23))
    col *= (0.93 + 0.08 * weave + 0.04 * thread)[:, None]
    # Creases across it where it bunches, a little lighter beside each.
    c = noise(np.stack([along + 0.35 * h, zero, zero], 1), 0.018, 25)
    col *= (1 - 0.22 * (1 - smooth(np.abs(c), 0.02, 0.07)) + 0.05 * smooth(c, 0.10, 0.25))[:, None]
    # Darker round its edges and inside, worn paler in patches.
    edge = np.maximum(smooth(np.abs(h), BAND_W / 2 - 0.0035, BAND_W / 2), 1 - smooth(o, 0.0015, 0.003))
    col *= (1 - 0.35 * edge)[:, None]
    col = lerp(col, np.array([0.78, 0.40, 0.30]), 0.18 * smooth(fbm(Q, 0.03, 27, 2), 0.3, 0.7))
    return (Y * size + X).ravel(), np.clip(col, 0, 1)


def paint_feathers(size):
    """The feathers' texels: (texel index, colour), FEATHER_UV's three patterns."""
    out_i, out_c = [], []
    rng = np.random.default_rng(SEED + 1)
    for (u0, u1), (root, upper, bar, split, bars) in zip(FEATHER_UV, PATTERNS):
        xs = np.arange(int(np.floor(u0 * size)), int(np.ceil(u1 * size)))
        X, Y = np.meshgrid(xs, np.arange(size))
        q = (((X + 0.5) / size - u0) / (u1 - u0) * 2 - 1).ravel()
        s = ((Y + 0.5) / size).ravel()
        w = np.maximum(feather_hw(s), 1e-3)
        across = np.abs(np.where(q < 0, q / (0.8 * w), q / w))
        y = q * FEATHER_W
        Q = np.stack([s * FEATHER_L[0], y, np.full(len(s), u0)], 1)
        # The root colour reaches higher along the shaft.
        up = smooth(s + 0.06 * fbm(Q, 0.02, 31, 2) - 0.10 * (1 - across), split - 0.05, split + 0.05)
        col = lerp(root, upper, up)
        band = np.sin(2 * np.pi * ((s - split) * bars - 0.30 * across + 0.1 * fbm(Q, 0.015, 33, 2)))
        col = lerp(col, bar, 0.85 * up * smooth(band, 0.25, 0.65))
        col = lerp(col, DARK * 0.8, smooth(s, 0.85, 0.94))
        # A down of pale fluff above the quill, darker toward the vanes' edges.
        col = lerp(col, CREAM, 0.7 * (1 - smooth(s, QUILL + 0.02, QUILL + 0.09)))
        col *= (1 - 0.25 * smooth(across, 0.7, 1.0))[:, None]
        # Fine barbs slanting from the shaft, and two splits in the vane.
        barb = np.sin(2 * np.pi * (s * FEATHER_L[0] / 0.0011 - np.abs(y) / 0.0007))
        col *= (1 + 0.07 * barb)[:, None]
        for _ in range(2):
            s0, side = rng.uniform(0.45, 0.8), rng.choice((-1, 1))
            gap = (np.sign(q) == side) & (np.abs(s - s0 - 0.12 * across) < 0.003) & (across > 0.25)
            col[gap] *= 0.55
        # The shaft, pale, thinning toward the tip; the bare quill below the vane.
        shaft = 1 - smooth(np.abs(y), 0.0006 * (1 - 0.6 * s), 0.0010 * (1 - 0.6 * s))
        col = lerp(col, SHAFT, shaft)
        col = np.where((s < QUILL)[:, None], SHAFT * 0.92, col)
        out_i.append((Y * size + X).ravel())
        out_c.append(np.clip(col, 0, 1))
    return np.concatenate(out_i), np.concatenate(out_c)


def spread(C, covered, n):
    """Each colour spread `n` texels past its island's edge."""
    for _ in range(n):
        grown = np.zeros_like(covered)
        for ax, sh in ((0, 1), (0, -1), (1, 1), (1, -1)):
            nc, ncov = np.roll(C, sh, ax), np.roll(covered, sh, ax)
            take = ~covered & ~grown & ncov
            C[take] = nc[take]
            grown |= take
        covered |= grown
    return C


def paint_mask(ob, dst, size=SIZE):
    """Paint `ob` (beak_mask.build_mask's) into `dst` and give it MATERIAL with it."""
    t0 = time.time()
    sk = Skull(np.array(ob["eyes"]))
    ao = bake_ao(ob, size // 2)
    ao = np.kron(ao, np.ones((2, 2)))
    me = ob.data
    idx, P, N = texels(me, size, SKULL_UV)
    C = np.zeros((size * size, 3), np.float32)
    covered = np.zeros(size * size, bool)
    C[idx] = paint_skull(sk, idx, P, N, ao.ravel()[idx])
    covered[idx] = True
    C = spread(C.reshape(size, size, 3), covered.reshape(size, size), 8).reshape(-1, 3)
    for i, c in (paint_band(size), paint_feathers(size)):
        C[i] = c
    img = bpy.data.images.new("mask_paint", size, size)
    full = np.ones((size * size, 4), np.float32)
    full[:, :3] = C
    img.pixels.foreach_set(full.ravel())
    img.filepath_raw = str(dst)
    img.file_format = "JPEG"
    img.save(quality=92)
    bpy.data.images.remove(img)
    # One material with the texture for the whole mask.
    mat = bpy.data.materials.get(MATERIAL) or bpy.data.materials.new(MATERIAL)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tex = next((n for n in nt.nodes if n.type == "TEX_IMAGE"), None) or nt.nodes.new("ShaderNodeTexImage")
    image = bpy.data.images.load(str(dst), check_existing=True)
    image.reload()
    tex.image = image
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.7
    old = list(me.materials)
    me.materials.clear()
    me.materials.append(mat)
    me.polygons.foreach_set("material_index", np.zeros(len(me.polygons), np.int32))
    for m in old:
        if m.users == 0:
            bpy.data.materials.remove(m)
    print("BEAK_MASK_PAINT %d skull texels; %.0f s -> %s" % (len(idx), time.time() - t0, dst))
    return image


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    blend = Path(bpy.data.filepath)
    dst = Path(argv[0]) if argv else blend.parent / "textures" / "goblin_shaman_beak_mask_basecolor.jpg"
    paint_mask(bpy.data.objects["MaskPlate"], dst)
