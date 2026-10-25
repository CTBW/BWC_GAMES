"""Preserve supplied FBX, build editable attack studies and export native previews.

Run in a disposable Blender process. No user scene or global settings are changed.
"""
import bpy
import hashlib
import json
import math
import shutil
from pathlib import Path
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[6]
ART = ROOT / 'projects/meridius/source/godot/art/footman/mixamo_attacks'
OUT = ROOT / 'workspace/2026-10-20_meridius/motion-study/mixamo'
ART.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)
PREFIX = 'mixamorig:'

def material(name, color, metallic=0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = .65
    return m

def box(name, size, mat):
    bpy.ops.mesh.primitive_cube_add(size=1)
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat)
    bevel = o.modifiers.new('Soft edges', 'BEVEL')
    bevel.width = .012
    bevel.segments = 2
    o.modifiers.new('Weighted normals', 'WEIGHTED_NORMAL')
    return o

def animate_matrix(obj, matrix, frame):
    obj.rotation_mode = 'QUATERNION'
    obj.matrix_world = matrix
    obj.keyframe_insert('location', frame=frame)
    obj.keyframe_insert('rotation_quaternion', frame=frame)
    obj.keyframe_insert('scale', frame=frame)

def rigid_on_bone(obj, rig, bone, world):
    # Armature modifier makes this a rigidly weighted mesh in the same bind space.
    obj.matrix_world = world
    group = obj.vertex_groups.new(name=PREFIX + bone)
    group.add(list(range(len(obj.data.vertices))), 1, 'REPLACE')
    mod = obj.modifiers.new('Runtime skeleton', 'ARMATURE')
    mod.object = rig
    obj.parent = rig
    obj.matrix_world = world

manifest = {'revision': 'Mixamo attacks v02', 'source_url': 'https://www.mixamo.com/',
            'fps': 30, 'units': 'metres', 'blender_forward': '-Y', 'blender_up': '+Z',
            'runtime': 'Godot study only; production sprites unchanged', 'clips': []}

