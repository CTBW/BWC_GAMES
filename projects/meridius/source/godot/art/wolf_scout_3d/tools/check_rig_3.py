"""Wolf Scout 3 rig check: weight report, bone overlay and joint-extreme renders.

  blender -b --factory-startup --python check_rig_3.py -- <out dir>

Poses rotate bones about world axes at their heads, so the renders show the
skin, not the bone rolls. Workbench with the base-colour textures.
"""
import bpy, json, math, sys
from pathlib import Path
from mathutils import Matrix, Vector

ART = Path(__file__).resolve().parents[1]
OUT = Path(sys.argv[sys.argv.index('--') + 1]); OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ART / 'wolf_scout_3_rig.blend'))
sc = bpy.context.scene
rig = bpy.data.objects['WolfScout3_Rig']; P = rig.pose.bones
meshes = [o for o in bpy.data.objects if o.type == 'MESH']

report = {}
for o in meshes:
    names = {g.index: g.name for g in o.vertex_groups}
    zero = sum(1 for v in o.data.vertices if sum(g.weight for g in v.groups) < 0.99)
    most = max(len(v.groups) for v in o.data.vertices)
    used = sorted({names[g.group] for v in o.data.vertices for g in v.groups if g.weight > 0.01})
    report[o.name] = {'verts': len(o.data.vertices), 'faces': len(o.data.polygons),
                      'unweighted_or_short': zero, 'max_influences': most, 'bones_used': len(used)}
report['bones'] = len(rig.data.bones)
def blade(o):
    # Signed volume (positive: normals face out) and the blade's rest direction.
    import bmesh
    bm = bmesh.new(); bm.from_mesh(o.data); vol = bm.calc_volume(signed=True); bm.free()
    socket = rig.data.bones['DaggerSocket.' + o.name.split('.')[-1]]
    far = max(o.data.vertices, key=lambda v: (v.co - socket.head_local).length).co - socket.head_local
    return {'signed_volume': round(vol, 6), 'tip_dir': [round(c, 2) for c in far.normalized()]}
report['daggers'] = {o.name: blade(o) for o in meshes if 'Dagger' in o.name}
report['deform_bones'] = sum(b.use_deform for b in rig.data.bones)
(OUT / 'rig-check.json').write_text(json.dumps(report, indent=2))
print('REPORT', json.dumps(report))

def setup(res):
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.render.resolution_x = sc.render.resolution_y = res
    sh = sc.display.shading
    sh.light = 'STUDIO'; sh.color_type = 'TEXTURE'; sh.show_backface_culling = False
    sh.background_type = 'VIEWPORT'; sh.background_color = (0.35, 0.37, 0.4)
def shot(name, loc, target, ortho, res=800, xray=False):
    setup(res); sc.display.shading.show_xray = xray; sc.display.shading.xray_alpha = 0.35
    cam = bpy.data.objects.get('CheckCam') or bpy.data.objects.new('CheckCam', bpy.data.cameras.new('CheckCam'))
    if cam.name not in sc.collection.objects: sc.collection.objects.link(cam)
    cam.location = loc; cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = ortho; sc.camera = cam
    sc.render.filepath = str(OUT / f'{name}.png'); bpy.ops.render.render(write_still=True)

# Bone overlay: one thin octahedron per deform bone, red for the left side.
bm_me = bpy.data.meshes.new('BoneViz'); verts, faces = [], []
for b in rig.data.bones:
    if not b.use_deform: continue
    h, t = b.head_local, b.tail_local; axis = (t - h); L = axis.length
    if L < 1e-5: continue
    q = axis.normalized().to_track_quat('Y', 'Z').to_matrix()
    r = min(0.012, L * 0.12); m = h + axis * 0.2; base = len(verts)
    verts += [h, m + q @ Vector((r, 0, 0)), m + q @ Vector((0, 0, r)), m + q @ Vector((-r, 0, 0)), m + q @ Vector((0, 0, -r)), t]
    faces += [(base, base + i, base + i % 4 + 1) for i in range(1, 5)] + [(base + 5, base + i % 4 + 1, base + i) for i in range(1, 5)]
bm_me.from_pydata(verts, [], faces)
viz = bpy.data.objects.new('BoneViz', bm_me); sc.collection.objects.link(viz)
mat = bpy.data.materials.new('BoneVizMat'); mat.diffuse_color = (1, 0.85, 0.1, 1); viz.data.materials.append(mat)
sc.display.shading.color_type = 'TEXTURE'
shot('rest-bones-front', (0, -6, 1.0), (0, 0.2, 1.0), 2.1, xray=True)
shot('rest-bones-side', (6, 0.25, 1.0), (0, 0.25, 1.0), 2.1, xray=True)
shot('rest-bones-back', (0, 6, 1.0), (0, 0.25, 1.0), 2.1, xray=True)
bpy.data.objects.remove(viz)

