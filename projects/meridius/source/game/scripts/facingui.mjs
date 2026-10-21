// Facing preview in the real battle UI: select a squad, hover a destination
// with the cursor toward each edge of the tile, cycle with Q / E, then move and
// confirm the squad faces the previewed way.
// Usage: node scripts/facingui.mjs <outDir>   (BASE_URL overrides the dev server)
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';

const out = process.argv[2] ?? 'facingui';
fs.mkdirSync(out, { recursive: true });
const base = process.env.BASE_URL ?? 'http://localhost:5199';
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
await page.goto(`${base}/?newgame&seed=3`);
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base', null, { timeout: 60000 });
await page.evaluate(() => {
  const s = window.__meridius.store;
  s.debug.testBattle('goblin_scouts', { seed: 7, mapId: 'forest_clearing' });
  // An open field, so every approach is possible.
  for (const t of s.battleScene.b.map.tiles) { t.prop = undefined; t.h = 0; t.terrain = 'grass'; }
  s.battleScene.begin();
});
await page.waitForFunction(() => !window.__meridius.store.battleScene.busy && window.__meridius.store.battleScene.b.phase === 'player', null, { timeout: 30000 });

// Screen position of a point inside a tile, offset toward one of its edges (grid units).
const screenOf = (gx, gy) =>
  page.evaluate(([gx, gy]) => {
    const sc = window.__meridius.store.battleScene;
    const t = sc.b.map.tiles.find((q) => q.x === Math.round(gx) && q.y === Math.round(gy));
    const wx = (gx - gy) * 64;
    const wy = (gx + gy) * 32 - (t?.h ?? 0) * 26;
    const c = sc.cam;
    return { x: (wx - c.x) * c.zoom + innerWidth / 2, y: (wy - c.y) * c.zoom + innerHeight / 2 };
  }, [gx, gy]);

const info = await page.evaluate(() => {
  const sc = window.__meridius.store.battleScene;
  const u = sc.b.active('player').find((x) => x.typeId === 'footman') ?? sc.b.active('player')[0];
  sc.select(u.uid);
  sc.cam.tx = sc.cam.x = (u.x - (u.y - 2)) * 64;
  sc.cam.ty = sc.cam.y = (u.x + u.y - 2) * 32 - 40;
  sc.cam.tzoom = sc.cam.zoom = 1.25;
  return { uid: u.uid, x: u.x, y: u.y, facing: u.facing };
});
await page.waitForTimeout(400);
const dest = { x: info.x, y: info.y - 2 };
const results = [];
const names = ['+x', '+y', '-x', '-y'];
for (const [i, d] of [[1, 0], [0, 1], [-1, 0], [0, -1]].entries()) {
  const p = await screenOf(dest.x + d[0] * 0.33, dest.y + d[1] * 0.33);
  await page.mouse.move(p.x, p.y);
  await page.waitForTimeout(250);
  const h = await page.evaluate(() => {
    const hv = window.__meridius.store.battleScene.ui.hover;
    return { facing: hv.facing, facings: hv.facings, path: hv.path?.length };
  });
  results.push({ point: names[i], ...h });
  await page.screenshot({ path: path.join(out, `hover-${i}-${names[i]}.png`) });
}
// Cycle with E from the centre.
const c = await screenOf(dest.x, dest.y);
await page.mouse.move(c.x, c.y);
await page.waitForTimeout(200);
const cyc = [];
for (let k = 0; k < 4; k++) {
  cyc.push(await page.evaluate(() => window.__meridius.store.battleScene.ui.hover.facing));
  await page.keyboard.press('e');
  await page.waitForTimeout(120);
}
// Point at the -x edge and click: the squad must arrive facing -x.
const p = await screenOf(dest.x - 0.33, dest.y);
await page.mouse.move(p.x, p.y);
await page.waitForTimeout(200);
const want = await page.evaluate(() => window.__meridius.store.battleScene.ui.hover.facing);
await page.mouse.click(p.x, p.y);
await page.waitForFunction(() => !window.__meridius.store.battleScene.busy, null, { timeout: 20000 });
await page.waitForTimeout(300);
const after = await page.evaluate((uid) => {
  const u = window.__meridius.store.battleScene.b.unit(uid);
  return { x: u.x, y: u.y, facing: u.facing };
}, info.uid);
await page.screenshot({ path: path.join(out, 'after-move.png') });
console.log(JSON.stringify({ start: info, hover: results, cycle: cyc, want, after }, null, 1));
console.log(errors.length ? errors.join('\n') : 'no page errors');
await browser.close();
