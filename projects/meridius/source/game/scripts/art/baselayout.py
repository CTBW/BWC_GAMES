"""Offline layout check for the Amberfeld base.

Composites the building, palisade, gate-tower and decor sprites exactly as
src/render/baseScene.ts draws them (same anchors, scales and depth order) and
reports, per building level set, how much of each building is hidden by
objects in front of it and whether nameplates collide with each other or sit
on another building.

  .venv-art/Scripts/python.exe scripts/art/baselayout.py <outDir> [--pos '{"infirmary":[3,9]}'] [--decor '[[8,8.6,"campfire"]]'] [--levels 1,2,3]

Writes one composite PNG per level set and prints a report. Exit code 1 when a
check fails, so it can guard layout edits.
"""
import argparse
import itertools
import json
import math
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
PUB = ROOT / 'public' / 'assets'
K = 0.5  # composite resolution relative to world pixels
ZOOM = 0.62  # default base camera zoom (makeCamera in baseScene.ts)
SOLID = 200  # alpha above which a pixel is body, not baked shadow

# Limits for the report. Hidden = share of a building's body covered by
# something drawn in front of it.
MAX_HIDDEN = 0.12
MAX_LABEL_ON_BODY = 0.10


def iso(x, y):
    return (x - y) * 64.0, (x + y) * 32.0


def parse_buildings():
    src = (ROOT / 'src' / 'data' / 'buildings.ts').read_text(encoding='utf8')
    out = []
    for block in re.split(r"\n  \{\n", src)[1:]:
        bid = re.search(r"id: '([a-z]+)'", block).group(1)
        px, py = (float(v) for v in re.search(r"pos: \[([\d.]+), ([\d.]+)\]", block).groups())
        names = re.findall(r"name: '((?:[^'\\]|\\')+)', cost", block)
        out.append({'id': bid, 'pos': [px, py], 'names': [n.replace("\\'", "'") for n in names]})
    return out


def parse_decor():
    src = (ROOT / 'src' / 'render' / 'baseScene.ts').read_text(encoding='utf8')
    body = re.search(r"const decor: \[number, number, string\]\[\] = \[(.*?)\];", src, re.S).group(1)
    return [(float(a), float(b), p) for a, b, p in re.findall(r"\[([\d.]+), ([\d.]+), '([a-z_]+)'\]", body)]


class Sprites:
    def __init__(self):
        self.man = json.loads((PUB / 'manifest.json').read_text(encoding='utf8'))['sprites']
        self.cache = {}

    def get(self, key, v=0):
        frames = self.man[key]
        e = frames[v % len(frames)]
        ck = (key, v % len(frames))
        if ck not in self.cache:
            im = Image.open(PUB / e['file']).convert('RGBA')
            sc = e.get('scale', 1) * K
            w, h = max(1, round(im.width * sc)), max(1, round(im.height * sc))
            self.cache[ck] = (im.resize((w, h), Image.LANCZOS), e['ax'] * sc, e['ay'] * sc, e.get('scale', 1))
        return self.cache[ck]


def label_width(name):
    w = 0.0
    for c in name.upper():
        w += 7 if c == ' ' else 5 if c == "'" else 8 if c == 'I' else 21 if c in 'MW' else 15.5
    return w + 22 / ZOOM


