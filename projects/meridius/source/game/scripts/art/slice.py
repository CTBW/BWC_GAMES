"""Slice a background-removed sprite sheet into game sprites.

Usage: python slice.py <spec.json>

Spec fields:
  input        path to an RGBA sheet (background already removed)
  items        list of {"key": str, "v": int} in reading order (rows top to bottom,
               left to right within a row). Use {"skip": true} to drop a blob.
  height       target pixel height of the tallest sprite in this sheet (default 400)
  world        world-pixel height the tallest sprite should have in game (default 130)
  anchor       "feet" (bottom centre of the lowest opaque rows) or "centre" or "bottom"
  min_area     ignore blobs smaller than this many opaque pixels (default 1500)
  merge        pixel distance for merging nearby blobs (weapons, flags) (default 18)
  row_tol      fraction of median blob height treated as the same row (default 0.45)
  out_dir      directory under art/sprites for the PNG masters (default art/sprites)
  manifest     manifest path (default public/assets/manifest.json)
Each blob is trimmed, scaled uniformly with the others in the sheet, saved as the
master <out_dir>/<key>_<v>.png, published to the game as WebP (publish.py) and
registered as manifest.sprites[key][v] = {file, ax, ay, scale}.
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
from publish import manifest_file, publish


def load_manifest(path):
    if os.path.exists(path):
        with open(path, encoding='utf-8') as f:
            return json.load(f)
    return {'sprites': {}, 'textures': {}}


def main():
    spec = json.load(open(sys.argv[1], encoding='utf-8'))
    im = Image.open(spec['input']).convert('RGBA')
    a = np.array(im)
    alpha = a[:, :, 3]
    mask = alpha > 40
    merge = spec.get('merge', 18)
    grown = ndimage.binary_dilation(mask, iterations=merge) if merge else mask
    labels, n = ndimage.label(grown)
    blobs = []
    for i, sl in enumerate(ndimage.find_objects(labels), start=1):
        if sl is None:
            continue
        region = (labels[sl] == i) & mask[sl]
        area = int(region.sum())
        if area < spec.get('min_area', 1500):
            continue
        ys, xs = np.nonzero(region)
        y0, y1 = sl[0].start + ys.min(), sl[0].start + ys.max() + 1
        x0, x1 = sl[1].start + xs.min(), sl[1].start + xs.max() + 1
        blobs.append({'label': i, 'box': (x0, y0, x1, y1), 'area': area, 'cy': (y0 + y1) / 2, 'cx': (x0 + x1) / 2})
    if not blobs:
        raise SystemExit('no blobs found')
    med_h = float(np.median([b['box'][3] - b['box'][1] for b in blobs]))
    tol = spec.get('row_tol', 0.45) * med_h
    blobs.sort(key=lambda b: b['cy'])
    rows = []
    for b in blobs:
        if rows and abs(b['cy'] - rows[-1][0]['cy']) < tol:
            rows[-1].append(b)
        else:
            rows.append([b])
    ordered = [b for row in rows for b in sorted(row, key=lambda q: q['cx'])]
    items = spec['items']
    print(f'found {len(ordered)} blobs in {len(rows)} rows; spec lists {len(items)} items')
    if len(ordered) < len([i for i in items if not i.get('skip')]):
        print('WARNING: fewer blobs than items')
    tallest = max(b['box'][3] - b['box'][1] for b in ordered)
    target_h = spec.get('height', 400)
    world_h = spec.get('world', 130)
    k = min(1.0, target_h / tallest)
    out_dir = spec.get('out_dir', 'art/sprites')
    os.makedirs(out_dir, exist_ok=True)
    manifest_path = spec.get('manifest', 'public/assets/manifest.json')
    manifest = load_manifest(manifest_path)
    for item, b in zip(items, ordered):
        if item.get('skip'):
            continue
        x0, y0, x1, y1 = b['box']
        crop = a[y0:y1, x0:x1].copy()
        # Remove other blobs that intrude into this box.
        lab = labels[y0:y1, x0:x1]
        crop[(lab != b['label']) & (lab != 0), 3] = 0
        sprite = Image.fromarray(crop)
        w, h = sprite.size
        if k < 1:
            sprite = sprite.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS)
        w, h = sprite.size
        al = np.array(sprite)[:, :, 3] > 60
        anchor = item.get('anchor', spec.get('anchor', 'feet'))
        if anchor == 'centre':
            ax, ay = w / 2, h / 2
        else:
            rows_idx = np.nonzero(al.any(axis=1))[0]
            bottom = rows_idx.max() if len(rows_idx) else h - 1
            band = al[max(0, bottom - max(3, h // 14)): bottom + 1]
            cols = np.nonzero(band.any(axis=0))[0]
            ax = float(cols.mean()) if anchor == 'feet' and len(cols) else w / 2
            ay = float(bottom) - (h * 0.02 if anchor == 'feet' else 0)
        key = item['key']
        v = item.get('v', 0)
        fname = f'{key}_{v}.png'
        sprite.save(os.path.join(out_dir, fname))
        scale = world_h / (tallest * k) * item.get('scale', 1.0)
        rel = manifest_file(os.path.join(out_dir, fname))
        lst = manifest['sprites'].setdefault(key, [])
        while len(lst) <= v:
            lst.append(None)
        lst[v] = {'file': rel, 'ax': round(ax, 1), 'ay': round(ay, 1), 'scale': round(scale, 4)}
        print(f'  {key}[{v}] {w}x{h} anchor=({ax:.0f},{ay:.0f}) scale={scale:.3f}')
    for key in list(manifest['sprites'].keys()):
        manifest['sprites'][key] = [e for e in manifest['sprites'][key] if e]
    with open(manifest_path, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, indent=1)
    print('manifest updated', manifest_path)
    publish([f"{i['key']}_" for i in items if not i.get('skip')])


if __name__ == '__main__':
    main()
