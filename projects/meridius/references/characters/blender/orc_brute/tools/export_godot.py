"""Export the orc brute with his clips for the Godot 3D sandbox (background Blender), as
goblin_spear/tools/export_godot.py.

  blender -b brute_clips.blend --python export_godot.py -- <out.glb> [texture_px]
  blender -b brute_dual_clips.blend --python export_godot.py -- <out_dual.glb> [texture_px]

Reads the scratch copy of the rig that retarget_clips.py saves (its clips are Mixamo motion,
so the export stays local like the rabble's), and works on the open copy only (nothing is
saved):
  * the bone widgets go; the weapons of the rig's loadout stay (PROPS_OF): the club alone
    from orc_brute_rig.blend (retarget_clips.py has already left the knife out of the clips
    and the copy), both clubs from orc_brute_dual_rig.blend, Club and ClubLeft;
  * each pauldron, its two plates and five spikes, comes out of the body as a mesh of its
    own, PauldronLeft and PauldronRight, with the body's skin weights; the sidecar's `kit`
    names the variants that take one off (the shoulder beneath is modelled and painted);
  * the squad's faces join from orc_brute_faces.blend (jaw_plate.py, fit_beard.py): the
    meshes JawPlate and Beard, skinned to the head; the scar's body colour
    (scar_texture.py) goes next to the GLB, scaled as the body's; the sidecar's `faces`
    says which meshes and colours make each face;
  * every clip is baked, frame by frame, from the evaluated pose (the grips' Action
    constraints and their keyed influence, the forearm twist, the loincloth flaps' drivers
    and the keyed weapon bones) onto plain keys of the deforming bones plus the weapons';
    then the constraints, drivers and the grip and stand actions go, so Godot plays exactly
    the baked pose;
  * each weapon is skinned (weight 1) to its bone instead of parented to it;
  * textures scaled down to `texture_px` (default 1024, JPEG);
  * a sidecar <out>.json as the rabble's: per clip its length, loop, frames, ground speed in
    Godot axes (x, z, -y of Blender; the model faces +Z), turn, hips drift and events (the
    blow's `contact`, footfalls, the weapons' drops, death settled), plus `roles`.
The walk and idle are in place; the walk's speed is the travel retarget_clips.py removed
(the action's root_vel), checked against how fast his planted foot slides back.
"""
import json
import math
import sys
import time
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = Path(argv[0])
TEX = int(argv[1]) if len(argv) > 1 else 1024
FPS = 30.0
T0 = time.time()
PROPS_OF = {"club_knife": ("Club",), "dual": ("Club", "ClubLeft")}
FACES_BLEND = Path(__file__).resolve().parents[1] / "orc_brute_faces.blend"
SCAR_TEX = FACES_BLEND.parent / "textures" / "orc_brute_body_scar_basecolor.jpg"
# Each face: the meshes it shows (every other face mesh is hidden) and the meshes whose base
# colour it swaps for a file next to the GLB.
FACES = {"jaw": {"show": ["JawPlate"]}, "beard": {"show": ["Beard"]},
         "scar": {"albedo": {"OrcBrute": SCAR_TEX.name}}}
# Each kit variant: the meshes it takes off. The pauldrons, out of the body's shells (as
# rig_orc_brute.py sorts them): not the body, boots, bracers or the head's bits, lowest point
# above 1.50 m; his left is +X.
PAULDRONS = {"PauldronLeft": 1, "PauldronRight": -1}
KIT = {"no_left_pauldron": {"hide": ["PauldronLeft"]}, "no_right_pauldron": {"hide": ["PauldronRight"]}}
CLIPS = ["idle", "walk", "attack", "death"]
SWING_FAST = 0.35   # the swing: the club tip at least this share of its top speed
LOOPS = {"idle", "walk"}
sc = bpy.context.scene
sc.render.fps = int(FPS)
rig = bpy.data.objects["OrcBruteRig"]
body = bpy.data.objects["OrcBrute"]
LOADOUT = rig.get("loadout", "club_knife")
KEEP_PROPS = PROPS_OF[LOADOUT]
DUAL = LOADOUT == "dual"
assert rig.matrix_world == Matrix.Identity(4)
PB = rig.pose.bones
MX = "mixamorig:"
CLIPS = [c for c in CLIPS if c in bpy.data.actions and "frames" in bpy.data.actions[c]]
print("EXPORT clips", CLIPS)

