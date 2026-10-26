"""The Sovereign Kiss's fog heart, a study for review (background Blender; runs again cleanly).

  blender -b <kiss blend> --python kiss_heart.py -- [target distance (m)]

Run on the kiss blend (README, Sovereign Kiss) after kiss_motion.py: builds the SK_FogHeart
collection, keyed from sovereign_kiss's kiss_release, and saves. render_kiss_heart.py
renders it from the game's camera.

The look follows the user's reference (26 October 2026: a pink charm heart in a League of
Legends clip at 5:06): a clear pink heart that starts small at her lips, grows as it flies,
passes through the target and dissolves beyond it. The approved pink fog
(workspace/2026-10-20_meridius/sovereign-kiss/blender-handoff-fog.md) is in its churning
edge, its wake and the dissolve.

- SK_Heart, an empty, is the projectile: it forms at KissSocket's tail over FORM frames,
  leaves at the release and flies straight to the target's chest (CHEST, TARGET_D ahead),
  then on beyond it, slowing, while it dissolves (DISSOLVE). Its scale is the heart's width
  (W_*). It carries SLICES camera-facing cards a few centimetres apart in depth, so it has
  some thickness when it passes through the target.
- SK_Puff_*: the breath at her lips, the wake behind the heart and the wisps it sheds as it
  dissolves; world-space cards that grow and fade on their own.
- SK_ContactVeil: a pink wash over the target's chest as the heart passes through it;
  SK_EnthrallMark: a small heart over its head that fades in after and pulses.
- Every card faces the camera (SK_Camera) and reads its density, erosion and noise seed
  from its object colour (R, G, B), keyed per frame, so one material per texture serves all.
  The textures hold a signed distance in R (0.5 at the edge, rising inwards; the highlight
  in G); they are generated here and packed. The shader thresholds distance plus noise, so
  erosion eats the shape from its edge inwards and opens holes.
- SK_Target: an empty at the target's feet; render_kiss_heart.py puts a stand-in there.
The collection's "timing" property holds the frames and seconds for the game handoff.
"""
import json
import math
import random
import sys

import bpy
import numpy as np
from mathutils import Vector

CLIP = "sovereign_kiss"
FPS = 30
TARGET_D = 5.0                 # the target's feet, straight ahead of her (m; a tile is 2.72 m)
CHEST = 1.2                    # the height it passes through the target at (m)
SPEED = 10.0                   # m/s once launched
LAUNCH = (4.0, 0.12)           # m/s as it leaves her lips, and the time to reach SPEED (s)
FORM = 3                       # frames before the release in which it forms at her lips
W_FORM, W_RELEASE, W_HIT, W_END = 0.06, 0.25, 1.2, 1.8    # its width (m)
DISSOLVE = 0.5                 # s from its middle crossing the target to gone
END_SPEED = 1.5                # m/s at the end of the dissolve
ERODE_FROM = 0.12              # fraction of DISSOLVE before it erodes (its back has passed)
SLICES = {-2: 0.35, -1: 0.45, 0: 0.55, 1: 0.45, 2: 0.35}  # depth step: density
SLICE_GAP = 0.07               # depth step, of its width
PAD = 1.45                     # card / heart width (room for the halo)
MARK = (2.15, 0.34)            # the enthrall mark: height over the target's feet, width (m)
# palette (blender-handoff-fog.md)
PINK = {"raspberry": "C82777", "rose": "F44C9D", "main": "FF82C2", "blush": "FFC0DF",
        "pale": "FFE3F1", "plum": "2B1738"}

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if argv and argv[0]:
    TARGET_D = float(argv[0])
sc = bpy.context.scene
rig = bpy.data.objects["SuccubusRig"]
act = bpy.data.actions[CLIP]
release = next(m.frame for m in act.pose_markers if m.name == "kiss_release")
rnd = random.Random(7)


