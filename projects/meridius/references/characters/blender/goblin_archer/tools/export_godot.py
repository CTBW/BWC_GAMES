"""Export the archer with his clips for the Godot 3D sandbox (background Blender), as
goblin_rabble/tools/export_godot.py.

  blender -b archer_clips.blend --python export_godot.py -- <out.glb> [texture_px]

Reads the scratch copy of the rig that retarget_clips.py saves (its clips are Mixamo motion,
so the export stays local like the rabble's), and works on the open copy only (nothing is
saved):
  * the bone widgets go; the bow, quiver and arrow stay;
  * every clip is baked, frame by frame, from the evaluated pose (the grips' Action
    constraints, the hand's hold on the bow, the forearm twist, the cape's drivers and its
    keyed `cape_back`, the keyed String and Bow bones) onto plain keys of the deforming
    bones plus Bow, String, Quiver and Arrow; then the constraints, drivers and the grip and
    stand actions go, so Godot plays exactly the baked pose;
  * the props are skinned (weight 1) to their bones instead of parented to them, and the
    string's middle to the String bone in place of the Hook modifier;
  * the arrow shows where the clip keys the rig's `arrow` to 1: elsewhere the Arrow bone is
    keyed at zero scale (as the crossbowman's bolt), so no visibility track is needed;
  * textures scaled down to `texture_px` (default 1024, JPEG);
  * a sidecar <out>.json as the rabble's: per clip its length, loop, frames, ground speed in
    Godot axes (x, z, -y of Blender; the model faces +Z), turn, hips drift and events (the
    shot, the nock, the arrow's frames, footfalls, the bow's drop, death settled), plus
    `roles`.
The idle, walk and run are in place; their speed is the travel retarget_clips.py removed
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
PROPS = ("Bow", "Quiver", "Arrow")
CLIPS = ["idle", "walk", "run", "attack", "block", "death"]
LOOPS = {"idle", "walk", "run"}
sc = bpy.context.scene
sc.render.fps = int(FPS)
rig = bpy.data.objects["GoblinArcherRig"]
body = bpy.data.objects["GoblinArcher"]
assert rig.matrix_world == Matrix.Identity(4)
PB = rig.pose.bones
MX = "mixamorig:"
CLIPS = [c for c in CLIPS if c in bpy.data.actions and "frames" in bpy.data.actions[c]]
print("EXPORT clips", CLIPS)

for p in ("bow_ik", "draw_ik", "leg_ik"):
    assert rig[p] == 0, p
rig.update_tag()
bpy.context.view_layer.update()

# The bones that go out: every deforming bone, and the four the props ride.
for n in ("Bow", "String", "Quiver", "Arrow"):
    rig.data.bones[n].use_deform = True
OUT_BONES = [b.name for b in rig.data.bones if b.use_deform]
OUT_SET = set(OUT_BONES)
for n in OUT_BONES:
    b = rig.data.bones[n]
    assert b.parent is None or b.parent.name in OUT_SET, (n, b.parent.name)
    assert b.use_inherit_rotation and b.inherit_scale == "FULL" and (b.use_local_location or b.use_connect), n
assert not any(b.parent and b.parent.name == "Arrow" for b in rig.data.bones), "Arrow has children"
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


def prop_world(nm, co):
    # A point of a prop (its own space) in the world, through the bone it rides.
    o = bpy.data.objects[nm]
    pb = PB[o.parent_bone]
    return rig.matrix_world @ pb.matrix @ Matrix.Translation((0, pb.bone.length, 0)) @ \
        o.matrix_parent_inverse @ o.matrix_basis @ co


# The arrow's head: its vertex farthest from the nock (the prop's origin).
HEAD = max((v.co for v in bpy.data.objects["Arrow"].data.vertices), key=lambda c: c.length).copy()

# 1. Sample every clip from the evaluated pose (constraints and drivers included).
pose, samp, src_vel, marks = {}, {}, {}, {}
height = None
for name in CLIPS:
    act = bpy.data.actions[name]
    use(act)
    n = int(act["frames"])
    src_vel[name] = list(act.get("root_vel", [0.0, 0.0]))
    marks[name] = {k: int(act[k]) for k in ("shot_frame", "bow_release") if k in act}
    mats = []
    d = {"hips": [], "yaw": [], "ank": {"Left": [], "Right": []}, "foot": {"Left": [], "Right": []},
         "toe": {"Left": [], "Right": []}, "arrow": [], "string": [], "head": []}
    for f in range(1, n + 1):
        sc.frame_set(f)
        mats.append({bn: PB[bn].matrix.copy() for bn in OUT_BONES})
        d["hips"].append(b("Hips").head.copy())
        d["yaw"].append(hips_yaw())
        for s in ("Left", "Right"):
            d["ank"][s].append(b(s + "Foot").head.z)
            d["foot"][s].append(b(s + "Foot").head.copy())
            d["toe"][s].append(b(s + "ToeBase").head.copy())
        d["arrow"].append(float(rig["arrow"]) >= 0.5)
        d["string"].append(PB["String"].location.length)
        d["head"].append(prop_world("Arrow", HEAD))
        if name == "idle" and f == 1:
            ev = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
            height = max((ev.matrix_world @ v.co).z for v in ev.data.vertices)
    pose[name], samp[name] = mats, d
    print("SAMPLED", name, n, "frames, arrow shown in", sum(d["arrow"]))
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

# 3. Key the baked poses: basis = (parent_rest^-1 rest)^-1 parent_pose^-1 pose. The Arrow
# bone is keyed at zero scale wherever the arrow is hidden.
REST = {bn: rig.data.bones[bn].matrix_local.copy() for bn in OUT_BONES}
for bn in OUT_BONES:
    PB[bn].rotation_mode = "QUATERNION"
baked = {}
for name in CLIPS:
    mats = pose[name]
    shown = samp[name]["arrow"]
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
            if bn == "Arrow" and not shown[k]:
                s_ = Vector((0.0, 0.0, 0.0))
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

# The bake must reproduce the sampled pose (the hidden arrow's tail sits on its head).
worst = 0.0
for name in CLIPS:
    use(baked[name])
    for k in sorted({0, len(pose[name]) // 3, 2 * len(pose[name]) // 3, len(pose[name]) - 1}):
        sc.frame_set(k + 1)
        for bn in OUT_BONES:
            tail = pose[name][k][bn] @ Vector((0, PB[bn].bone.length, 0))
            if bn == "Arrow" and not samp[name]["arrow"][k]:
                tail = pose[name][k][bn].translation
            worst = max(worst, (PB[bn].matrix.translation - pose[name][k][bn].translation).length,
                        (PB[bn].tail - tail).length)
print("BAKE worst bone error %.2e m" % worst)
assert worst < 1e-4, worst

# 4. The props skinned to their bones in the rest pose; the string's middle to String, by
# the Hook modifier's own weights.
for o in list(bpy.data.objects):
    if o.name.startswith("WGT_"):
        bpy.data.objects.remove(o, do_unlink=True)
for pb in PB:
    pb.custom_shape = None
for nm in PROPS:
    o = bpy.data.objects[nm]
    bone = rig.data.bones[o.parent_bone]
    hook = {}
    for m in list(o.modifiers):
        assert m.type == "HOOK" and m.subtarget == "String" and m.falloff_type == "NONE" and m.strength == 1.0, (nm, m.name)
        g = o.vertex_groups[m.vertex_group]
        hook = {v.index: e.weight for v in o.data.vertices for e in v.groups if e.group == g.index and e.weight > 0}
        o.modifiers.remove(m)
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
    if hook:
        gs = o.vertex_groups.new(name="String")
        for i, w in hook.items():
            g.add([i], 1.0 - w, "REPLACE")
            gs.add([i], w, "REPLACE")
        print("STRING", nm, len(hook), "vertices on String, weights", sorted(set(round(w, 3) for w in hook.values())))
    o.modifiers.new("Armature", "ARMATURE").object = rig
    o.hide_viewport = o.hide_render = False
    o.hide_set(False)
print("PROPS skinned", {nm: [g.name for g in bpy.data.objects[nm].vertex_groups] for nm in PROPS})
for o in bpy.data.objects:
    if o.type == "MESH":
        for v in o.data.vertices:
            for g in v.groups:
                if g.weight > 1.0:
                    g.weight = 1.0


def steps_of(d, t, fr):
    # A footfall: the ankle comes down within 2 cm of its lowest after rising 4 cm above it
    # (round the loop's seam, so a footfall on the first frame counts once).
    steps = []
    for s, z in d["ank"].items():
        z = np.array(z)
        lo = z.min()
        up = bool(z[int(np.argmax(z))] > lo + 0.04)
        k0 = int(np.argmax(z))
        for j in range(1, len(z) + 1):
            k = (k0 + j) % len(z)
            if z[k] > lo + 0.04:
                up = True
            elif up and z[k] < lo + 0.02:
                steps.append([t(fr[k]), s])
                up = False
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


def spans(flags, t, fr):
    # Runs of True as [[first, last], ...] in seconds.
    out, start = [], None
    for k, on in enumerate(flags + [False]):
        if on and start is None:
            start = k
        elif not on and start is not None:
            out.append([t(fr[start]), t(fr[k - 1])])
            start = None
    return out


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
        "root_motion": name in ("block", "death"),
        "turn_deg": round(((d["yaw"][-1] - d["yaw"][0] + 180) % 360) - 180, 1),
        "hips_drift": to_godot(d["hips"][-1] - d["hips"][0]),
        "events": {},
    }
    if name in LOOPS:
        a0, a1 = pose[name][0], pose[name][-1]
        info["loop_seam_cm"] = round(100 * max((a1[bn].translation - a0[bn].translation).length for bn in OUT_BONES), 2)
    if name in ("walk", "run"):
        # The travel retarget_clips.py removed (the action's root_vel, Blender x and y, m/s).
        vel = Vector((src_vel[name][0], src_vel[name][1], 0.0))
        info["root_vel"] = to_godot(vel)
        info["speed_mps"] = round(vel.length, 4)
        info["travel_from"] = "source clip"
        info["events"]["steps"] = steps_of(d, t, fr)
        fl = footlock(d)
        info["speed_footlock_mps"] = round(float(np.median(np.linalg.norm(fl, axis=1))) * FPS, 4)
    if name == "attack":
        shown = [k for k in range(n) if d["arrow"][k]]
        k_shot = shown[-1]
        assert k_shot + 1 == marks[name]["shot_frame"], (k_shot + 1, marks[name])
        # The nock goes on the string where the String bone first leaves its rest.
        k_nock = next(k for k in range(shown[0], n) if d["string"][k] > 1e-3)
        head, nock = d["head"][k_shot], pose[name][k_shot]["Arrow"].translation
        aim = head - nock
        info["events"]["draw"] = t(fr[shown[0]])
        info["events"]["nock"] = t(fr[k_nock])
        info["events"]["shot"] = t(fr[k_shot])
        info["events"]["arrow_shown"] = spans(d["arrow"], t, fr)
        # The arrow's middle as he looses: the sandbox's missile, as long as the arrow, takes
        # its place there.
        info["shot_from"] = to_godot((head + nock) / 2)
        info["aim_up_deg"] = round(math.degrees(math.atan2(aim.z, Vector((aim.x, aim.y)).length)), 1)
        # Off his facing (+Z in Godot, -Y here), positive toward his left (+X in Godot).
        info["aim_yaw_deg"] = round(math.degrees(math.atan2(aim.x, -aim.y)), 1)
        info["held_frames"] = n - 1 - k_shot
        print("ATTACK arrow from frame", shown[0] + 1, "nocked", k_nock + 1, "loosed", k_shot + 1,
              "from", info["shot_from"], "aim up", info["aim_up_deg"], "yaw", info["aim_yaw_deg"])
    if name == "death":
        hips = d["hips"]
        still = n - 1
        while still > 1 and (hips[still] - hips[still - 1]).length < 0.003:
            still -= 1
        info["events"]["settled"] = t(fr[still])
        info["events"]["bow_drop"] = t(marks[name]["bow_release"])
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
roles = {"idle": "idle", "walk": "walk", "attack": ["attack"], "hit": "block", "death": ["death"], "extra": ["run"]}
notes = [
    "Clips are baked from the rig's evaluated pose (grips, the hand's hold on the bow, forearm twist, the cape "
    "and the keyed bow and string); no constraints or drivers go out. The props are skinned to the bones Bow "
    "(child of mixamorig:LeftHand), Quiver (child of mixamorig:Spine2) and Arrow (child of mixamorig:RightHand); "
    "the string's middle to String (child of Bow), which the shot draws.",
    "attack is the shot: events.draw is when the arrow appears in his right fist above his shoulder, events.nock "
    "when its nock goes on the string, events.shot when he looses (shot_from is the arrow's middle at that frame, "
    "Godot axes from his feet; it points aim_up_deg above level and aim_yaw_deg off his facing, positive to his "
    "left). The arrow shows only in events.arrow_shown; elsewhere, "
    "and in every other clip, the Arrow bone is at zero scale. The last held_frames frames hold the follow-through. "
    "No reload clip: the shot draws its own arrow.",
    "Locomotion is in place. walk and run move the figure by root_vel (m/s, Godot axes): the travel "
    "retarget_clips.py removed (travel_from); speed_footlock_mps is how fast his planted foot slides back. "
    "idle stands still. block and death keep their authored travel on the hips (root_motion true, hips_drift); "
    "do not add it again.",
    "block is the source's hit reaction (he crouches and raises the bow across his body), so it is his hit role.",
    "death: events.bow_drop is when he lets go of the bow; the Bow bone then lays it flat on the ground.",
    "Godot imports every clip with loop mode none; set it from clips.<clip>.loop. Animation names equal the "
    "clip names (clips.<clip>.anim).",
]
meta = {"fps": FPS, "source": "projects/meridius/references/characters/blender/goblin_archer/goblin_archer_rig.blend",
        "props": list(PROPS), "forward": [0, 0, 1],
        "height_m": round(float(height), 3),
        "height_rest_m": round(float(max(v.co.z for v in body.data.vertices)), 3),
        "roles": roles, "notes": notes,
        "objects": sorted(o.name for o in meshes), "bones": len(OUT_BONES), "triangles": sum(tris.values()),
        "texture_px": max([s[0] for s in textures.values()] or [0]), "clips": clips}
OUT.with_suffix(".json").write_text(json.dumps(meta, indent=1))
print("EXPORT_DONE", OUT, OUT.stat().st_size, "in %.1fs" % (time.time() - T0))
