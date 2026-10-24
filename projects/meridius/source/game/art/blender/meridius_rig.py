"""Meridius sprite rig for Blender 5.x.

Builds stylised props procedurally and renders them as isometric sprites whose
projection matches the game exactly (2:1 dimetric, 90.51 world px per metre).
Game coordinates (x, y) map to Blender (X, -Y); the game's light comes from the
upper left of the screen, which is Blender -X, so shadows fall to +X.

Usage inside Blender:
    import sys, importlib; sys.path.insert(0, r'<this folder>')
    import meridius_rig as R; importlib.reload(R)
    R.setup_scene(); obj = R.pine(1); R.render_asset(obj, 'tree_pine', 0)
"""
import json
import math
import os
import random

import bmesh
import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Matrix, Vector

GAME_PPM = 90.51  # world pixels per metre in the game's projection
PPM = 181.0  # sprite pixels per metre (2x for crisp downscaling)
GAME_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT_DIR = os.path.join(GAME_DIR, 'art', 'raw', 'blender')
MANIFEST = os.path.join(GAME_DIR, 'public', 'assets', 'manifest.json')
SCENE = 'MeridiusSprites'
INK = (0.16, 0.10, 0.06)


# ---------------------------------------------------------------- scene


def scene():
    return bpy.data.scenes[SCENE]


def setup_scene(samples=96):
    scn = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
    bpy.context.window.scene = scn
    scn.render.engine = 'CYCLES'
    scn.cycles.device = 'GPU'
    scn.cycles.samples = samples
    scn.cycles.use_denoising = True
    scn.render.film_transparent = True
    scn.render.image_settings.file_format = 'PNG'
    scn.render.image_settings.color_mode = 'RGBA'
    scn.render.resolution_percentage = 100
    try:
        scn.view_settings.view_transform = 'Standard'
    except TypeError:
        pass
    scn.view_settings.exposure = -0.55
    # World: cool sky fill so shadows read blue-green, as in the references.
    world = bpy.data.worlds.get('MeridiusSky') or bpy.data.worlds.new('MeridiusSky')
    scn.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs[0].default_value = (0.62, 0.74, 0.92, 1)
    bg.inputs[1].default_value = 0.8
    coll = rig_collection()
    # Camera.
    cam = bpy.data.objects.get('SpriteCam')
    if not cam:
        cam = bpy.data.objects.new('SpriteCam', bpy.data.cameras.new('SpriteCam'))
        coll.objects.link(cam)
    cam.data.type = 'ORTHO'
    cam.rotation_euler = (math.radians(60), 0, math.radians(45))
    cam.data.clip_start = 0.1
    cam.data.clip_end = 200
    scn.camera = cam
    # Sun from the upper left of the screen (Blender -X), warm.
    sun = bpy.data.objects.get('SpriteSun')
    if not sun:
        sun = bpy.data.objects.new('SpriteSun', bpy.data.lights.new('SpriteSun', 'SUN'))
        coll.objects.link(sun)
    sun.data.energy = 3.4
    sun.data.color = (1.0, 0.93, 0.80)
    sun.data.angle = math.radians(6)
    sun.rotation_euler = (math.radians(8), math.radians(-42), 0)
    # Shadow catcher ground.
    ground = bpy.data.objects.get('SpriteGround')
    if not ground:
        bm = bmesh.new()
        bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=30)
        me = bpy.data.meshes.new('SpriteGround')
        bm.to_mesh(me)
        bm.free()
        ground = bpy.data.objects.new('SpriteGround', me)
        coll.objects.link(ground)
    ground.is_shadow_catcher = True
    # Outlines.
    scn.render.use_freestyle = True
    scn.render.line_thickness_mode = 'ABSOLUTE'
    scn.render.line_thickness = 1.0
    vl = scn.view_layers[0]
    vl.use_freestyle = True
    fs = vl.freestyle_settings
    fs.crease_angle = math.radians(128)
    ls = fs.linesets[0] if len(fs.linesets) else fs.linesets.new('Outline')
    ls.select_by_visibility = True
    ls.select_by_edge_types = True
    ls.select_silhouette = True
    ls.select_border = False
    ls.select_crease = False
    ls.select_external_contour = True
    ls.linestyle.color = (0.10, 0.12, 0.05)
    ls.linestyle.thickness = 1.5
    ls.linestyle.alpha = 0.9
    os.makedirs(OUT_DIR, exist_ok=True)
    return scn


