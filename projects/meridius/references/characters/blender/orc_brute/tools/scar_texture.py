"""Paint the claw scar from the scar bust (face_scar.png) into a copy of the body's base
colour: one of his squad's faces.

  python scar_texture.py ratio <face_scar.png> <ratio.npz> [debug_prefix]
  python scar_texture.py paint <body_basecolor.jpg> <ratio.npz> <uvmap.npz> <out.jpg> [debug.png]

`ratio` lifts the scar off the bust as a colour ratio against the skin around it. The scar
is every strongly red pixel (crimson to pink; the skin is orange-brown) plus its dark rim,
grown a little and feathered. The skin under it is estimated by a normalised blur of the
skin around the scar, and the scar is stored as the bust's colour divided by that estimate,
so painting it multiplies the 3D texture's own skin and keeps its lighting. The bust is
mapped to the head's front view (x, z in metres) by an affine fit on the eyes and nostrils,
measured on the bust and on a front render of the head.

Between the two, scar_uvmap.py (Blender) maps the body's texels to bust pixels.

`paint` multiplies each mapped texel's colour by the scar's ratio at the bust pixel it
shows, weighted by the scar mask, faded where the skin turns away from the front (the bust
is a front view, so it says little about surfaces seen edge-on) and skipped where the front
view does not reach the texel."""
import sys

import numpy as np
from PIL import Image

X0, Y0, X1, Y1 = 1950, 380, 2520, 1200          # region of the bust holding the scar
EYE = (2242, 858, 78, 30)                        # his left eye's opening: centre and half-axes (px)
# Landmarks (eyes, nostrils): bust pixels and the same points on the front render
# (4000 px/m, centre (500, 500) at x 0, z 1.88).
BUST = np.array([[1860, 862], [2245, 860], [1970, 1020], [2130, 1020]], float)
REND = np.array([[307.5, 532.5], [670, 532], [410, 675], [570, 675]], float)


def box(m, k):
    """Mean over a (2k+1)^2 box, by cumulative sums."""
    p = np.pad(m.astype(np.float64), k, mode="edge")
    c = np.pad(p.cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    n = 2 * k + 1
    return ((c[n:, n:] - c[:-n, n:] - c[n:, :-n] + c[:-n, :-n]) / n / n).astype(np.float32)


def blur(m, k, passes=3):
    for _ in range(passes):
        m = box(m, k)
    return m


def ratio(src, out, dbg=None):
    world = np.stack([(REND[:, 0] - 500) / 4000, 1.88 - (REND[:, 1] - 500) / 4000], 1)
    A = np.c_[BUST, np.ones(4)]
    M = np.linalg.lstsq(A, world, rcond=None)[0]   # bust (X, Y, 1) -> world (x, z)
    print("AFFINE residual (mm)", np.round(np.linalg.norm(A @ M - world, axis=1) * 1000, 2))

    img = np.asarray(Image.open(src).convert("RGB"), np.float32)[Y0:Y1, X0:X1] / 255
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    mx, mn = img.max(-1), img.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1e-4)
    d = np.maximum(mx - mn, 1e-4)
    hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    # Crimson: the wound (the line art is a darker, browner red, hue 5-15, and less saturated).
    # Specks are dropped: crimson counts where enough of its neighbourhood is crimson too.
    crim = ((hue > 340) | (hue < 2)) & (sat > 0.5) & (mx > 0.3)
    crim &= box(crim, 3) > 0.3
    # The pink, raw rims along the wound: light, salmon-hued, close to the crimson.
    pink = (box(crim, 10) > 0.04) & (hue >= 2) & (hue < 20) & (sat > 0.25) & (mx > 0.58)
    # The wound's dark maroon edges, next to the crimson.
    maroon = (box(crim, 4) > 0.05) & ((hue > 335) | (hue < 6)) & (sat > 0.45) & (mx > 0.1)
    core = crim | pink | maroon
    # Not the eye itself: its iris is red-brown too, and the slashes stop at the lids.
    yy, xx = np.mgrid[Y0:Y1, X0:X1]
    core &= ((xx - EYE[0]) / EYE[2]) ** 2 + ((yy - EYE[1]) / EYE[3]) ** 2 > 1
    mask = blur(np.clip(box(core, 2) * 2.5, 0, 1), 1, 2)
    # The skin under the scar: a normalised blur of everything outside a wider mask.
    keep = (box(core, 9) < 0.01).astype(np.float32)
    skin = np.stack([blur(img[..., c] * keep, 14) for c in range(3)], -1) / np.maximum(blur(keep, 14), 1e-4)[..., None]
    rat = np.clip(img / np.maximum(skin, 0.03), 0, 2.5)
    ys, xs = np.nonzero(mask > 0.02)
    corners = np.array([[xs.min() + X0, ys.min() + Y0, 1], [xs.max() + X0, ys.max() + Y0, 1]], float) @ M
    print("SCAR pixels", int((mask > 0.5).sum()), "bust X %d..%d Y %d..%d" % (
        xs.min() + X0, xs.max() + X0, ys.min() + Y0, ys.max() + Y0),
        "world x %.4f..%.4f z %.4f..%.4f" % (corners[0, 0], corners[1, 0], corners[1, 1], corners[0, 1]))
    np.savez(out, ratio=rat.astype(np.float16), mask=mask.astype(np.float16), origin=np.array([X0, Y0]), affine=M)
    if dbg:
        Image.fromarray((mask * 255).astype(np.uint8)).save(dbg + "_mask.png")
        Image.fromarray((np.clip(skin, 0, 1) * 255).astype(np.uint8)).save(dbg + "_skin.png")
        over = img.copy()
        over[mask > 0.5] = over[mask > 0.5] * 0.4 + np.array([0, 1, 0]) * 0.6
        Image.fromarray((np.clip(over, 0, 1) * 255).astype(np.uint8)).save(dbg + "_over.png")


