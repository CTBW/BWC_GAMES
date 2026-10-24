"""Meridius character kit: posable miniature soldiers built from parts.

Model frame: forward = -Y, the character's left = +X, up = +Z, feet at the
origin. Poses give limb directions; weapons attach to the hands. Figures are
rendered in four facings so the light always comes from the screen's upper left.
"""
import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

import meridius_rig as R
from meridius_rig import _obj_from_bm, _ramp_mat, join

# ---------------------------------------------------------------- materials


def M(name, a, b, scale=10.0, rough=0.75):
    return _ramp_mat('C_' + name, [a, b], scale, rough=rough)


SKINS = [((0.62, 0.38, 0.26), (0.78, 0.52, 0.38)), ((0.55, 0.33, 0.22), (0.70, 0.46, 0.32)), ((0.68, 0.45, 0.32), (0.84, 0.60, 0.45))]
HAIRS = [((0.16, 0.09, 0.04), (0.26, 0.15, 0.07)), ((0.45, 0.32, 0.12), (0.62, 0.47, 0.20)), ((0.05, 0.04, 0.03), (0.11, 0.09, 0.07)), ((0.32, 0.12, 0.05), (0.48, 0.20, 0.09))]
GOB_SKINS = [((0.22, 0.32, 0.08), (0.34, 0.45, 0.13)), ((0.26, 0.36, 0.10), (0.40, 0.50, 0.16)), ((0.18, 0.28, 0.07), (0.30, 0.40, 0.11))]
ORC_SKINS = [((0.20, 0.28, 0.08), (0.30, 0.38, 0.12)), ((0.18, 0.25, 0.07), (0.27, 0.35, 0.11)), ((0.23, 0.30, 0.09), (0.33, 0.41, 0.14))]


def mats(v):
    return {
        'skin': M(f'Skin{v % 3}', *SKINS[v % 3], 6),
        'hair': M(f'Hair{v % 4}', *HAIRS[v % 4], 20),
        'gskin': M(f'GSkin{v % 3}', *GOB_SKINS[v % 3], 6),
        'oskin': M(f'OSkin{v % 3}', *ORC_SKINS[v % 3], 6),
        'tunic': M('Tunic', (0.55, 0.50, 0.38), (0.70, 0.65, 0.52), 9),
        'blue': M('Blue', (0.035, 0.08, 0.30), (0.07, 0.15, 0.48), 9),
        'blue_d': M('BlueD', (0.02, 0.04, 0.16), (0.04, 0.08, 0.26), 9),
        'leather': M('Leather', (0.16, 0.08, 0.035), (0.26, 0.14, 0.06), 14),
        'boots': M('Boots', (0.08, 0.04, 0.02), (0.14, 0.08, 0.04), 14),
        'steel': M('Steel', (0.40, 0.42, 0.45), (0.66, 0.68, 0.70), 12, rough=0.35),
        'iron': M('Iron', (0.16, 0.17, 0.19), (0.30, 0.31, 0.33), 12, rough=0.45),
        'wood': M('Wood', (0.18, 0.10, 0.04), (0.32, 0.19, 0.08), 18),
        'gold': M('Gold', (0.50, 0.33, 0.06), (0.78, 0.58, 0.16), 9, rough=0.35),
        'white': M('White', (0.70, 0.68, 0.62), (0.86, 0.85, 0.80), 6),
        'dark': M('Dark', (0.02, 0.015, 0.01), (0.05, 0.04, 0.03), 6),
        'eye_y': _ramp_mat('C_EyeY', [(0.9, 0.7, 0.05), (1.0, 0.85, 0.2)], 5, emission=(1.0, 0.7, 0.1)),
        'red': M('Red', (0.24, 0.025, 0.015), (0.42, 0.06, 0.03), 10),
        'rag': M('Rag', (0.30, 0.03, 0.02), (0.48, 0.07, 0.04), 12),
        'gcloth': M('GCloth', (0.05, 0.04, 0.035), (0.10, 0.08, 0.07), 9),
        'hood_g': M('HoodG', (0.035, 0.03, 0.03), (0.07, 0.06, 0.055), 9),
        'fur': M('Fur', (0.06, 0.045, 0.03), (0.14, 0.10, 0.07), 22),
        'bone': M('Bone', (0.62, 0.58, 0.48), (0.82, 0.78, 0.68), 9),
        'straw': M('StrawC', (0.55, 0.42, 0.18), (0.72, 0.60, 0.30), 20),
    }


# ---------------------------------------------------------------- geometry helpers


def frame(z_dir, x_hint=Vector((1, 0, 0))):
    z = Vector(z_dir).normalized()
    xh = Vector(x_hint)
    if abs(xh.normalized().dot(z)) > 0.95:
        xh = Vector((0, 1, 0)) if abs(z.y) < 0.9 else Vector((1, 0, 0))
    x = (xh - z * xh.dot(z)).normalized()
    y = z.cross(x)
    m = Matrix((x, y, z)).transposed()
    return m


def place(bm, m3, pos):
    mm = Matrix.Translation(Vector(pos)) @ m3.to_4x4()
    bmesh.ops.transform(bm, matrix=mm, verts=bm.verts)


