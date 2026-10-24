"""Build eight-direction squad sprites from per-soldier pixel-art turnaround sheets.

Usage:
  python squad.py extract <sheet.png> <fig_dir> <soldier> <views>
      Cut the figures of one generated sheet (reading order) and save them as
      <fig_dir>/<view>_<soldier>.png, scaled to one body height on the native
      pixel grid. <views> is comma separated, e.g. s,sw,e,n,ne; "-" skips one.
  python squad.py grid <fig_dir> <view> <out.png> [--mirror]
      Lay out the six soldiers' <view> figures in a 3 x 2 grid on flat grey
      (K raw pixels per native pixel) as the input for an edit: mirrored, for
      an edit that puts sword and shield back in the right hands (SE from SW,
      W from E, NW from NE); as they are, for an edit into another action.
      "mirror" is short for grid --mirror.
  python squad.py extract6 <edited.png> <fig_dir> <view> [--fixed]
      Cut the six figures of an edited grid into <fig_dir>/<view>_<1..6>.png.
      --fixed keeps the size drawn in the grid instead of the BODY height.
  python squad.py assemble <fig_dir> <out_dir> [--colors 64]
      Quantize every figure to one shared palette, then compose each direction
      as a 3 x 2 formation (slots 1-3 rear rank, 4-6 front rank) with banded
      contact shadows. Writes footman_squad_<dir>_512.png (native) and
      footman_squad_<dir>.png (2x nearest-neighbour), plus the single soldiers
      under <out_dir>/soldiers/.

Figures are anchored at the feet. Body height (head to feet, ignoring the thin
raised blade) is BODY native pixels for every soldier in every direction.
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
from pixelize import block_median, cut_out

BODY = 190  # native pixels, head to feet
K = 4  # raw pixels per native pixel when resampling a figure
NATIVE = 512
DIRS = ['s', 'sw', 'w', 'nw', 'n', 'ne', 'e', 'se']
# Feet of the six formation slots on the native canvas (rear rank, then front rank).
SLOTS = [(126, 272), (256, 272), (386, 272), (126, 452), (256, 452), (386, 452)]
BG = (190, 188, 188)


def solid_mask(rgba):
    return rgba[:, :, 3] == 255


def body_top(mask):
    """First row that is wider than a blade: the top of the head."""
    widths = mask.sum(axis=1)
    rows = np.nonzero(widths >= 0.12 * widths.max())[0]
    return rows[0]


def find_figures(raw, expected):
    """Bounding boxes of the figures on a sheet, in reading order."""
    small = block_median(raw, 8)
    out, _, _ = cut_out(small)
    mask = ndimage.binary_dilation(solid_mask(out), iterations=2)
    labels, n = ndimage.label(mask)
    boxes = []
    for i, sl in enumerate(ndimage.find_objects(labels), start=1):
        area = int((labels[sl] == i).sum())
        boxes.append((area, sl))
    boxes.sort(key=lambda b: -b[0])
    boxes = [b for b in boxes if b[0] >= 0.25 * boxes[0][0]]
    if len(boxes) != expected:
        raise SystemExit(f'expected {expected} figures, found {len(boxes)}')
    boxes = [(sl[0].start * 8, sl[1].start * 8, sl[0].stop * 8, sl[1].stop * 8) for _, sl in boxes]
    med_h = np.median([b[2] - b[0] for b in boxes])
    boxes.sort(key=lambda b: (b[0] + b[2]) / 2)
    rows = []
    for b in boxes:
        cy = (b[0] + b[2]) / 2
        if rows and abs(cy - (rows[-1][0][0] + rows[-1][0][2]) / 2) < 0.4 * med_h:
            rows[-1].append(b)
        else:
            rows.append([b])
    return [b for row in rows for b in sorted(row, key=lambda q: q[1])]


def main_part(mask):
    """Drop stray specks (shadow rims, generator noise) away from the figure."""
    labels, n = ndimage.label(ndimage.binary_dilation(mask, iterations=2))
    if n <= 1:
        return mask
    sizes = ndimage.sum(mask, labels, range(1, n + 1))
    return mask & np.isin(labels, np.nonzero(sizes >= 0.05 * sizes.max())[0] + 1)


def figure(raw, box, scale=None):
    """One figure as an unquantized native RGBA array with hard alpha, feet at the bottom.

    Without `scale` the figure is resized to BODY native pixels from head to
    feet. With `scale` (raw resize factor) its size is kept as drawn, for
    edits of a grid laid out at K raw pixels per native pixel, where a crouch
    or a fall must not be stretched back to standing height.
    """
    h, w, _ = raw.shape
    m = 40
    y0, x0, y1, x1 = max(0, box[0] - m), max(0, box[1] - m), min(h, box[2] + m), min(w, box[3] + m)
    crop = raw[y0:y1, x0:x1]
    if scale is None:
        probe, _, _ = cut_out(block_median(crop, K))
        pm = main_part(solid_mask(probe))
        ys = np.nonzero(pm.any(axis=1))[0]
        body_raw = (ys[-1] - body_top(pm) + 1) * K
        s = BODY * K / body_raw
    else:
        s = scale
    img = Image.fromarray(crop).resize((max(K, round(crop.shape[1] * s)), max(K, round(crop.shape[0] * s))), Image.Resampling.LANCZOS)
    pad = Image.new('RGB', (img.width + 8 * K - img.width % K, img.height + 8 * K - img.height % K), BG)
    pad.paste(img, (4 * K, 4 * K))
    small = block_median(np.array(pad), K)
    out, _, _ = cut_out(small)
    # Generated shadows are dropped; assemble draws one consistent shadow per slot.
    alpha = np.where(main_part(solid_mask(out)), 255, 0).astype(np.uint8)
    ys, xs = np.nonzero(alpha)
    rgba = np.dstack([small, alpha])[ys.min(): ys.max() + 1, xs.min(): xs.max() + 1]
    return rgba


def foot_x(rgba):
    a = rgba[:, :, 3] > 0
    ys = np.nonzero(a.any(axis=1))[0]
    feet = a[max(0, ys[-1] - 10): ys[-1] + 1]
    return float(np.nonzero(feet)[1].mean())


def save_fig(fig_dir, name, rgba):
    os.makedirs(fig_dir, exist_ok=True)
    Image.fromarray(rgba, 'RGBA').save(os.path.join(fig_dir, f'{name}.png'))
    print(f'{name}: {rgba.shape[1]}x{rgba.shape[0]}')


def cmd_extract(sheet, fig_dir, soldier, views):
    views = views.split(',')
    raw = np.array(Image.open(sheet).convert('RGB'))
    boxes = find_figures(raw, len(views))
    for view, box in zip(views, boxes):
        if view != '-':
            save_fig(fig_dir, f'{view}_{soldier}', figure(raw, box))


GRID = 2048  # side of the edit input grids


def cmd_grid(fig_dir, view, out, mirror=False):
    cw, ch = GRID // 3, GRID // 2
    canvas = Image.new('RGB', (GRID, GRID), BG)
    for i in range(6):
        im = Image.open(os.path.join(fig_dir, f'{view}_{i + 1}.png'))
        if mirror:
            im = im.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        im = im.resize((im.width * K, im.height * K), Image.Resampling.NEAREST)
        cx = (i % 3) * cw + cw // 2
        base = (i // 3) * ch + ch - 60
        canvas.paste(im, (cx - im.width // 2, base - im.height), im)
    canvas.save(out)


def cmd_extract6(edited, fig_dir, view, fixed=False):
    raw = np.array(Image.open(edited).convert('RGB'))
    # An edit of a GRID-sized input keeps the figures' drawn size.
    scale = GRID / raw.shape[1] if fixed else None
    for i, box in enumerate(find_figures(raw, 6)):
        save_fig(fig_dir, f'{view}_{i + 1}', figure(raw, box, scale))


def feet_span(rgba):
    """Leftmost and rightmost opaque columns of the lowest rows (the boots)."""
    a = rgba[:, :, 3] > 0
    ys = np.nonzero(a.any(axis=1))[0]
    xs = np.nonzero(a[max(0, ys[-1] - 12): ys[-1] + 1].any(axis=0))[0]
    return xs[0], xs[-1]


def shadow_layer(size, shadows):
    """Banded elliptical contact shadows, one (cx, cy, half_width) per soldier."""
    yy, xx = np.mgrid[0:size, 0:size]
    a = np.zeros((size, size), np.float32)
    for cx, cy, rx in shadows:
        d = ((xx - cx) / rx) ** 2 + ((yy - cy) / 10.0) ** 2
        a = np.maximum(a, np.where(d < 0.45, 0.34, np.where(d < 1.0, 0.2, 0)))
    layer = np.zeros((size, size, 4), np.uint8)
    layer[:, :, 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(layer, 'RGBA')


def load_figs(fig_dir):
    figs = {}
    for d in DIRS:
        for i in range(1, 7):
            p = os.path.join(fig_dir, f'{d}_{i}.png')
            if not os.path.exists(p):
                raise SystemExit(f'missing {p}')
            figs[(d, i)] = np.array(Image.open(p).convert('RGBA'))
    return figs


def shared_palette(figs, colors=64):
    """One palette for the whole set so every direction uses the same colours."""
    opaque = np.concatenate([f[f[:, :, 3] > 0][:, :3] for f in figs])
    side = int(np.ceil(np.sqrt(len(opaque))))
    mosaic = np.zeros((side * side, 3), np.uint8)
    mosaic[: len(opaque)] = opaque
    mosaic[len(opaque):] = opaque[0]
    return Image.fromarray(mosaic.reshape(side, side, 3)).quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)


def cmd_assemble(fig_dir, out_dir, colors=64):
    figs = load_figs(fig_dir)
    pal = shared_palette(figs.values(), colors)
    for key, f in figs.items():
        q = Image.fromarray(np.ascontiguousarray(f[:, :, :3])).quantize(palette=pal, dither=Image.Dither.NONE)
        f[:, :, :3] = np.array(q.convert('RGB'))

    sol_dir = os.path.join(out_dir, 'soldiers')
    os.makedirs(sol_dir, exist_ok=True)
    anchors = {}
    for (d, i), f in figs.items():
        name = f'footman_{d}_{i}'
        Image.fromarray(f, 'RGBA').save(os.path.join(sol_dir, f'{name}.png'))
        anchors[name] = {'ax': round(foot_x(f), 1), 'ay': f.shape[0]}
    with open(os.path.join(sol_dir, 'anchors.json'), 'w', encoding='utf-8') as fh:
        json.dump(anchors, fh, indent=1)

    for d in DIRS:
        placed = []
        for i, (fx, fy) in enumerate(SLOTS, start=1):
            f = figs[(d, i)]
            x = int(round(fx - foot_x(f)))
            l, r = feet_span(f)
            placed.append((f, x, fy - f.shape[0], (x + (l + r) / 2, fy - 2, max(28.0, (r - l) / 2 + 8))))
        canvas = shadow_layer(NATIVE, [p[3] for p in placed])
        for f, x, y, _ in placed:
            canvas.alpha_composite(Image.fromarray(f, 'RGBA'), (x, y))
        canvas.save(os.path.join(out_dir, f'footman_squad_{d}_512.png'))
        canvas.resize((NATIVE * 2, NATIVE * 2), Image.Resampling.NEAREST).save(os.path.join(out_dir, f'footman_squad_{d}.png'))
        print(f'squad {d}')


def main():
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == 'extract':
        cmd_extract(*args)
    elif cmd == 'grid':
        cmd_grid(args[0], args[1], args[2], '--mirror' in args[3:])
    elif cmd == 'mirror':
        cmd_grid(*args, mirror=True)
    elif cmd == 'extract6':
        cmd_extract6(args[0], args[1], args[2], '--fixed' in args[3:])
    elif cmd == 'assemble':
        cmd_assemble(args[0], args[1], int(args[3]) if len(args) > 3 and args[2] == '--colors' else 64)
    else:
        raise SystemExit(__doc__)


if __name__ == '__main__':
    main()