def bilinear(img, x, y):
    H, W = img.shape[:2]
    x = np.clip(x, 0, W - 1.001)
    y = np.clip(y, 0, H - 1.001)
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = x - x0, y - y0
    if img.ndim == 3:
        fx, fy = fx[:, None], fy[:, None]
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x0 + 1] * fx * (1 - fy)
            + img[y0 + 1, x0] * (1 - fx) * fy + img[y0 + 1, x0 + 1] * fx * fy)


def paint(tex_p, ratio_p, uvmap_p, out, dbg=None):
    S = np.load(ratio_p)
    rat, mask = S["ratio"].astype(np.float32), S["mask"].astype(np.float32)
    X, Y = S["origin"]
    U = np.load(uvmap_p)
    tex = np.asarray(Image.open(tex_p).convert("RGB"), np.float32) / 255
    H, W = mask.shape
    x, y = U["bx"] - X, U["by"] - Y
    inside = (x >= 0) & (x < W - 1) & (y >= 0) & (y < H - 1)
    m = np.where(inside, bilinear(mask, x, y), 0)
    facing = np.clip((U["face"] - 0.15) / 0.25, 0, 1)
    wgt = m * facing * U["seen"]
    r = bilinear(rat, x, y)
    c, rw = U["col"], U["row"]
    ok = (wgt > 0.003) & (c >= 0) & (c < tex.shape[1]) & (rw >= 0) & (rw < tex.shape[0])
    tex[rw[ok], c[ok]] = np.clip(tex[rw[ok], c[ok]] * (1 + (r[ok] - 1) * wgt[ok, None]), 0, 1)
    print("PAINTED texels", int(ok.sum()), "full strength", int((wgt > 0.9).sum()),
          "hidden skipped", int(((m > 0.1) & ~U["seen"]).sum()), "edge-on faded", int(((m > 0.1) & (facing < 1)).sum()))
    Image.fromarray((tex * 255 + 0.5).astype(np.uint8)).save(out, quality=95)
    if dbg:
        c0, c1 = max(c[ok].min() - 40, 0), c[ok].max() + 40
        r0, r1 = max(rw[ok].min() - 40, 0), rw[ok].max() + 40
        Image.fromarray((tex[r0:r1, c0:c1] * 255).astype(np.uint8)).save(dbg)
        print("DEBUG crop cols %d..%d rows %d..%d" % (c0, c1, r0, r1))


if __name__ == "__main__":
    cmd, args = sys.argv[1], sys.argv[2:]
    {"ratio": ratio, "paint": paint}[cmd](*args)