class Fig:
    """Collects parts in the model frame with an optional upper-body transform."""

    def __init__(self, name):
        self.name = name
        self.parts = []
        self.T = Matrix.Identity(4)  # applied to upper-body points

    def obj(self, bm, mat, smooth=True):
        o = _obj_from_bm(bm, f'{self.name}_{len(self.parts)}', mat, smooth)
        self.parts.append(o)
        return o

    def ball(self, c, r, mat, sx=1.0, sy=1.0, sz=1.0, upper=True, sub=2):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=r) if sub >= 2 else bmesh.ops.create_icosphere(bm, subdivisions=1, radius=r)
        bmesh.ops.scale(bm, vec=Vector((sx, sy, sz)), verts=bm.verts)
        p = self.T @ Vector(c) if upper else Vector(c)
        bmesh.ops.transform(bm, matrix=Matrix.Translation(p) @ (self.T.to_3x3().to_4x4() if upper else Matrix.Identity(4)), verts=bm.verts)
        return self.obj(bm, mat)

    def seg(self, p0, p1, r0, r1, mat, upper=True, segs=12, caps=True):
        a = self.T @ Vector(p0) if upper else Vector(p0)
        b = self.T @ Vector(p1) if upper else Vector(p1)
        d = b - a
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segs, radius1=r0, radius2=r1, depth=max(1e-4, d.length))
        place(bm, frame(d), (a + b) / 2)
        o = self.obj(bm, mat)
        return o

    def box(self, c, size, mat, rot=None, upper=True, bevel=0.012):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
        if bevel:
            bmesh.ops.bevel(bm, geom=bm.verts[:] + bm.edges[:], offset=bevel, segments=2, affect='EDGES')
        m3 = rot if rot is not None else Matrix.Identity(3)
        p = self.T @ Vector(c) if upper else Vector(c)
        if upper:
            m3 = self.T.to_3x3() @ m3
        place(bm, m3, p)
        return self.obj(bm, mat, smooth=False)

    def prism(self, pts2d, depth, mat, m3, pos, upper=True):
        """Extrude a polygon given in local (x, z) along local y, then place it."""
        bm = bmesh.new()
        f0 = [bm.verts.new((x, -depth / 2, z)) for x, z in pts2d]
        f1 = [bm.verts.new((x, depth / 2, z)) for x, z in pts2d]
        bm.faces.new(f0)
        bm.faces.new(list(reversed(f1)))
        n = len(pts2d)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((f0[i], f0[j], f1[j], f1[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        p = self.T @ Vector(pos) if upper else Vector(pos)
        if upper:
            m3 = self.T.to_3x3() @ m3
        place(bm, m3, p)
        return self.obj(bm, mat, smooth=False)

    def cone(self, base, tip, r, mat, upper=True, segs=10):
        return self.seg(base, tip, r, 0.0, mat, upper=upper, segs=segs)


# ---------------------------------------------------------------- styles


def style(t, v):
    s = {
        'kind': 'human', 'h': 1.0, 'bulk': 1.0, 'skin': 'skin', 'tunic': 'tunic', 'tabard': 'blue', 'legs': 'blue_d',
        'head': 'hair', 'beard': v == 1, 'weapon': 'sword', 'shield': None, 'scarf': 'blue', 'pauldrons': None,
        'quiver': False, 'rags': False, 'fur': False, 'emblem': True, 'helmet': None, 'banner': False, 'skulls': False,
    }
    if t == 'footman':
        s.update(weapon='sword', shield='kite', bulk=1.05, helmet='cap' if v == 2 else None)
    elif t == 'spearman':
        s.update(weapon='spear', pauldrons='leather', helmet='kettle' if v != 1 else None, scarf=None)
    elif t == 'crossbowman':
        s.update(weapon='crossbow', head='hood', quiver=True, scarf=None, beard=v == 0)
    elif t == 'goblin_spear':
        s.update(kind='goblin', h=0.78, bulk=0.9, skin='gskin', tunic='gcloth', tabard='hood_g', legs='gcloth', head='helmet_g' if v % 2 == 0 else 'hood_g',
                 beard=False, weapon='gspear', scarf=None, rags=True, emblem=False)
    elif t == 'goblin_archer':
        s.update(kind='goblin', h=0.76, bulk=0.88, skin='gskin', tunic='gcloth', tabard='hood_g', legs='gcloth', head='hood_g', beard=False,
                 weapon='bow', scarf=None, rags=True, quiver=True, emblem=False)
    elif t == 'orc_warrior':
        s.update(kind='orc', h=1.12, bulk=1.45, skin='oskin', tunic='leather', tabard='red', legs='gcloth', head='helmet_o' if v != 2 else 'topknot',
                 beard=False, weapon='cleaver', shield='round', scarf=None, pauldrons='spiked', rags=True, fur=True, emblem=False)
    elif t == 'orc_warlord':
        s.update(kind='orc', h=1.3, bulk=1.7, skin='oskin', tunic='leather', tabard='red', legs='gcloth', head='topknot', beard=True,
                 weapon='mace', scarf=None, pauldrons='spiked', rags=True, fur=True, emblem=False, banner=True, skulls=True)
    return s


# ---------------------------------------------------------------- poses
# Directions in the model frame: +X = character's left, -Y = forward, +Z = up.


def V(x, y, z):
    return Vector((x, y, z)).normalized()


def pose_def(t, pose):
    st = style(t, 0)
    w = st['weapon']
    P = {
        'lean': 0.0,
        'leg_r': (V(-0.04, 0, -1), V(0, 0, -1)),
        'leg_l': (V(0.04, 0, -1), V(0, 0, -1)),
        'arm_r': (V(-0.25, -0.15, -0.95), V(-0.1, -0.6, -0.8)),
        'arm_l': (V(0.25, -0.15, -0.95), V(0.1, -0.6, -0.8)),
        'weapon_dir': V(0, -0.35, 0.94),
        'shield_open': 0.0,
    }
    stride = {'leg_l': (V(0.04, -0.42, -0.9), V(0, 0.05, -1)), 'leg_r': (V(-0.04, 0.38, -0.92), V(0, 0.42, -0.9))}
    if pose == 'idle':
        if w == 'sword':
            P.update(arm_r=(V(-0.22, -0.12, -0.97), V(-0.05, -0.75, -0.65)), weapon_dir=V(-0.05, -0.55, 0.83),
                     arm_l=(V(0.3, -0.45, -0.85), V(-0.55, -0.82, -0.12)))
        elif w == 'spear':
            P.update(arm_r=(V(-0.3, -0.2, -0.93), V(-0.08, -0.5, -0.1)), weapon_dir=V(-0.02, -0.06, 1.0),
                     arm_l=(V(0.25, -0.2, -0.95), V(0.05, -0.4, -0.9)))
        elif w == 'crossbow':
            P.update(arm_r=(V(-0.15, -0.25, -0.95), V(0.25, -0.8, -0.1)), arm_l=(V(0.2, -0.35, -0.9), V(-0.25, -0.95, 0.15)),
                     weapon_dir=V(0.05, -1.0, 0.25))
        elif w == 'gspear':
            P.update(lean=12, arm_r=(V(-0.2, 0.1, -0.97), V(0.1, -0.7, 0.2)), arm_l=(V(0.3, -0.5, -0.8), V(0.0, -0.9, 0.1)),
                     weapon_dir=V(0.08, -1.0, 0.18))
        elif w == 'bow':
            P.update(lean=6, arm_l=(V(0.25, -0.35, -0.9), V(0.1, -0.6, -0.5)), arm_r=(V(-0.25, 0, -0.95), V(-0.1, -0.3, -0.9)),
                     weapon_dir=V(0.1, -0.4, 0.9))
        elif w in ('cleaver', 'mace'):
            P.update(lean=6, arm_r=(V(-0.35, -0.1, -0.93), V(-0.1, -0.55, -0.4)), weapon_dir=V(-0.1, -0.45, 0.88),
                     arm_l=(V(0.35, -0.35, -0.87), V(-0.3, -0.9, -0.1)))
    elif pose == 'atk':
        P.update(stride)
        P['lean'] = 14
        if w == 'sword':
            P.update(arm_r=(V(-0.2, -0.85, 0.35), V(-0.05, -0.95, 0.25)), weapon_dir=V(0.0, -0.98, 0.18),
                     arm_l=(V(0.35, -0.45, -0.82), V(-0.2, -0.95, 0.1)))
        elif w == 'spear':
            P.update(lean=8, arm_r=(V(-0.3, 0.25, -0.92), V(0.05, -0.9, -0.1)), arm_l=(V(0.25, -0.7, -0.65), V(-0.05, -1.0, 0.0)),
                     weapon_dir=V(0.02, -1.0, 0.24))
        elif w == 'crossbow':
            P.update(lean=4, arm_r=(V(-0.3, -0.4, -0.25), V(0.2, -0.95, 0.05)), arm_l=(V(0.25, -0.75, -0.3), V(-0.15, -1.0, 0.05)),
                     weapon_dir=V(0, -1.0, 0.03))
        elif w == 'gspear':
            P.update(lean=20, arm_r=(V(-0.2, 0.3, -0.9), V(0.05, -0.95, 0.05)), arm_l=(V(0.25, -0.8, -0.5), V(0, -1, 0.05)),
                     weapon_dir=V(0.02, -1.0, 0.02))
        elif w == 'bow':
            P.update(lean=4, arm_l=(V(0.15, -0.98, 0.1), V(0.05, -1.0, 0.05)), arm_r=(V(-0.45, -0.3, 0.1), V(0.55, 0.8, 0.0)),
                     weapon_dir=V(0.0, -0.1, 1.0))
        elif w in ('cleaver', 'mace'):
            P.update(arm_r=(V(-0.45, 0.1, 0.9), V(-0.1, -0.35, 0.93)), weapon_dir=V(0.0, 0.25, 0.97),
                     arm_l=(V(0.4, -0.5, -0.75), V(-0.3, -0.9, -0.1)))
    elif pose == 'flee':
        P.update(stride)
        P.update(lean=22, arm_r=(V(-0.55, 0.15, 0.82), V(-0.2, 0.1, 0.97)), arm_l=(V(0.55, 0.1, 0.82), V(0.25, 0.05, 0.97)), weapon_dir=None)
    return P


# ---------------------------------------------------------------- builders


def build(t, pose, v, name='fig'):
    """Build a posed figure facing -Y. Returns (joined object, head centre)."""
    st = style(t, v)
    mm = mats(v)
    P = pose_def(t, 'idle' if pose == 'dead' else pose)
    if pose == 'dead':
        P.update(arm_r=(V(-0.9, -0.1, 0.4), V(-0.7, -0.3, 0.6)), arm_l=(V(0.9, -0.1, 0.35), V(0.8, -0.2, 0.5)),
                 leg_l=(V(0.25, 0, -1), V(0.2, 0, -1)), leg_r=(V(-0.2, 0, -1), V(-0.1, 0, -1)), weapon_dir=None, lean=0)
    F = Fig(name)
    h = st['h']
    B = st['bulk']
    gob = st['kind'] == 'goblin'
    orc = st['kind'] == 'orc'
    # Proportions (metres): a chunky miniature, about 1.2 m for a human.
    s = 1.2 * h
    hip_z = 0.43 * s
    knee_z = 0.22 * s
    chest_z = 0.72 * s
    sh_z = 0.76 * s
    head_r = (0.145 if gob else 0.135 if orc else 0.122) * (s / 1.2) ** 0.55 * (1.0 if not orc else 1.05)
    head_z = sh_z + head_r * 1.05 + 0.02
    hip_w = 0.09 * B * (s / 1.2)
    sh_w = 0.2 * B * (s / 1.2)
    limb_r = 0.05 * (B ** 0.7) * (s / 1.2)
    leg_r = 0.06 * (B ** 0.7) * (s / 1.2)
    lean = math.radians(P['lean'])
    hip = Vector((0, 0, hip_z))
    # Rotating about X by +lean tips the chest forward (toward -Y).
    F.T = Matrix.Translation(hip) @ Matrix.Rotation(lean, 4, 'X') @ Matrix.Translation(-hip)
    skin = mm[st['skin']]

    # Legs (not affected by lean).
    for side, key in ((1, 'leg_l'), (-1, 'leg_r')):
        top = Vector((side * hip_w, 0.0, hip_z))
        thigh, shin = P[key]
        knee = top + thigh * (hip_z - knee_z) * 1.02
        ankle = knee + shin * (knee_z - 0.06 * (s / 1.2))
        F.seg(top, knee, leg_r * 1.05, leg_r * 0.92, mm[st['legs']], upper=False)
        F.ball(knee, leg_r * 0.92, mm[st['legs']], upper=False)
        F.seg(knee, ankle, leg_r * 0.92, leg_r * 0.8, mm[st['legs']], upper=False)
        # Boot: rounded box pointing forward.
        F.box(ankle + Vector((0, -0.04, -0.035 * (s / 1.2))), (leg_r * 2.3, leg_r * 3.6, 0.075 * (s / 1.2)), mm['boots'], upper=False, bevel=0.015)
        F.seg(ankle + Vector((0, 0, -0.02)), ankle + Vector((0, 0, 0.07 * (s / 1.2))), leg_r * 1.15, leg_r * 1.1, mm['boots'], upper=False)

    # Torso.
    waist = Vector((0, 0, hip_z - 0.02))
    chest = Vector((0, 0, sh_z - 0.02))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=16, radius1=hip_w * 1.6, radius2=sh_w * 0.95, depth=(chest - waist).length)
    bmesh.ops.scale(bm, vec=Vector((1.0, 0.7, 1.0)), verts=bm.verts)
    for vtx in bm.verts:
        # Rounded shoulders.
        if vtx.co.z > 0:
            vtx.co.x *= 1.0 - 0.06 * (vtx.co.z / ((chest - waist).length / 2))
    bmesh.ops.translate(bm, vec=(waist + chest) / 2, verts=bm.verts)
    bmesh.ops.transform(bm, matrix=F.T, verts=bm.verts)
    F.obj(bm, mm[st['tunic']])
    F.ball(chest + Vector((0, 0, 0.0)), sh_w * 0.95, mm[st['tunic']], sx=1.0, sy=0.72, sz=0.45)
    # Tabard front and back: panels wrapped around the torso's elliptical section.
    z0 = hip_z - 0.13 * s
    z1 = sh_z - 0.01
    for centre in (-math.pi / 2, math.pi / 2):
        tabard_panel(F, centre, math.radians(42), z0, z1, hip_w * 1.6, sh_w * 0.95, waist.z, chest.z, mm[st['tabard']])
    if st['emblem']:
        ez = (hip_z + sh_z) / 2 - 0.02 * s
        ef = max(0.0, min(1.0, (ez - waist.z) / (chest.z - waist.z)))
        er = hip_w * 1.6 + (sh_w * 0.95 - hip_w * 1.6) * ef + 0.012
        eagle(F, (0, -(er * 0.7) - 0.006, ez), 0.11 * (s / 1.2), mm['white'])
    # Belt and buckle.
    F.seg(Vector((0, 0, hip_z + 0.02)), Vector((0, 0, hip_z + 0.07)), hip_w * 1.75, hip_w * 1.75, mm['leather'])
    F.box((0, -hip_w * 1.2, hip_z + 0.045), (0.05, 0.02, 0.045), mm['gold'], bevel=0.004)
    if st['rags']:
        rng = random.Random(v)
        for k in range(6):
            a = -math.pi * 0.85 + k * math.pi * 0.34
            x = math.sin(a) * hip_w * 1.6
            y = -math.cos(a) * hip_w * 1.2
            F.box((x, y, hip_z - 0.06), (0.06, 0.015, 0.14 + rng.uniform(0, 0.05)), mm['rag' if k % 2 else 'red'], rot=Matrix.Rotation(-a, 3, 'Z'), bevel=0.003)
    if st['skulls']:
        for k in range(3):
            x = (k - 1) * hip_w * 1.1
            F.ball((x, -hip_w * 1.4, hip_z - 0.02), 0.035, mm['bone'], sy=0.9)
    if st['fur']:
        F.seg(Vector((0, 0.03, sh_z - 0.02)), Vector((0, 0.03, sh_z + 0.035)), sh_w * 1.08, sh_w * 0.8, mm['fur'])
    if st['scarf']:
        F.seg(Vector((0, -0.01, sh_z - 0.01)), Vector((0, -0.01, sh_z + 0.05)), sh_w * 0.62, sh_w * 0.5, mm[st['scarf']])

    # Arms.
    hands = {}
    for side, key in ((1, 'arm_l'), (-1, 'arm_r')):
        shoulder = Vector((side * sh_w * 0.98, 0, sh_z - 0.03))
        u, w = P[key]
        elbow = shoulder + u * 0.2 * (s / 1.2)
        hand = elbow + w * 0.18 * (s / 1.2)
        sleeve = mm[st['tunic']] if not (gob or orc) else skin
        F.ball(shoulder, limb_r * 1.25, mm[st['tunic']] if not orc else skin)
        F.seg(shoulder, elbow, limb_r * 1.1, limb_r * 0.95, sleeve)
        F.ball(elbow, limb_r * 0.95, sleeve)
        F.seg(elbow, hand, limb_r * 0.95, limb_r * 0.85, skin if (gob or orc) else mm['tunic'])
        if not (gob or orc):
            # Leather bracer.
            F.seg(elbow + (hand - elbow) * 0.45, hand - (hand - elbow) * 0.05, limb_r * 1.0, limb_r * 0.95, mm['leather'])
        F.ball(hand, limb_r * 1.05, skin if (gob or orc) else mm['leather'])
        hands[side] = (F.T @ hand, (F.T.to_3x3() @ w).normalized())
        if st['pauldrons']:
            col = mm['leather'] if st['pauldrons'] == 'leather' else mm['iron']
            F.ball(shoulder + Vector((side * 0.01, 0, 0.03)), limb_r * 1.9, col, sx=1.0, sy=1.0, sz=0.75)
            if st['pauldrons'] == 'spiked':
                for k in range(3):
                    base = shoulder + Vector((side * (0.02 + k * 0.02), (k - 1) * 0.04, 0.06))
                    F.cone(base, base + Vector((side * 0.05, (k - 1) * 0.02, 0.09)), 0.022, mm['bone'])

    # Head.
    head_c = Vector((0, -0.005, head_z))
    F.seg(Vector((0, 0, sh_z - 0.02)), head_c + Vector((0, 0, -head_r * 0.7)), limb_r * 1.2, limb_r * 1.1, skin)
    F.ball(head_c, head_r, skin, sx=1.0 if not orc else 1.08, sy=0.98, sz=1.0)
    face_y = -head_r * 0.92
    eye_m = mm['eye_y'] if (gob or orc) else mm['dark']
    for sx in (-1, 1):
        F.ball(head_c + Vector((sx * head_r * 0.36, face_y, head_r * 0.12)), head_r * 0.11, eye_m, sy=0.6)
    if gob:
        F.cone(head_c + Vector((0, face_y * 0.9, -head_r * 0.05)), head_c + Vector((0, face_y - head_r * 0.6, -head_r * 0.25)), head_r * 0.2, skin)
        for sx in (-1, 1):
            F.cone(head_c + Vector((sx * head_r * 0.8, 0.0, head_r * 0.1)), head_c + Vector((sx * head_r * 2.1, head_r * 0.35, head_r * 0.55)), head_r * 0.3, skin, segs=8)
    elif orc:
        F.box(head_c + Vector((0, face_y * 0.85, -head_r * 0.55)), (head_r * 1.3, head_r * 0.7, head_r * 0.55), skin, bevel=0.02)
        for sx in (-1, 1):
            F.cone(head_c + Vector((sx * head_r * 0.42, face_y * 1.05, -head_r * 0.62)), head_c + Vector((sx * head_r * 0.5, face_y * 1.15, -head_r * 0.15)), head_r * 0.12, mm['bone'], segs=8)
        F.box(head_c + Vector((0, face_y * 0.98, head_r * 0.32)), (head_r * 1.2, head_r * 0.25, head_r * 0.16), skin, bevel=0.01)
        for sx in (-1, 1):
            F.cone(head_c + Vector((sx * head_r * 0.85, 0.0, head_r * 0.15)), head_c + Vector((sx * head_r * 1.5, head_r * 0.2, head_r * 0.45)), head_r * 0.25, skin, segs=8)
    else:
        F.ball(head_c + Vector((0, face_y * 1.05, -head_r * 0.1)), head_r * 0.16, skin, sz=1.2)
        for sx in (-1, 1):
            F.ball(head_c + Vector((sx * head_r * 0.98, 0.0, 0.0)), head_r * 0.2, skin, sx=0.6)
        if st['beard']:
            F.ball(head_c + Vector((0, face_y * 0.55, -head_r * 0.55)), head_r * 0.75, mm['hair'], sx=1.0, sy=0.7, sz=0.6)
    hd = st['head']
    if hd == 'hair':
        F.ball(head_c + Vector((0, head_r * 0.12, head_r * 0.14)), head_r * 1.06, mm['hair'], sx=1.0, sy=1.0, sz=0.95)
    elif hd in ('hood', 'hood_g'):
        hm = mm['blue'] if hd == 'hood' else mm['hood_g']
        F.ball(head_c + Vector((0, head_r * 0.5, head_r * 0.18)), head_r * 1.1, hm, sx=1.08, sy=1.0, sz=1.05)
        F.cone(head_c + Vector((0, head_r * 0.9, head_r * 0.7)), head_c + Vector((0, head_r * 1.7, head_r * 1.0)), head_r * 0.45, hm)
        # Hood rim framing the face.
        F.seg(head_c + Vector((0, -head_r * 0.35, 0.0)), head_c + Vector((0, -head_r * 0.15, 0.0)), head_r * 1.08, head_r * 1.1, hm)
        # Mantle over the shoulders.
        F.seg(Vector((0, 0.01, sh_z - 0.04)), Vector((0, 0.01, sh_z + 0.06)), sh_w * 1.15, sh_w * 0.7, hm)
    elif hd == 'helmet_g':
        F.ball(head_c + Vector((0, 0.01, head_r * 0.2)), head_r * 1.08, mm['iron'], sz=0.85)
        F.box(head_c + Vector((0, face_y * 1.02, head_r * 0.02)), (head_r * 0.14, 0.02, head_r * 0.6), mm['iron'], bevel=0.004)
        for k in range(5):
            F.cone(head_c + Vector(((k - 2) * 0.012, 0.0, head_r * 1.05)), head_c + Vector(((k - 2) * 0.03, head_r * 0.6, head_r * 1.85)), 0.018, mm['red'], segs=6)
    elif hd == 'helmet_o':
        F.ball(head_c + Vector((0, 0.01, head_r * 0.22)), head_r * 1.12, mm['iron'], sz=0.88)
        F.seg(head_c + Vector((0, 0.01, head_r * 0.05)), head_c + Vector((0, 0.01, head_r * 0.12)), head_r * 1.2, head_r * 1.18, mm['iron'])
        for k in range(6):
            F.cone(head_c + Vector(((k - 2.5) * 0.012, 0.0, head_r * 1.1)), head_c + Vector(((k - 2.5) * 0.03, head_r * 0.8, head_r * 2.0)), 0.02, mm['red'], segs=6)
    elif hd == 'topknot':
        F.cone(head_c + Vector((0, 0.02, head_r * 0.85)), head_c + Vector((0, head_r * 0.5, head_r * 1.7)), head_r * 0.28, mm['hair'], segs=8)
        F.ball(head_c + Vector((0, 0.02, head_r * 0.9)), head_r * 0.3, mm['gold'], sz=0.5)
    if st['helmet'] == 'cap':
        F.ball(head_c + Vector((0, 0.01, head_r * 0.42)), head_r * 1.05, mm['steel'], sz=0.75)
        F.box(head_c + Vector((0, face_y * 1.03, head_r * 0.12)), (head_r * 0.14, 0.02, head_r * 0.45), mm['steel'], bevel=0.004)
    elif st['helmet'] == 'kettle':
        F.ball(head_c + Vector((0, 0.01, head_r * 0.48)), head_r * 1.02, mm['steel'], sz=0.8)
        F.seg(head_c + Vector((0, 0.01, head_r * 0.36)), head_c + Vector((0, 0.01, head_r * 0.44)), head_r * 1.6, head_r * 1.45, mm['steel'])

    # Quiver on the back.
    if st['quiver']:
        qa = Vector((sh_w * 0.4, sh_w * 0.85, hip_z + 0.05))
        qb = qa + V(-0.35, 0.25, 0.9) * 0.36 * (s / 1.2)
        F.seg(qa, qb, 0.05, 0.055, mm['leather'])
        for k in range(4):
            off = Vector(((k - 1.5) * 0.018, 0, 0))
            F.seg(qb + off, qb + off + V(-0.35, 0.25, 0.9) * 0.1, 0.008, 0.008, mm['wood'], segs=5)
            F.cone(qb + off + V(-0.35, 0.25, 0.9) * 0.1, qb + off + V(-0.35, 0.25, 0.9) * 0.15, 0.02, mm['white' if not gob else 'red'], segs=4)

    # Banner on the back (warlord).
    if st['banner']:
        base = Vector((0, sh_w * 0.9, hip_z))
        top = base + Vector((0, 0.05, 1.05 * s))
        F.seg(base, top, 0.02, 0.018, mm['wood'], segs=6)
        F.box(top + Vector((0.2, 0.02, -0.26)), (0.42, 0.015, 0.5), mm['red'], bevel=0.004)
        F.ball(top + Vector((0.2, 0.005, -0.24)), 0.1, mm['dark'], sy=0.2)
        F.ball(top, 0.035, mm['gold'])

    # Weapons and shields.
    hr, wr = hands[-1]
    hl, wl = hands[1]
    wd = P['weapon_dir']
    if wd is not None:
        wdw = (F.T.to_3x3() @ wd).normalized()
        weapon(F, st['weapon'], hr, hl, wdw, mm, s, pose)
    if st['shield']:
        # Shield on the left forearm, facing forward (and a little outward).
        fwd = (F.T.to_3x3() @ V(0.35, -1.0, 0.0)).normalized()
        if st['shield'] == 'kite':
            kite(F, hl + fwd * 0.03, fwd, mm, s)
        else:
            round_shield(F, hl + fwd * 0.04, fwd, mm, s)
    ob = join_anchor(F.parts, name)
    return ob, head_c


def tabard_panel(F, centre, half, z0, z1, r_bot, r_top, zb, zt, mat, depth=0.7, out=0.012, rows=6, cols=8):
    """A cloth panel following the torso cone (radius r_bot at zb to r_top at zt, Y squashed by depth)."""
    bm = bmesh.new()
    grid = []
    for i in range(rows + 1):
        z = z0 + (z1 - z0) * i / rows
        f = max(0.0, min(1.0, (z - zb) / max(1e-4, zt - zb)))
        r = r_bot + (r_top - r_bot) * f + out
        if z < zb:
            r = r_bot + out + (zb - z) * 0.25  # flare below the belt
        row = []
        for j in range(cols + 1):
            a = centre - half + 2 * half * j / cols
            row.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r * depth + math.sin(a) * out * 0.3, z)))
        grid.append(row)
    for i in range(rows):
        for j in range(cols):
            bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    sol = bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
    vs = [e for e in sol['geom'] if isinstance(e, bmesh.types.BMVert)]
    for vtx in vs:
        n = Vector((vtx.co.x, vtx.co.y, 0))
        if n.length > 0:
            vtx.co -= n.normalized() * 0.008
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.transform(bm, matrix=F.T, verts=bm.verts)
    return F.obj(bm, mat)


