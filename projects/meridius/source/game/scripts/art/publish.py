"""Publish sprite masters to the game as WebP.

Masters are the editable painted PNGs in art/sprites/<dir>/<name>.png. The game
loads public/assets/sprites/<dir>/<name>.webp: lossy colour at quality 92 with
lossless alpha, so hit-testing masks and layout checks stay pixel-exact while
the download shrinks to about a quarter. New or changed masters are converted,
and manifest entries are pointed at the published .webp files.

  .venv-art/Scripts/python.exe scripts/art/publish.py [name-prefix ...]

paint_all.py and slice.py call this after writing masters.
"""
import glob
import json
import os
import sys

from PIL import Image

MASTERS = 'art/sprites'
PUBLISHED = 'public/assets/sprites'
MANIFEST = 'public/assets/manifest.json'
QUALITY = 92


def published_path(master):
    rel = os.path.relpath(master, MASTERS)
    return os.path.join(PUBLISHED, os.path.splitext(rel)[0] + '.webp')


def manifest_file(master):
    """The manifest's file field for a master (relative to public/assets)."""
    rel = os.path.relpath(published_path(master), os.path.dirname(MANIFEST))
    return rel.replace('\\', '/')


def publish(prefixes=None, force=False):
    masters = sorted(glob.glob(os.path.join(MASTERS, '**', '*.png'), recursive=True))
    if prefixes:
        masters = [m for m in masters if any(os.path.basename(m).startswith(p) for p in prefixes)]
    converted = 0
    for m in masters:
        dst = published_path(m)
        if not force and os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(m):
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        Image.open(m).convert('RGBA').save(dst, 'WEBP', quality=QUALITY, alpha_quality=100, method=4)
        converted += 1
    # Point manifest entries at the published files.
    with open(MANIFEST, encoding='utf-8') as f:
        manifest = json.load(f)
    by_png = {os.path.relpath(m, MASTERS).replace('\\', '/'): manifest_file(m) for m in glob.glob(os.path.join(MASTERS, '**', '*.png'), recursive=True)}
    missing = []
    for entries in manifest['sprites'].values():
        for e in entries:
            rel = e['file'][len('sprites/'):] if e['file'].startswith('sprites/') else None
            if rel and rel.endswith('.png') and rel in by_png:
                e['file'] = by_png[rel]
            if not os.path.exists(os.path.join(os.path.dirname(MANIFEST), e['file'])):
                missing.append(e['file'])
    with open(MANIFEST, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, indent=1)
    print(f'published {converted} of {len(masters)} masters as WebP')
    for f in missing:
        print('  WARNING: manifest file not published:', f)
    return converted


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if a != '--force']
    publish(args or None, force='--force' in sys.argv)
