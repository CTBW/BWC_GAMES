"""Turn edited keyframe sheets into registered pixel-art animation frames.

The six soldiers of a facing are laid out in a row, one row per keyframe, and
an image edit redraws each row in a new phase of the action. Every cut figure
keeps its offset from the source figure drawn in its cell, so the frames of an
animation register against the idle sprites.

Usage:
  python anim.py sheet <fig_dir> <out.png> <src>[,<src>...]
      [--grid 3x2 --cell 840x840 --base 60]
      Lay out the six soldiers' <src> figures in six columns, one row per
      <src>, on flat grey at K raw pixels per native pixel (cells as in
      squad.py grid), as the input for an edit. Writes <out>.json, the layout.
      --grid lays out one <src> in that many columns and rows of --cell raw
      pixels, feet --base raw pixels above each cell's bottom: room for bodies
      falling on the ground. <fig_dir> may be a frame dir, to chain edits.
  python anim.py legacy <fig_dir> <view> <out.json>
      The layout of a 3 x 2 grid made by squad.py grid (unmirrored).
  python anim.py cut <edited.png> <layout.json> <frame_dir> <name>[,<name>...]
      [--split x0,y0,x1,y1 ...] [--keep-y] [--bg-tol 22] [--no-shadows]
      Cut the figures of an edited sheet at the drawn size into
      <frame_dir>/<name>_<soldier>.png, one name per layout row (a legacy grid
      has one), and record each offset from its source figure, feet on the
      source's ground line, in <frame_dir>/offsets.json; a source that is
      itself a cut frame passes on its own offset. --keep-y keeps the drawn
      height instead (bodies lying on the ground). --split draws a background
      line (native sheet pixels) through a contact between figures.
      --no-shadows keeps grey hair or steel that the contact-shadow key takes
      for shadow; a lower --bg-tol keeps colours close to the background.
  python anim.py breathe <fig_dir> <frame_dir> <view> [--px 0,1,2,1]
      Idle frames made from the still figures: the upper body sinks by the
      given pixels (rows dropped at chest height), as idle_<view>_<n>.
  python anim.py palette <fig_dir> <out.png>
      Save the idle set's shared palette, as squad.py assemble computes it.
  python anim.py play <fig_dir> <frame_dir> <out_dir> <anim> <frame>[,<frame>...]
      [--palette <palette.png>] [--ms 120[,...]]
      Compose each soldier's frames (cut names, or fig views such as "sw")
      on one canvas per soldier, mapped to --palette. Writes
      <out_dir>/<anim>/<anim>_<soldier>_<nn>.png,
      anchors.json, <anim>_strip.png (soldiers x frames) and <anim>.gif (all
      six on grass, 2x).
  python anim.py export <play_dir> <out_dir> <anim>=<key>[:m] ...
      Copy played animations under game sprite keys as
      <out_dir>/frames/<key>_<nn>_<v>.png (v = soldier - 1); ":m" mirrors,
      since the game's _fs and _bs sprites hold a mirrored true SE and NW.
      Writes <out_dir>/sprites.json (manifest-style entries per frame key,
      without scale, plus each animation's frame keys and durations) and the
      review GIFs and strips under <out_dir>/review/.
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
from pixelize import block_median, cut_out
from squad import BG, GRID, K, foot_x, load_figs, shared_palette, solid_mask

CW, CH = GRID // 3, GRID // 2  # cell of an edit grid, raw pixels
BASE = 60  # feet above the bottom of a cell, raw pixels
MIN_PART = 150  # native pixels; smaller loose parts are generator specks
GRASS = (92, 110, 60, 255)


def load_fig(fig_dir, name):
    return Image.open(os.path.join(fig_dir, f'{name}.png')).convert('RGBA')


def place(cells, fig_dir, src, soldier, row, col, top, cw=CW, ch=CH, margin=BASE):
    """Placement of one source figure, centred in its cell, feet on the cell's ground line."""
    w, h = load_fig(fig_dir, f'{src}_{soldier}').size
    cx = col * cw + cw // 2
    base = top + ch - margin
    cells.append({'src': src, 'soldier': soldier, 'row': row,
                  'x': cx - w * K // 2, 'y': base - h * K, 'w': w, 'h': h,
                  'cell': [col * cw, top, (col + 1) * cw, top + ch]})


def render(layout, fig_dir, out):
    canvas = Image.new('RGB', (layout['width'], layout['height']), BG)
    for c in layout['cells']:
        im = load_fig(fig_dir, f"{c['src']}_{c['soldier']}")
        im = im.resize((im.width * K, im.height * K), Image.Resampling.NEAREST)
        canvas.paste(im, (c['x'], c['y']), im)
    canvas.save(out)