def rig_collection():
    scn = bpy.data.scenes[SCENE]
    coll = bpy.data.collections.get('SpriteRig')
    if not coll:
        coll = bpy.data.collections.new('SpriteRig')
        scn.collection.children.link(coll)
    return coll


def asset_collection():
    scn = bpy.data.scenes[SCENE]
    coll = bpy.data.collections.get('SpriteAssets')
    if not coll:
        coll = bpy.data.collections.new('SpriteAssets')
        scn.collection.children.link(coll)
    return coll


def clear_assets():
    coll = asset_collection()
    for o in list(coll.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        if m.users == 0:
            bpy.data.meshes.remove(m)


# ---------------------------------------------------------------- materials


def _ramp_mat(name, colors, noise_scale=6.0, rough=0.85, moss=None, emission=None, height_dark=0.0, height_span=3.0):
    """Principled material with noise-driven colour variation (painterly)."""
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Roughness'].default_value = rough
    tex = nt.nodes.new('ShaderNodeTexCoord')
    noise = nt.nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = noise_scale
    noise.inputs['Detail'].default_value = 4
    nt.links.new(tex.outputs['Object'], noise.inputs['Vector'])
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    el = ramp.color_ramp.elements
    el[0].position = 0.3
    el[0].color = (*colors[0], 1)
    el[1].position = 0.72
    el[1].color = (*colors[-1], 1)
    if len(colors) > 2:
        mid = el.new(0.5)
        mid.color = (*colors[1], 1)
    nt.links.new(noise.outputs['Fac'], ramp.inputs['Fac'])
    col = ramp.outputs['Color']
    if moss:
        geo = nt.nodes.new('ShaderNodeNewGeometry')
        sep = nt.nodes.new('ShaderNodeSeparateXYZ')
        nt.links.new(geo.outputs['Normal'], sep.inputs['Vector'])
        mr = nt.nodes.new('ShaderNodeMapRange')
        mr.inputs['From Min'].default_value = 0.55
        mr.inputs['From Max'].default_value = 0.85
        nt.links.new(sep.outputs['Z'], mr.inputs['Value'])
        n2 = nt.nodes.new('ShaderNodeTexNoise')
        n2.inputs['Scale'].default_value = 9
        mul = nt.nodes.new('ShaderNodeMath')
        mul.operation = 'MULTIPLY'
        nt.links.new(mr.outputs['Result'], mul.inputs[0])
        nt.links.new(n2.outputs['Fac'], mul.inputs[1])
        gt = nt.nodes.new('ShaderNodeMath')
        gt.operation = 'GREATER_THAN'
        gt.inputs[1].default_value = 0.28
        nt.links.new(mul.outputs[0], gt.inputs[0])
        mix = nt.nodes.new('ShaderNodeMix')
        mix.data_type = 'RGBA'
        nt.links.new(gt.outputs[0], mix.inputs['Factor'])
        nt.links.new(col, mix.inputs['A'])
        mix.inputs['B'].default_value = (*moss, 1)
        col = mix.outputs['Result']
    if height_dark > 0:
        # Darken toward the base (ambient occlusion look).
        tc = nt.nodes.new('ShaderNodeTexCoord')
        sep2 = nt.nodes.new('ShaderNodeSeparateXYZ')
        nt.links.new(tc.outputs['Object'], sep2.inputs['Vector'])
        mr2 = nt.nodes.new('ShaderNodeMapRange')
        mr2.inputs['From Min'].default_value = 0.0
        mr2.inputs['From Max'].default_value = height_span
        mr2.inputs['To Min'].default_value = 1 - height_dark
        mr2.inputs['To Max'].default_value = 1.0
        nt.links.new(sep2.outputs['Z'], mr2.inputs['Value'])
        mix2 = nt.nodes.new('ShaderNodeMix')
        mix2.data_type = 'RGBA'
        mix2.blend_type = 'MULTIPLY'
        mix2.inputs['Factor'].default_value = 1.0
        comb = nt.nodes.new('ShaderNodeCombineXYZ')
        for k in ('X', 'Y', 'Z'):
            nt.links.new(mr2.outputs['Result'], comb.inputs[k])
        nt.links.new(col, mix2.inputs['A'])
        nt.links.new(comb.outputs['Vector'], mix2.inputs['B'])
        col = mix2.outputs['Result']
    nt.links.new(col, bsdf.inputs['Base Color'])
    if emission:
        bsdf.inputs['Emission Color'].default_value = (*emission, 1)
        bsdf.inputs['Emission Strength'].default_value = 6.0
    return m


def mats():
    return {
        'pine_d': _ramp_mat('M_PineD', [(0.015, 0.07, 0.03), (0.03, 0.11, 0.04)], 14),
        'pine_m': _ramp_mat('M_PineM', [(0.03, 0.13, 0.04), (0.05, 0.19, 0.05)], 14),
        'pine_l': _ramp_mat('M_PineL', [(0.08, 0.24, 0.05), (0.16, 0.34, 0.06)], 14),
        'oak_d': _ramp_mat('M_OakD', [(0.04, 0.12, 0.02), (0.07, 0.18, 0.03)], 14),
        'oak_m': _ramp_mat('M_OakM', [(0.10, 0.27, 0.03), (0.16, 0.35, 0.04)], 14),
        'oak_l': _ramp_mat('M_OakL', [(0.30, 0.48, 0.06), (0.46, 0.58, 0.10)], 14),
        'pine': _ramp_mat('M_Pine', [(0.04, 0.13, 0.05), (0.08, 0.22, 0.07), (0.20, 0.34, 0.10)], 6, height_dark=0.45, height_span=4.2),
        'oak': _ramp_mat('M_Oak', [(0.10, 0.24, 0.04), (0.24, 0.42, 0.07), (0.52, 0.62, 0.16)], 4, height_dark=0.45, height_span=3.6),
        'bush': _ramp_mat('M_Bush', [(0.10, 0.28, 0.05), (0.22, 0.45, 0.08), (0.45, 0.62, 0.16)], 8, height_dark=0.3, height_span=0.9),
        'bark': _ramp_mat('M_Bark', [(0.16, 0.09, 0.04), (0.30, 0.18, 0.08)], 18),
        'stone': _ramp_mat('M_Stone', [(0.17, 0.17, 0.16), (0.27, 0.27, 0.25), (0.38, 0.37, 0.33)], 4, rough=0.9, moss=(0.12, 0.22, 0.04)),
        'wood': _ramp_mat('M_Wood', [(0.25, 0.14, 0.06), (0.45, 0.28, 0.12)], 14),
        'hide': _ramp_mat('M_Hide', [(0.30, 0.18, 0.10), (0.45, 0.30, 0.17)], 9),
        'red': _ramp_mat('M_Red', [(0.38, 0.05, 0.03), (0.62, 0.10, 0.06)], 10),
        'bone': _ramp_mat('M_Bone', [(0.72, 0.68, 0.58), (0.92, 0.88, 0.78)], 9),
        'ember': _ramp_mat('M_Ember', [(0.9, 0.35, 0.05), (1.0, 0.75, 0.2)], 12, emission=(1.0, 0.45, 0.08)),
        'canvas': _ramp_mat('M_Canvas', [(0.70, 0.64, 0.50), (0.86, 0.81, 0.68)], 8),
        'blue': _ramp_mat('M_Blue', [(0.06, 0.13, 0.42), (0.12, 0.25, 0.66)], 9),
        'roof_red': _ramp_mat('M_RoofRed', [(0.32, 0.08, 0.05), (0.52, 0.16, 0.09)], 12),
        'thatch': _ramp_mat('M_Thatch', [(0.48, 0.38, 0.18), (0.70, 0.58, 0.30)], 16),
        'plaster': _ramp_mat('M_Plaster', [(0.80, 0.75, 0.62), (0.92, 0.88, 0.76)], 6),
        'iron': _ramp_mat('M_Iron', [(0.22, 0.23, 0.25), (0.40, 0.42, 0.45)], 12, rough=0.5),
    }


# ---------------------------------------------------------------- mesh helpers


def _obj_from_bm(bm, name, mat, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    asset_collection().objects.link(ob)
    return ob


def _jitter(bm, rng, amt, keep_bottom=False):
    for v in bm.verts:
        if keep_bottom and v.co.z < 0.02:
            continue
        v.co += Vector((rng.uniform(-amt, amt), rng.uniform(-amt, amt), rng.uniform(-amt, amt) * 0.6))


def _blob(rng, center, radius, mat, name, squash=0.85, subdiv=2, rough=0.22):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    for v in bm.verts:
        n = v.co.normalized()
        bump = 1 + rough * (math.sin(n.x * 7 + rng.random() * 6) * 0.5 + math.cos(n.y * 9 + n.z * 5) * 0.5) + rng.uniform(-rough, rough) * 0.5
        v.co = Vector((v.co.x * bump, v.co.y * bump, v.co.z * bump * squash)) + Vector(center)
    return _obj_from_bm(bm, name, mat)


def _cyl(p0, p1, r0, r1, mat, name, segs=8, smooth=True):
    bm = bmesh.new()
    d = (Vector(p1) - Vector(p0))
    length = d.length
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r0, radius2=r1, depth=length)
    # Align +Z to d.
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=rot, verts=bm.verts)
    mid = (Vector(p0) + Vector(p1)) / 2
    bmesh.ops.translate(bm, vec=mid, verts=bm.verts)
    return _obj_from_bm(bm, name, mat, smooth)


