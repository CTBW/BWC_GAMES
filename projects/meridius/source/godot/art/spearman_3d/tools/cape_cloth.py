"""Simulated cloth for the spearman's cape (background Blender).

  blender -b <rig.blend> --python cape_cloth.py -- setup        (after rig_spearman.py)
  blender -b <rig.blend> --python cape_cloth.py -- sim <cache_dir> [clip,clip...]   (after spear_motion.py)

Setup comes before retarget_clips.py, whose ground check needs the cape off the body.

Tripo modelled the cape flared out for the T-pose, and skinned to the body it moved like a
board. "setup" replaces it with cloth:
- the cape is found by growing from a face in the middle of its back over cape-blue texture,
  below the hood (CAPE_TOP); that region (back, the sides that wrap forward, the hem) leaves
  the body. Its outer layer becomes the object "Cape" (welded, texture kept); a Solidify
  modifier gives it back its thickness;
- the top rows under the hood are pinned to the spine bones; the rest is cloth (wool, about
  CAPE_KG in all) colliding with the ground and with ellipsoids riding on the bones (torso,
  pelvis, thighs, shins; not the arms) and one round the back of his tunic's skirt and belt,
  each clear of the free cloth at rest (Tripo's cape cuts through his back at rest, so
  nothing truer to his body can start clear of it). Only the free cloth collides: the pinned
  rows lie on his back;
- his lower back under the cape (belt, its fringe, the pouch on his right hip) is pressed
  flat, so the cloth hanging on it never shows it through.
"sim" runs the cloth for every clip and writes the cape's vertex positions per frame (rig
space, before Solidify, kept GROUND_CLEAR above the ground) to <cache_dir>/<clip>.pc2.
Each run starts in the rest pose, where nothing overlaps, eases into the clip's first pose
and holds it, so the clip starts with the cape settled; loops are simulated twice and the
second pass kept, its last frames eased into its first. The renders read the caches with a
Mesh Cache modifier, so every facing shows the same cloth.
"""
import math
import struct
import sys
from collections import deque
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

PREROLL = 50           # run-up frames: rest pose, easing into the first pose by PREROLL_HOLD
PREROLL_HOLD = 18      # ... which is then held this many frames before frame 1
CAPE_KG = 2.6
LOOPS = {"idle", "idle_rest", "walk", "step_lane"}
SEAM = 10
CAPE_TOP = 1.42        # the hood and the drape over the shoulders stay on the body
PIN_TOP, PIN_BOTTOM = 1.37, 1.31   # pinned fully above PIN_TOP, free below PIN_BOTTOM
GROUND_CLEAR = 0.01    # m: the baked cape is kept this far above the ground (Solidify thickens it inwards)
BACK_BOX = ((-0.30, 0.30), (0.90, 1.30))     # rest x and z of his lower back, always under the cape
BACK_LINE, BACK_KEEP = 0.10, 0.0              # rest y the back is pressed onto, share of the depth behind it kept

argv = sys.argv[sys.argv.index("--") + 1:]
mode = argv[0]
sc = bpy.context.scene
rig = bpy.data.objects["SpearmanRig"]
body = bpy.data.objects["Spearman"]
SPINE = ["Hips", "Spine", "Spine1", "Spine2", "Neck"]


def cape_faces(me):
    """Faces of the cape: grown from the middle of its back over cape-blue texture."""
    img = next(n.image for m in me.materials for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image)
    W, H = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
    uv = me.uv_layers.active.data
    cols = np.zeros((len(me.polygons), 3))
    for p in me.polygons:
        u = sum((uv[li].uv for li in p.loop_indices), Vector((0, 0))) / p.loop_total
        cols[p.index] = px[min(H - 1, max(0, int(u.y * H))), min(W - 1, max(0, int(u.x * W))), :3]
    blue = lambda c: c[2] > c[0] + 0.10 and c[2] > c[1] + 0.04
    bm = bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
    cen = np.array([f.calc_center_median()[:] for f in bm.faces])
    cand = [i for i in range(len(cen)) if blue(cols[i]) and cen[i][1] > 0.1 and 0.9 < cen[i][2] < 1.25 and abs(cen[i][0]) < 0.1]
    seed = max(cand, key=lambda i: cen[i][1])
    sel = {seed}; q = deque([seed])
    while q:
        f = bm.faces[q.popleft()]
        for e in f.edges:
            for g in e.link_faces:
                i = g.index
                if i in sel or cen[i][2] > CAPE_TOP or cen[i][2] < 0.6:
                    continue
                if blue(cols[i]) or (blue(cols[f.index]) and np.mean(cols[i]) < 0.25):
                    sel.add(i); q.append(i)
    outer = set()
    for i in sel:
        f = bm.faces[i]
        c = cen[i]
        o = Vector((c[0], c[1], 0.0))
        if o.length > 1e-6 and f.normal.dot(o.normalized()) > 0.2:
            outer.add(i)
    bm.free()
    return sel, outer


