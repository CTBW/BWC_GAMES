"""Battlefield works for the horde battles: walls, gates, stakes and farm clutter.

Same rig and conventions as meridius_rig.py: game (x, y) is Blender (X, -Y),
one tile is one metre, light from the screen's upper left. Every builder makes
one tile's worth of geometry centred on the origin. Axis 'x' runs along game x;
axis 'y' along game y. The inside of a wall (where gates open) is game +y for an
x-wall and game +x for a y-wall, as in the hand-drawn last-stand layouts.

Usage inside Blender:
    import sys, importlib; sys.path.insert(0, r'<this folder>')
    import meridius_rig as R, meridius_build as B, meridius_horde as Hd
    R.setup_scene(samples=64); R.clear_assets()
    R.render_asset(Hd.make(Hd.wall_segment('x', 1), 'wall_x'), 'bwall_x', 0)
"""
import math
import random

import bmesh
from mathutils import Matrix, Vector

import meridius_build as B
import meridius_rig as R


def make(parts, name):
    return R.join(parts, name)


def _along(axis, t, off=0.0):
    """A point t metres along the wall axis, `off` metres toward the inside."""
    return (t, -off, 0.0) if axis == 'x' else (off, -t, 0.0)


def _log(p0, p1, r, M, name, mat='wood'):
    return R._cyl(p0, p1, r, r * 0.92, M[mat], name, segs=7, smooth=False)


def _point(x, y, z, r, M, name):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=7, radius1=r, radius2=0.0, depth=r * 2.6)
    bmesh.ops.translate(bm, vec=Vector((x, y, z + r * 1.3)), verts=bm.verts)
    return R._obj_from_bm(bm, name, M['wood'], smooth=False)


def wall_segment(axis, seed=0):
    """A full tile of tall sharpened-log palisade with a walkway rail behind."""
    rng = random.Random(seed)
    M = B.bmats()
    parts = []
    n = 6
    for k in range(n):
        t = -0.5 + (k + 0.5) / n
        x, y, _ = _along(axis, t)
        hh = rng.uniform(1.45, 1.7)
        parts.append(_log((x, y, 0), (x + rng.uniform(-0.02, 0.02), y + rng.uniform(-0.02, 0.02), hh), 0.088, M, f'w{k}'))
        parts.append(_point(x, y, hh, 0.085, M, f'wt{k}'))
    for z in (0.35, 1.05):
        a = _along(axis, -0.5, 0.09)
        b = _along(axis, 0.5, 0.09)
        parts.append(_log((a[0], a[1], z), (b[0], b[1], z + rng.uniform(-0.03, 0.03)), 0.034, M, f'r{z}', 'timber'))
    # A skull or a shield nailed to some segments, from earlier fights.
    if rng.random() < 0.35:
        p = _along(axis, rng.uniform(-0.3, 0.3), -0.1)
        parts.append(R._blob(rng, (p[0], p[1], 1.15), 0.07, M['bone'], 'skull', squash=1.0, subdiv=1, rough=0.05))
    return parts


def gate(axis, seed=0):
    """An open gateway: two heavy posts, a lintel, and the gate leaves swung inward."""
    rng = random.Random(seed)
    M = B.bmats()
    parts = []
    for side in (-1, 1):
        x, y, _ = _along(axis, side * 0.47)
        parts.append(_log((x, y, 0), (x, y, 2.05), 0.12, M, f'post{side}', 'timber'))
        parts.append(_point(x, y, 2.05, 0.12, M, f'pt{side}'))
        # Leaf: hinged on the post, swung about 80 degrees toward the inside.
        ang = math.radians(78)
        leaf_len = 0.44
        hx, hy = x, y
        if axis == 'x':
            ex, ey = hx - side * leaf_len * math.cos(ang), hy - leaf_len * math.sin(ang)
        else:
            ex, ey = hx + leaf_len * math.sin(ang), hy + side * leaf_len * math.cos(ang)
        for k in range(3):
            f = (k + 0.5) / 3
            px, py = hx + (ex - hx) * f, hy + (ey - hy) * f
            parts.append(_log((px, py, 0.05), (px, py, 1.45 + rng.uniform(-0.04, 0.04)), 0.07, M, f'leaf{side}{k}'))
        parts.append(_log((hx, hy, 0.4), (ex, ey, 0.4), 0.03, M, f'lb{side}', 'iron'))
        parts.append(_log((hx, hy, 1.1), (ex, ey, 1.1), 0.03, M, f'lt{side}', 'iron'))
    a = _along(axis, -0.6)
    b = _along(axis, 0.6)
    parts.append(_log((a[0], a[1], 1.95), (b[0], b[1], 1.95), 0.08, M, 'lintel', 'timber'))
    # A small blue pennant over the gate: this is the company's ground.
    m = _along(axis, 0.0)
    parts += B.banner(m[0], m[1], 2.55, 'blue', 'gban')
    return parts


def stakes(axis, seed=0):
    """Sharpened stakes driven in crosswise: a line no squad can walk through."""
    rng = random.Random(seed)
    M = B.bmats()
    parts = []
    a = _along(axis, -0.5)
    b = _along(axis, 0.5)
    parts.append(_log((a[0], a[1], 0.32), (b[0], b[1], 0.32), 0.07, M, 'beam', 'timber'))
    for k in range(5):
        t = -0.42 + k * 0.21
        c = _along(axis, t)
        for s in (-1, 1):
            lean = 0.55 * s
            tip = _along(axis, t + rng.uniform(-0.04, 0.04), lean)
            parts.append(_log((c[0], c[1], 0.0), (tip[0], tip[1], 0.95 + rng.uniform(-0.08, 0.08)), 0.04, M, f's{k}{s}'))
    return parts


