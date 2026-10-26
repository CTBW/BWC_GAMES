"""The Sovereign Kiss additions to a succubus rig (background Blender; runs again cleanly).

  blender -b succubus_rig.blend --python kiss_rig.py -- [out.blend]

Her mouth is painted on the texture (a grin with teeth; the model has no mouth of its own)
and the rig has no face, so (workspace/2026-10-20_meridius/sovereign-kiss/
blender-handoff-fog.md, "Character and cast"):

- Kiss_Pucker, a shape key on the body: the mouth's corners drawn in towards its middle,
  the lips pressed together and pushed forward, so the painted grin closes into a small
  pout. Exhale: the lips rounded open and forward (the breath after the release).
  Both act only on the face round the mouth (MOUTH_R), fading out towards the nose and
  chin, and leave the basis untouched.
- KissSocket, a bone on mixamorig:Head: its head at the puckered lips, pointing straight
  out of the mouth (+Y along the bone, Z up), RELEASE long, so its tail is the release
  point the fog heart is spawned at (about 0.12 m ahead of the lips: the breath bridges
  the gap). It deforms nothing; use_deform is set only so the Godot export (deforming
  bones only) keeps it.
"""
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

MOUTH_Z = 1.611              # the painted mouth's middle (front render, 26 Oct 2026)
# The area the keys move: half width, half height above (the nose is 1.4-2.2 cm up) and
# below (the chin), and the inner part that moves fully before it fades out (m, fraction).
MOUTH_R = (0.055, 0.018, 0.028, 0.45)
LIPS_R = (0.035, 0.010, 0.014, 0.40)    # the lips themselves (Exhale opens these)
PUCKER = {"pinch": 0.45, "press": 0.35, "forward": 0.007}
EXHALE = {"pinch": 0.25, "open": 0.70, "forward": 0.006}
RELEASE = 0.12               # KissSocket's length: the release point ahead of the lips (m)

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
rig = bpy.data.objects["SuccubusRig"]
body = bpy.data.objects["Succubus"]
assert rig.matrix_world == rig.matrix_world.Identity(4) and body.matrix_world == body.matrix_world.Identity(4)
me = body.data

# the lips' surface straight ahead of the mouth's middle
bvh = BVHTree.FromPolygons([v.co for v in me.vertices], [p.vertices for p in me.polygons])
hit = bvh.ray_cast(Vector((0.0, -1.0, MOUTH_Z)), Vector((0, 1, 0)))
assert hit[0] is not None, "no face ahead of the mouth"
C = Vector((0.0, hit[0].y, MOUTH_Z))

co = np.empty(len(me.vertices) * 3)
me.vertices.foreach_get("co", co)
co = co.reshape(-1, 3)
head_w = np.zeros(len(me.vertices))
gi = body.vertex_groups["mixamorig:Head"].index
for v in me.vertices:
    for g in v.groups:
        if g.group == gi:
            head_w[v.index] = g.weight
d = co - np.array(C)


def falloff(rx, rz_up, rz_down, inner):
    rz = np.where(d[:, 2] > 0, rz_up, rz_down)
    r = np.sqrt((d[:, 0] / rx) ** 2 + (d[:, 2] / rz) ** 2)
    k = np.clip((r - inner) / (1 - inner), 0, 1)
    # the face only: on the head, and on its front (not the hair or the back of the head)
    on = (r < 1) & (head_w > 0.5) & (d[:, 1] < 0.03)
    return np.where(on, 1 - k * k * (3 - 2 * k), 0.0)


w, w_lips = falloff(*MOUTH_R), falloff(*LIPS_R)
pucker = co.copy()
pucker[:, 0] -= d[:, 0] * PUCKER["pinch"] * w
pucker[:, 2] -= d[:, 2] * PUCKER["press"] * w
pucker[:, 1] -= PUCKER["forward"] * w_lips
exhale = co.copy()
exhale[:, 0] -= d[:, 0] * EXHALE["pinch"] * w
exhale[:, 2] += d[:, 2] * EXHALE["open"] * w_lips
exhale[:, 1] -= EXHALE["forward"] * w_lips

if not me.shape_keys:
    body.shape_key_add(name="Basis", from_mix=False)
for name, new in (("Kiss_Pucker", pucker), ("Exhale", exhale)):
    old = me.shape_keys.key_blocks.get(name)
    if old is not None:
        body.shape_key_remove(old)
    k = body.shape_key_add(name=name, from_mix=False)
    k.data.foreach_set("co", new.ravel())
    k.value = 0.0
    k.slider_min, k.slider_max = 0.0, 1.0

bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
eb = rig.data.edit_bones
if "KissSocket" in eb:
    eb.remove(eb["KissSocket"])
b = eb.new("KissSocket")
b.head = C + Vector((0, -PUCKER["forward"], 0))
b.tail = b.head + Vector((0, -RELEASE, 0))
b.align_roll(Vector((0, 0, 1)))
b.parent = eb["mixamorig:Head"]
b.use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")
rig.data.bones["KissSocket"].use_deform = True
rig["kiss_socket"] = {"release": RELEASE, "mouth": list(C)}
print("KISS_RIG mouth at %s, %d face vertices move (%d on the lips); KissSocket %s -> %s" % (
    tuple(round(x, 4) for x in C), int((w > 0).sum()), int((w_lips > 0).sum()),
    tuple(round(x, 3) for x in rig.data.bones["KissSocket"].head_local),
    tuple(round(x, 3) for x in rig.data.bones["KissSocket"].tail_local)))
if argv and argv[0]:
    bpy.ops.wm.save_as_mainfile(filepath=argv[0], compress=True)
else:
    bpy.ops.wm.save_mainfile(compress=True)
print("KISS_RIG_SAVED", bpy.data.filepath)