def spine_weights(z):
    hz = [(n, rig.data.bones["mixamorig:" + n].head_local.z) for n in SPINE]
    if z <= hz[0][1]:
        return {hz[0][0]: 1.0}
    if z >= hz[-1][1]:
        return {hz[-1][0]: 1.0}
    for (na, za), (nb, zb) in zip(hz, hz[1:]):
        if za <= z <= zb:
            t = (z - za) / (zb - za)
            return {na: 1.0 - t, nb: t}


# name, first bone, last bone, parent bone, lateral cap (m) that keeps other limbs out of the fit
COLLIDERS = [("torso", "Spine", "Spine1", "Spine", 0.17),   # lower back only: the shoulder blades are under the pinned rows
             ("pelvis", "Hips", "Hips", "Hips", 0.20),
             ("thigh_l", "LeftUpLeg", "LeftUpLeg", "LeftUpLeg", 0.11), ("thigh_r", "RightUpLeg", "RightUpLeg", "RightUpLeg", 0.11),
             ("shin_l", "LeftLeg", "LeftLeg", "LeftLeg", 0.10), ("shin_r", "RightLeg", "RightLeg", "RightLeg", 0.10),
             ("skirt", "Hips", "Hips", "Hips", 0.26)]
SKIRT_Z = (0.78, 1.12)  # the tunic's flared skirt and the belt stand out of the pelvis and thigh ellipsoids


