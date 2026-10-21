// Diffs the browser and Godot contact sheets of tests/visual/out:
//   node tools/bake/compare.mjs [name…]
// For each sheet assets_<name>_{browser,godot}.png it prints the mean absolute
// channel difference and the share of pixels differing by more than 24 / 64
// (of 255), and writes assets_<name>_diff.png (the browser sheet dimmed, with
// differing pixels in red) and assets_<name>_pair.png (browser | godot).

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { decodePNG, encodePNG } from './png.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.resolve(HERE, '../../tests/visual/out');
const only = process.argv.slice(2);
const names = fs
  .readdirSync(OUT)
  .filter((f) => /^assets_.+_browser\.png$/.test(f))
  .map((f) => f.slice('assets_'.length, -'_browser.png'.length))
  .filter((n) => !only.length || only.includes(n));

let worst = 0;
for (const n of names) {
  const gFile = path.join(OUT, `assets_${n}_godot.png`);
  if (!fs.existsSync(gFile)) {
    console.log(`${n}: no Godot sheet`);
    continue;
  }
  const a = decodePNG(fs.readFileSync(path.join(OUT, `assets_${n}_browser.png`)));
  const b = decodePNG(fs.readFileSync(gFile));
  if (a.w !== b.w || a.h !== b.h) {
    console.log(`${n}: size differs ${a.w}x${a.h} vs ${b.w}x${b.h}`);
    continue;
  }
  const diff = Buffer.alloc(a.w * a.h * 4);
  let sum = 0;
  let over24 = 0;
  let over64 = 0;
  for (let i = 0; i < a.w * a.h; i++) {
    let m = 0;
    for (let c = 0; c < 3; c++) {
      const d = Math.abs(a.rgba[i * 4 + c] - b.rgba[i * 4 + c]);
      sum += d;
      if (d > m) m = d;
    }
    if (m > 24) over24++;
    if (m > 64) over64++;
    const g = (a.rgba[i * 4] + a.rgba[i * 4 + 1] + a.rgba[i * 4 + 2]) / 3;
    const k = m > 24 ? 1 : 0;
    diff[i * 4] = k ? Math.min(255, 128 + m) : g * 0.5;
    diff[i * 4 + 1] = k ? 0 : g * 0.5;
    diff[i * 4 + 2] = k ? 0 : g * 0.5;
    diff[i * 4 + 3] = 255;
  }
  fs.writeFileSync(path.join(OUT, `assets_${n}_diff.png`), encodePNG(a.w, a.h, diff));
  const pair = Buffer.alloc(a.w * 2 * a.h * 4);
  for (let y = 0; y < a.h; y++) {
    a.rgba.copy(pair, y * a.w * 8, y * a.w * 4, (y + 1) * a.w * 4);
    b.rgba.copy(pair, y * a.w * 8 + a.w * 4, y * a.w * 4, (y + 1) * a.w * 4);
  }
  fs.writeFileSync(path.join(OUT, `assets_${n}_pair.png`), encodePNG(a.w * 2, a.h, pair));
  const px = a.w * a.h;
  const pct24 = (100 * over24) / px;
  worst = Math.max(worst, pct24);
  console.log(`${n.padEnd(22)} ${a.w}x${a.h}  mean |d| ${(sum / (px * 3)).toFixed(2)}  >24: ${pct24.toFixed(2)}%  >64: ${((100 * over64) / px).toFixed(2)}%`);
}
console.log(`worst share of pixels off by more than 24/255: ${worst.toFixed(2)}%`);
