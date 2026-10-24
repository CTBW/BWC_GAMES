// Captures each battle map type (and a night raid) for visual review.
// Usage: node scripts/maps.mjs <outDir>
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';
const out = process.argv[2] ?? 'maps';
fs.mkdirSync(out, { recursive: true });
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
await page.goto('http://localhost:5199/?newgame&seed=5');
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base');
const cases = [
  ['forest', 'raiding_party', { mapId: 'forest_clearing', seed: 3 }],
  ['river', 'orc_overseer', { mapId: 'river_ruins', seed: 4 }],
  ['camp', 'warband_camp', { mapId: 'goblin_camp', seed: 5 }],
  ['ambush', 'road_ambush', { seed: 6 }],
  ['night-torch', 'road_ambush', { seed: 8, night: true, darkness: false }],
  ['night-dark', 'road_ambush', { seed: 9, night: true, darkness: true }],
];
for (const [name, enc, opts] of cases) {
  await page.evaluate(([e, o]) => window.__meridius.store.debug.testBattle(e, o), [enc, opts]);
  await page.waitForTimeout(1800);
  await page.screenshot({ path: path.join(out, `${name}.png`) });
  console.log('shot', name);
}
console.log('errors', errors.length, errors.slice(0, 3).join(' | '));
await browser.close();
