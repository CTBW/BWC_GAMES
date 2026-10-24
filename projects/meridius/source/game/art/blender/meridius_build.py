"""Meridius structure kit: base buildings (3 levels each), camp props and
campaign landmarks, built from simple parametric parts.

Blender axes: game +x = Blender +X, game +y = Blender -Y. The camera sees the
faces whose normals point to +X (screen lower right) and -Y (screen lower left),
so doors, windows and detail go on those faces.
"""
import math
import random

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

import meridius_rig as R
from meridius_rig import _box, _blob, _cyl, _obj_from_bm, _ramp_mat, join, mats


# ---------------------------------------------------------------- materials


def bmats():
    m = mats()
    m.update(
        {
            'timber': _ramp_mat('M_Timber', [(0.10, 0.06, 0.03), (0.20, 0.12, 0.06)], 16),
            'plaster': _ramp_mat('M_Plaster3', [(0.50, 0.44, 0.32), (0.64, 0.58, 0.45)], 5, height_dark=0.3, height_span=2.5),
            'roof_blue': _shingle('M_RoofBlue3', (0.02, 0.05, 0.22), (0.06, 0.14, 0.48)),
            'roof_red': _shingle('M_RoofRed3', (0.16, 0.025, 0.015), (0.40, 0.07, 0.035)),
            'roof_thatch': _shingle('M_Thatch3', (0.26, 0.18, 0.07), (0.52, 0.40, 0.17), bands=22),
            'roof_slate': _shingle('M_Slate3', (0.07, 0.08, 0.10), (0.20, 0.22, 0.26)),
            'stone2': _ramp_mat('M_Stone2', [(0.30, 0.29, 0.26), (0.46, 0.44, 0.39), (0.60, 0.58, 0.51)], 5, rough=0.9, moss=(0.16, 0.26, 0.06)),
            'canvas2': _ramp_mat('M_Canvas3', [(0.50, 0.44, 0.31), (0.66, 0.60, 0.46)], 7, height_dark=0.3, height_span=2.0),
            'stripe': _stripe('M_Stripe2', (0.05, 0.11, 0.42), (0.66, 0.61, 0.48)),
            'white': _ramp_mat('M_White2', [(0.62, 0.60, 0.54), (0.76, 0.74, 0.68)], 6, height_dark=0.25, height_span=2.0),
            'glow': _ramp_mat('M_Glow', [(1.0, 0.62, 0.18), (1.0, 0.85, 0.45)], 8, emission=(1.0, 0.55, 0.15)),
            'dark': _ramp_mat('M_Dark2', [(0.04, 0.03, 0.02), (0.08, 0.06, 0.04)], 6),
            'gold': _ramp_mat('M_Gold', [(0.55, 0.38, 0.08), (0.85, 0.66, 0.22)], 9, rough=0.4),
            'hay': _ramp_mat('M_Hay', [(0.62, 0.50, 0.20), (0.82, 0.70, 0.36)], 20),
            'straw': _ramp_mat('M_Straw', [(0.70, 0.58, 0.30), (0.88, 0.78, 0.48)], 25),
            'green_cloth': _ramp_mat('M_GreenCloth', [(0.12, 0.30, 0.10), (0.22, 0.45, 0.16)], 9),
        }
    )
    return m


def _shingle(name, dark, light, bands=14):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Roughness'].default_value = 0.8
    tc = nt.nodes.new('ShaderNodeTexCoord')
    wave = nt.nodes.new('ShaderNodeTexWave')
    wave.wave_type = 'BANDS'
    wave.bands_direction = 'Z'
    wave.wave_profile = 'SAW'
    wave.inputs['Scale'].default_value = bands * 0.55
    wave.inputs['Distortion'].default_value = 0.6
    nt.links.new(tc.outputs['Object'], wave.inputs['Vector'])
    noise = nt.nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = 7
    nt.links.new(tc.outputs['Object'], noise.inputs['Vector'])
    mix = nt.nodes.new('ShaderNodeMath')
    mix.operation = 'MULTIPLY'
    nt.links.new(wave.outputs['Fac'], mix.inputs[0])
    nt.links.new(noise.outputs['Fac'], mix.inputs[1])
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position = 0.05
    ramp.color_ramp.elements[0].color = (*dark, 1)
    ramp.color_ramp.elements[1].position = 0.45
    ramp.color_ramp.elements[1].color = (*light, 1)
    nt.links.new(mix.outputs[0], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], bsdf.inputs['Base Color'])
    return m


def _stripe(name, a, b):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Roughness'].default_value = 0.85
    tc = nt.nodes.new('ShaderNodeTexCoord')
    wave = nt.nodes.new('ShaderNodeTexWave')
    wave.wave_type = 'BANDS'
    wave.bands_direction = 'X'
    wave.inputs['Scale'].default_value = 1.6
    wave.wave_profile = 'SAW'
    nt.links.new(tc.outputs['Object'], wave.inputs['Vector'])
    gt = nt.nodes.new('ShaderNodeMath')
    gt.operation = 'GREATER_THAN'
    gt.inputs[1].default_value = 0.5
    nt.links.new(wave.outputs['Fac'], gt.inputs[0])
    mixc = nt.nodes.new('ShaderNodeMix')
    mixc.data_type = 'RGBA'
    nt.links.new(gt.outputs[0], mixc.inputs['Factor'])
    mixc.inputs['A'].default_value = (*a, 1)
    mixc.inputs['B'].default_value = (*b, 1)
    nt.links.new(mixc.outputs['Result'], bsdf.inputs['Base Color'])
    return m


