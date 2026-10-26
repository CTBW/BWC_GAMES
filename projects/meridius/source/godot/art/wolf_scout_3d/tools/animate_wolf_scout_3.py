"""Wolf Scout 3 clips: Wolf Scout 2's approved motion on the new rig.

  blender -b --factory-startup --python animate_wolf_scout_3.py

Body motion comes from wolf_scout_2.blend (sneak, attack, death) as
world-space rotation changes from rest. The idle holds her standard pose, the
crouch in Animations/Crouching - Wolf scout.fbx, the same way (scaled to her
legs), and breathes, looks around and flicks her ears on top; a fist that would
reach into the floor is raised with the arm. The arms are first aligned from WS2's
A-pose rest to this T-pose rest. The legs are solved again with two-bone IK so
her feet ride on WS2's feet: her shins are 7 cm longer, so a plain rotation copy
would sink them into the floor in a crouch. Fingers hold the reverse grip the
rig script fitted to the dagger (GripPose on the rig).

The tail and the five cloak chains are a Verlet simulation that follows the body
with lag, gravity and collisions (legs, trunk, tail, floor), baked to keys. The
tail sways on top of that. In the idle it rests on a line of its own: out from under
the cape's left side, straight along the ground, sweeping up at the tip. Each cloak chain is drawn towards where a strip of
cloth from its anchor would fall: over her back, seat, thighs and tail, then
straight down; her trunk, thighs and tail push it out on the side of her back.
Those targets are smoothed over time, and in the idle and sneak so are the
simulated strips, so the cape hangs steady instead of fluttering. After the
simulation the chain bones turn outwards until the skinned cape clears the skinned
body, and a panel that would go under the floor is turned up (both eased over
neighbouring frames; in the idle the cape clears the whole tail with one turn held
throughout). Each tail bone keeps a steady roll about its length: it bends
and sways but does not turn round. Loops are simulated until periodic and closed at
the seam; in the death the tail and cloak go limp and settle over her and the floor,
the tail smoothed and bending at each joint no further than a tail can.

Output: art/wolf_scout_3d/wolf_scout_3.blend, review/.../wolf-scout-3/animation.json
"""
import bpy, json, math, os
import numpy as np
from pathlib import Path
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

ART = Path(__file__).resolve().parents[1]
REVIEW = ART.parents[5] / 'projects/meridius/review/wolf-scout/wolf-scout-3'
CLIPS = ('idle', 'sneak', 'attack', 'death')
LOOP = {'idle': True, 'sneak': True, 'attack': False, 'death': False}
FPS, SUB = 30, 4
H = 1 / (FPS * SUB)

def bind(owner, action):
    owner.animation_data_create(); owner.animation_data.action = action
    if action.slots: owner.animation_data.action_slot = action.slots[0]
def smooth(t):
    t = max(0.0, min(1.0, t)); return t * t * (3 - 2 * t)
def R3(m): return m.to_3x3().normalized()
def seg_closest(p, a, b):
    ab = b - a; t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-12))); return a + ab * t

# ------------------------------------------------------------- WS2 motion
bpy.ops.wm.open_mainfile(filepath=str(ART / 'wolf_scout_2.blend'))
sc = bpy.context.scene; old = bpy.data.objects['WolfScout_Rig']
OREST = {b.name: b.matrix_local.copy() for b in old.data.bones}
SRC, PROPS = {}, {}
for name in CLIPS:
    a = bpy.data.actions[name]; bind(old, a)
    PROPS[name] = json.loads(json.dumps(dict(a.items()), default=lambda v: list(v)))
    SRC[name] = []
    for f in range(1, int(a['frames']) + 1):
        sc.frame_set(f); SRC[name].append({p.name: p.matrix.copy() for p in old.pose.bones})
print('SAMPLED', {n: len(s) for n, s in SRC.items()}, flush=True)

# ------------------------------------------------------------- crouch
# Her standard pose, which the idle holds: a static Mixamo crouch (Y Bot, T-pose
# rest), in world space. It has no ears; they ride on the head.
bpy.ops.import_scene.fbx(filepath=str(ART.parents[5] / 'projects/meridius/Animations/Crouching - Wolf scout.fbx'))
ybot = next(o for o in sc.objects if o.type == 'ARMATURE' and o != old); sc.frame_set(1)
CREST = {b.name: ybot.matrix_world @ b.matrix_local for b in ybot.data.bones}
CROUCH = {p.name: ybot.matrix_world @ p.matrix for p in ybot.pose.bones}
for d in (CREST, CROUCH):
    d['Ear.Left'] = d['mixamorig:Head'].copy(); d['Ear.Right'] = d['mixamorig:Head'].copy()
IDLE_FRAMES = 121   # 4 s loop

# ------------------------------------------------------------- WS3 rig
bpy.ops.wm.open_mainfile(filepath=str(ART / 'wolf_scout_3_rig.blend'))
sc = bpy.context.scene; rig = bpy.data.objects['WolfScout3_Rig']; B = rig.data.bones; P = rig.pose.bones
body = bpy.data.objects['WolfScout3_Body']
ORDER = []
def visit(b):
    ORDER.append(b.name)
    for c in b.children: visit(c)
for b in B:
    if b.parent is None: visit(b)
REST = {n: B[n].matrix_local.copy() for n in ORDER}
PAR = {n: (B[n].parent.name if B[n].parent else None) for n in ORDER}
REL = {n: (REST[PAR[n]].inverted() @ REST[n]) if PAR[n] else REST[n] for n in ORDER}
FINGERS = ('Thumb', 'Index', 'Middle', 'Ring', 'Pinky')
def is_finger(n): return 'Hand' in n and any(f in n for f in FINGERS)

SRCNAME = {n: n for n in ORDER if n.startswith('mixamorig:') and not is_finger(n)}
SRCNAME.update({'Ear.L': 'Ear.Left', 'Ear.R': 'Ear.Right'})
ARMS = {f'mixamorig:{s}{p}' for s in ('Left', 'Right') for p in ('Arm', 'ForeArm', 'Hand')}
def bases(O, align):
    """world rotation = source posed rotation @ base. Aligned bones first turn the
    new rest onto the source's bone direction (WS2's A-pose arms, the Y Bot)."""
    out = {}
    for n, o in SRCNAME.items():
        if o not in O: continue
        base = R3(O[o]).inverted()
        if align(n):
            y_new = R3(REST[n]) @ Vector((0, 1, 0)); y_old = R3(O[o]) @ Vector((0, 1, 0))
            base = base @ y_new.rotation_difference(y_old).to_matrix()
        out[n] = base @ R3(REST[n])
    return out
BASE = bases(OREST, lambda n: n in ARMS)
CBASE = bases(CREST, lambda n: n.startswith('mixamorig:'))
# The Y Bot's positions scaled to her legs, so the crouch bends her knees as much as its.
def leg_len(R, s):
    j = [R[f'mixamorig:{s}{b}'].translation for b in ('UpLeg', 'Leg', 'Foot')]
    return (j[1] - j[0]).length + (j[2] - j[1]).length
