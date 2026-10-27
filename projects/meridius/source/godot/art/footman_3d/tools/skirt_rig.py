"""Keep the tunic's skirt over his thighs (background Mixar / Blender).

  mixar.exe --background <rig.blend> --python skirt_rig.py -- save|<out.blend>

The skirt (the tunic below the belt) is a shell of its own, skinned by bone
heat to the hips and spine only: his thighs swing out through it in his guard
stance and in every step, lunge and blow. Six skirt bones fix that, a front, a
side and a back one over each thigh, children of the hips with their heads on
the hip joint:
  * each turns with its thigh, aiming (damped track: the swing, not the twist)
    at its knee. The front and back ones aim at a stand-in for the knee,
    `SkirtAim*`, a child of the thigh held in the hips' axes so that it only
    moves the way that thigh pushes that part of the cloth: forward for the
    front one, back for the back one (out and in for both). A thigh raised
    forward lifts the front of the skirt and leaves the back hanging; the side
    one, over the outside of the thigh, goes every way the thigh does;
  * the skirt's lower rings are weighted to them, from nothing at the belt to
    all at the hem, by where round the skirt they hang (front, side, back),
    the middle of the front and of the back shared between the two thighs;
  * the hem is pushed out a little (`PUSH`), so it hangs clear of the thigh
    instead of on its surface, and the sides halfway down a little more
    (`PUSH_SIDE`, over the hips only: `SIDE`), where the top of the thigh
    turns out under them.
The bones are constraint-driven: every clip, the renders and the export (which
samples the pose) pick them up with no keys of their own. Re-running replaces
them (the skirt's rest shape is kept in the mesh attribute `skirt_rest`, so the
push is never applied twice). Saves the .blend with `save`, or to `out.blend`;
with neither, it only sets up the open copy.
"""
import math
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = (bpy.data.filepath if argv[0] == "save" else argv[0]) if argv and argv[0] else None
rig = bpy.data.objects["FootmanRig"]
body = bpy.data.objects["Footman"]
SIDES = {"L": "Left", "R": "Right"}
KINDS = ("F", "S", "B")
# How much of the thigh's swing each bone takes; the rings' share (by rest
# height: none at Z_TOP, all at Z_HEM, eased by RAMP); the hem's push and the
# push over the hips' sides, most halfway down (m).
FOLLOW = {"F": 1.0, "S": 1.0, "B": 1.0}
Z_TOP, Z_HEM, RAMP = 1.06, 0.765, 0.85
PUSH, PUSH_SIDE = 0.02, 0.05
# Round the skirt (degrees from his front): all front bone up to FRONT[0], all
# side bone from FRONT[1] to BACK[0], all back bone from BACK[1].
FRONT, BACK = (30.0, 90.0), (90.0, 150.0)
# The sides' push: none nearer his front or back than SIDE[0] (his fist and the
# blade rest there on his thigh as he falls), all of it from SIDE[1].
SIDE = (60.0, 80.0)
BONE_LEN = 0.14


def skirt_verts():
    """The skirt shell: the one island that spans belt to hem round both thighs."""
    me = body.data
    adj = [[] for _ in me.vertices]
    for e in me.edges:
        a, b = e.vertices
        adj[a].append(b)
        adj[b].append(a)
    lab = [-1] * len(me.vertices)
    islands = []
    for v0 in range(len(me.vertices)):
        if lab[v0] >= 0:
            continue
        lab[v0] = len(islands)
        stack, cur = [v0], []
        while stack:
            v = stack.pop()
            cur.append(v)
            for o in adj[v]:
                if lab[o] < 0:
                    lab[o] = len(islands)
                    stack.append(o)
        islands.append(cur)

    def is_skirt(ids):
        z = [me.vertices[i].co.z for i in ids]
        x = [me.vertices[i].co.x for i in ids]
        return min(z) > 0.6 and min(z) < 0.85 and max(z) < 1.25 and min(x) < -0.15 and max(x) > 0.15
    found = [ids for ids in islands if is_skirt(ids)]
    assert len(found) == 1, f"expected one skirt shell, found {len(found)}"
    return found[0]