# ---------------------------------------------------------------- parts


def boxr(center, size, mat, name, rot=(0, 0, 0), bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if bevel:
        bmesh.ops.bevel(bm, geom=bm.verts[:] + bm.edges[:], offset=bevel, segments=1, affect='EDGES')
    bmesh.ops.transform(bm, matrix=Euler(rot).to_matrix().to_4x4(), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return _obj_from_bm(bm, name, mat, smooth=False)


def poly_prism(points2d, z0, z1, mat, name, plane='xz', offset=0.0):
    """Extrude a 2D polygon between two depths. plane 'xz' extrudes along Y; 'yz' along X."""
    bm = bmesh.new()
    vs0, vs1 = [], []
    for (a, b) in points2d:
        if plane == 'xz':
            vs0.append(bm.verts.new((a, z0 + offset, b)))
            vs1.append(bm.verts.new((a, z1 + offset, b)))
        else:
            vs0.append(bm.verts.new((z0 + offset, a, b)))
            vs1.append(bm.verts.new((z1 + offset, a, b)))
    bm.faces.new(vs0)
    bm.faces.new(list(reversed(vs1)))
    n = len(points2d)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((vs0[i], vs0[j], vs1[j], vs1[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _obj_from_bm(bm, name, mat, smooth=False)


def gable_roof(w, d, H, Rh, mat, name, over=0.18, thick=0.09, gable_mat=None):
    """Gable roof with the ridge along X over a w x d footprint at eave height H."""
    parts = []
    half = d / 2 + over
    ang = math.atan2(Rh, half)
    slope = math.hypot(half, Rh)
    for side in (-1, 1):
        c = (0, side * half / 2, H + Rh / 2 - thick * 0.3)
        parts.append(boxr(c, (w + 2 * over, slope + 0.06, thick), mat, f'{name}_s{side}', rot=(-side * ang, 0, 0)))
    # Ridge beam.
    parts.append(boxr((0, 0, H + Rh + 0.02), (w + 2 * over + 0.06, 0.12, 0.1), R.mats()['wood'], f'{name}_ridge'))
    if gable_mat is not None:
        tri = [(-d / 2, H), (d / 2, H), (0, H + Rh - 0.04)]
        for side in (-1, 1):
            parts.append(poly_prism(tri, -0.04, 0.04, gable_mat, f'{name}_g{side}', plane='yz', offset=side * w / 2))
    return parts


def house(w, d, H, Rh, wall, roof, timber=True, plinth=True, door_side='-y', windows=2, chimney=False, seed=0, name='house'):
    rng = random.Random(seed)
    M = bmats()
    parts = []
    if plinth:
        parts.append(boxr((0, 0, 0.12), (w + 0.12, d + 0.12, 0.24), M['stone2'], f'{name}_plinth', bevel=0.03))
    parts.append(boxr((0, 0, H / 2 + 0.1), (w, d, H - 0.2), M[wall], f'{name}_walls'))
    parts += gable_roof(w, d, H, Rh, M[roof], f'{name}_roof', gable_mat=M[wall])
    if timber:
        T = M['timber']
        t = 0.07
        for sx in (-1, 1):
            for sy in (-1, 1):
                parts.append(boxr((sx * (w / 2), sy * (d / 2), H / 2), (t * 1.3, t * 1.3, H), T, f'{name}_post{sx}{sy}'))
        for z in (0.3, H * 0.55, H - 0.05):
            parts.append(boxr((0, -d / 2 - 0.01, z), (w, t, t), T, f'{name}_bx{z:.2f}'))
            parts.append(boxr((w / 2 + 0.01, 0, z), (t, d, t), T, f'{name}_by{z:.2f}'))
        # Braces on the visible faces.
        n = max(1, int(w / 1.1))
        for i in range(n):
            x0 = -w / 2 + (i + 0.5) * w / n
            parts.append(boxr((x0, -d / 2 - 0.015, H * 0.78), (0.6 * w / n, t * 0.8, t * 0.8), T, f'{name}_br{i}', rot=(0, (-1) ** i * 0.6, 0)))
        m = max(1, int(d / 1.1))
        for i in range(m):
            y0 = -d / 2 + (i + 0.5) * d / m
            parts.append(boxr((w / 2 + 0.015, y0, H * 0.78), (t * 0.8, 0.6 * d / m, t * 0.8), T, f'{name}_bry{i}', rot=((-1) ** i * 0.6, 0, 0)))
    # Door.
    if door_side == '-y':
        parts.append(boxr((-w * 0.15, -d / 2 - 0.02, 0.62), (0.42, 0.06, 0.95), M['dark'], f'{name}_door'))
        parts.append(boxr((-w * 0.15, -d / 2 - 0.05, 0.62), (0.5, 0.04, 1.05), M['wood'], f'{name}_doorframe'))
        parts.append(boxr((-w * 0.15, -d / 2 - 0.035, 0.62), (0.36, 0.05, 0.86), M['wood'], f'{name}_doorleaf'))
    else:
        parts.append(boxr((w / 2 + 0.02, d * 0.1, 0.62), (0.06, 0.42, 0.95), M['dark'], f'{name}_door'))
        parts.append(boxr((w / 2 + 0.05, d * 0.1, 0.62), (0.04, 0.5, 1.05), M['wood'], f'{name}_doorframe'))
        parts.append(boxr((w / 2 + 0.035, d * 0.1, 0.62), (0.05, 0.36, 0.86), M['wood'], f'{name}_doorleaf'))
    # Windows: warm-lit openings with shutters, placed only where they fit.
    slots = []
    door_x = -w * 0.15 if door_side == '-y' else None
    door_y = d * 0.1 if door_side == '+x' else None
    for fx in (0.22, -0.38, 0.0, 0.42):
        x = w * fx
        if abs(x) + 0.42 > w / 2:
            continue
        if door_x is not None and abs(x - door_x) < 0.75:
            continue
        slots.append(('-y', x))
    for fy in (-0.22, 0.25, 0.0):
        y = d * fy
        if abs(y) + 0.42 > d / 2:
            continue
        if door_y is not None and abs(y - door_y) < 0.75:
            continue
        slots.append(('+x', y))
    # Alternate faces so both visible walls get windows.
    ordered = [sl for pair in zip([q for q in slots if q[0] == '-y'], [q for q in slots if q[0] == '+x']) for sl in pair]
    ordered += [q for q in slots if q not in ordered]
    for i, (face, c) in enumerate(ordered[:windows]):
        if face == '-y':
            parts.append(boxr((c, -d / 2 - 0.02, H * 0.6), (0.3, 0.05, 0.32), M['glow'], f'{name}_win{i}'))
            parts.append(boxr((c - 0.22, -d / 2 - 0.04, H * 0.6), (0.12, 0.04, 0.36), M['wood'], f'{name}_sh{i}a'))
            parts.append(boxr((c + 0.22, -d / 2 - 0.04, H * 0.6), (0.12, 0.04, 0.36), M['wood'], f'{name}_sh{i}b'))
        else:
            parts.append(boxr((w / 2 + 0.02, c, H * 0.6), (0.05, 0.3, 0.32), M['glow'], f'{name}_win{i}'))
            parts.append(boxr((w / 2 + 0.04, c - 0.22, H * 0.6), (0.04, 0.12, 0.36), M['wood'], f'{name}_sh{i}a'))
            parts.append(boxr((w / 2 + 0.04, c + 0.22, H * 0.6), (0.04, 0.12, 0.36), M['wood'], f'{name}_sh{i}b'))
    if chimney:
        parts.append(boxr((-w * 0.3, d * 0.15, H + Rh * 0.7), (0.32, 0.32, Rh * 1.1), M['stone2'], f'{name}_chim', bevel=0.02))
    return parts


def ridge_tent(L, W, Hh, mat, name, stripe=False):
    """Ridge tent along X, gable ends facing +-X."""
    M = bmats()
    tri = [(-W / 2, 0.0), (W / 2, 0.0), (0.0, Hh)]
    parts = [poly_prism(tri, -L / 2, L / 2, M['stripe'] if stripe else M[mat], f'{name}_cloth', plane='yz')]
    # Door flap on the +X gable.
    parts.append(poly_prism([(-W * 0.16, 0.0), (W * 0.16, 0.0), (0.0, Hh * 0.62)], L / 2 + 0.005, L / 2 + 0.03, M['dark'], f'{name}_door', plane='yz'))
    for sx in (-1, 1):
        parts.append(_cyl((sx * L / 2, 0, 0), (sx * L / 2, 0, Hh + 0.25), 0.035, 0.03, M['wood'], f'{name}_pole{sx}', segs=6))
    # Guy ropes and pegs.
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(_cyl((sx * (L / 2 + 0.05), 0, Hh), (sx * (L / 2 + 0.45), sy * 0.35, 0.02), 0.008, 0.008, M['canvas2'], f'{name}_rope{sx}{sy}', segs=4))
    return parts


def bell_tent(r, h, mat, name, stripe=False):
    M = bmats()
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=14, radius1=r, radius2=0.04, depth=h)
    bmesh.ops.translate(bm, vec=Vector((0, 0, h / 2)), verts=bm.verts)
    parts = [_obj_from_bm(bm, f'{name}_cone', M['stripe'] if stripe else M[mat])]
    parts.append(_cyl((0, 0, 0), (0, 0, h + 0.35), 0.03, 0.025, M['wood'], f'{name}_pole', segs=6))
    parts.append(boxr((r * 0.55, -r * 0.55, 0.42), (0.04, 0.3, 0.78), M['dark'], f'{name}_door', rot=(0, 0.45, -0.78)))
    return parts


def banner(x, y, h, color_mat, name, emblem=True, side=1):
    M = bmats()
    parts = [_cyl((x, y, 0), (x, y, h), 0.035, 0.03, M['wood'], f'{name}_pole', segs=6)]
    parts.append(_blob(random.Random(1), (x, y, h + 0.04), 0.06, M['gold'], f'{name}_knob', subdiv=1, rough=0))
    cloth_w = 0.46
    off = side * (cloth_w / 2 + 0.03) * 0.7071
    parts.append(boxr((x + off, y + off, h - 0.4), (cloth_w, 0.03, 0.68), M[color_mat], f'{name}_cloth', rot=(0, 0, math.pi / 4)))
    # Swallow-tail notch shadow and a white emblem on the camera-facing side.
    if emblem:
        parts.append(boxr((x + off + 0.025, y + off - 0.025, h - 0.36), (0.17, 0.03, 0.17), M['white'], f'{name}_emb', rot=(0, math.pi / 4, math.pi / 4)))
    return parts


def palisade(points, name, h=1.3, seed=0):
    rng = random.Random(seed)
    M = bmats()
    parts = []
    for i in range(len(points) - 1):
        a = Vector(points[i])
        b = Vector(points[i + 1])
        n = max(1, int((b - a).length / 0.22))
        for k in range(n):
            p = a + (b - a) * (k + 0.5) / n
            hh = h * rng.uniform(0.9, 1.08)
            parts.append(_cyl((p.x, p.y, 0), (p.x, p.y, hh), 0.1, 0.09, M['wood'], f'{name}_{i}_{k}', segs=6, smooth=False))
            bm = bmesh.new()
            bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=6, radius1=0.09, radius2=0.0, depth=0.22)
            bmesh.ops.translate(bm, vec=Vector((p.x, p.y, hh + 0.11)), verts=bm.verts)
            parts.append(_obj_from_bm(bm, f'{name}_t{i}_{k}', M['wood'], smooth=False))
    return parts


def wagon(name, covered=True):
    M = bmats()
    parts = [boxr((0, 0, 0.55), (1.6, 0.8, 0.28), M['wood'], f'{name}_bed', bevel=0.02)]
    for sx in (-0.55, 0.55):
        for sy in (-0.45, 0.45):
            parts.append(_cyl((sx, sy - 0.03, 0.32), (sx, sy + 0.03, 0.32), 0.3, 0.3, M['wood'], f'{name}_wheel{sx}{sy}', segs=12, smooth=False))
            parts.append(_cyl((sx, sy - 0.05, 0.32), (sx, sy + 0.05, 0.32), 0.07, 0.07, M['iron'], f'{name}_hub{sx}{sy}', segs=8))
    parts.append(_cyl((0.8, 0, 0.5), (1.6, 0, 0.32), 0.04, 0.04, M['wood'], f'{name}_shaft', segs=5))
    if covered:
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=16, radius1=0.44, radius2=0.44, depth=1.5)
        bmesh.ops.rotate(bm, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.pi / 2, 3, 'Y'), verts=bm.verts)
        for v in bm.verts:
            if v.co.z < 0:
                v.co.z = 0
        bmesh.ops.translate(bm, vec=Vector((0, 0, 0.7)), verts=bm.verts)
        parts.append(_obj_from_bm(bm, f'{name}_cover', M['canvas2']))
    return parts


def barrel(x, y, name, r=0.2, h=0.5):
    M = bmats()
    return [
        _cyl((x, y, 0), (x, y, h), r * 0.9, r * 0.9, M['wood'], f'{name}_b', segs=12),
        _cyl((x, y, h * 0.2), (x, y, h * 0.25), r * 0.93, r * 0.93, M['iron'], f'{name}_h1', segs=12),
        _cyl((x, y, h * 0.75), (x, y, h * 0.8), r * 0.93, r * 0.93, M['iron'], f'{name}_h2', segs=12),
    ]


def crate(x, y, s, name, rot=0.0):
    M = bmats()
    return [boxr((x, y, s / 2), (s, s, s), M['wood'], f'{name}_c', rot=(0, 0, rot), bevel=0.02)]


def dummy(x, y, name):
    M = bmats()
    rng = random.Random(int(abs(x * 100 + y * 10)))
    return [
        _cyl((x, y, 0), (x, y, 1.45), 0.05, 0.045, M['wood'], f'{name}_post', segs=6),
        _cyl((x - 0.32, y + 0.32, 1.12), (x + 0.32, y - 0.32, 1.12), 0.035, 0.035, M['wood'], f'{name}_arm', segs=5),
        _blob(rng, (x, y, 0.9), 0.22, M['straw'], f'{name}_body', squash=1.5, subdiv=2, rough=0.12),
        _blob(rng, (x, y, 1.42), 0.14, M['straw'], f'{name}_head', squash=1.0, subdiv=2, rough=0.1),
        boxr((x + 0.13, y - 0.13, 0.95), (0.12, 0.03, 0.12), M['red'], f'{name}_mark', rot=(0, 0, -math.pi / 4)),
    ]


def weapon_rack(x, y, name):
    M = bmats()
    parts = [
        _cyl((x - 0.4, y, 0), (x - 0.4, y, 0.9), 0.04, 0.04, M['wood'], f'{name}_p1', segs=5),
        _cyl((x + 0.4, y, 0), (x + 0.4, y, 0.9), 0.04, 0.04, M['wood'], f'{name}_p2', segs=5),
        _cyl((x - 0.45, y, 0.75), (x + 0.45, y, 0.75), 0.03, 0.03, M['wood'], f'{name}_bar', segs=5),
    ]
    for i in range(4):
        px = x - 0.3 + i * 0.2
        parts.append(_cyl((px, y + 0.05, 0.02), (px, y - 0.08, 1.45), 0.018, 0.018, M['wood'], f'{name}_spear{i}', segs=5))
        parts.append(_cyl((px, y - 0.08, 1.45), (px, y - 0.09, 1.6), 0.03, 0.0, M['iron'], f'{name}_tip{i}', segs=4))
    return parts


def target(x, y, name):
    M = bmats()
    parts = [_cyl((x, y + 0.15, 0), (x, y + 0.05, 1.0), 0.03, 0.03, M['wood'], f'{name}_leg', segs=5)]
    parts.append(_cyl((x - 0.02, y, 0.85), (x + 0.06, y, 0.85), 0.36, 0.36, M['straw'], f'{name}_butt', segs=16))
    for i, (r, mat) in enumerate(((0.26, 'white'), (0.17, 'blue'), (0.08, 'red'))):
        parts.append(_cyl((x + 0.06 + i * 0.004, y, 0.85), (x + 0.07 + i * 0.004, y, 0.85), r, r, M[mat], f'{name}_ring{i}', segs=16))
    return parts


def anvil(x, y, name):
    M = bmats()
    return [
        boxr((x, y, 0.2), (0.22, 0.22, 0.4), M['wood'], f'{name}_stump'),
        boxr((x, y, 0.47), (0.5, 0.18, 0.14), M['iron'], f'{name}_top', bevel=0.02),
        boxr((x + 0.3, y, 0.49), (0.16, 0.1, 0.08), M['iron'], f'{name}_horn', rot=(0, -0.3, 0)),
    ]


def forge(x, y, name):
    M = bmats()
    return [
        boxr((x, y, 0.4), (0.9, 0.8, 0.8), M['stone2'], f'{name}_hearth', bevel=0.03),
        boxr((x, y, 0.82), (0.6, 0.5, 0.06), M['glow'], f'{name}_coals'),
        boxr((x - 0.1, y + 0.2, 1.6), (0.38, 0.38, 1.7), M['stone2'], f'{name}_chimney', bevel=0.03),
    ]


def hay(x, y, name):
    M = bmats()
    return [_cyl((x - 0.3, y, 0.22), (x + 0.3, y, 0.22), 0.24, 0.24, M['hay'], f'{name}_bale', segs=10)]


def fire(x, y, name):
    M = bmats()
    rng = random.Random(3)
    parts = []
    for i in range(8):
        a = i * math.tau / 8
        parts.append(_blob(rng, (x + math.cos(a) * 0.3, y + math.sin(a) * 0.3, 0.05), 0.09, M['stone2'], f'{name}_st{i}', subdiv=1, rough=0.15))
    parts.append(_blob(rng, (x, y, 0.1), 0.13, M['glow'], f'{name}_coal', subdiv=1, rough=0.3))
    return parts


def tower(x, y, w, h, name, roof='roof_blue', stone=True):
    M = bmats()
    parts = [boxr((x, y, h / 2), (w, w, h), M['stone2' if stone else 'timber'], f'{name}_body', bevel=0.03)]
    # Crenellations or a pointed roof.
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=4, radius1=w * 0.85, radius2=0.0, depth=w * 1.3)
    bmesh.ops.rotate(bm, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.pi / 4, 3, 'Z'), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector((x, y, h + w * 0.65)), verts=bm.verts)
    parts.append(_obj_from_bm(bm, f'{name}_roof', M[roof], smooth=False))
    parts.append(boxr((x + w / 2 + 0.02, y, h * 0.7), (0.05, 0.16, 0.34), M['glow'], f'{name}_slit'))
    parts.append(boxr((x, y - w / 2 - 0.02, h * 0.55), (0.16, 0.05, 0.34), M['glow'], f'{name}_slit2'))
    return parts