K = leg_len(REST, 'Left') / leg_len(CREST, 'Left')
for d in (CREST, CROUCH):
    for m in d.values(): m.translation = m.translation * K
print('CROUCH scale', round(K, 4), 'missing', sorted(n for n, o in SRCNAME.items() if o not in CROUCH), flush=True)
SRC['idle'] = [CROUCH] * IDLE_FRAMES
PLANTED = [s for s in ('Left', 'Right') if CROUCH[f'mixamorig:{s}Hand'].translation.z < 0.3]
print('PLANTED', PLANTED, {s: round(CROUCH[f'mixamorig:{s}Hand'].translation.z, 3) for s in ('Left', 'Right')}, flush=True)
KIDS = {n: [c for c in ORDER if PAR[c] == n] for n in ORDER}
def desc(n): return [n] + [d for c in KIDS[n] for d in desc(c)]

# The reverse grip fitted to the dagger by rig_wolf_scout_3.py (local finger rotations).
GRIP = {n: Quaternion(rig['GripPose'][n]).to_matrix().to_4x4() if n in rig['GripPose'] else Matrix()
        for n in ORDER if is_finger(n)}

def two_bone(Hp, A, l1, l2, pole):
    d = A - Hp; dist = d.length; u = d / dist
    reach = min(max(dist, abs(l1 - l2) + 1e-4), (l1 + l2) * 0.9995)
    A2 = Hp + u * reach
    v = pole - u * pole.dot(u)
    v = v.normalized() if v.length > 1e-6 else Vector((0, -1, 0))
    a = (l1 * l1 - l2 * l2 + reach * reach) / (2 * reach)
    return Hp + u * a + v * math.sqrt(max(l1 * l1 - a * a, 0.0)), A2, dist / (l1 + l2)

def body_pose(src, stats, O, BS):
    """WS3 armature-space pose matrices for one source frame (rest O, bases BS); tail and cloak rigid."""
    pose, ankle = {}, {}
    for n in ORDER:
        par = PAR[n]; base = (pose[par] if par else Matrix()) @ REL[n]; head = base.translation.copy()
        if n in BS:
            o = SRCNAME[n]; rot = R3(src[o]) @ BS[n]
            if n == 'mixamorig:Hips':
                head = (src[o] @ O[o].inverted()) @ REST[n].translation
        elif is_finger(n):
            rot = R3(base @ GRIP[n])
        else:
            rot = R3(base)
        if n.endswith('UpLeg'):
            side = n[10:-5]; leg, foot = f'mixamorig:{side}Leg', f'mixamorig:{side}Foot'
            target = (src[foot] @ O[foot].inverted()) @ REST[foot].translation
            l1, l2 = B[n].length, B[leg].length
            y1 = rot @ Vector((0, 1, 0)); y2 = R3(src[leg]) @ BS[leg] @ Vector((0, 1, 0))
            knee_fk = head + y1 * l1; ankle_fk = knee_fk + y2 * l2
            pole = (knee_fk - (head + ankle_fk) / 2) + rot @ Vector((0, 0, 0.02))   # local Z is her front
            knee, ankle[side], ratio = two_bone(head, target, l1, l2, pole)
            stats['reach_max'] = max(stats.get('reach_max', 0), ratio)
            if ratio > 0.9995: stats['clamped'] = stats.get('clamped', 0) + 1
            rot = y1.rotation_difference(knee - head).to_matrix() @ rot
        elif n.endswith('Leg') and not n.endswith('UpLeg'):
            side = n[10:-3]
            rot = (rot @ Vector((0, 1, 0))).rotation_difference(ankle[side] - head).to_matrix() @ rot
        pose[n] = Matrix.Translation(head) @ rot.to_4x4()
    return pose

# ------------------------------------------------------------- idle life
# Each closed fist with its dagger as points in the hand bone's frame, to keep
# them on top of the floor.
for n, q in rig['GripPose'].items(): P[n].rotation_mode = 'QUATERNION'; P[n].rotation_quaternion = q
bpy.context.view_layer.update(); dg = bpy.context.evaluated_depsgraph_get()
FIST = {}
for side in ('Left', 'Right'):
    hb = f'mixamorig:{side}Hand'; inv = REST[hb].inverted() @ rig.matrix_world.inverted(); pts = []
    for o in (body, bpy.data.objects[f'WolfScout3_Dagger.{side}']):
        names = {g.index: g.name for g in o.vertex_groups}
        ev = o.evaluated_get(dg); me = ev.to_mesh()
        for v, ve in zip(o.data.vertices, me.vertices):
            if len(v.groups) and names[max(v.groups, key=lambda g: g.weight).group].startswith(hb):
                pts.append(inv @ o.matrix_world @ ve.co)
        ev.to_mesh_clear()
    FIST[side] = pts
for pb in P: pb.matrix_basis = Matrix()

def turn(pose, about, axis, deg, keep=()):
    """Turn a bone and everything under it about its head; the chains in keep only move along."""
    h = pose[about].translation.copy()
    M = Matrix.Translation(h) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-h)
    moved = set()
    for k in keep:
        d = M @ pose[k].translation - pose[k].translation
        for n in desc(k): pose[n] = Matrix.Translation(d) @ pose[n]; moved.add(n)
    for n in desc(about):
        if n not in moved: pose[n] = M @ pose[n]

def life(pose, fi, period):
    """The held crouch breathes, looks around and flicks an ear now and then."""
    ph = 2 * math.pi * fi / period
    def side_axis(n): return R3(pose[n]) @ R3(REST[n]).inverted() @ Vector((1, 0, 0))
    def up_axis(n): return R3(pose[n]) @ R3(REST[n]).inverted() @ Vector((0, 0, 1))
    turn(pose, 'mixamorig:Spine1', side_axis('mixamorig:Spine1'), 1.3 * math.sin(3 * ph),
         [f'mixamorig:{s}Arm' for s in ('Left', 'Right')])   # three breaths, arms ride along
    turn(pose, 'mixamorig:Neck', Vector((0, 0, 1)), 8 * math.sin(ph))
    turn(pose, 'mixamorig:Neck', side_axis('mixamorig:Neck'), 2.5 * math.sin(2 * ph + 1))
    for ear, at, s in (('Ear.L', 0.22, 1), ('Ear.R', 0.55, -1), ('Ear.L', 0.83, 1)):
        u = (fi - at * period) / 9   # back in three frames, up again in six
        if not 0 <= u <= 1: continue
        e = smooth(u / 0.33) if u < 0.33 else 1 - smooth((u - 0.33) / 0.67)
        turn(pose, ear, side_axis('mixamorig:Head'), -20 * e)
        turn(pose, ear, up_axis('mixamorig:Head'), s * 10 * e)