def join_anchor(parts, name):
    me = bpy.data.meshes.new(f'{name}_anchor')
    me.from_pydata([(0, 0, 0)], [], [])
    anchor = bpy.data.objects.new(f'{name}_anchor', me)
    R.asset_collection().objects.link(anchor)
    return join([anchor] + parts, name)


def eagle(F, pos, size, mat):
    pts = [(0, 1), (0.25, 0.65), (1.05, 1.0), (0.9, 0.5), (1.2, 0.45), (0.7, 0.05), (0.25, 0.05), (0.32, -0.6), (0, -1.0),
           (-0.32, -0.6), (-0.25, 0.05), (-0.7, 0.05), (-1.2, 0.45), (-0.9, 0.5), (-1.05, 1.0), (-0.25, 0.65)]
    pts = [(x * size * 0.5, z * size * 0.5) for x, z in pts]
    F.prism(pts, 0.008, mat, Matrix.Identity(3), pos)


def kite(F, center, fwd, mm, s):
    k = s / 1.2
    pts = [(-0.16, 0.2), (-0.08, 0.235), (0.0, 0.245), (0.08, 0.235), (0.16, 0.2), (0.15, 0.0), (0.1, -0.16), (0.0, -0.3), (-0.1, -0.16), (-0.15, 0.0)]
    pts = [(x * k, z * k) for x, z in pts]
    # Local frame: x across, y = thickness (forward), z up.
    yaxis = -fwd.normalized()
    zaxis = Vector((0, 0, 1))
    xaxis = yaxis.cross(zaxis).normalized()
    zaxis = xaxis.cross(yaxis).normalized()
    m3 = Matrix((xaxis, yaxis, zaxis)).transposed()
    c = center + Vector((0, 0, -0.02))
    F.prism([(x * 1.08, z * 1.06) for x, z in pts], 0.022, mm['iron'], m3, c + fwd * 0.004, upper=False)
    F.prism(pts, 0.03, mm['blue'], m3, c + fwd * 0.012, upper=False)
    eagle_pos = c + fwd * 0.03 + Vector((0, 0, 0.03 * k))
    pe = [(0, 1), (0.25, 0.65), (1.05, 1.0), (0.9, 0.5), (1.2, 0.45), (0.7, 0.05), (0.25, 0.05), (0.32, -0.6), (0, -1.0),
          (-0.32, -0.6), (-0.25, 0.05), (-0.7, 0.05), (-1.2, 0.45), (-0.9, 0.5), (-1.05, 1.0), (-0.25, 0.65)]
    pe = [(x * 0.1 * k, z * 0.1 * k) for x, z in pe]
    F.prism(pe, 0.01, mm['white'], m3, eagle_pos, upper=False)