def build_colliders(free_pts):
    """An ellipsoid per body part in the bone's frame, fitted to the body's own surface in a slab
    along the bone (front and back, left and right measured separately, so it sits in the real
    middle), 1.5 cm inside it and at least MARGIN clear of the free cloth at rest; the skirt's
    is fitted round it instead. No arm colliders: the arms come down through the cape's sides
    during the run-up from the T-pose."""
    MARGIN = 0.03
    V = np.array([v.co[:] for v in body.data.vertices])
    cloth = np.asarray(free_pts)
    made = []
    for name, first, last, parent, cap in COLLIDERS:
        b0, b1 = rig.data.bones["mixamorig:" + first], rig.data.bones["mixamorig:" + last]
        a, b = Vector(b0.head_local), Vector(b1.tail_local)
        M = rig.data.bones["mixamorig:" + parent].matrix_local.to_3x3()
        ax_y = (b - a).normalized()
        ax_x = M @ Vector((1, 0, 0))
        ax_x = (ax_x - ax_y * ax_x.dot(ax_y)).normalized()
        ax_z = ax_x.cross(ax_y)
        L = (b - a).length
        rel = V - np.array(a)
        lx, ly, lz = rel @ np.array(ax_x), rel @ np.array(ax_y), rel @ np.array(ax_z)
        m = (ly > 0.1 * L) & (ly < 0.9 * L) & (np.abs(lx) < cap) & (np.abs(lz) < cap + 0.08)
        x0, x1 = np.percentile(lx[m], [8, 92]); z0, z1 = np.percentile(lz[m], [8, 92])
        rx, rz = (x1 - x0) / 2 - 0.015, (z1 - z0) / 2 - 0.015
        ry = L / 2 + 0.4 * min(rx, rz)
        c = a + ax_y * (L / 2) + ax_x * float((x0 + x1) / 2) + ax_z * float((z0 + z1) / 2)
        if name == "skirt":
            # Upright, round the back half of the skirt and belt, 2 cm outside them: when the
            # step into lane turns his body 70 degrees, the cape's lower part swung in under
            # the skirt and showed it and the belt's fringe through.
            ax_x, ax_y, ax_z = Vector((1, 0, 0)), Vector((0, 0, 1)), Vector((0, -1, 0))
            sl = V[(V[:, 2] > SKIRT_Z[0]) & (V[:, 2] < SKIRT_Z[1]) & (np.abs(V[:, 0]) < cap)]
            c = Vector((float(sl[:, 0].min() + sl[:, 0].max()) / 2, float(sl[:, 1].min() + sl[:, 1].max()) / 2, sum(SKIRT_Z) / 2))
            q = sl - np.array(c)
            back = q[q[:, 1] > 0]
            rx, ry, rz = float(np.abs(q[:, 0]).max()), (SKIRT_Z[1] - SKIRT_Z[0]) / 2, float(back[:, 1].max())
            grow = float(np.sqrt((back[:, 0] / rx) ** 2 + (back[:, 2] / ry) ** 2 + (back[:, 1] / rz) ** 2).max())
            rx, ry, rz = rx * grow + 0.02, ry * grow + 0.02, rz * grow + 0.02
        if name == "torso":
            # Kept well below the pinned rows: with its dome right under them the cloth piled
            # up on top of it and never fell.
            ry *= 0.75; rx -= 0.02; rz -= 0.02
            c = c - ax_y * 0.04
        R = np.array([ax_x, ax_y, ax_z])
        for _ in range(30):
            q = (cloth - np.array(c)) @ R.T
            if not np.any((q[:, 0] / (rx + MARGIN)) ** 2 + (q[:, 1] / (ry + MARGIN)) ** 2 + (q[:, 2] / (rz + MARGIN)) ** 2 < 1.0):
                break
            rx *= 0.95; rz *= 0.95
        bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=14, radius=1.0)
        e = bpy.context.active_object
        e.name = "CapeCollider_" + name
        Mw = Matrix((ax_x * rx, ax_y * ry, ax_z * rz)).transposed().to_4x4()
        Mw.translation = c
        e.matrix_world = Mw
        e.hide_render = True
        e.display_type = "WIRE"
        mw = e.matrix_world.copy()
        e.parent = rig; e.parent_type = "BONE"; e.parent_bone = "mixamorig:" + parent
        e.matrix_world = mw
        e.modifiers.new("Collision", "COLLISION")
        e.collision.thickness_outer = 0.012
        e.collision.cloth_friction = 2
        made.append((name, round(float(rx), 3), round(float(ry), 3), round(float(rz), 3)))
    print("CAPE colliders", made)


def ground_collision(ground):
    """Single sided, normal up: cloth that a falling body pins through the ground is pushed
    back on top instead of sinking (Death 2 sank 66 cm with a two-sided plane)."""
    ground.collision.thickness_outer = 0.02
    ground.collision.use_culling = True
    ground.collision.use_normal = True


def flatten_back(me):
    """His lower back under the cape: the belt's fringe and buckles, the leather pouch on his
    right hip (5-9 cm proud) and the tunic stand out of the ellipsoids, and in the step into
    lane, his body turned 70 degrees, they showed through the cloth. Everything behind
    BACK_LINE in BACK_BOX is pressed towards it, BACK_KEEP of its depth kept, easing out over
    3 cm at the box's edges. The cape always covers it."""
    (x0, x1), (z0, z1) = BACK_BOX
    n = 0
    for v in me.vertices:
        x, y, z = v.co
        if x0 < x < x1 and z0 < z < z1 and y > BACK_LINE:
            edge = min(x - x0, x1 - x, z - z0, z1 - z) / 0.03
            k = 1.0 - (1.0 - BACK_KEEP) * min(1.0, edge)
            v.co.y = BACK_LINE + (y - BACK_LINE) * k
            n += 1
    print("CAPE back flattened", n, "vertices")