for p in [p for p in rig.keys() if p.endswith("_ik")]:
    assert rig[p] == 0, p
rig.update_tag()
bpy.context.view_layer.update()

# The bones that go out: every deforming bone, and the ones the weapons ride.
for nm in KEEP_PROPS:
    rig.data.bones[nm].use_deform = True
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


# The (right) club's tip: its highest vertex in its own space (the handle on z, the head up).
weapon = bpy.data.objects["Club"]
TIP = max((v.co for v in weapon.data.vertices), key=lambda c: c.z).copy()
W_LOCAL = weapon.matrix_parent_inverse @ weapon.matrix_basis
marks = {}


def tip_world():
    pb = PB["Club"]
    return rig.matrix_world @ pb.matrix @ Matrix.Translation((0, pb.bone.length, 0)) @ W_LOCAL @ TIP


# 1. Sample every clip from the evaluated pose (constraints and drivers included).
pose, samp, src_vel = {}, {}, {}
height = None
for name in CLIPS:
    act = bpy.data.actions[name]
    use(act)
    n = int(act["frames"])
    src_vel[name] = list(act.get("root_vel", [0.0, 0.0]))
    marks[name] = {k: int(act[k]) for k in (p.lower() + "_release" for p in KEEP_PROPS) if k in act}
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

# The pauldrons, each out of the body into a copy of it that keeps only its shells.
bm = bmesh.new()
bm.from_mesh(body.data)
bm.verts.ensure_lookup_table()
island = np.full(len(bm.verts), -1)
parts = []
for v in bm.verts:
    if island[v.index] >= 0:
        continue
    k, stack, part = len(parts), [v], []
    island[v.index] = k
    while stack:
        w = stack.pop()
        part.append(w.index)
        for e in w.link_edges:
            o = e.other_vert(w)
            if island[o.index] < 0:
                island[o.index] = k
                stack.append(o)
    parts.append(np.array(part))
bm.free()
V = np.array([v.co[:] for v in body.data.vertices])
main = max(range(len(parts)), key=lambda k: len(parts[k]))
pads = {nm: [] for nm in PAULDRONS}
for k, part in enumerate(parts):
    P = V[part]
    lo, c = P.min(0), P.mean(0)
    if k == main or lo[2] < 0.01 or abs(c[0]) > 0.58 or (lo[2] > 1.70 and abs(c[0]) < 0.16) or lo[2] <= 1.50:
        continue
    pads[next(nm for nm, sx in PAULDRONS.items() if sx * c[0] > 0)].append(part)
for nm, shells in pads.items():
    big = sorted(len(sh) > 60 for sh in shells)
    assert big.count(True) == 2 and big.count(False) == 5, (nm, [len(sh) for sh in shells])


def keep_only(mesh, keep):
    """Delete every vertex of `mesh` not in `keep` (indices)."""
    bm_ = bmesh.new()
    bm_.from_mesh(mesh)
    bm_.verts.ensure_lookup_table()
    k_ = set(keep.tolist())
    bmesh.ops.delete(bm_, geom=[v for v in bm_.verts if v.index not in k_], context="VERTS")
    bm_.to_mesh(mesh)
    bm_.free()


for nm, shells in pads.items():
    o = body.copy()
    o.data = body.data.copy()
    o.name = o.data.name = nm
    sc.collection.objects.link(o)
    keep_only(o.data, np.concatenate(shells))
all_pads = np.concatenate([sh for shells in pads.values() for sh in shells])
keep_only(body.data, np.setdiff1d(np.arange(len(V)), all_pads))
print("PAULDRONS", {nm: len(bpy.data.objects[nm].data.vertices) for nm in PAULDRONS}, "body", len(body.data.vertices))