def _box(center, size, mat, name, rot_z=0.0, bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if rot_z:
        bmesh.ops.rotate(bm, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(rot_z, 3, 'Z'), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    if bevel:
        bmesh.ops.bevel(bm, geom=bm.verts[:] + bm.edges[:], offset=bevel, segments=1, affect='EDGES')
    return _obj_from_bm(bm, name, mat, smooth=False)


def join(objs, name):
    """Join objects into one (keeps materials)."""
    objs = [o for o in objs if o]
    base = objs[0]
    with bpy.context.temp_override(active_object=base, selected_editable_objects=objs, selected_objects=objs, object=base):
        bpy.ops.object.join()
    base.name = name
    return base


# ---------------------------------------------------------------- props


def _frond(rng, length, width, mat, name, a, z, droop):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=7, radius1=width, radius2=0.015, depth=length)
    bmesh.ops.rotate(bm, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.radians(90 + droop), 3, 'Y'), verts=bm.verts)
    bmesh.ops.scale(bm, vec=Vector((1, 1.7, 0.5)), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector((length * 0.48, 0, 0)), verts=bm.verts)
    bmesh.ops.rotate(bm, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(a, 3, 'Z'), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector((0, 0, z)), verts=bm.verts)
    _jitter(bm, rng, width * 0.12)
    return _obj_from_bm(bm, name, mat)


