// Contact sheets from a frame-by-frame capture folder (combatlab, magiclab):
// a few frames per stage, cropped to the action, in a 3-column JPEG.
// Usage: node scripts/sheets.mjs <labDir> <outDir> [framesPerSheet=6] [crop=250,60,780,580]
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';

const [lab, out] = process.argv.slice(2, 4);
const per = Number(process.argv[4] ?? 6);
const [cx, cy, cw, ch] = (process.argv[5] ?? '250,60,780,580').split(',').map(Number);
fs.mkdirSync(out, { recursive: true });
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage();
for (const stage of fs.readdirSync(lab).sort()) {
  const dir = path.join(lab, stage);
  if (!fs.statSync(dir).isDirectory()) continue;
  const frames = fs.readdirSync(dir).filter((f) => f.endsWith('.png')).sort();
  if (!frames.length) continue;
  const pick = frames.length <= per ? frames : Array.from({ length: per }, (_, i) => frames[Math.round((i * (frames.length - 1)) / (per - 1))]);
  const urls = pick.map((f) => `data:image/png;base64,${fs.readFileSync(path.join(dir, f)).toString('base64')}`);
  const jpeg = await page.evaluate(async ({ urls, names, cx, cy, cw, ch }) => {
    const cols = 3;
    const rows = Math.ceil(urls.length / cols);
    const c = document.createElement('canvas');
    c.width = cols * cw;
    c.height = rows * ch;
    const x = c.getContext('2d');
    x.fillStyle = '#14100c';
    x.fillRect(0, 0, c.width, c.height);
    for (let i = 0; i < urls.length; i++) {
      const img = new Image();
      img.src = urls[i];
      await img.decode();
      const px = (i % cols) * cw;
      const py = Math.floor(i / cols) * ch;
      x.drawImage(img, cx, cy, cw, ch, px, py, cw, ch);
      x.fillStyle = 'rgba(20,16,12,0.85)';
      x.fillRect(px + 4, py + 4, 46, 20);
      x.fillStyle = '#f0e2c0';
      x.font = '13px sans-serif';
      x.fillText(names[i], px + 9, py + 19);
    }
    return c.toDataURL('image/jpeg', 0.88);
  }, { urls, names: pick.map((f) => f.slice(0, -4)), cx, cy, cw, ch });
  fs.writeFileSync(path.join(out, `${stage}.jpg`), Buffer.from(jpeg.split(',')[1], 'base64'));
  console.log(stage, `${frames.length} frames ->`, pick.map((f) => f.slice(0, -4)).join(', '));
}
await browser.close();
