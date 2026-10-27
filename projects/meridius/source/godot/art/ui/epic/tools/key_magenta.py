"""Key the flat magenta out of a generated interface master.

    python art/ui/epic/tools/key_magenta.py SOURCE.png OUT.png [--margin 8] [--scale 0.6]

The image generator gives no alpha, so frames are painted on flat magenta
(#FF00FF): the outside and the opening. Alpha comes from how magenta a pixel is
(the least of red and blue over green); the magenta is unmixed from the
anti-aliased rim. Only magenta reachable from the image's border (or from its
middle, an empty opening) is keyed, so a ruby or a rust stain inside the frame
keeps its alpha. The result is cropped to the frame plus `margin` pixels and
scaled by `scale` (Lanczos). Prints the frame's rect in the output's pixels.
"""
import argparse

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def key(src: Image.Image) -> Image.Image:
    im = np.asarray(src.convert("RGB")).astype(np.float32)
    h, w, _ = im.shape
    corners = [im[:20, :20], im[:20, -20:], im[-20:, :20], im[-20:, -20:]]
    bg = np.median(np.concatenate([p.reshape(-1, 3) for p in corners]), axis=0)
    m = np.minimum(im[..., 0], im[..., 2]) - im[..., 1]
    full = min(bg[0], bg[2]) - bg[1]
    a = 1.0 - np.clip((m - 40.0) / (full - 70.0), 0.0, 1.0)
    # The magenta regions joined to the border (and the opening): flood fills.
    clear = Image.fromarray(np.where(m > 120, 255, 0).astype(np.uint8), "L").copy()
    seeds = [(x, y) for x in range(0, w, 16) for y in (0, h - 1)]
    seeds += [(x, y) for y in range(0, h, 16) for x in (0, w - 1)]
    seeds.append((w // 2, h // 2))
    for p in seeds:
        if clear.getpixel(p) == 255:
            ImageDraw.floodfill(clear, p, 128)
    keep = Image.fromarray(np.where(np.asarray(clear) == 128, 255, 0).astype(np.uint8), "L")
    # A few pixels more, for the anti-aliased rim.
    zone = np.asarray(keep.filter(ImageFilter.MaxFilter(9))) > 0
    a = np.where(zone, a, 1.0)
    aa = np.maximum(a, 1e-3)[..., None]
    rgb = np.clip((im - (1.0 - aa) * bg) / aa, 0, 255)
    out = np.dstack([rgb, a * 255.0]).astype(np.uint8)
    out[a < 0.02] = 0
    return Image.fromarray(out, "RGBA")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("out")
    ap.add_argument("--margin", type=int, default=8)
    ap.add_argument("--scale", type=float, default=1.0)
    args = ap.parse_args()
    keyed = key(Image.open(args.source))
    alpha = np.asarray(keyed)[..., 3]
    ys, xs = np.nonzero(alpha > 128)
    x0, y0 = max(0, xs.min() - args.margin), max(0, ys.min() - args.margin)
    x1, y1 = min(keyed.width, xs.max() + 1 + args.margin), min(keyed.height, ys.max() + 1 + args.margin)
    out = keyed.crop((x0, y0, x1, y1))
    if args.scale != 1.0:
        out = out.resize((round(out.width * args.scale), round(out.height * args.scale)), Image.LANCZOS)
    out.save(args.out, optimize=True)
    k = out.width / (x1 - x0)
    print("cropped from", (x0, y0, x1, y1), "size", out.size)
    print("frame rect", ((xs.min() - x0) * k, (ys.min() - y0) * k, (xs.max() + 1 - xs.min()) * k, (ys.max() + 1 - ys.min()) * k))


if __name__ == "__main__":
    main()