def pine(seed, height=None):
    """Layered pine: rings of flattened, drooping fronds around a dark core."""
    rng = random.Random(seed)
    M = mats()
    h = height or rng.uniform(3.8, 4.8)
    parts = [_cyl((0, 0, 0), (0, 0, h * 0.5), 0.12, 0.08, M['bark'], 'trunk')]
    tiers = rng.randint(7, 8)
    for i in range(tiers):
        t = i / (tiers - 1)
        z = h * (0.16 + 0.76 * t)
        reach = (1.0 - 0.85 * t) * h * 0.27 + 0.1
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=10, radius1=reach * 0.55, radius2=0.02, depth=h * 0.18)
        bmesh.ops.translate(bm, vec=Vector((0, 0, z + h * 0.05)), verts=bm.verts)
        parts.append(_obj_from_bm(bm, f'core{i}', M['pine_d']))
        n = max(6, int(14 - 8 * t))
        for k in range(n):
            a = k * math.tau / n + rng.uniform(-0.2, 0.2) + i * 0.5
            facing = math.cos(a - math.radians(200))  # brighter toward the sun side
            mat = M['pine_l'] if (facing > 0.3 and rng.random() < 0.75) or (t > 0.8 and rng.random() < 0.5) else (M['pine_m'] if rng.random() < 0.7 else M['pine_d'])
            parts.append(_frond(rng, reach * rng.uniform(0.8, 1.05), 0.17 + 0.1 * (1 - t), mat, f'f{i}_{k}', a, z + rng.uniform(-0.04, 0.06), 26 + rng.uniform(0, 14)))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=7, radius1=0.13, radius2=0.0, depth=h * 0.18)
    bmesh.ops.translate(bm, vec=Vector((0, 0, h * 1.01)), verts=bm.verts)
    parts.append(_obj_from_bm(bm, 'top', M['pine_l']))
    ob = join(parts, f'pine_{seed}')
    ob.rotation_euler.z = rng.uniform(0, math.tau)
    return ob


