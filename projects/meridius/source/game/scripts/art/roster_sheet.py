# Lineup of rendered unit poses for review: python roster_sheet.py <out.png> [variant]
import os, sys
from PIL import Image, ImageDraw
out = sys.argv[1]
v = sys.argv[2] if len(sys.argv) > 2 else '0'
D = 'art/raw/blender'
types = ['footman', 'spearman', 'crossbowman', 'goblin_spear', 'goblin_archer', 'orc_warrior', 'orc_warlord']
poses = ['idle_f', 'atk_f', 'idle_fr', 'idle_b', 'idle_bl', 'flee_b', 'dead']
cw, ch = 300, 470
sheet = Image.new('RGBA', (cw * (len(poses) + 1), ch * len(types) // 2 + 40), (126, 160, 62, 255))
dr = ImageDraw.Draw(sheet)
row_h = ch // 2
for ti, t in enumerate(types):
    y0 = ti * row_h + 20
    dr.text((10, y0 + 10), t, fill=(30, 20, 10))
    for pi, p in enumerate(poses):
        f = os.path.join(D, f'{t}_{p}_{v}.png' if p != 'dead' else f'{t}_dead_{v}.png')
        if not os.path.exists(f):
            continue
        im = Image.open(f).convert('RGBA')
        k = min(1.0, (row_h - 10) / im.height)
        im = im.resize((int(im.width * k), int(im.height * k)), Image.LANCZOS)
        x = cw * (pi + 1) + (cw - im.width) // 2
        sheet.alpha_composite(im, (x, y0 + row_h - 10 - im.height))
ports = [Image.open(os.path.join(D, f'portrait_{t}_{v}.png')).convert('RGBA') for t in types if os.path.exists(os.path.join(D, f'portrait_{t}_{v}.png'))]
if ports:
    strip = Image.new('RGBA', (len(ports) * 260, 260), (60, 80, 140, 255))
    for i, p in enumerate(ports):
        strip.alpha_composite(p.resize((256, 256)), (i * 260, 2))
    big = Image.new('RGBA', (max(sheet.width, strip.width), sheet.height + 270), (126, 160, 62, 255))
    big.alpha_composite(sheet, (0, 0))
    big.alpha_composite(strip, (0, sheet.height + 5))
    sheet = big
sheet.save(out)
print(out, sheet.size)