# ---------------------------------------------------------------- buildings


def building(bid, lvl):
    """Return a list of parts for a base building at a level (1-3)."""
    P = []
    if bid == 'command':
        if lvl == 1:
            P += ridge_tent(2.0, 1.6, 1.5, 'canvas2', 'cmd', stripe=True)
            P += banner(-1.0, -1.0, 2.2, 'blue', 'cmd_b1')
            P += banner(1.15, -0.95, 2.0, 'blue', 'cmd_b2')
            P += crate(1.1, -0.6, 0.3, 'cmd_cr')
            P += barrel(-1.25, 0.6, 'cmd_bar')
        elif lvl == 2:
            P += house(2.4, 1.6, 1.5, 1.0, 'plaster', 'roof_blue', windows=3, chimney=True, seed=1, name='hall')
            P += banner(1.6, -1.1, 2.6, 'blue', 'hall_b1')
            P += banner(-1.6, -1.1, 2.6, 'blue', 'hall_b2')
        else:
            P += house(2.8, 1.8, 2.0, 1.2, 'stone2', 'roof_blue', windows=4, timber=False, chimney=True, seed=2, name='keep_hall')
            P += tower(-1.75, 0.45, 1.15, 3.8, 'keep_tower')
            P += banner(-1.75, 0.45, 5.5, 'blue', 'keep_b')
            P += banner(1.75, -1.2, 2.8, 'blue', 'keep_b2')
            P += banner(-0.3, -1.25, 2.6, 'blue', 'keep_b3')
    elif bid == 'barracks':
        if lvl == 1:
            P += [_move(o, (-0.7, 0.5, 0)) for o in ridge_tent(1.3, 1.1, 1.0, 'canvas2', 'bt1')]
            P += [_move(o, (0.7, 0.5, 0)) for o in ridge_tent(1.3, 1.1, 1.0, 'canvas2', 'bt2')]
            P += [_move(o, (0.0, -0.8, 0)) for o in ridge_tent(1.3, 1.1, 1.0, 'canvas2', 'bt3')]
            P += banner(1.4, -0.9, 1.8, 'red', 'bt_b', emblem=False)
            P += fire(-0.9, -0.9, 'bt_fire')
        elif lvl == 2:
            P += house(2.8, 1.3, 1.3, 0.9, 'plaster', 'roof_red', windows=4, seed=3, name='barr')
            P += barrel(1.65, -0.5, 'barr_bar')
            P += [_move(o, (1.85, 0.2, 0)) for o in weapon_rack(0, 0, 'barr_rack')]
        else:
            P += house(2.8, 1.5, 2.1, 1.0, 'plaster', 'roof_red', windows=4, chimney=True, seed=4, name='barr3')
            P += [_move(o, (0, 0, 0)) for o in palisade([(-1.6, -1.2), (1.6, -1.2)], 'barr3_pal', h=0.6)]
            P += banner(1.75, -1.0, 2.8, 'red', 'barr3_b', emblem=False)
    elif bid == 'training':
        if lvl == 1:
            P += dummy(-0.6, -0.3, 'd1') + dummy(0.4, -0.7, 'd2') + dummy(0.7, 0.5, 'd3')
            P += weapon_rack(-0.9, 0.7, 'tr_rack')
            P += target(1.3, -0.2, 'tr_t')
        elif lvl == 2:
            P += dummy(-0.4, -0.4, 'd1') + dummy(0.5, -0.8, 'd2')
            P += house(1.4, 1.0, 1.1, 0.7, 'plaster', 'roof_thatch', windows=1, timber=True, seed=5, name='shed', door_side='+x')
            P += [_move(o, (-0.5, 0.9, 0)) for o in house(1.2, 0.9, 1.0, 0.6, 'plaster', 'roof_thatch', windows=1, seed=6, name='shed2')]
            P += target(1.4, 0.3, 'tr_t')
            P += _fence_ring(1.8, 1.4, 'tr_f')
        else:
            P += dummy(-0.3, -0.6, 'd1') + dummy(0.6, -0.9, 'd2')
            P += [_move(o, (-0.2, 0.7, 0)) for o in house(2.4, 1.2, 1.6, 0.9, 'plaster', 'roof_slate', windows=3, chimney=False, seed=7, name='hallf')]
            P += target(1.5, -0.2, 'tr_t')
            P += weapon_rack(-1.2, -0.7, 'tr_rack')
            P += banner(1.6, 0.9, 2.6, 'blue', 'tr_b')
    elif bid == 'armoury':
        if lvl == 1:
            P += forge(-0.3, 0.3, 'fg')
            P += anvil(0.6, -0.4, 'an')
            P += _lean_to(1.8, 1.4, 1.5, 'lt')
            P += barrel(-1.0, -0.6, 'ar_bar')
        elif lvl == 2:
            P += house(2.0, 1.4, 1.4, 0.9, 'plaster', 'roof_slate', windows=2, chimney=True, seed=8, name='smithy')
            P += anvil(1.5, -0.9, 'an')
            P += [_move(o, (0.4, -1.3, 0)) for o in weapon_rack(0, 0, 'ar_rack')]
        else:
            P += house(2.4, 1.6, 1.8, 1.0, 'stone2', 'roof_slate', windows=3, timber=False, chimney=True, seed=9, name='armoury')
            P += anvil(1.7, -1.0, 'an')
            P += forge(-1.6, -1.0, 'fg2')
            P += banner(1.75, 0.95, 2.8, 'blue', 'arm_b')
    elif bid == 'infirmary':
        if lvl == 1:
            P += ridge_tent(1.8, 1.4, 1.3, 'white', 'inf')
            P += banner(-1.1, -0.8, 1.7, 'green_cloth', 'inf_b', emblem=True)
            P += crate(1.0, -0.7, 0.3, 'inf_cr')
            P += _cot(0.6, 0.9, 'cot1')
        elif lvl == 2:
            P += house(2.0, 1.4, 1.3, 0.9, 'white', 'roof_thatch', windows=3, seed=10, name='inf2')
            P += _herb_garden(1.6, -0.6, 'herbs')
        else:
            P += house(2.6, 1.6, 1.7, 1.0, 'white', 'roof_red', windows=4, chimney=True, seed=11, name='inf3')
            P += _herb_garden(1.8, -0.9, 'herbs')
            P += banner(-1.6, -1.0, 2.6, 'green_cloth', 'inf3_b')
    elif bid == 'quartermaster':
        if lvl == 1:
            P += wagon('wg')
            P += crate(1.1, -0.6, 0.35, 'q1') + crate(1.25, -0.2, 0.28, 'q2', rot=0.4)
            P += barrel(-1.1, -0.6, 'qb1') + barrel(-1.25, -0.2, 'qb2')
            P += hay(0.2, -1.0, 'qh')
        elif lvl == 2:
            P += house(2.2, 1.4, 1.2, 0.8, 'plaster', 'roof_thatch', windows=1, seed=12, name='store', door_side='+x')
            P += crate(1.6, -0.9, 0.35, 'q1') + crate(1.4, -1.3, 0.28, 'q2', rot=0.4) + barrel(-1.3, -1.0, 'qb1')
        else:
            P += house(2.8, 1.8, 1.8, 1.0, 'stone2', 'roof_red', windows=2, timber=False, seed=13, name='store3', door_side='+x')
            P += [_move(o, (0, -1.45, 0)) for o in wagon('wg', covered=False)]
            P += crate(1.8, -1.2, 0.35, 'q1') + barrel(-1.7, -1.1, 'qb1') + barrel(-1.5, -1.4, 'qb2')
    return P


