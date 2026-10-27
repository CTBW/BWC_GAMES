"""Export a goblin shaman with his clips for the Godot 3D sandbox (background Blender), as
goblin_spear/tools/export_godot.py.

  blender -b <skull|beak>_clips.blend --python export_godot.py -- <out.glb> [texture_px]

Reads the scratch copy of either rig that retarget_clips.py saves (its clips are Mixamo motion,
so the export stays local like the other goblins'), and works on the open copy only (nothing is
saved):
  * the bone widgets go; the staff and the mask stay;
  * every clip is baked, frame by frame, from the evaluated pose (the grips' Action constraints
    and their keyed influence, the wrist's hold on the staff through `StaffHold`, the forearm
    twist and the keyed Staff bone) onto plain keys of the deforming bones plus Staff and Mask;
    then the constraints, drivers and the grip and stand actions go, so Godot plays exactly the
    baked pose;
  * the staff and the mask are skinned (weight 1) to the Staff and Mask bones instead of
    parented to them;
  * textures scaled down to `texture_px` (default 1024, JPEG);
  * a sidecar <out>.json as the spearman's: per clip its length, loop, frames, ground speed in
    Godot axes (x, z, -y of Blender; the model faces +Z), turn, hips drift and events
    (footfalls, the staff's drop and when it lies flat, death settled), plus `roles`.
The walk and idle are in place; the walk's speed is the travel retarget_clips.py removed (the
action's root_vel), checked against how fast his planted foot slides back.
"""
import json
import math
import sys
import time
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = Path(argv[0])
TEX = int(argv[1]) if len(argv) > 1 else 1024
FPS = 30.0
T0 = time.time()
KEEP_PROPS = ("Staff", "MaskPlate")
CLIPS = ["idle", "walk", "death"]
LOOPS = {"idle", "walk"}
sc = bpy.context.scene
sc.render.fps = int(FPS)
rig = bpy.data.objects["GoblinShamanRig"]
body = bpy.data.objects["GoblinShaman"]
mask = bpy.data.objects["MaskPlate"]
assert rig.matrix_world == Matrix.Identity(4)
PB = rig.pose.bones
MX = "mixamorig:"
VARIANT = "beak" if any(s.material and "Beak" in s.material.name for s in mask.material_slots) else "skull"
RIG_BLEND = {"skull": "goblin_shaman_rig.blend", "beak": "goblin_shaman_beak_rig.blend"}[VARIANT]
CLIPS = [c for c in CLIPS if c in bpy.data.actions and "frames" in bpy.data.actions[c]]
print("EXPORT", VARIANT, "clips", CLIPS)

for p in ("staff_ik", "cast_ik", "leg_ik"):
    assert rig[p] == 0, p
assert rig["staff_hold"] == 1
rig.update_tag()
bpy.context.view_layer.update()

# The bones that go out: every deforming bone, and the two the props ride.
for n in ("Staff", "Mask"):
    rig.data.bones[n].use_deform = True
OUT_BONES = [b.name for b in rig.data.bones if b.use_deform]
OUT_SET = set(OUT_BONES)
for n in OUT_BONES:
    b = rig.data.bones[n]
    assert b.parent is None or b.parent.name in OUT_SET, (n, b.parent.name)
    assert b.use_inherit_rotation and b.inherit_scale == "FULL" and (b.use_local_location or b.use_connect), n
print("BONES out", len(OUT_BONES), "of", len(rig.data.bones))


def b(n):
    return PB[MX + n]


def to_godot(v):
    # glTF / Godot: x, z, -y of Blender.
    return [round(float(v[0]), 4), round(float(v[2]), 4), round(float(-v[1]), 4)]


def hips_yaw():
    # Facing of the hips about Z, from the hip line (his right is -X at rest, he faces -Y).
    r = b("RightUpLeg").head - b("LeftUpLeg").head
    fwd = Vector((0, 0, 1)).cross(r)
    return math.degrees(math.atan2(fwd.x, -fwd.y))


def use(act):
    rig.animation_data.action = act
    if act.slots:
        rig.animation_data.action_slot = act.slots[0]


def world_z(o, local):
    """The heights of an object's vertices (local, n x 3) in the evaluated scene."""
    M = np.array(o.evaluated_get(bpy.context.evaluated_depsgraph_get()).matrix_world)
    return local @ M[2, :3] + M[2, 3]