def run(levels, bdefs, decor, spr, out_png):
    items = []  # (depth, order, kind, id, sprite, wx, wy)
    order = 0
    for x, y, p in decor:
        items.append((x + y, order, 'decor', p, spr.get(p, int(x * 3 + y)), *iso(x, y)))
        order += 1
    for i in range(1, 15):
        pts = [(i, 0.6, 'palisade_x'), (0.6, i, 'palisade_y'), (i, 14.4, 'palisade_x')]
        if not 8 <= i <= 10:
            pts.append((14.4, i, 'palisade_y'))
        for x, y, key in pts:
            items.append((x + y, order, 'wall', key, spr.get(key, math.floor(x * 3 + y * 7)), *iso(x, y)))
            order += 1
    for gx, gy in ((14.5, 7.4), (14.5, 10.6)):
        items.append((gx + gy + 0.2, order, 'tower', 'gate_tower', spr.get('gate_tower'), *iso(gx, gy)))
        order += 1
    for b, lv in zip(bdefs, levels):
        items.append((b['pos'][0] + b['pos'][1] + 0.6, order, 'building', b['id'], spr.get(f"b_{b['id']}_{lv}"), *iso(*b['pos'])))
        order += 1
    # JS sort is stable, so equal depths keep insertion order.
    items.sort(key=lambda t: (t[0], t[1]))

    boxes = []
    for it in items:
        im, ax, ay, _ = it[4]
        boxes.append((it[5] * K - ax, it[6] * K - ay, im.width, im.height))
    labels = []
    for b, lv in zip(bdefs, levels):
        im, ax, ay, sc = spr.get(f"b_{b['id']}_{lv}")
        x, y = iso(*b['pos'])
        ly = y - (ay / K) + 6  # ay is already scaled by K; world anchor = ay / K
        size = 15 / max(0.5, ZOOM)
        tw = label_width(b['names'][lv - 1])
        labels.append((b['id'], b['names'][lv - 1], (x - tw / 2, ly - size * 1.1, x + tw / 2, ly + size * 0.4)))
    # Whole-pixel origin, so sprite offsets round the same way whatever else is on the canvas.
    x0 = math.floor(min(min(bx for bx, _, _, _ in boxes), min(r[0] * K for _, _, r in labels))) - 20
    y0 = math.floor(min(min(by for _, by, _, _ in boxes), min(r[1] * K for _, _, r in labels))) - 20
    x1 = max(max(bx + w for bx, _, w, _ in boxes), max(r[2] * K for _, _, r in labels)) + 20
    y1 = max(max(by + h for _, by, _, h in boxes), max(r[3] * K for _, _, r in labels)) + 20
    W, H = int(x1 - x0), int(y1 - y0)
    canvas = Image.new('RGBA', (W, H), (40, 60, 30, 255))
    owner = np.full((H, W), -1, dtype=np.int16)
    body = {}
    for idx, (it, (bx, by, w, h)) in enumerate(zip(items, boxes)):
        im = it[4][0]
        ox, oy = int(round(bx - x0)), int(round(by - y0))
        canvas.alpha_composite(im, (ox, oy))
        a = np.asarray(im)[:, :, 3] > SOLID
        sl = owner[oy:oy + h, ox:ox + w]
        sl[a[:sl.shape[0], :sl.shape[1]]] = idx
        if it[2] == 'building':
            m = np.zeros((H, W), bool)
            m[oy:oy + h, ox:ox + w] = a[:sl.shape[0], :sl.shape[1]]
            body[idx] = m

    fails = []
    report = []
    name_of = {i: it[3] for i, it in enumerate(items)}
    for idx, m in body.items():
        total = int(m.sum())
        hidden_by = {}
        o = owner[m]
        for j in np.unique(o):
            if j != idx:
                hidden_by[name_of[int(j)]] = round(float((o == j).sum()) / total, 3)
        hidden = round(sum(hidden_by.values()), 3)
        bid = items[idx][3]
        top = sorted(hidden_by.items(), key=lambda kv: -kv[1])[:3]
        report.append(f"  {bid:<14} hidden {hidden:5.1%}  by " + ', '.join(f"{k} {v:.1%}" for k, v in top))
        if hidden > MAX_HIDDEN:
            fails.append(f"{bid} hidden {hidden:.1%}")
    # Nameplates: against each other, and on top of another building's visible body.
    for i, (bid, name, r) in enumerate(labels):
        for bid2, name2, r2 in labels[i + 1:]:
            if r[0] < r2[2] and r2[0] < r[2] and r[1] < r2[3] and r2[1] < r[3]:
                fails.append(f"label {name} overlaps label {name2}")
        rx0, ry0 = int(r[0] * K - x0), int(r[1] * K - y0)
        rx1, ry1 = int(r[2] * K - x0), int(r[3] * K - y0)
        area = owner[ry0:ry1, rx0:rx1]
        for idx, m in body.items():
            other = items[idx][3]
            if other == bid:
                continue
            share = float((area == idx).sum()) / max(1, area.size)
            if share > MAX_LABEL_ON_BODY:
                fails.append(f"label {name} sits on {other} ({share:.0%})")
    d = ImageDraw.Draw(canvas)
    for bid, name, r in labels if out_png else []:
        rr = [r[0] * K - x0, r[1] * K - y0, r[2] * K - x0, r[3] * K - y0]
        d.rectangle(rr, fill=(40, 28, 16, 210), outline=(200, 170, 110, 255))
        d.text(((rr[0] + rr[2]) / 2, (rr[1] + rr[3]) / 2), name.upper(), fill=(239, 227, 196, 255), anchor='mm')
    if out_png:
        canvas.convert('RGB').save(out_png)
    # World-space points where each building is the visible top layer and no
    # nameplate covers it: probes for the in-game hover check (scripts/basepick.mjs).
    free = owner.copy()
    for _, _, r in labels:
        m = 16 * K  # label widths are estimates; keep probes clear of the edges
        free[max(0, int(r[1] * K - y0 - m)):int(r[3] * K - y0 + m), max(0, int(r[0] * K - x0 - m)):int(r[2] * K - x0 + m)] = -1
    rng = np.random.default_rng(5)
    samples = {}
    for idx in body:
        ys, xs = np.nonzero(free == idx)
        pick = rng.choice(len(xs), size=min(30, len(xs)), replace=False) if len(xs) else []
        samples[items[idx][3]] = [[round((xs[i] + x0) / K, 1), round((ys[i] + y0) / K, 1)] for i in pick]
    return report, fails, samples


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('out')
    ap.add_argument('--pos', default='{}', help='JSON {id: [x, y]} overrides')
    ap.add_argument('--decor', default=None, help='JSON [[x, y, prop], ...] replacing the decor list')
    ap.add_argument('--samples', default=None, help='write visible-body probe points per level set to this JSON file')
    ap.add_argument('--levels', default='1,2,3', help="comma list, each value setting every building to that level, or 'all' for every mix")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    bdefs = parse_buildings()
    for b in bdefs:
        b['pos'] = json.loads(args.pos).get(b['id'], b['pos'])
    spr = Sprites()
    decor = [tuple(d) for d in json.loads(args.decor)] if args.decor else parse_decor()
    failed = False
    probes = {}
    if args.levels == 'all':
        # Every mix of levels: print only the failing sets, then the worst share per building.
        worst = {}
        for combo in itertools.product((1, 2, 3), repeat=len(bdefs)):
            report, fails, _ = run(list(combo), bdefs, decor, spr, None)
            for line in report:
                bid, share = line.split()[0], float(line.split()[2].rstrip('%')) / 100
                if share >= worst.get(bid, (0, None))[0]:
                    worst[bid] = (share, combo)
            if fails:
                print('levels', ''.join(map(str, combo)), '; '.join(fails))
                failed = True
        order = ''.join(b['id'][0] for b in bdefs)
        for bid, (share, combo) in worst.items():
            print(f'  worst {bid:<14} {share:5.1%} at levels {order}={"".join(map(str, combo))}')
        print('positions', json.dumps({b['id']: b['pos'] for b in bdefs}))
        sys.exit(1 if failed else 0)
    for tok in args.levels.split(','):
        # A single digit sets every building; a digit per building sets a mix (order as in buildings.ts).
        lv = [int(c) for c in tok] if len(tok) == len(bdefs) else [int(tok)] * len(bdefs)
        report, fails, samples = run(lv, bdefs, decor, spr, out / f'layout_l{tok}.png')
        probes[tok] = samples
        print(f'Levels {tok}:')
        print('\n'.join(report))
        for f in fails:
            print('  FAIL', f)
        failed |= bool(fails)
    if args.samples:
        Path(args.samples).write_text(json.dumps(probes), encoding='utf8')
    print('positions', json.dumps({b['id']: b['pos'] for b in bdefs}))
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