order = []
def visit(b):
    order.append(b.name)
    for c in b.children: visit(c)
for b in rig.data.bones:
    if b.parent is None: visit(b)
def pose(rots, grip=False):
    """rots: bone -> (world axis, degrees); applied parent-first about each head.
    grip: the fingers hold the daggers (the rig's GripPose)."""
    for pb in P: pb.matrix_basis = Matrix()
    if grip:
        for n, q in rig['GripPose'].items(): P[n].rotation_mode = 'QUATERNION'; P[n].rotation_quaternion = q
    bpy.context.view_layer.update()
    for name in order:
        if name not in rots: continue
        axis, deg = rots[name]; pb = P[name]
        h = pb.head.copy()   # posed head, armature space
        R = Matrix.Translation(h) @ Matrix.Rotation(math.radians(deg), 4, Vector(axis)) @ Matrix.Translation(-h)
        pb.matrix = R @ pb.matrix
        bpy.context.view_layer.update()

def side(name, s):
    return name.replace('Left', 'Right') if s < 0 else name
TESTS = {
    'arms-up': {'mixamorig:LeftArm': ((0, 1, 0), -70), 'mixamorig:RightArm': ((0, 1, 0), 70),
                'mixamorig:LeftShoulder': ((0, 1, 0), -12), 'mixamorig:RightShoulder': ((0, 1, 0), 12)},
    'arms-down': {'mixamorig:LeftArm': ((0, 1, 0), 75), 'mixamorig:RightArm': ((0, 1, 0), -75)},
    'arms-forward-elbows': {'mixamorig:LeftArm': ((0, 0, 1), -80), 'mixamorig:RightArm': ((0, 0, 1), 80),
                            'mixamorig:LeftForeArm': ((0, 0, 1), -100), 'mixamorig:RightForeArm': ((0, 0, 1), 100)},
    'squat': {'mixamorig:Hips': ((1, 0, 0), 0), 'mixamorig:LeftUpLeg': ((1, 0, 0), -95), 'mixamorig:RightUpLeg': ((1, 0, 0), -95),
              'mixamorig:LeftLeg': ((1, 0, 0), 120), 'mixamorig:RightLeg': ((1, 0, 0), 120),
              'mixamorig:LeftFoot': ((1, 0, 0), -25), 'mixamorig:RightFoot': ((1, 0, 0), -25)},
    'stride': {'mixamorig:LeftUpLeg': ((1, 0, 0), -50), 'mixamorig:RightUpLeg': ((1, 0, 0), 35),
               'mixamorig:LeftLeg': ((1, 0, 0), 60), 'mixamorig:RightLeg': ((1, 0, 0), 20)},
    'twist-bend': {'mixamorig:Spine': ((0, 0, 1), 20), 'mixamorig:Spine1': ((0, 0, 1), 15), 'mixamorig:Spine2': ((1, 0, 0), -25),
                   'mixamorig:Neck': ((0, 0, 1), 25), 'mixamorig:Head': ((0, 0, 1), 25)},
    'tail-ears': {**{f'Tail.0{i}': ((0, 0, 1), 18) for i in range(1, 7)}, 'Tail.01': ((1, 0, 0), -25),
                  'Ear.L': ((0, 1, 0), -25), 'Ear.R': ((1, 0, 0), 30)},
    'grip': {'mixamorig:LeftArm': ((0, 1, 0), 60), 'mixamorig:RightArm': ((0, 1, 0), -60)},
    'grip-hang': {'mixamorig:LeftArm': ((0, 1, 0), 78), 'mixamorig:RightArm': ((0, 1, 0), -78),
                  'mixamorig:LeftForeArm': ((0, 1, 0), 6), 'mixamorig:RightForeArm': ((0, 1, 0), -6)},
}
for name, rots in TESTS.items():
    pose(rots, name.startswith('grip'))
    shot(f'pose-{name}-front', (0, -6, 1.0), (0, 0.2, 1.0), 2.2)
    shot(f'pose-{name}-q34', (4.5, -4.5, 1.4), (0, 0.2, 0.95), 2.2)
    if name in ('squat', 'stride', 'tail-ears', 'twist-bend'):
        shot(f'pose-{name}-back', (0, 6, 1.0), (0, 0.2, 1.0), 2.2)
    if name == 'grip-hang':
        shot(f'pose-{name}-side', (6, 0.2, 1.0), (0, 0.2, 1.0), 2.2)
pose(TESTS['grip'], True)
for s, nm in ((1, 'left'), (-1, 'right')):
    hp = rig.matrix_world @ P[side('mixamorig:LeftHand', s)].tail
    shot(f'grip-{nm}-front', hp + Vector((0, -2, 0)), hp, 0.35, 700)
    shot(f'grip-{nm}-side', hp + Vector((s * 2, 0, 0)), hp, 0.35, 700)
for pb in P: pb.matrix_basis = Matrix()
print('DONE', OUT)
