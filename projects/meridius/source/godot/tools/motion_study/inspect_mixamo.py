"""Inspect user-supplied Mixamo attacks in a disposable Blender process."""
import bpy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[6]
OUT = ROOT / '.cache/motion-study/mixamo'
OUT.mkdir(parents=True, exist_ok=True)
report = []
for name in ['Stabbing - Footman', 'Stable Sword Outward Slash - Footman']:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(Path('E:/Animations') / (name + '.fbx')))
    scene = bpy.context.scene
    rigs = [o for o in scene.objects if o.type == 'ARMATURE']
    entry = {'file': name, 'fps': scene.render.fps / scene.render.fps_base,
             'objects': [{'name': o.name, 'type': o.type, 'dimensions': list(o.dimensions),
                          'vertices': len(o.data.vertices) if o.type == 'MESH' else None}
                         for o in scene.objects],
             'actions': [{'name': a.name, 'range': list(a.frame_range)} for a in bpy.data.actions],
             'rigs': []}
    for rig in rigs:
        info = {'name': rig.name, 'scale': list(rig.scale), 'rotation': list(rig.rotation_euler),
                'bones': [{'name': b.name, 'parent': b.parent.name if b.parent else None,
                           'head': list(rig.matrix_world @ b.head_local),
                           'tail': list(rig.matrix_world @ b.tail_local)} for b in rig.data.bones],
                'samples': []}
        action = rig.animation_data.action if rig.animation_data else None
        if action:
            start, end = map(int, action.frame_range)
            for frame in range(start, end + 1):
                scene.frame_set(frame)
                info['samples'].append({'frame': frame, 'bones': {b.name: {
                    'head': list(rig.matrix_world @ b.head),
                    'tail': list(rig.matrix_world @ b.tail),
                    'matrix': [list(row) for row in rig.matrix_world @ b.matrix]}
                    for b in rig.pose.bones}})
        entry['rigs'].append(info)
    report.append(entry)
(OUT / 'inspection.json').write_text(json.dumps(report, indent=2))
print('MIXAMO_INSPECTION', json.dumps([{k: v for k, v in e.items() if k != 'rigs'} for e in report]))
print('OUTPUT', OUT)
