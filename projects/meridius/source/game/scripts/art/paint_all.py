# Paint every raw Blender render into a sprite master, then publish it to the game as WebP.
import glob, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from paint import paint
from publish import publish
src = 'art/raw/blender'
dst = 'art/sprites/blender'
os.makedirs(dst, exist_ok=True)
only = sys.argv[1:]
for f in sorted(glob.glob(os.path.join(src, '*.png'))):
    name = os.path.basename(f)
    if only and not any(name.startswith(o) for o in only):
        continue
    big = 'tree' in name or name.startswith('b_') or name.startswith('node_')
    paint(f, os.path.join(dst, name), 6 if big else 4, 26)
    print('painted', name)
publish(only or None)