def build_bones():
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = rig.data.edit_bones
    for n in [b.name for b in eb if b.name.startswith("Skirt")]:
        eb.remove(eb[n])
    hips = eb["mixamorig:Hips"]
    for s, side in SIDES.items():
        thigh = eb[f"mixamorig:{side}UpLeg"]
        along = (thigh.tail - thigh.head).normalized()
        for k in KINDS:
            # The thigh's rest frame (a new bone has no length to take a matrix).
            b = eb.new(f"Skirt{k}.{s}")
            b.head = thigh.head
            b.tail = thigh.head + along * BONE_LEN
            b.align_roll(thigh.z_axis)
            b.parent = hips
            b.use_connect = False
            b.use_deform = True
            if k == "S":
                continue
            t = eb.new(f"SkirtAim{k}.{s}")
            t.head = thigh.tail
            t.tail = thigh.tail + along * 0.04
            t.align_roll(thigh.z_axis)
            t.parent = thigh
            t.use_connect = False
            t.use_deform = False
    bpy.ops.object.mode_set(mode="POSE")
    H = rig.data.bones["mixamorig:Hips"].matrix_local.inverted()
    for s, side in SIDES.items():
        for k in KINDS:
            pb = rig.pose.bones[f"Skirt{k}.{s}"]
            pb.rotation_mode = "QUATERNION"
            for c in list(pb.constraints):
                pb.constraints.remove(c)
            aim = f"mixamorig:{side}UpLeg"
            if k != "S":
                # In the hips' own axes +Z is his front: the stand-in keeps to
                # the front (or back) of where the knee rests.
                ab = rig.pose.bones[f"SkirtAim{k}.{s}"]
                for c in list(ab.constraints):
                    ab.constraints.remove(c)
                rest = H @ ab.bone.head_local
                lim = ab.constraints.new("LIMIT_LOCATION")
                lim.owner_space = "CUSTOM"
                lim.space_object = rig
                lim.space_subtarget = "mixamorig:Hips"
                if k == "F":
                    lim.use_min_z, lim.min_z = True, rest.z
                else:
                    lim.use_max_z, lim.max_z = True, rest.z
                    # A knee raised past level would lift it over the hip
                    # and flip the back of the skirt up: it stays below.
                    lim.use_max_y, lim.max_y = True, (H @ rig.data.bones[f"mixamorig:{side}UpLeg"].head_local).y - 0.1
                aim = ab.name
            t = pb.constraints.new("DAMPED_TRACK")
            t.target = rig
            t.subtarget = aim
            t.head_tail = 1.0 if k == "S" else 0.0
            t.track_axis = "TRACK_Y"
            t.influence = FOLLOW[k]
    bpy.ops.object.mode_set(mode="OBJECT")


def smooth(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def weigh(ids):
    me = body.data
    rest = me.attributes.get("skirt_rest")
    if rest is None:
        rest = me.attributes.new("skirt_rest", "FLOAT_VECTOR", "POINT")
        for i in ids:
            rest.data[i].vector = me.vertices[i].co
    for i in ids:
        me.vertices[i].co = rest.data[i].vector
    for n in [g.name for g in body.vertex_groups if g.name.startswith("Skirt")]:
        body.vertex_groups.remove(body.vertex_groups[n])
    for s in SIDES:
        for k in KINDS:
            body.vertex_groups.new(name=f"Skirt{k}.{s}")
    hem = [i for i in ids if me.vertices[i].co.z < Z_HEM + 0.03]
    yc = sum(me.vertices[i].co.y for i in hem) / len(hem)
    names = {g.index: g.name for g in body.vertex_groups}
    moved = 0
    for i in ids:
        v = me.vertices[i]
        t = min(1.0, max(0.0, (Z_TOP - v.co.z) / (Z_TOP - Z_HEM))) ** RAMP
        if t <= 0:
            continue
        x, y = v.co.x, v.co.y
        phi = math.degrees(math.atan2(abs(x), yc - y))  # 0 front, 90 side, 180 back
        f = 1.0 - smooth(*FRONT, phi)
        b = smooth(*BACK, phi)
        part = {"F": f, "S": 1.0 - f - b, "B": b}
        left = smooth(-0.05, 0.05, x)
        share = {f"Skirt{k}.{s}": (left if s == "L" else 1.0 - left) * w for k, w in part.items() for s in SIDES}
        old = {names[g.group]: g.weight for g in v.groups if g.weight > 0 and not names[g.group].startswith("Skirt")}
        tot = sum(old.values()) or 1.0
        new = {n: (1 - t) * w / tot for n, w in old.items()}
        for n, w in share.items():
            new[n] = new.get(n, 0.0) + t * w
        # Four influences at most (the glTF export keeps four), renormalised.
        keep = dict(sorted(new.items(), key=lambda kv: -kv[1])[:4])
        total = sum(keep.values())
        for n in old:
            body.vertex_groups[n].remove([i])
        for n, w in keep.items():
            if w > 1e-4:
                body.vertex_groups[n].add([i], w / total, "REPLACE")
        r = Vector((x, y - yc, 0.0))
        if r.length > 1e-6:
            # Most at the hem; over the hips' sides also halfway up, where the
            # top of the thigh turns out under the skirt close to the joint.
            v.co += r.normalized() * (PUSH * t + PUSH_SIDE * smooth(*SIDE, min(phi, 180.0 - phi)) * math.sin(math.pi * t))
        moved += 1
    return moved, yc


ids = skirt_verts()
build_bones()
n, yc = weigh(ids)
print("SKIRT_RIG shell %d verts, %d reweighted (hem centre y %.3f), follow %s, push %.3f m, sides %.3f m" % (len(ids), n, yc, FOLLOW, PUSH, PUSH_SIDE))
if OUT:
    bpy.ops.wm.save_as_mainfile(filepath=OUT)
    print("SKIRT_RIG saved", OUT)