def oak(seed):
    """Broadleaf tree: a trunk with branches and a canopy of many small leaf clumps."""
    rng = random.Random(seed)
    M = mats()
    h = rng.uniform(1.3, 1.7)
    parts = [_cyl((0, 0, 0), (0.05, 0.02, h + 0.2), 0.2, 0.12, M['bark'], 'trunk')]
    for i in range(4):
        a = rng.uniform(0, math.tau)
        parts.append(_cyl((0, 0, h * 0.7), (math.cos(a) * 0.6, math.sin(a) * 0.6, h + 0.5), 0.09, 0.04, M['bark'], f'branch{i}'))
    R0 = rng.uniform(1.05, 1.3)
    cz = h + 0.95
    parts.append(_blob(rng, (0, 0, cz), R0 * 0.85, M['oak_d'], 'core', squash=0.78, subdiv=2, rough=0.15))
    n = rng.randint(34, 44)
    for i in range(n):
        # Points on an upper-weighted ellipsoid shell.
        u = rng.uniform(-0.35, 1.0)
        a = rng.uniform(0, math.tau)
        rr = math.sqrt(max(0.0, 1 - u * u))
        p = Vector((math.cos(a) * rr * R0, math.sin(a) * rr * R0, u * R0 * 0.78 + cz))
        lit = (u > 0.35) or (math.cos(a - math.radians(200)) > 0.4 and u > -0.1)
        mat = M['oak_l'] if lit and rng.random() < 0.8 else (M['oak_m'] if rng.random() < 0.65 else M['oak_d'])
        parts.append(_blob(rng, p, rng.uniform(0.26, 0.42), mat, f'leaf{i}', squash=0.82, subdiv=2, rough=0.18))
    return join(parts, f'oak_{seed}')


def bush(seed, flowers=True):
    rng = random.Random(seed)
    M = mats()
    parts = []
    for i in range(rng.randint(8, 11)):
        a = rng.uniform(0, math.tau)
        rr = rng.uniform(0, 0.32)
        parts.append(_blob(rng, (math.cos(a) * rr, math.sin(a) * rr, 0.22 + rng.uniform(0, 0.15)), rng.uniform(0.2, 0.3), M['oak_l'] if i % 3 == 0 else M['oak_m'], f'b{i}', squash=0.8, subdiv=2))
    if flowers:
        fm = _ramp_mat(f'M_Flower{seed % 3}', [[(0.95, 0.85, 0.35), (0.98, 0.95, 0.85)], [(0.95, 0.95, 0.9), (1, 1, 1)], [(0.62, 0.45, 0.85), (0.75, 0.6, 0.95)]][seed % 3], 20, rough=0.6)
        for i in range(rng.randint(5, 9)):
            a = rng.uniform(0, math.tau)
            rr = rng.uniform(0.15, 0.42)
            parts.append(_blob(rng, (math.cos(a) * rr, math.sin(a) * rr, 0.35 + rng.uniform(0, 0.25)), 0.028, fm, f'f{i}', subdiv=1, rough=0.1))
    return join(parts, f'bush_{seed}')


def rock(seed, size=1.0):
    rng = random.Random(seed)
    M = mats()
    parts = []
    count = 3 if size > 0.8 else 2
    for i in range(count):
        bm = bmesh.new()
        r = size * rng.uniform(0.32, 0.5) * (1 if i == 0 else 0.7)
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=r)
        sx, sy, sz = rng.uniform(0.9, 1.3), rng.uniform(0.8, 1.1), rng.uniform(0.6, 0.95)
        for v in bm.verts:
            v.co = Vector((v.co.x * sx, v.co.y * sy, max(-0.02, v.co.z * sz)))
        _jitter(bm, rng, r * 0.18)
        off = Vector((rng.uniform(-0.35, 0.35), rng.uniform(-0.3, 0.3), r * sz * 0.55)) * (0 if i == 0 else 1)
        bmesh.ops.translate(bm, vec=off + Vector((0, 0, r * sz * 0.5 if i == 0 else 0)), verts=bm.verts)
        parts.append(_obj_from_bm(bm, f'r{i}', M['stone'], smooth=False))
    return join(parts, f'rock_{seed}')