def aim_blade(pose, side, bend=35):
    """Point a blade back: along the ground from a planted fist, else up the outside of
    the forearm. The forearm and hand twist about the forearm (half each), then the
    wrist bends at most bend degrees."""
    f, h, s = (f'mixamorig:{side}ForeArm', f'mixamorig:{side}Hand', f'DaggerSocket.{side}')
    def blade(): return R3(pose[s]) @ Vector((0, 1, 0))
    ax = (pose[h].translation - pose[f].translation).normalized()
    back = R3(pose['mixamorig:Hips']) @ R3(REST['mixamorig:Hips']).inverted() @ Vector((0, 1, 0))
    out = R3(pose['mixamorig:Hips']) @ R3(REST['mixamorig:Hips']).inverted() @ Vector((1 if side == 'Left' else -1, 0, 0))
    if side in PLANTED: want = Vector((back.x, back.y, 0)).normalized()
    else: want = (-ax + 0.35 * out + 0.25 * back).normalized()
    u, v = blade() - ax * blade().dot(ax), want - ax * want.dot(ax)
    twist = math.degrees(math.atan2(ax.dot(u.cross(v)), u.dot(v)))
    turn(pose, f, ax, twist / 2); turn(pose, h, ax, twist / 2)
    q = blade().rotation_difference(want)
    turn(pose, h, q.axis, min(math.degrees(q.angle), bend))
    return round(twist, 1), round(math.degrees(blade().angle(want)), 1)

def fist_low(pose, side):
    return min((pose[f'mixamorig:{side}Hand'] @ p).z for p in FIST[side])

def lift_fist(pose, side, dz):
    """Raise a hand by dz with the arm bent to suit (two-bone IK); the hand keeps its turn."""
    a, f, h = (f'mixamorig:{side}{b}' for b in ('Arm', 'ForeArm', 'Hand'))
    A, E, W = (pose[n].translation.copy() for n in (a, f, h))
    E2, W2, _ = two_bone(A, W + Vector((0, 0, dz)), (E - A).length, (W - E).length, E - (A + W) / 2)
    pose[a] = Matrix.Translation(A) @ ((E - A).rotation_difference(E2 - A).to_matrix() @ R3(pose[a])).to_4x4()
    pose[f] = Matrix.Translation(E2) @ ((W - E).rotation_difference(W2 - E2).to_matrix() @ R3(pose[f])).to_4x4()
    for n in desc(h): pose[n] = Matrix.Translation(W2 - W) @ pose[n]

# ------------------------------------------------------------- colliders
def bone_seg(pose, n):
    m = pose[n]; return m.translation, m.translation + R3(m) @ Vector((0, B[n].length, 0))
def radius(n, pct, wmin=0.5):
    gi = body.vertex_groups[n].index; a, b = bone_seg(REST, n)
    ds = sorted((v.co - seg_closest(v.co, a, b)).length for v in body.data.vertices
                for g in v.groups if g.group == gi and g.weight > wmin)
    return ds[int(len(ds) * pct)] if ds else 0.05
LEGS = [f'mixamorig:{s}{p}' for s in ('Left', 'Right') for p in ('UpLeg', 'Leg', 'Foot')]
BODY_COL = {n: radius(n, 0.85) for n in LEGS + ['mixamorig:Hips', 'mixamorig:Spine', 'mixamorig:Spine1']}
TAIL = [f'Tail.0{i}' for i in range(1, 7)]
TAIL_R = [radius(n, 0.6) for n in TAIL]
def below(n):
    gi = body.vertex_groups[n].index
    return [v.co.z for v in body.data.vertices for g in v.groups if g.group == gi and g.weight > 0.3]
CHAINS = {c: [f'Cloak.{c}.{i}' for i in (1, 2, 3)] for c in ('Edge.R', 'Back.R', 'Back.C', 'Back.L', 'Edge.L')}
print('RADII', {k.split(':')[-1]: round(v, 3) for k, v in BODY_COL.items()}, 'tail', [round(r, 3) for r in TAIL_R], flush=True)

def points(pose, names):
    return [pose[names[0]].translation.copy()] + [bone_seg(pose, n)[1] for n in names]

def capped(rest_pts, segs, want):
    """Per point radius for each collider, never more than its rest clearance."""
    out = []
    for (a, b), r in zip(segs, want):
        out.append([min(r, (p - seg_closest(p, a, b)).length - 0.01) for p in rest_pts])
    return out

REST_TAIL = points(REST, TAIL)
# How far the fur reaches below each tail point at rest (either neighbouring bone).
TAIL_FLOOR = [0.0] + [max(REST_TAIL[i].z - min(below(TAIL[j])) for j in {i - 1, min(i, 5)}) + 0.01 for i in range(1, 7)]
print('TAIL_FLOOR', [round(x, 3) for x in TAIL_FLOOR], flush=True)
REST_CLOAK = {c: points(REST, ns) for c, ns in CHAINS.items()}
tail_cols = LEGS   # leg radius plus most of the tail's own thickness at each point
TAIL_CAP = [[min(BODY_COL[n] + 0.7 * TAIL_R[min(i, 5)], (p - seg_closest(p, *bone_seg(REST, n))).length - 0.01)
             for i, p in enumerate(REST_TAIL)] for n in tail_cols]
TRUNK = ['mixamorig:Hips', 'mixamorig:Spine', 'mixamorig:Spine1']
cloak_body = LEGS + TRUNK
BEHIND = set(TRUNK) | {'mixamorig:LeftUpLeg', 'mixamorig:RightUpLeg', 'tail'}
rest_tail_segs = [(REST_TAIL[i], REST_TAIL[i + 1]) for i in range(6)]
# The rest cape hangs through the tail (the tail moves); the simulation lays it over it.
CLOAK_CAP = {c: capped(REST_CLOAK[c], [bone_seg(REST, n) for n in cloak_body], [BODY_COL[n] + 0.025 for n in cloak_body])
             + [[r + 0.03] * 4 for r in TAIL_R] for c in CHAINS}
# Her idle tail lies out from under the cape's left side, close under the cloth:
# there the cape keeps further off it, so the panels between the chains clear its fur.
CAPE_TAIL_GAP = {'idle': 0.06}

# ------------------------------------------------------------- simulation
def simulate(goals, lengths, k, damp, grav, collide, floor, loop, env=None):
    """Verlet chain. goals[f] = target points, point 0 the anchor. collide(f, X) moves
    points out of colliders in place. Returns points per frame (and the seam error)."""
    n, m = len(goals), len(goals[0])
    frames = list(range(n - 1)) if loop else list(range(n))
    X = [p.copy() for p in goals[0]]; Xp = [p.copy() for p in X]
    def step(G, fi, kk):
        for i in range(1, m):
            v = (X[i] - Xp[i]) * (1 - damp); Xp[i] = X[i].copy()
            X[i] = X[i] + v + Vector((0, 0, -9.81 * grav * H * H))
            X[i] = X[i] + (G[i] - X[i]) * k[i] * kk
        X[0] = G[0].copy(); Xp[0] = G[0].copy()
        for _ in range(3):
            for i in range(1, m):
                X[i] = X[i - 1] + (X[i] - X[i - 1]).normalized() * lengths[i - 1]
            collide(fi, X)
            for i in range(1, m): X[i].z = max(X[i].z, floor[i])
    def frame(fi, prev):
        kk = env(fi) if env else 1.0
        for s in range(1, SUB + 1):
            step([prev[i].lerp(goals[fi][i], s / SUB) for i in range(m)], fi, kk)
    if not loop:
        for _ in range(40): frame(0, goals[0])
    rec = []
    for _ in range(3 if loop else 1):
        rec = []
        for j, fi in enumerate(frames):
            frame(fi, goals[frames[j - 1]] if (j or loop) else goals[0]); rec.append([p.copy() for p in X])
    seam = 0.0
    if loop:
        frame(frames[0], goals[frames[-1]])
        err = [X[i] - rec[0][i] for i in range(m)]; N = len(frames)
        seam = max(e.length for e in err)
        rec = [[p - err[i] * (j / N) for i, p in enumerate(ps)] for j, ps in enumerate(rec)]
        rec.append([p.copy() for p in rec[0]])
    return rec, seam