# The faces' meshes, on this rig. Appending them brings their own rig (its widgets, its
# armature and actions) along as dependencies; those go.
before = set(bpy.data.objects)
before_data = {k: set(getattr(bpy.data, k)) for k in ("armatures", "actions")}
face_names = [n for f in FACES.values() for n in f.get("show", [])]
with bpy.data.libraries.load(str(FACES_BLEND), link=False) as (src, dst):
    assert set(face_names) <= set(src.objects), face_names
    dst.objects = list(face_names)
for o in dst.objects:
    sc.collection.objects.link(o)
    o.parent = rig
    o.matrix_parent_inverse = Matrix.Identity(4)
    for m in o.modifiers:
        if m.type == "ARMATURE":
            m.object = rig
    assert {g.name for g in o.vertex_groups} <= OUT_SET, (o.name, [g.name for g in o.vertex_groups])
    for slot in o.material_slots:
        for n in slot.material.node_tree.nodes:
            if n.type == "TEX_IMAGE":
                assert n.image.size[0] > 0, (o.name, n.image.filepath)
for o in set(bpy.data.objects) - before - set(dst.objects):
    bpy.data.objects.remove(o, do_unlink=True)
for k, old in before_data.items():
    for d in set(getattr(bpy.data, k)) - old:
        getattr(bpy.data, k).remove(d)
assert set(bpy.data.actions) == set(baked.values()), [a.name for a in bpy.data.actions]
assert SCAR_TEX.exists(), SCAR_TEX
print("FACES", {n: len(bpy.data.objects[n].data.vertices) for n in face_names})
for o in bpy.data.objects:
    if o.type == "MESH":
        for v in o.data.vertices:
            for g in v.groups:
                if g.weight > 1.0:
                    g.weight = 1.0


