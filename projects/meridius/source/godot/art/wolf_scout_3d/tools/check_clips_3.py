"""Wolf Scout 3 clip check: per-frame floor numbers and key-frame renders.

  blender -b --factory-startup --python check_clips_3.py -- <out dir> [clip,clip]

Writes clips-check.json (lowest point of each mesh per frame; the body's should
sit at 0 on support frames, the cloak and daggers stay above the floor) and
<clip>-<frame>-<view>.png Workbench renders of the key frames.
"""
import bpy, json, sys
import numpy as np
from pathlib import Path
from mathutils import Vector

ART = Path(__file__).resolve().parents[1]
argv = sys.argv[sys.argv.index('--') + 1:]
OUT = Path(argv[0]); OUT.mkdir(parents=True, exist_ok=True)
KEYS = {'idle': [1, 34, 68, 101], 'sneak': [1, 9, 17, 25], 'attack': [1, 14, 20, 25, 33, 42, 62], 'death': [10, 25, 35, 45, 55, 69]}
clips = argv[1].split(',') if len(argv) > 1 and argv[1] else list(KEYS)
bpy.ops.wm.open_mainfile(filepath=str(ART / 'wolf_scout_3.blend'))
sc = bpy.context.scene; rig = bpy.data.objects['WolfScout3_Rig']
meshes = [o for o in sc.objects if o.type == 'MESH']
sc.render.engine = 'BLENDER_WORKBENCH'; sc.render.resolution_x = sc.render.resolution_y = 800
sh = sc.display.shading; sh.light = 'STUDIO'; sh.color_type = 'TEXTURE'; sh.show_backface_culling = False
sh.background_type = 'VIEWPORT'; sh.background_color = (0.35, 0.37, 0.4)
cam = bpy.data.objects.new('ClipCam', bpy.data.cameras.new('ClipCam')); sc.collection.objects.link(cam)
cam.data.type = 'ORTHO'; cam.data.ortho_scale = 2.4; sc.camera = cam
# A floor to judge contact against.
bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, 0)); floor = bpy.context.object
fm = bpy.data.materials.new('Floor'); fm.diffuse_color = (0.42, 0.45, 0.38, 1); floor.data.materials.append(fm)

# Each vertex's main bone, so a low point can be named (tail, head, foot...).
MAIN = {}
for o in meshes:
    names = {g.index: g.name for g in o.vertex_groups}
    MAIN[o.name] = np.array([names[max(v.groups, key=lambda g: g.weight).group].split(':')[-1] if len(v.groups) else '-'
                             for v in o.data.vertices])
def lowest(o, parts=None):
    ev = o.evaluated_get(bpy.context.evaluated_depsgraph_get()); me = ev.to_mesh()
    co = np.empty(len(me.vertices) * 3, np.float32); me.vertices.foreach_get('co', co); ev.to_mesh_clear()
    co = co.reshape(-1, 3) @ np.array(o.matrix_world)[:3, :3].T + np.array(o.matrix_world)[:3, 3]
    if parts is None: return float(co[:, 2].min())
    tail = np.char.startswith(MAIN[o.name], 'Tail')
    out = {}
    for key, mask in (('tail', tail), ('rest', ~tail)):
        if not mask.any(): out[key] = (9.0, '-'); continue
        i = np.flatnonzero(mask)[np.argmin(co[mask, 2])]; out[key] = (round(float(co[i, 2]), 4), str(MAIN[o.name][i]))
    return out

report = {}
for name in clips:
    a = bpy.data.actions[name]; rig.animation_data.action = a; rig.animation_data.action_slot = a.slots[0]
    n = int(a['frames']); rows = []
    for f in range(1, n + 1):
        sc.frame_set(f); row = {o.name.replace('WolfScout3_', ''): round(lowest(o), 4) for o in meshes}
        row['parts'] = {k: lowest(bpy.data.objects[k], True) for k in ('WolfScout3_Body', 'WolfScout3_Cloak')}
        rows.append(row)
    report[name] = {'frames': n, 'body_min': min(r['Body'] for r in rows), 'body_max_of_min': max(r['Body'] for r in rows),
                    'cloak_min': min(r['Cloak'] for r in rows),
                    'dagger_min': min(min(r['Dagger.Left'], r['Dagger.Right']) for r in rows),
                    'lowest': {f'{o}.{k}': min(((r['parts'][o][k][0], i + 1, r['parts'][o][k][1]) for i, r in enumerate(rows)))
                               for o in ('WolfScout3_Body', 'WolfScout3_Cloak') for k in ('tail', 'rest')},
                    'per_frame': rows}
    for f in (KEYS[name] if '--no-render' not in argv else []):
        sc.frame_set(f)
        t = rig.matrix_world @ rig.pose.bones['mixamorig:Hips'].head if name == 'death' else Vector((0, 0.1, 0))
        t = Vector((t.x, t.y, 0.95))
        for view, d in (('front', (0.6, -1, 0.35)), ('back', (0.5, 1, 0.4)), ('side', (1, 0, 0.12))):
            d = Vector(d).normalized(); cam.location = t + d * 6
            cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
            sc.render.filepath = str(OUT / f'{name}-{f:03d}-{view}.png'); bpy.ops.render.render(write_still=True)
    print('CLIP', name, {k: v for k, v in report[name].items() if k != 'per_frame'}, flush=True)
(OUT / 'clips-check.json').write_text(json.dumps(report, indent=1))
print('DONE', OUT)