def stump(seed):
    rng = random.Random(seed)
    M = mats()
    t = _cyl((0, 0, 0), (0, 0, 0.32), 0.26, 0.22, M['bark'], 'stump', segs=10)
    top = _cyl((0, 0, 0.32), (0, 0, 0.335), 0.22, 0.21, _ramp_mat('M_Cut', [(0.62, 0.45, 0.25), (0.78, 0.6, 0.35)], 30), 'cut', segs=10)
    return join([t, top], f'stump_{seed}')


def wall_ruin(seed, axis='x'):
    rng = random.Random(seed)
    M = mats()
    parts = []
    courses = rng.randint(3, 5)
    length = 1.0
    for c in range(courses):
        z = 0.11 + c * 0.2
        n = 3
        for b in range(n):
            if c >= 2 and rng.random() < 0.35 + c * 0.1:
                continue
            bl = length / n * rng.uniform(0.85, 1.0)
            off = -length / 2 + (b + 0.5) * length / n + (0.08 if c % 2 else -0.04)
            size = (bl, 0.36, 0.19) if axis == 'x' else (0.36, bl, 0.19)
            center = (off, rng.uniform(-0.02, 0.02), z) if axis == 'x' else (rng.uniform(-0.02, 0.02), off, z)
            parts.append(_box(center, size, M['stone'], f's{c}{b}', rot_z=rng.uniform(-0.05, 0.05), bevel=0.025))
    # Rubble at the foot.
    for i in range(3):
        parts.append(_box((rng.uniform(-0.5, 0.5), rng.uniform(0.25, 0.4) * rng.choice([-1, 1]), 0.05), (0.16, 0.14, 0.1), M['stone'], f'rub{i}', rot_z=rng.uniform(0, 3), bevel=0.02))
    return join(parts, f'wall_{axis}_{seed}')


def wall_high(seed):
    """Broken round tower: a hollow stone drum with a jagged top and a doorway."""
    rng = random.Random(seed)
    M = mats()
    parts = []
    r_out, ring = 0.62, 0.2
    courses = 12
    for c in range(courses):
        z = 0.1 + c * 0.19
        n = 9
        for k in range(n):
            a = (k + 0.5 * (c % 2)) * math.tau / n
            # Broken crown: higher courses lose stones on the far side.
            top_loss = (c - 5) / 7.0 * (0.5 + 0.5 * math.cos(a - math.radians(130)))
            if c > 5 and rng.random() < top_loss:
                continue
            # Doorway facing the camera's lower-left side (-Y).
            if c < 5 and abs(((a - math.radians(250)) + math.pi) % math.tau - math.pi) < 0.35:
                continue
            cx = math.cos(a) * (r_out - ring / 2)
            cy = math.sin(a) * (r_out - ring / 2)
            bl = math.tau * r_out / n * 0.94
            parts.append(_box((cx, cy, z), (ring, bl, 0.18), M['stone'], f'tb{c}_{k}', rot_z=a, bevel=0.022))
    for i in range(5):
        a = rng.uniform(0, math.tau)
        rr = rng.uniform(0.75, 1.05)
        parts.append(_box((math.cos(a) * rr, math.sin(a) * rr, 0.06), (0.2, 0.16, 0.12), M['stone'], f'rub{i}', rot_z=rng.uniform(0, 3), bevel=0.02))
    return join(parts, f'tower_{seed}')


def fence(seed, axis='x'):
    rng = random.Random(seed)
    M = mats()
    parts = []
    for i, p in enumerate((-0.45, 0.0, 0.45)):
        pos = (p, 0, 0) if axis == 'x' else (0, p, 0)
        top = (pos[0] + rng.uniform(-0.04, 0.04), pos[1] + rng.uniform(-0.04, 0.04), 0.62 + rng.uniform(-0.05, 0.05))
        parts.append(_cyl(pos, top, 0.05, 0.045, M['wood'], f'post{i}', segs=6, smooth=False))
    for j, z in enumerate((0.26, 0.5)):
        a = (-0.52, 0, z) if axis == 'x' else (0, -0.52, z)
        b = (0.52, 0, z + rng.uniform(-0.05, 0.05)) if axis == 'x' else (0, 0.52, z + rng.uniform(-0.05, 0.05))
        parts.append(_cyl(a, b, 0.035, 0.035, M['wood'], f'rail{j}', segs=6, smooth=False))
    return join(parts, f'fence_{axis}_{seed}')