def setup():
    me = body.data
    region, outer = cape_faces(me)
    print("CAPE region faces", len(region), "outer layer", len(outer))
    bpy.context.view_layer.objects.active = body
    for o in list(bpy.context.selected_objects):
        o.select_set(False)
    body.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_mode(type="FACE")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    for p in me.polygons:
        p.select = p.index in outer
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.duplicate()
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    capeo = next(o for o in bpy.context.selected_objects if o is not body)
    capeo.name = capeo.data.name = "Cape"
    for p in me.polygons:
        p.select = p.index in region
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.delete(type="FACE")
    bpy.ops.object.mode_set(mode="OBJECT")
    # Clean the cloth: weld slivers, then weights (spine by height), pins and the pinned group.
    cbm = bmesh.new(); cbm.from_mesh(capeo.data)
    nv = len(cbm.verts)
    bmesh.ops.remove_doubles(cbm, verts=cbm.verts, dist=0.0015)
    bmesh.ops.dissolve_degenerate(cbm, edges=cbm.edges, dist=0.0008)
    cbm.to_mesh(capeo.data); cbm.free()
    for g in list(capeo.vertex_groups):
        capeo.vertex_groups.remove(g)
    for m in list(capeo.modifiers):
        capeo.modifiers.remove(m)
    for n in SPINE:
        capeo.vertex_groups.new(name="mixamorig:" + n)
    pin = capeo.vertex_groups.new(name="pin")
    pinned = capeo.vertex_groups.new(name="pinned")   # left out of object collisions
    free_pts = []
    for v in capeo.data.vertices:
        for n, w in spine_weights(v.co.z).items():
            capeo.vertex_groups["mixamorig:" + n].add([v.index], w, "REPLACE")
        pw = min(1.0, max(0.0, (v.co.z - PIN_BOTTOM) / (PIN_TOP - PIN_BOTTOM)))
        if pw > 0:
            pin.add([v.index], pw, "REPLACE")
        if pw < 0.3:
            free_pts.append(tuple(v.co))
        else:
            pinned.add([v.index], 1.0, "REPLACE")
    for p in capeo.data.polygons:
        p.use_smooth = True
    print("CAPE cloth verts", len(capeo.data.vertices), "welded", nv - len(capeo.data.vertices), "free", len(free_pts))
    arm = capeo.modifiers.new("Armature", "ARMATURE"); arm.object = rig
    cl = capeo.modifiers.new("Cloth", "CLOTH")
    cl.show_viewport = False             # on only while "sim" runs: retarget_clips.py and spear_motion.py step through frames
    s = cl.settings
    s.quality = 12
    s.mass = CAPE_KG / len(capeo.data.vertices)
    s.air_damping = 0.5
    s.tension_stiffness = s.compression_stiffness = 15
    s.shear_stiffness = 5
    s.bending_stiffness = 0.08          # soft enough that the T-pose flare collapses into hanging folds
    s.tension_damping = s.compression_damping = s.shear_damping = 5
    s.bending_damping = 0.3
    s.vertex_group_mass = "pin"
    s.pin_stiffness = 1.0
    cs = cl.collision_settings
    cs.collision_quality = 5
    cs.distance_min = 0.012
    cs.use_self_collision = False
    cs.vertex_group_object_collisions = "pinned"   # Blender leaves out the triangles all in this group
    sol = capeo.modifiers.new("Solidify", "SOLIDIFY")
    sol.thickness = 0.010
    sol.offset = -1.0
    sol.use_even_offset = False         # even thickness throws spikes off folded cloth
    sol.use_quality_normals = True
    flatten_back(me)
    build_colliders(free_pts)
    bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0, 0))
    ground = bpy.context.active_object
    ground.name = "CapeGround"
    ground.hide_render = True
    ground.modifiers.new("Collision", "COLLISION")
    ground_collision(ground)
    bpy.ops.wm.save_mainfile(compress=True)
    print("CAPE_SETUP_SAVED")


def write_pc2(path, frames):
    n = len(frames[0])
    with open(path, "wb") as f:
        f.write(struct.pack("<12siiffi", b"POINTCACHE2\0", 1, n, 1.0, 1.0, len(frames)))
        for fr in frames:
            f.write(np.asarray(fr, dtype="<f4").tobytes())