def _move(ob, d):
    ob.location = Vector(ob.location) + Vector(d)
    return ob


def _fence_ring(hw, hd, name):
    M = bmats()
    parts = []
    pts = [(-hw, -hd), (hw, -hd), (hw, hd)]
    for i in range(len(pts) - 1):
        a, b = Vector((*pts[i], 0)), Vector((*pts[i + 1], 0))
        n = int((b - a).length / 0.6)
        for k in range(n + 1):
            p = a + (b - a) * k / n
            parts.append(_cyl((p.x, p.y, 0), (p.x, p.y, 0.55), 0.04, 0.04, M['wood'], f'{name}_p{i}{k}', segs=5, smooth=False))
        for z in (0.25, 0.48):
            parts.append(_cyl((a.x, a.y, z), (b.x, b.y, z), 0.025, 0.025, M['wood'], f'{name}_r{i}{z}', segs=5, smooth=False))
    return parts


def _lean_to(w, d, h, name):
    M = bmats()
    parts = []
    for sx in (-1, 1):
        parts.append(_cyl((sx * w / 2, -d / 2, 0), (sx * w / 2, -d / 2, h * 0.75), 0.05, 0.05, M['wood'], f'{name}_pf{sx}', segs=6))
        parts.append(_cyl((sx * w / 2, d / 2, 0), (sx * w / 2, d / 2, h), 0.05, 0.05, M['wood'], f'{name}_pb{sx}', segs=6))
    ang = math.atan2(h * 0.25, d)
    parts.append(boxr((0, 0, h * 0.875), (w + 0.3, math.hypot(d, h * 0.25) + 0.3, 0.07), M['roof_thatch'], f'{name}_roof', rot=(ang, 0, 0)))
    return parts