def tent(seed):
    rng = random.Random(seed)
    M = mats()
    parts = []
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=7, radius1=0.95, radius2=0.08, depth=1.5)
    for v in bm.verts:
        if v.co.z < 0:
            v.co.x *= 1 + rng.uniform(-0.08, 0.08)
            v.co.y *= 1 + rng.uniform(-0.08, 0.08)
    bmesh.ops.translate(bm, vec=Vector((0, 0, 0.75)), verts=bm.verts)
    parts.append(_obj_from_bm(bm, 'hide', M['hide'], smooth=False))
    for i in range(4):
        a = i * math.tau / 4 + 0.4
        parts.append(_cyl((math.cos(a) * 0.05, math.sin(a) * 0.05, 1.2), (math.cos(a) * 0.32, math.sin(a) * 0.32, 1.95), 0.03, 0.025, M['wood'], f'pole{i}', segs=5))
    # Red rag banner.
    parts.append(_box((0.35, -0.55, 0.9), (0.04, 0.3, 0.5), M['red'], 'rag', rot_z=0.4))
    return join(parts, f'tent_{seed}')


def totem(seed):
    rng = random.Random(seed)
    M = mats()
    parts = [_cyl((0, 0, 0), (0, 0, 2.0), 0.07, 0.06, M['wood'], 'pole', segs=6)]
    parts.append(_cyl((-0.35, 0, 1.6), (0.35, 0, 1.65), 0.04, 0.04, M['wood'], 'bar', segs=5))
    parts.append(_blob(rng, (0, 0, 2.08), 0.17, M['bone'], 'skull', squash=1.0, subdiv=2, rough=0.05))
    for i, hx in enumerate((-0.06, 0.06)):
        parts.append(_blob(rng, (hx, -0.12, 2.1), 0.045, _ramp_mat('M_Dark', [(0.05, 0.03, 0.02), (0.1, 0.06, 0.04)], 5), f'eye{i}', subdiv=1, rough=0))
    parts.append(_box((0.18, 0, 1.25), (0.04, 0.42, 0.65), M['red'], 'banner'))
    return join(parts, f'totem_{seed}')


def campfire(seed):
    rng = random.Random(seed)
    M = mats()
    parts = []
    for i in range(9):
        a = i * math.tau / 9
        parts.append(_blob(rng, (math.cos(a) * 0.36, math.sin(a) * 0.36, 0.06), 0.1, M['stone'], f'st{i}', subdiv=1, rough=0.15))
    for i in range(4):
        a = i * math.tau / 4 + 0.3
        parts.append(_cyl((math.cos(a) * 0.3, math.sin(a) * 0.3, 0.05), (math.cos(a) * -0.05, math.sin(a) * -0.05, 0.3), 0.05, 0.045, M['bark'], f'log{i}', segs=6))
    parts.append(_blob(rng, (0, 0, 0.12), 0.14, M['ember'], 'embers', subdiv=1, rough=0.3))
    return join(parts, f'campfire_{seed}')


def crates(seed):
    rng = random.Random(seed)
    M = mats()
    parts = [
        _box((-0.15, 0.1, 0.2), (0.4, 0.4, 0.4), M['wood'], 'c1', rot_z=rng.uniform(-0.2, 0.2), bevel=0.02),
        _box((0.25, -0.1, 0.15), (0.3, 0.3, 0.3), M['wood'], 'c2', rot_z=rng.uniform(-0.3, 0.3), bevel=0.02),
        _box((-0.1, 0.05, 0.53), (0.28, 0.28, 0.26), M['wood'], 'c3', rot_z=rng.uniform(-0.3, 0.3), bevel=0.02),
    ]
    parts.append(_cyl((0.0, -0.4, 0), (0.0, -0.4, 0.45), 0.17, 0.17, M['wood'], 'barrel', segs=12))
    return join(parts, f'crates_{seed}')


# ---------------------------------------------------------------- rendering


def _project_points(cam, pts):
    inv = cam.matrix_world.inverted()
    out = []
    for p in pts:
        l = inv @ p
        out.append((l.x * PPM, l.y * PPM))
    return out


