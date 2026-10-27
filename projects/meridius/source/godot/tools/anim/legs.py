"""Leg transplants for the footman walk.

The generated walk keys (art/sprites/footman_anim in ../game) lead with the
same leg in both steps, so the walk limps, and their upper bodies differ
from the idle pose (a sword can jump between keys). Every walk key is
therefore built on one step frame's upper body, and only the legs change:
the step's own legs (contact), the idle legs (passing), or the step's legs
mirrored about their middle (the other foot forward).

Legs are boots plus the trousers just above them, with their outline, found
by growing from the boots. All pixels come from the frames themselves.
Frames are RGBA numpy arrays on one canvas, anchored at the same feet point.
"""
import numpy as np
from scipy import ndimage

# Trouser rows above the boot tops that move with the boots (source px).
KNEE = 13
# Widest gap in the cloak lining (source px) that counts as hidden lining.
GAP = 12


def hls(rgb):
    """Hue, lightness, saturation (0..1) of an H x W x 3 uint8 array."""
    c = rgb.astype(np.float32) / 255.0
    mx = c.max(axis=2)
    mn = c.min(axis=2)
    l = (mx + mn) / 2
    d = mx - mn
    s = np.where(d == 0, 0, np.where(l <= 0.5, d / np.maximum(mx + mn, 1e-6), d / np.maximum(2 - mx - mn, 1e-6)))
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    dd = np.maximum(d, 1e-6)
    h = np.where(mx == r, (g - b) / dd, np.where(mx == g, 2 + (b - r) / dd, 4 + (r - g) / dd))
    h = np.where(d == 0, 0, (h / 6) % 1.0)
    return h, l, s


def classes(img):
    h, l, s = hls(img[..., :3])
    opaque = img[..., 3] > 128
    brown = opaque & ((h >= 0.93) | (h <= 0.11)) & (s >= 0.15) & (l >= 0.08) & (l <= 0.45)
    blue = opaque & (h >= 0.55) & (h <= 0.69) & (s >= 0.35) & (l >= 0.2) & (l <= 0.52)
    lining = opaque & (h >= 0.6) & (h <= 0.73) & (s >= 0.33) & (l < 0.2)
    dark = opaque & (l < 0.27) & ~lining
    cream = opaque & (l > 0.55) & (h > 0.04) & (h < 0.17) & (s > 0.2)
    return {"opaque": opaque, "brown": brown, "blue": blue, "lining": lining, "dark": dark, "cream": cream}


def _dilate4(m):
    n = m.copy()
    n[1:] |= m[:-1]
    n[:-1] |= m[1:]
    n[:, 1:] |= m[:, :-1]
    n[:, :-1] |= m[:, 1:]
    return n


def _grow(seed, allowed):
    m = seed & allowed
    while True:
        n = _dilate4(m) & allowed
        if (n == m).all():
            return m
        m = n


def leg_mask(img, ax, ay, back):
    """(mask, top): the legs, and the row above which nothing is touched."""
    k = classes(img)
    H, W = k["opaque"].shape
    ys = np.arange(H)[:, None] * np.ones((1, W), dtype=int)
    xs = np.ones((H, 1), dtype=int) * np.arange(W)[None, :]
    ay = int(round(ay))
    # Boots: brown near the ground. Gloves, belts and the sword grip sit higher.
    seed = k["brown"] & (ys > ay - 46)
    if not seed.any():
        return np.zeros_like(seed), ay
    bx = xs[seed]
    x0, x1 = bx.min() - 4, bx.max() + 4
    if back:
        # From behind, the cloak hangs to the calves: only what shows below its hem.
        top = ay - 40
        allowed = (k["brown"] | k["dark"] | (k["blue"] & (ys > ay - 30))) & (ys > top)
    else:
        # From the knee down: the thighs stay under the tunic as drawn, so
        # the hips keep their shape and only the stride changes.
        band = k["cream"] & (np.abs(xs - ax) < 30) & (ys > ay - 110)
        hem = ys[band].max() if band.any() else ay - 60
        top = max(hem, ys[seed].min() - KNEE, ay - 75)
        allowed = (k["brown"] | k["blue"] | k["dark"]) & (ys > top)
    allowed &= (xs >= x0) & (xs <= x1)
    m = _grow(seed, allowed)
    # The outline around boots and trousers is two pixels thick in places.
    edge = k["dark"] & (ys > top)
    m = m | (_dilate4(m) & edge)
    m = m | (_dilate4(m) & edge)
    return m, top