# Cloak vertices that belong mostly to each chain bone, in the bone's rest frame:
# where a panel reaches beyond its chain, for the floor.
cloak_ob = bpy.data.objects['WolfScout3_Cloak']; SAMPLES = {}
for ns in CHAINS.values():
    for b in ns:
        gi = cloak_ob.vertex_groups[b].index; inv = REST[b].inverted()
        vs = [inv @ v.co for v in cloak_ob.data.vertices for g in v.groups if g.group == gi and g.weight > 0.5]
        SAMPLES[b] = vs[::max(1, len(vs) // 80)]

def floor_twist(head, rot, S):
    """Smallest turn about the bone that keeps its panel above the floor."""
    offs = [rot @ s for s in S]
    if not offs or min(head.z + o.z for o in offs) >= 0.01: return 0.0
    y = rot @ Vector((0, 1, 0)); best = None
    for deg in sorted(range(-120, 121, 5), key=abs):
        Q = Matrix.Rotation(math.radians(deg), 3, y); lo = min(head.z + (Q @ o).z for o in offs)
        if lo >= 0.01: return math.radians(deg)
        if best is None or lo > best[0]: best = (lo, deg)
    return math.radians(best[1])

def aim(pose, names, pts, twist=None):
    """Point each chain bone at the next simulated point. twist: None for no
    floor twist, 'find' to choose it, or one angle per bone."""
    used = []
    for i, n in enumerate(names):
        base = pose[PAR[n]] @ REL[n]; head = base.translation.copy(); rot = R3(base)
        rot = (rot @ Vector((0, 1, 0))).rotation_difference(pts[i + 1] - head).to_matrix() @ rot
        if twist is not None:
            a = floor_twist(head, rot, SAMPLES[n]) if twist == 'find' else twist[i]
            rot = Matrix.Rotation(a, 3, rot @ Vector((0, 1, 0))) @ rot; used.append(a)
        pose[n] = Matrix.Translation(head) @ rot.to_4x4()
    return used

def yaw_of(m, rest):
    """Heading of a bone's turn from rest: from its side axis, which stays level
    when she bends forward, else from its front."""
    R = R3(m @ rest.inverted()); x = R @ Vector((1, 0, 0))
    if Vector((x.x, x.y)).length > 0.5: return math.atan2(x.y, x.x)
    f = R @ Vector((0, -1, 0))
    return math.atan2(f.x, -f.y) if Vector((f.x, f.y)).length > 0.3 else None

WAG = {'idle': (11, 2), 'sneak': (8, 1), 'attack': (5, 1), 'death': (0, 1)}   # degrees at the tip, cycles per clip
TAIL_K = [0, 0.5, 0.36, 0.26, 0.19, 0.14, 0.11]
# Her crouched idle rests the tail on its own line instead of the standing pose's:
# straight out from her seat, turned the given degrees to her left of the rest
# tail's heading, each bone pitched the given degrees above level, so it slopes down,
# lies along the ground on its fur and sweeps up at the tip. Turned with her hips,
# the standing tail dove into the floor, was pushed back up over its own fur and
# zigzagged. The turn takes it out under the cape's left side, past the corner that
# hangs to the ground over the rest heading. TAIL_FLOOR, measured on the hanging rest
# tail, would hold a lying one 0.2 m up, so on this line the floor gives way to it.
TAIL_LINE = {'idle': (20, (-35, -35, -25, -3, 20, 60))}
CLOAK_K = [0, 0.3, 0.15, 0.09]
# Smoothing over time, in frames (Gaussian sigma): each cape strip's drape target
# and its simulated points (0: none), then how much of each one's motion about its
# mean over the clip is kept. The drape target jumps when a thigh enters or leaves
# the strip's slice, and a point that a thigh catches is put on its back side at
# once; both made the cape flutter. In the idle she hardly moves, so neither does it.
SMOOTH = {'idle': (4, 2, 0.4, 0.4), 'sneak': (3, 2, 0.5, 1.0), 'attack': (2, 0, 1.0, 1.0), 'death': (2, 2, 1.0, 1.0)}
# The tail's roll: the hips' turn it rides on is smoothed over ROLL_SMOOTH frames
# (the sneak's sway; the attack follows the hips as they are), and each bone keeps its
# mean roll over the clip. The death has no entry: its limp tail moves too far for a
# mean roll, and keeps the roll aim() gives it once its bends are limited below.
ROLL_SMOOTH = {'idle': 5, 'sneak': 3, 'attack': 0}
# In the death the limp tail was thrown about by the floor and her legs: in a frame a
# joint kinked by up to 86 degrees, and its root folded back to 170, where aim()'s roll
# flips. Each joint bends at most TAIL_BEND_MAX degrees from its rest direction on its
# parent, and the points are smoothed over TAIL_SMOOTH frames in the frame of her hips.
TAIL_BEND_MAX = {'death': 110}
TAIL_SMOOTH = {'death': 2}

def gauss(vals, sigma, loop):
    """Each frame's value as the Gaussian-weighted mean of its neighbours'. A loop
    wraps (its last frame repeats the first); otherwise the end frames are held."""
    n = len(vals); P = n - 1 if loop else n; r = int(3 * sigma)
    if r < 1: return [v.copy() for v in vals]
    w = [math.exp(-0.5 * (k / sigma) ** 2) for k in range(-r, r + 1)]
    out = []
    for f in range(P):
        acc = vals[f] * 0.0
        for k, wk in zip(range(-r, r + 1), w):
            acc = acc + vals[(f + k) % P if loop else min(max(f + k, 0), n - 1)] * wk
        out.append(acc / sum(w))
    if loop: out.append(out[0].copy())
    return out

def smooth_chain(pts, poses, sigma, loop, kept=1.0, bone='mixamorig:Spine2'):
    """Smooths each point of a chain (point 0 its anchor) over time as an offset from
    the anchor in the frame of `bone` (her upper back), in place, keeping `kept` of
    its motion about the mean offset."""
    sp = [R3(pose[bone]) for pose in poses]
    P = len(pts) - 1 if loop else len(pts)
    for i in range(1, len(pts[0])):
        off = gauss([sp[f].transposed() @ (pts[f][i] - pts[f][0]) for f in range(len(pts))], sigma, loop)
        mean = sum(off[:P], Vector()) / P
        for f, o in enumerate(off): pts[f][i] = pts[f][0] + sp[f] @ (mean + (o - mean) * kept)

def quats(mats):
    q = [m.to_quaternion() for m in mats]
    for i in range(1, len(q)): q[i].make_compatible(q[i - 1])
    return q

def mean_turns(mats, sigma, loop):
    """Rotations averaged over time: over `sigma` frames (Gaussian; 0 leaves them
    as they are), or over the whole clip for None."""
    q = [Vector(x) for x in quats(mats)]
    if sigma is not None: return [Quaternion(v).normalized().to_matrix() for v in gauss(q, sigma, loop)]
    m = Quaternion(sum(q[:len(q) - 1 if loop else len(q)], Vector((0, 0, 0, 0)))).normalized().to_matrix()
    return [m] * len(mats)

def steady_roll(poses, names, loop, hips_sigma):
    """Keeps each bone's roll about its own length steady: the bone points where it
    did, turned the shortest way from its mean frame over the clip (riding on the
    smoothed hips). aim() turns each bone the shortest way from its rest direction on
    its parent: along a curving, swaying tail those turns roll the bones, and a joint
    bent far from its rest rolls a lot for a small move, so her fur turned round it.
    Returns the largest change in degrees."""
    D = mean_turns([R3(p['mixamorig:Hips']) @ R3(REST['mixamorig:Hips']).transposed() for p in poses], hips_sigma, loop)
    Y = Vector((0, 1, 0)); most = 0.0
    for n in names:
        Q = [D[f].transposed() @ R3(p[n]) for f, p in enumerate(poses)]
        M = mean_turns(Q, None, loop)
        for f, p in enumerate(poses):
            R = D[f] @ (M[f] @ Y).rotation_difference(Q[f] @ Y).to_matrix() @ M[f]
            a = R3(p[n]).to_quaternion().rotation_difference(R.to_quaternion()).angle
            most = max(most, min(a, 2 * math.pi - a))
            p[n] = Matrix.Translation(p[n].translation) @ R.to_4x4()
    return round(math.degrees(most), 1)

# ------------------------------------------------------------- cloak clearance
# The chains collide only as points with round colliders, so the sheet between
# them can still cut into her seat, back or tail root. After the simulation each
# chain bone turns outwards about its head, top down, until the skinned cape
# clears the skinned body.
NB = {n: i for i, n in enumerate(ORDER)}
REST_INV = {n: REST[n].inverted() for n in ORDER}
def skin_table(ob, keep=None):
    """Rows, rest positions, bone indices and weights (four at most) of a mesh."""
    names = {g.index: g.name for g in ob.vertex_groups}
    rows, idx, w = [], [], []
    for v in ob.data.vertices:
        gs = sorted(((g.weight, names[g.group]) for g in v.groups if names[g.group] in NB and g.weight > 0), reverse=True)[:4]
        if not gs or (keep and gs[0][1] not in keep): continue
        tot = sum(a for a, _ in gs); pad = 4 - len(gs)
        rows.append(v.index); idx.append([NB[b] for _, b in gs] + [0] * pad); w.append([a / tot for a, _ in gs] + [0] * pad)
    co = np.array([(*ob.data.vertices[i].co, 1.0) for i in rows])
    return np.array(rows), co, np.array(idx), np.array(w)
def skinned(tab, pose):
    _, co, idx, w = tab
    M = np.array([np.array(pose[n] @ REST_INV[n]) for n in ORDER])
    return (np.einsum('nkij,nj->nki', M[idx], co)[..., :3] * w[..., None]).sum(1)
BODY_TAB = skin_table(body)
_row = {v: k for k, v in enumerate(BODY_TAB[0])}
BODY_POLYS = [[_row[i] for i in p.vertices] for p in body.data.polygons if all(i in _row for i in p.vertices)]
# Only her back, seat, thighs and tail root count: the arms come and go under
# the cape's sides and the tuft's spiky fur has no clear inside.
CLEAR_BONES = {f'mixamorig:{n}' for n in ('Hips', 'Spine', 'Spine1', 'Spine2', 'LeftUpLeg', 'RightUpLeg')} | {'Tail.01', 'Tail.02'}
# Her idle tail lies out from under the cape, so there the cape also clears the
# rest of it; in the other clips the tail swings through the cape too fast for that.
CLEAR_MORE = {'idle': {'Tail.03', 'Tail.04', 'Tail.05'}}
# In the idle each chain bone keeps one clearance turn, the largest any frame
# needs, so the cape rests over the swaying tail instead of following it.
STEADY_CLEAR = {'idle'}
_dom = {r: ORDER[BODY_TAB[2][k][0]] for k, r in enumerate(BODY_TAB[0])}
def face_ok(bones):
    return [sum(_dom.get(BODY_TAB[0][i]) in bones for i in f) * 2 > len(f) for f in BODY_POLYS]
FACE_OK = face_ok(CLEAR_BONES)
CLOAK_TAB = skin_table(cloak_ob)
CHAIN_OF = {b: ns for ns in CHAINS.values() for b in ns}
OWN, OWN_W = [], []   # each cape vertex's strongest chain bone
for ks, ws in zip(CLOAK_TAB[2], CLOAK_TAB[3]):
    c = [(w, ORDER[k]) for k, w in zip(ks, ws) if ORDER[k] in CHAIN_OF and w > 0]
    w, b = max(c) if c else (0.0, None); OWN.append(b); OWN_W.append(w)
print('CLEARANCE body verts', len(BODY_TAB[0]), 'polys', len(BODY_POLYS), 'cape verts on chains', sum(b is not None for b in OWN), flush=True)

def cape_pen(pose, bvh, margin, level=None):
    """Deepest intrusion (margin minus clearance) per chain bone: (depth, point,
    normal), from the vertices that bone mostly moves, well away from its head."""
    out = {}
    for k, p in enumerate(skinned(CLOAK_TAB, pose)):
        b = OWN[k]
        if b is None or OWN_W[k] < 0.4 or (level is not None and b not in level): continue
        p = Vector(p)
        if (p - pose[b].translation).length < 0.12: continue
        loc, nrm, face, _ = bvh.find_nearest(p, 0.15)
        if loc is None or not FACE_OK[face]: continue
        d = (margin - (p - loc).dot(nrm)) / OWN_W[k]
        if d > 0 and d > out.get(b, (0,))[0]: out[b] = (d, p, nrm)
    return out

def cape_low(pose, bones):
    """Lowest cape vertex that the given chain bones mostly move."""
    m = np.array([b in bones for b in OWN])
    return float(skinned(CLOAK_TAB, pose)[m, 2].min()) if m.any() else 9.0

def clear_cape(pose, margin=0.012, most=math.radians(40)):
    bvh = BVHTree.FromPolygons(skinned(BODY_TAB, pose).tolist(), BODY_POLYS)
    before = max((d for d, _, _ in cape_pen(pose, bvh, margin).values()), default=0.0)
    turned = {}
    for _ in range(3):
        for i in range(3):
            level = {ns[i] for ns in CHAINS.values()}
            for b, (d, p, nrm) in cape_pen(pose, bvh, margin, level).items():
                h = pose[b].translation.copy(); arm = p - h; axis = arm.cross(nrm)
                if axis.length < 1e-6: continue
                s = max(0.3, 1 - (arm.normalized().dot(nrm)) ** 2)
                ang = min(math.atan2(d, arm.length * s), most - turned.get(b, 0.0))
                if ang <= 0: continue
                ns = CHAIN_OF[b]; below = ns[ns.index(b):]; keep = {m: pose[m] for m in below}
                z0 = cape_low(pose, below)
                for f in (1.0, 0.5, 0.25):   # never into the floor
                    R = Matrix.Translation(h) @ Matrix.Rotation(ang * f, 4, axis.normalized()) @ Matrix.Translation(-h)
                    for m in below: pose[m] = R @ keep[m]
                    if cape_low(pose, below) >= min(z0, 0.01): turned[b] = turned.get(b, 0.0) + ang * f; break
                else:
                    pose.update(keep)
    left = cape_pen(pose, bvh, margin)
    after = max((d for d, _, _ in left.values()), default=0.0)
    if after > 0.05 and DEBUG_PEN[0] < 12:
        DEBUG_PEN[0] += 1
        print('PEN left', {b: (round(d, 3), tuple(round(c, 2) for c in p), tuple(round(c, 2) for c in nrm), round(math.degrees(turned.get(b, 0)), 1)) for b, (d, p, nrm) in left.items() if d > 0.03}, flush=True)
    return before, after, max(turned.values(), default=0.0)
DEBUG_PEN = [0]

def pen_depth(pose, margin=0.012):
    bvh = BVHTree.FromPolygons(skinned(BODY_TAB, pose).tolist(), BODY_POLYS)
    return max((d for d, _, _ in cape_pen(pose, bvh, margin).values()), default=0.0)

def chain_local(pose):
    return {b: R3(pose[PAR[b]]).transposed() @ R3(pose[b]) for b in CHAIN_OF}

def eased_turns(turns, loop):
    """Each frame's clearance turns (per chain bone, in its parent's frame), eased
    over its neighbours like the floor lift: the strongest of its own and its
    neighbours' turns, scaled down with the distance, then averaged once with them."""
    F = len(turns); P = F - 1 if loop else F
    def at(f): return turns[f % P] if loop else turns[min(max(f, 0), F - 1)]
    out = []
    for f in range(P):
        row = {}
        for b in CHAIN_OF:
            w, q = max(((w, at(f + o)[b]) for o, w in ((0, 1), (-1, 0.7), (1, 0.7), (-2, 0.4), (2, 0.4))),
                       key=lambda t: t[0] * t[1].angle)
            row[b] = Quaternion().slerp(q, w)
        out.append(row)
    def at2(f): return out[f % P] if loop else out[min(max(f, 0), P - 1)]
    eased = []
    for f in range(P):
        row = {}
        for b in CHAIN_OF:
            q = at2(f)[b]; acc = Vector(q) * 0.5
            for o in (-1, 1):
                p = at2(f + o)[b].copy(); p.make_compatible(q); acc += Vector(p) * 0.25
            row[b] = Quaternion(acc).normalized()
        eased.append(row)
    if loop: eased.append(eased[0])
    return eased

def turn_chains(pose, turns):
    """Applies turns from eased_turns to the chains, root to tip."""
    for ns in CHAINS.values():
        local = {b: pose[PAR[b]].inverted() @ pose[b] for b in ns}
        for b in ns:
            L = local[b]
            pose[b] = pose[PAR[b]] @ Matrix.Translation(L.translation) @ (turns[b].to_matrix() @ R3(L)).to_4x4()

def lift_cape(pose, floor=0.01, given=None):
    """Last word: a chain bone whose panel ends up under the floor turns up about
    its head, top down, by the smallest step that clears it (or by the given
    angles). Returns the angle per bone."""
    out = {}
    for ns in CHAINS.values():
        for i, b in enumerate(ns):
            below = ns[i:]; m = np.array([o in below for o in OWN])
            P = skinned(CLOAK_TAB, pose)[m]; k = int(P[:, 2].argmin())
            want = given.get(b, 0) if given else None
            if want == 0 or (want is None and P[k, 2] >= floor): continue
            h = pose[b].translation.copy(); axis = (Vector(P[k]) - h).cross(Vector((0, 0, 1)))
            if axis.length < 1e-6: continue
            keep = {o: pose[o] for o in below}
            def turn_to(deg):
                R = Matrix.Translation(h) @ Matrix.Rotation(math.radians(deg), 4, axis.normalized()) @ Matrix.Translation(-h)
                for o in below: pose[o] = R @ keep[o]
            if want is None:
                best = max(((cape_low(turn_to(d) or pose, below), d) for d in range(3, 91, 3)), key=lambda t: (t[0] >= floor, -t[1] if t[0] >= floor else t[0]))
                want = best[1]
            turn_to(want); out[b] = want
    return out

# Where each cape strip falls: like a string from its anchor, over her back,
# seat, thighs and tail (whatever lies behind the anchor in the upright slice
# through it), then straight down from the hindmost point and along the floor.
DRAPE_BONES = ({NB[f'mixamorig:{n}'] for n in ('Hips', 'Spine', 'Spine1', 'Spine2', 'LeftUpLeg', 'RightUpLeg', 'LeftLeg', 'RightLeg')}
               | {NB[t] for t in TAIL})
DRAPE_ROWS = np.array([k[0] in DRAPE_BONES for k in BODY_TAB[2]])
DRAPE_GAP, DRAPE_SLICE = 0.03, 0.1
_ring = np.array([(math.cos(a), math.sin(a)) for a in np.linspace(0, 2 * math.pi, 8, endpoint=False)]) * DRAPE_GAP
def drape_goal(BP, A, yaw, lengths):
    r = Vector((-math.sin(yaw), math.cos(yaw), 0)); l = Vector((math.cos(yaw), math.sin(yaw), 0))   # rearwards, sideways
    d = BP - np.array(A)
    m = np.abs(d @ np.array(l)) < DRAPE_SLICE
    P = np.stack([d[m] @ np.array(r), BP[m, 2]], 1)
    P = np.unique(np.round(P / 0.01), axis=0) * 0.01
    P = (P[:, None] + _ring[None]).reshape(-1, 2); P = P[P[:, 0] > 0.005]
    hull = [(0.0, A.z)]
    for h, z in P[np.lexsort((P[:, 1], P[:, 0]))]:
        while len(hull) > 1 and ((hull[-1][0] - hull[-2][0]) * (z - hull[-2][1]) - (hull[-1][1] - hull[-2][1]) * (h - hull[-2][0])) >= 0:
            hull.pop()
        hull.append((h, z))
    path = [Vector(q) for q in hull]
    if path[-1].y > 0.03: path.append(Vector((path[-1].x, 0.03)))
    path.append(path[-1] + Vector((5.0, 0)))   # then along the floor
    cum = [0.0]
    for p, q in zip(path, path[1:]): cum.append(cum[-1] + (q - p).length)
    out, s = [A.copy()], 0.0
    for L in lengths:
        s += L; k = next((j for j in range(len(path) - 1) if cum[j + 1] >= s), len(path) - 2)
        q = path[k].lerp(path[k + 1], (s - cum[k]) / max(cum[k + 1] - cum[k], 1e-9))
        out.append(Vector((A.x, A.y, 0)) + r * q.x + Vector((0, 0, q.y)))
    return out

def death_env(frames):
    return lambda fi: 1.0 - smooth((fi - 0.30 * frames) / (0.35 * frames))

def animate(name):
    stats = {}; src = SRC[name]; n = len(src)
    FACE_OK[:] = face_ok(CLEAR_BONES | CLEAR_MORE.get(name, set()))
    O, BS = (CREST, CBASE) if name == 'idle' else (OREST, BASE)
    poses = [body_pose(s, stats, O, BS) for s in src]
    env = death_env(n) if name == 'death' else None
    amp, cycles = WAG[name]; period = (n - 1) if LOOP[name] else n
    if name == 'idle':
        for fi, pose in enumerate(poses):
            life(pose, fi, period)
            for side in ('Left', 'Right'):
                stats[f'blade_twist_off_{side}'] = aim_blade(pose, side)
            for side in ('Left', 'Right'):   # the hand the crouch plants rests its fist and guard on the ground
                low = fist_low(pose, side)
                if side in PLANTED or low < 0.008: lift_fist(pose, side, 0.008 - low)
                stats[f'fist_move_{side}'] = round(0.008 - low, 4)
    stats['fist_min'] = round(min(fist_low(p, s) for p in poses for s in ('Left', 'Right')), 4)
    # Tail
    goals = []; lengths = [B[t].length for t in TAIL]
    for fi, pose in enumerate(poses):
        D = pose['mixamorig:Hips'] @ REST['mixamorig:Hips'].inverted()
        G = [D @ p for p in REST_TAIL]; up = R3(D) @ Vector((0, 0, 1))
        if name in TAIL_LINE:
            turn, pitches = TAIL_LINE[name]
            back = R3(D) @ (REST_TAIL[-1] - REST_TAIL[0])
            back = Matrix.Rotation(math.radians(-turn), 3, 'Z') @ Vector((back.x, back.y, 0)).normalized()
            for i, deg in enumerate(pitches):
                a = math.radians(deg)
                G[i + 1] = G[i] + (back * math.cos(a) + Vector((0, 0, math.sin(a)))) * lengths[i]
        out = [G[0]]
        for i in range(6):
            w = (0.25, 0.45, 0.65, 0.85, 1.0, 1.0)[i]
            a = math.radians(amp) * w * math.sin(2 * math.pi * cycles * fi / period - 0.55 * i)
            out.append(out[-1] + Matrix.Rotation(a, 3, up) @ (G[i + 1] - G[i]))
        goals.append(out)
    rest_dirs = [(REST_TAIL[i + 1] - REST_TAIL[i]).normalized() for i in range(6)]
    def tail_collide(fi, X):
        for (a, b), row in zip((bone_seg(poses[fi], c) for c in tail_cols), TAIL_CAP):
            for i in range(1, 7):
                if row[i] <= 0: continue
                q = seg_closest(X[i], a, b); e = X[i] - q
                if e.length < row[i]: X[i] = q + (e.normalized() if e.length > 1e-6 else Vector((0, 1, 0))) * row[i]
        if name in TAIL_BEND_MAX:
            top = math.radians(TAIL_BEND_MAX[name])
            D = R3(poses[fi]['mixamorig:Hips'] @ REST['mixamorig:Hips'].inverted())
            for i in range(1, 7):
                rest = D @ rest_dirs[i - 1]
                if i > 1: rest = (D @ rest_dirs[i - 2]).rotation_difference(X[i - 1] - X[i - 2]).to_matrix() @ rest
                d = X[i] - X[i - 1]
                if d.length > 1e-6 and rest.angle(d) > top:
                    axis = rest.cross(d)
                    if axis.length < 1e-6: axis = rest.orthogonal()
                    X[i] = X[i - 1] + Matrix.Rotation(top, 3, axis.normalized()) @ rest * d.length
    floor = TAIL_FLOOR
    if name in TAIL_LINE:
        floor = [min(TAIL_FLOOR[i], min(g[i].z for g in goals) - 0.03) for i in range(7)]
    tail_pts, stats['tail_seam_m'] = simulate(goals, lengths, TAIL_K, 0.06, 0.25 if name != 'death' else 1.0,
                                              tail_collide, floor, LOOP[name], env)
    if name in TAIL_SMOOTH:
        smooth_chain(tail_pts, poses, TAIL_SMOOTH[name], LOOP[name], bone='mixamorig:Hips')
        for pts in tail_pts:
            for i in range(1, 7):
                pts[i] = pts[i - 1] + (pts[i] - pts[i - 1]).normalized() * lengths[i - 1]
                pts[i].z = max(pts[i].z, floor[i])
    for pose, pts in zip(poses, tail_pts): aim(pose, TAIL, pts)
    if name in ROLL_SMOOTH:
        stats['tail_roll_fix_deg'] = steady_roll(poses, TAIL, LOOP[name], ROLL_SMOOTH[name])
    # Cloak
    stats['cloak_seam_m'] = 0.0
    BPs = [skinned(BODY_TAB, pose)[DRAPE_ROWS] for pose in poses]
    yaws = [yaw_of(pose['mixamorig:Spine2'], REST['mixamorig:Spine2']) for pose in poses]
    for fi in range(len(yaws)):   # lying down she has no heading: keep the last one
        if yaws[fi] is None: yaws[fi] = next((y for y in yaws[fi::-1] if y is not None), next((y for y in yaws if y is not None), 0.0))
    for c, names in CHAINS.items():
        goals = []
        lengths = [B[b].length for b in names]
        for fi, pose in enumerate(poses):
            D = pose['mixamorig:Spine2'] @ REST['mixamorig:Spine2'].inverted()
            goals.append(drape_goal(BPs[fi], D @ REST_CLOAK[c][0], yaws[fi], lengths))
        smooth_chain(goals, poses, SMOOTH[name][0], LOOP[name], SMOOTH[name][2])
        def cloak_collide(fi, X, c=c):
            segs = [bone_seg(poses[fi], b) for b in cloak_body] + [(tail_pts[fi][i], tail_pts[fi][i + 1]) for i in range(6)]
            backs = {n: R3(poses[fi][n]) @ R3(REST[n]).inverted() @ Vector((0, 1, 0)) for n in ('mixamorig:Hips', 'mixamorig:Spine1')}
            for k, ((a, b), row) in enumerate(zip(segs, CLOAK_CAP[c])):
                n = cloak_body[k] if k < len(cloak_body) else 'tail'
                if n == 'tail': row = [r + CAPE_TAIL_GAP.get(name, 0.0) for r in row]
                behind = n in BEHIND
                back = backs['mixamorig:Spine1' if n in ('mixamorig:Spine', 'mixamorig:Spine1') else 'mixamorig:Hips']
                for i in range(1, 4):
                    if row[i] <= 0: continue
                    q = seg_closest(X[i], a, b); e = X[i] - q
                    if e.length >= row[i]: continue
                    if not behind:
                        X[i] = q + (e.normalized() if e.length > 1e-6 else Vector((0, 1, 0))) * row[i]; continue
                    # The cape leaves her trunk, thighs and tail on the side of her back,
                    # never through her chest, between her legs or under the tail.
                    ax = (b - a).normalized(); up = back - ax * back.dot(ax)
                    if up.length < 0.3: up = Vector((0, 0, 1)) - ax * ax.z
                    up.normalize(); side = ax.cross(up); es = e.dot(side)
                    X[i] = q + side * es + up * math.sqrt(max(row[i] ** 2 - es ** 2, 0.0))
        pts, seam = simulate(goals, lengths, CLOAK_K, 0.08, 1.0, cloak_collide, [0, 0.03, 0.03, 0.03], LOOP[name],
                             (lambda fi: 0.35 + 0.65 * env(fi)) if env else None)
        stats['cloak_seam_m'] = max(stats['cloak_seam_m'], seam)
        if SMOOTH[name][1]:
            smooth_chain(pts, poses, SMOOTH[name][1], LOOP[name], SMOOTH[name][3])
            for ps in pts:
                for p in ps[1:]: p.z = max(p.z, 0.03)
        # Floor twists, smoothed over time, then the chain is aimed again with them.
        tw = [aim({**pose}, names, p, 'find') for pose, p in zip(poses, pts)]
        for _ in range(4):
            tw = [[0.25 * tw[(f - 1) % len(tw) if LOOP[name] else max(f - 1, 0)][i] + 0.5 * tw[f][i]
                   + 0.25 * tw[(f + 1) % len(tw) if LOOP[name] else min(f + 1, len(tw) - 1)][i] for i in range(3)]
                  for f in range(len(tw))]
        stats['cloak_twist_max_deg'] = max(stats.get('cloak_twist_max_deg', 0), round(max(abs(math.degrees(a)) for t in tw for a in t), 1))
        for pose, p, t in zip(poses, pts, tw): aim(pose, names, p, t)
    pen, turns = [(0, 0, 0)], []
    if os.environ.get('CAPE_CLEAR', '1') == '1':   # found on copies, then eased over neighbouring frames
        pen = []
        for pose in poses:
            trial = dict(pose); L0 = chain_local(pose); pen.append(clear_cape(trial)); L1 = chain_local(trial)
            turns.append({b: (L1[b] @ L0[b].transposed()).to_quaternion() for b in CHAIN_OF})
        if name in STEADY_CLEAR:
            most = {b: max((t[b] for t in turns), key=lambda q: q.angle) for b in CHAIN_OF}
            turns = [dict(most) for _ in turns]
        for pose, t in zip(poses, eased_turns(turns, LOOP[name])): turn_chains(pose, t)
        for pose in poses:   # easing can leave a fast frame short of its own turn: finish it there
            if pen_depth(pose) > 0.02: clear_cape(pose)
    left = [pen_depth(pose) for pose in poses]
    stats['cape_into_body_mm'] = [round(max(a for a, _, _ in pen) * 1000, 1), round(max(left) * 1000, 1)]
    stats['cape_into_body_worst_frame'] = 1 + max(range(len(left)), key=lambda f: left[f])
    stats['cape_clear_turn_deg'] = round(math.degrees(max(t for _, _, t in pen)), 1)
    # Found on copies, then eased in and out over neighbouring frames.
    need = [lift_cape(dict(pose)) for pose in poses]
    F = len(poses); wrap = LOOP[name]
    def at(f): return need[f % F] if wrap else (need[f] if 0 <= f < F else {})
    lift = [{b: max(round(w * at(f + o).get(b, 0)) for o, w in ((0, 1), (-1, 0.7), (1, 0.7), (-2, 0.4), (2, 0.4))) for b in CHAIN_OF}
            for f in range(F)]
    for pose, l in zip(poses, lift): lift_cape(pose, given=l)
    stats['cape_floor_lift_deg'] = {f + 1: max(l.values()) for f, l in enumerate(lift) if max(l.values())}
    return poses, stats

def write_action(name, poses):
    a = bpy.data.actions.new(name); a.use_fake_user = True; bind(rig, a)
    nf = len(poses)
    for n in ORDER:
        pb = P[n]; pb.rotation_mode = 'QUATERNION'; par = PAR[n]
        locs, quats, prev = [], [], None
        for pose in poses:
            basis = REL[n].inverted() @ (pose[par].inverted() if par else Matrix()) @ pose[n]
            q = basis.to_quaternion()
            if prev is not None: q.make_compatible(prev)
            prev = q; quats.append(q)
            locs.append(basis.to_translation() if n == 'mixamorig:Hips' else Vector())
        for path, vals, size in (('location', locs, 3), ('rotation_quaternion', quats, 4)):
            for i in range(size):
                fc = a.fcurve_ensure_for_datablock(rig, f'pose.bones["{n}"].{path}', index=i, group_name=n)
                fc.keyframe_points.add(nf)
                fc.keyframe_points.foreach_set('co', [c for f, v in enumerate(vals) for c in (f + 1, v[i])])
                fc.keyframe_points.foreach_set('interpolation', [1] * nf)   # linear
                fc.update()
    props = PROPS[name] if name != 'idle' else {
        'source': 'Crouching - Wolf scout.fbx (held)', 'root_motion': False,
        'secondary_motion': 'Breathing, a slow look around and ear flicks; Verlet tail and five-panel cloak.'}
    for k, v in props.items(): a[k] = v
    a['frames'] = nf; a['fps'] = FPS; a['loop'] = LOOP[name]
    a.use_frame_range = True; a.frame_start = 1; a.frame_end = nf; a.use_cyclic = LOOP[name]
    return a

report = {}; actions = {}
for name in CLIPS:
    poses, stats = animate(name)
    actions[name] = write_action(name, poses)
    report[name] = {'frames': len(poses), **{k: (round(v, 5) if isinstance(v, float) else v) for k, v in stats.items()}}
    print('CLIP', name, json.dumps(report[name]), flush=True)

ad = rig.animation_data
for tr in list(ad.nla_tracks): ad.nla_tracks.remove(tr)
for name, a in actions.items():
    tr = ad.nla_tracks.new(); tr.name = name
    st = tr.strips.new(name, 1, a); st.extrapolation = 'NOTHING'; tr.mute = True
bind(rig, actions['idle'])
for pb in P: pb.matrix_basis = Matrix()
sc.render.fps = FPS; sc.frame_start = 1; sc.frame_end = len(SRC['idle']); sc.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(ART / 'wolf_scout_3.blend'), relative_remap=True)
REVIEW.mkdir(parents=True, exist_ok=True)
(REVIEW / 'animation.json').write_text(json.dumps({'source_motion': 'wolf_scout_2.blend', 'rig': 'wolf_scout_3_rig.blend',
    'grip': 'reverse, blades back', 'clips': report}, indent=2))
print('SAVED', ART / 'wolf_scout_3.blend', flush=True)
