"""Export Wolf Scout 3's four clips as one GLB with its sidecar, and check it.

  blender -b --factory-startup --python export_wolf_scout_3.py

Reads art/wolf_scout_3d/wolf_scout_3.blend (animate_wolf_scout_3.py). Writes
wolf_scout_3.glb and wolf_scout_3.json next to it and copies both to
prototypes/wolf_scout_anim/art3d/. The clips are bone animation only (the cape
is five bone chains), one glTF animation per Action, each starting at 0 s.

The GLB is then imported into an empty scene and every mesh is compared with
the source at sampled frames of every clip (nearest-vertex distance, since the
export splits vertices at UV seams); the report goes to
review/wolf-scout/wolf-scout-3/export-check.json. The clips come from the Wolf
Scout FBX takes, so the GLB stays local like the other rigged models.
"""
import bpy, json, math, shutil, struct
import numpy as np
from pathlib import Path
from mathutils import Vector
from mathutils.kdtree import KDTree

ART = Path(__file__).resolve().parents[1]
REPO = ART.parents[5]
GODOT = REPO / 'projects/meridius/source/godot/prototypes/wolf_scout_anim/art3d'
REVIEW = REPO / 'projects/meridius/review/wolf-scout/wolf-scout-3'
CLIPS = ('idle', 'sneak', 'attack', 'death')
SAMPLE = {'idle': [1, 31, 61, 91, 121], 'sneak': [1, 9, 17, 25, 33], 'attack': [1, 14, 25, 33, 42, 62], 'death': [1, 25, 35, 45, 69]}
# Wolf Scout 2's attack and death events: these clips keep WS2's timing.
EVENTS = {'attack': [{'time': 0.8, 'name': 'strike_left'}, {'time': 0.8333, 'name': 'strike_right'}],
          'death': [{'time': 2.2667, 'name': 'settled'}]}

bpy.ops.wm.open_mainfile(filepath=str(ART / 'wolf_scout_3.blend'))
sc = bpy.context.scene; rig = bpy.data.objects['WolfScout3_Rig']
meshes = [o for o in sc.objects if o.type == 'MESH' and o.name.startswith('WolfScout3_')]
MESH_NAMES = sorted(o.name for o in meshes)

def bind(name):
    a = bpy.data.actions[name]; rig.animation_data.action = a; rig.animation_data.action_slot = a.slots[0]
    return a

def world_verts(o):
    ev = o.evaluated_get(bpy.context.evaluated_depsgraph_get()); me = ev.to_mesh()
    co = np.empty(len(me.vertices) * 3, np.float32); me.vertices.foreach_get('co', co); ev.to_mesh_clear()
    M = np.array(o.matrix_world); return co.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3]

# Reference poses from the source, before anything is changed for export.
ref = {}
for name in CLIPS:
    bind(name)
    for f in SAMPLE[name]:
        sc.frame_set(f)
        for o in meshes: ref[(name, f, o.name)] = world_verts(o)
meta_src = {n: {k: (list(v) if hasattr(v, '__len__') and not isinstance(v, str) else v) for k, v in bpy.data.actions[n].items()} for n in CLIPS}

# The daggers ride their sockets as rigid skins: the sockets must be joints.
for side in ('Left', 'Right'): rig.data.bones[f'DaggerSocket.{side}'].use_deform = True
for p in rig.pose.bones: p.custom_shape = None
rig.animation_data.action = None
for t in rig.animation_data.nla_tracks: t.mute = True
for o in bpy.data.objects: o.select_set(o == rig or o in meshes)
bpy.context.view_layer.objects.active = rig
sc.frame_start, sc.render.fps = 1, 30
glb = ART / 'wolf_scout_3.glb'
opts = dict(filepath=str(glb), export_format='GLB', use_selection=True, export_animations=True,
            export_animation_mode='ACTIONS', export_force_sampling=True, export_frame_range=False,
            export_skins=True, export_def_bones=False, export_apply=False, export_morph=False,
            export_optimize_animation_size=False, export_rest_position_armature=True, export_anim_slide_to_zero=True)
bpy.ops.export_scene.gltf(**opts)

