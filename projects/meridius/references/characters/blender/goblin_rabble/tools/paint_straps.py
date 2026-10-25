"""Paint the Goblin Rabble's strap atlas, textures/goblin_rabble_straps_basecolor.jpg
(1024 x 1024), in the hand-painted look of the Tripo textures: soft blotches in two or
three tone steps, dark burnished edges and a light stitched seam along each edge. The
strips tile along their length (u). Rows from the top, at about 10 px per millimetre:

  0-255    strap face A (barrel shield): 26 mm across, 104 mm along, stitched
  256-511  strap face B (plank shield): darker, scuffed, the stitching broken in places
  512-639  the straps' sides and undersides, plain dark leather
  640-703  16 iron rivet heads seen from above, 64 x 64 px each, highlight to the upper left
  704-767  plain iron (nail shanks)
  768-1023 spare, plain leather

  python paint_straps.py [out.jpg]
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "textures" / "goblin_rabble_straps_basecolor.jpg"
rng = np.random.default_rng(20261025)


def noise(h, w, beta):
    """Fourier noise in 0..1 that tiles both ways; larger beta, larger blotches."""
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    f = np.hypot(fx, fy) * max(h, w)      # cycles per pixel, the same both ways
    f[0, 0] = 1
    amp = f ** -beta
    amp[0, 0] = 0
    n = np.real(np.fft.ifft2(amp * (rng.standard_normal((h, w)) + 1j * rng.standard_normal((h, w)))))
    return (n - n.min()) / (n.max() - n.min())


def ramp(x, lo, hi):
    return np.clip((x - lo) / (hi - lo), 0, 1)


def tones(L, shadow, base, light, steps=(0.40, 0.62), soft=0.035):
    """Two or three painted tone steps with soft transitions."""
    a, b = ramp(L, steps[0] - soft, steps[0] + soft)[..., None], ramp(L, steps[1] - soft, steps[1] + soft)[..., None]
    s, m, l = (np.array(c, float) for c in (shadow, base, light))
    return s + (m - s) * a + (l - m) * b


def blend(img, col, alpha):
    a = alpha[..., None]
    return img * (1 - a) + np.array(col, float) * a


def strap_face(h, w, shadow, base, light, edge, thread, broken=0.0, scuffs=26):
    v = np.linspace(0, 1, h)[:, None] * np.ones((1, w))
    L = 0.6 * noise(h, w, 2.4) + 0.3 * noise(h, w, 1.7) + 0.1 * noise(h, w, 0.9)
    img = tones(L, shadow, base, light)
    # Burnished edges, a highlight along the upper edge and shade toward the lower one.
    img = blend(img, light, 0.45 * ramp(v, 0.06, 0.10) * (1 - ramp(v, 0.13, 0.20)))
    img = blend(img, shadow, 0.35 * ramp(v, 0.70, 0.94))
    img = blend(img, edge, np.maximum(1 - ramp(v, 0.035, 0.065), ramp(v, 0.935, 0.965)))
    # Worn spots near the edges.
    wear = noise(h, w, 1.2) * (np.abs(v - 0.5) > 0.36)
    img = blend(img, light, 0.5 * ramp(wear, 0.62, 0.72))
    canvas = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).resize((w * 4, h * 4), Image.BICUBIC)
    d = ImageDraw.Draw(canvas, "RGBA")
    S = 4
    # Scratches and nicks.
    for _ in range(scuffs):
        x0, y0 = rng.uniform(0, w), rng.uniform(0.15 * h, 0.85 * h)
        ln, ang = rng.uniform(15, 60), rng.uniform(-0.5, 0.5)
        pts = [((x0 + t * ln * np.cos(ang)) * S, (y0 + t * ln * np.sin(ang) + 4 * np.sin(t * 3)) * S) for t in np.linspace(0, 1, 8)]
        col = tuple(int(c) for c in light) + (110,) if rng.random() < 0.7 else tuple(int(c) for c in edge) + (120,)
        for dx in (-w * S, 0, w * S):
            d.line([(x + dx, y) for x, y in pts], fill=col, width=int(1.6 * S))
    # The seams: a pressed groove, then short slanted stitches of thick thread, each from
    # one dark hole to the next.
    period = w / 15
    dark, thr = tuple(int(c) for c in edge), tuple(int(c) for c in thread)

    def stroke(p0, p1, width, fill):
        d.line([p0, p1], fill=fill, width=int(width))
        for px, py in (p0, p1):
            d.ellipse([px - width / 2, py - width / 2, px + width / 2, py + width / 2], fill=fill)

    for row in (0.22, 0.78):
        y = row * h * S
        d.line([(0, y + 3 * S), (w * S, y + 3 * S)], fill=dark + (110,), width=int(4 * S))
        for k in range(15):
            x0, x1 = (k * period + 6) * S, (k * period + 6 + period * 0.55) * S
            p0, p1 = (x0, y + 4 * S), (x1, y - 4 * S)
            for dx in (-w * S, 0, w * S):
                a, b = (p0[0] + dx, p0[1]), (p1[0] + dx, p1[1])
                for px, py in (a, b):
                    d.ellipse([px - 4.5 * S, py - 4.5 * S, px + 4.5 * S, py + 4.5 * S], fill=dark + (255,))
                if rng.random() < broken:
                    continue
                stroke(a, b, 10 * S, dark + (255,))
                stroke(a, b, 6.5 * S, thr + (255,))
                stroke((a[0] + 3 * S, a[1] - 2.2 * S), (b[0] - 3 * S, b[1] - 2.2 * S), 2.2 * S, (255, 248, 226, 150))
    return np.array(canvas.resize((w, h), Image.LANCZOS), float)


def plain(h, w, shadow, base, light):
    L = 0.6 * noise(h, w, 2.2) + 0.4 * noise(h, w, 1.0)
    return tones(L, shadow, base, light, steps=(0.42, 0.7))


def rivets(h, w, n):
    S, c = 4, 64
    canvas = Image.new("RGB", (w * S, h * S), (60, 40, 30))
    d = ImageDraw.Draw(canvas, "RGBA")
    for k in range(n):
        cx, cy, r = (k * c + 32) * S, 32 * S, 27 * S
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(46, 42, 44))
        r2 = r - 3 * S
        d.ellipse([cx - r2, cy - r2, cx + r2, cy + r2], fill=(92, 88, 90))
        # Shade toward the lower right, light to the upper left.
        d.ellipse([cx - r2 + 6 * S, cy - r2 + 6 * S, cx + r2, cy + r2], fill=(70, 66, 70))
        d.ellipse([cx - r2, cy - r2, cx + r2 - 9 * S, cy + r2 - 9 * S], fill=(104, 100, 100))
        for _ in range(int(rng.integers(3, 7))):
            a, rr = rng.uniform(0.2 * np.pi, 1.3 * np.pi), rng.uniform(0.45, 0.9) * r2
            px, py, pr = cx + rr * np.cos(a), cy + rr * np.sin(a), rng.uniform(2, 5) * S
            d.ellipse([px - pr, py - pr, px + pr, py + pr], fill=(132, 74, 44, 150))
        hx, hy, hr = cx - 8 * S, cy - 8 * S, 6 * S
        d.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=(168, 162, 150, 220))
    return np.array(canvas.filter(ImageFilter.GaussianBlur(S * 0.4)).resize((w, h), Image.LANCZOS), float)


atlas = np.zeros((SIZE, SIZE, 3))
atlas[0:256] = strap_face(256, SIZE, (86, 52, 32), (120, 76, 46), (156, 104, 64), (48, 28, 18), (222, 196, 150))
atlas[256:512] = strap_face(256, SIZE, (70, 44, 30), (98, 64, 42), (132, 92, 62), (40, 24, 16), (194, 178, 146),
                            broken=0.22, scuffs=48)
atlas[512:640] = plain(128, SIZE, (50, 30, 20), (72, 46, 30), (92, 60, 40))
atlas[640:704] = rivets(64, SIZE, 16)
iron = plain(64, SIZE, (44, 42, 46), (70, 68, 72), (96, 92, 94))
atlas[704:768] = blend(iron, (128, 72, 40), 0.6 * ramp(noise(64, SIZE, 1.4), 0.66, 0.8))
atlas[768:1024] = plain(256, SIZE, (66, 42, 28), (96, 62, 40), (120, 80, 52))
OUT.parent.mkdir(parents=True, exist_ok=True)
Image.fromarray(np.clip(atlas, 0, 255).astype(np.uint8)).save(OUT, quality=92, subsampling=0)
print(OUT)
