"""Export the goblin spearman with his clips for the Godot 3D sandbox (background Blender), as
goblin_rabble/tools/export_godot.py.

  blender -b spear_clips.blend --python export_godot.py -- <out.glb> [texture_px]

Reads the scratch copy of the rig that retarget_clips.py saves (its clips are Mixamo motion,
so the export stays local like the rabble's), and works on the open copy only (nothing is
saved):
  * the bone widgets go; the spear stays;
  * every clip is baked, frame by frame, from the evaluated pose (the grips' Action
    constraints and their keyed influence, the left hand's hold on the shaft through
    `support_ik`, the forearm twist, the cape's and the flaps' drivers and the keyed Spear
    bone) onto plain keys of the deforming bones plus Spear; then the constraints, drivers
    and the grip and stand actions go, so Godot plays exactly the baked pose;
  * the spear is skinned (weight 1) to the Spear bone instead of parented to it;
  * textures scaled down to `texture_px` (default 1024, JPEG);
  * a sidecar <out>.json as the rabble's: per clip its length, loop, frames, ground speed in
    Godot axes (x, z, -y of Blender; the model faces +Z), turn, hips drift and events (the
    thrust's `contact`, footfalls, the spear's drop, death settled), plus `roles`.
The walk and idle are in place; the walk's speed is the travel retarget_clips.py removed
(the action's root_vel), checked against how fast his planted foot slides back.
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
KEEP_PROPS = ("Spear",)
CLIPS = ["idle", "walk", "attack", "death"]
LOOPS = {"idle", "walk"}
sc = bpy.context.scene
sc.render.fps = int(FPS)
rig = bpy.data.objects["GoblinSpearmanRig"]
body = bpy.data.objects["GoblinSpearman"]
assert rig.matrix_world == Matrix.Identity(4)
PB = rig.pose.bones
MX = "mixamorig:"
CLIPS = [c for c in CLIPS if c in bpy.data.actions and "frames" in bpy.data.actions[c]]
print("EXPORT clips", CLIPS)

for p in ("spear_ik", "leg_ik"):
    assert rig[p] == 0, p
rig.update_tag()
bpy.context.view_layer.update()

# The bones that go out: every deforming bone, and the one the spear rides.
rig.data.bones["Spear"].use_deform = True
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


# The spear's tip: its highest vertex in its own space (the shaft on z, the head up).
weapon = bpy.data.objects["Spear"]
TIP = max((v.co for v in weapon.data.vertices), key=lambda c: c.z).copy()
W_LOCAL = weapon.matrix_parent_inverse @ weapon.matrix_basis
marks = {}


def tip_world():
    pb = PB["Spear"]
    return rig.matrix_world @ pb.matrix @ Matrix.Translation((0, pb.bone.length, 0)) @ W_LOCAL @ TIP


# 1. Sample every clip from the evaluated pose (constraints and drivers included).
pose, samp, src_vel = {}, {}, {}
height = None
for name in CLIPS:
    act = bpy.data.actions[name]
    use(act)
    n = int(act["frames"])
    src_vel[name] = list(act.get("root_vel", [0.0, 0.0]))
    marks[name] = {k: int(act[k]) for k in ("spear_release",) if k in act}
    mats = []
    d = {"hips": [], "yaw": [], "ank": {"Left": [], "Right": []}, "foot": {"Left": [], "Right": []},
         "toe": {"Left": [], "Right": []}, "tip": []}
    for f in range(1, n + 1):
        sc.frame_set(f)
        mats.append({bn: PB[bn].matrix.copy() for bn in OUT_BONES})
        d["hips"].append(b("Hips").head.copy())
        d["yaw"].append(hips_yaw())
        for s in ("Left", "Right"):
            d["ank"][s].append(b(s + "Foot").head.z)
            d["foot"][s].append(b(s + "Foot").head.copy())
            d["toe"][s].append(b(s + "ToeBase").head.copy())
        d["tip"].append(tip_world())
        if name == "idle" and f == 1:
            ev = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
            height = max((ev.matrix_world @ v.co).z for v in ev.data.vertices)
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
    curves = {}
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

# 4. Only this loadout's props, skinned to their bones in the rest pose.
for o in list(bpy.data.objects):
    if o.name.startswith("WGT_") or (o.type == "MESH" and o not in (body,) and o.name not in KEEP_PROPS):
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


def steps_of(d, t, fr, stance=4):
    """Footfalls: an ankle coming down within 2 cm of its lowest and staying there `stance`
    frames or more (a shorter touch is the swinging foot scuffing the ground)."""
    steps = []
    for s, z in d["ank"].items():
        z = np.array(z)
        gnd = z < z.min() + 0.02
        for k in range(1, len(gnd)):
            if gnd[k] and not gnd[k - 1]:
                run = next((j for j in range(k, len(gnd)) if not gnd[j]), len(gnd)) - k
                print("STEP %s frame %d: down %d frames" % (s, fr[k], run))
                if run >= stance or k + run == len(gnd):
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
    if name == "walk":
        # The travel retarget_clips.py removed (the action's root_vel, Blender x and y, m/s).
        vel = Vector((src_vel[name][0], src_vel[name][1], 0.0))
        info["root_vel"] = to_godot(vel)
        info["speed_mps"] = round(vel.length, 4)
        info["travel_from"] = "source clip"
        info["events"]["steps"] = steps_of(d, t, fr)
        fl = footlock(d)
        info["speed_footlock_mps"] = round(float(np.median(np.linalg.norm(fl, axis=1))) * FPS, 4)
    if name == "attack":
        tip = d["tip"]
        h0 = d["hips"][0]
        fwd = [-(p.y - h0.y) for p in tip]
        k_back = int(np.argmin(fwd[:int(n * 0.6)]))
        k_hit = k_back + int(np.argmax(fwd[k_back:]))
        spd = [(tip[k + 1] - tip[k]).length * FPS for k in range(n - 1)]
        info["events"]["contact"] = t(fr[k_hit])
        info["events"]["thrust"] = [t(fr[k_back]), t(fr[k_hit])]
        info["tip_reach_m"] = round(fwd[k_hit], 3)
        info["tip_height_m"] = round(tip[k_hit].z, 3)
        info["lead_m"] = round(-(d["hips"][k_hit].y - h0.y), 3)
        info["tip_speed_max_mps"] = round(max(spd), 2)
        print("ATTACK tip per frame (forward m, height m, speed m/s):",
              [(k + 1, round(fwd[k], 2), round(tip[k].z, 2), round(spd[min(k, n - 2)], 1)) for k in range(n)])
    if name == "death":
        hips = d["hips"]
        still = n - 1
        while still > 1 and (hips[still] - hips[still - 1]).length < 0.003:
            still -= 1
        info["events"]["settled"] = t(fr[still])
        if "spear_release" in marks[name]:
            info["events"]["spear_drop"] = t(marks[name]["spear_release"])
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
roles = {"idle": "idle", "walk": "walk", "attack": ["attack"], "death": ["death"]}
notes = [
    "Clips are baked from the rig's evaluated pose (both grips, the left hand's hold on the shaft, forearm "
    "twist, the cape and the skirt flaps, and the keyed spear); no constraints or drivers go out. The spear is "
    "skinned to the bone Spear (child of mixamorig:RightHand).",
    "Locomotion is in place. walk moves the figure by root_vel (m/s, Godot axes): the travel "
    "retarget_clips.py removed (travel_from); speed_footlock_mps is how fast his planted foot slides back. "
    "idle stands still with the spear levelled in both hands, as does the walk. The death keeps its authored "
    "travel on the hips (root_motion true, hips_drift); do not add it again.",
    "attack is a two-handed thrust: events.contact is when the spear's tip is furthest forward after it is "
    "drawn back (tip_reach_m from where he stood, at tip_height_m); events.thrust spans the drive.",
    "death: events.spear_drop is when his right fist lets go; the Spear bone then lays the spear on the ground.",
    "No hit clip: the sandbox flinches procedurally.",
    "Godot imports every clip with loop mode none; set it from clips.<clip>.loop. Animation names equal the "
    "clip names (clips.<clip>.anim).",
]
meta = {"fps": FPS, "source": "projects/meridius/references/characters/blender/goblin_spear/goblin_spear_rig.blend",
        "props": list(KEEP_PROPS), "forward": [0, 0, 1],
        "height_m": round(float(height), 3),
        "height_rest_m": round(float(max(v.co.z for v in body.data.vertices)), 3),
        "roles": roles, "notes": notes,
        "objects": sorted(o.name for o in meshes), "bones": len(OUT_BONES), "triangles": sum(tris.values()),
        "texture_px": max([s[0] for s in textures.values()] or [0]), "clips": clips}
OUT.with_suffix(".json").write_text(json.dumps(meta, indent=1))
print("EXPORT_DONE", OUT, OUT.stat().st_size, "in %.1fs" % (time.time() - T0))