# The GLB: one animation per clip, each from 0 s to its last frame.
raw = glb.read_bytes(); n = struct.unpack_from('<I', raw, 12)[0]; doc = json.loads(raw[20:20 + n])
spans = {}
for a in doc['animations']:
    ts = [doc['accessors'][s['input']] for s in a['samplers']]
    spans[a['name']] = (min(t['min'][0] for t in ts), max(t['max'][0] for t in ts))
assert set(spans) == set(CLIPS), spans
for c in CLIPS:
    want = (int(meta_src[c]['frames']) - 1) / 30
    assert abs(spans[c][0]) < 1e-4 and abs(spans[c][1] - want) < 1e-3, (c, spans[c], want)

# Sidecar.
clips = {}
for c in CLIPS:
    m = meta_src[c]; fr = int(m['frames']); rv = m.get('root_vel', [0, 0])
    clips[c] = {'frames': fr, 'length': (fr - 1) / 30, 'loop': bool(m['loop']), 'source': m.get('source', ''),
                'root_motion': bool(m.get('root_motion', False)), 'events': EVENTS.get(c, [])}
    if c == 'sneak': clips[c]['speed_mps'] = round(math.hypot(*rv[:2]), 6)
meta = {'revision': 'wolf-scout-3-v1', 'source': 'art/wolf_scout_3d/wolf_scout_3.blend', 'rig': 'art/wolf_scout_3d/wolf_scout_3_rig.blend',
        'fps': 30, 'height_m': 1.94, 'forward': [0, 0, 1],
        'roles': {'idle': 'idle', 'walk': 'sneak', 'attack': ['attack'], 'death': 'death'},
        'objects': [o.name for o in meshes], 'bones': len(rig.data.bones),
        'cape': 'Five baked bone chains (Cloak.*), no morphs.', 'clips': clips}
(ART / 'wolf_scout_3.json').write_text(json.dumps(meta, indent=2) + '\n')

# Reimport into an empty scene and compare.
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = 30   # the importer keys by the scene's rate
bpy.ops.import_scene.gltf(filepath=str(glb))
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
imp = {o.name: o for o in bpy.data.objects if o.name in MESH_NAMES}   # not the importer's bone shape
report = {'bones': len(arm.data.bones), 'meshes': sorted(imp), 'clips': {},
          'textures': sorted({n.image.name for m in bpy.data.materials if m.node_tree for n in m.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image})}
assert sorted(imp) == MESH_NAMES, (sorted(imp), MESH_NAMES)
for c in CLIPS:
    a = next(x for x in bpy.data.actions if x.name.split('_')[0] == c or x.name == c)
    arm.animation_data.action = a
    if a.slots: arm.animation_data.action_slot = a.slots[0]
    worst = 0.0
    for f in SAMPLE[c]:
        bpy.context.scene.frame_set(f - 1 + int(a.frame_range[0]))
        for name, o in imp.items():
            got = world_verts(o); kd = KDTree(len(got))
            for i, p in enumerate(got): kd.insert(p, i)
            kd.balance()
            R = ref[(c, f, name)]
            d = max(kd.find(Vector(p))[2] for p in R[::max(1, len(R) // 1500)])
            worst = max(worst, d)
    report['clips'][c] = {'action': a.name, 'frame_range': list(a.frame_range), 'max_vertex_error_mm': round(worst * 1000, 3)}
    print('REIMPORT', c, report['clips'][c], flush=True)
REVIEW.mkdir(parents=True, exist_ok=True)
(REVIEW / 'export-check.json').write_text(json.dumps(report, indent=1) + '\n')
assert all(v['max_vertex_error_mm'] < 2.0 for v in report['clips'].values()), report['clips']
GODOT.mkdir(parents=True, exist_ok=True)
shutil.copy2(glb, GODOT / glb.name); shutil.copy2(ART / 'wolf_scout_3.json', GODOT / 'wolf_scout_3.json')
print('WOLF_SCOUT_3_EXPORTED', json.dumps({'bytes': glb.stat().st_size, 'spans': spans, 'bones': report['bones']}), flush=True)
