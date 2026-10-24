"""Count body vertices showing through the cloth cape, over frames and the four facings.

  CLIP=walk STEP=4 CAPE_CACHE=<dir> blender -b spearman_rig.blend --python cape_poke.py

(tools/poke_cape.sh runs it per clip.) Every second body vertex is tested from the battle
camera (30 deg down) at yaw 45, -45, 135 and -135: it counts when the cape lies within 6 cm
in front of it and nothing else is in front of that. Prints POKEALL <clip> total <n>
worst (<n>, (<frame>, <yaw>)); DBG=1 also prints every view.
"""
import bpy, math, os
from mathutils import Vector, Euler

CLIP = os.environ.get("CLIP", "walk"); STEP = int(os.environ.get("STEP", "4"))
sc = bpy.context.scene; rig = bpy.data.objects["SpearmanRig"]; cape = bpy.data.objects["Cape"]; body = bpy.data.objects["Spearman"]
act = bpy.data.actions[CLIP]; rig.animation_data.action = act
for m in cape.modifiers:
    if m.type in ("ARMATURE", "CLOTH"): m.show_viewport = False
mc = cape.modifiers.new("CapeCache", "MESH_CACHE"); cape.modifiers.move(cape.modifiers.find(mc.name), 0)
mc.cache_format = "PC2"; mc.filepath = os.path.join(os.environ["CAPE_CACHE"], CLIP + ".pc2"); mc.play_mode = "SCENE"; mc.time_mode = "FRAME"; mc.frame_start = 1.0
mc.forward_axis, mc.up_axis = "POS_Y", "POS_Z"
for o in bpy.data.objects:
    if o.type == "MESH" and o not in (cape, body): o.hide_viewport = True
e = math.radians(30); d = Vector((0, -math.cos(e), math.sin(e)))
f0, f1 = (int(v) for v in act.frame_range)
total, worst = 0, (0, None)
for f in range(f0, f1 + 1, STEP):
    sc.frame_set(f)
    for yaw in (45, -45, 135, -135):
        rig.rotation_euler = Euler((0, 0, math.radians(yaw))); bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        me = body.evaluated_get(dg).to_mesh(); pts = [body.matrix_world @ v.co for i, v in enumerate(me.vertices) if i % 2 == 0]
        body.evaluated_get(dg).to_mesh_clear()
        ce = cape.evaluated_get(dg); _ = len(ce.data.vertices)   # evaluate the cached cape before ray casting
        n = 0
        for p in pts:
            r = sc.ray_cast(dg, p + d * 0.002, -d, distance=0.06)
            if r[0] and r[4] is not None and r[4].name == "Cape" and not sc.ray_cast(dg, p + d * 0.002, d, distance=3)[0]:
                n += 1
        total += n
        # Reading the evaluated cape's coordinates keeps the cache in step from view to view.
        # The counts of 2026-10-24 were taken with this read in place (then behind DBG=1).
        zmin = min((cape.matrix_world @ v.co).z for v in cape.evaluated_get(dg).data.vertices)
        if os.environ.get("DBG"): print("DBGP", f, yaw, n, "cape z-range", round(zmin, 3))
        if n > worst[0]: worst = (n, (f, yaw))
rig.rotation_euler = Euler((0, 0, 0))
print("POKEALL", CLIP, "total", total, "worst", worst)