staff = bpy.data.objects["Staff"]
STAFF_V = np.array([v.co[:] for v in staff.data.vertices])
marks = {}

# 1. Sample every clip from the evaluated pose (constraints and drivers included).
pose, samp, src_vel = {}, {}, {}
height = staff_top = None
for name in CLIPS:
    act = bpy.data.actions[name]
    use(act)
    n = int(act["frames"])
    src_vel[name] = list(act.get("root_vel", [0.0, 0.0]))
    marks[name] = {k: int(act[k]) for k in ("staff_release",) if k in act}
    mats = []
    d = {"hips": [], "yaw": [], "foot": {"Left": [], "Right": []},
         "toe": {"Left": [], "Right": []}, "staff_lo": [], "staff_hi": []}
    for f in range(1, n + 1):
        sc.frame_set(f)
        mats.append({bn: PB[bn].matrix.copy() for bn in OUT_BONES})
        d["hips"].append(b("Hips").head.copy())
        d["yaw"].append(hips_yaw())
        for s in ("Left", "Right"):
            d["foot"][s].append(b(s + "Foot").head.copy())
            d["toe"][s].append(b(s + "ToeBase").head.copy())
        z = world_z(staff, STAFF_V)
        d["staff_lo"].append(float(z.min()))
        d["staff_hi"].append(float(z.max()))
        if name == "idle" and f == 1:
            dg = bpy.context.evaluated_depsgraph_get()
            height = max(max((o.evaluated_get(dg).matrix_world @ v.co).z for v in o.evaluated_get(dg).data.vertices)
                         for o in (body, mask))
            staff_top = float(z.max())
    pose[name], samp[name] = mats, d
print("SAMPLED %d clips in %.1fs" % (len(CLIPS), time.time() - T0))

# 2. Strip the rig to plain FK: no constraints, no drivers, no other actions.
for pb in PB:
    for c in list(pb.constraints):
        pb.constraints.remove(c)
for idb in [rig, rig.data] + list(bpy.data.objects):
    ad = idb.animation_data
    if ad:
        for dr in list(ad.drivers):
            ad.drivers.remove(dr)
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)

# 3. Key the baked poses: basis = (parent_rest^-1 rest)^-1 parent_pose^-1 pose.
REST = {bn: rig.data.bones[bn].matrix_local.copy() for bn in OUT_BONES}
for bn in OUT_BONES:
    PB[bn].rotation_mode = "QUATERNION"
baked = {}
for name in CLIPS:
    mats = pose[name]
    n = len(mats)
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data.action = act
    for bn in OUT_BONES:
        par = rig.data.bones[bn].parent
        prev = None
        loc, rot, scl = [], [], []
        for k in range(n):
            M = mats[k][bn]
            if par is None:
                basis = REST[bn].inverted() @ M
            else:
                basis = (REST[par.name].inverted() @ REST[bn]).inverted() @ mats[k][par.name].inverted() @ M
            l_, q, s_ = basis.decompose()
            if prev is not None:
                q.make_compatible(prev)
            prev = q
            loc.append(l_), rot.append(q), scl.append(s_)
        for path, vals, size in (("location", loc, 3), ("rotation_quaternion", rot, 4), ("scale", scl, 3)):
            for i in range(size):
                fc = act.fcurve_ensure_for_datablock(rig, f'pose.bones["{bn}"].{path}', index=i, group_name=bn)
                fc.keyframe_points.add(n)
                co = np.empty(2 * n)
                co[0::2] = np.arange(1, n + 1)
                co[1::2] = [v[i] for v in vals]
                fc.keyframe_points.foreach_set("co", co.tolist())
                fc.keyframe_points.foreach_set("interpolation", [1] * n)   # LINEAR
                fc.update()
    act["frames"] = n
    act.use_frame_range = True
    act.frame_range = (1, n)
    baked[name] = act