for key, filename, hand, contact in [
        ('stab', 'Stabbing - Footman.fbx', 'LeftHand', 25),
        ('slash', 'Stable Sword Outward Slash - Footman.fbx', 'RightHand', 27)]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = 30
    source = Path('E:/Animations') / filename
    preserved = ART / filename
    if not preserved.exists():
        shutil.copy2(source, preserved)
    assert hashlib.sha256(source.read_bytes()).digest() == hashlib.sha256(preserved.read_bytes()).digest()
    bpy.ops.import_scene.fbx(filepath=str(preserved))
    rig = next(o for o in scene.objects if o.type == 'ARMATURE')
    action = rig.animation_data.action
    action.name = 'SOURCE_' + key
    action.use_fake_user = True
    start, end = [int(v) for v in action.frame_range]
    scene.frame_start, scene.frame_end = start, end
    scene.frame_set(start)
    bpy.ops.export_scene.gltf(filepath=str(OUT / (key + '_source.glb')), export_format='GLB',
        export_animation_mode='ACTIVE_ACTIONS', export_frame_range=True, export_force_sampling=True,
        export_anim_slide_to_zero=True)
    # Preserve authored lower-body movement and original timing. The study has
    # no controller lunge, translation overlay, retiming or smoothing filter.
    derived = action.copy()
    derived.name = 'FOOTMAN_' + key
    rig.animation_data.action = derived
    mirror = key == 'stab'
    off = 'Right' if mirror else 'Left'
    guard = bpy.data.objects.new('Shield hand IK', None)
    scene.collection.objects.link(guard)
    for frame in range(start, end + 1):
        scene.frame_set(frame)
        hip = rig.matrix_world @ rig.pose.bones[PREFIX + 'Hips'].head
        guard.location = hip + Vector((-.26 if mirror else .26, -.30, .32))
        guard.keyframe_insert('location', frame=frame)
    ik = rig.pose.bones[PREFIX + off + 'ForeArm'].constraints.new('IK')
    ik.name = 'Compact shield guard'
    ik.target = guard
    ik.chain_count = 2
    ik.use_stretch = False
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    bpy.ops.nla.bake(frame_start=start, frame_end=end, step=1, only_selected=False,
                    visual_keying=True, clear_constraints=True, use_current_action=True,
                    bake_types={'POSE'})
    bpy.data.objects.remove(guard, do_unlink=True)
    cream = material('Study / linen', (.60, .53, .39))
    steel = material('Study / iron', (.36, .43, .49), .65)
    dark = material('Study / leather', (.065, .083, .095))
    blue = material('Study / blue', (.055, .18, .31))
    gold = material('Study / brass', (.53, .35, .12), .5)
    for o in list(scene.objects):
        if o.type == 'MESH':
            o.data.materials.clear()
            o.data.materials.append(cream if o.name == 'Beta_Surface' else dark)
    # Minimal costume: the source mannequin remains visible for motion review.
    for name, size, bone, pos, mat in [
        ('Breastplate', (.33,.19,.28), 'Spine2', (0,-.045,1.36), steel),
        ('Blue waist', (.31,.22,.10), 'Hips', (0,-.01,1.02), blue),
        ('Belt', (.32,.23,.045), 'Hips', (0,-.012,1.08), dark),
        ('Buckle', (.06,.02,.055), 'Hips', (0,-.14,1.08), gold)]:
        rigid_on_bone(box(name, size, mat), rig, bone, Matrix.Translation(pos))
    # Calibrate a fixed weapon grip at full extension. Its subsequent rotation
    # comes entirely from the source hand; the source contains no weapon mesh.
    scene.frame_set(contact)
    hand_world = rig.matrix_world @ rig.pose.bones[PREFIX + hand].matrix
    local_direction = hand_world.to_3x3().inverted() @ Vector((0,-1,0))
    local_direction.normalize()
    blade = box('Sword blade', (.045,.74,.022), steel)
    grip = box('Sword grip', (.035,.16,.035), dark)
    cross = box('Sword guard', (.20,.035,.045), gold)
    shield = box('Shield rim', (.45,.065,.59), steel)
    face = box('Shield blue', (.40,.012,.54), blue)
    stripe = box('Shield mark', (.055,.014,.38), cream)
    shield_parts = [shield, face, stripe]
    # Flattened point rather than a square-ended sword.
    for v in blade.data.vertices:
        if v.co.y < 0:
            v.co.x *= .15
    data = []
    for frame in range(start, end + 1):
        scene.frame_set(frame)
        h = rig.matrix_world @ rig.pose.bones[PREFIX + hand].matrix
        direction = (h.to_3x3() @ local_direction).normalized()
        # Local -Y is the blade's forward axis.
        rot = Vector((0,-1,0)).rotation_difference(direction).to_matrix().to_4x4()
        wrist = h.translation
        palm = wrist + (rig.matrix_world @ rig.pose.bones[PREFIX + hand].tail - wrist) * .55
        for obj, offset in [(blade,.45), (grip,0), (cross,.075)]:
            animate_matrix(obj, Matrix.Translation(palm + direction*offset) @ rot, frame)
        sh = rig.matrix_world @ rig.pose.bones[PREFIX + off + 'Hand'].head
        for obj, y in [(shield,-.065),(face,-.104),(stripe,-.113)]:
            animate_matrix(obj, Matrix.Translation(sh + Vector((0,y,0))), frame)
        record = {'frame':frame,'time':(frame-start)/30,
                  'hip':list(rig.matrix_world @ rig.pose.bones[PREFIX+'Hips'].head),
                  'sword_tip':list(palm+direction*.82),
                  'feet':{s:list(rig.matrix_world @ rig.pose.bones[PREFIX+s+'Foot'].head) for s in ['Left','Right']}}
        data.append(record)
    if mirror:
        root = bpy.data.objects.new('Right handed mirror / source left-hand stab', None)
        scene.collection.objects.link(root)
        for o in list(scene.objects):
            if o != root and not o.parent:
                o.parent = root
        root.scale.x = -1
        for row in data:
            for v in [row['hip'],row['sword_tip'],*row['feet'].values()]: v[0] *= -1
    scene.frame_set(start)
    scene.timeline_markers.new('WEAPON CONTACT / proposed', frame=contact)
    scene['source_file'] = filename
    scene['source_fps'] = 30
    scene['preview_note'] = 'Source timing retained; compact shield guard; no controller lunge. Study mannequin, not production art.'
    # Reliable ordinary playback, independent of the native review renderer.
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == 'VIEW_3D':
                area.spaces.active.shading.type = 'MATERIAL'
                area.spaces.active.region_3d.view_distance = 4
                area.spaces.active.region_3d.view_location = (0,-.2,.9)
    bpy.ops.wm.save_as_mainfile(filepath=str(ART / (key + '.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT / (key + '.glb')), export_format='GLB',
        export_animation_mode='ACTIVE_ACTIONS', export_frame_range=True, export_force_sampling=True,
        export_anim_slide_to_zero=True)
    (OUT / (key + '_samples.json')).write_text(json.dumps(data))
    manifest['clips'].append({'id':key,'source_file':filename,
        'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'frames':[start,end], 'samples':end-start+1,'duration':(end-start)/30,
        'contact_frame':contact,'contact_seconds':(contact-start)/30,
        'loop':False,'mirrored':mirror,'source_attack_hand':hand,
        'edits':['offhand IK shield guard','right-handed mirror' if mirror else 'original handedness',
                 'rigid sword with grip calibrated at proposed contact','simple study costume'],
        'bone_count':len(rig.data.bones),'source_action':action.name,'preview_action':derived.name})
(OUT / 'manifest.json').write_text(json.dumps(manifest,indent=2))
print('MIXAMO_PREPARED', json.dumps(manifest))