def cmd_sheet(fig_dir, out, srcs, grid=None, cell=None, margin=BASE):
    srcs = srcs.split(',')
    cells = []
    if grid:
        if len(srcs) != 1:
            raise SystemExit('--grid takes one source')
        cols, rows = grid
        cw, ch = cell
        for i in range(6):
            place(cells, fig_dir, srcs[0], i + 1, 0, i % cols, (i // cols) * ch, cw, ch, margin)
        layout = {'width': cols * cw, 'height': rows * ch, 'cells': cells}
    else:
        for r, src in enumerate(srcs):
            for i in range(6):
                place(cells, fig_dir, src, i + 1, r, i, r * CH)
        # Two grids wide, so a 4k edit of four rows comes back at exactly this size.
        layout = {'width': 2 * GRID, 'height': len(srcs) * CH, 'cells': cells}
    render(layout, fig_dir, out)
    with open(os.path.splitext(out)[0] + '.json', 'w', encoding='utf-8') as fh:
        json.dump(layout, fh, indent=1)
    print(f'{out}: {layout["width"]}x{layout["height"]}, rows {srcs}')


def cmd_legacy(fig_dir, view, out):
    cells = []
    for i in range(6):
        place(cells, fig_dir, view, i + 1, 0, i % 3, (i // 3) * CH)
    with open(out, 'w', encoding='utf-8') as fh:
        json.dump({'width': GRID, 'height': GRID, 'cells': cells}, fh, indent=1)


def cmd_cut(edited, layout_path, frame_dir, names, splits, keep_y=False, bg_tol=22.0, shadows=True):
    with open(layout_path, encoding='utf-8') as fh:
        layout = json.load(fh)
    names = names.split(',')
    raw = Image.open(edited).convert('RGB')
    if raw.size != (layout['width'], layout['height']):
        # Back to the input's scale, so one native pixel is K raw pixels again.
        raw = raw.resize((layout['width'], layout['height']), Image.Resampling.LANCZOS)
    small = block_median(np.array(raw), K)
    out, _, _ = cut_out(small, bg_tol, shadows=shadows)
    solid = solid_mask(out)
    # Dilated, so a blade drawn a pixel or two off the hand stays with its man;
    # the split lines cut the dilated mask, where neighbours meet.
    joined = ndimage.binary_dilation(solid, iterations=2)
    for x0, y0, x1, y1 in splits:
        n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for t in np.linspace(0, 1, n * 2):
            joined[int(round(y0 + (y1 - y0) * t)), int(round(x0 + (x1 - x0) * t))] = False

    # Each part goes to the cell that holds its centre; parts touching across
    # cells would land in one, so every cell must end up with a figure.
    cells = layout['cells']
    rects = [[v // K for v in c['cell']] for c in cells]
    labels, n = ndimage.label(joined)
    labels[~solid] = 0
    sizes = ndimage.sum(solid, labels, range(1, n + 1))
    with np.errstate(invalid='ignore'):  # parts that are all split line have no centre
        centres = ndimage.center_of_mass(solid, labels, range(1, n + 1))
    owner = np.zeros(n + 1, np.int32)
    for j, ((cy, cx), size) in enumerate(zip(centres, sizes), start=1):
        if size < MIN_PART:
            continue
        for ci, (x0, y0, x1, y1) in enumerate(rects):
            if x0 <= cx < x1 and y0 <= cy < y1:
                owner[j] = ci + 1
    lab = owner[labels]
    found = set(np.unique(lab)) - {0}
    missing = [ci for ci in range(len(cells)) if ci + 1 not in found]
    if missing:
        raise SystemExit(f'no figure in cells {missing}: figures touch; add --split lines')

    path = os.path.join(frame_dir, 'offsets.json')
    offsets = load_offsets(frame_dir)
    os.makedirs(frame_dir, exist_ok=True)
    for ci, c in enumerate(cells):
        m = lab == ci + 1
        ys, xs = np.nonzero(m)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        rgba = np.dstack([small[y0:y1, x0:x1], np.where(m[y0:y1, x0:x1], 255, 0).astype(np.uint8)])
        name = f"{names[c['row']]}_{c['soldier']}"
        Image.fromarray(rgba, 'RGBA').save(os.path.join(frame_dir, f'{name}.png'))
        src = f"{c['src']}_{c['soldier']}"
        parent = offsets.get(src, {'src': src, 'dx': 0, 'dy': 0})
        dx = int(x0 - round(c['x'] / K))
        drift = int(y1 - round(c['y'] / K) - c['h'])
        # Feet go on the source figure's ground line; the drawn row may sit a little off it.
        dy = int(y0 - round(c['y'] / K)) if keep_y else int(c['h'] - (y1 - y0))
        offsets[name] = {'src': parent['src'], 'dx': parent['dx'] + dx, 'dy': parent['dy'] + dy, 'drift': drift}
        print(f"{name}: {x1 - x0}x{y1 - y0}, dx {dx}, ground drift {drift}")
    with open(path, 'w', encoding='utf-8') as fh:
        json.dump(offsets, fh, indent=1)


CHEST = 0.42  # fraction of a figure's height, from the top, where breathing rows drop


def load_offsets(frame_dir):
    path = os.path.join(frame_dir, 'offsets.json')
    if not os.path.exists(path):
        return {}
    with open(path, encoding='utf-8') as fh:
        return json.load(fh)


def cmd_breathe(fig_dir, frame_dir, view, px=(0, 1, 2, 1)):
    offsets = load_offsets(frame_dir)
    os.makedirs(frame_dir, exist_ok=True)
    for i in range(1, 7):
        fig = np.array(load_fig(fig_dir, f'{view}_{i}'))
        seam = int(fig.shape[0] * CHEST)
        for n, p in enumerate(px):
            out = np.zeros_like(fig)
            out[seam:] = fig[seam:]
            # Everything above the seam moves down p rows, over the rows just below it.
            out[p: seam + p] = np.where(fig[:seam, :, 3:] > 0, fig[:seam], out[p: seam + p])
            name = f'idle_{view}_{n}_{i}'
            Image.fromarray(out, 'RGBA').save(os.path.join(frame_dir, f'{name}.png'))
            offsets[name] = {'src': f'{view}_{i}', 'dx': 0, 'dy': 0, 'drift': 0}
    with open(os.path.join(frame_dir, 'offsets.json'), 'w', encoding='utf-8') as fh:
        json.dump(offsets, fh, indent=1)
    print(f'idle_{view}: {len(px)} frames, sink {list(px)}')


def cmd_palette(fig_dir, out):
    """The idle set's palette (squad.py assemble), so frames match the still sprites exactly."""
    shared_palette(load_figs(fig_dir).values()).save(out)
    print(f'{out}: palette of the idle set')


def to_palette(rgba, pal):
    out = rgba.copy()
    q = Image.fromarray(np.ascontiguousarray(rgba[:, :, :3])).quantize(palette=pal, dither=Image.Dither.NONE)
    out[:, :, :3] = np.array(q.convert('RGB'))
    return out


def cmd_play(fig_dir, frame_dir, out_dir, anim, frames, pal_path=None, ms=(120,)):
    frames = frames.split(',')
    offsets = load_offsets(frame_dir)
    pal = Image.open(pal_path) if pal_path else None
    dest = os.path.join(out_dir, anim)
    os.makedirs(dest, exist_ok=True)
    anchors, rows = {}, []
    for i in range(1, 7):
        seq = []
        for f in frames:
            key = f'{f}_{i}'
            if key in offsets:
                o = offsets[key]
                im = np.array(Image.open(os.path.join(frame_dir, f'{key}.png')).convert('RGBA'))
                seq.append((o['src'], im, o['dx'], o['dy']))
            else:
                seq.append((key, np.array(load_fig(fig_dir, key)), 0, 0))
        srcs = {s for s, *_ in seq}
        if len(srcs) != 1:
            raise SystemExit(f'soldier {i}: frames drawn from different figures {sorted(srcs)}')
        src = np.array(load_fig(fig_dir, srcs.pop()))
        ux0 = min(dx for _, _, dx, _ in seq)
        uy0 = min(dy for _, _, _, dy in seq)
        ux1 = max(dx + im.shape[1] for _, im, dx, _ in seq)
        uy1 = max(dy + im.shape[0] for _, im, _, dy in seq)
        canvases = []
        for n, (_, im, dx, dy) in enumerate(seq):
            if pal is not None:
                im = to_palette(im, pal)
            c = Image.new('RGBA', (ux1 - ux0, uy1 - uy0))
            c.alpha_composite(Image.fromarray(im, 'RGBA'), (dx - ux0, dy - uy0))
            c.save(os.path.join(dest, f'{anim}_{i}_{n:02d}.png'))
            canvases.append(c)
        anchors[f'{anim}_{i}'] = {'ax': round(foot_x(src) - ux0, 1), 'ay': src.shape[0] - uy0, 'frames': len(seq),
                                  'ms': [ms[min(n, len(ms) - 1)] for n in range(len(seq))]}
        rows.append((canvases, foot_x(src) - ux0, src.shape[0] - uy0))
    with open(os.path.join(dest, 'anchors.json'), 'w', encoding='utf-8') as fh:
        json.dump(anchors, fh, indent=1)

    # Review sheets: every soldier's frames on a shared anchor grid.
    left = int(max(ax for _, ax, _ in rows)) + 4
    right = int(max(c[0].width - ax for c, ax, _ in rows)) + 4
    up = max(ay for _, _, ay in rows) + 4
    down = max(c[0].height - ay for c, _, ay in rows) + 4
    fw, fh_ = left + right, up + down
    strip = Image.new('RGBA', (fw * len(frames), fh_ * 6), GRASS)
    gif = []
    for n in range(len(frames)):
        g = Image.new('RGBA', (fw * 6, fh_), GRASS)
        for i, (canvases, ax, ay) in enumerate(rows):
            pos = (int(round(left - ax)), up - ay)
            g.alpha_composite(canvases[n], (i * fw + pos[0], pos[1]))
            strip.alpha_composite(canvases[n], (n * fw + pos[0], i * fh_ + pos[1]))
        gif.append(g.convert('RGB').resize((g.width * 2, g.height * 2), Image.Resampling.NEAREST))
    strip.save(os.path.join(dest, f'{anim}_strip.png'))
    durations = [ms[min(n, len(ms) - 1)] for n in range(len(frames))]
    gif[0].save(os.path.join(dest, f'{anim}.gif'), save_all=True, append_images=gif[1:], duration=durations, loop=0)
    print(f'{anim}: {len(frames)} frames -> {dest}')


def cmd_export(play_dir, out_dir, specs):
    frame_dir, review = os.path.join(out_dir, 'frames'), os.path.join(out_dir, 'review')
    os.makedirs(frame_dir, exist_ok=True)
    os.makedirs(review, exist_ok=True)
    path = os.path.join(out_dir, 'sprites.json')
    data = {'sprites': {}, 'animations': {}}
    if os.path.exists(path):
        with open(path, encoding='utf-8') as fh:
            data = json.load(fh)
    for spec in specs:
        anim, key = spec.split('=')
        key, mirror = (key[:-2], True) if key.endswith(':m') else (key, False)
        src = os.path.join(play_dir, anim)
        with open(os.path.join(src, 'anchors.json'), encoding='utf-8') as fh:
            anchors = json.load(fh)
        n = anchors[f'{anim}_1']['frames']
        keys = [f'{key}_{f:02d}' for f in range(n)]
        for f, fk in enumerate(keys):
            entries = []
            for i in range(1, 7):
                im = Image.open(os.path.join(src, f'{anim}_{i}_{f:02d}.png'))
                a = anchors[f'{anim}_{i}']
                ax = a['ax']
                if mirror:
                    im = im.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                    ax = round(im.width - ax, 1)
                name = f'{fk}_{i - 1}.png'
                im.save(os.path.join(frame_dir, name))
                entries.append({'file': f'frames/{name}', 'ax': ax, 'ay': a['ay']})
            data['sprites'][fk] = entries
        data['animations'][key] = {'frames': keys, 'ms': anchors[f'{anim}_1']['ms']}
        for ext in ('.gif', '_strip.png'):
            with open(os.path.join(src, anim + ext), 'rb') as a, open(os.path.join(review, anim + ext), 'wb') as b:
                b.write(a.read())
        print(f'{anim} -> {key}{" (mirrored)" if mirror else ""}: {n} frames')
    with open(path, 'w', encoding='utf-8') as fh:
        json.dump(data, fh, indent=1)


def option(args, flag, default=None):
    if flag in args:
        return args[args.index(flag) + 1]
    return default


def main():
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == 'sheet':
        size = lambda v: tuple(int(n) for n in v.split('x')) if v else None
        cmd_sheet(*args[:3], size(option(args, '--grid')), size(option(args, '--cell', '840x840')), int(option(args, '--base', str(BASE))))
    elif cmd == 'legacy':
        cmd_legacy(*args[:3])
    elif cmd == 'cut':
        splits = [tuple(float(v) for v in a.split(',')) for k, a in zip(args, args[1:]) if k == '--split']
        cmd_cut(*args[:4], splits, '--keep-y' in args, float(option(args, '--bg-tol', '22')), '--no-shadows' not in args)
    elif cmd == 'palette':
        cmd_palette(*args[:2])
    elif cmd == 'breathe':
        cmd_breathe(*args[:3], tuple(int(v) for v in option(args, '--px', '0,1,2,1').split(',')))
    elif cmd == 'play':
        ms = tuple(int(v) for v in option(args, '--ms', '120').split(','))
        cmd_play(*args[:5], option(args, '--palette'), ms)
    elif cmd == 'export':
        cmd_export(args[0], args[1], args[2:])
    else:
        raise SystemExit(__doc__)


if __name__ == '__main__':
    main()