def sim(cache_dir, clips):
    cache_dir.mkdir(parents=True, exist_ok=True)
    capeo = bpy.data.objects["Cape"]
    assert capeo.matrix_world == Matrix.Identity(4) and rig.matrix_world == Matrix.Identity(4)   # cache space = ground space
    cl = capeo.modifiers["Cloth"]
    ground_collision(bpy.data.objects["CapeGround"])
    for m in list(capeo.modifiers):
        if m.type == "MESH_CACHE":
            capeo.modifiers.remove(m)
    for m in capeo.modifiers:
        m.show_viewport = m.type != "SOLIDIFY"
    bones = list(rig.pose.bones)
    for pb in bones:
        # No clip keys these (spear_motion.py clear_unkeyed). Float noise left on them, which
        # the chaotic cloth turns into a different cape, once made bakes depend on the file.
        pb.scale = (1, 1, 1)
        if pb.name != "mixamorig:Hips":
            pb.location = (0, 0, 0)
    for clip in clips:
        act = bpy.data.actions[clip]
        n = int(act["frames"])
        loop = clip in LOOPS
        total = (2 if loop else 1) * n
        rig.animation_data_create()
        rig.animation_data.action = act
        poses = {}
        for f in range(1, n + 1):
            sc.frame_set(f)
            poses[f] = [(pb.rotation_quaternion.copy(), pb.location.copy()) for pb in bones]
        tmp = bpy.data.actions.new("_capesim_" + clip)
        rig.animation_data.action = tmp
        start = 1 - PREROLL
        for pb in bones:
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = (1, 0, 0, 0); pb.location = (0, 0, 0)
            pb.keyframe_insert("rotation_quaternion", frame=start)
            pb.keyframe_insert("location", frame=start)
        for t in [1 - PREROLL_HOLD] + list(range(1, total + 1)):
            src = ((t - 1) % n) + 1 if t >= 1 else 1
            for pb, (q, loc) in zip(bones, poses[src]):
                pb.rotation_quaternion = q; pb.location = loc
                pb.keyframe_insert("rotation_quaternion", frame=t)
                pb.keyframe_insert("location", frame=t)
        sc.frame_start, sc.frame_end = start, total
        cl.point_cache.frame_start, cl.point_cache.frame_end = start, total
        rows = {}
        for f in range(start, total + 1):
            sc.frame_set(f)
            if f >= 1:
                ev = capeo.evaluated_get(bpy.context.evaluated_depsgraph_get())
                rows[f] = np.array([v.co[:] for v in ev.data.vertices], dtype=np.float32)
        rig.animation_data.action = act
        bpy.data.actions.remove(tmp)
        keep = list(range(n + 1, 2 * n + 1)) if loop else list(range(1, n + 1))
        # Lying on his back, cloth caught between his hips and the ground can be squeezed
        # through it, and the pinned rows ride a few cm under with the spine: put it on the ground.
        frames = [np.concatenate([rows[f][:, :2], np.maximum(rows[f][:, 2:], GROUND_CLEAR)], axis=1) for f in keep]
        if loop:
            first = frames[0]
            for k in range(SEAM):
                i = len(frames) - SEAM + k
                w = (k + 1) / (SEAM + 1)
                w = w * w * (3 - 2 * w)
                frames[i] = frames[i] * (1 - w) + first * w
        write_pc2(cache_dir / f"{clip}.pc2", frames)
        ext = max(float(np.max(np.ptp(fr, axis=0))) for fr in frames)
        low = min(float(fr[:, 2].min()) for fr in frames)
        print("CAPE_SIM", clip, "frames", len(frames), "verts", len(frames[0]), "loop" if loop else "", "largest extent %.2f m, lowest %.2f m" % (ext, low))
    for m in capeo.modifiers:
        m.show_viewport = m.type != "CLOTH"


if mode == "setup":
    setup()
elif mode == "sim":
    cache = Path(argv[1])
    clips = argv[2].split(",") if len(argv) > 2 and argv[2] else ["idle", "idle_rest", "walk", "attack", "hit", "death", "death_2", "death_3", "turn_90", "step_lane"]
    sim(cache, clips)