def lin(hex_):
    """sRGB hex to linear RGBA."""
    c = [int(hex_[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c) + (1.0,)


def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


# --- textures: signed distance in R (0.5 at the edge), the highlight in G ---------------
RES = 512


def sdf_image(name, outline, highlight=None):
    """outline: closed polygon in texture units (0..1); distance mapped so that a feature
    half a heart wide inside reads 1."""
    img = bpy.data.images.get(name)
    if img is not None:
        bpy.data.images.remove(img)
    poly = np.asarray(outline)
    a, b = poly, np.roll(poly, -1, axis=0)
    ab = b - a
    ab2 = (ab ** 2).sum(1)
    xs = (np.arange(RES) + 0.5) / RES
    out = np.zeros((RES, RES, 4), np.float32)
    span = poly[:, 0].max() - poly[:, 0].min()
    for r0 in range(0, RES, 16):
        P = np.stack(np.meshgrid(xs, xs[r0:r0 + 16]), -1).reshape(-1, 1, 2)
        t = np.clip(((P - a) * ab).sum(2) / ab2, 0, 1)
        d = np.sqrt((((a + t[..., None] * ab) - P) ** 2).sum(2)).min(1)
        # inside: even-odd crossings of a ray to +x
        y, x = P[:, 0, 1:2], P[:, 0, 0:1]
        cross = ((a[:, 1] > y) != (b[:, 1] > y)) & (x < a[:, 0] + (y - a[:, 1]) * ab[:, 0] / np.where(ab[:, 1] == 0, 1e-9, ab[:, 1]))
        inside = cross.sum(1) % 2 == 1
        sd = np.where(inside, -d, d)
        out[r0:r0 + 16, :, 0] = np.clip(0.5 - sd / span, 0, 1).reshape(-1, RES)
        if highlight is not None:
            (hx, hy), hs = highlight
            g = np.exp(-(((x - hx) ** 2 + (y - hy) ** 2) / (2 * hs * hs)))[:, 0]
            out[r0:r0 + 16, :, 1] = (g * inside).reshape(-1, RES)
    out[..., 3] = 1.0
    img = bpy.data.images.new(name, RES, RES, alpha=True)
    img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(out.ravel())
    img.pack()
    return img


def heart_outline(n=360):
    t = np.linspace(0, 2 * math.pi, n, endpoint=False)
    x = 16 * np.sin(t) ** 3
    y = 13 * np.cos(t) - 5 * np.cos(2 * t) - 2 * np.cos(3 * t) - np.cos(4 * t)
    x, y = x - (x.max() + x.min()) / 2, y - (y.max() + y.min()) / 2
    s = 1 / (PAD * (x.max() - x.min()))
    # the highlight: on the upper left lobe, about a fifth of the width across
    return np.stack([0.5 + x * s, 0.5 + y * s], 1), ((0.5 + 0.45 * x.min() * s, 0.5 + 0.5 * y.max() * s), 3.2 * s)


def puff_outline(n=240):
    t = np.linspace(0, 2 * math.pi, n, endpoint=False)
    r = 0.33 * (1 + 0.08 * np.sin(5 * t + 1) + 0.05 * np.sin(9 * t + 2))
    return np.stack([0.5 + r * np.cos(t), 0.5 + r * np.sin(t)], 1)


heart_img = sdf_image("SK_HeartSDF", *heart_outline())
puff_img = sdf_image("SK_PuffSDF", puff_outline())


# --- the material ----------------------------------------------------------------------
def fog_material(name, img, bands, depth, shade_bottom, edge=(0.025, 0.035), halo_k=0.5):
    """bands: (position, colour) inwards from the edge over `depth` of distance (cel steps);
    edge: the soft edge's width outside and inside; halo_k: the glow's strength outside it."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    m.surface_render_method = "BLENDED"
    nt = m.node_tree
    nt.nodes.clear()
    N, L = nt.nodes.new, nt.links.new

    def op(o, a, b=None, c=None):
        n = N("ShaderNodeMath")
        n.operation = o
        for i, v in enumerate((a, b, c)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = v
            else:
                L(v, n.inputs[i])
        return n.outputs[0]

    def ramp(v, lo, hi, smooth_=True):
        n = N("ShaderNodeMapRange")
        n.interpolation_type = "SMOOTHSTEP" if smooth_ else "LINEAR"
        L(v, n.inputs[0])
        for i, x in ((1, lo), (2, hi)):
            if isinstance(x, (int, float)):
                n.inputs[i].default_value = x
            else:
                L(x, n.inputs[i])
        return n.outputs[0]

    def mix(fac, a, b):
        n = N("ShaderNodeMix")
        n.data_type = "RGBA"
        ins = [s for s in n.inputs if s.type == "RGBA"]
        L(fac, n.inputs[0])
        for s, v in zip(ins, (a, b)):
            if isinstance(v, tuple):
                s.default_value = v
            else:
                L(v, s)
        return [s for s in n.outputs if s.type == "RGBA"][0]

    uv = N("ShaderNodeTexCoord").outputs["UV"]
    tex = N("ShaderNodeTexImage")
    tex.image, tex.extension, tex.interpolation = img, "CLIP", "Linear"
    L(uv, tex.inputs["Vector"])
    st = N("ShaderNodeSeparateColor")
    L(tex.outputs["Color"], st.inputs[0])
    s, hl = st.outputs[0], st.outputs[1]
    oc = N("ShaderNodeSeparateColor")
    L(N("ShaderNodeObjectInfo").outputs["Color"], oc.inputs[0])
    dens, ero, seed = oc.outputs[0], oc.outputs[1], oc.outputs[2]
    time = N("ShaderNodeValue")
    drv = time.outputs[0].driver_add("default_value").driver
    drv.type, drv.expression = "SCRIPTED", "frame / %d" % FPS
    noise = N("ShaderNodeTexNoise")
    noise.noise_dimensions = "4D"
    noise.inputs["Scale"].default_value = 3.5
    noise.inputs["Detail"].default_value = 3.0
    L(uv, noise.inputs["Vector"])
    L(op("MULTIPLY_ADD", seed, 10.0, op("MULTIPLY", time.outputs[0], 0.9)), noise.inputs["W"])
    amp = op("MULTIPLY_ADD", ero, 0.45, 0.07)
    f = op("ADD", s, op("MULTIPLY", op("MULTIPLY_ADD", noise.outputs["Fac"], 2.0, -1.0), amp))
    th = op("MULTIPLY_ADD", ero, 0.3, 0.5)
    body = ramp(f, op("SUBTRACT", th, edge[0]), op("ADD", th, edge[1]))
    halo = op("MULTIPLY", op("MULTIPLY", ramp(f, op("SUBTRACT", th, 0.12), th), op("SUBTRACT", 1.0, body)),
              op("MULTIPLY", op("SUBTRACT", 1.0, ero), halo_k))
    cr = N("ShaderNodeValToRGB")
    L(ramp(op("SUBTRACT", f, th), 0.0, depth, False), cr.inputs[0])
    els = cr.color_ramp.elements
    els[0].position, els[0].color = bands[0][0], lin(PINK[bands[0][1]])
    els[1].position, els[1].color = 1.0, lin(PINK[bands[-1][1]])
    for p_, c in bands[1:]:
        els.new(p_).color = lin(PINK[c])
    col = cr.outputs["Color"]
    if shade_bottom:      # plum-raspberry towards the point, the highlight on the upper left lobe
        sy = N("ShaderNodeSeparateXYZ")
        L(uv, sy.inputs[0])
        low = op("MULTIPLY", op("POWER", op("SUBTRACT", 1.0, sy.outputs["Y"]), 2.0), 0.45)
        col = mix(low, col, lin(PINK["raspberry"]))
        col = mix(op("MULTIPLY", op("MULTIPLY", hl, 0.85), op("SUBTRACT", 1.0, ero)), col, lin(PINK["pale"]))
    col = mix(body, lin(PINK["rose"]), col)
    alpha = op("MULTIPLY", op("ADD", body, halo), dens, None)
    em = N("ShaderNodeEmission")
    L(col, em.inputs["Color"])
    sh = N("ShaderNodeMixShader")
    L(op("MINIMUM", alpha, 1.0), sh.inputs[0])
    L(N("ShaderNodeBsdfTransparent").outputs[0], sh.inputs[1])
    L(em.outputs[0], sh.inputs[2])
    L(sh.outputs[0], N("ShaderNodeOutputMaterial").inputs["Surface"])
    return m


# the heart: a raspberry rim, rose, main pink, a blush core; the fog: rose to main pink
heart_mat = fog_material("SK_Heart", heart_img, ((0.0, "raspberry"), (0.06, "raspberry"), (0.12, "rose"),
                                                 (0.50, "rose"), (0.58, "main"), (0.84, "main"), (0.92, "blush")),
                         0.3, True)
puff_mat = fog_material("SK_Puff", puff_img, ((0.0, "rose"), (0.35, "rose"), (0.6, "main"), (0.95, "blush")),
                         0.7, False, (0.1, 0.18), 0.0)

# --- the collection, built afresh ----------------------------------------------------
coll = bpy.data.collections.get("SK_FogHeart")
if coll is not None:
    for o in list(coll.objects):
        bpy.data.objects.remove(o)
else:
    coll = bpy.data.collections.new("SK_FogHeart")
    sc.collection.children.link(coll)
card = bpy.data.meshes.get("SK_Card")
if card is None:
    card = bpy.data.meshes.new("SK_Card")
    card.from_pydata([(-0.5, -0.5, 0), (0.5, -0.5, 0), (0.5, 0.5, 0), (-0.5, 0.5, 0)], [], [(0, 1, 2, 3)])
    uvl = card.uv_layers.new(name="UVMap")
    for li, (u, v) in zip(range(4), ((0, 0), (1, 0), (1, 1), (0, 1))):
        uvl.data[li].uv = (u, v)
card.materials.clear()
card.materials.append(None)             # one slot, linked to each card's object
bpy.context.preferences.edit.keyframe_new_interpolation_type = "LINEAR"

cam = bpy.data.objects.get("SK_Camera")
if cam is None:
    cam = bpy.data.objects.new("SK_Camera", bpy.data.cameras.new("SK_Camera"))
    cam.data.type = "ORTHO"
    sc.collection.objects.link(cam)
sc.camera = cam


def new(name, mat=None, parent=None, empty=False):
    o = bpy.data.objects.new(name, None if empty else card)
    coll.objects.link(o)
    if not empty:
        o.material_slots[0].link = "OBJECT"
        o.material_slots[0].material = mat
        o.visible_shadow = False
    if parent is None:
        c = o.constraints.new("COPY_ROTATION")
        c.target = cam
    else:
        o.parent = parent
    return o


def key(o, f, loc=None, scale=None, color=None):
    if loc is not None:
        o.location = loc
        o.keyframe_insert("location", frame=f)
    if scale is not None:
        o.scale = (scale, scale, scale)
        o.keyframe_insert("scale", frame=f)
    if color is not None:
        o.color = color
        o.keyframe_insert("color", frame=f)


def life(o, f0, f1):
    """Rendered from f0 to f1."""
    for f, h in ((f0 - 1, True), (f0, False), (f1 + 1, True)):
        o.hide_render = o.hide_viewport = h
        o.keyframe_insert("hide_render", frame=f)
        o.keyframe_insert("hide_viewport", frame=f)


# --- the heart's flight -------------------------------------------------------------
rig.animation_data.action = act
socket = {}
for f in range(release - 6, release + 4):
    sc.frame_set(f)
    pb = rig.pose.bones["KissSocket"]
    socket[f] = (rig.matrix_world @ pb.head, rig.matrix_world @ pb.tail)
P0 = socket[release][1]
target = Vector((0.0, -TARGET_D, 0.0))
C = Vector((0.0, -TARGET_D, CHEST))
L1 = (C - P0).length
fwd = (C - P0).normalized()
flat = Vector((fwd.x, fwd.y, 0)).normalized()

track = {}     # frame: (position, width, density, erosion, direction, phase)
for f in range(release - FORM, release):
    k = (f - (release - FORM)) / FORM
    track[f] = (socket[f][1].copy(), W_FORM + (W_RELEASE - W_FORM) * k, k, 0.0, fwd, "form")
dist, t, t_hit, f, sub = 0.0, 0.0, None, release, 8
while True:
    if t_hit is None:
        p = dist / L1
        track[f] = (P0 + (C - P0) * p, W_RELEASE + (W_HIT - W_RELEASE) * (1 - (1 - p) ** 1.5),
                    1 - 0.08 * p, 0.0, fwd, "flight")
    else:
        q = (t - t_hit) / DISSOLVE
        if q > 1:
            break
        pos = C + flat * (dist - L1) + Vector((0, 0, 0.18 * q * q))
        track[f] = (pos, W_HIT + (W_END - W_HIT) * (1 - (1 - q) ** 2), 0.92 * (1 - smooth(ERODE_FROM + 0.1, 1, q)),
                    smooth(ERODE_FROM, 0.95, q), flat, "dissolve")
    for _ in range(sub):
        dt = 1 / (FPS * sub)
        if t_hit is None:
            v = LAUNCH[0] + (SPEED - LAUNCH[0]) * smooth(0, LAUNCH[1], t)
        else:
            v = SPEED + (END_SPEED - SPEED) * min(1.0, (t - t_hit) / DISSOLVE)
        dist += v * dt
        t += dt
        if t_hit is None and dist >= L1:
            t_hit = t
            f_hit = release + t_hit * FPS
    f += 1
f_last = f - 1
hit = int(round(f_hit))

heart = new("SK_Heart", empty=True)
heart.empty_display_type, heart.empty_display_size = "PLAIN_AXES", 0.5
slices = {}
for k, w in SLICES.items():
    o = new("SK_HeartSlice_%+d" % k, heart_mat, heart)
    o.location = (0, 0, k * SLICE_GAP)
    o.scale = (PAD * math.sqrt(1 - (k / 2.8) ** 2),) * 3
    slices[k] = (o, w, rnd.random())
for f, (pos, w, d, e, _, _) in track.items():
    key(heart, f, loc=pos, scale=w)
    for o, wt, seed in slices.values():
        key(o, f, color=(d * wt, e, seed, 1.0))
for o in [heart] + [s[0] for s in slices.values()]:
    life(o, release - FORM + 1, f_last)

# --- puffs -----------------------------------------------------------------------------
puffs = []


def puff(f0, n, pos, vel, size, dens, ero=(0.1, 0.6)):
    puffs.append((f0, n, pos.copy(), vel.copy(), size, dens, ero, rnd.random()))


def jitter(r):
    while True:
        v = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1)))
        if v.length <= 1:
            return v * r


up = Vector((0, 0, 1))
for f in range(release - 5, release):          # the breath gathering at her lips
    h, tl = socket[f]
    puff(f, 6, h + (tl - h) * 0.3, (tl - h).normalized() * 0.3 + up * 0.1, (0.05, 0.11), 0.3)
for f in range(release, release + 3):          # the breath bridge to the leaving heart
    h = socket[f][0]
    for _ in range(2):
        puff(f, 6, h + (track[f][0] - h) * rnd.uniform(0.2, 0.9), up * 0.15, (0.09, 0.16), 0.35)
WAKE_SUB = 3                                   # wake puffs per frame, along the frame's travel
for f, (pos, w, d, e, dirn, ph) in track.items():
    if f - 1 in track and (ph == "flight" or (ph == "dissolve" and f <= hit + 4)):
        # the wake: a tapering streak from the heart's point back along its path
        prev = track[f - 1][0]
        for i in range(WAKE_SUB):
            at = prev + (pos - prev) * ((i + 1) / WAKE_SUB) - dirn * 0.3 * w - up * 0.15 * w
            puff(f, 7, at + jitter(0.06 * w), -dirn * 0.6 + up * 0.15 + jitter(0.15),
                 (0.55 * w, 0.2 * w), 0.5 * d, (0.1, 0.5))
    if ph == "dissolve" and e > 0.02:          # the wisps it sheds
        for _ in range(2):
            j = jitter(0.4 * w)
            puff(f, 14, pos + j, j * 1.2 + dirn * 1.2 + up * 0.35, (0.35 * w, 0.7 * w), 0.32 * min(1.0, 3 * e),
                 (0.3, 0.9))
f_end = f_last
for i, (f0, n, pos, vel, (s0, s1), dens, (e0, e1), seed) in enumerate(puffs):
    o = new("SK_Puff_%03d" % i, puff_mat)
    for a in range(n + 1):
        u = a / n
        key(o, f0 + a, loc=pos + vel * (a / FPS), scale=s0 + (s1 - s0) * (1 - (1 - u) ** 2),
            color=(dens * smooth(0, 0.15, u) * (1 - smooth(0.35, 1, u)), e0 + (e1 - e0) * u, seed, 1.0))
    life(o, f0, f0 + n)
    f_end = max(f_end, f0 + n)

# --- on the target ----------------------------------------------------------------------
tgt = new("SK_Target", empty=True)
tgt.constraints.clear()
tgt.location = target
tgt.empty_display_type, tgt.empty_display_size = "SINGLE_ARROW", 0.6
tgt.rotation_euler = (0, 0, math.pi)          # facing her
veil_at = new("SK_ContactVeilPivot", empty=True)       # faces the camera; the veil 0.45 m nearer it
veil_at.location = C
veil = new("SK_ContactVeil", puff_mat, veil_at)
veil.location = (0, 0, 0.45)
for f, d, s, e in ((hit - 1, 0.0, 1.0, 0.2), (hit, 0.55, 1.15, 0.25), (hit + 1, 0.5, 1.25, 0.3),
                   (hit + 6, 0.0, 1.5, 0.7)):
    key(veil, f, scale=s, color=(d, e, 0.37, 1.0))
life(veil, hit - 1, hit + 6)
f_end = max(f_end, hit + 30)
mark = new("SK_EnthrallMark", heart_mat)
for f in range(hit + 3, f_end + 1):
    a = (f - hit - 3) / FPS
    key(mark, f, loc=target + up * MARK[0], scale=PAD * MARK[1] * (1 + 0.06 * math.sin(2 * math.pi * 1.2 * a)),
        color=(0.85 * smooth(0, 0.2, a), 0.0, 0.61, 1.0))
life(mark, hit + 3, f_end)

timing = {"release_frame": release, "form_frames": FORM, "contact_frame": round(f_hit, 2),
          "contact_s": round((f_hit - release) / FPS, 3), "dissolve_s": DISSOLVE, "gone_frame": f_last,
          "last_wisp_frame": f_end, "target_distance_m": TARGET_D, "speed_mps": SPEED,
          "width_m": {"release": W_RELEASE, "contact": W_HIT, "end": W_END}, "fps": FPS}
coll["timing"] = json.dumps(timing)
sc.frame_start, sc.frame_end = 1, f_end
rig.animation_data.action = act
sc.frame_set(release)
bpy.ops.wm.save_mainfile(compress=True)
print("KISS_HEART release %d, contact %.1f (%.2f s after), dissolved by %d, last wisp %d; %d puffs; "
      "%.2f m to the target's chest" % (release, f_hit, (f_hit - release) / FPS, f_last, f_end, len(puffs), L1))
print("KISS_HEART_SAVED", bpy.data.filepath)
