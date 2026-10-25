"""Account-free Mixar render, packed texture, save/reopen and GLB export check.

Run only in a disposable --background --factory-startup process.
"""
import json
import os
from pathlib import Path

import bpy
from mathutils import Vector
import keyring
import mcp
import truststore

assert bpy.app.background, 'This check must run in a disposable background process.'
root = Path(__file__).resolve().parents[2]
out = root / 'projects/meridius/review/mixar-setup'
out.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.5))
cube = bpy.context.object
cube.name = 'Mixar_Verification_Crate'
mat = bpy.data.materials.new('Verification_Wood')
mat.use_nodes = True
bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
bsdf.inputs['Roughness'].default_value = 0.72
tex = bpy.data.images.new('Verification_Packed_Texture', width=64, height=64)
pixels = []
for y in range(64):
    for x in range(64):
        seam = x % 16 < 2 or y < 3 or y > 60
        pixels.extend((0.12, 0.06, 0.025, 1) if seam else (0.52, 0.25, 0.065, 1))
tex.pixels.foreach_set(pixels)
tex.filepath_raw = str(out / 'texture.png')
tex.file_format = 'PNG'
tex.save()
tex.pack()
node = mat.node_tree.nodes.new('ShaderNodeTexImage')
node.image = tex
mat.node_tree.links.new(node.outputs['Color'], bsdf.inputs['Base Color'])
cube.data.materials.append(mat)
bevel = cube.modifiers.new('Soft_Edges', 'BEVEL')
bevel.width = 0.025
bevel.segments = 2
scene.world = bpy.data.worlds.new('Verification_World')
scene.world.use_nodes = True
bg = next(n for n in scene.world.node_tree.nodes if n.type == 'BACKGROUND')
bg.inputs['Color'].default_value = (0.16, 0.19, 0.24, 1)
bg.inputs['Strength'].default_value = 0.5
for name, location, power, size in [
    ('Key', (3, -4, 6), 650, 4), ('Fill', (-3, -1, 3), 300, 3),
]:
    data = bpy.data.lights.new(name, 'AREA')
    data.energy, data.shape, data.size = power, 'DISK', size
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector((0, 0, 0.5)) - obj.location).to_track_quat('-Z', 'Y').to_euler()
data = bpy.data.cameras.new('Isometric_Camera')
camera = bpy.data.objects.new('Isometric_Camera', data)
scene.collection.objects.link(camera)
camera.location = (3, -3, 3)
camera.rotation_euler = (Vector((0, 0, 0.5)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
data.type, data.ortho_scale = 'ORTHO', 1.9
scene.camera = camera
scene.render.engine = 'CYCLES'
scene.cycles.device, scene.cycles.samples = 'CPU', 16
scene.render.resolution_x = scene.render.resolution_y = 512
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.filepath = str(out / 'verification.png')
bpy.ops.object.select_all(action='DESELECT')
cube.select_set(True)
bpy.context.view_layer.objects.active = cube
glb = out / 'verification.glb'
bpy.ops.export_scene.gltf(filepath=str(glb), export_format='GLB', use_selection=True, export_apply=True)
blend = out / 'verification.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(blend), thumbnail=False)
bpy.ops.wm.open_mainfile(filepath=str(blend))
cube = bpy.data.objects['Mixar_Verification_Crate']
assert len(cube.data.polygons) == 6
assert len(cube.data.uv_layers) == 1
assert bpy.data.images['Verification_Packed_Texture'].packed_file
assert tuple(round(v, 6) for v in cube.dimensions) == (1.0, 1.0, 1.0)
bpy.ops.render.render(write_still=True)
png = out / 'verification.png'
assert png.stat().st_size > 1000
assert glb.read_bytes()[:4] == b'glTF'
verdict = {
    'mixar_release': '4.3.5', 'reported_version': bpy.app.version_string,
    'python_modules': [keyring.__name__, mcp.__name__, truststore.__name__],
    'save_reopen': True, 'packed_texture': True, 'uvs': True,
    'dimensions_metres': list(cube.dimensions), 'cycles_cpu_render': True,
    'rgba_png': str(png.relative_to(root)), 'glb_export': True,
    'source': str(blend.relative_to(root)),
}
(out / 'local-checks.json').write_text(json.dumps(verdict, indent=2) + '\n', encoding='utf-8')
print('MIXAR_SMOKE_OK', json.dumps(verdict))