def cart(seed=0):
    """A farm cart tipped on its side as a barricade, a wheel in the air."""
    rng = random.Random(seed)
    M = B.bmats()
    parts = B.wagon('cart', covered=False)
    ob = make(parts, 'cart_raw')
    ob.rotation_euler = (math.radians(84), 0, math.radians(rng.uniform(20, 40)))
    ob.location = (0, 0, 0.42)
    ob.scale = (0.72, 0.72, 0.72)
    return [ob]


def haystack(seed=0):
    rng = random.Random(seed)
    M = B.bmats()
    parts = [R._blob(rng, (0, 0, 0.36), 0.5, M['hay'], 'stack', squash=1.1, subdiv=3, rough=0.12)]
    parts.append(R._blob(rng, (0.05, -0.02, 0.86), 0.24, M['straw'], 'top', squash=0.9, subdiv=2, rough=0.18))
    parts.append(_log((0.0, 0.0, 0.6), (0.06, -0.04, 1.35), 0.025, M, 'pole'))
    for k in range(6):
        ang = rng.uniform(0, math.tau)
        r = rng.uniform(0.45, 0.62)
        parts.append(R._box((math.cos(ang) * r, math.sin(ang) * r, 0.02), (0.18, 0.04, 0.02), M['straw'], f'tuft{k}', rot_z=rng.uniform(0, 3)))
    return parts


def well(seed=0):
    rng = random.Random(seed)
    M = B.bmats()
    parts = []
    n = 10
    for k in range(n):
        a = k * math.tau / n
        parts.append(R._blob(rng, (math.cos(a) * 0.36, math.sin(a) * 0.36, 0.18), 0.13, M['stone2'], f'st{k}', squash=1.2, subdiv=1, rough=0.12))
        parts.append(R._blob(rng, (math.cos(a + 0.3) * 0.36, math.sin(a + 0.3) * 0.36, 0.42), 0.12, M['stone2'], f'su{k}', squash=1.0, subdiv=1, rough=0.12))
    for s in (-1, 1):
        parts.append(_log((s * 0.4, 0, 0.2), (s * 0.4, 0, 1.25), 0.045, M, f'up{s}', 'timber'))
    parts.append(_log((-0.48, 0, 1.18), (0.48, 0, 1.18), 0.04, M, 'axle'))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=4, radius1=0.62, radius2=0.0, depth=0.42)
    bmesh.ops.rotate(bm, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.pi / 4, 3, 'Z'), verts=bm.verts)
    bmesh.ops.scale(bm, vec=Vector((1.0, 0.75, 1.0)), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector((0, 0, 1.45)), verts=bm.verts)
    parts.append(R._obj_from_bm(bm, 'roof', M['roof_thatch'], smooth=False))
    parts.append(R._cyl((0.1, 0.1, 0.62), (0.1, 0.1, 0.84), 0.09, 0.1, M['wood'], 'bucket', segs=10))
    return parts


def steading_landmark():
    """Brannsted on the campaign map: a palisaded farm on a rise, gate tower and blue banners."""
    M = B.bmats()
    P = []
    # Palisade round three sides, the gate gap facing the road.
    P += B.palisade([(-1.6, 1.4), (-1.6, -1.4), (1.6, -1.4)], 'sp1', h=1.1, seed=7)
    P += B.palisade([(1.6, -1.4), (1.6, 0.3)], 'sp2', h=1.1, seed=8)
    P += B.palisade([(1.6, 1.0), (1.6, 1.4), (-1.6, 1.4)], 'sp3', h=1.1, seed=9)
    P += [B._move(o, (-0.5, -0.4, 0)) for o in B.house(1.3, 0.9, 0.85, 0.7, 'plaster', 'roof_thatch', windows=1, seed=31, name='sh1')]
    P += [B._move(o, (0.6, 0.5, 0)) for o in B.house(1.0, 0.8, 0.75, 0.6, 'plaster', 'roof_red', windows=1, seed=32, name='sh2', door_side='+x')]
    P += [B._move(o, (-1.6, -1.4, 0)) for o in B.gate_tower()]
    P += B.banner(1.7, 0.45, 1.9, 'blue', 'sb1')
    P += B.banner(1.7, 0.95, 1.9, 'blue', 'sb2')
    P += B.hay(-0.6, 0.8, 'shay')
    return P


def war_banner(seed=0):
    """The horde's standard: a tall pole hung with skulls and red rags."""
    rng = random.Random(seed)
    M = B.bmats()
    parts = [_log((0, 0, 0), (0.05, 0, 2.8), 0.05, M, 'pole')]
    parts.append(_log((-0.45, 0, 2.45), (0.45, 0, 2.5), 0.03, M, 'bar'))
    parts.append(R._blob(rng, (0.05, 0, 2.9), 0.15, M['bone'], 'skull', squash=1.0, subdiv=2, rough=0.05))
    for k, x in enumerate((-0.38, 0.0, 0.38)):
        parts.append(R._box((x, 0.02, 2.0), (0.22, 0.03, 0.8 + rng.uniform(-0.15, 0.15)), M['red'], f'rag{k}'))
    for k in range(3):
        parts.append(R._blob(rng, (rng.uniform(-0.3, 0.3), 0.0, 2.35 - k * 0.12), 0.06, M['bone'], f'sk{k}', subdiv=1, rough=0.05))
    return parts
