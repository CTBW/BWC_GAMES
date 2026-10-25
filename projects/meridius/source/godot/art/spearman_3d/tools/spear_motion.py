"""Move the spear with the hands for every clip (background Blender), after retarget_clips.py.

  blender -b <rig.blend> --python spear_motion.py -- [clip,clip...]

The spear (butt at its origin, tip along +Z, blade width along X) becomes a child of
SpearmanRig and gets one action per clip, "<clip>__spear", keyed in rig space, so turning
the rig for the game's facings turns the spear too. Three ways of holding it:
  two    both fists on the shaft: it runs from the rear fist through the front one (along
         his facing), the rear fist GRIP metres from the butt, the blade's flat level;
  carry  marching and at ease: an analytic two-bone IK keeps the right wrist in front of the
         right hip at elbow height (riding with the hips), the forearm level; the hand rolls
         so the fist's grip axis stands upright (leaning a little forward and out) and the
         spear runs along it, the butt above knee height so the striding thigh never meets
         it; the right arm's keys in the clip are replaced;
  shoulder  the sidestep into lane (the clip turns his hips and chest ~70 degrees right): the
         spine turns his chest back by SPINE_UNTWIST of that, and the neck and the head's joint
         share the rest, so his head looks straight ahead throughout; the shaft rests against
         the front of his right shoulder, leaning back mostly from the way he walks (the hips;
         "travel"), the fist just below at his collarbone and the elbow back by his ribs; the
         wrist bends a little (up to ~11 degrees) so the shaft keeps its lean;
  turn   the turn: both hands on the shaft as in the guard (the arms take the guard's pose
         on the turning body), the spear lowered a little (TURN_LOWER, eased in and out) with
         the front arm re-solved so its fist stays on the shaft;
  rigid  fixed in the right fist as it is held in the idle's first frame (hit); where the
         flinch would swing the shaft through him, his wrist bends it clear (wrist_clear:
         edits the right hand's keys in place, so retarget the clip again before a re-run);
  drop   deaths: rigid until his hips start to sink, then he lets go and the spear falls
         flat onto the ground (accelerating, like a dropped rod), landing below his hands.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

GRIP = 0.14            # m from the butt to the rear fist in two-handed holds: at the butt cap, for reach
                       # (at full lunge the right arm lies along the shaft's line, so more shaft behind
                       # the fist runs up through the arm)
# Carry (march, at ease): right fist position (rest pose, rides with the hips), the spear's
# lean forward and outward (degrees) and how high the butt rides above the ground.
# His arms are short (43 cm shoulder to wrist): the wrist sits where a bent arm reaches with
# the upper arm hanging and the forearm level.
CARRY_CFG = {"fist": [-0.24, -0.19, 1.27], "fwd": 0.0, "out": 4.0, "butt_z": 0.78}
CARRY_CFG.update(json.loads(os.environ.get("SPEAR_CARRY", "{}")))
# Sidestep into lane: the spear leans back onto the right shoulder ("fwd" negative = back).
# "contact": where the shaft touches the front of the shoulder (rest pose), "len": metres down
# the shaft from there to the fist, "pole": which way the elbow points (rest pose).
# "travel": how much "back" is measured from his hips (the way he walks) rather than his chest.
# With the spine untwisted his chest faces ~35 degrees further left than his hips; leaning
# back from the chest alone stood the spear upright in the SE view, against the owner's
# 2026-10-23 arrows (tip to the right); 0.75 keeps that lean, and 1.0 ran the shaft over his face.
SHOULDER_CFG = {"contact": [-0.20, -0.11, 1.55], "len": 0.16, "fwd": -22.0, "out": 3.0, "butt_z": 0.85,
                "pole": [-0.3, 0.6, -1.0], "travel": 0.75}
SHOULDER_CFG.update(json.loads(os.environ.get("SPEAR_SHOULDER", "{}")))
# Share of the chest's turn the spine turns back in the sidestep, spread over its three bones
# (twisting each about its own length). With the head held straight ahead, the source clip's
# untwisted spine left the whole 64-79 degrees to the neck.
SPINE_UNTWIST = float(os.environ.get("SPINE_UNTWIST", "0.5"))
SPINE_SHARES = (("Spine", 0.3), ("Spine1", 0.35), ("Spine2", 0.35))
CARRY_POLE = Vector((-0.5, 1.0, -0.25))  # rest-pose world direction: the elbow points back, out and a little down
TURN_LOWER = 16.0      # degrees the spear dips during the turn
TURN_EASE = 6          # frames to ease the dip in and out
MODES = {"idle": "two", "attack": "two",
         "idle_rest": "carry", "walk": "carry", "step_lane": "shoulder",
         "hit": os.environ.get("SPEAR_HIT_MODE", "rigid"), "death": "drop", "death_2": "drop", "death_3": "drop", "turn_90": "turn"}
SHAFT_R = 0.02
DROP_FRAMES = 14       # 0.47 s from letting go to lying on the ground
# Hit: the rigid spear swung through his belly and his left forearm in 10 of 61 frames as he
# flinched. The wrist bends it clear instead, about one axis in the hand's X-Z plane per
# stretch of such frames (12 directions tried), so that in every frame neither the shaft's
# axis nor four lines CLEAR_R off it cross the body outside the fists. The bend per frame is
# the cheapest path in 2-degree steps (least bend, least change from frame to frame, at most
# CLEAR_STEP per frame) from a straight wrist CLEAR_PAD frames before the stretch back to a
# straight wrist CLEAR_PAD frames after it. One fixed bend for the whole stretch pushed the
# shaft into his left arm in frames that were clear before.
CLEAR_R = SHAFT_R + 0.005
CLEAR_MAX = 30         # degrees the wrist may bend for it
CLEAR_STEP = 6         # degrees per frame at most
CLEAR_PAD = 8          # frames
SPEAR_L, STEP = 2.40, 0.04   # the walk along the shaft, as in spear_clearance.py

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
only = argv[0].split(",") if argv and argv[0] else None
sc = bpy.context.scene
rig = bpy.data.objects["SpearmanRig"]
spear = bpy.data.objects["Spear"]
assert rig.matrix_world == Matrix.Identity(4)
spear.parent = rig
spear.parent_type = "OBJECT"
spear.matrix_parent_inverse = Matrix.Identity(4)
spear.rotation_mode = "QUATERNION"
PB = rig.pose.bones
B = rig.data.bones
fist_off = {s: B[f"mixamorig:{s}Hand"].matrix_local.inverted() @ Vector(rig[f"fist_{s.lower()}"]) for s in ("Right", "Left")}
UP = Vector((0, 0, 1))


def fist(side):
    return PB[f"mixamorig:{side}Hand"].matrix @ fist_off[side]


def frame_from_axis(z, x_hint):
    z = z.normalized()
    x = (x_hint - z * x_hint.dot(z))
    if x.length < 1e-4:
        x = Vector((1, 0, 0)) - z * z.x
    x.normalize()
    y = z.cross(x)
    return Matrix((x, y, z)).transposed()


def facing():
    """His facing on the ground: the hips bone's Z axis (the bones' Y runs up the spine)."""
    f = PB["mixamorig:Hips"].matrix.to_3x3() @ Vector((0, 0, 1))
    f.z = 0
    return f.normalized()


def two_handed():
    r, l = fist("Right"), fist("Left")
    if (r - l).dot(facing()) > 0:
        r, l = l, r                       # r is the rear fist, l the front one
    z = (l - r).normalized()
    x = UP.cross(z)                       # blade width level: its flat faces up
    if x.length < 0.2:
        x = PB["mixamorig:Hips"].matrix.to_3x3() @ Vector((1, 0, 0))
    R = frame_from_axis(z, x)
    M = R.to_4x4()
    M.translation = r - z * GRIP
    return M


def clear_unkeyed(pb):
    """No clip keys scale, nor location below the hips. Assigning pb.matrix leaves float noise
    there (scale up to 1.0001 on the right arm), saved in the file and shared by every clip; the
    cape sim amplified it into different bakes from the same keys."""
    pb.scale = (1, 1, 1)
    if pb.name != "mixamorig:Hips":
        pb.location = (0, 0, 0)


def set_matrix(pb, M):
    pb.matrix = M
    clear_unkeyed(pb)
    bpy.context.view_layer.update()


def set_bone_dir(pb, target_dir):
    """Turn a pose bone (armature space) so its Y axis points along target_dir, with the least twist."""
    M = pb.matrix.copy()
    cur = (M.to_3x3() @ Vector((0, 1, 0))).normalized()
    q = cur.rotation_difference(target_dir.normalized())
    R = (q.to_matrix() @ M.to_3x3().normalized()).to_4x4()
    R.translation = M.translation
    set_matrix(pb, R)


def solve_arm(side, T, pole, grip=None, palm=None, bend=False):
    """Analytic two-bone IK: put the wrist at T, the elbow towards pole; then turn the hand so
    its X axis (the fist's grip axis) lies along grip, with a straight wrist.
    bend: the grip axis exactly along grip instead, the wrist bending sideways as little as
    that needs. palm: the side the fist's middle should lie on, seen from the wrist."""
    arm, fore, hand = PB[f"mixamorig:{side}Arm"], PB[f"mixamorig:{side}ForeArm"], PB[f"mixamorig:{side}Hand"]
    a = (B[f"mixamorig:{side}ForeArm"].head_local - B[f"mixamorig:{side}Arm"].head_local).length
    b = (B[f"mixamorig:{side}Hand"].head_local - B[f"mixamorig:{side}ForeArm"].head_local).length
    S = arm.matrix.translation.copy()
    d_vec = T - S
    d = min(d_vec.length, a + b - 1e-3)
    dirv = d_vec.normalized()
    cos_a = max(-1.0, min(1.0, (a * a + d * d - b * b) / (2 * a * d)))
    n = (pole - dirv * pole.dot(dirv)).normalized()
    E = S + dirv * a * cos_a + n * a * math.sqrt(max(0.0, 1 - cos_a * cos_a))
    set_bone_dir(arm, E - S)
    set_bone_dir(fore, (S + dirv * d) - E)
    if grip is not None:
        cur_x = hand.matrix.to_3x3() @ Vector((1, 0, 0))
        hand.rotation_quaternion = Quaternion()
        bpy.context.view_layer.update()
        y = (fore.matrix.to_3x3() @ Vector((0, 1, 0))).normalized()
        x = (grip - y * grip.dot(y)).normalized()
        if bend:
            x = grip.normalized()
            y = (y - x * y.dot(x)).normalized()
        if palm is not None:
            lx = fist_off[side].normalized()     # hand-local direction to the fist's middle
            if (Matrix((x, y, x.cross(y))).transposed() @ lx).dot(palm) < 0:
                x = -x
        elif x.dot(cur_x) < 0:
            x = -x                       # the grip axis is a line: keep the roll small
        z = x.cross(y)
        Mh = Matrix((x, y, z)).transposed().to_4x4()
        Mh.translation = hand.matrix.translation
        set_matrix(hand, Mh)
    for pb in (arm, fore, hand):
        pb.keyframe_insert("rotation_quaternion", frame=sc.frame_current)


def lean_dir(cfg, fwd):
    right = fwd.cross(UP)
    return (UP + fwd * math.tan(math.radians(cfg["fwd"])) + right * math.tan(math.radians(cfg["out"]))).normalized()


def carry_ik(cfg, fwd=None):
    """The right wrist at cfg's place (rest pose, riding with the hips), the fist's grip axis
    along the spear's lean (relative to fwd: his facing unless given)."""
    hips = PB["mixamorig:Hips"].matrix
    T = hips @ (hips_rest_inv @ Vector(cfg["fist"]))
    pole = hips.to_3x3() @ (hips_rest_inv.to_3x3() @ CARRY_POLE)
    solve_arm("Right", T, pole, lean_dir(cfg, fwd if fwd is not None else facing()))


def shoulder_ik(cfg):
    """The spear resting against the front of the right shoulder: the shaft runs through the
    contact point (rest pose, riding with the chest) at the lean, the fist len metres down it,
    the elbow back by his ribs; the wrist bends a little so the shaft keeps its lean, and the
    fist's middle lies towards his chest (thumb up)."""
    chest = PB["mixamorig:Spine2"].matrix
    fwd = chest.to_3x3() @ Vector((0, 0, 1))      # back from his chest ...
    fwd.z = 0
    hips = PB["mixamorig:Hips"].matrix.to_3x3() @ Vector((0, 0, 1))
    hips.z = 0
    fwd = fwd.normalized().lerp(hips.normalized(), cfg["travel"])   # ... or from his hips, the way he walks
    g = lean_dir(cfg, fwd.normalized())
    P = chest @ (B["mixamorig:Spine2"].matrix_local.inverted() @ Vector(cfg["contact"]))
    F = P - g * cfg["len"]
    pole = chest.to_3x3() @ (B["mixamorig:Spine2"].matrix_local.inverted().to_3x3() @ Vector(cfg["pole"]))
    palm = chest.to_3x3() @ (B["mixamorig:Spine2"].matrix_local.inverted().to_3x3() @ Vector((1, 0, 0.3)))
    T = F.copy()
    for _ in range(4):
        solve_arm("Right", T, pole, g, palm=palm, bend=True)
        T = T + (F - fist("Right"))
    fy = PB["mixamorig:RightForeArm"].matrix.to_3x3() @ Vector((0, 1, 0))
    hy = PB["mixamorig:RightHand"].matrix.to_3x3() @ Vector((0, 1, 0))
    return math.degrees(fy.angle(hy))                 # how far the wrist bends sideways


def ground_yaw(name):
    """How far a bone's forward (its Z axis) is turned on the ground from its rest, in radians,
    + = to his left."""
    cur = PB[name].matrix.to_3x3() @ Vector((0, 0, 1))
    rest = B[name].matrix_local.to_3x3() @ Vector((0, 0, 1))
    a = math.atan2(cur.y, cur.x) - math.atan2(rest.y, rest.x)
    return (a + math.pi) % (2 * math.pi) - math.pi


def twist_to(bones, target):
    """Twist bones about their own length (Y runs up the spine), each by its share, until the
    last one's ground yaw is target (radians); the twist about a leaning bone turns it a
    little more or less on the ground, hence the few rounds."""
    last = "mixamorig:" + bones[-1][0]
    for _ in range(3):
        d = target - ground_yaw(last)
        for name, w in bones:
            pb = PB["mixamorig:" + name]
            pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((0, 1, 0), d * w)
        bpy.context.view_layer.update()
    for name, _ in bones:
        PB["mixamorig:" + name].keyframe_insert("rotation_quaternion", frame=sc.frame_current)


def untwist_spine(share):
    """Turn his chest back towards his facing by share of its turn, over the spine bones."""
    twist_to(SPINE_SHARES, (1 - share) * ground_yaw("mixamorig:Spine2"))
    return math.degrees(ground_yaw("mixamorig:Spine2"))


def head_forward():
    """Head fully back to its rest orientation: looking straight ahead, level. The neck goes
    halfway there, then turns to halfway between his chest and his head, so the two joints
    share the twist."""
    for name, k in (("Neck", 0.5), ("Head", 1.0)):
        pb = PB["mixamorig:" + name]
        cur = pb.matrix.to_quaternion()
        rest = B["mixamorig:" + name].matrix_local.to_quaternion()
        rest.make_compatible(cur)
        M = cur.slerp(rest, k).to_matrix().to_4x4()
        M.translation = pb.matrix.translation
        set_matrix(pb, M)
        if name == "Neck":
            twist_to((("Neck", 1.0),), 0.5 * ground_yaw("mixamorig:Spine2"))
        else:
            pb.keyframe_insert("rotation_quaternion", frame=sc.frame_current)


ARM_BONES = [f"mixamorig:{s}{b}" for s in ("Left", "Right") for b in ("Shoulder", "Arm", "ForeArm", "Hand")]


def turn_two_handed(act, frames):
    """The turn: arms from the guard (looping its frames) on the turning body, the spear
    dipped by TURN_LOWER (eased), the front fist re-solved onto the dipped shaft."""
    idle = bpy.data.actions["idle"]
    n_idle = int(idle["frames"])
    rig.animation_data.action = idle
    guard = {}
    for k in range(1, n_idle + 1):
        sc.frame_set(k)
        guard[k] = {b: PB[b].rotation_quaternion.copy() for b in ARM_BONES}
    rig.animation_data.action = act
    n = len(frames)
    for i, f in enumerate(frames):
        sc.frame_set(f)
        for b in ARM_BONES:
            PB[b].rotation_quaternion = guard[(i % n_idle) + 1][b]
            PB[b].keyframe_insert("rotation_quaternion", frame=f)
        bpy.context.view_layer.update()
        ease = min(1.0, (i + 1) / TURN_EASE, (n - i) / TURN_EASE)
        ease = ease * ease * (3 - 2 * ease)
        r, l = fist("Right"), fist("Left")
        front = "Left"
        if (r - l).dot(facing()) > 0:
            r, l, front = l, r, "Right"
        z = (l - r).normalized()
        d = (l - r).length
        h = Vector((z.x, z.y, 0)).normalized()
        pitch = math.asin(max(-1.0, min(1.0, z.z))) - math.radians(TURN_LOWER) * ease
        z2 = h * math.cos(pitch) + UP * math.sin(pitch)
        T = r + z2 * d
        S = PB[f"mixamorig:{front}Arm"].matrix.translation.copy()
        W = PB[f"mixamorig:{front}Hand"].matrix.translation.copy()
        E = PB[f"mixamorig:{front}ForeArm"].matrix.translation.copy()
        pole = E - (S + W) / 2
        for _ in range(3):
            off = fist(front) - PB[f"mixamorig:{front}Hand"].matrix.translation
            solve_arm(front, T - off, pole, z2)


def frames_of(act):
    f0, f1 = (int(round(v)) for v in act.frame_range)
    return list(range(f0, f1 + 1))


def body_bvh():
    ev = bpy.data.objects["Spearman"].evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = ev.to_mesh()
    bvh = BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
    ev.to_mesh_clear()
    return bvh


def crosses(bvh, M, fists):
    """Does the spear at M cross the body anywhere more than 10 cm from the fists? Walks its
    axis and four lines CLEAR_R off it in STEP pieces, ray-casting each piece."""
    for ox, oy in ((0, 0), (CLEAR_R, 0), (-CLEAR_R, 0), (0, CLEAR_R), (0, -CLEAR_R)):
        p0 = M @ Vector((ox, oy, 0.0))
        for i in range(1, int(round(SPEAR_L / STEP)) + 1):
            p1 = M @ Vector((ox, oy, i * STEP))
            d = p1 - p0
            loc = bvh.ray_cast(p0, d.normalized(), d.length)[0]
            if loc is not None and min((loc - h).length for h in fists) > 0.10:
                return True
            p0 = p1
    return False


def wrist_clear(act, frames):
    """Bend the right wrist where the rigid spear would cross his body (see CLEAR_R). Returns
    [(first frame, last frame, direction degrees, largest bend degrees)] per stretch, the
    direction None where no bend up to CLEAR_MAX clears it (left straight)."""
    assert "wrist_clear" not in act, f"{act.name}: wrist already bent; run retarget_clips.py on it first"
    hand = PB["mixamorig:RightHand"]
    dirs = [Vector((math.cos(a), 0, math.sin(a))) for a in (math.radians(30 * k) for k in range(12))]
    angles = list(range(0, CLEAR_MAX + 1, 2))
    step = CLEAR_STEP // 2

    def tester(f):
        sc.frame_set(f)
        bvh, H, left = body_bvh(), hand.matrix.copy(), fist("Left")
        return lambda R: not crosses(bvh, H @ R @ REL, [H @ R @ fist_off["Right"], left])

    bad = [f for f in frames if not tester(f)(Matrix.Identity(4))]
    groups = []
    for f in bad:
        if groups and f - groups[-1][-1] <= 2 * CLEAR_PAD:
            groups[-1].append(f)
        else:
            groups.append([f])
    # States: the straight wrist, and each bend angle in each direction, as a 2D bend vector.
    states = [(0, 0)] + [(k, a) for k in range(len(dirs)) for a in angles[1:]]
    vec = [Vector((math.cos(math.radians(30 * k)), math.sin(math.radians(30 * k)))) * a for k, a in states]
    near = [[(j, (vec[i] - vec[j]).length_squared) for j in range(len(states))
             if (vec[i] - vec[j]).length <= CLEAR_STEP + 1e-6] for i in range(len(states))]
    rot = [Matrix.Rotation(math.radians(a), 4, dirs[k]) for k, a in states]
    out = []
    for g in groups:
        span = [f for f in frames if g[0] - CLEAR_PAD <= f <= g[-1] + CLEAR_PAD]
        ok = {}
        for f in span:
            clear = tester(f)
            ok[f] = [clear(R) for R in rot]
        cost = [0.0] + [math.inf] * (len(states) - 1)           # straight wrist before the span
        back = []
        for f in span:
            cur, arg = [math.inf] * len(states), [0] * len(states)
            for i in range(len(states)):
                if ok[f][i]:
                    for j, d2 in near[i]:
                        c = cost[j] + d2 + 0.2 * vec[i].length_squared
                        if c < cur[i]:
                            cur[i], arg[i] = c, j
            back.append(arg)
            cost = cur
        end = min((i for i in range(len(states)) if vec[i].length <= CLEAR_STEP + 1e-6),
                  key=lambda i: cost[i] + vec[i].length_squared)  # and straight again after it
        if cost[end] == math.inf:
            out.append((g[0], g[-1], [f for f in span if not any(ok[f])]))
            continue
        path, i = [], end
        for arg in reversed(back):
            path.append(i)
            i = arg[i]
        path.reverse()
        for f, i in zip(span, path):
            if i:
                sc.frame_set(f)
                k, a = states[i]
                hand.rotation_quaternion = hand.rotation_quaternion @ Quaternion(dirs[k], math.radians(a))
                hand.keyframe_insert("rotation_quaternion", frame=f)
        out.append((g[0], g[-1], max(states[i][1] for i in path)))
    act["wrist_clear"] = [str(o) for o in out]
    return out


for pb in PB:          # rigs saved before set_matrix kept that noise
    clear_unkeyed(pb)

# The rigid hold: the spear in the right fist as in the idle's first frame.
rig.animation_data_create()
rig.animation_data.action = bpy.data.actions["idle"]
sc.frame_set(1)
REL = PB["mixamorig:RightHand"].matrix.inverted() @ two_handed()
hips_rest_inv = B["mixamorig:Hips"].matrix_local.inverted()

clips = [c for c in MODES if c in bpy.data.actions and (only is None or c in only)]
for clip in clips:
    act = bpy.data.actions[clip]
    mode = MODES[clip]
    rig.animation_data.action = act
    sname = clip + "__spear"
    if sname in bpy.data.actions:
        bpy.data.actions.remove(bpy.data.actions[sname])
    sact = bpy.data.actions.new(sname)
    sact.use_fake_user = True
    spear.animation_data_create()
    spear.animation_data.action = sact
    frames = frames_of(act)
    fist_z, bend, chest_yaw = [], [], []
    if mode in ("carry", "shoulder"):
        cfg = CARRY_CFG if mode == "carry" else SHOULDER_CFG
        for f in frames:
            sc.frame_set(f)
            if mode == "shoulder":
                chest_yaw.append(untwist_spine(SPINE_UNTWIST))
                head_forward()
                bend.append(shoulder_ik(cfg))
            else:
                carry_ik(cfg)
            fist_z.append(fist("Right").z)
        grip_c = sum(fist_z) / len(fist_z) - cfg["butt_z"]
    if mode == "turn":
        turn_two_handed(act, frames)
    wrist = wrist_clear(act, frames) if mode == "rigid" else None
    release = None
    if mode == "drop":
        sc.frame_set(frames[0])
        h0 = PB["mixamorig:Hips"].matrix.translation.z
        for f in frames:
            sc.frame_set(f)
            if PB["mixamorig:Hips"].matrix.translation.z < 0.82 * h0:
                release = max(frames[0] + 1, f - 3)
                break
        release = release or frames[len(frames) // 3]
        sc.frame_set(release)
        M_rel = PB["mixamorig:RightHand"].matrix @ REL
        sc.frame_set(release - 1)
        vel = M_rel.translation - (PB["mixamorig:RightHand"].matrix @ REL).translation
        ax = M_rel.to_3x3() @ Vector((0, 0, 1))
        head = Vector((ax.x, ax.y, 0))
        if head.length < 0.2:
            head = facing()
        head.normalize()
        mid = M_rel @ Vector((0, 0, 1.2))                    # the spear's middle
        land = Vector((mid.x, mid.y, 0)) + Vector((vel.x, vel.y, 0)) * 6
        z_l = head
        # Where he ends up lying: keep the spear's landing spot clear of that footprint.
        sc.frame_set(frames[-1])
        dg = bpy.context.evaluated_depsgraph_get()
        ev = bpy.data.objects["Spearman"].evaluated_get(dg)
        me = ev.to_mesh()
        foot = [Vector((v.co.x, v.co.y)) for i, v in enumerate(me.vertices) if i % 4 == 0 and v.co.z < 0.6]
        ev.to_mesh_clear()
        cen = sum(foot, Vector((0, 0))) / max(1, len(foot))
        away = Vector((land.x, land.y)) - cen
        away = away.normalized() if away.length > 1e-3 else Vector((-z_l.y, z_l.x))

        def clearance(c, h):
            pts = [c + h * (t - 1.2) for t in (0.0, 0.3, 0.6, 0.9, 1.2, 1.5, 1.8, 2.1, 2.4)]
            return min((p - q).length for p in pts for q in foot)

        # A few headings and short slides away from where he ends up lying; the first that
        # clears him by 12 cm wins, otherwise the clearest.
        best = None
        c0, h0 = Vector((land.x, land.y)), Vector((z_l.x, z_l.y)).normalized()
        for push in (0.0, 0.1, 0.2, 0.3, 0.45, 0.6, 0.8):
            for ang in (0, 25, -25, 50, -50, 80, -80):
                h = Matrix.Rotation(math.radians(ang), 2) @ h0
                c = c0 + away * push
                cl = clearance(c, h)
                if best is None or cl > best[0]:
                    best = (cl, c, h)
                if cl > 0.12:
                    break
            if best[0] > 0.12:
                break
        _, c, h = best
        land = Vector((c.x, c.y, 0))
        z_l = Vector((h.x, h.y, 0)).normalized()
        R_land = frame_from_axis(z_l, UP.cross(z_l))          # lying flat, blade's flat facing up
        M_land = R_land.to_4x4()
        M_land.translation = land - z_l * 1.2 + Vector((0, 0, SHAFT_R))
        q0, q1 = M_rel.to_quaternion(), M_land.to_quaternion()
        q1.make_compatible(q0)
    for f in frames:
        sc.frame_set(f)
        if mode == "drop" and f >= release:
            u = min(1.0, (f - release) / DROP_FRAMES)
            e = u * u                                          # falls faster and faster
            M = q0.slerp(q1, e).to_matrix().to_4x4()
            M.translation = M_rel.translation.lerp(M_land.translation, e)
            spear.matrix_basis = M
            spear.keyframe_insert("location", frame=f)
            spear.keyframe_insert("rotation_quaternion", frame=f)
            continue
        if mode in ("two", "turn"):
            M = two_handed()
        elif mode in ("carry", "shoulder"):
            hips = PB["mixamorig:Hips"].matrix.to_3x3()
            z = (PB["mixamorig:RightHand"].matrix.to_3x3() @ Vector((1, 0, 0))).normalized()   # the fist's grip axis
            if z.z < 0:
                z = -z
            R = frame_from_axis(z, hips @ Vector((1, 0, 0)))
            M = R.to_4x4()
            M.translation = fist("Right") - z * grip_c
        else:
            M = PB["mixamorig:RightHand"].matrix @ REL
        spear.matrix_basis = M
        spear.keyframe_insert("location", frame=f)
        spear.keyframe_insert("rotation_quaternion", frame=f)
    for fc in getattr(sact, "fcurves", []):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    sact["mode"] = mode
    if release:
        sact["release_frame"] = release
    print("SPEAR", clip, mode, len(frames), "frames", "wrist bend up to %.0f deg" % max(bend) if bend else "",
          "chest turned %.0f to %.0f deg" % (min(chest_yaw), max(chest_yaw)) if chest_yaw else "",
          "wrist bent clear (first, last crossing frame, largest bend deg): %s" % wrist if wrist is not None else "")
rig.animation_data.action = bpy.data.actions["idle"]
spear.animation_data.action = bpy.data.actions["idle__spear"]
sc.frame_set(1)
assert all(tuple(pb.scale) == (1, 1, 1) and (pb.name == "mixamorig:Hips" or not any(pb.location)) for pb in PB)
bpy.ops.wm.save_mainfile(compress=True)
print("SPEAR_SAVED", bpy.data.filepath)