def _cot(x, y, name):
    M = bmats()
    return [boxr((x, y, 0.25), (0.9, 0.4, 0.08), M['canvas2'], f'{name}_bed'), boxr((x, y, 0.12), (0.85, 0.35, 0.24), M['wood'], f'{name}_frame')]


def _herb_garden(x, y, name):
    M = bmats()
    rng = random.Random(9)
    parts = [boxr((x, y, 0.08), (0.9, 0.6, 0.16), M['wood'], f'{name}_box')]
    for i in range(6):
        parts.append(_blob(rng, (x - 0.3 + (i % 3) * 0.3, y - 0.15 + (i // 3) * 0.3, 0.22), 0.12, M['oak_m'] if i % 2 else M['oak_l'], f'{name}_h{i}', subdiv=1, rough=0.2))
    return parts


# ---------------------------------------------------------------- landmarks (campaign map)


def landmark(kind):
    P = []
    M = bmats()
    if kind == 'village':
        P += [_move(o, (-0.6, 0.4, 0)) for o in house(1.2, 0.9, 0.9, 0.7, 'plaster', 'roof_thatch', windows=1, seed=21, name='v1')]
        P += [_move(o, (0.8, -0.3, 0)) for o in house(1.0, 0.8, 0.8, 0.6, 'plaster', 'roof_thatch', windows=1, seed=22, name='v2', door_side='+x')]
        P += [_move(o, (-0.4, -1.0, 0)) for o in house(0.9, 0.7, 0.7, 0.55, 'plaster', 'roof_red', windows=1, seed=23, name='v3')]
        P += hay(0.9, 0.9, 'vh') + _fence_ring(1.6, 1.4, 'vf')
    elif kind == 'camp':
        P += [_move(o, (-0.3, 0.4, 0)) for o in ridge_tent(1.1, 0.9, 0.8, 'canvas2', 'ct1')]
        P += [_move(o, (0.7, -0.4, 0)) for o in ridge_tent(1.1, 0.9, 0.8, 'canvas2', 'ct2')]
        P += fire(-0.4, -0.7, 'cf')
        P += barrel(0.9, 0.8, 'cb')
    elif kind == 'scout':
        P += _watchtower(0, 0, 'wt')
        P += banner(0.9, -0.7, 1.4, 'blue', 'wt_b')
    elif kind == 'battle':
        P += palisade([(-1.0, -0.4), (0.0, -0.9), (1.0, -0.4)], 'bp', h=0.9, seed=2)
        P += banner(0.0, 0.2, 2.0, 'red', 'bt_b', emblem=False)
        P.append(_move(R.tent(8), (0.6, 0.6, 0)))
    elif kind == 'objective':
        P += palisade([(-1.5, -1.3), (1.5, -1.3), (1.5, 1.3)], 'op', h=1.1, seed=5)
        big = R.tent(9)
        big.scale = (1.4, 1.4, 1.4)
        P.append(big)
        P += banner(-0.9, -0.5, 2.6, 'red', 'ob1', emblem=False)
        P += banner(0.9, 0.6, 2.6, 'red', 'ob2', emblem=False)
        P += fire(0.6, -0.6, 'of')
    elif kind == 'event':
        P += _signpost(0, 0, 'sp')
        P.append(_move(R.rock(77, 0.6), (0.6, 0.3, 0)))
    elif kind == 'start':
        P += banner(0, 0, 2.4, 'blue', 'st_b')
        P += [_move(o, (0.5, 0.5, 0)) for o in wagon('stw')]
        P += crate(-0.7, 0.5, 0.3, 'st_c')
    elif kind == 'ambush':
        P.append(R.rock(91, 1.0))
        P += banner(0.4, -0.3, 1.6, 'red', 'am_b', emblem=False)
    return [p for p in P if p is not None]


def _watchtower(x, y, name):
    M = bmats()
    parts = []
    h = 2.2
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(_cyl((x + sx * 0.45, y + sy * 0.45, 0), (x + sx * 0.35, y + sy * 0.35, h), 0.06, 0.05, M['wood'], f'{name}_leg{sx}{sy}', segs=6))
    parts.append(boxr((x, y, h), (1.0, 1.0, 0.1), M['wood'], f'{name}_floor'))
    for side in range(4):
        a = side * math.pi / 2
        parts.append(boxr((x + math.cos(a) * 0.48, y + math.sin(a) * 0.48, h + 0.25), (0.06 if side % 2 == 0 else 1.0, 1.0 if side % 2 == 0 else 0.06, 0.4), M['wood'], f'{name}_rail{side}'))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=4, radius1=0.85, radius2=0.0, depth=0.7)
    bmesh.ops.rotate(bm, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.pi / 4, 3, 'Z'), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector((x, y, h + 1.15)), verts=bm.verts)
    parts.append(_obj_from_bm(bm, f'{name}_roof', M['roof_thatch'], smooth=False))
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(_cyl((x + sx * 0.4, y + sy * 0.4, h), (x + sx * 0.4, y + sy * 0.4, h + 0.85), 0.03, 0.03, M['wood'], f'{name}_rp{sx}{sy}', segs=5))
    parts.append(_cyl((x - 0.3, y - 0.6, 0), (x - 0.05, y - 0.45, h), 0.03, 0.03, M['wood'], f'{name}_ladder', segs=5))
    return parts


def _signpost(x, y, name):
    M = bmats()
    return [
        _cyl((x, y, 0), (x, y, 1.3), 0.05, 0.045, M['wood'], f'{name}_post', segs=6),
        boxr((x + 0.22, y - 0.05, 1.12), (0.5, 0.04, 0.16), M['wood'], f'{name}_s1', rot=(0, 0, -0.5)),
        boxr((x - 0.05, y - 0.22, 0.88), (0.04, 0.46, 0.15), M['wood'], f'{name}_s2', rot=(0, 0, 0.3)),
        _blob(random.Random(4), (x + 0.2, y + 0.25, 0.15), 0.16, M['stone2'], f'{name}_stone', subdiv=1, rough=0.2),
    ]


def compose(parts, name):
    """Join parts into one object whose origin is the world origin (the footprint centre)."""
    me = bpy.data.meshes.new(f'{name}_anchor')
    me.from_pydata([(0, 0, 0)], [], [])
    anchor = bpy.data.objects.new(f'{name}_anchor', me)
    R.asset_collection().objects.link(anchor)
    return join([anchor] + [p for p in parts if p is not None], name)


def palisade_segment(axis, seed=0):
    """One tile of sharpened-log palisade along game x ('x') or game y ('y')."""
    rng = random.Random(seed)
    M = bmats()
    parts = []
    n = 5
    for k in range(n):
        t = -0.5 + (k + 0.5) / n
        px, py = (t, 0.0) if axis == 'x' else (0.0, -t)
        hh = rng.uniform(1.15, 1.35)
        parts.append(_cyl((px, py, 0), (px + rng.uniform(-0.02, 0.02), py + rng.uniform(-0.02, 0.02), hh), 0.1, 0.09, M['wood'], f'pal{k}', segs=7, smooth=False))
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=7, radius1=0.092, radius2=0.0, depth=0.24)
        bmesh.ops.translate(bm, vec=Vector((px, py, hh + 0.12)), verts=bm.verts)
        parts.append(_obj_from_bm(bm, f'palt{k}', M['wood'], smooth=False))
    a, b = ((-0.5, 0.06), (0.5, 0.06)) if axis == 'x' else ((0.06, 0.5), (0.06, -0.5))
    for z in (0.35, 0.9):
        parts.append(_cyl((a[0], a[1], z), (b[0], b[1], z), 0.03, 0.03, M['timber'], f'palr{z}', segs=5, smooth=False))
    return parts


def gate_tower(seed=0):
    """Timber gate tower with a thatched roof and a blue banner."""
    M = bmats()
    parts = []
    h = 2.3
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(_cyl((sx * 0.42, sy * 0.42, 0), (sx * 0.38, sy * 0.38, h + 0.9), 0.07, 0.06, M['wood'], f'gl{sx}{sy}', segs=7))
    parts.append(boxr((0, 0, h), (1.05, 1.05, 0.12), M['wood'], 'gfloor'))
    for side in range(4):
        a = side * math.pi / 2
        parts.append(boxr((math.cos(a) * 0.5, math.sin(a) * 0.5, h + 0.3), (0.07 if side % 2 == 0 else 1.05, 1.05 if side % 2 == 0 else 0.07, 0.5), M['timber'], f'gw{side}'))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=4, radius1=0.9, radius2=0.0, depth=0.8)
    bmesh.ops.rotate(bm, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.pi / 4, 3, 'Z'), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector((0, 0, h + 1.3)), verts=bm.verts)
    parts.append(_obj_from_bm(bm, 'groof', M['roof_thatch'], smooth=False))
    parts += banner(0.0, 0.0, h + 2.25, 'blue', 'gban')
    return parts