def steps_of(d, t, fr, vel, down=0.02, lift=0.05, slip=0.5):
    """Footfalls of the in-place walk, read round its seam (its last frame is its first): a
    stance is a run of frames where the ankle is within `lift` of its lowest and the foot all but
    still on the ground (under `slip` of the walk's speed, with the travel the clip lost, `vel`,
    added back); its footfall is its first frame with the ankle within `down` of its lowest.
    Height alone will not do: his heavy walk rolls the planted foot onto its outer edge, lifting
    the ankle up to 4 cm mid-stance, and swings the other foot within 2 cm of the ground."""
    n = len(fr) - 1
    v = Vector((vel[0], vel[1], 0.0))
    steps = []
    for s in ("Left", "Right"):
        z = np.array(d["ank"][s][:n])
        z -= z.min()
        p = d["foot"][s]
        still = [z[k] < lift and ((p[k + 1] - p[k]) * FPS + v).to_2d().length < slip * v.length
                 for k in range(n)]
        if all(still) or not any(still):
            continue
        k0 = still.index(False)
        for i in range(1, n + 1):
            k = (k0 + i) % n
            if still[k] and not still[k - 1]:
                run = []
                while still[(k + len(run)) % n] and len(run) < n:
                    run.append((k + len(run)) % n)
                land = next((j for j in run if z[j] < down), k)
                print("STEP %s frame %d (stance from %d)" % (s, fr[land], fr[k]))
                steps.append([t(fr[land]), s])
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
        info["events"]["steps"] = steps_of(d, t, fr, src_vel[name])
        assert [s for _, s in info["events"]["steps"]] in (["Left", "Right"], ["Right", "Left"]), \
            "the walk should have one footfall a foot"
        fl = footlock(d)
        info["speed_footlock_mps"] = round(float(np.median(np.linalg.norm(fl, axis=1))) * FPS, 4)
    if name == "attack":
        tip = d["tip"]
        h0 = d["hips"][0]
        fwd = [-(p.y - h0.y) for p in tip]
        # A rising swing on his right (the club drawn back low behind his hip, swept forward
        # past his side and up through the foe at chest height, then over his left shoulder):
        # the blow lands where the tip reaches furthest forward while the club moves fast (at
        # least SWING_FAST of its top speed); the swing spans that fast run up to the blow.
        spd = [(tip[k + 1] - tip[k]).length * FPS for k in range(n - 1)]
        spd.append(spd[-1])
        fast = [v >= SWING_FAST * max(spd) for v in spd]
        k_hit = max((k for k in range(n) if fast[k]), key=lambda k: fwd[k])
        k_start = k_hit
        while k_start > 0 and fast[k_start - 1]:
            k_start -= 1
        info["events"]["contact"] = t(fr[k_hit])
        info["events"]["swing"] = [t(fr[k_start]), t(fr[k_hit])]
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
        for k in (p.lower() for p in KEEP_PROPS):
            if k + "_release" in marks[name]:
                info["events"][k + "_drop"] = t(marks[name][k + "_release"])
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
    "Clips are baked from the rig's evaluated pose (both grips, forearm twist, the loincloth flaps, and the "
    "keyed weapons); no constraints or drivers go out. The club is skinned to the bone Club (child of "
    "mixamorig:RightHand). " + ("The second club, ClubLeft, is skinned to the bone ClubLeft (child of "
    "mixamorig:LeftHand)." if DUAL else "He carries the club alone: his left hand is empty, half closed."),
    "Locomotion is in place. walk moves the figure by root_vel (m/s, Godot axes): the travel "
    "retarget_clips.py removed (travel_from); speed_footlock_mps is how fast his planted foot slides back. "
    "idle stands still, " + ("a club in each fist" if DUAL else "club in his right fist") + ", as does the walk. "
    "The death keeps its "
    "authored travel on the hips (root_motion true, hips_drift); do not add it again.",
    "attack is a rising swing of the club on his right side: drawn back low behind his hip, swept forward "
    "past his side and up through the foe at chest height, then over his left shoulder. events.contact is "
    "when the club's tip is furthest forward while it moves fast (tip_reach_m from where he stood, at "
    "tip_height_m); events.swing spans the fast part of the swing up to it." + (
        " The left club stays in his left fist, its arm kept clear of the body." if DUAL else ""),
    ("death: events.club_drop and events.clubleft_drop are when each fist lets go; the Club and ClubLeft "
     "bones then lay the clubs on the ground." if DUAL else
     "death: events.club_drop is when his fist lets go; the Club bone then lays the club on the ground."),
    "No hit clip: the sandbox flinches procedurally.",
    "faces: his squad's face variants, any of which a unit may combine. A unit shows the meshes of its "
    "faces' `show` and drops every other face's; `albedo` swaps a mesh's base colour for the file next to "
    "the GLB (the scar: the body's colour with two claw gouges over his left eye). JawPlate (an iron jaw "
    "guard) rides the head; Beard (braided, resting on the chest strap) blends from the head through the "
    "neck to the chest.",
    "kit: variants of his gear, which a unit may combine with each other and with his faces. A unit drops "
    "the meshes of its kit's `hide`: PauldronLeft and PauldronRight are his spiked shoulder plates, skinned "
    "as the body (the shoulder beneath is modelled and painted).",
    "Godot imports every clip with loop mode none; set it from clips.<clip>.loop. Animation names equal the "
    "clip names (clips.<clip>.anim).",
]
meta = {"fps": FPS, "source": "projects/meridius/references/characters/blender/orc_brute/"
        + ("orc_brute_dual_rig.blend" if DUAL else "orc_brute_rig.blend"), "loadout": LOADOUT,
        "props": list(KEEP_PROPS), "faces": FACES, "kit": KIT, "forward": [0, 0, 1],
        "height_m": round(float(height), 3),
        "height_rest_m": round(float(max(v.co.z for v in body.data.vertices)), 3),
        "roles": roles, "notes": notes,
        "objects": sorted(o.name for o in meshes), "bones": len(OUT_BONES), "triangles": sum(tris.values()),
        "texture_px": max([s[0] for s in textures.values()] or [0]), "clips": clips}
OUT.with_suffix(".json").write_text(json.dumps(meta, indent=1))

# The scar's body colour, scaled and encoded as the body's.
scar = bpy.data.images.load(str(SCAR_TEX))
if scar.size[0] > TEX:
    scar.scale(TEX, TEX)
scar.file_format = "JPEG"
scar.save(filepath=str(OUT.parent / SCAR_TEX.name), quality=88)
print("SCAR texture", OUT.parent / SCAR_TEX.name, tuple(scar.size))
print("EXPORT_DONE", OUT, OUT.stat().st_size, "in %.1fs" % (time.time() - T0))