# The bake must reproduce the sampled pose.
worst = 0.0
for name in CLIPS:
    use(baked[name])
    for k in sorted({0, len(pose[name]) // 3, 2 * len(pose[name]) // 3, len(pose[name]) - 1}):
        sc.frame_set(k + 1)
        for bn in OUT_BONES:
            worst = max(worst, (PB[bn].matrix.translation - pose[name][k][bn].translation).length,
                        (PB[bn].tail - pose[name][k][bn] @ Vector((0, PB[bn].bone.length, 0))).length)
print("BAKE worst bone error %.2e m" % worst)
assert worst < 1e-4, worst

# 4. Only the body, the staff and the mask, the props skinned to their bones in the rest pose.
for o in list(bpy.data.objects):
    if o.name.startswith("WGT_") or (o.type == "MESH" and o is not body and o.name not in KEEP_PROPS):
        bpy.data.objects.remove(o, do_unlink=True)
for pb in PB:
    pb.custom_shape = None
for nm in KEEP_PROPS:
    o = bpy.data.objects[nm]
    bone = rig.data.bones[o.parent_bone]
    mw = rig.matrix_world @ bone.matrix_local @ Matrix.Translation((0, bone.length, 0)) @ o.matrix_parent_inverse @ o.matrix_basis
    o.parent_type = "OBJECT"
    o.parent_bone = ""
    o.parent = rig
    o.matrix_parent_inverse = Matrix.Identity(4)
    o.matrix_basis = Matrix.Identity(4)
    o.data.transform(mw)
    o.vertex_groups.clear()
    g = o.vertex_groups.new(name=bone.name)
    g.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
    o.modifiers.new("Armature", "ARMATURE").object = rig
    o.hide_viewport = o.hide_render = False
    o.hide_set(False)
print("PROPS skinned", {nm: bpy.data.objects[nm].vertex_groups[0].name for nm in KEEP_PROPS})
for o in bpy.data.objects:
    if o.type == "MESH":
        for v in o.data.vertices:
            for g in v.groups:
                if g.weight > 1.0:
                    g.weight = 1.0


def steps_of(d, t, fr, vel, stance=4, slip=0.2):
    """Footfalls in an in-place loop: the first frame of each stance, where an ankle that swung
    forward moves back with the ground (vel, m/s) to within `slip` of its speed and keeps doing
    so `stance` frames or more. His crouched walk lands heel first with the ankle still well
    up, so the ankle's height alone finds the stance late."""
    g = Vector((vel.x, vel.y, 0.0)) / FPS
    steps = []
    for s, ps in d["foot"].items():
        n = len(ps)       # the loop's last frame repeats its first
        held = [((ps[(k + 1) % (n - 1)] - ps[k % (n - 1)]).to_2d() + g.to_2d()).length < slip * g.length
                for k in range(n - 1)]
        for k in range(n - 1):
            if held[k] and not held[k - 1]:
                run = next((j for j in range(1, n) if not held[(k + j) % (n - 1)]), n)
                print("STEP %s frame %d: held %d frames" % (s, fr[k], run))
                if run >= stance:
                    steps.append([t(fr[k]), s])
    return sorted(steps)


def footlock(d):
    """How fast his planted foot slides back (m/frame per frame): the lowest of his ankles and
    toes, each against its own lowest point."""
    pts = [d[p][s_] for p in ("foot", "toe") for s_ in ("Left", "Right")]
    lo = [min(q.z for q in pt) for pt in pts]
    v = []
    for k in range(len(d["hips"]) - 1):
        j = min(range(len(pts)), key=lambda j_: pts[j_][k].z - lo[j_])
        dv = pts[j][k + 1] - pts[j][k]
        v.append((-dv.x, -dv.y))
    return np.array(v)


# 5. The sidecar's clips.
clips = {}
for name in CLIPS:
    d = samp[name]
    n = len(pose[name])
    fr = list(range(1, n + 1))
    t = lambda f: round((f - 1) / FPS, 4)
    info = {
        "anim": name,
        "length": t(fr[-1]),
        "loop": name in LOOPS,
        "frames": n,
        "root_vel": [0.0, 0.0, 0.0],
        "root_motion": name == "death",
        "turn_deg": round(((d["yaw"][-1] - d["yaw"][0] + 180) % 360) - 180, 1),
        "hips_drift": to_godot(d["hips"][-1] - d["hips"][0]),
        "events": {},
    }
    if name in LOOPS:
        a0, a1 = pose[name][0], pose[name][-1]
        info["loop_seam_cm"] = round(100 * max((a1[bn].translation - a0[bn].translation).length for bn in OUT_BONES), 2)
        info["staff_foot_m"] = [round(min(d["staff_lo"]), 3), round(max(d["staff_lo"]), 3)]
    if name == "walk":
        # The travel retarget_clips.py removed (the action's root_vel, Blender x and y, m/s).
        vel = Vector((src_vel[name][0], src_vel[name][1], 0.0))
        info["root_vel"] = to_godot(vel)
        info["speed_mps"] = round(vel.length, 4)
        info["travel_from"] = "source clip"
        info["events"]["steps"] = steps_of(d, t, fr, vel)
        fl = footlock(d)
        info["speed_footlock_mps"] = round(float(np.median(np.linalg.norm(fl, axis=1))) * FPS, 4)
    if name == "death":
        hips = d["hips"]
        still = n - 1
        while still > 1 and (hips[still] - hips[still - 1]).length < 0.003:
            still -= 1
        info["events"]["settled"] = t(fr[still])
        rel = marks[name].get("staff_release")
        assert rel, "the death has no staff_release: rerun retarget_clips.py"
        info["events"]["staff_drop"] = t(rel)
        # Flat on the ground: its highest point within 1 cm of where it ends up.
        hi = d["staff_hi"]
        down = next(k for k in range(rel, n) if all(h <= hi[-1] + 0.01 for h in hi[k:]))
        info["events"]["staff_down"] = t(fr[down])
    clips[name] = info
    print("CLIP", name, json.dumps(info))

# 6. Export.
use(baked["idle"])
sc.frame_set(1)
textures = {}
for img in bpy.data.images:
    if img.users == 0 or img.size[0] == 0:
        continue
    if img.size[0] > TEX:
        img.scale(TEX, TEX)
        img.file_format = "JPEG"
    textures[img.name] = list(img.size)
    print("TEXTURE", img.name, tuple(img.size), img.file_format)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
tris = {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes}
print("TRIANGLES", tris, sum(tris.values()))
for o in bpy.data.objects:
    o.select_set(o is rig or o in meshes)
OUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=str(OUT), export_format="GLB", export_yup=True, export_apply=False,
    export_image_format="AUTO", export_jpeg_quality=88,
    export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True,
    export_frame_range=False, export_anim_slide_to_zero=True, export_anim_single_armature=True, export_reset_pose_bones=True,
    export_def_bones=True, export_optimize_animation_size=False, export_bake_animation=False,
    export_morph=False, export_all_influences=False,
    export_extras=False, export_cameras=False, export_lights=False, use_selection=True,
)
roles = {"idle": "idle", "walk": "walk", "death": ["death"]}
notes = [
    "Clips are baked from the rig's evaluated pose (both hands' grips, the wrist's hold on the staff, forearm "
    "twist and the keyed staff); no constraints or drivers go out. The staff is skinned to the bone Staff (child "
    "of mixamorig:RightHand), the mask to the bone Mask (child of mixamorig:Head).",
    "Locomotion is in place. walk moves the figure by root_vel (m/s, Godot axes): the travel retarget_clips.py "
    "removed (travel_from); speed_footlock_mps is how fast his planted foot slides back. In the idle and the walk "
    "he carries the staff upright in front of his right side with its foot off the ground (staff_foot_m, its "
    "lowest point's height). The death keeps its authored travel on the hips (root_motion true, hips_drift); do "
    "not add it again.",
    "death: events.staff_drop is when his right fist lets go; the Staff bone then lays the staff on the ground, "
    "flat from events.staff_down.",
    "No attack or hit clip: he will mostly cast spells, and there is no cast clip yet; the sandbox flinches "
    "procedurally.",
    "height_m is his top in the idle's first frame, the mask included; the staff reaches staff_top_m.",
    "Godot imports every clip with loop mode none; set it from clips.<clip>.loop. Animation names equal the clip "
    "names (clips.<clip>.anim).",
]
meta = {"fps": FPS, "source": "projects/meridius/references/characters/blender/goblin_shaman/" + RIG_BLEND,
        "variant": VARIANT, "props": list(KEEP_PROPS), "forward": [0, 0, 1],
        "height_m": round(float(height), 3),
        "height_rest_m": round(float(max(max(v.co.z for v in o.data.vertices) for o in (body, mask))), 3),
        "staff_top_m": round(staff_top, 3),
        "roles": roles, "notes": notes,
        "objects": sorted(o.name for o in meshes), "bones": len(OUT_BONES), "triangles": sum(tris.values()),
        "texture_px": max([s[0] for s in textures.values()] or [0]), "clips": clips}
OUT.with_suffix(".json").write_bytes((json.dumps(meta, indent=1) + "\n").encode("utf-8"))
print("EXPORT_DONE", OUT, OUT.stat().st_size, "in %.1fs" % (time.time() - T0))