def lift(img, m, floor):
    """The frame without the masked legs. The cloak lining they hid is filled
    with its shadow colour where lining closes the gap on both sides within a
    short reach, above row `floor` (the boot tops); elsewhere, between the
    feet, the gap is open air."""
    k = classes(img)
    H, W = m.shape
    out = img.copy()
    out[m] = 0
    lining = k["lining"] & ~m
    shade = np.median(img[lining], axis=0).astype(np.uint8) if lining.any() else np.array([18, 17, 47, 255], np.uint8)
    ys, xs = np.nonzero(m)
    for y, x in zip(ys, xs):
        if y >= floor:
            continue
        left = right = None
        for d in range(1, GAP + 1):
            if left is None and x - d >= 0 and not m[y, x - d] and out[y, x - d, 3] > 128:
                left = x - d
            if right is None and x + d < W and not m[y, x + d] and out[y, x + d, 3] > 128:
                right = x + d
        if left is not None and right is not None and lining[y, left] and lining[y, right]:
            out[y, x] = shade
    return out


def put(base, top, src, m, mirror=False):
    """Paste the masked legs of `src` onto `base` (mirrored about their own
    middle if asked), then clean the leg zone below `top` of what old legs
    left on the cloth: hairline outline (pixels in no solid 2 x 2 block) and
    pieces cut off from the figure that are not the new legs."""
    H, W = m.shape
    out = base.copy()
    keep = np.zeros((H, W), dtype=bool)
    ys, xs = np.nonzero(m)
    if len(xs):
        nx = (xs.min() + xs.max()) - xs if mirror else xs
        ok = (nx >= 0) & (nx < W)
        out[ys[ok], nx[ok]] = src[ys[ok], xs[ok]]
        keep[ys[ok], nx[ok]] = True
    zone = np.zeros((H, W), dtype=bool)
    zone[top + 1:] = True
    a = out[..., 3] > 128
    solid = ndimage.binary_opening(a, structure=np.ones((2, 2)))
    out[a & zone & ~solid & ~keep] = 0
    a = out[..., 3] > 128
    lab, n = ndimage.label(a, structure=np.ones((3, 3)))
    if n > 1:
        sizes = ndimage.sum(a, lab, range(1, n + 1))
        for i, size in enumerate(sizes, start=1):
            part = lab == i
            if size < 400 and (part & zone).sum() >= size / 2 and not (part & keep).any():
                out[part] = 0
    return out


def walk_keys(step, idle, ax, ay, back):
    """(contact, passing, other contact), all on the step frame's upper body."""
    ms, top_s = leg_mask(step, ax, ay, back)
    mi, top_i = leg_mask(idle, ax, ay, back)
    top = min(top_s, top_i)
    boots = classes(step)["brown"] & ms
    floor = np.nonzero(boots.any(axis=1))[0].min() + 4 if boots.any() else int(ay)
    body = lift(step, ms | mi, floor)
    return put(body, top, step, ms), put(body, top, idle, mi), put(body, top, step, ms, mirror=True)


# ---------------------------------------------------------------- any unit