def round_shield(F, center, fwd, mm, s):
    k = s / 1.2
    F.seg(center - fwd * 0.015, center + fwd * 0.015, 0.2 * k, 0.2 * k, mm['red'], upper=False, segs=20)
    F.seg(center - fwd * 0.02, center + fwd * 0.005, 0.215 * k, 0.215 * k, mm['iron'], upper=False, segs=20)
    F.ball(center + fwd * 0.02, 0.045 * k, mm['steel'], upper=False)
    yaxis = -fwd.normalized()
    zaxis = Vector((0, 0, 1))
    xaxis = yaxis.cross(zaxis).normalized()
    zaxis = xaxis.cross(yaxis).normalized()
    m3 = Matrix((xaxis, yaxis, zaxis)).transposed()
    star = []
    for i in range(8):
        a = i * math.pi / 4
        r = 0.17 * k if i % 2 == 0 else 0.05 * k
        star.append((math.cos(a) * r, math.sin(a) * r))
    F.prism(star, 0.008, mm['dark'], m3, center + fwd * 0.018, upper=False)


def weapon(F, kind, hr, hl, d, mm, s, pose):
    k = s / 1.2
    side = Vector((1, 0, 0))
    if kind == 'sword':
        tip = hr + d * 0.52 * k
        flat = d.cross(Vector((0, 0, 1)))
        m3 = frame(d, flat if flat.length > 0.1 else side)
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector((0.045 * k, 0.012, 0.44 * k)), verts=bm.verts)
        for vtx in bm.verts:
            if vtx.co.z > 0.2 * k:
                vtx.co.x *= 0.15
        place(bm, m3, hr + d * 0.29 * k)
        F.obj(bm, mm['steel'], smooth=False)
        F.box(hr + d * 0.065 * k, (0.17 * k, 0.03, 0.03), mm['gold'], rot=m3, upper=False, bevel=0.005)
        F.seg(hr - d * 0.06 * k, hr + d * 0.05 * k, 0.018, 0.018, mm['leather'], upper=False, segs=6)
        F.ball(hr - d * 0.08 * k, 0.03, mm['gold'], upper=False)
    elif kind in ('spear', 'gspear'):
        L = (1.65 if kind == 'spear' else 1.25) * k
        butt = hr - d * L * 0.32
        top = hr + d * L * 0.68
        F.seg(butt, top, 0.018, 0.016, mm['wood'], upper=False, segs=7)
        m3 = frame(d, Vector((1, 0, 0)) if abs(d.x) < 0.9 else Vector((0, 1, 0)))
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=4, radius1=0.05 * k, radius2=0.0, depth=0.2 * k)
        bmesh.ops.scale(bm, vec=Vector((1.0, 0.3, 1.0)), verts=bm.verts)
        place(bm, m3, top + d * 0.1 * k)
        F.obj(bm, mm['steel'], smooth=False)
        if kind == 'gspear':
            F.box(top - d * 0.03, (0.05, 0.012, 0.16), mm['rag'], rot=m3, upper=False, bevel=0.003)
        else:
            F.seg(top - d * 0.01, top + d * 0.02, 0.026, 0.026, mm['blue'], upper=False, segs=8)
    elif kind == 'crossbow':
        k = k * 1.45
        front = hl + d * 0.12 * k
        back = hr - d * 0.08 * k
        F.seg(back, front + d * 0.06 * k, 0.03, 0.026, mm['wood'], upper=False, segs=6)
        across = d.cross(Vector((0, 0, 1))).normalized()
        if across.length < 0.1:
            across = Vector((1, 0, 0))
        tipa = front + d * 0.05 * k + across * 0.26 * k - d * 0.08 * k
        tipb = front + d * 0.05 * k - across * 0.26 * k - d * 0.08 * k
        mid = front + d * 0.07 * k
        F.seg(tipa, mid, 0.014, 0.02, mm['wood'], upper=False, segs=6)
        F.seg(mid, tipb, 0.02, 0.014, mm['wood'], upper=False, segs=6)
        F.seg(tipa, back + d * 0.12 * k, 0.004, 0.004, mm['white'], upper=False, segs=4)
        F.seg(tipb, back + d * 0.12 * k, 0.004, 0.004, mm['white'], upper=False, segs=4)
        if pose == 'idle' or pose == 'atk':
            F.seg(back + d * 0.12 * k, front + d * 0.1 * k, 0.007, 0.007, mm['wood'], upper=False, segs=4)
            F.cone(front + d * 0.1 * k, front + d * 0.15 * k, 0.012, mm['steel'], upper=False, segs=4)
    elif kind == 'bow':
        up = d
        across = Vector((0, -1, 0)).cross(up).normalized() if abs(up.y) < 0.9 else Vector((1, 0, 0))
        n = 8
        pts = []
        for i in range(n + 1):
            t = i / n - 0.5
            bend = (1 - (2 * t) ** 2) * 0.08 * k
            pts.append(hl + up * t * 1.0 * k - Vector((0, 1, 0)) * bend * 1.4 * (1 if pose != 'atk' else 1.4))
        for i in range(n):
            F.seg(pts[i], pts[i + 1], 0.02, 0.02, mm['wood'], upper=False, segs=6)
        pull = hr if pose == 'atk' else hl + Vector((0, 0.05, 0))
        F.seg(pts[0], pull, 0.003, 0.003, mm['white'], upper=False, segs=3)
        F.seg(pull, pts[-1], 0.003, 0.003, mm['white'], upper=False, segs=3)
        if pose == 'atk':
            F.seg(hr, hl - Vector((0, 0.12, 0)), 0.006, 0.006, mm['wood'], upper=False, segs=4)
            F.cone(hl - Vector((0, 0.12, 0)), hl - Vector((0, 0.18, 0)), 0.012, mm['steel'], upper=False, segs=4)
    elif kind == 'cleaver':
        m3 = frame(d, Vector((1, 0, 0)) if abs(d.x) < 0.9 else Vector((0, 1, 0)))
        bm = bmesh.new()
        pts = [(-0.02, 0.06), (0.06, 0.07), (0.1, 0.42), (0.02, 0.5), (-0.05, 0.46)]
        f0 = [bm.verts.new((x * k, -0.008, z * k)) for x, z in pts]
        f1 = [bm.verts.new((x * k, 0.008, z * k)) for x, z in pts]
        bm.faces.new(f0)
        bm.faces.new(list(reversed(f1)))
        for i in range(len(pts)):
            j = (i + 1) % len(pts)
            bm.faces.new((f0[i], f0[j], f1[j], f1[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        place(bm, m3, hr)
        F.obj(bm, mm['steel'], smooth=False)
        F.seg(hr - d * 0.08 * k, hr + d * 0.07 * k, 0.02, 0.02, mm['leather'], upper=False, segs=6)
    elif kind == 'mace':
        k = k * 1.3
        top = hr + d * 0.5 * k
        F.seg(hr - d * 0.1 * k, top, 0.022, 0.022, mm['wood'], upper=False, segs=6)
        F.ball(top + d * 0.05 * k, 0.085 * k, mm['iron'], upper=False)
        for i in range(8):
            a = i * math.tau / 8
            dd = Vector((math.cos(a), math.sin(a), (0.6 if i % 2 else -0.6))).normalized()
            F.cone(top + d * 0.05 * k + dd * 0.07 * k, top + d * 0.05 * k + dd * 0.15 * k, 0.025, mm['steel'], upper=False, segs=5)


# ---------------------------------------------------------------- rendering

FACINGS = {'f': 0.0, 'fr': math.pi / 2, 'b': math.pi, 'bl': -math.pi / 2}


def render_unit(t, pose, facing, v, outline=2.4):
    R.clear_assets()
    ob, head = build(t, pose, v, f'{t}_{pose}_{facing}')
    st = style(t, v)
    anchor = None
    if pose == 'dead':
        # Lie on the back, then centre the body (not the feet) on the tile.
        yaw = 0.6
        ob.rotation_euler = (-math.pi / 2 + 0.05, 0, yaw)
        half = 0.5 * 1.2 * st['h']
        ob.location = (math.sin(yaw) * half, -math.cos(yaw) * half, 0.11 * st['bulk'] * st['h'])
        anchor = Vector((0, 0, 0))
    else:
        ob.rotation_euler = (0, 0, FACINGS[facing])
    scn = R.scene()
    ls = scn.view_layers[0].freestyle_settings.linesets[0].linestyle
    ls.thickness = outline
    ls.color = (0.12, 0.07, 0.04)
    key = f'{t}_dead' if pose == 'dead' else f'{t}_{pose}_{facing}'
    e = R.render_asset(ob, key, v, pad=8, shadow=False, anchor_world=anchor)
    return e


PORTRAIT_SIZE = {'goblin_spear': 0.6, 'goblin_archer': 0.6, 'orc_warrior': 0.66, 'orc_warlord': 0.8}


def render_portrait(t, v, px=256):
    R.clear_assets()
    ob, head = build(t, 'idle', v, f'{t}_portrait')
    # Turn the face toward the camera, three-quarter view.
    ob.rotation_euler = (0, 0, math.radians(32))
    bpy.context.view_layer.update()
    hw = ob.matrix_world @ (head + Vector((0, 0, -0.06)))
    return R.render_portrait(ob, f'portrait_{t}', v, hw, PORTRAIT_SIZE.get(t, 0.52), px)