def render_asset(ob, key, v=0, pad=12, shadow=True, scale_mul=1.0, anchor_world=None):
    """Render one object as a sprite and register it in the game's manifest.

    shadow=True bakes the cast shadow (shadow catcher on); units render without it
    so the game can cast their shadow itself and mirror them freely."""
    scn = scene()
    cam = scn.camera
    for o in asset_collection().objects:
        o.hide_render = o is not ob
    bpy.data.objects['SpriteGround'].hide_render = not shadow
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(deps)
    me = ev.to_mesh()
    pts = [ob.matrix_world @ vv.co for vv in me.vertices]
    ev.to_mesh_clear()
    if shadow:
        sun = bpy.data.objects['SpriteSun']
        d = (sun.matrix_world.to_3x3() @ Vector((0, 0, -1))).normalized()
        pts += [p + d * (p.z / -d.z) for p in pts if p.z > 0.01]
    # Frame: centre the projected bounds.
    cam.location = Vector((8, -8, 9.24))
    bpy.context.view_layer.update()
    proj = _project_points(cam, pts)
    xs = [p[0] for p in proj]
    ys = [p[1] for p in proj]
    minx, maxx, miny, maxy = min(xs) - pad, max(xs) + pad, min(ys) - pad, max(ys) + pad
    w = int(math.ceil(maxx - minx))
    h = int(math.ceil(maxy - miny))
    w += w % 2
    h += h % 2
    cx = (minx + maxx) / 2 / PPM
    cy = (miny + maxy) / 2 / PPM
    m = cam.matrix_world.to_3x3()
    cam.location = cam.location + m @ Vector((cx, cy, 0))
    cam.data.ortho_scale = max(w, h) / PPM
    scn.render.resolution_x = w
    scn.render.resolution_y = h
    bpy.context.view_layer.update()
    os.makedirs(OUT_DIR, exist_ok=True)
    fname = f'{key}_{v}.png'
    scn.render.filepath = os.path.join(OUT_DIR, fname)
    bpy.ops.render.render(write_still=True, scene=scn.name)
    base = Vector(anchor_world) if anchor_world is not None else ob.matrix_world.translation.copy()
    base.z = 0
    u = world_to_camera_view(scn, cam, base)
    ax, ay = u.x * w, (1 - u.y) * h
    entry = {'file': f'sprites/blender/{key}_{v}.webp', 'ax': round(ax, 1), 'ay': round(ay, 1), 'scale': round(GAME_PPM / PPM * scale_mul, 4), 'noShadow': bool(shadow)}
    _register(key, v, entry)
    print(f'rendered {key}[{v}] {w}x{h} anchor=({ax:.0f},{ay:.0f})')
    return entry


def _register(key, v, entry):
    data = {'sprites': {}, 'textures': {}}
    if os.path.exists(MANIFEST):
        with open(MANIFEST, encoding='utf-8') as f:
            data = json.load(f)
    lst = data['sprites'].setdefault(key, [])
    while len(lst) <= v:
        lst.append(None)
    lst[v] = entry
    data['sprites'][key] = [e for e in lst if e]
    with open(MANIFEST, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=1)


def render_portrait(ob, key, v, center_world, size_m, px=256):
    """Head-and-shoulders portrait from a lower, more frontal camera."""
    scn = scene()
    cam = scn.camera
    for o in asset_collection().objects:
        o.hide_render = o is not ob
    bpy.data.objects['SpriteGround'].hide_render = True
    saved_rot = tuple(cam.rotation_euler)
    cam.rotation_euler = (math.radians(76), 0, math.radians(45))
    cam.location = Vector(center_world) + cam.matrix_world.to_3x3() @ Vector((0, 0, 12))
    bpy.context.view_layer.update()
    m = cam.matrix_world.to_3x3()
    cam.location = Vector(center_world) + m @ Vector((0, 0, 12))
    cam.data.ortho_scale = size_m
    scn.render.resolution_x = px
    scn.render.resolution_y = px
    bpy.context.view_layer.update()
    fname = f'{key}_{v}.png'
    scn.render.filepath = os.path.join(OUT_DIR, fname)
    bpy.ops.render.render(write_still=True, scene=scn.name)
    cam.rotation_euler = saved_rot
    entry = {'file': f'sprites/blender/{key}_{v}.webp', 'ax': px / 2, 'ay': px, 'scale': 1.0, 'noShadow': True}
    _register(key, v, entry)
    print(f'portrait {key}[{v}]')
    return entry