def leg_colours(figures, band=0.22, upper=0.5, ratio=1.5):
    """Colours (RGB tuples) that make the legs of a unit: common in the band just
    above the feet, rare in the upper body. `figures` are (rgba, ax, ay) of the
    standing frames, already on one shared palette."""
    low, high = {}, {}
    for im, ax, ay in figures:
        a = im[..., 3] > 128
        ys = np.nonzero(a.any(axis=1))[0]
        if not len(ys):
            continue
        top, bottom = ys[0], ys[-1]
        h = bottom - top + 1
        for y in range(top, bottom + 1):
            row = im[y][a[y]][:, :3]
            target = low if y >= bottom - band * h else (high if y <= top + upper * h else None)
            if target is None:
                continue
            for c in map(tuple, row):
                target[c] = target.get(c, 0) + 1
    nl, nh = max(1, sum(low.values())), max(1, sum(high.values()))
    return {c for c, n in low.items() if n / nl > 0.004 and (n / nl) > ratio * (high.get(c, 0) / nh)}


def colour_mask(img, cols):
    rgb = img[..., :3]
    m = np.zeros(img.shape[:2], dtype=bool)
    for c in cols:
        m |= (rgb[..., 0] == c[0]) & (rgb[..., 1] == c[1]) & (rgb[..., 2] == c[2])
    return m & (img[..., 3] > 128)


def leg_mask_any(img, ax, ay, cols, band=0.26):
    """(mask, top) of the legs of any figure: leg-coloured pixels grown up from
    the ground through leg colours and dark outline, inside the band above the feet."""
    k = classes(img)
    a = k["opaque"]
    ys_all = np.nonzero(a.any(axis=1))[0]
    if not len(ys_all):
        return np.zeros_like(a), int(ay)
    bottom = int(ys_all[-1])
    h = bottom - int(ys_all[0]) + 1
    top = int(bottom - band * h)
    H, W = a.shape
    ys = np.arange(H)[:, None] * np.ones((1, W), dtype=int)
    legc = colour_mask(img, cols)
    xs = np.ones((H, 1), dtype=int) * np.arange(W)[None, :]
    # Legs stand under the body: seeds only within the torso's width around the
    # feet, so a spear head or blade held low at the side is not taken for a boot.
    chest = np.nonzero(a[int(bottom - 0.55 * h)])[0]
    half = 0.45 * (chest.max() - chest.min() + 1) if len(chest) else W
    # The lowest fifth: boots, including a back foot lifted off the ground, but no hems.
    seed = legc & (ys > bottom - 0.2 * h) & (np.abs(xs - ax) < half)
    if not seed.any():
        return np.zeros_like(a), top
    bx = xs[seed]
    allowed = (legc | k["dark"]) & (ys > top) & (xs >= bx.min() - 4) & (xs <= bx.max() + 4)
    m = _grow(seed, allowed)
    # Shading inside the boots that is not a leg colour belongs to them too.
    m = ndimage.binary_fill_holes(m)
    # Thin parts (a spear butt or a shaft beside the boots) are not legs: keep
    # what survives an opening and regrow only its own outline.
    core = ndimage.binary_opening(m, structure=np.ones((4, 4)))
    if core.any():
        m = ndimage.binary_dilation(core, iterations=2) & m
    edge = k["dark"] & (ys > top)
    m = m | (_dilate4(m) & edge)
    return m, top


def _patch_cut(img, hole, passes=5):
    """Grow cloth down into the cut above moved legs: a hole pixel with an opaque
    pixel right above it takes that pixel's colour, a row at a time. The open
    gap between the feet has nothing above it and stays clear."""
    out = img.copy()
    for _ in range(passes):
        a = out[..., 3] > 128
        grow = hole & ~a
        grow[1:] &= a[:-1]
        grow[0] = False
        if not grow.any():
            break
        ys, xs = np.nonzero(grow)
        out[ys, xs] = out[ys - 1, xs]
    return out


def walk_keys_any(step, idle, ax, ay, cols):
    """(contact, passing, other contact) for any unit: the step as drawn, the
    standing frame, and the step with its legs mirrored."""
    ms, top = leg_mask_any(step, ax, ay, cols)
    if not ms.any():
        return step, idle, step
    rows = np.nonzero(ms.any(axis=1))[0]
    floor = int(rows.min() + 0.5 * (rows.max() - rows.min()))
    body = lift(step, ms, floor)
    other = put(body, top, step, ms, mirror=True)
    return step, idle, _patch_cut(other, ms)
