"""Map the body texture's texels on the scarred side of the face to the scar bust: one of his
squad's faces.

  blender -b orc_brute_rig.blend --python scar_uvmap.py -- <scar_ratio.npz> <out.npz> [tex_px]

The ratio file is scar_texture.py's (`ratio`); its affine takes bust pixels to the head's
front view (x, z in metres). For every texel of a front-facing triangle whose front view
falls on the scar, this stores the texel (column, row from the top), the bust pixel the
front view shows there, how squarely the surface faces the front, and whether the front view
reaches it (nothing nearer, such as the brow over the eye socket). scar_texture.py (`paint`)
then paints from it."""
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
T = int(argv[2]) if len(argv) > 2 else 4096
S = np.load(SRC)
M = S["affine"]                     # bust (X, Y, 1) -> world (x, z)
X0, Y0 = S["origin"]
ys, xs = np.nonzero(S["mask"].astype(np.float32) > 0.01)
Minv = np.linalg.inv(M[:2])


def to_bust(x, z):
    return (np.stack([x, z], -1) - M[2]) @ Minv


corners = np.array([[xs.min() + X0, ys.min() + Y0, 1], [xs.max() + X0, ys.max() + Y0, 1]], float) @ M
XL, XH = sorted(corners[:, 0])
ZL, ZH = sorted(corners[:, 1])
XL, XH, ZL, ZH = XL - 0.004, XH + 0.004, ZL - 0.004, ZH + 0.004
print("WORLD box x %.4f..%.4f z %.4f..%.4f" % (XL, XH, ZL, ZH))

body = bpy.data.objects["OrcBrute"]
bpy.data.objects["OrcBruteRig"].data.pose_position = "REST"
bpy.context.view_layer.update()
me = body.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
mw = body.matrix_world
co = np.array([(mw @ v.co)[:] for v in me.vertices])
tree = BVHTree.FromPolygons([Vector(c) for c in co], [p.vertices[:] for p in me.polygons])
uvl = me.uv_layers.active.data
me.calc_loop_triangles()
print("UV", me.uv_layers.active.name, "tris", len(me.loop_triangles))

cols, rows, bx, by, face, seen, inner = [], [], [], [], [], [], []
for lt in me.loop_triangles:
    P = co[list(lt.vertices)]
    if P[:, 0].max() < XL or P[:, 0].min() > XH or P[:, 2].max() < ZL or P[:, 2].min() > ZH:
        continue
    n = np.cross(P[1] - P[0], P[2] - P[0])
    n /= max(np.linalg.norm(n), 1e-12)
    if n[1] > -0.05:             # faces away from the front
        continue
    UV = np.array([uvl[li].uv[:] for li in lt.loops])
    px = np.stack([UV[:, 0] * T - 0.5, (1 - UV[:, 1]) * T - 0.5], 1)
    c0, c1 = int(np.floor(px[:, 0].min())) - 1, int(np.ceil(px[:, 0].max())) + 1
    r0, r1 = int(np.floor(px[:, 1].min())) - 1, int(np.ceil(px[:, 1].max())) + 1
    gc, gr = np.meshgrid(np.arange(c0, c1 + 1), np.arange(r0, r1 + 1))
    q = np.stack([gc.ravel(), gr.ravel()], 1).astype(float)
    a, b, c = px
    den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
    if abs(den) < 1e-9:
        continue
    l1 = ((b[1] - c[1]) * (q[:, 0] - c[0]) + (c[0] - b[0]) * (q[:, 1] - c[1])) / den
    l2 = ((c[1] - a[1]) * (q[:, 0] - c[0]) + (a[0] - c[0]) * (q[:, 1] - c[1])) / den
    L = np.stack([l1, l2, 1 - l1 - l2], 1)
    # A margin of 1.5 texels round the triangle, so seams get no unpainted rim.
    edge = 1.5 / max(np.sqrt(abs(den)), 1e-6)
    ok = (L > -edge).all(1)
    if not ok.any():
        continue
    L = np.clip(L[ok], 0, None)
    L /= L.sum(1, keepdims=True)
    W = L @ P
    B = to_bust(W[:, 0], W[:, 2])
    cols.append(q[ok, 0].astype(int))
    rows.append(q[ok, 1].astype(int))
    bx.append(B[:, 0])
    by.append(B[:, 1])
    face.append(np.full(ok.sum(), -n[1]))
    inner.append(L.min(1))
    vis = np.empty(ok.sum(), bool)
    for k, w in enumerate(W):
        vis[k] = tree.ray_cast(Vector(w) + Vector((0, -0.0015, 0)), Vector((0, -1, 0)))[0] is None
    seen.append(vis)
cols, rows = np.concatenate(cols), np.concatenate(rows)
bx, by = np.concatenate(bx), np.concatenate(by)
face, seen, inner = np.concatenate(face), np.concatenate(seen), np.concatenate(inner)
# One entry per texel: the triangle it lies deepest inside.
order = np.lexsort((-inner, rows, cols))
key = cols[order] * T + rows[order]
pick = order[np.r_[True, key[1:] != key[:-1]]]
print("TEXELS", len(pick), "visible", int(seen[pick].sum()),
      "cols %d..%d rows %d..%d" % (cols.min(), cols.max(), rows.min(), rows.max()))
np.savez(OUT, col=cols[pick], row=rows[pick], bx=bx[pick], by=by[pick], face=face[pick], seen=seen[pick])
